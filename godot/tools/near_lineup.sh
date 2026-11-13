#!/usr/bin/env bash
# Look-dev lineup of the near traffic cars (MultiMesh HI / LO meshes with the real shaders), software Vulkan. From godot/:
#   VIEW_RES=2400x1080 tools/near_lineup.sh /tmp/prefix mesh=hi view=chase dist=9 night=0 wet=0 q=1
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
timeout 280 xvfb-run -a -s "-screen 0 ${VIEW_RES:-1600x720}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution ${VIEW_RES:-1600x720} --path . res://tests/near_lineup.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID\|audio_server\|^ERROR: Condition \"status" || true
