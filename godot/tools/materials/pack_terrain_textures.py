#!/usr/bin/env python3
"""Fetch (plain curl, descriptive user agent) the 1K diffuse maps of the Poly Haven CC0 terrain sets below and pack them as
assets/textures/terrain_<layer>.webp (1024 px, lossy WebP q82, sRGB albedo, seamless as published). The terrain shader (assets/shaders/terrain.gdshader) reads the
seven files as ONE Texture2DArray (scripts/terrain/terrain_textures.gd). Raw downloads go to assets_incoming/terrain_raw/ (git-ignored); only the packed result is committed.
Then: tools/import.sh, `python3 tools/materials/pack_terrain_textures.py --patch-imports` (VRAM compression with mipmaps), tools/import.sh again.
  python3 tools/materials/pack_terrain_textures.py [--fetch] [--patch-imports]"""
import argparse, os, re, subprocess, sys
from PIL import Image

UA = "QuantumTeleportar-asset-fetch/1.0 (CC0 asset import; github.com/pikishor/QUANTUM_Teleportar)"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
RAW = os.path.join(ROOT, "assets_incoming", "terrain_raw")
OUT = os.path.join(ROOT, "assets", "textures")
# layer order = the layer index in the terrain shader
LAYERS = [
    ("grass", "forrest_ground_01"),
    ("forest", "rocky_terrain_02"),
    ("desert", "dry_ground_rocks"),
    ("beach", "aerial_sand"),
    ("rock", "rock_boulder_dry"),
    ("snow", "snow_02"),
    ("dirt", "gravel_road"),
]


def fetch():
    os.makedirs(RAW, exist_ok=True)
    bad = 0
    for _, slug in LAYERS:
        dst = os.path.join(RAW, "%s_diff_1k.jpg" % slug)
        if os.path.exists(dst) and os.path.getsize(dst) > 1000:
            continue
        url = "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/%s/%s_diff_1k.jpg" % (slug, slug)
        if subprocess.run(["curl", "-sS", "-f", "-L", "-A", UA, "-o", dst, url]).returncode != 0:
            print("FAILED", url); bad += 1
    return bad


def pack():
    for name, slug in LAYERS:
        im = Image.open(os.path.join(RAW, "%s_diff_1k.jpg" % slug)).convert("RGB")
        if im.size != (1024, 1024):
            im = im.resize((1024, 1024), Image.LANCZOS)
        im.save(os.path.join(OUT, "terrain_%s.webp" % name), quality=82, method=6)
        print("packed terrain_%s <- %s" % (name, slug))


def patch_imports():
    n = 0
    for fn in sorted(os.listdir(OUT)):
        if not (fn.startswith("terrain_") and fn.endswith(".webp.import")):
            continue
        p = os.path.join(OUT, fn)
        s = open(p).read()
        for key, val in (("compress/mode", "2"), ("compress/high_quality", "true"), ("mipmaps/generate", "true")):
            s = re.sub(r"^%s=.*$" % re.escape(key), "%s=%s" % (key, val), s, flags=re.M)
        open(p, "w").write(s)
        n += 1
    print("patched %d .import files" % n)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--patch-imports", action="store_true")
    a = ap.parse_args()
    if a.patch_imports:
        patch_imports(); sys.exit(0)
    if a.fetch or not os.path.isdir(RAW):
        if fetch():
            sys.exit(1)
    pack()
