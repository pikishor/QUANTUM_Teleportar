"""Cabin of Cars v2: dashboard, steering wheel, seats, a driver, and the plain liner (floor, door panels, headliner) that closes the cabin so the
windows show a dark interior instead of the street behind it. Driver parts carry the Details classes D_SKIN / D_CLOTH, which the shader can switch off per car."""
import math

import numpy as np

from . import kit
from .kit import D_CHROME, D_FABRIC, D_LEATHER, D_PLASTIC, D_SCREEN, Mesh

D_SKIN, D_CLOTH = 18, 19
SEAT = (0.075, 0.078, 0.09)
SEAT_TAN = (0.17, 0.115, 0.07)
DASH = (0.022, 0.022, 0.026)
DASH_TOP = (0.035, 0.036, 0.042)
LINER = (0.045, 0.047, 0.055)
TRIM_LIGHT = (0.13, 0.135, 0.15)
SKIN = (0.5, 0.32, 0.24)
CLOTH = (0.08, 0.10, 0.16)


def _seat(x, y, z, tilt=0.0, w=0.46, col=SEAT, head=True, h=0.55):
    """A seat facing the nose (+Y): cushion, back with side bolsters, headrest (plain boxes: 12 triangles each)."""
    m = Mesh()
    back_col = tuple(min(c * 0.72, 1.0) for c in col)
    cush = kit.box((0, 0, 0), (w, 0.50, 0.13))
    cush.style(D_FABRIC, col)
    m.add_mesh(cush, kit.trans(x, y, z))
    back = kit.box((0, 0, 0), (w * 0.86, 0.11, h))
    back.style(D_FABRIC, back_col)
    back = back.xformed(kit.rot_x(-tilt))
    m.add_mesh(back, kit.trans(x, y - 0.25, z + 0.28))
    for sx in (-1.0, 1.0):                                         # bolsters: a thin raised cheek on each side of the cushion and of the back
        bc = kit.box((0, 0, 0), (0.07, 0.42, 0.075))
        bc.style(D_FABRIC, col)
        m.add_mesh(bc, kit.trans(x + sx * (w * 0.5 - 0.03), y + 0.02, z + 0.085))
        bb = kit.box((0, 0, 0), (0.075, 0.15, h * 0.82))
        bb.style(D_FABRIC, col)
        bb = bb.xformed(kit.rot_x(-tilt))
        m.add_mesh(bb, kit.trans(x + sx * (w * 0.5 - 0.02), y - 0.23, z + 0.26))
    if head:
        hr = kit.box((0, 0, 0), (0.21, 0.09, 0.16))
        hr.style(D_FABRIC, col)
        m.add_mesh(hr, kit.trans(x, y - 0.25 - math.sin(tilt) * 0.36, z + 0.28 + math.cos(tilt) * 0.40))
    return m


def driver(x, y, z, scale=1.0):
    """A seated driver: head with hair, neck, torso with shoulders, a seat belt, arms to the wheel."""
    m = Mesh()
    head = kit.sphere((0, 0, 0), 0.105, seg=8, rings=4, squash=(0.92, 1.0, 1.12))
    head.style(D_SKIN, SKIN)
    m.add_mesh(head, kit.trans(x, y - 0.05, z + 0.70))
    hair = kit.sphere((0, 0, 0), 0.112, seg=8, rings=3, squash=(0.95, 1.02, 0.62))
    hair.style(D_CLOTH, (0.035, 0.03, 0.03))
    m.add_mesh(hair, kit.trans(x, y - 0.065, z + 0.745))
    neck = kit.cylinder((x, y - 0.07, z + 0.55), (x, y - 0.07, z + 0.62), 0.045, 0.045, seg=6)
    neck.style(D_SKIN, SKIN)
    m.add_mesh(neck)
    torso = kit.box((0, 0, 0), (0.36, 0.22, 0.40))
    torso.style(D_CLOTH, CLOTH)
    m.add_mesh(torso, kit.trans(x, y - 0.11, z + 0.30))
    shoulders = kit.box((0, 0, 0), (0.46, 0.16, 0.10))
    shoulders.style(D_CLOTH, CLOTH)
    m.add_mesh(shoulders, kit.trans(x, y - 0.10, z + 0.52))
    belt = kit.quad((-0.05, 0.0, 0.0), (0.05, 0.0, 0.0), (0.22, 0.0, -0.46), (0.12, 0.0, -0.46), "Details")
    belt.style(D_FABRIC, (0.015, 0.015, 0.018))
    m.add_mesh(belt, kit.trans(x - 0.05, y + 0.0, z + 0.56))
    for sgn in (-1.0, 1.0):
        arm = kit.tube([(x + sgn * 0.23, y - 0.10, z + 0.50), (x + sgn * 0.25, y + 0.18, z + 0.38), (x + sgn * 0.16, y + 0.42, z + 0.46)], 0.04, sides=5, caps=False)
        arm.style(D_CLOTH, CLOTH)
        m.add_mesh(arm)
    return m


def cabin(d, lod, driver_on=True):
    """Everything inside the greenhouse, for the sedan family (cabin dict in the archetype overrides the defaults)."""
    c = dict(dash_y=0.80, dash_z=0.84, wheel_y=0.44, seat_y=0.10, seat_z=0.46, rear_y=-0.82, rear_z=0.50, seat_x=0.40, rear_seat=True, floor_z=0.28, tan=False, liner_y=(0.84, -1.2))
    c.update(d.get("cabin", {}))
    belt = d.get("belt", [])
    belt = sorted(belt) if isinstance(belt, (list, tuple)) and belt and isinstance(belt[0], (list, tuple)) else []
    if belt:                                                       # the dashboard must sit under the cowl: a low sports car has its beltline well under 0.84 m
        zb = float(np.interp(c["dash_y"] - 0.15, [b[0] for b in belt], [b[1] for b in belt]))
        c["dash_z"] = min(c["dash_z"], zb - 0.12)
    col = SEAT_TAN if c["tan"] else SEAT
    m = Mesh()
    xs = c["seat_x"]
    if lod == 0:
        # dashboard: a slab across the cabin with a binnacle hump in front of the driver
        dash = kit.box((0, 0, 0), (1.50, 0.40, 0.14))
        dash.style(D_LEATHER, DASH)
        m.add_mesh(dash.xformed(kit.rot_x(0.22)), kit.trans(0.0, c["dash_y"] - 0.20, c["dash_z"]))           # its top slopes up to the glass like a real dashboard
        hump = kit.box((0, 0, 0), (0.46, 0.26, 0.12))
        hump.style(D_LEATHER, DASH)
        m.add_mesh(hump, kit.trans(-xs, c["dash_y"] - 0.24, c["dash_z"] + 0.12))
        scr = kit.quad((-0.12, 0.0, -0.05), (0.12, 0.0, -0.05), (0.12, 0.0, 0.05), (-0.12, 0.0, 0.05), "Details").flipped()
        scr.style(D_SCREEN, (0.1, 0.5, 0.8))
        m.add_mesh(scr, kit.trans(-xs, c["dash_y"] - 0.37, c["dash_z"] + 0.12))
        cons = kit.box((0, 0, 0), (0.22, 0.65, 0.20))
        cons.style(D_PLASTIC, DASH)
        m.add_mesh(cons, kit.trans(0.0, c["seat_y"] + 0.12, c["seat_z"] - 0.04))
        # the instrument cluster under a binnacle hood, three vents and door armrests
        hood = kit.box((0, 0, 0), (0.50, 0.20, 0.07))
        hood.style(D_PLASTIC, DASH_TOP)
        m.add_mesh(hood, kit.trans(-xs, c["dash_y"] - 0.30, c["dash_z"] + 0.22))
        clu = kit.quad((-0.17, 0.0, -0.045), (0.17, 0.0, -0.045), (0.17, 0.0, 0.045), (-0.17, 0.0, 0.045), "Details").flipped()
        clu.style(D_SCREEN, (0.9, 0.55, 0.15))
        m.add_mesh(clu, kit.trans(-xs, c["dash_y"] - 0.405, c["dash_z"] + 0.155))
        for vx in (-0.30, 0.30, 0.62):
            vent = kit.box((0, 0, 0), (0.13, 0.012, 0.035))
            vent.style(D_PLASTIC, (0.008, 0.008, 0.01))
            m.add_mesh(vent, kit.trans(vx, c["dash_y"] - 0.385, c["dash_z"] + 0.09))
        for sx in (-1.0, 1.0):
            arm = kit.box((0, 0, 0), (0.07, 0.55, 0.06))
            arm.style(D_LEATHER, TRIM_LIGHT)
            m.add_mesh(arm, kit.trans(sx * 0.80, c["seat_y"] + 0.05, c["seat_z"] + 0.20))
        # steering wheel (tilted ring) and column
        sw = kit.torus((0, 0, 0), 0.17, 0.018, seg=12, sides=4, axis="y")
        sw.style(D_PLASTIC, (0.03, 0.03, 0.035))
        sw = sw.xformed(kit.rot_x(0.45))
        m.add_mesh(sw, kit.trans(-xs, c["wheel_y"], c["dash_z"] + 0.02))
        hub = kit.box((0, 0, 0), (0.07, 0.04, 0.07))
        hub.style(D_PLASTIC, (0.03, 0.03, 0.035))
        m.add_mesh(hub, kit.trans(-xs, c["wheel_y"], c["dash_z"] + 0.02))
        for ang in (math.radians(90), math.radians(210), math.radians(330)):                       # three spokes from the hub to the rim
            sp = kit.box((0, 0, 0), (0.17, 0.02, 0.02))
            sp.style(D_PLASTIC, (0.03, 0.03, 0.035))
            sp = sp.xformed(kit.rot_y(ang)).xformed(kit.rot_x(0.45))
            m.add_mesh(sp, kit.trans(-xs, c["wheel_y"], c["dash_z"] + 0.02))
    # seats
    for sx in (-xs, xs):
        m.add_mesh(_seat(sx, c["seat_y"], c["seat_z"], tilt=0.18, col=col))
    if c["rear_seat"]:
        bench = kit.box((0, 0, 0), (1.30, 0.48, 0.14))
        bench.style(D_FABRIC, col)
        m.add_mesh(bench, kit.trans(0.0, c["rear_y"], c["rear_z"] - 0.05))
        back = kit.box((0, 0, 0), (1.30, 0.12, 0.52))
        back.style(D_FABRIC, col)
        m.add_mesh(back.xformed(kit.rot_x(-0.22)), kit.trans(0.0, c["rear_y"] - 0.24, c["rear_z"] + 0.22))
        if lod == 0:
            for sx in (-0.42, 0.0, 0.42):
                hr = kit.box((0, 0, 0), (0.2, 0.08, 0.15))
                hr.style(D_FABRIC, col)
                m.add_mesh(hr, kit.trans(sx, c["rear_y"] - 0.31, c["rear_z"] + 0.58))
    if driver_on:
        m.add_mesh(driver(-xs, c["seat_y"], c["seat_z"]))
    return m


def liner(d, info, lod, inset=0.05):
    """A plain dark cabin shell (floor, inner door panels, headliner) built from the loft rings between the cabin's front and rear stations, inset a little and facing inwards.
    It closes the cabin, so the side windows show a dark interior with the seats in it instead of the street behind."""
    rings = info["rings"]
    c = dict(liner_y=(0.86, -1.22), floor_z=0.28)
    c.update(d.get("cabin", {}))
    ya, yb = c["liner_y"]
    sel = [i for i in range(len(rings)) if yb - 0.02 <= rings[i][0, 1] <= ya + 0.02]
    if len(sel) < 2:
        return Mesh()
    sel = sel[::3] if sel[-1] in sel[::3] else sel[::3] + [sel[-1]]
    K = info["K"]
    n_up = info.get("n_up", 9)
    slots = [0, 2, n_up - 1] if lod == 0 else [0, 1, n_up - 1]
    slots = [j for j in slots if j < n_up]
    loops = []
    for i in sel:
        r = rings[i]
        zc = c["floor_z"] + 0.45
        right = []
        for j in slots:
            p = r[j].copy()
            q = p.copy()
            q[0] = p[0] - inset if p[0] > 0.05 else 0.0
            q[2] = p[2] - (inset if j <= 2 else 0.0)
            right.append(q)
        fl = right[-1].copy()
        fl[2] = c["floor_z"]
        right.append(fl)
        left = [np.array([-q[0], q[1], q[2]]) for q in right[::-1]]
        loop = right + left[1:-1] if False else right + [np.array([-q[0], q[1], q[2]]) for q in right[::-1][:-1]]
        loops.append(loop)
    G = np.array(loops)
    m = Mesh().add_grid(G, "Details", wrap_v=True)
    m.style(D_FABRIC, LINER)
    # face inwards
    P = m.P
    F = m.F.copy()
    A, B, C = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    nrm = np.cross(B - A, C - A)
    mid = (A + B + C) / 3.0
    cen = np.column_stack([np.zeros(len(mid)), mid[:, 1], np.full(len(mid), c["floor_z"] + 0.45)])
    flip = (nrm * (cen - mid)).sum(axis=1) < 0
    F[flip] = F[flip][:, ::-1]
    out = Mesh().add(P, F, "Details", col=m.C, uv=m.U)
    # front and rear walls
    for loop, fl in ((loops[0], True), (loops[-1], False)):
        cap = kit.poly_fan(loop, "Details", col=(*LINER, 1.0), uv=None) if False else kit.poly_fan(loop, "Details")
        cap.style(D_FABRIC, LINER)
        out.add_mesh(cap if not fl else cap.flipped())
    return out
