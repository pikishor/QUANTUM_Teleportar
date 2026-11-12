#!/usr/bin/env python3
"""The tall anchors of the outskirts (wave 112): wind turbine tower and head (blades spin in the vertex shader), transmission pylon, guyed radio mast, tower crane, airstrip hangar,
windsock, edge marker. Hard-surface kit built from square beams (flat shaded, painted by vertex colour, material code in COLOR.a: 0 paint, 1 beacon light, 2 spinning blade, 3 wire,
4 windsock cloth, 5 corrugated sheet). Output assets/models/land_props.glb, nodes named after the pieces; constants the game needs (pylon arm heights, hub height ...) live in
scripts/landscape/anchor_world.gd next to the code that uses them.
  godot/.venv-tools/bin/python godot/tools/landscape/build_land_props.py
"""
import math

import numpy as np

from mb import MeshBuilder, _norm

STEEL = (0.62, 0.66, 0.70)
WHITE = (0.92, 0.93, 0.95)
RED = (0.80, 0.14, 0.10)
YELLOW = (0.96, 0.74, 0.10)
DARK = (0.18, 0.19, 0.21)


def turbine_tower():
    mb = MeshBuilder()
    pts = [np.array([0.0, y, 0.0]) for y in (0.0, 16.0, 32.0, 48.0, 64.0)]
    radii = np.array([2.35, 2.05, 1.75, 1.50, 1.35])
    mb.tube(pts, radii, 12, uv_len=100.0, tint=WHITE, cap=False)
    mb.box((0.0, 1.3, 2.4), (1.4, 2.6, 0.4), (0.30, 0.32, 0.36))           # door
    mb.box((0.0, 0.25, 0.0), (7.0, 0.5, 7.0), (0.55, 0.55, 0.55))         # base slab
    return mb


def turbine_head():
    """Rotor axis = +Z through the origin (the hub), the tower top is at y = -1.8 below it. Blades 34 m, spin code 2."""
    mb = MeshBuilder()
    mb.box((0.0, -0.4, -1.8), (3.3, 3.5, 9.5), (0.90, 0.91, 0.93))        # nacelle
    mb.box((0.0, -2.0, -0.4), (2.2, 0.4, 4.0), (0.70, 0.72, 0.76))        # skirt
    mb.cone((0.0, 0.0, 2.0), (0.0, 0.0, 5.0), 1.55, 10, (0.94, 0.95, 0.97))
    mb.tube([np.array([0.0, 0.0, 1.2]), np.array([0.0, 0.0, 2.2])], np.array([1.7, 1.7]), 10, tint=(0.94, 0.95, 0.97), cap=False)
    for k in range(3):
        th = math.tau * k / 3.0 + 0.5
        u = np.array([math.cos(th), math.sin(th), 0.0])
        v = np.array([-math.sin(th), math.cos(th), 0.0])
        z = np.array([0.0, 0.0, 1.0])
        secs = []
        for s in range(6):
            f = s / 5.0
            r = 1.8 + 33.0 * f
            chord = 3.3 * (1.0 - f) ** 0.75 + 0.55
            t = 0.28 * (1.0 - 0.6 * f) + 0.05
            pitch = math.radians(14.0 * (1.0 - f) + 2.0)
            cv = v * math.cos(pitch) + z * math.sin(pitch)
            cz = z * math.cos(pitch) - v * math.sin(pitch)
            base = u * r + z * 2.6
            secs.append([base - cv * chord * 0.35, base - cv * chord * 0.05 + cz * t, base + cv * chord * 0.65, base - cv * chord * 0.05 - cz * t])
        col = (0.94, 0.95, 0.97)
        for s in range(5):
            for e in range(4):
                a0, a1 = secs[s][e], secs[s][(e + 1) % 4]
                b0, b1 = secs[s + 1][e], secs[s + 1][(e + 1) % 4]
                nrm = _norm(np.cross(a1 - a0, b0 - a0))
                if np.dot(nrm, (a0 + a1 + b0 + b1) / 4.0 - (secs[s][0] + secs[s][1] + secs[s][2] + secs[s][3]) / 4.0 - z * 0.0) < 0 and e in (0, 1):
                    nrm = -nrm
                mb._flat_quad(a0, a1, b1, b0, nrm, col, 2.0)
    return mb


PYLON_BAYS = (0.0, 8.5, 17.0, 26.0, 36.0)
PYLON_HW = (3.2, 2.35, 1.55, 0.95, 0.60)
PYLON_ARMS = ((30.0, 7.2), (33.6, 6.4), (37.0, 5.4))


def pylon():
    mb = MeshBuilder()
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for k in range(len(PYLON_BAYS) - 1):
        y0, y1 = PYLON_BAYS[k], PYLON_BAYS[k + 1]
        h0, h1 = PYLON_HW[k], PYLON_HW[k + 1]
        for sx, sz in corners:
            mb.beam((sx * h0, y0, sz * h0), (sx * h1, y1, sz * h1), 0.42 - 0.05 * k, STEEL)
        if k < 3:
            for i in range(4):
                (ax, az), (bx, bz) = corners[i], corners[(i + 1) % 4]
                p0 = np.array([ax * h0, y0, az * h0])
                p1 = np.array([bx * h1, y1, bz * h1]) if k % 2 == 0 else np.array([bx * h0, y0, bz * h0])
                mb.beam((ax * h0, y0, az * h0), (bx * h1, y1, bz * h1), 0.18, STEEL)
        for i in range(4):
            (ax, az), (bx, bz) = corners[i], corners[(i + 1) % 4]
            mb.beam((ax * h1, y1, az * h1), (bx * h1, y1, bz * h1), 0.2, STEEL)
    mb.beam((0.0, 36.0, 0.0), (0.0, 41.0, 0.0), 0.35, STEEL, w1=0.14)
    for y, ln in PYLON_ARMS:
        mb.beam((-ln, y, 0.0), (ln, y, 0.0), 0.34, STEEL)
        for sx in (-1, 1):
            mb.beam((sx * 0.6, y - 2.3, 0.0), (sx * ln, y, 0.0), 0.18, STEEL)
            mb.beam((sx * 0.6, y - 0.3, 0.0), (sx * ln * 0.55, y, 0.0), 0.16, STEEL)
            mb.beam((sx * ln, y - 0.2, 0.0), (sx * ln, y - 2.4, 0.0), 0.22, (0.55, 0.65, 0.60))     # insulator string
    return mb


def mast():
    """Guyed triangular lattice mast, 72 m, red and white bands, a blinking beacon on top (code 1), three guys."""
    mb = MeshBuilder()
    H = 72.0
    bays = 6
    R = 1.15
    ang = [math.radians(90 + 120 * i) for i in range(3)]
    for b in range(bays):
        y0, y1 = H * b / bays, H * (b + 1) / bays
        col = RED if b % 2 == 0 else WHITE
        for i in range(3):
            p0 = np.array([R * math.cos(ang[i]), y0, R * math.sin(ang[i])])
            p1 = np.array([R * math.cos(ang[i]), y1, R * math.sin(ang[i])])
            mb.beam(p0, p1, 0.28, col)
            j = (i + 1) % 3
            q0 = np.array([R * math.cos(ang[j]), y0, R * math.sin(ang[j])])
            q1 = np.array([R * math.cos(ang[j]), y1, R * math.sin(ang[j])])
            mb.beam(p0, q1 if b % 2 == 0 else np.array([R * math.cos(ang[j]), y0, R * math.sin(ang[j])]), 0.12, STEEL)
            mb.beam(p1, q1, 0.14, STEEL)
    mb.beam((0.0, H, 0.0), (0.0, H + 7.0, 0.0), 0.2, STEEL, w1=0.08)
    mb.box((0.0, H + 0.3, 0.0), (0.9, 0.7, 0.9), (0.30, 0.32, 0.36))
    mb.box((0.0, H + 1.0, 0.0), (0.55, 0.55, 0.55), (1.0, 0.12, 0.08), code=1.0)
    mb.box((0.0, 56.0, 1.9), (0.3, 2.2, 1.6), (0.88, 0.89, 0.90))                             # a dish
    mb.box((1.7, 44.0, -0.5), (1.4, 1.4, 0.3), (0.88, 0.89, 0.90))
    for i in range(3):
        a = ang[i] + math.radians(60)
        mb.beam((R * 0.9 * math.cos(ang[i]), 52.0, R * 0.9 * math.sin(ang[i])), (34.0 * math.cos(a), 0.2, 34.0 * math.sin(a)), 0.07, (0.25, 0.26, 0.28), code=3.0)
    return mb


def crane():
    """Tower crane (yellow lattice): mast 48 m, jib 54 m along +x, counter jib 20 m, counterweight, cab, trolley and hook."""
    mb = MeshBuilder()
    H = 48.0
    bays = 5
    h = 1.1
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for b in range(bays):
        y0, y1 = H * b / bays, H * (b + 1) / bays
        for sx, sz in corners:
            mb.beam((sx * h, y0, sz * h), (sx * h, y1, sz * h), 0.3, YELLOW)
        for i in range(4):
            (ax, az), (bx, bz) = corners[i], corners[(i + 1) % 4]
            mb.beam((ax * h, y1, az * h), (bx * h, y1, bz * h), 0.16, YELLOW)
            mb.beam((ax * h, y0, az * h), (bx * h, y1, bz * h), 0.13, YELLOW)
    mb.box((0.0, 0.4, 0.0), (5.5, 0.8, 5.5), (0.55, 0.55, 0.55))
    top = H
    mb.box((0.0, top + 1.0, 0.0), (3.0, 2.0, 3.0), (0.30, 0.31, 0.34))                        # slewing unit
    mb.box((1.5, top + 3.0, 0.0), (2.0, 2.0, 2.2), (0.85, 0.88, 0.92))                        # cab
    mb.beam((0.0, top + 2.0, 0.0), (0.0, top + 9.0, 0.0), 0.5, YELLOW, w1=0.3)
    # jib: triangular truss along +x
    for k in range(14):
        x0, x1 = 2.0 + 52.0 * k / 14, 2.0 + 52.0 * (k + 1) / 14
        mb.beam((x0, top + 2.4, 0.0), (x1, top + 2.4, 0.0), 0.22, YELLOW)
        mb.beam((x0, top + 0.8, -0.9), (x1, top + 0.8, -0.9), 0.2, YELLOW)
        mb.beam((x0, top + 0.8, 0.9), (x1, top + 0.8, 0.9), 0.2, YELLOW)
        mb.beam((x0, top + 0.8, 0.0 if k % 2 else -0.9), (x1, top + 2.4, 0.0), 0.12, YELLOW)
    mb.beam((0.0, top + 9.0, 0.0), (54.0, top + 2.3, 0.0), 0.08, DARK, code=3.0)
    mb.beam((0.0, top + 9.0, 0.0), (-20.0, top + 2.3, 0.0), 0.08, DARK, code=3.0)
    for k in range(5):                                                                      # counter jib
        x0, x1 = -2.0 - 18.0 * k / 5, -2.0 - 18.0 * (k + 1) / 5
        mb.beam((x0, top + 1.6, -0.8), (x1, top + 1.6, -0.8), 0.2, YELLOW)
        mb.beam((x0, top + 1.6, 0.8), (x1, top + 1.6, 0.8), 0.2, YELLOW)
    mb.box((-17.0, top + 0.9, 0.0), (3.4, 2.2, 2.4), (0.60, 0.60, 0.62))                      # counterweight
    mb.box((34.0, top + 0.0, 0.0), (1.8, 0.9, 1.4), (0.30, 0.31, 0.34))                       # trolley
    mb.beam((34.0, top - 0.4, 0.0), (34.0, 12.0, 0.0), 0.08, DARK, code=3.0)                 # hoist cable
    mb.box((34.0, 11.4, 0.0), (1.0, 1.2, 1.0), (0.20, 0.20, 0.22))                            # hook block
    mb.box((0.0, top + 9.6, 0.0), (0.4, 0.4, 0.4), (1.0, 0.1, 0.08), code=1.0)
    return mb


def hangar():
    """A small corrugated hangar 14 x 10 m, gabled roof, the doors on the -z side (front = -z)."""
    mb = MeshBuilder()
    green = (0.46, 0.55, 0.50)
    mb.box((0.0, 2.1, 0.0), (14.0, 4.2, 10.0), green, code=5.0)
    # gable roof: two sloped slabs
    for sx in (-1, 1):
        a = np.array([sx * 7.3, 4.0, -5.4])
        b = np.array([sx * 7.3, 4.0, 5.4])
        c = np.array([0.0, 6.0, 5.4])
        d = np.array([0.0, 6.0, -5.4])
        nrm = _norm(np.cross(b - a, d - a)) * (1 if sx > 0 else -1)
        mb._flat_quad(a, b, c, d, nrm if nrm[1] > 0 else -nrm, (0.52, 0.55, 0.56), 5.0)
    mb.box((0.0, 1.7, -5.05), (9.6, 3.4, 0.25), (0.34, 0.38, 0.36), code=5.0)           # doors
    mb.box((0.0, 4.3, -5.05), (14.0, 0.35, 0.3), (0.85, 0.85, 0.85))
    return mb


def windsock():
    """An 8 m pole (white, with a red top), the sock (orange / white stripes, code 4) along +x from the pole top: the shader swings it round with the wind."""
    mb = MeshBuilder()
    mb.beam((0.0, 0.0, 0.0), (0.0, 7.6, 0.0), 0.18, WHITE, w1=0.11)
    mb.box((0.0, 7.8, 0.0), (0.3, 0.3, 0.3), (0.80, 0.14, 0.10))
    mb.sock(3.6, 0.46, 0.22)
    # the sock hangs from the pole top: shift its origin up to y = 7.7 by building the pole instead of moving the sock: the shader pivots round x = z = 0
    for i, v in enumerate(mb.V):
        if mb.C[i][3] == 4.0:
            mb.V[i] = v + np.array([0.0, 7.7, 0.0], dtype=np.float32)
    return mb


def marker():
    """An edge marker for airstrips: a squat white and orange pyramid."""
    mb = MeshBuilder()
    mb.cone((0.0, 0.0, 0.0), (0.0, 0.8, 0.0), 0.34, 4, (0.95, 0.95, 0.95))
    mb.cone((0.0, 0.0, 0.0), (0.0, 0.35, 0.0), 0.37, 4, (0.95, 0.45, 0.10))
    return mb


def build_all():
    return {"turbine_tower": turbine_tower(), "turbine_head": turbine_head(), "pylon": pylon(), "mast": mast(), "crane": crane(), "hangar": hangar(), "windsock": windsock(),
            "marker": marker()}
