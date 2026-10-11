"""GDS -> data for the WebGL viewer in viewer3d.js.

Each layer is merged and cut into horizontal trapezoids (y1, y2, x bottom-left/right, x top-left/right) in
5 nm units (SKY130 grid). Per layer, sorted by (y1, xbl), the fields are delta-coded, split into byte planes
and gzipped: ~0.33 MB for the 1x1 tile (2.1 MB raw). viewer3d.js decode() undoes it.

Usage: python gen3d.py [--raw] <gds> <out.html> [title]   -> standalone full-window viewer (view options in the
       URL hash: #view=iso|top|close&layers=all|metal|cells&z=4&panel=0). --raw: planes not gzipped, so the model
       is drawn before the page's load event (needed for `firefox --screenshot`)
       (import encode() for embedding, see build_overview.py)
"""
import base64
import gzip
import json
import os
import sys

import klayout.db as db
import numpy as np

GRID_NM = 5
# (name, gds layer/datatype, z bottom µm, z top µm, colour) — approximate SKY130 stack
LAYERS = [
    ("diff",  (65, 20), 0.00,   0.12,   "#3f9b52"),
    ("tap",   (65, 44), 0.00,   0.12,   "#2b6b3a"),
    ("poly",  (66, 20), 0.3262, 0.5062, "#d23c3c"),
    ("licon", (66, 44), 0.12,   0.9361, "#9a9aa8"),
    ("li1",   (67, 20), 0.9361, 1.0361, "#8e5cc8"),
    ("mcon",  (67, 44), 1.0361, 1.3761, "#b8b8c4"),
    ("met1",  (68, 20), 1.3761, 1.7361, "#3f7fff"),
    ("via",   (68, 44), 1.7361, 2.0061, "#c8c8d4"),
    ("met2",  (69, 20), 2.0061, 2.3661, "#ff5a8c"),
    ("via2",  (69, 44), 2.3661, 2.7861, "#d4d4dc"),
    ("met3",  (70, 20), 2.7861, 3.6311, "#3ad0a0"),
    ("via3",  (70, 44), 3.6311, 4.0211, "#e0e0e8"),
    ("met4",  (71, 20), 4.0211, 4.8661, "#ffb020"),
]
HERE = os.path.dirname(os.path.abspath(__file__))


def trapezoids(ly, top, li, box, scale):
    out = []
    for poly in db.Region(top.begin_shapes_rec(li)).merged().decompose_trapezoids_to_region().each():
        pts = [(p.x, p.y) for p in poly.each_point_hull()]
        y1, y2 = min(y for _, y in pts), max(y for _, y in pts)
        if y1 == y2:
            continue
        bot = sorted(x for x, y in pts if y == y1)
        tx = sorted(x for x, y in pts if y == y2)
        g = [y1 - box.bottom, y2 - box.bottom] + [x - box.left for x in (bot[0], bot[-1], tx[0], tx[-1])]
        assert all(v % scale == 0 and 0 <= v // scale < 65536 for v in g), g
        out.append([v // scale for v in g])
    return np.array(out, dtype=np.int64).reshape(-1, 6)


def pack(a, raw=False):
    """Sort, delta-code (y1 vs previous row; xbl vs previous trapezoid in the same row; widths and
    top-edge offsets relative to the bottom edge), byte planes, gzip, base64."""
    a = a[np.lexsort((a[:, 2], a[:, 0]))]
    n = len(a)
    same = np.r_[False, a[1:, 0] == a[:-1, 0]]
    f = np.empty_like(a)
    f[:, 0] = np.r_[a[:1, 0], np.diff(a[:, 0])]
    f[:, 1] = a[:, 1] - a[:, 0]
    f[:, 2] = np.where(same, a[:, 2] - np.r_[0, a[:-1, 2]], a[:, 2])
    f[:, 3] = a[:, 3] - a[:, 2]
    f[:, 4] = a[:, 4] - a[:, 2]
    f[:, 5] = a[:, 5] - a[:, 3]
    u = (f & 0xFFFF).astype(np.uint16)
    planes = b"".join((u[:, k] & 0xFF).astype(np.uint8).tobytes() + (u[:, k] >> 8).astype(np.uint8).tobytes()
                      for k in range(6))
    assert len(planes) == 12 * n
    return base64.b64encode(planes if raw else gzip.compress(planes, 9, mtime=0)).decode()


def encode(gds, title, raw=False):
    ly = db.Layout()
    ly.read(gds)
    top = ly.top_cell()
    box = top.bbox()
    scale = round(GRID_NM / (ly.dbu * 1000))
    layers = []
    for name, (l, d), z0, z1, col in LAYERS:
        li = ly.find_layer(l, d)
        if li is None:
            continue
        a = trapezoids(ly, top, li, box, scale)
        layers.append(dict(name=name, z0=z0, z1=z1, color=col, count=len(a), data=pack(a, raw)))
    return dict(title=title, grid_um=GRID_NM / 1000, w_um=box.width() * ly.dbu, h_um=box.height() * ly.dbu,
                raw=raw, layers=layers)


STANDALONE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>{title}</title>
<style>html, body {{ margin: 0; height: 100%; background: #0d1016; overflow: hidden; }} #v {{ position: fixed; inset: 0; }}</style>
</head><body><div id="v"></div>
<script>{js}</script>
<script>
const hp = new URLSearchParams(location.hash.slice(1));
initGds3D(document.getElementById("v"), {meta}, {{ active: true, view: hp.get("view"), layers: hp.get("layers"),
  z: hp.get("z") ? +hp.get("z") : undefined, panel: hp.get("panel") !== "0" }});
</script></body></html>
"""


def standalone(meta):
    js = open(os.path.join(HERE, "viewer3d.js")).read()
    return STANDALONE.format(title=meta["title"], js=js, meta=json.dumps(meta))


if __name__ == "__main__":
    raw = "--raw" in sys.argv
    if raw:
        sys.argv.remove("--raw")
    meta = encode(sys.argv[1], sys.argv[3] if len(sys.argv) > 3 else "GDS 3D view", raw)
    html = standalone(meta)
    open(sys.argv[2], "w").write(html)
    print(f"wrote {sys.argv[2]}: {len(html) / 1e6:.2f} MB, "
          f"{sum(L['count'] for L in meta['layers'])} trapezoids", file=sys.stderr)
