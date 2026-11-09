#!/usr/bin/env bash
# Look-dev viewer of the wildlife with the real shader and clips (software Vulkan). From godot/:
#   tools/wildlife_view.sh /tmp/prefix species=deer,wolf pose=walk views=side,3q [night=1] [dist=9] [h=1.2] [t=0.5 with pose=dissolve]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
timeout 200 xvfb-run -a -s "-screen 0 ${VIEW_RES:-1600x700}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution ${VIEW_RES:-1600x700} --path . res://tests/wildlife_viewer.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID" || true
