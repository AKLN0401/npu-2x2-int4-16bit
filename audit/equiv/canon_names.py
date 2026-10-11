#!/usr/bin/env python3
"""Make the gate netlist's register names canonical in the gold RTLIL.
For every name N that names a flop output / ICG output in the gate netlist and exists in gold
only as an alias (`connect \\N \\S`), drop the alias and rename S -> N everywhere. Pure renaming:
no cell or connection changes, so the gold logic is untouched."""
import re, sys
gold_in, netlist, gold_out = sys.argv[1:4]
nl = open(netlist).read()
names = set(re.findall(r"\.(?:Q|GCLK)\(\s*\\?([^\s)]+)\s*\)", nl))
il = open(gold_in).read()
conns = dict(re.findall(r"^\s*connect (\\\S+) (\\\S+)\s*$", il, re.M))
ren = {}
def root(x):
    seen = set()
    while x in conns and x not in seen:   # follow alias chains to the driving wire
        seen.add(x)
        x = conns[x]
    return x
alias_of = {}
for n in names:
    t = "\\" + n
    if t in conns:
        r = root(t)
        if r != t and r not in ren:
            ren[r] = t
drop = set(ren.values())
lines = []
for line in il.splitlines():
    m = re.match(r"^\s*connect (\\\S+) (\\\S+)\s*$", line)
    if m and m.group(1) in drop:
        continue                                   # drop the alias connection of a target name
    m = re.match(r"^(\s*wire .*?)(\\\S+)\s*$", line)
    if m and m.group(2) in drop and m.group(2) not in ren:
        continue                                   # drop the alias wire declaration
    lines.append(line)
out = "\n".join(lines) + "\n"
tok = re.compile(r"\\\S+")
out = tok.sub(lambda m: ren.get(m.group(0), m.group(0)), out)
open(gold_out, "w").write(out)
print(f"gate names {len(names)}, renamed {len(ren)}, already canonical/ports {len(names) - len(ren)}")
