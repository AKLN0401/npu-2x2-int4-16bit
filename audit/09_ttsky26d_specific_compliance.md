# 09 — TTSKY26d-specific compliance

Checked 2026-10-11 against the live official repositories (GitHub API) and the tinytapeout.com website source.
Copies of the fetched files: `logs/evidence/official/`.

## 1. Authoritative sources and revisions

| Source | Revision inspected | Role |
|---|---|---|
| Production shuttle repo `TinyTapeout/tinytapeout-sky-26d` | `main` @ `ebc34ed30b` (2026-10-11T12:19Z), 69 projects | **authoritative** for integration: projects are being added here now |
| Staging repo `TinyTapeout/tinytapeout-sky-26d-staging` | `main` @ `4afb9a37cc` (2026-09-17) | pre-launch copy; only `tt_um_factory_test` |
| Template `TinyTapeout/ttsky-verilog-template` | `main` @ `68c3fd3f3e` (2026-09-30, "chore: update tags for TTSKY26d" at `97c933a34b`) | project template |
| GDS action `TinyTapeout/tt-gds-action@ttsky26d` | tag → commit `395eedb3ee` (2026-09-18) | flow used by the project's CI |
| `TinyTapeout/tt-support-tools` | `main` @ `01d5d2814f` (used by the action, unpinned) / `ff75e344cd` (shuttle submodule) | harden / precheck / docs tools |
| Website `TinyTapeout/tinytapeout_www` `content/chips/_index.md` | `89f5025406` (2026-10-08, PR #315 "update shuttle dates") | dates |
| app.tinytapeout.com/shuttles/ttsky26d | **not readable** (JavaScript app; fetch returned no content) | live submission page → see §6 |

### Staging vs production (differences that could affect the project)

| Item | Production | Staging | Effect on project |
|---|---|---|---|
| `config.yaml` (id, pdk, end_date, top macro) | `ttsky26d`, `sky130A`, `2026-11-30`, `openframe_project_wrapper` | identical | none |
| `.github/config/librelane.txt` | `LIBRELANE_TAG=3.0.0.dev40`, `SKY130_PDK_VERSION=8afc8346…` | identical | none |
| Submodules `tt` / `tt-multiplexer` | `ff75e344cd` / `8fbe6cd3eb` | identical | none |
| `BUILDING.md`, `mux_overrides.yaml`, workflow set | identical | identical | none |
| `projects/` | 69 projects; **`tt_um_akln0401_npu` absent** | factory test only; absent | project not submitted yet |

Conclusion: production is authoritative, and staging adds nothing that affects this project.
`BUILDING.md` names SKY130 PDK `6d4d1178…`, but the machine-read config (`librelane.txt`, used by the
workflows) is `8afc8346…`. The text in BUILDING.md is outdated, and the config file decides.

## 2. Requirements and evidence

| # | Requirement | Official source | Project evidence | Status | Action |
|---|---|---|---|---|---|
| S1 | Shuttle id `ttsky26d`, PDK **sky130A** | prod `config.yaml` (`id`, `pdk`) | `info.yaml`/template is the ttsky template; CI `pdk: sky130A` in `gds.yaml`; `pdk.json` PDK sky130A | PASS | — |
| S2 | PDK version **open_pdks 8afc8346a57f…** | prod `.github/config/librelane.txt` | `final/pdk.json` (CI and local) `PDK_VERSION 8afc8346…` | PASS | — |
| S3 | Project flow = `tt-gds-action@ttsky26d` → LibreLane **3.0.14** via `tt_tool.py --harden` | `tt-gds-action` `action.yml` @ `395eedb3ee` | `.github/workflows/gds.yaml` uses `@ttsky26d`, identical to template; `pdk.json FLOW_VERSION 3.0.14` | PASS | — |
| S4 | Shuttle integration flow LibreLane 3.0.0.dev40 (TT-side), project GDS taken as macro | prod `librelane.txt`, `BUILDING.md` | n/a for the project; LEF/GDS pass the precheck the shuttle reruns (`project_submission.yaml` → precheck on changed OAS) | PASS (precheck 15/15) | — |
| S5 | tt-support-tools version | action checks out `main` (unpinned); shuttle pins `ff75e344cd` | CI used `01d5d281` = `ff75e344` + 2 commits (`project.py` no-remote fix, `tt_fpga.py`); neither changes hardening for a repo with a remote | PASS (no effect) | rerun CI before submitting if tt-support-tools `main` moves |
| S6 | Template workflows and tags for TTSKY26d | template @ `68c3fd3f3e` | `gds.yaml`, `test.yaml`, `docs.yaml` byte-identical to template; `fpga.yaml` uses `@ttsky26d` | PASS | — |
| S7 | Tile sizes 1x1 … 8x2 (sky130A); 1x1 = 161.00 × 111.52 µm | `tt/tech/sky130A/tile_sizes.yaml`; template `info.yaml` comment | `tiles: "1x1"`; DEF `DIEAREA (0 0) (161000 111520)` | PASS | — |
| S8 | Pins: 8 in, 8 out, 8 bidir + clk + rst_n + ena; `uio_oe` 1 = output | template `src/project.v`, `tb.v`; FAQ | 24 pins used as in `info.yaml` pinout; `uio_oe = 0x80` | PASS | — |
| S9 | Clock ≤ 66 MHz input, ~50 MHz expected; insertion delay ≤ 10 ns | tinytapeout.com/specs/clock | 50 MHz; interface async (synchronized strobe); TT duty-cycle uncertainty in SDC | PASS | — |
| S10 | Output ≤ 33 MHz (SKY130 rating) | tinytapeout.com/specs/gpio | outputs change at host rate | PASS | — |
| S11 | Reset `rst_n` active low, handled like a normal input | FAQ, specs/clock | 2-flop synchronizer, async assert | PASS | host: clock running during reset (AS-3) |
| S12 | Top-module name, sources, metadata, docs | `tt-support-tools` `project_info.py`, `project_checks.py` | `--check-docs` passes; CI harden passes port/source checks | PASS | — |
| S13 | GDS action must pass to submit | FAQ | run 38113024258 on HEAD: gds ✓, precheck ✓, gl_test ✓, viewer ✓; docs ✓, test ✓ | PASS | must be re-green on the commit that's finally submitted |
| S14 | Precheck (shuttle reruns it) | `tt-gds-action/precheck`, prod `project_submission.yaml` | 15/15 in CI and locally | PASS | — |
| S15 | Final artifact = `tt_submission` of the gds run for the submitted commit | `action.yml` "Prepare tt_submission artifact"; FAQ "create a new submission" | artifact of run 38113024258: `commit_id.json` = `ce832bb…`, GDS geometry = local signoff run (XOR 0) | PASS for `ce832bb` | if the doc branch is merged, the new commit needs its own green run, and that commit is what you submit |
| S16 | Submission deadline | prod `config.yaml` `end_date: 2026-11-30`; website table "Closes 2026-11-30", shuttle CI-2612 | today 2026-10-11, 50 days left | PASS (date) | **time of day / time zone not published in the sources read** → confirm on the live app page |
| S17 | Manufacturing milestones | website table: "Chips expected 2027-05-12", "Estimated shipping date 2027-06-09" | matches the brief | INFO | — |
| S18 | Project registered on the shuttle | prod `projects/` | **absent** | **OPEN** | submit via app.tinytapeout.com (user action, needs approval) |
| S19 | No unsupported macros / analog / special cells | `project_info.py` (analog_pins), TT docs | 0 macros, 0 analog pins; one std ICG cell from sky130_fd_sc_hd | PASS | — |
| S20 | Live shuttle page instructions / restrictions | app.tinytapeout.com/shuttles/ttsky26d | **could not be read** (JavaScript app) | **UNRESOLVED** | open the page in a browser before submitting: price per tile, any extra fields, exact cutoff time |

## 3. CI coverage vs. this audit

| Check | TT CI | This audit |
|---|---|---|
| Verilator lint | flow step (results not gating) | `-Wall` at 4 parameter sets, 0 warnings |
| RTL sim | `test` workflow, 8 tests, 1 seed | 8 tests × 5 seeds + 9 independent tests × 3 seeds + mutation check |
| GL sim | `gl_test`, unit delay, 8 tests | + 9 tests × 2 seeds; SDF at 2 corners; RTL-vs-netlist random co-sim |
| Synthesis checks | flow checkers | + cell inventory vs RTL |
| STA | flow, 12 corners (project config adds ss_n40C) | + ICG gating and reset checks at 4 corners, unconstrained-endpoint check |
| DRC/LVS/antenna | flow (Magic DRC, Netgen LVS) + precheck (Magic + KLayout) | evidence review |
| Formal | none | PE proof (unbounded), RTL ≡ netlist (induction) |
| Artifact integrity | none | CI ↔ local netlist hash, metrics, GDS XOR |

## 4. Configuration compatibility

`src/config.json` = template + user-section additions only (`06` #17). Every addition is a LibreLane 3.0.14 option.
The CI run used this exact config and succeeded, which shows the config is compatible with the official flow. The
custom `FALLBACK_SDC_FILE` (`src/base.sdc`) first reads the TT base SDC.

## 5. Final-GDS generation and same-revision check

1. Source of truth: the **`tt_submission` artifact** of the gds run on the commit you submit (`action.yml`).
2. For `ce832bb`: sources in the artifact = repo; netlist = local signoff netlist; GDS geometry = local signoff GDS
   (XOR 0). The local signoff evidence therefore applies to the artifact TT will take.
3. If the branch `audit/host-protocol-docs` is merged (it changes `docs/info.md` and tests only, **no** `src/`,
   `info.yaml` or config change), the GDS should come out the same. Still, confirm that the new run's netlist hash
   equals `d6f17c20…`. `run_pre_tapeout_audit.sh` does that automatically (check C13/C14) once the run exists.

## 6. Submission process (user actions, not done by this audit)

1. (Optional) merge `audit/host-protocol-docs` → push → wait for gds/test/docs green → rerun
   `run_pre_tapeout_audit.sh` (C13/C14 must PASS against the new HEAD).
2. Open app.tinytapeout.com, select TTSKY26d, create the submission from `AKLN0401/npu-2x2-int4-16bit`, and choose
   the green gds run of the final commit.
3. After submitting: check that `projects/tt_um_akln0401_npu` appears in `TinyTapeout/tinytapeout-sky-26d` and that
   its precheck passes there.
4. Any later change needs a new submission (FAQ) before 2026-11-30.
