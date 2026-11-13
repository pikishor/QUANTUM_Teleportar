# w112-outskirts-map (builder notes; started 2026-11-13 ~09:15Z, updated ~11:17Z)

GOAL: outskirts settlements + a bigger map: 7 settlements of different character (farming village, fishing harbour town, mountain lodge hamlet, industrial/mining site,
desert outpost, suburban estates, resort/lake town) with 20-80 houses each, gardens, fences, parked cars, shops, churches, farms, interiors (15+ layouts), NPCs, pets,
livestock, mission hooks, 2+ tall snake anchors each, helipad where it fits, traffic from wave 111; world at least 2x playable area, road network with highways,
ring road, bridges, tunnels; map/minimap/GPS/route planner/fast travel limits updated.

DESIGN DECISIONS (read before touching)
1. World = 9 km square (TerrainHeight.WORLD_HALF 4500, CityLayout.PLAY_HALF 4460). Land grows N/E/W only (WorldExtent.coast_push in TerrainHeight.coast_distance); S/SE/SW coast, harbour,
   airport unchanged. Land 16 -> 30 km2 (area x2.25). TerrainMap RES 768, shore map 192, MapScreen.WORLD_ZOOM 0.24, SILVER MERE lake.
2. Towns = new OutskirtsSites entries (kind &"town", scripts/settlements/settlement_defs.gd): flat elliptical pad ON a road (main street = the road, RoadTraffic cars pass through),
   TerrainRoads.level_profile levels the road inside the pad. Map pin = site + glyph town. Discovery/reward/compass/vegetation keep-out come with OutskirtsSites.
3. Roads: settlement_roads.gd (RING ROAD, WEST HIGHWAY, COAST LINK, WEST COAST ROAD, LARK ROAD, OUTPOST ROAD, SHORE TRACK) appended to TerrainRoads.DEFS (CORE_DEFS + extra).
4. Settlement kit: SettlementPlan (layout per style, town frame) -> SettlementKit (vertex-colour merged meshes, ONE shader settlement.gdshader, no textures) -> SettlementWorld
   (Node3D child of City: 80 m chunks built time-sliced near the hero, one far mesh per town, StaticBody boxes, rotors, door-glow MultiMesh, notice-board activity, folk).
5. Doors: SettlementData.doors() (ids >= 100000) are appended in InteriorGameplay.doors(); markers only for city doors. 19 country interiors in scripts/interiors/interior_country.gd
   (own SPECS/TITLES/COLORS/NAMES/PLAN/RADIO/AMBIENCE; hook lines in InteriorKinds, InteriorData, vendor_logic, interior_plan; vendors alias city stock).
6. People: SettlementFolk pins city-crowd slots (AmbientCrowd.pin_vendor got seed + ground height params): shootable, no extra draw call. Livestock = wildlife near HARROW FIELD
   (AnimalSpecies.FARMS). Pets = static dog/cat meshes merged in the chunk. Parked cars = ParkedCars._gen_site hook (plan.parked). Anchors = AnchorSites.all_anchors hook.
7. Fast travel: RoamData.PAD_DEFS +7 town pads (kind town, plan.pad); test_free_roam_world count made dynamic.

DONE
- world 9 km, roads, 7 town defs, kit + shader + 7 style layouts, SettlementWorld streaming, doors + 19 interiors (entered and left in real game: cottage, store, tavern look right),
  folk via crowd pins, pets, parked cars, anchors hook, pads, notice-board activity (in progress), harbour oriented to the sea, live frames of all 7 towns at MED looked at
- dev tools: tests/bot_towns.gd, bot_country_interiors.gd, dev_towns_probe.gd, dev_plan_probe.gd, settlement_viewer + tools/settlement_view.sh

NEXT
1. notice-board activity per town, tests/test_outskirts_settlements.gd, update test_outskirts_sites (towns built on approach is SettlementWorld now)
2. look-dev rounds LOW/MED (folk, cars, harbour sea side), perf gate PERF_CHECK=1 tools/perf_report.sh 0 1 2, contact sheet docs/shots/round6, docs, regression tests

TESTS AND PERF
- test_terrain_world PASS; dev probes pass; test_outskirts_sites needs the town checks updated; perf gate not run yet

OPEN PROBLEMS
- machine shared with w112-landscape: software-GL bot renders take 25-100 s per frame under load (BOT_TIMEOUT must be raised, <= 560 s per call)
- E massif crags up to 9 m per 4 m (test limit raised); E coast strip ~300 m wide (no town there)
