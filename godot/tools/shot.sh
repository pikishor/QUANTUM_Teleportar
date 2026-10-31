#!/usr/bin/env bash
# Render with software GL under a virtual display and save a screenshot (--headless cannot render).
#   tools/shot.sh out.png [res://scenes/main.tscn] [frames]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
# RENDERER=mobile (default: Vulkan Mobile renderer on software Vulkan) or RENDERER=compat (OpenGL Compatibility renderer)
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
OUT="$(realpath -m "$1")"; SCENE="${2:-res://scenes/main.tscn}"; FRAMES="${3:-30}"
timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS \
  --resolution 1280x720 --path . "$SCENE" -- --shot="$OUT" --frames="$FRAMES" ${QUALITY:+--quality=$QUALITY} 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
