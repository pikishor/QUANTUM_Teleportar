#!/usr/bin/env python3
"""Procedural app icon, quantum theme: a bright core with two orbit rings and a teleport spark on a deep violet field.
Writes assets/icon/icon_1024.png (opaque, store icon), icon_192.png, and the adaptive layers (432x432, content in the central 66%):
icon_fg_432.png (transparent), icon_bg_432.png (opaque), icon_mono_432.png (white silhouette on transparent).
Usage: python3 -I tools/release/make_icon.py [outdir]   (needs Pillow; deterministic)"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersample


def glow(size, pts, color, blur):
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for p in pts:
        d.ellipse(p, fill=color)
    return im.filter(ImageFilter.GaussianBlur(blur))


def background(n):
    im = Image.new("RGB", (n, n))
    px = im.load()
    c = n / 2
    for y in range(n):
        for x in range(n):
            t = min(1.0, math.hypot(x - c, y - c) / (n * 0.72))
            px[x, y] = (int(40 * (1 - t) + 5 * t), int(14 * (1 - t) + 3 * t), int(88 * (1 - t) + 22 * t))
    return im


def foreground(n, mono=False):
    """Symbol inside the central 66 % (adaptive safe zone)."""
    big = n * S
    c = big / 2
    r = big * 0.30
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = (255, 255, 255, 255) if mono else (120, 235, 255, 255)
    col2 = (255, 255, 255, 255) if mono else (255, 120, 235, 255)
    w = max(2, int(big * 0.022))
    for ang, color in ((28, col), (-28, col2)):
        ring = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring)
        rd.ellipse((c - r, c - r * 0.42, c + r, c + r * 0.42), outline=color, width=w)
        im.alpha_composite(ring.rotate(ang, resample=Image.BICUBIC))
    core = r * 0.30
    if not mono:
        im.alpha_composite(glow((big, big), [(c - core * 2, c - core * 2, c + core * 2, c + core * 2)], (120, 235, 255, 150), big * 0.03))
    d = ImageDraw.Draw(im)
    d.ellipse((c - core, c - core, c + core, c + core), fill=(255, 255, 255, 255))
    # teleport spark: a small diamond on the upper ring
    sx, sy = c + r * 0.74, c - r * 0.34
    k = big * 0.04
    d.polygon([(sx, sy - k * 1.6), (sx + k, sy), (sx, sy + k * 1.6), (sx - k, sy)], fill=col2)
    return im.resize((n, n), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icon")
    os.makedirs(out, exist_ok=True)
    full = background(1024)
    full.paste(foreground(1024).resize((1024, 1024)), (0, 0), foreground(1024))
    full.save(os.path.join(out, "icon_1024.png"))
    full.resize((192, 192), Image.LANCZOS).save(os.path.join(out, "icon_192.png"))
    background(432).save(os.path.join(out, "icon_bg_432.png"))
    foreground(432).save(os.path.join(out, "icon_fg_432.png"))
    foreground(432, mono=True).save(os.path.join(out, "icon_mono_432.png"))
    print("icons written to", os.path.normpath(out))


main()
