"""Wheels of Cars v2: tyre (revolved profile, tread uv for the shared normal map), rim (barrel, lip, spokes, hub), brake disc and caliper.

The wheel is built around the X axis at the origin with its outer face towards +X (the left wheels are the same mesh turned by 180 degrees under their wheel node).
Vertex uv0 = (angle fraction, profile fraction) for the tread normal map, uv2.x = part code read by assets/shaders/car_wheel.gdshader:
"""
import math

import numpy as np

from . import kit
from .kit import Mesh

WC_TYRE, WC_RIM, WC_BRAKE, WC_CALIPER, WC_HUB, WC_BARREL, WC_BOLT = range(7)


def _spoke_strip(x_face, r_h, r_i, a, w_h, w_i, dish, mat="Wheel"):
    """One flat-ish spoke: a quad strip from the hub radius to the rim radius around angle a (double sided in the shader)."""
    rs = [r_h, (r_h + r_i) * 0.5, r_i]
    ws = [w_h, (w_h + w_i) * 0.5, w_i]
    G = np.zeros((3, 2, 3))
    for i, (r, w) in enumerate(zip(rs, ws)):
        x = x_face - dish * (1.0 - ((r - r_h) / max(r_i - r_h, 1e-6))) * 1.0
        for j, s in enumerate((-0.5, 0.5)):
            aa = a + s * w / max(r, 1e-6)
            G[i, j] = (x, r * math.cos(aa), r * math.sin(aa))
    return Mesh().add_grid(G, mat)


DESIGNS = {
    "five": dict(n=5, w_h=0.075, w_i=0.060, kind="spoke"),
    "six": dict(n=6, w_h=0.060, w_i=0.050, kind="spoke"),
    "ten": dict(n=10, w_h=0.040, w_i=0.034, kind="spoke"),
    "mesh": dict(n=14, w_h=0.030, w_i=0.026, kind="spoke"),
    "steel": dict(n=0, kind="disc"),
    "split": dict(n=7, w_h=0.050, w_i=0.040, kind="split"),
    "truck": dict(n=0, kind="disc"),
}


def wheel_mesh(R, W, design="five", lod=0, rim_ratio=0.62, rim_col=(0.62, 0.64, 0.68), seg=None, caliper_col=(0.55, 0.05, 0.04), bolts=5):
    """The wheel as a Mesh with material 'Wheel'. R tyre radius, W tyre width."""
    seg = seg or {0: 22, 1: 10, 2: 6}[lod]
    r_rim = R * rim_ratio
    h = R - r_rim
    hw = W * 0.5
    des = DESIGNS.get(design, DESIGNS["five"])
    m = Mesh()
    # tyre
    prof = [(hw * 0.84, r_rim), (hw * 1.0, r_rim + 0.30 * h), (hw * 0.98, r_rim + 0.74 * h), (hw * 0.80, R), (-hw * 0.80, R), (-hw * 0.98, r_rim + 0.74 * h),
            (-hw * 1.0, r_rim + 0.30 * h), (-hw * 0.84, r_rim)]
    if lod == 1:
        prof = [(hw * 0.95, r_rim), (hw * 0.85, R), (-hw * 0.85, R), (-hw * 0.95, r_rim)]
    if lod == 2:
        prof = [(hw * 0.95, R * 0.9), (-hw * 0.95, R * 0.9)]
    vmap = {8: [0.0, 0.10, 0.20, 0.30, 0.70, 0.80, 0.90, 1.0], 6: [0.0, 0.2, 0.3, 0.7, 0.8, 1.0], 4: [0.0, 0.3, 0.7, 1.0], 2: [0.3, 0.7]}[len(prof)]
    tyre = kit.revolve(prof, seg=seg, axis="x", mat="Wheel", col=(0.035, 0.035, 0.038, 1.0), seam=True, uv_fn=lambda i, j, n, sg: (j / sg, vmap[i]))
    tyre = _orient_radial(tyre, outward=True, check_radius=R)
    tyre.style(uv2=WC_TYRE)
    m.add_mesh(tyre)
    face_x = hw * 0.64
    if lod == 2:                                                  # a six sided drum with a lid on the outer face: the far car's wheel
        lid = kit.poly_fan([(hw * 0.95, R * 0.62 * math.cos(2 * math.pi * k / seg), R * 0.62 * math.sin(2 * math.pi * k / seg)) for k in range(seg)], "Wheel", col=(*rim_col, 1.0))
        lid = _orient_axis(lid, +1.0)
        lid.style(uv2=WC_RIM)
        m.add_mesh(lid)
        return m
    # rim lip + barrel
    lip = kit.revolve([(hw * 0.90, r_rim - 0.03), (hw * 0.88, r_rim + 0.004)], seg=seg, axis="x", mat="Wheel", col=(*rim_col, 1.0))
    lip = _orient_radial(lip, outward=True, check_radius=r_rim + 0.004)
    lip.style(uv2=WC_RIM)
    m.add_mesh(lip)
    if lod == 0:
        barrel = kit.revolve([(hw * 0.84, r_rim - 0.015), (-hw * 0.45, r_rim - 0.03)], seg=seg, axis="x", mat="Wheel", col=(0.10, 0.10, 0.11, 1.0))
        barrel = _orient_radial(barrel, outward=False, check_radius=r_rim)
        barrel.style(uv2=WC_BARREL)
        m.add_mesh(barrel)
    # face: spokes or a disc
    r_h = r_rim * 0.20
    r_i = r_rim - 0.012
    dish = 0.03
    if lod >= 1:
        disc = kit.poly_fan([(face_x, r_i * math.cos(2 * math.pi * k / seg), r_i * math.sin(2 * math.pi * k / seg)) for k in range(seg)], "Wheel", col=(*rim_col, 1.0))
        disc = _orient_axis(disc, +1.0)
        disc.style(uv2=WC_RIM)
        m.add_mesh(disc)
        if lod == 1:
            hubd = kit.poly_fan([(face_x + 0.01, r_rim * 0.22 * math.cos(2 * math.pi * k / 8), r_rim * 0.22 * math.sin(2 * math.pi * k / 8)) for k in range(8)], "Wheel", col=(0.25, 0.25, 0.27, 1.0))
            hubd = _orient_axis(hubd, +1.0)
            hubd.style(uv2=WC_HUB)
            m.add_mesh(hubd)
        return m
    if des["kind"] == "disc":
        disc = kit.poly_fan([(face_x, r_i * math.cos(2 * math.pi * k / seg), r_i * math.sin(2 * math.pi * k / seg)) for k in range(seg)], "Wheel", col=(*rim_col, 1.0))
        disc = _orient_axis(disc, +1.0)
        disc.style(uv2=WC_RIM)
        m.add_mesh(disc)
        for k in range(bolts):                                    # wheel nuts
            a = 2 * math.pi * k / bolts
            nut = kit.cylinder((face_x + 0.004, 0.3 * r_rim * math.cos(a), 0.3 * r_rim * math.sin(a)), (face_x + 0.02, 0.3 * r_rim * math.cos(a), 0.3 * r_rim * math.sin(a)), 0.014, 0.012, seg=5, mat="Wheel", col=(0.5, 0.5, 0.52, 1.0), caps=(False, True))
            nut.style(uv2=WC_BOLT)
            m.add_mesh(nut)
    else:
        n = des["n"]
        spokes = Mesh()
        for k in range(n):
            a = 2 * math.pi * k / n + 0.2
            if des["kind"] == "split":
                for off in (-0.09, 0.09):
                    spokes.add_mesh(_spoke_strip(face_x, r_h, r_i, a + off, des["w_h"] * 0.6, des["w_i"] * 0.6, dish))
            else:
                spokes.add_mesh(_spoke_strip(face_x, r_h, r_i, a, des["w_h"], des["w_i"], dish))
        spokes.style(uv2=WC_RIM, color=(*rim_col, 1.0))
        spokes = _orient_axis(spokes, +1.0)
        m.add_mesh(spokes)
    hub = kit.poly_fan([(face_x + 0.012, r_h * 1.2 * math.cos(2 * math.pi * k / 12), r_h * 1.2 * math.sin(2 * math.pi * k / 12)) for k in range(12)], "Wheel", col=(0.07, 0.07, 0.08, 1.0))
    hub = _orient_axis(hub, +1.0)
    hub.style(uv2=WC_HUB)
    m.add_mesh(hub)
    cap = kit.poly_fan([(face_x + 0.018, r_h * 0.62 * math.cos(2 * math.pi * k / 10), r_h * 0.62 * math.sin(2 * math.pi * k / 10)) for k in range(10)], "Wheel", col=(0.72, 0.74, 0.78, 1.0))
    cap = _orient_axis(cap, +1.0)
    cap.style(uv2=WC_RIM)                                              # a bright centre cap in the dark hub
    # brake disc and caliper, seen between the spokes
    xd = hw * 0.18
    disc_r = r_rim * 0.86
    ring = kit.revolve([(xd, r_rim * 0.34), (xd, disc_r)], seg=seg, axis="x", mat="Wheel", col=(0.30, 0.30, 0.32, 1.0))
    ring.style(uv2=WC_BRAKE)
    m.add_mesh(ring)
    cal = kit.box((xd + 0.02, 0.0, disc_r * 0.92), (0.07, 0.05, 0.13), "Wheel", col=(*caliper_col, 1.0))
    cal.style(uv2=WC_CALIPER)
    cal = cal.xformed(kit.rot_x(0.5))
    m.add_mesh(cal)
    return m


def _orient_radial(mesh, outward, check_radius):
    """Flip the faces so that the faces on the surface at radius `check_radius` point away from (outward) or towards the X axis."""
    P = mesh.P
    F = mesh.F.copy()
    rad = np.sqrt(P[:, 1] ** 2 + P[:, 2] ** 2)
    A, B, C = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    n = np.cross(B - A, C - A)
    mid = (A + B + C) / 3.0
    r_dir = np.column_stack([np.zeros(len(mid)), mid[:, 1], mid[:, 2]])
    dots = (n * r_dir).sum(axis=1)
    sel = np.abs(np.sqrt(mid[:, 1] ** 2 + mid[:, 2] ** 2) - check_radius) < 0.02
    if sel.sum() == 0:
        sel = np.ones(len(F), dtype=bool)
    pointing_out = dots[sel].mean() > 0
    if pointing_out != outward:
        out = Mesh()
        return out.add(P, F[:, ::-1].copy(), None, col=mesh.C, uv=mesh.U, uv2=mesh.U2, fmat=[mesh.mats[i] for i in mesh.Fm], fpart=mesh.Fp)
    return mesh


def _orient_axis(mesh, sign):
    """Flip so the average normal points along sign * X (a flat face of the wheel)."""
    P = mesh.P
    F = mesh.F.copy()
    A, B, C = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    n = np.cross(B - A, C - A)
    flip = n[:, 0] * sign < 0
    F[flip] = F[flip][:, ::-1]
    out = Mesh()
    return out.add(P, F, None, col=mesh.C, uv=mesh.U, uv2=mesh.U2, fmat=[mesh.mats[i] for i in mesh.Fm], fpart=mesh.Fp)
