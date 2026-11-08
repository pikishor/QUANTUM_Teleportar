#!/usr/bin/env python3
"""Open-source weapons -> assets/models/ow_<weapon id>.glb (round 4). Pure Python + numpy (no Blender needed).

Sources (CC0, art_sources/open_weapons/): Quaternius "Ultimate Gun Pack" (OGA, 11 guns used) and the RPG-7 of "Low poly weapon pack" (OGA, byzmod3d).
Each OBJ (barrel along +X, Y up) becomes one mesh in the frame WeaponModels expects: the MUZZLE is the origin, the barrel points to -Z, +Y up, the body extends toward +Z,
scaled to a realistic length, the bore axis at y = 0. One material "Weapon", vertex colours = the mtl diffuse colours lifted a little (WeaponModels' shader reads COLOR),
alpha 0 (no glow: the real guns are plain steel; the glow of the quantum look stays on the procedural fallback).

Run:  python3 godot/tools/open_models/convert_weapons.py
"""
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.abspath(os.path.join(GODOT, "..", "art_sources", "open_weapons"))
OUT = os.environ.get("QT_MODELS_DIR", os.path.join(GODOT, "assets", "models"))
UG = "ultimate_gun_pack"

# weapon id: (source folder, obj name, length in metres behind the muzzle)
WEAPONS = {
    "pistol": (UG, "Pistol_1", 0.215),
    "burst": (UG, "Pistol_6", 0.30),
    "revolver": (UG, "Revolver_2", 0.27),
    "akimbo": (UG, "Pistol_3", 0.215),
    "flux": (UG, "SubmachineGun_1", 0.50),
    "carbine": (UG, "AssaultRifle_2", 0.92),
    "marksman": (UG, "SniperRifle_6", 1.0),
    "arc": (UG, "Bullpup_1", 0.80),
    "scatter": (UG, "Shotgun_1", 0.98),
    "breacher": (UG, "Shotgun_ShortStock", 0.78),
    "rail": (UG, "SniperRifle_2", 1.12),
    "rocket": ("rpg7", "rpg7_1", 0.98, "z+"),
}
RPG_COLOURS = {"Material.001": (0.07, 0.075, 0.07), "Material.002": (0.17, 0.18, 0.12), "Material.003": (0.11, 0.075, 0.05), "Material.004": (0.09, 0.09, 0.1)}


def read_mtl(path):
    out = {}
    cur = None
    if not os.path.exists(path):
        return out
    for l in open(path):
        p = l.split()
        if not p:
            continue
        if p[0] == "newmtl":
            cur = p[1]
        elif p[0] == "Kd" and cur:
            out[cur] = tuple(float(x) for x in p[1:4])
    return out


def lift(c):
    return tuple(min(1.0, 0.09 + 1.9 * x) for x in c)


def load_obj(path, mtl):
    v, vn = [], []
    faces = []                      # (list of (vi, ni), colour)
    cur = (0.3, 0.3, 0.3)
    for l in open(path):
        p = l.split()
        if not p:
            continue
        if p[0] == "v":
            v.append([float(x) for x in p[1:4]])
        elif p[0] == "vn":
            vn.append([float(x) for x in p[1:4]])
        elif p[0] == "usemtl":
            cur = mtl.get(p[1], (0.3, 0.3, 0.3))
        elif p[0] == "f":
            idx = []
            for tok in p[1:]:
                a = tok.split("/")
                vi = int(a[0]) - 1
                ni = int(a[2]) - 1 if len(a) > 2 and a[2] else -1
                idx.append((vi, ni))
            faces.append((idx, cur))
    return np.array(v, dtype=np.float64), np.array(vn, dtype=np.float64), faces


def convert(wid, folder, name, length, axis="x+"):
    d = os.path.join(SRC, folder)
    mtl = read_mtl(os.path.join(d, name + ".mtl"))
    if folder == "rpg7":
        mtl = RPG_COLOURS
    v, vn, faces = load_obj(os.path.join(d, name + ".obj"), mtl)
    # axis: the obj axis the muzzle points along ("x+" = toward +X, "z-" = toward -Z ...); the right-hand axis follows so that the turn is a proper rotation
    fa = "xyz".index(axis[0])
    fs = 1.0 if axis[1] == "+" else -1.0
    ra, rs = {(0, 1.0): (2, 1.0), (0, -1.0): (2, -1.0), (2, 1.0): (0, -1.0), (2, -1.0): (0, 1.0)}[(fa, fs)]
    f = v[:, fa] * fs
    fmax, fmin = f.max(), f.min()
    span = fmax - fmin
    near = v[f > fmax - 0.1 * span]                            # the muzzle end: barrel only
    bore_y = (near[:, 1].min() + near[:, 1].max()) / 2
    mid_r = (near[:, ra].min() + near[:, ra].max()) / 2
    s = length / span

    def tp(p):                                                 # obj -> game (x right, y up, -z forward, muzzle at the origin)
        return np.array([(p[ra] - mid_r) * rs * s, (p[1] - bore_y) * s, (fmax - p[fa] * fs) * s])

    def tn(n):
        return np.array([n[ra] * rs, n[1], -n[fa] * fs])

    pos, nor, col, idx = [], [], [], []
    for corners, c in faces:
        base = len(pos)
        pts = [tp(v[vi]) for vi, _ in corners]
        if any(ni < 0 for _, ni in corners):
            n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
            n = n / (np.linalg.norm(n) + 1e-12)
            ns = [n] * len(corners)
        else:
            ns = [tn(vn[ni]) for _, ni in corners]
        for p, n in zip(pts, ns):
            pos.append(p)
            nor.append(n)
            col.append((*lift(c), 0.0))
        for k in range(1, len(corners) - 1):
            idx += [base, base + k, base + k + 1]
    pos = np.array(pos, dtype=np.float32)
    nor = np.array(nor, dtype=np.float32)
    col = np.array(col, dtype=np.float32)
    idx = np.array(idx, dtype=np.uint32)
    # winding: the obj is counter-clockwise from outside (glTF too); a mirrored axis (z -> -x ...) is a proper rotation, so it stays
    tris = len(idx) // 3
    # check the winding against the normals once; flip when most disagree
    a, b, c = pos[idx[0::3]], pos[idx[1::3]], pos[idx[2::3]]
    fn = np.cross(b - a, c - a)
    agree = (fn * nor[idx[0::3]]).sum(1) > 0
    if agree.mean() < 0.5:
        idx = idx.reshape(-1, 3)[:, ::-1].reshape(-1)
    bin_ = b"".join(x.tobytes() for x in (pos, nor, col, idx))
    off = [0, pos.nbytes, pos.nbytes + nor.nbytes, pos.nbytes + nor.nbytes + col.nbytes]
    gltf = {
        "asset": {"version": "2.0", "generator": "convert_weapons.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "Weapon", "mesh": 0}],
        "meshes": [{"name": "Weapon", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "Weapon", "pbrMetallicRoughness": {"metallicFactor": 0.3, "roughnessFactor": 0.55}}],
        "buffers": [{"byteLength": len(bin_)}],
        "bufferViews": [{"buffer": 0, "byteOffset": off[0], "byteLength": pos.nbytes, "target": 34962},
                        {"buffer": 0, "byteOffset": off[1], "byteLength": nor.nbytes, "target": 34962},
                        {"buffer": 0, "byteOffset": off[2], "byteLength": col.nbytes, "target": 34962},
                        {"buffer": 0, "byteOffset": off[3], "byteLength": idx.nbytes, "target": 34963}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
                      {"bufferView": 1, "componentType": 5126, "count": len(nor), "type": "VEC3"},
                      {"bufferView": 2, "componentType": 5126, "count": len(col), "type": "VEC4"},
                      {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_ += b"\0" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    path = os.path.join(OUT, "ow_%s.glb" % wid)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(bin_)) + b"BIN\0" + bin_)
    print("%-9s %-20s %4d tris  %.2f m  -> %s (%d KB)  y %.3f..%.3f" % (wid, name, tris, length, os.path.basename(path), os.path.getsize(path) // 1024,
                                                                         pos[:, 1].min(), pos[:, 1].max()))


def main():
    names = sys.argv[1:] or list(WEAPONS)
    for n in names:
        convert(n, *WEAPONS[n])


if __name__ == "__main__":
    main()
