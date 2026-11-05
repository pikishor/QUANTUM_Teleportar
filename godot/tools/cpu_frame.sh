#!/usr/bin/env bash
# CPU frame time of the real main scene per tier, and where it goes per system (PerfTimers table). Default: headless (dummy renderer = script + physics only).
#   tools/cpu_frame.sh [tiers]       default "0 1 2";  CPU_LOWPLUS=1 tools/cpu_frame.sh 0   measures LOW+
#   env CPU_FRAMES=n (default 240)   CPU_ENEMIES=n (default 4)   CPU_NOTHROTTLE=1  HUD / touch / minimap redraw every frame (the numbers before the redraw limits)
#   env CPU_RENDER=1                 real software renderer under xvfb (llvmpipe: the frame time then includes the fragment work, a proxy for a fill-rate bound phone GPU)
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
for q in ${*:-0 1 2}; do
  if [ -n "${CPU_RENDER:-}" ]; then
    CPU_TIER="$q" timeout "${CPU_TIMEOUT:-400}" xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --fixed-fps 30 --resolution "${CPU_RES:-1280x576}" --path . res://tests/runner.tscn -- --test=res://tests/cpu_probe.gd --timeout=380 --quality="$q" ${CPU_LOWPLUS:+--low-plus} 2>&1 | grep -E "^CPU|^  [A-Z]|SCRIPT ERROR"
  else
    CPU_TIER="$q" timeout "${CPU_TIMEOUT:-300}" "$BIN" --headless --fixed-fps 30 --path . res://tests/runner.tscn -- --test=res://tests/cpu_probe.gd --timeout=280 --quality="$q" 2>&1 | grep -E "^CPU|^  [A-Z]|SCRIPT ERROR"
  fi
done
