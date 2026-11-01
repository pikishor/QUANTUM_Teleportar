"""Enemy "Vael trooper" (game type `operative`): a chitinous armoured insectoid biped. Hunched, digitigrade, four small glowing red eyes, mandible
guard, asymmetric bulk (heavy left shoulder carapace), a second small arm pair on the chest, dorsal spines and a tail (bones Sec1-3 on the Hips,
swayed by CharacterRig). Dark bone-grey shell, pale bone plates, orange seams, crimson bio-glow. Holds a carapace carbine. About 1.8 m.
Blender axes: x right, y front, z up. ONE skinned mesh, one atlas material "Gear" (see alienlib.py)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: F401,E402
from mathutils import Matrix, Vector  # noqa: E402

from alienlib import make_finalize, surf_y, two_bone, xy_rings  # noqa: E402
from helpers import (empty, export_model, hexc, light, make_material, new_scene, ring_se, rotm, scale_c, set_detail)  # noqa: E402
from humanoid import RigPart  # noqa: E402
import atlas  # noqa: E402

atlas.PAD = 8             # UV island padding (was 4): no atlas bleed at mip 3+ and on the LOW 1K read
new_scene()
set_detail(1.1)
BRIGHT = 1.6
chit = make_material("Chitin", tex="shell")
glr = make_material("GlowR", tex="glow", color=hexc("#ff2234"))
glo = make_material("GlowO", tex="glow", color=hexc("#ff7a1c"))


def T(h, k=BRIGHT):
    return scale_c(hexc(h), k)


SHELL = T("#585a5e", 1.55)
SHELL2 = T("#3b3c40", 1.8)
BONE = T("#b3a88f", 1.15)
BONE2 = T("#6f6556", 1.3)
FLESH = T("#7a3234", 1.6)
CLAW = T("#cdbfa6", 1.0)

HIP = (0.0, 0.0, 0.98)
WAIST = (0.0, 0.03, 1.08)
NECK = (0.0, 0.26, 1.46)
RIFLE_O = (0.14, 0.26, 1.31)
SH = (0.27, 0.10, 1.40)

hips = RigPart("Hips", HIP, None, seed=3)
torso = RigPart("Torso", WAIST, "Hips", seed=5)
head = RigPart("Head", NECK, "Torso", seed=9)
rifle = RigPart("Rifle", RIFLE_O, "Torso", seed=11)
TAIL = [(0.0, -0.10, 1.0), (0.0, -0.50, 0.92), (0.0, -0.84, 0.87)]
sec = [RigPart("Sec1", TAIL[0], "Hips", seed=41), RigPart("Sec2", TAIL[1], "Sec1", seed=42), RigPart("Sec3", TAIL[2], "Sec2", seed=43)]
KNEE = (0.0, 0.17, 0.60)
HOCK = (0.0, -0.10, 0.30)
thigh, shin, foot = {}, {}, {}
for s, side in ((-1, "L"), (1, "R")):
    x0 = 0.14 * s
    thigh[s] = RigPart("Thigh" + side, (x0, 0.02, 0.98), "Hips", seed=7 + s)
    shin[s] = RigPart("Shin" + side, (x0, KNEE[1], KNEE[2]), "Thigh" + side, seed=21 + s)
    foot[s] = RigPart("Foot" + side, (x0, HOCK[1], HOCK[2]), "Shin" + side, seed=31 + s)

TORSO = [(1.04, 0.02, 0.16, 0.125), (1.14, 0.06, 0.19, 0.145), (1.26, 0.12, 0.23, 0.16), (1.38, 0.18, 0.265, 0.165),
         (1.46, 0.22, 0.23, 0.135), (1.50, 0.23, 0.11, 0.09)]

# ------------------------------------------------------------------ hips, legs, tail
hips.loft(xy_rings([(0.92, 0.0, 0.13, 0.10), (1.0, 0.0, 0.16, 0.12), (1.08, 0.02, 0.15, 0.115)]), mat=chit, tint=SHELL2)
hips.loft(xy_rings([(1.05, 0.02, 0.172, 0.132), (1.09, 0.025, 0.172, 0.132)]), mat=glo)                               # orange belt seam
hips.box((0.14, 0.05, 0.1), (0, 0.12, 0.97), mat=chit, tint=BONE2, bevel=0.008, top=(0.7, 1.0))
for s in (-1, 1):
    x0 = 0.14 * s
    p, q, f = thigh[s], shin[s], foot[s]
    p.tube([(x0, 0.02, 1.0), (x0, 0.08, 0.82), (x0, KNEE[1], KNEE[2])], [(0.1, 0.11), (0.095, 0.11), (0.066, 0.072)], mat=chit, tint=SHELL, n=10, exp=2.2, sub=2)
    p.sphere(0.065, (x0, KNEE[1], KNEE[2]), mat=chit, tint=SHELL2, segs=10, rings=6)
    p.box((0.1, 0.07, 0.15), (x0 + s * 0.03, 0.14, 0.76), rot=(-18, 0, 0), mat=chit, tint=BONE, bevel=0.01, bsegs=1, top=(0.8, 0.9), jitter=0.05)   # thigh plate
    p.rod((x0 + s * 0.06, 0.1, 0.86), (x0 + s * 0.07, 0.17, 0.66), 0.01, mat=glo, segs=4)
    p.rod((x0, KNEE[1] + 0.05, KNEE[2] + 0.0), (x0, KNEE[1] + 0.17, KNEE[2] - 0.06), 0.028, mat=chit, tint=CLAW, r2=0.003, segs=6)      # knee spike
    q.tube([(x0, KNEE[1], KNEE[2]), (x0, 0.04, 0.44), (x0, HOCK[1], HOCK[2])], [(0.066, 0.07), (0.06, 0.08), (0.048, 0.05)], mat=chit, tint=SHELL, n=9, exp=2.2, sub=2)
    q.bar((x0, 0.135, 0.56), (x0, 0.03, 0.38), 0.07, 0.024, mat=chit, tint=BONE, bevel=0.006, taper=(0.7, 0.7))              # shin plate
    q.rod((x0 + s * 0.04, 0.11, 0.55), (x0 + s * 0.038, -0.07, 0.34), 0.008, mat=glo, segs=4)
    f.sphere(0.052, (x0, HOCK[1], HOCK[2]), mat=chit, tint=SHELL2, segs=9, rings=6)
    f.rod((x0, HOCK[1] - 0.02, HOCK[2] + 0.04), (x0, -0.26, 0.4), 0.03, mat=chit, tint=CLAW, r2=0.004, segs=6)                    # hock spur
    f.tube([(x0, HOCK[1], HOCK[2]), (x0, 0.04, 0.16), (x0, 0.12, 0.05)], [(0.05, 0.055), (0.042, 0.048), (0.046, 0.042)], mat=chit, tint=SHELL, n=8, exp=2.2, sub=1)
    for dx in (-0.045, 0.0, 0.045):
        f.rod((x0 + dx * 0.4, 0.11, 0.045), (x0 + dx, 0.25, 0.022), 0.024, mat=chit, tint=SHELL2, r2=0.015, segs=7)
        f.rod((x0 + dx, 0.245, 0.024), (x0 + dx, 0.32, 0.008), 0.015, mat=chit, tint=CLAW, r2=0.002, segs=6)
tail_pts = [TAIL[0], (0.0, -0.3, 0.97), TAIL[1], (0.0, -0.68, 0.895), TAIL[2], (0.0, -1.0, 0.9), (0.0, -1.2, 0.97)]
radii = [0.085, 0.075, 0.06, 0.05, 0.04, 0.03, 0.006]
sec[0].tube(tail_pts[0:3], [(radii[0], radii[0] * 0.95), (radii[1], radii[1] * 0.95), (radii[2], radii[2] * 0.95)], mat=chit, tint=SHELL, n=8, sub=2)
sec[1].tube(tail_pts[2:5], [(radii[2], radii[2] * 0.95), (radii[3], radii[3] * 0.95), (radii[4], radii[4] * 0.95)], mat=chit, tint=SHELL2, n=8, sub=2)
sec[2].tube(tail_pts[4:7], [(radii[4], radii[4] * 0.95), (radii[5], radii[5] * 0.95), (0.006, 0.006)], mat=chit, tint=BONE2, n=8, sub=2)
for k, (a, b) in enumerate([(0.12, 0.3), (0.3, 0.55)]):
    sec[0].rod((0, TAIL[0][1] - 0.2 - 0.2 * k, 1.04 - 0.02 * k), (0, TAIL[0][1] - 0.26 - 0.2 * k, 1.13 - 0.02 * k), 0.016, mat=chit, tint=CLAW, r2=0.002, segs=5)
sec[1].rod((0, -0.62, 0.93), (0, -0.7, 1.02), 0.014, mat=chit, tint=CLAW, r2=0.002, segs=5)
sec[2].rod((0, -1.1, 0.93), (0, -1.28, 1.02), 0.02, mat=chit, tint=CLAW, r2=0.002, segs=6)                              # barbed stinger
sec[2].sphere(0.03, (0, -1.02, 0.91), mat=glo, segs=7, rings=5)

# ------------------------------------------------------------------ torso: hunched thorax, dorsal carapace and spines, second small arm pair
torso.loft(xy_rings(TORSO), mat=chit, tint=SHELL)
torso.loft(xy_rings([(1.06, 0.03, 0.158, 0.12), (1.2, 0.09, 0.185, 0.135), (1.3, 0.14, 0.205, 0.145)]), mat=chit, tint=FLESH)           # soft belly
for k in range(4):                                                                                                  # stacked dorsal carapace bands + orange seams
    z = 1.17 + 0.075 * k
    cy = surf_y(TORSO, z, 0, back=True)
    w = 0.3 + 0.012 * k
    torso.box((w, 0.05, 0.085), (0, cy - 0.012, z), rot=(-16 - 4 * k, 0, 0), mat=chit, tint=BONE2 if k % 2 else SHELL2, bevel=0.007, top=(0.85, 1.0), jitter=0.05)
    torso.box((w * 0.8, 0.012, 0.008), (0, cy - 0.036 - 0.004 * k, z - 0.045), rot=(-16 - 4 * k, 0, 0), mat=glo)
for k in range(6):                                                                                                  # dorsal spines
    z = 1.14 + 0.065 * k
    cy = surf_y(TORSO, z, 0, back=True)
    torso.rod((0, cy - 0.03, z), (0, cy - 0.22 + 0.01 * k, z + 0.1 + 0.015 * k), 0.026 - 0.002 * k, mat=chit, tint=CLAW if k % 2 == 0 else BONE, r2=0.002, segs=6)
for sx in (-1, 1):                                                                                                  # chest ridges
    torso.box((0.13, 0.03, 0.045), (sx * 0.075, surf_y(TORSO, 1.36, 0.075) + 0.003, 1.36), rot=(0, 0, -sx * 20), mat=chit, tint=BONE, bevel=0.006)
    torso.box((0.1, 0.03, 0.04), (sx * 0.07, surf_y(TORSO, 1.27, 0.07) + 0.003, 1.27), rot=(0, 0, -sx * 20), mat=chit, tint=BONE2, bevel=0.006)
    torso.rod((sx * 0.04, surf_y(TORSO, 1.31, 0.04) + 0.003, 1.31), (sx * 0.15, surf_y(TORSO, 1.4, 0.15) + 0.003, 1.4), 0.009, mat=glo, segs=4)
    # second, small arm pair folded on the chest
    a0 = Vector((sx * 0.12, surf_y(TORSO, 1.2, 0.12) - 0.01, 1.2))
    a1 = a0 + Vector((sx * 0.08, 0.1, -0.03))
    a2 = a1 + Vector((-sx * 0.05, 0.12, 0.03))
    torso.rod(a0, a1, 0.022, mat=chit, tint=SHELL2, r2=0.017, segs=7)
    torso.rod(a1, a2, 0.017, mat=chit, tint=BONE, r2=0.011, segs=7)
    torso.sphere(0.022, a1, mat=chit, tint=SHELL2, segs=7, rings=5)
    for d in (-1, 0, 1):
        torso.rod(a2, a2 + Vector((d * 0.025 - sx * 0.02, 0.07, 0.02)), 0.008, mat=chit, tint=CLAW, r2=0.002, segs=5)
torso.sphere(0.032, (0, surf_y(TORSO, 1.18) + 0.0, 1.18), mat=glr, segs=8, rings=6)                                    # red belly node
# neck
torso.tube([(0, 0.2, 1.42), (0, 0.27, 1.47), (0, 0.32, 1.5)], [(0.07, 0.07), (0.06, 0.06), (0.06, 0.06)], mat=chit, tint=SHELL2, n=8, sub=1)

# ------------------------------------------------------------------ head: wide insect skull, four small red eyes, mandibles
cran = [(0.20, 1.55, 0.09, 0.095), (0.28, 1.585, 0.125, 0.115), (0.38, 1.575, 0.125, 0.11), (0.48, 1.52, 0.095, 0.085), (0.56, 1.47, 0.05, 0.05),
        (0.60, 1.45, 0.02, 0.025)]
head.loft([ring_se(0, y, zc, rx, rz, 12, 2.3, plane="xz") for y, zc, rx, rz in cran], mat=chit, tint=SHELL)
head.loft([ring_se(0, y, zc, rx, rz, 8, 2.0, plane="xz") for y, zc, rx, rz in
           [(0.2, 1.62, 0.02, 0.03), (0.3, 1.69, 0.024, 0.045), (0.4, 1.68, 0.022, 0.05), (0.5, 1.6, 0.015, 0.04), (0.56, 1.53, 0.008, 0.015)]], mat=chit, tint=BONE)   # brow ridge
for sx in (-1, 1):
    head.sphere(0.024, (sx * 0.045, 0.545, 1.5), mat=glr, segs=8, rings=6)                                       # four eyes: two large forward
    head.sphere(0.016, (sx * 0.085, 0.485, 1.54), mat=glr, segs=7, rings=5)                                       # two small side
    head.rod((sx * 0.05, 0.57, 1.42), (sx * 0.1, 0.7, 1.37), 0.022, mat=chit, tint=BONE, r2=0.012, segs=7)        # mandibles
    head.rod((sx * 0.1, 0.7, 1.37), (sx * 0.05, 0.78, 1.37), 0.012, mat=chit, tint=CLAW, r2=0.002, segs=6)
    head.rod((sx * 0.1, 0.22, 1.6), (sx * 0.22, 0.02, 1.7), 0.014, mat=chit, tint=CLAW, r2=0.002, segs=5)         # swept horns
head.box((0.12, 0.1, 0.03), (0, 0.6, 1.4), mat=chit, tint=BONE2, bevel=0.006, top=(0.7, 0.8))                         # mandible guard plate
head.rod((0, 0.19, 1.62), (0, -0.1, 1.68), 0.02, mat=chit, tint=CLAW, r2=0.002, segs=6)                              # crest

# ------------------------------------------------------------------ rifle: chunky carapace carbine with a bio-maw muzzle (rifle-local axes: +Y muzzle)
RR = rotm(1.2, 0, 0)
R = Matrix.Translation(Vector(RIFLE_O)) @ RR


def rp(v):
    return R @ Vector(v)


def rbox(size, pos, mat, tint=(1, 1, 1), **kw):
    rifle.box(size, rp(pos), mat=mat, tint=tint, frame=RR, **kw)


def rrod(a, b, r, mat, tint=(1, 1, 1), **kw):
    rifle.rod(rp(a), rp(b), r, mat=mat, tint=tint, **kw)


rings = [ring_se(0, y, zc, rx, rz, 10, 2.2, plane="xz") for y, zc, rx, rz in
         [(-0.04, -0.02, 0.034, 0.06), (0.12, -0.02, 0.048, 0.078), (0.32, -0.01, 0.05, 0.07), (0.55, 0.0, 0.046, 0.056), (0.72, 0.0, 0.04, 0.045)]]
rifle.loft([[tuple(rp(p)) for p in ring] for ring in rings], mat=chit, tint=SHELL2)
for yy in (0.15, 0.3, 0.45, 0.6):
    rifle.loft([[tuple(rp(p)) for p in ring_se(0, y, 0.0, 0.058, 0.074, 10, 2.2, plane="xz")] for y in (yy, yy + 0.04)],
               mat=chit, tint=BONE2)
rbox((0.03, 0.55, 0.03), (0, 0.32, 0.085), chit, BONE, bevel=0.004, top=(1.0, 0.5))
rbox((0.035, 0.05, 0.13), (0, 0.235, -0.085), chit, SHELL2, bevel=0.005)
rbox((0.03, 0.055, 0.075), (0, 0.41, -0.05), chit, SHELL2, bevel=0.005)
rifle.box((0.04, 0.07, 0.17), rp((0, 0.33, -0.145)), mat=chit, tint=FLESH, frame=RR @ rotm(-9, 0, 0), bevel=0.006)    # bio-cell (MagWell)
rbox((0.008, 0.05, 0.12), (0.022, 0.33, -0.15), glo)
rbox((0.062, 0.2, 0.012), (0, 0.18, 0.062), glo)                                                                    # orange spine seam
for k in range(4):                                                                                                  # petal prongs of the maw
    a = math.pi / 4 + k * math.pi / 2
    rrod((0.03 * math.cos(a), 0.7, 0.03 * math.sin(a)), (0.048 * math.cos(a), 0.93, 0.048 * math.sin(a)), 0.014, chit, CLAW, r2=0.004, segs=6)
rifle.sphere(0.022, rp((0, 0.86, 0)), mat=glr, segs=8, rings=5)
muzzle = rp((0, 0.93, 0))

# ------------------------------------------------------------------ arms: thick chitin limbs, heavy left carapace, clawed hands
hands = {1: rp((0.0, 0.235, -0.115)), -1: rp((0.0, 0.41, -0.012))}
wrists = {1: rp((0.012, 0.19, -0.068)), -1: rp((0.045, 0.325, 0.01))}
R3 = R.to_3x3()
uarm, farm, wrist_pos = {}, {}, {}
for s, side in ((-1, "L"), (1, "R")):
    Sv = Vector((SH[0] * s, SH[1], SH[2]))
    E, W = two_bone(Sv, wrists[s], 0.35, 0.33, (0.6 * s, -0.4, -1.0))
    wrist_pos[s] = W
    uarm[s] = RigPart("UpperArm" + side, Sv, "Torso", seed=51 + s)
    farm[s] = RigPart("ForeArm" + side, E, "UpperArm" + side, seed=61 + s)
    ua, fa_ = uarm[s], farm[s]
    if s == -1:                                                                                                       # heavy left shoulder carapace
        ua.sphere((0.2, 0.16, 0.1), Sv + Vector((-0.05, -0.01, 0.07)), rot=(0, -18, 0), mat=chit, tint=SHELL, segs=14, rings=8)
        ua.sphere((0.17, 0.13, 0.05), Sv + Vector((-0.08, 0.0, 0.14)), rot=(0, -26, 0), mat=chit, tint=BONE2, segs=12, rings=7)
        ua.box((0.22, 0.012, 0.01), Sv + Vector((-0.07, 0.15, 0.06)), rot=(0, -20, 0), mat=glo)
        for k, (dx, dz) in enumerate([(-0.17, 0.12), (-0.2, 0.04), (-0.12, 0.19)]):
            ua.rod(Sv + Vector((dx * 0.6, 0.0, dz * 0.6 + 0.02)), Sv + Vector((dx * 1.4, -0.02 * k, dz * 1.4 + 0.07)), 0.032, mat=chit, tint=CLAW, r2=0.003, segs=6)
    else:
        ua.sphere((0.12, 0.1, 0.06), Sv + Vector((0.04, 0.0, 0.06)), rot=(0, 18, 0), mat=chit, tint=SHELL, segs=12, rings=7)
        ua.rod(Sv + Vector((0.08, 0.0, 0.1)), Sv + Vector((0.13, -0.04, 0.2)), 0.02, mat=chit, tint=CLAW, r2=0.003, segs=6)
    ua.tube([Sv, (Sv + E) / 2 + Vector((s * 0.012, 0, 0)), E], [(0.07, 0.07), (0.062, 0.062), (0.055, 0.055)], mat=chit, tint=SHELL, n=9, sub=1)
    fa_.sphere(0.05, E, mat=chit, tint=SHELL2, segs=9, rings=6)
    fa_.rod(E, E + Vector((s * 0.03, -0.1, 0.05)), 0.024, mat=chit, tint=CLAW, r2=0.003, segs=6)                    # elbow spike
    fv = W - E
    fa_.tube([E, E + fv * 0.5, W], [(0.058, 0.058), (0.052, 0.052), (0.04, 0.04)], mat=chit, tint=SHELL, n=9, sub=1)
    fa_.bar(E + fv * 0.2, E + fv * 0.78, 0.085, 0.07, mat=chit, tint=BONE, bevel=0.008, taper=(0.8, 0.8))            # forearm carapace
    fa_.rod(E + fv * 0.82, E + fv * 0.86, 0.04, mat=glo, segs=10)
    h = hands[s]
    fa_.tube([W - fv.normalized() * 0.02, h], [(0.034, 0.034), (0.04, 0.038)], mat=chit, tint=SHELL2, n=8, sub=0)
    fa_.box((0.06, 0.075, 0.075), h, mat=chit, tint=SHELL2, frame=RR, bevel=0.01, bsegs=1)
    for k in range(3):
        zk = 0.026 - 0.026 * k
        a = h + R3 @ Vector((0, 0.025, zk))
        b = h + R3 @ Vector((0, 0.072, zk))
        c = h + R3 @ Vector((0, 0.09, zk + 0.02))
        fa_.rod(a, b, 0.012, mat=chit, tint=SHELL2, r2=0.01, segs=6)
        fa_.rod(b, c, 0.01, mat=chit, tint=CLAW, r2=0.002, segs=5)
    fa_.rod(h + R3 @ Vector((-s * 0.025, 0.0, 0.04)), h + R3 @ Vector((-s * 0.05, 0.05, 0.06)), 0.011, mat=chit, tint=CLAW, r2=0.002, segs=5)

# ------------------------------------------------------------------ silhouette pass: heavier plating, readable joints, serrated mandibles, neck frill
for s in (-1, 1):
    x0 = 0.14 * s
    Sv = Vector((SH[0] * s, SH[1], SH[2]))
    ua, fa_ = uarm[s], farm[s]
    for k in range(3):                                                                                              # stacked pauldron lamellae (the left one heavier)
        big = 1.12 if s == -1 else 1.0
        ua.sphere((0.15 * big - 0.015 * k, 0.12 * big, 0.026), Sv + Vector((s * (0.1 + 0.05 * k) * big, 0.0, -0.02 - 0.06 * k)), rot=(0, s * (30 + 16 * k), 0),
                  mat=chit, tint=BONE2 if k % 2 else SHELL, segs=12, rings=6)
    ua.torus(0.07, 0.016, Sv + Vector((s * 0.0, 0, -0.17)), mat=chit, tint=BONE, segs=12, sides=5)                       # elbow-side joint rings
    fa_.torus(0.062, 0.015, fa_.origin, mat=chit, tint=BONE2, segs=12, sides=5)
    thigh[s].box((0.15, 0.1, 0.3), (x0 + s * 0.04, 0.1, 0.78), rot=(-8, 0, s * 5), mat=chit, tint=BONE, bevel=0.012, bsegs=2, top=(0.85, 0.95), jitter=0.04)  # heavy thigh plate
    thigh[s].torus(0.085, 0.018, (x0, KNEE[1], KNEE[2]), mat=glo, segs=12, sides=5)                                         # knee joint ring
    thigh[s].sphere((0.09, 0.07, 0.09), (x0, KNEE[1] + 0.06, KNEE[2] + 0.02), mat=chit, tint=BONE2, segs=12, rings=6)         # knee cap
    shin[s].box((0.11, 0.07, 0.2), (x0, 0.13, 0.5), rot=(-10, 0, 0), mat=chit, tint=BONE2, bevel=0.01, top=(0.8, 0.8))      # greave
    shin[s].torus(0.062, 0.014, (x0, 0.02, 0.42), mat=chit, tint=BONE, segs=12, sides=5)
    head.rod((s * 0.09, 0.6, 1.42), (s * 0.15, 0.72, 1.36), 0.018, mat=chit, tint=BONE, r2=0.008, segs=6)                  # outer mandible pair
    for k in range(3):                                                                                              # serrations
        head.rod((s * (0.085 + 0.012 * k), 0.63 + 0.04 * k, 1.395 - 0.005 * k), (s * (0.045 + 0.012 * k), 0.64 + 0.04 * k, 1.35 - 0.005 * k), 0.007, mat=chit, tint=CLAW, r2=0.001, segs=4)
    head.rod((s * 0.12, 0.34, 1.62), (s * 0.28, 0.14, 1.78), 0.016, mat=chit, tint=CLAW, r2=0.002, segs=5)                  # second horn pair
for k in range(7):                                                                                                  # neck frill of spikes
    a = -75 + 25 * k
    ar = math.radians(a)
    torso.rod((0.09 * math.sin(ar), 0.2 - 0.09 * math.cos(ar) + 0.05, 1.45), (0.2 * math.sin(ar), 0.2 - 0.2 * math.cos(ar) + 0.0, 1.55), 0.014, mat=chit, tint=CLAW, r2=0.002, segs=5)
torso.loft(xy_rings([(1.3, 0.18, 0.285, 0.18), (1.42, 0.22, 0.25, 0.145), (1.46, 0.23, 0.2, 0.12)], n=14), mat=chit, tint=BONE, bevel=0.006)      # front breast carapace
torso.loft(xy_rings([(1.16, 0.08, 0.2, 0.15), (1.26, 0.13, 0.245, 0.17), (1.31, 0.15, 0.25, 0.17)], n=14), mat=chit, tint=BONE2, bevel=0.006)    # lower rib plate
hips.box((0.07, 0.2, 0.2), (0.0, -0.02, 0.94), rot=(0, 0, 0), mat=chit, tint=BONE2, bevel=0.008, top=(1.0, 0.8))             # tail root plate

# ------------------------------------------------------------------ export
parts = [hips, torso, head, uarm[-1], farm[-1], uarm[1], farm[1], rifle] + [thigh[s] for s in (-1, 1)] + [shin[s] for s in (-1, 1)] + [foot[s] for s in (-1, 1)] + sec
rig = [empty("Muzzle", muzzle), empty("WristL", wrist_pos[-1]), empty("WristR", wrist_pos[1]),
       empty("MagWell", rp((0, 0.33, -0.2))), empty("MagPouch", (-0.09, 0.26, 1.05)),
       light("Fill", (0.0, 0.8, 1.55), "omni", (0.78, 0.84, 1.0), 1.2, 3.6, mask="own", attenuation=1.2, fade=(30, 12)),
       light("Rim", (0.25, -0.8, 2.1), "omni", (1.0, 0.35, 0.3), 1.4, 3.8, mask="own", attenuation=1.2, fade=(30, 12))]
print("  parts=%d tris(before culling)=%d" % (len(parts), sum(p.tri_count() for p in parts)))
export_model("operative", parts, extras=rig, size=1024, decals=[], ao_dist=0.2, ao_strength=0.55, emit_strength=2.0,
             finalize=make_finalize(["Sec1", "Sec2", "Sec3"]), hipoly=dict(levels=2))
