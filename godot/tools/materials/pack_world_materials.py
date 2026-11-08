#!/usr/bin/env python3
"""Pack the scanned Poly Haven sets (tools/materials/fetch_polyhaven.py) into the city shaders' own slot format, so they plug into the existing taps (no extra draw, no extra tap):
  kind slot -> assets/textures/world_<name>_a.webp  RGB = albedo as a DETAIL MODULATOR (median luminance 0.5, `hue` = how much of the colour survives, the world's palette multiplies it), A = dry roughness
               assets/textures/world_<name>_n.webp  RG = tangent normal xy (G flipped to the engine's convention), B = cavity (1 on the typical surface), A = wet roughness
  kind flat -> assets/textures/world_<name>_a.webp  RGB = modulator x cavity (interiors: one tap), A = dry roughness
Size 1024 (lossy WebP, quality 90, alpha lossless). Then tools/import.sh and `python3 tools/materials/pack_world_materials.py --patch-imports` (ASTC / BPTC, mipmaps), tools/import.sh again.
  python3 tools/materials/pack_world_materials.py [--src DIR] [--out DIR] [--size 1024] [--only a,b]"""
import argparse, json, os, re, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


def load(path, size, mode):
    im = Image.open(path).convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0


def modulate(rgb, hue, gain, contrast=1.0):
    lum = (rgb @ LUMA)[..., None]
    rgb = lum + (rgb - lum) * hue                                   # keep `hue` of the colour: the world's own palette decides the district tint
    m = np.median(rgb @ LUMA)
    out = rgb * (0.5 * gain / max(m, 1e-4))
    return np.clip(0.5 + (out - 0.5) * contrast, 0.0, 1.0)         # contrast about the median: scans are flatter than the drawn look they replace


def u8(x):
    return (np.clip(x, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def pack(name, spec, src, out, size):
    d = os.path.join(src, spec["slug"])
    diff = load(os.path.join(d, "%s_diff_1k.jpg" % spec["slug"]), size, "RGB")
    arm = load(os.path.join(d, "%s_arm_1k.jpg" % spec["slug"]), size, "RGB")
    nor = load(os.path.join(d, "%s_nor_gl_1k.jpg" % spec["slug"]), size, "RGB")
    ao = arm[..., 0]
    rough = arm[..., 1]
    cavity = np.clip(ao / max(np.percentile(ao, 75), 1e-3), 0.0, 1.0)
    mod = modulate(diff, spec["hue"], spec["gain"], spec.get("contrast", 1.0))
    if spec["kind"] == "flat":
        a = np.dstack([mod * (0.45 + 0.55 * cavity[..., None]), rough])
        Image.fromarray(u8(a), "RGBA").save(os.path.join(out, "world_%s_a.webp" % name), quality=90, alpha_quality=100, method=6)
    else:
        a = np.dstack([mod, rough])
        n = np.dstack([nor[..., 0], 1.0 - nor[..., 1], cavity, np.clip(rough * 0.42, 0.04, 0.45)])
        Image.fromarray(u8(a), "RGBA").save(os.path.join(out, "world_%s_a.webp" % name), quality=90, alpha_quality=100, method=6)
        Image.fromarray(u8(n), "RGBA").save(os.path.join(out, "world_%s_n.webp" % name), quality=90, alpha_quality=100, method=6)
    print("packed %-14s <- %s" % (name, spec["slug"]))


def patch_imports(out):
    """VRAM compression (ASTC 4x4 / BPTC, high quality) with mipmaps; the packed normal stays a plain colour texture (RG + cavity + wet roughness are packed)."""
    n = 0
    for fn in sorted(os.listdir(out)):
        if not (fn.startswith("world_") and fn.endswith(".webp.import")):
            continue
        p = os.path.join(out, fn)
        s = open(p).read()
        for key, val in (("compress/mode", "2"), ("compress/high_quality", "true"), ("compress/normal_map", "2"), ("mipmaps/generate", "true"),
                         ("compress/channel_pack", "0"), ("process/fix_alpha_border", "false")):
            s = re.sub(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, val), s, flags=re.M)
        open(p, "w").write(s)
        n += 1
    print("patched %d .import files" % n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(ROOT, "assets_incoming", "polyhaven_raw"))
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "textures"))
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--only", default="")
    ap.add_argument("--patch-imports", action="store_true")
    a = ap.parse_args()
    if a.patch_imports:
        patch_imports(a.out); return 0
    sets = json.load(open(os.path.join(HERE, "world_materials.json")))["sets"]
    only = [x for x in a.only.split(",") if x]
    for name, spec in sets.items():
        if only and name not in only:
            continue
        pack(name, spec, a.src, a.out, a.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
