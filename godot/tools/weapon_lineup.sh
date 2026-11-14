#!/usr/bin/env bash
# Lineup of weapon models (software Vulkan under xvfb): tools/weapon_lineup.sh /tmp/prefix batch=0 per=40 cols=8 view=side lod=0 [ids=a,b,c] [res=2400x1350]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
RES="2400x1350"
ARGS=()
for a in "$@"; do if [[ "$a" == res=* ]]; then RES="${a#res=}"; else ARGS+=("$a"); fi; done
W="${RES%x*}"; H="${RES#*x}"
timeout 300 xvfb-run -a -s "-screen 0 ${W}x${H}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution "${W}x${H}" --path . res://tests/weapon_lineup.tscn -- out="$OUT" "${ARGS[@]}" 2>&1 | grep -E "LINEUP|SCRIPT ERROR|SHADER ERROR|ERROR: .*(shader|Shader)|Parse Error|^E " || true
