#!/usr/bin/env bash
# Look-dev lineup of the Cars v2 set on a wet floor (software Vulkan). From godot/:
#   VIEW_RES=2400x1080 tools/carv2_lineup.sh /tmp/prefix kinds=sedan,sport view=front3q q=0 lod=0
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
timeout 280 xvfb-run -a -s "-screen 0 ${VIEW_RES:-1600x720}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution ${VIEW_RES:-1600x720} --path . res://tests/carv2_lineup.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID\|audio_server\|^ERROR: Condition \"status" || true
