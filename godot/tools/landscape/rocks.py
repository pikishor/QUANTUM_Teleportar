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
