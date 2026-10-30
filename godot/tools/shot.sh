#!/usr/bin/env bash
# Render with software GL under a virtual display and save a screenshot (--headless cannot render).
#   tools/shot.sh out.png [res://scenes/main.tscn] [frames]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$(realpath -m "$1")"; SCENE="${2:-res://scenes/main.tscn}"; FRAMES="${3:-30}"
timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1280x720 --path . "$SCENE" -- --shot="$OUT" --frames="$FRAMES" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
