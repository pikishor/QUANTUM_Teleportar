#!/usr/bin/env python3
"""Landscape trees (wave 112): build the foliage atlas, the nine tree species at three levels of detail, their cross-billboard impostors and the GLB the game loads.

  godot/.venv-tools/bin/python godot/tools/landscape/build_land_trees.py [--preview OUT.png] [--out-models DIR] [--out-tex DIR] [--only oak,pine]

Outputs (the contract of scripts/landscape/land_kit.gd):
  assets/models/land_trees.glb       nodes <species>_0 (full), <species>_0l (lite, LOW), <species>_1 (mid LOD) + meta_<species> (extras: height, crown_r, trunk_r, quad_w, quad_h, imp_cell, tris)
  assets/textures/land_foliage.webp  2048 x 1024 sprite atlas (leaves, needles, fronds, grass, ferns, flowers), alpha = coverage
  assets/textures/land_impostor.webp 1024 x 1024: two baked side views (90 degrees apart) per species in 192 x 256 cells, for the cross impostors
Everything is procedural with fixed seeds (no downloaded art in the geometry); the bark textures (Poly Haven CC0) are packed by tools/landscape/pack_bark.py.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import foliage  # noqa: E402
import impostor  # noqa: E402
import rocks  # noqa: E402
import species as sp  # noqa: E402
from mb import write_glb  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CELL_W, CELL_H = 192, 256
IMP_COLS = 5
ORDER = ["oak", "birch", "poplar", "pine", "fir", "palm", "acacia", "dead", "alien"]
BARK_RGB = {"oak": (96, 76, 52), "birch": (214, 210, 200), "poplar": (120, 108, 88), "pine": (112, 70, 48), "fir": (82, 62, 46), "palm": (150, 140, 120), "acacia": (96, 78, 58),
            "dead": (118, 108, 96), "alien": (70, 50, 100)}
TRUNK_R = {"oak": 0.42, "birch": 0.16, "poplar": 0.26, "pine": 0.30, "fir": 0.28, "palm": 0.22, "acacia": 0.28, "dead": 0.26, "alien": 0.30}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    ap.add_argument("--out-models", default=os.environ.get("QT_MODELS_DIR", os.path.join(ROOT, "assets", "models")))
    ap.add_argument("--out-tex", default=os.environ.get("QT_TEX_DIR", os.path.join(ROOT, "assets", "textures")))
    ap.add_argument("--only", default="")
    ap.add_argument("--no-write", action="store_true")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s] or ORDER
    atlas, _ = foliage.build_atlas()
    meshes = {}
    extras = {}
    imp_cells = {}
    imp_atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    previews = []
    total_tris = {}
    for si, name in enumerate(ORDER):
        if name not in only:
            continue
        built = {}
        for key in ("0", "0l", "1"):
            mb = sp.build(name, key)
            built[key] = mb
            meshes["%s_%s" % (name, key)] = mb
        full = built["0"]
        h, rad = impostor.extents(full)
        # one scale for both views so that the crown fits the cell
        scale = min((CELL_H - 6) / h, (CELL_W - 6) / (2.0 * rad * 1.02))
        quad_w, quad_h = CELL_W / scale, CELL_H / scale
        cell = si * 2
        views = []
        for vi, az in enumerate((0.0, math.pi / 2 if False else 1.5707963)):
            im = impostor.render(full, atlas, az, scale, (CELL_W, CELL_H), BARK_RGB[name])
            views.append(im)
            cx, cy = ((cell + vi) % IMP_COLS) * CELL_W, ((cell + vi) // IMP_COLS) * CELL_H
            imp_atlas.paste(im, (cx, cy))
        imp_cells[name] = cell
        tris = {k: m.tri_count() for k, m in built.items()}
        total_tris[name] = tris
        meta = {"height": round(h, 2), "crown_r": round(rad, 2), "trunk_r": TRUNK_R[name], "quad_w": round(quad_w, 3), "quad_h": round(quad_h, 3), "imp_cell": cell,
                "tris_full": tris["0"], "tris_lite": tris["0l"], "tris_mid": tris["1"]}
        extras["meta_" + name] = meta
        print("%-7s height %5.1f crown_r %4.1f  tris full %4d lite %4d mid %3d   quad %.1f x %.1f m" % (name, h, rad, tris["0"], tris["0l"], tris["1"], quad_w, quad_h))
        if a.preview:
            row = []
            for key in ("0", "0l", "1"):
                row.append(impostor.render(built[key], atlas, 0.5, scale, (CELL_W, CELL_H), BARK_RGB[name]))
            row += views
            previews.append(row)
    if not only or "rocks" in only or a.only == "":
        for shape in ("a", "b", "c", "d"):
            meshes["rock_%s_0" % shape] = rocks.build(shape, 8)
            meshes["rock_%s_1" % shape] = rocks.build(shape, 4)
            print("rock_%s  tris %d / %d" % (shape, meshes["rock_%s_0" % shape].tri_count(), meshes["rock_%s_1" % shape].tri_count()))
    if not a.no_write:
        os.makedirs(a.out_models, exist_ok=True)
        os.makedirs(a.out_tex, exist_ok=True)
        # metadata carriers: empty meshes are not allowed in glTF, so the meta nodes ride on a one-triangle mesh
        from mb import MeshBuilder
        for name in [n for n in ORDER if n in only]:
            m = MeshBuilder()
            m._v([0, 0, 0], [0, 1, 0], [0, 0], [0, 0], [1, 1, 1, 1])
            m._v([0, 0.001, 0], [0, 1, 0], [0, 0], [0, 0], [1, 1, 1, 1])
            m._v([0.001, 0, 0], [0, 1, 0], [0, 0], [0, 0], [1, 1, 1, 1])
            m.I.append((0, 1, 2))
            meshes["meta_" + name] = m
        extras["meta__atlas"] = {"w": foliage.ATLAS_W, "h": foliage.ATLAS_H, "cells": {k: list(v) for k, v in foliage.LAYOUT.items()}}
        mm = MeshBuilder()
        mm._v([0, 0, 0], [0, 1, 0], [0, 0], [0, 0], [1, 1, 1, 1])
        mm._v([0, 0.001, 0], [0, 1, 0], [0, 0], [0, 0], [1, 1, 1, 1])
        mm._v([0.001, 0, 0], [0, 1, 0], [0, 0], [0, 0], [1, 1, 1, 1])
        mm.I.append((0, 1, 2))
        meshes["meta__atlas"] = mm
        size = write_glb(os.path.join(a.out_models, "land_trees.glb"), meshes, extras)
        print("land_trees.glb %.0f KB" % (size / 1024.0))
        atlas.save(os.path.join(a.out_tex, "land_foliage.webp"), quality=90, method=6)
        imp_atlas.save(os.path.join(a.out_tex, "land_impostor.webp"), quality=90, method=6)
        print("land_foliage.webp %.0f KB, land_impostor.webp %.0f KB" % (os.path.getsize(os.path.join(a.out_tex, "land_foliage.webp")) / 1024.0, os.path.getsize(os.path.join(a.out_tex, "land_impostor.webp")) / 1024.0))
    if a.preview and previews:
        cols = len(previews[0])
        sheet = Image.new("RGBA", (cols * CELL_W, len(previews) * CELL_H), (170, 196, 226, 255))
        for ri, row in enumerate(previews):
            for ci, im in enumerate(row):
                sheet.alpha_composite(im, (ci * CELL_W, ri * CELL_H))
        sheet.convert("RGB").save(a.preview)
        print("preview", a.preview, sheet.size)


import math  # noqa: E402

if __name__ == "__main__":
    main()
