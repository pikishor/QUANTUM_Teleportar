#!/usr/bin/env bash
# Performance report of the staged full-game view (hero + 4 enemies + the starter car + HUD) per graphics tier, with the real main scene and the auto-quality
# governor off (tools): visible and total (with shadow passes) draw calls and triangles, node count, texture memory, the canvas draws of the HUD, and the worst
# frame of the 4-enemy simultaneous death. Software Vulkan under xvfb (numbers of draws / triangles are the same as on a phone, frame times are not).
#   tools/perf_report.sh [tiers]            default "0 1 2"; e.g. tools/perf_report.sh 1
#   env  RENDERER=compat   OpenGL Compatibility renderer;   BOT_TOUCH=1   touch layout;   BOT_DUMP=1   biggest shadow casters;   BOT_FAR=1   enemies at 55 m
#   env  PERF_SEED=n       world seed of the bot (default 20260101: props, traffic and drops differ per seed)
#   env  PERF_CHECK=1      exit status 1 when a tier is over its budget (scripts/common/perf_probe.gd BUDGETS): this is the budget gate
#   env  PERF_RES=1280x720 resolution (draw counts hardly depend on it);   PERF_SHOTS=/path/prefix  also saves the pictures of frames 30 / 60 / 90 (staged view, hud off, death)
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
TIERS="${*:-0 1 2}"
if [ "${RENDERER:-mobile}" = "compat" ]; then RENDER_ARGS="--rendering-driver opengl3 --rendering-method gl_compatibility"; else RENDER_ARGS="--rendering-driver vulkan --rendering-method mobile"; fi
status=0
for q in $TIERS; do
  out="$(timeout "${PERF_TIMEOUT:-420}" xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" $RENDER_ARGS --fixed-fps 30 --resolution "${PERF_RES:-1280x720}" --path . res://scenes/main.tscn -- \
    --bot=res://tests/bot_perf.gd --quality="$q" ${PERF_HIGHTEX:+--high-textures} ${PERF_SHOTS:+--shot-seq="${PERF_SHOTS}_q$q" --every=30 --count=3} 2>&1 | grep -E "^PERF|SCRIPT ERROR|^SHOT_SAVED|^ERROR: .*(shader|Shader)" )"
  echo "$out"
  echo "$out" | grep -q "^PERF RESULT" || { echo "PERF RESULT tier=$q verdict=NO_RESULT (the bot did not finish)"; status=1; }
  echo "$out" | grep -q "verdict=OVER" && status=1
done
if [ -n "${PERF_CHECK:-}" ]; then exit $status; fi
exit 0
