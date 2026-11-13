# w112-outskirts-map (builder notes; started 2026-11-13 ~09:15Z, updated ~10:10Z)

GOAL: outskirts settlements + a bigger map: 7 settlements of different character (farming village, fishing harbour town, mountain lodge hamlet, industrial/mining site,
desert outpost, suburban estates, resort/lake town) with 20-80 houses each, gardens, fences, parked cars, shops, churches, farms, interiors (15+ layouts), NPCs, pets,
livestock, mission hooks, 2+ tall snake anchors each, helipad where it fits, traffic from wave 111; world at least 2x playable area, road network with highways,
ring road, bridges, tunnels; map/minimap/GPS/route planner/fast travel limits updated.

STATE AT START: previous agent with this label did nothing (hit weekly limit). Parallel builder w112-landscape edits terrain/veg/landscape files (do not touch beyond one-line hooks).
Baseline frames (scratchpad outskirts/base): DUST WELLS = cuboid mud houses, flat dark walls, giant plain sand street, no fences/gardens/people; PINE HOLLOW = plain log boxes, huge dirt street.

DESIGN DECISIONS (read before touching)
1. World = 9 km square: TerrainHeight.WORLD_HALF 4500, CityLayout.PLAY_HALF 4460. Land grows N/E/W only (WorldExtent.coast_push added in TerrainHeight.coast_distance; S/SE/SW coast,
   harbour, ships, airport unchanged). Land 16 -> ~30 km2, area x2.25. TerrainMap RES 768, WATER_N 192, shore map MAP_CELLS 192, MapScreen.WORLD_ZOOM 0.24, SILVER MERE lake (WaterLayout.LAKES).
2. Towns = NEW ENTRIES OF OutskirtsSites (kind &"town", data scripts/settlements/settlement_defs.gd, appended in OutskirtsSites.ensure). Pad = ellipse (r across, len along the street,
   OutskirtsSites._pad_d), road profiles inside it levelled (TerrainRoads.level_profile), pad leaves the land near the road centre alone in the blend zone. Map pin = kind site + glyph town.
3. Roads: scripts/settlements/settlement_roads.gd (RING ROAD, WEST HIGHWAY, COAST LINK, WEST COAST ROAD, LARK ROAD, OUTPOST ROAD, SHORE TRACK) appended to TerrainRoads.DEFS (const CORE_DEFS + extra);
   TerrainRoads got `end_on`, `slack`, `level_profile`; OutskirtsSites.keep_clear makes the router avoid free-standing pads. A town stands ON its road (main street = the road, RoadTraffic cars).
4. Doors: town doors appended to Game.world.doors (ids >= 100000), country interior types in a separate table (hooks in InteriorKinds / InteriorData: the original TYPES arrays stay 16: 6 tests pin it).
5. Anchors for quantum snakes: SettlementAnchors.all_anchors() in the AnchorSites format {id, kind, name, pos (top), base, height, radius}.
6. People: reuse the crowd mesh + shader (AmbientCrowd._person_meshes, prop_crowd.gdshader) in own MultiMesh, shootable through a hook in AmbientCity.civilian_ray (planned).

DONE
- WorldExtent + world size + map/shore constants + lake + 7 roads + 7 town defs (positions resolved; all roads <= their grade limit, bench = profile, test_terrain_world PASS)
- tests edited with reasons: test_terrain_world (world size 9 km, step 9 m, far tiles <= 90, shore search, WORLD view), test_outskirts_sites (counts + towns)
- dev tools: tests/dev_world_scan.gd (map + flat spots, SCAN_BOX), dev_height_grid.gd, dev_roads_dump.gd, dev_probe_roads.gd

NEXT
1. SettlementPlan (layout per style) + SettlementKit (house variants, shader settlement.gdshader) + SettlementWorld (streaming, collision, LOD) + look-dev bot; baseline vs frames
2. doors + 16 country interior types; folk (people), pets, livestock; traffic slots (ParkedCars hook); anchors; helipads; hooks; map pins done (glyph), minimap check
3. tests/test_outskirts_settlements.gd; perf gate; docs (ARCHITECTURE, HANDOFF, THIRD_PARTY if art); contact sheet docs/shots/round6/

TESTS AND PERF
- test_terrain_world PASS; test_outskirts_sites: only the 7 'built on approach' checks fail (need SettlementWorld) + 2 weather checks that are load-flaky (pass when the machine is idle)
- perf gate not run yet

OPEN PROBLEMS
- machine shared with w112-landscape (software-GL renders 5 min for 3 frames at 2400x1080); tests that wait 6 frames flake under load
- E massif (x 2100-3500) has crags up to 9 m per 4 m (test limit raised); E coast strip is only ~300 m wide (no town there)
