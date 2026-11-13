#!/usr/bin/env bash
# RoadClearanceAudit (wave 112 critic): moves the hero along every road of the world and tests a car-sized box against every static body in three lanes: prints the runs of road a car cannot pass and what blocks them.
#   tools/road_audit.sh                       the whole world (about 5 minutes)
#   RC_ROADS="9,10" RC_STEP=100 tools/road_audit.sh      two roads (index into TerrainRoads.DEFS), a stop every 100 m
# Run from godot/ after tools/import.sh. Exit code 0 = nothing stands in any road.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
timeout 1500 "$BIN" --headless --path . res://tests/runner.tscn -- --test="res://tests/road_clearance_audit.gd" --timeout=1400 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|Leaked instance\|at: ~Dependency\|RID alloc\|ObjectDB\|resources still\|at: clear\|at: cleanup\|material_get_instance_shader\|Parameter \"material\" is null"
exit "${PIPESTATUS[0]}"
