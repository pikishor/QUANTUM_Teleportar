"""Vael patrol hover-vehicle (4.9 x 2.1 x 1.3 m): an armoured beetle gunship hull. Domed paint elytra with ribbed chitin arches and violet glow seams, a horned prow with
mandible blades, a slit-visor cockpit, slit-eye headlights, twin plasma thrusters, a hive-siren cluster on the roof and four chitin hover pads with cilia. No wheels.
The hull underside sits at HOVER_H = 0.5 m. Body = paint (the hive colours, recoloured by the game), Details = chitin, glass, glow; flat Headlights / Taillights / Underglow.
Front = +Y in Blender (-Z in Godot)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import add_glow, glow_beam, glow_disc, glow_ellipse  # noqa: E402
from helpers import Part, export_model, hexc, make_material, new_scene, ring_se  # noqa: E402
from lodlib import make_lod1, tri_count  # noqa: E402
from vehlib import glow_mat, lamp_rig  # noqa: E402

NAME = "car_vael_patrol"
HOVER_H = 0.5
UG = "#b45cff"

new_scene()
body = make_material("Body", tex="paint", color=hexc("#4c5a40"))
glass = make_material("Glass", tex="glass", color=(0.012, 0.02, 0.026))
trim = make_material("Trim", tex="rubber")
chit = make_material("Chitin", tex="chitin")
head = make_material("Headlights", emit=hexc("#d6ff7a"), emit_strength=3.0)
tail = make_material("Taillights", emit=hexc("#ff3a10"), emit_strength=2.6)
under = make_material("Underglow", emit=hexc(UG), emit_strength=2.0)
glow = glow_mat(UG)
siren = glow_mat("#ff2a2a", name="Siren")
T_black = hexc("#1b1d1f")
SHELL2 = hexc("#2b2a33")
BONE = hexc("#a69fb0")
FLESH = hexc("#59385f")
GL = (0.012, 0.02, 0.026)

P = Part("Body", seed=67)


def ring(y, zc, rx, rz, n=18, exp=2.4):
    return ring_se(0, y, zc, rx, rz, n, exp, plane="xz")


# ---- elytra (paint) and the chitin lower hull
ely = [(-2.35, 0.78, 0.5, 0.16), (-2.0, 0.86, 0.95, 0.3), (-1.2, 0.92, 1.04, 0.36), (-0.2, 0.93, 1.05, 0.37), (0.7, 0.88, 0.95, 0.32), (1.5, 0.78, 0.7, 0.22),
       (2.1, 0.66, 0.35, 0.12), (2.4, 0.62, 0.1, 0.06)]
P.loft([ring(*e) for e in ely], mat=body, caps=(True, True), sharp=89.0)
P.loft([ring(-2.0, 0.62, 0.86, 0.1, exp=2.8), ring(-1.0, 0.6, 1.02, 0.1, exp=2.8), ring(0.5, 0.58, 0.97, 0.1, exp=2.8), ring(1.6, 0.56, 0.62, 0.07, exp=2.8)],
       mat=chit, tint=SHELL2, caps=(True, True), sharp=89.0)
for y0 in (-1.7, -1.15, -0.6, -0.05, 0.5):                                                                          # arched rib plates across the elytra, with a glow seam
    rx, rz, zc = 1.05 - 0.09 * abs(y0 + 0.2) * 0.5, 0.37 - 0.03 * abs(y0 + 0.2), 0.93
    arc = [(rx * 1.015 * math.cos(math.radians(t)), y0, zc + rz * 1.015 * math.sin(math.radians(t))) for t in range(0, 181, 30)]
    P.tube(arc, [(0.028, 0.028)] * len(arc), mat=chit, tint=BONE, n=5, sub=1, up=(0, 1, 0))
    arc2 = [(rx * 1.0 * math.cos(math.radians(t)), y0 + 0.14, zc + rz * 1.005 * math.sin(math.radians(t))) for t in range(10, 171, 40)]
    P.tube(arc2, [(0.009, 0.009)] * len(arc2), mat=glow, n=4, sub=1, up=(0, 1, 0))
P.tube([(0, -2.1, 0.99), (0, -1.2, 1.3), (0, 0.0, 1.31), (0, 0.9, 1.15)], [(0.011, 0.011)] * 4, mat=glow, n=4, sub=2, up=(1, 0, 0))     # the elytra split line
# ---- cockpit visor and armoured brow
P.box((0.9, 0.75, 0.1), (0, 1.08, 1.0), mat=glass, tint=GL, rot=(-18, 0, 0), top=(0.7, 1.0), bevel=0.01)
P.box((1.0, 0.1, 0.07), (0, 0.72, 1.12), mat=chit, tint=SHELL2, bevel=0.012, rot=(-12, 0, 0))
# ---- prow: horn and mandible blades
P.tube([(0, 1.95, 0.7), (0, 2.2, 0.74), (0, 2.45, 0.84)], [(0.12, 0.08), (0.07, 0.06), (0.012, 0.012)], mat=chit, tint=BONE, n=8, sub=2)
for sx in (1, -1):
    P.tube([(sx * 0.42, 1.85, 0.62), (sx * 0.6, 2.15, 0.62), (sx * 0.38, 2.4, 0.64)], [(0.06, 0.05), (0.04, 0.04), (0.008, 0.008)], mat=chit, tint=BONE, n=6, sub=2)
# ---- headlights: slit eyes
for sx in (1, -1):
    P.box((0.3, 0.04, 0.05), (sx * 0.4, 2.0, 0.76), mat=head, bevel=0.01, rot=(0, 0, -sx * 22))
    P.box((0.36, 0.06, 0.09), (sx * 0.4, 1.99, 0.76), mat=trim, tint=T_black, bevel=0.015, rot=(0, 0, -sx * 22))
# ---- rear: tail bar and the twin plasma thrusters
P.box((1.5, 0.04, 0.05), (0, -2.22, 0.9), mat=tail, bevel=0.008)
P.box((1.54, 0.07, 0.085), (0, -2.215, 0.9), mat=trim, tint=T_black, bevel=0.012)
for sx in (1, -1):
    P.cyl(0.2, 0.4, (sx * 0.55, -2.25, 0.7), axis="y", mat=chit, tint=SHELL2, segs=14, bevel=0.004)
    P.torus(0.2, 0.025, (sx * 0.55, -2.45, 0.7), rot=(90, 0, 0), mat=chit, tint=BONE, segs=14, sides=5)
    P.cyl(0.14, 0.02, (sx * 0.55, -2.45, 0.7), axis="y", mat=glow, segs=12)
# ---- siren cluster (red, baked glow) and rooftop spines
for sx in (1, -1):
    P.cyl(0.09, 0.07, (sx * 0.42, -0.45, 1.3), mat=chit, tint=SHELL2, segs=10)
    P.sphere(0.075, (sx * 0.42, -0.45, 1.36), mat=siren, segs=10, rings=6, scale=(1, 1, 0.8))
    P.tube([(sx * 0.7, -1.6, 1.22), (sx * 0.85, -1.9, 1.5), (sx * 0.8, -2.2, 1.28)], [(0.03, 0.03), (0.018, 0.018), (0.008, 0.008)], mat=chit, tint=BONE, n=5, sub=2)
# ---- side vanes and the four hover pads with cilia
for sx in (1, -1):
    P.bar((sx * 0.85, 0.3, 0.72), (sx * 0.98, -0.6, 0.78), 0.2, 0.035, mat=chit, tint=SHELL2, taper=(1.0, 0.5), up=(0, 0, 1))
    P.rod((sx * 0.9, 0.2, 0.74), (sx * 1.02, -0.6, 0.8), 0.01, mat=glow, segs=5)
    for yy in (1.45, -1.45):
        x = sx * 0.72
        P.box((0.32, 0.72, 0.16), (x, yy, 0.58), mat=chit, tint=SHELL2, bevel=0.03, bsegs=2, top=(0.9, 0.95))
        P.torus(0.27, 0.032, (x, yy, 0.4), mat=chit, tint=BONE, segs=22, sides=5)
        P.cyl(0.25, 0.025, (x, yy, 0.37), mat=glow, segs=18)
        P.torus(0.27, 0.011, (x, yy, 0.435), mat=glow, segs=22, sides=4)
        for k in range(8):
            a = math.pi * 2 * k / 8
            P.bar((x + 0.27 * math.cos(a), yy + 0.27 * math.sin(a), 0.41), (x + 0.36 * math.cos(a), yy + 0.36 * math.sin(a), 0.35), 0.05, 0.009,
                  mat=chit, tint=FLESH if k % 2 else SHELL2, taper=(1.0, 0.3))
# ---- underglow strip under the hull
P.box((1.4, 3.2, 0.012), (0, 0, 0.47), mat=under)

items = []
for sx in (1, -1):
    items.append(("Headlights", *glow_disc((sx * 0.4, 2.04, 0.76), (1, 0, 0), (0, 0, 1), 0.4, 0.17, 0.30)))
    items.append(("Headlights", *glow_beam(sx * 0.4, 2.1, 0.03, 7.0, 0.7, 2.4, 0.18)))
items.append(("Taillights", *glow_disc((0.0, -2.26, 0.9), (1, 0, 0), (0, 0, 1), 0.9, 0.15, 0.30)))
items.append(("Taillights", *glow_beam(0.0, -2.5, 0.03, 2.6, 1.6, 2.6, 0.2, direction=-1.0)))
items.append(("Underglow", *glow_ellipse((0.0, 0.0, 0.03), 2.0, 3.3, [(0.0, 0.3), (0.55, 0.5), (0.78, 0.26), (1.0, 0.0)])))


def finalize(parts_, objs_, extras_):
    lod = make_lod1(parts_[0].obj, 0.3)
    print("  LOD0 body %d tris, LOD1 %d tris" % (tri_count(parts_[0].obj), tri_count(lod)))
    add_glow(lod, items)
    add_glow(parts_[0].obj, items)
    return list(objs_) + list(extras_) + [lod]


print("  body tris %d" % P.tri_count())
rig = lamp_rig(4.9, 1.0, hexc(UG), head_x=0.0, head_z=0.8, fill_z=2.3)
groups = {"paint": dict(base=NAME + "_paint", material="Body", size=512), "atlas": dict(base=NAME, material="Details", size=512)}
export_model(NAME, [P], extras=rig, groups=groups, ao_dist=0.5, ao_strength=0.65, emit_strength=2.0, finalize=finalize,
             keep_vcol=("Headlights", "Taillights", "Underglow"))
