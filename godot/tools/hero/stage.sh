#!/usr/bin/env bash
# Hero look-dev stage at phone aspect (software Vulkan, no city): tools/hero/stage.sh OUT_PREFIX views=game,back,front suit=assault pose=run glow=flow:1.5:00e5ff light=dusk q=1
# Writes OUT_PREFIX_<view>.png (1600x720 by default; STAGE_RES=2400x1080 for the real phone size). RENDERER=compat renders with the OpenGL Compatibility renderer.
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
RES="${STAGE_RES:-1600x720}"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
timeout 240 xvfb-run -a -s "-screen 0 ${RES}x24" "$BIN" $RENDER_ARGS --resolution "$RES" --path . res://tests/hero_stage.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|status < 0\|     at:" || true
