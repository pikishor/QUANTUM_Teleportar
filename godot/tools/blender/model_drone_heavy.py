"""Heavy: armoured gunship drone. Angular hull, four large ducted fans, chin turret with twin barrels, red optic bar (Eye)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dronelib import ducted_fan, rotor_part  # noqa: E402
from helpers import (Part, bake_ao, empty, export_model, hexc, make_material, new_scene, paint, ring_se)  # noqa: E402

new_scene()
armor = make_material("Armor", tex="plating")
carbon = make_material("Carbon", tex="carbon")
gun = make_material("Gunmetal", tex="steel")
glow = make_material("Glow", emit=hexc("#ff2a55"), emit_strength=5.0, vcol=False)
ring_glow = make_material("HoverGlow", emit=hexc("#b35cff"), emit_strength=4.0, vcol=False)

hull = paint("plating", "#3f434b")
hull2 = paint("plating", "#2d3037")
plate = paint("plating", "#575c66")
cf = paint("carbon", "#55585d")
gm = paint("steel", "#555a60")
gm2 = paint("steel", "#2b2e33")
lens_t = paint("steel", "#0b0c0e")

Z = 1.4
b = Part("Body", seed=51)
rings = [ring_se(0, y, Z + dz, rx, rz, 14, 3.4, plane="xz") for y, rx, rz, dz in
         [(-0.95, 0.30, 0.20, 0.0), (-0.6, 0.50, 0.31, 0.0), (-0.1, 0.62, 0.38, 0.02), (0.4, 0.56, 0.34, 0.0), (0.82, 0.38, 0.27, -0.04), (1.0, 0.22, 0.19, -0.06)]]
b.loft(rings, mat=armor, tint=hull)
# armour plates
b.box((0.95, 1.25, 0.07), (0, -0.08, Z + 0.4), mat=armor, tint=plate, bevel=0.02, bsegs=2, top=(0.82, 0.85))
b.box((0.55, 0.5, 0.08), (0, 0.78, Z + 0.17), mat=armor, tint=plate, bevel=0.02, bsegs=2, top=(0.7, 0.55))
b.box((0.2, 0.9, 0.18), (0.58, 0.1, Z + 0.02), mat=armor, tint=hull2, bevel=0.02, bsegs=2, mirror=True)
b.box((0.04, 0.8, 0.24), (0.66, 0.1, Z - 0.02), mat=armor, tint=plate, bevel=0.012, mirror=True)
b.box((0.5, 0.3, 0.14), (0, -0.88, Z + 0.1), mat=armor, tint=hull2, bevel=0.02, bsegs=2)
for x in (-0.18, -0.09, 0.0, 0.09, 0.18):
    b.box((0.03, 0.4, 0.2), (x, -0.88, Z + 0.22), mat=gun, tint=gm2, bevel=0.004)                       # heat-sink fins
for y in (-0.5, -0.4, -0.3, -0.2, -0.1):
    b.box((0.4, 0.045, 0.012), (0, y, Z + 0.44), mat=gun, tint=gm2)
b.rod((0.3, -0.7, Z + 0.4), (0.36, -0.9, Z + 0.95), 0.007, mat=gun, tint=gm, segs=5)
b.rod((-0.3, -0.7, Z + 0.4), (-0.34, -0.85, Z + 0.8), 0.007, mat=gun, tint=gm, segs=5)
b.sphere(0.07, (0, 0.3, Z + 0.43), mat=gun, tint=gm2, scale=(1, 1, 0.65), segs=10, rings=6)
# chin turret with twin barrels
b.box((0.34, 0.42, 0.1), (0, 0.62, Z - 0.3), mat=armor, tint=hull2, bevel=0.02, bsegs=2)
b.sphere(0.15, (0, 0.78, Z - 0.37), mat=gun, tint=gm, segs=12, rings=8)
for x in (-0.07, 0.07):
    b.cyl(0.024, 0.62, (x, 1.1, Z - 0.37), axis="y", mat=gun, tint=gm2, segs=8, bevel=0.002)
    b.cyl(0.036, 0.2, (x, 1.22, Z - 0.37), axis="y", mat=gun, tint=gm, segs=10)
    b.cyl(0.04, 0.03, (x, 1.335, Z - 0.37), axis="y", mat=gun, tint=gm2, segs=10)
b.box((0.2, 0.3, 0.12), (0, 0.9, Z - 0.34), mat=armor, tint=plate, bevel=0.015, top=(0.9, 0.9))
# optic bar + lenses on the nose
b.box((0.5, 0.06, 0.12), (0, 0.985, Z + 0.02), mat=gun, tint=gm2, bevel=0.012)
for x in (-0.18, 0.0, 0.18):
    b.cyl(0.036, 0.03, (x, 1.022, Z + 0.02), axis="y", mat=gun, tint=lens_t, segs=12)
b.box((0.3, 0.02, 0.02), (0, 1.03, Z - 0.1), mat=glow)
b.box((0.04, 0.02, 0.1), (0.3, 0.99, Z + 0.02), mat=glow, mirror=True)
# arms + ducted fans
rotors = []
for sx in (-1, 1):
    for sy in (-1, 1):
        mx, my = 1.0 * sx, 0.78 * sy
        b.bar((0.45 * sx, 0.18 * sy, Z + 0.05), (mx * 0.94, my * 0.94, Z + 0.1), 0.16, 0.1, mat=armor, tint=hull2, bevel=0.02, bsegs=2)
        b.box((0.2, 0.2, 0.12), (0.7 * sx, 0.4 * sy, Z + 0.07), mat=armor, tint=plate, bevel=0.02)
        ducted_fan(b, (mx, my, Z + 0.1), 0.42, carbon, cf, gun, gm2, ring_glow, height=0.14, lip=0.03, segs=18, struts=3, hub_r=0.09, hub_mat=gun, hub_tint=gm)
        name = ("RotorF" if sy > 0 else "RotorR") + ("L" if sx < 0 else "R")
        rotors.append(rotor_part(name, (mx, my, Z + 0.18), 0.385, 3, carbon, cf, seed=60 + len(rotors), chord=0.085, hub_r=0.07, thickness=0.01))
eye = Part("Eye", origin=(0, 1.04, Z + 0.02), seed=3)
eye.box((0.4, 0.012, 0.03), (0, 1.045, Z + 0.065), mat=glow)
bake_ao([b], samples=14, dist=0.3, strength=0.6)
objs = [p.build() for p in [b] + rotors] + [eye.build(), empty("Muzzle", (0, 1.36, Z - 0.37))]
print("  body tris", b.tri_count(), "rotors", sum(p.tri_count() for p in rotors))
export_model("drone_heavy", objs)
