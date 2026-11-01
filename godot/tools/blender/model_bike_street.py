"""Street bike (2.1 x 0.8 x 1.3 m): a naked-sport motorcycle with a bio-mechanical engine (chitin casing, glowing ribs), a fairing nose with a slit headlight, a glowing rim ring
on both wheels and a plasma exhaust tip. Nodes: Body, WheelF (steers about Y, rolls about X), WheelR, both pivoted at their axle. Front = +Y in Blender (-Z in Godot)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import add_glow, glow_beam, glow_disc, glow_ellipse  # noqa: E402
from helpers import Part, export_model, hexc, make_material, new_scene, ring_se  # noqa: E402
from lodlib import make_lod1, tri_count  # noqa: E402
from vehlib import glow_mat, lamp_rig, wheel_part  # noqa: E402

NAME = "bike_street"
R = 0.34
YF, YR = 0.74, -0.70                      # axle positions
UG = "#18d6ff"

new_scene()
body = make_material("Body", tex="paint", color=hexc("#4f7f9a"))
glass = make_material("Glass", tex="glass", color=(0.012, 0.02, 0.026))
trim = make_material("Trim", tex="rubber")
chrome = make_material("Chrome", tex="steel")
chit = make_material("Chitin", tex="chitin")
head = make_material("Headlights", emit=hexc("#fff1d0"), emit_strength=3.0)
tail = make_material("Taillights", emit=hexc("#ff1020"), emit_strength=2.6)
under = make_material("Underglow", emit=hexc(UG), emit_strength=2.0)
glow = glow_mat(UG)
T_black, T_dark, T_chrome = hexc("#1b1d1f"), hexc("#2c3033"), hexc("#b4bcc3")
T_chit = hexc("#2a2f36")
T_bone = hexc("#8b8a8e")

P = Part("Body", seed=21)


def ring(y, z, rx, rz, n=14, exp=2.4):
    return ring_se(0, y, z, rx, rz, n, exp, plane="xz")


# ---- tank, seat cowl, tail, fairing nose (paint)
P.loft([ring(-0.20, 0.99, 0.10, 0.10), ring(-0.05, 1.03, 0.19, 0.16), ring(0.20, 1.05, 0.215, 0.17), ring(0.45, 1.01, 0.19, 0.15), ring(0.62, 0.96, 0.12, 0.11)],
       mat=body, caps=(True, True), sharp=89.0)
P.loft([ring(-0.55, 0.97, 0.10, 0.06), ring(-0.75, 1.0, 0.13, 0.08), ring(-0.95, 1.04, 0.10, 0.07), ring(-1.04, 1.06, 0.05, 0.05)], mat=body, caps=(True, True), sharp=89.0)
P.loft([ring(0.52, 1.0, 0.13, 0.13), ring(0.70, 1.06, 0.19, 0.19), ring(0.90, 1.04, 0.16, 0.16), ring(1.0, 0.99, 0.09, 0.09)], mat=body, caps=(True, True), sharp=89.0)
P.box((0.2, 0.05, 0.07), (0.0, 0.99, 1.03), mat=head, bevel=0.012, bsegs=1, top=(0.9, 0.9))                                  # slit headlight
P.box((0.25, 0.08, 0.10), (0.0, 0.975, 1.03), mat=trim, tint=T_black, bevel=0.015)
P.box((0.2, 0.012, 0.22), (0, 0.78, 1.21), mat=glass, tint=(0.012, 0.02, 0.026), rot=(-32, 0, 0), bevel=0.003)           # screen
P.box((0.12, 0.05, 0.035), (0.0, -1.04, 1.04), mat=tail, bevel=0.008, bsegs=1)                                                # tail light
P.box((0.015, 0.3, 0.14), (0.205, 0.0, 0.98), mat=body, bevel=0.005, mirror=True)                                    # side panels
# ---- seat, mudguards
P.box((0.25, 0.62, 0.07), (0, -0.40, 0.94), mat=trim, tint=T_dark, bevel=0.02, bsegs=2, top=(0.92, 0.8))
P.box((0.2, 0.46, 0.03), (0, -0.88, 0.66), mat=body, bevel=0.008, rot=(10, 0, 0))                                          # rear fender
P.box((0.17, 0.52, 0.03), (0, 0.84, 0.72), mat=body, bevel=0.008, rot=(-6, 0, 0))                                          # front fender
for sx in (1, -1):
    P.bar((sx * 0.07, 0.76, 0.69), (sx * 0.1, 0.62, 0.95), 0.025, 0.02, mat=trim, tint=T_dark)                             # fender stays
# ---- engine (chitin casing, glowing ribs) and frame
P.box((0.30, 0.48, 0.32), (0, 0.06, 0.52), mat=chit, tint=T_chit, bevel=0.03, bsegs=2)
for k in range(5):
    P.box((0.325, 0.025, 0.2), (0, -0.12 + k * 0.095, 0.56), mat=glow, bevel=0.004)                                             # glowing ribs along the casing
P.cyl(0.08, 0.34, (0.0, 0.34, 0.66), axis="x", mat=chit, tint=T_chit, segs=12)                                              # cylinder head
P.box((0.22, 0.2, 0.22), (0, -0.30, 0.42), mat=chit, tint=T_bone, bevel=0.02)                                              # gearbox
P.box((0.2, 0.5, 0.05), (0, 0.05, 0.31), mat=trim, tint=T_black, bevel=0.01)                                               # belly pan
for sx in (1, -1):
    P.rod((sx * 0.07, 0.68, 0.98), (sx * 0.06, 0.1, 0.78), 0.022, mat=chrome, tint=hexc("#3a3f44"), segs=8)                 # frame spars
    P.rod((sx * 0.07, -0.1, 0.95), (sx * 0.06, -0.3, 0.52), 0.02, mat=chrome, tint=hexc("#3a3f44"), segs=8)
    P.rod((sx * 0.1, 0.60, 1.0), (sx * 0.1, YF, R), 0.021, mat=chrome, tint=T_chrome, segs=8)                               # fork legs
    P.rod((sx * 0.1, 0.62, 0.52), (sx * 0.1, 0.62, 0.40), 0.03, mat=chrome, tint=hexc("#3a3f44"), segs=8)
    P.bar((sx * 0.1, -0.28, 0.52), (sx * 0.1, YR, R), 0.05, 0.06, mat=chit, tint=T_chit, bevel=0.008)                       # swingarm
    P.rod((sx * 0.07, -0.55, 0.95), (sx * 0.1, -0.55, 0.52), 0.016, mat=chrome, tint=T_chrome, segs=8)                       # shock
    P.cyl(0.028, 0.2, (sx * 0.07, -0.55, 0.72), axis="z", mat=glow, segs=8)
    P.box((0.09, 0.14, 0.012), (sx * 0.16, -0.22, 0.42), mat=trim, tint=T_dark, bevel=0.004)                                # foot pegs
    P.rod((sx * 0.38, 0.5, 1.13), (sx * 0.2, 0.5, 1.1), 0.012, mat=trim, tint=T_black, segs=6)                              # handlebar
    P.cyl(0.017, 0.12, (sx * 0.36, 0.5, 1.13), axis="x", mat=trim, tint=T_black, segs=8)                                    # grips
    P.rod((sx * 0.33, 0.52, 1.14), (sx * 0.35, 0.56, 1.3), 0.007, mat=trim, tint=T_black, segs=5)                           # mirror stalks
    P.box((0.09, 0.012, 0.055), (sx * 0.355, 0.57, 1.3), mat=glass, tint=(0.012, 0.02, 0.026), bevel=0.003)
    P.rod((sx * 0.11, 0.62, 0.99), (sx * 0.11, 0.62, 1.05), 0.026, mat=chrome, tint=T_chrome, segs=8)
# ---- exhaust with a plasma tip
P.rod((0.15, 0.22, 0.32), (0.17, -0.3, 0.30), 0.035, mat=chrome, tint=hexc("#4a4f55"), segs=8)
P.cyl(0.055, 0.5, (0.17, -0.78, 0.44), axis="y", mat=chrome, tint=T_chrome, segs=12, bevel=0.003)
P.cyl(0.04, 0.02, (0.17, -1.04, 0.44), axis="y", mat=glow, segs=10)
P.rod((0.17, -0.3, 0.30), (0.17, -0.55, 0.44), 0.03, mat=chrome, tint=hexc("#4a4f55"), segs=8)
# ---- glowing trim: along the tank, the fairing and the tail (alien sci-fi)
for sx in (1, -1):
    P.rod((sx * 0.215, -0.1, 1.04), (sx * 0.222, 0.25, 1.06), 0.009, mat=glow, segs=5)
    P.rod((sx * 0.222, 0.25, 1.06), (sx * 0.19, 0.5, 1.02), 0.009, mat=glow, segs=5)
    P.rod((sx * 0.125, -0.6, 1.0), (sx * 0.12, -0.9, 1.06), 0.008, mat=glow, segs=5)
    P.rod((sx * 0.19, 0.62, 1.07), (sx * 0.1, 0.96, 1.07), 0.008, mat=glow, segs=5)
# ---- underglow strip
P.box((0.3, 1.1, 0.012), (0.0, 0.0, 0.17), mat=under)

# ---- wheels: separate nodes pivoted at the axle
mats = dict(trim=trim, chrome=chrome)
wf = wheel_part("WheelF", 0.0, YF, R, R, 0.15, mats, rim="#8d959c", spoke="#c3cad1", spokes=6, seed=71, ring=glow)
wr = wheel_part("WheelR", 0.0, YR, R, R, 0.21, mats, rim="#8d959c", spoke="#c3cad1", spokes=6, seed=72, ring=glow)

# ---- lamps: glow fans (halos, road pools), added after the bake (and to the LOD1 copy)
items = [("Headlights", *glow_disc((0.0, 1.03, 1.03), (1, 0, 0), (0, 0, 1), 0.34, 0.14, 0.30)),
         ("Headlights", *glow_beam(0.0, 1.04, 0.03, 6.0, 0.45, 2.0, 0.20)),
         ("Taillights", *glow_disc((0.0, -1.075, 1.04), (1, 0, 0), (0, 0, 1), 0.3, 0.12, 0.30)),
         ("Taillights", *glow_beam(0.0, -1.08, 0.03, 2.2, 0.5, 1.6, 0.20, direction=-1.0)),
         ("Underglow", *glow_ellipse((0.0, 0.0, 0.03), 0.95, 1.7, [(0.0, 0.22), (0.6, 0.42), (0.78, 0.2), (1.0, 0.0)]))]


def finalize(parts_, objs_, extras_):
    lod = make_lod1(parts_[0].obj, 0.3)
    print("  LOD0 body %d tris, LOD1 %d tris" % (tri_count(parts_[0].obj), tri_count(lod)))
    add_glow(lod, items)
    add_glow(parts_[0].obj, items)
    return list(objs_) + list(extras_) + [lod]


print("  body tris %d, wheel tris %d" % (P.tri_count(), wf.tri_count() + wr.tri_count()))
rig = lamp_rig(2.1, 1.05, hexc(UG), head_z=1.0, fill_z=2.0, head_energy=2.0)
groups = {"paint": dict(base=NAME + "_paint", material="Body", size=512), "atlas": dict(base=NAME, material="Details", size=512)}
export_model(NAME, [P, wf, wr], extras=rig, groups=groups, ao_dist=0.4, ao_strength=0.65, emit_strength=2.0, finalize=finalize,
             keep_vcol=("Headlights", "Taillights", "Underglow"))
