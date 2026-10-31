#!/usr/bin/env bash
# Deterministic VFX / enemy picture run (tests/bot_vfx_check.gd): every frame is exactly 1/30 game second (--fixed-fps), so pictures show fixed effect ages
# even under slow software rendering.   tools/vfx_check.sh OUT_PREFIX [WxH] [quality 0-2]     env: BOT_SET=vfx|enemies|all, BOT_STATS=1, RENDERER=compat
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
PREFIX="$(realpath -m "$1")"; RES="${2:-960x432}"; Q="${3:-1}"
mkdir -p "$(dirname "$PREFIX")"
timeout ${VFX_TIMEOUT:-420} xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "$RES" --path . res://scenes/main.tscn -- \
  --bot=res://tests/bot_vfx_check.gd --out="$PREFIX" --quality="$Q" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
