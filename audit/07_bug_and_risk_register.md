# 07 — Bug and risk register

Severity: CRITICAL (chip won't work / can't be submitted), HIGH (likely bench failure or wrong spec),
MEDIUM (bench risk with a documented workaround), LOW (minor), INFO.
**No functional, arithmetic, timing, DRC, LVS or integration defect was found in the RTL or the layout.**

| ID | Sev. | Finding | Evidence | Root cause | Fix / status | Regression | Residual risk |
|---|---|---|---|---|---|---|---|
| R-01 | HIGH (spec, owner decision) | Brief says "2×2 NPU with 16 INT4 accumulators"; the design has **4 accumulators × 16 bit** (int4 operands) | `src/project.v` `NPE = ROWS*COLS`, `ACC_W = 16`; ID byte 2 = 0x10; `docs/info.md` | wording ("16" = accumulator width) or a real spec mismatch | **OPEN: needs your confirmation.** If 16 accumulators were intended, the design doesn't meet it, and a 4×4 array doesn't fit 1×1 (2×3 already failed placement) | — | none if wording only |
| R-02 | MEDIUM | Datasheet said address/data and strobe "at the same time is fine". With a MicroPython host, `ui_in` and `uio_in` are separate writes µs apart, so strobe-first ordering captures stale data/address 2–3 clk after the strobe | `src/project.v:106–118` (data sampled when `wr`, 2–3 clk after strobe rise); `docs/info.md` §Write protocol | documentation | **FIXED on branch** `audit/host-protocol-docs` (commit `699b9e5`): data first, then address + strobe; pseudocode reordered | t03/t08 + `test.py::test_write_protocol` (protocol); doc-only | low once followed |
| R-03 | LOW | A strobe that is high when `rst_n` is released performs **one write** after reset (edge detector sees 0→1) | `tests/audit_arith.py::t09` (RTL + GL) | `wr_sync` reset to 0 | **FIXED (doc)** on the branch: "keep uio[3] low during and at reset release". RTL left as is (changing it = interface change, not needed) | t09 pins the behaviour | low |
| R-04 | MEDIUM | `uio[4]` test_mode / `uio[5]` scan_en floating or high in mission mode would force clocks on / scan-shift every clock and corrupt state | RTL `test_mode = uio_in[4]`, `scan_en = uio_in[5] & test_mode`; no on-chip pull | DFT pins are plain inputs; pad pull state not documented in the TT specs read (UNRESOLVED) | **FIXED (doc)** on the branch: host must drive `uio[6:0]`, keep `uio[4:5]` low, `uio[7]` as input | — | low if the host configures the bidir pins (TT SDK per-project uio direction setting) |
| R-05 | LOW | Synchronous clears need the clock running during reset | `st` and accumulators cleared via `!rstn` on clock edges | design choice (only the synchronizer is async) | documented in `01` (AS-3); TT RP2 SDK clocks the project during reset | RTL/GL reset tests | low |
| R-06 | LOW | 10 max-slew pins at max_ss_n40C, 0.838 ns vs 0.75 ns flow limit (RSEL read-mux fanout nets) | `checks.rpt`, metrics | resizer left two fanout nets slow at the cold-ss corner | accepted 2026-10-10 (timing includes the slew; lib tables to 1.5 ns; large slack) | STA | low |
| R-07 | LOW | Scan-in pin path and test_mode→ICG path are false-pathed (untimed) | `src/base.sdc` | static DFT pins | justified exception; bench: shift with slow/stopped clock (documented) | — | low (bench procedure) |
| R-08 | LOW | `docs/overview.html` (~2 MB, embedded images) is in `docs/` and ships in `tt_submission` | `tt_submission/docs/overview.html` | portfolio page kept next to the datasheet | none needed: the datasheet uses `info.md` only, and the docs action passes; move it if TT asks | docs action | low |
| R-09 | LOW | `tt-gds-action` checks out tt-support-tools `main` unpinned; a later push can be built with newer tools than this signoff | `action.yml` `tools-ref: main` | TT action design | rerun `run_pre_tapeout_audit.sh` after each push (C13/C14 compare the new artifact with the signed-off netlist/GDS) | C13/C14 | low |
| R-10 | INFO | Flow power is vectorless; clock-gating saving not quantified by the flow | `04` §6 | no VCD-based power in flow | **DONE**: vector-based power in `11_power_clock_gating.md`: gating saves 45–59% (≈ 0.25–0.27 mW at tt). Bench suggestion: compare test_mode on/off with the same workload (ROWEN 11 vs 01 shows only ≈ 17 µW) | `power/run_power.sh` | n/a |
| R-11 | INFO | Live shuttle page (app.tinytapeout.com) unreadable by the tools here; exact cutoff time unknown | `09` S20 | JS app | user checks the page before submitting | — | process |
| R-12 | INFO | Project not yet submitted to TTSKY26d | prod `projects/` | — | user action (`09` §6) | — | process |
| R-13 | INFO | Existing `test.py` checks wrap at only one point; a saturating adder would pass it | mutation m3 survives `test.py` alone (only t02 kills it) | test gap | **FIXED on branch** (commit `7b70bc6`): independent suite added as `test/test_arith.py` (runs in CI RTL + GL) | 17/17 RTL and GL | none |
| R-14 | INFO | Local hardening writes placeholder commit metadata | `runs/wokwi/final/commit_id.json` | `tools/harden.sh` wrapper | none: submission uses the CI artifact, which is identical | C13 | none |

## Items deliberately not changed

- RTL: no change is justified. Changing the reset behaviour of the strobe (R-03) or adding pull-ups/pull-downs
  (R-04) would alter the external interface and require a full re-harden for a bench-procedure issue.
- Constraints: no exception added or relaxed.
- No checks removed and no warnings suppressed.
