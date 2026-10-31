#!/usr/bin/env bash
# First-use frame-time probe (tests/bot_warm.gd): the longest frame after the first shot, enemy, blast, quantum effect and pause screen, relative to a steady frame, with and without the
# shader / material pre-warm (scripts/common/shader_warmup.gd, which main.gd runs behind the loading overlay). Software Vulkan compiles every new pipeline with LLVM, so a hitch shows up
# as a long frame there (a phone GPU driver stalls the same way, only shorter).
#   tools/warm_probe.sh [quality]        default MED (1); prints both runs and the comparison.   env RENDERER=compat, WARM_RES=960x540
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
Q="${1:-1}"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
for w in 0 1; do
  echo "== pre-warm WARM=$w"
  WARM=$w timeout "${WARM_TIMEOUT:-400}" xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "${WARM_RES:-960x540}" --path . res://scenes/main.tscn -- \
    --bot=res://tests/bot_warm.gd --quality="$Q" 2>&1 | grep -E "^WARM|SCRIPT ERROR"
done
