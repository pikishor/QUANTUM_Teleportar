"""Procedural tactical operative (shared by model_player.py and model_operative.py).

Layout (Blender axes, model front = +Y, which becomes -Z in Godot):
  Body  : torso, plate carrier, helmet, arms and the rifle in the hands (one mesh, 5 materials)
  LegL / LegR : legs, origin at the hip joint so the game can swing them about X
  Muzzle: empty at the rifle tip
Height 1.82 m with helmet. Triangle budget 12k.
"""
import math

from mathutils import Matrix, Vector

from helpers import (Part, bake_ao, empty, export_model, hexc, make_material, new_scene, paint, ring_se, rotm,
                     scale_c, xform)


def two_bone(S, W, l1, l2, pole):
    """Elbow position for a shoulder S and a wrist target W (arm lengths l1, l2); returns (elbow, wrist)."""
    S, W = Vector(S), Vector(W)
    d = W - S
    dist = min(d.length, (l1 + l2) * 0.995)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    p = Vector(pole) - n * Vector(pole).dot(n)
    p.normalize()
    return S + n * a + p * h, S + n * dist


def helmet_rings(cy, cz, a, b, c, k=9, n=22, phi_front=71.0, phi_side=115.0, phi_back=130.0, top=5.0):
    """Ellipsoid dome whose rim height varies around the head (high at the brow, low at the nape)."""
    rings = []
    for j in range(k + 1):
        t = j / k
        ring = []
        for i in range(n):
            th = 2 * math.pi * i / n          # 0 = front (+Y)
            cf = math.cos(th)
            rim = phi_side - (phi_side - phi_front) * max(0.0, cf) + (phi_back - phi_side) * max(0.0, -cf)
            phi = math.radians(rim * (1 - t) + top * t)
            s = math.sin(phi)
            ring.append((a * s * -math.sin(th), cy + b * s * cf, cz + c * math.cos(phi)))
        rings.append(ring)
    return rings


def arc_rings(cx, cy, rx, ry, zs, a0, a1, n=9):
    """Open arc rings (front visor): angle measured from +Y, a0 -> a1 degrees, one ring per z."""
    rings = []
    for z in zs:
        ring = []
        for i in range(n):
            a = math.radians(a0 + (a1 - a0) * i / (n - 1))
            ring.append((cx + rx * math.sin(a), cy + ry * math.cos(a), z))
        rings.append(ring)
    return rings


def build(S):
    new_scene()
    bulk = S.get("bulk", 1.0)
    fab = make_material("Fabric", tex="fabric")
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    visor = make_material("Visor", color=(0.012, 0.02, 0.025), metallic=0.85, roughness=0.10, vcol=False)
    glow = make_material("Glow", emit=S["accent"], emit_strength=S["accent_strength"], vcol=False)

    uni = paint("fabric", S["uniform"])
    pants = paint("fabric", S["pants"])
    carr = paint("fabric", S["carrier"])
    carr2 = paint("fabric", S["carrier2"])
    glove = paint("fabric", S["glove"])
    boot = paint("fabric", S["boot"])
    pl = paint("plating", S["plate"])
    hel = paint("plating", S["helmet"])
    trim = paint("plating", S["trim"])
    gm = paint("steel", S["metal"])
    gm2 = paint("steel", S["metal2"])
    sole = paint("fabric", "#0c0d0e")

    body = Part("Body", seed=3)
    legs = {}

    # ------------------------------------------------------------------ legs (origin at the hip joint)
    for s, name in ((-1, "LegL"), (1, "LegR")):
        p = Part(name, origin=(0.098 * s, 0.0, 0.93), seed=7 + s)
        legs[name] = p
        x0 = 0.098 * s
        p.tube([(x0, 0.0, 0.94), (x0 + 0.004 * s, 0.015, 0.70), (x0, 0.025, 0.505)],
               [(0.100 * bulk, 0.108 * bulk), (0.088 * bulk, 0.094 * bulk), (0.068, 0.072)], mat=fab, tint=pants, n=12, exp=2.3, sub=3, jitter=0.02)
        p.box((0.034, 0.12, 0.16), (x0 + s * 0.098 * bulk, 0.02, 0.70), mat=fab, tint=carr, bevel=0.007, bsegs=1, jitter=0.06)
        p.box((0.036, 0.12, 0.03), (x0 + s * 0.099 * bulk, 0.02, 0.775), mat=fab, tint=carr2, bevel=0.005, jitter=0.04)
        p.box((0.106, 0.07, 0.135), (x0, 0.085, 0.505), mat=armor, tint=pl, bevel=0.014, bsegs=2, top=(0.92, 0.9), jitter=0.05)
        p.box((0.115, 0.075, 0.025), (x0, 0.045, 0.43), mat=fab, tint=carr2, bevel=0.006)
        p.tube([(x0 + 0.004 * s, 0.025, 0.49), (x0 + 0.006 * s, 0.01, 0.30), (x0 + 0.006 * s, -0.005, 0.15)],
               [(0.062, 0.066), (0.052, 0.058), (0.05, 0.054)], mat=fab, tint=pants, n=12, exp=2.3, sub=2)
        p.box((0.075, 0.026, 0.19), (x0 + 0.004 * s, 0.062, 0.31), mat=armor, tint=pl, bevel=0.009, bsegs=1, top=(0.9, 1.0), jitter=0.05)
        # boot: shaft + lofted foot + sole
        p.tube([(x0 + 0.006 * s, -0.005, 0.24), (x0 + 0.006 * s, -0.005, 0.10)], [(0.058, 0.062), (0.060, 0.066)], mat=fab, tint=boot, n=12, exp=2.4, sub=0)
        rings = [ring_se(x0 + 0.008 * s, y, zc, rx, rz, 12, 2.6, plane="xz") for y, rx, rz, zc in
                 [(-0.100, 0.046, 0.050, 0.083), (-0.050, 0.056, 0.052, 0.080), (0.040, 0.057, 0.043, 0.067),
                  (0.130, 0.052, 0.034, 0.056), (0.205, 0.040, 0.027, 0.048)]]
        p.loft(rings, mat=fab, tint=boot, caps=(True, True), jitter=0.03)
        p.box((0.116, 0.31, 0.03), (x0 + 0.008 * s, 0.047, 0.015), mat=fab, tint=sole, bevel=0.01, bsegs=2)
        p.box((0.118, 0.07, 0.028), (x0 + 0.008 * s, -0.07, 0.014), mat=fab, tint=sole, bevel=0.008)

    # ------------------------------------------------------------------ pelvis, belt, torso
    pr = [ring_se(0, 0.0, z, rx * bulk, ry * bulk, 14, 2.4) for z, rx, ry in
          [(0.83, 0.172, 0.115), (0.90, 0.200, 0.128), (1.00, 0.190, 0.122), (1.08, 0.176, 0.116)]]
    body.loft(pr, mat=fab, tint=pants, jitter=0.0)
    tr = [ring_se(0, 0.012, z, rx * bulk, ry * bulk, 16, 2.3) for z, rx, ry in
          [(1.06, 0.172, 0.116), (1.18, 0.178, 0.121), (1.32, 0.190, 0.131), (1.44, 0.206, 0.126), (1.505, 0.176, 0.104)]]
    body.loft(tr, mat=fab, tint=uni)
    # plate carrier shell + cummerbund
    vr = [ring_se(0, 0.012, z, rx * bulk, ry * bulk, 18, 3.2) for z, rx, ry in
          [(1.135, 0.198, 0.146), (1.22, 0.205, 0.153), (1.36, 0.215, 0.160), (1.45, 0.220, 0.150), (1.485, 0.200, 0.126)]]
    body.loft(vr, mat=fab, tint=carr)
    cr = [ring_se(0, 0.012, z, rx * bulk, ry * bulk, 18, 3.0) for z, rx, ry in
          [(1.075, 0.196, 0.142), (1.105, 0.208, 0.152), (1.20, 0.210, 0.156), (1.235, 0.200, 0.148)]]
    body.loft(cr, mat=fab, tint=carr2)
    # plates (front / back), bevelled and worn
    body.box((0.275 * bulk, 0.032, 0.315), (0, 0.178 * bulk, 1.335), mat=armor, tint=pl, bevel=0.012, bsegs=2, top=(0.9, 1.0), jitter=0.04)
    body.box((0.275 * bulk, 0.030, 0.315), (0, -0.152 * bulk, 1.335), mat=armor, tint=pl, bevel=0.012, bsegs=2, top=(0.9, 1.0), jitter=0.04)
    # MOLLE webbing rows on the plate frame and cummerbund
    for z in (1.205, 1.245, 1.425, 1.465):
        body.box((0.30 * bulk, 0.008, 0.016), (0, 0.176 * bulk + 0.01, z), mat=fab, tint=carr2, jitter=0.05)
    # magazine pouches (front, below the plate) and a radio pouch on the plate
    for x in (-0.085, 0.0, 0.085):
        body.box((0.074, 0.05, 0.125), (x, 0.176 * bulk, 1.105), mat=fab, tint=carr, bevel=0.007, bsegs=1, jitter=0.08)
        body.box((0.077, 0.014, 0.055), (x, 0.205 * bulk, 1.145), mat=fab, tint=carr2, bevel=0.005, jitter=0.05)
        body.box((0.016, 0.01, 0.025), (x, 0.213 * bulk, 1.12), mat=gun, tint=gm2)
    body.box((0.058, 0.042, 0.10), (-0.105, 0.205 * bulk, 1.395), mat=fab, tint=carr2, bevel=0.007, jitter=0.06)
    body.box((0.095, 0.03, 0.065), (0.085, 0.202 * bulk, 1.415), mat=fab, tint=carr, bevel=0.006, jitter=0.06)
    body.box((0.012, 0.01, 0.012), (-0.105, 0.231 * bulk, 1.43), mat=glow)
    # side pouches / grenade-style canisters
    body.box((0.05, 0.075, 0.115), (0.212 * bulk, 0.045, 1.14), mat=fab, tint=carr, bevel=0.008, mirror=True, jitter=0.07)
    # shoulder straps (flat bands over the shoulders)
    body.tube([(0.115, 0.13, 1.455), (0.125, 0.0, 1.522), (0.115, -0.12, 1.455)], [(0.013, 0.034), (0.013, 0.034), (0.013, 0.034)],
              mat=fab, tint=carr2, n=8, exp=4.0, sub=3, mirror=True)
    # belt, buckle, hip holster
    br = [ring_se(0, 0.0, z, rx * bulk, ry * bulk, 18, 3.0) for z, rx, ry in [(0.975, 0.198, 0.134), (1.03, 0.2, 0.136)]]
    body.loft(br, mat=fab, tint=boot)
    body.box((0.05, 0.016, 0.045), (0, 0.137 * bulk, 1.0), mat=gun, tint=gm, bevel=0.004)
    body.box((0.052, 0.09, 0.17), (0.215 * bulk, 0.02, 0.9), mat=fab, tint=carr2, bevel=0.008, bsegs=1, jitter=0.05)
    body.box((0.046, 0.075, 0.075), (0.215 * bulk, 0.02, 0.985), mat=gun, tint=gm2, bevel=0.006)
    body.box((0.05, 0.07, 0.11), (-0.205 * bulk, -0.05, 0.99), mat=fab, tint=carr, bevel=0.007, jitter=0.07)

    # back: equipment pack with vents and light strips
    if S.get("backpack") == "core":
        body.box((0.27, 0.105, 0.35), (0, -0.215 * bulk - 0.01, 1.31), mat=armor, tint=trim, bevel=0.016, bsegs=2, top=(0.94, 1.0), jitter=0.03)
        body.box((0.21, 0.04, 0.2), (0, -0.285 * bulk - 0.008, 1.27), mat=armor, tint=pl, bevel=0.012, bsegs=1)
        for z in (1.17, 1.195, 1.22, 1.245):
            body.box((0.18, 0.012, 0.007), (0, -0.307 * bulk - 0.008, z), mat=gun, tint=gm2)
        for x in (-0.105, 0.105):
            body.box((0.008, 0.008, 0.25), (x, -0.272 * bulk - 0.01, 1.325), mat=glow)
        body.box((0.07, 0.02, 0.025), (0, -0.25 * bulk - 0.01, 1.505), mat=armor, tint=pl, bevel=0.005)
        body.rod((0.1, -0.24, 1.48), (0.13, -0.27, 1.72), 0.0045, mat=gun, tint=gm2, segs=5)
    else:
        body.box((0.30, 0.12, 0.38), (0, -0.226 * bulk, 1.30), mat=fab, tint=carr, bevel=0.025, bsegs=2, top=(0.9, 0.9), jitter=0.04)
        for z in (1.18, 1.26, 1.34, 1.42):
            body.box((0.31, 0.012, 0.014), (0, -0.292 * bulk, z), mat=fab, tint=carr2, jitter=0.04)
        body.box((0.12, 0.05, 0.16), (0, -0.30 * bulk, 1.30), mat=fab, tint=carr2, bevel=0.01)

    # ------------------------------------------------------------------ neck, head, helmet
    body.tube([(0, 0.012, 1.495), (0, 0.016, 1.60)], [(0.060, 0.062), (0.054, 0.058)], mat=fab, tint=uni, n=12, exp=2.2, sub=0)
    body.sphere((0.084, 0.098, 0.108), (0, 0.016, 1.672), mat=fab, tint=scale_c(boot, 1.3), segs=14, rings=9)
    hcz = 1.69
    shell = helmet_rings(0.012, hcz, 0.113, 0.136, 0.142, k=9, n=22)
    body.loft(shell, mat=armor, tint=hel, caps=(False, True), closed=False, sharp=80.0, jitter=0.0)
    # helmet details: side rails, ear covers, rear counterweight, NVG shroud, chin strap
    body.box((0.012, 0.11, 0.025), (0.118, 0.012, 1.69), mat=gun, tint=gm, bevel=0.003, mirror=True)
    body.box((0.03, 0.08, 0.075), (0.108, -0.018, 1.655), mat=armor, tint=trim, bevel=0.01, bsegs=1, mirror=True, jitter=0.04)
    body.box((0.12, 0.05, 0.07), (0, -0.138, 1.665), mat=fab, tint=carr, bevel=0.01, bsegs=1, jitter=0.03)
    body.box((0.065, 0.045, 0.045), (0, 0.128, 1.775), mat=gun, tint=gm, bevel=0.006)
    body.cyl(0.017, 0.04, (0, 0.158, 1.775), axis="y", mat=gun, tint=gm2, segs=10)
    body.box((0.012, 0.012, 0.012), (0.045, 0.16, 1.80), mat=glow)
    body.bar((0.1, 0.03, 1.64), (0.065, 0.1, 1.575), 0.012, 0.006, mat=fab, tint=boot, mirror=True)
    if S["helmet_type"] == "visor":
        zs = [1.742, 1.715, 1.68, 1.645, 1.612]
        vr_ = arc_rings(0, 0.014, 0.103, 0.130, zs, 74, -74, n=11)
        body.loft(vr_, mat=visor, caps=(False, False), closed=False, sharp=80.0)
        # visor frame (top, bottom rim glow)
        rim = arc_rings(0, 0.014, 0.1045, 0.1315, [1.608], 74, -74, n=11)[0]
        for i in range(len(rim) - 1):
            body.rod(rim[i], rim[i + 1], 0.0034, mat=glow, segs=4)
        top = arc_rings(0, 0.014, 0.106, 0.1335, [1.745], 70, -70, n=11)[0]
        for i in range(len(top) - 1):
            body.rod(top[i], top[i + 1], 0.0055, mat=gun, tint=gm2, segs=4)
        # mouth piece / filters
        body.box((0.10, 0.06, 0.06), (0, 0.098, 1.575), mat=gun, tint=gm2, bevel=0.01, bsegs=1, top=(0.9, 0.85))
        body.cyl(0.02, 0.045, (0.062, 0.095, 1.58), axis="y", mat=gun, tint=gm, segs=10, mirror=True, bevel=0.003)
    else:
        # full-face mask with a narrow optic slit
        zs = [1.735, 1.71, 1.665, 1.62, 1.575]
        mk = arc_rings(0, 0.014, 0.102, 0.128, zs, 76, -76, n=11)
        body.loft(mk, mat=armor, tint=trim, caps=(False, False), closed=False, sharp=80.0)
        sl = arc_rings(0, 0.014, 0.1045, 0.1305, [1.708, 1.69], 56, -56, n=9)
        body.loft(sl, mat=visor, caps=(False, False), closed=False)
        sg = arc_rings(0, 0.014, 0.1055, 0.1318, [1.704, 1.694], 50, -50, n=9)
        body.loft(sg, mat=glow, caps=(False, False), closed=False)
        body.box((0.07, 0.05, 0.07), (0, 0.1, 1.592), mat=gun, tint=gm2, bevel=0.008)
        body.cyl(0.021, 0.05, (0.056, 0.1, 1.598), axis="y", mat=gun, tint=gm, segs=10, mirror=True)

    # ------------------------------------------------------------------ rifle (held low-ready, butt at the right shoulder pocket)
    RR = rotm(1.2, 0, 0)
    R = Matrix.Translation(Vector((0.118, 0.14, 1.365))) @ RR

    def rp(v):
        return R @ Vector(v)

    def rbox(size, pos, mat, tint=(1, 1, 1), **kw):
        body.box(size, rp(pos), mat=mat, tint=tint, frame=RR, **kw)

    def rcyl(r, ln, pos, mat, tint=(1, 1, 1), **kw):
        body.cyl(r, ln, rp(pos), mat=mat, tint=tint, frame=RR @ rotm(-90, 0, 0), **kw)

    rbox((0.042, 0.03, 0.115), (0, 0.015, -0.035), gun, gm2, bevel=0.005)              # butt pad
    rbox((0.04, 0.17, 0.06), (0, 0.11, -0.03), gun, gm, bevel=0.006, top=(0.9, 0.7))      # stock
    rbox((0.034, 0.12, 0.025), (0, 0.1, 0.012), gun, gm2, bevel=0.004)                   # cheek riser
    rbox((0.05, 0.21, 0.065), (0, 0.295, -0.032), gun, gm, bevel=0.006)                 # lower receiver
    rbox((0.052, 0.27, 0.056), (0, 0.325, 0.012), gun, gm2, bevel=0.005)                 # upper receiver
    rbox((0.022, 0.47, 0.014), (0, 0.425, 0.048), gun, gm, bevel=0.002)                  # top rail
    for yy in (0.22, 0.27, 0.32, 0.37, 0.42, 0.47, 0.52, 0.57, 0.62):
        rbox((0.026, 0.011, 0.01), (0, yy, 0.056), gun, gm2)
    body.box((0.034, 0.075, 0.2), rp((0, 0.33, -0.145)), mat=gun, tint=gm, frame=RR @ rotm(-9, 0, 0), bevel=0.006)   # magazine
    body.box((0.036, 0.05, 0.11), rp((0, 0.235, -0.115)), mat=fab, tint=boot, frame=RR @ rotm(18, 0, 0), bevel=0.008)   # pistol grip
    rbox((0.03, 0.07, 0.014), (0, 0.28, -0.075), gun, gm, bevel=0.003)                   # trigger guard
    rbox((0.058, 0.30, 0.06), (0, 0.51, 0.0), gun, gm, bevel=0.008)                     # handguard
    for yy in (0.43, 0.49, 0.55, 0.61):
        rbox((0.06, 0.026, 0.02), (0, yy, 0.0), gun, gm2)                               # M-LOK style cutouts (dark)
    rbox((0.07, 0.1, 0.05), (0, 0.36, 0.075), gun, gm2, bevel=0.007)                     # optic body
    rcyl(0.021, 0.04, (0, 0.425, 0.075), gun, gm2, segs=10)
    rbox((0.052, 0.012, 0.03), (0, 0.307, 0.083), gun, gm2)                             # optic rear
    rbox((0.008, 0.006, 0.008), (0, 0.31, 0.086), glow)
    rcyl(0.0105, 0.14, (0, 0.71, 0.0), gun, gm, segs=8)                                 # barrel
    rcyl(0.027, 0.2, (0, 0.80, 0.0), gun, gm2, segs=12, bevel=0.003)                    # suppressor
    rcyl(0.029, 0.014, (0, 0.905, 0.0), gun, gm, segs=12)
    rbox((0.02, 0.07, 0.02), (0.04, 0.55, -0.005), gun, gm2, bevel=0.003)                # weapon light
    rbox((0.012, 0.012, 0.012), (0.04, 0.59, -0.005), glow if S.get("light_glow") else gun, gm)
    rbox((0.008, 0.07, 0.008), (0.027, 0.2, -0.01), glow)                               # status strip
    muzzle = rp((0, 0.915, 0))

    # ------------------------------------------------------------------ arms
    hands = {1: rp((0.0, 0.235, -0.115)), -1: rp((0.0, 0.41, -0.012))}
    wrists = {1: rp((0.012, 0.19, -0.068)), -1: rp((0.045, 0.325, 0.01))}
    for s in (1, -1):
        Sv = Vector((0.222 * s * bulk, 0.0, 1.43))
        E, W = two_bone(Sv, wrists[s], 0.31, 0.28, (0.5 * s, -0.5, -1.0))
        body.sphere(0.066 * bulk, Sv + Vector((0.0, 0.0, -0.005)), mat=fab, tint=uni, scale=(1.0, 1.0, 0.92), segs=12, rings=8)
        body.tube([Sv, E], [(0.058 * bulk, 0.058 * bulk), (0.049 * bulk, 0.049 * bulk)], mat=fab, tint=uni, n=10, exp=2.2, sub=1)
        body.tube([E, W], [(0.049, 0.049), (0.038, 0.038)], mat=fab, tint=uni, n=10, exp=2.2, sub=1)
        body.sphere(0.05, E, mat=fab, tint=uni, segs=10, rings=7)
        body.box((0.07, 0.07, 0.07), E + Vector((s * 0.03, -0.012, 0.0)), mat=armor, tint=pl, bevel=0.014, bsegs=2, jitter=0.04)
        if S.get("pauldrons"):
            body.box((0.13, 0.17, 0.05), Sv + Vector((s * 0.035, 0.0, 0.055)), mat=armor, tint=pl, rot=(0, s * -14, 0), bevel=0.014, bsegs=2, top=(0.82, 0.8), jitter=0.04)
            body.box((0.12, 0.14, 0.035), Sv + Vector((s * 0.045, 0.0, 0.02)), mat=armor, tint=trim, rot=(0, s * -26, 0), bevel=0.01, bsegs=1)
        else:
            body.box((0.075, 0.11, 0.03), Sv + Vector((s * 0.02, 0.0, 0.05)), mat=armor, tint=pl, rot=(0, s * -10, 0), bevel=0.01, bsegs=1, top=(0.9, 0.9))
            body.box((0.012, 0.09, 0.006), Sv + Vector((s * 0.03, 0.0, 0.068)), mat=glow, rot=(0, s * -8, 0))
        # glove: cuff + fist around the grip
        body.tube([W - (W - E).normalized() * 0.03, hands[s]], [(0.04, 0.04), (0.046, 0.04)], mat=fab, tint=glove, n=8, exp=2.5, sub=0)
        body.box((0.058, 0.075, 0.078), hands[s], mat=fab, tint=glove, frame=RR, bevel=0.01, bsegs=1, jitter=0.04)
        body.box((0.02, 0.05, 0.03), hands[s] + Vector((-s * 0.028, 0.0, 0.03)), mat=fab, tint=glove, frame=RR, bevel=0.006)

    # ------------------------------------------------------------------ bake AO and build objects
    parts = [body] + list(legs.values())
    bake_ao(parts, samples=18, dist=0.22, strength=0.72)
    objs = [pt.build() for pt in parts]
    objs.append(empty("Muzzle", muzzle))
    for p in parts:
        print("  part %-6s tris=%d" % (p.name, p.tri_count()))
    return export_model(S["name"], objs)
