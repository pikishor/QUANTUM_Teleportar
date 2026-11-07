#!/usr/bin/env bash
# Run a bot script that drives the game through input actions, saving a screenshot sequence under software GL.
# QUALITY=0|1|2 picks the graphics tier (the auto-quality governor is off in tools runs, so the shots show that tier).
# BOT_USER_ARGS adds game flags after `--` (BOT_USER_ARGS="--touch" draws the phone HUD).
# ENGINE_ARGS adds engine flags (for example ENGINE_ARGS="--fixed-fps 12" gives deterministic game seconds per frame).
#   tools/bot.sh res://tests/bot_walk.gd /tmp/out_prefix [every_frames] [count]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
# RENDERER=mobile (default: Vulkan Mobile renderer on software Vulkan) or RENDERER=compat (OpenGL Compatibility renderer)
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
BOT="$1"; PREFIX="$(realpath -m "$2")"; EVERY="${3:-30}"; COUNT="${4:-5}"
timeout "${BOT_TIMEOUT:-300}" xvfb-run -a -s "-screen 0 ${BOT_RES:-1280x720}x24" "$BIN" $RENDER_ARGS \
  ${ENGINE_ARGS:-} --resolution ${BOT_RES:-1280x720} --path . res://scenes/main.tscn -- --bot="$BOT" --shot-seq="$PREFIX" --every="$EVERY" --count="$COUNT" ${BOT_USER_ARGS:-} ${QUALITY:+--quality=$QUALITY} 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
