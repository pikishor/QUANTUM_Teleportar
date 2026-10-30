"""Striker: loitering munition. Needle fuselage with an amber warhead band, four small ducted props and an amber seeker eye."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dronelib import ducted_fan, rotor_part  # noqa: E402
from helpers import (Part, bake_ao, empty, export_model, hexc, make_material, new_scene, paint, ring_se)  # noqa: E402

new_scene()
armor = make_material("Armor", tex="plating")
carbon = make_material("Carbon", tex="carbon")
gun = make_material("Gunmetal", tex="steel")
lens = make_material("Lens", color=(0.004, 0.006, 0.008), metallic=0.9, roughness=0.08, vcol=False)
glow = make_material("Glow", emit=hexc("#ff8a1c"), emit_strength=5.5, vcol=False)

hull = paint("plating", "#454840")
hull2 = paint("plating", "#2f322d")
band = paint("plating", "#c4731d")
cf = paint("carbon", "#585a5c")
gm = paint("steel", "#555a5e")
gm2 = paint("steel", "#2c3033")

Z = 0.82
b = Part("Body", seed=31)
rings = [ring_se(0, y, Z, r, r, 16, 2.0, plane="xz") for y, r in
         [(-0.45, 0.035), (-0.38, 0.07), (-0.2, 0.108), (0.0, 0.12), (0.12, 0.122), (0.3, 0.115), (0.4, 0.088), (0.47, 0.05), (0.505, 0.024)]]
b.loft(rings, mat=armor, tint=hull)
b.cyl(0.126, 0.13, (0, 0.2, Z), axis="y", mat=armor, tint=band, segs=18, bevel=0.004, sharp=60.0)      # warhead band
for y in (0.125, 0.275):
    b.cyl(0.128, 0.014, (0, y, Z), axis="y", mat=armor, tint=hull2, segs=18)
for k in range(4):
    import math
    a = math.radians(45 + 90 * k)
    c, s = math.cos(a), math.sin(a)
    b.box((0.012, 0.15, 0.16), (c * 0.1, -0.33, Z + s * 0.1), rot=(0, 0, 0), mat=armor, tint=hull2, bevel=0.003, frame=None)
b.torus(0.12, 0.011, (0, -0.4, Z), rot=(90, 0, 0), mat=carbon, tint=cf, segs=20, sides=6)                 # tail ring
b.cyl(0.062, 0.04, (0, -0.44, Z), axis="y", mat=gun, tint=gm2, segs=12)
b.cyl(0.043, 0.03, (0, 0.485, Z), axis="y", mat=lens, segs=12)
b.box((0.2, 0.3, 0.035), (0, -0.04, Z - 0.125), mat=gun, tint=gm2, bevel=0.008)                          # battery
b.box((0.06, 0.1, 0.02), (0, 0.14, Z + 0.128), mat=gun, tint=gm, bevel=0.004)                            # arming pod
b.box((0.012, 0.02, 0.012), (0, 0.14, Z + 0.142), mat=glow)
rotors = []
for sx in (-1, 1):
    for sy in (-1, 1):
        mx, my = 0.34 * sx, 0.26 * sy
        b.rod((0.1 * sx, 0.04 * sy, Z + 0.02), (mx, my, Z + 0.04), 0.017, mat=carbon, tint=cf, segs=8)
        ducted_fan(b, (mx, my, Z + 0.04), 0.165, carbon, cf, gun, gm2, glow, height=0.07, lip=0.016, segs=20, struts=2, hub_r=0.035, hub_mat=gun, hub_tint=gm)
        name = ("RotorF" if sy > 0 else "RotorR") + ("L" if sx < 0 else "R")
        rotors.append(rotor_part(name, (mx, my, Z + 0.078), 0.15, 2, carbon, cf, seed=40 + len(rotors), chord=0.045, hub_r=0.028))
eye = Part("Eye", origin=(0, 0.5, Z), seed=3)
eye.sphere(0.028, (0, 0.5, Z), mat=glow, segs=10, rings=7)
bake_ao([b], samples=14, dist=0.15, strength=0.6)
objs = [p.build() for p in [b] + rotors] + [eye.build()]
print("  body tris", b.tri_count(), "rotors", sum(p.tri_count() for p in rotors))
export_model("drone_striker", objs)
