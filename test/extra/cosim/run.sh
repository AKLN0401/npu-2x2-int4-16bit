#!/bin/bash
# usage: run.sh <rtl file> <seed> <cycles>
set -e
L=$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog
out=sim_$(basename $1 .v).vvp
[ $out -nt $1 ] && [ $out -nt cosim_tb.v ] || iverilog -g2012 -o $out -DSIM -DFUNCTIONAL -DUSE_POWER_PINS -DUNIT_DELAY=#1 -I/work/src \
  $L/primitives.v $L/sky130_fd_sc_hd.v /work/runs/wokwi/final/pnl/tt_um_akln0401_npu.pnl.v \
  $1 /work/src/npu_array.v /work/src/npu_pe.v /work/src/dft/clk_gate.v cosim_tb.v 2>/dev/null
vvp -n $out +seed=$2 +cycles=$3 | grep -E "COSIM|MISMATCH" | head -4
