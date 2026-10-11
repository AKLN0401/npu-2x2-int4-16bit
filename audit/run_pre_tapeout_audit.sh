#!/usr/bin/env bash
# Pre-tapeout audit of the TTSKY26d submission tt_um_akln0401_npu (npu1x1).
#
# Usage: audit/run_pre_tapeout_audit.sh [path/to/npu1x1]   (default: the repo this audit/ folder is in)
#
# Re-runs every check that can be automated in this environment and writes
#   results/results.json   one record per check: id, status, mandatory, evidence
#   logs/<timestamp>/      raw logs
# Status values: PASS, FAIL, BLOCKED (tool/input missing), NOT_RUN (optional input absent).
# Exit code: 1 if any mandatory check FAILs, 2 if none fail but a mandatory one is BLOCKED/NOT_RUN, else 0.
#
# Nothing in the project is modified: work happens in <npu1x1>/runs/audit_run (gitignored), the
# original runs/wokwi is only read. test/gate_level_netlist.v (gitignored copy) is refreshed from
# runs/wokwi/final/pnl, and test/results.xml / test/sim_build are regenerated, as `make` does anyway.
#
# Needs: podman/docker images tt-riscv-npu-tools (tools/build-image.sh) and
# ghcr.io/librelane/librelane:3.0.14, the sky130 PDK in ~/.ciel (open_pdks 8afc8346), cocotb 2.1
# in <npu1x1>/tools/.cocotb2 (pip install --target tools/.cocotb2 cocotb==2.1.0), optional `gh`.
set -u
AUD="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${1:-}" ]; then NPU="$(cd "$1" && pwd)"; elif [ -f "$AUD/../info.yaml" ]; then NPU="$(cd "$AUD/.." && pwd)"; else NPU="$(cd "$AUD/../npu1x1" && pwd)"; fi
TS=$(date +%Y%m%d-%H%M%S)
LOG="$AUD/logs/$TS"; mkdir -p "$LOG" "$AUD/results"
RES="$LOG/results.tsv"; : > "$RES"
WORK="$NPU/runs/audit_run"; rm -rf "$WORK"; mkdir -p "$WORK"
LL_IMG=ghcr.io/librelane/librelane:3.0.14
PDK="$(ls -d "$HOME"/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/ 2>/dev/null || true)"
NL="$NPU/runs/wokwi/final/pnl/tt_um_akln0401_npu.pnl.v"
COCO='export PYTHONPATH=/work/tools/.cocotb2 PATH=/work/tools/.cocotb2/bin:$PATH'

record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RES"; printf '%-28s %-8s %s\n' "$1" "$2" "$4"; }
have_img() { docker image inspect "$1" >/dev/null 2>&1; }
tools() { ( cd "$1" && shift && "$NPU/tools/run.sh" "$@" ); }          # tools image, cwd mapped
ll() { local d=$1; shift; docker run --rm --userns=keep-id -v "$NPU:/work:z" ${PDK:+-v "$PDK:/pdk:ro,z"} \
        -w "/work/${d#$NPU/}" "$LL_IMG" bash -c "$*"; }
xml_ok() { python3 - "$1" <<'EOF'
import sys, xml.etree.ElementTree as E
try: r = E.parse(sys.argv[1]).getroot()
except Exception: sys.exit(1)
t = list(r.iter("testcase")); bad = [c for c in t if any(x.tag in ("failure", "error") for x in c)]
print(f"{len(t) - len(bad)}/{len(t)}"); sys.exit(0 if t and not bad else 1)
EOF
}

echo "pre-tapeout audit $TS  project=$NPU"
# ---------------------------------------------------------------- A: baseline
cd "$NPU"
HEAD=$(git rev-parse HEAD); DIRTY=$(git status --porcelain | wc -l)
record A1_git_baseline INFO n "HEAD $HEAD, $DIRTY uncommitted paths, branch $(git rev-parse --abbrev-ref HEAD)"
[ -f "$NL" ] && record A2_final_netlist PASS y "$(sha256sum "$NL" | cut -c1-16)… runs/wokwi/final/pnl" \
             || record A2_final_netlist BLOCKED y "runs/wokwi/final missing: run tools/harden.sh"
have_img tt-riscv-npu-tools || record A3_tools_image BLOCKED y "image tt-riscv-npu-tools missing (tools/build-image.sh)"
have_img "$LL_IMG"          || record A4_librelane_image BLOCKED y "$LL_IMG missing"
[ -n "$PDK" ]               || record A5_pdk BLOCKED y "sky130 open_pdks 8afc8346 not in ~/.ciel"
[ -d "$NPU/tools/.cocotb2" ] || record A6_cocotb2 BLOCKED y "tools/.cocotb2 missing (cocotb 2.1, as in test/requirements.txt)"

# ---------------------------------------------------------------- B: lint
if tools "$NPU" verilator --lint-only -Wall -Wno-DECLFILENAME -DSIM --top-module tt_um_akln0401_npu \
     src/project.v src/npu_array.v src/npu_pe.v src/dft/clk_gate.v > "$LOG/lint.log" 2>&1; then
  record B1_verilator_lint PASS y "verilator -Wall: $(grep -c '%Warning' "$LOG/lint.log") warnings"
else record B1_verilator_lint FAIL y "see lint.log"; fi

# ---------------------------------------------------------------- B: existing cocotb suite (CI flow)
cp "$NL" "$NPU/test/gate_level_netlist.v" 2>/dev/null
for cfg in rtl:1 rtl:2 gl:1; do
  k=${cfg%:*}; s=${cfg#*:}; g=no; [ $k = gl ] && g=yes
  tools "$NPU/test" bash -c "$COCO; rm -rf sim_build results.xml; make GATES=$g COCOTB_RANDOM_SEED=$s" > "$LOG/existing_${k}_$s.log" 2>&1
  cp "$NPU/test/results.xml" "$LOG/existing_${k}_$s.xml" 2>/dev/null
  n=$(xml_ok "$LOG/existing_${k}_$s.xml") && record "B2_existing_${k}_seed$s" PASS y "test/test.py $n" \
                                          || record "B2_existing_${k}_seed$s" FAIL y "test/test.py ${n:-no results}"
done
rm -rf "$NPU/test/sim_build" "$NPU/test/results.xml"

# ---------------------------------------------------------------- B: independent arithmetic suite
S="$WORK/sim"; mkdir -p "$S"; cp "$AUD"/tests/{audit_arith.py,Makefile,mutants.sh,audit_regress.sh} "$S/"
tools "$S" /work/runs/audit_run/sim/audit_regress.sh /work/runs/audit_run/sim > "$LOG/audit_regress.summary" 2>&1
for f in "$S"/audit_*_seed*.xml; do
  b=$(basename "$f" .xml); cp "$f" "$S/$b.log" "$LOG/" 2>/dev/null
  n=$(xml_ok "$f") && record "B3_$b" PASS y "audit_arith.py $n" || record "B3_$b" FAIL y "audit_arith.py ${n:-?}"
done
tools "$S" /work/runs/audit_run/sim/mutants.sh /work/runs/audit_run/sim > "$LOG/mutants.summary" 2>&1
k=$(grep -c ' KILLED' "$LOG/mutants.summary"); t=$(grep -c '^m[0-9]' "$LOG/mutants.summary")
[ "$t" -gt 0 ] && [ "$k" = "$t" ] && record B4_mutation_check PASS y "$k/$t RTL mutants killed" \
                                  || record B4_mutation_check FAIL y "$k/$t killed, see mutants.summary"

# ---------------------------------------------------------------- B: formal (LibreLane image: sby + abc, no SMT solvers)
F="$WORK/formal"; mkdir -p "$F"; cp "$AUD"/formal/{pe.sby,pe_props.sv,npu_pe_mut.v} "$F/"
sed -i 's|\.\./\.\./npu1x1/src/npu_pe.v|/work/src/npu_pe.v|; s|\.\./\.\./src/npu_pe.v|/work/src/npu_pe.v|' "$F/pe.sby"
ll "$F" 'sby -f pe.sby' > "$LOG/formal_pe.log" 2>&1
grep -q 'pe_prove.*DONE (PASS' "$LOG/formal_pe.log" && record B5_formal_pe_prove PASS y "abc pdr: npu_pe next state, all acc states x 256 operand pairs" \
                                                   || record B5_formal_pe_prove FAIL y "see formal_pe.log"
grep -q 'pe_mutant.*returned FAIL' "$LOG/formal_pe.log" && record B5_formal_pe_nonvacuity PASS y "zero-extension mutant fails the proof" \
                                                       || record B5_formal_pe_nonvacuity FAIL y "mutant not caught"

# ---------------------------------------------------------------- B: RTL vs post-PnR netlist equivalence
E="$WORK/equiv"; mkdir -p "$E/mut"
cp "$AUD"/equiv/{icg_bb.v,gold.ys,gate.ys,canon_names.py,name_icg_gate.py,gen_induction.py,run_equiv.sh} "$E/"
ll "$E" './run_equiv.sh' > "$LOG/equiv.log" 2>&1
for p in step base; do grep -q "equiv_$p PASS" "$LOG/equiv.log" && record "B6_equiv_$p" PASS y "yosys sat induction ($p), 98 state bits + outputs + ICG GATE" \
                                                               || record "B6_equiv_$p" FAIL y "see equiv.log"; done
cp "$E"/{icg_bb.v,gold.ys,gate.ys,canon_names.py,name_icg_gate.py,gen_induction.py,run_equiv.sh} "$E/mut/"
awk 'BEGIN{d=0} /sky130_fd_sc_hd__nand2_[0-9] /&&!d{sub(/nand2_/,"nor2_");d=1} {print}' "$NPU/runs/wokwi/final/nl/tt_um_akln0401_npu.nl.v" > "$E/mut/nl_mut.v"
sed -i 's|^NL=.*|NL=/work/runs/audit_run/equiv/mut/nl_mut.v|' "$E/mut/run_equiv.sh"
sed -i 's|/work/runs/wokwi/final/nl/tt_um_akln0401_npu.nl.v|/work/runs/audit_run/equiv/mut/nl_mut.v|' "$E/mut/gate.ys"
ll "$E/mut" './run_equiv.sh' > "$LOG/equiv_mutant.log" 2>&1
grep -q 'equiv_step FAIL' "$LOG/equiv_mutant.log" && record B6_equiv_nonvacuity PASS y "1 NAND2->NOR2 netlist mutant is caught" \
                                                  || record B6_equiv_nonvacuity FAIL y "mutant not caught"

# ---------------------------------------------------------------- B: STA spot checks (clock gating, reset)
T="$WORK/sta"; mkdir -p "$T"; cp "$AUD/sta/icg.tcl" "$T/"
for c in "ss_n40C_1v60 max" "ss_100C_1v60 max" "tt_025C_1v80 nom" "ff_n40C_1v95 min"; do
  set -- $c
  ll "$T" "LIB=sky130_fd_sc_hd__$1.lib SPEF=$2 sta -no_init -exit icg.tcl" > "$LOG/sta_icg_$1.log" 2>&1
  met=$(grep -c '(MET)' "$LOG/sta_icg_$1.log"); vio=$(grep -c 'VIOLATED' "$LOG/sta_icg_$1.log")
  unc=$(sed -n '/unconstrained endpoints/,/--- end/p' "$LOG/sta_icg_$1.log" | grep -v -- '---' | grep -c .)
  [ "$met" -ge 6 ] && [ "$vio" = 0 ] && [ "$unc" = 0 ] && record "B7_sta_icg_reset_$1" PASS y "$met checks MET, 0 unconstrained" \
                                                     || record "B7_sta_icg_reset_$1" FAIL y "MET $met, VIOLATED $vio, unconstrained lines $unc"
done

# ---------------------------------------------------------------- C: signoff metrics of the final run
python3 - "$NPU/runs/wokwi/final/metrics.json" >> "$RES" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
def row(i, ok, mand, ev, warn=False):
    print(f"{i}\t{'PASS' if ok else ('WARN' if warn else 'FAIL')}\t{mand}\t{ev}")
g = m.get
row("C1_magic_drc", g("magic__drc_error__count") == 0, "y", f"magic__drc_error__count={g('magic__drc_error__count')}")
row("C2_lvs", g("design__lvs_error__count") == 0, "y", f"design__lvs_error__count={g('design__lvs_error__count')}")
row("C3_route_drc", g("route__drc_errors") == 0, "y", f"route__drc_errors={g('route__drc_errors')}")
row("C4_antenna", g("route__antenna_violation__count") == 0 and g("antenna__violating__nets") == 0, "y", f"antenna nets={g('antenna__violating__nets')}")
row("C5_setup_all_corners", g("timing__setup__ws") >= 0 and g("timing__setup__tns") == 0, "y", f"setup ws={g('timing__setup__ws'):.3f} ns")
row("C6_hold_all_corners", g("timing__hold__ws") >= 0 and g("timing__hold__tns") == 0, "y", f"hold ws={g('timing__hold__ws'):.3f} ns")
row("C7_max_cap_fanout", g("design__max_cap_violation__count") == 0 and g("design__max_fanout_violation__count") == 0, "y", "max cap/fanout violations 0")
s = g("design__max_slew_violation__count")
row("C8_max_slew", s == 0, "n", f"{s} max-slew pins (accepted <= 0.84 ns vs 0.75 limit, lib table 1.5)", warn=(0 < s <= 10))
row("C9_utilization", g("design__instance__utilization") < 1, "y", f"util={g('design__instance__utilization'):.3f}")
row("C10_latch_unmapped", g("design__inferred_latch__count") == 0 and g("design__instance_unmapped__count") == 0 and g("synthesis__check_error__count") == 0, "y", "latches 0, unmapped 0, synth check errors 0")
row("C11_power_grid", g("design__power_grid_violation__count") == 0, "y", f"IR drop worst {g('ir__drop__worst')} V")
EOF
tail -n 11 "$RES" | while IFS=$'\t' read -r i s m e; do printf '%-28s %-8s %s\n' "$i" "$s" "$e"; done

# ---------------------------------------------------------------- C: precheck + CI provenance
PC="$NPU/runs/audit/ci_38113024258/precheck_reports/results.md"; [ -f "$PC" ] || PC="$NPU/runs/wokwi/precheck/reports/results.md"
if [ -f "$PC" ]; then n=$(grep -c '✅' "$PC"); b=$(grep -c '❌' "$PC")
  [ "$b" = 0 ] && record C12_tt_precheck PASS y "$n/$((n+b)) ($PC)" || record C12_tt_precheck FAIL y "$b failing ($PC)"
else record C12_tt_precheck NOT_RUN y "no precheck results: tools/precheck.sh runs/wokwi or the gds action"; fi
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  REPO=$(git -C "$NPU" remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')
  RUN=$(gh run list -R "$REPO" -w gds -c "$HEAD" -L 1 --json databaseId,conclusion -q '.[0]|"\(.databaseId) \(.conclusion)"' 2>/dev/null)
  if [ -n "$RUN" ]; then set -- $RUN; D="$WORK/ci_$1"; mkdir -p "$D"
    gh run download "$1" -R "$REPO" -n tt_submission -D "$D" >/dev/null 2>&1
    CINL="$D/tt_submission/tt_um_akln0401_npu.v"
    [ "$2" = success ] && cmp -s "$CINL" "$NL" && record C13_ci_gds_matches_local PASS y "gds run $1 on $HEAD: success, netlist identical" \
                       || record C13_ci_gds_matches_local FAIL y "gds run $1 conclusion=$2, netlist identical: $(cmp -s "$CINL" "$NL" && echo yes || echo no)"
    if [ -f "$D/tt_submission/tt_um_akln0401_npu.gds" ]; then
      cp "$D/tt_submission/tt_um_akln0401_npu.gds" "$WORK/ci.gds"; cp "$NPU/runs/wokwi/final/gds/tt_um_akln0401_npu.gds" "$WORK/local.gds"
      cat > "$WORK/xor.py" <<'EOF'
import klayout.db as db
a = db.Layout(); a.read("ci.gds"); b = db.Layout(); b.read("local.gds"); ta, tb = a.top_cell(), b.top_cell()
L = set((l.layer, l.datatype) for l in a.layer_infos()) | set((l.layer, l.datatype) for l in b.layer_infos())
d = 0
for ln, dt in sorted(L):
    ia, ib = a.find_layer(ln, dt), b.find_layer(ln, dt)
    ra = db.Region(ta.begin_shapes_rec(ia)) if ia is not None else db.Region()
    rb = db.Region(tb.begin_shapes_rec(ib)) if ib is not None else db.Region()
    d += not (ra ^ rb).is_empty()
print(f"XOR layers={len(L)} differing={d} top={ta.name}/{tb.name} bbox={ta.dbbox()}")
EOF
      x=$(ll "$WORK" 'python3 xor.py' 2>&1 | tail -1)
      echo "$x" | grep -q 'differing=0' && record C14_gds_xor_ci_vs_local PASS y "$x" || record C14_gds_xor_ci_vs_local FAIL y "$x"
    fi
  else record C13_ci_gds_matches_local NOT_RUN y "no gds workflow run for $HEAD (push, then rerun)"; fi
else record C13_ci_gds_matches_local BLOCKED y "gh CLI missing or not logged in"; fi

# ---------------------------------------------------------------- C: docs
if [ -x "$NPU/tools/.venv/bin/python" ] && [ -f "$NPU/tt/tt_tool.py" ]; then
  ( cd "$NPU" && tools/.venv/bin/python tt/tt_tool.py --project-dir "$NPU" --check-docs ) > "$LOG/docs.log" 2>&1 \
    && record C15_tt_check_docs PASS y "tt_tool.py --check-docs" || record C15_tt_check_docs FAIL y "see docs.log"
else record C15_tt_check_docs BLOCKED y "tt-support-tools (tt/) or tools/.venv missing"; fi

# ---------------------------------------------------------------- optional: earlier dynamic harnesses
if [ -x "$NPU/runs/cosim/run.sh" ] && [ -f "$NPU/runs/cosim/rtl_top.v" ]; then
  o=$(tools "$NPU/runs/cosim" ./run.sh rtl_top.v 4242 200000 2>&1 | tr '\n' ' ')
  echo "$o" | grep -q 'COSIM PASS' && record D1_cosim_unit_delay PASS n "seed 4242, 200k cycles: ${o:0:60}" || record D1_cosim_unit_delay FAIL n "$o"
else record D1_cosim_unit_delay NOT_RUN n "runs/cosim not present (copy test/extra/cosim, see test/extra/README.md)"; fi

# ---------------------------------------------------------------- summary
python3 - "$RES" "$AUD/results/results.json" "$TS" "$HEAD" <<'EOF'
import json, sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
recs = [dict(id=r[0], status=r[1], mandatory=r[2] == "y", evidence=r[3]) for r in rows]
out = dict(run=sys.argv[3], project_head=sys.argv[4], checks=recs,
           summary={s: sum(r["status"] == s for r in recs) for s in ("PASS", "FAIL", "WARN", "BLOCKED", "NOT_RUN", "INFO")})
json.dump(out, open(sys.argv[2], "w"), indent=1)
print("summary:", out["summary"])
fail = any(r["mandatory"] and r["status"] == "FAIL" for r in recs)
blk = any(r["mandatory"] and r["status"] in ("BLOCKED", "NOT_RUN") for r in recs)
sys.exit(1 if fail else 2 if blk else 0)
EOF
rc=$?; cp "$RES" "$AUD/results/results.tsv"; echo "results: $AUD/results/results.json  logs: $LOG  exit $rc"; exit $rc
