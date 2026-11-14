#!/usr/bin/env python
"""The parametric Blender weapon kit (wave 114): builds a distinct detailed model for EVERY weapon id of the game from the spec table (weapon_specs.py) with the parts library (wparts.py, wguns.py,
wexotic.py, wmelee.py), bakes vertex AO and edge wear (mathutils BVH of the bpy wheel), and writes assets/models/weapons/<id>.glb (LOD0 for the hand and the pictures, LOD1 for enemies and pickups),
weapons_meta.json (grips, eject port, aim point, moving parts, triangle counts) and the Godot .import files. Run with the pinned interpreter:

    godot/.venv-tools/bin/python godot/tools/blender/weapon_kit.py [--ids a,b] [--class pistol,smg] [--sheet DIR] [--jobs 3] [--atlas] [--report]

    --atlas    also regenerate the three material atlases (weapon_mats.py)
    --sheet    write numpy preview sheets (muzzle to the right, side + three quarter) of what was built into DIR
    --report   print the triangle / byte table and the silhouette duplicate check
"""
import argparse
import hashlib
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import weaponlib as wl  # noqa: E402
import weapon_mats as M  # noqa: E402
import wparts as wp  # noqa: E402
import wguns as wg  # noqa: E402
import wexotic as we  # noqa: E402
import wmelee as wm  # noqa: E402
import weapon_specs as SP  # noqa: E402
from weaponlib import G  # noqa: E402

OUT_DIR = os.environ.get("QT_WEAPON_DIR", os.path.join(ROOT, "assets", "models", "weapons"))
RECIPES = {"long": wg.longgun, "pistol": wg.pistol, "revolver": wg.revolver, "energy": we.energy_gun, "launcher": we.launcher, "rotary": we.rotary, "flamer": we.flamer,
           "bow": we.bow, "melee": wm.melee, "device": wm.device}

IMPORT_TEMPLATE = """[remap]

importer="scene"
type="PackedScene"

[deps]

source_file="res://assets/models/weapons/%(id)s.glb"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/force_disable_compression=false
skins/use_named_skins=false
animation/import=false
materials/extract=0
"""

ARRAY_IMPORT = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://assets/models/weapons/weapon_atlas_%(t)s.png"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=4
slices/vertical=8
"""


def hex_linear(h):
    return wp.lin(h)


def seed_of(id_):
    return int(hashlib.md5(id_.encode()).hexdigest()[:6], 16)


def to_godot(p):
    return [round(float(p[0]), 5), round(float(p[2]), 5), round(float(-p[1]), 5)]


def build_one(id_, lod):
    spec = SP.S[id_]
    row = SP.BY_ID[id_]
    poly = spec.get("poly")
    if poly is None and spec["fac"] in ("ceramic", "quantum"):          # the energy shells come in several finishes: graphite, navy, pearl, teal, violet ...
        poly = ["slate", "navy", "white", "teal", "violet", "grey", "bone", "black"][seed_of(id_) % 8]
    pal = wp.palette(spec["fac"], glow=hex_linear(row["look"]), accent=spec.get("accent"), poly=poly, wood=spec.get("wood", "dark"))
    g = G(lod=lod, seed=seed_of(id_))
    p = {k: v for k, v in spec.items() if k not in ("fn", "fac", "hold", "accent", "poly", "wood")}
    out = RECIPES[spec["fn"]](g, pal, p)
    tier = int(row.get("tier", 3) or 3)
    wear = spec.get("wear", {1: 0.8, 2: 0.7, 3: 0.55, 4: 0.45, 5: 0.3, 6: 0.2}.get(tier, 0.55))
    m = g.finish(ao_rays=14 if lod == 0 else 8, wear=wear)
    return g, out, m, spec


def build_weapon(id_, outdir=OUT_DIR, write=True):
    t0 = time.time()
    g0, out0, m0, spec = build_one(id_, 0)
    g1, out1, m1, _ = build_one(id_, 1)
    ymax = float(m0["P"][:, 1].max())                  # the origin of the mesh frame is the FRONT of the weapon (the tip of the muzzle device / blade / head)
    for m in (m0, m1):
        m["P"] = m["P"] - np.array([0.0, ymax, 0.0])
        m["color"] = m["tint"]
    markers = {k: (v[0], v[1] - ymax, v[2]) for k, v in g0.markers.items()}
    markers["muzzle"] = (0.0, 0.0, 0.0)
    if write:
        os.makedirs(outdir, exist_ok=True)
        path = os.path.join(outdir, id_ + ".glb")
        gm = {}
        names = {"gr": "grip_r", "gl": "grip_l"}
        for k, v in markers.items():
            gm[names.get(k, k)] = v
        size = wl.write_glb(path, [("L0", m0), ("L1", m1)], gm, extras={"id": id_})
        imp = path + ".import"
        if not os.path.exists(imp):
            open(imp, "w").write(IMPORT_TEMPLATE % {"id": id_})
    else:
        size = 0
    parts = sorted(set(int(x) for x in m0["part"] if x != 0))
    gr = to_godot(markers["gr"])
    gl = to_godot(markers["gl"])
    hold = SP.HOLD.get(spec["hold"], 0.18)
    P = m0["P"]
    gp = np.stack([P[:, 0], P[:, 2], -P[:, 1]], axis=1)
    length = float(gp[:, 2].max())
    reach = gr[2] + hold
    back = {"rifle": 0.08, "sniper": 0.08, "shotgun": 0.08, "lmg": 0.1, "smg": 0.08, "energy": 0.08, "launcher": 0.14, "flamer": 0.1}.get(spec["hold"])
    if back is not None:                                      # a shoulder weapon: its butt rests at the pivot (the shoulder), however long the stock is
        reach = max(reach, length - back)
    meta = {"gr": gr, "gl": gl, "reach": round(reach, 4), "eject": to_godot(markers["eject"]), "aim": to_godot(markers["aim"]), "mag": to_godot(markers["mag"]),
            "optic": to_godot(markers["optic"]), "laser": to_godot(markers["laser"]),
            "parts": [wl.PART_NAMES[i] for i in parts], "tris0": int(len(m0["F"])), "tris1": int(len(m1["F"])), "verts0": int(len(m0["P"])), "verts1": int(len(m1["P"])),
            "aabb": [[round(float(c), 4) for c in gp.min(axis=0)], [round(float(c), 4) for c in gp.max(axis=0)]], "bytes": int(size), "fn": spec["fn"], "fac": spec["fac"], "rec": spec.get("rec", ""), "kind": spec.get("kind", "")}
    if "rotor" in markers:
        meta["rotor"] = to_godot(markers["rotor"])
    if "hinge" in markers:
        meta["hinge"] = to_godot(markers["hinge"])
    return id_, meta, m0, time.time() - t0


def _job(args):
    id_, outdir = args
    try:
        i, meta, m0, dt = build_weapon(id_, outdir)
        return id_, meta, dt, None, m0
    except Exception as e:  # noqa: BLE001
        import traceback
        return id_, None, 0.0, traceback.format_exc(), None


def silhouette(m, w=120, h=40):
    """Side-view occupancy mask of a mesh (muzzle to the right), for the duplicate check."""
    from PIL import Image, ImageDraw
    P, F = m["P"], m["F"]
    y, z = P[:, 1], P[:, 2]
    x0, x1, z0, z1 = -1.6, 0.0, -0.4, 0.4
    sx = (y - x0) / (x1 - x0) * (w - 1)
    sy = (1.0 - (z - z0) / (z1 - z0)) * (h - 1)
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    for t in F:
        d.polygon([(sx[t[0]], sy[t[0]]), (sx[t[1]], sy[t[1]]), (sx[t[2]], sy[t[2]])], fill=255)
    return np.asarray(im) > 127


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="")
    ap.add_argument("--class", dest="cls", default="")
    ap.add_argument("--family", default="")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--atlas", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--no-write", action="store_true")
    a = ap.parse_args()
    ids = [r["id"] for r in SP.INDEX]
    if a.ids:
        ids = [i for i in a.ids.split(",") if i]
    if a.cls:
        cl = set(a.cls.split(","))
        ids = [i for i in ids if SP.BY_ID[i]["class"] in cl]
    if a.family:
        fl = set(a.family.split(","))
        ids = [i for i in ids if SP.BY_ID[i]["family"] in fl]
    os.makedirs(a.out, exist_ok=True)
    if a.atlas:
        for p in M.build_atlas(a.out):
            print("atlas", os.path.basename(p), os.path.getsize(p) // 1024, "KB")
        for t in ("alb", "orm", "nrm"):
            imp = os.path.join(a.out, "weapon_atlas_%s.png.import" % t)
            if not os.path.exists(imp):
                open(imp, "w").write(ARRAY_IMPORT % {"t": t})
    t0 = time.time()
    results = {}
    meshes = {}
    work = [(i, a.out) for i in ids]
    if a.jobs > 1 and len(work) > 4:
        import multiprocessing as mp
        with mp.get_context("fork").Pool(a.jobs) as pool:
            for k, (id_, meta, dt, err, m0) in enumerate(pool.imap_unordered(_job, work)):
                if err:
                    print("FAILED", id_, "\n", err)
                    continue
                results[id_] = meta
                meshes[id_] = m0
                print("%3d/%d %-14s %-8s tris %5d / %4d  verts %5d  %6.1f KB  %.1fs" % (k + 1, len(work), id_, meta["fn"], meta["tris0"], meta["tris1"], meta["verts0"], meta["bytes"] / 1024.0, dt), flush=True)
    else:
        for k, w in enumerate(work):
            id_, meta, dt, err, m0 = _job(w)
            if err:
                print("FAILED", id_, "\n", err)
                continue
            results[id_] = meta
            meshes[id_] = m0
            print("%3d/%d %-14s %-8s tris %5d / %4d  verts %5d  %6.1f KB  %.1fs" % (k + 1, len(work), id_, meta["fn"], meta["tris0"], meta["tris1"], meta["verts0"], meta["bytes"] / 1024.0, dt), flush=True)
    meta_path = os.path.join(a.out, "weapons_meta.json")
    allmeta = {}
    if os.path.exists(meta_path):
        allmeta = json.load(open(meta_path))
    allmeta.update(results)
    if not a.no_write:
        json.dump({k: allmeta[k] for k in sorted(allmeta)}, open(meta_path, "w"), separators=(",", ":"))
    print("built %d weapons in %.0f s; meta entries %d" % (len(results), time.time() - t0, len(allmeta)))
    if a.report:
        report(allmeta, meshes)
    if a.sheet:
        os.makedirs(a.sheet, exist_ok=True)
        import weapon_preview as pv
        order = [i for i in ids if i in meshes]
        per = 12
        for b in range(0, len(order), per):
            chunk = order[b:b + per]
            items = [(i + "  " + SP.BY_ID[i]["name"], meshes[i]) for i in chunk]
            pv.sheet(items, os.path.join(a.sheet, "sheet_%02d.png" % (b // per)), views=("side", "q34"), cell=(420, 170), cols=2)
        print("sheets in", a.sheet)


def report(allmeta, meshes):
    tot0 = tot1 = byt = 0
    rows = []
    for k, m in sorted(allmeta.items()):
        tot0 += m["tris0"]
        tot1 += m["tris1"]
        byt += m["bytes"]
        rows.append((m["tris0"], k))
    n = len(allmeta)
    print("weapons %d  LOD0 tris avg %.0f max %d  LOD1 avg %.0f max %d  glb total %.2f MB" % (n, tot0 / n, max(m["tris0"] for m in allmeta.values()), tot1 / n,
                                                                                           max(m["tris1"] for m in allmeta.values()), byt / 1048576.0))
    # silhouette duplicates inside a class
    sil = {k: silhouette(m) for k, m in meshes.items()}
    keys = sorted(sil)
    worst = []
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if SP.BY_ID[a]["family"] != SP.BY_ID[b]["family"]:
                continue
            A, B = sil[a], sil[b]
            iou = float((A & B).sum()) / max(1.0, float((A | B).sum()))
            if iou > 0.9:
                worst.append((iou, a, b))
    worst.sort(reverse=True)
    print("silhouette pairs of one family with IoU > 0.90: %d" % len(worst))
    for iou, a, b in worst[:20]:
        print("  %.3f  %s  %s" % (iou, a, b))


if __name__ == "__main__":
    main()
