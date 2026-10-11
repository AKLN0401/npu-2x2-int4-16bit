# 11 — Vector-based power and the clock-gating saving

Added 2026-10-11 after the main audit. Replaces the vectorless estimate as the power reference. It is still an
estimate: a pre-silicon model of this tile's 1.8 V core only. It's not a measurement.

## 1. Method

| Step | Detail |
|---|---|
| Netlist | post-PnR `runs/wokwi/final/pnl` (= CI artifact, sha256 `d6f17c20…`) |
| Stimulus | `power/power_tb.v`: pin-level host writes at the datasheet protocol (strobe 4 clk, gap ≥ 2 clk), matmul stream A0 → B0 → CTRL.step with fixed-seed random operands; 50 MHz; measured window 20,000 clocks (400 µs) after reset/setup |
| Gating baseline | the **same stimulus** with `test_mode` = 1: both ICGs forced on, so every PE flop and the gated clock tree toggle every cycle while the PEs still hold through their data enable. Both runs end with identical accumulator values, which confirms the same function and the same traffic. This is what the design would burn without the clock gates |
| Activity | Icarus VCD of every net (unit delay); cross-check with SDF delays (nom_tt) so glitches are included |
| Power | OpenSTA 2.7.0 (LibreLane 3.0.14 image): routed netlist + SPEF (nom/min/max per corner) + final SDC + `read_vcd`; **4,546 / 4,546 pins annotated** from the VCD (unit-delay runs) |
| Script | `power/run_power.sh` (results: `logs/evidence/power/`, `power_results.json`) |

## 2. Results

Typical corner tt_025C_1v80 (nom SPEF):

| Workload | Gated (normal) | Gating defeated | **Saved by clock gating** |
|---|---|---|---|
| Idle: clock running, no host traffic | 191.3 µW | 461.5 µW | **270.3 µW (58.6%)** |
| Max bus rate, ROWEN=11 (952 steps / 400 µs, 1 step / 21 clk) | 276.7 µW | 533.6 µW | **256.9 µW (48.2%)** |
| Max bus rate, ROWEN=01 (row 1 off) | 260.0 µW | 523.6 µW | **263.6 µW (50.3%)** |
| Slower host, 1 write / 100 clk (67 steps / 400 µs) | 197.4 µW | 466.7 µW | **269.3 µW (57.7%)** |
| Max bus rate, ROWEN=11, **SDF-annotated VCD** (glitches included) | 308.2 µW | 561.7 µW | **253.5 µW (45.1%)** |

Other corners (unit-delay VCD, same workloads):

| Workload | ff_n40C_1v95: gated / forced / saved | ss_n40C_1v60: gated / forced / saved |
|---|---|---|
| Idle | 220.6 / 532.6 / **312.0 µW (58.6%)** | 146.9 / 354.6 / **207.7 µW (58.6%)** |
| Max rate, ROWEN=11 | 316.8 / 613.4 / **296.6 µW (48.4%)** | 213.0 / 410.6 / **197.5 µW (48.1%)** |
| Max rate, ROWEN=01 | 298.0 / 602.3 / **304.3 µW (50.5%)** | 200.2 / 402.8 / **202.6 µW (50.3%)** |
| Slow host | 227.5 / 538.4 / **310.9 µW (57.7%)** | 151.7 / 358.7 / **207.0 µW (57.7%)** |

Where the saving comes from (tt, max rate, ROWEN=11): the clock group falls from 266.0 to 130.3 µW (the gated
branches of the clock tree stop), and the sequential group from 200.9 to 79.4 µW (the clock pins of the 64
accumulator flops). Combinational power is identical (66.9 vs 66.7 µW), because the data activity is the same.
Leakage is ≈ 8 nW at tt, negligible.

## 3. What it means

- Clock gating **roughly halves this tile's power**: it saves 45–59% (≈ 0.25–0.27 mW at tt, 0.30–0.31 mW at the
  fast corner, 0.20–0.21 mW at the slow corner). The saving is largest when the array is idle, which is most of
  the time with a MicroPython host (the "slow host" row is close to idle).
- With gating on, the NPU's own power hardly depends on the workload (191 µW idle → 277 µW at the maximum
  protocol rate). What remains is the always-on part: the root clock tree and the 34 ungated interface/sync flops.
- Disabling a row (ROWEN=01) saves only a further 17 µW at max rate here, because steps are rare compared to clock
  cycles (1 per 21 clk): each row's clock is already off ≈ 95% of the time.
- At 1.8 V the saving is ≈ 0.14–0.17 mA of core current. Whether that's visible on the bench depends on the
  demo board's core-current measurement and on the rest of the TT chip; that's **not verified**. The bench
  procedure in `docs/info.md` (ROWEN 11 vs 01) only exposes the small row-disable difference. **Toggling
  test_mode (uio[4]) with the same workload shows the full gating saving.** It's safe as long as uio[5] (scan_en)
  stays low, and the datasheet could suggest it as the measurement.

## 4. Limits

- Core power of this tile only: no TT mux, IO pads, chip clock distribution or other projects.
- Unit-delay activity omits glitches (the SDF run shows +28 µW combinational at max rate); the saving is barely
  affected (253.5 vs 256.9 µW).
- The SDF-run VCD comes from the harness netlist with 12 renamed instances (ICGs + gated clock buffers). Their 26
  pins are filled in by OpenSTA's activity propagation instead of the VCD; the clock-group totals agree with the
  fully annotated run within 3.5 µW.
- The liberty power models and the RCX parasitics are the only physics here. Silicon can differ (process,
  temperature, supply), so the absolute numbers are estimates and the gated/forced ratio is the more robust result.
