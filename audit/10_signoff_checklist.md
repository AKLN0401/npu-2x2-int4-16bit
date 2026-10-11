# 10 — Signoff checklist

Revision `ce832bb` (gds run 38113024258). Status: PASS, FAIL, BLOCKED, NOT RUN, NOT APPLICABLE, OPEN (needs owner
action). Machine-readable subset: `results/results.json`.

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Correct design identified (npu1x1, not the 6×2 parent) | PASS | `01` §1 |
| 2 | Spec intent "16 INT4 accumulators" vs 4 × 16-bit | **OPEN** | R-01, owner to confirm |
| 3 | Baseline recorded (commit, clean tree, artifacts) | PASS | `08` §1, A1 |
| 4 | Verilator lint `-Wall` | PASS | B1, 0 warnings |
| 5 | Existing cocotb suite RTL (5 seeds) / GL (3 seeds) | PASS | B2, `stage_runs/` |
| 6 | Independent reference model + exhaustive 16×16 per PE | PASS | B3 t01 |
| 7 | Exact overflow boundaries, wrap both directions | PASS | t02 |
| 8 | Alternating/random long runs, zero operands, clear/restart | PASS | t03, t04 |
| 9 | Reset idle / during activity / first op after reset | PASS | t05 |
| 10 | Lane isolation, read port, ROWEN | PASS | t06 |
| 11 | Matrix product vs reference (incl. K = 511, tiled 4×4) | PASS | t07 |
| 12 | Valid/ready, backpressure, pipeline | NOT APPLICABLE | no such protocol; strobe protocol tested instead |
| 13 | Mutation check (suite can fail) | PASS | B4, 6/6 |
| 14 | Formal PE proof (unbounded) + non-vacuity | PASS | B5 |
| 15 | Formal RTL ≡ post-PnR netlist (step + base) + non-vacuity | PASS | B6 |
| 16 | SDF-annotated GL at slow/fast corners | PASS | SDF cocotb 8/8 ×2 corners (this audit), 4 corners (2026-10-10) |
| 17 | Random RTL-vs-netlist co-sim | PASS | 4 × 1M + 3 × 200k SDF (this audit), 0 mismatches |
| 18 | Flop setup/hold checks in simulation | NOT RUN | Icarus ignores `$setuphold`; STA is the signoff |
| 19 | Functional/code coverage tool | NOT RUN | no tool; coverage by construction (`02` §4) |
| 20 | Synthesis: no latches/unmapped/black boxes, flop count = RTL | PASS | C10, `04` §1 |
| 21 | Clock definition = 50 MHz everywhere | PASS | `04` §3 |
| 22 | Timing exceptions justified | PASS | `04` §3 (2 false paths, DFT only) |
| 23 | Setup/hold at all 12 corners incl. ss_n40C | PASS | C5/C6: +5.70 / +0.162 ns |
| 24 | ICG gating checks, reset recovery/removal, unconstrained endpoints | PASS | B7, 4 corners |
| 25 | Max cap / fanout | PASS | C7 |
| 26 | Max slew | PASS with WARN | C8: 10 pins ≤ 0.84 ns (R-06, accepted) |
| 27 | Magic DRC | PASS | C1 = 0 |
| 28 | KLayout DRC (FEOL/BEOL/offgrid) | PASS | precheck |
| 29 | Netgen LVS | PASS | C2, "Circuits match uniquely" |
| 30 | Antenna | PASS | C4 |
| 31 | Routing DRC | PASS | C3 |
| 32 | Power grid / IR (block level) | PASS | C11 (vectorless) |
| 33 | TT precheck 15/15 | PASS | C12 |
| 34 | CI gds/precheck/gl_test/docs/test green on HEAD | PASS | run 38113024258 + docs/test runs |
| 35 | CI artifact = local signoff (netlist hash, metrics, GDS XOR) | PASS | C13, C14 |
| 36 | Tile size / die area | PASS | 161 × 111.52 µm |
| 37 | Template/workflow compliance | PASS | `06` |
| 38 | TTSKY26d PDK/flow/version match | PASS | `09` S1–S5 |
| 39 | Datasheet docs check | PASS | C15 |
| 40 | Host-protocol documentation complete | PASS on branch / OPEN on `main` | R-02/R-03/R-04, branch `audit/host-protocol-docs` |
| 41 | Power estimate | PASS (estimate only) | `11`: vector-based, 191–308 µW at tt, all pins annotated |
| 42 | Clock-gating saving quantified | PASS (estimate) | `11`: 45–59% saved (≈ 0.25–0.27 mW at tt), 3 corners, unit-delay + SDF VCD |
| 43 | Live shuttle page read (cutoff time, extra fields) | BLOCKED | JS page not readable here → owner checks |
| 44 | Project submitted to TTSKY26d | **OPEN** | not in `tinytapeout-sky-26d/projects` |
| 45 | Silicon-only behaviour (TT mux, pads, real host) | NOT APPLICABLE pre-silicon | AS-5 |
