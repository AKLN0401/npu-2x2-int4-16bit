#!/usr/bin/env bash
# Mutation check for audit_arith.py: each mutant must FAIL the RTL audit suite.
# Runs inside the tools container (npu1x1 at /work). Usage: mutants.sh <sim dir>
set -u
S=$1; cd "$S"
export PYTHONPATH=/work/tools/.cocotb2 PATH=/work/tools/.cocotb2/bin:$PATH AUDIT_SEED=1
declare -A M=(
 [m1_unsigned_mult]='s/wire signed \[2\*DW-1:0\] prod = a \* b;/wire [2*DW-1:0] prod = $unsigned(a) * $unsigned(b);/|npu_pe.v'
 [m2_zero_extend_product]='s/{{(ACC_W-2\*DW){prod\[2\*DW-1\]}}, prod}/{{(ACC_W-2*DW){1'"'"'b0}}, prod}/|npu_pe.v'
 [m3_saturate]='s/acc <= acc + {{(ACC_W-2\*DW){prod\[2\*DW-1\]}}, prod};/acc <= sat(acc, prod);/|npu_pe.v'
 [m4_lane_swap_row1]='s/\.b       (b\[DW\*j +: DW\]),/.b       (b[DW*(i==1 ? 1-j : j) +: DW]),/|npu_array.v'
 [m5_read_zero_extend]='s/{{(32-ACC_W){acc_sel\[ACC_W-1\]}}, acc_sel}/{{(32-ACC_W){1'"'"'b0}}, acc_sel}/|project.v'
 [m6_sext_from_bit6]='s/{{(ACC_W-2\*DW){prod\[2\*DW-1\]}}, prod}/{{(ACC_W-2*DW+1){prod[2*DW-2]}}, prod[2*DW-2:0]}/|npu_pe.v'
)
for m in $(echo "${!M[@]}" | tr ' ' '\n' | sort); do
  rule=${M[$m]%|*}; file=${M[$m]#*|}
  d=mut_$m; rm -rf $d; mkdir -p $d/dft; cp /work/src/*.v $d/; cp /work/src/dft/*.v $d/dft/
  sed -i "$rule" $d/$file
  if [ $m = m3_saturate ]; then
    sed -i 's|^    wire signed \[2\*DW-1:0\] prod = a \* b;|&\n    function signed [ACC_W-1:0] sat(input signed [ACC_W-1:0] x, input signed [2*DW-1:0] p);\n        reg signed [ACC_W:0] s; begin s = x + p; sat = (s > 32767) ? 16'"'"'sh7fff : (s < -32768) ? 16'"'"'sh8000 : s[ACC_W-1:0]; end\n    endfunction|' $d/$file
  fi
  if cmp -s $d/$file /work/src/$file 2>/dev/null || cmp -s $d/$file /work/src/dft/$file 2>/dev/null; then echo "$m NOT-APPLIED"; continue; fi
  rm -rf sim_build results.xml
  make SRC_DIR=$PWD/$d > $d/run.log 2>&1
  if python -m cocotb_tools.check_results results.xml >/dev/null 2>&1; then r="SURVIVED (BAD)"; else r="KILLED"; fi
  echo "$m $r $(grep -o 'TESTS=[0-9]* PASS=[0-9]* FAIL=[0-9]*' $d/run.log | tail -1)"
done
rm -rf sim_build results.xml
