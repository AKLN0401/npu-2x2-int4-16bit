#!/usr/bin/env bash
# RTL vs post-PnR netlist: explicit induction (step + reset base) with yosys sat. LibreLane image.
set -eu
NL=/work/runs/wokwi/final/nl/tt_um_akln0401_npu.nl.v
yosys -q -l gold.log gold.ys
python3 canon_names.py gold_raw.il $NL gold.il
yosys -q -l gate.log gate.ys
python3 name_icg_gate.py gold.il gold_named.il
python3 name_icg_gate.py gate_raw.il gate_named.il
python3 gen_induction.py $NL
for p in step base; do
  if yosys -q -l $p.log -p "read_verilog icg_bb.v; script $p.ys" >/dev/null 2>&1 && grep -q 'SUCCESS!' $p.log; then echo "equiv_$p PASS"; else echo "equiv_$p FAIL"; fi
done
