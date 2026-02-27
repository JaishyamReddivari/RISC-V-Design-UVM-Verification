#!/usr/bin/env python3
"""
regress.py — Multi-seed regression runner for RISC-V UVM (ModelSim)
Usage:
    python3 regress.py                      # 10 random seeds
    python3 regress.py -n 20                # 20 random seeds
    python3 regress.py -s 100 200 300       # specific seeds
    python3 regress.py -t riscv_rtype_test  # different test
"""

import argparse, subprocess, os, sys, random, shutil, re
from datetime import datetime

# ─── Configuration ───────────────────────────────────────────────
WORK_DIR   = "regression_results"
MERGED_UCDB = "merged_coverage.ucdb"

# Adjust these to match your file structure
RTL_FILES = [
    "riscv_pkg.sv",
    "imem_if.sv",
    "dmem_if.sv",
    "riscv_core.sv",
    "riscv_assertions.sv",
    "riscv_bind.sv",
    "testbench.sv",
]

TOP_MODULE = "riscv_tb"

# ─── Color helpers ───────────────────────────────────────────────
C = sys.stdout.isatty()
def green(s):  return f"\033[92m{s}\033[0m" if C else s
def red(s):    return f"\033[91m{s}\033[0m" if C else s
def yellow(s): return f"\033[93m{s}\033[0m" if C else s
def bold(s):   return f"\033[1m{s}\033[0m"  if C else s


def parse_args():
    p = argparse.ArgumentParser(description="RISC-V UVM regression (ModelSim)")
    p.add_argument("-n", "--num-seeds", type=int, default=10)
    p.add_argument("-s", "--seeds", type=int, nargs="+")
    p.add_argument("-t", "--test", default="riscv_random_test")
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--no-compile", action="store_true",
                   help="Skip compilation (reuse existing work lib)")
    p.add_argument("--clean", action="store_true")
    return p.parse_args()


def run_cmd(cmd, log_path=None):
    """Run shell command, optionally log output. Returns (retcode, stdout)."""
    if log_path:
        with open(log_path, "w") as f:
            r = subprocess.run(cmd, shell=True, stdout=f, stderr=f)
        return r.returncode, None
    else:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return r.returncode, r.stdout


def compile_design():
    print(bold("\n══════ COMPILING ══════"))
    log = os.path.join(WORK_DIR, "compile.log")

    cmds = [
        "vlib work",
        "vlog -sv +incdir+. " + " ".join(RTL_FILES),
    ]

    with open(log, "w") as f:
        for cmd in cmds:
            f.write(f"\n--- {cmd} ---\n"); f.flush()
            r = subprocess.run(cmd, shell=True, stdout=f, stderr=f)
            if r.returncode != 0:
                print(red(f"  COMPILE FAILED — see {log}"))
                return False

    print(green("  Compile OK"))
    return True


def run_seed(seed, test, timeout):
    seed_dir = os.path.join(WORK_DIR, f"seed_{seed}")
    os.makedirs(seed_dir, exist_ok=True)

    ucdb_path = os.path.abspath(os.path.join(seed_dir, f"cov_{seed}.ucdb"))
    log_path  = os.path.join(seed_dir, f"sim_{seed}.log")
    do_path   = os.path.join(seed_dir, f"run_{seed}.do")

    # Write per-seed TCL script
    with open(do_path, "w") as f:
        f.write(f"run -all;\n")
        f.write(f"coverage save {ucdb_path};\n")
        f.write(f"quit -sim;\n")
        f.write(f"exit;\n")

    # ModelSim command
    cmd = (
        f"vsim -c +access+r "
        f"+UVM_TESTNAME={test} "
        f"-sv_seed {seed} "
        f"-do {do_path} "
        f"{TOP_MODULE}"
    )

    result = {
        "seed": seed, "status": "UNKNOWN",
        "uvm_errors": 0, "uvm_fatals": 0,
        "pass_count": 0, "fail_count": 0,
        "ucdb": None, "log": log_path,
    }

    try:
        with open(log_path, "w") as f:
            subprocess.run(cmd, shell=True, stdout=f, stderr=f, timeout=timeout)
    except subprocess.TimeoutExpired:
        result["status"] = "TIMEOUT"
        return result

    # ─── Parse log ───────────────────────────────────────
    if not os.path.exists(log_path):
        result["status"] = "NO_LOG"
        return result

    with open(log_path, "r", errors="replace") as f:
        log_text = f.read()

    m = re.search(r"UVM_ERROR\s*:\s*(\d+)", log_text)
    if m: result["uvm_errors"] = int(m.group(1))

    m = re.search(r"UVM_FATAL\s*:\s*(\d+)", log_text)
    if m: result["uvm_fatals"] = int(m.group(1))

    # Your scoreboard prints: "Results: X passed, Y failed"
    m = re.search(r"(\d+)\s+passed,\s+(\d+)\s+failed", log_text)
    if m:
        result["pass_count"] = int(m.group(1))
        result["fail_count"] = int(m.group(2))

    if os.path.exists(ucdb_path):
        result["ucdb"] = ucdb_path

    # Classify
    if result["uvm_fatals"] > 0:
        result["status"] = "FATAL"
    elif result["uvm_errors"] > 0 or result["fail_count"] > 0:
        result["status"] = "FAIL"
    elif result["pass_count"] > 0:
        result["status"] = "PASS"
    else:
        result["status"] = "UNKNOWN"

    return result


def merge_coverage(results):
    ucdbs = [r["ucdb"] for r in results if r["ucdb"] and os.path.exists(r["ucdb"])]

    if not ucdbs:
        print(yellow("\n  No coverage databases to merge."))
        return None

    merged = os.path.join(WORK_DIR, MERGED_UCDB)
    report = os.path.join(WORK_DIR, "merged_coverage.txt")

    print(bold(f"\n══════ MERGING COVERAGE ({len(ucdbs)} databases) ══════"))

    # vcover merge (ModelSim native)
    merge_cmd = f"vcover merge {merged} " + " ".join(ucdbs)
    merge_log = os.path.join(WORK_DIR, "merge.log")
    run_cmd(merge_cmd, merge_log)

    # vcover report
    report_cmd = f"vcover report {merged} -output {report}"
    run_cmd(report_cmd)

    # Also generate detailed per-covergroup report
    detail_report = os.path.join(WORK_DIR, "merged_coverage_detail.txt")
    run_cmd(f"vcover report {merged} -details -output {detail_report}")

    # Parse coverage %
    cov_pct = None
    if os.path.exists(report):
        with open(report, "r", errors="replace") as f:
            for line in f:
                # ModelSim vcover prints lines like:
                #   Total Coverage (filtered) = 96.01%
                #   or: Covergroup Coverage = 96.01%
                m = re.search(r"(?:Total|Covergroup)\s+Coverage.*?=\s*([\d.]+)%", line)
                if m:
                    cov_pct = float(m.group(1))
                    break
        print(green(f"  Summary : {report}"))
        print(green(f"  Details : {detail_report}"))
    else:
        print(yellow(f"  Report not generated — check {merge_log}"))

    return cov_pct


def print_summary(results, merged_cov, elapsed):
    total   = len(results)
    passed  = sum(1 for r in results if r["status"] == "PASS")
    failed  = sum(1 for r in results if r["status"] in ("FAIL", "FATAL"))
    timeouts = sum(1 for r in results if r["status"] == "TIMEOUT")
    total_checks = sum(r["pass_count"] for r in results)
    total_fails  = sum(r["fail_count"] for r in results)

    print(bold("\n════════════════════════════════════════════════════════════════"))
    print(bold("                      REGRESSION SUMMARY"))
    print(bold("════════════════════════════════════════════════════════════════"))

    hdr = f"  {'Seed':>8}  {'Status':^10}  {'Pass':>6}  {'Fail':>6}  {'Errors':>7}  {'Fatals':>7}"
    print(hdr)
    print("  " + "─" * 58)

    for r in results:
        st = r["status"]
        if st == "PASS":       st_s = green(f"{'PASS':^10}")
        elif st == "TIMEOUT":  st_s = yellow(f"{'TIMEOUT':^10}")
        elif st == "UNKNOWN":  st_s = yellow(f"{'???':^10}")
        else:                  st_s = red(f"{st:^10}")

        print(f"  {r['seed']:>8}  {st_s}  {r['pass_count']:>6}  "
              f"{r['fail_count']:>6}  {r['uvm_errors']:>7}  {r['uvm_fatals']:>7}")

    print(bold("\n────────────────────────────────────────────────────────────────"))
    print(f"  Seeds run     : {total}")
    print(f"  Passed        : {green(str(passed))}")
    print(f"  Failed        : {red(str(failed)) if failed else '0'}")
    print(f"  Timeouts      : {yellow(str(timeouts)) if timeouts else '0'}")
    print(f"  Total checks  : {total_checks}")
    print(f"  Total failures: {red(str(total_fails)) if total_fails else '0'}")

    if merged_cov is not None:
        cs = f"{merged_cov:.2f}%"
        if merged_cov >= 95:    cs = green(cs)
        elif merged_cov >= 80:  cs = yellow(cs)
        else:                   cs = red(cs)
        print(f"  Merged cov    : {cs}")

    print(f"  Elapsed       : {elapsed:.1f}s")
    print(f"  Results       : {WORK_DIR}/")
    print(bold("════════════════════════════════════════════════════════════════\n"))

    return failed == 0 and timeouts == 0


def main():
    args = parse_args()
    start = datetime.now()

    print(bold(f"\n RISC-V UVM Regression — {args.test}"))
    print(f"  Date : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Tool : ModelSim\n")

    if args.clean and os.path.exists(WORK_DIR):
        shutil.rmtree(WORK_DIR)
    os.makedirs(WORK_DIR, exist_ok=True)

    if not args.no_compile:
        if not compile_design():
            sys.exit(1)

    seeds = args.seeds if args.seeds else [random.randint(1, 99999) for _ in range(args.num_seeds)]

    print(bold(f"\n══════ RUNNING {len(seeds)} SEEDS ══════"))

    results = []
    for i, seed in enumerate(seeds):
        print(f"  [{i+1}/{len(seeds)}] Seed {seed:>6} ... ", end="", flush=True)
        r = run_seed(seed, args.test, args.timeout)
        results.append(r)

        if r["status"] == "PASS":
            print(green(f"PASS  ({r['pass_count']} checks)"))
        elif r["status"] == "TIMEOUT":
            print(yellow("TIMEOUT"))
        else:
            print(red(f"{r['status']}  (err={r['uvm_errors']}, "
                       f"fatal={r['uvm_fatals']}, fail={r['fail_count']})"))

    merged_cov = merge_coverage(results)

    elapsed = (datetime.now() - start).total_seconds()
    ok = print_summary(results, merged_cov, elapsed)

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
