"""The enemy armour kit: helmets, vests, pauldrons, packs, shields and props for 13 human looks (6 contract mercenaries, 7 authority troopers), fitted to the T-pose Quaternius body.

One function per piece; every piece registers its Part(s) in the Kit with a bone, a kind (shader palette slot), a glow zone and the looks it belongs to. Blender axes: x = right, y = forward,
z = up, metres. Body landmarks (T pose): feet z 0, ankle 0.086, knee 0.542, hip joint 0.971, pelvis 0.949, spine 1.07 / 1.18 / 1.31, neck 1.52, head centre (0, -0.012, 1.70) 0.18 wide, 0.21 deep,
top 1.81, chin 1.565; shoulder joint (+-0.212, -0.065, 1.455), elbow x 0.463, wrist x 0.706; chest depth y -0.144 .. 0.121 at z 1.3.

Silhouette rules (they decide what reads at 15-80 m on a phone): the HEAD shape (cap brim, antenna, filters, hood, hard hat), the SHOULDER line (pad size), what sticks out of the BACK (tube, rack, antenna,
tripod, power cell), the thing in the HAND or FRONT (shield, charges, bandolier) and two or three colour blocks. Fine detail is for the 15 m view only.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lib import (K_BRASS, K_CLOTH, K_DARK, K_FABRIC_A, K_FABRIC_B, K_GLASS, K_GLOW, K_HAZARD, K_MARK, K_PLATE_A, K_PLATE_B, K_RUBBER, K_STEEL, K_TRIM, Z_PIPS, Z_TELL, Z_TRIM, Z_VISOR,  # noqa: E402
                 Z_WEAK, bar, box, cyl, dome_profile, lathe, rod, sphere, R)

HY = -0.012                       # the vertical axis of the head
MERCS = "merc_rifle,merc_shotgun,merc_rocket,merc_medic,merc_officer,merc_sniper"
AUTH = "auth_rifle,auth_riot,auth_heavy,auth_breacher,auth_ghost,auth_drone,auth_engineer"
ALL = MERCS + "," + AUTH


def _p(kit, name):
    return kit.new(name)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# shared: boots, gloves, belt, knees
# ------------------------------------------------------------------------------------------------------------------------------------------------

def boots(kit, looks=ALL, tall=0.34, bulk=1.0):
    p = _p(kit, "boot_foot")
    box(p, (0.108 * bulk, 0.29, 0.095), (0.114, 0.03, 0.068), bevel=0.014, mirror=True, top=(0.96, 0.92))
    box(p, (0.1 * bulk, 0.075, 0.065), (0.114, 0.185, 0.05), bevel=0.012, mirror=True, top=(0.9, 0.7))
    box(p, (0.104 * bulk, 0.07, 0.08), (0.114, -0.105, 0.05), bevel=0.01, mirror=True)
    kit.done(p, "foot_r", K_FABRIC_B, 0, looks, lr=True)
    p = _p(kit, "boot_sole")
    box(p, (0.116 * bulk, 0.325, 0.026), (0.114, 0.03, 0.013), bevel=0.006, mirror=True, top=(1.0, 0.94))
    kit.done(p, "foot_r", K_RUBBER, 0, looks, lr=True)
    p = _p(kit, "boot_shaft")
    cyl(p, 0.082 * bulk, tall - 0.08, (0.114, -0.036, 0.08 + (tall - 0.08) / 2), r2=0.076 * bulk, segs=10, bevel=0.0, mirror=True)
    cyl(p, 0.088 * bulk, 0.024, (0.114, -0.036, tall), segs=10, mirror=True)
    kit.done(p, "calf_r", K_FABRIC_B, 0, looks, lr=True)


def gloves(kit, looks=ALL, kind=K_RUBBER, cuff=K_FABRIC_B, long_cuff=False):
    """Mitts that cover the whole hand (palm, fingers, thumb): the fingers of the base body are removed under them."""
    p = _p(kit, "glove")
    box(p, (0.17, 0.085, 0.105), (0.79, -0.062, 1.456), bevel=0.014, mirror=True, top=(0.8, 0.85))
    box(p, (0.07, 0.05, 0.1), (0.755, 0.0, 1.43), bevel=0.012, mirror=True)
    box(p, (0.09, 0.07, 0.1), (0.705, -0.065, 1.456), bevel=0.012, mirror=True)
    kit.done(p, "hand_r", kind, 0, looks, lr=True)
    p = _p(kit, "glove_cuff")
    cyl(p, 0.062, 0.1 if long_cuff else 0.06, (0.665 if long_cuff else 0.672, -0.07, 1.455), axis="x", segs=8, mirror=True)
    kit.done(p, "lowerarm_r", cuff, 0, looks, lr=True)


def belt(kit, looks=ALL, kind=K_DARK, pouches=3, width=0.2, heavy=False):
    p = _p(kit, "belt")
    cyl(p, 0.188, 0.07, (0.0, -0.01, 1.03), segs=14, ry=0.158, ry2=0.158, bevel=0.0)
    kit.done(p, "pelvis", kind, 0, looks)
    p = _p(kit, "belt_buckle")
    box(p, (0.06, 0.02, 0.05), (0.0, 0.158, 1.03), bevel=0.004)
    kit.done(p, "pelvis", K_STEEL, 0, looks)
    p = _p(kit, "belt_pouch")
    for i in range(pouches):
        x = 0.07 + 0.065 * i
        box(p, (0.055, 0.05, 0.085), (x, 0.145, 0.995), bevel=0.006, mirror=True)
    if heavy:
        box(p, (0.07, 0.12, 0.09), (0.215, -0.01, 0.98), bevel=0.008, mirror=True)
    kit.done(p, "pelvis", K_FABRIC_A, 0, looks, lr=False)


def knees(kit, looks=ALL, big=False, kind=K_PLATE_B):
    p = _p(kit, "knee_pad")
    r = 0.078 if big else 0.064
    sphere(p, r, (0.114, 0.05, 0.545), scale=(1.12, 0.46, 1.1), segs=8, rings=5, mirror=True)
    kit.done(p, "calf_r", kind, 0, looks, lr=True)


def shins(kit, looks=ALL, kind=K_PLATE_A):
    p = _p(kit, "shin_guard")
    box(p, (0.1, 0.045, 0.27), (0.114, 0.045, 0.34), bevel=0.01, mirror=True, top=(0.85, 1.0))
    kit.done(p, "calf_r", kind, 0, looks, lr=True)


def thigh_plates(kit, looks=ALL, kind=K_PLATE_A, w=0.12):
    p = _p(kit, "thigh_plate")
    box(p, (w, 0.05, 0.24), (0.118, 0.07, 0.8), bevel=0.01, mirror=True, top=(0.88, 1.0))
    kit.done(p, "thigh_r", kind, 0, looks, lr=True)


def leg_stripe(kit, looks, glow=True):
    """A lit stripe down the outer thigh and shin: the authority's 'uniform' that reads on the move."""
    p = _p(kit, "leg_stripe")
    box(p, (0.012, 0.03, 0.4), (0.196, -0.03, 0.78), bevel=0.0, mirror=True)
    box(p, (0.012, 0.03, 0.26), (0.192, -0.02, 0.36), bevel=0.0, mirror=True)
    kit.done(p, "thigh_r", K_TRIM, Z_TRIM if glow else 0, looks, lr=True)


def cargo(kit, looks, kind=K_FABRIC_A):
    p = _p(kit, "cargo")
    box(p, (0.05, 0.1, 0.12), (0.205, 0.0, 0.76), bevel=0.006)
    box(p, (0.05, 0.1, 0.12), (-0.205, 0.0, 0.76), bevel=0.006)
    kit.done(p, "thigh_r", kind, 0, looks)


def holster(kit, looks, side=1.0):
    p = _p(kit, "holster")
    box(p, (0.045, 0.085, 0.16), (side * 0.2, 0.0, 0.88), bevel=0.008)
    box(p, (0.03, 0.05, 0.05), (side * 0.2, 0.05, 0.96), bevel=0.006)
    kit.done(p, "thigh_r" if side > 0 else "thigh_l", K_DARK, 0, looks)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# torso: vests and plates
# ------------------------------------------------------------------------------------------------------------------------------------------------

def vest_light(kit, looks, plate=K_PLATE_A, cloth=K_FABRIC_B, w=0.3, h=0.34, deep=0.05):
    """A plate carrier: front and back plate, shoulder straps, cummerbund and three magazine pouches."""
    p = _p(kit, "vest_plate")
    box(p, (w * 0.86, deep, h * 0.82), (0.0, 0.14, 1.335), bevel=0.014, top=(0.8, 1.0), bsegs=2)
    box(p, (w * 0.9, deep, h * 0.85), (0.0, -0.185, 1.33), bevel=0.014, top=(0.85, 1.0), bsegs=2)
    kit.done(p, "spine_03", plate, 0, looks)
    p = _p(kit, "vest_cloth")
    for s_ in (-1.0, 1.0):
        box(p, (0.065, 0.31, 0.03), (s_ * 0.095, -0.02, 1.505), bevel=0.006)
        box(p, (0.07, 0.04, 0.2), (s_ * 0.095, 0.12, 1.405), bevel=0.006)
    cyl(p, 0.2, 0.16, (0.0, -0.025, 1.14), segs=14, ry=0.162, ry2=0.162, bevel=0.0)
    box(p, (w * 1.02, 0.07, h * 0.9), (0.0, 0.13, 1.33), bevel=0.012, top=(0.84, 1.0))
    kit.done(p, "spine_02", cloth, 0, looks)
    p = _p(kit, "vest_pouch")
    for i in range(3):
        box(p, (0.06, 0.05, 0.085), (-0.08 + 0.08 * i, 0.188, 1.17), bevel=0.006)
    kit.done(p, "spine_02", K_FABRIC_A, 0, looks)


def vest_auth(kit, looks, heavy=False, stripe=True):
    """Authority armour: a ridged breastplate over a banded abdomen, a high collar and the white-blue stripe."""
    big = 1.18 if heavy else 1.0
    p = _p(kit, "auth_chest")
    # breastplate: a loft of three rings (waist, chest, collar)
    rings = []
    for z, rx, ry, dz in ((1.11, 0.188 * big, 0.152 * big, 0.0), (1.28, 0.218 * big, 0.172 * big, 0.0), (1.42, 0.206 * big, 0.158 * big, 0.0), (1.50, 0.15 * big, 0.125 * big, 0.0)):
        ring = []
        for j in range(14):
            a = 2.0 * math.pi * j / 14
            ring.append((rx * math.cos(a), -0.02 + ry * math.sin(a), z))
        rings.append(ring)
    p.loft(rings, mat=__import__("helpers").MATS["enemy_kit"], caps=(False, False), closed=False, bevel=0.0, sharp=75.0, outward_from=(0, -0.02, 1.3))
    kit.done(p, "spine_03", K_PLATE_A, 0, looks)
    p = _p(kit, "auth_ridge")
    box(p, (0.034, 0.05, 0.3), (0.0, 0.158 * big, 1.28), bevel=0.008, top=(0.7, 1.0))
    for z in (1.2, 1.3, 1.4):
        box(p, (0.18 * big, 0.03, 0.026), (0.0, 0.148 * big, z), bevel=0.006)
    kit.done(p, "spine_03", K_PLATE_B, 0, looks)
    if stripe:
        p = _p(kit, "auth_stripe")
        box(p, (0.05, 0.015, 0.26), (-0.1 * big, 0.171 * big, 1.3), bevel=0.003)
        box(p, (0.05, 0.015, 0.26), (0.1 * big, 0.171 * big, 1.3), bevel=0.003)
        kit.done(p, "spine_03", K_TRIM, Z_TRIM, looks)
    p = _p(kit, "auth_back")
    box(p, (0.26 * big, 0.06, 0.32), (0.0, -0.185 * big, 1.3), bevel=0.012, top=(0.9, 1.0))
    kit.done(p, "spine_03", K_PLATE_A, 0, looks)
    p = _p(kit, "auth_belt")
    cyl(p, 0.2 * big, 0.12, (0.0, -0.02, 1.05), segs=14, ry=0.165 * big, ry2=0.165 * big)
    kit.done(p, "pelvis", K_DARK, 0, looks)
    p = _p(kit, "auth_pouch")
    for i in range(3):
        box(p, (0.06, 0.05, 0.085), (-0.085 + 0.085 * i, 0.165 * big, 1.04), bevel=0.006)
    kit.done(p, "pelvis", K_FABRIC_A, 0, looks)


def collar(kit, looks, r=0.1, h=0.07, kind=K_PLATE_A, z=1.545, flare=1.0):
    p = _p(kit, "collar")
    lathe(p, None, [(r * 0.96, z - h / 2), (r * flare, z + h / 2), (r * 0.98 * flare, z + h / 2)] if False else [(r * 0.94, z - h / 2), (r, z), (r * flare, z + h / 2)], center=(0, -0.03, 0), sx=1.0, sy=1.0, segs=12)
    kit.done(p, "spine_03", kind, 0, looks)


def pips(kit, looks, front=True, back=True, z_front=1.44, z_back=1.56, n=5):
    """Health pips: a row of n small lights, lit while health lasts (the shader reads the pip index from UV2): a bar on the upper chest and one on the back of the neck."""
    if front:
        p = _p(kit, "pips_front")
        for i in range(n):
            x = (i - (n - 1) / 2.0) * 0.026
            box(p, (0.016, 0.03, 0.016), (x, 0.172, z_front), bevel=0.0)
        kit.done(p, "spine_03", K_GLOW, Z_PIPS, looks)
    if back:
        p = _p(kit, "pips_back")
        for i in range(n):
            x = (i - (n - 1) / 2.0) * 0.03
            box(p, (0.018, 0.03, 0.018), (x, -0.135, z_back), bevel=0.0)
        kit.done(p, "spine_03", K_GLOW, Z_PIPS, looks)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# shoulders and arms
# ------------------------------------------------------------------------------------------------------------------------------------------------

def pauldron(kit, looks, size=1.0, lames=2, kind=K_PLATE_A, fin=False, spike=False, trim=True):
    """A dome around the shoulder joint (it turns with the arm and never cuts the skin) with `lames` overlapping bands."""
    p = _p(kit, "pauldron")
    jx, jy, jz = 0.212, -0.065, 1.455
    r = 0.112 * size
    prof = dome_profile(r, 0.0, r * 0.92, n=5, power=1.0)
    # dome opening toward the arm (-x for the right shoulder pointing outward): revolve about the x axis -> use a rotated lathe: build about z then rotate by 90 deg about y
    from helpers import MATS
    verts, faces = [], []
    segs = 12
    for k, (rr, zz) in enumerate(prof):
        for j in range(segs):
            a = 2.0 * math.pi * j / segs
            # axis along +x (outward): local z -> world x, local x -> world -z... keep it simple: x = jx + zz, y = jy + rr*cos, z = jz + rr*sin
            verts.append((jx - 0.02 + zz, jy + rr * math.cos(a) * 1.05, jz + rr * math.sin(a) * 0.95))
    for k in range(len(prof) - 1):
        for j in range(segs):
            a_ = k * segs + j
            b_ = k * segs + (j + 1) % segs
            c_ = (k + 1) * segs + (j + 1) % segs
            d_ = (k + 1) * segs + j
            faces.append((a_, d_, c_, b_))
    p.raw(verts, faces, MATS["enemy_kit"], closed=False, bevel=0.0, sharp=70.0, mirror=True)
    for i in range(lames):
        z = jz + r * (0.55 - 0.42 * i)
        w = r * (1.15 - 0.12 * i)
        box(p, (0.07 * size, w * 1.9, 0.034 * size), (jx + r * 0.78 + 0.01 * i, jy, z - 0.02 * i), rot=(0, 0, 0), bevel=0.006, mirror=True)
    if spike:
        rod(p, (jx + 0.02, jy, jz + r * 0.8), (jx + 0.08, jy - 0.02, jz + r * 1.9), 0.026, 0.004, segs=5, mirror=True)
    if fin:
        box(p, (0.012, 0.16 * size, 0.1 * size), (jx + 0.12 * size, jy - 0.03, jz + 0.1 * size + 0.04), bevel=0.003, mirror=True, top=(1.0, 0.4))
    kit.done(p, "upperarm_r", kind, 0, looks, lr=True)
    if trim:
        p = _p(kit, "pauldron_trim")
        box(p, (0.012, r * 1.5, 0.02), (jx + r * 0.95 + 0.012, jy, jz + 0.01), bevel=0.002, mirror=True)
        kit.done(p, "upperarm_r", K_TRIM, 0, looks, lr=True)


def vambrace(kit, looks, kind=K_PLATE_B, long=False):
    p = _p(kit, "vambrace")
    L = 0.26 if long else 0.2
    box(p, (L, 0.09, 0.085), (0.54, -0.074, 1.455), bevel=0.01, mirror=True, top=(1.0, 0.85))
    kit.done(p, "lowerarm_r", kind, 0, looks, lr=True)


def elbow(kit, looks, kind=K_PLATE_B):
    p = _p(kit, "elbow_pad")
    box(p, (0.07, 0.085, 0.085), (0.46, -0.12, 1.455), bevel=0.012, mirror=True)
    kit.done(p, "lowerarm_r", kind, 0, looks, lr=True)


def armband(kit, looks, kind=K_TRIM, x=0.33):
    p = _p(kit, "armband")
    cyl(p, 0.062, 0.05, (x, -0.068, 1.455), axis="x", segs=8, mirror=True)
    kit.done(p, "upperarm_r", kind, 0, looks, lr=True)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# helmets and hats (bone Head)
# ------------------------------------------------------------------------------------------------------------------------------------------------

def _shell(kit, name, looks, rx, ry, rim_z, top_z, kind, n=6, power=1.0, band=0.03, segs=14, cz=0.0, tilt=0.0):
    p = _p(kit, name)
    prof = [(rx * 0.985, rim_z - band)] + dome_profile(rx, rim_z, top_z, n, power)
    lathe(p, None, prof, center=(0.0, HY, cz), sx=1.0, sy=ry / rx, segs=segs, tilt=tilt)
    kit.done(p, "Head", kind, 0, looks)
    return p


def helm_trooper(kit, looks):
    _shell(kit, "helm_shell", looks, 0.113, 0.128, 1.665, 1.86, K_PLATE_A, n=7)
    p = _p(kit, "helm_visor")
    box(p, (0.165, 0.045, 0.058), (0.0, 0.098, 1.722), bevel=0.01, top=(0.96, 1.0))
    kit.done(p, "Head", K_GLASS, 0, looks)
    p = _p(kit, "helm_visor_glow")
    box(p, (0.14, 0.01, 0.022), (0.0, 0.123, 1.722), bevel=0.003)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "helm_crest")
    box(p, (0.022, 0.26, 0.075), (0.0, -0.03, 1.895), bevel=0.004, top=(1.0, 0.55))
    box(p, (0.17, 0.05, 0.05), (0.0, -0.132, 1.655), bevel=0.008)
    for s in (-1.0, 1.0):
        box(p, (0.03, 0.09, 0.09), (s * 0.108, 0.01, 1.7), bevel=0.006)
    kit.done(p, "Head", K_PLATE_B, 0, looks)
    p = _p(kit, "helm_mask")
    box(p, (0.125, 0.045, 0.075), (0.0, 0.098, 1.612), bevel=0.01, top=(0.85, 1.0))
    for s in (-1.0, 1.0):
        cyl(p, 0.022, 0.04, (s * 0.04, 0.125, 1.6), axis="y", segs=6)
    kit.done(p, "Head", K_DARK, 0, looks)


def helm_riot(kit, looks):
    _shell(kit, "helm_shell", looks, 0.118, 0.134, 1.64, 1.87, K_PLATE_A, n=7)
    p = _p(kit, "helm_flare")                                   # neck guard that flares at the back, and a chin bar
    box(p, (0.19, 0.07, 0.1), (0.0, -0.14, 1.62), bevel=0.01, top=(1.0, 1.0), rot=(-12, 0, 0))
    box(p, (0.13, 0.04, 0.03), (0.0, 0.11, 1.575), bevel=0.006)
    kit.done(p, "Head", K_PLATE_B, 0, looks)
    p = _p(kit, "helm_visor")                                   # the big clear visor: a wide curved panel
    box(p, (0.17, 0.05, 0.115), (0.0, 0.1, 1.71), bevel=0.014, top=(0.94, 1.0))
    kit.done(p, "Head", K_GLASS, 0, looks)
    p = _p(kit, "helm_visor_glow")
    box(p, (0.15, 0.01, 0.014), (0.0, 0.127, 1.77), bevel=0.003)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "helm_light")
    for s in (-1.0, 1.0):
        box(p, (0.03, 0.04, 0.03), (s * 0.118, 0.0, 1.825), bevel=0.004)
    kit.done(p, "Head", K_TRIM, Z_TRIM, looks)


def helm_heavy(kit, looks):
    p = _p(kit, "helm_shell")
    box(p, (0.25, 0.27, 0.2), (0.0, HY, 1.76), bevel=0.03, bsegs=2, top=(0.82, 0.86))
    box(p, (0.22, 0.2, 0.1), (0.0, HY - 0.03, 1.855), bevel=0.02, top=(0.8, 0.9))
    kit.done(p, "Head", K_PLATE_A, 0, looks)
    p = _p(kit, "helm_jaw")                                     # heavy jaw / mask block and a neck ring
    box(p, (0.19, 0.075, 0.1), (0.0, 0.1, 1.6), bevel=0.014, top=(0.8, 1.0))
    cyl(p, 0.11, 0.07, (0.0, -0.03, 1.545), segs=10, bevel=0.0)
    for s in (-1.0, 1.0):
        box(p, (0.04, 0.12, 0.12), (s * 0.13, 0.02, 1.66), bevel=0.01)
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "helm_visor")
    box(p, (0.2, 0.04, 0.052), (0.0, 0.118, 1.725), bevel=0.01)
    kit.done(p, "Head", K_GLASS, 0, looks)
    p = _p(kit, "helm_visor_glow")
    box(p, (0.18, 0.012, 0.024), (0.0, 0.14, 1.725), bevel=0.003)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "helm_horns")
    for s in (-1.0, 1.0):
        rod(p, (s * 0.11, 0.0, 1.86), (s * 0.15, 0.04, 1.97), 0.024, 0.006, segs=5)
    kit.done(p, "Head", K_PLATE_B, 0, looks)


def helm_gas(kit, looks):
    _shell(kit, "helm_shell", looks, 0.113, 0.126, 1.66, 1.855, K_PLATE_A, n=6)
    p = _p(kit, "helm_mask")                                    # gas mask: a muzzle with a big front canister and two side filters
    box(p, (0.14, 0.06, 0.12), (0.0, 0.095, 1.64), bevel=0.014, top=(0.8, 1.0))
    cyl(p, 0.05, 0.1, (0.0, 0.17, 1.62), axis="y", segs=10, bevel=0.003, r2=0.046)
    for s in (-1.0, 1.0):
        cyl(p, 0.03, 0.07, (s * 0.1, 0.06, 1.615), axis="y", segs=8)
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "helm_goggles")                                  # two big round lenses
    for s in (-1.0, 1.0):
        cyl(p, 0.038, 0.05, (s * 0.05, 0.108, 1.725), axis="y", segs=10, r2=0.034)
    kit.done(p, "Head", K_STEEL, 0, looks)
    p = _p(kit, "helm_lens")
    for s in (-1.0, 1.0):
        cyl(p, 0.029, 0.02, (s * 0.05, 0.136, 1.725), axis="y", segs=10)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "helm_plate")
    box(p, (0.02, 0.18, 0.04), (0.0, -0.02, 1.88), bevel=0.004, top=(1.0, 0.5))
    box(p, (0.16, 0.06, 0.06), (0.0, -0.13, 1.655), bevel=0.01)
    kit.done(p, "Head", K_PLATE_B, 0, looks)


def hood_ghost(kit, looks):
    p = _p(kit, "hood")
    lathe(p, None, [(0.135, 1.585), (0.15, 1.65)] + dome_profile(0.15, 1.65, 1.9, n=6)[1:], center=(0.0, HY - 0.015, 0.0), sx=1.0, sy=1.12, segs=12)
    kit.done(p, "Head", K_CLOTH, 0, looks)
    p = _p(kit, "hood_front")                                    # the cowl opening: a dark mask and the single glowing lens
    box(p, (0.12, 0.05, 0.1), (0.0, 0.1, 1.655), bevel=0.012, top=(0.85, 1.0))
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "hood_lens")
    cyl(p, 0.026, 0.03, (0.04, 0.132, 1.72), axis="y", segs=10)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "hood_strands")                                   # shaggy strips hanging from the brow
    for i in range(9):
        a = math.radians(-70 + 17.5 * i)
        x, y = 0.145 * math.sin(a), HY + 0.16 * math.cos(a)
        rod(p, (x * 0.9, y * 0.95 + 0.0, 1.78), (x * 1.18, y + 0.03 * math.cos(a), 1.62 - 0.03 * (i % 3)), 0.012, 0.004, segs=4)
    kit.done(p, "Head", K_CLOTH, 0, looks)


def helm_vr(kit, looks):
    _shell(kit, "helm_shell", looks, 0.108, 0.122, 1.675, 1.845, K_PLATE_B, n=6)
    p = _p(kit, "helm_visor")                                    # a wrap-around visor band
    box(p, (0.19, 0.075, 0.07), (0.0, 0.088, 1.718), bevel=0.016, top=(0.9, 1.0))
    kit.done(p, "Head", K_GLASS, 0, looks)
    p = _p(kit, "helm_visor_glow")
    box(p, (0.17, 0.01, 0.018), (0.0, 0.126, 1.72), bevel=0.003)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "helm_ears")                                     # radio ear cups and two whip antennas
    for s in (-1.0, 1.0):
        cyl(p, 0.04, 0.035, (s * 0.112, 0.0, 1.71), axis="x", segs=8)
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "helm_antenna")
    rod(p, (0.1, -0.05, 1.72), (0.13, -0.13, 2.16), 0.007, 0.004, segs=4)
    rod(p, (-0.1, -0.05, 1.72), (-0.13, -0.13, 2.0), 0.006, 0.003, segs=4)
    sphere(p, 0.014, (0.13, -0.13, 2.165), segs=6, rings=4)
    kit.done(p, "Head", K_STEEL, 0, looks)
    p = _p(kit, "helm_tip")
    sphere(p, 0.016, (0.13, -0.13, 2.17), segs=6, rings=4)
    kit.done(p, "Head", K_GLOW, Z_WEAK, looks)


def helm_hard(kit, looks):
    _shell(kit, "helm_shell", looks, 0.112, 0.126, 1.68, 1.84, K_TRIM, n=5)
    p = _p(kit, "helm_brim")                                     # hard hat: short brim all round, a ridge, a head lamp
    lathe(p, None, [(0.19, 1.685), (0.185, 1.7), (0.11, 1.7), (0.11, 1.685)][::-1] if False else [(0.11, 1.678), (0.17, 1.676), (0.19, 1.684), (0.17, 1.69), (0.11, 1.692)], center=(0.0, HY, 0.0), sx=1.0, sy=1.12, segs=14)
    box(p, (0.03, 0.2, 0.025), (0.0, HY, 1.853), bevel=0.004)
    kit.done(p, "Head", K_TRIM, 0, looks)
    p = _p(kit, "helm_lamp")
    box(p, (0.05, 0.04, 0.04), (0.0, 0.11, 1.8), bevel=0.006)
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "helm_lamp_glow")
    box(p, (0.034, 0.01, 0.028), (0.0, 0.133, 1.8), bevel=0.002)
    kit.done(p, "Head", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "helm_welder")                                   # the welding shield flipped up on the brow
    box(p, (0.17, 0.06, 0.12), (0.0, 0.08, 1.83), bevel=0.012, rot=(-52, 0, 0), top=(1.0, 0.9))
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "helm_goggles")                                  # goggles over the eyes
    box(p, (0.16, 0.04, 0.05), (0.0, 0.1, 1.72), bevel=0.01)
    kit.done(p, "Head", K_RUBBER, 0, looks)


def hat_boonie(kit, looks, kind=K_FABRIC_A, band=K_FABRIC_B):
    p = _p(kit, "hat_crown")
    lathe(p, None, [(0.116, 1.72)] + dome_profile(0.116, 1.72, 1.855, n=5)[1:], center=(0.0, HY, 0.0), sx=1.0, sy=1.13, segs=14)
    kit.done(p, "Head", kind, 0, looks)
    p = _p(kit, "hat_brim")                                       # a wide, slightly drooping round brim
    lathe(p, None, [(0.115, 1.7), (0.2, 1.688), (0.215, 1.695), (0.2, 1.7), (0.115, 1.715)], center=(0.0, HY, 0.0), sx=1.0, sy=1.05, segs=16)
    kit.done(p, "Head", kind, 0, looks)
    p = _p(kit, "hat_band")
    lathe(p, None, [(0.1185, 1.716), (0.1185, 1.744)], center=(0.0, HY, 0.0), sx=1.0, sy=1.13, segs=14)
    kit.done(p, "Head", band, 0, looks)


def goggles(kit, looks, glow=True, kind=K_RUBBER):
    p = _p(kit, "goggles")
    box(p, (0.17, 0.035, 0.05), (0.0, 0.098, 1.722), bevel=0.01, top=(0.96, 1.0))
    kit.done(p, "Head", kind, 0, looks)
    if glow:
        p = _p(kit, "goggle_lens")
        box(p, (0.145, 0.01, 0.026), (0.0, 0.119, 1.722), bevel=0.003)
        kit.done(p, "Head", K_GLOW, Z_VISOR, looks)


def scarf(kit, looks, kind=K_FABRIC_A, up=False):
    p = _p(kit, "scarf")
    lathe(p, None, [(0.088, 1.54), (0.108, 1.58), (0.1, 1.62 if up else 1.605)], center=(0.0, -0.03, 0.0), sx=1.0, sy=1.12, segs=12)
    kit.done(p, "Head", kind, 0, looks)


def helm_combat(kit, looks, kind=K_PLATE_A, ear=True, nvg=False, cross=False):
    _shell(kit, "helm_shell", looks, 0.114, 0.13, 1.69, 1.855, kind, n=6, band=0.05)
    if ear:
        p = _p(kit, "helm_ears")
        for s in (-1.0, 1.0):
            cyl(p, 0.046, 0.04, (s * 0.115, 0.0, 1.715), axis="x", segs=8)
        kit.done(p, "Head", K_DARK, 0, looks)
    if nvg:
        p = _p(kit, "helm_nvg")
        box(p, (0.07, 0.05, 0.04), (0.0, 0.12, 1.84), bevel=0.006)
        kit.done(p, "Head", K_DARK, 0, looks)
    if cross:
        p = _p(kit, "helm_cross")
        box(p, (0.05, 0.012, 0.016), (0.0, 0.128, 1.8), bevel=0.002)
        box(p, (0.016, 0.012, 0.05), (0.0, 0.128, 1.8), bevel=0.002)
        kit.done(p, "Head", K_GLOW, Z_TRIM, looks)


def cap_peaked(kit, looks):
    p = _p(kit, "cap_top")
    lathe(p, None, [(0.112, 1.715), (0.112, 1.76), (0.145, 1.8), (0.15, 1.81), (0.0, 1.812)], center=(0.0, HY, 0.0), sx=1.0, sy=1.13, segs=16)
    kit.done(p, "Head", K_DARK, 0, looks)
    p = _p(kit, "cap_band")
    lathe(p, None, [(0.1135, 1.716), (0.1135, 1.742)], center=(0.0, HY, 0.0), sx=1.0, sy=1.13, segs=14)
    box(p, (0.05, 0.02, 0.04), (0.0, 0.134, 1.785), bevel=0.004)
    kit.done(p, "Head", K_BRASS, 0, looks)
    p = _p(kit, "cap_visor")
    box(p, (0.17, 0.09, 0.012), (0.0, 0.17, 1.735), bevel=0.004, rot=(10, 0, 0), top=(0.8, 1.0))
    kit.done(p, "Head", K_RUBBER, 0, looks)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# backs and carried things
# ------------------------------------------------------------------------------------------------------------------------------------------------

def pack_assault(kit, looks, kind=K_FABRIC_A, w=0.3, h=0.36, deep=0.15):
    p = _p(kit, "pack")
    box(p, (w, deep, h), (0.0, -0.25, 1.28), bevel=0.014, top=(0.92, 0.9))
    box(p, (w * 0.8, 0.07, h * 0.5), (0.0, -0.355, 1.2), bevel=0.012)
    kit.done(p, "spine_03", kind, 0, looks)
    p = _p(kit, "pack_straps")
    for s in (-1.0, 1.0):
        box(p, (0.03, 0.17, 0.02), (s * 0.12, -0.25, 1.28 + h / 2 + 0.0), bevel=0.003)
        box(p, (0.035, 0.012, 0.34), (s * 0.1, -0.322, 1.28), bevel=0.003)
    kit.done(p, "spine_03", K_RUBBER, 0, looks)


def pack_rocket(kit, looks):
    pack_assault(kit, looks, K_FABRIC_B, 0.28, 0.32, 0.13)
    p = _p(kit, "rocket_tube")                                    # a launcher tube strapped across the back, rising over the right shoulder, and a spare rocket
    rod(p, (0.1, -0.31, 1.0), (0.13, -0.24, 1.95), 0.062, 0.062, segs=10)
    cyl(p, 0.072, 0.06, (0.13, -0.24, 1.95), axis="z", segs=10)
    kit.done(p, "spine_03", K_DARK, 0, looks)
    p = _p(kit, "rocket_rings")
    for t in (0.3, 0.62, 0.88):
        z = 1.0 + 0.95 * t
        cyl(p, 0.07, 0.03, (0.1 + 0.03 * t, -0.31 + 0.07 * t, z), segs=10)
    kit.done(p, "spine_03", K_TRIM, 0, looks)
    p = _p(kit, "rocket_spare")
    rod(p, (-0.1, -0.32, 1.0), (-0.1, -0.32, 1.5), 0.04, 0.04, segs=8)
    cyl(p, 0.025, 0.12, (-0.1, -0.32, 1.54), segs=8, r2=0.0)
    kit.done(p, "spine_03", K_STEEL, 0, looks)
    p = _p(kit, "rocket_spare_tip")
    cyl(p, 0.026, 0.05, (-0.1, -0.32, 1.52), segs=8)
    kit.done(p, "spine_03", K_TRIM, Z_TELL, looks)


def pack_medic(kit, looks):
    p = _p(kit, "pack")
    box(p, (0.34, 0.17, 0.36), (0.0, -0.255, 1.26), bevel=0.016, top=(0.94, 0.92))
    box(p, (0.3, 0.05, 0.1), (0.0, -0.355, 1.4), bevel=0.01)
    kit.done(p, "spine_03", K_MARK, 0, looks)
    p = _p(kit, "pack_cross")
    box(p, (0.17, 0.014, 0.05), (0.0, -0.346, 1.27), bevel=0.003)
    box(p, (0.05, 0.014, 0.17), (0.0, -0.346, 1.27), bevel=0.003)
    box(p, (0.1, 0.014, 0.03), (0.0, 0.0, 0.0))
    kit.done(p, "spine_03", K_GLOW, Z_WEAK, looks)
    p = _p(kit, "pack_bag")                                       # the field bag on the hip
    box(p, (0.07, 0.15, 0.16), (-0.225, 0.0, 0.93), bevel=0.012)
    kit.done(p, "pelvis", K_MARK, 0, looks)
    p = _p(kit, "pack_bag_cross")
    box(p, (0.012, 0.07, 0.02), (-0.262, 0.0, 0.93), bevel=0.002)
    box(p, (0.012, 0.02, 0.07), (-0.262, 0.0, 0.93), bevel=0.002)
    kit.done(p, "pelvis", K_GLOW, Z_TRIM, looks)


def pack_radio(kit, looks):
    pack_assault(kit, looks, K_DARK, 0.26, 0.3, 0.13)
    p = _p(kit, "radio_whip")
    rod(p, (0.1, -0.3, 1.34), (0.13, -0.38, 2.12), 0.007, 0.004, segs=4)
    kit.done(p, "spine_03", K_STEEL, 0, looks)
    p = _p(kit, "radio_box")
    box(p, (0.2, 0.06, 0.12), (0.0, -0.345, 1.34), bevel=0.01)
    kit.done(p, "spine_03", K_PLATE_B, 0, looks)
    p = _p(kit, "radio_tip")
    sphere(p, 0.016, (0.13, -0.38, 2.13), segs=6, rings=4)
    kit.done(p, "spine_03", K_GLOW, Z_WEAK, looks)


def pack_drones(kit, looks):
    p = _p(kit, "rack")
    box(p, (0.3, 0.12, 0.34), (0.0, -0.23, 1.26), bevel=0.012)
    box(p, (0.34, 0.03, 0.06), (0.0, -0.31, 1.52), bevel=0.006)
    for s in (-1.0, 1.0):
        box(p, (0.03, 0.2, 0.03), (s * 0.15, -0.3, 1.1), bevel=0.004)
    kit.done(p, "spine_03", K_DARK, 0, looks)
    p = _p(kit, "rack_drones")                                    # two docked quad drones standing on the rack: a body disc and four rotor discs each
    for s in (-1.0, 1.0):
        c = (s * 0.1, -0.33, 1.64)
        cyl(p, 0.05, 0.035, c, segs=8)
        for dx in (-1, 1):
            for dy in (-1, 1):
                cyl(p, 0.04, 0.008, (c[0] + dx * 0.07, c[1] + dy * 0.07, c[2] + 0.025), segs=8)
                rod(p, (c[0], c[1], c[2]), (c[0] + dx * 0.07, c[1] + dy * 0.07, c[2] + 0.02), 0.006, 0.006, segs=4)
    kit.done(p, "spine_03", K_PLATE_B, 0, looks)
    p = _p(kit, "rack_glow")
    for s in (-1.0, 1.0):
        sphere(p, 0.013, (s * 0.1, -0.282, 1.635), segs=6, rings=4)
    kit.done(p, "spine_03", K_GLOW, Z_WEAK, looks)
    p = _p(kit, "rack_dish")
    cyl(p, 0.06, 0.012, (0.0, -0.33, 1.1), axis="y", segs=10, r2=0.05)
    kit.done(p, "spine_03", K_STEEL, 0, looks)


def controller(kit, looks):
    p = _p(kit, "wrist_ctrl")                                      # a bulky wrist controller with a lit screen on the left forearm
    box(p, (0.1, 0.07, 0.05), (-0.57, -0.01, 1.455), bevel=0.008)
    kit.done(p, "lowerarm_l", K_DARK, 0, looks)
    p = _p(kit, "wrist_screen")
    box(p, (0.07, 0.04, 0.012), (-0.57, -0.01, 1.486), bevel=0.002)
    kit.done(p, "lowerarm_l", K_GLOW, Z_TELL, looks)


def pack_turret(kit, looks):
    """The engineer's turret pack: a box with a folded turret on top (a gun pointing forward over the left shoulder) and three tripod legs splayed down the back."""
    p = _p(kit, "pack")
    box(p, (0.34, 0.17, 0.4), (0.0, -0.25, 1.26), bevel=0.014, top=(0.92, 0.9))
    kit.done(p, "spine_03", K_FABRIC_A, 0, looks)
    p = _p(kit, "turret_head")
    box(p, (0.17, 0.2, 0.1), (-0.07, -0.3, 1.55), bevel=0.01)
    cyl(p, 0.03, 0.34, (-0.07, -0.18, 1.57), axis="y", segs=8, r2=0.022)
    box(p, (0.1, 0.1, 0.06), (-0.07, -0.34, 1.62), bevel=0.008)
    kit.done(p, "spine_03", K_DARK, 0, looks)
    p = _p(kit, "turret_legs")
    rod(p, (0.1, -0.33, 1.4), (0.2, -0.46, 0.7), 0.017, 0.012, segs=5)
    rod(p, (-0.1, -0.33, 1.4), (-0.2, -0.46, 0.7), 0.017, 0.012, segs=5)
    rod(p, (0.0, -0.34, 1.45), (0.0, -0.5, 0.82), 0.017, 0.012, segs=5)
    kit.done(p, "spine_03", K_STEEL, 0, looks)
    p = _p(kit, "turret_hazard")
    box(p, (0.34, 0.012, 0.05), (0.0, -0.337, 1.12), bevel=0.002)
    box(p, (0.34, 0.012, 0.05), (0.0, -0.337, 1.4), bevel=0.002)
    kit.done(p, "spine_03", K_HAZARD, 0, looks)
    p = _p(kit, "turret_core")
    sphere(p, 0.03, (-0.07, -0.4, 1.56), segs=6, rings=4)
    kit.done(p, "spine_03", K_GLOW, Z_WEAK, looks)


def pack_power(kit, looks):
    """The heavy trooper's power cell: two tall cells with glowing slits (the weak point), fins and hoses."""
    p = _p(kit, "pack")
    box(p, (0.36, 0.2, 0.42), (0.0, -0.26, 1.27), bevel=0.016, top=(0.94, 0.9))
    for s in (-1.0, 1.0):
        box(p, (0.1, 0.07, 0.3), (s * 0.12, -0.37, 1.3), bevel=0.01)
    kit.done(p, "spine_03", K_PLATE_B, 0, looks)
    p = _p(kit, "pack_cell")
    for s in (-1.0, 1.0):
        box(p, (0.034, 0.014, 0.24), (s * 0.12, -0.409, 1.3), bevel=0.002)
    kit.done(p, "spine_03", K_GLOW, Z_WEAK, looks)
    p = _p(kit, "pack_fins")
    for i in range(4):
        box(p, (0.3, 0.05, 0.016), (0.0, -0.36, 1.12 + 0.07 * i), bevel=0.003)
    kit.done(p, "spine_03", K_DARK, 0, looks)


def cloak_ghost(kit, looks):
    """The ghillie cloak: a hump on the back and shaggy strips hanging over the shoulders and down the back (the lower strips follow the motion)."""
    p = _p(kit, "cloak_hump")
    lathe(p, None, [(0.2, 1.1), (0.23, 1.3), (0.2, 1.52), (0.12, 1.62), (0.0, 1.64)], center=(0.0, -0.09, 0.0), sx=1.0, sy=0.9, segs=12)
    kit.done(p, "spine_03", K_CLOTH, 0, looks)
    p = _p(kit, "cloak_shoulder")
    for s in (-1.0, 1.0):
        for i in range(6):
            x = s * (0.12 + 0.065 * i)
            rod(p, (x, -0.06 + 0.02 * (i % 2), 1.52 - 0.02 * i), (x * 1.05, -0.07, 1.34 - 0.04 * i - 0.03 * (i % 2)), 0.016, 0.005, segs=4)
    kit.done(p, "spine_03", K_CLOTH, 0, looks)
    p = _p(kit, "cloak_tails")
    for i in range(9):
        x = -0.2 + 0.05 * i
        box(p, (0.05, 0.03, 0.4 + 0.08 * (i % 3)), (x, -0.27, 0.92 - 0.04 * (i % 3)), bevel=0.003, top=(0.5, 1.0))
    kit.done(p, "chain:Sec1,Sec2,Sec3", K_CLOTH, 0, looks, chain={"pos": [(0.0, -0.22, 1.2), (0.0, -0.27, 0.95), (0.0, -0.3, 0.7)], "parent": "spine_02"})


def coat_tails(kit, looks):
    p = _p(kit, "coat_tails")
    box(p, (0.3, 0.025, 0.55), (0.0, -0.205, 0.72), bevel=0.003, top=(1.2, 1.0))
    for s in (-1.0, 1.0):
        box(p, (0.12, 0.025, 0.5), (s * 0.19, -0.1, 0.74), bevel=0.003, rot=(0, 0, s * -8))
    kit.done(p, "chain:Sec1,Sec2,Sec3", K_FABRIC_B, 0, looks, chain={"pos": [(0.0, -0.18, 1.0), (0.0, -0.21, 0.8), (0.0, -0.24, 0.6)], "parent": "pelvis"})
    p = _p(kit, "coat_trim")
    box(p, (0.3, 0.03, 0.025), (0.0, -0.21, 0.46), bevel=0.003, top=(1.2, 1.0))
    kit.done(p, "chain:Sec1,Sec2,Sec3", K_BRASS, 0, looks, chain={"pos": [(0.0, -0.18, 1.0), (0.0, -0.21, 0.8), (0.0, -0.24, 0.6)], "parent": "pelvis"})


def epaulettes(kit, looks):
    p = _p(kit, "epaulette")
    box(p, (0.1, 0.12, 0.02), (0.235, -0.04, 1.545), bevel=0.003, mirror=True, rot=(0, 0, -10))
    kit.done(p, "upperarm_r", K_BRASS, 0, looks, lr=True)
    p = _p(kit, "epaulette_fringe")
    for i in range(5):
        rod(p, (0.2 + 0.02 * i, -0.095, 1.54), (0.2 + 0.02 * i, -0.105, 1.49), 0.004, 0.003, segs=3, mirror=True)
    kit.done(p, "upperarm_r", K_BRASS, 0, looks, lr=True)


def sash(kit, looks):
    p = _p(kit, "sash")
    rod(p, (0.16, 0.12, 1.46), (-0.18, 0.13, 1.1), 0.032, 0.032, segs=6)
    kit.done(p, "spine_03", K_TRIM, 0, looks)


def bandolier(kit, looks):
    p = _p(kit, "bandolier")
    rod(p, (0.17, 0.15, 1.47), (-0.17, 0.155, 1.12), 0.028, 0.028, segs=6)
    kit.done(p, "spine_03", K_FABRIC_B, 0, looks)
    p = _p(kit, "bandolier_shells")
    for i in range(9):
        t = (i + 0.5) / 9
        x = 0.17 - 0.34 * t
        z = 1.47 - 0.35 * t
        cyl(p, 0.017, 0.07, (x, 0.17, z), rot=(0, 0, 0), segs=6, axis="z")
    kit.done(p, "spine_03", K_TRIM, 0, looks)


def charges(kit, looks):
    p = _p(kit, "charges")                                         # three breaching charges on the chest, orange timers
    for i in range(3):
        x = -0.1 + 0.1 * i
        box(p, (0.07, 0.05, 0.1), (x, 0.185, 1.22), bevel=0.006)
    kit.done(p, "spine_03", K_DARK, 0, looks)
    p = _p(kit, "charges_timers")
    for i in range(3):
        x = -0.1 + 0.1 * i
        box(p, (0.04, 0.012, 0.02), (x, 0.213, 1.245), bevel=0.002)
    kit.done(p, "spine_03", K_GLOW, Z_TELL, looks)
    p = _p(kit, "charges_ram")                                      # the ram plate: one heavy shoulder slab
    box(p, (0.1, 0.2, 0.24), (0.31, -0.065, 1.5), bevel=0.014, rot=(0, 0, -10))
    kit.done(p, "upperarm_r", K_PLATE_B, 0, looks)


def ammo_box(kit, looks):
    p = _p(kit, "ammo_box")
    box(p, (0.1, 0.16, 0.14), (-0.255, 0.06, 0.98), bevel=0.01)
    kit.done(p, "pelvis", K_DARK, 0, looks)
    p = _p(kit, "ammo_chain")                                       # the belt drapes from the box up to the gun
    rod(p, (-0.22, 0.12, 1.04), (-0.12, 0.3, 1.28), 0.016, 0.016, segs=5)
    kit.done(p, "spine_02", K_BRASS, 0, looks)


def shield_riot(kit, looks):
    """The riot shield: a big slab in front of the body on the weapon bone (it follows the aim): frame, a clear window with a glowing edge and an emitter (the weak point). It stops below the weapon line, so the pistol
    arm reaches over the top edge."""
    p = _p(kit, "shield_frame")
    box(p, (0.66, 0.045, 0.86), (0.02, 0.5, 0.98), bevel=0.016, top=(0.94, 1.0))
    kit.done(p, "Rifle", K_PLATE_B, 0, looks)
    p = _p(kit, "shield_glass")
    box(p, (0.5, 0.02, 0.3), (0.02, 0.528, 1.2), bevel=0.01)
    kit.done(p, "Rifle", K_GLASS, 0, looks)
    p = _p(kit, "shield_edge")
    box(p, (0.5, 0.014, 0.014), (0.02, 0.54, 1.355), bevel=0.002)
    box(p, (0.5, 0.014, 0.014), (0.02, 0.54, 1.045), bevel=0.002)
    for s_ in (-1.0, 1.0):
        box(p, (0.014, 0.014, 0.32), (0.02 + s_ * 0.25, 0.54, 1.2), bevel=0.002)
    kit.done(p, "Rifle", K_GLOW, Z_VISOR, looks)
    p = _p(kit, "shield_emitter")
    cyl(p, 0.045, 0.03, (0.02, 0.54, 0.74), axis="y", segs=8)
    kit.done(p, "Rifle", K_GLOW, Z_WEAK, looks)
    p = _p(kit, "shield_marks")
    box(p, (0.5, 0.012, 0.09), (0.02, 0.535, 0.88), bevel=0.002)
    kit.done(p, "Rifle", K_TRIM, 0, looks)
    p = _p(kit, "shield_handle")
    box(p, (0.03, 0.2, 0.03), (0.02, 0.4, 0.9), bevel=0.004)
    kit.done(p, "Rifle", K_DARK, 0, looks)


def baton(kit, looks):
    p = _p(kit, "baton")
    rod(p, (-0.21, 0.02, 0.98), (-0.23, 0.1, 0.62), 0.016, 0.016, segs=5)
    kit.done(p, "thigh_l", K_DARK, 0, looks)


def tool_belt(kit, looks):
    p = _p(kit, "toolbelt")
    cyl(p, 0.2, 0.09, (0.0, -0.01, 1.01), segs=14, ry=0.168, ry2=0.168)
    kit.done(p, "pelvis", K_FABRIC_A, 0, looks)
    p = _p(kit, "tools")
    for i, x in enumerate((-0.2, -0.13, 0.13, 0.2)):
        box(p, (0.05, 0.06, 0.12 + 0.02 * (i % 2)), (x, 0.13 if abs(x) < 0.15 else 0.08, 0.95), bevel=0.006)
    rod(p, (0.22, 0.04, 1.0), (0.25, 0.1, 0.78), 0.013, 0.013, segs=5)
    kit.done(p, "pelvis", K_DARK, 0, looks)
    p = _p(kit, "tools_hazard")
    box(p, (0.4, 0.012, 0.03), (0.0, 0.168, 0.99), bevel=0.002)
    kit.done(p, "pelvis", K_HAZARD, 0, looks)


def binoculars(kit, looks):
    p = _p(kit, "binoculars")
    for s in (-1.0, 1.0):
        cyl(p, 0.022, 0.1, (s * 0.03 + 0.12, 0.2, 1.1), axis="y", segs=8)
    kit.done(p, "spine_02", K_DARK, 0, looks)


def build(kit, body=None):
    boots(kit)
    gloves(kit)
    # ---------------- contract mercenaries (warm tan / olive paint, orange tape, amber goggles)
    L = "merc_rifle"
    hat_boonie(kit, L)
    goggles(kit, L)
    scarf(kit, L, K_FABRIC_B)
    vest_light(kit, L, K_PLATE_A, K_FABRIC_B)
    pack_assault(kit, L)
    pauldron(kit, L, 0.75, 1, K_FABRIC_B, trim=False)
    knees(kit, L, False, K_PLATE_B)
    belt(kit, L, K_FABRIC_B, 3)
    armband(kit, L, K_TRIM)
    vambrace(kit, L, K_FABRIC_B)
    holster(kit, L, 1.0)
    pips(kit, L)
    L = "merc_shotgun"
    _shell(kit, "beanie", L, 0.108, 0.12, 1.7, 1.845, K_FABRIC_B, n=5, band=0.05)
    goggles(kit, L)
    p = _p(kit, "skull_mask")
    box(p, (0.14, 0.05, 0.095), (0.0, 0.088, 1.625), bevel=0.012, top=(0.85, 1.0))
    kit.done(p, "Head", K_DARK, 0, L)
    p = _p(kit, "skull_teeth")
    for i in range(4):
        box(p, (0.016, 0.01, 0.026), (-0.03 + 0.02 * i, 0.116, 1.615), bevel=0.001)
    kit.done(p, "Head", K_MARK, 0, L)
    vest_light(kit, L, K_PLATE_B, K_FABRIC_B, 0.34, 0.36, 0.06)
    bandolier(kit, L)
    pauldron(kit, L, 1.05, 2, K_PLATE_B, trim=False)
    pack_assault(kit, L, K_FABRIC_B, 0.26, 0.28, 0.12)
    knees(kit, L, True, K_PLATE_B)
    belt(kit, L, K_DARK, 3, 0.2, True)
    vambrace(kit, L, K_PLATE_B, True)
    elbow(kit, L, K_PLATE_B)
    pips(kit, L)
    L = "merc_rocket"
    helm_combat(kit, L, K_PLATE_B, True, True)
    goggles(kit, L, True, K_DARK)
    vest_light(kit, L, K_PLATE_A, K_FABRIC_B, 0.32, 0.34)
    pack_rocket(kit, L)
    pauldron(kit, L, 0.95, 2, K_PLATE_A)
    knees(kit, L, True, K_PLATE_A)
    belt(kit, L, K_FABRIC_B, 4)
    vambrace(kit, L, K_PLATE_A)
    pips(kit, L)
    L = "merc_medic"
    helm_combat(kit, L, K_MARK, True, False, True)
    goggles(kit, L, True, K_DARK)
    vest_light(kit, L, K_MARK, K_FABRIC_B)
    pack_medic(kit, L)
    pauldron(kit, L, 0.8, 1, K_MARK, trim=True)
    knees(kit, L, False, K_MARK)
    belt(kit, L, K_FABRIC_B, 2)
    armband(kit, L, K_GLOW)
    vambrace(kit, L, K_FABRIC_B)
    pips(kit, L)
    L = "merc_officer"
    cap_peaked(kit, L)
    goggles(kit, L, False, K_DARK)
    vest_light(kit, L, K_PLATE_A, K_DARK, 0.28, 0.3)
    p = _p(kit, "officer_jacket")                                   # a long dark jacket over the vest: shoulders and chest panel
    box(p, (0.4, 0.2, 0.22), (0.0, -0.02, 1.4), bevel=0.02, top=(0.9, 0.9))
    kit.done(p, "spine_03", K_DARK, 0, L)
    epaulettes(kit, L)
    sash(kit, L)
    pack_radio(kit, L)
    coat_tails(kit, L)
    belt(kit, L, K_BRASS, 2)
    vambrace(kit, L, K_DARK)
    binoculars(kit, L)
    pips(kit, L)
    L = "merc_sniper"
    hat_boonie(kit, L, K_CLOTH, K_FABRIC_B)
    scarf(kit, L, K_CLOTH, True)
    goggles(kit, L, True, K_DARK)
    vest_light(kit, L, K_FABRIC_B, K_CLOTH, 0.28, 0.3)
    pauldron(kit, L, 0.85, 1, K_CLOTH, trim=False)
    p = _p(kit, "sniper_cape")
    for i in range(10):
        a = -0.2 + 0.044 * i
        box(p, (0.05, 0.03, 0.3 + 0.07 * (i % 3)), (a, -0.2, 1.32 - 0.05 * (i % 3)), bevel=0.003, top=(0.5, 1.0))
    kit.done(p, "spine_03", K_CLOTH, 0, L)
    pack_assault(kit, L, K_FABRIC_B, 0.24, 0.3, 0.12)
    knees(kit, L, False, K_FABRIC_B)
    belt(kit, L, K_FABRIC_B, 2)
    pips(kit, L)
    # ---------------- authority troopers (graphite plates, white-blue stripe, red visor)
    L = "auth_rifle"
    helm_trooper(kit, L)
    leg_stripe(kit, L)
    vest_auth(kit, L)
    collar(kit, L)
    pauldron(kit, L, 1.0, 2, K_PLATE_A, fin=True)
    pack_assault(kit, L, K_DARK, 0.28, 0.3, 0.12)
    knees(kit, L, False, K_PLATE_A)
    shins(kit, L, K_PLATE_A)
    vambrace(kit, L, K_PLATE_A)
    pips(kit, L)
    L = "auth_riot"
    helm_riot(kit, L)
    leg_stripe(kit, L, False)
    vest_auth(kit, L, False)
    collar(kit, L, 0.105, 0.08, K_PLATE_B)
    pauldron(kit, L, 1.15, 3, K_PLATE_A, trim=True)
    knees(kit, L, True, K_PLATE_B)
    shins(kit, L, K_PLATE_A)
    thigh_plates(kit, L, K_PLATE_A)
    vambrace(kit, L, K_PLATE_B, True)
    shield_riot(kit, L)
    baton(kit, L)
    pack_assault(kit, L, K_DARK, 0.26, 0.26, 0.1)
    pips(kit, L)
    L = "auth_heavy"
    helm_heavy(kit, L)
    leg_stripe(kit, L)
    vest_auth(kit, L, True)
    collar(kit, L, 0.125, 0.09, K_PLATE_B)
    pauldron(kit, L, 1.5, 3, K_PLATE_A, spike=True)
    pack_power(kit, L)
    thigh_plates(kit, L, K_PLATE_A, 0.14)
    knees(kit, L, True, K_PLATE_B)
    shins(kit, L, K_PLATE_A)
    vambrace(kit, L, K_PLATE_B, True)
    elbow(kit, L, K_PLATE_B)
    ammo_box(kit, L)
    pips(kit, L)
    L = "auth_breacher"
    helm_gas(kit, L)
    leg_stripe(kit, L)
    cargo(kit, L)
    vest_auth(kit, L, False, False)
    collar(kit, L)
    charges(kit, L)
    pauldron(kit, L, 0.95, 2, K_PLATE_A)
    pack_assault(kit, L, K_DARK, 0.3, 0.24, 0.13)
    knees(kit, L, True, K_PLATE_A)
    vambrace(kit, L, K_PLATE_B, True)
    shins(kit, L, K_PLATE_B)
    pips(kit, L)
    L = "auth_ghost"
    hood_ghost(kit, L)
    cloak_ghost(kit, L)
    vest_light(kit, L, K_DARK, K_DARK, 0.26, 0.28)
    pack_assault(kit, L, K_DARK, 0.22, 0.26, 0.1)
    knees(kit, L, False, K_DARK)
    vambrace(kit, L, K_DARK)
    pips(kit, L, False, True)
    L = "auth_drone"
    helm_vr(kit, L)
    leg_stripe(kit, L)
    vest_auth(kit, L, False)
    collar(kit, L)
    pauldron(kit, L, 0.8, 1, K_PLATE_B, fin=True)
    pack_drones(kit, L)
    controller(kit, L)
    knees(kit, L, False, K_PLATE_B)
    vambrace(kit, L, K_PLATE_A)
    pips(kit, L)
    L = "auth_engineer"
    helm_hard(kit, L)
    cargo(kit, L)
    vest_auth(kit, L, False, False)
    pauldron(kit, L, 1.0, 2, K_TRIM)
    pack_turret(kit, L)
    tool_belt(kit, L)
    knees(kit, L, True, K_PLATE_A)
    shins(kit, L, K_PLATE_A)
    vambrace(kit, L, K_TRIM)
    elbow(kit, L, K_TRIM)
    pips(kit, L)
