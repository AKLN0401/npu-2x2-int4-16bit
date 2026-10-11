#!/usr/bin/env bash
# Vector-based power matrix (post-PnR netlist, unit-delay GL VCD -> OpenSTA + routed SPEF).
# Usage (from <npu1x1>/runs/audit/power): run_power.sh <npu1x1 dir>
set -eu
NPU=$1; D=$NPU/runs/audit/power; cd "$D"
PDK="$(ls -d "$HOME"/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/)"
CYC=20000
# name : plusargs
SCEN="${SCEN:-idle:+work=0 max_r11:+gap=2+rowen=3 max_r01:+gap=2+rowen=1 slow_r11:+gap=94+rowen=3}"
"$NPU/tools/run.sh" bash -c 'L=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog; iverilog -g2012 -o ptb.vvp -DFUNCTIONAL -DUSE_POWER_PINS -DUNIT_DELAY=#1 $L/primitives.v $L/sky130_fd_sc_hd.v /work/runs/wokwi/final/pnl/tt_um_akln0401_npu.pnl.v power_tb.v 2>/dev/null'
[ -n "${KEEP_SIMLOG:-}" ] || : > sim.log
for s in $SCEN; do n=${s%%:*}; a=${s#*:}; a=${a//+/ +}
  for tm in 0 1; do
    "$NPU/tools/run.sh" bash -c "vvp -n ptb.vvp $a +tm=$tm +cycles=$CYC +vcd=${n}_tm$tm.vcd | grep POWER_TB" | sed "s/^/$n /" >> sim.log
  done
done
cat sim.log
for s in $SCEN; do n=${s%%:*}
  for tm in 0 1; do
    for c in "tt_025C_1v80 nom" "ff_n40C_1v95 min" "ss_n40C_1v60 max"; do set -- $c
      docker run --rm --userns=keep-id -v "$NPU:/work:z" -v "$PDK:/pdk:ro,z" -w /work/runs/audit/power ghcr.io/librelane/librelane:3.0.14 \
        bash -c "VCD=${n}_tm$tm.vcd LIB=sky130_fd_sc_hd__$1.lib SPEF=$2 sta -no_init -exit power.tcl" > "pwr_${n}_tm${tm}_$1.log" 2>&1
    done
  done
done
