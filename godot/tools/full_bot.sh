#!/usr/bin/env bash
# Full-feature live bot (tests/bot_full_game.gd): plays the REAL game scene for ~8 simulated minutes and exercises every system of waves 21-45
# (abilities, weapons, cover, vehicles + garage, side missions, collectibles, events, activities, set pieces, stealth, weather, map, options, customisation, save / load).
# Same options and exit codes as tools/soak.sh.   tools/full_bot.sh [--minutes=8] [--seed=1] [--groups=quantum,weapons,...] [--render]
cd "$(dirname "$0")/.."
export SOAK_BOT=res://tests/bot_full_game.gd
has_minutes=0
for a in "$@"; do case "$a" in --minutes=*) has_minutes=1 ;; esac; done
if [ "$has_minutes" = 0 ]; then set -- --minutes=8 "$@"; fi
exec tools/soak.sh "$@"
