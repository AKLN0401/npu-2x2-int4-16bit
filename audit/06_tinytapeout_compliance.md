# 06 — Tiny Tapeout integration compliance (generic template requirements)

Shuttle-specific items (TTSKY26d repo, staging vs production, dates, flow pins) are in
`09_ttsky26d_specific_compliance.md`. Sources: official template `TinyTapeout/ttsky-verilog-template` @ `68c3fd3f3e`
(2026-09-30), `tt-support-tools` @ `01d5d281` (`project_info.py`, `project.py`, `project_checks.py`),
tinytapeout.com/specs/{clock,gpio}, tinytapeout.com/faq (fetched 2026-10-11).

| # | Requirement | Official source | Project evidence | Result | Action |
|---|---|---|---|---|---|
| 1 | Top module starts with `tt_um_`, unique (GitHub user) | template `info.yaml` comment; `project.py` | `tt_um_akln0401_npu`; GitHub user AKLN0401 | PASS | — |
| 2 | Top module exists in exactly one listed source | `project.py:273–287` | defined only in `src/project.v` | PASS (gds action green) | — |
| 3 | Fixed TT port list (`ui_in`, `uo_out`, `uio_in`, `uio_out`, `uio_oe`, `ena`, `clk`, `rst_n`, widths) | `project.py::check_ports` | `src/project.v:47–56`; CI harden passes port check | PASS | — |
| 4 | Every source in `info.yaml source_files`, in `src/`, one per line | template `info.yaml` | 4 files, all in `src/`; = `PROJECT_SOURCES` in `test/Makefile` | PASS | — |
| 5 | `yaml_version` = 6, title/author/description non-empty, valid `tiles`, `clock_hz` | `project_info.py` | yaml_version 6; fields set; tiles 1x1; clock_hz 50000000 | PASS | `discord` empty (optional) |
| 6 | Pinout section: keep all pins, descriptive names | template `info.yaml` | all 24 entries present and named | PASS | — |
| 7 | `docs/info.md` "How it works" / "How to test" filled | `project_checks.py::check_info_md` | both sections filled; `tt_tool.py --check-docs` passes | PASS | — |
| 8 | Datasheet images < 512 KB each, < 1 MB total | `docs/info.md` template comment | no images in `docs/` (info.md has none) | PASS | `docs/overview.html` (~2 MB, embedded images) is not referenced by the datasheet and ships in `tt_submission`. Not covered by the rule; low risk (R-08) |
| 9 | Drive every output, tie unused to 0 | template / TT guides | `uio_out[6:0]` = 0, `uio_oe` = 0x80 constant, all `uo_out` driven | PASS | — |
| 10 | `uio_oe` semantics: 1 = output | template `tb.v` comment | only `uio[7]` (scan_out) is an output | PASS | host must configure uio[7] as RP input (doc fix, R-02) |
| 11 | Clock: one input clock `clk`, ≤ 66 MHz max input, ~50 MHz expected max | specs/clock, FAQ "at least 50MHz" | 50 MHz, single clock | PASS | — |
| 12 | Clock/reset are "handled like any other input pins" (async to the design's expectations) | specs/clock | `rst_n` synchronized (async assert, sync release); strobe synchronized | PASS | — |
| 13 | Outputs ≤ 33 MHz rated | specs/gpio | data outputs change at host-write rate; scan_out at shift rate (bench, slow) | PASS | keep scan shift ≤ a few MHz (docs say slow) |
| 14 | IO voltage 3.3 V on the demo board, inputs not 5 V tolerant | specs/gpio | no external hardware | N/A | — |
| 15 | No FPGA primitives / simulation-only constructs in synthesis | template / flow lint | only a sky130 ICG cell (legal std cell in the PDK); `SIM` model is under `ifdef SIM`, which synthesis doesn't define | PASS | — |
| 16 | Custom cells/macros allowed only if hardened and in the flow | TT docs | no macros (`design__instance__count__macros` 0) | PASS | — |
| 17 | `config.json`: only change the documented user section | `src/config.json` comments ("DO NOT CHANGE ANYTHING BELOW THIS POINT") | changes only above the line (hold margins, corners, SDC, repair, exclusions); below-the-line block equals the template | PASS | — |
| 18 | Testbench runs with the template `test` workflow (cocotb 2.1, `check_results`) | template `.github/workflows/test.yaml` | workflow byte-identical to template; `test/requirements.txt` = template; CI test job green | PASS | — |
| 19 | GL test runs on the gds action's netlist | `tt-gds-action/gl_test` | CI gl_test 8/8 | PASS | — |
| 20 | GDS action must pass for submission | FAQ "A project can't be submitted to a shuttle if its GDS action is failing" | run 38113024258 success on HEAD | PASS | rerun after any push |
| 21 | Analog pins | `project_info.py` (`analog_pins` 0–6) | none (key absent → 0) | N/A | — |
| 22 | Resubmit after any change ("create a new submission") | FAQ | not yet submitted | OPEN | submit at app.tinytapeout.com (09 §6) |
| 23 | `ena` | template comment "goes high when design is selected" | unused | PASS (allowed) | — |
| 24 | Reset polarity active-low | FAQ "nreset (low to reset)" | `rst_n` active low | PASS | — |
| 25 | Tile area | `tile_sizes.yaml` 1x1 = 161 × 111.52 µm | DEF DIEAREA identical; util 84.4% | PASS | — |

No incompatibility with the template was found.
