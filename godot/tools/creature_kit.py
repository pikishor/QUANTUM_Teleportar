#!/usr/bin/env python3
"""Creature / flora / vehicle kit: converts Quaternius Ultimate Space Kit pieces (CC0, art_sources/quaternius_ultimate_space_kit) into lean glb files, no Blender needed.

Per piece: the glTF nodes are baked to one mesh, the Atlas.png colour is sampled into COLOR_0 (desaturated towards the quantum-realism palette), the mesh is decimated by
vertex clustering to a triangle cap, feet go to y = 0, x / z are centred, the front faces -Z. Outputs in assets/models:
  car_rover.glb, car_skiff.glb   vehicles: node "Body" (material "Body") plus WheelFL / FR / RL / RR for the rover (the skiff is a hover craft: no wheels)
  pickup_weapon.glb              Pickup_Bullets
  kit_flora.glb                  nine pieces as separate nodes (Tree0-2, Plant0-2, Rock0-2), read by scripts/world/creature_kit.gd into the street kit's merged mesh
Run from godot/:  python3 tools/creature_kit.py     (needs numpy, Pillow)
"""
import base64
import io
import json
import math
import os
import struct

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "art_sources", "quaternius_ultimate_space_kit"))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models"))

# node name -> (source piece, triangle cap, height in metres)
FLORA = {
    "Tree0": ("Environment/Tree_Swirl_1", 220, 4.2), "Tree1": ("Environment/Tree_Spiral_2", 220, 4.2), "Tree2": ("Environment/Tree_Light_1", 220, 4.2),
    "Plant0": ("Environment/Plant_1", 100, 1.1), "Plant1": ("Environment/Bush_2", 100, 1.1), "Plant2": ("Environment/Plant_3", 100, 1.1),
    "Rock0": ("Environment/Rock_2", 70, 0.9), "Rock1": ("Environment/Rock_Large_1", 80, 1.5), "Rock2": ("Environment/Rock_4", 70, 0.8),
}


def load(path):
    d = json.load(open(path))
    bufs = []
    for b in d["buffers"]:
        uri = b["uri"]
        bufs.append(base64.b64decode(uri.split(",", 1)[1]) if uri.startswith("data:") else open(os.path.join(os.path.dirname(path), uri), "rb").read())
    return d, bufs


def accessor(d, bufs, i):
    a = d["accessors"][i]
    bv = d["bufferViews"][a["bufferView"]]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    raw = bufs[bv["buffer"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    item = np.dtype(comp).itemsize * n
    stride = bv.get("byteStride", 0) or item
    out = np.empty((a["count"], n), comp)
    for k in range(a["count"]):
        out[k] = np.frombuffer(raw, comp, n, off + k * stride)
    return out if n > 1 else out[:, 0]


def atlas(d, bufs):
    bv = d["bufferViews"][d["images"][0]["bufferView"]]
    o = bv.get("byteOffset", 0)
    data = bufs[bv["buffer"]][o: o + bv["byteLength"]]
    return np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), np.float32) / 255.0


def node_matrix(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    s = n.get("scale", [1, 1, 1])
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = r * np.array(s)
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def quantum_colour(c, desat, tint):
    lum = (c * np.array([0.2126, 0.7152, 0.0722])).sum(axis=1, keepdims=True)
    c = c * (1 - desat) + lum * desat
    return np.clip(c * np.array(tint), 0.0, 1.0)


def read_mesh(d, bufs, tex, mesh_i, desat, tint):
    """(pos, nrm, col, idx) of glTF mesh `mesh_i` in local space; colour from the atlas."""
    P, N, C, I = [], [], [], []
    base = 0
    for prim in d["meshes"][mesh_i]["primitives"]:
        at = prim["attributes"]
        p = accessor(d, bufs, at["POSITION"]).astype(np.float64)
        n = accessor(d, bufs, at["NORMAL"]).astype(np.float64)
        uv = accessor(d, bufs, at["TEXCOORD_0"])
        h, w = tex.shape[:2]
        px = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
        py = np.clip((uv[:, 1] * h).astype(int), 0, h - 1)
        c = quantum_colour(srgb_to_lin(tex[py, px]), desat, tint)
        idx = accessor(d, bufs, prim["indices"]).astype(np.int64)
        P.append(p)
        N.append(n)
        C.append(c)
        I.append(idx + base)
        base += len(p)
    return np.concatenate(P), np.concatenate(N), np.concatenate(C), np.concatenate(I)


def transform(p, n, m):
    q = p @ m[:3, :3].T + m[:3, 3]
    nn = n @ np.linalg.inv(m[:3, :3])
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    return q, nn


def baked(src, desat, tint):
    """[(node name, local mesh (p, n, c, i), node matrix)] of a piece."""
    d, bufs = load(os.path.join(SRC, src + ".gltf"))
    tex = atlas(d, bufs)
    return [(nd["name"], read_mesh(d, bufs, tex, nd["mesh"], desat, tint), node_matrix(nd)) for nd in d["nodes"] if "mesh" in nd]


def merge(parts):
    P, N, C, I = [], [], [], []
    base = 0
    for p, n, c, i in parts:
        P.append(p)
        N.append(n)
        C.append(c)
        I.append(i + base)
        base += len(p)
    return np.concatenate(P), np.concatenate(N), np.concatenate(C), np.concatenate(I)


def world(parts):
    out = []
    for _, (p, n, c, i), m in parts:
        q, nn = transform(p, n, m)
        out.append((q, nn, c, i))
    return out


def cluster(p, n, c, i, cap):
    """Vertex-clustering decimation to at most `cap` triangles."""
    if len(i) // 3 <= cap:
        return p, n, c, i
    lo_p = p.min(axis=0)
    size = float((p.max(axis=0) - lo_p).max())
    lo, hi = size / 600.0, size / 2.0
    best = None
    for _ in range(22):
        s = math.sqrt(lo * hi)
        q = np.floor((p - lo_p) / s).astype(np.int64)
        key = (q[:, 0] * 100003 + q[:, 1]) * 100003 + q[:, 2]
        uniq, inv = np.unique(key, return_inverse=True)
        t = inv[i].reshape(-1, 3)
        t = t[(t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])]
        tri = len(np.unique(np.sort(t, axis=1), axis=0))
        if tri > cap:
            lo = s
        else:
            hi = s
            best = (len(uniq), inv, t)
    if best is None:
        raise SystemExit("cannot reach the triangle cap")
    nu, inv, t = best
    t = np.unique(np.sort(t, axis=1), axis=0)          # winding is lost by the sort: fixed below from the original normals
    cnt = np.bincount(inv, minlength=nu).astype(np.float64)[:, None]
    np_, nn, cc = np.zeros((nu, 3)), np.zeros((nu, 3)), np.zeros((nu, 3))
    np.add.at(np_, inv, p)
    np.add.at(nn, inv, n)
    np.add.at(cc, inv, c)
    np_ /= cnt
    cc /= cnt
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    a, b, d = np_[t[:, 0]], np_[t[:, 1]], np_[t[:, 2]]
    fn = np.cross(b - a, d - a)
    flip = (fn * (nn[t[:, 0]] + nn[t[:, 1]] + nn[t[:, 2]])).sum(axis=1) < 0
    t[flip] = t[flip][:, [0, 2, 1]]
    used = np.unique(t)
    remap = -np.ones(nu, np.int64)
    remap[used] = np.arange(len(used))
    return np_[used], nn[used], cc[used], remap[t].reshape(-1)


def rot_y_pi(p, n):
    f = np.array([-1.0, 1.0, -1.0])
    return p * f, n * f


class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accs, self.meshes, self.nodes, self.mats = [], [], [], [], []

    def _add(self, arr, ctype, typ, target):
        while len(self.bin) % 4:
            self.bin.append(0)
        b = arr.tobytes()
        self.views.append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(b), "target": target})
        self.bin += b
        a = {"bufferView": len(self.views) - 1, "componentType": ctype, "count": len(arr), "type": typ}
        if typ == "VEC3":
            a["min"] = arr.min(axis=0).tolist()
            a["max"] = arr.max(axis=0).tolist()
        self.accs.append(a)
        return len(self.accs) - 1

    def material(self, name, rough, metal):
        for k, m in enumerate(self.mats):
            if m["name"] == name:
                return k
        self.mats.append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": metal, "roughnessFactor": rough}})
        return len(self.mats) - 1

    def add(self, name, p, n, c, idx, mat, translation=None):
        col = np.concatenate([c, np.ones((len(c), 1))], axis=1).astype(np.float32)
        at = {"POSITION": self._add(p.astype(np.float32), 5126, "VEC3", 34962), "NORMAL": self._add(n.astype(np.float32), 5126, "VEC3", 34962),
              "COLOR_0": self._add(col, 5126, "VEC4", 34962)}
        ix = self._add(idx.astype(np.uint32), 5125, "SCALAR", 34963)
        self.meshes.append({"name": name, "primitives": [{"attributes": at, "indices": ix, "material": mat}]})
        node = {"name": name, "mesh": len(self.meshes) - 1}
        if translation is not None:
            node["translation"] = [float(x) for x in translation]
        self.nodes.append(node)

    def write(self, path, root_name):
        nodes = self.nodes                  # several scene roots: Godot adds one root named after the file, the pieces sit directly under it
        doc = {"asset": {"version": "2.0", "generator": "tools/creature_kit.py"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": self.meshes,
               "materials": self.mats, "accessors": self.accs, "bufferViews": self.views, "buffers": [{"byteLength": len(self.bin) + (-len(self.bin) % 4)}]}
        js = json.dumps(doc, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        b = bytes(self.bin) + b"\0" * (-len(self.bin) % 4)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b)))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(b), 0x004E4942) + b)


def fit_height(p, height):
    lo, hi = p.min(axis=0), p.max(axis=0)
    c = (lo + hi) / 2
    return (p - np.array([c[0], lo[1], c[2]])) * (height / (hi[1] - lo[1]))


def build_flora():
    g = Glb()
    mat = g.material("Flora", 0.8, 0.0)
    for name, (src, cap, height) in FLORA.items():
        p, n, c, i = merge(world(baked(src, 0.45, (0.82, 1.0, 0.95))))
        p = fit_height(p, height)
        p, n, c, i = cluster(p, n, c, i, cap)
        p = p - np.array([0.0, p[:, 1].min(), 0.0])               # the clustering lifts the feet: back to y = 0
        g.add(name, p, n, c, i, mat)
    g.write(os.path.join(OUT, "kit_flora.glb"), "KitFlora")


def build_pickup():
    p, n, c, i = merge(world(baked("Items/Pickup_Bullets", 0.35, (0.9, 1.0, 1.0))))
    p = fit_height(p, 0.62)
    p, n, c, i = cluster(p, n, c, i, 300)
    g = Glb()
    g.add("Pickup", p, n, c, i, g.material("Pickup", 0.5, 0.2))
    g.write(os.path.join(OUT, "pickup_weapon.glb"), "PickupWeapon")


def build_rover(out_name, src, height, body_cap, wheel_cap):
    parts = baked(src, 0.3, (0.85, 1.0, 1.0))
    body = [x for x in parts if not x[0].startswith("Wheel")]
    wheels = [x for x in parts if x[0].startswith("Wheel")]
    bp, bn, bc, bi = merge(world(body))
    ground = min(min(m[1, 3] + mesh[0][:, 1].min() for _, mesh, m in wheels), bp[:, 1].min())
    k = height / (bp.max(axis=0)[1] - ground)
    shift = np.array([(bp.max(axis=0)[0] + bp.min(axis=0)[0]) / 2, ground, (bp.max(axis=0)[2] + bp.min(axis=0)[2]) / 2])
    bp, bn = rot_y_pi((bp - shift) * k, bn)
    bp, bn, bc, bi = cluster(bp, bn, bc, bi, body_cap)
    g = Glb()
    g.add("Body", bp, bn, bc, bi, g.material("Body", 0.5, 0.2))
    for _, (p, n, c, i), m in wheels:
        t = (m[:3, 3] - shift) * k * np.array([-1.0, 1.0, -1.0])
        p, n = rot_y_pi(p * k, n)
        p, n, c, i = cluster(p, n, c, i, wheel_cap)
        g.add(("WheelF" if t[2] < 0 else "WheelR") + ("L" if t[0] < 0 else "R"), p, n, c, i, g.material("Wheel", 0.7, 0.0), translation=t)
    g.write(os.path.join(OUT, out_name + ".glb"), out_name)


def build_skiff(out_name, src, length, cap):
    p, n, c, i = merge(world(baked(src, 0.3, (0.85, 1.0, 1.0))))
    lo, hi = p.min(axis=0), p.max(axis=0)
    k = length / (hi[0] - lo[0])                                     # the ship's long axis is X in the source: turned to Z
    p = (p - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])) * k
    p, n = p[:, [2, 1, 0]] * np.array([-1.0, 1.0, 1.0]), n[:, [2, 1, 0]] * np.array([-1.0, 1.0, 1.0])     # (x, y, z) -> (-z, y, x): a +90 degree turn, keeps the winding
    p, n, c, i = cluster(p, n, c, i, cap)
    g = Glb()
    g.add("Body", p, n, c, i, g.material("Body", 0.45, 0.25))
    g.write(os.path.join(OUT, out_name + ".glb"), out_name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    build_flora()
    build_pickup()
    build_rover("car_rover", "Vehicles/Rover_1", 2.3, 1500, 140)
    build_skiff("car_skiff", "Vehicles/Spaceship_FinnTheFrog", 5.2, 1400)
    print("ok")
