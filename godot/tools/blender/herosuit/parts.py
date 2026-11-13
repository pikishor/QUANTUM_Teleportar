"""The hero suit kit (wave 112): layered tactical armour fitted to the Quaternius base body. One function per armour piece; each registers its Part(s) in the Kit with a bone, a kind
(shader palette slot), a glow zone and the suit sets it belongs to. Blender axes: x = right, y = forward, z = up, metres. Every conformal piece is a shell() of ray-fitted quads.

Silhouette idea (reads from behind, in motion, at 15-80 m): a broad layered shoulder line (three stacked lames per pauldron, the right one carries a swept phase fin), a tall gorget
framing the head, a vertical core pack with two antenna blades and a glowing ring on the back, a banded waist, articulated thigh / knee / shin guards, heavy boots, and a short cloak.
"""
import math
import os
import sys

from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from fit import Limb, bump, dome_surf, ellipse_surf, lerp, planar, sheet, shell, shell_fn, sm  # noqa: E402
from helpers import ring_se  # noqa: E402
from kitlib import (K_ACCENT, K_CANVAS, K_CLOTH, K_DARK, K_FABRIC, K_GLOW, K_GOLD, K_PLATE, Z_ARMS, Z_CORE, Z_HANDS, Z_HEAD, Z_LEGS, Z_WINGS)  # noqa: E402

import shade  # noqa: E402
import numpy as np  # noqa: E402


def shade_hplate(c, i):
    """Painted composite armour of the hero (kit kind "hplate"): a clean satin paint, soft wear on the convex edges only (bare metal), a faint grime in the cavities, crisp panel grooves in
    the concave creases. The stock `plating` kind scratches and stains too much for a hero (it read as cracked concrete on a phone)."""
    sm_, P, C = shade.sm, c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 4.0, 3, 0.5, 11)
    fine = c.noise.fbm3(P, 140.0, 2, 0.5, 12)
    edge = sm_(0.0045, 0.0006, c.cx[i]) * sm_(0.2, 0.6, c.noise.fbm3(P, 55.0, 3, 0.5, 13))
    dirt = shade.grime_mask(c, i, 0.35, 0.3, 0.7, 0.4, 5)
    paint = C * (0.9 + 0.2 * mott)[:, None] * (0.97 + 0.06 * fine)[:, None]
    bare = np.array([0.55, 0.55, 0.57]) * (0.85 + 0.3 * fine)[:, None]
    alb = paint * (1.0 - 0.26 * dirt)[:, None]
    alb = alb * (1.0 - edge[:, None]) + bare * edge[:, None]
    groove = sm_(0.0022, 0.0, c.cc[i])
    alb = alb * (1.0 - 0.38 * groove)[:, None]
    c.alb[i] = alb
    c.rough[i] = np.clip(0.46 + 0.10 * (mott - 0.5) + 0.12 * dirt - 0.22 * edge, 0.2, 0.8)
    c.metal[i] = np.clip(edge * 0.9, 0.0, 0.9)
    c.height[i] = -0.0004 * edge - 0.0007 * groove + 0.00015 * (fine - 0.5)


def shade_hdark(c, i):
    """Dark satin composite (kit kind "hdark": the pack, bracers, bands, shafts): a soft mottle, a fine grain, bare metal on the convex edges. No weave: the stock carbon twill aliased into
    large light diamonds at the hero's texel density."""
    sm_, P, C = shade.sm, c.P[i], c.C[i]
    mott = c.noise.fbm3(P, 5.0, 3, 0.5, 31)
    fine = c.noise.fbm3(P, 160.0, 2, 0.5, 32)
    edge = sm_(0.0042, 0.0005, c.cx[i]) * sm_(0.25, 0.6, c.noise.fbm3(P, 60.0, 3, 0.5, 33))
    alb = C * (0.85 + 0.3 * mott)[:, None] * (0.95 + 0.10 * fine)[:, None]
    alb = alb * (1.0 - edge[:, None]) + np.array([0.28, 0.29, 0.31]) * edge[:, None]
    groove = sm_(0.0022, 0.0, c.cc[i])
    c.alb[i] = alb * (1.0 - 0.3 * groove)[:, None]
    c.rough[i] = np.clip(0.42 + 0.10 * (fine - 0.5) - 0.2 * edge, 0.15, 0.8)
    c.metal[i] = np.clip(0.2 + 0.6 * edge, 0.0, 0.9)
    c.height[i] = -0.0005 * groove + 0.0001 * (fine - 0.5)


shade.KINDS["hdark"] = shade_hdark
shade.KIND_IDS["hdark"] = len(shade.KIND_IDS)
shade.KINDS["hplate"] = shade_hplate
shade.KIND_IDS["hplate"] = len(shade.KIND_IDS)            # the baker dispatches through KIND_IDS (built once at import)

R = math.radians
RES = float(os.environ.get("QT_HERO_RES", "0.55"))              # grid resolution factor of every conformal piece (triangle budget lever)


def _rc(rows, cols, closed_s):
    r = rows if rows <= 1 else max(2, int(round(rows * RES)))
    c = cols if cols <= 1 else max(8 if closed_s else 2, int(round(cols * RES)))
    return r, c


def sh(body, rows, cols, rayfn, off_out, off_in, closed_s=False, miss_r=None, maxd=1.6):
    """shell() with the kit's resolution factor: strips (one row or one column) keep their single row / column."""
    r, c = _rc(rows, cols, closed_s)
    return shell(body, r, c, rayfn, off_out, off_in, closed_s, maxd=maxd, miss_r=miss_r)


def shf(rows, cols, surf, off_out, off_in, closed_s=False):
    r, c = _rc(rows, cols, closed_s)
    return shell_fn(r, c, surf, off_out, off_in, closed_s)


ALL = "vanguard,stealth,assault,flight"
HEAVY = "vanguard,assault"


def _raw(part, vf, mat, tint=(1, 1, 1), bevel=0.0025, bsegs=1, mirror=True, sharp=55.0, bangle=55.0):
    v, f = vf
    part.raw(v, f, mat, tint, closed=False, bevel=bevel, bsegs=bsegs, bangle=bangle, sharp=sharp, mirror=mirror)


def materials(kit):
    m = {}
    m["plate"] = kit.mat("plate", tex="hplate", color=(0.50, 0.50, 0.52))
    m["steel"] = kit.mat("steel", tex="steel", color=(0.15, 0.16, 0.18))
    m["rubber"] = kit.mat("rubber", tex="rubber", color=(0.05, 0.05, 0.055))
    m["fabric"] = kit.mat("fabric", tex="fabric", color=(0.45, 0.45, 0.47))
    m["carbon"] = kit.mat("carbon", tex="hdark", color=(0.10, 0.105, 0.115))
    m["boot"] = kit.mat("boot", tex="fabric", color=(0.09, 0.09, 0.098))
    m["cloak"] = kit.mat("cloak", tex="fabric", color=(0.5, 0.5, 0.52))
    m["canvas"] = kit.mat("canvas", tex="fabric", color=(0.16, 0.15, 0.11))
    m["glow"] = kit.mat("glow", tex=None, color=(1.0, 1.0, 1.0), emit=(1.0, 1.0, 1.0), emit_strength=1.0)
    return m


# ------------------------------------------------------------------------------------------------------------------------------------------------
# torso
# ------------------------------------------------------------------------------------------------------------------------------------------------

def chest(kit, body, M):
    """Breastplate with a raised sternum spine, two pectoral shells and the quantum core in a housing."""
    p = kit.new("chest_base")

    def ext(s, t):
        a = abs(2 * s - 1)
        w = 0.148 + 0.050 * sm(0.0, 0.5, t) - 0.024 * sm(0.62, 1.0, t)
        zb = 1.160 + 0.036 * a ** 1.5
        zt = 1.462 - 0.058 * math.exp(-((2 * s - 1) / 0.30) ** 2)
        return (2 * s - 1) * w, zb + t * (zt - zb)

    fn = planar(body, (0, 1.0, 0), (0, -1, 0), (1, 0, 0), (0, 0, 1), ext)
    _raw(p, sh(body, 10, 14, fn, lambda s, t: 0.017 + 0.004 * bump(s, 0.5, 0.35), 0.006), M["plate"], mirror=False, bevel=0.003, bsegs=1)
    kit.done(p, "spine_02", K_PLATE, Z_CORE, ALL)

    p = kit.new("chest_pec")
    def ext2(s, t):
        x = 0.014 + s * 0.158
        zb = 1.300 - 0.052 * s
        zt = 1.440 - 0.040 * s * s
        return x, zb + t * (zt - zb)
    fn = planar(body, (0, 1.0, 0), (0, -1, 0), (1, 0, 0), (0, 0, 1), ext2)
    _raw(p, sh(body, 6, 8, fn, lambda s, t: 0.031 + 0.004 * bump(s, 0.4, 0.5), 0.013), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "spine_02", K_ACCENT, Z_CORE, HEAVY, lr=True)

    p = kit.new("chest_sternum")
    def ext3(s, t):
        return (2 * s - 1) * 0.029 * (1.0 - 0.3 * t), 1.178 + t * 0.255
    fn = planar(body, (0, 1.0, 0), (0, -1, 0), (1, 0, 0), (0, 0, 1), ext3)
    _raw(p, sh(body, 8, 3, fn, lambda s, t: 0.033 + 0.003 * bump(s, 0.5, 0.5), 0.012), M["steel"], mirror=False, bevel=0.002, bsegs=1)
    kit.done(p, "spine_02", K_DARK, Z_CORE, ALL)

    # the quantum core: a steel housing ring, a recessed glowing disc
    yz = body.ray((0, 1.0, 1.335), (0, -1, 0))
    yf = yz[0].y + 0.036
    p = kit.new("core_ring")
    p.torus(0.036, 0.0075, pos=(0, yf, 1.335), rot=(90, 0, 0), mat=M["steel"], segs=18, sides=6)
    p.cyl(0.030, 0.006, pos=(0, yf - 0.002, 1.335), axis="y", mat=M["steel"], segs=18)
    kit.done(p, "spine_02", K_DARK, Z_CORE, ALL)
    p = kit.new("core_glow")
    p.cyl(0.025, 0.004, pos=(0, yf + 0.004, 1.335), axis="y", mat=M["glow"], segs=18)
    kit.done(p, "spine_02", K_GLOW, Z_CORE, ALL)


def abdomen(kit, body, M):
    """Two overlapping lames around the belly and the belt with its buckle and pouches."""
    for name, z0, z1, off in (("abd_lame_a", 1.075, 1.135, 0.026), ("abd_lame_b", 1.020, 1.075, 0.020)):
        limb = Limb(body, (0, -0.02, z0 - 0.01), (0, -0.02, z1 + 0.01), 6, up=(0, 1, 0), fwd=(1, 0, 0), radius=0.2)
        p = kit.new(name)
        fn = limb.span(0.08, 0.92, R(-62), R(62))
        _raw(p, sh(body, 4, 10, fn, lambda s, t, o=off: o + 0.006 * (1 - t) ** 2 + 0.004 * bump(s, 0.5, 0.5), 0.007), M["plate"], bevel=0.003, bsegs=1, mirror=False)
        kit.done(p, "spine_01", K_PLATE, Z_CORE, HEAVY)

    p = kit.new("belt")
    limb = Limb(body, (0, -0.045, 0.93), (0, -0.045, 1.01), 6, up=(0, 1, 0), fwd=(1, 0, 0), radius=0.22)
    fn = limb.span(0.10, 0.90, R(0), R(360))
    _raw(p, sh(body, 4, 28, fn, lambda s, t: 0.026 - 0.006 * (1 - bump(t, 0.5, 0.5)), 0.007, closed_s=True), M["fabric"], bevel=0.002, bsegs=1, mirror=False)
    kit.done(p, "pelvis", K_FABRIC, Z_CORE, ALL)
    yf = body.ray((0, 1.0, 0.972), (0, -1, 0))[0].y
    p = kit.new("buckle")
    p.box((0.068, 0.022, 0.050), (0, yf + 0.032, 0.972), mat=M["steel"], bevel=0.004, bsegs=1)
    p.box((0.040, 0.010, 0.030), (0, yf + 0.046, 0.972), mat=M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "pelvis", K_DARK, Z_CORE, ALL)
    p = kit.new("buckle_glow")
    p.box((0.020, 0.004, 0.014), (0, yf + 0.052, 0.972), mat=M["glow"], bevel=0.0)
    kit.done(p, "pelvis", K_GLOW, Z_CORE, ALL)
    # hip pouches (canvas) and a hip plate each side
    p = kit.new("pouch")
    p.box((0.060, 0.080, 0.095), (0.198, -0.015, 0.900), mat=M["canvas"], bevel=0.007, bsegs=1, mirror=True)
    p.box((0.064, 0.086, 0.026), (0.198, -0.015, 0.950), mat=M["canvas"], bevel=0.005, bsegs=1, mirror=True)
    kit.done(p, "pelvis", K_CANVAS, Z_CORE, ALL, lr=True)


def back(kit, body, M):
    """The vertical core pack: slab, glowing ring, vents, two antenna blades, two nozzles."""
    yb = body.ray((0, -1.0, 1.30), (0, 1, 0))[0].y
    cy = yb - 0.052
    p = kit.new("pack")
    p.box((0.250, 0.090, 0.340), (0, cy, 1.285), mat=M["carbon"], bevel=0.007, bsegs=1)
    p.box((0.262, 0.030, 0.050), (0, cy - 0.004, 1.470), mat=M["plate"], bevel=0.005, bsegs=1)       # top cap
    p.box((0.262, 0.030, 0.040), (0, cy - 0.004, 1.115), mat=M["plate"], bevel=0.005, bsegs=1)       # bottom cap
    p.box((0.036, 0.012, 0.250), (0.085, cy - 0.050, 1.290), mat=M["steel"], bevel=0.003, bsegs=1, mirror=True)       # vent frames
    p.torus(0.052, 0.009, pos=(0, cy - 0.047, 1.305), rot=(90, 0, 0), mat=M["steel"], segs=20, sides=6)
    p.cyl(0.043, 0.010, pos=(0, cy - 0.046, 1.305), axis="y", mat=M["steel"], segs=20)
    # antenna blades
    p.bar((0.092, cy + 0.015, 1.455), (0.160, cy - 0.050, 1.625), 0.072, 0.017, mat=M["carbon"], up=(0, 1, 0), taper=(0.30, 1.0), bevel=0.002, mirror=True)          # swept fins
    p.bar((0.092, cy + 0.015, 1.455), (0.160, cy - 0.050, 1.625), 0.018, 0.022, mat=M["steel"], up=(0, 1, 0), taper=(0.5, 1.0), bevel=0.0015, mirror=True)
    # nozzles
    p.cyl(0.026, 0.060, pos=(0.075, cy - 0.01, 1.095), axis="z", mat=M["steel"], r2=0.021, segs=16, bevel=0.002, mirror=True)
    kit.done(p, "spine_02", K_DARK, Z_WINGS, ALL)
    g = kit.new("pack_glow")
    g.cyl(0.036, 0.004, pos=(0, cy - 0.054, 1.305), axis="y", mat=M["glow"], segs=20)
    g.box((0.010, 0.004, 0.220), (0.085, cy - 0.057, 1.290), mat=M["glow"], bevel=0.0, mirror=True)
    g.cyl(0.0225, 0.004, pos=(0.075, cy - 0.01, 1.062), axis="z", mat=M["glow"], segs=16, mirror=True)
    kit.done(g, "spine_02", K_GLOW, Z_WINGS, ALL)


def collar(kit, body, M):
    """A standing gorget that frames the head from behind (open at the front): an analytic ring around the neck, taller at the back, flaring up."""
    def zt(s, t):
        back = bump(lerp(R(40), R(320), s), R(180), R(120))
        return lerp(1.495, 1.585 + 0.075 * back, t)
    surf = ellipse_surf(0.0, -0.038, 0.090, 0.097, zt, 0, R(36), R(324), flare=lambda t: 0.024 * sm(0.25, 1.0, t))
    p = kit.new("collar")
    _raw(p, shf(4, 16, surf, 0.012, 0.0), M["plate"], bevel=0.003, bsegs=1, mirror=False)
    kit.done(p, "spine_02", K_ACCENT, Z_HEAD, ALL)
    g = kit.new("collar_glow")
    surf2 = ellipse_surf(0.0, -0.038, 0.090, 0.097, 1.545, 1.553, R(56), R(304), flare=lambda t: 0.006)
    _raw(g, shf(1, 18, surf2, 0.0155, 0.0125), M["glow"], bevel=0.0, mirror=False)
    kit.done(g, "spine_02", K_GLOW, Z_HEAD, ALL)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# shoulders and arms
# ------------------------------------------------------------------------------------------------------------------------------------------------

def shoulders(kit, body, M):
    """Pauldrons as spherical shells about the shoulder joint (they ride with the upper arm bone and keep clear of the skin in every arm pose), a skirt lame below the cap with a glowing
    rim, and a yoke on the torso over the trapezius."""
    j = Vector(body.bone["upperarm_r"])
    axis = Vector((0.45, -0.05, 1.0))

    def notch(th):                                                    # a notched rim: shorter at the front and back
        return 0.10 * (1.0 + math.cos(th * 2.0)) * 0.5
    p = kit.new("pauld_cap")
    surf = dome_surf(j, axis, 0.098, R(10), R(66), notch)
    _raw(p, shf(5, 12, surf, lambda s, t: 0.0 + 0.010 * bump(t, 0.2, 0.6), -0.010, True), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "upperarm_r", K_ACCENT, Z_ARMS, HEAVY + ",flight,stealth", lr=True)
    p = kit.new("pauld_lame")
    surf = dome_surf(j, axis, 0.112, R(60), R(92), None)
    _raw(p, shf(3, 12, surf, lambda s, t: 0.0, -0.010, True), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "upperarm_r", K_PLATE, Z_ARMS, HEAVY, lr=True)
    p = kit.new("pauld_glow")
    surf = dome_surf(j, axis, 0.1175, R(93), R(95), None)
    _raw(p, shf(1, 12, surf, 0.0, -0.004, True), M["glow"], bevel=0.0)
    kit.done(p, "upperarm_r", K_GLOW, Z_ARMS, HEAVY + ",flight,stealth", lr=True)
    # the yoke: a plate over the trapezius slope (rays from above, outside the neck / head column)
    p = kit.new("yoke")
    def fn(s, t):
        x = 0.105 + s * 0.095
        y = lerp(-0.125, 0.045 - (x - 0.105) * 0.95, t)
        return Vector((x, y, 1.9)), Vector((0, 0, -1))
    _raw(p, sh(body, 5, 4, fn, lambda s, t: 0.016 + 0.004 * bump(t, 0.5, 0.5), 0.006), M["plate"], bevel=0.0025, bsegs=1)
    kit.done(p, "spine_02", K_PLATE, Z_ARMS, HEAVY, lr=True)


def arms(kit, body, M):
    """Bicep band with a glow ring, forearm bracer with an armour plate, glow strip and the emitter ring, knuckle plates."""
    up = Limb(body, body.bone["upperarm_r"], body.bone["lowerarm_r"], 10, up=(0, 0, 1), fwd=(0, 1, 0), radius=0.1)
    p = kit.new("bicep")
    _raw(p, sh(body, 3, 18, up.span(0.50, 0.80, R(0), R(360)), lambda s, t: 0.016 + 0.004 * bump(t, 0.5, 0.5), 0.006, closed_s=True), M["carbon"], bevel=0.0025, bsegs=1)
    kit.done(p, "upperarm_r", K_DARK, Z_ARMS, ALL, lr=True)
    p = kit.new("bicep_glow")
    _raw(p, sh(body, 1, 18, up.span(0.645, 0.655, R(0), R(360)), 0.0215, 0.0165, closed_s=True), M["glow"], bevel=0.0)
    kit.done(p, "upperarm_r", K_GLOW, Z_ARMS, ALL, lr=True)

    fa = Limb(body, body.bone["lowerarm_r"], body.bone["hand_r"], 10, up=(0, 0, 1), fwd=(0, 1, 0), radius=0.08)
    p = kit.new("bracer")
    _raw(p, sh(body, 6, 18, fa.span(0.10, 0.92, R(0), R(360)), lambda s, t: 0.014 + 0.012 * sm(0.0, 0.25, 1 - t) + 0.004 * bump(t, 0.9, 0.12), 0.006, closed_s=True), M["carbon"], bevel=0.0025, bsegs=1)
    kit.done(p, "lowerarm_r", K_DARK, Z_ARMS, ALL, lr=True)
    p = kit.new("bracer_plate")
    _raw(p, sh(body, 6, 8, fa.span(0.16, 0.80, R(-62), R(62)), lambda s, t: 0.034 - 0.010 * sm(0.5, 1.0, t) + 0.004 * bump(s, 0.5, 0.4), 0.014), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "lowerarm_r", K_PLATE, Z_ARMS, HEAVY + ",stealth", lr=True)
    p = kit.new("bracer_glow")
    _raw(p, sh(body, 1, 18, fa.span(0.865, 0.88, R(0), R(360)), 0.0300, 0.0150, closed_s=True), M["glow"], bevel=0.0)       # the emitter ring at the wrist
    _raw(p, sh(body, 6, 1, fa.span(0.22, 0.78, R(-14), R(14)), 0.0345, 0.0335), M["glow"], bevel=0.0)
    kit.done(p, "lowerarm_r", K_GLOW, Z_HANDS, ALL, lr=True)

    h = Limb(body, body.bone["hand_r"], (0.82, -0.025, 1.448), 4, up=(0, 0, 1), fwd=(0, 1, 0), radius=0.06)
    p = kit.new("knuckle")
    _raw(p, sh(body, 4, 8, h.span(0.10, 0.80, R(-48), R(48)), 0.0115, 0.004), M["steel"], bevel=0.0015, bsegs=1)
    kit.done(p, "hand_r", K_DARK, Z_HANDS, ALL, lr=True)


# ------------------------------------------------------------------------------------------------------------------------------------------------
# legs
# ------------------------------------------------------------------------------------------------------------------------------------------------

def legs(kit, body, M):
    leg = Limb(body, body.bone["thigh_r"], body.bone["foot_r"], 30, up=(0, 1, 0), fwd=(1, 0, 0), radius=0.13)

    def tz(z):
        return (0.971 - z) / (0.971 - 0.086)

    p = kit.new("thigh")
    _raw(p, sh(body, 7, 10, leg.span(tz(0.90), tz(0.60), R(-24), R(104)), lambda s, t: 0.019 + 0.004 * bump(s, 0.45, 0.5) + 0.005 * sm(0.7, 1.0, t), 0.008), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "thigh_r", K_PLATE, Z_LEGS, HEAVY + ",stealth", lr=True)
    p = kit.new("thigh_glow")
    _raw(p, sh(body, 6, 1, leg.span(tz(0.88), tz(0.64), R(88), R(94)), 0.0245, 0.0195), M["glow"], bevel=0.0)
    kit.done(p, "thigh_r", K_GLOW, Z_LEGS, ALL, lr=True)

    p = kit.new("knee")
    _raw(p, sh(body, 6, 10, leg.span(tz(0.625), tz(0.455), R(-52), R(70)), lambda s, t: 0.026 + 0.010 * bump(s, 0.42, 0.45) * bump(t, 0.45, 0.6), 0.010), M["plate"], bevel=0.0035, bsegs=1)
    kit.done(p, "calf_r", K_ACCENT, Z_LEGS, ALL, lr=True)

    p = kit.new("shin")
    _raw(p, sh(body, 8, 10, leg.span(tz(0.46), tz(0.17), R(-48), R(96)), lambda s, t: 0.020 + 0.006 * bump(s, 0.33, 0.3) - 0.005 * t, 0.008), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "calf_r", K_PLATE, Z_LEGS, ALL, lr=True)
    p = kit.new("shin_glow")
    _raw(p, sh(body, 6, 1, leg.span(tz(0.43), tz(0.22), R(60), R(64)), 0.027, 0.021), M["glow"], bevel=0.0)
    kit.done(p, "calf_r", K_GLOW, Z_LEGS, ALL, lr=True)


def boots(kit, body, M):
    """Analytic ankle boots (the bare foot of the base mesh is cut away under them): a lofted upper with a heel counter and a toe taper, a rubber sole with a wider rim, a toe cap,
    and the shaft: a conformal ring around the lower shin that hides the join."""
    cx = 0.114
    # y, half width, z bottom, z top
    st = [(-0.160, 0.030, 0.034, 0.100), (-0.148, 0.047, 0.030, 0.126), (-0.105, 0.060, 0.030, 0.190), (-0.045, 0.063, 0.030, 0.158), (0.030, 0.064, 0.030, 0.118),
          (0.110, 0.070, 0.030, 0.094), (0.175, 0.063, 0.032, 0.076), (0.215, 0.046, 0.034, 0.060), (0.238, 0.022, 0.037, 0.046)]
    rings = [ring_se(cx, y, (zb + zt) / 2, hw, (zt - zb) / 2, n=12, exp=3.0, plane="xz") for (y, hw, zb, zt) in st]
    p = kit.new("boot")
    p.loft(rings, mat=M["boot"], caps=(True, True), mirror=True, bevel=0.0015, bsegs=1)
    kit.done(p, "foot_r", K_FABRIC, Z_LEGS, ALL, lr=True)
    sole = [ring_se(cx, y, 0.018, hw + 0.007, 0.018, n=10, exp=3.0, plane="xz") for (y, hw, zb, zt) in st]
    p = kit.new("sole")
    p.loft(sole, mat=M["rubber"], caps=(True, True), mirror=True)
    kit.done(p, "foot_r", K_FABRIC, Z_LEGS, ALL, lr=True)
    tc = [ring_se(cx, y, (zb + zt) / 2 + 0.006, hw + 0.006, (zt - zb) / 2 + 0.006, n=12, exp=3.0, plane="xz") for (y, hw, zb, zt) in st[5:]]
    p = kit.new("toecap")
    p.loft(tc, mat=M["plate"], caps=(True, True), mirror=True, bevel=0.0015, bsegs=1)
    kit.done(p, "foot_r", K_PLATE, Z_LEGS, HEAVY + ",stealth", lr=True)

    p = kit.new("boot_shaft")
    leg = Limb(body, (0.114, -0.04, 0.30), (0.114, -0.075, 0.085), 8, up=(0, 1, 0), fwd=(1, 0, 0), radius=0.1)
    _raw(p, sh(body, 5, 18, leg.span(0.0, 1.0, R(0), R(360)), lambda s, t: 0.014 + 0.008 * sm(0.6, 1.0, t), 0.006, closed_s=True), M["carbon"], bevel=0.0025, bsegs=1)
    kit.done(p, "foot_r", K_DARK, Z_LEGS, ALL, lr=True)


def legs_rear(kit, body, M):
    """Rear calf plates and a hamstring panel: the back of the legs is what the camera sees most."""
    leg = Limb(body, body.bone["thigh_r"], body.bone["foot_r"], 30, up=(0, 1, 0), fwd=(1, 0, 0), radius=0.13)

    def tz(z):
        return (0.971 - z) / (0.971 - 0.086)

    p = kit.new("calf_rear")
    _raw(p, sh(body, 7, 8, leg.span(tz(0.50), tz(0.20), R(138), R(222)), lambda s, t: 0.018 + 0.007 * bump(s, 0.5, 0.5) * bump(t, 0.4, 0.6), 0.008), M["plate"], bevel=0.003, bsegs=1)
    kit.done(p, "calf_r", K_PLATE, Z_LEGS, ALL, lr=True)
    p = kit.new("calf_rear_glow")
    _raw(p, sh(body, 6, 1, leg.span(tz(0.47), tz(0.24), R(178), R(182)), 0.0275, 0.0225), M["glow"], bevel=0.0)
    kit.done(p, "calf_r", K_GLOW, Z_LEGS, ALL, lr=True)
    p = kit.new("ham_rear")
    _raw(p, sh(body, 6, 8, leg.span(tz(0.88), tz(0.62), R(140), R(225)), lambda s, t: 0.016 + 0.005 * bump(s, 0.5, 0.5), 0.007), M["plate"], bevel=0.0028, bsegs=1)
    kit.done(p, "thigh_r", K_ACCENT, Z_LEGS, HEAVY, lr=True)


def assault_extras(kit, body, M):
    """ASSAULT: a third shoulder lame, big outer thigh guards, a row of magazine pouches on the chest."""
    arm = Limb(body, body.bone["upperarm_r"], body.bone["lowerarm_r"], 10, up=(0, 0, 1), fwd=(0, 1, 0), radius=0.1)
    p = kit.new("pauld_over")
    surf = dome_surf(Vector(body.bone["upperarm_r"]), Vector((0.45, -0.05, 1.0)), 0.128, R(8), R(78), lambda th: 0.12 * (1.0 + math.cos(th * 3.0)) * 0.5)
    _raw(p, shf(5, 12, surf, lambda s, t: 0.010 * bump(t, 0.3, 0.7), -0.012, True), M["plate"], bevel=0.0035, bsegs=1)
    kit.done(p, "upperarm_r", K_ACCENT, Z_ARMS, "assault", lr=True)
    leg = Limb(body, body.bone["thigh_r"], body.bone["foot_r"], 30, up=(0, 1, 0), fwd=(1, 0, 0), radius=0.13)

    def tz(z):
        return (0.971 - z) / (0.971 - 0.086)

    p = kit.new("thigh_guard")
    _raw(p, sh(body, 6, 8, leg.span(tz(0.86), tz(0.56), R(60), R(124)), lambda s, t: 0.034 + 0.008 * bump(s, 0.5, 0.5), 0.012), M["plate"], bevel=0.0035, bsegs=1)
    kit.done(p, "thigh_r", K_ACCENT, Z_LEGS, "assault", lr=True)
    yz = body.ray((0, 1.0, 1.16), (0, -1, 0))[0].y
    p = kit.new("chest_pouches")
    for x in (-0.085, 0.0, 0.085):
        p.box((0.058, 0.032, 0.080), (x, yz + 0.026, 1.215), mat=M["canvas"], bevel=0.006, bsegs=1)
        p.box((0.060, 0.034, 0.014), (x, yz + 0.030, 1.250), mat=M["steel"], bevel=0.003, bsegs=1)
    kit.done(p, "spine_02", K_CANVAS, Z_CORE, "assault")


def flight_extras(kit, body, M):
    """FLIGHT: wing mounts on the back (two sockets with glowing strips) and two folded wing blades that lie along the back; the SNAKE FLIGHT wave unfolds or replaces them
    (HeroSuit.hardpoint(&"wing_l" / &"wing_r") is the socket)."""
    yb = body.ray((0, -1.0, 1.30), (0, 1, 0))[0].y
    cy = yb - 0.052
    p = kit.new("wing_mount")
    p.box((0.060, 0.060, 0.120), (0.150, cy - 0.005, 1.395), mat=M["steel"], bevel=0.004, bsegs=1, mirror=True)
    p.cyl(0.026, 0.050, pos=(0.165, cy - 0.020, 1.395), axis="y", mat=M["plate"], segs=14, bevel=0.0025, mirror=True)
    kit.done(p, "spine_02", K_DARK, Z_WINGS, "flight")
    p = kit.new("wing_blade")
    p.bar((0.175, cy - 0.04, 1.43), (0.30, cy - 0.15, 0.82), 0.075, 0.014, mat=M["plate"], up=(0, 1, 0), taper=(0.25, 1.0), bevel=0.002, mirror=True)
    p.bar((0.175, cy - 0.04, 1.43), (0.30, cy - 0.15, 0.82), 0.022, 0.020, mat=M["steel"], up=(0, 1, 0), taper=(0.4, 1.0), bevel=0.0015, mirror=True)
    kit.done(p, "spine_02", K_ACCENT, Z_WINGS, "flight")
    g = kit.new("wing_glow")
    g.cyl(0.018, 0.052, pos=(0.165, cy - 0.021, 1.395), axis="y", mat=M["glow"], segs=14, mirror=True)
    g.bar((0.185, cy - 0.048, 1.38), (0.287, cy - 0.140, 0.90), 0.010, 0.006, mat=M["glow"], up=(0, 1, 0), mirror=True)
    kit.done(g, "spine_02", K_GLOW, Z_WINGS, "flight")


def cape(kit, body, M):
    """A half cape over the LEFT shoulder (asymmetry reads from behind and in motion): a cloth sheet that hangs behind the left arm, skinned along the Sec1-3 chain (the rig's cloak springs
    swing it back with speed and sway it when turning). The chain pivots are exported in the part's extras in MODEL space (x right, y up, z back)."""
    chain = [(-0.185, -0.115, 1.475), (-0.215, -0.185, 1.175), (-0.240, -0.235, 0.870)]        # Blender coords
    top, bot = 1.505, 0.800

    def pt(s, t):
        z = lerp(top, bot, t)
        x0 = lerp(-0.125, -0.085, t) - 0.0
        x1 = lerp(-0.330, -0.420, t * t * 0.6 + t * 0.4)
        x = lerp(x0, x1, s)
        r = body.ray(Vector((x, -1.0, z)), Vector((0, 1, 0)), 1.5)
        yb = r[0].y if r else -0.13
        y = yb - (0.030 + 0.075 * t + 0.045 * math.sin(s * math.pi) * t)
        return Vector((x, y, z))

    p = kit.new("cape")
    v, f = sheet(7, 5, pt, (0, -1, 0))
    p.raw(v, f, M["cloak"], closed=False, bevel=0.0, mirror=False)
    kit.done(p, "chain:Sec1,Sec2,Sec3", K_CLOTH, Z_ARMS, HEAVY)
    kit.parts[-1].props["chain_pos"] = ";".join("%.4f,%.4f,%.4f" % (x, z, -y) for (x, y, z) in chain)      # model space
    kit.parts[-1].props["chain_parent"] = "spine_02"
    g = kit.new("cape_hem")
    def hem(s, t):
        q = pt(s, 1.0)
        return Vector((q.x, q.y - 0.001 * (1 - t), q.z + 0.012 * (1 - t)))
    v, f = sheet(1, 5, hem, (0, -1, 0))
    g.raw(v, f, M["glow"], closed=False, bevel=0.0, mirror=False)
    kit.done(g, "chain:Sec1,Sec2,Sec3", K_GLOW, Z_ARMS, HEAVY)
    kit.parts[-1].props["chain_pos"] = kit.parts[-2].props["chain_pos"]
    kit.parts[-1].props["chain_parent"] = "spine_02"


def build(kit, body):
    M = materials(kit)
    chest(kit, body, M)
    abdomen(kit, body, M)
    back(kit, body, M)
    collar(kit, body, M)
    shoulders(kit, body, M)
    arms(kit, body, M)
    legs(kit, body, M)
    boots(kit, body, M)
    legs_rear(kit, body, M)
    assault_extras(kit, body, M)
    flight_extras(kit, body, M)
    cape(kit, body, M)
    return M
