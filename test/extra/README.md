# Extra pre-submission checks (archived)

Harnesses for the checks run on 2026-10-10 against the tapeout netlist (2×2 array, 16-bit accumulators, 50 MHz).
They are not part of the CI tests in `test/`. The scripts expect the original working layout: repo mounted at
`/work` by `tools/run.sh`, PnR run in `runs/wokwi/`, and the generated files in `runs/cosim/` and `runs/sdf/`
(gitignored), so copy them back there to rerun.

- `cosim/`: lock-step random co-simulation, RTL vs. post-PnR netlist, all outputs compared 4-state every cycle.
  `run.sh <rtl.v> <seed> <cycles>` (unit delay; `rtl.v` = `src/project.v` with the module renamed to `rtl_top`),
  `run_sdf.sh <corner> <seed> <cycles>` (SDF delays, 50 MHz). Results (2026-10-10): 20 seeds × 1M cycles unit delay,
  0 mismatches; 3 corners × 5 seeds × 400k cycles with SDF, 0 mismatches.
- `sdf/`: the cocotb tests of `test/` on the netlist with SDF back-annotation, `make CORNER=<corner>`. Inputs are
  generated: `patch_lib.py` (drives the `*_delayed` nets of `sky130_fd_sc_hd.v`, since Icarus ignores
  `$setuphold`) and `sanitize.py` (renames the escaped ICG / gated-clock instances that Icarus' SDF reader can't
  resolve). `test.py.diff` / `tb.v.diff` are the changes from the copies in `test/`. Icarus does not evaluate
  timing checks, so STA remains the timing signoff.
