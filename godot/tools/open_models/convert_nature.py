#!/usr/bin/env python3
"""Quaternius Stylized Nature MegaKit (Standard, CC0) -> the outskirts' vegetation kit (wave 105, mountain sites and vegetation).

Source: https://opengameart.org/content/stylized-nature-megakit (CC0 1.0, Quaternius; licence + SOURCE.md in art_sources/quaternius_stylized_nature_megakit,
the 104 MB archive is NOT committed).  Usage from godot/ with the tool venv (bpy 5.2):
    .venv-tools/bin/python tools/open_models/convert_nature.py <dir with the unzipped glTF/ and Textures/ folders>
Output (the contract of scripts/terrain/veg_kit.gd):
    assets/models/nature_kit.glb      one node per piece, one mesh each, ONE material: POSITION, NORMAL, COLOR_0, TEXCOORD_0, indices. y up, ground at y = 0, trunk on the axis.
                                      COLOR_0.a = 0: solid (bark, rock): rgb = the colour sampled from the source texture, normal as written
                                      COLOR_0.a = 1: foliage card: rgb = a grey ambient-occlusion ramp (dark inside the crown), UV0 = the tile of the atlas (alpha test)
    assets/textures/nature_atlas.webp 1024 x 512, 4 x 2 tiles of 256: pine fan, broadleaf cluster, bush, fern, grass blade (alpha masks, white), 5 = opaque white, lossy WebP

Size reduction: the trunks go through Blender's collapse decimator (about 70 triangles left), the foliage keeps a fraction of its cards (every card is a separate island; the kept ones
are scaled up so the crown keeps its volume), rocks are used as they are.  Everything is flat colours except the foliage atlas: no bark or rock texture is shipped.
"""
import json
import os
import struct
import sys

import bpy
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_MODELS = os.environ.get("QT_MODELS_DIR", os.path.join(GODOT, "assets", "models"))
OUT_TEX = os.environ.get("QT_TEX_DIR", os.path.join(GODOT, "assets", "textures"))

TILE = 256
# atlas tile index -> (source texture, crop box in 0..1 gltf uv space or None for the whole image)
TILES = {
    0: ("Leaf_Pine.png", None),
    1: ("Leaves_NormalTree.png", None),
    2: ("Leaves_TwistedTree.png", None),
    3: ("Leaves.png", (0.0, 0.0, 0.30, 0.58)),            # the fern leaf island of the plant sheet
    4: ("Grass.png", (0.17, 0.0, 0.22, 1.0)),             # one tall blade
}
LEAF_TILE = {"Leaves_Pine": 0, "Leaves_NormalTree": 1, "Leaves_TwistedTree": 2, "Leaves": 3, "Grass": 4}
BARK = {"Bark_NormalTree": (0.105, 0.072, 0.045), "Bark_DeadTree": (0.13, 0.11, 0.09), "Bark_TwistedTree": (0.12, 0.085, 0.06)}      # linear
ROCK_TEX = {"Rocks": "Rocks_Diffuse.png", "PathRocks": "PathRocks_Diffuse.png"}

# piece name -> (source, trunk triangles to keep, fraction of the foliage cards to keep, foliage card scale boost applied automatically)
PIECES = {
    "pine_a": ("Pine_5", 70, 0.42),
    "pine_b": ("Pine_4", 80, 0.38),
    "pine_c": ("Pine_2", 90, 0.5),
    "broad_a": ("CommonTree_3", 90, 0.34),
    "broad_b": ("CommonTree_5", 80, 0.4),
    "broad_c": ("CommonTree_4", 90, 0.55),
    "dead_a": ("DeadTree_3", 260, 1.0),
    "dead_b": ("DeadTree_5", 240, 1.0),
    "bush": ("Bush_Common", 0, 0.22),
    "fern": ("Fern_1", 0, 0.5),
    "grass": ("Grass_Common_Tall", 0, 0.4),
    "tuft": ("Grass_Wispy_Short", 0, 0.3),
    "rock_a": ("Rock_Medium_1", 0, 1.0),
    "rock_b": ("Rock_Medium_2", 0, 1.0),
    "rock_c": ("Rock_Medium_3", 0, 1.0),
    "pebble": ("Pebble_Round_2", 0, 1.0),
}


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def load_tex(path):
    im = Image.open(path).convert("RGB")
    im.thumbnail((256, 256))
    return np.asarray(im, dtype=np.float32) / 255.0


def import_piece(src_dir, name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src_dir, "glTF", name + ".gltf"))
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def split_material(ob, want):
    """A new object with only the faces whose material name satisfies `want`."""
    me = ob.data
    keep = [p.index for p in me.polygons if me.materials[p.material_index] is not None and want(me.materials[p.material_index].name)]
    if not keep:
        return None
    dup = ob.copy()
    dup.data = me.copy()
    bpy.context.collection.objects.link(dup)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(dup.data)
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if f.index not in set(keep)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(dup.data)
    bm.free()
    return dup


def decimate(ob, tris):
    if ob is None:
        return None
    n = len(ob.data.polygons)
    if n <= tris:
        return ob
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)           # the source splits every uv seam: weld them or the collapse stops early
    bm.to_mesh(ob.data)
    bm.free()
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(0.02, tris / n)
    mod.use_collapse_triangulate = True
    deps = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(deps)
    me = bpy.data.meshes.new_from_object(ev)
    out = bpy.data.objects.new(ob.name + "_d", me)
    bpy.context.collection.objects.link(out)
    return out


def extract(ob):
    """(pos[n,3] godot y-up, normal[n,3], uv[n,2] gltf-space, material name per tri) per face corner (non-indexed)."""
    me = ob.data
    me.calc_loop_triangles()
    uvl = me.uv_layers.active
    pos, nrm, uv, mat = [], [], [], []
    try:
        cn = me.corner_normals
    except AttributeError:
        cn = None
    for tri in me.loop_triangles:
        for li, vi in zip(tri.loops, tri.vertices):
            co = me.vertices[vi].co
            pos.append((co.x, co.z, -co.y))
            n = cn[li].vector if cn is not None else me.vertices[vi].normal
            nrm.append((n.x, n.z, -n.y))
            u = uvl.data[li].uv if uvl else (0.0, 0.0)
            uv.append((u[0], 1.0 - u[1]))
        m = me.materials[tri.material_index] if tri.material_index < len(me.materials) and me.materials[tri.material_index] else None
        mat.append(m.name if m else "")
    return np.array(pos, np.float32), np.array(nrm, np.float32), np.array(uv, np.float32), mat


def components(pos):
    """Connected island index per triangle of a non-indexed triangle soup (vertices equal when their positions are)."""
    tri = len(pos) // 3
    key = {}
    parent = list(range(tri))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for t in range(tri):
        for k in range(3):
            p = tuple(np.round(pos[t * 3 + k], 4))
            if p in key:
                ra, rb = find(t), find(key[p])
                if ra != rb:
                    parent[ra] = rb
            else:
                key[p] = t
    return np.array([find(t) for t in range(tri)])


def thin_cards(pos, nrm, uv, frac, seed):
    """Keep a fraction of the foliage islands (always the outermost ones first, so the silhouette stays) and grow the kept ones about their centres."""
    if frac >= 0.999 or len(pos) == 0:
        return pos, nrm, uv
    comp = components(pos)
    ids = sorted(set(comp.tolist()))
    cent = {}
    for c in ids:
        sel = np.repeat(comp == c, 3)
        cent[c] = pos[sel].mean(axis=0)
    rng = np.random.RandomState(seed)
    r = {c: float(np.hypot(cent[c][0], cent[c][2])) + float(rng.rand()) * 0.7 for c in ids}
    order = sorted(ids, key=lambda c: -r[c])
    keep = set(order[: max(2, int(round(len(ids) * frac)))])
    boost = 1.0 / np.sqrt(max(frac, 0.2))
    out_p, out_n, out_u = [], [], []
    for t in range(len(comp)):
        if comp[t] not in keep:
            continue
        c = cent[comp[t]]
        for k in range(3):
            out_p.append(c + (pos[t * 3 + k] - c) * boost)
            out_n.append(nrm[t * 3 + k])
            out_u.append(uv[t * 3 + k])
    return np.array(out_p, np.float32), np.array(out_n, np.float32), np.array(out_u, np.float32)


def sample(tex, u, v):
    h, w = tex.shape[:2]
    x = np.clip((np.mod(u, 1.0) * w).astype(int), 0, w - 1)
    y = np.clip((np.mod(v, 1.0) * h).astype(int), 0, h - 1)
    return tex[y, x]


def build(piece, spec, src_dir, rock_tex, seed):
    src, trunk_tris, frac = spec
    ob = import_piece(src_dir, src)
    solid_ob = split_material(ob, lambda n: n.startswith("Bark") or n in ROCK_TEX)
    leaf_ob = split_material(ob, lambda n: n in LEAF_TILE)
    parts = []
    if solid_ob is not None:
        so = decimate(solid_ob, trunk_tris) if trunk_tris > 0 else solid_ob
        p, n, uv, mats = extract(so)
        col = np.zeros((len(p), 4), np.float32)
        for t in range(len(mats)):
            m = mats[t]
            if m in ROCK_TEX:
                tx = rock_tex[m]
                c = sample(tx, uv[t * 3: t * 3 + 3, 0].mean(), uv[t * 3: t * 3 + 3, 1].mean())
                c = srgb_to_lin(c)
                lum = float(c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11)
                c = (np.array([lum, lum * 0.97, lum * 0.93], np.float32) * 0.6 + c * 0.4) * 1.45          # the source rocks are mossy green: pull them towards grey stone
            else:
                base = np.array(BARK.get(m, (0.2, 0.15, 0.1)), np.float32)
                c = base
            col[t * 3: t * 3 + 3, :3] = c
        # darker towards the ground contact and slightly lighter up the trunk
        hmax = max(float(p[:, 1].max()), 0.1)
        col[:, :3] *= (0.78 + 0.3 * np.clip(p[:, 1:2] / hmax, 0, 1))
        col[:, 3] = 0.0
        parts.append((p, n, np.zeros((len(p), 2), np.float32), col))
    if leaf_ob is not None:
        p, n, uv, mats = extract(leaf_ob)
        # remap the uv of every triangle into its atlas tile
        newuv = np.zeros_like(uv)
        for t in range(len(mats)):
            tile = LEAF_TILE[mats[t]]
            box = TILES[tile][1]
            for k in range(3):
                u, v = uv[t * 3 + k]
                if box is not None:
                    u = (u - box[0]) / (box[2] - box[0])
                    v = (v - box[1]) / (box[3] - box[1])
                u = float(np.clip(u, 0.0, 1.0))
                v = float(np.clip(v, 0.0, 1.0))
                col, row = tile % 4, tile // 4
                newuv[t * 3 + k] = ((col + 0.03 + u * 0.94) * 0.25, (row + 0.03 + v * 0.94) * 0.5)
        p, n, newuv = thin_cards(p, n, newuv, frac, seed)
        # outward normals (a crown is lit like a ball, not like flat cards) and the ambient-occlusion ramp
        ymax = max(float(p[:, 1].max()), 0.1)
        ymin = float(p[:, 1].min())
        cy = (ymin + ymax) * 0.5 if ymax > 3.0 else ymin
        rad = max(float(np.hypot(p[:, 0], p[:, 2]).max()), 0.1)
        ctr = np.stack([np.zeros(len(p)), np.full(len(p), cy), np.zeros(len(p))], axis=1)
        out = p - ctr
        ln = np.linalg.norm(out, axis=1, keepdims=True)
        n = np.where(ln > 1e-4, out / np.maximum(ln, 1e-4), np.array([0, 1, 0], np.float32))
        d = np.clip(np.hypot(p[:, 0], p[:, 2]) / rad, 0, 1)
        up = np.clip((p[:, 1] - ymin) / max(ymax - ymin, 0.1), 0, 1)
        ao = 0.62 + 0.38 * np.clip(d * 0.85 + up * 0.35, 0, 1)
        col = np.stack([ao, ao, ao, np.ones(len(p))], axis=1).astype(np.float32)
        parts.append((p, n.astype(np.float32), newuv, col))
    pos = np.concatenate([x[0] for x in parts])
    nrm = np.concatenate([x[1] for x in parts])
    uv = np.concatenate([x[2] for x in parts])
    col = np.concatenate([x[3] for x in parts])
    # on the axis, ground at y = 0 (the root flare goes under the ground by a few cm)
    mn = pos.min(axis=0)
    pos = pos - np.array([0.0, max(mn[1], -0.05) if mn[1] > -0.05 else 0.0, 0.0], np.float32)
    return pos, nrm, uv, col


def dedupe(pos, nrm, uv, col):
    q = np.concatenate([np.round(pos * 1000), np.round(nrm * 100), np.round(uv * 10000), np.round(col * 100)], axis=1)
    _, idx, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    return pos[idx], nrm[idx], uv[idx], col[idx], inv.reshape(-1).astype(np.uint32)


def write_glb(path, pieces):
    bufs = bytearray()
    views, accs, meshes, nodes = [], [], [], []

    def add(data, target):
        off = len(bufs)
        bufs.extend(data)
        bufs.extend(b"\0" * (-len(bufs) % 4))
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(views) - 1
    for name, (pos, nrm, uv, col, idx) in pieces.items():
        a = len(accs)
        accs.append({"bufferView": add(pos.astype("<f4").tobytes(), 34962), "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()})
        accs.append({"bufferView": add(nrm.astype("<f4").tobytes(), 34962), "componentType": 5126, "count": len(pos), "type": "VEC3"})
        accs.append({"bufferView": add(col.astype("<f4").tobytes(), 34962), "componentType": 5126, "count": len(pos), "type": "VEC4"})
        accs.append({"bufferView": add(uv.astype("<f4").tobytes(), 34962), "componentType": 5126, "count": len(pos), "type": "VEC2"})
        accs.append({"bufferView": add(idx.astype("<u4").tobytes(), 34963), "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a, "NORMAL": a + 1, "COLOR_0": a + 2, "TEXCOORD_0": a + 3}, "indices": a + 4, "material": 0}]})
        nodes.append({"mesh": len(meshes) - 1, "name": name})
    g = {"asset": {"version": "2.0", "generator": "convert_nature.py"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes,
         "materials": [{"name": "Nature", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}}],
         "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(bufs)}]}
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bufs)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bufs), 0x004E4942) + bytes(bufs))


def make_atlas(src_dir, out_path):
    atlas = Image.new("RGBA", (TILE * 4, TILE * 2), (255, 255, 255, 0))
    for tile, (fn, box) in TILES.items():
        im = Image.open(os.path.join(src_dir, "Textures", fn)).convert("RGBA")
        if box is not None:
            w, h = im.size
            im = im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
        im = im.resize((TILE, TILE), Image.LANCZOS)
        a = np.asarray(im, dtype=np.float32) / 255.0
        alpha = a[..., 3]
        lum = (a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11)
        # the atlas carries SHAPE only (white, alpha): the colour comes from the vertex colour and the shader
        rgb = np.clip(0.55 + 0.45 * lum / max(float((lum * (alpha > 0.5)).max()), 0.05), 0.0, 1.0)
        rgb = np.where(alpha[..., None] > 0.02, rgb[..., None], 1.0) * np.ones(3)
        out = np.concatenate([rgb, alpha[..., None]], axis=-1)
        atlas.paste(Image.fromarray((out * 255).astype(np.uint8), "RGBA"), ((tile % 4) * TILE, (tile // 4) * TILE))
    atlas.paste(Image.new("RGBA", (TILE, TILE), (255, 255, 255, 255)), (1 * TILE, 1 * TILE))      # tile 5: fully opaque, for the generated far LOD crowns and cones
    atlas.save(out_path, "WEBP", quality=80, method=6)


def main():
    src_dir = sys.argv[1]
    rock_tex = {k: load_tex(os.path.join(src_dir, "Textures", v)) for k, v in ROCK_TEX.items()}
    os.makedirs(OUT_MODELS, exist_ok=True)
    out = {}
    total = 0
    for i, (piece, spec) in enumerate(PIECES.items()):
        pos, nrm, uv, col = build(piece, spec, src_dir, rock_tex, 11 + i)
        pos, nrm, uv, col, idx = dedupe(pos, nrm, uv, col)
        out[piece] = (pos, nrm, uv, col, idx)
        total += len(idx) // 3
        size = pos.max(axis=0) - pos.min(axis=0)
        print("PIECE %-8s tris=%4d verts=%4d size=%.1f x %.1f x %.1f" % (piece, len(idx) // 3, len(pos), *size))
    write_glb(os.path.join(OUT_MODELS, "nature_kit.glb"), out)
    make_atlas(src_dir, os.path.join(OUT_TEX, "nature_atlas.webp"))
    print("TOTAL tris", total)


if __name__ == "__main__":
    main()
