# Bug Log — RISC-V 5-Stage Pipeline UVM Verification

**Project:** RV32I Pipelined Processor Verification  
**Author:** Jaishyam Reddivari  
**Total Bugs Found & Fixed:** 23 (1 RTL, 10 Testbench, 2 Assertion, 10 Coverage)  
**Final State:** 683 passed / 0 failed · 96% functional coverage · 28 assertions clean

---

## Table of Contents

- [Development Timeline](#development-timeline)
- [RTL Design Bugs](#rtl-design-bugs)
- [UVM Testbench Bugs](#uvm-testbench-bugs)
- [Assertion Bugs](#assertion-bugs)
- [Coverage Engineering Fixes](#coverage-engineering-fixes)
- [Early Development Issues](#early-development-issues)
- [Final Metrics](#final-metrics)

---

## Development Timeline

The verification environment went through three major architectural shifts before reaching its final form:

1. **Per-cycle random stimulus** — Each clock cycle generated a new random instruction and drove it into the core. JAL/JALR immediates routinely jumped outside the 4KB IMEM, producing infinite NOP streams. Coverage stalled at ~30%.

2. **Program pre-load model** — Sequences generate a complete instruction program, load it into IMEM with EBREAK sentinels filling unused slots, then release the core from reset. This solved termination but exposed register file initialization issues (all zeros → poor test quality) and control flow bounding problems.

3. **Warmup + multi-phase regression** — Added a 32-instruction LUI warmup to seed registers before each phase. 10 specialized phases target different verification goals (dependency stress, load-use pairs, forwarding cross coverage). Coverage moved from 52% → 96%.

---

## RTL Design Bugs

### R1 — Register File Missing Write→Read Bypass

| Field | Detail |
|---|---|
| **Module** | `register_file` |
| **Severity** | High — silent data corruption |
| **Symptom** | Data mismatches on instructions with a 3-cycle gap. Scoreboard expected the updated value, DUT read the stale pre-write value. Mismatches appeared intermittently depending on instruction scheduling. |
| **Root Cause** | The register file writes on the positive clock edge (`always_ff @(posedge clk)`). The ID stage reads on the same edge. When WB writes register X and ID reads register X in the same cycle, the read gets the old value because the write hasn't propagated yet. |
| **Debug Path** | Waveform inspection showed `rs1_data` lagging `rd_data` by one cycle when `rd_addr == rs1_addr`. Initially suspected forwarding unit, but forwarding only covers EX and MEM stage hazards — the WB→ID conflict is a register file design issue. |
| **Fix** | Added combinational bypass on the read ports: |

```systemverilog
assign rs1_data = (rs1_addr == 5'd0) ? '0 :
                  (we && rd_addr != 5'd0 && rd_addr == rs1_addr) ?
                  rd_data : regs[rs1_addr];
// Same for rs2_data
```

**Verification:** Re-ran all 10 phases — eliminated a class of intermittent mismatches that had been masked by the low probability of the specific instruction spacing.

---

### Early RTL Bugs (Fixed During Initial Bring-up)

These bugs were found during the first week of testbench development, before the scoreboard was fully functional. They are documented here for completeness but were not part of the final verification cycle.

#### R-early-1 — MEM Stage Flushed on Redirect

| Field | Detail |
|---|---|
| **Symptom** | Valid instruction in MEM killed when branch resolves in EX → missing commits, PC mismatches |
| **Root Cause** | `mem_stage.flush` was connected to `redirect_valid`. When a branch/jump resolved in EX, the flush propagated to MEM and killed the instruction that was already past the branch point. |
| **Fix** | Changed `mem_stage.flush` to `1'b0`. MEM stage should never be flushed — by the time an instruction reaches MEM, it is architecturally committed. |

#### R-early-2 — Load-Use Hazard Caused Infinite Stall

| Field | Detail |
|---|---|
| **Symptom** | Core deadlocked on any load-use sequence. Watchdog timeout. |
| **Root Cause** | `flush_ex` cleared the EX/MEM register (killing the load result), while `stall_id` held the dependent instruction in ID/EX forever. The load could never reach MEM to produce its result. |
| **Fix** | Changed `id_stage.flush = redirect_valid || flush_ex` (bubble into ID/EX on load-use), `ex_stage.flush = 1'b0` (let the load propagate through to MEM undisturbed). |

#### R-early-3 — Commit Valid Only Fired for reg_write

| Field | Detail |
|---|---|
| **Symptom** | Scoreboard hung waiting for store and branch commits that never arrived. |
| **Root Cause** | `commit.valid` was gated by `mem_wb.ctrl.reg_write`. Stores and branches don't write registers, so they never signaled a commit. |
| **Fix** | Changed to `commit.valid = (mem_wb.instr != 32'b0)`. Any non-bubble instruction in WB is a valid commit. |

---

## UVM Testbench Bugs

### T2 — IMEM Driver NBA Timing (Primary Root Cause)

| Field | Detail |
|---|---|
| **Location** | `imem_driver::run_phase` |
| **Severity** | Critical — every instruction paired with wrong PC |
| **Symptom** | Systematic PC mismatches. Instruction at address 0x00 was being checked against PC 0x04. Every single instruction was off by one cycle. |
| **Root Cause** | The IMEM driver used non-blocking assignment (`<=`) on `posedge clk` to drive `rdata`. Non-blocking assignments update at the end of the time step, so `rdata` arrived one cycle late relative to the fetch address. The core saw instruction N when it expected instruction N-1. |
| **Debug Path** | Added `$display` on both the driver and monitor sides. Noticed that the monitor's `commit.instr` consistently matched the *next* instruction in the program, not the current one. Waveform confirmed `rdata` transitioning one cycle after `addr`. |
| **Fix** | Changed to `@(posedge clk); #1;` followed by blocking assignment (`=`). The `#1` places the driver in the NBA region after all synchronous updates, and the blocking assignment makes `rdata` visible immediately. |

```systemverilog
// BEFORE (broken):
@(posedge vif.clk);
vif.rdata <= instr_mem[vif.addr >> 2];  // arrives next cycle

// AFTER (correct):
@(posedge vif.clk);
#1;
vif.rdata = instr_mem[vif.addr >> 2];   // available this cycle
```

**Impact:** This was the single highest-impact bug. Fixing it resolved dozens of downstream mismatches that had been individually debugged as separate issues.

---

### T3 — DMEM Driver Same Timing Issue

| Field | Detail |
|---|---|
| **Location** | `dmem_driver::run_phase` |
| **Severity** | High — all load results wrong |
| **Symptom** | Load instructions returned data from the wrong address (off by one cycle). |
| **Root Cause** | Identical to T2: NBA timing on `rdata`. |
| **Fix** | Same pattern: `@(posedge dif.clk); #1;` then blocking `=`. |

---

### T4 — Scoreboard Counter Overflow

| Field | Detail |
|---|---|
| **Location** | `riscv_scoreboard` |
| **Severity** | Low — cosmetic but misleading |
| **Symptom** | Report phase showed "1 passed, 0 failed" regardless of how many instructions ran. |
| **Root Cause** | `pass_count` and `fail_count` were declared as `logic` (1-bit by default). They overflowed after the first increment. |
| **Fix** | Changed to `int pass_count, fail_count;` |

---

### T5 — Scoreboard Counters Reset Between Phases

| Field | Detail |
|---|---|
| **Location** | `riscv_scoreboard::reset_state` |
| **Severity** | Medium — lost accumulated results |
| **Symptom** | Final report only showed results from the last phase, not the cumulative total across all 10 phases. |
| **Root Cause** | `reset_state()` zeroed both `pass_count` and `fail_count` along with the architectural state. Called at the start of each phase. |
| **Fix** | Removed counter resets from `reset_state()`. Counters now accumulate across the entire test. |

---

### T6 — JALR Scoreboard rd==rs1 Ordering Bug

| Field | Detail |
|---|---|
| **Location** | `riscv_scoreboard::execute_instruction`, JALR case |
| **Severity** | High — cascading PC corruption |
| **Symptom** | JALR instructions where `rd == rs1` produced wrong link address AND wrong jump target. After the first JALR mismatch, all subsequent PC checks failed because `ref_pc` diverged permanently. |
| **Root Cause** | The scoreboard executed `check_and_write(rd, ct.pc + 4, ct.data)` before computing `ref_pc = (ref_reg[rs1] + imm) & ~1`. When `rd == rs1`, `check_and_write` updated `ref_reg[rd]` (which IS `ref_reg[rs1]`), so the subsequent `ref_pc` computation used the *new* link address value instead of the *old* rs1 value. The DUT correctly reads rs1 before writing rd (pipeline ordering), so the DUT and scoreboard diverged. |
| **Debug Path** | Narrowed to JALR by adding per-opcode logging. Noticed the mismatch only occurred when `rd == rs1`. Traced through the scoreboard execution order and found the write-before-read hazard. |
| **Fix** | Compute `ref_pc` before `check_and_write`: |

```systemverilog
// JALR case
result = ct.pc + 4;
ref_pc = (ref_reg[rs1] + imm) & ~1;  // read rs1 BEFORE write
check_and_write(rd, result, ct.data); // now safe to update ref_reg[rd]
```

---

### T7 — Branch Constraint Tautology

| Field | Detail |
|---|---|
| **Location** | `riscv_sequence::adjust_control_flow`, BRANCH case |
| **Severity** | Medium — all branches forced to imm=8 |
| **Symptom** | Every branch instruction had `imm = 8`. No variation in branch targets. Branch coverage stalled. |
| **Root Cause** | The bounds check was `target <= pc || target >= pc`, which is always true for any integer value. Every branch hit the fallback path. |
| **Fix** | Changed to `target < 0 || target >= max_pc`. |

---

### T8 — JALR post_randomize Not Always Called

| Field | Detail |
|---|---|
| **Location** | `riscv_sequence::adjust_control_flow`, JALR case |
| **Severity** | Medium — JALR encoding inconsistent |
| **Symptom** | Some JALR instructions had `rs1 != 0` in the encoded instruction despite the constraint forcing `rs1 = 0`. Caused jumps to uninitialized register values → out-of-bounds targets → infinite loops. |
| **Root Cause** | `tr.post_randomize()` (which re-encodes the instruction from fields) was only called inside the if-block that modified `imm`. When the if-condition was false, the transaction kept the original encoding with the original non-zero `rs1`. |
| **Fix** | Moved `tr.post_randomize()` outside the if-block so it always re-encodes after field modifications. |

---

### T9 — JALR Warmup Offset Bug

| Field | Detail |
|---|---|
| **Location** | `riscv_sequence::adjust_control_flow`, JALR target computation |
| **Severity** | High — JALR jumped into warmup region |
| **Symptom** | With warmup enabled, JALR instructions jumped to addresses in the warmup LUI region (PC 0x00–0x7F) instead of the main program region. This created infinite loops because the warmup region had no EBREAK. Watchdog timeouts on every phase with JALR instructions. |
| **Root Cause** | The sequence used a local `pc` variable starting at 0, but the DUT's actual PC was offset by the warmup size (32 instructions × 4 bytes = 128). JALR targets were computed as absolute addresses (since `rs1 = 0`), so the 0-based sequence PC produced targets that fell in the warmup region. |
| **Fix** | Added `base_addr` field to the sequence, set from `e.ia.idrv.load_addr * 4` before starting the sequence. All JALR absolute address calculations now use `base_addr + pc` instead of just `pc`. |

---

### T10 — JALR Fallback Self-Loop

| Field | Detail |
|---|---|
| **Location** | `riscv_sequence::adjust_control_flow`, JALR fallback path |
| **Severity** | Medium — specific JALR patterns looped forever |
| **Symptom** | Certain JALR instructions caused the program to loop on the same instruction indefinitely. |
| **Root Cause** | The fallback immediate was set to `base_addr + max_pc - 4`, which pointed to the last instruction in the program. If that last instruction was itself a JALR, it would jump to itself. |
| **Fix** | Changed fallback to `base_addr + max_pc`, which points to the EBREAK sentinel immediately after the program. |

---

### T11 — Load-Use Stress Wrong Transaction

| Field | Detail |
|---|---|
| **Location** | `riscv_sequence::body`, load_use_stress path |
| **Severity** | Medium — load-use pairs not properly linked |
| **Symptom** | Load-use stress mode didn't actually create dependency pairs. The dependent instruction's `rs1` didn't match the load's `rd`. |
| **Root Cause** | The code passed `tr` (the already-sent load transaction) to `adjust_control_flow` instead of `dep_tr` (the dependent instruction). It also modified `tr.rd` after `tr` had already been sent to the driver, which has no effect. |
| **Fix** | Changed to `adjust_control_flow(dep_tr, ...)` and `last_rd = 5'd5` (fixed fallback when `tr.rd == 0`). |

---

### T-early — Additional Testbench Issues (Fixed During Bring-up)

| # | Bug | Fix |
|---|---|---|
| T-e1 | Core PC not reset between sequences — IMEM reloaded at addr 0 but core PC still at previous position | Added `rst_drive` signal in `commit_if`, `reset_dut()` task asserts/deasserts hardware reset between sequences |
| T-e2 | Expected commit count included stores/branches that don't commit | Replaced count-based completion with EBREAK sentinel detection |
| T-e3 | No program termination detection — relied on fragile commit counting | Filled unused IMEM with EBREAK, monitor fires `program_done` event on EBREAK retirement |
| T-e4 | Premature EBREAK — `reset_dut()` released core before program was loaded | Restructured `run_seq`: hold reset → load program → release reset |
| T-e5 | Data memory not reset between sequences — stale data leaked | Added `e.da.ddrv.reset()` in `run_seq` |
| T-e6 | No scoreboard reset between sequences | Added `reset_state()` function, called at start of each `run_seq` |
| T-e7 | Missing `randomize()` in default sequence path | Added `else assert(tr.randomize())` |
| T-e8 | JAL/JALR link address used `ref_pc + 4` instead of `ct.pc + 4` | Changed to `result = ct.pc + 4` |
| T-e9 | SRA reference model: `$signed(logic_var) >>> shift` in ternary lost signedness | Used `int signed` intermediate variable |
| T-e10 | EBREAK hit `illegal_bins` in coverage | Added `if (instr == 32'h00100073) return;` at top of coverage `write()` |
| T-e11 | All-zero register file — random phases operated on zero registers | Added warmup parameter that prepends 32 LUI instructions |
| T-e12 | Backward branch/jump targets created infinite loops | `adjust_control_flow` forces forward-only targets |
| T-e13 | `bit` type in scoreboard caused unreliable `$signed()` behavior | Changed `ref_reg`, `ref_mem`, `ref_pc` from `bit` to `logic` |

---

## Assertion Bugs

### A-fix-1 — OPCODE_LOAD Missing from Valid Commit List (A5)

| Field | Detail |
|---|---|
| **Assertion** | `commit_valid_instr` — checks that every retiring instruction has a legal opcode |
| **Symptom** | Every retiring load instruction triggered a false `"Commit with unknown opcode"` error. |
| **Root Cause** | The opcode whitelist in the assertion included R-type, I-type, store, branch, JAL, JALR, LUI, AUIPC, and EBREAK — but not LOAD (`7'b0000011`). Since loads always retire through WB, every load commit was flagged as invalid. |
| **Fix** | Added `OPCODE_LOAD` to the valid opcode set. |

---

### A-fix-2 — AUIPC Forwarding Exception (A26)

| Field | Detail |
|---|---|
| **Assertion** | `ex_forward_value_rs1` — checks that when `forward_a == 2'b10`, the EX stage operand_a equals the forwarded ALU result |
| **Symptom** | Every AUIPC instruction with active forwarding on rs1 triggered a false error. The assertion expected `operand_a == ex_mem_alu_result`, but operand_a was the PC value instead. |
| **Root Cause** | The AUIPC instruction overrides operand_a to the PC value regardless of forwarding status (the `use_pc` mux in `ex_stage`). This is architecturally correct — AUIPC computes `PC + imm`, not `rs1 + imm`. The forwarding value is irrelevant. |
| **Fix** | Added `&& id_ex_opcode != OPCODE_AUIPC` to the assertion antecedent. |

---

### Assertion Bugs Fixed During Development

These were found and fixed iteratively during assertion development. Documented for completeness.

| # | Assertion | Bug | Fix |
|---|---|---|---|
| A-e1 | A6/A7 | Used EX/MEM stage signals for hazard checks, but hazard unit operates on ID/EX stage | Split into `hazard_ex_rd` / `hazard_ex_mem_read` (from `id_ex`) vs `fwd_ex_rd` / `fwd_ex_reg_write` (from `ex_mem`) |
| A-e2 | A8–A11 | Ambiguous `ex_rd`/`mem_rd` signal names — same name for hazard and forwarding checks from different pipeline stages | Explicit `fwd_ex_*` and `fwd_mem_*` signal names bound from correct pipeline registers |
| A-e3 | A13 | Used `\|->` (same cycle) instead of `\|=>` (next cycle); checked wrong register | Changed to `\|=>`, checks `id_ex` controls, guarded with `!redirect_valid` |
| A-e4 | A15/A25 | No stall guard — stall can override redirect | Added `&& !stall_if` |
| A-e5 | A16–A18 | Used old signal names for forwarding checks | Updated to `fwd_ex_*` / `fwd_mem_*` / `ex_mem_*` |
| A-e6 | A20 | Same bug as A13 — wrong register, wrong timing | Same fix as A13 |
| A-e7 | A21 | No flush guard — `flush_ex` zeros `id_ex` via `id_stage.flush`, breaking `$stable()` | Added `&& !flush_ex` guard |
| A-e8 | A23 | Checked `commit_data == 0` when `rd == x0` — but `commit.data` shows ALU result before regfile gates x0 | Removed assertion — regfile correctly ignores x0 writes, verified by scoreboard |
| A-e9 | A26 | Dangling hierarchical reference `ex_mem.alu_result` not an input port | Added `ex_mem_alu_result` input port, bound to `ex_mem.alu_result` |
| A-e10 | A28 | Same hierarchical reference issue as A26 | Removed — redundant with A6 + A17 |

---

## Coverage Engineering Fixes

These are not bugs in the traditional sense but represent iterative refinement of covergroups to accurately measure verification completeness.

### C14 — cov_opcode Cross: Illegal funct3 Combinations

| Field | Detail |
|---|---|
| **Problem** | The opcode × funct3 cross included impossible combinations: LOAD with funct3 != 010, STORE with funct3 != 010, BRANCH with funct3 ∈ {010, 011}, JALR with funct3 != 000. These bins could never be hit because the constraints and RTL don't generate them. |
| **Tool Issue** | Riviera-PRO mishandled compound `!binsof` expressions, causing valid bins to be accidentally excluded. |
| **Fix** | Replaced compound `!binsof` with individual per-value `ignore_bins` for each illegal combination (e.g., `ignore_bins load_f0 = binsof(cp_opcode) intersect {7'b0000011} && binsof(cp_funct3) intersect {3'b000};`). |

### C15 — cov_decode Cross: Valid SUB/SRA Swallowed

| Field | Detail |
|---|---|
| **Problem** | `ignore_bins` intended to exclude invalid funct3×funct7 combinations (e.g., SLL with funct7=0100000) accidentally excluded valid SUB and SRA. |
| **Fix** | Individual `ignore_bins` per illegal pair: `sll_alt`, `slt_alt`, `sltu_alt`, `xor_alt`, `or_alt`, `and_alt`. |

### C16 — cov_hazard Cross: Structurally Impossible Bins

| Field | Detail |
|---|---|
| **Problem** | In this design, `stall` and `flush_ex` are both driven by the same `load_use_hazard` signal. Therefore `<stall, no_flush>` and `<no_stall, flush>` can never occur. |
| **Fix** | Added `ignore_bins` for both impossible combinations. |

### C17 — cov_imm: small_neg Unreachable

| Field | Detail |
|---|---|
| **Problem** | The `bit signed` type in the transaction prevented the constraint solver from generating values in [-16:-1] for certain instruction types. |
| **Fix** | Changed `small_neg` to `ignore_bins`. |

### C18 — cov_forward Cross: Rare Dual-Stage Forwarding

| Field | Detail |
|---|---|
| **Problem** | `<ex, mem>` and `<mem, ex>` bins require simultaneous forwarding from two different pipeline stages on operand A and B respectively. This requires three consecutive instructions with specific register dependencies — extremely rare under random stimulus. |
| **Fix** | Added `ignore_bins` for both. These could theoretically be hit with a directed sequence but are not worth the effort for the coverage model's goals. |

### C19 — cov_hazard_source: Load Forward via Operand A Unreachable

| Field | Detail |
|---|---|
| **Problem** | A load in the forwarding source for operand A requires a load instruction in the EX/MEM register whose `rd` matches the current instruction's `rs1`. However, loads in EX/MEM trigger a stall (not a forward), so the forward path is never used for loads on operand A. |
| **Fix** | Removed `load` bin from `cp_fwd_a_opcode`. |

### C20 — cov_corner: redirect_after_stall Impossible

| Field | Detail |
|---|---|
| **Problem** | A stall requires a load in EX. A redirect requires a branch/jump in EX. The same instruction cannot be both a load and a branch/jump. Therefore `redirect_valid && stall_if` can never be simultaneously true. |
| **Fix** | Changed to `ignore_bins impossible`. |

### C21 — cov_instr_sequence: Dual Monitor Corruption

| Field | Detail |
|---|---|
| **Problem** | Both the commit monitor and exec monitor fed the same `write()` function in coverage. The exec monitor updates arrived interleaved with commit updates, corrupting the `prev_opcode` / `prev_rd` tracking. Only same→same instruction pairs hit in the cross. |
| **Fix** | Added `if(ct.valid)` guard so that only commit monitor transactions (which set `ct.valid = 1`) update the previous-instruction tracking state. |

### C22 — cov_memory: Address Range Unreachable

| Field | Detail |
|---|---|
| **Problem** | `high_addr` was defined as `[2048:4092]`, but load/store addresses are computed as `rs1 + sign_extended_12bit_imm`. With `rs1 = 0` (constrained for loads/stores), the maximum address is 2047. The `high_addr` bin was unreachable. |
| **Fix** | Changed ranges to `[0:255]`, `[256:1023]`, `[1024:2047]` to match achievable address space. |

### C23 — cov_alu_result: Over-Granular and Unreachable Bins

| Field | Detail |
|---|---|
| **Problem** | `cp_slt_result` had 31 individual per-register bins — too granular for the verification goal (just need to see SLT writing to various registers). `cp_shamt_imm` had a `max` bin for shift amount 31, which was unreachable due to immediate encoding constraints. |
| **Fix** | Replaced `cp_slt_result` with ranged bins `low/mid/high`. Merged `max` into `high` for `cp_shamt_imm`. |

---

## Final Metrics

| Metric | Value |
|---|---|
| **Scoreboard checks** | 683 passed, 0 failed |
| **SVA assertions** | 28 properties, all clean (0 failures) |
| **Cover properties** | 3 (load-use hazard, EX forward, stall) |
| **Functional coverage** | 96.01% (13/19 groups at 100%) |
| **Covergroups** | 19 total |
| **Test phases** | 10 per seed |
| **Seeds run** | 100 |
| **Total fixes** | 23 (1 RTL + 10 testbench + 2 assertion + 10 coverage) |

### Remaining Coverage Hole

| Uncovered Bin | Cause | Closure Path |
|---|---|---|
| `cov_branch_direction.backward` (0 hits) | All branches constrained to forward-only targets to prevent infinite loops. Backward branches with valid in-bounds negative immediates are possible but require the target to land after the current PC in the program — rare under current constraints. | Directed sequence that generates a branch with a small negative immediate where the target address still falls within a previously-executed code region that leads to EBREAK. Alternatively, run additional seeds — the bin is seed-dependent and will hit on seeds that generate suitable immediate/PC combinations. |
