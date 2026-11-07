#!/usr/bin/env bash
# Render-glitch scan at the phone resolution (2400x1080 by default): real game camera, touch HUD on, the places where the owner saw translucent slabs / white sheets.
# For every spot it saves the frame, and with LAYERS=1 (default) hides every translucent family (shader or transparent material) one at a time and prints
# `LAYER <spot> <family> frac=.. rect=.. slab` for the ones that add a big flat patch (VisualQaLib.translucent_slabs on the frame with and without the layer).
#   tools/glitch_scan.sh OUT_DIR [spots=street_12,street_21,int_apartment,burst,tp_1] [QUALITY=0|1|2]
# Spots: street_<hour>, int_<type>, hero_back, hero_side, burst (hit burst + fireball puffs at the lens), tp_<n> (teleport, n frames after), beacon; `name#2` repeats a spot.
# Env: GLITCH_MIN (smallest frac printed, 0.004), GLITCH_HIDE=a,b (hide nodes by path / shader name), BOT_RES.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(realpath -m "$1")"; mkdir -p "$OUT"
SPOTS="${2:-street_12,street_21,int_apartment,int_checkpoint,int_server_room,int_tech,burst,tp_1,tp_4}"
GLITCH_OUT="$OUT" GLITCH_SPOTS="$SPOTS" GLITCH_LAYERS="${LAYERS:-1}" BOT_RES="${BOT_RES:-2400x1080}" QUALITY="${QUALITY:-0}" BOT_FASTEXIT=1 BOT_TIMEOUT="${BOT_TIMEOUT:-900}" \
  tools/bot.sh res://tests/bot_glitch_scan.gd "$OUT/x" 100000 1 2>&1 | grep -E "LAYER|GLITCH|NEAR|NOHUD|SCRIPT ERROR|Parse Error" || true
python3 tools/contact_sheet.py "$OUT/sheet.png" 3 "$OUT/*.png" 0.5 2>/dev/null || true
