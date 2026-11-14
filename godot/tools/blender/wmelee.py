"""Melee weapons and hand devices (grenades, mines, strike designators) of the weapon kit (wave 114). Melee: the blade or head points to the front (tip / head at d = 0), the hilt and haft run back,
the hands (markers gr, gl) sit on the haft. Devices are small objects held in one hand: body centred about d = 0.12."""
import math

import numpy as np

import weaponlib as wl
import weapon_mats as M
from weaponlib import Style
import wparts as wp
from wparts import rbox, tube, lathe_d, side_w, side, screw, seam, serrate, vent_row, rail, muzzle_device, optic
import wexotic as we


def blade_path(Lb, bow=0.0, rise=0.0, n=9):
    """Centre line of a blade from the tip (d = 0) back to the base (d = Lb): the tip curves up by `rise`, `bow` bulges the middle."""
    pts = []
    for i in range(n):
        t = i / (n - 1)                      # 0 at the tip, 1 at the base
        pts.append((0.0, -(Lb * t), rise * (1.0 - t) ** 2 + bow * math.sin(math.pi * t)))
    return pts


def blade(g, st, Lb, w, th, bow=0.0, rise=0.0, edge=-1.0, spine=0.0, base_w=None, tip=0.1, chamfer=0.0, back_st=None, glow=None, path=None):
    """A blade swept along a curved path, tapering to a point; the cutting edge on the side `edge` (-1 down). `tip` = share of the length over which it narrows. t = 0 at the tip."""
    base_w = w if base_w is None else base_w
    if path is None:
        path = blade_path(Lb, bow, rise)

    def outline(t):
        # t = 0 at the tip: width tapers over the first `tip` of the length
        k = min(1.0, t / max(tip, 0.01)) ** 0.8 if t < tip else 1.0
        ww = (w + (base_w - w) * t) * max(k, 0.02)
        tt = th * max(k, 0.15)
        e = edge
        pts = [(e * ww * 0.5, 0.0), (e * ww * 0.18, tt * 0.5), (-e * ww * 0.5, tt * 0.5 * (0.6 if spine else 1.0)), (-e * ww * 0.5, -tt * 0.5 * (0.6 if spine else 1.0)), (e * ww * 0.18, -tt * 0.5)]
        if e < 0:
            pts = pts[::-1]
        return wl.outline_poly(pts, hard=True)

    g.sweep(path, outline, st, up=(1, 0, 0), caps=(False, True))
    # a fuller (groove) down the middle as a thin dark strip
    if g.fine and Lb > 0.2:
        ys = [-(Lb * 0.18), -(Lb * 0.78)]
        zc = rise * (1 - 0.5) ** 2 + bow
        g.box((th * 0.5 + 0.0003, (ys[0] + ys[1]) / 2, -edge * w * 0.12), (0.0012, abs(ys[1] - ys[0]), w * 0.16), (back_st or st).t(tint=tuple(c * 0.55 for c in st.tint)))


def hilt(g, pal, d0, L, r=0.0125, wrap=True, guard=None, pommel=True, guard_w=0.1, st=None, z=0.0):
    """A grip from d0 to d0 + L (tube, with a wrap pattern), a guard at d0 and a pommel at the end."""
    dk = pal["dark"]
    grip = st or (pal["leather"] if wrap else pal["rub"])
    tube(g, d0, d0 + L, r, grip, z=z, n=10, ch=0.001)
    if g.fine and wrap:
        for k in range(int(L / 0.014)):
            d = d0 + 0.008 + k * 0.014
            if d + 0.004 > d0 + L:
                break
            tube(g, d, d + 0.003, r * 1.06, dk, z=z, n=10)
    if guard == "cross":
        rbox(g, d0 - 0.014, d0, z - 0.012, z + 0.012, guard_w, pal["metal"], r=0.003, ch=0.002)
    elif guard == "disc":
        tube(g, d0 - 0.008, d0, guard_w * 0.5, pal["metal"], z=z, n=16, ch=0.001)
    elif guard == "knuckle":
        rbox(g, d0 - 0.012, d0, z - 0.012, z + 0.012, guard_w * 0.8, pal["metal"], r=0.003, ch=0.002)
        path = [(0.0, -(d0 - 0.002), z - 0.012), (0.0, -(d0 + L * 0.35), z - 0.034), (0.0, -(d0 + L * 0.75), z - 0.02)]
        g.sweep(path, lambda t: wl.outline_circle(0.0036, 8), pal["metal"], up=(1, 0, 0))
    elif guard == "hook":
        rbox(g, d0 - 0.012, d0, z - 0.016, z + 0.016, guard_w * 0.5, pal["metal"], r=0.003, ch=0.002)
    if pommel:
        g.sphere((0.0, -(d0 + L + 0.008), z), r * 1.35, pal["metal"], n=8, squash=(1.0, 0.7, 1.0))


def melee(g, pal, s):
    kind = s.get("kind", "dagger")
    bd, dk, mt, fr, ac, gl, wd, lt, br, hz = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"], pal["furn"], pal["leather"], pal["bright"], pal["hazard"]
    steel = Style(M.ALLOY, (0.62, 0.64, 0.68)) if pal["_faction"] not in ("chrome", "gold") else pal["chrome"]       # blades: brushed alloy, the streaks run along the edge
    edge_glow = pal["glow"]
    cx = 0.0
    out = {}
    Lh = s.get("hilt", 0.2)
    if kind == "dagger" or kind == "hook" or kind == "machete" or kind == "katana" or kind == "cutlass" or kind == "chop":
        Lb = s.get("blade", {"dagger": 0.2, "hook": 0.2, "machete": 0.5, "katana": 0.72, "cutlass": 0.6, "chop": 0.4}[kind])
        w = {"dagger": 0.034, "hook": 0.03, "machete": 0.065, "katana": 0.032, "cutlass": 0.05, "chop": 0.06}[kind]
        rise = {"dagger": 0.0, "hook": -0.04, "machete": 0.012, "katana": 0.035, "cutlass": 0.05, "chop": 0.0}[kind]
        for xx in (s.get("xs", (0.0,))):
            with g.at((xx, 0.0, 0.0)):
                st_b = steel if kind not in ("cutlass",) else Style(M.STEEL_BRIGHT, (0.6, 0.62, 0.66))
                blade(g, st_b, Lb, w, 0.0075 if kind != "machete" else 0.0045, bow=0.0, rise=rise, edge=-1.0, tip=0.14 if kind != "hook" else 0.2, spine=1.0 if kind in ("katana", "machete") else 0.0)
                if kind in ("cutlass",) or s.get("glow"):                       # an energy edge along the blade
                    blade(g, edge_glow, Lb * 0.96, w * 0.3, 0.002, bow=0.0, rise=rise, edge=-1.0, tip=0.14) if False else None
                    g.box((0.0045, -(Lb * 0.55), -w * 0.5 + 0.004 + rise * 0.0), (0.0016, Lb * 0.84, 0.006), edge_glow)
                    g.box((-0.0045, -(Lb * 0.55), -w * 0.5 + 0.004), (0.0016, Lb * 0.84, 0.006), edge_glow)
                if kind == "hook":                                                   # the hook: a curved extension at the tip
                    path = [(0.0, -0.02, -0.01), (0.0, 0.0, -0.025), (0.0, 0.012, -0.05), (0.0, 0.01, -0.075)]
                    g.sweep(path, lambda t: wl.outline_rrect(0.006, 0.0075 * (1 - 0.5 * t), 0.001, 1), steel, up=(1, 0, 0))
                guard = "cross" if kind in ("dagger",) else ("disc" if kind in ("katana",) else ("knuckle" if kind in ("cutlass", "machete") else "hook"))
                hilt(g, pal, Lb, Lh if kind != "dagger" else 0.12, r=0.0125, guard=guard, guard_w=0.11 if kind == "dagger" else (0.07 if kind == "katana" else 0.085), z=0.0)
            g.mark("gr" if xx >= 0 else "gl", (xx, -(Lb + (Lh if kind != "dagger" else 0.12) * 0.28), 0.0))
        Lt = Lb + (Lh if kind != "dagger" else 0.12) + 0.02
        gr = (0.0, -(Lb + (Lh if kind != "dagger" else 0.12) * 0.3), 0.0)
        gl_ = (0.0, -(Lb + (Lh if kind != "dagger" else 0.12) * 0.78), 0.0)
        if len(s.get("xs", (0.0,))) == 1:
            g.mark("gr", gr)
            g.mark("gl", gl_)
        out = {"length": Lt}
    elif kind in ("axe", "hatchet", "greataxe", "sledge", "mallet", "crowbar", "maul", "pickaxe"):
        H = s.get("haft", {"axe": 0.8, "hatchet": 0.4, "greataxe": 1.1, "sledge": 0.95, "mallet": 0.55, "crowbar": 0.8, "maul": 0.9, "pickaxe": 0.85}[kind])
        r = {"axe": 0.0165, "hatchet": 0.0145, "greataxe": 0.019, "sledge": 0.018, "mallet": 0.016, "crowbar": 0.0095, "maul": 0.02, "pickaxe": 0.0165}[kind]
        # the haft runs from d = hd0 (just behind the head) back to hd0 + H
        hd0 = {"axe": 0.06, "hatchet": 0.05, "greataxe": 0.09, "sledge": 0.09, "mallet": 0.07, "crowbar": 0.0, "maul": 0.1, "pickaxe": 0.07}[kind]
        if kind == "crowbar":                                    # a steel bar with a hooked end and a flat claw end
            g.cyl((0.0, -hd0 - 0.04, 0.0), (0.0, -(hd0 + H), 0.0), r, steel, n=12)
            for dd in (0.2, 0.35, 0.5):
                tube(g, dd, dd + 0.006, r * 1.18, dk, n=12)
            tube(g, hd0 + H * 0.5, hd0 + H * 0.5 + 0.22, r * 1.14, pal["rub"], n=12)
            path = [(0.0, -0.06, 0.0), (0.0, -0.01, -0.012), (0.0, 0.015, -0.05), (0.0, 0.006, -0.085)]
            g.sweep(path, lambda t: wl.outline_rrect(0.019 - 0.008 * t, 0.012, 0.0025, 1), steel, up=(1, 0, 0))
            rbox(g, hd0 + H - 0.06, hd0 + H + 0.012, -0.01, 0.012, 0.03, steel, r=0.003, ch=0.003)
            if g.fine:
                g.box((0.0, -(hd0 + H + 0.006), 0.0), (0.006, 0.014, 0.003), dk)
        else:
            tube(g, hd0 - 0.04, hd0 + H, r, wd if kind not in ("sledge", "greataxe", "maul") else (pal["fr"] if "fr" in pal else fr), n=10, ch=0.002) if kind in ("axe", "hatchet", "mallet", "pickaxe") else \
                g.cyl((0.0, -(hd0 - 0.04), 0.0), (0.0, -(hd0 + H), 0.0), r, mt, n=10, chamfer=0.002)
            if g.fine and kind in ("sledge", "greataxe", "maul"):                     # a rubber / wrapped grip on the lower third
                tube(g, hd0 + H * 0.6, hd0 + H, r * 1.12, pal["rub"], n=10, ch=0.001)
            g.sphere((0.0, -(hd0 + H + 0.01), 0.0), r * 1.25, mt if kind != "mallet" else wd, n=8, squash=(1.0, 0.7, 1.0))
        if kind in ("axe", "hatchet", "greataxe"):
            hw = {"axe": 0.17, "hatchet": 0.11, "greataxe": 0.3}[kind]               # height of the bit
            hl = {"axe": 0.1, "hatchet": 0.075, "greataxe": 0.12}[kind]             # how far the cheek runs forward
            up = [(hd0 + 0.05, 0.03), (hd0 + 0.0, 0.034), (hd0 - hl * 0.5, 0.036), (hd0 - hl, hw * 0.5), (hd0 - hl * 0.92, hw * 0.28), (hd0 - hl * 0.1, 0.03)]
            if kind == "greataxe":
                up = [(hd0 + 0.06, 0.032), (hd0 - 0.01, 0.04), (hd0 - hl * 0.8, hw * 0.34), (hd0 - hl, hw * 0.5), (hd0 - hl * 0.55, hw * 0.52), (hd0 + 0.04, hw * 0.2)]
            if kind == "greataxe":
                poly = up + [(d, -z) for (d, z) in reversed(up)]                       # a double bit, mirrored below the haft
            else:
                poly = [(d, z + 0.0) for (d, z) in up] + [(d, -z * (0.35 if kind == "axe" else 0.55)) for (d, z) in reversed(up)]   # a single bit, the poll below is short
            side_w(g, poly, 0.013 if kind != "greataxe" else 0.017, steel, ch=0.0035)
            if g.fine:
                for sz in ((1.0, -1.0) if kind == "greataxe" else (1.0,)):
                    g.box((0.0072 if kind != "greataxe" else 0.0095, -(hd0 - hl * 0.7), sz * hw * 0.36), (0.0014, hl * 0.5, 0.012), edge_glow if kind == "greataxe" else dk)
                    g.box((-0.0072 if kind != "greataxe" else -0.0095, -(hd0 - hl * 0.7), sz * hw * 0.36), (0.0014, hl * 0.5, 0.012), edge_glow if kind == "greataxe" else dk)
            rbox(g, hd0 - 0.03, hd0 + 0.06, -0.026, 0.026, 0.024, mt, r=0.004, ch=0.003)                       # the eye
            if kind == "axe":
                rbox(g, hd0 + 0.05, hd0 + 0.1, -0.016, 0.016, 0.018, mt, r=0.003, ch=0.002)                  # poll
            for dd in (hd0 + 0.07, hd0 + 0.1):
                tube(g, dd, dd + 0.004, r * 1.2, dk, n=10)
        elif kind in ("sledge", "maul", "mallet"):
            hl = {"sledge": 0.16, "maul": 0.14, "mallet": 0.17}[kind]
            hr = {"sledge": 0.05, "maul": 0.07, "mallet": 0.045}[kind]
            hs = steel if kind != "mallet" else wd
            if kind == "mallet":
                tube(g, hd0 - hl, hd0 + 0.0, hr, wd, z=0.0, x=0.0, n=14, ch=0.005)
                tube(g, hd0 - hl - 0.002, hd0 - hl + 0.014, hr * 1.04, mt, n=14)
                tube(g, hd0 - 0.014, hd0 + 0.002, hr * 1.04, mt, n=14)
            else:
                rbox(g, hd0 - hl, hd0 + 0.02, -hr, hr, hr * 2.0, hs if kind == "sledge" else mt, r=0.012, ch=0.008, seg=2)
                rbox(g, hd0 - hl - 0.01, hd0 - hl + 0.014, -hr * 1.02, hr * 1.02, hr * 2.04, dk, r=0.008, ch=0.004)
                rbox(g, hd0 + 0.006, hd0 + 0.03, -hr * 1.02, hr * 1.02, hr * 2.04, dk, r=0.008, ch=0.004)
                if kind == "maul":
                    for sx in (-1.0, 1.0):
                        g.cyl((sx * (hr + 0.002), -(hd0 - hl * 0.5), 0.0), (sx * (hr + 0.03), -(hd0 - hl * 0.5), 0.0), 0.022, edge_glow, n=12)
                    g.box((0.0, -(hd0 - hl - 0.012), 0.0), (hr * 1.4, 0.006, hr * 1.4), edge_glow)
        elif kind == "pickaxe":
            path = [(0.0, -(hd0 - 0.12), -0.08), (0.0, -(hd0 - 0.05), -0.03), (0.0, -hd0, 0.0), (0.0, -(hd0 + 0.05), -0.03), (0.0, -(hd0 + 0.12), -0.08)]
            g.sweep(path, lambda t: wl.outline_rrect(0.022 * (1 - 0.6 * abs(t - 0.5) * 2) + 0.006, 0.02, 0.003, 1), steel, up=(1, 0, 0))
        out = {"length": hd0 + H + 0.02}
        gr = (0.0, -(hd0 + H * 0.72), 0.0)
        gl_ = (0.0, -(hd0 + H * 0.4), 0.0) if kind not in ("hatchet", "crowbar") else (0.0, -(hd0 + H * 0.6), 0.0)
        g.mark("gr", gr)
        g.mark("gl", gl_)
    elif kind in ("spear", "staff", "scythe"):
        H = s.get("haft", {"spear": 1.15, "staff": 1.1, "scythe": 1.15}[kind])
        r = 0.0135
        g.cyl((0.0, -0.0, 0.0), (0.0, -H, 0.0), r, wd, n=10, chamfer=0.001)
        if kind == "spear":
            lathe_d(g, [(-0.2, 0.0006), (-0.17, 0.016), (-0.07, 0.016), (-0.02, 0.0115), (0.0, 0.0115)], steel, n=4, hard=(1, 2)) if False else None
            side_w(g, [(-0.001, 0.0), (0.06, 0.023), (0.14, 0.028), (0.19, 0.0), (0.14, -0.028), (0.06, -0.023)], 0.006, steel, ch=0.0015)
            tube(g, 0.19, 0.215, r * 1.5, mt, n=12)
            tube(g, 0.25, 0.262, r * 1.3, ac, n=12)
            for sz in (-1.0, 1.0):
                side_w(g, [(0.17, sz * 0.012), (0.2, sz * 0.03), (0.215, sz * 0.012)], 0.006, steel, ch=0.001)                # barbs at the base of the blade
            g.box((0.0035, -0.1, 0.0), (0.0014, 0.12, 0.01), pal["glow"] if False else dk)
            for k in range(5):
                tube(g, 0.3 + k * 0.05, 0.3 + k * 0.05 + 0.02, r * 1.1, lt, n=12)
            g.cyl((0.0, -(H - 0.0), 0.0), (0.0, -(H + 0.05), 0.0), 0.006, mt, r1=0.0015, n=6)
            if g.fine:
                tube(g, 0.22, 0.235, r * 1.4, lt, n=10)
        elif kind == "staff":
            for dd in (0.0, 0.06, H * 0.5, H - 0.06, H):
                tube(g, dd, dd + 0.025, r * 1.4, mt, n=10, ch=0.001)
            g.sphere((0.0, 0.02, 0.0), 0.034, edge_glow, n=10)
            for k in range(3):
                ring_a = 0.05 + k * 0.012
            tube(g, 0.0, 0.04, 0.026, dk, n=10)
            for dd in (H * 0.28, H * 0.72):
                tube(g, dd, dd + 0.12, r * 1.18, lt, n=10)
                g.torus((0.0, -(dd + 0.06), 0.0), r * 1.2, 0.0022, edge_glow, n=12, m=5, axis="y")
        else:                                                                         # scythe: a crescent blade rising from the front of the haft and arcing forward
            R = 0.34
            arc = []
            for i in range(11):
                a_ = math.radians(8 + 100 * i / 10.0)
                arc.append((0.0, 0.03 + R * math.sin(a_) * 0.9 - 0.0, 0.02 + R * (1 - math.cos(a_)) * 1.05))
            tip_first = arc[::-1]                                                      # blade_path runs from the tip back to the base
            blade(g, steel, 0.5, 0.075, 0.007, edge=1.0, tip=0.35, base_w=0.085, path=tip_first)
            blade(g, edge_glow, 0.5, 0.02, 0.0095, edge=1.0, tip=0.35, base_w=0.026, path=tip_first) if False else None
            rbox(g, -0.02, 0.07, -0.03, 0.05, 0.034, mt, r=0.006, ch=0.004)             # socket where the blade meets the haft
            g.sphere((0.0, -0.0, 0.0), 0.0, mt, n=4) if False else None
            for k in range(3):
                zz = 0.1 + 0.1 * k
                g.box((0.0045, 0.03 + R * math.sin(math.radians(30 + 28 * k)) * 0.9, 0.02 + R * (1 - math.cos(math.radians(30 + 28 * k))) * 1.05), (0.0014, 0.03, 0.01), edge_glow)
            tube(g, H * 0.5, H * 0.58, r * 1.25, lt, n=10)
            tube(g, H * 0.8, H * 0.86, r * 1.25, lt, n=10)
        out = {"length": H + 0.02}
        g.mark("gr", (0.0, -H * (0.74 if kind != "staff" else 0.66), 0.0))
        g.mark("gl", (0.0, -H * (0.5 if kind != "staff" else 0.38), 0.0))
    elif kind in ("sabre", "arcsabre", "phaseblade", "qblade", "eblade", "blink", "pblade"):
        Lb = s.get("blade", 0.85)
        # emitter hilt (a metal hilt with a guard) and a glowing blade (core layer, additive look through emission)
        hl_ = s.get("hilt", 0.26)
        w = s.get("width", 0.038)
        hilt(g, pal, Lb, hl_, r=0.0155, wrap=False, guard="cross", guard_w=0.085, st=pal["rub"], pommel=True)
        tube(g, Lb - 0.03, Lb + 0.005, 0.0205, mt, n=12, ch=0.002)
        if g.fine:
            for k in range(3):
                tube(g, Lb + 0.05 + k * 0.045, Lb + 0.053 + k * 0.045, 0.0165, mt, n=12)
        rise = 0.0 if kind in ("sabre", "eblade") else 0.03
        blade(g, edge_glow, Lb, w, 0.011, rise=rise, edge=-1.0, tip=0.1)
        blade(g, pal["glow"].t(tint=(1.0, 1.0, 1.0)), Lb * 0.98, w * 0.5, 0.013, rise=rise, edge=-1.0, tip=0.1) if kind in ("phaseblade", "blink") else None
        if kind == "phaseblade":                                                             # drifting shards
            for k in range(4):
                g.box((0.0, -(Lb * (0.12 + 0.22 * k)), -(w * 0.5 + 0.02 + (k % 2) * 0.02)), (0.008, 0.05, 0.012), edge_glow)
        if kind == "arcsabre":                                                              # a second small blade (a crossguard blade)
            for sx in (-1.0, 1.0):
                g.cyl((sx * 0.02, -(Lb + 0.01), 0.0), (sx * 0.1, -(Lb + 0.01), 0.0), 0.0045, edge_glow, n=6)
        out = {"length": Lb + hl_ + 0.03}
        g.mark("gr", (0.0, -(Lb + hl_ * 0.32), 0.0))
        g.mark("gl", (0.0, -(Lb + hl_ * 0.78), 0.0))
    elif kind in ("baton", "tonfa", "whip", "chainwhip", "chainblade"):
        if kind == "baton":
            L = 0.7
            g.cyl((0.0, 0.0, 0.0), (0.0, -L, 0.0), 0.0145, dk, n=10, chamfer=0.002)
            for k in range(4):
                tube(g, 0.0 + 0.04 + k * 0.05, 0.0 + 0.052 + k * 0.05, 0.017, edge_glow, n=10) if k < 3 else None
            g.sphere((0.0, 0.01, 0.0), 0.02, edge_glow, n=8)
            for sx in (-1.0, 1.0):
                g.cyl((sx * 0.012, -0.0, 0.0), (sx * 0.012, -0.05, 0.0), 0.004, mt, n=6)
            hilt(g, pal, L * 0.55, L * 0.45, r=0.017, wrap=False, guard="disc", guard_w=0.034, st=pal["rub"])
            g.mark("gr", (0.0, -(L * 0.72), 0.0))
            g.mark("gl", (0.0, -(L * 0.9), 0.0))
            out = {"length": L + 0.02}
        elif kind == "tonfa":
            # a short bar with a perpendicular side handle
            g.cyl((0.0, -0.02, 0.0), (0.0, -0.5, 0.0), 0.0165, dk, n=10, chamfer=0.002)
            rbox(g, 0.0, 0.05, -0.018, 0.018, 0.04, pal["rub"], r=0.006, ch=0.003)
            g.cyl((0.0, -0.18, 0.0), (0.0, -0.18, -0.12), 0.0145, pal["rub"], n=10, chamfer=0.002)
            g.cyl((0.0, -0.17, -0.12), (0.0, -0.2, -0.12), 0.02, mt, n=10)
            g.box((0.0, -0.24, 0.0175), (0.003, 0.2, 0.004), edge_glow)
            g.mark("gr", (0.0, -0.18, -0.1))
            g.mark("gl", (0.0, -0.4, 0.0))
            out = {"length": 0.52}
        elif kind == "whip":                                                                # arc whip: a handle and a coiled glowing lash
            hilt(g, pal, 0.0, 0.22, r=0.017, wrap=True, guard="disc", guard_w=0.04)
            pts = [(0.0, -(0.22 + 0.04 * t), 0.0) for t in (0, 1)]
            path = [(0.0, -(0.22 + 0.06 * t), 0.04 * math.sin(t * 6.0) * t) for t in np.linspace(0, 1, 14)]
            path = [(0.0, -(0.22 - 0.0 * t) + 0.0, 0.0) for t in (0, 1)]
            lash = [(0.0, 0.0 + 0.5 * (1 - t), 0.03 * math.sin(t * 9) * (1 - t) + 0.0) for t in np.linspace(0, 1, 16)]
            lash = [(0.02 * math.sin(t * 11) * (1 - t * 0.6), 0.22 * (1 - t) * -1.0 + 0.0, 0.1 * math.sin(t * 5) * t) for t in np.linspace(0, 1, 18)]
            lash = [(0.025 * math.sin(t * 12) * t, -(0.22 + 0.0) + 0.55 * t, 0.05 * math.sin(t * 7) * t * 1.0) for t in np.linspace(0, 1, 18)]
            g.sweep(lash, lambda t: wl.outline_circle(0.007 * (1 - 0.7 * t) + 0.002, 8), edge_glow)
            g.sphere(lash[-1], 0.009, br, n=6)
            g.mark("gr", (0.0, -0.08, 0.0))
            g.mark("gl", (0.0, -0.17, 0.0))
            out = {"length": 0.26}
        elif kind == "chainwhip":
            hilt(g, pal, 0.0, 0.22, r=0.017, wrap=True, guard="disc", guard_w=0.045)
            n = 24
            pts = []
            for k in range(n):
                t = k / (n - 1)
                pts.append(np.array([0.025 * math.sin(t * 11) * t, -0.22 + 0.72 * t, 0.07 * math.sin(t * 6) * t]))
            for k in range(n - 1):
                tg = pts[k + 1] - pts[k]
                tg = tg / max(np.linalg.norm(tg), 1e-9)
                ux = wl.unit(np.cross(tg, wl.Z_AX if abs(tg[2]) < 0.9 else wl.X_AX))
                uz = np.cross(ux, tg)
                if k % 2:
                    ux, uz = uz, -ux
                Rm = np.stack([ux, tg, uz], axis=1)
                with g.at(tuple((pts[k] + pts[k + 1]) / 2), R=Rm):
                    g.box((0.0, 0.0, 0.0), (0.016, 0.03, 0.0065), steel, r=0.0015, chamfer=0.001, axis="y")
                    g.box((0.0, 0.0, 0.0), (0.009, 0.03, 0.0090), dk, axis="y") if g.fine and k % 3 == 0 else None
            g.sphere(tuple(pts[-1]), 0.022, mt, n=8)
            if g.fine:
                for k in range(6):
                    a_ = k * math.pi / 3
                    g.cyl(tuple(pts[-1] + np.array([math.cos(a_) * 0.018, 0.0, math.sin(a_) * 0.018])), tuple(pts[-1] + np.array([math.cos(a_) * 0.034, 0.012, math.sin(a_) * 0.034])), 0.004, mt, r1=0.0015, n=5)
            g.mark("gr", (0.0, -0.08, 0.0))
            g.mark("gl", (0.0, -0.17, 0.0))
            out = {"length": 0.26}
        else:                                                                               # chainblade: a motor housing and a toothed loop around a blade
            Lb = 0.62
            rbox(g, Lb, Lb + 0.2, -0.035, 0.035, 0.06, pal["body"], r=0.01, ch=0.004, seg=2)
            rbox(g, Lb - 0.01, Lb + 0.01, -0.035, 0.035, 0.07, dk, r=0.005)
            side_w(g, [(0.0, 0.0), (0.02, 0.035), (Lb, 0.04), (Lb, -0.04), (0.02, -0.035)], 0.016, mt, ch=0.003)
            # toothed edge and the glowing channel
            if g.fine:
                for k in range(int((Lb - 0.06) / 0.022)):
                    d = 0.05 + k * 0.022
                    for sz in (1.0, -1.0):
                        g.box((0.0, -d, sz * 0.043), (0.012, 0.01, 0.008), steel)
            g.box((0.0, -(Lb * 0.5), 0.0), (0.018, Lb * 0.9, 0.012), edge_glow) if False else None
            g.box((0.0088, -(Lb * 0.5), 0.0), (0.0016, Lb * 0.8, 0.01), edge_glow)
            g.box((-0.0088, -(Lb * 0.5), 0.0), (0.0016, Lb * 0.8, 0.01), edge_glow)
            hilt(g, pal, Lb + 0.2, 0.2, r=0.017, wrap=False, guard="knuckle", guard_w=0.05, st=pal["rub"])
            g.mark("gr", (0.0, -(Lb + 0.28), 0.0))
            g.mark("gl", (0.0, -(Lb + 0.1), -0.04))
            out = {"length": Lb + 0.4}
    elif kind == "gauntlet":                                                                # a power fist: forearm shell, curled finger blocks, thumb, wrist emitter
        we.fuselage(g, [(0.12, 0.1, 0.1, 0.0, 0.02), (0.22, 0.115, 0.11, 0.004, 0.022), (0.36, 0.1, 0.095, 0.0, 0.02), (0.5, 0.078, 0.075, -0.004, 0.016)], bd)
        for k in range(4):                                                                  # four finger blocks curled over the front
            x = -0.045 + k * 0.03
            rbox(g, 0.0, 0.09, 0.012 - 0.006 * abs(k - 1.5), 0.05, 0.027, pal["metal"], r=0.006, ch=0.004, x=x)
            rbox(g, 0.0, 0.04, -0.03, 0.016, 0.027, dk, r=0.005, ch=0.003, x=x)
            g.box((x, -0.002, 0.03), (0.02, 0.006, 0.016), edge_glow) if g.fine else None
        side_w(g, [(0.07, -0.02), (0.15, -0.05), (0.2, -0.07), (0.12, -0.075), (0.06, -0.04)], 0.032, pal["metal"], ch=0.004, x=0.062)      # the thumb
        for sx in (-1.0, 1.0):
            g.box((sx * 0.0585, -0.3, 0.0), (0.0015, 0.12, 0.036), edge_glow)
            vent_row(g, 0.16, 0.32, -0.03, 0.058 * sx, dk, n=4, h=0.03, w=0.01, both=False)
        g.cyl((0.0, -0.1, 0.055), (0.0, -0.22, 0.062), 0.022, edge_glow, n=12)
        rbox(g, 0.22, 0.34, 0.05, 0.075, 0.06, dk, r=0.006, ch=0.004)
        rbox(g, 0.34, 0.6, -0.04, 0.036, 0.088, pal["rub"], r=0.01, ch=0.004)
        g.cyl((0.0, -0.2, -0.05), (0.0, -0.22, -0.11), 0.02, pal["rub"], n=8)
        g.mark("gr", (0.0, -0.22, -0.09))
        g.mark("gl", (0.0, -0.36, 0.0))
        out = {"length": 0.6}
    elif kind == "shield":
        # a riot shield: a curved plate in front of the hero with a visor window and a grip behind
        path = []
        for i in range(9):
            t = i / 8.0 - 0.5
            path.append((t * 0.36, -(0.06 + 0.07 * (1 - 4 * t * t) * -1.0) * 0.0 - 0.07 * (1 - 4 * t * t), 0.0))
        def sec(t):
            return wl.outline_rrect(0.012, 0.74, 0.004, 1)
        g.sweep(path, lambda t: wl.outline_rrect(0.74, 0.012, 0.004, 1), bd, up=(0, 1, 0), chamfer=(0.002, 0.002))
        g.box((0.0, -0.07, 0.19), (0.3, 0.012, 0.09), pal["lens_glow"])
        for sx in (-1.0, 1.0):
            g.box((sx * 0.165, -0.1, 0.0), (0.012, 0.012, 0.72), mt)
        g.box((0.0, -0.19, 0.0), (0.02, 0.16, 0.02), dk) if False else None
        g.cyl((0.0, -0.1, 0.06), (0.0, -0.22, 0.06), 0.012, pal["rub"], n=8)
        g.cyl((0.0, -0.1, -0.06), (0.0, -0.22, -0.06), 0.012, pal["rub"], n=8)
        g.cyl((-0.06, -0.19, 0.0), (0.06, -0.19, 0.0), 0.012, pal["rub"], n=8)
        g.mark("gr", (0.0, -0.19, 0.0))
        g.mark("gl", (0.0, -0.19, 0.0))
        out = {"length": 0.24}
    elif kind == "bat":
        L = 0.9
        lathe_d(g, [(0.0, 0.034), (0.03, 0.038), (0.22, 0.035), (0.5, 0.022), (0.84, 0.0125), (0.9, 0.016)], wd, n=14, hard=())
        lathe_d(g, [(0.84, 0.0128), (0.9, 0.017)], pal["rub"], n=12) if False else None
        tube(g, 0.48, 0.9, 0.0155, pal["rub"], n=12, ch=0.001)
        g.sphere((0.0, -0.905, 0.0), 0.021, dk, n=8, squash=(1.0, 0.6, 1.0))
        if g.fine:
            for k in range(6):
                ang = k * math.pi / 3
                g.box((math.cos(ang) * 0.037, -0.11 - 0.0 * k, math.sin(ang) * 0.037), (0.004, 0.18, 0.004), dk)
        g.mark("gr", (0.0, -0.78, 0.0))
        g.mark("gl", (0.0, -0.6, 0.0))
        out = {"length": 0.92}
    elif kind == "knives":                                                                  # throwing knives: a fan of three
        for k, ang in enumerate((-18, 0, 18)):
            with g.at((0.0, 0.0, 0.0), rot=(0, ang, 0)):
                with g.at((0.0, -0.02, 0.0)):
                    blade(g, steel, 0.17, 0.028, 0.005, rise=0.0, edge=-1.0, tip=0.25)
                    hilt(g, pal, 0.17, 0.1, r=0.01, guard="cross", guard_w=0.05)
        g.mark("gr", (0.0, -0.3, 0.0))
        g.mark("gl", (0.0, -0.33, 0.0))
        out = {"length": 0.34}
    else:
        g.box((0.0, -0.4, 0.0), (0.04, 0.8, 0.04), steel)
        g.mark("gr", (0.0, -0.6, 0.0))
        g.mark("gl", (0.0, -0.7, 0.0))
        out = {"length": 0.82}
    # shared markers for the effects
    gr_m = g.markers.get("gr", (0.0, -0.5, 0.0))
    g.mark("eject", (0.0, -0.3, 0.0))
    g.mark("mag", (0.0, -0.3, 0.0))
    g.mark("aim", (0.0, -0.1, 0.05))
    g.mark("optic", (0.0, -0.1, 0.05))
    g.mark("laser", (0.0, 0.0, 0.0))
    out.setdefault("butt", out.get("length", 0.5))
    out.setdefault("muz_ext", 0.0)
    out.setdefault("grip_d", -gr_m[1])
    return out


# ---------------------------------------------------------------------------------------------------------------------------------------- hand devices
def device(g, pal, s):
    """Grenades, mines and strike designators held in one hand. s['kind']."""
    kind = s.get("kind", "frag")
    bd, dk, mt, fr, ac, gl, hz, br = pal["body"], pal["dark"], pal["metal"], pal["frame"], pal["accent"], pal["glow"], pal["hazard"], pal["bright"]
    cd = 0.12                                                               # body centre distance
    out = {"length": 0.24, "butt": 0.24}
    if kind == "frag":                                                      # an ovoid with a lever and a pin ring
        g.sphere((0.0, -cd, 0.0), 0.04, bd, n=14, squash=(1.0, 1.1, 1.0))
        if g.fine:
            for k in range(7):
                for j in range(6):
                    a = 2 * math.pi * j / 6 + k * 0.5
                    zz = math.sin(a) * 0.04
                    g.box((math.cos(a) * 0.041, -(cd - 0.04 + 0.0135 * k), zz), (0.004, 0.003, 0.004), dk) if k % 2 == 0 else None
        tube(g, cd - 0.04, cd - 0.03, 0.016, mt, n=10)
        rbox(g, cd - 0.08, cd - 0.03, 0.036, 0.05, 0.014, mt, r=0.002)
        g.sphere((0.0, -(cd + 0.0), 0.058), 0.0, mt, n=4) if False else None
        g.torus((0.014, -(cd - 0.06), 0.056), 0.011, 0.0016, br, n=10, m=5, axis="x")
        side_w(g, [(cd - 0.035, 0.036), (cd + 0.02, 0.036), (cd + 0.045, -0.006), (cd + 0.02, 0.012), (cd - 0.035, 0.044)], 0.008, mt, ch=0.0008) if False else None
    elif kind == "tick":                                                    # a rounded body with little legs
        g.sphere((0.0, -cd, 0.0), 0.04, bd, n=12, squash=(1.1, 1.0, 0.8))
        g.sphere((0.0, -(cd - 0.045), 0.0), 0.016, gl, n=8)
        for k in range(8):
            a = 2 * math.pi * k / 8
            g.cyl((math.cos(a) * 0.036, -(cd + math.sin(a) * 0.03), -0.01), (math.cos(a) * 0.075, -(cd + math.sin(a) * 0.06), -0.03), 0.0045, dk, r1=0.003, n=6)
    elif kind == "scatter":                                                 # a cluster of small bomblets in a cage
        for k in range(7):
            a = 2 * math.pi * k / 6
            p = (math.cos(a) * 0.026, -(cd + (0.0 if k == 6 else math.sin(a) * 0.026)), (0.0))
            if k == 6:
                p = (0.0, -cd, 0.0)
            g.sphere(p if k < 6 else (0.0, -cd, 0.0), 0.021, bd if k % 2 == 0 else ac, n=8)
        tube(g, cd - 0.05, cd - 0.04, 0.04, mt, n=14)
        tube(g, cd + 0.04, cd + 0.05, 0.04, mt, n=14)
    elif kind in ("ember", "fog", "blinder", "rattle", "can"):               # cylinder family: bottle, smoke can, flashbang, noise maker
        r = {"ember": 0.03, "fog": 0.034, "blinder": 0.03, "rattle": 0.032, "can": 0.034}[kind]
        if kind == "ember":                                                  # a glass bottle with a rag and a glow
            lathe_d(g, [(cd - 0.1, 0.02), (cd - 0.095, 0.0095), (cd - 0.065, 0.0095), (cd - 0.035, r), (cd + 0.07, r), (cd + 0.075, r * 0.8), (cd + 0.077, 0.001)], pal["lens_glow"], n=14, hard=())
            tube(g, cd + 0.0, cd + 0.065, r * 0.92, gl, n=12)
            g.cyl((0.0, -(cd - 0.1), 0.0), (0.0, -(cd - 0.14), 0.012), 0.007, pal["fabric"], n=6)
        elif kind == "blinder":
            lathe_d(g, [(cd - 0.07, r * 0.9), (cd - 0.065, r), (cd + 0.07, r), (cd + 0.075, r * 0.9)], mt, n=14, hard=(1, 2))
            if g.fine:
                for k in range(8):
                    a = 2 * math.pi * k / 8
                    g.cyl((math.cos(a) * r * 0.9, -(cd - 0.03), math.sin(a) * r * 0.9), (math.cos(a) * r * 0.95, -(cd - 0.03), math.sin(a) * r * 0.95), 0.0045, gl, n=6) if False else \
                        g.box((math.cos(a) * r * 1.0, -(cd - 0.035), math.sin(a) * r * 1.0), (0.006, 0.006, 0.006), gl)
            tube(g, cd + 0.075, cd + 0.095, 0.016, dk, n=10)
        elif kind == "fog":
            lathe_d(g, [(cd - 0.09, r * 0.8), (cd - 0.085, r), (cd + 0.09, r), (cd + 0.095, r * 0.85)], bd, n=14, hard=(1, 2))
            tube(g, cd - 0.04, cd - 0.02, r * 1.02, ac, n=14)
            tube(g, cd + 0.03, cd + 0.05, r * 1.02, ac, n=14)
            tube(g, cd - 0.105, cd - 0.09, 0.014, mt, n=10)
        elif kind == "rattle":
            lathe_d(g, [(cd - 0.07, r * 0.85), (cd - 0.065, r), (cd + 0.07, r), (cd + 0.075, r * 0.85)], bd, n=12, hard=(1, 2))
            if g.fine:
                for k in range(10):
                    a = 2 * math.pi * k / 10
                    for dd in (cd - 0.03, cd + 0.03):
                        g.box((math.cos(a) * r, -dd, math.sin(a) * r), (0.008, 0.008, 0.008), ac)
            tube(g, cd + 0.075, cd + 0.09, 0.012, mt, n=8)
    elif kind == "spark":                                                    # a cylinder with a coil
        lathe_d(g, [(cd - 0.08, 0.026), (cd - 0.075, 0.034), (cd + 0.075, 0.034), (cd + 0.08, 0.026)], bd, n=14, hard=(1, 2))
        for k in range(4):
            we.ring_d(g, cd - 0.05 + k * 0.033, 0.0365, 0.004, pal["coil"], n=14)
        g.sphere((0.0, -(cd - 0.09), 0.0), 0.012, gl, n=8)
    elif kind == "arc":                                                      # a short bottle with two electrodes arcing between prongs
        lathe_d(g, [(cd - 0.04, 0.022), (cd - 0.035, 0.036), (cd + 0.05, 0.036), (cd + 0.07, 0.02)], bd, n=14, hard=(1,))
        for sx in (-1.0, 1.0):
            g.cyl((sx * 0.02, -(cd - 0.04), 0.0), (sx * 0.026, -(cd - 0.11), 0.0), 0.006, mt, r1=0.0035, n=6)
        g.cyl((-0.026, -(cd - 0.1), 0.0), (0.026, -(cd - 0.1), 0.0), 0.0028, gl, n=6)
        we.ring_d(g, cd + 0.0, 0.038, 0.004, pal["coil"], n=14)
        we.ring_d(g, cd + 0.03, 0.038, 0.004, pal["coil"], n=14)
        tube(g, cd + 0.07, cd + 0.09, 0.012, mt, n=8)
    elif kind == "well":                                                     # a sphere held in a three ring cage
        g.sphere((0.0, -cd, 0.0), 0.034, gl, n=12)
        for k in range(3):
            with g.at((0.0, -cd, 0.0), rot=(0, 0, 60 * k)):
                g.torus((0.0, 0.0, 0.0), 0.046, 0.0036, bd, n=18, m=6, axis="x")
        tube(g, cd + 0.04, cd + 0.075, 0.016, mt, n=10)
        tube(g, cd - 0.075, cd - 0.04, 0.016, mt, n=10)
    elif kind == "still":                                                    # a pod: a milky sphere in two clamps on a base ring
        g.sphere((0.0, -cd, 0.0), 0.04, pal["lens_glow"], n=12)
        for sx in (-1.0, 1.0):
            rbox(g, cd - 0.015, cd + 0.015, -0.05, 0.05, 0.014, bd, r=0.003, x=sx * 0.044)
        for k in range(2):
            g.torus((0.0, -(cd + (k - 0.5) * 0.05), 0.0), 0.044, 0.004, mt, n=16, m=6, axis="y")
        tube(g, cd + 0.06, cd + 0.09, 0.022, dk, n=12)
        tube(g, cd - 0.09, cd - 0.06, 0.022, dk, n=12)
        g.sphere((0.0, -cd, 0.0), 0.02, gl, n=8)
    elif kind == "collapse":                                                 # a dark orb with four prongs
        g.sphere((0.0, -cd, 0.0), 0.03, dk, n=12)
        g.sphere((0.0, -cd, 0.0), 0.016, gl, n=8)
        for k in range(4):
            a_ = math.pi / 2 * k + math.pi / 4
            g.cyl((math.cos(a_) * 0.034, -(cd - 0.03), math.sin(a_) * 0.034), (math.cos(a_) * 0.05, -(cd + 0.07), math.sin(a_) * 0.05), 0.0075, bd, r1=0.004, n=6)
        tube(g, cd - 0.06, cd - 0.045, 0.04, mt, n=14)
    elif kind in ("prox", "gravity", "bounce", "emp"):                       # a disc mine on a ground plate
        if kind == "emp":                                                    # an EMP mine: three antenna spikes and a ring of studs
            for k in range(3):
                a_ = 2 * math.pi * k / 3
                g.cyl((math.cos(a_) * 0.05, -(cd + math.sin(a_) * 0.05), -0.02), (math.cos(a_) * 0.06, -(cd + math.sin(a_) * 0.06), 0.1), 0.004, dk, r1=0.0015, n=5)
        if kind == "gravity":                                                # a floating ring above the dome
            g.torus((0.0, -cd, 0.075), 0.045, 0.006, pal["coil"], n=18, m=6, axis="z")
        r = {"prox": 0.1, "gravity": 0.1, "bounce": 0.07, "emp": 0.095}[kind]
        h = {"prox": 0.055, "gravity": 0.06, "bounce": 0.09, "emp": 0.06}[kind]
        zc = -0.06 + h / 2
        lathe_d(g, [(cd - r, 0.004), (cd - r * 0.95, h * 0.5), (cd - r * 0.8, h * 0.5), (cd - r * 0.4, h * 0.5), (cd + r * 0.4, h * 0.5), (cd + r * 0.8, h * 0.5), (cd + r, 0.004)], bd, n=20, cx=0.0, cz=0.0) if False else None
        # discs lie flat: rotate the lathe so its axis is vertical (z)
        with g.at((0.0, -cd, -0.03), rot=(90, 0, 0)):
            g.lathe([(h * 0.0, r), (-h * 0.18, r), (-h * 0.5, r * 0.82), (-h * 0.9, r * 0.5), (-h, r * 0.4)], bd, n=24, hard=(1,)) if False else \
                g.lathe([(0.0, r * 0.4), (-0.012, r * 0.5), (-0.03, r * 0.85), (-0.045, r)], bd, n=24, hard=()) if False else \
                g.lathe([(h, r * 0.55), (h * 0.75, r * 0.85), (h * 0.12, r), (0.0, r), (0.0, r * 0.95)], bd, n=24, hard=(2, 3))
            g.lathe([(h + 0.0, r * 0.22), (h * 1.1, r * 0.22)], gl if kind != "bounce" else ac, n=14)
            if kind in ("gravity", "emp"):
                for k in range(3):
                    g.torus((0.0, h * 0.72, 0.0), r * (0.5 + 0.12 * k), 0.003, pal["coil"], n=24, m=5, axis="y")
        # hazard band and a pressure plate
        rbox(g, cd - r * 0.12, cd + r * 0.12, -0.06 + h * 0.9, -0.06 + h * 1.0, r * 1.3, hz, r=0.002) if False else None
        if kind == "bounce":
            g.cyl((0.0, -cd, -0.03), (0.0, -cd, -0.06), 0.012, mt, n=8)
    elif kind in ("c4", "remote", "satchel", "shaped", "trip", "directional"):
        if kind == "c4" or kind == "remote":
            rbox(g, cd - 0.07, cd + 0.07, -0.03, 0.03, 0.12, pal["body"], r=0.004, ch=0.003)
            rbox(g, cd - 0.06, cd + 0.06, -0.036, -0.03, 0.11, ac, r=0.002)
            rbox(g, cd - 0.03, cd + 0.03, 0.03, 0.05, 0.05, dk, r=0.004)
            g.box((0.0, -cd, 0.0505), (0.03, 0.02, 0.002), pal["screen"])
            g.cyl((0.02, -(cd + 0.07), 0.03), (0.04, -(cd + 0.1), 0.1 if kind == "remote" else 0.05), 0.0025, dk, n=6)
        elif kind == "satchel":
            rbox(g, cd - 0.08, cd + 0.08, -0.06, 0.06, 0.1, pal["fabric"], r=0.015, ch=0.008, seg=2)
            rbox(g, cd - 0.08, cd + 0.08, 0.04, 0.07, 0.1, pal["fabric"].k(0.8), r=0.01)
            for sx in (-1.0, 1.0):
                rbox(g, cd - 0.012, cd + 0.012, -0.07, 0.07, 0.01, pal["leather"], r=0.002, x=sx * 0.04)
            rbox(g, cd - 0.012, cd + 0.012, 0.065, 0.082, 0.02, mt, r=0.002)
        elif kind == "shaped":                                               # a cone-lined charge
            lathe_d(g, [(cd - 0.09, 0.0), (cd - 0.088, 0.018), (cd - 0.02, 0.055), (cd + 0.07, 0.055), (cd + 0.075, 0.04)], bd, n=16, hard=(3,))
            tube(g, cd + 0.075, cd + 0.09, 0.03, dk, n=12)
            tube(g, cd - 0.015, cd, 0.057, hz, n=16)
        elif kind == "trip":                                                 # a post, a spool and a wire
            tube(g, cd - 0.06, cd + 0.06, 0.022, bd, z=0.0, n=12)
            tube(g, cd - 0.07, cd - 0.055, 0.03, mt, n=12)
            g.cyl((0.0, -(cd - 0.07), 0.0), (0.0, -(cd - 0.2), 0.0), 0.0016, pal["fabric"], n=4)
            g.cyl((0.03, -cd, 0.0), (0.03, -cd, -0.07), 0.006, mt, n=6)
            g.sphere((0.0, -(cd + 0.0), 0.03), 0.012, gl, n=8)
        else:                                                                # directional: a curved claymore plate on scissor legs
            path = [(-0.095 + 0.19 * t, -(cd + 0.0 - 0.028 * (1.0 - (2 * t - 1) ** 2)), 0.0) for t in np.linspace(0, 1, 9)]
            g.sweep(path, lambda t: wl.outline_rrect(0.022, 0.08, 0.004, 1), bd, up=(0, 0, 1), chamfer=(0.002, 0.002))
            for sx in (-1.0, 1.0):
                g.cyl((sx * 0.06, -(cd + 0.02), -0.04), (sx * 0.095, -(cd + 0.04), -0.09), 0.0045, mt, n=6)
                g.cyl((sx * 0.06, -(cd + 0.02), -0.04), (sx * 0.04, -(cd + 0.045), -0.09), 0.0045, mt, n=6)
            g.box((0.0, -(cd - 0.036), 0.0), (0.12, 0.003, 0.034), hz)
    else:                                                                    # strike designators: a handheld beacon / tablet / designator, in several variants
        out = {"length": 0.62, "butt": 0.62}
        sk = s.get("style", "beacon")
        var = s.get("variant", 0)
        L = 0.5
        if sk in ("beacon", "flare"):
            r0 = 0.026 + 0.003 * (var % 3)
            tube(g, 0.0, L * 0.8, r0, bd, n=14, ch=0.003)
            tube(g, 0.0, 0.03, r0 + 0.004, dk, n=14)
            if var == 0:                                                     # a glowing head and a whip antenna
                g.sphere((0.0, 0.004, 0.0), 0.028, gl, n=10)
                g.cyl((0.0, -L * 0.3, r0), (0.0, -L * 0.3 - 0.01, 0.15), 0.003, dk, n=6)
                g.sphere((0.0, -L * 0.3 - 0.01, 0.152), 0.007, gl, n=6)
            elif var == 1:                                                   # a ground spike and a strobe cap
                g.cyl((0.0, 0.0, 0.0), (0.0, 0.08, 0.0), r0 * 0.5, mt, r1=0.002, n=8)
                g.sphere((0.0, -L * 0.8 - 0.0, 0.0), 0.0, mt, n=4) if False else None
                tube(g, L * 0.8 - 0.05, L * 0.8, r0 + 0.006, ac, n=14)
                g.cyl((0.0, -L * 0.8, 0.0), (0.0, -(L * 0.8 + 0.04), 0.0), 0.02, gl, n=12)
            elif var == 2:                                                   # a smoke canister cluster
                for k in range(3):
                    a_ = 2 * math.pi * k / 3
                    tube(g, 0.02, L * 0.6, 0.014, ac if k % 2 else dk, x=math.cos(a_) * 0.03, z=math.sin(a_) * 0.03 + 0.0, n=10)
                    g.sphere((math.cos(a_) * 0.03, 0.01, math.sin(a_) * 0.03), 0.012, gl, n=6)
            else:                                                            # a crystal on a collar
                lathe_d(g, [(-0.07, 0.003), (-0.045, 0.026), (-0.01, 0.026), (0.0, 0.0)], gl, n=6, hard=(1, 2)) if False else lathe_d(g, [(-0.08, 0.002), (-0.05, 0.022), (-0.01, 0.022), (0.0, 0.0001)], gl, n=6, hard=(1, 2))
                tube(g, 0.0, 0.03, r0 + 0.006, mt, n=14)
            for k in range(3):
                tube(g, 0.08 + k * 0.1, 0.092 + k * 0.1, r0 + 0.0025, ac, n=14)
            g.cyl((0.0, -L * 0.8, 0.0), (0.0, -(L * 0.8 + 0.12), 0.0), 0.014, pal["rub"], n=10)
            gr = (0.0, -L * 0.7, -0.01)
        elif sk == "tablet":
            rbox(g, 0.1, 0.4, -0.06, 0.06, 0.03, bd, r=0.008, ch=0.004, seg=2)
            g.box((0.0158, -0.25, 0.0), (0.0016, 0.25, 0.1), pal["screen"])
            g.box((-0.0158, -0.25, 0.0), (0.0016, 0.25, 0.1), pal["screen"])
            g.cyl((0.0, -0.12, 0.06), (0.0, -0.1, 0.22), 0.004, dk, n=6)
            g.sphere((0.0, -0.1, 0.225), 0.012, gl, n=8)
            rbox(g, 0.36, 0.5, -0.03, 0.03, 0.032, pal["rub"], r=0.01)
            if var % 3 == 1:                                                 # a folding solar panel
                rbox(g, 0.12, 0.38, 0.06, 0.066, 0.1, pal["lens"], r=0.002, x=0.0)
                for k in range(4):
                    g.box((0.0, -(0.17 + 0.07 * k), 0.0665), (0.1, 0.002, 0.0012), pal["bright"])
            elif var % 3 == 2:                                               # a second antenna and a keypad
                g.cyl((0.03, -0.14, 0.06), (0.035, -0.12, 0.2), 0.003, dk, n=6)
                for kx in range(3):
                    for ky in range(3):
                        g.box((0.0165, -(0.15 + 0.03 * ky), -0.02 + 0.02 * kx), (0.0012, 0.02, 0.014), pal["accent"])
            gr = (0.0, -0.43, 0.0)
        else:                                                                # laser designator: a tube with a lens and a handle
            tube(g, 0.0, 0.34, 0.034, bd, n=16, ch=0.004)
            tube(g, 0.0, 0.02, 0.04, dk, n=16)
            tube(g, 0.003, 0.006, 0.03, pal["lens_glow"], n=16)
            tube(g, 0.3, 0.36, 0.04, dk, n=16)
            g.box((0.0, -0.18, 0.04), (0.05, 0.1, 0.03), dk, r=0.005, chamfer=0.002)
            side_w(g, [(0.16, -0.03), (0.2, -0.03), (0.21, -0.12), (0.17, -0.12)], 0.03, pal["rub"], ch=0.003)
            if var % 3 == 1:                                                 # a tripod stub and a long tube
                for sx in (-1.0, 1.0):
                    g.cyl((sx * 0.01, -0.2, -0.034), (sx * 0.06, -0.26, -0.12), 0.006, dk, n=6)
                tube(g, 0.34, 0.46, 0.028, bd, n=14)
            elif var % 3 == 2:                                               # a scope on top and a big battery
                optic(g, "prism", 0.16, 0.04, pal, x=0.0)
                rbox(g, 0.34, 0.48, -0.03, 0.03, 0.06, dk, r=0.006)
            gr = (0.0, -0.19, -0.075)
        g.mark("gr", gr)
        g.mark("gl", (-0.04, -0.46, -0.02))
    if kind in ("c4", "remote", "satchel", "shaped", "trip", "directional", "fog", "blinder", "can") and g.fine:
        # stencilled label plates, a strap and a screw row: the simple shapes get their small details
        g.box((0.0, -cd, 0.0), (0.0, 0.0, 0.0), dk) if False else None
        g.box((0.0275 if kind in ("fog", "blinder", "can") else 0.0, -cd, 0.0), (0.0, 0.0, 0.0), dk) if False else None
        lab = pal["label"]
        if kind in ("fog", "blinder", "can"):
            r_ = 0.034 if kind != "blinder" else 0.03
            g.box((r_ + 0.0004, -cd, 0.0), (0.0012, 0.07, 0.02), lab)
            g.box((-r_ - 0.0004, -cd, 0.0), (0.0012, 0.07, 0.02), lab)
            g.torus((0.0, -(cd - 0.07), 0.0), r_ * 0.5, 0.003, pal["bright"], n=12, m=5, axis="y")
            for k in range(8):
                a_ = 2 * math.pi * k / 8
                screw(g, (math.cos(a_) * r_ * 0.96, -(cd + 0.055), math.sin(a_) * r_ * 0.96), pal["bright"], axis="y", r=0.003)
        elif kind in ("c4", "remote"):
            g.box((0.0, -cd, 0.0316), (0.09, 0.03, 0.0016), lab)
            for sx in (-1.0, 1.0):
                for sd in (-1.0, 1.0):
                    screw(g, (sx * 0.05, -(cd + sd * 0.055), 0.0305), pal["bright"], axis="z", r=0.004)
            for k in range(3):
                g.cyl((0.0, -(cd - 0.07), 0.0), (0.0, -(cd - 0.16), 0.02 + 0.02 * k), 0.0022, [pal["dark"], pal["accent"], pal["glow"]][k], n=5)
        elif kind == "satchel":
            for sx in (-1.0, 1.0):
                g.box((sx * 0.04, -cd, 0.0), (0.012, 0.0, 0.0), dk) if False else None
                for sd in (-1.0, 1.0):
                    rbox(g, cd + sd * 0.03 - 0.003, cd + sd * 0.03 + 0.003, -0.06, 0.06, 0.016, pal["leather"], r=0.002, x=sx * 0.04)
            g.box((0.0, -cd, 0.0615), (0.06, 0.03, 0.0016), lab)
        elif kind == "shaped":
            g.box((0.0, -(cd + 0.02), 0.0555), (0.0, 0.0, 0.0), dk) if False else None
            tube(g, cd - 0.07, cd - 0.065, 0.055, pal["bright"], n=18)
            for k in range(6):
                a_ = 2 * math.pi * k / 6
                screw(g, (math.cos(a_) * 0.05, -(cd + 0.073), math.sin(a_) * 0.05), pal["bright"], axis="y", r=0.004)
        elif kind == "trip":
            g.box((0.0, -cd, 0.0225), (0.03, 0.05, 0.0014), lab)
            tube(g, cd + 0.02, cd + 0.03, 0.026, dk, n=12)
            g.torus((0.0, -(cd - 0.2), 0.0), 0.016, 0.003, pal["bright"], n=12, m=5, axis="y")
        elif kind == "directional":
            for k in range(4):
                g.box((-0.054 + 0.036 * k, -(cd - 0.0305), 0.0), (0.01, 0.0014, 0.02), pal["brass"]) if False else g.box((-0.054 + 0.036 * k, -(cd - 0.031), 0.0), (0.014, 0.0014, 0.03), pal["accent"])
            g.box((0.0, -(cd + 0.0305), 0.0), (0.06, 0.0014, 0.02), lab)
            g.cyl((0.0, -cd, 0.045), (0.0, -cd, 0.06), 0.0035, dk, n=6)
            g.box((0.0, -(cd - 0.0), 0.068), (0.012, 0.03, 0.012), dk)
    if "gr" not in g.markers:
        g.mark("gr", (0.0, -cd - 0.0, 0.0))
        g.mark("gl", (-0.06, -(cd + 0.06), -0.03))
    g.mark("eject", (0.0, -cd, 0.0))
    g.mark("mag", (0.0, -cd, 0.0))
    g.mark("aim", (0.0, -cd, 0.05))
    g.mark("optic", (0.0, -cd, 0.05))
    g.mark("laser", (0.0, 0.0, 0.0))
    out["muz_ext"] = 0.0
    out["grip_d"] = -g.markers["gr"][1]
    return out
