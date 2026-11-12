"""Procedural rocks and boulders for the landscape (wave 112): cube-sphere superellipsoids cut by random planes (flat cleaved faces), noise-displaced, with normals smoothed only
across gentle edges, a flat sunk base and a baked ambient-occlusion tint. Four shapes (round boulder, angular block, flat slab, tall block) at two levels of detail.
No UVs: assets/shaders/land_rock.gdshader maps the terrain's own rock layers tri-planar from the object position (the same texture memory as the terrain).
"""
import math

import numpy as np

from mb import MeshBuilder

SHAPES = {
    #       axes (x, y, z),        exponent, cuts, noise amplitude, seed
    "a": ((1.00, 0.78, 0.92), 2.25, 5, 0.075, 11),     # round boulder
    "b": ((1.00, 0.85, 0.80), 3.1, 8, 0.055, 22),      # angular block
    "c": ((1.25, 0.52, 0.95), 2.8, 6, 0.060, 33),      # flat slab
    "d": ((0.80, 1.25, 0.78), 3.0, 7, 0.060, 44),      # tall block
}


def _noise3(p, freq, seed):
    """Cheap smooth 3D value noise at points p (n x 3), -1..1: a hash of the integer lattice, trilinearly blended."""
    q = p * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)

    def h(ix, iy, iz):
        x = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
        x = (x ^ (x >> 13)) * 0x5bd1e995
        x = x ^ (x >> 15)
        return (x & 0xFFFF).astype(np.float64) / 65535.0 * 2.0 - 1.0

    out = np.zeros(len(p))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out += w * h(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out


def rock(shape, n, seed_off=0):
    axes, expo, cuts, amp, seed = SHAPES[shape]
    rng = np.random.RandomState(seed + seed_off)
    # cube sphere: six faces of an (n+1) x (n+1) grid
    verts = []
    tris = []
    face_dirs = [((1, 0, 0), (0, 1, 0), (0, 0, 1)), ((-1, 0, 0), (0, 1, 0), (0, 0, -1)), ((0, 1, 0), (1, 0, 0), (0, 0, -1)), ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
                 ((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (-1, 0, 0), (0, 1, 0))]
    for fd in face_dirs:
        n0, u, v = [np.array(a, dtype=np.float64) for a in fd]
        base = len(verts)
        for j in range(n + 1):
            for i in range(n + 1):
                a = (i / n) * 2 - 1
                b = (j / n) * 2 - 1
                verts.append(n0 + u * a + v * b)
        for j in range(n):
            for i in range(n):
                a0 = base + j * (n + 1) + i
                tris.append((a0, a0 + 1, a0 + n + 2))
                tris.append((a0, a0 + n + 2, a0 + n + 1))
    P = np.array(verts)
    P = P / np.linalg.norm(P, axis=1, keepdims=True)
    # superellipsoid: push the sphere towards a rounded box
    e = 2.0 / expo
    P = np.sign(P) * np.abs(P) ** e
    P = P / np.maximum(np.linalg.norm(P, axis=1, keepdims=True), 1e-6) * np.maximum(np.max(np.abs(P), axis=1, keepdims=True), 1e-6)
    P = P * np.array(axes)
    # cleaved faces: random planes cut the surface flat
    for _ in range(cuts):
        d = rng.normal(size=3)
        d[1] = abs(d[1]) * 0.8 + 0.2 if rng.rand() < 0.5 else d[1]
        d /= np.linalg.norm(d)
        off = rng.uniform(0.62, 0.86) * np.max(np.abs(P))
        dist = P @ d
        over = dist > off
        P[over] -= np.outer(dist[over] - off, d)
    # lumps and chips
    P = P * (1.0 + amp * _noise3(P, 1.7, seed + seed_off)[:, None]) + amp * 0.35 * rng.normal(size=P.shape) * 0.0
    P = P * (1.0 + amp * 0.6 * _noise3(P, 4.3, seed + 7)[:, None])
    # a flat base that sits in the ground
    lo = -0.34 * np.max(P[:, 1])
    P[:, 1] = np.maximum(P[:, 1], lo)
    # normalise: about 1.6 m across, base on y = 0 at its lowest, slightly buried by the scatter's own sink
    P -= np.array([0.0, P[:, 1].min(), 0.0])
    ext = np.max(np.abs(P[:, [0, 2]]))
    P *= 0.80 / ext
    return P, np.array(tris)


def _face_normals(P, T):
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    fn = np.cross(b - a, c - a)
    ln = np.linalg.norm(fn, axis=1, keepdims=True)
    return fn / np.maximum(ln, 1e-12), ln[:, 0]


def build(shape, n, seed_off=0, tint_lo=0.62):
    """A MeshBuilder holding the rock with crease-aware normals (triangle soup: positions shared only inside a smooth group)."""
    P, T = rock(shape, n, seed_off)
    return _finish(P, T, tint_lo)


def arch(variant=0):
    """A natural rock arch in metres (wave 112): a thick slab swept along a half ellipse (span 22 m / height 14 m for variant 0, 15 m / 17 m for variant 1), thicker at the feet than at
    the crown, noise-displaced, the feet sunk 1.5 m below y = 0. Local x = the span, y up, z = the depth of the slab. Returns the MeshBuilder; AA = (half span, crown height)."""
    half, top, depth, tin_foot, tin_crown, seed = ((11.0, 12.5, 5.2, 4.4, 2.6, 71), (7.6, 15.5, 4.6, 3.6, 2.2, 83))[variant]
    rng = np.random.RandomState(seed)
    rings, sides = 30, 14
    verts = []
    for i in range(rings + 1):
        th = -0.14 + (math.pi + 0.28) * i / rings
        cx, cy = half * math.cos(th), top * math.sin(th)
        # tangent and in-plane normal of the centre line
        tx, ty = -half * math.sin(th), top * math.cos(th)
        tl = math.hypot(tx, ty)
        tx, ty = tx / tl, ty / tl
        nx, ny = -ty, tx
        crown = math.sin(max(0.0, min(math.pi, th)))
        r_in = (tin_foot + (tin_crown - tin_foot) * crown ** 1.4) * (1.0 + 0.16 * math.sin(th * 3.7 + seed) + 0.1 * math.sin(th * 7.9))
        r_out = depth * (0.92 + 0.14 * math.sin(th * 2.3 + 1.0)) * (1.0 + 0.25 * (1.0 - crown))
        for j in range(sides):
            a = math.tau * j / sides
            ca, sa = math.cos(a), math.sin(a)
            e = 2.0 / 2.6                                                                         # a boxy section
            u = math.copysign(abs(ca) ** e, ca) * r_in
            v = math.copysign(abs(sa) ** e, sa) * r_out
            verts.append([cx + nx * u, cy + ny * u, v])
    P = np.array(verts)
    # rock: lumps at two scales, the feet flattened into the ground
    P = P + 0.55 * _noise3(P, 0.31, seed)[:, None] * np.array([1.0, 1.0, 1.0]) + 0.22 * _noise3(P, 0.9, seed + 5)[:, None] * np.array([1.0, 1.0, 1.0])
    P[:, 1] = np.maximum(P[:, 1], -1.5)
    tris = []
    for i in range(rings):
        for j in range(sides):
            a0 = i * sides + j
            a1 = i * sides + (j + 1) % sides
            b0 = (i + 1) * sides + j
            b1 = (i + 1) * sides + (j + 1) % sides
            tris.append((a0, a1, b0))                                                              # counter-clockwise seen from outside (glTF); the importer flips it for Godot
            tris.append((a1, b1, b0))
    # caps at both feet (fans round the ring centre)
    for ring, flip in ((0, False), (rings, True)):
        c = len(P)
        P = np.vstack([P, P[ring * sides:(ring + 1) * sides].mean(axis=0)])
        for j in range(sides):
            a = ring * sides + j
            b = ring * sides + (j + 1) % sides
            tris.append((c, a, b) if flip else (c, b, a))
    T = np.array(tris)
    return _finish(P, T, 0.58)


def _finish(P, T, tint_lo):
    # weld coincident cube edge vertices so the angle test sees real neighbours
    key = np.round(P * 1e4).astype(np.int64)
    uniq = {}
    remap = np.zeros(len(P), dtype=np.int64)
    for i, k in enumerate(map(tuple, key)):
        remap[i] = uniq.setdefault(k, len(uniq))
    nv = len(uniq)
    W = np.zeros((nv, 3))
    for i in range(len(P)):
        W[remap[i]] = P[i]
    T = remap[T]
    T = np.array([t for t in T if len({t[0], t[1], t[2]}) == 3])
    fn, area = _face_normals(W, T)
    adj = [[] for _ in range(nv)]
    for ti, t in enumerate(T):
        for v in t:
            adj[v].append(ti)
    mb = MeshBuilder()
    cos_t = math.cos(math.radians(42.0))
    ymax = W[:, 1].max()
    for ti, t in enumerate(T):
        idx = []
        for v in t:
            acc = np.zeros(3)
            for tj in adj[v]:
                if np.dot(fn[ti], fn[tj]) >= cos_t:
                    acc += fn[tj] * area[tj]
            nrm = acc / max(np.linalg.norm(acc), 1e-9) if np.linalg.norm(acc) > 1e-9 else fn[ti]
            y = W[v][1]
            ao = tint_lo + (1.0 - tint_lo) * min(1.0, max(0.0, y / max(ymax, 1e-6) * 1.15))
            idx.append(mb._v(W[v], nrm, (0.0, 0.0), (0.0, 0.0), (ao, ao, ao, 0.0)))
        mb.I.append((idx[0], idx[1], idx[2]))
    return mb
