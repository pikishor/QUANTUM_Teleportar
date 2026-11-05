#!/usr/bin/env bash
# Full balance tables (weapons, ttk, survival, bosses, abilities, skill tree, factions, companion, HeroPower) from the headless runner.
set -euo pipefail
cd "$(dirname "$0")/.."
exec tools/test.sh tests/balance_sim.gd
