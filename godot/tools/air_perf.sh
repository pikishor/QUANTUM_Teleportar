#!/usr/bin/env bash
# Wave 129: the AIRFIELD draw budget (tests/test_airfield_perf_w129.gd) under a real renderer: on foot at the heli line, plane line, gates, hangars and army base, boarded by
# real fingers in a fighter, a helicopter, a tank with 8 more tanks in view, and flying over the outskirts. One process per tier (software Vulkan under xvfb, Mobile renderer).
#   tools/air_perf.sh [tiers]       default "0 1 2"; "lp" = LOW+.  Exit 1 when a view is over the tier's PerfProbe budget (or the test did not finish).
#   env  W129A_OLD=1  the old airfield code;  AIR_VIEWS=foot_heli,tank9  a subset
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
status=0
for q in ${*:-0 1 2}; do
  qa="--quality=$q"; if [ "$q" = "lp" ]; then qa="--quality=0 --low-plus"; fi
  out="$(timeout "${AIR_TIMEOUT:-600}" xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --fixed-fps 30 --resolution 1200x540 \
    --path . res://tests/runner.tscn -- --test=res://tests/test_airfield_perf_w129.gd --timeout=560 $qa 2>&1)"
  echo "$out" | grep -E "^AIR VIEW|^ok:|FAIL|^RESULT|SCRIPT ERROR|NOTE" | sed "s/^/tier $q: /"
  echo "$out" | grep -q "^RESULT: PASS" || status=1
done
exit $status
