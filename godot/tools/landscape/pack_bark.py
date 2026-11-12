#!/usr/bin/env python3
"""Bark textures of the landscape trees (wave 112): Poly Haven CC0 1K diffuse maps (plain urllib, descriptive user agent) packed as assets/textures/land_bark_<species>.webp
(512 px, seamless as published, graded per species; birch gets painted lenticels, the alien tree a procedural glowing bark).
  godot/.venv-tools/bin/python godot/tools/landscape/pack_bark.py [--fetch]
Raw downloads go to a scratch folder ($QT_RAW_DIR, default godot/assets_incoming/land_raw, git-ignored); only the packed result is committed (art_sources/polyhaven_land keeps the licence).
"""
import argparse
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

UA = "QuantumTeleportar-asset-fetch/1.0 (CC0 asset import; github.com/pikishor/QUANTUM_Teleportar)"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RAW = os.environ.get("QT_RAW_DIR", os.path.join(ROOT, "assets_incoming", "land_raw"))
OUT = os.environ.get("QT_TEX_DIR", os.path.join(ROOT, "assets", "textures"))

# species -> (poly haven slug, brightness, saturation, tint (multiplies rgb))
BARK = {
    "oak": ("bark_brown_01", 0.92, 0.85, (1.0, 0.96, 0.9)),
    "pine": ("pine_bark", 1.0, 0.9, (1.0, 0.95, 0.92)),
    "fir": ("chinese_cedar_bark", 0.78, 0.9, (0.95, 0.92, 0.95)),
    "birch": ("tree_bark_03", 1.45, 0.25, (1.0, 1.0, 1.0)),
    "poplar": ("bark_brown_02", 0.92, 0.7, (1.0, 0.98, 0.95)),
    "palm": ("palm_tree_bark", 1.0, 0.8, (1.0, 0.97, 0.9)),
    "acacia": ("bark_willow", 1.15, 0.8, (1.0, 0.92, 0.85)),
    "dead": ("bark_brown_02", 1.25, 0.18, (0.96, 0.95, 0.94)),
}


def fetch(slug):
    os.makedirs(RAW, exist_ok=True)
    dst = os.path.join(RAW, "%s_diff_1k.jpg" % slug)
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        return dst
    req = urllib.request.Request("https://api.polyhaven.com/files/" + slug, headers={"User-Agent": UA})
    d = json.loads(urllib.request.urlopen(req, timeout=60).read())
    url = d["Diffuse"]["1k"]["jpg"]["url"]
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with open(dst, "wb") as f:
        f.write(urllib.request.urlopen(req, timeout=120).read())
    return dst


def grade(im, bright, sat, tint):
    im = im.convert("RGB")
    im = ImageEnhance.Color(im).enhance(sat)
    im = ImageEnhance.Brightness(im).enhance(bright)
    a = np.asarray(im, dtype=np.float32)
    a *= np.array(tint, dtype=np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def birch_marks(im, seed=7):
    """Dark horizontal lenticels and a few grey patches on the pale bark (tiling: marks wrap around the edges)."""
    rng = np.random.RandomState(seed)
    W, H = im.size
    big = Image.new("RGB", (W * 3, H * 3))
    for ox in range(3):
        for oy in range(3):
            big.paste(im, (ox * W, oy * H))
    dr = ImageDraw.Draw(big)
    for i in range(int(110 * 3)):
        x = rng.uniform(0, W * 3)
        y = rng.uniform(0, H * 3)
        w = rng.uniform(W * 0.04, W * 0.20)
        h = rng.uniform(H * 0.006, H * 0.016)
        dark = int(rng.uniform(18, 60))
        dr.ellipse([x - w, y - h, x + w, y + h], fill=(dark, dark - 2, dark - 4))
    for i in range(24):
        x = rng.uniform(0, W * 3)
        y = rng.uniform(0, H * 3)
        r = rng.uniform(W * 0.06, W * 0.16)
        g = int(rng.uniform(110, 150))
        dr.ellipse([x - r, y - r * 0.45, x + r, y + r * 0.45], fill=(g, g, g - 6))
    big = big.filter(ImageFilter.GaussianBlur(1.2))
    return big.crop((W, H, 2 * W, 2 * H))


def alien_bark(size=512, seed=3):
    """Dark violet bark with glowing cyan veins; tiles in both directions."""
    rng = np.random.RandomState(seed)
    n = np.zeros((size, size), dtype=np.float32)
    for k, wgt in ((6, 0.55), (14, 0.3), (40, 0.15)):
        g = rng.rand(k, k).astype(np.float32)
        t = np.tile(g, (3, 3))
        im = Image.fromarray((t * 255).astype(np.uint8), "L").resize((size * 3, size * 3), Image.BICUBIC).crop((size, size, 2 * size, 2 * size))
        n += wgt * np.asarray(im, dtype=np.float32) / 255.0
    base = np.stack([0.14 + 0.2 * n, 0.07 + 0.1 * n, 0.26 + 0.30 * n], axis=2)
    big = Image.new("RGB", (size * 3, size * 3), (0, 0, 0))
    dr = ImageDraw.Draw(big)
    for i in range(70 * 3):
        x, y = rng.uniform(0, size * 3), rng.uniform(0, size * 3)
        a = rng.uniform(-0.4, 0.4) + np.pi / 2
        pts = [(x, y)]
        for s in range(rng.randint(5, 14)):
            a += rng.uniform(-0.5, 0.5)
            x += np.cos(a) * rng.uniform(8, 22)
            y += np.sin(a) * rng.uniform(8, 22)
            pts.append((x, y))
        dr.line(pts, fill=(60, 240, 230), width=int(rng.uniform(1, 3)))
    veins = np.asarray(big.filter(ImageFilter.GaussianBlur(1.4)).crop((size, size, 2 * size, 2 * size)), dtype=np.float32) / 255.0
    glow = np.asarray(big.filter(ImageFilter.GaussianBlur(5.0)).crop((size, size, 2 * size, 2 * size)), dtype=np.float32) / 255.0
    out = np.clip(base + veins * 1.0 + glow * 0.5, 0, 1)
    return Image.fromarray((out * 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fetch", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for name, (slug, br, sat, tint) in BARK.items():
        path = os.path.join(RAW, "%s_diff_1k.jpg" % slug)
        if a.fetch or not os.path.exists(path):
            path = fetch(slug)
        im = Image.open(path)
        im = im.resize((512, 512), Image.LANCZOS)
        im = grade(im, br, sat, tint)
        if name == "birch":
            im = birch_marks(im)
        im.save(os.path.join(OUT, "land_bark_%s.webp" % name), quality=84, method=6)
        print("land_bark_%s.webp <- %s" % (name, slug))
    alien_bark().save(os.path.join(OUT, "land_bark_alien.webp"), quality=84, method=6)
    print("land_bark_alien.webp (procedural)")


if __name__ == "__main__":
    sys.exit(main())
