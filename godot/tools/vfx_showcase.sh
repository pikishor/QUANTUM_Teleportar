#!/usr/bin/env bash
# Render every quantum VFX at fixed game ages on a dark street (tests/vfx_showcase.tscn, --fixed-fps 30).
#   tools/vfx_showcase.sh OUT_PREFIX [WxH] [quality 0-2]      env: VFX_ONLY=teleport,beam  VFX_AGES=0.12,0.3,0.6  RENDERER=compat
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
PREFIX="$(realpath -m "$1")"; RES="${2:-640x360}"; Q="${3:-1}"
mkdir -p "$(dirname "$PREFIX")"
timeout ${VFX_TIMEOUT:-300} xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "$RES" --path . res://tests/vfx_showcase.tscn -- --out="$PREFIX" --q="$Q" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
