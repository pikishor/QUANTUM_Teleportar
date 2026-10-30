"""Sentinel: quad-rotor surveillance drone with a chin gimbal camera (red Eye)."""
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
glow = make_material("Glow", emit=hexc("#ff2038"), emit_strength=5.0, vcol=False)

hull = paint("plating", "#4a5057")
hull2 = paint("plating", "#383d43")
cf = paint("carbon", "#5a5e63")
gm = paint("steel", "#555c63")
gm2 = paint("steel", "#2d3237")

Z = 0.95
b = Part("Body", seed=11)
rings = [ring_se(0, y, zc + 0.0, rx, rz, 16, 3.0, plane="xz") for y, rx, rz, zc in
         [(-0.36, 0.10, 0.075, Z), (-0.24, 0.17, 0.115, Z + 0.01), (-0.05, 0.235, 0.15, Z + 0.015), (0.15, 0.225, 0.14, Z + 0.005),
          (0.30, 0.17, 0.11, Z - 0.015), (0.385, 0.085, 0.065, Z - 0.03)]]
b.loft(rings, mat=armor, tint=hull)
b.box((0.27, 0.36, 0.028), (0, -0.04, Z + 0.158), mat=armor, tint=hull2, bevel=0.012, bsegs=2, top=(0.9, 0.9))
for y in (-0.2, -0.14, -0.08, -0.02, 0.04):
    b.box((0.2, 0.025, 0.012), (0, y, Z + 0.176), mat=gun, tint=gm2)
b.box((0.3, 0.2, 0.06), (0, -0.05, Z - 0.16), mat=armor, tint=hull2, bevel=0.012, bsegs=2)       # battery
b.box((0.18, 0.1, 0.03), (0, -0.2, Z - 0.12), mat=gun, tint=gm2, bevel=0.006)
b.rod((0.08, -0.2, Z + 0.17), (0.12, -0.3, Z + 0.4), 0.004, mat=gun, tint=gm, segs=5)
b.rod((-0.08, -0.2, Z + 0.17), (-0.13, -0.28, Z + 0.34), 0.004, mat=gun, tint=gm, segs=5)
b.sphere(0.04, (0, 0.05, Z + 0.18), mat=gun, tint=gm2, scale=(1, 1, 0.7), segs=10, rings=6)     # top sensor dome
# gimbal camera under the nose
b.bar((0.0, 0.28, Z - 0.05), (0.0, 0.33, Z - 0.13), 0.05, 0.05, mat=gun, tint=gm2, bevel=0.004)
b.sphere(0.092, (0, 0.34, Z - 0.17), mat=gun, tint=gm, segs=16, rings=10)
b.torus(0.108, 0.0085, (0, 0.34, Z - 0.17), rot=(0, 90, 0), mat=armor, tint=hull, segs=20, sides=6)
b.cyl(0.05, 0.05, (0, 0.425, Z - 0.17), axis="y", mat=gun, tint=gm2, segs=14, bevel=0.004)
b.cyl(0.036, 0.012, (0, 0.452, Z - 0.17), axis="y", mat=lens, segs=14)
b.box((0.012, 0.012, 0.012), (0.0, 0.2, Z - 0.012), mat=glow)
b.box((0.02, 0.01, 0.01), (0.0, -0.37, Z + 0.01), mat=glow)                                       # tail light
# arms, ducts, rotors
rotors = []
for sx in (-1, 1):
    for sy in (-1, 1):
        mx, my = 0.5 * sx, 0.46 * sy
        b.rod((0.16 * sx, 0.1 * sy, Z + 0.02), (mx, my, Z + 0.05), 0.024, mat=carbon, tint=cf, segs=8)
        b.box((0.07, 0.07, 0.03), (0.2 * sx, 0.12 * sy, Z + 0.015), mat=armor, tint=hull, bevel=0.008)
        ducted_fan(b, (mx, my, Z + 0.05), 0.255, carbon, cf, gun, gm2, glow, hub_mat=gun, hub_tint=gm)
        name = ("RotorF" if sy > 0 else "RotorR") + ("L" if sx < 0 else "R")
        rotors.append(rotor_part(name, (mx, my, Z + 0.1), 0.235, 3, carbon, cf, seed=20 + len(rotors)))

eye = Part("Eye", origin=(0, 0.462, Z - 0.17), seed=3)
eye.sphere(0.021, (0, 0.462, Z - 0.17), mat=glow, segs=10, rings=7)

parts = [b] + rotors
bake_ao([b], samples=14, dist=0.2, strength=0.6)
objs = [p.build() for p in parts] + [eye.build(), empty("Muzzle", (0, 0.46, Z - 0.17))]
print("  body tris", b.tri_count(), "rotors", sum(p.tri_count() for p in rotors))
export_model("drone_sentinel", objs)
