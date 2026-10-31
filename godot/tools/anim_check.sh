#!/usr/bin/env bash
# Deterministic animation check (tests/bot_animation.gd): hero and trooper in the real city, every frame exactly 1/30 game second (--fixed-fps).
# Prints the mesh tree, the foot slide per stride and the pelvis / knee ranges, and saves side-camera pictures.
#   tools/anim_check.sh OUT_PREFIX [WxH]       env: RENDERER=compat, BOT_ONLY=walk,jump,...
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
PREFIX="$(realpath -m "$1")"; RES="${2:-640x360}"
mkdir -p "$(dirname "$PREFIX")"
timeout ${ANIM_TIMEOUT:-900} xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "$RES" --path . res://scenes/main.tscn -- \
  --bot=res://tests/bot_animation.gd --out="$PREFIX" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
