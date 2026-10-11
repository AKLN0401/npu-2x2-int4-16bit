# 08 — Final release manifest

## 1. Source revision under signoff

| Item | Value |
|---|---|
| Repository | https://github.com/AKLN0401/npu-2x2-int4-16bit (local `~/tinytapeout/npu1x1`) |
| Branch / commit | `main` @ **`ce832bbafac3472bc7360173b35ae52156fc60fa`** (= `origin/main`, working tree clean) |
| Top module / parameters | `tt_um_akln0401_npu`, ROWS 2, COLS 2, ACC_W 16 (defaults, no overrides) |
| Signed-off build | GitHub Actions gds run **38113024258** (2026-10-11T04:53Z), artifact `tt_submission` |
| Local reference build | `npu1x1/runs/wokwi` (2026-10-10 22:04), identical netlist/metrics/geometry |
| Audit branch (not merged, not pushed) | `audit/host-protocol-docs` @ `7b70bc6` (worktree `~/tinytapeout/wt/npu1x1-audit`): `699b9e5` docs host rules, `7b70bc6` test/test_arith.py. Doesn't touch `src/`, `info.yaml` or config |

### Source hashes (sha256, at `ce832bb`)

    202c0717c22a6031b30cbee6aac0e5766f169a6dd3d72cf65d58d2688cec2a26  src/project.v
    0efbd091844c299209d79c3f344226902fc1e5229f0476d8e89220478acbf44b  src/npu_array.v
    cb5f67a1bf86e2be56000711dce6307869ac4a0efb0f15ab68a3aabffb9c1715  src/npu_pe.v
    09b6599b2bb6967c4e7fab2beb0190ea132cb5a211cadbd7fd266e8bdb077033  src/dft/clk_gate.v
    335380b85144f6e985366574e8f57ef012085b8e1ef6dc598c8d1c16113c2745  src/config.json
    59d71586a922344e42a1e7a036e375098644484580b89d41a6ac01f661078e7b  src/base.sdc
    05aa801c3e049db57a1dc02081bb83858a034e08a69f33800d0f3496fc3906c8  info.yaml
    0bb6814582632725d6d7aa01e3c11910b492d05942fe7a9c7baadaa99b6ae8df  docs/info.md
    c7fbe61d356455fae9e5f2a60aabe36f03b140dc199b215fe81aebb6b860878a  test/test.py
    402c3a00071406045d2807c441e1d9125e1b06ce0e8545f3e80476a147bf4bb4  test/Makefile
    e9e3c651e90331bf78a3e8fa3a51c095dc3fce19714d6b115a3f53ca9439aa34  test/tb.v

## 2. Artifacts (sha256)

| Artifact | CI run 38113024258 `tt_submission` | Local `runs/wokwi/final` |
|---|---|---|
| `tt_um_akln0401_npu.gds` | `0b7413fefb84c97fb4c0c35d84b933d330b0b586aab0a31ed85fe46d7b157c61` | `19e1a05a9b8dd53c640a0c8dd693e400138d4d1fd53fad53e2f696b0ccb1a7b4`: geometry identical (KLayout XOR 0/34 layers); bytes differ (metadata) |
| post-PnR netlist (`.v` / `.pnl.v`) | `d6f17c20d5446035c01e9e92d27109ce27eb64cab1fefc935cb051fbd1feddef` | **same** |
| LEF | `cda5a5a42b3e81ada3b224855b2ea310f943b8245230f3aa8a220729385556b0` | **same** |
| OAS | `c7c582626e61919e61b56e5f3d05215b69bf6ea239e553a48868aeb48b875f32` | — |
| SPEF max/nom/min | `074387f7…`, `a48e0555…`, `17b0f46f…` | — |
| `commit_id.json` | commit `ce832bb…`, workflow URL of run 38113024258 | placeholder (local) |
| `pdk.json` | LibreLane 3.0.14, sky130A, open_pdks 8afc8346… | same |
| `metrics.json` | 371 keys | 371 keys, all equal |

Full hash list: `logs/evidence/manifest_raw.txt`.

## 3. Tool versions

| Tool | Version | Used by |
|---|---|---|
| LibreLane | 3.0.14 (image `ghcr.io/librelane/librelane@sha256:23fc800d…`) | flow (CI: `pip install librelane==3.0.14`) |
| tt-support-tools | `01d5d2814fa9dd61e9d211e0b235a4a592a9316a` | harden, precheck, docs |
| tt-gds-action | tag `ttsky26d` → `395eedb3eeec3c2f4961c3b04ff2cf87f5525636` | CI |
| PDK | sky130A, open_pdks `8afc8346a57fe1ab7934ba5a6056ea8b43078e71` (= shuttle `librelane.txt`) | all |
| Yosys | 0.62 (`7326bb7d`) | flow synthesis, audit equivalence |
| OpenROAD / OpenSTA | `dcf36133` / 2.7.0 | flow PnR + STA, audit STA |
| Magic / Netgen / KLayout | 8.3.623 / 1.5.316 / 0.30.7 | DRC / LVS / XOR |
| Verilator | 5.044 (flow) / 5.020 (audit lint) | lint |
| Icarus Verilog | 12.0 (tools image) | sims |
| cocotb | 2.1.0 (`test/requirements.txt`) | sims |
| SymbiYosys | LibreLane bundle, engine `abc pdr` | PE proof |
| tools image | `tt-riscv-npu-tools` `778d139a9580…` (Ubuntu 24.04) | sims, lint |

## 4. Regressions and seeds

See `02_verification_plan.md` §3. Scripted end-to-end run: `logs/20261011-105948/`, `results/results.json`
(35 PASS, 1 WARN = max-slew, 0 FAIL, 0 BLOCKED, 0 NOT_RUN, exit 0).
Seeds: existing suite 1–5 (RTL), 1–3 (GL); audit suite 1–3 (RTL), 1–2 (GL); co-sim 9101–9104 (1M cycles),
9201 (SDF, 3 corners, 200k), 4242 (scripted, 200k); SDF cocotb 77.

## 5. Audit harness hashes (sha256, `pre_tapeout_audit/`)

    244bee9ae464cca56b4b27855b0097b077c29a9278346661eb5b7a8c5a0346cc  run_pre_tapeout_audit.sh
    0c7e2ef6756bf550c2208a1b30456641ebc1cfec7aaa3751f8f308dd571942a8  tests/audit_arith.py
    7c94f357db893b5d8b7c582ffae1452e3d97c2624705c536e8923f4b8b5b2493  formal/pe.sby
    1fae099c41a1e4529775c1a81bbda0404adc4bbbcb280b70e1081e95ab046d97  formal/pe_props.sv
    e595e4cc20d4dbbf2671360faac9c9f6080af31f59bf11f42c7a4cda4695cc37  equiv/run_equiv.sh
    2061899cadce7c04e03723eff86b7fde453724887579a9f2250cd042898a29c7  equiv/gen_induction.py
    3be729630b4a140851945780bd0f1b8eb41674fba3e8af4edd6ea8a096ed7d4e  equiv/canon_names.py
    c457c70cc6bf14f7cf0ff5d611e99c1a18f6e205fea04afb2b02afce4422ddf0  sta/icg.tcl

## 6. Working-tree state at the end of the audit

- `npu1x1` (`main`): clean, unchanged (verified with `git status` after the scripted run).
- Worktree `~/tinytapeout/wt/npu1x1-audit`: branch `audit/host-protocol-docs`, 2 local commits, **not pushed**.
  The gitignored helper copies `tools/.cocotb2` are only in the worktree.
- Generated audit data: `npu1x1/runs/audit/`, `npu1x1/runs/audit_run/` (gitignored `runs/`); `runs/wokwi` only
  read, not modified.
- Parent repo `~/tinytapeout`: `.git/info/exclude` gained `/pre_tapeout_audit/` (local, untracked). Its existing
  uncommitted `MEMORY.md` / `docs/overview.html` edits were left untouched.

## 7. Rule for any further change

After any commit that's to be submitted: push → wait for the gds action → `./run_pre_tapeout_audit.sh` must exit 0
with C13 (CI netlist = local signoff netlist) and C14 (XOR 0). If `src/`, `info.yaml` or `src/config.json` change,
the whole signoff (sections 03–05) has to be redone on the new build.
