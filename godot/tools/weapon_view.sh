#!/usr/bin/env bash
# Weapon close-ups: the hero holding every weapon (look-dev viewer, software Vulkan), one image per weapon and view, then one contact sheet.
#   tools/weapon_view.sh OUT_PREFIX [weapons=a,b,c] [views=rifle,side] [pose=aim]      e.g. tools/weapon_view.sh /tmp/w/w
# Default: every weapon of WeaponDefs.IDS. The contact sheet is <OUT_PREFIX>_sheet.png (needs python3 with PIL).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
ARGS=("$@")
HAVE_W=0; for a in "${ARGS[@]}"; do [[ "$a" == weapons=* ]] && HAVE_W=1; done
if [ "$HAVE_W" = 0 ]; then ARGS+=("weapons=pistol,flux,carbine,scatter,rail,gravity,blade,marksman,burst,revolver,akimbo,breacher,arc,lance,whip,rocket,minigun,grenade"); fi
HAVE_V=0; for a in "${ARGS[@]}"; do [[ "$a" == views=* ]] && HAVE_V=1; done
if [ "$HAVE_V" = 0 ]; then ARGS+=("views=rifle,side"); fi
HAVE_P=0; for a in "${ARGS[@]}"; do [[ "$a" == pose=* ]] && HAVE_P=1; done
if [ "$HAVE_P" = 0 ]; then ARGS+=("pose=aim"); fi
tools/hero/view.sh "$OUT" "${ARGS[@]}"
python3 - "$OUT" "${ARGS[@]}" <<'PY'
import sys, glob, os
from PIL import Image, ImageDraw
out = sys.argv[1]
kv = dict(a.split("=", 1) for a in sys.argv[2:] if "=" in a)
ws = kv["weapons"].split(","); vs = kv["views"].split(",")
cw, ch = 400, 300
cols = len(vs) * 2
rows = (len(ws) + 1) // 2
sheet = Image.new("RGB", (cols * cw, rows * ch), (10, 10, 14))
d = ImageDraw.Draw(sheet)
for i, w in enumerate(ws):
    for j, v in enumerate(vs):
        f = "%s_%s_%s.png" % (out, w, v)
        if not os.path.exists(f):
            continue
        im = Image.open(f).convert("RGB")
        # crop around the weapon area (right of centre) and fit
        W, H = im.size
        box = (int(W * 0.22), int(H * 0.12), int(W * 0.78), int(H * 0.75)) if v == "rifle" else (int(W * 0.3), int(H * 0.15), int(W * 0.78), int(H * 0.6))
        im = im.crop(box).resize((cw, ch))
        x = ((i % 2) * len(vs) + j) * cw; y = (i // 2) * ch
        sheet.paste(im, (x, y))
    d.text(((i % 2) * len(vs) * cw + 8, (i // 2) * ch + 6), w.upper(), fill=(255, 220, 120))
sheet.save(out + "_sheet.png")
print("sheet", out + "_sheet.png")
PY
