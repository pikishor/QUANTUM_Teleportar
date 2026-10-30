"""Parametric car builder used by model_car_sedan.py / model_car_sport.py / model_car_suv.py.

Body: one closed hull loft (rings along the car, with real wheel-arch notches, rocker sills, nose/tail taper) plus a greenhouse
loft whose faces are assigned Body / Glass / Trim by region. Wheels are four separate objects pivoted at the axle
(WheelFL/FR/RL/RR), the front of the car is +Y in Blender (-Z in Godot).
Materials: Body (paint, recolourable), Glass (blended), Trim (dark metal/plastic), Wheel, Headlights, Taillights, Underglow.
"""
import math

import bpy  # noqa: F401  (must be imported before mathutils)
from mathutils import Vector

from helpers import (Part, bake_ao, empty, export_model, hexc, make_material, new_scene, paint, vertex_gradient)


def clamp(x, a, b):
    return a if x < a else b if x > b else x


def prof(points, y):
    if y <= points[0][0]:
        return points[0][1]
    if y >= points[-1][0]:
        return points[-1][1]
    for (y0, v0), (y1, v1) in zip(points, points[1:]):
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0) if y1 > y0 else 0.0
            return v0 + (v1 - v0) * t
    return points[-1][1]


def sprof(points, y, k=0.10):
    taps = (-2, -1, 0, 1, 2)
    w = (1, 4, 6, 4, 1)
    return sum(wi * prof(points, y + t * k) for t, wi in zip(taps, w)) / 16.0


def build_car(spec):
    new_scene()
    L, W, WB = spec["L"], spec["W"], spec["WB"]
    R, tw, track = spec["R"], spec["tw"], spec["track"]
    gc = spec["gc"]
    zc = R
    Ra = R + 0.065
    taper = spec.get("taper", 0.6)
    x_in = track / 2 - tw / 2 - 0.05

    body = make_material("Body", tex="metal_painted", color=paint("metal_painted", spec["paint"]))
    glass = make_material("Glass", tex="glass", color=(0.03, 0.045, 0.055), alpha=0.45, vcol=False)
    trim = make_material("Trim", tex="steel")
    wheelm = make_material("Wheel", tex="steel")
    head = make_material("Headlights", emit=hexc("#fff1d0"), emit_strength=7.0, vcol=False)
    tail = make_material("Taillights", emit=hexc("#ff1020"), emit_strength=5.0, vcol=False)
    under = make_material("Underglow", emit=hexc(spec.get("underglow", "#18d6ff")), emit_strength=4.0, vcol=False)

    T_black = paint("steel", "#17191b")
    T_dark = paint("steel", "#25292d")
    T_chrome = paint("steel", "#a4adb5")
    T_int = paint("steel", "#1d2124")

    P = Part("Body", seed=spec.get("seed", 5))
    gh_pts = spec["gh"]
    y_ws, y_rf = gh_pts[0][0], spec["roof_front"]
    y_rr, y_rw = spec["roof_rear"], gh_pts[-1][0]
    belt = spec["belt"]

    # ------------------------------------------------------------------ profiles
    def hw(y):
        e = abs(y) - (L / 2 - taper)
        k = 1.0 if e <= 0 else max(0.0, 1.0 - 0.34 * (e / taper) ** 2.0)
        return (W / 2) * k

    def ztop(y):
        return sprof(spec["ztop"], y, 0.12)

    def zbot(y):
        rise = spec["rise"][0] if y > 0 else spec["rise"][1]
        e = abs(y) - (L / 2 - 0.55)
        return gc + (rise * (e / 0.55) ** 2 if e > 0 else 0.0)

    def arch(y):
        for yw in (WB / 2, -WB / 2):
            dy = y - yw
            if abs(dy) <= Ra + 1e-6:
                return zc + math.sqrt(max(Ra * Ra - dy * dy, 0.0))
        return None

    # ------------------------------------------------------------------ hull
    ys = {round(-L / 2 + L * i / int(L / 0.11), 3) for i in range(int(L / 0.11) + 1)}
    for yw in (WB / 2, -WB / 2):
        for i in range(-6, 7):
            ys.add(round(yw + Ra * math.sin(i * math.pi / 12.0), 3))
        ys.add(round(yw + Ra + 0.02, 3))
        ys.add(round(yw - Ra - 0.02, 3))
    for a in (y_ws, y_rw):
        ys.add(round(a, 3))
    ordered = sorted(ys)
    stations = [ordered[0]]
    for y in ordered[1:]:
        if y - stations[-1] > 0.018:
            stations.append(y)

    def hull_ring(y):
        hwv, zt, zb = hw(y), ztop(y), zbot(y)
        za = arch(y)
        zr = zb + 0.075
        zl = za if za is not None else zr
        zs = max(zt - 0.045, zl + 0.035)

        def xs(z):
            t = clamp((z - zr) / max(zs - zr, 1e-3), 0.0, 1.0)
            return hwv * (0.972 + 0.03 * math.sin(math.pi * min(1.0, t * 1.1)) - 0.045 * t ** 3)

        if za is not None:
            r = [(x_in, zb), (x_in, za), (xs(za), za)]
        else:
            r = [(xs(zr) - 0.09, zb), (xs(zr) - 0.025, zb + 0.032), (xs(zr), zr)]
        xc = xs(zs)
        r += [(xs(zl + 0.3 * (zs - zl)), zl + 0.3 * (zs - zl)), (xs(zl + 0.65 * (zs - zl)), zl + 0.65 * (zs - zl)), (xc, zs),
              (xc - 0.04, zs + 0.03), (xc * 0.80, zt - 0.012), (xc * 0.45, zt + 0.004), (xc * 0.2, zt + 0.011)]
        right = [Vector((x, y, z)) for x, z in r]
        left = [Vector((-x, y, z)) for x, z in reversed(r)]
        ring = [Vector((0, y, zb))] + right + [Vector((0, y, zt + 0.014))] + left
        return [(v.x, v.y, v.z) for v in ring], za is not None

    rings, has_arch = [], []
    for y in stations:
        rg, ar = hull_ring(y)
        rings.append(rg)
        has_arch.append(ar)
    PTS = len(rings[0])        # 22
    nP = (PTS - 2) // 2        # 10 right points
    face_mats = []
    cabin_lo, cabin_hi = y_rw + 0.05, y_ws - 0.05
    for k in range(len(rings) - 1):
        ymid = 0.5 * (stations[k] + stations[k + 1])
        in_cabin = cabin_lo <= ymid <= cabin_hi
        for i in range(PTS):
            c = i if i <= nP else (2 * nP + 1 - i)
            if c == 0:
                m, t = trim, T_black
            elif c in (1, 2):
                m, t = trim, T_black
            elif in_cabin and c >= 6:
                m, t = trim, T_int
            else:
                m, t = body, (1.0, 1.0, 1.0)
            face_mats.append((m, t))
    face_mats += [(body, (1.0, 1.0, 1.0)), (body, (1.0, 1.0, 1.0))]      # nose and tail caps
    P.loft(rings, mat=body, caps=(True, True), closed=True, sharp=89.0, face_mats=face_mats)

    # ------------------------------------------------------------------ greenhouse
    wb_ratio, roof_ratio = 0.88, spec.get("roof_w", 0.74)
    fr = [0.0, 0.05, 0.12, 0.45, 0.80, 0.91, 0.975]
    gst, grings = [], []
    for (y, ztp) in gh_pts:
        zbs = prof(spec["ztop"], y) - 0.035
        h = max(ztp - zbs, 0.03)
        wbv = hw(y) * wb_ratio
        wtv = wbv * roof_ratio
        right = []
        for f in fr:
            right.append((wbv - (wbv - wtv) * (f ** 1.25), zbs + h * f))
        top = (0.0, ztp + (0.014 if h > 0.2 else 0.0))
        pts = [Vector((x, y, z)) for x, z in right] + [Vector((top[0], y, top[1]))] + [Vector((-x, y, z)) for x, z in reversed(right)]
        grings.append([(v.x, v.y, v.z) for v in pts])
        gst.append(y)
    GP = len(grings[0])        # 15
    gmats = []
    by0, by1 = spec["b_pillar"]
    side_lo, side_hi = spec["side_glass"]
    for k in range(len(grings) - 1):
        ymid = 0.5 * (gst[k] + gst[k + 1])
        for i in range(GP):
            if i == GP - 1:
                gmats.append((trim, T_int))
                continue
            c = i if i <= 7 else 13 - i
            if c <= 1:
                m = trim
            elif y_rf < ymid and c >= 5:
                m = glass
            elif ymid < y_rr and c >= 5:
                m = glass
            elif c in (2, 3) and side_lo <= ymid <= side_hi and not (by0 <= ymid <= by1):
                m = glass
            else:
                m = body
            gmats.append((m, T_black if m is trim else (1.0, 1.0, 1.0)))
    gmats += [(trim, T_int), (trim, T_int)]
    P.loft(grings, mat=body, caps=(True, True), closed=True, sharp=89.0, face_mats=gmats)
    # dark inner liner so the cabin reads as dark through the glass (normals point inward)
    inner = [[(x * 0.965, y, z - 0.012 + (0.0 if abs(x) > 0.01 else -0.025)) for (x, y, z) in ring] for ring in grings]
    P.loft(inner, mat=trim, tint=T_int, caps=(True, True), closed=True, sharp=89.0, flip=True)

    # ------------------------------------------------------------------ body details
    def xs_at(y, z):
        zb, zt = zbot(y), ztop(y)
        zr = zb + 0.075
        zs = zt - 0.045
        t = clamp((z - zr) / max(zs - zr, 1e-3), 0.0, 1.0)
        return hw(y) * (0.972 + 0.03 * math.sin(math.pi * min(1.0, t * 1.1)) - 0.045 * t ** 3)

    # panel gap lines (dark thin tubes following the side contour)
    for yl in spec["door_lines"]:
        zlo, zhi = gc + 0.2, belt - 0.015
        pts = [(xs_at(yl, z) + 0.002, yl, z) for z in (zlo, (zlo + zhi) / 2, zhi)]
        P.tube(pts, [(0.004, 0.005)] * 3, mat=trim, tint=T_black, n=4, sub=1, mirror=True, sharp=89.0)
    # door handles
    for yh in spec["handles"]:
        z = belt - 0.075
        P.box((0.016, 0.15, 0.022), (xs_at(yh, z) + 0.006, yh, z), mat=trim, tint=T_chrome, bevel=0.004, mirror=True)
    # mirrors
    ym = y_ws - 0.14
    zm = belt + 0.10
    xm = hw(ym) * 0.95 + 0.06
    P.box((0.1, 0.14, 0.085), (xm, ym, zm), mat=body, bevel=0.025, bsegs=2, top=(0.9, 0.8), mirror=True)
    P.bar((xm - 0.08, ym + 0.02, zm - 0.07), (xm - 0.02, ym, zm - 0.02), 0.02, 0.016, mat=trim, tint=T_black, mirror=True)
    # headlights, grille, fog lamps, plates (front = +Y)
    yf = L / 2
    for sx in (1, -1):
        yh = yf - 0.33
        zh = ztop(yh) - 0.085
        x = sx * (hw(yh) - 0.30)
        P.box((0.34, 0.12, 0.075), (x, yh, zh), mat=head, bevel=0.018, bsegs=2, top=(0.9, 0.9), rot=(-12, 0, -sx * 14), mirror=False)
        P.box((0.38, 0.14, 0.095), (x, yh - 0.008, zh), mat=trim, tint=T_black, bevel=0.02, bsegs=2, top=(0.92, 0.9), rot=(-12, 0, -sx * 14))
    P.box((0.78, 0.08, 0.17), (0, yf - 0.09, gc + 0.27), mat=trim, tint=T_black, bevel=0.02, bsegs=2, rot=(-8, 0, 0))
    for yy in (0.0,):
        for zz in (gc + 0.22, gc + 0.27, gc + 0.32):
            P.box((0.66, 0.012, 0.012), (0, yf - 0.043, zz), mat=trim, tint=T_dark, rot=(-8, 0, 0))
    P.box((0.5, 0.012, 0.11), (0, yf - 0.02, gc + 0.4), mat=trim, tint=T_chrome, bevel=0.003)           # plate
    P.box((0.9, 0.06, 0.02), (0, yf - 0.06, zbot(yf - 0.1) + 0.06), mat=trim, tint=T_dark, bevel=0.006)        # splitter lip
    # tail lights, plate, exhaust
    yr = -L / 2
    for sx in (1, -1):
        yt = yr + 0.30
        zt_ = ztop(yt) - 0.10
        x = sx * (hw(yt) - 0.26)
        P.box((0.36, 0.1, 0.07), (x, yt, zt_), mat=tail, bevel=0.015, bsegs=2, rot=(8, 0, sx * 12))
        P.box((0.4, 0.12, 0.09), (x, yt + 0.006, zt_), mat=trim, tint=T_black, bevel=0.02, bsegs=2, rot=(8, 0, sx * 12))
        P.cyl(0.04, 0.14, (sx * 0.52, yr + 0.02, zbot(yr + 0.1) + 0.05), axis="y", mat=trim, tint=T_chrome, segs=12, bevel=0.004)
    P.box((0.52, 0.012, 0.11), (0, yr + 0.02, zbot(yr + 0.1) + 0.30), mat=trim, tint=T_chrome, bevel=0.003)
    P.box((0.82, 0.07, 0.06), (0, yr + 0.07, zbot(yr + 0.1) + 0.07), mat=trim, tint=T_dark, bevel=0.01)
    P.box((1.2, 0.012, 0.012), (0, yr + 0.045, ztop(yr + 0.3) - 0.1), mat=tail)
    # underglow strips + sill glow
    for sx in (1, -1):
        P.box((0.035, WB + 0.7, 0.012), (sx * (W / 2 - 0.13), 0, gc - 0.003), mat=under)
    # interior (above the belt line so it is visible through the glass): seats, dash, steering wheel
    seat_y = spec["seats"]
    for (sy_, headrest) in seat_y:
        P.box((0.46, 0.1, 0.5), (0.36, sy_, belt + 0.14), mat=trim, tint=T_int, bevel=0.03, bsegs=2, rot=(-8, 0, 0), mirror=True)
        if headrest:
            P.box((0.2, 0.07, 0.15), (0.36, sy_ - 0.02, belt + 0.46), mat=trim, tint=T_int, bevel=0.025, mirror=True)
    ydash = y_ws - 0.12
    P.box((1.18, 0.34, 0.10), (0, ydash - 0.02, belt + 0.05), mat=trim, tint=T_int, bevel=0.03, bsegs=2)
    P.torus(0.17, 0.014, (0.36, ydash - 0.26, belt + 0.22), rot=(60, 0, 0), mat=trim, tint=T_black, segs=18, sides=5)
    # extras (spoiler, roof rails, ...)
    for fn in spec.get("extras", []):
        fn(P, dict(trim=trim, body=body, tail=tail, head=head, T_black=T_black, T_dark=T_dark, T_chrome=T_chrome, hw=hw, ztop=ztop,
                   zbot=zbot, L=L, W=W, WB=WB, gc=gc, belt=belt, spec=spec, glass=glass))

    # ------------------------------------------------------------------ wheels (separate nodes pivoted at the axle)
    def make_wheel(name, sx, sy):
        cx, cy = sx * track / 2, sy * WB / 2
        w = Part(name, origin=(cx, cy, zc), seed=70 + (sx + 1) + (sy + 1) // 2)
        s = sx

        def pr(r, x):
            return (r, s * x)

        t_prof = [pr(0.60 * R, -0.46 * tw), pr(0.80 * R, -0.52 * tw), pr(0.95 * R, -0.49 * tw), pr(R, -0.32 * tw), pr(R, 0.32 * tw),
                  pr(0.95 * R, 0.49 * tw), pr(0.80 * R, 0.52 * tw), pr(0.60 * R, 0.46 * tw)]
        w.revolve(t_prof, (cx, cy, zc), mat=wheelm, tint=paint("steel", "#0b0c0d"), segs=28, closed=True)
        r_prof = [pr(0.025 * R, 0.47 * tw), pr(0.17 * R, 0.47 * tw), pr(0.21 * R, 0.37 * tw), pr(0.55 * R, 0.37 * tw), pr(0.62 * R, 0.46 * tw),
                  pr(0.63 * R, 0.30 * tw), pr(0.58 * R, -0.3 * tw), pr(0.025 * R, -0.3 * tw)]
        w.revolve(r_prof, (cx, cy, zc), mat=wheelm, tint=paint("steel", spec.get("rim", "#8d959c")), segs=28, closed=True)
        for k in range(spec.get("spokes", 5)):
            a = 2 * math.pi * k / spec.get("spokes", 5) + 0.3
            d = Vector((0, math.cos(a), math.sin(a)))
            c0 = Vector((cx + s * 0.485 * tw, cy, zc))
            w.bar(c0 + d * 0.17 * R, c0 + d * 0.60 * R, 0.11 * R, 0.035, mat=wheelm, tint=paint("steel", spec.get("spoke", "#c3cad1")), up=(s, 0, 0), bevel=0.004)
        w.cyl(0.075 * R, 0.03, (cx + s * 0.50 * tw, cy, zc), axis="x", mat=wheelm, tint=paint("steel", "#2a2e33"), segs=12)
        return w

    wheels = [make_wheel("WheelFL", -1, 1), make_wheel("WheelFR", 1, 1), make_wheel("WheelRL", -1, -1), make_wheel("WheelRR", 1, -1)]

    # ------------------------------------------------------------------ AO, grime, build, export
    bake_ao([P], samples=14, dist=0.6, strength=0.55)
    vertex_gradient(P, 2, gc, gc + 0.55, (0.5, 0.5, 0.52), (1.0, 1.0, 1.0))
    objs = [P.build()] + [wh.build() for wh in wheels]
    print("  body tris %d, wheel tris %d" % (P.tri_count(), sum(w.tri_count() for w in wheels)))
    return export_model(spec["name"], objs)
