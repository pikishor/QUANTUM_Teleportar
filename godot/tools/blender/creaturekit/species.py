"""The alien and machine bodies of the enemy roster v3: five bipeds from one parametric skeleton (grunt, brute, hunter, elite, stalker), the quadruped jackal, the bloater, and two walkers (light walker,
heavy mech with missile pods). Final size in metres, facing +Y in Blender (the game's front), feet on z = 0, glow mask in the vertex alpha (eyes, seams, cores, tips)."""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lib import Creature, R  # noqa: E402


def sc(a, k):
    return tuple(min(1.0, x * k) for x in a)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# clips (rotations in degrees about armature axes: x forward swing / pitch, y roll, z yaw)
# ------------------------------------------------------------------------------------------------------------------------------------------------

def biped_clips(c, P):
    amp = P.get("amp", 1.0)
    tails = [b for b in c.order if b.startswith("tail")]

    def gait(speed, a):
        def fn(t, p):
            ph = 2.0 * math.pi * t
            for side, off in (("l", 0.0), ("r", math.pi)):
                s = math.sin(ph + off)
                cs = math.cos(ph + off)
                p.rot("thigh_" + side, x=a * 34.0 * s)
                p.rot("shin_" + side, x=-a * 38.0 * max(0.0, cs) - 6.0)
                p.rot("foot_" + side, x=a * 12.0 * s + 10.0 * max(0.0, cs))
                p.rot("arm_" + side, x=-a * 26.0 * s * P.get("armswing", 1.0))
                p.rot("fore_" + side, x=-a * 10.0 * max(0.0, -s))
            p.rot("spine", z=a * 5.0 * math.sin(ph), x=P.get("lean", 6.0) * a)
            p.rot("chest", z=-a * 4.0 * math.sin(ph))
            p.rot("head", z=a * 3.0 * math.sin(ph))
            p.move("root", z=-0.025 * a * abs(math.cos(ph)) * 2.0)
            for i, tb in enumerate(tails):
                p.rot(tb, z=a * 12.0 * math.sin(ph + i * 0.9))
        return fn

    c.clip("walk", 24, gait(1.0, 0.8 * amp))
    c.clip("run", 16, gait(1.6, 1.25 * amp))

    def idle(t, p):
        ph = 2.0 * math.pi * t
        p.rot("chest", x=2.2 * math.sin(ph))
        p.rot("spine", x=1.2 * math.sin(ph + 0.5))
        p.rot("head", x=-2.0 * math.sin(ph + 0.9), z=3.0 * math.sin(ph * 0.5))
        p.rot("arm_l", x=3.0 * math.sin(ph + 1.0))
        p.rot("arm_r", x=-3.0 * math.sin(ph + 1.0))
        for i, tb in enumerate(tails):
            p.rot(tb, z=6.0 * math.sin(ph + i * 0.8))
        p.move("root", z=0.006 * math.sin(ph))
    c.clip("idle", 30, idle)

    def attack(t, p):
        if t < 0.35:                                                     # wind up: crouch, arms back
            k = t / 0.35
            e = k * k * (3 - 2 * k)
            p.rot("spine", x=-14.0 * e)
            p.rot("chest", x=-10.0 * e)
            p.rot("arm_l", x=-70.0 * e * P.get("strike", 1.0))
            p.rot("arm_r", x=-70.0 * e * P.get("strike", 1.0))
            p.rot("thigh_l", x=10.0 * e)
            p.rot("thigh_r", x=10.0 * e)
            p.rot("jaw", x=-18.0 * e)
            p.move("root", z=-0.06 * e)
        elif t < 0.55:                                                   # strike
            k = (t - 0.35) / 0.2
            e = k * k * (3 - 2 * k)
            p.rot("spine", x=lerp_(-14.0, 22.0, e))
            p.rot("chest", x=lerp_(-10.0, 16.0, e))
            p.rot("arm_l", x=lerp_(-70.0, 80.0, e) * P.get("strike", 1.0))
            p.rot("arm_r", x=lerp_(-70.0, 80.0, e) * P.get("strike", 1.0))
            p.rot("thigh_l", x=lerp_(10.0, 28.0, e))
            p.rot("thigh_r", x=lerp_(10.0, -12.0, e))
            p.rot("jaw", x=lerp_(-18.0, 20.0, e))
            p.move("root", y=0.2 * e, z=lerp_(-0.06, -0.02, e))
        else:                                                            # recover
            k = (t - 0.55) / 0.45
            e = 1.0 - k * k * (3 - 2 * k)
            p.rot("spine", x=22.0 * e)
            p.rot("chest", x=16.0 * e)
            p.rot("arm_l", x=80.0 * e * P.get("strike", 1.0))
            p.rot("arm_r", x=80.0 * e * P.get("strike", 1.0))
            p.rot("thigh_l", x=28.0 * e)
            p.rot("thigh_r", x=-12.0 * e)
            p.move("root", y=0.2 * e)
    c.clip("attack", 20, attack, False)

    def hit(t, p):
        e = math.sin(math.pi * min(t * 1.4, 1.0))
        p.rot("spine", x=-16.0 * e)
        p.rot("chest", x=-10.0 * e)
        p.rot("head", x=14.0 * e, z=8.0 * e)
        p.rot("arm_l", x=20.0 * e)
        p.rot("arm_r", x=20.0 * e)
        p.move("root", y=-0.08 * e)
    c.clip("hit", 12, hit, False)

    def dead(t, p):
        e = min(t * 1.25, 1.0)
        e = e * e * (3 - 2 * e)
        p.rot("root", x=84.0 * e)
        p.rot("thigh_l", x=-70.0 * e)
        p.rot("thigh_r", x=-30.0 * e)
        p.rot("shin_l", x=-60.0 * e)
        p.rot("shin_r", x=-20.0 * e)
        p.rot("arm_l", x=-40.0 * e, y=-20.0 * e)
        p.rot("arm_r", x=-70.0 * e, y=20.0 * e)
        p.rot("head", x=20.0 * e)
        p.rot("jaw", x=24.0 * e)
        for tb in tails:
            p.rot(tb, z=14.0 * e)
    c.clip("dead", 24, dead, False)

    def jump(t, p):
        if t < 0.3:
            e = t / 0.3
            p.rot("spine", x=-12.0 * e)
            p.rot("thigh_l", x=40.0 * e)
            p.rot("thigh_r", x=40.0 * e)
            p.rot("shin_l", x=-50.0 * e)
            p.rot("shin_r", x=-50.0 * e)
            p.move("root", z=-0.18 * e)
        else:
            e = min((t - 0.3) / 0.3, 1.0)
            p.rot("spine", x=lerp_(-12.0, 18.0, e))
            p.rot("thigh_l", x=lerp_(40.0, -20.0, e))
            p.rot("thigh_r", x=lerp_(40.0, -20.0, e))
            p.rot("shin_l", x=lerp_(-50.0, -20.0, e))
            p.rot("shin_r", x=lerp_(-50.0, -20.0, e))
            p.rot("arm_l", x=lerp_(0.0, 70.0, e))
            p.rot("arm_r", x=lerp_(0.0, 70.0, e))
            p.move("root", z=lerp_(-0.18, 0.1, e))
    c.clip("jump", 16, jump, False)


def lerp_(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------------------------------------------------------------------------------------
# the parametric biped
# ------------------------------------------------------------------------------------------------------------------------------------------------

def biped(name, P):
    c = Creature(name)
    S = P.get("s", (1.0, 1.0, 1.0))
    rs = P.get("rs", 1.0)
    skin, dark, plate, glow = P["skin"], P["dark"], P["plate"], P["glow"]
    armor = P.get("armor", plate)                                           # pauldrons, knee guards, fists and back plates (the bone `plate` colour is for spikes, claws, teeth, mandibles)
    angular = P.get("angular", False)                                       # hard-edged armour plates instead of balls

    def T(p):
        return (p[0] * S[0], p[1] * S[1], p[2] * S[2])

    def r(x):
        return x * rs

    hunch = P.get("hunch", 0.0)
    bones = [("root", (0, 0, 0), (0, 0, 0.1), None), ("hips", (0, -0.02, 0.95), (0, 0, 1.05), "root"), ("spine", (0, 0, 1.05), (0, 0.1 + hunch, 1.3), "hips"),
             ("chest", (0, 0.1 + hunch, 1.3), (0, 0.16 + hunch, 1.5), "spine"), ("neck", (0, 0.16 + hunch, 1.5), (0, 0.24 + hunch * 1.3, 1.62), "chest"),
             ("head", (0, 0.24 + hunch * 1.3, 1.62), (0, 0.38 + hunch * 1.3, 1.7), "neck"), ("jaw", (0, 0.34 + hunch * 1.3, 1.64), (0, 0.46 + hunch * 1.3, 1.6), "head")]
    for side, sx in (("l", -1), ("r", 1)):
        w = P.get("stance", 0.14)
        bones += [("thigh_" + side, (sx * w, 0, 0.95), (sx * w, 0.16, 0.55), "hips"), ("shin_" + side, (sx * w, 0.16, 0.55), (sx * w, -0.02, 0.2), "thigh_" + side),
                  ("foot_" + side, (sx * w, -0.02, 0.2), (sx * w, 0.14, 0.02), "shin_" + side),
                  ("arm_" + side, (sx * P.get("shoulder", 0.24), 0.12 + hunch, 1.45), (sx * (P.get("shoulder", 0.24) + 0.16), 0.18 + hunch, 1.15), "chest"),
                  ("fore_" + side, (sx * (P.get("shoulder", 0.24) + 0.16), 0.18 + hunch, 1.15), (sx * (P.get("shoulder", 0.24) + 0.22), 0.34 + hunch, 0.82), "arm_" + side)]
    if P.get("tail", True):
        bones += [("tail1", (0, -0.05, 1.0), (0, -0.3, 0.92), "hips"), ("tail2", (0, -0.3, 0.92), (0, -0.6, 0.82), "tail1"), ("tail3", (0, -0.6, 0.82), (0, -0.9, 0.8), "tail2")]
    for n, h, t, par in bones:
        c.bone(n, T(h), T(t), par)
    sh = P.get("shoulder", 0.24)
    # the body: one continuous skin over a stick figure (hips, spine, chest, neck, arms, digitigrade legs, tail)
    nd, ed = [], []

    def N(pos, rx, ry=None):
        nd.append((T(pos), (r(rx) * S[0] ** 0.5, r(ry if ry is not None else rx) * S[1] ** 0.5)))
        return len(nd) - 1

    cw = P.get("chest_w", 1.0)
    i_h = N((0, -0.02, 0.98), 0.17, 0.13)
    i_s = N((0, 0.02 + hunch * 0.4, 1.2), 0.16, 0.12)
    i_c = N((0, 0.1 + hunch * 0.9, 1.42), 0.2 * cw, 0.14)
    i_n = N((0, 0.17 + hunch, 1.57), 0.065)
    i_hb = N((0, 0.27 + hunch * 1.3, 1.67), 0.07)
    ed += [(i_h, i_s), (i_s, i_c), (i_c, i_n), (i_n, i_hb)]
    lr = P.get("leg_r", 0.09)
    ar = P.get("arm_r", 0.055)
    for sx in (-1, 1):
        w = P.get("stance", 0.14)
        i0 = N((sx * w * 0.9, 0.0, 0.95), lr * 1.05)
        i1 = N((sx * w, 0.16, 0.55), lr * 0.78)
        i2 = N((sx * w, -0.02, 0.2), lr * 0.5)
        i3 = N((sx * w, 0.13, 0.04), lr * 0.4, lr * 0.32)
        ed += [(i_h, i0), (i0, i1), (i1, i2), (i2, i3)]
        a0 = N((sx * sh, 0.12 + hunch, 1.45), ar * 1.35)
        a1 = N((sx * (sh + 0.16), 0.18 + hunch, 1.15), ar)
        a2 = N((sx * (sh + 0.22), 0.34 + hunch, 0.84), ar * 0.72)
        ed += [(i_c, a0), (a0, a1), (a1, a2)]
    if P.get("tail", True):
        t1 = N((0, -0.12, 1.0), 0.07)
        t2 = N((0, -0.45, 0.88), 0.045)
        t3 = N((0, -0.92, 0.8), 0.016)
        ed += [(i_h, t1), (t1, t2), (t2, t3)]

    def paint(p, n):
        up = 0.5 + 0.5 * n.z
        k = 0.62 + 0.5 * up
        belly = max(0.0, n.y - 0.15) * (1.0 if 1.1 < p.z / S[2] < 1.6 else 0.0) * 0.35
        band = 0.82 + 0.18 * math.sin(p.z / S[2] * 46.0) if p.z / S[2] < 0.95 else 1.0
        base = P.get("skin2", skin) if (p.z / S[2] > 1.05 and n.y > 0.35) else skin
        return (min(1.0, base[0] * k * band + belly * 0.6), min(1.0, base[1] * k * band + belly * 0.5), min(1.0, base[2] * k * band + belly * 0.4))

    def veins(p, n):
        return 0.55 if P.get("belly_glow") and abs(p.x) < 0.02 and n.y > 0.5 and 1.2 < p.z / S[2] < 1.6 else 0.0

    from lib import add_skin_piece
    add_skin_piece(c, nd, ed, paint, [b[0] for b in bones if b[0] != "root"], subdiv=2, target_tris=P.get("skin_tris", 1700), glow_fn=veins)
    # head: a wedge skull with a brow ridge, big glowing eyes, a jaw with teeth and short mandibles
    hd = P.get("head", (0.1, 0.2, 0.1))
    hc = (0, 0.36 + hunch * 1.3, 1.7 + P.get("head_lift", 0.0))
    skull = P.get("skull", plate)
    c.ellipsoid(T(hc), (hd[0] * S[0], hd[1] * S[1], hd[2] * S[2]), skull, ["head", "neck"], rot=(8, 0, 0), tint=(1.2, 0.6), segs=12, rings=7)
    c.ellipsoid(T((0, hc[1] + hd[1] * 0.35, hc[2] + hd[2] * 0.42)), (hd[0] * 1.05 * S[0], hd[1] * 0.55 * S[1], hd[2] * 0.3 * S[2]), dark, ["head"], rot=(-12, 0, 0), tint=(1.1, 0.6), segs=10, rings=4)     # brow ridge
    c.ellipsoid(T((0, hc[1] + hd[1] * 0.55, hc[2] - hd[2] * 0.5)), (hd[0] * 0.82 * S[0], hd[1] * 0.6 * S[1], hd[2] * 0.42 * S[2]), dark, ["head", "jaw"], rot=(14, 0, 0), tint=(1.1, 0.6), segs=10, rings=5)   # jaw
    for sx in (-1, 1):
        c.ellipsoid(T((sx * hd[0] * 0.58, hc[1] + hd[1] * 0.62, hc[2] + hd[2] * 0.12)), (r(0.034) * S[0], r(0.022) * S[1], r(0.03) * S[2]), glow, ["head"], glow=1.0, segs=8, rings=5)
        for k in range(P.get("eyes", 4) // 2 - 1):
            c.ellipsoid(T((sx * hd[0] * 0.28, hc[1] + hd[1] * 0.78, hc[2] + hd[2] * (0.42 + 0.2 * k))), (r(0.018), r(0.014), r(0.016)), glow, ["head"], glow=1.0, segs=6, rings=4)
        for k in range(4):                                                  # teeth along the jaw line
            c.cone(T((sx * hd[0] * (0.2 + 0.16 * k), hc[1] + hd[1] * (1.0 - 0.05 * k), hc[2] - hd[2] * 0.2)), T((sx * hd[0] * (0.2 + 0.16 * k), hc[1] + hd[1] * (1.05 - 0.05 * k), hc[2] + hd[2] * 0.12)), r(0.011), (0.9, 0.88, 0.8), ["jaw"], segs=3)
        c.cone(T((sx * hd[0] * 0.7, hc[1] + hd[1] * 0.8, hc[2] - hd[2] * 0.45)), T((sx * hd[0] * 1.5, hc[1] + hd[1] * 1.25, hc[2] - hd[2] * 0.8)), r(0.022), plate, ["jaw", "head"], segs=4, tip_glow=0.6)    # mandible
    if P.get("crest"):
        k = P["crest"]
        for i in range(4):
            c.cone(T((0, hc[1] - hd[1] * (0.4 - 0.45 * i / 3), hc[2] + hd[2] * 0.85)), T((0, hc[1] - hd[1] * (0.9 - 0.7 * i / 3) - 0.1, hc[2] + hd[2] * (0.85 + 0.9 * k))), r(0.03), plate, ["head"], segs=4, tip_glow=0.6)
    # arms
    fist = P.get("fist", 0.0)
    for side, sx in (("l", -1), ("r", 1)):
        a0 = (sx * sh, 0.12 + hunch, 1.45)
        a1 = (sx * (sh + 0.16), 0.18 + hunch, 1.15)
        a2 = (sx * (sh + 0.22), 0.34 + hunch, 0.82)
        ar = P.get("arm_r", 0.055)
        cannon = P.get("cannon") and side == "r"
        if P.get("pauldrons") and angular:                                  # a sloped plate over the shoulder with a bone spike (a hard edge reads as armour, a ball as a balloon)
            c.box(T((a0[0] + sx * ar * 0.5, a0[1], a0[2] + ar * 0.6)), (r(ar * 3.0), r(ar * 2.6), r(ar * 1.3)), armor, ["arm_" + side, "chest"], rot=(0, 20 * sx, 0), taper=(0.66, 0.8))
            c.cone(T((a0[0] + sx * ar * 1.0, a0[1], a0[2] + ar * 1.4)), T((a0[0] + sx * ar * 1.8, a0[1] - 0.02, a0[2] + ar * 3.6)), r(0.028), plate, ["arm_" + side, "chest"], segs=4, tip_glow=0.5)
        else:
            c.ellipsoid(T(a0), (r(ar * 1.7), r(ar * 1.5), r(ar * 1.5)), armor if P.get("pauldrons") else skin, ["arm_" + side, "chest"], tint=(1.2, 0.7))
        if fist > 0:
            if angular:                                                     # a knuckle block with bone spikes
                c.box(T((a2[0], a2[1] + 0.05, a2[2] - 0.05)), (r(fist * 1.7), r(fist * 1.6), r(fist * 1.5)), armor, ["fore_" + side], rot=(0, 0, 0), taper=(0.85, 0.9))
                for k in range(3):
                    c.cone(T((a2[0] + (k - 1) * fist * 0.55, a2[1] + 0.05 + fist * 0.8, a2[2] - 0.02)), T((a2[0] + (k - 1) * fist * 0.62, a2[1] + 0.05 + fist * 1.6, a2[2] + 0.02)), r(0.026), plate, ["fore_" + side], segs=4, tip_glow=0.5)
            else:
                c.ellipsoid(T((a2[0], a2[1] + 0.04, a2[2] - 0.05)), (r(fist), r(fist * 0.9), r(fist)), armor, ["fore_" + side], tint=(1.15, 0.7))
            for k in range(3):
                c.cone(T((a2[0] + (k - 1) * 0.04, a2[1] + 0.1, a2[2] - 0.02)), T((a2[0] + (k - 1) * 0.05, a2[1] + 0.2, a2[2] - 0.0)), r(0.025), dark, ["fore_" + side], segs=4, tip_glow=0.6)
        elif not cannon:
            for k in range(3):                                               # claws
                c.cone(T((a2[0] + (k - 1) * 0.025, a2[1] + 0.01, a2[2] - 0.02)), T((a2[0] + (k - 1) * 0.04, a2[1] + 0.16, a2[2] - 0.12)), r(0.015), plate, ["fore_" + side], segs=4, tip_glow=0.8)
        if P.get("blades") and not cannon:
            c.cone(T((a2[0], a2[1] - 0.05, a2[2] + 0.12)), T((a2[0] + sx * 0.02, a2[1] + 0.5, a2[2] - 0.5)), r(0.03), plate, ["fore_" + side], segs=4, glow=0.0, tip_glow=1.0)
            c.cone(T((a2[0], a2[1] - 0.05, a2[2] + 0.12)), T((a2[0] + sx * 0.02, a2[1] + 0.5, a2[2] - 0.5)), r(0.012), glow, ["fore_" + side], segs=4, glow=1.0)
        if cannon:                                                           # the hunter's bio-cannon: a heavy barrel with armour bands, glowing coil rings and a glowing maw
            c.tube([T((a2[0], a2[1] - 0.08, a2[2] + 0.02)), T((a2[0], a2[1] + 0.4, a2[2] - 0.02)), T((a2[0], a2[1] + 0.95, a2[2] + 0.03))], [r(0.095), r(0.075), r(0.06)], dark, ["fore_" + side], segs=8)
            for yy, rr in ((0.14, 0.12), (0.42, 0.105), (0.7, 0.088)):
                c.ellipsoid(T((a2[0], a2[1] + yy, a2[2])), (r(rr), r(0.04), r(rr)), plate, ["fore_" + side], segs=10, rings=3)
                c.ellipsoid(T((a2[0], a2[1] + yy + 0.055, a2[2])), (r(rr * 0.92), r(0.012), r(rr * 0.92)), glow, ["fore_" + side], glow=0.9, segs=10, rings=3)
            c.ellipsoid(T((a2[0], a2[1] + 0.97, a2[2] + 0.03)), (r(0.07), r(0.045), r(0.07)), glow, ["fore_" + side], glow=1.0, segs=8, rings=4)
            c.ellipsoid(T((a2[0], a2[1] - 0.02, a2[2] + 0.05)), (r(0.12), r(0.12), r(0.12)), plate, ["fore_" + side])
        if P.get("emitter") and side == "l":                                 # the elite's shield emitter on the left forearm: a glowing disc and a rim
            c.ellipsoid(T((a2[0] - 0.05, a2[1] + 0.12, a2[2] + 0.2)), (r(0.2), r(0.03), r(0.2)), plate, ["fore_l"], rot=(0, 0, 0), segs=12, rings=4)
            c.ellipsoid(T((a2[0] - 0.05, a2[1] + 0.145, a2[2] + 0.2)), (r(0.15), r(0.012), r(0.15)), glow, ["fore_l"], glow=1.0, segs=12, rings=3)
    # legs (digitigrade)
    w = P.get("stance", 0.14)
    for side, sx in (("l", -1), ("r", 1)):
        t0, t1, t2, t3 = (sx * w, 0, 0.95), (sx * w, 0.16, 0.55), (sx * w, -0.02, 0.2), (sx * w, 0.14, 0.02)
        lr = P.get("leg_r", 0.09)
        if P.get("knees"):
            if angular:                                                     # a faceted guard with a forward spike
                c.box(T((t1[0], t1[1] + lr * 0.7, t1[2] + 0.01)), (r(lr * 1.8), r(lr * 1.2), r(lr * 1.8)), armor, ["thigh_" + side, "shin_" + side], taper=(0.8, 0.7))
                c.cone(T((t1[0], t1[1] + lr * 1.3, t1[2])), T((t1[0], t1[1] + lr * 2.6, t1[2] + 0.03)), r(0.024), plate, ["thigh_" + side, "shin_" + side], segs=4, tip_glow=0.4)
            else:
                c.ellipsoid(T(t1), (r(lr * 1.0), r(lr * 1.05), r(lr * 1.0)), armor, ["thigh_" + side, "shin_" + side], tint=(1.1, 0.7))
        c.ellipsoid(T((sx * w, 0.07, 0.05)), (r(lr * 0.5), r(lr * 0.85), r(lr * 0.28)), dark, ["foot_" + side, "shin_" + side], tint=(1.1, 0.7))
        for k in range(3):
            c.cone(T((sx * w + (k - 1) * 0.04, 0.12, 0.04)), T((sx * w + (k - 1) * 0.055, 0.26, 0.0)), r(0.02), plate, ["foot_" + side], segs=4)
    if P.get("tail", True):
        c.ellipsoid(T((0, -0.92, 0.8)), (r(0.02), r(0.04), r(0.02)), glow, ["tail3"], glow=1.0, segs=6, rings=4)
        if P.get("tail_blade"):
            c.cone(T((0, -0.88, 0.82)), T((0, -1.25, 0.9)), r(0.035), plate, ["tail3"], segs=4, tip_glow=1.0)
    # back armour and spines
    for i in range(P.get("plates", 3)):
        z = 1.5 - 0.17 * i
        c.ellipsoid(T((0, 0.0 + hunch * (0.9 - 0.2 * i) - 0.04, z)), (r(0.24 - 0.02 * i) * P.get("chest_w", 1.0) * S[0], r(0.05) * S[1], r(0.085) * S[2]), armor, ["spine", "chest"], rot=(-10, 0, 0), tint=(1.2, 0.7), segs=10, rings=4)
    for i in range(P.get("spines", 5)):
        z = 1.55 - 0.1 * i
        y = -0.1 + hunch * (0.9 - 0.15 * i) - 0.02 * i
        c.cone(T((0, y, z)), T((0, y - 0.1, z + 0.12 + 0.01 * i)), r(0.022), plate, ["spine", "chest"], segs=4, tip_glow=0.6)
    if P.get("ribs"):                                                       # dark chitin ribs across the chest and belly and a sternum plate: an armoured front, not bare skin
        for i in range(int(P["ribs"])):
            z = 1.52 - 0.075 * i
            w = (0.17 - 0.012 * i) * cw
            c.ellipsoid(T((0, 0.1 + hunch * 0.9 + 0.125 - 0.01 * i, z)), (r(w) * S[0], r(0.045) * S[1], r(0.022) * S[2]), dark, ["chest", "spine"], tint=(1.15, 0.7), segs=10, rings=3)
        c.ellipsoid(T((0, 0.1 + hunch * 0.9 + 0.14, 1.42)), (r(0.035) * S[0], r(0.03) * S[1], r(0.17) * S[2]), plate, ["chest", "spine"], tint=(1.1, 0.7), segs=6, rings=4)
    if P.get("belly_glow"):
        for i in range(4):
            c.box(T((0, 0.24 + hunch * 0.5, 1.4 - 0.1 * i)), (r(0.15) * S[0], r(0.01), r(0.016)), glow, ["chest", "spine"], glow=1.0)
    biped_clips(c, P)
    return c


# ------------------------------------------------------------------------------------------------------------------------------------------------
# the jackal: a fast quadruped pack hunter
# ------------------------------------------------------------------------------------------------------------------------------------------------

def jackal(name, P):
    from lib import add_skin_piece
    c = Creature(name)
    skin, dark, plate, glow = P["skin"], P["dark"], P["plate"], P["glow"]
    B = [("root", (0, 0, 0), (0, 0, 0.1), None), ("hips", (0, -0.3, 0.58), (0, -0.1, 0.6), "root"), ("spine", (0, -0.1, 0.6), (0, 0.15, 0.62), "hips"), ("chest", (0, 0.15, 0.62), (0, 0.38, 0.64), "spine"),
         ("neck", (0, 0.38, 0.66), (0, 0.55, 0.74), "chest"), ("head", (0, 0.55, 0.74), (0, 0.72, 0.74), "neck"), ("jaw", (0, 0.66, 0.7), (0, 0.84, 0.66), "head"),
         ("tail1", (0, -0.38, 0.6), (0, -0.7, 0.62), "hips"), ("tail2", (0, -0.7, 0.62), (0, -1.0, 0.7), "tail1"), ("tail3", (0, -1.0, 0.7), (0, -1.3, 0.82), "tail2")]
    for sd, sx in (("l", -1), ("r", 1)):
        B += [("fup_" + sd, (sx * 0.1, 0.34, 0.6), (sx * 0.11, 0.38, 0.3), "chest"), ("flow_" + sd, (sx * 0.11, 0.38, 0.3), (sx * 0.11, 0.3, 0.03), "fup_" + sd),
              ("bup_" + sd, (sx * 0.1, -0.3, 0.58), (sx * 0.11, -0.2, 0.3), "hips"), ("blow_" + sd, (sx * 0.11, -0.2, 0.3), (sx * 0.11, -0.34, 0.03), "bup_" + sd)]
    for n, h, t, par in B:
        c.bone(n, h, t, par)
    bones = [b[0] for b in B if b[0] != "root"]
    nd, ed = [], []

    def N(pos, rx, ry=None):
        nd.append((pos, (rx, ry if ry is not None else rx)))
        return len(nd) - 1
    i0 = N((0, -0.3, 0.58), 0.12, 0.1)
    i1 = N((0, 0.0, 0.6), 0.12, 0.1)
    i2 = N((0, 0.32, 0.62), 0.15, 0.12)
    i3 = N((0, 0.52, 0.72), 0.07)
    i4 = N((0, 0.66, 0.74), 0.07, 0.06)
    ed += [(i0, i1), (i1, i2), (i2, i3), (i3, i4)]
    for sx in (-1, 1):
        f0 = N((sx * 0.1, 0.34, 0.58), 0.065)
        f1 = N((sx * 0.11, 0.38, 0.3), 0.035)
        f2 = N((sx * 0.11, 0.3, 0.04), 0.03, 0.035)
        b0 = N((sx * 0.1, -0.28, 0.56), 0.08)
        b1 = N((sx * 0.11, -0.2, 0.3), 0.04)
        b2 = N((sx * 0.11, -0.34, 0.04), 0.03, 0.035)
        ed += [(i2, f0), (f0, f1), (f1, f2), (i0, b0), (b0, b1), (b1, b2)]
    t0 = N((0, -0.4, 0.6), 0.05)
    t1 = N((0, -0.8, 0.64), 0.03)
    t2 = N((0, -1.3, 0.84), 0.012)
    ed += [(i0, t0), (t0, t1), (t1, t2)]

    def paint(p, n):
        up = 0.5 + 0.5 * n.z
        k = 0.6 + 0.55 * up
        stripe = 0.5 + 0.5 * math.sin(p.y * 24.0)
        base = (skin[0] * k, skin[1] * k, skin[2] * k)
        if stripe > 0.78 and p.y > -0.35 and p.y < 0.4 and n.z > 0.1:
            return (min(1.0, dark[0] * 1.4), min(1.0, dark[1] * 1.4), min(1.0, dark[2] * 1.4))
        return base

    def stripes(p, n):
        stripe = 0.5 + 0.5 * math.sin(p.y * 24.0)
        return 0.7 if stripe > 0.78 and -0.35 < p.y < 0.4 and n.z > 0.1 else (0.9 if p.y < -1.1 else 0.0)
    add_skin_piece(c, nd, ed, paint, bones, subdiv=2, target_tris=1500, glow_fn=stripes)
    # head: long snout, brow, eyes, teeth, ears
    c.ellipsoid((0, 0.7, 0.73), (0.075, 0.13, 0.065), skin, ["head", "neck"], rot=(4, 0, 0), tint=(1.2, 0.6), segs=10, rings=6)
    c.ellipsoid((0, 0.86, 0.69), (0.05, 0.1, 0.04), dark, ["head", "jaw"], rot=(8, 0, 0), tint=(1.1, 0.6), segs=8, rings=5)
    c.ellipsoid((0, 0.8, 0.64), (0.045, 0.1, 0.022), dark, ["jaw"], rot=(10, 0, 0), segs=8, rings=4)
    for sx in (-1, 1):
        c.ellipsoid((sx * 0.055, 0.73, 0.78), (0.022, 0.018, 0.02), glow, ["head"], glow=1.0, segs=6, rings=4)
        c.cone((sx * 0.05, 0.6, 0.8), (sx * 0.09, 0.52, 0.99), 0.03, dark, ["head"], segs=4)
        for k in range(3):
            c.cone((sx * 0.025, 0.84 + 0.04 * k, 0.66), (sx * 0.025, 0.86 + 0.04 * k, 0.73), 0.008, (0.92, 0.9, 0.82), ["jaw", "head"], segs=3)
    for i in range(5):                                                       # dorsal spines
        c.cone((0, -0.3 + 0.15 * i, 0.69 + 0.02 * (i % 2)), (0, -0.36 + 0.15 * i, 0.86 + 0.03 * (i % 2)), 0.02, plate, ["spine", "hips", "chest"], segs=4, tip_glow=0.7)
    c.cone((0, -1.28, 0.8), (0, -1.5, 0.95), 0.03, plate, ["tail3"], segs=4, tip_glow=1.0)                 # tail barb
    for sx in (-1, 1):
        for pre, y in (("flow_", 0.3), ("blow_", -0.34)):
            for k in range(3):
                c.cone((sx * 0.11 + (k - 1) * 0.02, y, 0.03), (sx * 0.11 + (k - 1) * 0.03, y + 0.1, 0.0), 0.009, plate, [pre + ("l" if sx < 0 else "r")], segs=3)
    quad_clips(c, P)
    return c


def quad_clips(c, P):
    tails = ["tail1", "tail2", "tail3"]

    def gait(a, run):
        def fn(t, p):
            ph = 2.0 * math.pi * t
            for sd, off in (("l", 0.0), ("r", math.pi)):
                f = math.sin(ph + off)
                b = math.sin(ph + off + (math.pi if not run else 0.9))
                p.rot("fup_" + sd, x=a * 38.0 * f)
                p.rot("flow_" + sd, x=-a * 32.0 * max(0.0, math.cos(ph + off)) - 6.0)
                p.rot("bup_" + sd, x=a * 36.0 * b)
                p.rot("blow_" + sd, x=a * 34.0 * max(0.0, math.cos(ph + off + math.pi)) + 8.0)
            p.rot("spine", x=a * (8.0 if run else 3.0) * math.sin(ph * 2.0 + 0.8), z=a * 5.0 * math.sin(ph))
            p.rot("chest", z=-a * 4.0 * math.sin(ph))
            p.rot("head", x=-a * 5.0 * math.sin(ph * 2.0 + 0.8))
            p.move("root", z=0.04 * a * (abs(math.sin(ph * (1.0 if run else 1.0)))) * (1.6 if run else 1.0))
            for i, tb in enumerate(tails):
                p.rot(tb, z=a * 16.0 * math.sin(ph + i * 0.9))
        return fn
    c.clip("walk", 24, gait(0.8, False))
    c.clip("run", 14, gait(1.3, True))

    def idle(t, p):
        ph = 2.0 * math.pi * t
        p.rot("chest", x=1.8 * math.sin(ph))
        p.rot("head", x=-3.0 * math.sin(ph + 0.9), z=6.0 * math.sin(ph * 0.5))
        p.rot("jaw", x=3.0 + 3.0 * math.sin(ph * 2.0))
        for i, tb in enumerate(tails):
            p.rot(tb, z=10.0 * math.sin(ph + i * 0.8))
    c.clip("idle", 30, idle)

    def attack(t, p):                                                     # lunge and bite
        if t < 0.3:
            e = t / 0.3
            p.rot("spine", x=-10.0 * e)
            p.rot("head", x=-12.0 * e)
            p.rot("jaw", x=-26.0 * e)
            p.move("root", y=-0.1 * e, z=-0.05 * e)
        elif t < 0.5:
            e = (t - 0.3) / 0.2
            p.rot("spine", x=lerp_(-10.0, 14.0, e))
            p.rot("head", x=lerp_(-12.0, 16.0, e))
            p.rot("jaw", x=lerp_(-26.0, 20.0, e))
            p.rot("fup_l", x=40.0 * e)
            p.rot("fup_r", x=40.0 * e)
            p.move("root", y=lerp_(-0.1, 0.3, e))
        else:
            e = 1.0 - (t - 0.5) / 0.5
            p.rot("spine", x=14.0 * e)
            p.rot("head", x=16.0 * e)
            p.rot("jaw", x=20.0 * e)
            p.rot("fup_l", x=40.0 * e)
            p.rot("fup_r", x=40.0 * e)
            p.move("root", y=0.3 * e)
    c.clip("attack", 18, attack, False)

    def hit(t, p):
        e = math.sin(math.pi * min(t * 1.4, 1.0))
        p.rot("spine", x=-12.0 * e)
        p.rot("head", x=18.0 * e, z=10.0 * e)
        p.move("root", y=-0.1 * e)
    c.clip("hit", 10, hit, False)

    def dead(t, p):
        e = min(t * 1.3, 1.0)
        e = e * e * (3 - 2 * e)
        p.rot("root", y=88.0 * e)
        p.rot("fup_l", x=40.0 * e)
        p.rot("fup_r", x=-30.0 * e)
        p.rot("bup_l", x=-30.0 * e)
        p.rot("bup_r", x=40.0 * e)
        p.rot("head", x=20.0 * e)
        p.rot("jaw", x=26.0 * e)
        p.move("root", z=0.02 * e)
    c.clip("dead", 20, dead, False)

    def jump(t, p):
        e = math.sin(math.pi * t)
        p.rot("spine", x=-14.0 * (1.0 - t) + 10.0 * t)
        for sd in ("l", "r"):
            p.rot("fup_" + sd, x=-50.0 * e)
            p.rot("flow_" + sd, x=-20.0 * e)
            p.rot("bup_" + sd, x=60.0 * e)
            p.rot("blow_" + sd, x=-30.0 * e)
        p.move("root", z=0.1 * e)
    c.clip("jump", 14, jump, False)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# the bloater: a walking spore sac that swells and bursts
# ------------------------------------------------------------------------------------------------------------------------------------------------

def bloater(name, P):
    from lib import add_skin_piece
    c = Creature(name)
    skin, dark, plate, glow = P["skin"], P["dark"], P["plate"], P["glow"]
    B = [("root", (0, 0, 0), (0, 0, 0.1), None), ("body", (0, 0, 0.7), (0, 0.05, 1.2), "root"), ("head", (0, 0.5, 1.25), (0, 0.7, 1.3), "body"), ("jaw", (0, 0.62, 1.18), (0, 0.78, 1.1), "head")]
    for sd, sx in (("l", -1), ("r", 1)):
        B += [("leg_" + sd, (sx * 0.28, 0.0, 0.7), (sx * 0.3, 0.05, 0.3), "body"), ("foot_" + sd, (sx * 0.3, 0.05, 0.3), (sx * 0.3, 0.2, 0.04), "leg_" + sd),
              ("arm_" + sd, (sx * 0.5, 0.2, 1.1), (sx * 0.62, 0.34, 0.8), "body")]
    for n, h, t, par in B:
        c.bone(n, h, t, par)
    # the sac and the rest of the body as one skin
    nd, ed = [], []

    def N(pos, rx, ry=None):
        nd.append((pos, (rx, ry if ry is not None else rx)))
        return len(nd) - 1
    ib = N((0, 0.0, 0.95), 0.62, 0.55)
    ih = N((0, 0.52, 1.24), 0.16)
    ed.append((ib, ih))
    for sx in (-1, 1):
        l0 = N((sx * 0.28, 0.0, 0.62), 0.16)
        l1 = N((sx * 0.3, 0.05, 0.3), 0.11)
        l2 = N((sx * 0.3, 0.2, 0.05), 0.1, 0.13)
        a0 = N((sx * 0.5, 0.2, 1.1), 0.1)
        a1 = N((sx * 0.62, 0.34, 0.8), 0.07)
        ed += [(ib, l0), (l0, l1), (l1, l2), (ib, a0), (a0, a1)]

    def paint(p, n):
        up = 0.5 + 0.5 * n.z
        k = 0.65 + 0.5 * up
        if p.z > 0.55 and n.y > 0.1:
            return (min(1.0, skin[0] * k * 1.15 + 0.06), min(1.0, skin[1] * k * 1.15 + 0.08), min(1.0, skin[2] * k * 1.0))
        return (skin[0] * k, skin[1] * k, skin[2] * k)

    def pores(p, n):
        return 0.5 if p.z > 0.6 and abs(math.sin(p.x * 14.0) * math.sin(p.y * 14.0 + p.z * 9.0)) > 0.94 else 0.0
    add_skin_piece(c, nd, ed, paint, [b[0] for b in B if b[0] != "root"], subdiv=2, target_tris=1700, glow_fn=pores)
    c.ellipsoid((0, 0.2, 1.0), (0.34, 0.3, 0.36), (0.4, 0.55, 0.09), ["body"], glow=0.3, segs=10, rings=6)                      # the core, seen through the skin at the front
    c.ellipsoid((0, 0.54, 1.27), (0.14, 0.18, 0.12), dark, ["head", "body"], rot=(8, 0, 0), tint=(1.1, 0.6), segs=10, rings=5)
    c.ellipsoid((0, 0.66, 1.14), (0.1, 0.12, 0.06), dark, ["jaw"], segs=8, rings=4)
    for sx in (-1, 1):
        c.ellipsoid((sx * 0.075, 0.64, 1.31), (0.032, 0.024, 0.03), glow, ["head"], glow=1.0, segs=6, rings=4)
    for i in range(9):                                                          # spore pods on the back and sides
        a = 0.6 + i * 0.58
        c.cone((math.cos(a) * 0.5, -0.1 + 0.08 * (i % 3), 0.95 + 0.25 * math.sin(a * 1.7)), (math.cos(a) * 0.7, -0.15 + 0.08 * (i % 3), 1.05 + 0.4 * math.sin(a * 1.7)), 0.07, plate, ["body"], segs=5, tip_glow=1.0)
    bloater_clips(c)
    return c


def bloater_clips(c):
    def gait(a, speed):
        def fn(t, p):
            ph = 2.0 * math.pi * t
            for sd, off in (("l", 0.0), ("r", math.pi)):
                s_ = math.sin(ph + off)
                p.rot("leg_" + sd, x=a * 30.0 * s_)
                p.rot("foot_" + sd, x=-a * 16.0 * s_)
                p.rot("arm_" + sd, x=-a * 20.0 * s_)
            p.rot("body", z=a * 6.0 * math.sin(ph), y=a * 5.0 * math.sin(ph))
            p.move("root", z=0.05 * a * abs(math.sin(ph)))
            p.scale("body", 1.0 + 0.03 * math.sin(ph * 2.0), 1.0 + 0.03 * math.sin(ph * 2.0), 1.0 - 0.03 * math.sin(ph * 2.0))
        return fn
    c.clip("walk", 28, gait(0.9, 1.0))
    c.clip("run", 18, gait(1.4, 1.5))

    def idle(t, p):
        ph = 2.0 * math.pi * t
        k = 0.5 + 0.5 * math.sin(ph)
        p.scale("body", 1.0 + 0.05 * k, 1.0 + 0.05 * k, 1.0 + 0.04 * k)
        p.rot("head", x=-3.0 * math.sin(ph + 0.8), z=4.0 * math.sin(ph * 0.5))
        p.rot("arm_l", x=3.0 * math.sin(ph))
        p.rot("arm_r", x=-3.0 * math.sin(ph))
    c.clip("idle", 30, idle)

    def attack(t, p):                                                          # swell, then burst: the brain detonates it
        e = t * t
        p.scale("body", 1.0 + 0.3 * e, 1.0 + 0.3 * e, 1.0 + 0.25 * e)
        p.rot("arm_l", x=-40.0 * e)
        p.rot("arm_r", x=-40.0 * e)
        p.rot("head", x=-10.0 * e)
        p.rot("jaw", x=-24.0 * e)
    c.clip("attack", 18, attack, False)

    def hit(t, p):
        e = math.sin(math.pi * min(t * 1.4, 1.0))
        p.scale("body", 1.0 - 0.1 * e, 1.0 - 0.1 * e, 1.0 + 0.12 * e)
        p.rot("head", x=14.0 * e)
    c.clip("hit", 10, hit, False)

    def dead(t, p):
        e = min(t * 1.3, 1.0)
        p.scale("body", 1.0 + 0.35 * e, 1.0 + 0.35 * e, 1.0 - 0.5 * e)
        p.move("root", z=-0.15 * e)
        p.rot("leg_l", x=-30.0 * e)
        p.rot("leg_r", x=30.0 * e)
    c.clip("dead", 18, dead, False)
    c.clip("jump", 14, lambda t, p: p.scale("body", 1.0, 1.0, 1.0 + 0.1 * math.sin(math.pi * t)), False)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# the walkers: hard-surface bipedal machines (light walker, heavy mech with missile pods)
# ------------------------------------------------------------------------------------------------------------------------------------------------

def mech(name, P):
    c = Creature(name)
    k = P.get("k", 1.0)
    steel, dark, hazard, glow, plate = P["steel"], P["dark"], P["hazard"], P["glow"], P["plate"]
    glass = (0.02, 0.035, 0.06)
    glow_col = glow
    heavy = bool(P.get("pods"))

    def T(p):
        return (p[0] * k, p[1] * k, p[2] * k)
    B = [("root", (0, 0, 0), (0, 0, 0.1 * k), None), ("hips", (0, 0, 1.3), (0, 0, 1.5), "root"), ("torso", (0, 0, 1.5), (0, 0.05, 2.1), "hips"), ("head", (0, 0.3, 2.0), (0, 0.5, 2.05), "torso")]
    for sd, sx in (("l", -1), ("r", 1)):
        B += [("thigh_" + sd, (sx * 0.4, 0, 1.3), (sx * 0.4, 0.3, 0.8), "hips"), ("shin_" + sd, (sx * 0.4, 0.3, 0.8), (sx * 0.4, -0.1, 0.3), "thigh_" + sd), ("foot_" + sd, (sx * 0.4, -0.1, 0.3), (sx * 0.4, 0.3, 0.05), "shin_" + sd),
              ("arm_" + sd, (sx * 0.68, 0.05, 1.95), (sx * 0.74, 0.4, 1.55), "torso")]
    for n, h, t, par in B:
        c.bone(n, T(h), T(t), par)

    def bx(cen, size, col, bones, rot=(0, 0, 0), glow=0.0, taper=(1.0, 1.0)):
        c.box(T(cen), (size[0] * k, size[1] * k, size[2] * k), col, bones, rot, glow, taper)

    def el(cen, rad, col, bones, glow=0.0, segs=8, rings=5, rot=(0, 0, 0)):
        c.ellipsoid(T(cen), (rad[0] * k, rad[1] * k, rad[2] * k), col, bones, rot=rot, glow=glow, segs=segs, rings=rings)

    def cy(base, tip, r, col, bones, segs=8, glow=0.0, tip_glow=None):
        c.tube([T(base), T(tip)], [r * k, r * k], col, bones, segs=segs, glow=glow, caps=True, smooth=True)
        if tip_glow:                                                                  # a small glowing muzzle, not a glowing barrel
            c.ellipsoid(T(tip), (r * 0.85 * k, 0.03 * k, r * 0.85 * k), glow_col, bones, glow=tip_glow, segs=6, rings=3)
    # pelvis: a skirt of hip armour and a front plate
    bx((0, 0, 1.38), (0.9, 0.55, 0.3), dark, ["hips"])
    bx((0, 0.3, 1.27), (0.44, 0.14, 0.28), plate, ["hips"], taper=(0.8, 1.0))
    for sx in (-1, 1):
        bx((sx * 0.5, 0.0, 1.34), (0.26, 0.52, 0.34), steel, ["hips"])
    # torso: a box with a layered front glacis, side slabs, grille vents and a hazard roof
    bx((0, 0.0, 1.85), (0.95, 0.75, 0.75), steel, ["torso"], taper=(0.92, 0.9))
    bx((0, 0.39, 1.92), (0.8, 0.12, 0.5), plate, ["torso"], taper=(0.84, 1.0))
    bx((0, 0.4, 1.58), (0.62, 0.1, 0.14), dark, ["torso"])
    for i in range(3):
        bx((0, 0.452, 1.55 + 0.045 * i), (0.5, 0.02, 0.018), steel, ["torso"])
    for sx in (-1, 1):
        bx((sx * 0.5, 0.02, 1.86), (0.1, 0.6, 0.55), plate, ["torso"])
    bx((0, 0.0, 2.27), (0.8, 0.6, 0.12), hazard, ["torso"])
    # the sensor head: a dark wedge on the roof with a glowing visor and a lens, an antenna on the back
    bx((0, 0.3, 2.42), (0.46, 0.4, 0.22), dark, ["head", "torso"], taper=(0.9, 0.8))
    bx((0, 0.51, 2.43), (0.38, 0.03, 0.07), glow, ["head"], glow=1.0)
    el((0.16, 0.52, 2.43), (0.05, 0.03, 0.05), glass, ["head"], segs=6, rings=3)
    cy((-0.3, -0.2, 2.3), (-0.33, -0.26, 2.9), 0.012, dark, ["torso"], segs=4, tip_glow=0.8)
    # a chin cannon under the cockpit
    cy((0, 0.5, 1.72), (0, 1.0, 1.72), 0.065, dark, ["torso"], tip_glow=0.8)
    bx((0, 0.45, 1.72), (0.2, 0.14, 0.16), plate, ["torso"])
    # back unit: the glowing reactor (the weak point), grille bars, two exhaust stacks
    bx((0, -0.42, 1.95), (0.6, 0.18, 0.55), dark, ["torso"])
    bx((0, -0.535, 1.95), (0.46, 0.05, 0.44), dark, ["torso"])
    bx((0, -0.575, 1.95), (0.34, 0.05, 0.32), glow, ["torso"], glow=1.0)
    for dx in (-0.1, 0.0, 0.1):
        bx((dx, -0.605, 1.95), (0.02, 0.012, 0.32), dark, ["torso"])
    for sx in (-1, 1):
        cy((sx * 0.24, -0.46, 2.2), (sx * 0.24, -0.5, 2.72), 0.065, dark, ["torso"], segs=6, tip_glow=0.5)
        bx((sx * 0.24, -0.46, 2.2), (0.18, 0.18, 0.12), steel, ["torso"])
    for sd, sx in (("l", -1), ("r", 1)):
        # legs: hip joint, thigh piston with an armour plate, knee cap, shin piston with a front plate and a hazard stripe, ankle, a three-part foot
        el((sx * 0.4, 0.0, 1.3), (0.17, 0.17, 0.17), dark, ["hips", "thigh_" + sd])
        cy((sx * 0.4, 0.0, 1.3), (sx * 0.4, 0.3, 0.8), 0.12, steel, ["hips", "thigh_" + sd, "shin_" + sd])
        bx((sx * 0.4, 0.26, 1.12), (0.3, 0.1, 0.42), plate, ["thigh_" + sd], rot=(31, 0, 0), taper=(0.85, 0.9))
        cy((sx * 0.6, 0.0, 1.25), (sx * 0.58, 0.28, 0.86), 0.035, dark, ["hips", "thigh_" + sd], segs=5)
        el((sx * 0.4, 0.3, 0.8), (0.15, 0.17, 0.15), dark, ["thigh_" + sd, "shin_" + sd])
        bx((sx * 0.4, 0.41, 0.8), (0.22, 0.1, 0.26), plate, ["thigh_" + sd, "shin_" + sd], taper=(0.82, 0.9))
        bx((sx * 0.4, 0.465, 0.8), (0.12, 0.02, 0.14), hazard, ["thigh_" + sd, "shin_" + sd])
        cy((sx * 0.4, 0.3, 0.8), (sx * 0.4, -0.1, 0.3), 0.1, steel, ["thigh_" + sd, "shin_" + sd])
        bx((sx * 0.4, 0.19, 0.48), (0.26, 0.1, 0.4), plate, ["shin_" + sd], rot=(-39, 0, 0), taper=(0.8, 1.0))
        bx((sx * 0.4, 0.22, 0.4), (0.2, 0.04, 0.1), hazard, ["shin_" + sd], rot=(-39, 0, 0))
        el((sx * 0.4, -0.1, 0.3), (0.12, 0.12, 0.12), dark, ["shin_" + sd, "foot_" + sd])
        bx((sx * 0.4, 0.1, 0.1), (0.36, 0.7, 0.14), dark, ["foot_" + sd, "shin_" + sd])
        bx((sx * 0.4, 0.4, 0.11), (0.34, 0.22, 0.1), steel, ["foot_" + sd])
        bx((sx * 0.4, -0.2, 0.18), (0.3, 0.2, 0.22), steel, ["foot_" + sd, "shin_" + sd])
        # shoulder: a pauldron block with a hazard strip, the joint, the upper arm, the elbow
        bx((sx * 0.7, 0.02, 2.02), (0.36, 0.5, 0.3), plate, ["torso"], taper=(0.9, 0.9))
        bx((sx * 0.7, 0.02, 2.19), (0.34, 0.48, 0.05), hazard, ["torso"])
        el((sx * 0.62, 0.05, 1.93), (0.15, 0.17, 0.15), dark, ["arm_" + sd, "torso"])
        cy((sx * 0.68, 0.05, 1.95), (sx * 0.74, 0.4, 1.5), 0.11, steel, ["torso", "arm_" + sd])
        el((sx * 0.74, 0.4, 1.5), (0.13, 0.13, 0.13), dark, ["arm_" + sd])
        if heavy:                                                                    # a missile pod on each shoulder: a box with a grid of glowing tube mouths, and a heavy arm cannon
            bx((sx * 0.8, -0.05, 2.35), (0.55, 0.7, 0.42), dark, ["torso"])
            bx((sx * 0.8, -0.05, 2.58), (0.5, 0.64, 0.04), steel, ["torso"])
            for rr in range(2):
                for cc in range(3):
                    c.ellipsoid(T((sx * (0.66 + 0.15 * cc), 0.31, 2.27 + 0.16 * rr)), (0.055 * k, 0.03 * k, 0.055 * k), glow, ["torso"], glow=0.95, segs=6, rings=4)
            bx((sx * 0.74, 0.58, 1.5), (0.28, 0.4, 0.28), plate, ["arm_" + sd])
            cy((sx * 0.74, 0.6, 1.5), (sx * 0.74, 1.2, 1.5), 0.075, dark, ["arm_" + sd], tip_glow=0.9)
            bx((sx * 0.95, 0.5, 1.46), (0.14, 0.3, 0.3), dark, ["arm_" + sd])
        else:                                                                        # a twin autocannon with a shroud and a magazine
            bx((sx * 0.74, 0.55, 1.5), (0.28, 0.34, 0.22), plate, ["arm_" + sd])
            for dx in (-0.065, 0.065):
                cy((sx * 0.74 + dx, 0.62, 1.5), (sx * 0.74 + dx, 1.12, 1.5), 0.036, dark, ["arm_" + sd], segs=6, tip_glow=0.9)
            bx((sx * 0.92, 0.5, 1.5), (0.12, 0.26, 0.22), dark, ["arm_" + sd])
    mech_clips(c, P)
    return c


def mech_clips(c, P):
    k = P.get("amp", 1.0)

    def gait(a, quick):
        def fn(t, p):
            ph = 2.0 * math.pi * t
            for sd, off in (("l", 0.0), ("r", math.pi)):
                s_ = math.sin(ph + off)
                cs = math.cos(ph + off)
                p.rot("thigh_" + sd, x=a * 26.0 * s_)
                p.rot("shin_" + sd, x=-a * 34.0 * max(0.0, cs) - 4.0)
                p.rot("foot_" + sd, x=a * 10.0 * s_ + 12.0 * max(0.0, cs))
                p.rot("arm_" + sd, x=-a * 10.0 * s_)
            p.rot("torso", z=a * 5.0 * math.sin(ph), x=3.0 * a)
            p.rot("head", z=-a * 4.0 * math.sin(ph))
            p.move("root", z=-0.06 * a * abs(math.cos(ph)))
        return fn
    c.clip("walk", 30, gait(0.8 * k, False))
    c.clip("run", 20, gait(1.2 * k, True))

    def idle(t, p):
        ph = 2.0 * math.pi * t
        p.rot("head", z=8.0 * math.sin(ph), x=2.0 * math.sin(ph * 2.0))
        p.rot("torso", z=1.5 * math.sin(ph))
        p.move("root", z=0.004 * math.sin(ph * 2.0))
    c.clip("idle", 40, idle)

    def attack(t, p):                                                             # recoil: torso back, arms up, then settle
        e = math.sin(math.pi * min(t * 1.2, 1.0))
        p.rot("torso", x=-7.0 * e)
        p.rot("arm_l", x=-14.0 * e)
        p.rot("arm_r", x=-14.0 * e)
        p.rot("head", x=4.0 * e)
        p.move("root", y=-0.05 * e)
    c.clip("attack", 16, attack, False)

    def hit(t, p):
        e = math.sin(math.pi * min(t * 1.4, 1.0))
        p.rot("torso", x=-6.0 * e, z=4.0 * e)
        p.rot("head", z=-8.0 * e)
    c.clip("hit", 10, hit, False)

    def dead(t, p):                                                               # the knees give way, the torso drops forward and sparks out
        e = min(t * 1.2, 1.0)
        e = e * e * (3 - 2 * e)
        p.rot("thigh_l", x=60.0 * e)
        p.rot("thigh_r", x=70.0 * e)
        p.rot("shin_l", x=-100.0 * e)
        p.rot("shin_r", x=-110.0 * e)
        p.rot("torso", x=28.0 * e)
        p.rot("head", x=18.0 * e)
        p.rot("arm_l", x=40.0 * e)
        p.rot("arm_r", x=30.0 * e)
        p.move("root", z=-0.7 * e, y=0.3 * e)
    c.clip("dead", 24, dead, False)
    c.clip("jump", 14, lambda t, p: p.rot("torso", x=-6.0 * math.sin(math.pi * t)), False)


def build_all():
    out = {}
    # GRUNT: a hunched alien infantryman with long arms, claws and a whip tail
    out["vael_grunt"] = biped("vael_grunt", {"skin": (0.3, 0.17, 0.26), "dark": (0.15, 0.09, 0.16), "plate": (0.82, 0.76, 0.62), "glow": (1.0, 0.55, 0.12), "hunch": 0.1, "head": (0.095, 0.2, 0.1),
        "eyes": 4, "plates": 3, "spines": 5, "tail_blade": False, "amp": 1.0, "s": (1.0, 1.0, 1.0)})
    # BRUTE: huge, wide, fists and heavy back plates, glowing belly cracks
    out["vael_brute"] = biped("vael_brute", {"skin": (0.34, 0.14, 0.12), "dark": (0.17, 0.07, 0.07), "plate": (0.78, 0.7, 0.55), "armor": (0.24, 0.1, 0.09), "angular": True, "glow": (1.0, 0.45, 0.1), "hunch": 0.16, "head": (0.11, 0.17, 0.1),
        "head_lift": -0.04, "eyes": 2, "plates": 4, "spines": 6, "tail": False, "fist": 0.13, "arm_r": 0.1, "leg_r": 0.14, "shoulder": 0.3, "stance": 0.2, "chest_w": 1.55, "pauldrons": True,
        "knees": True, "belly_glow": True, "s": (1.35, 1.25, 1.42), "rs": 1.45, "amp": 0.8, "strike": 1.1, "lean": 8.0})
    # HUNTER: tall and slender, a long bio-cannon on the right arm, a swept crest
    out["vael_hunter"] = biped("vael_hunter", {"skin": (0.5, 0.31, 0.09), "dark": (0.15, 0.085, 0.03), "plate": (0.09, 0.095, 0.11), "glow": (0.3, 1.0, 0.95), "hunch": 0.05, "head": (0.095, 0.24, 0.11),
        "eyes": 2, "plates": 4, "spines": 3, "tail": True, "cannon": True, "crest": 1.0, "s": (1.0, 1.0, 1.26), "rs": 1.0, "amp": 1.0, "leg_r": 0.095, "arm_r": 0.062, "armswing": 0.5,
        "chest_w": 1.3, "angular": True, "pauldrons": True, "knees": True, "shoulder": 0.27, "ribs": 4, "skin_tris": 1350})
    # ELITE: armoured, shoulder pauldrons and knee guards, a crest, a shield emitter on the left arm
    out["vael_elite"] = biped("vael_elite", {"skin": (0.22, 0.26, 0.36), "dark": (0.1, 0.12, 0.2), "plate": (0.9, 0.82, 0.5), "glow": (0.3, 0.9, 1.0), "hunch": 0.02, "head": (0.1, 0.19, 0.11),
        "eyes": 2, "plates": 4, "spines": 2, "tail": False, "angular": True, "pauldrons": True, "knees": True, "emitter": True, "crest": 0.8, "shoulder": 0.27, "s": (1.08, 1.0, 1.14), "rs": 1.15, "amp": 0.9,
        "chest_w": 1.2, "skull_plate": True})
    # STALKER: thin, long limbs, forearm blades, a hooded fin, a long tail
    out["vael_stalker"] = biped("vael_stalker", {"skin": (0.16, 0.14, 0.26), "dark": (0.07, 0.06, 0.13), "plate": (0.55, 0.52, 0.7), "glow": (1.0, 0.25, 0.75), "hunch": 0.06, "head": (0.075, 0.2, 0.09),
        "eyes": 3, "plates": 2, "spines": 4, "tail": True, "blades": True, "tail_blade": True, "crest": 0.7, "s": (0.86, 1.0, 1.14), "rs": 0.8, "amp": 1.3, "leg_r": 0.07, "arm_r": 0.045,
        "strike": 1.2})
    out["vael_jackal"] = jackal("vael_jackal", {"skin": (0.12, 0.3, 0.3), "dark": (0.06, 0.16, 0.18), "plate": (0.8, 0.76, 0.62), "glow": (1.0, 0.45, 0.1)})
    out["vael_bloater"] = bloater("vael_bloater", {"skin": (0.3, 0.36, 0.11), "dark": (0.11, 0.15, 0.06), "plate": (0.62, 0.52, 0.24), "glow": (0.7, 1.0, 0.2)})
    out["grid_walker"] = mech("grid_walker", {"k": 0.95, "steel": (0.42, 0.45, 0.5), "dark": (0.14, 0.15, 0.18), "hazard": (0.9, 0.7, 0.1), "glow": (1.0, 0.5, 0.12), "plate": (0.55, 0.58, 0.62), "amp": 1.0})
    out["grid_heavy"] = mech("grid_heavy", {"k": 1.7, "steel": (0.32, 0.36, 0.4), "dark": (0.1, 0.11, 0.13), "hazard": (0.85, 0.6, 0.08), "glow": (1.0, 0.4, 0.1), "plate": (0.42, 0.46, 0.5), "pods": True, "amp": 0.8})
    return out
