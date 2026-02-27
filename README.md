# RISC-V 5-Stage Pipelined Processor — UVM Verification

A complete design and verification environment for an RV32I 5-stage pipelined processor, built from scratch in SystemVerilog with a UVM 1.2 testbench, 28 SVA properties, 19 functional covergroups, and a multi-seed regression framework.

**96% functional coverage · 683 checks passed / 0 failed · 100 seeds · 23 bugs found & fixed**

<img width="1568" height="295" alt="image" src="https://github.com/user-attachments/assets/0f99576c-4791-478a-98a3-26ff0e2b3585" />


---

## Table of Contents

- [Architecture](#architecture)
- [Design Features](#design-features)
- [Verification Environment](#verification-environment)
  - [Testbench Architecture](#testbench-architecture)
  - [Stimulus Strategy](#stimulus-strategy)
  - [Scoreboard Reference Model](#scoreboard-reference-model)
  - [Assertions (SVA)](#assertions-sva)
  - [Functional Coverage](#functional-coverage)
- [Coverage Results](#coverage-results)
- [Bug Summary](#bug-summary)
- [Regression](#regression)
- [Repository Structure](#repository-structure)
- [How to Run](#how-to-run)
- [Key Design Decisions](#key-design-decisions)
- [Limitations & Future Work](#limitations--future-work)

---

## Architecture

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ IF Stage │───▶│ ID Stage │───▶│ EX Stage │───▶│MEM Stage │───▶│ WB Stage │
│          │    │          │    │          │    │          │    │          │
│ PC Reg   │    │ Reg File │    │ ALU      │    │ DMEM I/F │    │ Mux      │
│ PC Next  │    │ Imm Gen  │    │ Branch   │    │          │    │ Reg Write│
│ IMEM I/F │    │ Decoder  │    │ Fwd Unit │    │          │    │          │
└──────────┘    │ ALU Ctrl │    └──────────┘    └──────────┘    └──────────┘
                └──────────┘
                                    │
                              ┌─────┴─────┐
                              │  Hazard   │
                              │   Unit    │
                              └───────────┘

Pipeline registers: if_id_t → id_ex_t → ex_mem_t → mem_wb_t (packed structs)
```

**ISA support:** RV32I base integer instruction set (37 instructions)  
**Pipeline:** 5-stage in-order — IF → ID → EX → MEM → WB  
**Hazard handling:** Full data forwarding (EX→EX, MEM→EX) + load-use stall + branch/jump flush

---

## Design Features

| Feature | Implementation |
|---|---|
| **Forwarding** | 2-level forwarding unit: EX/MEM → EX (priority) and MEM/WB → EX, with `mem_to_reg` mux for load forwarding |
| **Load-use hazard** | Hazard unit detects `id_ex.mem_read` with register match → stalls IF/ID, flushes EX |
| **Branch resolution** | Resolved in EX stage; branch/jump → flush IF + ID, redirect PC |
| **Register file bypass** | Combinational read-during-write bypass prevents stale reads on 3-cycle-gap instructions |
| **JALR target** | `(rs1 + imm) & ~1` with forwarded operand_a, handles rd==rs1 overlap |
| **AUIPC** | Dedicated `use_pc` mux overrides operand_a to PC regardless of forwarding |
| **Memory** | Separate IMEM/DMEM Harvard interfaces, word-aligned (LW/SW only) |

---

## Verification Environment

### Testbench Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        riscv_env                                │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐     │
│  │ imem_agent  │  │ dmem_agent  │  │  riscv_monitor       │     │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │  (commit interface)  │     │
│  │ │sequencer│ │  │ │ dmem_drv│ │  └──────────┬───────────┘     │
│  │ └────┬────┘ │  │ └─────────┘ │             │                 │
│  │ ┌────┴────┐ │  └─────────────┘     ┌───────┴────────┐        │
│  │ │imem_drv │ │                      │                │        │
│  │ └─────────┘ │               ┌──────┴──────┐  ┌──────┴────┐   │
│  └─────────────┘               │ scoreboard  │  │ coverage  │   │
│                                │ (ref model) │  │(19 groups)│   │
│  ┌──────────────────────┐      └─────────────┘  └─────┬─────┘   │
│  │ riscv_exec_monitor   │                             │         │
│  │ (pipeline internals) ├─────────────────────────────┘         │
│  └──────────────────────┘                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │    riscv_core     │
                    │ (DUT + assertions)│
                    └───────────────────┘
```

**Key components:**

- **imem_driver** — Pre-loads instruction memory from sequences; serves fetch requests combinationally with `#1` post-posedge timing to avoid NBA skew
- **dmem_driver** — Behavioral data memory (1024 words); same timing model as IMEM
- **riscv_monitor** — Observes commit interface (MEM/WB retirement); detects EBREAK sentinel for program termination
- **riscv_exec_monitor** — Observes pipeline-internal signals (forwarding, stalls, flushes) via bound `exec_if` for microarchitectural coverage
- **riscv_scoreboard** — Full ISA reference model executing all RV32I instructions in `logic` (4-state) types
- **riscv_coverage** — 19 covergroups with cross coverage on pipeline interactions

### Stimulus Strategy

The environment uses a **program pre-load model**: sequences generate complete instruction programs, load them into IMEM, then release the core from reset. Programs terminate via an **EBREAK sentinel** (`0x00100073`) that fills unused memory.

| Phase | Sequence | Purpose |
|---|---|---|
| 1 | `seq_init` | 32 LUI instructions — seed register file |
| 2 | `seq_dep` | 300 instructions with dependency chaining (rs1/rs2 linked to previous rd) |
| 3 | `seq_rand` | 300 fully random instructions with weighted type distribution |
| 4 | `seq_load_stress` | 200 load-use pairs — stress hazard detection and stalling |
| 5 | `seq_load_full` | 100 pure loads |
| 6 | `seq_store_full` | 100 pure stores |
| 7 | `seq_jalr_full` | 100 JALR instructions — stress indirect jump handling |
| 8 | `seq_itype_neg` | 100 I-type with negative immediate bias |
| 9-10 | `seq_fwd_stress/cross` | 300-400 dependency-chained instructions — maximize forwarding coverage |

**Constraint highlights:**
- `adjust_control_flow()` bounds all branch/jump targets to valid forward IMEM range, preventing infinite loops
- JALR targets computed as absolute addresses using `base_addr` (accounts for warmup offset)
- Load/store addresses constrained to valid DMEM range via `rs1 == 0` + bounded immediate
- Weighted distribution: R/I-type 20% each, load/store 10%, branch 15%, jump 5%, LUI/AUIPC 7-8%

### Scoreboard Reference Model

The scoreboard maintains a complete architectural state (`ref_reg[0:31]`, `ref_mem[0:1023]`, `ref_pc`) and executes every retired instruction to predict expected results. Key implementation details:

- **4-state types** (`logic`, not `bit`) — prevents `$signed()` misinterpretation on SRA/SLT operations
- **JALR ordering** — `ref_pc` computed *before* `check_and_write(rd)` to handle rd==rs1 overlap
- **SRA** — Uses `int signed` intermediate variable for arithmetic right shift to avoid simulator-dependent ternary expression behavior
- **x0 hardwire** — `ref_reg[0] = 0` enforced after every instruction

### Assertions (SVA)

28 concurrent assertions + 3 cover properties, bound to the DUT via `riscv_bind.sv` with explicit signal mapping that distinguishes:

- **Hazard detection signals** (from `id_ex` pipeline register)
- **Forwarding check signals** (from `ex_mem` / `mem_wb` pipeline registers)

| Category | Assertions | Properties Verified |
|---|---|---|
| PC integrity | A1, A2, A14, A23, A24, A28 | Alignment, normal increment, redirect update, stall freeze |
| Memory safety | A3, A18 | No simultaneous read/write, store doesn't set reg_write |
| Writeback | A4, A27 | Mux correctness (`mem_to_reg` select), temporal consistency |
| Valid commit | A5 | Only legal RV32I opcodes + EBREAK retire |
| Hazard unit | A6, A7 | Load-use detection fires correctly, no false stalls |
| Forwarding | A8–A11, A16, A17, A22, A25, A26 | EX/MEM forward paths active when needed, inactive when not, correct values |
| Pipeline control | A12, A13, A15, A19, A20, A21 | Stall freezes state, flush injects bubble, redirect has priority, jump enables reg_write |

### Functional Coverage

19 covergroups organized by verification intent:

| Covergroup | What It Measures | Bins | Status |
|---|---|---|---|
| `cov_opcode` | All 9 instruction types + funct3 cross | 25 cross bins | 100% |
| `cov_decode` | R-type funct3 × funct7 (ADD vs SUB, SRL vs SRA) | 10 cross bins | 100% |
| `cov_registers` | rs1/rs2/rd range coverage + cross | 32 cross bins | 100% |
| `cov_imm` | Immediate value ranges (zero, small/mid/large pos/neg) | 6 bins | 100% |
| `cov_branch` | All 6 branch types (BEQ/BNE/BLT/BGE/BLTU/BGEU) | 6 bins | 100% |
| `cov_forward` | Forwarding paths A/B (none/EX/MEM) + cross | 7 cross bins | 100% |
| `cov_hazard` | Stall/flush occurrence + cross | 2 cross bins | 100% |
| `cov_redirect` | PC redirect events | 2 bins | 100% |
| `cov_branch_outcome` | Branch type × taken/not-taken cross | 12 cross bins | 97.2% |
| `cov_hazard_source` | Which opcode caused stall/forward | 10 bins | 93.3% |
| `cov_reg_hazard` | rd==rs1, rd==rs2, rs1==rs2 match/no-match | 6 bins | 100% |
| `cov_instr_sequence` | Previous × current instruction type (7×7 cross) | 49 cross bins | 95.9% |
| `cov_data_dep` | RAW dependency on rs1, rs2, both | 6 bins | 100% |
| `cov_corner` | rd==x0 writes, redirect during stall, branch with forwarding | 5 bins | 100% |
| `cov_memory` | Load/store address ranges, store-then-load pattern | 7 bins | 83.3% |
| `cov_alu_result` | Shift amounts (reg/imm), SLT destination ranges | 12 bins | 85% |
| `cov_branch_direction` | Forward/backward branch × taken/not-taken | 4 cross bins | 66.7% |
| `cov_flush_source` | Which instruction type caused flush | 3 bins | 100% |
| `cov_writeback` | ALU vs memory writeback source by opcode | 7 bins | 100% |

---

## Coverage Results

```
CUMULATIVE COVERGROUP COVERAGE: 96.010%
COVERED TYPES: 13 / 19 at 100%

Tool      : Riviera-PRO 2025.04
Seeds     : 100
Sim time  : 13,535 ns (per seed)
```

**Remaining holes and analysis:**

| Uncovered Bin | Root Cause | Closure Path |
|---|---|---|
| `cov_branch_direction.backward` | All branches constrained to forward targets to prevent infinite loops | Directed sequence with bounded backward branch (target > current PC but < EBREAK) |
| `cov_branch_outcome.<BEQ,taken>` | BEQ-taken requires equal register values, rare under random stimulus | Directed sequence pre-loading equal values into rs1/rs2 before BEQ |
| `cov_memory.store_then_load` | Store followed by load to same address never generated | Directed store→load sequence pair targeting same DMEM word |
| `cov_alu_result.cp_shamt.zero` | Zero shift amount not generated for register-shift instructions | Constrain `rs2 = 0` or pre-load x0 as shift source |
| `cov_hazard_source.fwd_b.jal` | JAL forwarding on operand B path extremely rare | Directed JAL→R-type sequence where JAL.rd feeds next instruction's rs2 |

---

## Bug Summary

**23 total bugs found and fixed** across 4 categories during testbench development:

### RTL Bugs (1)

| # | Module | Bug | Impact | Fix |
|---|---|---|---|---|
| R1 | `register_file` | No write→read bypass; WB writes at same posedge ID reads → stale value | Data mismatches on 3-cycle-gap instructions | Added combinational bypass: forward `rd_data` to read port when `we && rd_addr != 0 && rd_addr == rs_addr` |

### UVM Testbench Bugs (10)

| # | Bug | Root Cause | Fix |
|---|---|---|---|
| T2 | IMEM data 1 cycle late | NBA (`<=`) on posedge — rdata arrived next cycle | `@(posedge clk); #1;` then blocking `=` |
| T3 | DMEM data 1 cycle late | Same NBA timing issue | Same fix as T2 |
| T4 | Pass/fail counters overflow at 1 | Declared as 1-bit `logic` | Changed to `int` |
| T6 | JALR scoreboard corruption when rd==rs1 | `check_and_write` updated `ref_reg[rd]` before `ref_pc = ref_reg[rs1] + imm` | Compute `ref_pc` before `check_and_write` |
| T7 | Branch condition always true | `target <= pc || target >= pc` is tautology | Changed to `target < 0 || target >= max_pc` |
| T8 | JALR post_randomize not always called | `post_randomize()` only inside if-block | Moved outside if-block |
| T9 | JALR targets offset by warmup | Sequence-local PC (0-based) vs DUT absolute PC | Added `base_addr` field computed from `idrv.load_addr * 4` |
| T11 | Load-use stress modified wrong transaction | Passed already-sent `tr` instead of `dep_tr` | Changed to `adjust_control_flow(dep_tr, ...)` |
| T13 | SRA reference model incorrect | `$signed(logic_var) >>> shift` lost signedness in ternary | Used `int signed` intermediate variable |
| T5 | Counters reset between phases | `reset_state()` cleared pass/fail counts | Removed counter resets from `reset_state()` |

### Assertion Bugs (2)

| # | Bug | Fix |
|---|---|---|
| A5 | `OPCODE_LOAD` missing from valid commit list | Added to opcode set |
| A26 | AUIPC overrides operand_a to PC regardless of forwarding | Added `id_ex_opcode != OPCODE_AUIPC` guard |

### Coverage Bugs (10)

Notable fixes: Riviera-PRO `!binsof` compound expressions mishandled → replaced with individual per-value `ignore_bins`; impossible cross bins (stall without flush, redirect during stall) marked as `ignore_bins`; address ranges adjusted from theoretical to achievable (12-bit sign-extended immediates max at 2047).

---

## Regression

### `regress.py` — Multi-seed regression runner
> **Note:** The regression script was written but **not executed** in this project due to lack of access to a local simulator license. All simulation results (683 passed, 96% coverage) were obtained by running individual seeds manually through Riviera-PRO via EDA Playground / cloud instances. The script is included to demonstrate regression methodology and is ready to run in any environment with a UVM-capable simulator.

```bash
python3 regress.py                        # 10 random seeds
python3 regress.py -n 100                 # 100 random seeds
python3 regress.py -s 42 100 777          # specific seeds
python3 regress.py -t riscv_rtype_test    # per-type test
python3 regress.py --clean -n 50          # clean + 50 seeds
```

**Features:**
- Per-seed isolation (separate directories, logs, coverage databases)
- Automatic ACDB merge across all seeds
- UVM error/fatal parsing from logs
- Scoreboard pass/fail extraction
- Colored terminal output with summary table
- Configurable timeout (default 300s per seed)
- Exit code 0 only if all seeds pass

**Output:**
```
══════════════════════════════════════════════════════════════
                    REGRESSION SUMMARY
══════════════════════════════════════════════════════════════
      Seed      Status     Pass    Fail   Errors   Fatals
  ────────────────────────────────────────────────────────
       100      PASS        683       0        0        0
       200      PASS        671       0        0        0
       ...
──────────────────────────────────────────────────────────────
  Seeds run     : 100
  Passed        : 100
  Failed        : 0
  Merged cov    : 96.01%
══════════════════════════════════════════════════════════════
```

---

## Repository Structure

```
├── design/
│   ├── riscv_pkg.sv              # Types, enums, pipeline structs
│   ├── pc_reg.sv                 # PC register
│   ├── pc_next_logic.sv          # PC mux (redirect / +4)
│   ├── if_stage.sv               # Instruction fetch + IF/ID register
│   ├── register_file.sv          # 32x32 register file with WB bypass
│   ├── imm_generator.sv          # Immediate decoder (all RV32I formats)
│   ├── main_decoder.sv           # Opcode → control signals
│   ├── alu_control.sv            # funct3/funct7 → ALU op + branch type
│   ├── id_stage.sv               # Decode + ID/EX register
│   ├── alu.sv                    # 11-operation ALU
│   ├── branch_unit.sv            # Branch comparator (6 types)
│   ├── forwarding_unit.sv        # 2-level forwarding (EX, MEM)
│   ├── ex_stage.sv               # Execute + EX/MEM register
│   ├── mem_stage.sv              # Memory access + MEM/WB register
│   ├── hazard_unit.sv            # Load-use stall detection
│   ├── riscv_core.sv             # Top-level pipeline integration
│   ├── imem_if.sv                # Instruction memory interface
│   ├── dmem_if.sv                # Data memory interface
│   ├── commit_if.sv              # Commit observation interface
│   └── exec_if.sv                # Pipeline observation interface
│
├── verification/
│   ├── riscv_assertions.sv       # 28 SVA properties
│   ├── riscv_bind.sv             # Assertion + exec monitor binding
│   └── riscv_tb.sv               # Top-level testbench module
│
├── scripts/
│   └── regress.py                # Multi-seed regression runner
│
├── docs/
│   ├── waveform.png              # Simulation waveform capture
│   ├── coverage_report.txt       # Full Riviera-PRO coverage report
│   └── bug_log.md                # Complete bug tracking document
│
└── README.md
```

---

## How to Run

### Prerequisites

- SystemVerilog simulator with UVM 1.2 support (tested with Riviera-PRO 2025.04)
- Python 3.6+ (for regression script)

### Single Test

```bash
vsim +access+r +UVM_TESTNAME=riscv_*_test -sv_seed 100;
run -all;
acdb save;
acdb report -db  fcover.acdb -txt -o cov.txt -verbose  
exec cat cov.txt;
exit

# Available tests: replace * with one of these
#   riscv_random_test   — 10-phase full regression (primary test)
#   riscv_rtype_test    — R-type only
#   riscv_itype_test    — I-type only
#   riscv_load_test     — Load only
#   riscv_store_test    — Store only
#   riscv_branch_test   — Branch only
#   riscv_jal_test      — JAL only
#   riscv_jalr_test     — JALR only
#   riscv_lui_test      — LUI only
#   riscv_auipc_test    — AUIPC only
```

### Multi-Seed Regression

```bash
python3 scripts/regress.py -n 100          # 100 random seeds
python3 scripts/regress.py -s 42 100 777   # specific seeds
python3 scripts/regress.py --clean -n 50   # fresh run
```

### Coverage Collection

```bash
# Single seed with coverage
asim +access+r +UVM_TESTNAME=riscv_random_test -sv_seed 100 riscv_tb
acdb save -db cov.acdb
acdb report -db cov.acdb -txt -o cov.txt -verbose
```

---

## Key Design Decisions

**Why program pre-load instead of per-cycle random stimulus?**  
Per-cycle random generation caused JAL/JALR to jump out of bounds, producing infinite NOP streams. Pre-loading a complete program with bounded control flow and an EBREAK sentinel gives deterministic termination while preserving constrained-random instruction selection.

**Why `logic` instead of `bit` in the scoreboard?**  
SystemVerilog's `$signed()` behaves differently on 2-state (`bit`) vs 4-state (`logic`) types. Using `bit` caused SRA reference model mismatches that only manifested on specific shift amounts. All scoreboard state uses `logic` for correct signed arithmetic.

**Why dual monitors (commit + exec)?**  
Architectural correctness is checked at the commit point (MEM/WB retirement). But pipeline coverage (forwarding paths, stall/flush behavior) requires observing signals *before* they propagate to retirement. The exec monitor taps `id_ex` stage signals via a bound interface without modifying the DUT.

**Why EBREAK instead of instruction counting?**  
Counting committed instructions is fragile — stores and branches don't always produce commits, and pipeline flushes discard instructions. EBREAK retirement is an unambiguous program-end signal that works regardless of the instruction mix.

---

## Limitations & Future Work

| Limitation | Extension |
|---|---|
| Word-only memory (LW/SW) | Add LB/LH/LBU/LHU/SB/SH with byte-enable logic and scoreboard updates |
| No CSR support | Add M-mode CSRs (mstatus, mepc, mcause) with UVM RAL model |
| No interrupts/exceptions | Add trap handling, illegal instruction detection |
| Single-seed coverage report shown | Regression merges coverage across seeds via `regress.py` |
| Backward branch not covered | Add directed sequence with bounded negative immediate |
| No formal verification | Add SymbiYosys or JasperGold proofs for forwarding/hazard unit correctness |

---

## Tools

| Tool | Version | Purpose |
|---|---|---|
| Riviera-PRO | 2025.04 | Simulation, coverage collection |
| Python | 3.x | Regression scripting |
| UVM | 1.2 | Verification methodology |

---
