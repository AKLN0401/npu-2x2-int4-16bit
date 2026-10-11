#!/bin/bash
# usage: run_sdf.sh <corner> <seed> <cycles>   (50 MHz, netlist with SDF delays, patched timing models)
set -e
D=/work/runs/sdf
out=sim_sdf_$1.vvp
[ -f $out ] || iverilog -g2012 -gspecify -s cosim_tb -o $out -DSIM -DUSE_POWER_PINS -DHALF=10 -DSDF_FILE=\"$D/sdf_fixed/$1.sdf\" -I/work/src \
  $D/primitives.v $D/sky130_fd_sc_hd_sdf.v $D/gate_level_netlist.v \
  rtl_top.v /work/src/npu_array.v /work/src/npu_pe.v /work/src/dft/clk_gate.v cosim_tb.v 2>/dev/null
vvp -n $out +seed=$2 +cycles=$3 $4 | grep -E "COSIM|MISMATCH|SDF|reset asserted" | head -${5:-6}
