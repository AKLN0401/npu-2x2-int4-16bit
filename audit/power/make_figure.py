#!/usr/bin/env python3
"""Static SVG of the clock-gating power result (README figure). Same data and styling as docs/overview.html §9.
Usage: make_figure.py <power_results.json> <out.svg>"""
import json, sys
R = json.load(open(sys.argv[1]))
tt = "tt_025C_1v80"
rows = [("idle", "Idle", "clock running, no host writes"), ("slow_r11", "Slow host", "1 write / 100 clocks"),
        ("max_r11", "Max bus rate", "1 step / 21 clocks, both rows"), ("max_r01", "Max bus rate, row 1 off", "ROWEN = 01")]
tot = lambda sc, k: float(R[f"{sc}|{tt}"][k]["Total"])
INK, MUTED, LINE, SURF, G, F = "#141413", "#5e5d59", "#e3e0d6", "#f0eee6", "#c96442", "#3a68a8"
FONT = "'Inter Tight','Helvetica Neue',Arial,sans-serif"
W, X0, X1, XMAX = 880, 220, 610, 600.0
x = lambda v: X0 + (X1 - X0) * v / XMAX
o = []
top = 120; rowh = 54
H = top + rowh * len(rows) + 60
o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}" role="img" '
         f'aria-label="Core power with and without clock gating for four workloads">')
o.append(f'<rect x="0.5" y="0.5" width="{W-1}" height="{H-1}" rx="6" fill="{SURF}" stroke="{LINE}"/>')
ig, if_ = tot("idle", "gated"), tot("idle", "forced")
o.append(f'<text x="24" y="40" font-size="15" font-weight="600" fill="{INK}">Clock gating saves {100*(if_-ig)/if_:.1f}% of core power when idle, 48–58% under load</text>')
o.append(f'<text x="24" y="62" font-size="12.5" fill="{MUTED}">Post-PnR netlist, 50 MHz, typical corner (tt 25 °C 1.80 V). Vector-based: gate-level VCD → OpenSTA with routed SPEF.</text>')
o.append(f'<rect x="24" y="84" width="12" height="12" rx="2" fill="{G}"/><text x="42" y="94.5" font-size="12.5" fill="{MUTED}">Clock gating on</text>')
o.append(f'<rect x="160" y="84" width="12" height="12" rx="2" fill="{F}"/><text x="178" y="94.5" font-size="12.5" fill="{MUTED}">No clock gating (row clocks forced on by test_mode)</text>')
for t in range(0, 601, 100):
    o.append(f'<line x1="{x(t):.1f}" y1="{top-6}" x2="{x(t):.1f}" y2="{top+rowh*len(rows)-14}" stroke="{LINE}" stroke-width="1"/>')
    anchor = "start" if t == 0 else "end" if t == 600 else "middle"
    o.append(f'<text x="{x(t):.1f}" y="{top+rowh*len(rows)+4}" font-size="11.5" fill="{MUTED}" text-anchor="{anchor}">{t}</text>')
o.append(f'<text x="{W-24}" y="{top+rowh*len(rows)+4}" font-size="11.5" fill="{MUTED}" text-anchor="end">µW</text>')
def bar(x0, y, w, c):   # 4 px rounded data end, square at the baseline
    r = min(4, w)
    return (f'<path d="M{x0:.1f},{y} h{w-r:.1f} a{r},{r} 0 0 1 {r},{r} v{12-2*r} a{r},{r} 0 0 1 -{r},{r} h-{w-r:.1f} z" fill="{c}"/>')
for i, (sc, name, sub) in enumerate(rows):
    y = top + i * rowh
    g, f = tot(sc, "gated"), tot(sc, "forced")
    o.append(f'<text x="24" y="{y+10}" font-size="13.5" fill="{INK}">{name}</text>')
    o.append(f'<text x="24" y="{y+27}" font-size="12" fill="{MUTED}">{sub}</text>')
    o.append(bar(X0, y, x(g) - X0, G) + f'<title>{name}, clock gating on: {g:.0f} µW</title>')
    o.append(bar(X0, y + 14, x(f) - X0, F) + f'<title>{name}, no clock gating: {f:.0f} µW</title>')
    o.append(f'<text x="{W-24}" y="{y+10}" font-size="13.5" font-weight="600" fill="{INK}" text-anchor="end">−{100*(f-g)/f:.1f}%</text>')
    o.append(f'<text x="{W-24}" y="{y+27}" font-size="12" fill="{MUTED}" text-anchor="end">{g:.0f} → {f:.0f} µW, {f-g:.0f} µW saved</text>')
o.append('</svg>')
open(sys.argv[2], "w").write("\n".join(o) + "\n")
