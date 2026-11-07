#!/usr/bin/env bash
# The mission audit (owner round 3: "gets stuck in a task"): a bot plays the real game WITHOUT the runner's skip and reports where a task does not progress.
#   tools/mission_audit.sh            chapters 1-4, the sandbox step kinds + structure of every mission system, and all twenty side missions
#   AUDIT_VERBOSE=1 tools/mission_audit.sh   also prints every finding as it happens and the walking / chase / boss traces
#   AUDIT_FROM=3:3 tools/test.sh tests/test_mission_audit.gd   one chapter from one step (1-based), for debugging a finding
# Output goes to the terminal and to docs/shots/slice/mission_audit.txt (filtered of the headless renderer's known noise).
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="../docs/shots/slice/mission_audit.txt"
FILTER='Leaked\|at: ~Dep\|RID alloc\|ObjectDB\|at: cleanup\|FSR1\|viewport_set\|GDScript backtrace\|^ *\[[0-9]*\] \|PagedAlloc\|paged_alloc\|Parameter "material" is null\|material_get_instance_shader'
: > "$OUT"
rc=0
for t in tests/test_mission_audit.gd tests/test_mission_audit_kinds.gd tests/bot_mission_audit_sides.gd; do
  echo "=== $t" | tee -a "$OUT"
  tools/test.sh "$t" 2>&1 | grep -v "$FILTER" | grep -v '^WALK\|^CHASE\|^CONVOY\|^ESCAPE\|^ESCORT\|^BOSS\|^SIDEDBG' | tee -a "$OUT"
  [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
done
exit $rc
