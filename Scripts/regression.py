"""
regress.py — Multi-seed regression runner for RISC-V UVM verification
Usage:
    python3 regress.py                      # 10 random seeds
    python3 regress.py -n 20                # 20 random seeds
    python3 regress.py -s 100 200 300       # specific seeds
    python3 regress.py -t riscv_rtype_test  # different test
"""

import argparse
import subprocess
import os
import sys
import random
import shutil
import re
from datetime import datetime

# ─── Configuration ───────────────────────────────────────────────
SIM_CMD     = "vsim"
TOP_MODULE  = "riscv_tb"
WORK_DIR    = "regression_results"
MERGED_ACDB = "merged_coverage.acdb"
COMPILE_LOG = "compile.log"

# ─── Color helpers (disabled if not a terminal) ──────────────────
USE_COLOR = sys.stdout.isatty()
def green(s):  return f"\033[92m{s}\033[0m" if USE_COLOR else s
def red(s):    return f"\033[91m{s}\033[0m" if USE_COLOR else s
def yellow(s): return f"\033[93m{s}\033[0m" if USE_COLOR else s
def bold(s):   return f"\033[1m{s}\033[0m"  if USE_COLOR else s


def parse_args():
    p = argparse.ArgumentParser(description="RISC-V UVM regression runner")
    p.add_argument("-n", "--num-seeds", type=int, default=10,
                   help="Number of random seeds (default: 10)")
    p.add_argument("-s", "--seeds", type=int, nargs="+",
                   help="Explicit seed list (overrides -n)")
    p.add_argument("-t", "--test", type=str, default="riscv_random_test",
                   help="UVM test name (default: riscv_random_test)")
    p.add_argument("--timeout", type=int, default=300,
                   help="Per-seed timeout in seconds (default: 300)")
    p.add_argument("--compile-only", action="store_true",
                   help="Compile only, don't run seeds")
    p.add_argument("--clean", action="store_true",
                   help="Remove all previous results before running")
    return p.parse_args()


def setup_dirs(clean):
    if clean and os.path.exists(WORK_DIR):
        shutil.rmtree(WORK_DIR)
    os.makedirs(WORK_DIR, exist_ok=True)


def compile_design():
    """Compile RTL + testbench. Returns True on success."""
    print(bold("\n══════ COMPILING DESIGN ══════"))
    log_path = os.path.join(WORK_DIR, COMPILE_LOG)

    cmds = [
        "vlib work",
        "vlog -sv -timescale 1ns/1ps "
        "+incdir+. "
        "riscv_pkg.sv "        # package first
        "imem_if.sv "
        "dmem_if.sv "
        "riscv_core.sv "       # all RTL
        "riscv_assertions.sv "
        "riscv_bind.sv "
        "riscv_tb.sv",
    ]

    with open(log_path, "w") as log:
        for cmd in cmds:
            log.write(f"\n--- {cmd} ---\n")
            log.flush()
            r = subprocess.run(cmd, shell=True, stdout=log, stderr=log)
            if r.returncode != 0:
                print(red(f"  COMPILE FAILED — see {log_path}"))
                return False

    print(green("  Compile OK"))
    return True


def generate_run_do(seed, test, acdb_name):
    """Generate a per-seed TCL run script."""
    return (
        f"vsim +access+r +UVM_TESTNAME={test} -sv_seed {seed} {TOP_MODULE};\n"
        f"run -all;\n"
        f"acdb save -db {acdb_name};\n"
        f"exit;\n"
    )


def run_seed(seed, test, timeout):
    """Run a single seed. Returns dict with results."""
    seed_dir = os.path.join(WORK_DIR, f"seed_{seed}")
    os.makedirs(seed_dir, exist_ok=True)

    acdb_name = os.path.join(seed_dir, f"cov_{seed}.acdb")
    do_path   = os.path.join(seed_dir, f"run_{seed}.do")
    log_path  = os.path.join(seed_dir, f"sim_{seed}.log")

    # Write per-seed TCL script
    with open(do_path, "w") as f:
        f.write(generate_run_do(seed, test, acdb_name))

    # Launch simulation
    cmd = f"{SIM_CMD} -c -do {do_path}"
    result = {
        "seed": seed,
        "status": "UNKNOWN",
        "uvm_errors": 0,
        "uvm_fatals": 0,
        "pass_count": 0,
        "fail_count": 0,
        "acdb": acdb_name if os.path.exists(acdb_name) else None,
        "log": log_path,
    }

    try:
        with open(log_path, "w") as log:
            r = subprocess.run(
                cmd, shell=True, stdout=log, stderr=log, timeout=timeout
            )
    except subprocess.TimeoutExpired:
        result["status"] = "TIMEOUT"
        return result

    # ─── Parse log ───────────────────────────────────────────
    if not os.path.exists(log_path):
        result["status"] = "NO_LOG"
        return result

    with open(log_path, "r", errors="replace") as f:
        log_text = f.read()

    # UVM error/fatal counts
    m = re.search(r"UVM_ERROR\s*:\s*(\d+)", log_text)
    if m:
        result["uvm_errors"] = int(m.group(1))

    m = re.search(r"UVM_FATAL\s*:\s*(\d+)", log_text)
    if m:
        result["uvm_fatals"] = int(m.group(1))

    # Scoreboard pass/fail from report_phase
    m = re.search(r"(\d+)\s+passed,\s+(\d+)\s+failed", log_text)
    if m:
        result["pass_count"] = int(m.group(1))
        result["fail_count"] = int(m.group(2))

    # Check for acdb file
    if os.path.exists(acdb_name):
        result["acdb"] = acdb_name

    # Determine status
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
    """Merge all per-seed acdb files and generate report."""
    acdb_files = [r["acdb"] for r in results if r["acdb"] and os.path.exists(r["acdb"])]

    if not acdb_files:
        print(yellow("\n  No coverage databases to merge."))
        return None

    merged_path = os.path.join(WORK_DIR, MERGED_ACDB)
    report_path = os.path.join(WORK_DIR, "merged_coverage.txt")

    print(bold(f"\n══════ MERGING COVERAGE ({len(acdb_files)} databases) ══════"))

    merge_do = os.path.join(WORK_DIR, "merge.do")
    with open(merge_do, "w") as f:
        f.write(f"acdb merge -o {merged_path}")
        for db in acdb_files:
            f.write(f" -i {db}")
        f.write(";\n")
        f.write(f"acdb report -db {merged_path} -txt -o {report_path} -verbose;\n")
        f.write("exit;\n")

    merge_log = os.path.join(WORK_DIR, "merge.log")
    with open(merge_log, "w") as log:
        subprocess.run(f"{SIM_CMD} -c -do {merge_do}", shell=True, stdout=log, stderr=log)

    # Parse merged coverage %
    cov_pct = None
    if os.path.exists(report_path):
        with open(report_path, "r", errors="replace") as f:
            for line in f:
                m = re.search(r"CUMULATIVE.*?COVERAGE:\s*([\d.]+)%", line)
                if m:
                    cov_pct = float(m.group(1))
                    break
        print(green(f"  Merged report: {report_path}"))
    else:
        print(yellow(f"  Merge report not generated — check {merge_log}"))

    return cov_pct


def print_summary(results, merged_cov, elapsed):
    """Print the final results table."""
    total   = len(results)
    passed  = sum(1 for r in results if r["status"] == "PASS")
    failed  = sum(1 for r in results if r["status"] in ("FAIL", "FATAL"))
    timeout = sum(1 for r in results if r["status"] == "TIMEOUT")
    unknown = total - passed - failed - timeout

    total_checks = sum(r["pass_count"] for r in results)
    total_fails  = sum(r["fail_count"] for r in results)

    print(bold("\n══════════════════════════════════════════════════════════════"))
    print(bold("                    REGRESSION SUMMARY"))
    print(bold("══════════════════════════════════════════════════════════════"))

    # Per-seed table
    hdr = f"  {'Seed':>8}  {'Status':^10}  {'Pass':>6}  {'Fail':>6}  {'Errors':>7}  {'Fatals':>7}"
    print(hdr)
    print("  " + "─" * (len(hdr) - 2))

    for r in results:
        st = r["status"]
        if st == "PASS":
            st_str = green(f"{'PASS':^10}")
        elif st in ("FAIL", "FATAL"):
            st_str = red(f"{st:^10}")
        elif st == "TIMEOUT":
            st_str = yellow(f"{'TIMEOUT':^10}")
        else:
            st_str = yellow(f"{'???':^10}")

        print(f"  {r['seed']:>8}  {st_str}  {r['pass_count']:>6}  "
              f"{r['fail_count']:>6}  {r['uvm_errors']:>7}  {r['uvm_fatals']:>7}")

    print(bold("\n──────────────────────────────────────────────────────────────"))
    print(f"  Seeds run     : {total}")
    print(f"  Passed        : {green(str(passed))}")
    print(f"  Failed        : {red(str(failed)) if failed else '0'}")
    print(f"  Timeout       : {yellow(str(timeout)) if timeout else '0'}")
    print(f"  Total checks  : {total_checks}")
    print(f"  Total failures: {red(str(total_fails)) if total_fails else '0'}")

    if merged_cov is not None:
        cov_str = f"{merged_cov:.2f}%"
        if merged_cov >= 95:
            cov_str = green(cov_str)
        elif merged_cov >= 80:
            cov_str = yellow(cov_str)
        else:
            cov_str = red(cov_str)
        print(f"  Merged cov    : {cov_str}")

    print(f"  Elapsed       : {elapsed:.1f}s")
    print(f"  Results dir   : {WORK_DIR}/")
    print(bold("══════════════════════════════════════════════════════════════\n"))

    return failed == 0 and timeout == 0


def main():
    args = parse_args()
    start = datetime.now()

    print(bold(f"\n RISC-V UVM Regression — {args.test}"))
    print(f"  Date: {start.strftime('%Y-%m-%d %H:%M:%S')}\n")

    setup_dirs(args.clean)

    # Compile
    if not compile_design():
        sys.exit(1)

    if args.compile_only:
        print(green("\n  Compile-only mode. Done."))
        sys.exit(0)

    # Determine seeds
    if args.seeds:
        seeds = args.seeds
    else:
        seeds = [random.randint(1, 99999) for _ in range(args.num_seeds)]

    print(bold(f"\n══════ RUNNING {len(seeds)} SEEDS ══════"))

    # Run each seed
    results = []
    for i, seed in enumerate(seeds):
        tag = f"[{i+1}/{len(seeds)}]"
        print(f"  {tag} Seed {seed:>6} ... ", end="", flush=True)

        r = run_seed(seed, args.test, args.timeout)
        results.append(r)

        if r["status"] == "PASS":
            print(green(f"PASS  ({r['pass_count']} checks)"))
        elif r["status"] == "TIMEOUT":
            print(yellow("TIMEOUT"))
        else:
            print(red(f"{r['status']}  (err={r['uvm_errors']}, "
                       f"fatal={r['uvm_fatals']}, fail={r['fail_count']})"))

    # Merge coverage
    merged_cov = merge_coverage(results)

    # Summary
    elapsed = (datetime.now() - start).total_seconds()
    all_pass = print_summary(results, merged_cov, elapsed)

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
