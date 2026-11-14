#!/usr/bin/env python3
"""Packs the weapon pictures of tools/icons/weapon_pics.gd into the atlas pages of assets/icons/wp/ (read by scripts/ui/weapon_pics.gd).

  python3 tools/icons/weapon_atlas.py --raw RAW_DIR --pack      pack the 1024 x 512 renders of RAW_DIR (every id of tools/blender/weapon_index.json that has a file there; the others keep
                                                                 the cell they have in the existing pages), write the pages, the .import files and manifest.json
  python3 tools/icons/weapon_atlas.py --stale                   print the ids (comma separated) whose model file or renderer VERSION changed since the manifest (empty = up to date)
  python3 tools/icons/weapon_atlas.py --check                   exit 1 and list the stale ids (tests/test_weapon_pics.gd does the same check inside the game)
  python3 tools/icons/weapon_atlas.py --sheet OUT.jpg [--ids a,b]   a contact sheet of the pages on the class backdrops (look-dev, docs)

Two page sets per class, in the order of weapon_index.json (the order of WeaponDefs.all_ids()):
  t_<class>_<n>.webp THUMBS  a frame of 256 x 128 (tiles, wheel discs, HUD plate, kill feed, pickups)
  c_<class>_<n>.webp CARDS   a frame of 512 x 256 (the big picture of a weapon card, the crate reveal, the shop)
The pictures have a transparent background and a thin outline in the class colour; the class backdrop is drawn by the UI. Every picture is cropped to its visible pixels and the crops are shelf-packed
into pages of at most 1024 x 1024 (manifest.json: per weapon the page, the rectangle and the offset inside its frame, which WeaponPics turns into an AtlasTexture with a margin, so callers see a
full-frame texture). Pages are WebP sources imported as VRAM-compressed textures (ETC2 / S3TC, 1 byte a pixel; thumbs with two mip levels): a page costs 1 MB of texture memory while a menu shows it.
"""
import argparse
import hashlib
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "icons", "wp")
MODELS = os.path.join(ROOT, "assets", "models", "weapons")
INDEX = os.path.join(ROOT, "tools", "blender", "weapon_index.json")
RENDERER = os.path.join(HERE, "weapon_pics.gd")
UIKIT = os.path.join(ROOT, "scripts", "ui", "ui_kit.gd")
CLASS_ORDER = ["pistol", "smg", "rifle", "shotgun", "sniper", "heavy", "melee", "quantum", "energy", "blast"]
THUMB = (256, 128, 8, 4)       # cell w, h, columns, rows
CARD = (512, 256, 4, 4)


def renderer_version():
    m = re.search(r"const VERSION := (\d+)", open(RENDERER).read())
    return int(m.group(1)) if m else 0


def class_tints():
    """The class colours of UiKit.CLASS_TINT (one source of truth: the UI kit)."""
    src = open(UIKIT).read()
    block = src[src.index("const CLASS_TINT"):]
    block = block[:block.index("}")]
    out = {}
    for m in re.finditer(r'&"(\w+)": Color\(([\d.]+), ([\d.]+), ([\d.]+)\)', block):
        out[m.group(1)] = tuple(int(round(float(m.group(i)) * 255)) for i in (2, 3, 4))
    return out


def load_index():
    items = json.load(open(INDEX))
    by_class = {c: [] for c in CLASS_ORDER}
    for it in items:
        by_class[it["class"]].append(it["id"])
    return items, by_class


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest():
    p = os.path.join(OUT, "manifest.json")
    if os.path.exists(p):
        return json.load(open(p))
    return {"version": 0, "weapons": {}}


def stale_ids():
    man = load_manifest()
    items, _ = load_index()
    ver = renderer_version()
    out = []
    for it in items:
        wid = it["id"]
        glb = os.path.join(MODELS, wid + ".glb")
        cur = md5_of(glb) if os.path.exists(glb) else ""
        rec = man.get("weapons", {}).get(wid)
        if rec is None or man.get("version") != ver or rec.get("md5") != cur:
            out.append(wid)
    return out


# ---------------------------------------------------------------------------------------------------------------------------------- sprites

def make_sprite(raw, tint, size, outline):
    """The picture of one weapon at `size` (a frame of 2:1) from its 1024 x 512 render: smooth downscale, a little sharpening, the darks lifted (a black rifle must read on a dark panel) and a thin
    light outline in the class colour (the wheel discs and the HUD plate are dark). The glow behind the weapon is the backdrop's job (WeaponPics.draw_backdrop)."""
    im = raw.convert("RGBA").resize(size, Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.0, percent=55, threshold=2))
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb = np.power(np.clip(a[..., :3], 0.0, 1.0), 0.82) * 1.04
    al = a[..., 3]
    alpha_img = Image.fromarray((al * 255).astype(np.uint8))
    grown = np.asarray(alpha_img.filter(ImageFilter.MaxFilter(2 * outline + 1))).astype(np.float32) / 255.0
    ring = np.clip(grown - al, 0.0, 1.0) * 0.4
    t = np.array(tint, dtype=np.float32) / 255.0
    rc = np.clip(t * 0.8 + 0.2, 0.0, 1.0)
    out_a = al + ring * (1.0 - al)
    safe = np.maximum(out_a, 1e-4)[..., None]
    out_rgb = (np.clip(rgb, 0, 1) * al[..., None] + rc[None, None, :] * (ring * (1.0 - al))[..., None]) / safe
    out = np.concatenate([np.clip(out_rgb, 0, 1), np.clip(out_a, 0, 1)[..., None]], axis=2)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def tight_box(im, pad=2):
    """The bounding box of the visible pixels of a sprite (with a pad of transparent pixels), (x0, y0, x1, y1)."""
    a = np.asarray(im)[..., 3]
    ys, xs = np.where(a > 3)
    if len(xs) == 0:
        return (0, 0, 4, 4)
    return (max(0, int(xs.min()) - pad), max(0, int(ys.min()) - pad), min(im.width, int(xs.max()) + 1 + pad), min(im.height, int(ys.max()) + 1 + pad))


# ---------------------------------------------------------------------------------------------------------------------------------- pages

PAGE_W = 1024
PAGE_H = 1024            # at most: a page of cards is 1 MB of texture memory (ETC2 / S3TC, 1 byte a pixel)
GUTTER = 2


def page_name(kind, cls, n):
    return "%s_%s_%d.webp" % ("t" if kind == "thumb" else "c", cls, n)


def read_sprite(rec, kind):
    """The existing picture of a weapon from its page (the full frame: the cropped sprite put back at its offset), None when it is not there."""
    spec = THUMB if kind == "thumb" else CARD
    r = rec.get("t" if kind == "thumb" else "c")
    if not r:
        return None
    p = os.path.join(OUT, page_name(kind, rec["cls"], r[0]))
    if not os.path.exists(p):
        return None
    page = Image.open(p).convert("RGBA")
    crop = page.crop((r[1], r[2], r[1] + r[3], r[2] + r[4]))
    frame = Image.new("RGBA", (spec[0], spec[1]), (0, 0, 0, 0))
    frame.paste(crop, (r[5], r[6]))
    return frame


def shelf_pack(items):
    """items: [(key, w, h)] -> {key: (page, x, y)} and the used height of every page. Tallest first, left to right in rows; a new page when the next row does not fit."""
    order = sorted(items, key=lambda it: (-it[2], -it[1], it[0]))
    place = {}
    heights = []
    page = 0
    x = y = row_h = 0
    for key, w, h in order:
        if x + w > PAGE_W and x > 0:
            x = 0
            y += row_h + GUTTER
            row_h = 0
        if y + h > PAGE_H and (y > 0 or x > 0):
            heights.append(y + row_h)
            page += 1
            x = y = row_h = 0
        place[key] = (page, x, y)
        x += w + GUTTER
        row_h = max(row_h, h)
    heights.append(y + row_h)
    return place, [((h + 3) // 4) * 4 for h in heights]


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=%s
mipmaps/limit=2
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def pack(raw_dir):
    items, by_class = load_index()
    tints = class_tints()
    ver = renderer_version()
    man = load_manifest()
    old = man.get("weapons", {})
    if man.get("version") != ver:
        old = {}                                    # a new renderer: every picture is new
    weapons = {}
    os.makedirs(OUT, exist_ok=True)
    keep = set()
    total_bytes = 0
    for cls in CLASS_ORDER:
        ids = by_class[cls]
        tint = tints.get(cls, (120, 200, 255))
        frames = {"thumb": {}, "card": {}}
        for wid in ids:
            rawp = os.path.join(raw_dir, wid + ".png") if raw_dir else ""
            if rawp and os.path.exists(rawp):
                raw = Image.open(rawp)
                frames["card"][wid] = make_sprite(raw, tint, (CARD[0], CARD[1]), 1)
                frames["thumb"][wid] = make_sprite(raw, tint, (THUMB[0], THUMB[1]), 1)
            else:
                rec = old.get(wid)
                t = read_sprite(rec, "thumb") if rec else None
                c = read_sprite(rec, "card") if rec else None
                if t is None or c is None:
                    sys.exit("no picture for %s: render it first (tools/icons/weapon_pics.sh)" % wid)
                frames["card"][wid] = c
                frames["thumb"][wid] = t
            glb = os.path.join(MODELS, wid + ".glb")
            weapons[wid] = {"cls": cls, "i": len(weapons), "md5": md5_of(glb) if os.path.exists(glb) else ""}
        for kind, spec, tag in (("thumb", THUMB, "t"), ("card", CARD, "c")):
            boxes = {wid: tight_box(frames[kind][wid]) for wid in ids}
            place, heights = shelf_pack([(wid, boxes[wid][2] - boxes[wid][0], boxes[wid][3] - boxes[wid][1]) for wid in ids])
            pages = [Image.new("RGBA", (PAGE_W, h), (0, 0, 0, 0)) for h in heights]
            for wid in ids:
                b = boxes[wid]
                pg, x, y = place[wid]
                pages[pg].paste(frames[kind][wid].crop(b), (x, y))
                weapons[wid][tag] = [pg, x, y, b[2] - b[0], b[3] - b[1], b[0], b[1]]
            for n, page in enumerate(pages):
                name = page_name(kind, cls, n)
                path = os.path.join(OUT, name)
                page.save(path, "WEBP", quality=90, method=4, alpha_quality=100)
                total_bytes += os.path.getsize(path)
                keep.add(name)
                with open(path + ".import", "w") as f:
                    f.write(IMPORT % ("true" if kind == "thumb" else "false"))
                keep.add(name + ".import")
    for f in os.listdir(OUT):                       # pages of an earlier layout (png or more pages than now) go
        if f not in keep and f != "manifest.json" and (f.startswith("t_") or f.startswith("c_")):
            os.remove(os.path.join(OUT, f))
    manifest = {"version": ver, "thumb": [THUMB[0], THUMB[1]], "card": [CARD[0], CARD[1]], "classes": CLASS_ORDER, "weapons": weapons}
    json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), separators=(",", ":"))
    print("packed %d weapons, %.1f MB of WebP in %s" % (len(weapons), total_bytes / 1048576.0, OUT))


def sheet(path, ids_arg):
    """A look-dev sheet: the card pictures on the class backdrop (a flat dark panel with the class colour)."""
    items, by_class = load_index()
    tints = class_tints()
    man = load_manifest()
    chosen = ids_arg.split(",") if ids_arg else [it["id"] for it in items]
    cols = 5
    cw, ch = 400, 200
    rows = (len(chosen) + cols - 1) // cols
    img = Image.new("RGB", (cols * cw, rows * ch), (12, 14, 24))
    for n, wid in enumerate(chosen):
        rec = man["weapons"][wid]
        im = read_sprite(rec, "card")
        if im is None:
            continue
        t = tints.get(rec["cls"], (120, 200, 255))
        bg = Image.new("RGBA", (cw, ch), (16, 20, 34, 255))
        yy, xx = np.mgrid[0:ch, 0:cw].astype(np.float32)
        d = np.sqrt(((xx - cw * 0.5) / (cw * 0.5)) ** 2 + ((yy - ch * 0.55) / (ch * 0.6)) ** 2)
        g = np.clip(1.0 - d, 0, 1) ** 1.6 * 0.45
        arr = np.asarray(bg).astype(np.float32)
        for k in range(3):
            arr[..., k] = np.clip(arr[..., k] + g * t[k] * 0.9, 0, 255)
        bg = Image.fromarray(arr.astype(np.uint8), "RGBA")
        bg.alpha_composite(im.resize((cw, ch), Image.LANCZOS))
        img.paste(bg.convert("RGB"), ((n % cols) * cw, (n // cols) * ch))
    img.save(path, quality=82)
    print("sheet", path, img.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw")
    ap.add_argument("--pack", action="store_true")
    ap.add_argument("--stale", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--sheet")
    ap.add_argument("--ids", default="")
    a = ap.parse_args()
    if a.stale:
        print(",".join(stale_ids()))
    elif a.check:
        s = stale_ids()
        if s:
            print("stale weapon pictures: " + ",".join(s))
            sys.exit(1)
        print("weapon pictures are up to date")
    elif a.pack:
        pack(a.raw)
    elif a.sheet:
        sheet(a.sheet, a.ids)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
