#!/usr/bin/env bash
# Audit suite at fixed seeds, RTL and GL (post-PnR netlist). Runs in the tools container.
set -u
S=$1; cd "$S"
export PYTHONPATH=/work/tools/.cocotb2 PATH=/work/tools/.cocotb2/bin:$PATH
NL=/work/runs/wokwi/final/pnl/tt_um_akln0401_npu.pnl.v
for cfg in rtl:1 rtl:2 rtl:3 gl:1 gl:2; do
  k=${cfg%:*}; s=${cfg#*:}
  rm -rf sim_build results.xml
  if [ $k = gl ]; then AUDIT_SEED=$s make GATES=yes NETLIST=$NL > audit_${k}_seed$s.log 2>&1
  else AUDIT_SEED=$s make > audit_${k}_seed$s.log 2>&1; fi
  cp results.xml audit_${k}_seed$s.xml 2>/dev/null
  python -m cocotb_tools.check_results results.xml >/dev/null 2>&1 && r=PASS || r=FAIL
  echo "audit $k seed=$s $r $(grep -o 'TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]*' audit_${k}_seed$s.log | tail -1)"
done
rm -rf sim_build results.xml
