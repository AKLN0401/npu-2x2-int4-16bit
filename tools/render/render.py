# KLayout batch render of the routing layers: klayout -b -r render.py -rd gds=.. -rd out=.. -rd box=x1,y1,x2,y2 -rd w=.. -rd h=..
import pya
lv = pya.LayoutView()
lv.load_layout(gds, False)
lv.max_hier()
lv.clear_layers()
# (source, fill, frame, dither, name): dither 0 = solid, 5 = sparse dots, 2 = hatched
layers = [
    ("67/20", 0x5a4a7a, 0x5a4a7a, 1, "li1"),
    ("68/20", 0x3a78ff, 0x3a78ff, 5, "met1"),
    ("69/20", 0xff4b4b, 0xff4b4b, 5, "met2"),
    ("70/20", 0x3ad06a, 0x3ad06a, 5, "met3"),
    ("71/20", 0xffb020, 0xffb020, 9, "met4"),
    ("71/16", 0xffffff, 0xffffff, 0, "met4 pin"),
    ("70/16", 0xffffff, 0xffffff, 0, "met3 pin"),
]
for src, fill, frame, dither, name in layers:
    lp = pya.LayerPropertiesNode()
    lp.source = src
    lp.fill_color = fill
    lp.frame_color = frame
    lp.dither_pattern = dither
    lp.name = name
    lv.insert_layer(lv.end_layers(), lp)
lv.set_config("background-color", "#0b0d12")
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", "false")
lv.set_config("cell-box-visible", "false")
x1, y1, x2, y2 = [float(v) for v in box.split(",")]
lv.zoom_box(pya.DBox(x1, y1, x2, y2))
lv.save_image(out, int(w), int(h))
print("wrote", out)
