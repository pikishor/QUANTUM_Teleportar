"""Minimal GLB utilities (pure Python, no bpy): inspect, count triangles, and move embedded images out to shared files.

Blender's glTF exporter always embeds textures inside a .glb. Godot then extracts every embedded image next to the model on
import (one copy per model, no sharing, duplicated in git). `externalize_images()` rewrites the GLB so that every image whose
name matches a file in the textures folder becomes a relative `uri` instead; the model stays tiny and all models share one
copy of each texture (and one GPU texture per set at runtime).
"""
import json
import os
import struct

_MAGIC = 0x46546C67
_JSON = 0x4E4F534A
_BIN = 0x004E4942


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != _MAGIC or version != 2:
        raise ValueError("not a glb v2 file: %s" % path)
    pos = 12
    js = None
    binary = b""
    while pos < len(data):
        clen, ctype = struct.unpack_from("<II", data, pos)
        chunk = data[pos + 8:pos + 8 + clen]
        if ctype == _JSON:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == _BIN:
            binary = chunk
        pos += 8 + clen
    return js, binary


def write_glb(path, js, binary):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    binary = bytes(binary)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(binary) if binary else 0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", _MAGIC, 2, total))
        f.write(struct.pack("<II", len(jb), _JSON) + jb)
        if binary:
            f.write(struct.pack("<II", len(binary), _BIN) + binary)


def triangle_count(js):
    """Triangles the scene renders: every node that references a mesh counts the mesh again (instances are not free)."""
    per_mesh = []
    for mesh in js.get("meshes", []):
        n = 0
        for prim in mesh.get("primitives", []):
            mode = prim.get("mode", 4)
            if mode != 4:
                continue
            if "indices" in prim:
                n += js["accessors"][prim["indices"]]["count"] // 3
            else:
                n += js["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
        per_mesh.append(n)
    total = 0
    for node in js.get("nodes", []):
        if "mesh" in node:
            total += per_mesh[node["mesh"]]
    return total


def strip_vertex_colors(path, keep_materials):
    """Drop COLOR_0 from every primitive whose material is not in `keep_materials`, then compact the binary chunk (unreferenced accessors and
    buffer views go away). The baked surfaces carry their tints in the textures, a vertex colour on them would be multiplied in by the importer."""
    js, binary = read_glb(path)
    mats = js.get("materials", [])
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            name = mats[prim["material"]].get("name") if "material" in prim else None
            if "COLOR_0" in prim["attributes"] and name not in keep_materials:
                prim["attributes"].pop("COLOR_0")
    used = set()
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            used.update(prim["attributes"].values())
            if "indices" in prim:
                used.add(prim["indices"])
            for tgt in prim.get("targets", []):
                used.update(tgt.values())
    for skin in js.get("skins", []):
        if "inverseBindMatrices" in skin:
            used.add(skin["inverseBindMatrices"])
    for anim in js.get("animations", []):
        for smp in anim.get("samplers", []):
            used.update((smp["input"], smp["output"]))
    acc_map, new_acc = {}, []
    for i, a in enumerate(js.get("accessors", [])):
        if i in used:
            acc_map[i] = len(new_acc)
            new_acc.append(a)
    view_used = {a["bufferView"] for a in new_acc if "bufferView" in a}
    view_used.update(img["bufferView"] for img in js.get("images", []) if "bufferView" in img)
    view_map, new_views, out = {}, [], bytearray()
    for i, v in enumerate(js.get("bufferViews", [])):
        if i not in view_used:
            continue
        while len(out) % 4:
            out.append(0)
        off = v.get("byteOffset", 0)
        nv = dict(v)
        nv["byteOffset"] = len(out)
        out += binary[off:off + v["byteLength"]]
        view_map[i] = len(new_views)
        new_views.append(nv)
    for a in new_acc:
        if "bufferView" in a:
            a["bufferView"] = view_map[a["bufferView"]]
    for img in js.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = view_map[img["bufferView"]]
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            prim["attributes"] = {k: acc_map[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = acc_map[prim["indices"]]
            for tgt in prim.get("targets", []):
                for k in list(tgt):
                    tgt[k] = acc_map[tgt[k]]
    for skin in js.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
    js["accessors"] = new_acc
    js["bufferViews"] = new_views
    js["buffers"][0]["byteLength"] = len(out)
    write_glb(path, js, out)


def externalize_images(path, textures_dir, uri_prefix="../textures/"):
    """Replace embedded images by relative URIs when `<textures_dir>/<image name>.<png|jpg|webp>` exists.
    Returns the list of image names that were externalized. Images with no matching file stay embedded."""
    js, binary = read_glb(path)
    images = js.get("images", [])
    if not images:
        return []
    drop_views = set()
    done = []
    for img in images:
        if "bufferView" not in img:
            continue
        name = img.get("name", "")
        for ext in (".png", ".jpg", ".webp"):
            if name and os.path.isfile(os.path.join(textures_dir, name + ext)):
                drop_views.add(img["bufferView"])
                img.pop("bufferView")
                img.pop("mimeType", None)
                img["uri"] = uri_prefix + name + ext
                done.append(name)
                break
    if not drop_views:
        return []
    old_views = js["bufferViews"]
    remap = {}
    new_views = []
    out = bytearray()
    for i, view in enumerate(old_views):
        if i in drop_views:
            continue
        off = view.get("byteOffset", 0)
        blob = binary[off:off + view["byteLength"]]
        while len(out) % 4:
            out.append(0)
        nv = dict(view)
        nv["byteOffset"] = len(out)
        out += blob
        remap[i] = len(new_views)
        new_views.append(nv)
    js["bufferViews"] = new_views
    for acc in js.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
    js["buffers"][0]["byteLength"] = len(out)
    write_glb(path, js, out)
    return done


def bounds(js):
    """Union of POSITION accessor min/max over all mesh-bearing nodes (node translations only, no rotation/scale)."""
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for node in js.get("nodes", []):
        if "mesh" not in node:
            continue
        t = node.get("translation", [0, 0, 0])
        for prim in js["meshes"][node["mesh"]]["primitives"]:
            acc = js["accessors"][prim["attributes"]["POSITION"]]
            for k in range(3):
                lo[k] = min(lo[k], acc["min"][k] + t[k])
                hi[k] = max(hi[k], acc["max"][k] + t[k])
    return lo, hi


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        j, b = read_glb(p)
        print(p, "tris=%d" % triangle_count(j), "bin=%d" % len(b), "images=%s" % [i.get("name") or i.get("uri") for i in j.get("images", [])])
