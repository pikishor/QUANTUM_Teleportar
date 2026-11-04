"""Extra city-kit pieces without Blender: reads Quaternius Downtown City MegaKit glTF (CC0) and writes lean flat-colour glb files, assets/models/kit_city_<name>.glb.

Same conventions as tools/blender/model_kit_city.py (vertex colour per material because the partial kit ships no textures, centred on x / z, feet at y = 0, non-indexed
triangles with flat normals), but only for low-poly pieces that need no decimation. Run: python3 tools/city_kit_extra.py (needs numpy).
"""
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "art_sources", "quaternius_downtown_city_megakit"))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "models"))
DIRS = ["buildings_decals", "streets_roofs_props"]

# name -> (source gltf, max triangles)
PIECES = {
    "column": ("Metal_Column_Center.gltf", 24),
    "column_small": ("Metal_Column_Small_Center.gltf", 24),
    "stoop": ("Stairs_Entrance_Concrete.gltf", 140),
    "stoop_flat": ("Entrance_Concrete_2x1.gltf", 24),
    "rail": ("Stairs_Rails_Metal_Straight_1.gltf", 180),
    "slate_cap": ("Roof_SlateCornice_Center.gltf", 40),
    "slate_roof": ("Roof_Slate_Center.gltf", 12),
    "trim_brick": ("Brick_TopTrim.gltf", 24),
    "trim_half": ("Brick_HalfTrim.gltf", 30),
    "shopwall": ("Metal_FirstFloor_Wall.gltf", 40),
}
COLOURS = {"RedBrick": (0.20, 0.07, 0.05), "Trim_Dark": (0.07, 0.075, 0.08), "Trim_Green": (0.06, 0.16, 0.12), "Trim": (0.30, 0.29, 0.27),
           "MetalConcrete": (0.22, 0.22, 0.23), "Slate": (0.09, 0.10, 0.13), "Concrete": (0.26, 0.26, 0.25), "Asphalt": (0.06, 0.06, 0.065),
           "InteriorWall": (0.20, 0.19, 0.17), "Glass": (0.02, 0.05, 0.07)}


def find(f):
    for d in DIRS:
        p = os.path.join(ROOT, d, f)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f)


def colour(name):
    for k in ("Trim_Dark", "Trim_Green", "MetalConcrete", "RedBrick", "InteriorWall", "Slate", "Concrete", "Asphalt", "Glass", "Trim"):
        if k in name:
            return COLOURS[k]
    return (0.3, 0.3, 0.3)


def load(path):
    j = json.load(open(path))
    buf = open(os.path.join(os.path.dirname(path), j["buffers"][0]["uri"]), "rb").read()

    def acc(i):
        a = j["accessors"][i]
        bv = j["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a["componentType"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(buf, dtype=dt, count=a["count"] * n, offset=off).reshape(-1, n) if n > 1 else np.frombuffer(buf, dtype=dt, count=a["count"], offset=off)

    tris, cols = [], []
    for m in j["meshes"]:
        for p in m["primitives"]:
            pos = acc(p["attributes"]["POSITION"]).astype(np.float64)
            idx = acc(p["indices"]).astype(np.int64)
            c = colour(j["materials"][p.get("material", 0)]["name"])
            if "Glass" in j["materials"][p.get("material", 0)]["name"] or "FakeInterior" in j["materials"][p.get("material", 0)]["name"]:
                c = COLOURS["Glass"]
            t = pos[idx].reshape(-1, 3, 3)
            tris.append(t)
            cols += [c] * len(t)
    return np.concatenate(tris), np.array(cols, dtype=np.float32)


def write_glb(path, tris, cols):
    n = len(tris) * 3
    v = tris.reshape(-1, 3).astype(np.float32)
    e1, e2 = tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    nm = np.cross(e1, e2)
    ln = np.linalg.norm(nm, axis=1, keepdims=True)
    nm = np.where(ln > 1e-12, nm / np.maximum(ln, 1e-12), np.array([0, 1, 0]))
    nn = np.repeat(nm, 3, axis=0).astype(np.float32)
    cc = np.repeat(np.concatenate([cols, np.ones((len(cols), 1), np.float32)], axis=1), 3, axis=0).astype(np.float32)
    uv = np.zeros((n, 2), np.float32)
    uv[:, 1] = v[:, 1] / max(float(v[:, 1].max()), 0.001)
    parts = [v.tobytes(), nn.tobytes(), cc.tobytes(), uv.tobytes()]
    offs, o = [], 0
    for p in parts:
        offs.append(o)
        o += len(p)
    binb = b"".join(parts)
    vmin, vmax = v.min(axis=0).tolist(), v.max(axis=0).tolist()
    g = {"asset": {"version": "2.0", "generator": "city_kit_extra.py"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": os.path.basename(path)[:-4]}],
         "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2, "TEXCOORD_0": 3}, "material": 0}]}],
         "materials": [{"name": "KitCity", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.6}}],
         "accessors": [{"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": vmin, "max": vmax},
                       {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
                       {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC4"},
                       {"bufferView": 3, "componentType": 5126, "count": n, "type": "VEC2"}],
         "bufferViews": [{"buffer": 0, "byteOffset": offs[i], "byteLength": len(parts[i]), "target": 34962} for i in range(4)], "buffers": [{"byteLength": len(binb)}]}
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binb += b"\0" * (-len(binb) % 4)
    total = 12 + 8 + len(js) + 8 + len(binb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)


def main():
    for name, (src, cap) in PIECES.items():
        tris, cols = load(find(src))
        keep = np.abs(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])).sum(axis=1) > 1e-9
        tris, cols = tris[keep], cols[keep]
        if len(tris) > cap:
            print("SKIP %s: %d tris > cap %d" % (name, len(tris), cap))
            continue
        mn, mx = tris.reshape(-1, 3).min(axis=0), tris.reshape(-1, 3).max(axis=0)
        tris = tris - np.array([(mn[0] + mx[0]) * 0.5, mn[1], (mn[2] + mx[2]) * 0.5])
        write_glb(os.path.join(OUT, "kit_city_%s.glb" % name), tris, cols)
        print("MODEL kit_city_%s tris=%d size=%.2f x %.2f x %.2f" % (name, len(tris), *(mx - mn)))


if __name__ == "__main__":
    main()
