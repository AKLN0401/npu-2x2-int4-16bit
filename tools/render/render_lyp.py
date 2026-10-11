# KLayout batch render with the PDK layer properties (all layers):
#   klayout -b -r render_lyp.py -rd gds=.. -rd lyp=.. -rd out=.. -rd w=.. -rd h=.. [-rd box=x1,y1,x2,y2]
import pya
lv = pya.LayoutView()
lv.load_layout(gds, False)
lv.load_layer_props(lyp)
lv.max_hier()
lv.set_config("background-color", "#ffffff")
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", "false")
try:
    x1, y1, x2, y2 = [float(v) for v in box.split(",")]
    lv.zoom_box(pya.DBox(x1, y1, x2, y2))
except NameError:
    lv.zoom_fit()
lv.save_image(out, int(w), int(h))
print("wrote", out)
