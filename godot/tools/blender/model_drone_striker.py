"""Striker: a spiked living bomb of the Vael. Ribbed amber-seamed pod, a curled stinger tail, one big amber eye (Eye) and a ring of thorns (the `Fins`
node, spins about the long axis and flares before the burst). Body centre y = 0.82 m, front +Y (-Z in Godot)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import (Part, export_model, hexc, light, make_material, new_scene, ring_se, scale_c)  # noqa: E402

new_scene()
chit = make_material("Chitin", tex="chitin")
glow = make_material("Glow", tex="glow", color=hexc("#ff8a1c"))
eyem = make_material("Eye", emit=hexc("#ff8a1c"), emit_strength=2.0)

SHELL = scale_c(hexc("#5a5650"), 1.35)
SHELL2 = scale_c(hexc("#3b3834"), 1.7)
BONE = scale_c(hexc("#c2b190"), 1.1)
FLESH = scale_c(hexc("#8a4a2a"), 1.4)

Z = 0.82
b = Part("Body", seed=31)
pod = [(-0.52, 0.02), (-0.44, 0.12), (-0.26, 0.24), (0.0, 0.31), (0.2, 0.3), (0.36, 0.22), (0.46, 0.11), (0.5, 0.04)]
b.loft([ring_se(0, y, Z, r, r * 0.95, 16, 2.0, plane="xz") for y, r in pod], mat=chit, tint=SHELL)
for y, r in [(-0.12, 0.312), (0.08, 0.318), (0.27, 0.275)]:                                                         # armoured bands with glowing seams
    b.torus(r, 0.02, (0, y, Z), rot=(90, 0, 0), mat=chit, tint=BONE, segs=18, sides=5)
    b.torus(r * 0.985, 0.007, (0, y + 0.03, Z), rot=(90, 0, 0), mat=glow, segs=18, sides=4)
for k in range(10):                                                                                                 # bulging amber pustules
    a = k * 2.4 + 0.5
    y = -0.3 + 0.07 * (k % 7)
    r = 0.3 if abs(y) < 0.25 else 0.2
    b.sphere(0.034, (r * 0.93 * math.cos(a), y, Z + r * 0.9 * math.sin(a)), mat=glow, segs=7, rings=5)
for sx in (-1, 1):
    b.torus(0.05, 0.014, (sx * 0.12, 0.43, Z + 0.07), rot=(70, 0, 0), mat=chit, tint=BONE, segs=10, sides=5)
    b.sphere(0.02, (sx * 0.12, 0.44, Z + 0.07), mat=glow, segs=7, rings=5)
b.tube([(0, -0.44, Z), (0, -0.62, Z + 0.08), (0, -0.74, Z + 0.26), (0, -0.66, Z + 0.45)], [(0.07, 0.07), (0.05, 0.05), (0.035, 0.035), (0.006, 0.006)],
       mat=chit, tint=SHELL2, n=8, sub=2)                                                                          # curled stinger tail
b.sphere(0.03, (0, -0.7, Z + 0.4), mat=glow, segs=7, rings=5)
for k in range(5):                                                                                                  # rear thrust gills
    b.rod((0.0, -0.4, Z - 0.1 + 0.05 * k), (0.0, -0.58, Z - 0.12 + 0.05 * k), 0.012, mat=glow, segs=4)

fins = Part("Fins", origin=(0, 0.05, Z), seed=33)
fins.tag(vis_end=60.0, no_shadow=1)
for k in range(10):                                                                                                 # equatorial thorn ring, thorns radial about the long axis
    a = 2 * math.pi * k / 10
    ca, sa = math.cos(a), math.sin(a)
    L = 0.62 + 0.08 * (k % 2)
    fins.rod((0.24 * ca, 0.05 + 0.02 * (k % 2), Z + 0.24 * sa), (L * ca, 0.0 - 0.1 + 0.04 * (k % 2), Z + L * sa), 0.036, mat=chit, tint=BONE if k % 2 else SHELL2, r2=0.003, segs=6)
fins.torus(0.27, 0.02, (0, 0.05, Z), rot=(90, 0, 0), mat=chit, tint=SHELL2, segs=18, sides=5)
eye = Part("Eye", origin=(0, 0.46, Z), seed=3)
eye.sphere(0.065, (0, 0.46, Z + 0.0), mat=eyem, segs=12, rings=8, scale=(1.0, 0.8, 1.2))

rig = [light("EyeLight", (0, 0.58, Z), "omni", (1.0, 0.55, 0.12), 1.2, 4.5, attenuation=1.6, fade=(30, 12), group="eye"),
       light("Fill", (0, 0.05, Z + 0.8), "omni", (1.0, 0.85, 0.7), 0.9, 3.0, mask="own", attenuation=1.2, fade=(28, 12))]
print("  body tris", b.tri_count(), "fins", fins.tri_count())
export_model("drone_striker", [b, fins, eye], extras=rig, groups={"atlas": dict(base="drone_striker", material="Hull")}, size=1024, decals=[],
             ao_dist=0.15, ao_strength=0.6, emit_strength=1.8)
