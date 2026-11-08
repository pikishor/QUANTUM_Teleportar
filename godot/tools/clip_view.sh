#!/usr/bin/env bash
# Captured clip look-dev: the hero pinned to evenly spaced frames of each clip (HeroClips.force), side camera contact sheets <OUT>/clip_<name>.png. Real renderer.
#   tools/clip_view.sh OUT_DIR [WxH]      env: CLIPS=jump_start,jump_loop  CLIP_FRAMES=14
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
OUT="$(realpath -m "$1")"; RES="${2:-844x390}"
mkdir -p "$OUT"
timeout ${LOCO_TIMEOUT:-900} xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "$RES" --path . res://tests/runner.tscn -- --timeout=800 --test=res://tests/clip_viewer.gd --out="$OUT" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
