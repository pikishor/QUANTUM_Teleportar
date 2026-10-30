#!/usr/bin/env bash
# Run a bot script that drives the game through input actions, saving a screenshot sequence under software GL.
#   tools/bot.sh res://tests/bot_walk.gd /tmp/out_prefix [every_frames] [count]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
# RENDERER=mobile (default: Vulkan Mobile renderer on software Vulkan) or RENDERER=compat (OpenGL Compatibility renderer)
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
BOT="$1"; PREFIX="$(realpath -m "$2")"; EVERY="${3:-30}"; COUNT="${4:-5}"
timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS \
  --resolution 1280x720 --path . res://scenes/main.tscn -- --bot="$BOT" --shot-seq="$PREFIX" --every="$EVERY" --count="$COUNT" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
