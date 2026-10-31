"""Parametric car builder used by model_car_sedan.py / model_car_sport.py / model_car_suv.py.

Body: one closed hull loft (rings along the car, with real wheel-arch notches, rocker sills, nose/tail taper) plus a greenhouse
loft whose faces are assigned paint / glass / trim by region. Wheels are four separate objects pivoted at the axle
(WheelFL/FR/RL/RR), the front of the car is +Y in Blender (-Z in Godot).

Surfaces (draw calls): "Body" (neutral baked paint, tinted by its material colour, vehicles recolour it), one baked "Details" material
(trim, rubber, chrome, tinted glass, tyres, rims), and three flat emissive materials Headlights / Taillights / Underglow: 5 surfaces on
the body mesh plus one per wheel. The glass is opaque and glossy (no blended pass, no interior).
Real lights come with the model: a headlight spot, an underglow omni and a fill that lights only the car (see helpers.light).
"""
import math

import bpy  # noqa: F401  (must be imported before mathutils)
from mathutils import Vector

from helpers import (Part, empty, export_model, hexc, light, make_material, new_scene, paint)
from shade import Decal, p_lines


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

    body = make_material("Body", tex="paint", color=hexc(spec["paint"]))
    glass = make_material("Glass", tex="glass", color=(0.012, 0.02, 0.026))
    trim = make_material("Trim", tex="rubber")
    chrome = make_material("Chrome", tex="steel")
    under = make_material("Under", tex="solid")
    head = make_material("Headlights", emit=hexc("#fff1d0"), emit_strength=3.0)
    tail = make_material("Taillights", emit=hexc("#ff1020"), emit_strength=2.6)
    glow = make_material("Underglow", emit=hexc(spec.get("underglow", "#18d6ff")), emit_strength=2.0)

    T_black = hexc("#1b1d1f")
    T_dark = hexc("#2c3033")
    T_chrome = hexc("#b4bcc3")
    T_under = hexc("#0b0c0d")

    P = Part("Body", seed=spec.get("seed", 5))
    gh_pts = spec["gh"]
    y_ws, y_rf = gh_pts[0][0], spec["roof_front"]
    y_rr, y_rw = spec["roof_rear"], gh_pts[-1][0]
    belt = spec["belt"]

    # ------------------------------------------------------------------ profiles
    def hw(y):
        e = abs(y) - (L / 2 - taper)
        k = 1.0 if e <= 0 else max(0.0, 1.0 - spec.get("taper_amt", 0.24) * (e / taper) ** 2.0)
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
                m, t = under, T_under                    # the underside
            elif c in (1, 2):
                m, t = (under, T_under) if has_arch[k] else (trim, T_black)       # wheel-well walls / sill plastic
            elif in_cabin and c >= 6:
                m, t = under, T_under
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
                gmats.append((trim, T_black))
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
            gmats.append((m, T_black if m is trim else (glass.color if m is glass else (1.0, 1.0, 1.0))))
    gmats += [(trim, T_black), (trim, T_black)]
    P.loft(grings, mat=body, caps=(True, True), closed=True, sharp=89.0, face_mats=gmats)

    # ------------------------------------------------------------------ body details
    def xs_at(y, z):
        zb, zt = zbot(y), ztop(y)
        zr = zb + 0.075
        zs = zt - 0.045
        t = clamp((z - zr) / max(zs - zr, 1e-3), 0.0, 1.0)
        return hw(y) * (0.972 + 0.03 * math.sin(math.pi * min(1.0, t * 1.1)) - 0.045 * t ** 3)

    # door handles
    for yh in spec["handles"]:
        z = belt - 0.075
        P.box((0.016, 0.15, 0.022), (xs_at(yh, z) + 0.006, yh, z), mat=chrome, tint=T_chrome, bevel=0.004, mirror=True)
    # mirrors
    ym = y_ws - 0.14
    zm = belt + 0.10
    xm = hw(ym) * 0.95 + 0.06
    P.box((0.1, 0.14, 0.085), (xm, ym, zm), mat=body, bevel=0.025, bsegs=2, top=(0.9, 0.8), mirror=True)
    P.bar((xm - 0.08, ym + 0.02, zm - 0.07), (xm - 0.02, ym, zm - 0.02), 0.02, 0.016, mat=trim, tint=T_black, mirror=True)
    # headlights, grille, plates (front = +Y): flush with the nose face, so they stay visible
    yf = L / 2
    ze, xe = ztop(yf - 0.05), hw(yf - 0.05)
    zbe = zbot(yf - 0.02)
    face_h = ze - zbe
    for sx in (1, -1):
        x = sx * (xe - 0.27)
        zh = ze - 0.12
        P.box((0.33, 0.1, 0.075), (x, yf - 0.025, zh), mat=head, bevel=0.018, bsegs=2, top=(0.9, 0.9), rot=(0, 0, -sx * 9))
        P.box((0.37, 0.12, 0.10), (x, yf - 0.035, zh), mat=trim, tint=T_black, bevel=0.02, bsegs=2, top=(0.92, 0.9), rot=(0, 0, -sx * 9))
        P.box((0.17, 0.09, 0.05), (sx * (xe - 0.35), yf - 0.02, zbe + 0.10), mat=head, bevel=0.012, bsegs=1)                 # fog lamps
    P.box((0.78, 0.09, face_h * 0.30), (0, yf - 0.02, zbe + face_h * 0.46), mat=trim, tint=T_black, bevel=0.02, bsegs=2)    # grille
    for k in (-1, 0, 1):
        P.box((0.7, 0.014, 0.012), (0, yf + 0.026, zbe + face_h * 0.46 + k * face_h * 0.075), mat=trim, tint=T_dark)
    P.box((0.5, 0.012, 0.11), (0, yf + 0.0, zbe + 0.07), mat=chrome, tint=T_chrome, bevel=0.003)                          # plate
    P.box((0.96, 0.07, 0.025), (0, yf - 0.02, zbe + 0.01), mat=trim, tint=T_dark, bevel=0.008)                          # splitter lip
    # tail lights, plate, exhaust
    yr = -L / 2
    zr_, xr_ = ztop(yr + 0.05), hw(yr + 0.05)
    zbr = zbot(yr + 0.02)
    for sx in (1, -1):
        x = sx * (xr_ - 0.25)
        zt_ = zr_ - 0.11
        P.box((0.38, 0.1, 0.07), (x, yr + 0.025, zt_), mat=tail, bevel=0.015, bsegs=2, rot=(0, 0, sx * 9))
        P.box((0.42, 0.12, 0.095), (x, yr + 0.035, zt_), mat=trim, tint=T_black, bevel=0.02, bsegs=2, rot=(0, 0, sx * 9))
        P.cyl(0.04, 0.14, (sx * 0.52, yr - 0.01, zbr + 0.06), axis="y", mat=chrome, tint=T_chrome, segs=12, bevel=0.004)
    P.box((0.52, 0.012, 0.11), (0, yr, zr_ - 0.2), mat=chrome, tint=T_chrome, bevel=0.003)
    P.box((0.9, 0.07, 0.06), (0, yr + 0.03, zbr + 0.06), mat=trim, tint=T_dark, bevel=0.01)
    P.box((xr_ * 1.3, 0.012, 0.012), (0, yr - 0.002, zr_ - 0.11), mat=tail)
    # underglow strips + sill glow
    for sx in (1, -1):
        P.box((0.035, WB + 0.7, 0.012), (sx * (W / 2 - 0.13), 0, gc - 0.003), mat=glow)
    # extras (spoiler, roof rails, ...)
    for fn in spec.get("extras", []):
        fn(P, dict(trim=trim, body=body, tail=tail, head=head, chrome=chrome, T_black=T_black, T_dark=T_dark, T_chrome=T_chrome, hw=hw,
                   ztop=ztop, zbot=zbot, L=L, W=W, WB=WB, gc=gc, belt=belt, spec=spec, glass=glass))

    # ------------------------------------------------------------------ wheels (separate nodes pivoted at the axle)
    def make_wheel(name, sx, sy):
        cx, cy = sx * track / 2, sy * WB / 2
        w = Part(name, origin=(cx, cy, zc), seed=70 + (sx + 1) + (sy + 1) // 2)
        w.tag(vis_end=60.0, no_shadow=1)
        s = sx

        def pr(r, x):
            return (r, s * x)

        t_prof = [pr(0.60 * R, -0.46 * tw), pr(0.80 * R, -0.52 * tw), pr(0.95 * R, -0.49 * tw), pr(R, -0.32 * tw), pr(R, 0.32 * tw),
                  pr(0.95 * R, 0.49 * tw), pr(0.80 * R, 0.52 * tw), pr(0.60 * R, 0.46 * tw)]
        w.revolve(t_prof, (cx, cy, zc), mat=trim, tint=hexc("#101113"), segs=22, closed=True)
        r_prof = [pr(0.025 * R, 0.47 * tw), pr(0.17 * R, 0.47 * tw), pr(0.21 * R, 0.37 * tw), pr(0.55 * R, 0.37 * tw), pr(0.62 * R, 0.46 * tw),
                  pr(0.63 * R, 0.30 * tw), pr(0.58 * R, -0.3 * tw), pr(0.025 * R, -0.3 * tw)]
        w.revolve(r_prof, (cx, cy, zc), mat=chrome, tint=hexc(spec.get("rim", "#8d959c")), segs=22, closed=True)
        for k in range(spec.get("spokes", 5)):
            a = 2 * math.pi * k / spec.get("spokes", 5) + 0.3
            d = Vector((0, math.cos(a), math.sin(a)))
            c0 = Vector((cx + s * 0.485 * tw, cy, zc))
            w.bar(c0 + d * 0.17 * R, c0 + d * 0.60 * R, 0.11 * R, 0.035, mat=chrome, tint=hexc(spec.get("spoke", "#c3cad1")), up=(s, 0, 0), bevel=0.004)
        w.cyl(0.075 * R, 0.03, (cx + s * 0.50 * tw, cy, zc), axis="x", mat=chrome, tint=hexc("#3b4045"), segs=12)
        return w

    wheels = [make_wheel("WheelFL", -1, 1), make_wheel("WheelFR", 1, 1), make_wheel("WheelRL", -1, -1), make_wheel("WheelRR", 1, -1)]

    # ------------------------------------------------------------------ decals: panel gaps along the doors and a dusty lower body
    decals = []
    gaps = list(spec["door_lines"])
    hz = (gc + 0.2 + belt) * 0.5
    for sgn in (1, -1):
        pos = [(-y if sgn < 0 else y) for y in gaps]
        decals.append(Decal((sgn * (W * 0.5), 0.0, hz), (sgn, 0, 0), (0, 0, 1), (L, belt - gc - 0.2), p_lines(pos, 0.0035, length=L, vertical=True),
                            depth=0.12, kinds=("paint",), min_dot=0.5))
    # ------------------------------------------------------------------ rig: real lights that make the car readable at night
    rig = []
    hl = spec.get("headlight_rig", (1.0, 0.93, 0.78))
    rig.append(light("Headlights", (0.0, L / 2 - 0.1, ze - 0.2), "spot", hl, 2.4, 22.0, direction=(0, 1, -0.07), angle=36.0,
                     attenuation=1.1, spot_attenuation=1.0, fade=(32, 14), group="headlight"))
    ug = hexc(spec.get("underglow", "#18d6ff"))
    ugc = tuple(min(1.0, c * 1.6 + 0.05) for c in ug)
    rig.append(light("UnderglowLight", (0.0, 0.0, 0.10), "omni", ugc, 1.3, 4.6, attenuation=1.5, fade=(28, 12), group="underglow"))
    rig.append(light("Fill", (0.0, 0.1, 2.3), "omni", (0.7, 0.82, 1.0), 1.0, 6.5, mask="own", attenuation=1.1, fade=(36, 14)))
    print("  body tris %d, wheel tris %d" % (P.tri_count(), sum(w.tri_count() for w in wheels)))
    groups = {"paint": dict(base=spec["name"] + "_paint", material="Body", size=spec.get("atlas_paint", 1024)),
              "atlas": dict(base=spec["name"], material="Details", size=spec.get("atlas", 1024))}
    return export_model(spec["name"], [P] + wheels, extras=rig, groups=groups, decals=decals, ao_dist=0.6, ao_strength=0.65, emit_strength=2.0)
