"""Hover car (4.6 x 2.0 x 1.15 m): a flat manta hull on four glowing hover pads, a glass canopy, a dorsal fin and twin rear plasma nozzles, glowing seam lines along the flanks.
No wheels (the game bobs the model). The underside of the hull sits at HOVER_H = 0.55 m above the ground, the pads hang to 0.36 m. Body = paint (recoloured by the game),
Details = canopy glass, intakes, chitin pods, glow trim; Headlights / Taillights / Underglow are the usual flat lamp surfaces. Front = +Y in Blender (-Z in Godot)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import add_glow, glow_beam, glow_disc, glow_ellipse  # noqa: E402
from helpers import Part, export_model, hexc, make_material, new_scene, ring_se  # noqa: E402
from lodlib import make_lod1, tri_count  # noqa: E402
from vehlib import glow_mat, lamp_rig  # noqa: E402

NAME = "car_hover"
HOVER_H = 0.55
UG = "#18ffd0"

new_scene()
body = make_material("Body", tex="paint", color=hexc("#4a86a6"))
glass = make_material("Glass", tex="glass", color=(0.012, 0.02, 0.026))
trim = make_material("Trim", tex="rubber")
chrome = make_material("Chrome", tex="steel")
chit = make_material("Chitin", tex="chitin")
head = make_material("Headlights", emit=hexc("#d8f6ff"), emit_strength=3.0)
tail = make_material("Taillights", emit=hexc("#ff1020"), emit_strength=2.6)
under = make_material("Underglow", emit=hexc(UG), emit_strength=2.0)
glow = glow_mat(UG)
T_black, T_dark = hexc("#1b1d1f"), hexc("#2c3033")
T_chit, T_bone = hexc("#262b33"), hexc("#8b8a8e")
GL = (0.012, 0.02, 0.026)

P = Part("Body", seed=61)


def ring(y, zc, rx, rz, n=16, exp=2.7):
    return ring_se(0, y, zc, rx, rz, n, exp, plane="xz")


# ---- hull: a flat manta, belly at HOVER_H
hull = [(-2.30, 0.74, 0.40, 0.12), (-2.05, 0.77, 0.80, 0.21), (-1.5, 0.78, 0.96, 0.23), (-0.5, 0.77, 1.0, 0.22), (0.6, 0.75, 0.96, 0.20),
        (1.5, 0.70, 0.78, 0.15), (2.1, 0.65, 0.45, 0.10), (2.3, 0.62, 0.15, 0.06)]
P.loft([ring(*h) for h in hull], mat=body, caps=(True, True), sharp=89.0)
# ---- canopy: glass in front, painted roof behind it
P.loft([ring(-0.2, 0.93, 0.62, 0.14), ring(0.0, 0.96, 0.70, 0.19), ring(0.55, 0.93, 0.6, 0.15), ring(1.05, 0.88, 0.42, 0.07)], mat=glass, tint=GL, caps=(True, True), sharp=89.0)
P.loft([ring(-1.5, 0.88, 0.45, 0.04), ring(-1.1, 0.93, 0.62, 0.11), ring(-0.6, 0.96, 0.69, 0.17), ring(-0.2, 0.93, 0.62, 0.14)], mat=body, caps=(True, True), sharp=89.0)
# ---- dorsal fin and tail fins
P.box((0.04, 1.1, 0.34), (0, -1.55, 1.05), mat=body, bevel=0.012, rot=(-10, 0, 0), top=(1.0, 0.45))
for sx in (1, -1):
    P.box((0.035, 0.85, 0.42), (sx * 0.62, -1.85, 1.0), mat=body, bevel=0.01, rot=(-8, 0, sx * 12), top=(1.0, 0.5))
    P.box((0.02, 0.86, 0.02), (sx * 0.64, -1.85, 1.2), mat=glow)
# ---- side sponsons with the hover pads
for sx in (1, -1):
    for yy in (1.3, -1.35):
        x = sx * 0.72
        P.box((0.3, 0.7, 0.16), (x, yy, 0.58), mat=chit, tint=T_chit, bevel=0.03, bsegs=2, top=(0.9, 0.95))                  # pod
        P.torus(0.26, 0.03, (x, yy, 0.42), mat=chit, tint=T_bone, segs=22, sides=5)                                           # pad ring
        P.cyl(0.24, 0.025, (x, yy, 0.39), mat=glow, segs=18)                                                                   # the glowing pad
        P.torus(0.26, 0.011, (x, yy, 0.455), mat=glow, segs=22, sides=4)
        for k in range(6):                                                                                                     # cilia around the pad
            a = math.pi * 2 * k / 6
            P.bar((x + 0.26 * math.cos(a), yy + 0.26 * math.sin(a), 0.43), (x + 0.34 * math.cos(a), yy + 0.34 * math.sin(a), 0.37), 0.04, 0.008,
                  mat=chit, tint=T_bone, taper=(1.0, 0.3))
# ---- glowing seam lines (Vael script) along the flanks, over the hood and the roof
for sx in (1, -1):
    P.rod((sx * 0.99, 1.1, 0.71), (sx * 1.01, -0.2, 0.77), 0.012, mat=glow, segs=5)
    P.rod((sx * 1.01, -0.2, 0.77), (sx * 0.96, -1.7, 0.78), 0.012, mat=glow, segs=5)
    P.rod((sx * 0.36, 1.45, 0.78), (sx * 0.4, 0.5, 0.86), 0.01, mat=glow, segs=5)
P.rod((0, -0.9, 1.1), (0, -1.45, 0.95), 0.01, mat=glow, segs=5)
# ---- nose: intake, eyes
P.box((0.8, 0.09, 0.07), (0, 2.18, 0.7), mat=trim, tint=T_black, bevel=0.012, top=(0.9, 0.9))
for sx in (1, -1):
    P.box((0.34, 0.07, 0.06), (sx * 0.5, 2.0, 0.78), mat=head, bevel=0.012, rot=(0, 0, -sx * 18), mirror=False)
    P.box((0.4, 0.09, 0.09), (sx * 0.5, 1.99, 0.78), mat=trim, tint=T_black, bevel=0.015, rot=(0, 0, -sx * 18))
# ---- rear: tail light bar, plasma nozzles
P.box((1.3, 0.04, 0.05), (0, -2.1, 0.86), mat=tail, bevel=0.008)
P.box((1.34, 0.07, 0.085), (0, -2.095, 0.86), mat=trim, tint=T_black, bevel=0.012)
for sx in (1, -1):
    P.cyl(0.13, 0.34, (sx * 0.42, -2.18, 0.72), axis="y", mat=chrome, tint=hexc("#4a4f55"), segs=14, bevel=0.004)
    P.cyl(0.095, 0.02, (sx * 0.42, -2.36, 0.72), axis="y", mat=glow, segs=12)
# ---- underglow strip under the hull
P.box((1.2, 2.8, 0.012), (0, 0, 0.5), mat=under)

wheels = []
items = []
for sx in (1, -1):
    items.append(("Headlights", *glow_disc((sx * 0.5, 2.05, 0.78), (1, 0, 0), (0, 0, 1), 0.4, 0.17, 0.30)))
    items.append(("Headlights", *glow_beam(sx * 0.5, 2.1, 0.03, 7.0, 0.7, 2.4, 0.18)))
    items.append(("Taillights", *glow_disc((sx * 0.5, -2.16, 0.86), (1, 0, 0), (0, 0, 1), 0.34, 0.14, 0.30)))
items.append(("Taillights", *glow_beam(0.0, -2.4, 0.03, 2.6, 1.6, 2.6, 0.2, direction=-1.0)))
items.append(("Underglow", *glow_ellipse((0.0, 0.0, 0.03), 1.9, 3.1, [(0.0, 0.3), (0.55, 0.5), (0.78, 0.26), (1.0, 0.0)])))


def finalize(parts_, objs_, extras_):
    lod = make_lod1(parts_[0].obj, 0.3)
    print("  LOD0 body %d tris, LOD1 %d tris" % (tri_count(parts_[0].obj), tri_count(lod)))
    add_glow(lod, items)
    add_glow(parts_[0].obj, items)
    return list(objs_) + list(extras_) + [lod]


print("  body tris %d" % P.tri_count())
rig = lamp_rig(4.6, 1.0, hexc(UG), head_x=0.0, head_z=0.8, fill_z=2.3)
groups = {"paint": dict(base=NAME + "_paint", material="Body", size=512), "atlas": dict(base=NAME, material="Details", size=512)}
export_model(NAME, [P], extras=rig, groups=groups, ao_dist=0.5, ao_strength=0.65, emit_strength=2.0, finalize=finalize,
             keep_vcol=("Headlights", "Taillights", "Underglow"))
