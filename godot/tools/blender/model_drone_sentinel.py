"""Sentinel: a floating sensor-jelly of the Vael. Armoured bone-grey bell with glowing red ribs and an eye cluster (Eye), a stinger proboscis (Muzzle)
and a frill of trailing tendrils (the `Fins` node: the game pulses and turns it instead of spinning rotors). Body centre y = 0.95 m."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import (Part, empty, export_model, hexc, light, make_material, new_scene, ring_se, scale_c)  # noqa: E402

new_scene()
chit = make_material("Chitin", tex="chitin")
glow = make_material("Glow", tex="glow", color=hexc("#ff2038"))
eyem = make_material("Eye", emit=hexc("#ff2038"), emit_strength=2.0)

SHELL = scale_c(hexc("#5b5a5d"), 1.35)
SHELL2 = scale_c(hexc("#3d3c3f"), 1.7)
BONE = scale_c(hexc("#b3a78f"), 1.1)
FLESH = scale_c(hexc("#7a3338"), 1.5)

Z = 0.95
b = Part("Body", seed=11)
prof = [(0.36, 0.05), (0.31, 0.24), (0.21, 0.41), (0.09, 0.51), (-0.01, 0.55), (-0.09, 0.5), (-0.04, 0.38), (0.03, 0.22), (0.06, 0.06)]
b.loft([ring_se(0, 0, Z + dz, r, r, 20, 2.0, plane="xy") for dz, r in prof], mat=chit, tint=SHELL)
b.loft([ring_se(0, 0, Z + dz, r, r, 20, 2.0, plane="xy") for dz, r in [(-0.07, 0.505), (-0.1, 0.49), (-0.105, 0.43)]], mat=chit, tint=SHELL2)   # rim lip
for k in range(8):                                                                                                  # armour ribs and the glowing veins between them
    a = 2 * math.pi * k / 8
    ca, sa = math.cos(a), math.sin(a)
    rib = [(r * 1.03 * ca, r * 1.03 * sa, Z + dz + 0.012) for dz, r in prof[1:5]]
    b.tube([(0.05 * ca, 0.05 * sa, Z + 0.365)] + rib, [(0.016, 0.016)] * 5, mat=chit, tint=BONE, n=5, sub=1, up=(-sa, ca, 0))
    a2 = a + math.pi / 8
    ca, sa = math.cos(a2), math.sin(a2)
    vein = [(r * 1.015 * ca, r * 1.015 * sa, Z + dz + 0.006) for dz, r in prof[1:5]]
    b.tube(vein, [(0.008, 0.008)] * 4, mat=glow, n=4, sub=1, up=(-sa, ca, 0))
b.sphere(0.07, (0, 0, Z + 0.36), mat=glow, segs=8, rings=6)                                                         # crown node
# eye cluster on the forward underside: bone sockets, small baked eyes (the big ones are the Eye node)
b.torus(0.088, 0.02, (0, 0.44, Z - 0.06), rot=(90, 0, 0), mat=chit, tint=BONE, segs=14, sides=6)
for sx in (-1, 1):
    b.torus(0.05, 0.014, (sx * 0.17, 0.4, Z - 0.04), rot=(80, 0, 0), mat=chit, tint=BONE, segs=10, sides=5)
    b.sphere(0.022, (sx * 0.1, 0.47, Z + 0.07), mat=glow, segs=7, rings=5)
    b.sphere(0.017, (sx * 0.2, 0.37, Z + 0.1), mat=glow, segs=7, rings=5)
b.tube([(0, 0.3, Z - 0.14), (0, 0.46, Z - 0.2), (0, 0.62, Z - 0.22)], [(0.04, 0.04), (0.03, 0.03), (0.012, 0.012)], mat=chit, tint=FLESH, n=8, sub=1)   # stinger proboscis
b.sphere(0.016, (0, 0.63, Z - 0.22), mat=glow, segs=7, rings=5)
for sx in (-1, 1):                                                                                                  # sensory whiskers
    b.tube([(sx * 0.25, 0.3, Z + 0.2), (sx * 0.4, 0.45, Z + 0.4), (sx * 0.5, 0.45, Z + 0.62)], [(0.008, 0.008), (0.006, 0.006), (0.002, 0.002)], mat=chit, tint=BONE, n=4, sub=1)
    b.sphere(0.014, (sx * 0.5, 0.45, Z + 0.62), mat=glow, segs=6, rings=4)

# Fins: the pulsing frill and the trailing tendrils (origin on the vertical axis through the body centre, the game turns it about Y)
fins = Part("Fins", origin=(0, 0, Z), seed=13)
fins.tag(vis_end=60.0, no_shadow=1)
for k in range(16):
    a = 2 * math.pi * k / 16
    ca, sa = math.cos(a), math.sin(a)
    fins.bar((0.5 * ca, 0.5 * sa, Z - 0.07), (0.78 * ca, 0.78 * sa, Z - 0.16 - 0.03 * (k % 2)), 0.07, 0.008, mat=chit, tint=FLESH if k % 2 else SHELL2, up=(0, 0, 1), taper=(0.2, 1.0))
for k in range(8):
    a = 2 * math.pi * k / 8 + 0.2
    ca, sa = math.cos(a), math.sin(a)
    path = []
    for j, (r, dz) in enumerate([(0.44, -0.1), (0.5, -0.3), (0.43, -0.5), (0.52, -0.66), (0.46, -0.78)]):
        w = 0.05 * math.sin(k * 1.7 + j * 1.3)
        path.append(((r + w) * ca - w * sa, (r + w) * sa + w * ca, Z + dz))
    fins.tube(path, [(0.02, 0.02), (0.017, 0.017), (0.013, 0.013), (0.009, 0.009), (0.004, 0.004)], mat=chit, tint=FLESH, n=5, sub=1)
    fins.sphere(0.017, path[-1], mat=glow, segs=6, rings=4)
eye = Part("Eye", origin=(0, 0.44, Z - 0.06), seed=3)
eye.sphere(0.07, (0, 0.445, Z - 0.06), mat=eyem, segs=12, rings=8)
for sx in (-1, 1):
    eye.sphere(0.035, (sx * 0.17, 0.41, Z - 0.04), mat=eyem, segs=10, rings=6)

rig = [empty("Muzzle", (0, 0.64, Z - 0.22)),
       light("EyeLight", (0, 0.72, Z - 0.06), "omni", (1.0, 0.18, 0.2), 1.4, 5.0, attenuation=1.6, fade=(32, 12), group="eye"),
       light("Fill", (0, 0.1, Z + 0.85), "omni", (0.9, 0.7, 0.75), 1.0, 3.4, mask="own", attenuation=1.2, fade=(30, 12))]
print("  body tris", b.tri_count(), "fins", fins.tri_count())
export_model("drone_sentinel", [b, fins, eye], extras=rig, groups={"atlas": dict(base="drone_sentinel", material="Hull")}, size=1024, decals=[],
             ao_dist=0.2, ao_strength=0.6, emit_strength=1.8)
