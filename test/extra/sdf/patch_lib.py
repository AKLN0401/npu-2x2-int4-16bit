"""Copy of sky130_fd_sc_hd.v for Icarus SDF sims: Icarus ignores $setuphold/$recrem, so the
*_delayed nets those checks would drive stay undriven (Z -> X). Drive each one from its source."""
import re, sys
src, dst = sys.argv[1:3]
out, n = [], 0
for line in open(src):
    out.append(line)
    m = re.match(r"\s*wire\s+(\w+)_delayed\s*;", line)
    if m:
        out.append(f"    assign {m.group(1)}_delayed = {m.group(1)};\n"); n += 1
open(dst, "w").writelines(out)
print(f"{n} delayed nets driven")
