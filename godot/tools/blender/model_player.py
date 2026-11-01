"""Player "Kestrel": a quantum-phased alien-human hybrid. Tall and lean (about 1.95 m), elongated cranium with a swept crest, smooth obsidian-pearl
faceplate with one thin cyan slit (no human face), four-fingered long hands, digitigrade legs, translucent pearl chitin shoulder plates, cyan
bioluminescent veins, a glowing quantum core in the chest, a phase halo and a tattered phase-cloak (bones Sec1-3, swayed by CharacterRig),
carrying an alien-tech fork-prong rifle. Blender axes: x right, y front, z up. ONE skinned mesh (see alienlib.py), one atlas material "Gear"."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: F401,E402
from mathutils import Matrix, Vector  # noqa: E402

from alienlib import make_finalize, surf_y, two_bone, xy_rings  # noqa: E402
from helpers import (empty, export_model, hexc, light, make_material, new_scene, ring_se, rotm, scale_c, set_detail)  # noqa: E402
from humanoid import RigPart, p_visor_sheen  # noqa: E402
from shade import Decal  # noqa: E402
import atlas  # noqa: E402

atlas.PAD = 8             # UV island padding (was 4): no atlas bleed at mip 3+ (10+ m) and on the LOW 1K read
new_scene()
set_detail(1.4)            # round limbs and plates: more segments, tube rings and bevel steps (helpers.DETAIL)
BRIGHT = 2.0
chit = make_material("Chitin", tex="shell")
silk = make_material("Silk", tex="silk")
obs = make_material("Obsidian", tex="glass", color=hexc("#2a3a46"))
glc = make_material("GlowC", tex="glow", color=hexc("#19d8ff"))
gla = make_material("GlowA", tex="glow", color=hexc("#ff9d2e"))
gun = make_material("Gunmetal", tex="steel")


def T(h, k=BRIGHT):
    return scale_c(hexc(h), k)


# value structure (clean-up pass): DARK armour body, slightly lighter slate plates (never pale: the old pearl plates + spikes read as a white halo),
# a lighter helmet shell against an obsidian faceplate, cyan only on the slit, the chest core, the spine line and the rifle coil, amber only on the belt and wrists
SKIN = T("#2c4552", 1.9)
SKIN2 = T("#203540", 1.9)
DARK = T("#0b161e", 2.0)
PEARL = T("#56748a", 1.45)           # plates: mid slate (was near white)
PEARL2 = T("#3a5361", 1.5)
HELM = T("#46606e", 1.25)            # helmet shell: the lightest value, so the dark faceplate reads against it
CLOAK = T("#1f3c4a", 1.9)
CLOAK2 = T("#0f2230", 1.9)
BONE = T("#3b4f58", 1.5)

HIP = (0.0, 0.0, 1.02)
WAIST = (0.0, 0.0, 1.15)
NECK = (0.0, 0.02, 1.58)
RIFLE_O = (0.12, 0.15, 1.41)
SH_Z = 1.49

hips = RigPart("Hips", HIP, None, seed=3)
torso = RigPart("Torso", WAIST, "Hips", seed=5)
head = RigPart("Head", NECK, "Torso", seed=9)
rifle = RigPart("Rifle", RIFLE_O, "Torso", seed=11)
sec = [RigPart("Sec1", (0.0, -0.14, 1.52), "Torso", seed=41), RigPart("Sec2", (0.0, -0.22, 1.22), "Sec1", seed=42),
       RigPart("Sec3", (0.0, -0.27, 0.92), "Sec2", seed=43)]
thigh, shin, foot, uarm, farm = {}, {}, {}, {}, {}
KNEE = (0.0, 0.10, 0.62)
HOCK = (0.0, -0.05, 0.33)
for s, side in ((-1, "L"), (1, "R")):
    x0 = 0.10 * s
    thigh[s] = RigPart("Thigh" + side, (x0, 0.0, 1.02), "Hips", seed=7 + s)
    shin[s] = RigPart("Shin" + side, (x0, KNEE[1], KNEE[2]), "Thigh" + side, seed=21 + s)
    foot[s] = RigPart("Foot" + side, (x0, HOCK[1], HOCK[2]), "Shin" + side, seed=31 + s)

# ------------------------------------------------------------------ hips and legs (digitigrade: knee forward, hock back, toes forward)
TORSO = [(1.10, 0.0, 0.125, 0.095), (1.20, 0.005, 0.135, 0.10), (1.32, 0.012, 0.155, 0.112), (1.43, 0.02, 0.178, 0.118),
         (1.52, 0.02, 0.16, 0.10), (1.58, 0.02, 0.075, 0.065)]
hips.loft(xy_rings([(0.95, 0.0, 0.11, 0.085), (1.03, 0.0, 0.14, 0.10), (1.11, 0.0, 0.125, 0.095)]), mat=chit, tint=SKIN2)
hips.loft(xy_rings([(1.105, 0.0, 0.132, 0.101), (1.117, 0.0, 0.132, 0.101)]), mat=gla)                      # amber belt line
hips.box((0.07, 0.03, 0.09), (0, 0.10, 1.0), mat=chit, tint=PEARL2, bevel=0.006, top=(0.7, 1.0))                # groin plate
for s in (-1, 1):
    x0 = 0.10 * s
    p, q, f = thigh[s], shin[s], foot[s]
    p.tube([(x0, 0.0, 1.03), (x0, 0.05, 0.84), (x0, KNEE[1], KNEE[2])], [(0.098, 0.108), (0.092, 0.106), (0.064, 0.07)], mat=chit, tint=SKIN, n=10, exp=2.2, sub=2)
    p.sphere(0.05, (x0, KNEE[1], KNEE[2]), mat=chit, tint=SKIN2, segs=10, rings=6)
    q.tube([(x0, KNEE[1], KNEE[2]), (x0, 0.03, 0.46), (x0, HOCK[1], HOCK[2])], [(0.064, 0.068), (0.058, 0.074), (0.042, 0.045)], mat=chit, tint=SKIN, n=9, exp=2.2, sub=2)
    q.bar((x0, 0.115, 0.56), (x0, 0.02, 0.4), 0.052, 0.018, mat=chit, tint=PEARL2, bevel=0.005, taper=(0.7, 0.7))   # shin guard
    f.sphere(0.036, (x0, HOCK[1], HOCK[2]), mat=chit, tint=SKIN2, segs=9, rings=6)
    f.tube([(x0, HOCK[1], HOCK[2]), (x0, 0.04, 0.17), (x0, 0.12, 0.05)], [(0.04, 0.044), (0.034, 0.038), (0.038, 0.034)], mat=chit, tint=SKIN, n=8, exp=2.2, sub=1)
    for k, dx in enumerate((-0.032, 0.0, 0.032)):                                                                   # three toes with claws
        f.rod((x0 + dx * 0.4, 0.115, 0.045), (x0 + dx, 0.26, 0.018), 0.017, mat=chit, tint=SKIN2, r2=0.011, segs=7)
        f.rod((x0 + dx, 0.255, 0.02), (x0 + dx, 0.31, 0.008), 0.011, mat=chit, tint=PEARL2, r2=0.004, segs=6)

# ------------------------------------------------------------------ torso
torso.loft(xy_rings(TORSO), mat=chit, tint=SKIN)
torso.loft(xy_rings([(1.52, 0.02, 0.163, 0.103), (1.545, 0.02, 0.15, 0.095)]), mat=chit, tint=PEARL2)              # collar
torso.loft(xy_rings([(1.36, 0.02, 0.172, 0.12), (1.44, 0.026, 0.192, 0.128), (1.50, 0.026, 0.17, 0.11)]), mat=chit, tint=PEARL2, bevel=0.004)     # pectoral shell
for z in (1.16, 1.215, 1.27):                                                                                       # abdominal bands
    torso.loft(xy_rings([(z, 0.008, 0.14 + 0.012 * (z - 1.16) * 3, 0.108), (z + 0.03, 0.01, 0.14 + 0.012 * (z - 1.16) * 3, 0.108)]), mat=chit, tint=DARK)
for k in range(4):                                                                                                  # rib chevrons
    z = 1.26 + 0.065 * k
    for sx in (-1, 1):
        torso.box((0.1, 0.014, 0.016), (sx * 0.055, surf_y(TORSO, z, 0.055) + 0.003, z), rot=(0, 0, -sx * 22), mat=chit, tint=PEARL2, bevel=0.003)
torso.torus(0.07, 0.013, (0, surf_y(TORSO, 1.38) - 0.004, 1.38), rot=(90, 0, 0), mat=chit, tint=PEARL, segs=18, sides=6)            # core frame
torso.sphere(0.05, (0, surf_y(TORSO, 1.38) - 0.008, 1.38), mat=glc, segs=12, rings=8)                                           # quantum core
torso.torus(0.05, 0.004, (0, surf_y(TORSO, 1.38) + 0.004, 1.38), rot=(90, 0, 0), mat=gla, segs=16, sides=4)


def vein(part, mat, pts, r=0.007, back=False):
    """Glowing vein hugging the torso: pts = [(x, z)]."""
    path = [(x, surf_y(TORSO, z, x, back) + (-0.002 if back else 0.002), z) for x, z in pts]
    part.tube(path, [(r, r)] * len(path), mat=mat, n=4, sub=1, up=(0, 1, 0))


for sx in (-1, 1):
    vein(torso, glc, [(sx * 0.045, 1.35), (sx * 0.085, 1.27), (sx * 0.09, 1.17)])
vein(torso, glc, [(0.0, 1.56), (0.0, 1.45), (0.0, 1.30), (0.0, 1.14)], r=0.0055, back=True)                           # glowing spine line (seen from behind)
# phase halo behind the shoulders (a thin luminous ring held by two struts) and an amber node

# ------------------------------------------------------------------ head: swept cranium, smooth faceplate with a cyan slit, crest
neck_pts = [(0, 0.0, 1.5), (0, 0.025, 1.6), (0, 0.045, 1.69)]
head.tube(neck_pts, [(0.045, 0.045), (0.04, 0.04), (0.04, 0.05)], mat=chit, tint=SKIN2, n=8, sub=1)
cran = [(-0.38, 1.745, 0.012, 0.014), (-0.34, 1.77, 0.03, 0.045), (-0.26, 1.80, 0.06, 0.085), (-0.16, 1.81, 0.085, 0.115),
        (-0.06, 1.80, 0.098, 0.13), (0.04, 1.785, 0.095, 0.125), (0.10, 1.765, 0.075, 0.105), (0.125, 1.75, 0.04, 0.07)]
head.loft([ring_se(0, y, zc, rx, rz, 12, 2.2, plane="xz") for y, zc, rx, rz in cran], mat=chit, tint=HELM)
head.sphere((0.083, 0.062, 0.112), (0, 0.075, 1.755), mat=obs, tint=scale_c(hexc("#1b2832"), 1.7), segs=14, rings=9)    # faceplate (obsidian, pearl sheen decal)
head.loft([ring_se(0, y, zc, rx, rz, 4, 2.0, plane="xz") for y, zc, rx, rz in
           [(0.06, 1.90, 0.011, 0.02), (-0.05, 1.925, 0.011, 0.04), (-0.2, 1.915, 0.011, 0.05), (-0.34, 1.87, 0.011, 0.045),
            (-0.46, 1.8, 0.011, 0.03), (-0.55, 1.72, 0.008, 0.012)]], mat=chit, tint=HELM, bevel=0.0)                 # swept crest
slit = [(x, 0.075 + 0.062 * math.sqrt(max(0.02, 1 - (0.02 / 0.112) ** 2 - (x / 0.083) ** 2)) + 0.001, 1.775) for x in (-0.06, -0.04, -0.02, 0.0, 0.02, 0.04, 0.06)]
head.tube(slit, [(0.0065, 0.0055)] * len(slit), mat=glc, n=4, sub=1, up=(0, 1, 0))                              # the thin cyan slit
for sx in (-1, 1):
    pass                                                                                                           # (cheek blades and chin spurs removed: spike clutter)

# ------------------------------------------------------------------ rifle: alien-tech fork-prong weapon (rifle-local axes: +Y muzzle, +Z up)
RR = rotm(1.2, 0, 0)
R = Matrix.Translation(Vector(RIFLE_O)) @ RR


def rp(v):
    return R @ Vector(v)


def rbox(size, pos, mat, tint=(1, 1, 1), **kw):
    rifle.box(size, rp(pos), mat=mat, tint=tint, frame=RR, **kw)


def rrod(a, b, r, mat, tint=(1, 1, 1), **kw):
    rifle.rod(rp(a), rp(b), r, mat=mat, tint=tint, **kw)


rings = [ring_se(0, y, zc, rx, rz, 10, 2.4, plane="xz") for y, zc, rx, rz in
         [(-0.04, -0.02, 0.026, 0.05), (0.1, -0.02, 0.036, 0.07), (0.3, -0.015, 0.038, 0.06), (0.5, 0.0, 0.03, 0.045), (0.66, 0.0, 0.022, 0.032)]]
rifle.loft([[tuple(rp(p)) for p in ring] for ring in rings], mat=chit, tint=BONE)
rifle.sphere((0.05, 0.1, 0.065), rp((0, 0.2, 0.0)), frame=RR, mat=chit, tint=PEARL2, segs=10, rings=7)               # bulb receiver
rbox((0.03, 0.05, 0.03), (0.04, 0.2, 0.0), gla)                                                                      # amber cell window
rbox((0.014, 0.5, 0.03), (0, 0.3, 0.075), chit, PEARL, bevel=0.003, top=(1.0, 0.5))                                  # dorsal fin
rbox((0.03, 0.05, 0.13), (0, 0.235, -0.085), chit, DARK, bevel=0.005)                                                # pistol grip
rbox((0.028, 0.055, 0.075), (0, 0.41, -0.05), chit, DARK, bevel=0.005)                                               # fore-grip
rifle.box((0.034, 0.07, 0.17), rp((0, 0.33, -0.145)), mat=chit, tint=PEARL2, frame=RR @ rotm(-9, 0, 0), bevel=0.006)  # cell (MagWell)
rbox((0.008, 0.05, 0.12), (0.019, 0.33, -0.15), gla)
for sx in (-1, 1):
    rrod((sx * 0.04, 0.6, 0.0), (sx * 0.026, 0.9, 0.0), 0.013, chit, BONE, r2=0.008, segs=7)                          # fork prongs
rrod((0, 0.66, 0), (0, 0.9, 0), 0.01, glc, segs=6)                                                                   # coil between the prongs
for yy in (0.68, 0.76, 0.84):
    rifle.cyl(0.03, 0.007, rp((0, yy, 0)), frame=RR @ rotm(-90, 0, 0), mat=glc, segs=10)
rifle.sphere(0.012, rp((0, 0.915, 0)), mat=glc, segs=6, rings=4)
muzzle = rp((0, 0.915, 0))

# ------------------------------------------------------------------ arms: lean, long, four-fingered hands
hands = {1: rp((0.0, 0.235, -0.115)), -1: rp((0.0, 0.41, -0.012))}
wrists = {1: rp((0.012, 0.19, -0.068)), -1: rp((0.045, 0.325, 0.01))}
wrist_pos = {}
R3 = R.to_3x3()
for s, side in ((-1, "L"), (1, "R")):
    Sv = Vector((0.205 * s, 0.0, SH_Z))
    E, W = two_bone(Sv, wrists[s], 0.33, 0.32, (0.5 * s, -0.5, -1.0))
    wrist_pos[s] = W
    uarm[s] = RigPart("UpperArm" + side, Sv, "Torso", seed=51 + s)
    farm[s] = RigPart("ForeArm" + side, E, "UpperArm" + side, seed=61 + s)
    ua, fa_ = uarm[s], farm[s]
    # translucent layered pearl shoulder plates + a swept spike
    for k, (rx, ry, rz, dx, dz) in enumerate([(0.12, 0.09, 0.03, 0.03, 0.065), (0.105, 0.08, 0.026, 0.065, 0.035), (0.085, 0.068, 0.022, 0.095, 0.008)]):
        ua.sphere((rx, ry, rz), Sv + Vector((s * dx, 0.0, dz)), rot=(0, s * (18 + 10 * k), 0), mat=chit, tint=PEARL if k == 0 else PEARL2, segs=12, rings=7)
    ua.tube([Sv + Vector((0, 0, 0.0)), (Sv + E) / 2 + Vector((s * 0.01, 0, 0)), E], [(0.044, 0.044), (0.038, 0.038), (0.034, 0.034)], mat=chit, tint=SKIN, n=9, sub=1)
    fa_.sphere(0.036, E, mat=chit, tint=SKIN2, segs=9, rings=6)
    fv = W - E
    fa_.tube([E, E + fv * 0.5, W], [(0.034, 0.034), (0.031, 0.031), (0.024, 0.024)], mat=chit, tint=SKIN, n=9, sub=1)
    fa_.bar(E + fv * 0.25, E + fv * 0.72, 0.062, 0.05, mat=chit, tint=DARK, bevel=0.006, taper=(0.8, 0.8))                # bracer
    fa_.rod(E + fv * 0.78, E + fv * 0.82, 0.032, mat=gla, segs=10)                                                        # amber wrist ring
    # hand: palm + FOUR long fingers wrapping the rifle + thumb spur
    h = hands[s]
    fa_.tube([W - fv.normalized() * 0.02, h], [(0.026, 0.026), (0.032, 0.03)], mat=chit, tint=SKIN2, n=8, sub=0)
    fa_.box((0.046, 0.07, 0.07), h, mat=chit, tint=SKIN2, frame=RR, bevel=0.01, bsegs=1)
    for k in range(4):
        zk = 0.03 - 0.02 * k
        a = h + R3 @ Vector((0, 0.022, zk))
        b = h + R3 @ Vector((0, 0.07, zk + 0.002))
        c = h + R3 @ Vector((0, 0.088, zk + 0.02 - 0.003 * k))
        fa_.rod(a, b, 0.0108, mat=chit, tint=SKIN2, r2=0.0092, segs=7)
        fa_.sphere(0.0105, a, mat=chit, tint=PEARL2, segs=6, rings=4)
        fa_.rod(b, c, 0.0092, mat=chit, tint=PEARL, r2=0.003, segs=6)
    fa_.rod(h + R3 @ Vector((-s * 0.02, 0.0, 0.04)), h + R3 @ Vector((-s * 0.045, 0.05, 0.055)), 0.009, mat=chit, tint=PEARL, r2=0.002, segs=5)

# ------------------------------------------------------------------ silhouette pass: layered pauldrons, gorget and standing collar, hip skirt, thigh and knee armour, hand plates, grip
for s in (-1, 1):
    ua = uarm[s]
    Sv = Vector((0.205 * s, 0.0, SH_Z))
    for k in range(3):                                       # descending lamellae: a stepped pauldron that reads from every side
        ua.sphere((0.135 - 0.012 * k, 0.105 - 0.006 * k, 0.02), Sv + Vector((s * (0.095 + 0.04 * k), 0.0, -0.005 - 0.065 * k)), rot=(0, s * (34 + 17 * k), 0),
                  mat=chit, tint=PEARL2 if k % 2 else PEARL, segs=12, rings=6)
    ua.sphere((0.1, 0.085, 0.04), Sv + Vector((s * 0.06, -0.01, 0.075)), rot=(0, s * 20, 0), mat=chit, tint=PEARL, segs=12, rings=6)     # one smooth dome instead of the spikes
torso.loft(xy_rings([(1.50, 0.02, 0.215, 0.14), (1.57, 0.03, 0.17, 0.12)], n=12), mat=chit, tint=PEARL2, bevel=0.004)                 # flared gorget
torso.box((0.3, 0.03, 0.2), (0, -0.105, 1.63), rot=(-14, 0, 0), mat=chit, tint=SKIN2, bevel=0.008, top=(0.55, 1.0))             # standing collar behind the head
torso.loft(xy_rings([(1.52, -0.02, 0.25, 0.15), (1.42, -0.055, 0.27, 0.165), (1.31, -0.085, 0.225, 0.165)], n=12), mat=silk, tint=CLOAK)  # mantle over the shoulders
for s in (-1, 1):
    hips.box((0.05, 0.19, 0.21), (s * 0.165, 0.0, 0.96), rot=(0, 0, -s * 10), mat=chit, tint=PEARL2, bevel=0.008, top=(0.8, 1.0))      # hip skirt plates
    x0 = 0.10 * s
    thigh[s].box((0.13, 0.1, 0.26), (x0 + s * 0.02, 0.08, 0.8), rot=(-6, 0, s * 4), mat=chit, tint=PEARL, bevel=0.01, bsegs=2, top=(0.85, 0.9))   # thigh armour
    thigh[s].sphere((0.075, 0.05, 0.075), (x0, KNEE[1] + 0.045, KNEE[2] + 0.015), mat=chit, tint=PEARL2, segs=12, rings=7)             # knee guard
    shin[s].torus(0.052, 0.009, (x0, 0.03, 0.45), mat=chit, tint=PEARL, segs=12, sides=4)
    foot[s].box((0.075, 0.13, 0.05), (x0, 0.09, 0.075), rot=(8, 0, 0), mat=chit, tint=PEARL2, bevel=0.008, top=(0.7, 0.9))                 # toe cap
    h = hands[s]
    farm[s].box((0.052, 0.075, 0.014), h + R3 @ Vector((0, 0.01, 0.05)), frame=RR, mat=chit, tint=PEARL2, bevel=0.004)                  # back-of-hand plate
rbox((0.04, 0.07, 0.17), (0, 0.235, -0.1), chit, DARK, bevel=0.006)                                                                    # fuller grip
rbox((0.008, 0.08, 0.035), (0, 0.3, -0.06), chit, PEARL2, bevel=0.002)                                                                 # trigger guard
rbox((0.045, 0.05, 0.03), (0, 0.46, -0.07), chit, PEARL2, bevel=0.005)                                                                 # hand rest

# ------------------------------------------------------------------ phase cloak: tattered tapering strips on the Sec chain (swayed by the rig)
seg_defs = [(sec[0], 1.52, 1.22, 0.10, 0.0), (sec[1], 1.22, 0.92, 0.12, 0.04), (sec[2], 0.92, 0.5, 0.14, 0.09)]
for si, (p, z0, z1, rad, flare) in enumerate(seg_defs):
    n = 8
    for j in range(n):
        phi = -68.0 + 136.0 * j / (n - 1)
        a = math.radians(phi)
        rd = Vector((math.sin(a), -math.cos(a), 0.0))
        jag = 1.0                     # a straight clean hem (the jagged hem read as noise from the chase camera)
        L = (z0 - z1) * jag
        top = Vector((rad * 1.45 * math.sin(a), -0.115 - rad * 0.9 * math.cos(a) - 0.05 * si, z0 + 0.02))
        bot = top + Vector((rd.x * flare, rd.y * (flare + 0.03), -L - 0.02))
        w = 0.066 + 0.016 * si                                   # half width: neighbouring ribbons overlap, so the cloak reads as one solid sheet
        tip = 0.8 if si == 2 else (0.9 if si == 1 else 0.95)       # wider hem: a solid cape shape, not tattered strips
        mid = top + (bot - top) * 0.5 + rd * 0.012
        # a solid satin ribbon (smooth elliptic section, thin along the radial direction, wide along the tangent), no alpha, no grain
        p.tube([top, mid, bot], [(0.006, w), (0.0065, w * (0.5 + 0.5 * tip)), (0.003, w * tip * 0.5)], mat=silk,
               tint=CLOAK if (j + si) % 2 == 0 else CLOAK2, n=6, up=rd, sub=1, exp=2.6)
    if si == 0:
        p.loft(xy_rings([(1.50, -0.02, 0.17, 0.115), (1.44, -0.05, 0.19, 0.13)]), mat=silk, tint=CLOAK)

# ------------------------------------------------------------------ export
parts = [hips, torso, head, uarm[-1], farm[-1], uarm[1], farm[1], rifle] + [thigh[s] for s in (-1, 1)] + [shin[s] for s in (-1, 1)] + [foot[s] for s in (-1, 1)] + sec
# parts must be exported in CORE order of bones only for the armature: finalize looks bones up by name
rig = [empty("Muzzle", muzzle), empty("WristL", wrist_pos[-1]), empty("WristR", wrist_pos[1]),
       empty("MagWell", rp((0, 0.33, -0.2))), empty("MagPouch", (-0.09, 0.2, 1.13)),
       light("Fill", (0.0, 0.8, 1.55), "omni", (0.5, 0.85, 1.0), 1.1, 3.6, mask="own", attenuation=1.2, fade=(30, 12)),
       light("Rim", (0.25, -0.8, 2.15), "omni", (0.35, 0.85, 1.0), 1.5, 3.8, mask="own", attenuation=1.2, fade=(30, 12))]
print("  parts=%d tris(before culling)=%d" % (len(parts), sum(p.tri_count() for p in parts)), {p.name: p.tri_count() for p in parts})
decals = [Decal((0.0, 0.1, 1.76), (0, 1, 0), (0, 0, 1), (0.2, 0.2), p_visor_sheen(hexc("#19d8ff")), depth=0.08, kinds=("glass",), min_dot=0.2)]
export_model("player", parts, extras=rig, size=1024, decals=decals, ao_dist=0.2, ao_strength=0.55, emit_strength=1.25,
             finalize=make_finalize(["Sec1", "Sec2", "Sec3"]), hipoly=dict(levels=2))
