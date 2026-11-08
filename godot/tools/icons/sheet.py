#!/usr/bin/env python3
"""Contact sheet of assets/icons on a dark panel: python3 tools/icons/sheet.py OUT.png [prefix ...]  (e.g. w_ v_)"""
import sys, os
from PIL import Image, ImageDraw
out = sys.argv[1]
pre = sys.argv[2:] or ["w_", "g_", "v_", "e_"]
d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "icons")
files = [f for f in sorted(os.listdir(d)) if f.endswith(".png") and any(f.startswith(p) for p in pre)]
cw, ch, cols = 200, 130, 6
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw, rows * ch), (16, 20, 30))
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(os.path.join(d, f)).convert("RGBA")
    k = min((cw - 12) / im.width, (ch - 28) / im.height)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    x, y = (i % cols) * cw, (i // cols) * ch
    dr.rectangle([x + 3, y + 3, x + cw - 4, y + ch - 4], fill=(26, 32, 46), outline=(50, 70, 90))
    sheet.paste(im, (x + (cw - im.width) // 2, y + 6 + (ch - 28 - im.height) // 2), im)
    dr.text((x + 8, y + ch - 20), f[:-4], fill=(120, 220, 255))
sheet.save(out)
print(out, len(files))
