"""High-poly source for the character bakes (needs bpy + numpy).

`HiPoly.from_parts(parts, detail)` takes the BUILT low-poly parts (helpers.Part with .obj), subdivides every one two levels
(Catmull-Clark, about 16x the triangles: about 250k for the hero), displaces the vertices along their smooth normals with a
per-surface-kind relief that is real geometry (chitin scutes with grooves and domed cells, panel lines with rivets on plating and gear,
satin folds on the cloak, a fine pitting everywhere), and keeps a BVH of it. `atlas.bake` then casts one ray per texel of the low-poly
mesh along its normal onto this surface and writes what a sculpt bake writes: the tangent-space normal of the high-poly surface and a
cavity term (how far the relief lies below / above the low-poly surface), which the baker folds into the normal map, the AO map and the
albedo grime. Everything is deterministic (fixed hashes, no random state), so the rebuild is byte-identical.
"""
import numpy as np

import bpy
from mathutils.bvhtree import BVHTree

CAGE = 0.012                 # rays start this far above the low-poly surface and look this far (x2) into it


def _hash3(ix, iy, iz, salt):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (salt * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0x1000000)


def worley(P, cell, salt=0):
    """Distance to the nearest (f1) and second nearest (f2) feature point of a jittered 3D grid with cell size `cell`; also the id hash of the nearest cell."""
    q = P / cell
    base = np.floor(q).astype(np.int64)
    f1 = np.full(len(P), 9.0)
    f2 = np.full(len(P), 9.0)
    cid = np.zeros(len(P))
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = base + np.array([dx, dy, dz])
                fp = c + np.stack([_hash3(c[:, 0], c[:, 1], c[:, 2], salt + k) for k in (1, 2, 3)], axis=1) * 0.85 + 0.075
                d = np.linalg.norm(q - fp, axis=1)
                new1 = d < f1
                f2 = np.where(new1, f1, np.minimum(f2, d))
                cid = np.where(new1, _hash3(c[:, 0], c[:, 1], c[:, 2], salt + 9), cid)
                f1 = np.where(new1, d, f1)
    return f1 * cell, f2 * cell, cid


def sm(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def relief(kind, P, noise, scale=1.0):
    """Displacement in metres along the outward normal for surface `kind` at the points P (n x 3)."""
    n = len(P)
    d = np.zeros(n)
    pit = (noise.fbm3(P, 160.0 * scale, 2, 0.5, 5) - 0.5) * 0.0012
    if kind in ("shell", "chitin"):
        cell = (0.036 if kind == "shell" else 0.026) / scale
        f1, f2, cid = worley(P, cell, 11)
        border = (f2 - f1)                                          # 0 on the seam between two scutes
        groove = 1.0 - sm(0.0015, 0.0055, border)
        dome = sm(cell * 0.6, 0.0, f1) * (0.0016 + 0.0016 * cid)    # each scute a little domed, each one a little different
        ridge = (noise.fbm3(P, 38.0 * scale, 3, 0.5, 2) - 0.5) * 0.0025
        d = -0.0022 * groove + dome + ridge + pit
    elif kind in ("steel", "plating", "carbon", "solid"):
        pitch = 0.07 / scale
        g = np.abs(((P + 0.013) / pitch) - np.round((P + 0.013) / pitch)) * pitch
        seam = 1.0 - sm(0.0012, 0.0042, np.minimum(np.minimum(g[:, 0], g[:, 1]), g[:, 2]))
        node = 1.0 - sm(0.0025, 0.0055, np.sqrt(np.minimum(g[:, 0], 0.03) ** 2 + np.minimum(g[:, 1], 0.03) ** 2 + np.minimum(g[:, 2], 0.03) ** 2))
        d = -0.0016 * seam + 0.0014 * node + pit * 1.5
    elif kind == "silk":
        s = P[:, 0] * 95.0 + P[:, 1] * 40.0 + (noise.fbm3(P, 9.0, 2, 0.5, 3) - 0.5) * 14.0
        d = 0.0011 * np.sin(s) + pit
    elif kind == "fabric":
        d = 0.0007 * np.sin(P[:, 2] * 700.0) * np.sin((P[:, 0] + P[:, 1]) * 700.0) + (noise.fbm3(P, 45.0, 3, 0.5, 4) - 0.5) * 0.003
    elif kind == "rubber":
        d = (noise.fbm3(P, 120.0, 2, 0.5, 7) - 0.5) * 0.002
    else:                                                           # glass, glow, paint, flat: smooth
        d = pit * 0.3
    return d


class HiPoly:
    pass


def _eval_subsurf(obj, levels):
    tmp = obj.copy()
    tmp.data = obj.data.copy()
    tmp.modifiers.clear()
    bpy.context.scene.collection.objects.link(tmp)
    mod = tmp.modifiers.new("hp", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    mod.subdivision_type = "CATMULL_CLARK"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    return me


def from_parts(parts, noise, levels=2, scale=1.0, kind_scale=None):
    """parts: built helpers.Part objects. kind_scale: optional {kind: displacement multiplier}."""
    P_all, T_all, K_all = [], [], []
    off = 0
    for p in parts:
        me = _eval_subsurf(p.obj, levels)
        nv = len(me.vertices)
        if nv == 0:
            bpy.data.meshes.remove(me)
            continue
        co = np.empty(nv * 3, np.float64)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3) + np.array(p.obj.location)
        vn = np.empty(nv * 3, np.float64)
        me.vertex_normals.foreach_get("vector", vn)
        vn = vn.reshape(-1, 3)
        me.calc_loop_triangles()
        nt = len(me.loop_triangles)
        tv = np.empty(nt * 3, np.int32)
        me.loop_triangles.foreach_get("vertices", tv)
        tp = np.empty(nt, np.int32)
        me.loop_triangles.foreach_get("polygon_index", tp)
        npoly = len(me.polygons)
        mi = np.empty(npoly, np.int32)
        me.polygons.foreach_get("material_index", mi)
        kinds = np.array([m.kind if i < len(p.slots) else "solid" for i, m in enumerate(p.slots)] or ["solid"])
        vkind = np.full(nv, "solid", dtype=object)
        tv = tv.reshape(-1, 3)
        tkind = kinds[np.minimum(mi[tp], len(kinds) - 1)]
        for c in range(3):
            vkind[tv[:, c]] = tkind
        disp = np.zeros(nv)
        for k in set(vkind.tolist()):
            sel = np.nonzero(vkind == k)[0]
            disp[sel] = relief(k, co[sel], noise, scale) * (kind_scale or {}).get(k, 1.0)
        co = co + vn * disp[:, None]
        P_all.append(co)
        T_all.append(tv + off)
        off += nv
        bpy.data.meshes.remove(me)
    h = HiPoly()
    h.P = np.concatenate(P_all)
    h.T = np.concatenate(T_all)
    tri = h.P[h.T]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    vn = np.zeros_like(h.P)
    for c in range(3):
        np.add.at(vn, h.T[:, c], fn)
    h.N = vn / (np.linalg.norm(vn, axis=1, keepdims=True) + 1e-12)
    h.tree = BVHTree.FromPolygons([tuple(v) for v in h.P], [tuple(int(i) for i in t) for t in h.T], epsilon=0.0)
    return h


def sample(h, P, N, T, B):
    """For texels with position P, normal N, tangent T and bitangent B (all n x 3, unit): the high-poly surface under each.
    Returns (n_ts (n x 3 tangent-space normal, +Z = low-poly normal), depth (metres, + = relief above the low-poly surface))."""
    n = len(P)
    ts = np.zeros((n, 3), np.float32)
    ts[:, 2] = 1.0
    depth = np.zeros(n, np.float32)
    hit_f = np.full(n, -1, np.int64)
    hit_p = np.zeros((n, 3))
    ray = h.tree.ray_cast
    from mathutils import Vector
    starts = P + N * CAGE
    for i in range(n):
        loc, nor, fi, dist = ray(Vector(starts[i]), Vector(-N[i]), CAGE * 2.0)
        if loc is not None:
            hit_f[i] = fi
            hit_p[i] = loc
            depth[i] = CAGE - dist
    ok = hit_f >= 0
    idx = np.nonzero(ok)[0]
    tri = h.T[hit_f[idx]]
    a, b, c = h.P[tri[:, 0]], h.P[tri[:, 1]], h.P[tri[:, 2]]
    p = hit_p[idx]
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
    d20, d21 = (v2 * v0).sum(1), (v2 * v1).sum(1)
    den = d00 * d11 - d01 * d01
    den = np.where(np.abs(den) < 1e-18, 1e-18, den)
    w1 = (d11 * d20 - d01 * d21) / den
    w2 = (d00 * d21 - d01 * d20) / den
    w0 = 1.0 - w1 - w2
    nh = h.N[tri[:, 0]] * w0[:, None] + h.N[tri[:, 1]] * w1[:, None] + h.N[tri[:, 2]] * w2[:, None]
    nh /= np.linalg.norm(nh, axis=1, keepdims=True) + 1e-12
    n_ts = np.stack([(nh * T[idx]).sum(1), (nh * B[idx]).sum(1), (nh * N[idx]).sum(1)], axis=1)
    good = n_ts[:, 2] > 0.35                               # a hit on a neighbouring part's surface is rejected
    n_ts[~good] = (0.0, 0.0, 1.0)
    depth[idx[~good]] = 0.0
    depth[~ok] = 0.0
    n_ts /= np.linalg.norm(n_ts, axis=1, keepdims=True) + 1e-12
    ts[idx] = n_ts.astype(np.float32)
    return ts, depth
