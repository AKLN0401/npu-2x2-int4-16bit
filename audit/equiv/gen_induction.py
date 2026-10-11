#!/usr/bin/env python3
"""Generate the explicit RTL-vs-netlist induction proof (yosys sat), see 05_physical_signoff.md.
Inputs: netlist (for the 98 flop Q names). Outputs: chk.v (side-by-side wrapper), step.ys, base.ys.
The ICG GATE input nets get named wires (icg_gate0/1) in both designs by a text pass over RTLIL."""
import re, sys
netlist = sys.argv[1]
q = sorted(set(re.findall(r"\.Q\(\s*\\?([^\s)]+)\s*\)", open(netlist).read())))
assert len(q) == 98, len(q)
open("state_names.txt", "w").write("\n".join(q) + "\n")
ports = "input clk, input rst_n, input ena, input [7:0] ui_in, input [7:0] uio_in"
open("chk.v", "w").write(f"""module chk({ports},
  output [7:0] uo_g, uo_t, uio_g, uio_t, oe_g, oe_t);
  gold g(.clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(ui_in),.uio_in(uio_in),.uo_out(uo_g),.uio_out(uio_g),.uio_oe(oe_g));
  gate t(.clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(ui_in),.uio_in(uio_in),.uo_out(uo_t),.uio_out(uio_t),.uio_oe(oe_t));
endmodule
""")
pre = """read_rtlil gate_named.il
read_rtlil gold_named.il
read_verilog chk.v
hierarchy -top chk
flatten
async2sync
opt_clean
"""
eq = lambda n: f"\\g.{n} \\t.{n}"
assume = " ".join(f"-set-at 1 {eq(n)}" for n in q)
prove = " ".join(f"-prove {eq(n)}" for n in q)
prove += " -prove uo_g uo_t -prove uio_g uio_t -prove oe_g oe_t -prove \\g.icg_gate0 \\t.icg_gate0 -prove \\g.icg_gate1 \\t.icg_gate1"
open("step.ys", "w").write(pre + f"sat -seq 2 -ignore_unknown_cells {assume} {prove} -prove-skip 1 -show-inputs\n")
# base: independent arbitrary initial states, rst_n low and scan_en pin low for 3 cycles
base_set = "-set rst_n 1'0 -set uio_in[5] 1'0"
open("base.ys", "w").write(pre + f"sat -seq 4 -ignore_unknown_cells {base_set} {prove} -prove-skip 3 -show-inputs\n")
print(f"{len(q)} state bits")
