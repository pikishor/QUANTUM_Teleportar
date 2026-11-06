#!/usr/bin/env bash
# Look-dev viewer of the cars on a plain floor (software Vulkan). From godot/:  tools/vehicle_view.sh /tmp/prefix kinds=sedan,sport views=front3q,side damage=0,0.6
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
timeout 280 xvfb-run -a -s "-screen 0 ${VIEW_RES:-1280x720}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution ${VIEW_RES:-1280x720} --path . res://tests/vehicle_viewer.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID" || true
