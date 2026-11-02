#!/usr/bin/env bash
# Visual QA: shoots ~12 fixed spots (streets x4, interior, car, chase, boss, title, hero, rain, storm) under software GL, saves
# docs/shots/<spot>.png, builds the contact sheet docs/shots/latest.png and prints PASS/FAIL per spot. Exit 1 on any FAIL.
#   tools/visual_qa.sh            QUALITY=0|1|2 picks the tier (default 1), VQA_SPOTS=hero,title for a subset
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="$(realpath -m ../docs/shots)"
mkdir -p "$OUT"
export VQA_OUT="$OUT" BOT_FASTEXIT=1 QUALITY="${QUALITY:-1}"
LOG="$(mktemp)"
tools/bot.sh res://tests/bot_visual_qa.gd "$OUT/_seq" 100000 1 | tee "$LOG" | grep "^VQA"
python3 - "$OUT" "$LOG" <<'PY'
import sys, os, re
from PIL import Image, ImageDraw
out, log = sys.argv[1], sys.argv[2]
res = [l.split() for l in open(log) if l.startswith("VQA ") and l.split()[2] in ("PASS", "FAIL")]
if not res:
    print("VQA_FAIL no spots were shot"); sys.exit(1)
W, H, cols = 427, 240, 4
rows = (len(res) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W, rows * H), (10, 10, 14))
d = ImageDraw.Draw(sheet)
for i, r in enumerate(res):
    p = os.path.join(out, r[1] + ".png")
    if os.path.exists(p):
        sheet.paste(Image.open(p).convert("RGB").resize((W, H)), ((i % cols) * W, (i // cols) * H))
    d.text(((i % cols) * W + 6, (i // cols) * H + 4), "%s %s" % (r[1], r[2]), fill=(255, 80, 80) if r[2] == "FAIL" else (120, 255, 160))
sheet.save(os.path.join(out, "latest.png"))
bad = [r[1] for r in res if r[2] == "FAIL"]
print("VQA_SUMMARY %d/%d pass%s" % (len(res) - len(bad), len(res), (" FAIL: " + ",".join(bad)) if bad else ""))
sys.exit(1 if bad else 0)
PY
