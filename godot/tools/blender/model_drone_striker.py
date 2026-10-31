"""Striker: loitering munition. Needle fuselage with an amber warhead band, four small ducted props and an amber seeker eye."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dronelib import ducted_fan, rotor_part  # noqa: E402
from helpers import (Part, export_model, hexc, light, make_material, new_scene, paint, ring_se)  # noqa: E402
from shade import Decal, p_barcode, p_glyphs, p_stripes  # noqa: E402

new_scene()
armor = make_material("Armor", tex="plating")
carbon = make_material("Carbon", tex="carbon")
gun = make_material("Gunmetal", tex="steel")
glass = make_material("Lens", tex="glass", color=(0.01, 0.012, 0.014))
glow = make_material("Glow", tex="glow", color=hexc("#ff8a1c"))
eyem = make_material("Eye", emit=hexc("#ff8a1c"), emit_strength=2.4)

hull = paint("plating", "#525a50")
hull2 = paint("plating", "#383e35")
band = paint("plating", "#d58a24")
cf = paint("carbon", "#666a6e")
gm = paint("steel", "#6a7076")
gm2 = paint("steel", "#343a3e")

Z = 0.82
b = Part("Body", seed=31)
rings = [ring_se(0, y, Z, r, r, 18, 2.0, plane="xz") for y, r in
         [(-0.45, 0.035), (-0.38, 0.07), (-0.2, 0.108), (0.0, 0.12), (0.12, 0.122), (0.3, 0.115), (0.4, 0.088), (0.47, 0.05), (0.505, 0.024)]]
b.loft(rings, mat=armor, tint=hull)
b.cyl(0.126, 0.13, (0, 0.2, Z), axis="y", mat=armor, tint=band, segs=20, bevel=0.004, sharp=60.0)      # warhead band
for y in (0.125, 0.275):
    b.cyl(0.128, 0.014, (0, y, Z), axis="y", mat=armor, tint=hull2, segs=20)
for k in range(4):                                                                                       # tail fins
    a = math.radians(45 + 90 * k)
    c, s = math.cos(a), math.sin(a)
    b.box((0.012, 0.17, 0.2), (c * 0.115, -0.33, Z + s * 0.115), mat=armor, tint=hull2, bevel=0.003, rot=(0, 0, 0))
b.torus(0.12, 0.011, (0, -0.4, Z), rot=(90, 0, 0), mat=carbon, tint=cf, segs=22, sides=6)             # tail ring
b.cyl(0.062, 0.04, (0, -0.44, Z), axis="y", mat=gun, tint=gm2, segs=12)
b.cyl(0.043, 0.03, (0, 0.485, Z), axis="y", mat=glass, segs=14)
b.box((0.2, 0.3, 0.035), (0, -0.04, Z - 0.125), mat=gun, tint=gm2, bevel=0.008)                          # battery
b.box((0.06, 0.1, 0.02), (0, 0.14, Z + 0.128), mat=gun, tint=gm, bevel=0.004)                            # arming pod
b.box((0.012, 0.02, 0.012), (0, 0.14, Z + 0.142), mat=glow)
rotors = []
for sx in (-1, 1):
    for sy in (-1, 1):
        mx, my = 0.34 * sx, 0.26 * sy
        b.rod((0.1 * sx, 0.04 * sy, Z + 0.02), (mx, my, Z + 0.04), 0.017, mat=carbon, tint=cf, segs=8)
        ducted_fan(b, (mx, my, Z + 0.04), 0.165, armor, hull2, gun, gm2, glow, height=0.08, lip=0.024, segs=20, struts=2, hub_r=0.035,
                   hub_mat=gun, hub_tint=gm, glow_tint=hexc("#ff8a1c"))
        name = ("RotorF" if sy > 0 else "RotorR") + ("L" if sx < 0 else "R")
        rotors.append(rotor_part(name, (mx, my, Z + 0.078), 0.15, 2, carbon, cf, seed=40 + len(rotors), chord=0.045, hub_r=0.028))
eye = Part("Eye", origin=(0, 0.5, Z), seed=3)
eye.sphere(0.03, (0, 0.5, Z), mat=eyem, segs=12, rings=8)

decals = [
    Decal((0.0, 0.2, Z + 0.12), (0, 0, 1), (0, 1, 0), (0.13, 0.13), p_stripes(5, 0.5, 45.0, hexc("#1a1c1e")), depth=0.06, kinds=("plating",)),
    Decal((0.0, 0.0, Z + 0.118), (0, 0, 1), (0, 1, 0), (0.14, 0.2), p_glyphs(hexc("#c8cdbf"), cells=3, rows=3, seed=17), depth=0.05),
    Decal((0.0, -0.2, Z + 0.11), (0, 0, 1), (0, 1, 0), (0.12, 0.2), p_barcode(hexc("#c8cdbf"), 10, seed=4), depth=0.05),
]
for sx in (-1, 1):
    decals.append(Decal((sx * 0.121, 0.0, Z), (sx, 0, 0), (0, 1, 0), (0.5, 0.1), p_stripes(8, 0.5, 90.0, hexc("#1a1c1e")), depth=0.04, kinds=("plating",)))
rig = [light("EyeLight", (0, 0.58, Z), "omni", (1.0, 0.55, 0.12), 1.2, 4.5, attenuation=1.6, fade=(30, 12), group="eye"),
       light("Fill", (0, 0.05, Z + 0.8), "omni", (0.78, 0.84, 1.0), 0.9, 3.0, mask="own", attenuation=1.2, fade=(28, 12))]
print("  body tris", b.tri_count(), "rotors", sum(p.tri_count() for p in rotors))
export_model("drone_striker", [b] + rotors + [eye], extras=rig, groups={"atlas": dict(base="drone_striker", material="Hull")}, size=1024,
             decals=decals, ao_dist=0.15, ao_strength=0.8, emit_strength=1.8)
