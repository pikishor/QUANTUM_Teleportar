"""Mesh builder and a pure-Python GLB writer for the landscape generators (no bpy needed).

MeshBuilder collects vertices with the attributes the vegetation shaders use:
    POSITION  metres, y up, the trunk on the y axis, the ground at y = 0
    NORMAL    smooth around a tube, BENT (pointing away from the crown centre) on foliage cards so a crown is lit like a soft ball, not like a pile of planes
    TEXCOORD_0   bark: u around the tube, v along it in bark-tile units (repeat);  foliage cards: the atlas rectangle of the sprite (0..1 of the foliage atlas)
    TEXCOORD_1   x = flutter weight (0 trunk .. 1 leaf tips), y = emission amount (alien trees)
    COLOR_0   rgb = ambient-occlusion tint (dark inside the crown, bright outside), a = 0 bark / 1 foliage card
"""
import json
import math
import struct

import numpy as np


def _norm(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else np.array([0.0, 1.0, 0.0])


def perp(v):
    """Any unit vector perpendicular to v."""
    v = _norm(v)
    a = np.array([1.0, 0.0, 0.0]) if abs(v[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
    return _norm(np.cross(v, a))


def rot_about(v, axis, ang):
    axis = _norm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(axis, v) * s + axis * np.dot(axis, v) * (1.0 - c)


class MeshBuilder:
    def __init__(self):
        self.V = []
        self.N = []
        self.U = []
        self.U2 = []
        self.C = []
        self.I = []
        self.cards = []                      # (center, right, up, uv rect, tint, cell name): kept for the impostor bake
        self.tubes = []                      # (points, radii) kept for the impostor bake

    # --- primitives -----------------------------------------------------------------------------------------------------------------------
    def _v(self, p, n, uv, uv2, c):
        self.V.append(np.asarray(p, dtype=np.float32))
        self.N.append(np.asarray(_norm(n), dtype=np.float32))
        self.U.append(np.asarray(uv, dtype=np.float32))
        self.U2.append(np.asarray(uv2, dtype=np.float32))
        self.C.append(np.asarray(c, dtype=np.float32))
        return len(self.V) - 1

    def tube(self, pts, radii, sides=6, uv_len=1.6, u_rep=1.0, tint=(1.0, 1.0, 1.0), cap=True, rng=None, noise=0.0, v0=0.0, flex=0.0):
        """A tapered tube along the polyline `pts` (k x 3) with a radius per point. UVs wrap the bark texture: u around, v along the length."""
        pts = [np.asarray(p, dtype=np.float64) for p in pts]
        k = len(pts)
        if k < 2:
            return
        self.tubes.append((np.array(pts), np.array(radii, dtype=np.float64)))
        tans = []
        for i in range(k):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, k - 1)]
            tans.append(_norm(b - a))
        n0 = perp(tans[0])
        frames = []
        n = n0
        for i in range(k):
            t = tans[i]
            n = _norm(n - t * np.dot(n, t))
            if np.linalg.norm(n) < 1e-6:
                n = perp(t)
            frames.append((n, np.cross(t, n)))
        rings = []
        vcum = v0
        jit = None
        if rng is not None and noise > 0:
            jit = rng.uniform(1.0 - noise, 1.0 + noise, size=(k, sides + 1))
            jit[:, sides] = jit[:, 0]
        for i in range(k):
            if i > 0:
                vcum += np.linalg.norm(pts[i] - pts[i - 1]) / uv_len
            nn, bb = frames[i]
            slope = 0.0
            if i < k - 1:
                seg = max(np.linalg.norm(pts[i + 1] - pts[i]), 1e-6)
                slope = (radii[i] - radii[i + 1]) / seg
            ring = []
            for j in range(sides + 1):
                a = math.tau * j / sides
                d = nn * math.cos(a) + bb * math.sin(a)
                r = radii[i] * (jit[i, j] if jit is not None else 1.0)
                nrm = d + tans[i] * slope
                ring.append(self._v(pts[i] + d * r, nrm, (u_rep * j / sides, vcum), (flex, 0.0), (tint[0], tint[1], tint[2], 0.0)))
            rings.append(ring)
        for i in range(k - 1):
            for j in range(sides):
                a, b, c, d = rings[i][j], rings[i][j + 1], rings[i + 1][j], rings[i + 1][j + 1]
                self.I.append((a, c, b))
                self.I.append((b, c, d))
        if cap and radii[-1] > 1e-3:
            tip = self._v(pts[-1] + tans[-1] * radii[-1] * 1.2, tans[-1], (0.5 * u_rep, vcum + 0.2), (flex, 0.0), (tint[0], tint[1], tint[2], 0.0))
            for j in range(sides):
                self.I.append((rings[-1][j], tip, rings[-1][j + 1]))

    def card(self, center, right, up, rect, bent, tint=(1, 1, 1), flutter=0.7, emit=0.0, cell=None, flip_u=False):
        """A foliage card: `right` and `up` are HALF-extent vectors, rect = (u0, v0, u1, v1) of the sprite in the atlas (v0 = the top of the sprite = the card's +up side)."""
        c = np.asarray(center, dtype=np.float64)
        r = np.asarray(right, dtype=np.float64)
        u = np.asarray(up, dtype=np.float64)
        u0, v0, u1, v1 = rect
        if flip_u:
            u0, u1 = u1, u0
        col = (tint[0], tint[1], tint[2], 1.0)
        a = self._v(c - r - u, bent, (u0, v1), (flutter, emit), col)
        b = self._v(c + r - u, bent, (u1, v1), (flutter, emit), col)
        cc = self._v(c + r + u, bent, (u1, v0), (flutter, emit), col)
        d = self._v(c - r + u, bent, (u0, v0), (flutter, emit), col)
        self.I.append((a, b, cc))
        self.I.append((a, cc, d))
        self.cards.append((c, r, u, rect, tint, cell, flip_u))

    def strip(self, pts, widths, rect, bent, tint=(1, 1, 1), flutter=0.7, emit=0.0, side=None, cell=None):
        """A bent leaf strip (palm frond): quads along `pts`, `widths` = half width per point, `side` = the sideways direction. u of the sprite runs along the strip, v across it."""
        pts = [np.asarray(p, dtype=np.float64) for p in pts]
        u0, v0, u1, v1 = rect
        k = len(pts)
        ids = []
        for i in range(k):
            t = _norm(pts[min(i + 1, k - 1)] - pts[max(i - 1, 0)])
            s = _norm(np.cross(t, np.array([0.0, 1.0, 0.0]))) if side is None else _norm(side)
            fu = u0 + (u1 - u0) * i / (k - 1)
            col = (tint[0], tint[1], tint[2], 1.0)
            a = self._v(pts[i] - s * widths[i], bent, (fu, v1), (flutter * (0.3 + 0.7 * i / (k - 1)), emit), col)
            b = self._v(pts[i] + s * widths[i], bent, (fu, v0), (flutter * (0.3 + 0.7 * i / (k - 1)), emit), col)
            ids.append((a, b))
        for i in range(k - 1):
            a, b = ids[i]
            c, d = ids[i + 1]
            self.I.append((a, c, b))
            self.I.append((b, c, d))
        self.cards.append(("strip", pts, widths, rect, tint, cell, side))

    def blob(self, center, radius, bark_uv=(0.5, 0.5), segs=6, rings=3, tint=(1, 1, 1), squash=1.0):
        """A small low-poly sphere (coconuts, burls)."""
        c = np.asarray(center, dtype=np.float64)
        top = self._v(c + np.array([0, radius * squash, 0]), [0, 1, 0], bark_uv, (0, 0), (tint[0], tint[1], tint[2], 0.0))
        rows = []
        for r in range(1, rings + 1):
            lat = math.pi / 2 - math.pi * r / (rings + 1)
            row = []
            for j in range(segs):
                a = math.tau * j / segs
                d = np.array([math.cos(a) * math.cos(lat), math.sin(lat), math.sin(a) * math.cos(lat)])
                row.append(self._v(c + d * radius * np.array([1, squash, 1]), d, bark_uv, (0, 0), (tint[0], tint[1], tint[2], 0.0)))
            rows.append(row)
        bot = self._v(c - np.array([0, radius * squash, 0]), [0, -1, 0], bark_uv, (0, 0), (tint[0], tint[1], tint[2], 0.0))
        for j in range(segs):
            self.I.append((top, rows[0][(j + 1) % segs], rows[0][j]))
        for r in range(rings - 1):
            for j in range(segs):
                j2 = (j + 1) % segs
                self.I.append((rows[r][j], rows[r][j2], rows[r + 1][j]))
                self.I.append((rows[r][j2], rows[r + 1][j2], rows[r + 1][j]))
        for j in range(segs):
            self.I.append((bot, rows[-1][j], rows[-1][(j + 1) % segs]))

    # --- output ----------------------------------------------------------------------------------------------------------------------------
    def arrays(self):
        return (np.array(self.V, dtype=np.float32), np.array(self.N, dtype=np.float32), np.array(self.U, dtype=np.float32), np.array(self.U2, dtype=np.float32),
                np.array(self.C, dtype=np.float32), np.array(self.I, dtype=np.uint32).reshape(-1))

    def tri_count(self):
        return len(self.I)

    def height(self):
        v = np.array(self.V)
        return float(v[:, 1].max()) if len(v) else 0.0

    def bounds(self):
        v = np.array(self.V)
        return v.min(axis=0), v.max(axis=0)


def write_glb(path, meshes, extras=None):
    """meshes: {node name: MeshBuilder}. One node and one mesh per entry, one shared double-sided material."""
    blob = bytearray()
    views = []
    accessors = []
    mesh_defs = []
    nodes = []

    def add_view(data, target):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data.tobytes())
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data.tobytes()), "target": target})
        return len(views) - 1

    def add_acc(view, ctype, count, typ, mn=None, mx=None):
        a = {"bufferView": view, "componentType": ctype, "count": int(count), "type": typ}
        if mn is not None:
            a["min"] = [float(x) for x in mn]
            a["max"] = [float(x) for x in mx]
        accessors.append(a)
        return len(accessors) - 1

    for name, mb in meshes.items():
        V, N, U, U2, C, I = mb.arrays()
        attrs = {}
        attrs["POSITION"] = add_acc(add_view(V, 34962), 5126, len(V), "VEC3", V.min(axis=0), V.max(axis=0))
        attrs["NORMAL"] = add_acc(add_view(N, 34962), 5126, len(N), "VEC3")
        attrs["TEXCOORD_0"] = add_acc(add_view(U, 34962), 5126, len(U), "VEC2")
        attrs["TEXCOORD_1"] = add_acc(add_view(U2, 34962), 5126, len(U2), "VEC2")
        attrs["COLOR_0"] = add_acc(add_view(C, 34962), 5126, len(C), "VEC4")
        idx = add_acc(add_view(I, 34963), 5125, len(I), "SCALAR")
        mesh_defs.append({"name": name, "primitives": [{"attributes": attrs, "indices": idx, "material": 0, "mode": 4}]})
        node = {"name": name, "mesh": len(mesh_defs) - 1}
        if extras and name in extras:
            node["extras"] = extras[name]
        nodes.append(node)
    js = {
        "asset": {"version": "2.0", "generator": "quantum-teleportar tools/landscape"},
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": mesh_defs,
        "materials": [{"name": "Land", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0}, "doubleSided": True}],
        "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
    }
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(jb) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    return total
