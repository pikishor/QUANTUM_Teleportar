#!/usr/bin/env bash
# Bakes the hero portraits (wave 112): renders the default hero (bust) and the six suits (waist) through HeroShowcase under software Vulkan and writes assets/ui/hero_portrait.webp and
# assets/ui/hero_suit_<id>.webp. From godot/:  tools/hero/bake_portraits.sh [extra args: yaw=0.5 suits=standard,flight kind=bust look=female:light:long:0:flight:3 out=/tmp/x]
# With look= or out= the PNGs stay in the output dir and nothing is converted. Needs pillow for the WebP conversion (.venv-tools).
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
OUT="/tmp/hero_portraits_$$"
CONVERT=1
for a in "$@"; do
  case "$a" in out=*) OUT="${a#out=}"; CONVERT=0;; look=*) CONVERT=0;; esac
done
RES="${STAGE_RES:-456x720}"
timeout 300 xvfb-run -a -s "-screen 0 ${RES}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution "$RES" --path . res://tests/hero_portrait_bake.tscn -- out="$OUT" "$@" 2>&1 \
  | grep -E "^BAKE|SCRIPT ERROR|ERROR:" | head -30
if [ "$CONVERT" = "1" ]; then
  .venv-tools/bin/python - "$OUT" <<'PY'
import os, sys
from PIL import Image
src = sys.argv[1]
dst = os.path.join("assets", "ui")
os.makedirs(dst, exist_ok=True)
for f in sorted(os.listdir(src)):
    if f.endswith(".png"):
        im = Image.open(os.path.join(src, f)).convert("RGB")
        out = os.path.join(dst, f[:-4] + ".webp")
        im.save(out, "WEBP", quality=82, method=6)
        print("wrote", out, im.size, os.path.getsize(out) // 1024, "KB")
PY
  rm -rf "$OUT"
fi
