#!/usr/bin/env bash
# Headless economy simulation: credits per hour vs cumulative gear cost.
set -euo pipefail
cd "$(dirname "$0")/.."
exec tools/test.sh tests/economy_sim.gd
