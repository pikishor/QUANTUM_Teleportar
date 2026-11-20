#!/usr/bin/env bash
# Wave 116: the view in the air, measured on rendered frames (tests/bot_w116_flight_view.gd). The real game at phone aspect, the phone HUD, real finger events: it flies, boosts, turns,
# hovers, gets a reward card, dives, lands, swings and zips, flies in the rain. At every shot the game is frozen and rendered again with one overlay layer hidden at a time; the pixels
# that change are that layer's. Prints FV COVER / FV VERDICT per shot; exit 1 when an in-air layer covers more than its limit of the central 60 % of the frame or of the crosshair disc.
#   tools/flight_view.sh [out_dir] [tiers]       default out ../docs/shots/round7/flight_view, tiers "0 1"
#   FV_OLD=1    the wave 115 look (wide wings, full speed lines, the full-screen reward card): the before frames      FV_SCENES=fly,swing,zip,rain   a subset
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="$(realpath -m "${1:-../docs/shots/round7/flight_view}")"
TIERS="${2:-0 1}"
bad=0
for q in $TIERS; do
  D="$OUT/$([ "$q" = 0 ] && echo low || ([ "$q" = 1 ] && echo med || echo high))${FV_OLD:+_old}"
  mkdir -p "$D"
  LOG="$D/log.txt"
  FV_OUT="$D" BOT_RES="${BOT_RES:-1200x540}" BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY="$q" BOT_TIMEOUT="${BOT_TIMEOUT:-580}" \
    tools/bot.sh res://tests/bot_w116_flight_view.gd "$D/seq" 100000 1 > "$LOG" 2>&1
  grep -E "^FV (COVER|VERDICT|DONE|BUTTON|CONDITION)|SCRIPT ERROR" "$LOG" | sed "s/^/tier $q: /"
  grep -q "^FV DONE" "$LOG" || { echo "tier $q: FV_FAIL the bot did not finish"; bad=1; }
  grep -q "^FV DONE shots [0-9]*  fails 0" "$LOG" || bad=1
done
exit $bad
