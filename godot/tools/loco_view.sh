#!/usr/bin/env bash
# Hero locomotion look-dev: contact sheets (every 2nd frame for 2 s, game camera and side camera) of idle / walk / jog / run / sprint / strafe / back / turn / stop / jump / slope,
# plus the LocoQA numbers (foot slide, cadence, bob). Real renderer, fixed 30 fps.
#   tools/loco_view.sh OUT_DIR [WxH]      env: LOCO_CASES=walk,run  LOCO_EVERY=2  LOCO_SECS=2  RENDERER=compat
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
OUT="$(realpath -m "$1")"; RES="${2:-844x390}"
mkdir -p "$OUT"
timeout ${LOCO_TIMEOUT:-900} xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "$RES" --path . res://tests/runner.tscn -- --timeout=800 --test=res://tests/loco_viewer.gd --out="$OUT" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
