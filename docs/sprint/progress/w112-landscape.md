# w112-landscape (builder notes; started 2026-11-12 ~21:00Z)

GOAL: landscape pass for round 6: 6+ tree species by biome with 3 LODs + impostors in MultiMesh chunks (zero per-tree nodes), undergrowth, waterfalls,
shorelines (wet sand, foam, shallow-to-deep ramp), mountain detail, tall anchors (turbines, masts, pylons, cranes), 3+ grass airstrips, wind + rain-wet.

DONE
- (nothing yet) read ROUND6, DESIGN, WORLD_EXPANSION, ARCHITECTURE terrain / water / vegetation sections.

NEXT
1. Read veg_kit / veg_scatter / vegetation_world / vegetation.gdshader / water shaders; render baseline frames (coast, forest road, mountain pass) at LOW + MED.
2. Defect list vs docs/owner_shots/round5; fix in render-look-fix loops (>= 6).
3. New files only for new systems (scripts/landscape/*), one hook line in shared tables.
4. test_landscape_dressing.gd; perf gate PERF_CHECK=1 tools/perf_report.sh 0 1 2; contact sheet docs/shots/round6/landscape_before_after.jpg.

DECISIONS (APIs other agents depend on)
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- disk: only ~4.0 GB free at start; keep scratch frames in the scratchpad and delete after contact sheets.
