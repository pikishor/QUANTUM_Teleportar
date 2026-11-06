#!/usr/bin/env python3
# Contact sheet of a frame sequence: tools/contact_sheet.py out.png COLS "glob/*.png" [scale]  (needs PIL). Used for the render-look-fix loops (docs/shots/slice).
import sys, glob
from PIL import Image, ImageDraw
# usage: sheet.py out.png cols prefix_dir_glob [scale]
out, cols, pattern = sys.argv[1], int(sys.argv[2]), sys.argv[3]
scale = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
files = sorted(glob.glob(pattern))
ims = [Image.open(f).convert("RGB") for f in files]
if not ims: sys.exit("no files")
w, h = int(ims[0].width*scale), int(ims[0].height*scale)
rows = (len(ims)+cols-1)//cols
sheet = Image.new("RGB", (cols*w, rows*h), (10,10,10))
d = ImageDraw.Draw(sheet)
for i, im in enumerate(ims):
    im = im.resize((w, h))
    x, y = (i%cols)*w, (i//cols)*h
    sheet.paste(im, (x, y))
    d.text((x+4, y+4), str(i), fill=(255,255,0))
sheet.save(out)
print(out, sheet.size)
