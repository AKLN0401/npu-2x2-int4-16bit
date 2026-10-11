# 02 — Verification plan, execution and limitations

## 1. Tools actually available (verified 2026-10-11)

| Tool | Where | Version | Used for |
|---|---|---|---|
| Icarus Verilog | tools image `tt-riscv-npu-tools` | 12.0 | RTL + GL cocotb sims (CI uses Ubuntu's iverilog) |
| Icarus Verilog | LibreLane image | 13.0 (devel) | — |
| cocotb | `npu1x1/tools/.cocotb2` | 2.1.0 (= `test/requirements.txt`, = CI) | all cocotb runs |
| Verilator | tools image / LibreLane image | 5.020 / 5.044 | lint (`-Wall`); flow lint step |
| Yosys | LibreLane image | 0.62 | synthesis (flow), equivalence (`sat`) |
| SymbiYosys + yosys-abc | LibreLane image | (bundled) | unbounded PE proof (`abc pdr`) |
| SMT solvers (z3, yices, boolector, bitwuzla) | — | **missing** | smtbmc engines, cover, CEX traces **unavailable** |
| OpenROAD / OpenSTA | LibreLane image | `dcf36133`, STA 2.7.0 | flow; extra STA queries |
| Magic / Netgen / KLayout | LibreLane image | 8.3.623 / 1.5.316 / 0.30.7 | flow DRC/LVS; GDS XOR |
| tt-support-tools | `tt/` | `01d5d281` (= `main`, as used by the CI action) | harden, precheck, docs check |
| Functional-coverage / assertion-coverage tool | — | **none** | coverage shown by construction + counters (see §4) |

## 2. Verification layers

| Layer | What it shows | Evidence |
|---|---|---|
| L1 lint | syntax, widths, unused, latches at 4 parameter sets | `logs/evidence/stage_runs/lint_*.log` (0 warnings) |
| L2 directed + random sim, RTL | behaviour vs **spec** (independent model) | existing `test/test.py` 8 tests × 5 seeds; audit `tests/audit_arith.py` 9 tests × 3 seeds |
| L3 same tests on the post-PnR netlist (unit delay) | netlist function vs spec | existing × 3 seeds, audit × 2 seeds, CI `gl_test` 8/8 |
| L4 formal PE proof | arithmetic for all states/operands | `formal/` (abc pdr) |
| L5 formal RTL ≡ netlist | every netlist state bit and output equals RTL | `equiv/` (yosys sat, induction) |
| L6 timing-annotated sims | function with real (SDF) delays, gated clocks, hold races | SDF cocotb 8/8 at max_ss_n40C and min_ff_n40C; SDF co-sim 3 corners × 200k cycles |
| L7 random lock-step co-sim | RTL vs netlist 4-state every cycle, incl. scan, test mode, async resets | 4 new seeds × 1M cycles (this audit) + 20 × 1M (2026-10-10) |
| L8 STA (flow + extra) | setup/hold at 12 corners, ICG gating checks, reset recovery/removal, unconstrained endpoints | `04_synthesis_and_timing.md` |
| L9 physical | DRC/LVS/antenna/precheck/XOR | `05_physical_signoff.md` |

## 3. Executed regressions (all PASS)

| Run | Seeds | Result | Log |
|---|---|---|---|
| existing suite RTL | 1–5 | 8/8 each | `stage_runs/existing_rtl_seed*.log` |
| existing suite GL | 1–3 | 8/8 each | `stage_runs/existing_gl_seed*.log` |
| audit suite RTL | 1–3 | 9/9 each | `stage_runs/audit_rtl_seed*.xml` |
| audit suite GL | 1–2 | 9/9 each | `stage_runs/audit_gl_seed*.xml` |
| mutation check | seed 1 | 6/6 killed | `stage_runs/mutants.summary` |
| PE formal + mutant | — | proved / mutant fails | `stage_runs/sby.log` |
| RTL ≡ netlist step + base + mutant | — | proved / proved / mutant fails | `stage_runs/{step,base}.log` |
| co-sim unit delay | 9101–9104 × 1M cycles | 0 mismatches (in total 629 accumulator wraps, 736 async resets, 362,075 scan-shift cycles) | `stage_runs/repro_dynamic.summary` |
| co-sim SDF | 9201 × 200k × {max_ss_n40C, min_ff_n40C, nom_tt} | 0 mismatches | same |
| SDF cocotb | 77 × {max_ss_n40C, min_ff_n40C} | 8/8 | `stage_runs/sdf_cocotb_*.log` |
| branch suite (`test.py` + new `test_arith.py`), CI-style | default | RTL 17/17, GL 17/17 | `stage_runs/branch_run_{no,yes}.log` |
| scripted end-to-end (`run_pre_tapeout_audit.sh`) | fixed | 35 PASS, 1 WARN, 0 FAIL | `logs/20261011-105948/`, `results/results.json` |
| CI on HEAD (GitHub) | CI default | gds ✓ precheck ✓ gl_test 8/8 ✓ docs ✓ test ✓ | run 38113024258 |

Seeds: cocotb `COCOTB_RANDOM_SEED` / `AUDIT_SEED` as listed, confirmed by "Seeding Python random module with N" in
the logs.

## 4. Coverage

There's no coverage tool, so coverage comes from how the tests are built plus counters in the logs:

| Goal | Achieved | How |
|---|---|---|
| All 256 operand pairs per PE instance | 4 × 256 = 1,024 / 1,024 | t01 asserts the per-lane set size |
| Both 16-bit boundaries, both directions | yes | t02 asserts the model value at each boundary |
| Every register address written incl. reserved 7 | yes | co-sim write counters (A0, A1, B0, B1, CTRL, ROWEN, RSEL, r7 all > 0) |
| Every ROWEN mask | 4/4 | t06, `test.py` |
| Every RSEL lane 0–15, every byte, ID bytes, bit 6 | yes | t06 |
| Scan: length, capture of every field, load + compute | yes | `test.py::test_scan_chain` (RTL + GL), co-sim scan bursts |
| Reset idle / during activity / strobe across reset | yes | t05, t09, co-sim (async resets at random times) |
| Clock-gate edge counts per row, test-mode forcing | yes | `test.py::test_row_enable_and_clock_gating` (RTL + GL ICG output net) |
| Code/toggle coverage | **NOT RUN** | no tool |

## 5. Limitations (what is not proven)

1. **Timing checks are not evaluated in simulation.** Icarus ignores `$setuphold`, so the SDF sims check
   function with real delays but not flop setup/hold. STA is the timing signoff.
2. **No SMT solver:** no bounded cover traces, no counterexample traces from sby. The PDR proof itself is
   complete.
3. **Equivalence models clocks as always-on.** The proof compares next-state functions of matched flops with
   the ICGs as identical blackboxes on both sides. Soundness relies on (a) the ICG GATE inputs being proven equal,
   (b) the PE only changing when step/clear/scan_en is high (proven in `formal/`), and (c) scan_en ⇒ test_mode
   (RTL). Gated-clock timing (glitch-free enable) is covered by the ICG cell plus the STA gating checks
   (`04` §4), not by the equivalence.
4. **Equivalence base case assumes `uio_in[5]`=0 during reset.** With scan_en asserted during reset the scan
   shift has priority, by design.
5. **TT harness, pads, mux, the real demo-board host and the 50 MHz clock source aren't modelled.** The
   official specs (66 MHz max input, 33 MHz max output, ≤ 10 ns clock insertion delay) are taken as given.
6. **Manufacturing defects** can't be covered pre-silicon; the scan chain (96 flops) is the bench tool for that.
7. **Power** is an estimate: vector-based from simulation VCDs (`11_power_clock_gating.md`), core of this tile only, not silicon.
