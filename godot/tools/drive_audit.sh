#!/usr/bin/env bash
# DriveAudit bot (wave 112 critic): drives a real car along every road of the world end to end with the phone's own inputs and reports stuck spots, wrecks, script errors and frame times.
#   tools/drive_audit.sh                      all roads at 3x speed
#   DA_ROADS="PASS ROAD,RING ROAD" DA_K=1 DA_MAXLEN=1500 tools/drive_audit.sh     two roads in real time, the first 1500 m
# Environment: DA_ROADS, DA_K, DA_MAXLEN, DA_QUALITY (0 LOW, 1 MED, 2 HIGH), DA_SEED, DA_REVERSE=1. Run from godot/ after tools/import.sh. Exit code 0 = every road drivable.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
timeout 1500 "$BIN" --headless --path . res://tests/runner.tscn -- --test="res://tests/drive_audit.gd" --timeout=1400 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|Leaked instance\|at: ~Dependency\|RID alloc\|ObjectDB\|resources still\|at: clear\|at: cleanup\|material_get_instance_shader\|Parameter \"material\" is null"
exit "${PIPESTATUS[0]}"
