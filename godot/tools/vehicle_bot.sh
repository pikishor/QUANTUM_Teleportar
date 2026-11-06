#!/usr/bin/env bash
# Drive bot of the car model on the real city (phone camera): BOT_OUT=/tmp/vr/run [BOT_SET=drive|crash|damage] [BOT_RES=1200x540] [QUALITY=1] tools/vehicle_bot.sh
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
RES="${BOT_RES:-1200x540}"
timeout "${BOT_TIMEOUT:-500}" xvfb-run -a -s "-screen 0 ${RES}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile \
  --resolution ${RES} --path . res://scenes/main.tscn -- --bot=res://tests/bot_vehicle_realism.gd --touch ${QUALITY:+--quality=$QUALITY} 2>&1 | grep -E "VBOT|SCRIPT ERROR|Parse" | head -${BOT_LINES:-60} || true
