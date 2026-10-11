# 04 — Synthesis and timing

Source of all numbers: `npu1x1/runs/wokwi` (local LibreLane 3.0.14 run). It is **identical** to GitHub CI run
38113024258 on HEAD `ce832bb`: same post-PnR netlist sha256 `d6f17c20…`, all 371 metrics equal
(`05_physical_signoff.md` §2).

## 1. Synthesis (Yosys 0.62 via LibreLane, `SYNTH_STRATEGY AREA 0`)

| Item | Value | Evidence |
|---|---|---|
| Top / sources | `tt_um_akln0401_npu`, the 4 files of `info.yaml` | `resolved.json`, CI `tt_submission/src` = HEAD |
| Synthesized cells / area | 1,014 cells, 11,217 µm² | `06-yosys-synthesis/reports/stat.json` |
| Flops | 96 `dfxtp_2` + 2 `dfrtp_2` = 98 = RTL inventory | stat.json, netlist |
| ICGs | 2 `dlclkp_1` (instance names `i_array.g_row[i].i_cg.icg` kept) | netlist |
| Latches (inferred) / unmapped / synth check errors | 0 / 0 / 0 | `design__inferred_latch__count`, `design__instance_unmapped__count`, `synthesis__check_error__count` |
| Lint (flow, Verilator 5.044) | 0 errors, 4 warnings | all 4 = `PINMISSING` VPWR/VGND/VPB/VNB on the RTL ICG instance (power pins, connected by PnR); benign |
| Yosys warnings | 1: ABC "Detected 2 multi-output cells (fa_1)" | informational |
| Largest synthesized cell types | xnor2 99, dfxtp 96, nand2 86, o21a 63, nor2 60, mux2 56, and3 52, xor2 48 | consistent with 4 × (4×4 multiplier + 16-bit adder) + muxes |
| Black boxes / undriven / multi-driven | none (gate model check in `equiv/gate.ys`, `check` clean) | |
| Required logic kept | all 64 accumulator bits, all 32 interface bits, both ICGs present; formal equivalence proves nothing was lost or changed | `05` §6 |

The excluded cells (`EXTRA_EXCLUDED_CELLS`: delay cells, `buf_1`, 4-high stacks `or4/nor4/a2111o`) are a
documented carry-over from the parent design. They don't affect function.

## 2. Post-PnR cell categories (`final/metrics.json`)

| Class | Count | Area µm² |
|---|---|---|
| sequential | 98 | 2,094.5 |
| multi-input combinational | 891 | 9,197.6 |
| timing-repair buffers | 321 | 1,686.6 |
| clock buffers / inverters | 20 / 2 | 500.5 / 7.5 |
| clock-gate cells | 2 | 35.0 |
| inverters | 23 | 86.3 |
| antenna diodes | 13 | 32.5 |
| tap / fill (physical only) | 225 / 922 | 281.5 / 2,571.2 |
| **std-cell total** | 1,595 | **13,922.1** |

Die 17,954.7 µm², core 16,493.3 µm², utilization **84.4%**. Wire length 32,795 µm, 9,600 vias.

## 3. Constraints review (`src/base.sdc`, final `final/sdc/tt_um_akln0401_npu.sdc`)

| Constraint | Value | Assessment |
|---|---|---|
| Clock | `clk`, 20 ns (50 MHz) = `CLOCK_PERIOD` = `info.yaml clock_hz` = `CLK_HZ` in `test/test.py` | consistent in all 3 places |
| TT base SDC | `read_sdc $::env(SCRIPTS_DIR)/base.sdc` first: default IO delays 20%, input transition, load, 5% OCV derate | kept, as the TT template |
| Clock uncertainty | 2.5 ns rise→fall, 2 ns fall→rise (TT mux duty-cycle) | copied from the TT template; conservative |
| `rst_n` input delay | 1.5 ns | TT template value |
| `set_false_path -from uio_in[4..6]` | test_mode, scan_en, scan_in | **justified**: static in mission mode, changed only with clock slow/stopped (documented in `docs/info.md`). Consequence: the scan_in → first flop and test_mode → ICG GATE paths are untimed, so scan must be shifted slowly on the bench. The flop-to-flop shift paths themselves stay timed |
| `set_false_path -to uio_out[7]` | scan_out | justified: only read in test mode at a slow shift clock; TT outputs are rated 33 MHz anyway |
| Host interface IO | default 20% IO delay on `ui_in`, `uio_in[3:0]`, `uo_out` | the interface is asynchronous by design (strobe synchronizer + ≥ 4-clock hold). These delays just keep the paths short; they don't represent a real interface timing. Acceptable |
| `set_propagated_clock` | all clocks | correct for post-CTS STA |
| Multicycle paths | none | — |

No exception hides a real synchronous path. **No new exceptions were added in this audit.**

## 4. Timing results (routed, RCX parasitics, 12 corners, 5% OCV derate)

`57-openroad-stapostpnr/summary.rpt`:

| Corner | Setup WS (ns) | Hold WS (ns) | Max-slew vio |
|---|---|---|---|
| nom_tt_025C_1v80 | 12.74 | 0.404 | 0 |
| nom_ss_100C_1v60 | 7.79 | 0.502 | 0 |
| nom_ss_n40C_1v60 | 5.86 | 0.343 | 4 |
| nom_ff_n40C_1v95 | 13.79 | 0.166 | 0 |
| min_* (4 corners) | ≥ 6.01 | ≥ 0.162 | 0 |
| max_tt_025C_1v80 | 12.68 | 0.410 | 0 |
| max_ss_100C_1v60 | 7.66 | 0.510 | 0 |
| **max_ss_n40C_1v60** | **5.70** | 0.350 | 10 |
| max_ff_n40C_1v95 | 13.75 | 0.169 | 0 |
| **Overall** | **+5.70**, TNS 0, 0 violators | **+0.162** (min_ff_n40C), TNS 0 | 10 |

- Worst setup path (max_ss_n40C): `a_reg[0]` (`_1875_`) → `acc[31]` (`_1819_`, MSB of acc[0][1]). That's the
  multiply + 16-bit carry path, the expected critical path. Arrival 15.40 ns, required 21.10 ns.
  Next: `b_reg[3]` → `acc[47]`, `b_reg[3]` → `acc[15]`.
- Worst hold: `acc[32]` → itself at min_ff_n40C (+0.162 ns), an accumulator feedback loop on the gated clock.
- The temperature-inversion corner ss_n40C_1v60 (slower cold at 1.60 V) is **in the flow's corner list and
  repaired**, so it isn't just reported (`LIB` + `STA_CORNERS` in `src/config.json`). The TT default flow
  doesn't include it, so this check goes beyond the default.
- Clock skew: worst setup skew 0.474 ns, hold skew −0.429 ns (metrics); 0.878 ns setup skew in the
  max_ss_n40C report. That includes the ICG insertion delay on the gated branches, and timing closes with it.
- Unconstrained endpoints / no-clock / loops: none (`check_setup` in `checks.rpt`, and the audit's own OpenSTA
  runs at 4 corners).
- Unannotated parasitics: 20 drivers. All are tie cells, the CTS load cells (`clkload0/1`) and the unused inputs
  `ena`, `uio_in[7]`. Expected.

### Clock-gating and reset checks (audit OpenSTA run on final netlist + SPEF, `sta/icg.tcl`)

| Corner (SPEF) | ICG GATE setup slack | ICG GATE hold slack | reset removal | reset recovery |
|---|---|---|---|---|
| ss_n40C_1v60 (max) | 13.65 / 13.95 | 3.50 / 2.89 | 0.35 | 18.50 |
| ss_100C_1v60 (max) | 13.91 / 14.21 | 3.15 / 2.63 | 0.51 | 18.46 |
| tt_025C_1v80 (nom) | 17.00 / 17.14 | 1.52 / 1.24 | 0.86 | 18.38 |
| ff_n40C_1v95 (min) | 18.05 / 18.14 | 0.87 / 0.70 | 0.99 | 18.34 |

(row 0 / row 1, ns, all MET). Reset recovery/removal is checked against the 1.5 ns `rst_n` input delay. The real
reset release is asynchronous and goes through the 2-flop synchronizer (`rst_sync[0]` D tied 1), so removal
margin at the pin isn't a functional requirement.

## 5. Electrical

- Max capacitance 0, max fanout 0 violations.
- **Max slew: 10 pins at max_ss_n40C (4 at nom_ss_n40C), worst 0.838 ns vs the 0.75 ns flow limit.** They sit on two
  fanout nets of the RSEL read-mux select (`_0906_`, `_0909_`, `fanout58/63/66`), not on clock or critical
  paths. The liberty tables go to 1.5 ns, and STA delays already include the slow slew (setup slack there is large).
  Accepted in the project log 2026-10-10. Residual risk: low (R-06).
- IR drop (vectorless): worst 73 µV. `VSRC_LOC_FILES` isn't set, so this is a block-level estimate only; the chip
  PDN is TT's.

## 6. Power (estimate, not signoff)

OpenSTA vectorless power, default switching activity, no VCD/SAIF:

| Corner | Total | Sequential | Combinational | Clock |
|---|---|---|---|---|
| nom_tt_025C_1v80 | 0.484 mW | 40.7% | 4.2% | 55.0% |
| max_ff_n40C_1v95 (= `power__total` in metrics) | 0.568 mW | | | |
| max_ss_n40C_1v60 | 0.372 mW | | | |

Leakage ≈ 21 nW (ff corner). These numbers don't reflect the real workload, and they can't show the clock-gating saving.
**Superseded by the vector-based analysis in `11_power_clock_gating.md`**: 191–308 µW at tt depending on workload,
and clock gating saves 45–59% (≈ 0.25–0.27 mW at tt).

## 7. Frequency

Rated 50 MHz. Setup slack at the worst corner (5.70 ns on 20 ns) suggests about 70 MHz reg-to-reg. That's above the
TT input rating (66 MHz) and doesn't matter: the design is limited by the host bus. 50 MHz is the TT default and is
well inside "at least 50 MHz" (TT FAQ).
