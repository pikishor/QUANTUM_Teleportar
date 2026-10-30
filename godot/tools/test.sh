#!/usr/bin/env bash
# Run a headless GDScript test (a script with `func run(host: Node)`). Exit code 0 = pass.
#   tools/test.sh tests/test_smoke.gd
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
timeout 150 "$BIN" --headless --path . res://tests/runner.tscn -- --test="res://$1" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver"
exit "${PIPESTATUS[0]}"
