#!/usr/bin/env python3
"""Bakes the SUIT MASK of the hero (wave 112): the painted layout of the bodysuit in the UV space of the Quaternius base body, written into the roughness slot of the skin material.

  assets_incoming/characters/hero/hero_<body>_rough.png   RGBA 1024:  R = the skin roughness of the kit (unchanged, the NPC shader path reads only R)
                                                                      G = panel A (the lighter quilted side panels: torso sides, outer legs, back of the arms, upper back)
                                                                      B = accent paint (thin stripes at the panel edges and down the spine: the scheme colour)
                                                                      A = seams (dark grooves: waist, hips, knees, elbows, wrists, ankles, panel borders)
The layout is defined as functions of the bind-pose position and normal (the same predicates for the male and the female body), evaluated per texel by rasterising the body's triangles
into UV space, so every line is registered to the mesh. Run after tools/hero/prep_hero_assets.py (which writes the plain roughness map):
  .venv-tools/bin/python tools/hero/bake_suit_mask.py [male|female] [--debug out.png]
Needs numpy and pillow (tools/requirements.txt)."""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = os.path.join(ROOT, "assets_incoming", "characters", "hero")
SRC = os.path.join(ROOT, "..", "art_sources", "quaternius_universal_base_characters")
SIZE = 1024


def accessor(d, binf, i):
    a = d["accessors"][i]
    bv = d["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    comp = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(binf, dtype=np.dtype(comp).newbyteorder("<"), count=a["count"] * n, offset=off).reshape(a["count"], n)


def load_body(gender):
    path = os.path.join(KIT, "Superhero_%s_FullBody.gltf" % gender.capitalize())
    d = json.load(open(path))
    binf = open(path.replace(".gltf", ".bin"), "rb").read()
    best = None
    for m in d["meshes"]:
        n = len(accessor(d, binf, m["primitives"][0]["attributes"]["POSITION"]))
        if best is None or n > best[0]:
            best = (n, m)
    prim = best[1]["primitives"][0]
    pos = accessor(d, binf, prim["attributes"]["POSITION"]).astype(np.float64)
    uv = accessor(d, binf, prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = accessor(d, binf, prim["indices"]).reshape(-1, 3).astype(np.int64)
    nrm = np.zeros_like(pos)
    fn = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
    for k in range(3):
        np.add.at(nrm, idx[:, k], fn)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    return pos, nrm, uv, idx


def rasterise(pos, nrm, uv, idx, size=SIZE):
    """Per texel: the interpolated bind-pose position and normal of the triangle that covers it (valid flag)."""
    P = np.zeros((size, size, 3))
    N = np.zeros((size, size, 3))
    valid = np.zeros((size, size), bool)
    for t in idx:
        uvs = uv[t] * size
        x0, y0 = np.floor(uvs.min(axis=0)).astype(int)
        x1, y1 = np.ceil(uvs.max(axis=0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = uvs
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        w2 = 1.0 - w0 - w1
        eps = -0.02
        inside = (w0 >= eps) & (w1 >= eps) & (w2 >= eps)
        if not inside.any():
            continue
        px = w0[..., None] * pos[t[0]] + w1[..., None] * pos[t[1]] + w2[..., None] * pos[t[2]]
        nx = w0[..., None] * nrm[t[0]] + w1[..., None] * nrm[t[1]] + w2[..., None] * nrm[t[2]]
        yy, xx = np.nonzero(inside)
        P[y0 + yy, x0 + xx] = px[yy, xx]
        N[y0 + yy, x0 + xx] = nx[yy, xx]
        valid[y0 + yy, x0 + xx] = True
    return P, N, valid


def sm(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def band(x, c, w, soft=0.0015):
    """1 inside |x - c| < w, with a soft edge."""
    return 1.0 - sm(w - soft, w + soft, np.abs(x - c))


def layout(P, N):
    """The suit layout as masks (panel A, accent, seams) from bind-pose position and normal (kit space: +x = the character's left, +z = front, y up)."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    ax = np.abs(x)
    nx, ny, nz = N[..., 0], N[..., 1], N[..., 2]
    torso = (ax < 0.26) & (y > 0.93) & (y < 1.47)
    leg = (y > 0.10) & (y < 0.97) & (ax < 0.21) & (ax > 0.015)
    arm = (ax > 0.215) & (y > 1.33) & (y < 1.62)
    lat_leg = np.where(x >= 0.0, x - 0.114, -x - 0.114)               # + toward the outside of the leg
    lat_leg = np.abs(x) - 0.114
    # ---- panel A
    side_torso = torso * sm(0.40, 0.62, np.abs(nx)) * sm(0.93, 0.99, y) * (1.0 - sm(1.30, 1.36, y))
    outer_leg = leg * sm(0.030, 0.052, lat_leg) * sm(0.14, 0.2, y)
    arm_back = arm * sm(0.15, 0.5, ny + 0.0 * nz) * (1.0 - sm(0.55, 0.9, ny))
    upper_back = (torso & (y > 1.20)) * sm(-0.050, -0.085, z) * (1.0 - sm(1.44, 1.48, y))
    panel_a = np.clip(side_torso + outer_leg + arm_back + upper_back, 0.0, 1.0)
    # ---- accent paint: piping at the panel edges, a spine line, a stripe along the arm
    edge_leg = leg * band(lat_leg, 0.041, 0.0042) * sm(0.14, 0.2, y)
    edge_torso = torso * band(np.abs(nx), 0.5, 0.045, 0.01) * sm(0.95, 1.0, y) * (1.0 - sm(1.28, 1.32, y))
    spine = (torso & (y > 0.99)) * band(ax, 0.0, 0.0085) * sm(-0.045, -0.075, z)
    arm_line = arm * band(nz, 0.0, 0.09, 0.02) * sm(0.55, 0.8, ny)
    accent = np.clip(edge_leg + edge_torso + spine + arm_line, 0.0, 1.0)
    # ---- seams: dark grooves across the limbs at the joints, and along the panel borders
    waist = band(y, 0.952, 0.0035) * (ax < 0.25)
    hip = band(y, 0.905, 0.003) * (ax < 0.22)
    knee_b = band(y, 0.545, 0.0035) * leg
    ankle = band(y, 0.215, 0.0035) * leg
    elbow = band(ax, 0.463, 0.0035) * arm
    cuff = band(ax, 0.655, 0.0035) * arm
    shoulder = band(ax, 0.268, 0.0035) * arm
    seams = np.clip(waist + hip + knee_b + ankle + elbow + cuff + shoulder + 0.8 * np.clip(side_torso * (1.0 - side_torso) * 4.0, 0, 1) + 0.8 * np.clip(outer_leg * (1.0 - outer_leg) * 4.0, 0, 1), 0.0, 1.0)
    return panel_a, accent, seams


def dilate(img, valid, iters=6):
    """Spreads the written texels into the empty margin so bilinear filtering and the mip chain never pick up black."""
    img = img.copy()
    v = valid.copy()
    for _ in range(iters):
        acc = np.zeros_like(img)
        cnt = np.zeros(v.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                sv = np.roll(np.roll(v, dy, axis=0), dx, axis=1)
                si = np.roll(np.roll(img, dy, axis=0), dx, axis=1)
                acc += si * sv[..., None]
                cnt += sv
        fill = (~v) & (cnt > 0)
        img[fill] = acc[fill] / cnt[fill][..., None]
        v = v | fill
    return img


def bake(gender, debug=None):
    pos, nrm, uv, idx = load_body(gender)
    P, N, valid = rasterise(pos, nrm, uv, idx)
    pa, ac, se = layout(P, N)
    src = Image.open(os.path.join(SRC, "T_Superhero_%s_Roughness.png" % gender.capitalize())).convert("RGB").split()[1]
    rough = np.array(src.resize((SIZE, SIZE), Image.LANCZOS), np.float64) / 255.0
    out = np.stack([rough, pa, ac, se], axis=-1)
    out[~valid] = np.stack([rough, np.zeros_like(rough), np.zeros_like(rough), np.zeros_like(rough)], axis=-1)[~valid]
    out = dilate(out, valid)
    img = Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    dst = os.path.join(KIT, "hero_%s_rough.png" % gender)
    img.save(dst, optimize=True)
    print("suit mask %s -> %s  (panel A %.1f %%, accent %.2f %%, seams %.2f %% of the covered texels)" % (gender, os.path.relpath(dst, ROOT), 100 * pa[valid].mean(), 100 * ac[valid].mean(), 100 * se[valid].mean()))
    if debug:
        dbg = np.stack([np.clip(pa * 0.7 + ac * 1.0, 0, 1), np.clip(pa * 0.7 + se * 0.5, 0, 1), np.clip(ac + se, 0, 1)], axis=-1) * valid[..., None]
        Image.fromarray((dbg * 255).astype(np.uint8)).save(debug)


if __name__ == "__main__":
    argv = sys.argv[1:]
    dbg = None
    if "--debug" in argv:
        k = argv.index("--debug")
        dbg = argv[k + 1]
        del argv[k:k + 2]
    for g in (argv or ["male", "female"]):
        bake(g, dbg if len(argv) == 1 else None)
