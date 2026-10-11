"""Icarus' SDF reader cannot resolve escaped instance names containing '.', '[' or ']'
(the ICGs and the gated-clock buffers). Rename those instances in copies of the netlist and
SDF files to plain identifiers. Nets keep their names (SDF only refers to instance.pin)."""
import re, sys
nl_in, nl_out = sys.argv[1:3]
sdfs = sys.argv[3:]          # pairs: in out
nl = open(nl_in).read()
names = re.findall(r"^\s*sky130_fd_sc_hd__\w+\s+\\(\S+)\s+\(", nl, re.M)
plain = {n: "x_" + re.sub(r"[.\[\]]", "_", n) for n in names}
for n, p in plain.items():
    nl, k = re.subn(r"(sky130_fd_sc_hd__\w+\s+)\\" + re.escape(n) + r"\s", r"\g<1>" + p + " ", nl)
    assert k == 1, n
open(nl_out, "w").write(nl)
for s_in, s_out in zip(sdfs[::2], sdfs[1::2]):
    s = open(s_in).read()
    for n, p in plain.items():
        esc = re.sub(r"([.\[\]])", r"\\\1", n)
        # instance refs: '(INSTANCE esc)' or 'esc.PIN'
        s = re.sub(r"(?<![\w\\])" + re.escape(esc) + r"(?=[.)\s])", p, s)
    open(s_out, "w").write(s)
print(len(plain), "instances renamed:", *plain.values(), sep="\n  ")
