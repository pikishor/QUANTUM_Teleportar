#!/usr/bin/env bash
# Render check of the citizen animation states and silhouettes under software GL (see tests/bot_citizen_states.gd).
#   tools/citizen_check.sh            Vulkan Mobile on software Vulkan;  RENDERER=compat for the Compatibility renderer;  QT_SAVE=/tmp/prefix saves the captures
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --resolution 1280x720 --path . res://tests/bot_citizen_states.tscn 2>&1 \
  | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|status < 0\|init_output_device\|initialize (servers" || true
