#!/usr/bin/env bash
# TrafficAudit bot (owner round 6, "cars go inside other cars"): drives a real car through the city and out along the highways at 4x speed for AUDIT_SECS game seconds (default 300) and
# fails when any two vehicle hulls (real cars, near traffic, road traffic, bridge cars, parked cars, wrecks) stay interpenetrated for more than 0.3 s.
#   tools/traffic_audit.sh                    five minutes, half in the city, half on the highways
#   AUDIT_SECS=90 AUDIT_CITY_SHARE=1 tools/traffic_audit.sh      a short city-only run
# Environment: AUDIT_SECS, AUDIT_CITY_SHARE (0..1), AUDIT_SEED, AUDIT_QUALITY (0 LOW, 1 MED, 2 HIGH). Run from godot/ after tools/import.sh. Prints the report; exit code 0 = no violation.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
timeout 1500 "$BIN" --headless --path . res://tests/runner.tscn -- --test="res://tests/traffic_audit.gd" --timeout=1400 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|Leaked instance\|at: ~Dependency\|RID alloc\|ObjectDB\|resources still\|at: clear\|at: cleanup\|material_get_instance_shader\|Parameter \"material\" is null"
exit "${PIPESTATUS[0]}"
