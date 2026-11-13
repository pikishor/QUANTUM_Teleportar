#!/usr/bin/env bash
# Look-dev viewer of a town on a flat pad (software Vulkan). From godot/:  tools/settlement_view.sh /tmp/prefix style=farm views=aerial,street,house q=1 hour=12
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
timeout 280 xvfb-run -a -s "-screen 0 ${VIEW_RES:-1600x720}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution ${VIEW_RES:-1600x720} --path . res://tests/settlement_viewer.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID" || true
