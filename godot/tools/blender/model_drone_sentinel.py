"""Sentinel: armoured surveillance drone. Flat manta chassis, four ducted fans in armoured nacelles, a forward sensor block with a
red iris (Eye), rear heat-sink fins and an antenna mast."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dronelib import ducted_fan, rotor_part  # noqa: E402
from helpers import (Part, empty, export_model, hexc, light, make_material, new_scene, paint, ring_se)  # noqa: E402
from shade import Decal, p_barcode, p_box, p_glyphs, p_stripes  # noqa: E402

new_scene()
armor = make_material("Armor", tex="plating")
carbon = make_material("Carbon", tex="carbon")
gun = make_material("Gunmetal", tex="steel")
glass = make_material("Lens", tex="glass", color=(0.01, 0.014, 0.018))
glow = make_material("Glow", tex="glow", color=hexc("#ff2038"))
eyem = make_material("Eye", emit=hexc("#ff2038"), emit_strength=2.4)

hull = paint("plating", "#566068")
hull2 = paint("plating", "#3d454c")
plate = paint("plating", "#6c7780")
cf = paint("carbon", "#6a7075")
gm = paint("steel", "#6c747b")
gm2 = paint("steel", "#363c42")
RED = hexc("#ff2038")

Z = 0.95
b = Part("Body", seed=11)
rings = [ring_se(0, y, Z + dz, rx, rz, 18, 3.6, plane="xz") for y, rx, rz, dz in
         [(-0.50, 0.14, 0.085, 0.0), (-0.34, 0.30, 0.13, 0.01), (-0.10, 0.43, 0.165, 0.02), (0.18, 0.40, 0.155, 0.01),
          (0.38, 0.27, 0.12, -0.01), (0.52, 0.14, 0.085, -0.02), (0.60, 0.07, 0.06, -0.025)]]
b.loft(rings, mat=armor, tint=hull)
b.box((0.56, 0.74, 0.045), (0, -0.06, Z + 0.168), mat=armor, tint=plate, bevel=0.016, bsegs=2, top=(0.9, 0.86))          # top plate
for y in (-0.30, -0.22, -0.14, -0.06):
    b.box((0.3, 0.035, 0.014), (0, y, Z + 0.196), mat=gun, tint=gm2)                                                   # vents
b.box((0.34, 0.5, 0.1), (0, -0.05, Z - 0.18), mat=armor, tint=hull2, bevel=0.016, bsegs=2)                             # battery pod
b.box((0.2, 0.12, 0.03), (0, -0.26, Z - 0.13), mat=gun, tint=gm2, bevel=0.006)
for x in (-0.15, -0.09, -0.03, 0.03, 0.09, 0.15):                                                                        # rear heat-sink fins
    b.box((0.022, 0.2, 0.14), (x, -0.5, Z + 0.1), mat=gun, tint=gm2, bevel=0.003)
b.rod((0.12, -0.34, Z + 0.19), (0.16, -0.5, Z + 0.62), 0.005, mat=gun, tint=gm, segs=5)                                 # antenna mast + dish
b.rod((-0.12, -0.34, Z + 0.19), (-0.17, -0.46, Z + 0.46), 0.004, mat=gun, tint=gm, segs=5)
b.cyl(0.05, 0.012, (0.16, -0.5, Z + 0.62), axis="y", mat=gun, tint=gm, segs=12, bevel=0.002)
# sensor block: dark housing, big lens (the Eye sits in front of it), two small lenses, scan bar
b.box((0.36, 0.2, 0.15), (0, 0.5, Z - 0.015), mat=gun, tint=gm2, bevel=0.016, bsegs=2, top=(0.9, 0.85))
b.cyl(0.062, 0.05, (0, 0.615, Z - 0.015), axis="y", mat=gun, tint=gm, segs=18, bevel=0.004)
b.cyl(0.048, 0.02, (0, 0.645, Z - 0.015), axis="y", mat=glass, segs=18)
for sx in (-1, 1):
    b.cyl(0.026, 0.03, (sx * 0.14, 0.598, Z - 0.015), axis="y", mat=gun, tint=gm, segs=12, bevel=0.003)
    b.cyl(0.019, 0.016, (sx * 0.14, 0.617, Z - 0.015), axis="y", mat=glass, segs=12)
b.box((0.3, 0.014, 0.014), (0, 0.6, Z - 0.1), mat=glow)                                                                 # scan bar
b.box((0.012, 0.014, 0.012), (0.0, 0.1, Z + 0.2), mat=glow)                                                             # status LED
b.box((0.02, 0.012, 0.012), (0.0, -0.595, Z + 0.02), mat=glow)
# arms, nacelles, ducted fans
rotors = []
for sx in (-1, 1):
    for sy in (-1, 1):
        mx, my = 0.64 * sx, 0.52 * sy
        b.bar((0.30 * sx, 0.12 * sy, Z + 0.0), (mx * 0.9, my * 0.9, Z + 0.05), 0.2, 0.1, mat=armor, tint=hull2, bevel=0.018, bsegs=2, taper=(0.8, 0.9))
        b.box((0.2, 0.2, 0.07), (mx * 0.93, my * 0.93, Z + 0.015), mat=armor, tint=plate, bevel=0.014, bsegs=1)
        ducted_fan(b, (mx, my, Z + 0.05), 0.27, armor, hull, gun, gm2, glow, height=0.12, lip=0.036, segs=22, struts=3, hub_r=0.055,
                   hub_mat=gun, hub_tint=gm, glow_tint=hexc("#ff2038"))
        b.box((0.03, 0.03, 0.016), (mx + sx * 0.255, my, Z + 0.105), mat=glow, tint=hexc("#ff2038") if sy > 0 else hexc("#20ff60"))  # nav light
        name = ("RotorF" if sy > 0 else "RotorR") + ("L" if sx < 0 else "R")
        rotors.append(rotor_part(name, (mx, my, Z + 0.1), 0.245, 3, carbon, cf, seed=20 + len(rotors), chord=0.055))

eye = Part("Eye", origin=(0, 0.652, Z - 0.015), seed=3)
eye.sphere(0.03, (0, 0.655, Z - 0.015), mat=eyem, segs=12, rings=8)

decals = [
    Decal((0.0, -0.06, Z + 0.192), (0, 0, 1), (0, 1, 0), (0.32, 0.18), p_glyphs(hexc("#b9c2c7"), cells=5, rows=2, seed=7), depth=0.05),
    Decal((0.0, 0.2, Z + 0.17), (0, 0, 1), (0, 1, 0), (0.4, 0.07), p_stripes(8, 0.5, 45.0, hexc("#c9a21f")), depth=0.06),
    Decal((0.0, -0.05, Z - 0.235), (0, 0, -1), (0, 1, 0), (0.3, 0.2), p_barcode(hexc("#b9c2c7"), 12, seed=2), depth=0.05),
]
for sx in (-1, 1):
    decals.append(Decal((sx * 0.45, 0.07, Z + 0.07), (0, 0, 1), (sx, 0.3, 0), (0.12, 0.3), p_stripes(5, 0.5, 90.0, hexc("#c9a21f")), depth=0.1))

rig = [empty("Muzzle", (0, 0.66, Z - 0.015)),
       light("EyeLight", (0, 0.72, Z - 0.015), "omni", (1.0, 0.18, 0.2), 1.4, 5.0, attenuation=1.6, fade=(32, 12), group="eye"),
       light("Fill", (0, 0.1, Z + 0.85), "omni", (0.72, 0.82, 1.0), 1.0, 3.4, mask="own", attenuation=1.2, fade=(30, 12))]
parts = [b] + rotors + [eye]
print("  body tris", b.tri_count(), "rotors", sum(p.tri_count() for p in rotors))
export_model("drone_sentinel", parts, extras=rig, groups={"atlas": dict(base="drone_sentinel", material="Hull")}, size=1024, decals=decals,
             ao_dist=0.2, ao_strength=0.8, emit_strength=1.8)
