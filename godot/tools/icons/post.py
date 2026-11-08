#!/usr/bin/env python3
"""Raw icon renders (2x, RGBA) -> small palette PNGs in assets/icons: halve (smooth edges), lift the dark steel a little, add a thin light outline (the pictures sit on dark panels),
palettise to 128 colours with alpha. Usage: python3 tools/icons/post.py RAW_DIR OUT_DIR [--large]
--large keeps the 2x size (384 x 192) and writes wl_<weapon>.png: the big picture of the LOADOUT screen (scripts/ui/item_icons.gd `weapon_large`)."""
import sys, os
from PIL import Image, ImageFilter, ImageChops

src, dst = sys.argv[1], sys.argv[2]
large = "--large" in sys.argv[3:]
os.makedirs(dst, exist_ok=True)
n = 0
for f in sorted(os.listdir(src)):
    if not f.endswith(".png"):
        continue
    im = Image.open(os.path.join(src, f)).convert("RGBA")
    if not large:
        im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS)
    elif not f.startswith("w_"):
        continue
    r, g, b, a = im.split()
    lut = [min(255, int(255.0 * (v / 255.0) ** 0.78)) for v in range(256)]          # lift the darks: black rifles must read on a dark panel
    im = Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))
    # outline: the alpha grown by 2 px, minus the picture itself, in a light cool tone
    big = a.filter(ImageFilter.MaxFilter(5))
    ring = ImageChops.subtract(big, a.point(lambda v: 255 if v > 40 else 0))
    ring = ring.point(lambda v: min(255, int(v * 0.75)))
    outline = Image.new("RGBA", im.size, (170, 215, 255, 0))
    outline.putalpha(ring)
    out = Image.alpha_composite(outline, im)
    alpha = out.getchannel("A")
    q = out.convert("RGB").quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    q.putalpha(alpha)
    q = q.quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q.save(os.path.join(dst, ("wl_" + f[2:]) if large else f), optimize=True)
    n += 1
print("icons written:", n, "->", dst)
