"""Recipes of the energy, quantum, exotic, launcher, rotary, flamer and bow weapons of the weapon kit (wave 114). Same conventions as wguns.py (muzzle at d = 0, distances behind it, z = 0 the bore axis)."""
import math

import numpy as np

import weaponlib as wl
import weapon_mats as M
from weaponlib import Style
import wparts as wp
from wparts import rbox, tube, lathe_d, side_w, side, screw, seam, serrate, vent_row, rail, grip_texture, muzzle_device, optic, stock, pistol_grip, trigger_group, magazine, underbarrel
import wguns as wg


def ring_d(g, d, r, rt, st, z=0.0, x=0.0, n=14, m=6):
    """A torus ring around the barrel axis at distance d: ring radius r, tube radius rt."""
    g.torus((x, -d, z), r, rt, st, n=n, m=m, axis="y")


# ---------------------------------------------------------------------------------------------------------------------------------------- emitters
def emitter(g, kind, pal, r=0.02, d0=0.0, z=0.0):
    """The business end of an energy weapon, in front of d0 (returns how far it reaches in front of the muzzle point)."""
    m = pal["metal"]
    dk = pal["dark"]
    gl = pal["glow"]
    cl = pal["coil"]
    bd = pal["body"]
    if kind == "ring":
        L = 0.05
        tube(g, d0 - L, d0, r * 0.95, bd, z=z, n=16, ch=0.002)
        ring_d(g, d0 - L, r * 1.0, 0.0035, gl, z=z)
        ring_d(g, d0 - L * 0.5, r * 1.04, 0.0025, dk, z=z)
        lathe_d(g, [(d0 - L - 0.012, r * 0.55), (d0 - L, r * 0.8), (d0 - L, r * 0.6)], dk, z=z, n=14)
        tube(g, d0 - L - 0.004, d0 - L + 0.012, r * 0.5, gl, z=z, n=12)
        return L + 0.012
    if kind == "fork":                                   # two prongs with a glowing gap
        L = 0.11
        for sx in (-1.0, 1.0):
            g.box((sx * r * 0.85, -(d0 - L * 0.5), z), (r * 0.5, L, r * 1.4), m, r=0.004, chamfer=0.004)
            g.box((sx * r * 0.58, -(d0 - L * 0.6), z), (0.002, L * 0.7, r * 0.9), gl)
        rbox(g, d0, d0 + 0.0, z - r * 0.6, z + r * 0.6, r * 1.2, dk, r=0.002)
        g.box((0, -(d0 - L * 0.1), z), (r * 1.4, 0.014, r * 0.9), bd, r=0.003, chamfer=0.003)
        return L
    if kind == "claw":                                   # three curved claws around a core
        L = 0.1
        for k in range(3):
            a = 2 * math.pi * k / 3 + math.pi / 2
            p0 = (math.cos(a) * r * 1.1, -(d0 - 0.002), z + math.sin(a) * r * 1.1)
            p1 = (math.cos(a) * r * 0.7, -(d0 - L), z + math.sin(a) * r * 0.7)
            g.cyl(p0, p1, 0.0055, m, r1=0.0025, n=8)
        g.sphere((0, -(d0 - L * 0.55), z), r * 0.5, gl, n=10)
        tube(g, d0 - 0.014, d0, r * 1.2, bd, z=z, n=14)
        return L
    if kind == "lens":                                   # a stack of focusing rings
        L = 0.085
        for k in range(4):
            dd = d0 - k * L / 4.0
            tube(g, dd - 0.012, dd, r * (1.25 - 0.1 * k), bd if k % 2 == 0 else dk, z=z, n=16, ch=0.001)
            ring_d(g, dd - 0.012, r * (1.25 - 0.1 * k), 0.0025, gl, z=z)
        tube(g, d0 - L - 0.004, d0 - L + 0.002, r * 0.8, pal["lens_glow"], z=z, n=14)
        return L + 0.004
    if kind == "dish":                                   # an emitter dish
        L = 0.06
        lathe_d(g, [(d0 - L, r * 2.1), (d0 - L + 0.004, r * 2.1), (d0 - L * 0.5, r * 1.0), (d0, r * 0.7)], bd, z=z, n=18, hard=(0,))
        lathe_d(g, [(d0 - L + 0.006, r * 1.9), (d0 - L * 0.5, r * 0.9)], gl, z=z, n=18, caps=(False, False))
        g.sphere((0, -(d0 - L * 0.55), z), r * 0.35, gl, n=8)
        return L
    if kind == "prism":                                  # a crystal prism
        L = 0.09
        lathe_d(g, [(d0 - L, 0.002), (d0 - L * 0.78, r * 0.95), (d0 - L * 0.2, r * 0.95), (d0, 0.004)], gl, z=z, n=6, hard=(1, 2))
        tube(g, d0 - 0.008, d0 + 0.006, r * 1.1, dk, z=z, n=6)
        return L
    if kind == "needle":                                 # a long glowing needle in a sleeve
        L = 0.13
        g.cyl((0, -d0, z), (0, -(d0 - L), z), 0.004, gl, r1=0.0015, n=8)
        tube(g, d0 - 0.03, d0, r * 0.9, bd, z=z, n=12)
        return L
    if kind == "bell":                                   # a flared bell (sonic)
        L = 0.1
        lathe_d(g, [(d0 - L, r * 2.3), (d0 - L * 0.7, r * 1.6), (d0 - L * 0.25, r * 0.95), (d0, r * 0.8)], bd, z=z, n=18)
        lathe_d(g, [(d0 - L + 0.002, r * 2.1), (d0 - L * 0.7, r * 1.4)], gl, z=z, n=18, caps=(False, False))
        for k in range(3):
            ring_d(g, d0 - L * (0.3 + 0.22 * k), r * (1.1 + 0.4 * k) + 0.002, 0.002, dk, z=z)
        return L
    if kind == "coilstack":                              # a tesla coil stack
        L = 0.12
        for k in range(5):
            dd = d0 - k * L / 5.0
            ring_d(g, dd, r * (0.7 + 0.12 * k), 0.0045, cl, z=z, m=6)
        tube(g, d0 - L, d0, r * 0.35, dk, z=z, n=10)
        g.sphere((0, -(d0 - L - 0.008), z), r * 0.55, gl, n=10)
        return L + 0.02
    if kind == "funnel":                                 # a collapse funnel
        L = 0.11
        lathe_d(g, [(d0 - L, r * 2.2), (d0 - L * 0.55, r * 1.0), (d0, r * 0.7)], dk, z=z, n=18)
        lathe_d(g, [(d0 - L + 0.002, r * 2.0), (d0 - L * 0.55, r * 0.9)], pal["lens_glow"], z=z, n=18, caps=(False, False))
        g.sphere((0, -(d0 - L * 0.6), z), r * 0.5, gl, n=10)
        return L
    if kind == "plate":                                  # a kinetic repulsor plate
        L = 0.04
        lathe_d(g, [(d0 - L, r * 2.2), (d0 - L + 0.006, r * 2.2), (d0 - L + 0.006, r * 1.5), (d0, r * 0.8)], bd, z=z, n=18, hard=(0, 1))
        tube(g, d0 - L - 0.003, d0 - L + 0.0005, r * 1.7, gl, z=z, n=18)
        return L
    if kind == "twin":                                   # twin emitters (superposition)
        L = 0.08
        for sx in (-1.0, 1.0):
            tube(g, d0 - L, d0, r * 0.55, bd, x=sx * r * 0.7, z=z, n=12, ch=0.002)
            tube(g, d0 - L - 0.002, d0 - L + 0.003, r * 0.38, gl, x=sx * r * 0.7, z=z, n=10)
        return L
    return 0.0


# ---------------------------------------------------------------------------------------------------------------------------------------- core modules
def core_module(g, kind, d, z, pal, len_=0.12, w=0.05, h=0.065):
    """A housing with a window and a glowing core, centred at distance d, bottom of the window z. Both sides show the core."""
    gl = pal["glow"]
    dk = pal["dark"]
    bd = pal["body"]
    cl = pal["coil"]
    zc = z + h / 2
    rbox(g, d - len_ / 2, d + len_ / 2, z, z + h, w, bd, r=0.009, ch=0.004, seg=2)
    if kind == "cell":
        g.box((w / 2 + 0.0006, -d, zc), (0.0016, len_ * 0.82, h * 0.58), dk)                                    # window recess (dark glass)
        g.box((-w / 2 - 0.0006, -d, zc), (0.0016, len_ * 0.82, h * 0.58), dk)
        g.cyl((0, -(d - len_ * 0.4), zc), (0, -(d + len_ * 0.4), zc), h * 0.2, gl, n=12, chamfer=0.003)         # the glowing cell, seen through a slot on the top as well
        g.box((0, -d, z + h + 0.0008), (w * 0.35, len_ * 0.7, 0.0018), gl)
        g.box((w / 2 + 0.0012, -d, zc), (0.0008, len_ * 0.76, h * 0.34), gl)
        g.box((-w / 2 - 0.0012, -d, zc), (0.0008, len_ * 0.76, h * 0.34), gl)
    elif kind == "vial":
        for sx in (-1.0, 1.0):
            g.box((sx * (w / 2 + 0.0005), -d, zc), (0.0016, len_ * 0.5, h * 0.7), dk)
        g.cyl((0, -d, z + h * 0.1), (0, -d, z + h * 0.95), len_ * 0.22, gl, n=10, chamfer=0.003)
        g.box((w / 2 + 0.0012, -d, zc), (0.0008, len_ * 0.22, h * 0.6), gl)
        g.box((-w / 2 - 0.0012, -d, zc), (0.0008, len_ * 0.22, h * 0.6), gl)
    elif kind == "orb":
        g.sphere((0, -d, zc), min(h, len_) * 0.4, gl, n=12)
        for sx in (-1.0, 1.0):
            g.box((sx * (w / 2 + 0.0005), -d, zc), (0.0016, len_ * 0.6, h * 0.62), dk)
        ring_d(g, d, min(h, len_) * 0.46, 0.0028, dk, z=zc)
    elif kind == "crystal":
        g.lathe([(-(d - len_ * 0.4), 0.002), (-(d - len_ * 0.28), h * 0.26), (-(d + len_ * 0.28), h * 0.26), (-(d + len_ * 0.4), 0.002)], gl, n=6, cx=0.0, cz=zc, hard=(1, 2))
        for sx in (-1.0, 1.0):
            g.box((sx * (w / 2 + 0.0005), -d, zc), (0.0016, len_ * 0.8, h * 0.5), dk)
    elif kind == "coil":
        for k in range(5):
            dd = d - len_ * 0.4 + k * len_ * 0.2
            ring_d(g, dd, h * 0.26, 0.0045, cl, z=zc, m=6)
        tube(g, d - len_ * 0.45, d + len_ * 0.45, h * 0.12, dk, z=zc, n=8)
    return zc


# ---------------------------------------------------------------------------------------------------------------------------------------- the energy gun
def fuselage(g, secs, st, caps=(True, True), ch=(0.004, 0.004), seg=2):
    """A lofted shell from rounded-rectangle sections: secs = [(d, width, height, z centre, corner radius), ...] from front to rear (smooth, organic bodies for the energy weapons)."""
    S = []
    for (d, w, h, zc, r) in secs:
        P, N, K = wl.outline_rrect(max(w, 0.004), max(h, 0.004), r, seg)
        S.append(wl.Sec(P, N, K, np.array([0.0, -d, zc]), wl.X_AX, wl.Z_AX))
    g.loft(S, st, caps=caps, chamfer=ch)


SHELLS = {
    # profile: sections as fractions along the body (t), width, height, z centre, radius (multiplied by the body width / height later)
    "wedge": [(0.0, 0.8, 0.6, 0.004, 0.012), (0.35, 1.0, 0.85, 0.010, 0.014), (0.75, 1.0, 1.0, 0.012, 0.014), (1.0, 0.85, 0.95, 0.008, 0.012)],
    "wing": [(0.0, 0.7, 0.6, 0.0, 0.012), (0.3, 1.25, 0.7, 0.004, 0.012), (0.7, 1.35, 0.8, 0.008, 0.014), (1.0, 0.9, 0.75, 0.006, 0.012)],
    "hump": [(0.0, 0.75, 0.55, 0.0, 0.012), (0.3, 1.0, 1.0, 0.012, 0.016), (0.65, 1.0, 1.05, 0.016, 0.016), (1.0, 0.8, 0.7, 0.004, 0.012)],
    "sleek": [(0.0, 0.6, 0.5, 0.0, 0.012), (0.4, 0.85, 0.72, 0.006, 0.014), (0.8, 0.85, 0.8, 0.008, 0.014), (1.0, 0.7, 0.7, 0.004, 0.012)],
    "slab": [(0.0, 0.9, 0.9, 0.006, 0.008), (0.5, 1.0, 1.0, 0.008, 0.008), (1.0, 0.95, 1.0, 0.006, 0.008)],
}


def energy_gun(g, pal, s):
    """s: size ('pistol','smg','carbine','rifle','cannon'), emitter, front ('rails','tube','fins','spine','coils','lens','none'), front_len, body_len, body_h, body_w, core, profile, stock, optic, grip, extras."""
    size = s.get("size", "rifle")
    bd, dk, mt, gl, cl, fr, ac = pal["body"], pal["dark"], pal["metal"], pal["glow"], pal["coil"], pal["frame"], pal["accent"]
    ex = set(s.get("extras", []))
    pistol_like = size == "pistol"
    r_em = s.get("emitter_r", 0.016 if size in ("pistol", "smg") else 0.021 if size != "cannon" else 0.03)
    reach_e = emitter(g, s.get("emitter", "ring"), pal, r=r_em, d0=0.0)
    front_len = s.get("front_len", {"pistol": 0.07, "smg": 0.14, "carbine": 0.2, "rifle": 0.3, "cannon": 0.34}[size])
    body_len = s.get("body_len", {"pistol": 0.13, "smg": 0.2, "carbine": 0.26, "rifle": 0.32, "cannon": 0.36}[size])
    bw = s.get("body_w", {"pistol": 0.042, "smg": 0.05, "carbine": 0.054, "rifle": 0.058, "cannon": 0.07}[size])
    bh = s.get("body_h", {"pistol": 0.07, "smg": 0.07, "carbine": 0.072, "rifle": 0.078, "cannon": 0.09}[size])
    front = s.get("front", "rails")
    d_b0 = front_len
    d_b1 = d_b0 + body_len
    # ---- front assembly: a core barrel, a collar at the emitter and the module on it (every piece touches the next)
    tube(g, 0.0, front_len + 0.02, r_em * 0.62, dk, n=14)
    tube(g, 0.0, 0.016, r_em * 1.12, mt, n=16, ch=0.002)
    if front == "rails":
        for sx in (-1.0, 1.0):
            g.cyl((sx * r_em * 0.95, -0.01, 0.0), (sx * r_em * 0.95, -(front_len + 0.02), 0.0), 0.0058, mt, n=8, chamfer=0.001)
        g.cyl((0, -0.01, 0.0), (0, -front_len, 0.0), 0.0085, gl, n=10)
        for k in range(max(2, int(front_len / 0.06))):
            dd = 0.03 + k * 0.06
            if dd > front_len - 0.015:
                break
            rbox(g, dd, dd + 0.012, -r_em * 1.5, r_em * 1.5, r_em * 2.6, bd, r=0.004, ch=0.002)
    elif front == "tube":
        tube(g, 0.012, front_len + 0.01, r_em * 0.95, bd, n=16, ch=0.003)
        for k in range(max(2, int(front_len / 0.034))):
            dd = 0.02 + k * 0.034
            if dd > front_len - 0.005:
                break
            ring_d(g, dd, r_em * 0.98, 0.0032, cl, n=16)
    elif front == "fins":
        for k in range(max(3, int(front_len / 0.018))):
            dd = 0.02 + k * 0.018
            if dd > front_len:
                break
            rbox(g, dd, dd + 0.0045, -0.034, 0.034, 0.05 - 0.0015 * k, dk if k % 3 else bd, r=0.002, ch=0.001)
        g.box((0, -(front_len * 0.55), 0.0), (0.006, front_len * 0.8, 0.07), gl)
    elif front == "spine":
        fuselage(g, [(0.01, r_em * 1.6, r_em * 1.3, 0.0, 0.006), (front_len * 0.5, r_em * 2.0, r_em * 1.6, 0.004, 0.008), (front_len, r_em * 2.4, r_em * 2.0, 0.006, 0.01)], bd)
        side_w(g, [(front_len * 0.15, r_em * 0.7), (front_len * 0.5, r_em * 2.4), (front_len * 0.95, r_em * 2.0), (front_len, r_em * 0.7)], 0.01, ac, ch=0.002)
        g.box((0.0, -(front_len * 0.5), r_em * 1.0 + 0.003), (0.006, front_len * 0.7, 0.002), gl)
    elif front == "coils":
        for k in range(max(2, int(front_len / 0.042))):
            dd = 0.026 + k * 0.042
            if dd > front_len:
                break
            ring_d(g, dd, r_em * (1.12 - 0.04 * (k % 2)), 0.0048, cl, n=16, m=6)
        for sx in (-1.0, 1.0):
            g.cyl((sx * r_em * 0.9, -0.02, 0.0), (sx * r_em * 0.9, -(front_len - 0.01), 0.0), 0.004, dk, n=6)
    elif front == "lens":
        for k in range(max(2, int(front_len / 0.055))):
            dd = 0.022 + k * 0.055
            if dd > front_len:
                break
            tube(g, dd, dd + 0.016, r_em * 1.25, bd, n=16, ch=0.002)
            tube(g, dd - 0.0005, dd + 0.0005, r_em * 1.0, pal["lens_glow"], n=16)
    # ---- the shell
    prof = SHELLS.get(s.get("profile", "wedge"), SHELLS["wedge"])
    secs = [(d_b0 + t * body_len, w * bw, h * bh, zc * (bh / 0.07), r) for (t, w, h, zc, r) in prof]
    fuselage(g, secs, bd, ch=(0.003, 0.003))
    # a collar where the barrel meets the shell
    rbox(g, d_b0 - 0.012, d_b0 + 0.006, -bh * 0.38, bh * 0.38, bw * 0.55, dk, r=0.004, ch=0.002)
    # accent panels (painted) on both sides, panel seams, the glow channel on the spine
    for sx in (-1.0, 1.0):
        side = sx * (bw * 0.5 + 0.0004)
        g.box((side, -(d_b0 + body_len * 0.28), bh * 0.18), (0.0012, body_len * 0.34, bh * 0.28), ac)
        g.box((side, -(d_b0 + body_len * 0.74), bh * 0.12), (0.0012, body_len * 0.22, bh * 0.4), ac)
        wp.seam(g, d_b0 + body_len * 0.1, d_b0 + body_len * 0.92, bh * 0.0, bh * 0.0 + 0.002, sx * bw * 0.5, dk)
        wp.screw(g, (sx * bw * 0.5, -(d_b0 + body_len * 0.45), bh * 0.3), pal["bright"], axis="x")
    zt = bh * 0.52
    g.box((0.0, -(d_b0 + body_len * 0.5), zt + 0.0006), (0.008, body_len * 0.55, 0.0018), gl)
    # the core in its window
    core_module(g, s.get("core", "cell"), d_b0 + body_len * 0.5, -bh * 0.32, pal, len_=min(0.15, body_len * 0.62), w=bw * 1.02, h=bh * 0.62)
    if s.get("vents", True):
        vent_row(g, d_b0 + body_len * 0.08, d_b0 + body_len * 0.26, bh * 0.28, bw / 2 + 0.0004, dk, n=4, h=0.016, w=0.005)
    # ---- grip and trigger
    gd = d_b1 - (0.075 if not pistol_like else 0.05)
    gz = -bh * 0.5 + 0.004
    gpos = pistol_grip(g, s.get("grip", "std"), gd, gz, pal, w=0.034 if not pistol_like else 0.032, h=0.1 if pistol_like else 0.095, rake=0.28)
    trigger_group(g, gd, gz, pal, guard_len=0.06 if not pistol_like else 0.05, guard_drop=0.034)
    # ---- stock
    butt = d_b1
    st_kind = s.get("stock", "none" if size in ("pistol", "smg") else "fixed")
    if st_kind != "none":
        butt = stock(g, st_kind, d_b1 - 0.006, pal, top=bh * 0.44, drop=-bh * 0.42, w=0.036, length=s.get("stock_len", 0.24 if size in ("rifle", "cannon") else 0.2))
    else:
        rbox(g, d_b1 - 0.004, d_b1 + 0.016, -bh * 0.4, bh * 0.4, bw * 0.8, dk, r=0.005, ch=0.003)
        butt = d_b1 + 0.016
    # ---- optic, foregrip, extras
    o = s.get("optic", "iron")
    lens = None
    top = bh * 0.55 + 0.004
    if o not in ("iron", "none", None):
        rail(g, d_b0 + 0.04, d_b1 - 0.03, top, dk, w=0.02, h=0.006, pitch=0.014)
        lens = optic(g, o, d_b0 + body_len * 0.5, top, pal)
    elif o == "iron":
        g.box((0, -(d_b0 + 0.03), top + 0.008), (0.004, 0.014, 0.016), gl)
        g.box((0, -(d_b1 - 0.04), top + 0.006), (0.014, 0.008, 0.012), dk)
    gl_pos = (0.0, -(front_len * 0.55 + 0.03), -0.03 if not pistol_like else -0.02)
    if "vgrip" in ex or "foregrip" in ex:
        underbarrel(g, "vgrip", front_len * 0.6 + 0.02, -r_em * 0.6, pal)
        gl_pos = (0.0, -(front_len * 0.6 + 0.02), -0.065)
    if "ghost" in ex:
        for sx in (0.032, -0.032):
            g.cyl((sx, -0.0, 0.018), (sx, -(front_len + 0.06), 0.018), 0.0065, pal["lens_glow"], n=8)
    if "link" in ex:
        for sx in (-1.0, 1.0):
            g.cyl((sx * 0.034, 0.0, 0.012), (sx * 0.034, -0.07, 0.02), 0.0042, gl, n=8)
        g.cyl((-0.034, 0.0, 0.012), (0.034, 0.0, 0.012), 0.0022, gl, n=6)
    if "cheek" in ex:
        rbox(g, d_b1, d_b1 + 0.1, bh * 0.4, bh * 0.4 + 0.016, 0.036, pal["rub"], r=0.005)
    if "antenna" in ex:
        g.cyl((0.02, -(d_b0 + 0.04), top), (0.026, -(d_b0 + 0.02), top + 0.1), 0.0025, dk, n=6)
        g.sphere((0.026, -(d_b0 + 0.02), top + 0.104), 0.006, gl, n=6)
    if "heatsink" in ex:
        for k in range(7):
            rbox(g, d_b0 + 0.02 + k * 0.013, d_b0 + 0.0255 + k * 0.013, top - 0.004, top + 0.028, 0.046, dk, r=0.001, ch=0.001)
    if s.get("cable", True) and not pistol_like:                       # a power cable from the stock to the front, along the side
        path = [(bw * 0.52, -(d_b1 - 0.02), -bh * 0.1), (bw * 0.6, -(d_b1 - 0.1), -bh * 0.18), (bw * 0.6, -(d_b0 + 0.02), -bh * 0.2), (r_em * 1.3, -(d_b0 - 0.02), -bh * 0.1)]
        g.sweep(path, lambda t: wl.outline_circle(0.0042, 6), dk, up=(0, 0, 1))
    g.mark("gr", (0.0, -(gpos[0]), gpos[1]))
    g.mark("gl", gl_pos)
    g.mark("eject", (0.0, -(d_b0 + body_len * 0.4), bh * 0.3))
    g.mark("mag", (0.0, -(d_b0 + body_len * 0.5), -bh * 0.3))
    g.mark("aim", (0.0, -(d_b0 + body_len * 0.5), top + 0.03))
    g.mark("optic", lens["lens"] if lens else (0.0, -(d_b1 - 0.03), top + 0.01))
    g.mark("laser", (0.0, -0.02, -0.01))
    return {"length": butt + reach_e, "butt": butt, "grip_d": gpos[0], "muz_ext": reach_e}


# ---------------------------------------------------------------------------------------------------------------------------------------- shoulder launchers
def launcher(g, pal, s):
    """Tube launchers. s: tube_len, tube_r, kind ('rocket','guided','wire','aa','bunker','cluster','recoilless','mortar','plasma','thermo','swarm','pump','revolver','rotary'), warhead, sight, flare."""
    kind = s.get("kind", "rocket")
    bd = pal["body"]
    dk = pal["dark"]
    mt = pal["metal"]
    fr = pal["frame"]
    gl = pal["glow"]
    ac = pal["accent"]
    hz = pal["hazard"]
    tl = s.get("tube_len", 0.9)
    tr = s.get("tube_r", 0.05)
    out = {}
    d_front = s.get("front", 0.06)
    if kind in ("pump", "revolver", "rotary"):
        return _grenade_launcher(g, pal, s)
    if kind == "swarm":
        return _pod_launcher(g, pal, s)
    # --- tube
    tube_mat = bd
    if kind == "recoilless":
        prof = [(d_front, tr * 0.8), (d_front + 0.02, tr * 1.02), (d_front + tl * 0.7, tr * 1.02), (d_front + tl * 0.86, tr * 1.3), (d_front + tl, tr * 1.12)]
    elif kind == "mortar":
        prof = [(d_front, tr * 0.9), (d_front + 0.02, tr), (d_front + tl, tr)]
    else:
        prof = [(d_front, tr * 0.86), (d_front + 0.03, tr), (d_front + tl * 0.82, tr), (d_front + tl * 0.82, tr * 1.14), (d_front + tl, tr * 1.38)]
    lathe_d(g, prof, tube_mat, n=20, hard=(2,) if kind != "recoilless" else ())
    # front bell and rings
    tube(g, d_front - 0.01, d_front + 0.012, tr * 0.98, dk, n=20)
    if g.fine:
        for k in range(3):
            tube(g, d_front + 0.1 + k * 0.28, d_front + 0.112 + k * 0.28, tr * 1.03, ac, n=20)
    if kind in ("rocket", "guided", "wire", "aa", "bunker", "cluster", "thermo", "plasma"):
        # the warhead standing out of the muzzle
        wr = tr * {"bunker": 0.92, "thermo": 0.95, "cluster": 0.75}.get(kind, 0.6)
        wl_ = {"bunker": 0.17, "aa": 0.28, "cluster": 0.2, "thermo": 0.14, "plasma": 0.0}.get(kind, 0.2)
        if kind == "plasma":
            lathe_d(g, [(d_front - 0.03, tr * 0.5), (d_front - 0.005, tr * 0.8), (d_front + 0.012, tr * 0.7)], gl, n=16)
        else:
            lathe_d(g, [(d_front - wl_, 0.004), (d_front - wl_ * 0.65, wr * 0.86), (d_front - wl_ * 0.25, wr), (d_front + 0.04, wr)], pal["body"] if kind in ("cluster",) else ac, n=14, hard=())
            tube(g, d_front - wl_ * 0.25, d_front - wl_ * 0.2, wr * 1.04, dk, n=14)
        if kind == "guided":
            g.cyl((0, -(d_front - wl_), 0.0), (0, -(d_front - wl_ - 0.03), 0.0), 0.004, pal["lens_glow"], n=8)
    # --- rear: venturi flare
    if kind not in ("mortar",):
        rd = d_front + tl
        lathe_d(g, [(rd, tr * 1.38), (rd + 0.015, tr * 1.5), (rd + 0.06, tr * 1.85)] if kind != "recoilless" else [(rd, tr * 1.12), (rd + 0.04, tr * 1.7)], dk, n=20, hard=())
    else:
        rbox(g, d_front + tl, d_front + tl + 0.02, -tr * 1.4, tr * 1.4, tr * 2.8, dk, r=0.006)
    # --- grips and shoulder
    sd = s.get("grip_d", d_front + tl * 0.46)
    side_w(g, [(sd, -tr * 0.8), (sd + 0.04, -tr * 0.8), (sd + 0.05, -tr * 0.8 - 0.11), (sd + 0.012, -tr * 0.8 - 0.115)], 0.034, fr, ch=0.003)
    trigger_group(g, sd, -tr * 0.8, pal, guard_len=0.06, guard_drop=0.04)
    fd = s.get("fore_d", d_front + tl * 0.2)
    side_w(g, [(fd, -tr * 0.9), (fd + 0.035, -tr * 0.9), (fd + 0.04, -tr * 0.9 - 0.1), (fd + 0.0, -tr * 0.9 - 0.1)], 0.03, fr, ch=0.003)
    rbox(g, fd - 0.03, fd + 0.06, -tr * 0.95, -tr * 0.8, 0.04, dk, r=0.003)
    rbox(g, sd - 0.05, sd + 0.1, -tr * 1.0, -tr * 0.7, 0.04, dk, r=0.003)
    # shoulder pad
    sp_d = s.get("pad_d", d_front + tl * 0.82)
    rbox(g, sp_d + 0.1, sp_d + 0.12, -tr * 1.4, tr * 0.8, tr * 1.6, pal["rub"], r=0.01, ch=0.004) if kind in ("recoilless",) else None
    # sights / optic on the left
    o = s.get("optic", "iron")
    lens = None
    top = tr + 0.004
    rail(g, d_front + tl * 0.3, d_front + tl * 0.62, top, dk, w=0.024, h=0.008)
    if o not in ("iron", "none", None):
        lens = optic(g, o, d_front + tl * 0.46, top, pal)
    else:
        rbox(g, d_front + 0.1, d_front + 0.116, top, top + 0.03, 0.006, dk, r=0.001)
        rbox(g, d_front + tl * 0.62, d_front + tl * 0.62 + 0.016, top, top + 0.036, 0.016, dk, r=0.002)
    if s.get("rack"):                                         # a rack of three sub-munition tubes on the top rail
        for k in range(3):
            tube(g, d_front + tl * 0.2, d_front + tl * 0.62, 0.016, dk, x=(k - 1) * 0.035, z=tr + 0.03, n=10)
            tube(g, d_front + tl * 0.18, d_front + tl * 0.2, 0.019, ac, x=(k - 1) * 0.035, z=tr + 0.03, n=10)
    if kind == "guided":                                      # laser designator box and an antenna
        rbox(g, d_front + tl * 0.3, d_front + tl * 0.5, tr * 0.2, tr * 1.0, 0.07, dk, r=0.006, x=tr + 0.02)
        tube(g, d_front + tl * 0.28, d_front + tl * 0.3, 0.014, pal["lens_glow"], z=tr * 0.6, x=tr + 0.02, n=10)
        g.cyl((tr * 0.6, -(d_front + tl * 0.5), tr), (tr * 0.9, -(d_front + tl * 0.42), tr + 0.12), 0.0025, dk, n=6)
    if kind == "wire":                                        # a wire spool at the rear
        tube(g, d_front + tl * 0.7, d_front + tl * 0.76, tr * 0.6, pal["brass"], z=-tr * 0.2, x=tr + 0.045, n=14)
        tube(g, d_front + tl * 0.69, d_front + tl * 0.77, tr * 0.18, dk, z=-tr * 0.2, x=tr + 0.045, n=10)
    if kind == "aa":                                          # seeker head bulge
        g.sphere((0, -(d_front - 0.26), 0.0), tr * 0.35, pal["lens_glow"], n=10)
    if kind == "thermo" or kind == "bunker":
        rbox(g, d_front + 0.05, d_front + 0.14, -tr, tr, tr * 2.2, hz, r=0.01, ch=0.004) if False else tube(g, d_front + 0.03, d_front + 0.15, tr * 1.08, hz, n=20)
    if kind == "mortar":                                      # base plate and bipod
        rbox(g, d_front + tl + 0.02, d_front + tl + 0.06, -0.12, 0.12, 0.2, dk, r=0.01)
        for sx in (-1.0, 1.0):
            g.cyl((sx * 0.03, -(d_front + tl * 0.5), -tr), (sx * 0.1, -(d_front + tl * 0.42), -0.28), 0.007, dk, n=8)
    if kind == "plasma":
        for k in range(4):
            ring_d(g, d_front + 0.1 + k * 0.07, tr * 1.04, 0.004, pal["coil"], m=6)
        for sx in (-1.0, 1.0):                                  # glowing channels along both sides, vents and a capacitor on top
            g.box((sx * (tr + 0.001), -(d_front + tl * 0.55), 0.0), (0.0016, tl * 0.7, 0.012), pal["glow"])
            vent_row(g, d_front + tl * 0.62, d_front + tl * 0.8, tr * 0.45, tr + 0.0008, dk, n=5, h=0.02, w=0.008, both=False)
        rbox(g, d_front + tl * 0.34, d_front + tl * 0.5, tr * 0.8, tr + 0.04, 0.05, dk, r=0.008, ch=0.004)
        g.box((0.0, -(d_front + tl * 0.42), tr + 0.0405), (0.03, tl * 0.1, 0.0016), pal["glow"])
        for sx in (-1.0, 1.0):
            g.box((sx * 0.026, -(d_front + tl * 0.42), tr + 0.02), (0.0016, tl * 0.1, 0.02), pal["glow"])
    g.mark("gr", (0.0, -(sd + 0.02), -tr * 0.8 - 0.06))
    g.mark("gl", (0.0, -(fd + 0.02), -tr * 0.9 - 0.06))
    g.mark("eject", (0.0, -(d_front + tl), 0.0))
    g.mark("mag", (0.0, -(d_front + tl * 0.5), -tr))
    g.mark("aim", (0.0, -(d_front + tl * 0.46), top + 0.03))
    g.mark("optic", lens["lens"] if lens else (0.0, -(d_front + tl * 0.62), top + 0.03))
    g.mark("laser", (0.0, -d_front, -tr))
    return {"length": d_front + tl + 0.06, "butt": d_front + tl + 0.06, "grip_d": sd, "muz_ext": 0.04}


def _grenade_launcher(g, pal, s):
    """Pump / revolver / rotary grenade launchers: a fat barrel, a drum or pump, a stock."""
    kind = s.get("kind", "pump")
    bd, dk, mt, fr, ac, gl = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"]
    bl = s.get("bbl_len", 0.34)
    br = s.get("bbl_r", 0.024)
    tube(g, 0.0, bl, br, mt, n=16, ch=0.002)
    tube(g, 0.0, 0.03, br * 1.18, dk, n=16)
    d_rec = bl
    if kind == "revolver":
        cr, cl = 0.052, 0.12
        with g.in_part(wl.P_ROTOR):
            lathe_d(g, [(d_rec, cr * 0.92), (d_rec + 0.008, cr), (d_rec + cl - 0.008, cr), (d_rec + cl, cr * 0.92)], bd, n=20, hard=(1, 2))
            if g.fine:
                for k in range(6):
                    a = 2 * math.pi * k / 6
                    g.box((math.cos(a) * cr, -(d_rec + cl * 0.5), math.sin(a) * cr), (0.01 if abs(math.cos(a)) > 0.5 else 0.014, cl * 0.6, 0.01 if abs(math.sin(a)) > 0.5 else 0.014), dk)
        g.mark("rotor", (0.0, -(d_rec + cl * 0.5), 0.0))
        rbox(g, d_rec - 0.01, d_rec + cl + 0.1, -0.042, 0.042, 0.04, mt, r=0.006, ch=0.003)
        rl = cl + 0.1
    elif kind == "rotary":
        cr, cl = 0.058, 0.14
        with g.in_part(wl.P_ROTOR):
            for k in range(6):
                a = 2 * math.pi * k / 6
                tube(g, d_rec, d_rec + cl, 0.0185, bd, x=math.cos(a) * cr * 0.7, z=math.sin(a) * cr * 0.7, n=10)
                tube(g, d_rec - 0.004, d_rec + 0.006, 0.0135, dk, x=math.cos(a) * cr * 0.7, z=math.sin(a) * cr * 0.7, n=10)
            tube(g, d_rec - 0.008, d_rec + 0.006, cr * 1.0, dk, n=18)
            tube(g, d_rec + cl - 0.006, d_rec + cl + 0.008, cr * 1.0, dk, n=18)
        g.mark("rotor", (0.0, -(d_rec + cl * 0.5), 0.0))
        rbox(g, d_rec + cl, d_rec + cl + 0.1, -0.04, 0.04, 0.06, bd, r=0.006, ch=0.003)
        rl = cl + 0.1
    else:                                                  # pump: a receiver and a sliding forend
        rbox(g, d_rec, d_rec + 0.18, -0.034, 0.036, 0.05, bd, r=0.007, ch=0.003, seg=2)
        with g.in_part(wl.P_PUMP):
            rbox(g, bl * 0.35, bl * 0.35 + 0.14, -0.046, -0.014, 0.046, pal["furn"], r=0.01, ch=0.003, seg=2)
            serrate(g, bl * 0.35 + 0.02, bl * 0.35 + 0.12, -0.04, -0.02, 0.024, dk, n=6)
        g.cyl((0, -(bl * 0.2), -0.036), (0, -(bl * 0.9), -0.036), 0.012, dk, n=10)
        rl = 0.18
    gd = d_rec + rl - 0.07
    gpos = pistol_grip(g, "std", gd, -0.04, pal, w=0.036, h=0.1, rake=0.3)
    trigger_group(g, gd, -0.04, pal, guard_len=0.065, guard_drop=0.038)
    butt = stock(g, s.get("stock", "fixed"), d_rec + rl, pal, top=0.034, drop=-0.034, w=0.04, length=s.get("stock_len", 0.26))
    rail(g, d_rec, d_rec + rl, 0.04 + 0.0075, dk, w=0.021)
    lens = optic(g, s.get("optic", "reddot") if s.get("optic", "reddot") != "iron" else "reddot", d_rec + rl * 0.45, 0.0475, pal)
    g.mark("gr", (0.0, -gpos[0], gpos[1]))
    g.mark("gl", (0.0, -(bl * 0.45), -0.05))
    g.mark("eject", (0.0, -(d_rec + 0.05), 0.0))
    g.mark("mag", (0.0, -(d_rec + 0.05), -0.04))
    g.mark("aim", (0.0, -(d_rec + rl * 0.45), 0.08))
    g.mark("optic", lens["lens"])
    g.mark("laser", (0.0, -0.02, -0.02))
    return {"length": butt, "butt": butt, "grip_d": gpos[0], "muz_ext": 0.0}


def _pod_launcher(g, pal, s):
    """A multi-tube rocket pod on a shoulder frame: a hex or 2 x 3 bundle of tubes."""
    bd, dk, mt, fr, ac, gl = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"]
    L = s.get("tube_len", 0.5)
    n = s.get("tubes", 6)
    r_t = s.get("tube_r", 0.024)
    pts = []
    if n == 6:
        for k in range(6):
            a = math.pi / 3 * k
            pts.append((math.cos(a) * r_t * 2.1, math.sin(a) * r_t * 2.1))
    elif n == 7:
        pts.append((0.0, 0.0))
        for k in range(6):
            a = math.pi / 3 * k
            pts.append((math.cos(a) * r_t * 2.1, math.sin(a) * r_t * 2.1))
    else:
        for k in range(n):
            pts.append((((k % 3) - 1) * r_t * 2.1, ((k // 3) - (n // 3 - 1) / 2.0) * r_t * 2.1))
    for (px, pz) in pts:
        tube(g, 0.0, L, r_t, bd, x=px, z=pz, n=12, ch=0.002)
        tube(g, 0.0, 0.01, r_t * 1.06, dk, x=px, z=pz, n=12)
        g.cyl((px, 0.0, pz), (px, -0.012, pz), r_t * 0.7, ac, r1=r_t * 0.25, n=10)
    tube(g, 0.02, 0.05, r_t * 5.0, dk, n=18)
    tube(g, L * 0.5, L * 0.5 + 0.03, r_t * 5.0, dk, n=18)
    tube(g, L - 0.03, L, r_t * 5.0, dk, n=18)
    gd = L * 0.52
    side_w(g, [(gd, -r_t * 4.4), (gd + 0.04, -r_t * 4.4), (gd + 0.05, -r_t * 4.4 - 0.1), (gd + 0.012, -r_t * 4.4 - 0.105)], 0.034, fr, ch=0.003)
    trigger_group(g, gd, -r_t * 4.4, pal, guard_len=0.06, guard_drop=0.038)
    fd = L * 0.2
    side_w(g, [(fd, -r_t * 4.4), (fd + 0.035, -r_t * 4.4), (fd + 0.04, -r_t * 4.4 - 0.095), (fd, -r_t * 4.4 - 0.095)], 0.03, fr, ch=0.003)
    rbox(g, L, L + 0.04, -r_t * 4.6, r_t * 4.6, r_t * 9.0, pal["rub"], r=0.01)
    lens = optic(g, "reddot", L * 0.35, r_t * 4.5, pal)
    g.mark("gr", (0.0, -(gd + 0.02), -r_t * 4.4 - 0.06))
    g.mark("gl", (0.0, -(fd + 0.02), -r_t * 4.4 - 0.06))
    g.mark("eject", (0.0, -L, 0.0))
    g.mark("mag", (0.0, -L * 0.5, -r_t * 4.4))
    g.mark("aim", (0.0, -L * 0.35, r_t * 4.5 + 0.05))
    g.mark("optic", lens["lens"])
    g.mark("laser", (0.0, -0.01, -r_t * 4.4))
    return {"length": L + 0.04, "butt": L + 0.04, "grip_d": gd, "muz_ext": 0.0}


# ---------------------------------------------------------------------------------------------------------------------------------------- rotary cannons
def rotary(g, pal, s):
    """A multi-barrel rotary gun (barrels, clamps, housing, ammo feed). s: barrels, bbl_len, housing_len, feed ('drum','belt','cable','tank'), electric (glow rings)."""
    n = s.get("barrels", 6)
    bl = s.get("bbl_len", 0.34)
    br = s.get("bbl_r", 0.0085)
    cr = s.get("cluster_r", 0.034)
    bd, dk, mt, fr, ac, gl = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"]
    hl = s.get("housing_len", 0.24)
    with g.in_part(wl.P_ROTOR):
        for k in range(n):
            a = 2 * math.pi * k / n
            x, z = math.cos(a) * cr, math.sin(a) * cr
            tube(g, 0.0, bl, br, mt, x=x, z=z, n=8)
            tube(g, 0.0, 0.016, br * 1.4, dk, x=x, z=z, n=8)
        for dd in (0.03, bl * 0.5, bl - 0.01):
            tube(g, dd, dd + 0.012, cr + br * 1.4, dk, n=n * 3)
        if s.get("electric"):
            ring_d(g, bl * 0.5 + 0.006, cr + br * 1.6, 0.003, pal["coil"], n=20)
    g.mark("rotor", (0.0, -(bl * 0.5), 0.0))
    # housing: a drum with a gearbox
    d0 = bl
    lathe_d(g, [(d0, cr * 1.5), (d0 + 0.012, cr * 1.8), (d0 + hl * 0.5, cr * 1.9), (d0 + hl, cr * 1.6)], bd, n=18, hard=())
    tube(g, d0 + hl * 0.2, d0 + hl * 0.28, cr * 1.96, dk, n=18)
    if g.fine:
        for k in range(4):
            a = math.pi / 2 * k + math.pi / 4
            g.box((math.cos(a) * cr * 1.88, -(d0 + hl * 0.6), math.sin(a) * cr * 1.88), (0.016, 0.03, 0.016), dk)
    rbox(g, d0 + hl, d0 + hl + 0.1, -cr * 1.2, cr * 1.2, cr * 2.2, dk, r=0.01, ch=0.004)
    feed = s.get("feed", "drum")
    if feed == "drum":
        zc = -cr * 1.9 - 0.05
        lathe_d(g, [(d0 + 0.05, 0.075), (d0 + 0.058, 0.09), (d0 + 0.2, 0.09), (d0 + 0.208, 0.075)], mt, z=zc, n=20, hard=(1, 2))
        rbox(g, d0 + 0.09, d0 + 0.17, zc + 0.06, -cr * 1.7, 0.05, dk, r=0.004)
    elif feed == "belt":
        rbox(g, d0 + 0.05, d0 + 0.2, -cr * 1.8 - 0.1, -cr * 1.7, 0.08, mt, r=0.006, ch=0.003)
        path = [(0.03, -(d0 + 0.1 + 0.06 * t), -cr * 1.7 + 0.04 * math.sin(math.pi * t)) for t in np.linspace(0, 1, 6)]
        g.sweep(path, lambda t: wl.outline_rrect(0.016, 0.012, 0.002, 1), pal["brass"], up=(1, 0, 0))
    elif feed == "cable":
        path = [(0.0, -(d0 + 0.1), -cr * 1.7), (0.0, -(d0 + 0.25), -0.12), (0.0, -(d0 + 0.5), -0.2)]
        g.sweep(path, lambda t: wl.outline_circle(0.012, 8), dk, up=(1, 0, 0))
    elif feed == "tank":
        tube(g, d0 + 0.04, d0 + 0.26, 0.05, mt, z=-cr * 1.7 - 0.05, n=16, ch=0.004)
    # handles
    gd = d0 + hl * 0.6
    side_w(g, [(gd, -cr * 1.9), (gd + 0.045, -cr * 1.9), (gd + 0.055, -cr * 1.9 - 0.12), (gd + 0.012, -cr * 1.9 - 0.125)], 0.04, fr, ch=0.004)
    trigger_group(g, gd, -cr * 1.9, pal, guard_len=0.07, guard_drop=0.045)
    fd = d0 + 0.02
    side_w(g, [(fd, -cr * 1.9), (fd + 0.04, -cr * 1.9), (fd + 0.045, -cr * 1.9 - 0.11), (fd, -cr * 1.9 - 0.11)], 0.036, fr, ch=0.004)
    rail(g, d0 + 0.02, d0 + hl, cr * 1.9 + 0.006, dk, w=0.024, h=0.008)
    g.cyl((0.0, -(d0 + hl * 0.35), cr * 1.9 + 0.006), (0.0, -(d0 + hl * 0.35), cr * 1.9 + 0.06), 0.006, dk, n=8)
    g.cyl((0.0, -(d0 + hl * 0.35), cr * 1.9 + 0.06), (0.0, -(d0 + hl * 0.7), cr * 1.9 + 0.06), 0.006, dk, n=8)
    butt = d0 + hl + 0.1
    g.mark("gr", (0.0, -(gd + 0.02), -cr * 1.9 - 0.07))
    g.mark("gl", (0.0, -(fd + 0.02), -cr * 1.9 - 0.065))
    g.mark("eject", (cr * 1.9, -(d0 + hl * 0.5), 0.0))
    g.mark("mag", (0.0, -(d0 + 0.12), -cr * 1.9 - 0.1))
    g.mark("aim", (0.0, -(d0 + hl * 0.5), cr * 1.9 + 0.06))
    g.mark("optic", (0.0, -(d0 + hl * 0.5), cr * 1.9 + 0.06))
    g.mark("laser", (0.0, -0.0, -cr))
    return {"length": butt, "butt": butt, "grip_d": gd, "muz_ext": 0.0}


# ---------------------------------------------------------------------------------------------------------------------------------------- flamers
def flamer(g, pal, s):
    """A flame / spray weapon: nozzle pipe with a pilot light, fuel tanks, hose and gauge. s: tanks, tank_r, color accents come from the palette."""
    bd, dk, mt, fr, ac, gl, hz = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"], pal["hazard"]
    nl = s.get("nozzle_len", 0.4)
    tr = s.get("tank_r", 0.045)
    tl = s.get("tank_len", 0.4)
    # nozzle: pipe, collar, wide mouth
    tube(g, 0.0, nl, 0.0145, mt, n=12, ch=0.002)
    lathe_d(g, [(0.0, 0.026), (0.016, 0.026), (0.03, 0.0145)], dk, n=16, hard=(1,))
    for k in range(3):
        tube(g, 0.08 + k * 0.1, 0.092 + k * 0.1, 0.019, dk, n=12)
    # pilot light: a small glowing tube beside the nozzle
    g.cyl((0.03, -0.0, 0.0), (0.03, -0.1, 0.0), 0.0035, gl, n=6) if False else g.cyl((0.0, -0.01, 0.026), (0.0, -0.1, 0.02), 0.004, gl, n=6)
    rbox(g, nl - 0.04, nl + 0.2, -0.045, 0.03, 0.06, bd, r=0.008, ch=0.004, seg=2)
    # tanks
    ntk = s.get("tanks", 2)
    for k in range(ntk):
        x = (k - (ntk - 1) / 2.0) * (tr * 2.15) if ntk > 1 else 0.0
        z = -0.1 - tr
        lathe_d(g, [(nl + 0.02, tr * 0.5), (nl + 0.04, tr), (nl + tl - 0.04, tr), (nl + tl, tr * 0.55)], hz if pal["_faction"] in ("industrial", "toxic", "ordnance") else bd, z=z, x=x, n=16, hard=())
        tube(g, nl + 0.12, nl + 0.14, tr * 1.04, dk, z=z, x=x, n=16)
        tube(g, nl + tl - 0.12, nl + tl - 0.1, tr * 1.04, dk, z=z, x=x, n=16)
    # top tank for the gel / cryo / toxic
    if s.get("top_tank"):
        lathe_d(g, [(nl + 0.05, 0.03), (nl + 0.08, 0.05), (nl + 0.3, 0.05), (nl + 0.34, 0.03)], pal["lens_glow"], z=0.075, n=14)
    # hose and gauge
    path = [(0.0, -(nl + 0.1), -0.06), (0.0, -(nl * 0.7), -0.1), (0.0, -(nl * 0.3), -0.04), (0.0, -(nl * 0.08), -0.01)]
    g.sweep(path, lambda t: wl.outline_circle(0.008, 8), dk, up=(1, 0, 0))
    g.cyl((0.04, -(nl + 0.12), 0.0), (0.046, -(nl + 0.12), 0.0), 0.016, mt, n=14)
    g.cyl((0.0465, -(nl + 0.12), 0.0), (0.047, -(nl + 0.12), 0.0), 0.0125, pal["screen"], n=12)
    # grips, stock
    gd = nl + 0.1
    gpos = pistol_grip(g, "std", gd, -0.045, pal, w=0.036, h=0.1, rake=0.28)
    trigger_group(g, gd, -0.045, pal, guard_len=0.06, guard_drop=0.036)
    fd = nl * 0.4
    side_w(g, [(fd, -0.012), (fd + 0.036, -0.012), (fd + 0.04, -0.1), (fd, -0.1)], 0.03, fr, ch=0.003)
    g.cyl((0.0, -(fd + 0.018), -0.012), (0.0, -(fd + 0.018), 0.0), 0.01, dk, n=8)
    butt = stock(g, "fixed", nl + 0.2, pal, top=0.028, drop=-0.04, w=0.04, length=0.22) if s.get("stock", True) else nl + 0.2
    g.mark("gr", (0.0, -gpos[0], gpos[1]))
    g.mark("gl", (0.0, -(fd + 0.02), -0.06))
    g.mark("eject", (0.0, -(nl + 0.1), 0.0))
    g.mark("mag", (0.0, -(nl + 0.2), -0.1))
    g.mark("aim", (0.0, -nl * 0.5, 0.05))
    g.mark("optic", (0.0, -nl * 0.5, 0.05))
    g.mark("laser", (0.0, -0.02, -0.01))
    return {"length": butt, "butt": butt, "grip_d": gpos[0], "muz_ext": 0.0}


# ---------------------------------------------------------------------------------------------------------------------------------------- bows
def bow(g, pal, s):
    """Bows and crossbows. s: kind ('recurve','long','compound','cross','repeater','heavy'), span (limb tip to tip), draw."""
    kind = s.get("kind", "recurve")
    bd, dk, mt, fr, ac, gl, wd = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"], pal["furn"]
    if kind in ("cross", "repeater", "heavy"):
        return _crossbow(g, pal, s)
    span = s.get("span", 0.72)
    # a vertical bow in the plane of the barrel axis: limbs curve forward at the tips; riser at d = 0.3
    d_r = s.get("riser_d", 0.3)
    n = 9
    for sgn in (1.0, -1.0):
        path = []
        for i in range(n):
            t = i / (n - 1)
            zz = sgn * (0.05 + (span / 2 - 0.05) * t)
            dd = d_r - (0.11 if kind != "long" else 0.07) * (t ** 2.3) + (0.03 * math.sin(t * math.pi * 0.9) if kind == "compound" else 0.0)
            path.append((0.0, -dd, zz))
        wlimb = 0.026 - 0.012 * 0.8
        g.sweep(path, lambda t: wl.outline_rrect(0.022 - 0.008 * t, 0.026 - 0.012 * t, 0.004, 1), wd if kind != "compound" else pal["carbon"], up=(1, 0, 0), chamfer=(0.0, 0.0025))
        tip = path[-1]
        g.sphere((0.0, tip[1], tip[2]), 0.0075, dk, n=8)
        if kind == "compound":                                # cams
            g.cyl((-0.01, tip[1], tip[2]), (0.01, tip[1], tip[2]), 0.02, dk, n=14)
    # riser and grip
    rbox(g, d_r - 0.03, d_r + 0.03, -0.11, 0.11, 0.03, mt if kind in ("compound", "recurve") else wd, r=0.01, ch=0.005, seg=2)
    rbox(g, d_r - 0.014, d_r + 0.032, -0.085, 0.025, 0.036, pal["rub"], r=0.007, ch=0.003)
    rbox(g, d_r + 0.03, d_r + 0.05, 0.02, 0.05, 0.016, dk, r=0.002)                    # arrow shelf
    # the string: a thin line between the tips
    zt = span / 2
    tipd = d_r - (0.11 if kind != "long" else 0.07)
    g.cyl((0.0, -tipd, zt), (0.0, -(d_r + 0.2), 0.0), 0.0012, pal["fabric"], n=4)
    g.cyl((0.0, -(d_r + 0.2), 0.0), (0.0, -tipd, -zt), 0.0012, pal["fabric"], n=4)
    # an arrow nocked on the string
    g.cyl((0.0, 0.0, 0.0), (0.0, -(d_r + 0.2), 0.0), 0.0032, pal["wood"], n=6)
    g.cyl((0.0, 0.0, 0.0), (0.0, -0.065, 0.0), 0.0075, mt, r1=0.0, n=8) if False else g.cyl((0.0, 0.0, 0.0), (0.0, -0.06, 0.0), 0.0, mt, r1=0.0058, n=8) if False else None
    lathe_d(g, [(-0.045, 0.0), (-0.03, 0.0058), (0.0, 0.0058)], mt, n=8) if False else lathe_d(g, [(0.0, 0.0001), (0.05, 0.0058), (0.06, 0.0058)], mt, n=8)
    for k in range(3):
        a = 2 * math.pi * k / 3
        side_w(g, [(d_r + 0.18, 0.0), (d_r + 0.24, 0.0), (d_r + 0.22, 0.014), (d_r + 0.17, 0.014)], 0.0012, ac, x=0.0) if k == 0 else None
    if "quiver" in s.get("extras", []):
        tube(g, d_r - 0.03, d_r + 0.2, 0.03, pal["leather"], z=-0.06, x=0.07, n=12)
    g.mark("gr", (0.0, -(d_r + 0.012), -0.04))
    g.mark("gl", (0.0, -(d_r + 0.2), 0.0))
    g.mark("eject", (0.0, -(d_r), 0.03))
    g.mark("mag", (0.0, -(d_r), -0.1))
    g.mark("aim", (0.0, -(d_r - 0.02), 0.06))
    g.mark("optic", (0.0, -(d_r - 0.02), 0.06))
    g.mark("laser", (0.0, 0.0, 0.0))
    return {"length": d_r + 0.25, "butt": d_r + 0.25, "grip_d": d_r, "muz_ext": 0.0}


def _crossbow(g, pal, s):
    kind = s.get("kind", "cross")
    bd, dk, mt, fr, ac, gl, wd = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"], pal["furn"]
    span = s.get("span", 0.62 if kind != "heavy" else 0.7)
    d_p = s.get("prod_d", 0.13)
    # the prod (limbs) across the front
    for sgn in (1.0, -1.0):
        path = []
        for i in range(8):
            t = i / 7.0
            path.append((sgn * (0.025 + (span / 2 - 0.025) * t), -(d_p - 0.07 * t ** 2.2), 0.0))
        g.sweep(path, lambda t: wl.outline_rrect(0.016 - 0.006 * t, 0.012, 0.002, 1), pal["carbon"] if kind != "heavy" else mt, up=(0, 0, 1), chamfer=(0.0, 0.0015))
        tip = path[-1]
        g.cyl((tip[0], tip[1], -0.008), (tip[0], tip[1], 0.008), 0.0075, dk, n=8)
    # stock with a rail, a groove for the bolt
    L = s.get("len", 0.6)
    rbox(g, d_p - 0.04, d_p + 0.16, -0.026, 0.022, 0.05, bd, r=0.008, ch=0.003)
    hs = 0.012 if s.get("heavy_stock") else 0.0
    side_w(g, [(d_p + 0.12, 0.022 + hs), (d_p + L * 0.75, 0.026 + hs), (d_p + L, 0.012 + hs), (d_p + L, -0.075 - hs), (d_p + L * 0.55, -0.032 - hs), (d_p + 0.12, -0.026 - hs)], 0.04 + 2 * hs, wd, ch=0.004)
    rail(g, 0.0, d_p + 0.22, 0.03, dk, w=0.02, h=0.007, pitch=0.014)
    g.cyl((0.0, -0.0, 0.0126), (0.0, -(d_p + 0.24), 0.0126), 0.0036, pal["wood"], n=6)
    lathe_d(g, [(0.0, 0.0001), (0.045, 0.0055), (0.05, 0.0055)], mt, n=8, z=0.0126)
    # string and the latch
    zt = span / 2
    g.cyl((-zt, -(d_p - 0.07), 0.0), (0.0, -(d_p + 0.1), 0.0), 0.0014, pal["fabric"], n=4)
    g.cyl((0.0, -(d_p + 0.1), 0.0), (zt, -(d_p - 0.07), 0.0), 0.0014, pal["fabric"], n=4)
    # stirrup and the foot ring
    g.torus((0.0, -(d_p - 0.045), 0.0), 0.024, 0.004, dk, n=14, m=6, axis="z") if False else None
    rbox(g, d_p - 0.045, d_p - 0.02, -0.035, -0.02, 0.06, dk, r=0.003)
    gd = d_p + L * 0.5
    gpos = pistol_grip(g, "std", gd, -0.03, pal, w=0.034, h=0.095, rake=0.3)
    trigger_group(g, gd, -0.03, pal, guard_len=0.06, guard_drop=0.036)
    mag = s.get("mag")
    if kind == "repeater":                                    # a box magazine on top
        rbox(g, d_p + 0.05, d_p + 0.2, 0.036, 0.1, 0.044, mt, r=0.006, ch=0.003)
        rbox(g, d_p + 0.05, d_p + 0.2, 0.1, 0.108, 0.048, dk, r=0.003)
    if kind == "heavy":
        tube(g, d_p + 0.02, d_p + 0.16, 0.02, dk, z=0.0, x=0.0, n=10) if False else rbox(g, d_p + 0.06, d_p + 0.14, 0.03, 0.05, 0.05, dk, r=0.004)
    o = s.get("optic", "iron")
    lens = None
    if o not in ("iron", "none", None):
        lens = optic(g, o, d_p + L * 0.3, 0.037, pal)
    else:
        rbox(g, d_p + 0.2, d_p + 0.21, 0.03, 0.05, 0.008, dk, r=0.001)
    g.mark("gr", (0.0, -gpos[0], gpos[1]))
    g.mark("gl", (0.0, -(d_p + 0.16), -0.03))
    g.mark("eject", (0.0, -(d_p + 0.1), 0.02))
    g.mark("mag", (0.0, -(d_p + 0.12), 0.05))
    g.mark("aim", (0.0, -(d_p + L * 0.3), 0.07))
    g.mark("optic", lens["lens"] if lens else (0.0, -(d_p + 0.2), 0.05))
    g.mark("laser", (0.0, -0.0, 0.0))
    return {"length": d_p + L, "butt": d_p + L, "grip_d": gpos[0], "muz_ext": 0.0}
