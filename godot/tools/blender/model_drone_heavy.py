"""Heavy: an armoured beetle gunship of the Vael. Domed elytra with ribbed plates, a horned head with an eye cluster (Eye), folded legs, a violet bio-cannon
under the chin (Muzzle) and a skirt of hover cilia (the `Fins` node, turned and pulsed by the game). Body centre y = 1.40 m, front +Y (-Z in Godot)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import (Part, empty, export_model, hexc, light, make_material, new_scene, ring_se, scale_c)  # noqa: E402

new_scene()
chit = make_material("Chitin", tex="chitin")
glow = make_material("Glow", tex="glow", color=hexc("#b45cff"))
eyem = make_material("Eye", emit=hexc("#c070ff"), emit_strength=2.0)

SHELL = scale_c(hexc("#4f4d55"), 1.35)
SHELL2 = scale_c(hexc("#35333b"), 1.7)
BONE = scale_c(hexc("#a69fb0"), 1.1)
FLESH = scale_c(hexc("#59385f"), 1.6)

Z = 1.4
b = Part("Body", seed=51)
ely = [(-1.1, Z + 0.05, 0.2, 0.15), (-0.8, Z + 0.15, 0.6, 0.42), (-0.3, Z + 0.2, 0.78, 0.52), (0.2, Z + 0.15, 0.74, 0.5), (0.65, Z + 0.05, 0.55, 0.38),
       (0.95, Z - 0.05, 0.3, 0.25), (1.1, Z - 0.1, 0.08, 0.1)]
b.loft([ring_se(0, y, zc, rx, rz, 18, 2.2, plane="xz") for y, zc, rx, rz in ely], mat=chit, tint=SHELL)
b.loft([ring_se(0, y, zc - 0.28, rx * 0.92, rz * 0.6, 14, 2.2, plane="xz") for y, zc, rx, rz in ely[1:6]], mat=chit, tint=FLESH)      # soft underbelly
for y0 in (-0.7, -0.35, 0.0, 0.35):                                                                                 # arched rib plates across the elytra
    zc = Z + 0.18
    rx, rz = 0.78 - 0.1 * abs(y0), 0.54 - 0.06 * abs(y0)
    arc = [(rx * 1.02 * math.cos(math.radians(t)), y0, zc + rz * 1.02 * math.sin(math.radians(t))) for t in range(0, 181, 30)]
    b.tube(arc, [(0.03, 0.03)] * len(arc), mat=chit, tint=BONE, n=5, sub=1, up=(0, 1, 0))
    arc2 = [(rx * 1.0 * math.cos(math.radians(t)), y0 + 0.17, zc + rz * 1.0 * math.sin(math.radians(t))) for t in range(10, 171, 40)]
    b.tube(arc2, [(0.011, 0.011)] * len(arc2), mat=glow, n=4, sub=1, up=(0, 1, 0))                                  # violet seam between the plates
b.tube([(0, -0.95, Z + 0.15), (0, -0.5, Z + 0.7), (0, 0.0, Z + 0.72), (0, 0.5, Z + 0.55)], [(0.012, 0.012)] * 4, mat=glow, n=4, sub=2, up=(1, 0, 0))   # elytra split line
for sx in (-1, 1):                                                                                                  # gill vents on the flanks
    for k in range(5):
        b.box((0.012, 0.16, 0.022), (sx * (0.74 - 0.02 * k), -0.1 - 0.16 * k + 0.5, Z - 0.02 + 0.03 * k - 0.1), rot=(0, 0, -sx * 12), mat=glow)
# head: horned, with a sensor-eye cluster
b.loft([ring_se(0, y, zc, rx, rz, 12, 2.2, plane="xz") for y, zc, rx, rz in [(0.7, Z + 0.0, 0.3, 0.26), (0.95, Z + 0.0, 0.3, 0.26), (1.12, Z - 0.02, 0.2, 0.2), (1.2, Z - 0.04, 0.08, 0.09)]],
       mat=chit, tint=SHELL2)
b.tube([(0, 0.95, Z + 0.15), (0, 1.3, Z + 0.15), (0, 1.55, Z + 0.4)], [(0.1, 0.08), (0.07, 0.07), (0.016, 0.016)], mat=chit, tint=BONE, n=8, sub=2)   # horn
for sx in (-1, 1):
    b.tube([(sx * 0.18, 1.05, Z - 0.12), (sx * 0.3, 1.38, Z - 0.18), (sx * 0.12, 1.55, Z - 0.2)], [(0.05, 0.05), (0.035, 0.035), (0.01, 0.01)], mat=chit, tint=BONE, n=6, sub=2)   # mandibles
    b.torus(0.055, 0.016, (sx * 0.12, 1.17, Z + 0.1), rot=(80, 0, 0), mat=chit, tint=BONE, segs=10, sides=5)
    b.torus(0.04, 0.012, (sx * 0.23, 1.06, Z + 0.17), rot=(70, 0, 0), mat=chit, tint=BONE, segs=10, sides=5)
    b.sphere(0.02, (sx * 0.2, 1.1, Z + 0.22), mat=glow, segs=6, rings=4)
# bio-cannon under the chin
b.tube([(0, 0.4, Z - 0.34), (0, 0.9, Z - 0.38), (0, 1.38, Z - 0.37)], [(0.2, 0.17), (0.15, 0.13), (0.11, 0.1)], mat=chit, tint=FLESH, n=10, sub=2)
for y in (0.7, 0.95, 1.2):
    b.torus(0.15 - 0.2 * (y - 0.7) * 0.2, 0.022, (0, y, Z - 0.37), rot=(90, 0, 0), mat=chit, tint=SHELL2, segs=14, sides=5)
b.torus(0.105, 0.03, (0, 1.4, Z - 0.37), rot=(90, 0, 0), mat=glow, segs=14, sides=5)
b.sphere(0.07, (0, 1.36, Z - 0.37), mat=glow, segs=8, rings=6)
for sx in (-1, 1):                                                                                                  # six folded legs
    for yy in (-0.55, 0.0, 0.5):
        k = 1.0 if yy != 0.0 else 1.15
        a = (sx * 0.5, yy, Z - 0.15)
        m = (sx * 0.9 * k, yy + 0.1, Z - 0.35)
        t = (sx * 0.8 * k, yy + 0.25, Z - 0.92)
        b.rod(a, m, 0.05, mat=chit, tint=SHELL2, r2=0.04, segs=6)
        b.rod(m, t, 0.04, mat=chit, tint=BONE, r2=0.008, segs=6)

fins = Part("Fins", origin=(0, 0, Z), seed=53)
fins.tag(vis_end=60.0, no_shadow=1)
for k in range(16):                                                                                                 # skirt of hover cilia under the belly
    a = 2 * math.pi * k / 16
    ca, sa = math.cos(a), math.sin(a)
    r0, r1 = 0.55, 0.95 + 0.06 * (k % 2)
    fins.bar((r0 * ca, r0 * sa * 1.1, Z - 0.5), (r1 * ca, r1 * sa * 1.2, Z - 0.66), 0.12, 0.01, mat=chit, tint=FLESH if k % 2 else SHELL2, up=(0, 0, 1), taper=(0.25, 1.0))
    fins.sphere(0.02, (r1 * ca, r1 * sa * 1.2, Z - 0.66), mat=glow, segs=6, rings=4)
eye = Part("Eye", origin=(0, 1.15, Z + 0.1), seed=3)
for sx in (-1, 1):
    eye.sphere(0.058, (sx * 0.12, 1.19, Z + 0.1), mat=eyem, segs=10, rings=7)
    eye.sphere(0.04, (sx * 0.23, 1.09, Z + 0.17), mat=eyem, segs=9, rings=6)
eye.sphere(0.04, (0, 1.2, Z + 0.17), mat=eyem, segs=9, rings=6)

rig = [empty("Muzzle", (0, 1.45, Z - 0.37)),
       light("EyeLight", (0, 1.3, Z + 0.1), "omni", (0.75, 0.35, 1.0), 1.6, 6.5, attenuation=1.6, fade=(34, 14), group="eye"),
       light("Fill", (0, 0.1, Z + 1.1), "omni", (0.85, 0.8, 1.0), 1.2, 5.2, mask="own", attenuation=1.2, fade=(32, 14))]
print("  body tris", b.tri_count(), "fins", fins.tri_count())
export_model("drone_heavy", [b, fins, eye], extras=rig, groups={"atlas": dict(base="drone_heavy", material="Hull")}, size=1024, decals=[],
             ao_dist=0.25, ao_strength=0.6, emit_strength=1.8)
