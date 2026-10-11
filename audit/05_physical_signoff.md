# 05 — Physical signoff

## 1. Flow identification (verified)

| Item | Value | Evidence |
|---|---|---|
| Flow | **LibreLane 3.0.14** (classic flow), driven by `tt-support-tools` `tt_tool.py --harden` | `final/pdk.json` `FLOW_VERSION`; `tt-gds-action@ttsky26d` `action.yml` (`librelane-version` default 3.0.14) |
| Not used | OpenLane 1, OpenLane 2 (`ghcr.io/efabless/openlane2:2.3.10` exists locally but isn't used by this project) | |
| PDK | `sky130A`, open_pdks **8afc8346a57fe1ab7934ba5a6056ea8b43078e71** | `final/pdk.json`; = `SKY130_PDK_VERSION` in TTSKY26d `.github/config/librelane.txt` |
| Std-cell library | `sky130_fd_sc_hd` | `LIB` in `src/config.json`, netlist |
| tt-support-tools | `01d5d281` ("Tiny Tapeout main 01d5d281") | `commit_id.json` (CI and local) |
| Floorplan | TT 1x1 block DEF `tt/tech/sky130A/def/tt_block_1x1_pg.def`, die 161 × 111.52 µm, met4 PDN stripes, no met5 | `tile_sizes.yaml`, final DEF `DIEAREA` |

Local runs use the same tool path as CI (`tools/harden.sh` wraps `tt_tool.py`). The **CI run is the
authoritative artifact**, and it's identical to the local one (§2).

## 2. Artifact provenance

| Check | Result | Evidence |
|---|---|---|
| CI `gds` workflow on HEAD `ce832bb` | success (gds, precheck, gl_test, viewer jobs) | run 38113024258, 2026-10-11T04:53Z |
| CI sources = HEAD | `src/*.v`, `config.json`, `base.sdc`, `info.yaml` byte-identical | `tt_submission` artifact vs checkout |
| CI `commit_id.json` | repo AKLN0401/npu-2x2-int4-16bit, commit `ce832bb…`, workflow URL | |
| CI netlist vs local | **identical** sha256 `d6f17c20…` | |
| CI metrics vs local | **371/371 equal** | `logs/evidence/ci_38113024258/metrics.json` vs `flow/metrics_local.json` |
| CI GDS vs local GDS | sha256 differs (timestamps) → KLayout XOR: **0 differing layers of 34**, same top cell, same bbox | `C14_gds_xor_ci_vs_local` |
| CI LEF vs local | identical sha256 `cda5a5a4…` | |
| Local run commit metadata | placeholder `000…0` (local wrapper) | not used for submission |

## 3. Stage-by-stage review (`runs/wokwi/<step>`)

| Stage | Result | Evidence |
|---|---|---|
| Lint (01–04) | 0 errors, 0 timing constructs, 4 benign warnings | metrics `design__lint_*` |
| Synthesis + checks (06–09) | 0 unmapped, 0 check errors, 0 latches; netlist assign statements checker passed | metrics |
| SDC check (10) | passed | |
| Floorplan, tap/endcap, PDN (13–21) | TT 1x1 template; power grid violations 0 (`30-checker-powergridviolations`) | metrics `design__power_grid_violation__count` 0 |
| Placement (24–34) | GPL-0302 warning "target density 0.60 too low": informational, the TT config fixes density | warning.log |
| CTS (35) | 20 clock buffers, 2 inverters; gated branches buffered after each ICG (`clkbuf_*_i_array.g_row[i]…`) | netlist |
| Post-CTS / post-GRT repair (37–45) | 321 repair buffers; `EST-0026 missing route to pin` only in the post-GRT repair steps 41/44, before detailed routing; **not in the final STA** | logs |
| Global route + antenna (39–43) | 13 antenna diodes; `GRT-0243 unable to repair antennas on net with diodes` (1 net) → final antenna check 0 | `48-openroad-checkantennas-1` |
| Detailed routing (46) | iterations 303 → 231 → 35 → 0 DRC; final **route DRC 0** | metrics `route__drc_errors__iter:*` |
| Disconnected pins (50–51) | 2 signal pins without connection: `ena`, `uio_in[7]` (unused inputs, by design); 0 critical | `full_disconnected_pins_table.txt` |
| Fill (54) | 922 fill cells | |
| RCX + STA post-PnR (56–57) | 12 corners, setup/hold met | `04_synthesis_and_timing.md` |
| IR drop (58) | 73 µV worst (vectorless, no VSRC_LOC) | |
| Stream-out Magic + KLayout (59–60) | GDS written by both | |
| **Magic DRC (64–65)** | **0** | `64-magic-drc/reports/drc.magic.rpt`, metric `magic__drc_error__count` 0 |
| SPICE extraction + **Netgen LVS (66–69)** | **"Circuits match uniquely"**, 0 errors / 0 unmatched devices, nets, pins | `68-netgen-lvs/reports/lvs.netgen.rpt` |
| Illegal overlap (67) | 0 | metric |
| Setup/hold/slew/cap checkers (70–73) | setup 0, hold 0, cap 0; slew 10 (reported, flow continues) | metrics |
| KLayout DRC in the flow | **skipped by the TT config** (`RUN_KLAYOUT_DRC 0`, in the "do not change" section) → covered by precheck | `klayout__drc_error__count not reported` |
| KLayout XOR in the flow | skipped by TT config (`RUN_KLAYOUT_XOR 0`) | |

## 4. TT precheck (the acceptance check run by the gds action)

CI precheck job on HEAD: **15/15 pass**: Magic DRC, KLayout FEOL, BEOL, offgrid, pin-label overlap, zero-area,
KLayout checks, pin check, boundary check, power-pin check, layer check, cell-name check, urpm/nwell, analog pin,
Verilog syntax. Local precheck (`tools/precheck.sh`) on the same GDS: 15/15 (`runs/wokwi/precheck/reports/results.md`).
Evidence: `logs/evidence/ci_38113024258/precheck_reports/`.

## 5. GL test in CI

`gl_test` job (template GL flow, post-PnR netlist with power pins, unit delay): 8/8 (`test_reset_and_id` …
`test_scan_chain`). `logs/evidence/ci_38113024258/results.xml`.

## 6. Formal equivalence RTL ≡ post-PnR netlist (added by this audit)

`equiv/run_equiv.sh` (yosys 0.62 `sat`, LibreLane image), checked through `run_pre_tapeout_audit.sh`:

- **Gold:** `src/*.v` (synthesis view: the `clk_gate` instantiates `dlclkp_1`), `proc; flatten; splitnets`.
  Register aliases renamed to the netlist's names, a pure rename (`canon_names.py`).
- **Gate:** `final/nl/tt_um_akln0401_npu.nl.v` with functional models read from the sky130 tt liberty (98 flops →
  96 `$_DFF_P_` + 2 `$_DFF_PN0_`, no undriven nets). `dlclkp_1` is the same blackbox on both sides. Its GATE
  input nets are named and compared.
- **Step proof:** all 98 flop outputs equal at t=1 (arbitrary values, all inputs free) ⇒ at t=2 all 98 next states,
  `uo_out`, `uio_out`, `uio_oe` and both ICG GATE inputs are equal. **PASS** (57k variables, 153k clauses, UNSAT).
- **Base proof:** from independent arbitrary initial states, with `rst_n`=0 and `uio_in[5]`=0 for 3 cycles, both
  designs reach identical state and outputs. **PASS.**
- **Non-vacuity:** the same flow on a netlist copy with one `nand2` changed to `nor2` → step proof FAILS (model found).
- Why `equiv_make/equiv_induct` wasn't used directly: it matches nets by name, and with RTL aliases
  (e.g. `auto` = `st[19]`) its induction proved 0 points even on unchanged logic. The explicit side-by-side
  induction above checks the same mathematical statement. (Debug history in `npu1x1/runs/audit/equiv/`.)
- Scope: functional equivalence with flops as unit delays and the ICG outputs as shared cut points. Why this is
  sound: `02_verification_plan.md` §5 item 3. Timing is covered by STA.

## 7. Not run / not applicable

| Item | Status | Reason |
|---|---|---|
| Flow KLayout DRC / XOR | NOT RUN in flow (TT config) | covered by precheck KLayout FEOL/BEOL/offgrid (pass) |
| Chip-level (tt_top) DRC/LVS with the mux | NOT APPLICABLE to the project | done by TT at shuttle integration (LibreLane 3.0.0.dev40, `tinytapeout-sky-26d`) |
| Density fill / sealring | NOT APPLICABLE | TT shuttle level (`sky130_density_fix` in the shuttle repo) |
| Static IR with real supply pins | NOT APPLICABLE | block-level; TT PDN |
| ERC beyond LVS (e.g. floating gates) | partially: LVS + precheck urpm/nwell + disconnected-pin report | no separate ERC tool in the flow |
