# w112-outskirts-map (builder notes; started 2026-11-13 ~09:15Z)

GOAL: outskirts settlements + a bigger map: 7 settlements of different character (farming village, fishing harbour town, mountain lodge hamlet, industrial/mining site,
desert outpost, suburban estates, resort/lake town) with 20-80 houses each, gardens, fences, parked cars, shops, churches, farms, interiors (15+ layouts), NPCs, pets,
livestock, mission hooks, 2+ tall snake anchors each, helipad where it fits, traffic from wave 111; world at least 2x playable area, road network with highways,
ring road, bridges, tunnels; map/minimap/GPS/route planner/fast travel limits updated.

STATE AT START: previous agent with this label did nothing (hit weekly limit). Parallel builder w112-landscape edits terrain/veg/landscape files (do not touch).

DONE
- (nothing yet; reading docs and code)

NEXT
1. read HANDOFF follow-ups, ARCHITECTURE sections (terrain world, outskirts sites, roads, traffic, interiors), existing OutskirtsSites code and tests
2. baseline renders of existing sites (LOW + MED), defect list
3. design settlement kit + data table, interior layouts, NPC/pet/livestock, hooks, map integration

DECISIONS (APIs other agents depend on)
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- disk: 6.3 GB free at start (keep >= 4 GB)
