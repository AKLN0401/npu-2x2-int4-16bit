#!/usr/bin/env python3
"""Add wires \\icg_gate0/1 aliasing the GATE input of each row ICG cell in an RTLIL module."""
import re, sys
src, dst = sys.argv[1:3]
il = open(src).read()
out, extra = [], {}
cell = None
for line in il.splitlines():
    m = re.match(r"\s*cell \\sky130_fd_sc_hd__dlclkp_1 \\i_array\.g_row\[(\d)\]\.i_cg\.icg\s*$", line)
    if m: cell = m.group(1)
    m2 = re.match(r"\s*connect \\GATE (.+)$", line)
    if cell is not None and m2:
        extra[cell] = m2.group(1).strip()
    if re.match(r"\s*end\s*$", line): cell = None
    out.append(line)
assert set(extra) == {"0", "1"}, extra
txt = "\n".join(out) + "\n"
# insert wires + connects before the end of the (single) module
add = "".join(f"  wire \\icg_gate{r}\n  connect \\icg_gate{r} {s}\n" for r, s in sorted(extra.items()))
i = txt.rstrip().rfind("\nend")
txt = txt[:i] + "\n" + add + txt[i:]
open(dst, "w").write(txt)
print(dst, extra)
