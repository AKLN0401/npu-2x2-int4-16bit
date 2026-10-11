#!/usr/bin/env python3
"""Static SVG of the clock-gating power result: grouped bar chart, black on white, in the style of a
textbook figure. Used for the README figure and inlined into docs/overview.html §9.
Usage: make_figure.py <power_results.json> <out.svg>"""
import json, sys

R = json.load(open(sys.argv[1]))
tt = "tt_025C_1v80"
rows = [("idle", "Idle"), ("slow_r11", "Slow host"), ("max_r11", "Max bus rate"), ("max_r01", "Max bus rate,\nrow 1 off")]
tot = lambda sc, k: float(R[f"{sc}|{tt}"][k]["Total"])

FONT = "Helvetica, Arial, sans-serif"
W, H = 760, 400
L, Rr, T, B = 78, 20, 28, 84          # plot area margins
PW, PH = W - L - Rr, H - T - B
YMAX = 700.0
y = lambda v: T + PH * (1 - v / YMAX)
n = len(rows)
gw = PW / n
bw = 52

o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="{FONT}" font-size="13" '
     f'role="img" aria-label="Core power with and without clock gating for four workloads">',
     '<defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
     '<rect width="6" height="6" fill="#fff"/><line x1="0" y1="0" x2="0" y2="6" stroke="#000" stroke-width="1.6"/>'
     '</pattern></defs>',
     f'<rect width="{W}" height="{H}" fill="#fff"/>']

# horizontal grid + y ticks
for t in range(0, 701, 100):
    yy = y(t)
    if 0 < t:
        o.append(f'<line x1="{L}" y1="{yy:.1f}" x2="{L+PW}" y2="{yy:.1f}" stroke="#bbb" stroke-width="0.7" stroke-dasharray="2 3"/>')
    o.append(f'<line x1="{L-5}" y1="{yy:.1f}" x2="{L}" y2="{yy:.1f}" stroke="#000" stroke-width="1"/>')
    o.append(f'<text x="{L-9}" y="{yy+4:.1f}" text-anchor="end">{t}</text>')
o.append(f'<text transform="translate(18 {T+PH/2:.0f}) rotate(-90)" text-anchor="middle">Core power (µW)</text>')

# axes
o.append(f'<path d="M{L},{T} V{T+PH} H{L+PW}" fill="none" stroke="#000" stroke-width="1.3"/>')

for i, (sc, name) in enumerate(rows):
    g, f = tot(sc, "gated"), tot(sc, "forced")
    cx = L + gw * (i + 0.5)
    for dx, v, fill, what in ((-bw - 3, g, "url(#hatch)", "clock gating on"), (3, f, "#000", "no clock gating")):
        x0 = cx + dx
        o.append(f'<rect x="{x0:.1f}" y="{y(v):.1f}" width="{bw}" height="{T+PH-y(v):.1f}" fill="{fill}" stroke="#000" stroke-width="1.2">'
                 f'<title>{name.replace(chr(10), " ")}, {what}: {v:.0f} µW</title></rect>')
        o.append(f'<text x="{x0+bw/2:.1f}" y="{y(v)-5:.1f}" text-anchor="middle">{v:.0f}</text>')
    for k, line in enumerate(name.split("\n")):
        o.append(f'<text x="{cx:.1f}" y="{T+PH+20+15*k}" text-anchor="middle">{line}</text>')
    ny = T + PH + 20 + 15 * name.count("\n") + 17
    o.append(f'<text x="{cx:.1f}" y="{ny}" text-anchor="middle" font-style="italic">−{100*(f-g)/f:.1f}%</text>')

# legend (inside plot, top left)
lx, ly = L + 14, T + 10
o.append(f'<rect x="{lx-8}" y="{ly-8}" width="208" height="58" fill="#fff" stroke="#000" stroke-width="0.8"/>')
o.append(f'<rect x="{lx}" y="{ly}" width="20" height="13" fill="url(#hatch)" stroke="#000" stroke-width="1.2"/>'
         f'<text x="{lx+28}" y="{ly+11}">clock gating on</text>')
o.append(f'<rect x="{lx}" y="{ly+25}" width="20" height="13" fill="#000" stroke="#000" stroke-width="1.2"/>'
         f'<text x="{lx+28}" y="{ly+36}">no clock gating</text>')
o.append('</svg>')
open(sys.argv[2], "w").write("\n".join(o) + "\n")
