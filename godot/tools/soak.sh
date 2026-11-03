#!/usr/bin/env bash
# Long-running QA soak: plays the real game for simulated minutes (drive, shoot, interiors, tiers, pause, death, new games) and fails on leaks or errors.
# Full description and thresholds: docs/QA.md.
#   tools/soak.sh                          10 simulated minutes, headless (dummy renderer: fast; texture / video memory read 0 and are not judged)
#   tools/soak.sh --render                 the same under software Vulkan + xvfb (texture / video memory judged; slow: use fewer minutes)
#   tools/soak.sh --minutes=3 --seed=7     any bot option: --minutes --seed --speed --scale --quality --no-reset --cycles --quiet
#   tools/soak.sh --monkey                 the seeded random-input monkey instead (tests/bot_monkey.gd): touch, buttons, menus; must never crash or soft lock
#   tools/soak.sh --real ...               (both bots) cutscenes, scripted campaign and tutorial on, like a player's first run (off in tools by default)
# Env: SOAK_TIMEOUT=seconds (real-time cap, default 3600).  RENDER_RES=640x360 and SOAK_FPS=12 (render mode: software Vulkan runs at a few real frames a second, so
# 3 simulated minutes take about 10 real ones: use --minutes=1.5 --scale=0.4 there).  Exit code 0 = PASS, 1 = FAIL, 124 = timed out.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
BOT="${SOAK_BOT:-res://tests/bot_soak.gd}"
RENDER=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --render) RENDER=1 ;;
    --monkey) BOT=res://tests/bot_monkey.gd ;;
    *) ARGS+=("$a") ;;
  esac
done
if [ "$BOT" = "res://tests/bot_monkey.gd" ]; then ARGS+=("--touch"); fi
LOG="$(mktemp "${TMPDIR:-/tmp}/soak.XXXXXX.log")"
ID="soak-$$"
# watcher: a bot script that does not compile never reports, and the game would just run until the timeout: stop it as soon as the log says so
( while sleep 3; do
    if grep -q "Failed to load script\|Cannot load bot\|Nonexistent function 'new'" "$LOG" 2>/dev/null; then echo "SOAK: the bot script did not load (see the errors above)"; pkill -f -- "--soak-id=$ID"; break; fi
  done ) &
WATCH=$!
trap 'kill $WATCH 2>/dev/null; rm -f "$LOG"' EXIT
if [ "$RENDER" = 1 ]; then
  # --fixed-fps: every rendered frame is exactly 1/N s of game time however slow the software renderer is; speed 1 (no time scale), 5 physics ticks per frame at 12 fps
  FPS="${SOAK_FPS:-12}"
  timeout "${SOAK_TIMEOUT:-3600}" xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --fixed-fps "$FPS" \
    --resolution "${RENDER_RES:-640x360}" --path . res://scenes/main.tscn -- --soak-id="$ID" --bot="$BOT" --speed=1 --quality="${QUALITY:-0}" ${ARGS[@]+"${ARGS[@]}"} 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" | tee "$LOG"
else
  timeout "${SOAK_TIMEOUT:-3600}" "$BIN" --headless --path . res://scenes/main.tscn -- --soak-id="$ID" --bot="$BOT" ${ARGS[@]+"${ARGS[@]}"} 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver" | tee "$LOG"
fi
code="${PIPESTATUS[0]}"
# exit-time engine noise ("RID allocations ... leaked at exit", dummy renderer pages) is not a game error; a SCRIPT ERROR or an ERROR before the result line is
if [ "$code" = 124 ]; then echo "SOAK TIMED OUT after ${SOAK_TIMEOUT:-3600} s"; exit 124; fi
if ! grep -q "RESULT verdict=" "$LOG"; then echo "SOAK: no RESULT line (the game crashed or exited early, exit code $code)"; exit 1; fi
if grep -q "RESULT verdict=PASS" "$LOG" && ! grep -q "SCRIPT ERROR" "$LOG"; then exit 0; fi
exit 1
