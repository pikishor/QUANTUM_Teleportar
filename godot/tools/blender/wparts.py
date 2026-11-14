"""Parts library of the weapon kit (wave 114). Everything is placed in the kit frame of weaponlib.py (muzzle at y = 0, the body lies behind it at y = -d, bore axis = Y axis, z up, x right);
helpers take DISTANCES d behind the muzzle (d0 < d1) and heights z so that a recipe reads like a drawing. `pal` is a dict of weaponlib.Style objects (see palette()).
Fine details (screws, serrations, vents, rail teeth) are dropped at LOD1 (g.fine False). Every function returns anchors where a later part needs them."""
import math

import numpy as np

import weaponlib as wl
import weapon_mats as M
from weaponlib import Style, G


# ------------------------------------------------------------------------------------------------------------------------------------------ palettes
def lin(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def mixc(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


POLY_TINTS = {"black": (0.04, 0.042, 0.046), "grey": (0.1, 0.105, 0.115), "od": (0.065, 0.078, 0.04), "tan": (0.24, 0.19, 0.115), "white": (0.44, 0.46, 0.48),
              "navy": (0.025, 0.04, 0.085), "red": (0.28, 0.03, 0.026), "orange": (0.4, 0.13, 0.022), "yellow": (0.42, 0.32, 0.02), "teal": (0.025, 0.15, 0.15), "violet": (0.075, 0.04, 0.15),
              "olive_dark": (0.04, 0.05, 0.028), "sand": (0.36, 0.29, 0.17), "slate": (0.055, 0.065, 0.082), "bone": (0.4, 0.36, 0.29)}

# factions: (frame polymer, metal layer + tint, accent paint, wood?, special layers)
FACTIONS = {
    "service": dict(poly="od", metal=(M.STEEL_P, (1.0, 1.0, 1.0)), accent="tan", rub="black"),
    "tactical": dict(poly="black", metal=(M.STEEL_P, (0.8, 0.82, 0.85)), accent="grey", rub="black"),
    "desert": dict(poly="tan", metal=(M.STEEL_P, (1.15, 1.1, 1.0)), accent="sand", rub="black"),
    "arctic": dict(poly="white", metal=(M.ALLOY, (0.9, 0.92, 0.95)), accent="grey", rub="slate"),
    "sport": dict(poly="black", metal=(M.STEEL_B, (1.0, 1.0, 1.05)), accent="red", wood=True, rub="black"),
    "heritage": dict(poly="black", metal=(M.STEEL_B, (1.0, 1.0, 1.05)), accent="bone", wood=True, rub="black"),
    "industrial": dict(poly="yellow", metal=(M.STEEL_P, (0.9, 0.9, 0.9)), accent="orange", rub="black"),
    "ordnance": dict(poly="od", metal=(M.STEEL_P, (0.95, 0.95, 0.92)), accent="orange", rub="black"),
    "ceramic": dict(poly="white", metal=(M.ALLOY, (1.0, 1.02, 1.08)), accent="navy", rub="slate", ceramic=True),
    "quantum": dict(poly="slate", metal=(M.TITANIUM, (0.75, 0.8, 0.95)), accent="violet", rub="black", ceramic=True),
    "chrome": dict(poly="black", metal=(M.CHROME, (1.0, 1.0, 1.0)), accent="red", wood=True, rub="black"),
    "carbon": dict(poly="black", metal=(M.ALLOY, (0.55, 0.57, 0.62)), accent="red", carbon=True, rub="black"),
    "camo_wood": dict(poly="black", metal=(M.STEEL_P, (0.9, 0.9, 0.9)), accent="od", camo=M.CAMO_A, rub="black"),
    "camo_desert": dict(poly="tan", metal=(M.STEEL_P, (1.1, 1.05, 0.95)), accent="sand", camo=M.CAMO_B, rub="black"),
    "camo_urban": dict(poly="grey", metal=(M.STEEL_P, (0.85, 0.87, 0.9)), accent="slate", camo=M.CAMO_C, rub="black"),
    "toxic": dict(poly="olive_dark", metal=(M.STEEL_P, (0.8, 0.9, 0.7)), accent="yellow", rub="black"),
    "riot": dict(poly="navy", metal=(M.STEEL_P, (0.8, 0.85, 0.95)), accent="orange", rub="black"),
    "gold": dict(poly="black", metal=(M.BRASS, (1.0, 1.0, 1.0)), accent="bone", wood=True, rub="black"),
}


def _mul(c, k):
    return tuple(min(1.0, c[i] * k[i]) for i in range(3))


def palette(faction="tactical", glow=(0.4, 0.9, 1.0), accent=None, poly=None, wood="dark", rng=None):
    """The styles of one weapon. `glow` = the weapon's look colour (the energy cores and trims take it). A tint is the base ALBEDO (linear) of the surface: the swatches only add grain."""
    f = FACTIONS.get(faction, FACTIONS["tactical"])
    pt = POLY_TINTS[poly or f["poly"]]
    ml, mt = f["metal"]
    ac = POLY_TINTS[accent or f["accent"]]
    camo = f.get("camo")
    LB = M.LAYER_BASE
    body = Style(camo, (0.5, 0.5, 0.5)) if camo is not None else (Style(M.CARBON, LB[M.CARBON]) if f.get("carbon") else
                                                                     (Style(M.CERAMIC, _mul(LB[M.CERAMIC], mixc((1, 1, 1), pt, 0.7))) if f.get("ceramic") else Style(M.POLY, pt)))
    wood_l = M.WOOD_DARK if wood == "dark" else M.WOOD_LIGHT
    pal = {
        "body": body,                                                    # receiver and shell
        "frame": Style(M.POLY, pt),                                      # lower frame, grips, stocks (polymer)
        "metal": Style(ml, _mul(LB[ml], mt)),                            # barrel, bolt, steel parts
        "dark": Style(M.STEEL_B, LB[M.STEEL_B]),                         # blackened small parts, screws, slots
        "bright": Style(M.STEEL_BRIGHT, LB[M.STEEL_BRIGHT]),             # polished edges, pins
        "accent": Style(M.PAINT, ac),                                    # painted trim
        "rub": Style(M.RUBBER, POLY_TINTS["black"] if f.get("rub", "black") == "black" else POLY_TINTS[f["rub"]]),     # grip panels, pads
        "wood": Style(wood_l, LB[wood_l]),
        "glow": Style(M.CORE, glow, 1.0),                                # energy core
        "coil": Style(M.COIL, glow, 1.0),
        "lens": Style(M.GLASS, (0.03, 0.05, 0.08), 0.0),
        "lens_glow": Style(M.GLASS, mixc(glow, (0.1, 0.12, 0.2), 0.5), 0.35),
        "screen": Style(M.SCREEN, glow, 0.8),
        "brass": Style(M.BRASS, LB[M.BRASS]),
        "chrome": Style(M.CHROME, LB[M.CHROME]),
        "carbon": Style(M.CARBON, LB[M.CARBON]),
        "leather": Style(M.LEATHER, LB[M.LEATHER]),
        "fabric": Style(M.FABRIC, LB[M.FABRIC]),
        "hazard": Style(M.HAZARD, (0.5, 0.5, 0.5)),
        "label": Style(M.LABEL, (0.5, 0.5, 0.5)),
        "gloss": Style(M.GLOSS, ac),
        "alloy": Style(M.ALLOY, LB[M.ALLOY]),
        "titanium": Style(M.TITANIUM, _mul(LB[M.TITANIUM], mixc((1, 1, 1), glow, 0.25))),
        "ceramic": Style(M.CERAMIC, _mul(LB[M.CERAMIC], mixc((1, 1, 1), pt, 0.7))),
        "plain": Style(M.POLY, pt),
    }
    pal["furn"] = pal["wood"] if f.get("wood") else pal["frame"]          # furniture: stocks, handguards
    pal["_faction"] = faction
    return pal


# ------------------------------------------------------------------------------------------------------------------------------------------ small helpers
def Dp(d, z=0.0, x=0.0):
    return (x, -d, z)


def rbox(g, d0, d1, z0, z1, w, st, r=0.004, ch=None, x=0.0, seg=1):
    """Box between the distances d0 < d1 behind the muzzle and the heights z0 < z1, width w, centred on x; r rounds the long edges, ch chamfers the ends."""
    g.box((x, -(d0 + d1) / 2.0, (z0 + z1) / 2.0), (w, d1 - d0, z1 - z0), st, r=min(r, 0.45 * min(w, z1 - z0)), chamfer=ch if ch is not None else min(r, 0.004) * 0.6, seg=seg)


def tube(g, d0, d1, r, st, z=0.0, x=0.0, n=12, r1=None, ch=0.0, caps=(True, True)):
    g.cyl((x, -d0, z), (x, -d1, z), r, st, r1=r1, n=n, chamfer=ch, caps=caps)


def lathe_d(g, prof, st, z=0.0, x=0.0, n=14, hard=(), caps=(True, True)):
    """Surface of revolution along the barrel axis: prof = [(d, r), ...] with d increasing (front to back)."""
    g.lathe([(-d, r) for (d, r) in prof], st, n=n, cx=x, cz=z, caps=caps, hard=hard)


def side(g, pts_dz, x0, x1, st, ch=0.0, x_scale1=None):
    """A side profile [(d, z), ...] (distance behind the muzzle, height) across x0..x1."""
    pts = [(-d, z) for (d, z) in pts_dz]
    area = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        area += a[0] * b[1] - b[0] * a[1]
    if area < 0:
        pts = pts[::-1]
    g.extrude(pts, x0, x1, st, chamfer=ch, x_scale1=x_scale1)


def side_w(g, pts_dz, w, st, ch=0.0, x=0.0, taper=None):
    side(g, pts_dz, x - w / 2.0, x + w / 2.0, st, ch, taper)


def screw(g, p, st, r=0.0026, axis="x", depth=0.0012):
    if not g.fine:
        return
    p = np.asarray(p, dtype=np.float64)
    ax = {"x": wl.X_AX, "y": wl.Y_AX, "z": wl.Z_AX}[axis]
    g.cyl(p, p + ax * depth, r, st, n=6, chamfer=0.0)


def seam(g, d0, d1, z0, z1, x, st, t=0.0015, proud=0.0006):
    """A thin dark strip proud of the surface (a panel line)."""
    if not g.fine:
        return
    sgn = 1.0 if x >= 0 else -1.0
    g.box((x + sgn * proud / 2.0, -(d0 + d1) / 2.0, (z0 + z1) / 2.0), (proud, abs(d1 - d0) if abs(d1 - d0) > t else t, abs(z1 - z0) if abs(z1 - z0) > t else t), st)


def serrate(g, d0, d1, z0, z1, x, st, n=6, t=0.0012, proud=0.0007):
    """Slide / handguard serrations: n thin vertical strips between d0 and d1 on the side x."""
    if not g.fine:
        return
    sgn = 1.0 if x >= 0 else -1.0
    for i in range(n):
        d = d0 + (d1 - d0) * i / max(1, n - 1)
        g.box((x + sgn * proud / 2.0, -d, (z0 + z1) / 2.0), (proud, t, abs(z1 - z0)), st)


def vent_row(g, d0, d1, z, x, st, n=6, h=0.012, w=0.004, both=True):
    """Cooling slots: dark boxes set a hair into the surface, on one or both sides."""
    if not g.fine:
        return
    for i in range(n):
        d = d0 + (d1 - d0) * i / max(1, n - 1)
        for sx in ((1.0, -1.0) if both else (1.0,)):
            g.box((sx * x, -d, z), (0.0012, w, h), st)


def rail(g, d0, d1, z, st, w=0.021, h=0.008, pitch=0.0125, x=0.0, teeth=True, dark=None):
    """Accessory rail: a base bar and (LOD0) raised teeth across it. z = the rail's top height."""
    rbox(g, d0, d1, z - h, z - h * 0.35, w, st, r=0.0015, ch=0.001, x=x)
    if g.fine and teeth:
        n = int((d1 - d0) / pitch)
        for i in range(n):
            if i % 2 == 0:
                continue
            d = d0 + (i + 0.5) * pitch
            g.box((x, -d, z - h * 0.35 + 0.0008), (w * 1.02, pitch * 0.5, h * 0.4), st)


def mlok(g, d0, d1, z, x, st, n=4, side_x=1.0):
    """Slotted handguard panels: a few dark slots (LOD0)."""
    if not g.fine:
        return
    for i in range(n):
        d = d0 + (d1 - d0) * (i + 0.5) / n
        g.box((side_x * x, -d, z), (0.0012, 0.017, 0.006), st)


def grip_texture(g, d0, d1, z0, z1, x, st, n=5):
    serrate(g, d0, d1, z0, z1, x, st, n=n, t=0.0014, proud=0.0009)


# ------------------------------------------------------------------------------------------------------------------------------------------ muzzle devices (anchor: the bore exits at d = 0; devices extend to d < 0 in front)
def muzzle_device(g, kind, r_bbl, pal, z=0.0, x=0.0, d0=0.0):
    """Muzzle end of a barrel at distance d0 behind the muzzle point (the device sticks out in front of it). The muzzle point itself stays the barrel tip: devices are drawn at -len..0."""
    m = pal["dark"]
    mt = pal["metal"]
    if kind == "none" or kind is None:
        lathe_d(g, [(d0, r_bbl * 0.92), (d0 + 0.004, r_bbl)], mt, z=z, x=x, n=12, caps=(True, False))
        return 0.0
    if kind == "crown":
        lathe_d(g, [(d0 - 0.004, r_bbl * 0.8), (d0, r_bbl * 1.05), (d0 + 0.006, r_bbl * 1.05), (d0 + 0.006, r_bbl)], mt, z=z, x=x, n=12)
        return 0.004
    if kind == "flash":                                 # birdcage flash hider: ribbed cage with a dark gap
        L = 0.06
        lathe_d(g, [(d0 - L, r_bbl * 1.18), (d0 - L, r_bbl * 1.5), (d0 - L * 0.9, r_bbl * 1.5), (d0 - L * 0.55, r_bbl * 1.5), (d0 - L * 0.5, r_bbl * 1.2), (d0 - L * 0.45, r_bbl * 1.5),
                          (d0 - 0.002, r_bbl * 1.5), (d0 - 0.002, r_bbl * 1.1), (d0 + 0.004, r_bbl)], m, z=z, x=x, n=12, hard=(1, 2, 3, 4, 5, 6))
        if g.fine:
            for k in range(3):                          # the slots
                a = 2 * math.pi * k / 3 + 0.5
                g.box((x + math.cos(a) * r_bbl * 1.5, -(d0 - L * 0.78), z + math.sin(a) * r_bbl * 1.5), (0.004, 0.026, 0.004), pal["bright"].k(0.1))
        return L
    if kind == "brake":                                 # muzzle brake with side ports
        L = 0.075
        lathe_d(g, [(d0 - L, r_bbl * 1.35), (d0 - L * 0.05, r_bbl * 1.35), (d0 - L * 0.05, r_bbl * 1.1), (d0 + 0.004, r_bbl)], m, z=z, x=x, n=12, hard=(1,))
        if g.fine:
            for k in range(3):
                d = d0 - L * (0.25 + 0.25 * k)
                for sx in (1.0, -1.0):
                    g.box((x + sx * r_bbl * 1.36, -d, z), (0.0014, 0.007, r_bbl * 1.6), pal["bright"].k(0.08))
        return L
    if kind == "comp":                                  # slotted compensator
        L = 0.045
        lathe_d(g, [(d0 - L, r_bbl * 1.25), (d0 - 0.002, r_bbl * 1.25), (d0 + 0.003, r_bbl)], m, z=z, x=x, n=12, hard=(0,))
        if g.fine:
            for k in range(2):
                g.box((x, -(d0 - L * (0.3 + 0.35 * k)), z + r_bbl * 1.27), (r_bbl * 1.1, 0.006, 0.0014), pal["bright"].k(0.08))
        return L
    if kind == "can" or kind == "supp":                 # suppressor: a long can with end cap and a ribbed band
        L = 0.17
        rc = r_bbl * 2.05
        lathe_d(g, [(d0 - L, rc * 0.96), (d0 - L, rc), (d0 - 0.015, rc), (d0 - 0.015, rc * 0.9), (d0 + 0.004, r_bbl * 1.3)], m, z=z, x=x, n=14, hard=(1, 2, 3))
        if g.fine:
            for k in range(4):
                tube(g, d0 - L * 0.78 + k * 0.011, d0 - L * 0.78 + k * 0.011 + 0.004, rc * 1.02, pal["bright"].k(0.12), z=z, x=x, n=14)
        return L
    if kind == "fin":                                   # finned heavy suppressor
        L = 0.15
        rc = r_bbl * 1.9
        for k in range(7):
            d = d0 - L + k * (L / 7.0)
            tube(g, d, d + L / 7.0 * 0.55, rc * 1.12, m, z=z, x=x, n=12)
        tube(g, d0 - L, d0, rc * 0.8, mt, z=z, x=x, n=12)
        return L
    if kind == "bell":                                  # flared shotgun / flare bell
        L = 0.045
        lathe_d(g, [(d0 - L, r_bbl * 2.1), (d0 - L * 0.4, r_bbl * 1.4), (d0 + 0.004, r_bbl)], m, z=z, x=x, n=14, hard=(0,))
        return L
    if kind == "choke":                                 # a short thread protector with a notched crown
        L = 0.024
        lathe_d(g, [(d0 - L, r_bbl * 1.18), (d0, r_bbl * 1.18), (d0 + 0.003, r_bbl)], m, z=z, x=x, n=12, hard=(0,))
        if g.fine:
            for k in range(4):
                a = math.pi / 2 * k
                g.box((x + math.cos(a) * r_bbl * 1.18, -(d0 - L), z + math.sin(a) * r_bbl * 1.18), (0.003, 0.004, 0.003), pal["bright"].k(0.1))
        return L
    if kind == "duck":                                  # wide rectangular spreader
        L = 0.05
        rbox(g, d0 - L, d0, z - r_bbl * 1.4, z + r_bbl * 1.4, r_bbl * 5.0, m, r=0.003, ch=0.002, x=x)
        return L
    if kind == "prong":                                 # taser style
        return 0.0
    return 0.0


# ------------------------------------------------------------------------------------------------------------------------------------------ optics (centred on x; `z` = the base of the mount, d = centre distance)
def optic(g, kind, d, z, pal, x=0.0, length=None):
    """Sights on top of a rail. Returns the height of the top of the optic and the lens centre {'lens': (x, y, z)}."""
    m = pal["dark"]
    b = pal["body"]
    if kind in (None, "none", "iron"):
        rbox(g, d - 0.006, d + 0.006, z, z + 0.017, 0.012, m, r=0.001, ch=0.0008, x=x)        # rear sight block
        if g.fine:
            g.box((x - 0.006, -d, z + 0.021), (0.0025, 0.007, 0.01), m)
            g.box((x + 0.006, -d, z + 0.021), (0.0025, 0.007, 0.01), m)
        return {"top": z + 0.022, "lens": (x, -d, z + 0.012)}
    if kind == "reddot":
        rbox(g, d - 0.025, d + 0.026, z, z + 0.012, 0.03, m, r=0.002, ch=0.0015, x=x)
        tube(g, d - 0.024, d + 0.024, 0.0145, m, z=z + 0.03, x=x, n=14, ch=0.001)
        tube(g, d - 0.0245, d - 0.0225, 0.0125, pal["lens"], z=z + 0.03, x=x, n=14)
        tube(g, d + 0.0225, d + 0.0245, 0.0125, pal["lens_glow"], z=z + 0.03, x=x, n=14)
        rbox(g, d - 0.01, d + 0.01, z + 0.012, z + 0.017, 0.018, m, r=0.002, x=x)
        return {"top": z + 0.0455, "lens": (x, -d - 0.025, z + 0.03)}
    if kind == "mini":                                  # open mini reflex
        rbox(g, d - 0.018, d + 0.018, z, z + 0.009, 0.026, m, r=0.002, ch=0.0012, x=x)
        rbox(g, d + 0.016, d + 0.02, z + 0.009, z + 0.034, 0.026, m, r=0.002, ch=0.0012, x=x)
        rbox(g, d - 0.019, d - 0.015, z + 0.009, z + 0.034, 0.026, m, r=0.002, ch=0.0012, x=x)
        g.box((x, -(d - 0.017), z + 0.022), (0.02, 0.0012, 0.02), pal["lens_glow"])
        return {"top": z + 0.034, "lens": (x, -d, z + 0.022)}
    if kind == "holo":                                  # holographic: a boxy frame with a window
        rbox(g, d - 0.03, d + 0.03, z, z + 0.012, 0.036, m, r=0.002, ch=0.0015, x=x)
        rbox(g, d - 0.03, d + 0.03, z + 0.012, z + 0.017, 0.04, m, r=0.002, ch=0.0015, x=x)
        rbox(g, d - 0.03, d - 0.024, z + 0.012, z + 0.05, 0.04, m, r=0.002, ch=0.0015, x=x)
        rbox(g, d + 0.024, d + 0.03, z + 0.012, z + 0.05, 0.04, m, r=0.002, ch=0.0015, x=x)
        rbox(g, d - 0.03, d + 0.03, z + 0.046, z + 0.052, 0.04, m, r=0.002, ch=0.0015, x=x)
        g.box((x, -(d - 0.0235), z + 0.031), (0.028, 0.0012, 0.026), pal["lens"])
        g.box((x, -(d + 0.0235), z + 0.031), (0.028, 0.0012, 0.026), pal["lens_glow"])
        return {"top": z + 0.052, "lens": (x, -d, z + 0.031)}
    if kind == "prism":                                 # short fixed-power prism sight
        L = 0.075
        lathe_d(g, [(d - L / 2, 0.011), (d - L / 2 + 0.01, 0.0155), (d + L / 2 - 0.014, 0.0185), (d + L / 2, 0.0185)], m, z=z + 0.024, x=x, n=14, hard=(2,))
        rbox(g, d - 0.02, d + 0.02, z, z + 0.012, 0.024, m, r=0.002, x=x)
        tube(g, d - L / 2 - 0.001, d - L / 2 + 0.001, 0.0105, pal["lens"], z=z + 0.024, x=x, n=12)
        tube(g, d + L / 2 - 0.001, d + L / 2 + 0.0008, 0.0165, pal["lens_glow"], z=z + 0.024, x=x, n=12)
        return {"top": z + 0.0425, "lens": (x, -(d - L / 2), z + 0.024)}
    if kind in ("scope", "scope_long", "thermal"):
        L = 0.17 if kind == "scope" else (0.24 if kind == "scope_long" else 0.2)
        rt = 0.0165 if kind != "thermal" else 0.024
        zc = z + 0.032 + (0.01 if kind == "thermal" else 0)
        if kind == "thermal":
            rbox(g, d - L / 2, d + L / 2, zc - 0.026, zc + 0.026, 0.056, m, r=0.006, ch=0.004, x=x, seg=2)
            tube(g, d - L / 2 - 0.02, d - L / 2 + 0.002, 0.026, m, z=zc, x=x, n=14, ch=0.002)
            tube(g, d - L / 2 - 0.0205, d - L / 2 - 0.0185, 0.021, pal["lens_glow"], z=zc, x=x, n=14)
            rbox(g, d - 0.02, d + 0.02, z, zc - 0.026, 0.026, m, r=0.002, x=x)
            tube(g, d + L / 2 - 0.002, d + L / 2 + 0.02, 0.019, m, z=zc, x=x, n=12)
            g.box((x + 0.0285, -d, zc + 0.01), (0.002, 0.04, 0.014), pal["screen"])
            return {"top": zc + 0.026, "lens": (x, -(d - L / 2 - 0.02), zc)}
        prof = [(d - L / 2 - 0.04, 0.026), (d - L / 2 - 0.01, 0.0215), (d - L / 2, rt), (d - L * 0.15, rt * 1.0), (d - 0.012, rt * 1.18), (d + 0.012, rt * 1.18),
                (d + L * 0.12, rt * 0.98), (d + L / 2 - 0.02, rt * 0.98), (d + L / 2 - 0.012, 0.0185), (d + L / 2 + 0.03, 0.0215)]
        lathe_d(g, prof, m, z=zc, x=x, n=16, hard=())
        # objective and eyepiece lenses
        tube(g, d - L / 2 - 0.0405, d - L / 2 - 0.0385, 0.0235, pal["lens_glow"], z=zc, x=x, n=16)
        tube(g, d + L / 2 + 0.0285, d + L / 2 + 0.0305, 0.0185, pal["lens"], z=zc, x=x, n=14)
        rbox(g, d - 0.03, d - 0.012, z, zc - rt, 0.02, m, r=0.002, x=x)        # rings and mount
        rbox(g, d + 0.034, d + 0.052, z, zc - rt, 0.02, m, r=0.002, x=x)
        g.box((x, -d, zc + rt * 1.2), (0.012, 0.012, 0.012), m)                # elevation turret
        g.box((x + rt * 1.2, -d, zc), (0.012, 0.012, 0.012), m)                # windage turret
        return {"top": zc + rt * 1.2 + 0.006, "lens": (x, -(d - L / 2 - 0.04), zc)}
    return {"top": z + 0.02, "lens": (x, -d, z + 0.01)}


# ------------------------------------------------------------------------------------------------------------------------------------------ stocks (anchor at the receiver rear d0, bore axis z=0)
def stock(g, kind, d0, pal, top=0.034, drop=-0.035, w=0.036, length=0.26, x=0.0, z_bore=0.0):
    """Buttstock from the receiver rear at distance d0 back to d0 + length. Returns the butt distance."""
    f = pal["furn"]
    fr = pal["frame"]
    dk = pal["dark"]
    rub = pal["rub"]
    d1 = d0 + length
    if kind in (None, "none"):
        rbox(g, d0, d0 + 0.012, drop + 0.012, top - 0.004, w * 0.8, dk, r=0.003, x=x)
        return d0 + 0.012
    if kind == "fixed":                                  # classic fixed stock, a tall comb and a pad
        pts = [(d0, top), (d0 + length * 0.4, top - 0.004), (d1 - 0.012, top - 0.026), (d1, top - 0.036), (d1, drop - 0.075), (d1 - 0.016, drop - 0.082), (d0 + length * 0.55, drop - 0.026),
               (d0 + length * 0.25, drop - 0.01), (d0, drop)]
        side_w(g, pts, w, f, ch=0.0035, x=x)
        rbox(g, d1 - 0.016, d1 + 0.002, drop - 0.08, top - 0.034, w * 1.02, rub, r=0.003, x=x)      # butt pad
        grip_texture(g, d1 - 0.012, d1 - 0.002, drop - 0.07, top - 0.04, x + w / 2, dk, n=3)
        return d1 + 0.002
    if kind == "thumb":                                  # thumbhole stock
        pts = [(d0, top), (d0 + length * 0.45, top - 0.002), (d1 - 0.01, top - 0.03), (d1, top - 0.04), (d1, drop - 0.085), (d1 - 0.02, drop - 0.09), (d0 + length * 0.5, drop - 0.062),
               (d0 + length * 0.42, drop - 0.03), (d0 + length * 0.18, drop - 0.03), (d0 + length * 0.1, drop - 0.1), (d0 + 0.02, drop - 0.115), (d0, drop - 0.02)]
        side_w(g, pts, w, f, ch=0.0035, x=x)
        rbox(g, d1 - 0.016, d1 + 0.002, drop - 0.09, top - 0.038, w * 1.02, rub, r=0.003, x=x)
        return d1 + 0.002
    if kind == "skeleton":                               # wire / skeleton frame
        pts_o = [(d0, top - 0.002), (d1 - 0.004, top - 0.03), (d1, top - 0.034), (d1, drop - 0.07), (d1 - 0.03, drop - 0.07), (d1 - 0.03, drop - 0.05), (d0 + 0.07, drop - 0.012), (d0, drop)]
        pts_i = [(d0 + 0.03, top - 0.017), (d1 - 0.02, top - 0.04), (d1 - 0.02, drop - 0.048), (d0 + 0.09, drop - 0.016)]
        # upper and lower bars, a rear plate
        for (a, b, c, e) in ((d0, top - 0.001, d1 - 0.004, top - 0.027), (d0, drop + 0.002, d1 - 0.03, drop - 0.048)):
            pass
        g.cyl((x, -d0, top - 0.012), (x, -d1 + 0.01, top - 0.036), 0.0065, f, n=8, chamfer=0.001)
        g.cyl((x, -d0 - 0.01, drop + 0.004), (x, -d1 + 0.03, drop - 0.062), 0.0065, f, n=8, chamfer=0.001)
        rbox(g, d1 - 0.026, d1 + 0.002, drop - 0.082, top - 0.034, w * 0.9, rub, r=0.003, x=x)
        g.cyl((x, -(d1 - 0.012), top - 0.036), (x, -(d1 - 0.012), drop - 0.07), 0.0055, f, n=8)
        return d1 + 0.002
    if kind == "tele":                                   # telescoping carbine stock: a tube with a cheek and a pad
        L = length
        side_w(g, [(d0, top - 0.004), (d0 + 0.07, top - 0.005), (d0 + 0.075, drop + 0.012), (d0 + 0.02, drop + 0.006), (d0, drop)], w * 0.86, fr, ch=0.003, x=x)
        rbox(g, d0 + 0.04, d1 - 0.03, drop + 0.012, top - 0.012, w * 0.7, dk, r=0.004, x=x)              # buffer tube
        side_w(g, [(d0 + 0.07, top - 0.002), (d1 - 0.02, top - 0.012), (d1, top - 0.026), (d1, drop - 0.075), (d1 - 0.026, drop - 0.082), (d0 + 0.09, drop + 0.004)], w, f, ch=0.003, x=x)
        rbox(g, d1 - 0.016, d1 + 0.004, drop - 0.08, top - 0.028, w * 1.02, rub, r=0.003, x=x)
        grip_texture(g, d1 - 0.012, d1 - 0.002, drop - 0.07, top - 0.034, x + w / 2, dk, n=3)
        return d1 + 0.004
    if kind == "fold":                                   # side folding frame, shown folded: a short plate and a hinge block
        rbox(g, d0, d0 + 0.045, drop - 0.002, top + 0.002, w * 0.9, dk, r=0.004, x=x)
        side_w(g, [(d0 + 0.045, top - 0.002), (d0 + length * 0.62, top - 0.012), (d0 + length * 0.64, drop - 0.01), (d0 + 0.045, drop)], w * 0.5, f, ch=0.003, x=x + w * 0.52)
        rbox(g, d0 + length * 0.6, d0 + length * 0.66, drop - 0.016, top - 0.008, w * 0.9, rub, r=0.003, x=x + w * 0.5)
        return d0 + length * 0.66
    if kind == "sniper":                                 # adjustable sniper stock: cheek riser, hooked butt, skeletonised
        pts = [(d0, top), (d0 + length * 0.5, top - 0.002), (d1 - 0.02, top - 0.026), (d1, top - 0.05), (d1, drop - 0.085), (d1 - 0.02, drop - 0.09), (d0 + length * 0.7, drop - 0.09), (d0 + length * 0.62, drop - 0.042),
               (d0 + length * 0.2, drop - 0.02), (d0, drop)]
        side_w(g, pts, w * 0.95, f, ch=0.0035, x=x)
        rbox(g, d0 + length * 0.12, d0 + length * 0.52, top, top + 0.016, w * 0.8, rub, r=0.004, x=x)      # cheek riser
        rbox(g, d1 - 0.018, d1 + 0.004, drop - 0.09, top - 0.045, w, rub, r=0.003, x=x)
        g.cyl((x, -(d0 + length * 0.4), drop - 0.04), (x, -(d0 + length * 0.4), drop - 0.1), 0.004, dk, n=8)   # monopod / spacer rod
        return d1 + 0.004
    if kind == "bullpup":                                # the body runs to the shoulder (handled by the receiver): a cheek and a pad only
        rbox(g, d0 - 0.005, d0 + 0.02, drop - 0.03, top - 0.005, w, rub, r=0.004, x=x)
        return d0 + 0.02
    if kind == "brace":                                  # pistol arm brace: a short strap loop
        side_w(g, [(d0, top - 0.01), (d0 + 0.12, top - 0.012), (d0 + 0.13, drop - 0.012), (d0, drop - 0.005)], w * 0.55, fr, ch=0.003, x=x)
        rbox(g, d0 + 0.02, d0 + 0.11, drop - 0.016, drop - 0.004, w * 0.62, pal["fabric"], r=0.002, x=x)
        return d0 + 0.13
    if kind == "wire":                                   # a single bent wire frame
        g.cyl((x + 0.012, -d0, top - 0.02), (x + 0.012, -d1, top - 0.03), 0.004, dk, n=6)
        g.cyl((x - 0.012, -d0, top - 0.02), (x - 0.012, -d1, top - 0.03), 0.004, dk, n=6)
        g.cyl((x + 0.012, -d1, top - 0.03), (x + 0.012, -d1, drop - 0.06), 0.004, dk, n=6)
        g.cyl((x - 0.012, -d1, top - 0.03), (x - 0.012, -d1, drop - 0.06), 0.004, dk, n=6)
        rbox(g, d1 - 0.004, d1 + 0.004, drop - 0.064, top - 0.03, w * 0.8, rub, r=0.002, x=x)
        return d1 + 0.004
    return d0


# ------------------------------------------------------------------------------------------------------------------------------------------ grips
def pistol_grip(g, kind, d, z_top, pal, w=0.034, h=0.1, rake=0.3, x=0.0):
    """A pistol grip under the receiver at distance d (front edge), z_top = where it meets the receiver. Returns the centre of the hand (d, z)."""
    fr = pal["frame"]
    rub = pal["rub"]
    dk = pal["dark"]
    if kind == "none":
        return (d, z_top - 0.04)
    dr = h * math.tan(rake)
    pw = 0.036 if kind != "slim" else 0.03
    pts = [(d, z_top), (d + pw, z_top), (d + pw + dr, z_top - h), (d + dr + 0.004, z_top - h - (0.008 if kind == "palm" else 0.0)), (d + dr - 0.002, z_top - h * 0.55)]
    if kind == "finger":                                  # a finger groove on the front strap
        pts = [(d, z_top), (d + pw, z_top), (d + pw + dr, z_top - h), (d + dr + 0.004, z_top - h), (d + dr * 0.8 + 0.002, z_top - h * 0.75), (d + dr * 0.5 - 0.004, z_top - h * 0.5), (d + dr * 0.2 + 0.004, z_top - h * 0.3)]
    side_w(g, pts, w, fr, ch=0.003, x=x)
    # side panels (wood on the sport and heritage guns)
    panel = pal["wood"] if pal["_faction"] in ("sport", "heritage", "chrome", "gold") else rub
    for sx in (-1.0, 1.0):
        side_w(g, [(d + 0.004 + dr * 0.1, z_top - 0.012), (d + pw - 0.004 + dr * 0.1, z_top - 0.012), (d + pw - 0.004 + dr * 0.95, z_top - h * 0.93), (d + 0.008 + dr * 0.95, z_top - h * 0.93)], 0.004, panel, ch=0.0008, x=x + sx * (w / 2 + 0.001))
    if g.fine:
        grip_texture(g, d + 0.006 + dr * 0.55, d + pw - 0.002 + dr * 0.55, z_top - h * 0.8, z_top - h * 0.2, x + w / 2 + 0.0016, dk, n=4)
    rbox(g, d + dr - 0.001, d + pw + dr + 0.003, z_top - h - 0.006, z_top - h, w * 1.04, dk, r=0.003, x=x)    # butt cap
    return (d + pw / 2 + dr * 0.5, z_top - h * 0.5)


def trigger_group(g, d, z_top, pal, x=0.0, guard_len=0.06, guard_drop=0.04):
    """Trigger and an open guard (a loop of three thin bars) in front of a grip whose front edge is at distance d, under a receiver whose bottom is z_top."""
    dk = pal["dark"]
    fr = pal["frame"]
    t = 0.0042
    zb = z_top - guard_drop
    rbox(g, d - guard_len, d - guard_len + t, zb, z_top + 0.001, 0.009, fr, r=0.0012, ch=0.0008, x=x)                 # front bar
    rbox(g, d - guard_len, d + 0.002, zb, zb + t, 0.009, fr, r=0.0012, ch=0.0008, x=x)                                # bottom bar
    side_w(g, [(d - guard_len, zb + t), (d - guard_len + t, zb + t + 0.007), (d - guard_len + t + 0.008, zb + t), (d - guard_len + t, zb)], 0.009, fr, ch=0.0008, x=x)   # round the corner
    # the trigger: a curved tongue hanging inside the loop
    side_w(g, [(d - guard_len * 0.62, z_top), (d - guard_len * 0.62 + 0.0055, z_top), (d - guard_len * 0.62 - 0.001, z_top - guard_drop * 0.62), (d - guard_len * 0.62 - 0.0068, z_top - guard_drop * 0.62)],
           0.0055, dk, ch=0.0006, x=x)


# ------------------------------------------------------------------------------------------------------------------------------------------ magazines
def magazine(g, kind, d, z_top, pal, w=0.026, length=0.15, x=0.0, curve=0.0, part=wl.P_MAG, lean=0.0):
    """A magazine inserted at distance d (centre) hanging from z_top. kinds: box, curved, short, long, drum, quad, belt, pistol, tube. Returns the z of the bottom."""
    mt = pal["frame"]
    dk = pal["dark"]
    m2 = pal["metal"]
    with g.in_part(part):
        if kind in ("box", "pistol", "short", "long", "stick", "curved", "banana"):
            L = length * {"short": 0.7, "long": 1.35}.get(kind, 1.0)
            dep = 0.036 if kind in ("box", "long", "stick") else (0.03 if kind in ("short", "pistol") else 0.038)
            bend = curve if kind in ("curved", "banana") else lean
            if kind == "banana":
                bend = max(bend, 0.07)
            if kind == "curved":
                bend = max(bend, 0.035)
            n = 7
            path = []
            for i in range(n):
                t = i / (n - 1)
                path.append((x, -(d + bend * (t ** 2 if bend > 0.03 else t)), z_top - 0.002 - L * t))
            mtl = m2 if kind in ("stick", "pistol") else mt
            g.sweep(path, lambda t: wl.outline_rrect(w * (1.0 - 0.06 * t), dep * (1.0 + 0.05 * t), 0.0045, 1), mtl, up=(1, 0, 0), chamfer=(0.0, 0.0015))
            # floor plate, ribs
            ex = path[-1]
            rbox(g, ex[1] * -1 - dep / 2 - 0.002, ex[1] * -1 + dep / 2 + 0.002, ex[2] - 0.008, ex[2] + 0.002, w * 1.06, dk, r=0.003, x=x)
            if g.fine and kind != "pistol":
                for k in range(3):
                    t = 0.25 + 0.2 * k
                    g.box((x + w * 0.5 * (1 - 0.06 * t) + 0.0005, -(d + bend * (t ** 2 if bend > 0.03 else t)), z_top - 0.002 - L * t), (0.001, dep * 0.7, 0.005), dk)
            return ex[2] - 0.008
        if kind == "drum":
            r = 0.075
            zc = z_top - r - 0.02
            lathe_d(g, [(d - 0.036, r * 0.55), (d - 0.034, r * 0.97), (d - 0.026, r), (d + 0.026, r), (d + 0.034, r * 0.97), (d + 0.036, r * 0.55)], mt, z=zc, x=x, n=20, hard=(1, 4))
            tube(g, d - 0.03, d + 0.03, r * 0.5, dk, z=zc, x=x, n=12)
            # neck
            rbox(g, d - 0.019, d + 0.019, zc + r * 0.55, z_top, w * 0.9, mt, r=0.003, x=x)
            if g.fine:
                for k in range(8):
                    a = 2 * math.pi * k / 8
                    g.box((x + 0.0368, -(d), zc + math.sin(a) * r * 0.78), (0.001, 0.01, 0.01), dk)
                    g.box((x - 0.0368, -(d), zc + math.sin(a) * r * 0.78), (0.001, 0.01, 0.01), dk)
            return zc - r
        if kind == "quad":                                 # a coupled double magazine
            for dx in (-0.028, 0.028):
                magazine(g, "box", d, z_top, pal, w=w * 0.9, length=length, x=x + dx, part=part)
            return z_top - length - 0.01
        if kind == "belt":                                 # box magazine with a feed belt
            bw = 0.07
            rbox(g, d - 0.05, d + 0.05, z_top - 0.12, z_top - 0.005, bw, mt, r=0.006, ch=0.003, x=x, seg=1)
            rbox(g, d - 0.052, d + 0.052, z_top - 0.126, z_top - 0.114, bw * 1.04, dk, r=0.003, x=x)
            if g.fine:
                for k in range(5):
                    g.box((x + bw / 2 + 0.0007, -(d - 0.036 + k * 0.018), z_top - 0.065), (0.0014, 0.008, 0.07), dk)
            # belt arch
            path = [(x, -(d - 0.03 + 0.04 * t), z_top - 0.02 + 0.035 * math.sin(math.pi * t) + 0.03 * t) for t in np.linspace(0, 1, 6)]
            g.sweep(path, lambda t: wl.outline_rrect(0.014, 0.012, 0.002, 1), pal["brass"], up=(1, 0, 0))
            return z_top - 0.126
        if kind == "tube":                                 # tube magazine under the barrel handled by the barrel code
            return z_top
    return z_top - length


def shell_fed_box(g, d0, d1, z_top, pal, x=0.0):
    pass


# ------------------------------------------------------------------------------------------------------------------------------------------ underbarrel and extras
def underbarrel(g, kind, d, z, pal, x=0.0):
    """z = the underside of the handguard. Returns the hand point (d, z) for the support hand."""
    dk = pal["dark"]
    fr = pal["frame"]
    if kind in (None, "none"):
        return (d, z)
    if kind == "vgrip":
        side_w(g, [(d - 0.016, z), (d + 0.016, z), (d + 0.012, z - 0.085), (d - 0.012, z - 0.085)], 0.026, fr, ch=0.003, x=x)
        grip_texture(g, d - 0.01, d + 0.01, z - 0.075, z - 0.012, x + 0.0135, dk, n=4)
        return (d, z - 0.045)
    if kind == "angled":
        side_w(g, [(d - 0.02, z), (d + 0.02, z), (d + 0.045, z - 0.055), (d + 0.04, z - 0.065), (d + 0.02, z - 0.06)], 0.026, fr, ch=0.003, x=x)
        return (d + 0.025, z - 0.035)
    if kind == "stub":
        rbox(g, d - 0.025, d + 0.03, z - 0.032, z, 0.026, fr, r=0.004, x=x)
        return (d, z - 0.02)
    if kind == "bipod":                                    # legs folded forward along the barrel
        rbox(g, d - 0.012, d + 0.012, z - 0.016, z, 0.03, dk, r=0.002, x=x)
        for sx in (-1.0, 1.0):
            g.cyl((x + sx * 0.012, -(d + 0.01), z - 0.012), (x + sx * 0.012, -(d - 0.15), z - 0.016), 0.0032, dk, n=6)
            g.cyl((x + sx * 0.012, -(d - 0.15), z - 0.016), (x + sx * 0.014, -(d - 0.17), z - 0.018), 0.0042, pal["rub"], n=6)
        return (d + 0.05, z)
    if kind == "bipod_open":
        rbox(g, d - 0.012, d + 0.012, z - 0.016, z, 0.03, dk, r=0.002, x=x)
        for sx in (-1.0, 1.0):
            g.cyl((x + sx * 0.012, -d, z - 0.012), (x + sx * 0.085, -(d - 0.03), z - 0.2), 0.0036, dk, n=6)
            g.cyl((x + sx * 0.085, -(d - 0.03), z - 0.2), (x + sx * 0.087, -(d - 0.036), z - 0.215), 0.0055, pal["rub"], n=6)
        return (d + 0.05, z)
    if kind == "launcher":                                 # underbarrel grenade launcher
        tube(g, d - 0.11, d + 0.08, 0.0185, dk, z=z - 0.026, x=x, n=12, ch=0.002)
        tube(g, d - 0.115, d - 0.105, 0.0215, pal["metal"], z=z - 0.026, x=x, n=12)
        rbox(g, d - 0.03, d + 0.05, z - 0.014, z - 0.004, 0.026, dk, r=0.003, x=x)
        side_w(g, [(d + 0.01, z - 0.04), (d + 0.045, z - 0.04), (d + 0.04, z - 0.09), (d + 0.015, z - 0.09)], 0.02, fr, ch=0.002, x=x)
        return (d + 0.03, z - 0.065)
    if kind == "laser":
        rbox(g, d - 0.025, d + 0.025, z - 0.026, z, 0.024, dk, r=0.003, x=x)
        tube(g, d - 0.04, d - 0.024, 0.0095, dk, z=z - 0.016, x=x, n=10)
        tube(g, d - 0.0405, d - 0.0395, 0.007, pal["lens_glow"], z=z - 0.016, x=x, n=10)
        return (d + 0.02, z)
    if kind == "light":
        tube(g, d - 0.05, d + 0.02, 0.0125, dk, z=z - 0.02, x=x, n=12, ch=0.001)
        tube(g, d - 0.062, d - 0.05, 0.0165, pal["metal"], z=z - 0.02, x=x, n=12)
        tube(g, d - 0.0625, d - 0.0615, 0.012, pal["lens_glow"], z=z - 0.02, x=x, n=12)
        return (d + 0.03, z)
    return (d, z)


def side_laser(g, d, z, pal, x=0.0, side_x=1.0):
    dk = pal["dark"]
    rbox(g, d - 0.022, d + 0.022, z - 0.011, z + 0.011, 0.02, dk, r=0.003, x=x + side_x * 0.03)
    tube(g, d - 0.034, d - 0.02, 0.0075, dk, z=z, x=x + side_x * 0.03, n=8)
    tube(g, d - 0.0345, d - 0.0335, 0.005, pal["lens_glow"], z=z, x=x + side_x * 0.03, n=8)
