"""Archetype definitions of the Cars v2 set. Every number is in metres; the nose is +Y (Blender), the origin is on the ground in the middle of the car.

`top`   the top silhouette along the car as (y, z, corner radius) keys from the front to the rear (bonnet, windscreen, roof, rear window, deck)
`belt`  the height of the beltline under the greenhouse (a number or [(y, z)])
`ws` / `rw`  y ranges of the windscreen and the rear window glass; `windows`  y ranges of the side lights
`fx`    where the lamps, grille, intakes, plates, exhausts, mirrors and handles go (see car_details); `cabin`  the interior layout
"""
import copy
import math

import numpy as np

from . import kit
from .kit import D_CHROME, D_PLASTIC

BASE = dict(
    L=4.75, W=1.85, R=0.335, tyre_w=0.225, track=1.54, axle_f=1.42, axle_r=-1.40, z_floor=0.16, z_sill=0.23, arch_gap=0.05,
    cap_f=0.12, cap_r=0.12, cap_s=(0.76, 0.80), end_w_f=0.80, end_w_r=0.82, plan_len=0.75, b_hood=0.07, p_hood=0.15, p_gh=0.30, crown=0.035,
    tuck=0.075, m_lo=2.6, bulge=0.006, rise=0.45, rise_len=0.8,
)


def lamp_shape(x0, x1, z0, z1, sweep=0.03):
    """A swept lamp outline for the +x side (inner edge x0, outer edge x1, bottom z0, top z1): the outer end is taller, the top edge slopes."""
    h = z1 - z0
    return [(x0, z0 + 0.20 * h), (x1 - 0.30 * (x1 - x0), z0), (x1, z0 + 0.12 * h), (x1 + sweep, z0 + 0.55 * h), (x1, z1), (x0 + 0.35 * (x1 - x0), z1 - 0.10 * h), (x0, z1 - 0.30 * h)]


def _cap_height(z0, z1, mx):
    """Limit a lamp's height to `mx` metres around its centre."""
    if z1 - z0 > mx:
        c = 0.5 * (z0 + z1)
        return c - 0.5 * mx, c + 0.5 * mx
    return z0, z1


def _fill_box(det, y, w, depth, h):
    """A dark box tucked under the outer shell around (0, y): its top follows the lowest point of the shell over its footprint, so it never shows through a low or tapered nose."""
    pts = [(x, y + dy) for x in (-w * 0.5, 0.0, w * 0.5) for dy in (-depth * 0.5, 0.0, depth * 0.5)]
    zs = []
    for x, yy in pts:
        hit = det.surf.top(x, yy)
        if hit is None:
            return
        zs.append(hit[0][2])
    top = min(zs) - 0.05
    h = min(h, top - 0.14)
    if h < 0.06:
        return
    box = kit.box((0, 0, 0), (w * 0.88, depth * 0.88, h))
    box.style(kit.D_UNDER, (0.012, 0.012, 0.014))
    det.mesh.add_mesh(box, kit.trans(0.0, y, top - h * 0.5))


def car_details(det):
    """The common surface details of a four-wheeled car from the archetype's `fx` table. Heights of the lamps, the grille and the plates are fractions (0 .. 1) of the
    height of the nose face (front) or the tail face (rear), measured on the finished shell, so a lamp always sits on the face whatever the car's shape."""
    d = det.d
    f = d["fx"]
    zf = lambda fr: det.fz("front", fr)
    zr = lambda fr: det.fz("rear", fr)
    fitf = lambda ol: det.fit_x(ol, "front")
    fitr = lambda ol: det.fit_x(ol, "rear")
    if "head" in f:
        x0, x1, g0, g1 = f["head"]
        z0, z1 = _cap_height(zf(g0), zf(g1), 0.27)             # a bus or a truck has a tall nose: its lamps stay lamps instead of becoming eyes
        if f.get("rect_lamps"):                                  # utility vehicles: plain rectangular clear lamps (a bezel and a reflector bowl read as angry eyes)
            det.lamp(fitf([(x0, z0), (x1, z0), (x1, z1), (x0, z1)]), "front", "head", bezel=False, detail=False)
        else:
            det.lamp(fitf(lamp_shape(x0, x1, z0, z1, f.get("sweep", 0.03))), "front", "head")
    if "grille" in f:
        x1, g0, g1, bars = f["grille"]
        det.grille(0.0, min(x1, det.face_half_width("front") * 0.55), zf(g0), zf(g1), bars=bars, plane="front", chrome=f.get("chrome", True))
    if "intake" in f:
        x1, g0, g1 = f["intake"]
        det.intake(min(x1, det.face_half_width("front") * 0.92), zf(g0), zf(g1), plane="front", slats=f.get("slats", 2))
    if "fog" in f:
        x0, x1, g0, g1 = f["fog"]
        det.lamp(fitf([(x0, zf(g0)), (x1, zf(g0)), (x1, zf(g1)), (x0, zf(g1))]), "front", "white", bezel=False)
    if "tail" in f:
        x0, x1, g0, g1 = f["tail"]
        z0, z1 = _cap_height(zr(g0), zr(g1), 0.30 if f.get("rect_lamps") else 0.25)
        if f.get("rect_lamps"):
            det.lamp(fitr([(x0, z0), (x1, z0), (x1, z1), (x0, z1)]), "rear", "tail", bezel=True, detail=False)
        else:
            det.lamp(fitr(lamp_shape(x0, x1, z0, z1, f.get("tsweep", 0.03))), "rear", "tail")
    if "rev" in f and f.get("rect_lamps"):                          # cars have the reverse lamp inside the tail cluster (see Detailer.lamp); utility vehicles a lamp of its own
        x0, x1, g0, g1 = f["rev"]
        x0, x1 = 0.33, 0.33 + (x1 - x0)                              # beside the plate, not at the corner where the bumper turns away
        g0, g1 = g0 + 0.05, g1 + 0.07
        det.lamp(fitr([(x0, zr(g0)), (x1, zr(g0)), (x1, zr(g1)), (x0, zr(g1))]), "rear", "rev", bezel=True, detail=False)
    if "plate_r" in f:
        z = zr(f["plate_r"])
        det.patch([(-0.29, z - 0.085), (0.29, z - 0.085), (0.29, z + 0.085), (-0.29, z + 0.085)], "rear", D_PLASTIC, (0.02, 0.02, 0.02), offset=0.003, rings=1)
        h = det.surf.rear(0.0, z)
        det.anchor("PlateR", (0.0, (h[0][1] if h else -d["L"] * 0.5) - 0.012, z))
    if "plate_f" in f:
        z = zf(f["plate_f"])
        h = det.surf.front(0.0, z)
        det.anchor("PlateF", (0.0, (h[0][1] if h else d["L"] * 0.5) + 0.012, z))
    if "exhaust" in f:
        ex = f["exhaust"]
        z = ex.get("z", zr(ex.get("g", 0.12)))
        det.exhaust(ex["x"], -d["L"] * 0.5 + 0.02, z, r=ex.get("r", 0.04), count=ex.get("n", 1), spread=ex.get("spread", 0.1))
        det.anchor("FxExhaust", (ex["x"][0], -d["L"] * 0.5, z))
    if "mirror" in f:
        y, z, off = f["mirror"]
        det.mirrors(y, z, off=off, scale=f.get("mirror_scale", 1.0))
    if "handles" in f:
        ys, z = f["handles"]
        det.handles(ys, z, painted=f.get("painted_handles", False))
    if "doors" in f:
        det.side_lines(f["doors"], f.get("z_belt", 0.93), f.get("z_door_low", 0.28))
    if det.lod == 0:                                              # what shows when the hood, the trunk lid or a bumper is torn off: a dark engine bay / trunk well
        Lh = d["L"] * 0.5
        _fill_box(det, Lh - 0.95, 0.9, 0.7, 0.26)
        if "rw" in d and d["rw"][1] > -8.0 and "bed" not in d:
            _fill_box(det, -Lh + 0.75, 0.9, 0.7, 0.22)
    det.anchor("FxEngine", (0.0, f.get("engine_y", d["L"] * 0.3), f.get("engine_z", 0.95)))
    c = d.get("cabin", {})
    det.anchor("Driver", (-c.get("seat_x", 0.40), c.get("seat_y", 0.10), c.get("seat_z", 0.46)))
    if "extras" in f and det.lod < 2:
        f["extras"](det)


# ------------------------------------------------------------------------------------------------------------------------------ sedan family
def _sedan_fx():
    return dict(head=(0.50, 0.86, 0.50, 0.88), grille=(0.46, 0.28, 0.66, 3), intake=(0.62, 0.02, 0.24), tail=(0.50, 0.88, 0.42, 0.92), rev=(0.40, 0.58, 0.06, 0.18),
                plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.55], g=0.10), mirror=(0.62, 1.03, 0.09), handles=([0.12, -0.78], 0.90), doors=[(0.62, -0.50), (-0.52, -1.26)],
                z_belt=0.93, z_door_low=0.28, engine_y=1.5, engine_z=0.95)


SEDAN = dict(
    BASE,
    name="sedan", R=0.35,
    top=[(2.255, 0.745, 0), (2.10, 0.80, 0.12), (0.85, 0.975, 0.45), (0.05, 1.43, 0.55), (-0.40, 1.455, 0), (-0.90, 1.435, 0.55),
         (-1.62, 1.00, 0.45), (-2.12, 0.945, 0.10), (-2.255, 0.88, 0)],
    belt=0.97,
    ws=(0.82, 0.05), rw=(-0.92, -1.58),
    windows=[(0.60, -0.46), (-0.62, -1.22)],
    fx=_sedan_fx(),
)


def _taxi_extras(det):
    from .kit import D_SIGN
    sign = kit.rbox((0, 0, 0), (0.62, 0.22, 0.13), 0.035, 1, "Details")
    sign.style(D_SIGN, (0.9, 0.75, 0.2))
    det.mesh.add_mesh(sign, kit.trans(0.0, -0.15, 1.455 + 0.075))
    foot = kit.box((0, 0, 0), (0.5, 0.12, 0.03))
    foot.style(D_PLASTIC, (0.02, 0.02, 0.02))
    det.mesh.add_mesh(foot, kit.trans(0.0, -0.15, 1.455 + 0.01))
    det.anchor("RoofSign", (0.0, -0.15, 1.53))


TAXI = copy.deepcopy(SEDAN)
TAXI.update(name="taxi")
TAXI["fx"]["extras"] = _taxi_extras


def _patrol_extras(det):
    from .kit import D_BLUE, D_RED
    bar = kit.rbox((0, 0, 0), (1.10, 0.28, 0.09), 0.03, 1, "Details")
    bar.style(D_PLASTIC, (0.03, 0.03, 0.035))
    det.mesh.add_mesh(bar, kit.trans(0.0, -0.1, 1.455 + 0.06))
    for sx, code, col in ((-1.0, D_BLUE, (0.05, 0.15, 0.95)), (1.0, D_RED, (0.95, 0.04, 0.03))):
        lens = kit.rbox((0, 0, 0), (0.48, 0.30, 0.06), 0.015, 1, "Details")
        lens.style(code, col)
        det.mesh.add_mesh(lens, kit.trans(sx * 0.27, -0.1, 1.455 + 0.115))
    # push bar on the nose
    for x in (-0.38, 0.0, 0.38):
        t = kit.tube([(x, 2.40, 0.40), (x, 2.46, 0.52), (x, 2.46, 0.68)], 0.025, sides=6, caps=True)
        t.style(D_PLASTIC, (0.02, 0.02, 0.02))
        det.mesh.add_mesh(t)
    rail = kit.tube([(-0.55, 2.46, 0.55), (0.55, 2.46, 0.55)], 0.03, sides=6, caps=True)
    rail.style(D_PLASTIC, (0.02, 0.02, 0.02))
    det.mesh.add_mesh(rail)
    det.anchor("LightBar", (0.0, -0.1, 1.56))


PATROL = copy.deepcopy(SEDAN)
PATROL.update(name="patrol", W=1.95)
PATROL["fx"]["extras"] = _patrol_extras


# ------------------------------------------------------------------------------------------------------------------------------ hatchback
HATCH = dict(
    BASE,
    name="hatch", L=3.9, W=1.76, R=0.31, tyre_w=0.195, track=1.46, axle_f=1.20, axle_r=-1.26, z_floor=0.15, z_sill=0.21, cap_f=0.10, cap_r=0.10, end_w_f=0.82, end_w_r=0.86, plan_len=0.6,
    top=[(1.85, 0.69, 0), (1.72, 0.755, 0.10), (0.80, 0.90, 0.35), (0.05, 1.34, 0.50), (-0.35, 1.36, 0), (-0.85, 1.345, 0.50), (-1.62, 0.98, 0.25), (-1.85, 0.88, 0)],
    belt=[(1.8, 0.86), (0.8, 0.90), (-1.8, 0.95)],
    ws=(0.78, 0.04), rw=(-0.90, -1.55),
    windows=[(0.55, -0.45), (-0.50, -1.15)],
    cabin=dict(dash_y=0.74, wheel_y=0.40, seat_y=0.06, seat_z=0.44, rear_y=-0.72, rear_z=0.47, liner_y=(0.78, -1.45), floor_z=0.26),
    fx=dict(head=(0.44, 0.78, 0.50, 0.88), grille=(0.40, 0.28, 0.66, 3), intake=(0.54, 0.02, 0.24), tail=(0.42, 0.80, 0.42, 0.92), rev=(0.34, 0.50, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.50], g=0.10), mirror=(0.55, 0.98, 0.09), handles=([0.10, -0.72], 0.86), doors=[(0.55, -0.45), (-0.48, -1.12)],
            z_belt=0.88, z_door_low=0.26, engine_y=1.3, engine_z=0.9),
)

# ------------------------------------------------------------------------------------------------------------------------------ coupe (racer)
COUPE = dict(
    BASE,
    name="coupe", L=4.3, W=1.88, R=0.32, tyre_w=0.235, track=1.57, axle_f=1.27, axle_r=-1.25, z_floor=0.13, z_sill=0.20, cap_f=0.11, cap_r=0.11, end_w_f=0.76, end_w_r=0.80, flare=(0.015, 0.03),
    top=[(2.04, 0.65, 0), (1.92, 0.71, 0.12), (0.72, 0.83, 0.45), (0.10, 1.185, 0.55), (-0.38, 1.205, 0), (-0.80, 1.15, 0.6), (-1.45, 0.93, 0.45), (-1.96, 0.90, 0.10), (-2.04, 0.84, 0)],
    belt=[(2.0, 0.80), (0.8, 0.84), (-0.8, 0.88), (-2.0, 0.91)],
    ws=(0.68, 0.05), rw=(-0.52, -1.28),
    windows=[(0.52, -0.58), (-0.68, -0.98)],
    cabin=dict(dash_y=0.68, wheel_y=0.38, seat_y=0.02, seat_z=0.35, rear_seat=False, liner_y=(0.74, -0.9), floor_z=0.21),
    p_gh=0.34,
    fx=dict(head=(0.46, 0.84, 0.50, 0.88), grille=(0.42, 0.28, 0.66, 4), intake=(0.60, 0.02, 0.24), tail=(0.44, 0.86, 0.42, 0.92), rev=(0.34, 0.50, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.46], g=0.10, n=2, spread=0.14, r=0.045), mirror=(0.48, 0.92, 0.09), handles=([0.05], 0.80), doors=[(0.52, -0.58)], z_belt=0.84,
            z_door_low=0.26, engine_y=1.3, engine_z=0.84),
)


def _coupe_extras(det):
    sp = kit.rbox((0, 0, 0), (1.5, 0.22, 0.03), 0.01, 1, "Details")
    sp.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
    det.mesh.add_mesh(sp, kit.trans(0.0, -1.85, 0.99))
    for sx in (-0.55, 0.55):
        st = kit.box((0, 0, 0), (0.04, 0.12, 0.06))
        st.style(D_PLASTIC, (0.02, 0.02, 0.02))
        det.mesh.add_mesh(st, kit.trans(sx, -1.85, 0.94))


COUPE["fx"]["extras"] = _coupe_extras

# ------------------------------------------------------------------------------------------------------------------------------ sports car (mid engine wedge)
SPORTS = dict(
    BASE,
    name="sports", L=4.5, W=1.92, R=0.335, R_r=0.355, arch_gap=0.04, tyre_w=0.24, tyre_w_r=0.29, track=1.58, axle_f=1.34, axle_r=-1.28, z_floor=0.11, z_sill=0.18, cap_f=0.12, cap_r=0.12, end_w_f=0.70, end_w_r=0.78,
    flare=(0.0, 0.05), b_hood=0.06, belt=[(2.1, 0.74), (0.9, 0.78), (-0.8, 0.88), (-2.1, 0.92)], p_gh=0.36, p_hood=0.18, crown=0.03, tuck=0.09,
    top=[(2.13, 0.52, 0), (1.95, 0.61, 0.12), (1.38, 0.76, 0.4), (0.95, 0.77, 0.5), (0.35, 0.83, 0.3), (-0.02, 1.215, 0.5), (-0.45, 1.22, 0.45), (-1.02, 1.0, 0.45), (-1.5, 0.98, 0.12), (-2.1, 0.96, 0.10), (-2.2, 0.86, 0)],
    ws=(0.35, 0.0), rw=(-0.55, -0.98),
    windows=[(0.30, -0.72)],
    cabin=dict(dash_y=0.50, wheel_y=0.22, seat_y=-0.18, seat_z=0.34, rear_seat=False, liner_y=(0.42, -0.9), floor_z=0.20, seat_x=0.36),
    fx=dict(head=(0.46, 0.84, 0.50, 0.88), grille=(0.38, 0.28, 0.66, 4), intake=(0.62, 0.02, 0.24), tail=(0.44, 0.88, 0.42, 0.92), rev=(0.30, 0.46, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.34], g=0.10, n=2, spread=0.14, r=0.05), mirror=(0.30, 0.90, 0.09), handles=([-0.08], 0.78), doors=[(0.30, -0.72)], z_belt=0.80,
            z_door_low=0.24, engine_y=-1.4, engine_z=0.92),
)


def _sports_extras(det):
    # rear wing on two thin painted stays
    wing = kit.rbox((0, 0, 0), (1.62, 0.28, 0.035), 0.012, 1, "Details")
    wing.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
    det.mesh.add_mesh(wing, kit.trans(0.0, -2.12, 1.20))
    for sx in (-0.50, 0.50):
        stay = kit.box((0, 0, 0), (0.035, 0.07, 0.17))
        stay.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
        det.mesh.add_mesh(stay.xformed(kit.rot_x(0.35)), kit.trans(sx, -2.06, 1.095))
        plate = kit.box((0, 0, 0), (0.03, 0.30, 0.10))
        plate.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
        det.mesh.add_mesh(plate, kit.trans(sx * 1.62, -2.12, 1.20))


SPORTS["fx"]["extras"] = _sports_extras

# ------------------------------------------------------------------------------------------------------------------------------ muscle car
MUSCLE = dict(
    BASE,
    name="muscle", L=5.0, W=1.90, R=0.34, R_r=0.355, tyre_w=0.245, tyre_w_r=0.285, track=1.56, axle_f=1.50, axle_r=-1.36, z_floor=0.15, z_sill=0.22, cap_f=0.12, cap_r=0.12, end_w_f=0.82, end_w_r=0.84,
    flare=(0.02, 0.05), b_hood=0.08, p_gh=0.28,
    top=[(2.38, 0.82, 0), (2.26, 0.90, 0.10), (0.60, 1.03, 0.35), (-0.10, 1.31, 0.45), (-0.55, 1.325, 0.0), (-1.00, 1.30, 0.5), (-1.45, 1.05, 0.3), (-2.30, 1.06, 0.10), (-2.38, 0.98, 0)],
    belt=[(2.3, 0.90), (0.6, 0.97), (-2.3, 1.02)],
    ws=(0.58, 0.0), rw=(-0.95, -1.38),
    windows=[(0.40, -0.72), (-0.82, -1.05)],
    cabin=dict(dash_y=0.54, wheel_y=0.20, seat_y=-0.12, seat_z=0.46, rear_y=-0.70, rear_z=0.5, liner_y=(0.56, -1.2), floor_z=0.28),
    fx=dict(head=(0.42, 0.86, 0.50, 0.88), grille=(0.38, 0.28, 0.66, 5), intake=(0.60, 0.02, 0.24), tail=(0.42, 0.88, 0.42, 0.92), rev=(0.36, 0.52, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.52], g=0.10, n=2, spread=0.14, r=0.05), mirror=(0.44, 1.04, 0.10), handles=([0.0, -0.9], 0.93), doors=[(0.40, -0.72), (-0.82, -1.08)],
            z_belt=0.97, z_door_low=0.28, engine_y=1.8, engine_z=1.05),
)


def _muscle_extras(det):
    scoop = kit.rbox((0, 0, 0), (0.54, 0.62, 0.075), 0.03, 1, "Details")
    scoop.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
    det.mesh.add_mesh(scoop, kit.trans(0.0, 1.45, 1.01))
    dark = kit.box((0, 0, 0), (0.40, 0.08, 0.05))
    dark.style(kit.D_UNDER, (0.01, 0.01, 0.012))
    det.mesh.add_mesh(dark, kit.trans(0.0, 1.76, 1.04))
    for sx in (-0.45, 0.45):                                           # chrome bumper blades
        pass
    bar = kit.rbox((0, 0, 0), (1.62, 0.07, 0.07), 0.02, 1, "Details")
    bar.style(D_CHROME, (0.62, 0.64, 0.68))
    det.mesh.add_mesh(bar, kit.trans(0.0, 2.46, 0.36))
    det.mesh.add_mesh(bar, kit.trans(0.0, -2.46, 0.41))


MUSCLE["fx"]["extras"] = _muscle_extras

# ------------------------------------------------------------------------------------------------------------------------------ SUV
SUV = dict(
    BASE,
    name="suv", L=4.7, W=1.98, R=0.38, tyre_w=0.255, track=1.66, axle_f=1.40, axle_r=-1.42, z_floor=0.27, z_sill=0.35, arch_gap=0.07, cap_f=0.12, cap_r=0.12, end_w_f=0.86, end_w_r=0.86, plan_len=0.6,
    flare=(0.03, 0.03), b_hood=0.09, p_hood=0.12, p_gh=0.20, tuck=0.04, bulge=0.0, rise=0.35, trim_slot=3, cap_s=(0.9, 0.92),
    top=[(2.23, 0.93, 0), (2.12, 1.0, 0.10), (0.95, 1.12, 0.4), (0.28, 1.72, 0.30), (-1.9, 1.74, 0.35), (-2.22, 1.58, 0.15), (-2.30, 1.30, 0)],
    belt=[(2.2, 1.06), (0.9, 1.12), (-2.2, 1.18)],
    ws=(0.92, 0.22), rw=(-2.0, -2.24),
    windows=[(0.55, -0.58), (-0.72, -1.55), (-1.62, -2.0)],
    cabin=dict(dash_y=0.78, wheel_y=0.42, seat_y=0.10, seat_z=0.62, rear_y=-0.92, rear_z=0.66, seat_x=0.42, liner_y=(0.88, -2.0), floor_z=0.40),
    fx=dict(head=(0.52, 0.90, 0.50, 0.88), grille=(0.48, 0.28, 0.66, 4), intake=(0.60, 0.02, 0.24), tail=(0.56, 0.93, 0.42, 0.92), rev=(0.40, 0.56, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.56], g=0.10), mirror=(0.58, 1.18, 0.10), handles=([0.15, -0.9], 1.0), doors=[(0.60, -0.60), (-0.64, -1.68)], z_belt=1.05, z_door_low=0.38,
            engine_y=1.5, engine_z=1.1),
)


def _suv_extras(det):
    for sgn in (-1.0, 1.0):                                            # roof rails follow the roof surface
        pts = det.roof_line(sgn * 0.70, 0.05, -1.95, lift=0.035, n=14)
        if len(pts) > 2:
            r = kit.tube(pts, 0.022, sides=6, caps=True)
            r.style(D_PLASTIC, (0.02, 0.02, 0.02))
            det.mesh.add_mesh(r)
            for k in (1, len(pts) // 2, len(pts) - 2):
                f = kit.box((0, 0, 0), (0.05, 0.05, 0.05))
                f.style(D_PLASTIC, (0.02, 0.02, 0.02))
                det.mesh.add_mesh(f, kit.trans(*(pts[k] - np.array([0.0, 0.0, 0.02]))))
    sk = kit.rbox((0, 0, 0), (1.0, 0.07, 0.08), 0.02, 1, "Details")
    sk.style(D_CHROME, (0.55, 0.57, 0.6))
    det.mesh.add_mesh(sk, kit.trans(0.0, 2.38, 0.40))


SUV["fx"]["extras"] = _suv_extras

# ------------------------------------------------------------------------------------------------------------------------------ pickup truck
PICKUP = dict(
    BASE,
    name="pickup", L=5.0, W=1.95, R=0.41, tyre_w=0.265, track=1.66, axle_f=1.55, axle_r=-1.45, z_floor=0.30, z_sill=0.40, arch_gap=0.08, cap_f=0.12, cap_r=0.10, end_w_f=0.86, end_w_r=0.90, plan_len=0.6,
    flare=(0.03, 0.03), b_hood=0.09, p_hood=0.12, p_gh=0.22, tuck=0.04, bulge=0.0, rise=0.3, trim_slot=3, cap_s=(0.9, 0.92),
    top=[(2.38, 0.95, 0), (2.26, 1.02, 0.10), (1.05, 1.14, 0.4), (0.50, 1.78, 0.30), (-0.30, 1.80, 0.35), (-0.60, 1.60, 0.2), (-0.63, 1.16, 0.0), (-0.80, 1.14, 0.10), (-2.38, 1.14, 0)],
    belt=[(2.3, 1.08), (1.0, 1.14), (-0.55, 1.18), (-2.4, 1.14)],
    ws=(1.0, 0.30), rw=(-0.40, -0.58),
    windows=[(0.75, -0.18)],
    bed=(-0.84, -2.30),
    cabin=dict(dash_y=0.85, wheel_y=0.50, seat_y=0.2, seat_z=0.70, rear_seat=False, seat_x=0.42, liner_y=(0.92, -0.58), floor_z=0.46),
    fx=dict(head=(0.52, 0.90, 0.50, 0.88), grille=(0.48, 0.28, 0.66, 4), intake=(0.62, 0.02, 0.24), tail=(0.80, 0.92, 0.42, 0.92), rev=(0.40, 0.56, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.62], g=0.10), mirror=(0.66, 1.22, 0.11), handles=([0.25], 1.02), doors=[(0.75, -0.30)], z_belt=1.06, z_door_low=0.44, engine_y=1.6,
            engine_z=1.15),
)


def _pickup_extras(det):
    L = det.d["L"]
    # load bed: floor, inner walls, headboard, tailgate inner face
    y0, y1 = -0.86, -2.36
    floor = kit.box((0, 0, 0), (1.56, abs(y1 - y0), 0.05))
    floor.style(D_PLASTIC, (0.025, 0.025, 0.028))
    det.mesh.add_mesh(floor, kit.trans(0.0, (y0 + y1) * 0.5, 0.82))
    for sx in (-0.80, 0.80):
        wall = kit.box((0, 0, 0), (0.06, abs(y1 - y0), 0.34))
        wall.style(D_PLASTIC, (0.03, 0.03, 0.034))
        det.mesh.add_mesh(wall, kit.trans(sx, (y0 + y1) * 0.5, 0.99))
    head = kit.box((0, 0, 0), (1.62, 0.06, 0.40))
    head.style(D_PLASTIC, (0.03, 0.03, 0.034))
    det.mesh.add_mesh(head, kit.trans(0.0, y0 + 0.03, 1.00))
    tg = kit.box((0, 0, 0), (1.62, 0.06, 0.34))
    tg.style(D_PLASTIC, (0.03, 0.03, 0.034))
    det.mesh.add_mesh(tg, kit.trans(0.0, y1 - 0.03, 0.99))
    # rails along the top of the walls: painted
    for sx in (-0.80, 0.80):
        rail = kit.rbox((0, 0, 0), (0.12, abs(y1 - y0) + 0.06, 0.03), 0.01, 1, "Details")
        rail.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
        det.mesh.add_mesh(rail, kit.trans(sx, (y0 + y1) * 0.5, 1.165))
    bar = kit.tube([(-0.7, y0 - 0.05, 1.10), (-0.7, y0 - 0.05, 1.62), (0.7, y0 - 0.05, 1.62), (0.7, y0 - 0.05, 1.10)], 0.025, sides=6, caps=True)
    bar.style(D_CHROME, (0.55, 0.57, 0.6))
    det.mesh.add_mesh(bar)


PICKUP["fx"]["extras"] = _pickup_extras

# ------------------------------------------------------------------------------------------------------------------------------ van
VAN = dict(
    BASE,
    name="van", L=5.2, W=2.0, R=0.36, tyre_w=0.235, track=1.72, axle_f=1.72, axle_r=-1.55, z_floor=0.26, z_sill=0.33, arch_gap=0.07, cap_f=0.12, cap_r=0.10, cap_s=(0.84, 0.9), end_w_f=0.9, end_w_r=0.94,
    plan_len=0.5, b_hood=0.10, p_hood=0.12, p_gh=0.14, tuck=0.02, bulge=0.0, m_lo=5.0, rise=0.3, trim_slot=3, crown=0.04,
    top=[(2.48, 0.98, 0), (2.38, 1.14, 0.12), (1.72, 1.26, 0.25), (0.92, 2.08, 0.25), (0.55, 2.10, 0), (-2.40, 2.10, 0.15), (-2.55, 2.0, 0)],
    belt=[(2.4, 1.0), (0.9, 1.06), (-2.5, 1.06)],
    ws=(1.62, 0.95), rw=(-9.0, -9.0),
    windows=[(0.82, 0.05)],
    cabin=dict(dash_y=1.00, wheel_y=0.60, seat_y=0.32, seat_z=0.74, rear_seat=False, seat_x=0.44, liner_y=(1.08, -0.1), floor_z=0.46),
    fx=dict(rect_lamps=True, head=(0.54, 0.92, 0.50, 0.88), grille=(0.50, 0.28, 0.66, 4), intake=(0.64, 0.02, 0.24), tail=(0.78, 0.96, 0.42, 0.92), rev=(0.40, 0.56, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, exhaust=dict(x=[0.70], g=0.10), mirror=(0.98, 1.28, 0.12, ), handles=([0.35], 1.04), doors=[(0.82, -0.05)], z_belt=1.04, z_door_low=0.36,
            engine_y=2.0, engine_z=1.2, mirror_scale=1.4),
)


def _van_extras(det):
    # sliding door rails and the rear door split
    for sgn in (1.0, -1.0):
        plane = "right" if sgn > 0 else "left"
        det.ribbon([(-0.15, 0.38), (-0.15, 1.95)], plane, 0.008, D_PLASTIC, kit.hexlin("#050505"), offset=0.003)
        det.ribbon([(-1.55, 0.38), (-1.55, 1.95)], plane, 0.008, D_PLASTIC, kit.hexlin("#050505"), offset=0.003)
        det.ribbon([(-0.15, 0.38), (-1.55, 0.38)], plane, 0.008, D_PLASTIC, kit.hexlin("#050505"), offset=0.003)
    det.ribbon([(0.0, 0.40), (0.0, 1.95)], "rear", 0.01, D_PLASTIC, kit.hexlin("#050505"), offset=0.003)
    for sx in (-0.45, 0.45):
        det.ribbon([(sx, 1.25), (sx + 0.0, 1.45)], "rear", 0.04, D_CHROME, kit.hexlin("#a0a4a8"), offset=0.005)


VAN["fx"]["extras"] = _van_extras

# ------------------------------------------------------------------------------------------------------------------------------ box truck
TRUCK = dict(
    BASE,
    name="boxtruck", L=6.4, W=2.2, R=0.44, tyre_w=0.275, track=1.84, axle_f=2.18, axle_r=-1.72, z_floor=0.30, z_sill=0.40, arch_gap=0.08, cap_f=0.12, cap_r=0.10,
    cap_s_f=(0.9, 0.92), cap_s_r=(0.985, 0.985), end_w_f=0.92, end_w_r=0.99, plan_len=0.5, b_hood=0.10, p_hood=0.10, p_gh=0.10, tuck=0.02, bulge=0.0, m_lo=5.0, rise=0.2, crown=0.02,
    half_w_keys=[(3.1, 1.02), (1.5, 1.02), (1.3, 1.08), (1.1, 1.10), (-3.1, 1.10)],
    sill_keys=[(3.1, 0.42), (1.45, 0.42), (1.3, 0.92), (-3.1, 0.92)],
    top=[(3.08, 1.30, 0), (2.98, 1.62, 0.12), (2.62, 2.42, 0.2), (2.30, 2.58, 0.15), (1.45, 2.60, 0.0), (1.34, 2.94, 0.0), (1.20, 2.96, 0.0), (-3.2, 2.96, 0.0)],
    belt=[(3.1, 1.12), (1.5, 1.12)],
    ws=(2.72, 2.35), rw=(-9.0, -9.0), windows=[(2.20, 1.6)],
    axle_f_extra=0,
    cabin=dict(dash_y=2.5, wheel_y=2.2, seat_y=1.95, seat_z=0.9, rear_seat=False, seat_x=0.42, liner_y=(2.7, 1.5), floor_z=0.7),
    fx=dict(head=(0.52, 0.88, 0.50, 0.88), grille=(0.52, 0.28, 0.66, 5), intake=(0.70, 0.02, 0.24), tail=(0.80, 1.02, 0.42, 0.92), rev=(0.40, 0.56, 0.06, 0.18),
            plate_r=0.38, plate_f=0.26, mirror=(2.30, 2.02, 0.20), handles=([1.9], 1.35), doors=[(2.5, 1.55)], z_belt=1.5, z_door_low=0.7, engine_y=3.0, engine_z=1.4, mirror_scale=1.6,
            rect_lamps=True),
)


def _truck_extras(det):
    from .kit import D_UNDER
    # chassis rails and fuel tank under the box, rear bumper, roll door lines on the box
    Lh = det.d["L"] * 0.5
    rail_len = det.d["L"] - 2.1
    for sx in (-0.55, 0.55):
        rail = kit.box((0, 0, 0), (0.12, rail_len, 0.16))
        rail.style(D_UNDER, (0.012, 0.012, 0.014))
        det.mesh.add_mesh(rail, kit.trans(sx, -Lh + 0.2 + rail_len * 0.5, 0.6))
    tank = kit.cylinder((-1.0, 0.75, 0.62), (-1.0, -0.35, 0.62), 0.24, 0.24, seg=10, mat="Details")
    tank.style(D_CHROME, (0.35, 0.37, 0.4))
    det.mesh.add_mesh(tank)
    for yy in (0.5, 0.0):                                                  # tank straps
        strap = kit.cylinder((-1.0, yy + 0.02, 0.62), (-1.0, yy - 0.02, 0.62), 0.255, 0.255, seg=10, mat="Details")
        strap.style(D_PLASTIC, (0.04, 0.04, 0.045))
        det.mesh.add_mesh(strap)
    d_ = det.d
    for sgn in (1.0, -1.0):                                                # a cab step under each door
        ya, yb = d_["fx"]["doors"][0] if d_["fx"].get("doors") else (2.3, 1.5)
        stp = kit.rbox((0, 0, 0), (0.22, abs(ya - yb) * 0.7, 0.05), 0.012, 1, "Details")
        stp.style(D_PLASTIC, (0.03, 0.03, 0.034))
        det.mesh.add_mesh(stp, kit.trans(sgn * (d_["W"] * 0.5 + 0.02), (ya + yb) * 0.5, d_["z_sill"] + 0.02))
    bump = kit.rbox((0, 0, 0), (2.2, 0.16, 0.22), 0.04, 1, "Details")
    bump.style(D_PLASTIC, (0.02, 0.02, 0.022))
    det.mesh.add_mesh(bump, kit.trans(0.0, -Lh - 0.06, 0.62))
    for sgn in (1.0, -1.0):
        det.ribbon([(1.3, 1.0), (1.3, 2.9)], "right" if sgn > 0 else "left", 0.012, D_PLASTIC, kit.hexlin("#050505"), offset=0.003)
    det.ribbon([(-0.02, 1.0), (-0.02, 2.88)], "rear", 0.012, D_PLASTIC, kit.hexlin("#050505"), offset=0.003)
    for z in (1.25, 1.65, 2.05, 2.45):
        det.ribbon([(-0.95, z), (0.95, z)], "rear", 0.008, D_PLASTIC, kit.hexlin("#0a0a0a"), offset=0.003)


TRUCK["fx"]["extras"] = _truck_extras

# ------------------------------------------------------------------------------------------------------------------------------ bus
BUS = dict(
    BASE,
    name="bus", L=9.5, W=2.5, R=0.46, tyre_w=0.28, track=2.04, axle_f=3.05, axle_r=-2.5, z_floor=0.32, z_sill=0.42, arch_gap=0.09, cap_f=0.12, cap_r=0.12, cap_s=(0.95, 0.97), end_w_f=0.93, end_w_r=0.96,
    plan_len=0.6, b_hood=0.12, p_hood=0.08, p_gh=0.10, tuck=0.02, bulge=0.0, m_lo=6.0, rise=0.1, crown=0.02,
    top=[(4.63, 1.55, 0), (4.52, 2.1, 0.12), (4.12, 3.12, 0.2), (3.8, 3.2, 0.1), (-4.6, 3.2, 0.1), (-4.68, 3.0, 0)],
    belt=[(4.6, 1.06), (-4.6, 1.06)],
    ws=(4.5, 4.15), rw=(-9.0, -9.0),
    windows=[(3.9, 2.7), (2.55, 1.5), (1.35, 0.2), (0.05, -1.2), (-1.35, -2.6), (-2.75, -4.1)],
    cabin=dict(dash_y=4.0, wheel_y=3.7, seat_y=3.3, seat_z=0.9, rear_seat=False, seat_x=0.8, liner_y=(4.4, -4.4), floor_z=0.7),
    fx=dict(rect_lamps=True, head=(0.82, 1.10, 0.14, 0.36), grille=(0.62, 0.42, 0.78, 4), tail=(0.84, 1.10, 0.16, 0.34), rev=(0.50, 0.62, 0.16, 0.24), plate_r=0.38, plate_f=0.10, mirror=(4.1, 2.3, 0.22), doors=[(3.85, 2.75)], z_belt=1.1,
            z_door_low=0.45, handles=([-0.8], 1.2), engine_y=-3.5, engine_z=2.4, mirror_scale=2.0),
)

def _bus_extras(det):
    # destination board on the top of the windscreen, a front door outline on the kerb side, a rear window
    det.patch([(-0.80, 2.66), (0.80, 2.66), (0.80, 2.90), (-0.80, 2.90)], "front", kit.D_SIGN, (1.0, 0.62, 0.12), offset=0.012, rings=1)
    z0 = det.d["z_sill"] + 0.18
    det.ribbon([(3.85, z0), (2.75, z0), (2.75, 2.45), (3.85, 2.45), (3.85, z0)], "right", 0.014, D_PLASTIC, (0.02, 0.02, 0.025), offset=0.006)
    det.ribbon([(3.30, z0), (3.30, 2.45)], "right", 0.012, D_PLASTIC, (0.02, 0.02, 0.025), offset=0.006)
    det.patch([(-0.95, 1.55), (0.95, 1.55), (0.95, 2.35), (-0.95, 2.35)], "rear", kit.D_UNDER, (0.01, 0.012, 0.016), offset=0.004, rings=1)


BUS["fx"]["extras"] = _bus_extras

# ------------------------------------------------------------------------------------------------------------------------------ hover car
HOVER = dict(
    BASE,
    name="hover", L=4.6, W=2.0, R=0.3, tyre_w=0.2, track=1.6, axle_f=1.4, axle_r=-1.4, z_floor=0.52, z_sill=0.6, arches=False, cap_f=0.14, cap_r=0.14, end_w_f=0.66, end_w_r=0.74, plan_len=0.9,
    b_hood=0.07, p_hood=0.20, p_gh=0.40, crown=0.04, tuck=0.12, m_lo=2.0, rise=0.0,
    top=[(2.28, 0.76, 0), (2.10, 0.84, 0.15), (0.9, 0.97, 0.55), (0.25, 1.12, 0.6), (-0.4, 1.15, 0.6), (-1.1, 1.02, 0.5), (-2.1, 0.94, 0.12), (-2.28, 0.86, 0)],
    belt=[(2.2, 0.88), (-2.2, 0.90)],
    ws=(0.8, 0.0), rw=(-0.5, -1.2),
    windows=[(0.60, -1.00)],
    cabin=dict(dash_y=0.62, wheel_y=0.3, seat_y=0.05, seat_z=0.62, rear_seat=False, seat_x=0.38, liner_y=(0.72, -1.1), floor_z=0.7),
    fx=dict(head=(0.40, 0.86, 0.50, 0.88), tail=(0.30, 0.82, 0.42, 0.92), plate_r=0.38, plate_f=0.26, mirror=(0.5, 0.98, 0.07, ), handles=([0.1], 0.82), doors=[(0.62, -1.0)], z_belt=0.88, z_door_low=0.66,
            engine_y=1.2, engine_z=0.95, mirror_scale=0.7),
)


def _hover_pod(det, cx, cy, cz=0.50):
    """A ducted fan thruster under the body: a ring duct, a dark inner wall, eight stator blades round a hub and the glow disc below them."""
    from .kit import D_GLOW
    duct = kit.torus((cx, cy, cz), 0.30, 0.05, seg=24, sides=8, axis="z", mat="Details")
    duct.style(D_CHROME, (0.16, 0.18, 0.20))
    det.mesh.add_mesh(duct)
    inner = kit.cylinder((cx, cy, cz + 0.10), (cx, cy, cz - 0.04), 0.255, 0.255, seg=24, mat="Details", caps=(False, False))
    inner.style(kit.D_UNDER, (0.01, 0.01, 0.012))
    det.mesh.add_mesh(inner)
    glow = kit.revolve([(0.0, 0.0), (0.0, 0.25)], seg=24, axis="z", center=(cx, cy, cz - 0.03), mat="Details")
    glow.style(D_GLOW, (0.2, 0.9, 1.0))
    det.mesh.add_mesh(glow)
    for k in range(8):
        a = k * math.pi / 4.0
        blade = kit.box((0, 0, 0), (0.20, 0.045, 0.012))
        blade.style(D_CHROME, (0.30, 0.32, 0.36))
        det.mesh.add_mesh(blade.xformed(kit.rot_z(a)), kit.trans(cx + 0.14 * math.cos(a), cy + 0.14 * math.sin(a), cz + 0.03))
    hub = kit.cylinder((cx, cy, cz + 0.06), (cx, cy, cz - 0.02), 0.06, 0.06, seg=12, mat="Details")
    hub.style(D_CHROME, (0.20, 0.20, 0.22))
    det.mesh.add_mesh(hub)
    strut = kit.box((0, 0, 0), (0.10, 0.10, 0.22))
    strut.style(kit.D_UNDER, (0.012, 0.012, 0.014))
    det.mesh.add_mesh(strut, kit.trans(cx * 0.82, cy, cz + 0.20))


def _hover_extras(det):
    from .kit import D_GLOW
    for sx in (-0.78, 0.78):
        for y in (1.36, -1.36):
            if det.lod == 0:
                _hover_pod(det, sx, y)
                continue
            ring = kit.revolve([(0.0, 0.0), (0.0, 0.30)], seg=16, axis="z", center=(sx, y, 0.50), mat="Details")
            ring.style(D_GLOW, (0.2, 0.9, 1.0))
            det.mesh.add_mesh(ring)
            cone = kit.cylinder((sx, y, 0.60), (sx, y, 0.50), 0.30, 0.22, seg=14, mat="Details", caps=(False, False))
            cone.style(kit.D_UNDER, (0.01, 0.01, 0.012))
            det.mesh.add_mesh(cone)
    for sgn in (1.0, -1.0):
        det.ribbon([(1.7, 0.66), (-1.9, 0.66)], "right" if sgn > 0 else "left", 0.03, D_GLOW, (0.2, 0.9, 1.0), offset=0.004)
    fin = kit.box((0, 0, 0), (0.04, 0.5, 0.32))
    fin.style(kit.D_PAINTED, (0.5, 0.5, 0.5))
    for sx in (-0.72, 0.72):
        det.mesh.add_mesh(fin, kit.trans(sx, -2.05, 1.0))
    if det.lod == 0:                                                 # an underbody diffuser with strakes and two rear thrust nozzles
        for k in range(7):
            strake = kit.box((0, 0, 0), (0.025, 1.0, 0.14))
            strake.style(kit.D_UNDER, (0.012, 0.012, 0.014))
            det.mesh.add_mesh(strake, kit.trans(-0.6 + 0.2 * k, -1.85, 0.52))
        for sx in (-0.38, 0.38):
            noz = kit.cylinder((sx, -2.18, 0.82), (sx, -2.36, 0.82), 0.10, 0.13, seg=14, mat="Details", caps=(False, False))
            noz.style(D_CHROME, (0.22, 0.24, 0.28))
            det.mesh.add_mesh(noz.xformed(np.eye(4)))
            core = kit.revolve([(0.0, 0.0), (0.0, 0.10)], seg=14, axis="y", center=(sx, -2.36, 0.82), mat="Details")
            core.style(D_GLOW, (0.2, 0.9, 1.0))
            det.mesh.add_mesh(core)
        for sgn in (1.0, -1.0):                                       # canopy rails
            rail = kit.tube([(sgn * 0.66, 0.62, 1.02), (sgn * 0.7, -0.2, 1.1), (sgn * 0.66, -1.1, 1.0)], 0.018, sides=6, caps=True)
            rail.style(D_CHROME, (0.3, 0.32, 0.36))
            det.mesh.add_mesh(rail)


HOVER["fx"]["extras"] = _hover_extras
# ------------------------------------------------------------------------------------------------------------------------------ variants (the other street kinds)
def variant(base, name, fx=None, **kw):
    v = copy.deepcopy(base)
    v.update(name=name, **kw)
    if fx:
        v["fx"] = dict(v["fx"], **fx)
    return v


def _bar(det, y, z, w=1.1, length=0.28, h=0.09, colors=True):
    from .kit import D_BLUE, D_RED
    bar = kit.rbox((0, 0, 0), (w, length, h), 0.03, 1, "Details")
    bar.style(D_PLASTIC, (0.03, 0.03, 0.035))
    det.mesh.add_mesh(bar, kit.trans(0.0, y, z))
    for sx, code, col in ((-1.0, D_BLUE, (0.05, 0.15, 0.95)), (1.0, D_RED, (0.95, 0.04, 0.03))):
        lens = kit.rbox((0, 0, 0), (w * 0.44, length * 1.05, h * 0.7), 0.015, 1, "Details")
        lens.style(code, col)
        det.mesh.add_mesh(lens, kit.trans(sx * w * 0.25, y, z + h * 0.55))


WAGON = variant(
    SEDAN, "wagon", L=4.92, W=1.90, tyre_w=0.22, axle_f=1.46, axle_r=-1.44,
    top=[(2.34, 0.745, 0), (2.18, 0.80, 0.12), (0.85, 0.975, 0.45), (0.05, 1.48, 0.55), (-0.45, 1.505, 0), (-1.85, 1.495, 0.45), (-2.30, 1.10, 0.25), (-2.34, 1.0, 0)],
    belt=[(2.3, 0.93), (0.8, 0.97), (-2.3, 1.03)], rw=(-2.08, -2.32), ws=(0.82, 0.05),
    windows=[(0.60, -0.46), (-0.62, -1.20), (-1.30, -2.0)],
    cabin=dict(dash_y=0.80, wheel_y=0.44, seat_y=0.10, seat_z=0.46, rear_y=-0.82, rear_z=0.50, liner_y=(0.84, -2.0), floor_z=0.28),
)
WAGON["fx"] = dict(_sedan_fx(), tail=(0.52, 0.90, 0.30, 0.95), rev=(0.40, 0.56, 0.06, 0.16), plate_r=0.32, doors=[(0.62, -0.50), (-0.52, -1.26)])


def _wagon_extras(det):
    for sgn in (-1.0, 1.0):
        pts = det.roof_line(sgn * 0.70, 0.0, -2.0, lift=0.03, n=12)
        if len(pts) > 2:
            r = kit.tube(pts, 0.02, sides=6, caps=True)
            r.style(D_PLASTIC, (0.02, 0.02, 0.02))
            det.mesh.add_mesh(r)


WAGON["fx"]["extras"] = _wagon_extras

LIMO = variant(
    SEDAN, "limo", L=5.4, W=1.95, R=0.36, tyre_w=0.235, track=1.62, axle_f=1.70, axle_r=-1.68, z_floor=0.17, z_sill=0.25, cap_f=0.12, cap_r=0.12,
    top=[(2.58, 0.78, 0), (2.42, 0.84, 0.12), (1.05, 1.0, 0.45), (0.25, 1.46, 0.55), (-0.50, 1.49, 0), (-1.70, 1.485, 0.55), (-2.30, 1.05, 0.45), (-2.58, 1.0, 0.10)],
    belt=[(2.6, 0.99), (-2.6, 1.04)], ws=(0.95, 0.2), rw=(-1.85, -2.25),
    windows=[(0.70, -0.48), (-0.62, -1.28), (-1.34, -1.8)],
    cabin=dict(dash_y=0.90, wheel_y=0.52, seat_y=0.20, seat_z=0.48, rear_y=-1.30, rear_z=0.52, liner_y=(0.95, -2.0), floor_z=0.30, tan=True),
)
LIMO["fx"] = dict(_sedan_fx(), doors=[(0.70, -0.52), (-0.60, -1.32)], handles=([0.15, -0.95], 0.92), mirror=(0.70, 1.05, 0.09), z_belt=0.98)

AMBULANCE = variant(
    VAN, "ambulance", L=5.4, W=2.05, R=0.375, tyre_w=0.235,
    top=[(2.58, 0.98, 0), (2.48, 1.14, 0.12), (1.82, 1.26, 0.25), (1.05, 2.04, 0.25), (0.35, 2.1, 0.15), (0.12, 2.42, 0.12), (-2.52, 2.43, 0.15), (-2.7, 2.3, 0)],
    belt=[(2.5, 1.0), (0.9, 1.06), (-2.6, 1.06)], ws=(1.7, 1.0), windows=[(0.86, 0.3)],
    cabin=dict(dash_y=1.04, wheel_y=0.62, seat_y=0.36, seat_z=0.74, rear_seat=False, seat_x=0.44, liner_y=(1.12, 0.2), floor_z=0.46),
)


def _ambulance_extras(det):
    _van_extras(det)
    _bar(det, 0.55, 2.145, w=1.2, length=0.3, h=0.1)
    for sx in (-0.8, 0.8):
        lamp = kit.box((0, 0, 0), (0.12, 0.06, 0.1))
        lamp.style(kit.D_RED, (0.95, 0.04, 0.03))
        det.mesh.add_mesh(lamp, kit.trans(sx, -2.72, 1.9))
    det.anchor("LightBar", (0.0, 0.55, 2.2))


AMBULANCE["fx"] = dict(VAN["fx"], extras=_ambulance_extras, doors=[(0.86, 0.3)])

ARMOURED = variant(
    VAN, "armoured", L=5.4, W=2.2, R=0.40, tyre_w=0.26, track=1.84, z_sill=0.4,
    top=[(2.58, 1.05, 0), (2.48, 1.2, 0.1), (1.8, 1.32, 0.2), (1.05, 2.0, 0.2), (0.5, 2.5, 0.1), (-2.55, 2.5, 0.12), (-2.7, 2.35, 0)],
    belt=[(2.5, 1.3), (-2.6, 1.3)], windows=[(0.78, 0.4)], ws=(1.7, 1.08),
    cabin=dict(dash_y=1.05, wheel_y=0.62, seat_y=0.36, seat_z=0.78, rear_seat=False, seat_x=0.46, liner_y=(1.12, 0.3), floor_z=0.5),
)


def _armoured_extras(det):
    L = det.d["L"]
    for sgn in (1.0, -1.0):                                        # bolted armour plates on the flanks
        plane = "right" if sgn > 0 else "left"
        for (ya, yb) in ((0.2, -0.9), (-1.0, -2.0)):
            det.patch([(ya, 0.55), (yb, 0.55), (yb, 1.9), (ya, 1.9)], plane, D_PLASTIC, (0.03, 0.035, 0.04), offset=0.012, rings=2)
            for yy in (ya - 0.1, (ya + yb) * 0.5, yb + 0.1):
                for zz in (0.7, 1.7):
                    h = det.surf.side(yy, zz, sgn)
                    if h is not None:
                        b = kit.box((0, 0, 0), (0.03, 0.05, 0.05))
                        b.style(D_CHROME, (0.3, 0.32, 0.35))
                        det.mesh.add_mesh(b, kit.trans(*(h[0] + h[1] * 0.02)))
    bb = kit.tube([(-0.9, L * 0.5 + 0.06, 0.45), (-0.9, L * 0.5 + 0.1, 1.0), (0.9, L * 0.5 + 0.1, 1.0), (0.9, L * 0.5 + 0.06, 0.45)], 0.05, sides=6, caps=True)
    bb.style(D_PLASTIC, (0.02, 0.02, 0.022))
    det.mesh.add_mesh(bb)
    ring = kit.torus((0.0, -0.8, 2.55), 0.42, 0.04, seg=16, sides=5, axis="z", mat="Details")
    ring.style(D_PLASTIC, (0.02, 0.02, 0.022))
    det.mesh.add_mesh(ring)
    gun = kit.cylinder((0.0, -0.8, 2.6), (0.0, -0.3, 2.62), 0.05, 0.04, seg=8, mat="Details")
    gun.style(D_PLASTIC, (0.015, 0.015, 0.018))
    det.mesh.add_mesh(gun)


ARMOURED["fx"] = dict(VAN["fx"], extras=_armoured_extras, doors=[(0.78, 0.4)], handles=([0.4], 1.35), mirror=(1.0, 1.55, 0.12))

DELIVERY = variant(
    TRUCK, "delivery", L=5.8, W=2.1, R=0.40, tyre_w=0.25, track=1.76, axle_f=1.95, axle_r=-1.55,
    half_w_keys=[(2.8, 0.97), (1.4, 0.97), (1.25, 1.03), (1.0, 1.05), (-2.8, 1.05)],
    sill_keys=[(2.8, 0.40), (1.3, 0.40), (1.15, 0.80), (-2.8, 0.80)],
    top=[(2.78, 1.22, 0), (2.68, 1.5, 0.12), (2.35, 2.05, 0.2), (2.0, 2.18, 0.15), (1.28, 2.20, 0.0), (1.15, 2.68, 0.0), (1.0, 2.7, 0.0), (-2.85, 2.7, 0.0)],
    belt=[(2.8, 1.1), (1.5, 1.1)], ws=(2.4, 2.05), windows=[(1.95, 1.4)],
    cabin=dict(dash_y=2.2, wheel_y=1.95, seat_y=1.7, seat_z=0.88, rear_seat=False, seat_x=0.42, liner_y=(2.4, 1.3), floor_z=0.66),
)
DELIVERY["fx"] = dict(TRUCK["fx"], doors=[(2.25, 1.35)], mirror=(2.05, 1.98, 0.2), extras=_truck_extras)

GARBAGE = variant(
    TRUCK, "garbage", L=6.5, W=2.3, R=0.45, tyre_w=0.28,
    top=[(3.18, 1.30, 0), (3.08, 1.65, 0.12), (2.72, 2.45, 0.2), (2.4, 2.62, 0.15), (1.6, 2.64, 0.0), (1.5, 2.9, 0.0), (1.2, 3.05, 0.2), (-3.15, 3.1, 0.2), (-3.25, 2.9, 0.0)],
)


def _garbage_extras(det):
    from .kit import D_UNDER
    hop = kit.rbox((0, 0, 0), (2.0, 0.9, 0.7), 0.06, 1, "Details")
    hop.style(D_PLASTIC, (0.05, 0.12, 0.07))
    det.mesh.add_mesh(hop, kit.trans(0.0, -3.2, 1.15))
    for sx in (-0.95, 0.95):
        arm = kit.tube([(sx, -3.0, 0.8), (sx, -3.3, 1.1), (sx, -3.25, 1.8)], 0.05, sides=6, caps=True)
        arm.style(D_UNDER, (0.01, 0.01, 0.012))
        det.mesh.add_mesh(arm)
    _truck_extras(det)


GARBAGE["fx"] = dict(TRUCK["fx"], extras=_garbage_extras)

FIRETRUCK = variant(
    TRUCK, "firetruck", L=7.0, W=2.3, R=0.46, tyre_w=0.285, axle_f=2.45, axle_r=-1.9, half_w_keys=[(3.4, 1.12), (1.9, 1.12), (1.7, 1.15), (-3.4, 1.15)],
    top=[(3.38, 1.35, 0), (3.28, 1.7, 0.12), (2.92, 2.6, 0.2), (2.6, 2.72, 0.15), (1.9, 2.74, 0.0), (1.75, 2.35, 0.0), (1.6, 2.33, 0.0), (-3.4, 2.33, 0.0)],
    sill_keys=[(3.4, 0.42), (1.8, 0.42), (1.7, 0.7), (-3.4, 0.7)], belt=[(3.4, 1.3), (1.9, 1.3)], ws=(3.0, 2.58), windows=[(2.5, 1.95)],
    cabin=dict(dash_y=2.8, wheel_y=2.5, seat_y=2.25, seat_z=0.95, rear_seat=False, seat_x=0.46, liner_y=(3.0, 1.9), floor_z=0.74),
)


def _fire_extras(det):
    _bar(det, 2.1, 2.78, w=1.4, length=0.3, h=0.1)
    for sgn in (-1.0, 1.0):                                         # ladder on the roof of the body
        pts = [(sgn * 0.45, 1.5, 2.4), (sgn * 0.45, -3.1, 2.4)]
        rail = kit.tube(pts, 0.03, sides=6, caps=True)
        rail.style(D_CHROME, (0.55, 0.57, 0.6))
        det.mesh.add_mesh(rail)
    for y in [1.4 - 0.35 * k for k in range(13)]:
        rung = kit.cylinder((-0.45, y, 2.4), (0.45, y, 2.4), 0.015, 0.015, seg=5, mat="Details")
        rung.style(D_CHROME, (0.55, 0.57, 0.6))
        det.mesh.add_mesh(rung)
    for sgn in (1.0, -1.0):                                         # equipment compartments: roller shutters, drawn as outlines and slats that follow the flank (a patch bowed on the curved side)
        pl = "right" if sgn > 0 else "left"
        for (ya, yb) in ((1.4, 0.2), (0.1, -1.3), (-1.4, -2.6)):
            det.ribbon([(ya, 1.15), (yb, 1.15), (yb, 2.1), (ya, 2.1), (ya, 1.15)], pl, 0.02, D_PLASTIC, (0.03, 0.03, 0.035), offset=0.006)
            for k in range(1, 6):
                zz = 1.15 + (2.1 - 1.15) * k / 6.0
                det.ribbon([(ya - 0.04, zz), (yb + 0.04, zz)], pl, 0.01, D_PLASTIC, (0.12, 0.02, 0.02), offset=0.005)
    det.anchor("LightBar", (0.0, 2.1, 2.85))


FIRETRUCK["fx"] = dict(TRUCK["fx"], extras=_fire_extras, mirror=(2.65, 2.05, 0.2))

for _a in (HATCH, COUPE, SPORTS, MUSCLE, SUV, PICKUP, VAN, TRUCK, BUS, HOVER, SEDAN, TAXI, PATROL, WAGON, LIMO, AMBULANCE, ARMOURED, DELIVERY, GARBAGE, FIRETRUCK):
    _a["detail"] = car_details

ARCHETYPES = {a["name"]: a for a in (SEDAN, TAXI, PATROL, HATCH, COUPE, SPORTS, MUSCLE, SUV, PICKUP, VAN, TRUCK, BUS, HOVER, WAGON, LIMO, AMBULANCE, ARMOURED, DELIVERY, GARBAGE, FIRETRUCK)}


def get(name):
    return copy.deepcopy(ARCHETYPES[name])
