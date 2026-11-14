"""Geometry core of the weapon kit (wave 114): numpy primitives with hand-set normals, welding, baked vertex AO / edge wear, a compact GLB writer.

Frame of the kit (the Blender frame of helpers.py): X right, Y FORWARD (the barrel points to +Y, the muzzle is at y = 0, the weapon body lies at y < 0), Z up, the bore axis is the Y axis.
The glTF export turns (x, y, z) into (x, z, -y): in Godot the barrel points to -Z, the body extends toward +Z, +Y is up.

A shape is built from SECTIONS: a convex or concave 2D outline (pts, outward normals, skip flags for the zero-width side of a hard corner) placed in 3D by (origin, U, V).
`G.loft` joins sections with quads, offers a flat cap with an optional chamfer ring (the normals of the cap vertices are the cap normal, the ring behind them keeps the side normals: that
is the 'weighted normal' look of hard-surface models, with shared vertices, so a bevelled box costs about 0.55 vertices per triangle instead of 2). `G.lathe` is a surface of revolution about Y,
`G.extrude` pushes a side profile across X, `G.sweep` follows a path (curved magazines, bow limbs, blades). Every emit carries the vertex attributes of the runtime shader:
material layer, part id (moving parts), glow, tint, and after `finish()` the baked AO and edge wear.
"""
import math
import random
from contextlib import contextmanager

import numpy as np

EPS = 1e-9
X_AX = np.array([1.0, 0.0, 0.0])
Y_AX = np.array([0.0, 1.0, 0.0])
Z_AX = np.array([0.0, 0.0, 1.0])

# moving parts (shader part ids): the runtime moves every vertex of a part by a uniform of the hero's weapon material
P_STATIC, P_SLIDE, P_MAG, P_PUMP, P_HAMMER, P_ROTOR, P_LEVER, P_PULSE = range(8)
PART_NAMES = ["static", "slide", "mag", "pump", "hammer", "rotor", "lever", "pulse"]


def v3(*a):
    return np.array(a if len(a) == 3 else a[0], dtype=np.float64)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, EPS)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def mat4(R=None, t=(0, 0, 0)):
    m = np.eye(4)
    if R is not None:
        m[:3, :3] = R
    m[:3, 3] = t
    return m


def euler(rx=0.0, ry=0.0, rz=0.0, deg=True):
    if deg:
        rx, ry, rz = math.radians(rx), math.radians(ry), math.radians(rz)
    return rot_z(rz) @ rot_y(ry) @ rot_x(rx)


class Style:
    """What a primitive is made of: material layer (weapon_mats.LAYERS index), tint (linear albedo multiplier), glow (0..1, emissive share)."""
    __slots__ = ("layer", "tint", "glow")

    def __init__(self, layer, tint=(1.0, 1.0, 1.0), glow=0.0):
        self.layer = int(layer)
        self.tint = tuple(float(c) for c in tint)
        self.glow = float(glow)

    def t(self, tint=None, glow=None, layer=None):
        return Style(self.layer if layer is None else layer, self.tint if tint is None else tint, self.glow if glow is None else glow)

    def k(self, f):
        return Style(self.layer, tuple(min(1.0, c * f) for c in self.tint), self.glow)


# ---------------------------------------------------------------------------------------------------------------- outlines (2D sections)
class Sec:
    """A 2D outline in 3D: pts (n,2) in the (U, V) plane at `origin`, nrm (n,2) outward unit normals, skip (n,) bool = the segment i -> i+1 has no width (hard corner duplicate)."""
    __slots__ = ("pts", "nrm", "skip", "origin", "U", "V")

    def __init__(self, pts, nrm, skip, origin, U, V):
        self.pts = np.asarray(pts, dtype=np.float64)
        self.nrm = np.asarray(nrm, dtype=np.float64)
        self.skip = np.asarray(skip, dtype=bool)
        self.origin = np.asarray(origin, dtype=np.float64)
        self.U = np.asarray(U, dtype=np.float64)
        self.V = np.asarray(V, dtype=np.float64)

    def p3(self):
        return self.origin + self.pts[:, 0:1] * self.U + self.pts[:, 1:2] * self.V

    def n3(self):
        return self.nrm[:, 0:1] * self.U + self.nrm[:, 1:2] * self.V

    def center(self):
        return self.origin + self.pts.mean(axis=0)[0] * self.U + self.pts.mean(axis=0)[1] * self.V

    def moved(self, d):
        return Sec(self.pts, self.nrm, self.skip, self.origin + d, self.U, self.V)


def outline_rrect(w, h, r=0.0, seg=1, cx=0.0, cz=0.0):
    """Rounded rectangle (a = x, b = z), counter-clockwise from the bottom right. r = 0: a hard box (8 points, 4 skipped corner segments); seg = segments of every corner arc."""
    hw, hh = w / 2.0, h / 2.0
    r = max(0.0, min(r, hw - 1e-6, hh - 1e-6))
    if r <= 1e-7:
        P = [(hw, -hh), (hw, hh), (hw, hh), (-hw, hh), (-hw, hh), (-hw, -hh), (-hw, -hh), (hw, -hh)]
        N = [(1, 0), (1, 0), (0, 1), (0, 1), (-1, 0), (-1, 0), (0, -1), (0, -1)]
        # points: 0,1 on the right side (bottom, top) | 2,3 top | 4,5 left | 6,7 bottom; segments 1->2, 3->4, 5->6, 7->0 are the zero width corners
        skip = [False, True, False, True, False, True, False, True]
        P = np.array(P, dtype=np.float64) + [cx, cz]
        return P, np.array(N, dtype=np.float64), np.array(skip)
    pts, nrm = [], []
    corners = [(hw - r, -hh + r, -90.0), (hw - r, hh - r, 0.0), (-hw + r, hh - r, 90.0), (-hw + r, -hh + r, 180.0)]
    for (ccx, ccz, a0) in corners:
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            nx, nz = math.cos(a), math.sin(a)
            pts.append((ccx + nx * r, ccz + nz * r))
            nrm.append((nx, nz))
    P = np.array(pts, dtype=np.float64) + [cx, cz]
    return P, np.array(nrm, dtype=np.float64), np.zeros(len(pts), dtype=bool)


def outline_circle(r, n=12, cx=0.0, cz=0.0, ry=None):
    ry = r if ry is None else ry
    a = 2.0 * math.pi * np.arange(n) / n
    pts = np.stack([cx + r * np.cos(a), cz + ry * np.sin(a)], axis=1)
    nrm = unit(np.stack([np.cos(a) / max(r, EPS), np.sin(a) / max(ry, EPS)], axis=1))
    return pts, nrm, np.zeros(n, dtype=bool)


def outline_poly(pts, hard=True):
    """A polygon from points (counter-clockwise); every corner becomes a hard corner (duplicated vertex with the two side normals) when hard, else smooth normals."""
    pts = np.asarray(pts, dtype=np.float64)
    n = len(pts)
    e = np.roll(pts, -1, axis=0) - pts
    en = unit(np.stack([e[:, 1], -e[:, 0]], axis=1))               # outward normal of edge i -> i+1 for a counter-clockwise polygon
    if not hard:
        vn = unit(en + np.roll(en, 1, axis=0))
        return pts, vn, np.zeros(n, dtype=bool)
    P, N, S = [], [], []
    for i in range(n):
        P.append(pts[i]); N.append(en[i - 1]); S.append(True)            # arriving edge's normal (i-1 -> i)
        P.append(pts[i]); N.append(en[i]); S.append(False)               # leaving edge's normal (i -> i+1)
    # S[k] True = the segment k -> k+1 is the zero-width corner (point i with arriving normal -> point i with leaving normal)
    return np.array(P), np.array(N), np.array(S)


def offset_outline(pts, nrm, skip, d):
    """Shrink (d > 0) or grow an outline by d along its normals; hard corner pairs move to their miter point so they stay together."""
    out = pts - d * nrm
    n = len(pts)
    for i in range(n):
        if skip[i]:
            j = (i + 1) % n
            n1, n2 = nrm[i], nrm[j]
            m = (n1 + n2) / max(1.0 + float(np.dot(n1, n2)), 0.2)
            out[i] = pts[i] - d * m
            out[j] = out[i]
    return out


def clean_ring(P, N):
    """Drop consecutive duplicate points (a hard box corner has two) for a cap polygon."""
    keep = [0]
    for i in range(1, len(P)):
        if np.linalg.norm(P[i] - P[keep[-1]]) > 1e-9:
            keep.append(i)
    if len(keep) > 1 and np.linalg.norm(P[keep[-1]] - P[keep[0]]) < 1e-9:
        keep.pop()
    return P[keep], N[keep]


def triangulate(poly):
    """Ear clipping of a simple 2D polygon (counter-clockwise or clockwise), returns triangles as index triples."""
    n = len(poly)
    if n < 3:
        return []
    idx = list(range(n))
    area = 0.0
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        area += x0 * y1 - x1 * y0
    if area < 0:
        idx.reverse()
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 4 * n * n:
        guard += 1
        ear = False
        for k in range(len(idx)):
            a, b, c = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            pa, pb, pc = poly[a], poly[b], poly[c]
            cr = (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0])
            if cr <= 1e-14:
                continue
            ok = True
            for m in idx:
                if m in (a, b, c):
                    continue
                q = poly[m]
                d1 = (pb[0] - pa[0]) * (q[1] - pa[1]) - (pb[1] - pa[1]) * (q[0] - pa[0])
                d2 = (pc[0] - pb[0]) * (q[1] - pb[1]) - (pc[1] - pb[1]) * (q[0] - pb[0])
                d3 = (pa[0] - pc[0]) * (q[1] - pc[1]) - (pa[1] - pc[1]) * (q[0] - pc[0])
                if d1 >= -1e-12 and d2 >= -1e-12 and d3 >= -1e-12:
                    ok = False
                    break
            if ok:
                tris.append((a, b, c))
                idx.pop(k)
                ear = True
                break
        if not ear:
            break
    if len(idx) == 3:
        tris.append((idx[0], idx[1], idx[2]))
    return tris


# ---------------------------------------------------------------------------------------------------------------- the weapon geometry accumulator
class G:
    def __init__(self, lod=0, seed=1):
        self.lod = lod
        self.fine = lod == 0                     # small detail (screws, serrations, vents, rail slots) only at LOD0
        self.rng = random.Random(seed)
        self._P, self._N, self._F, self._A = [], [], [], []
        self.nv = 0
        self.markers = {}
        self.parts = {}
        self.part = P_STATIC
        self._xf = [np.eye(4)]
        self.bevel_k = 1.0 if lod == 0 else 0.0   # bevels (chamfer rings) only at LOD0

    # -- transforms --------------------------------------------------------------------------------------------------------
    @contextmanager
    def at(self, pos=(0, 0, 0), rot=(0, 0, 0), R=None):
        M = mat4(euler(*rot) if R is None else R, pos)
        self._xf.append(self._xf[-1] @ M)
        try:
            yield
        finally:
            self._xf.pop()

    @contextmanager
    def in_part(self, part):
        old = self.part
        self.part = part
        try:
            yield
        finally:
            self.part = old

    def seg(self, n, lo=6):
        """Segment count for the current LOD (circles are coarser at LOD1)."""
        return n if self.lod == 0 else max(lo, int(round(n * 0.6)))

    def mark(self, name, p):
        M = self._xf[-1]
        self.markers[name] = (M[:3, :3] @ np.asarray(p, dtype=np.float64) + M[:3, 3]).tolist()

    # -- raw emit ----------------------------------------------------------------------------------------------------------
    def emit(self, P, N, F, st, glow=None, part=None):
        M = self._xf[-1]
        R = M[:3, :3]
        P = np.asarray(P, dtype=np.float64) @ R.T + M[:3, 3]
        N = unit(np.asarray(N, dtype=np.float64) @ np.linalg.inv(R).T)
        F = np.asarray(F, dtype=np.int64)
        if len(F) == 0:
            return
        n = len(P)
        a = np.zeros((n, 7), dtype=np.float64)
        a[:, 0] = st.layer
        a[:, 1] = self.part if part is None else part
        a[:, 2] = st.glow if glow is None else glow
        a[:, 3:6] = st.tint
        self._P.append(P)
        self._N.append(N)
        self._F.append(F + self.nv)
        self._A.append(a)
        self.nv += n

    # -- sections and lofts ------------------------------------------------------------------------------------------------
    def loft(self, secs, st, caps=(True, True), chamfer=(0.0, 0.0), retilt=True):
        """Quads between consecutive sections (same point count). Caps are flat; a chamfer c > 0 adds a ring inset by c and c beyond the end section (hard-surface bevel)."""
        secs = list(secs)
        if self.lod > 0:
            chamfer = (0.0, 0.0)
        rings = []                                   # (P3, N3, skip, flat)
        for s in secs:
            rings.append([s.p3(), s.n3(), s.skip, False, s])
        # direction of the loft for the cap normals
        c0 = secs[0].center()
        c1 = secs[-1].center()
        d_all = unit(c1 - c0) if np.linalg.norm(c1 - c0) > 1e-9 else unit(np.cross(secs[0].U, secs[0].V))
        d_first = unit(secs[1].center() - c0) if len(secs) > 1 and np.linalg.norm(secs[1].center() - c0) > 1e-9 else d_all
        d_last = unit(c1 - secs[-2].center()) if len(secs) > 1 and np.linalg.norm(c1 - secs[-2].center()) > 1e-9 else d_all
        if len(secs) > 1:
            # retilt the side normals of the inner rings by the taper of the loft
            for i in range(len(rings)):
                a = rings[max(0, i - 1)][0]
                b = rings[min(len(rings) - 1, i + 1)][0]
                dP = unit(b - a)
                Nn = rings[i][1]
                if retilt:
                    comp = np.sum(Nn * dP, axis=1, keepdims=True)
                    rings[i][1] = unit(Nn - dP * comp)
        front_n, back_n = d_all, -d_all
        out = list(rings)
        cap_rings = [None, None]
        if chamfer[0] > 0 and caps[0]:
            c = chamfer[0]
            s = secs[0]
            ins = offset_outline(s.pts, s.nrm, s.skip, c)
            s2 = Sec(ins, s.nrm, s.skip, s.origin - d_first * c, s.U, s.V)
            P3 = s2.p3()
            cap_rings[0] = [P3, np.tile(-d_first, (len(P3), 1)), s.skip, True, s2]
            out.insert(0, cap_rings[0])
        if chamfer[1] > 0 and caps[1]:
            c = chamfer[1]
            s = secs[-1]
            ins = offset_outline(s.pts, s.nrm, s.skip, c)
            s2 = Sec(ins, s.nrm, s.skip, s.origin + d_last * c, s.U, s.V)
            P3 = s2.p3()
            cap_rings[1] = [P3, np.tile(d_last, (len(P3), 1)), s.skip, True, s2]
            out.append(cap_rings[1])
        # vertices
        Pall = np.concatenate([r[0] for r in out])
        Nall = np.concatenate([r[1] for r in out])
        n = len(out[0][0])
        F = []
        for i in range(len(out) - 1):
            sk = out[i][2] if not out[i][3] else out[i + 1][2]
            for j in range(n):
                if sk[j]:
                    continue
                j2 = (j + 1) % n
                a, b, c_, d = i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j
                F.append((a, b, c_))
                F.append((a, c_, d))
        F = np.array(F, dtype=np.int64).reshape(-1, 3)
        # orient every triangle by the average of its vertex normals
        if len(F):
            g = np.cross(Pall[F[:, 1]] - Pall[F[:, 0]], Pall[F[:, 2]] - Pall[F[:, 0]])
            avg = Nall[F[:, 0]] + Nall[F[:, 1]] + Nall[F[:, 2]]
            flip = np.sum(g * avg, axis=1) < 0
            F[flip] = F[flip][:, [0, 2, 1]]
        self.emit(Pall, Nall, F, st)
        # caps
        for k, (cap_ring, end_sec, nrm) in enumerate(((cap_rings[0], secs[0], -d_first), (cap_rings[1], secs[-1], d_last))):
            if not caps[k]:
                continue
            if cap_ring is not None:
                P = cap_ring[0]
                Pc, _ = clean_ring(P, P)
                self._cap_from_ring(Pc, nrm, st, share=None)
            else:
                P3 = end_sec.p3()
                Pc, _ = clean_ring(P3, P3)
                self._cap_from_ring(Pc, nrm, st, share=None)

    def _cap_from_ring(self, P3, nrm, st, share=None):
        n = len(P3)
        if n < 3:
            return
        # 2D coordinates in the plane of the cap for the triangulation
        nrm = unit(nrm)
        a = unit(np.cross(nrm, Z_AX if abs(nrm[2]) < 0.9 else X_AX))
        b = np.cross(nrm, a)
        poly = np.stack([P3 @ a, P3 @ b], axis=1)
        tris = triangulate(poly)
        if not tris:
            return
        F = np.array(tris, dtype=np.int64)
        gcr = np.cross(P3[F[:, 1]] - P3[F[:, 0]], P3[F[:, 2]] - P3[F[:, 0]])
        flip = np.sum(gcr * nrm, axis=1) < 0
        F[flip] = F[flip][:, [0, 2, 1]]
        self.emit(P3, np.tile(nrm, (n, 1)), F, st)

    # -- primitives --------------------------------------------------------------------------------------------------------
    def box(self, c, size, st, r=0.0, chamfer=None, seg=1, axis="y"):
        """A box centred at c with the full `size` = (sx, sy, sz); r = corner radius of the long edges (parallel to `axis`), chamfer = end chamfer (default = r).
        The bevels are dropped at LOD1."""
        sx, sy, sz = size
        if axis == "x":
            L, a, b = sx, sy, sz
        elif axis == "z":
            L, a, b = sz, sx, sy
        else:
            L, a, b = sy, sx, sz
        if self.lod > 0 or self.bevel_k <= 0:
            r = 0.0
        ch = r if chamfer is None else chamfer
        if self.lod > 0:
            ch = 0.0
        r = min(r, 0.45 * min(a, b))
        ch = min(ch, 0.45 * L, 0.45 * min(a, b))
        P, N, S = outline_rrect(a, b, r, seg if r > 0 else 1)
        if axis == "y":
            U, V, dirv = X_AX, Z_AX, Y_AX
        elif axis == "x":
            U, V, dirv = Y_AX, Z_AX, X_AX
        else:
            U, V, dirv = X_AX, Y_AX, Z_AX
        c = np.asarray(c, dtype=np.float64)
        s0 = Sec(P, N, S, c - dirv * L / 2.0, U, V)
        s1 = Sec(P, N, S, c + dirv * L / 2.0, U, V)
        self.loft([s0, s1], st, chamfer=(ch, ch), retilt=False)

    def prism(self, c, size, st, r=0.0, axis="y", chamfer=None):
        self.box(c, size, st, r=r, chamfer=chamfer, axis=axis)

    def cyl(self, p0, p1, r0, st, r1=None, n=12, chamfer=0.0, caps=(True, True), ry=None):
        """Cylinder or cone between p0 and p1 (radius r0 at p0, r1 at p1), `chamfer` rounds the caps (a ring inset by it)."""
        p0 = np.asarray(p0, dtype=np.float64)
        p1 = np.asarray(p1, dtype=np.float64)
        r1 = r0 if r1 is None else r1
        d = p1 - p0
        L = np.linalg.norm(d)
        if L < 1e-7:
            return
        w = d / L
        U = unit(np.cross(w, Z_AX if abs(w[2]) < 0.9 else X_AX))
        V = np.cross(w, U)
        nseg = self.seg(n)
        P0, N0, S0 = outline_circle(r0, nseg)
        P1, N1, S1 = outline_circle(r1, nseg)
        ch = chamfer if self.lod == 0 else 0.0
        ch = min(ch, 0.45 * L, 0.9 * min(r0, r1))
        self.loft([Sec(P0, N0, S0, p0, U, V), Sec(P1, N1, S1, p1, U, V)], st, caps=caps, chamfer=(ch, ch))

    def lathe(self, prof, st, n=14, cx=0.0, cz=0.0, caps=(True, True), hard=(), ry_k=1.0):
        """Surface of revolution about the Y axis through (cx, cz). prof = [(y, r), ...] from the front (large y) to the back; a point whose index is in `hard` (or a repeated y = a step)
        gets a hard edge. Steps (same y, different r) become flat annuli."""
        nseg = self.seg(n)
        a = 2.0 * math.pi * np.arange(nseg) / nseg
        ca, sa = np.cos(a), np.sin(a)
        pts = [(float(y), float(r)) for (y, r) in prof]
        m = len(pts)
        # a segment normal in (radial, axial): outward for a profile that runs front to back
        segn = []
        for i in range(m - 1):
            dy = pts[i + 1][0] - pts[i][0]
            dr = pts[i + 1][1] - pts[i][1]
            ln = math.hypot(dy, dr)
            if ln < 1e-9:
                segn.append(None)
            else:
                segn.append((-dy / ln, dr / ln))
        rings = []                                         # (y, r, (radial, axial) normal)
        for i in range(m):
            sn_prev = segn[i - 1] if i > 0 else None
            sn_next = segn[i] if i < m - 1 else None
            is_hard = (i in hard) or (sn_prev is None and i > 0) or (sn_next is None and i < m - 1)
            if sn_prev is not None and sn_next is not None and not is_hard:
                dot = sn_prev[0] * sn_next[0] + sn_prev[1] * sn_next[1]
                if dot < 0.5:                              # a corner sharper than 60 degrees is a hard edge
                    is_hard = True
            if is_hard:
                if sn_prev is not None:
                    rings.append((pts[i][0], pts[i][1], sn_prev, i))
                if sn_next is not None:
                    rings.append((pts[i][0], pts[i][1], sn_next, i))
                if sn_prev is None and sn_next is None:
                    rings.append((pts[i][0], pts[i][1], (1.0, 0.0), i))
            else:
                sn = sn_prev if sn_prev is not None else sn_next
                if sn_prev is not None and sn_next is not None:
                    sn = ((sn_prev[0] + sn_next[0]) / 2.0, (sn_prev[1] + sn_next[1]) / 2.0)
                    ln = math.hypot(*sn)
                    sn = (sn[0] / ln, sn[1] / ln)
                rings.append((pts[i][0], pts[i][1], sn, i))
        # connect consecutive rings that belong to the same segment (ring k and k+1 share a segment when they sit on different profile points, or the same point i with different normals do not connect)
        P_all, N_all, F = [], [], []
        base = []
        for (y, r, sn, i) in rings:
            base.append(len(P_all))
            for k in range(nseg):
                P_all.append((cx + r * ca[k], y, cz + r * sa[k]))
                N_all.append((sn[0] * ca[k], sn[1], sn[0] * sa[k]))
        for k in range(len(rings) - 1):
            (y0, r0, _, i0), (y1, r1, _, i1) = rings[k], rings[k + 1]
            if i0 == i1:
                continue                                    # the two rings of one hard point: no band
            if abs(y1 - y0) < 1e-9 and abs(r1 - r0) < 1e-9:
                continue
            for j in range(nseg):
                j2 = (j + 1) % nseg
                a_, b_, c_, d_ = base[k] + j, base[k] + j2, base[k + 1] + j2, base[k + 1] + j
                F.append((a_, b_, c_))
                F.append((a_, c_, d_))
        P_all = np.array(P_all)
        N_all = np.array(N_all)
        F = np.array(F, dtype=np.int64).reshape(-1, 3)
        if len(F):
            g = np.cross(P_all[F[:, 1]] - P_all[F[:, 0]], P_all[F[:, 2]] - P_all[F[:, 0]])
            avg = N_all[F[:, 0]] + N_all[F[:, 1]] + N_all[F[:, 2]]
            flip = np.sum(g * avg, axis=1) < 0
            F[flip] = F[flip][:, [0, 2, 1]]
            self.emit(P_all, N_all, F, st)
        # end caps (discs)
        if caps[0] and pts[0][1] > 1e-6:
            self._disc(pts[0][0], pts[0][1], (0.0, 1.0, 0.0), nseg, cx, cz, ca, sa, st)
        if caps[1] and pts[-1][1] > 1e-6:
            self._disc(pts[-1][0], pts[-1][1], (0.0, -1.0, 0.0), nseg, cx, cz, ca, sa, st)

    def _disc(self, y, r, nrm, nseg, cx, cz, ca, sa, st):
        P = np.stack([cx + r * ca, np.full(nseg, y), cz + r * sa], axis=1)
        N = np.tile(np.array(nrm), (nseg, 1))
        F = np.array([(0, k, k + 1) for k in range(1, nseg - 1)], dtype=np.int64)
        if len(F) == 0:
            return
        g = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
        flip = np.sum(g * N[F[:, 0]], axis=1) < 0
        F[flip] = F[flip][:, [0, 2, 1]]
        self.emit(P, N, F, st)

    def sphere(self, c, r, st, n=10, squash=(1.0, 1.0, 1.0)):
        """A sphere / ellipsoid (poles on Y)."""
        rings = max(4, self.seg(n, 4) // 2 + 2)
        prof = []
        for i in range(rings + 1):
            t = math.pi * i / rings
            prof.append((r * squash[1] * math.cos(t), r * math.sin(t) * 0.9999))
        prof[0] = (prof[0][0], 1e-5)
        prof[-1] = (prof[-1][0], 1e-5)
        with self.at((c[0], c[1], c[2])):
            if squash[0] != 1.0 or squash[2] != 1.0:
                s = (squash[0], squash[2])
                self._lathe_ellipse(prof, st, n, s)
            else:
                self.lathe(prof, st, n=n, caps=(False, False))

    def _lathe_ellipse(self, prof, st, n, s):
        M = np.eye(4)
        M[0, 0], M[2, 2] = s[0], s[1]
        self._xf.append(self._xf[-1] @ M)
        try:
            self.lathe(prof, st, n=n, caps=(False, False))
        finally:
            self._xf.pop()

    def torus(self, c, R, r, st, n=16, m=8, axis="y"):
        """A torus (ring around `axis`) as a lathe of a small circle: tube radius r, ring radius R."""
        nseg = self.seg(m, 5)
        ring = []
        for k in range(nseg):
            a = 2.0 * math.pi * k / nseg
            ring.append((r * math.sin(a), R + r * math.cos(a)))      # (y offset, radius)
        # build as a closed loft around Y: use a custom ring walk
        na = self.seg(n, 8)
        P_all, N_all, F = [], [], []
        for i in range(na):
            th = 2.0 * math.pi * i / na
            ct, st_ = math.cos(th), math.sin(th)
            for (dy, rr) in ring:
                P_all.append((rr * ct, dy, rr * st_))
                rad = (rr - R) / r if r > 0 else 0.0
                N_all.append((((rr - R) / r) * ct, dy / r, ((rr - R) / r) * st_))
        for i in range(na):
            i2 = (i + 1) % na
            for k in range(nseg):
                k2 = (k + 1) % nseg
                a_, b_, c_, d_ = i * nseg + k, i2 * nseg + k, i2 * nseg + k2, i * nseg + k2
                F.append((a_, b_, c_))
                F.append((a_, c_, d_))
        P_all = np.array(P_all)
        N_all = np.array(N_all)
        F = np.array(F, dtype=np.int64)
        g = np.cross(P_all[F[:, 1]] - P_all[F[:, 0]], P_all[F[:, 2]] - P_all[F[:, 0]])
        flip = np.sum(g * N_all[F[:, 0]], axis=1) < 0
        F[flip] = F[flip][:, [0, 2, 1]]
        R_ax = {"y": np.eye(3), "x": rot_z(math.pi / 2), "z": rot_x(math.pi / 2)}[axis]
        with self.at(c, R=R_ax):
            self.emit(P_all, N_all, F, st)

    def extrude(self, poly_yz, x0, x1, st, chamfer=0.0, x_scale1=None):
        """A side profile (list of (y, z) points, counter-clockwise seen from +X) pushed across X from x0 to x1. `chamfer` bevels the outline edges across the thickness (LOD0 only).
        x_scale1 = (sy, sz) scales the outline about its centroid at x1 (a stock that narrows)."""
        pts = np.asarray(poly_yz, dtype=np.float64)
        P, N, S = outline_poly(pts, hard=True)
        # outline coordinates: a = y, b = z. U = Y axis, V = Z axis; the sections sit at x0 and x1, the plane normal is U x V = +X
        s0 = Sec(P, N, S, np.array([x0, 0.0, 0.0]), Y_AX, Z_AX)
        if x_scale1 is None:
            P1 = P
        else:
            cen = pts.mean(axis=0)
            P1 = (P - cen) * np.array([x_scale1[0], x_scale1[1]]) + cen
        s1 = Sec(P1, N, S, np.array([x1, 0.0, 0.0]), Y_AX, Z_AX)
        self.loft([s0, s1], st, chamfer=(chamfer, chamfer), retilt=False)

    def sweep(self, path, outline_fn, st, up=(0, 0, 1), caps=(True, True), chamfer=(0.0, 0.0)):
        """A tube along a polyline path. outline_fn(t) -> (pts, nrm, skip) in the frame (U, V) of the section (t = 0..1 along the path); U is `up` x tangent."""
        path = np.asarray(path, dtype=np.float64)
        m = len(path)
        secs = []
        up = unit(np.asarray(up, dtype=np.float64))
        for i in range(m):
            a = path[max(0, i - 1)]
            b = path[min(m - 1, i + 1)]
            t = unit(b - a)
            u = np.cross(up, t)
            if np.linalg.norm(u) < 1e-6:
                u = np.cross(X_AX, t)
            u = unit(u)
            v = np.cross(t, u)
            pts, nrm, skip = outline_fn(i / max(1, m - 1))
            secs.append(Sec(pts, nrm, skip, path[i], u, v))
        self.loft(secs, st, caps=caps, chamfer=chamfer)

    def tri_fan(self, P, st, nrm=None):
        """A flat polygon (list of 3D points, convex) with a normal (default from the points)."""
        P = np.asarray(P, dtype=np.float64)
        if nrm is None:
            nrm = unit(np.cross(P[1] - P[0], P[2] - P[0]))
        self._cap_from_ring(P, np.asarray(nrm), st)

    def quad(self, a, b, c, d, st, nrm=None):
        self.tri_fan([a, b, c, d], st, nrm)

    # -- finishing: weld, normals check, AO + wear ------------------------------------------------------------------------
    def tri_count(self):
        return int(sum(len(f) for f in self._F))

    def finish(self, ao_rays=24, ao_dist=0.07, bvh=True):
        """Weld identical vertices, drop degenerate triangles, bake vertex AO and the edge wear mask. Returns a dict of arrays (K frame)."""
        P = np.concatenate(self._P)
        N = np.concatenate(self._N)
        A = np.concatenate(self._A)
        F = np.concatenate(self._F)
        # weld
        key = np.concatenate([np.round(P * 2e5), np.round(N * 500.0), A[:, 0:3] * 1000.0, np.round(A[:, 3:6] * 255.0)], axis=1).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        P, N, A = P[first], N[first], A[first]
        F = inv[F]
        keep = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
        F = F[keep]
        # drop triangles of zero area
        ar = np.linalg.norm(np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]]), axis=1)
        F = F[ar > 1e-12]
        # unused vertices out
        used = np.zeros(len(P), dtype=bool)
        used[F.reshape(-1)] = True
        remap = -np.ones(len(P), dtype=np.int64)
        remap[used] = np.arange(int(used.sum()))
        P, N, A = P[used], N[used], A[used]
        F = remap[F]
        ao, wear = bake_ao_wear(P, N, F, ao_rays, ao_dist, bvh)
        return {"P": P, "N": N, "F": F, "layer": A[:, 0].astype(np.int64), "part": A[:, 1].astype(np.int64), "glow": A[:, 2], "tint": A[:, 3:6], "ao": ao, "wear": wear}


def bake_ao_wear(P, N, F, rays=24, dist=0.07, use_bvh=True):
    """Per-vertex ambient occlusion (cosine hemisphere rays against the weapon itself, mathutils BVH) and an edge mask from the angle between the face normals around the vertex position."""
    nv = len(P)
    ao = np.ones(nv, dtype=np.float64)
    # face normals
    fn = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    fa = np.linalg.norm(fn, axis=1)
    fn = fn / np.maximum(fa[:, None], EPS)
    # wear: positions merged, the largest angle between adjacent face normals
    pk = np.round(P * 1e5).astype(np.int64)
    _, pid, pinv = np.unique(pk, axis=0, return_index=True, return_inverse=True)
    pinv = pinv.reshape(-1)
    npos = len(pid)
    nmin = np.ones(npos)
    # for each position, collect the face normals; the minimum dot with the mean normal approximates the sharpest angle
    sums = np.zeros((npos, 3))
    for k in range(3):
        np.add.at(sums, pinv[F[:, k]], fn * fa[:, None])
    msum = unit(sums)
    for k in range(3):
        d = np.sum(fn * msum[pinv[F[:, k]]], axis=1)
        np.minimum.at(nmin, pinv[F[:, k]], d)
    ang = np.degrees(np.arccos(np.clip(nmin, -1, 1)))
    wear_pos = np.clip((ang - 18.0) / 50.0, 0.0, 1.0)
    wear = wear_pos[pinv]
    if use_bvh:
        try:
            import bpy  # noqa: F401  (registers the mathutils module of the bpy wheel)
            from mathutils import Vector
            from mathutils.bvhtree import BVHTree
            tree = BVHTree.FromPolygons([tuple(p) for p in P], [tuple(int(i) for i in f) for f in F], epsilon=1e-6)
            rng = np.random.RandomState(7)
            # fixed hemisphere sample set (cosine weighted), rotated per vertex into the normal frame
            u1 = (np.arange(rays) + 0.5) / rays
            u2 = rng.rand(rays)
            r_ = np.sqrt(u1)
            th = 2.0 * math.pi * u2
            loc = np.stack([r_ * np.cos(th), r_ * np.sin(th), np.sqrt(np.maximum(0.0, 1.0 - u1))], axis=1)
            for i in range(nv):
                n = N[i]
                t = unit(np.cross(n, X_AX if abs(n[0]) < 0.9 else Y_AX))
                b = np.cross(n, t)
                dirs = loc[:, 0:1] * t + loc[:, 1:2] * b + loc[:, 2:3] * n
                o = Vector((P[i] + n * 0.0006).tolist())
                hit = 0.0
                for d in dirs:
                    if tree.ray_cast(o, Vector(d.tolist()), dist)[0] is not None:
                        hit += 1.0
                ao[i] = 1.0 - hit / rays
        except ImportError:
            pass
    return ao, wear


# ---------------------------------------------------------------------------------------------------------------- GLB writer
def write_glb(path, lods, markers, extras=None):
    """lods = [(name, mesh dict from G.finish, color_mode)], markers = {name: (x, y, z) K frame}. Positions to glTF axes (x, z, -y). Attributes: POSITION float32, NORMAL signed byte normalized (KHR_mesh_quantization), COLOR_0 ubyte (tint rgb, glow),
    TEXCOORD_0 ushort (layer, part)/255, TEXCOORD_1 ushort (ao, wear). One mesh node per LOD (L0, L1), one empty per marker."""
    import json
    import struct
    bin_chunks = []
    views, accs, meshes, nodes = [], [], [], []

    def add_view(data, target=None, stride=None):
        pad = (-sum(len(c) for c in bin_chunks)) % 4
        if pad:
            bin_chunks.append(b"\x00" * pad)
        off = sum(len(c) for c in bin_chunks)
        bin_chunks.append(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        if stride:
            v["byteStride"] = stride
        views.append(v)
        return len(views) - 1

    def add_acc(view, ctype, count, atype, norm=False, mn=None, mx=None):
        a = {"bufferView": view, "componentType": ctype, "count": int(count), "type": atype}
        if norm:
            a["normalized"] = True
        if mn is not None:
            a["min"] = [float(x) for x in mn]
            a["max"] = [float(x) for x in mx]
        accs.append(a)
        return len(accs) - 1

    for (name, m) in lods:
        P = m["P"]
        Pg = np.stack([P[:, 0], P[:, 2], -P[:, 1]], axis=1).astype(np.float32)
        Ng = np.stack([m["N"][:, 0], m["N"][:, 2], -m["N"][:, 1]], axis=1).astype(np.float32)
        col = np.zeros((len(P), 4), dtype=np.uint8)
        col[:, 0:3] = np.clip(np.round(m["color"] * 255.0), 0, 255)
        col[:, 3] = np.clip(np.round(m["glow"] * 255.0), 0, 255)
        uv0 = np.zeros((len(P), 2), dtype=np.uint16)
        uv0[:, 0] = m["layer"].astype(np.uint32) * 257
        uv0[:, 1] = m["part"].astype(np.uint32) * 257
        uv1 = np.zeros((len(P), 2), dtype=np.uint16)
        uv1[:, 0] = np.clip(np.round(m["ao"] * 255.0), 0, 255).astype(np.uint32) * 257
        uv1[:, 1] = np.clip(np.round(m["wear"] * 255.0), 0, 255).astype(np.uint32) * 257
        # interleaved vertex buffer: pos 12, normal 4 (signed byte x3 normalized + 1 pad, KHR_mesh_quantization), color 4, uv0 4, uv1 4 = 28 bytes
        n = len(P)
        n8 = np.zeros((n, 4), dtype=np.int8)
        n8[:, 0:3] = np.clip(np.round(Ng * 127.0), -127, 127)
        buf = np.zeros(n, dtype=[("p", "<f4", 3), ("n", "i1", 4), ("c", "u1", 4), ("u0", "<u2", 2), ("u1", "<u2", 2)])
        buf["p"], buf["n"], buf["c"], buf["u0"], buf["u1"] = Pg, n8, col, uv0, uv1
        vview = add_view(buf.tobytes(), 34962, 28)
        F = m["F"]
        # glTF front faces are counter-clockwise; K -> glTF (x, z, -y) is a proper rotation (determinant +1), the winding of the kit (counter-clockwise from outside) is kept
        Fg = F.astype(np.uint16 if n < 65535 else np.uint32)
        iview = add_view(Fg.tobytes(), 34963)
        a_pos = add_acc(vview, 5126, n, "VEC3", mn=Pg.min(axis=0), mx=Pg.max(axis=0))
        # attributes share the interleaved view with byteOffset
        accs[-1]["byteOffset"] = 0
        a_nrm = add_acc(vview, 5120, n, "VEC3", norm=True)
        accs[-1]["byteOffset"] = 12
        a_col = add_acc(vview, 5121, n, "VEC4", norm=True)
        accs[-1]["byteOffset"] = 16
        a_u0 = add_acc(vview, 5123, n, "VEC2", norm=True)
        accs[-1]["byteOffset"] = 20
        a_u1 = add_acc(vview, 5123, n, "VEC2", norm=True)
        accs[-1]["byteOffset"] = 24
        a_idx = add_acc(iview, 5123 if n < 65535 else 5125, len(Fg) * 3, "SCALAR")
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "COLOR_0": a_col, "TEXCOORD_0": a_u0, "TEXCOORD_1": a_u1},
                                                     "indices": a_idx, "mode": 4}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    for mname, p in markers.items():
        nodes.append({"name": mname, "translation": [float(p[0]), float(p[2]), float(-p[1])]})
    js = {"asset": {"version": "2.0", "generator": "quantum weapon kit"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes,
          "meshes": meshes, "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": sum(len(c) for c in bin_chunks)}]}
    if extras:
        js["asset"]["extras"] = extras
    binary = b"".join(bin_chunks)
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)
    return total
