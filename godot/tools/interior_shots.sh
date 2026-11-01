#!/usr/bin/env bash
# Screenshots of one generated interior (software GL under xvfb): a camera flies through six poses, or with HERO=1 the real player stands at six spots.
#   tools/interior_shots.sh club 3 /tmp/prefix [quality 0-2] [every frames]      (RENDERER=compat for OpenGL, HERO=1 for the third-person view)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
TYPE="${1:-club}"; SEED="${2:-1}"; PREFIX="$(realpath -m "$3")"; Q="${4:-1}"; EVERY="${5:-8}"
timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --resolution 1280x720 --path . res://scenes/interiors/interior_view.tscn -- \
  --interior="$TYPE" --seed="$SEED" --quality="$Q" --every="$EVERY" --count=6 --shot-seq="$PREFIX" ${HERO:+--hero} 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" || true
