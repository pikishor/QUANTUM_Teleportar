# w112-outskirts-map (builder notes; started 2026-11-13 ~09:15Z)

GOAL: outskirts settlements + a bigger map: 7 settlements of different character (farming village, fishing harbour town, mountain lodge hamlet, industrial/mining site,
desert outpost, suburban estates, resort/lake town) with 20-80 houses each, gardens, fences, parked cars, shops, churches, farms, interiors (15+ layouts), NPCs, pets,
livestock, mission hooks, 2+ tall snake anchors each, helipad where it fits, traffic from wave 111; world at least 2x playable area, road network with highways,
ring road, bridges, tunnels; map/minimap/GPS/route planner/fast travel limits updated.

STATE AT START: previous agent with this label did nothing (hit weekly limit). Parallel builder w112-landscape edits terrain/veg/landscape files (do not touch beyond one-line hooks).
Baseline frames (scratchpad outskirts/base): DUST WELLS = cuboid mud houses, flat dark walls, giant plain sand street, no fences/gardens/people; PINE HOLLOW = plain log boxes, huge dirt street.

DESIGN DECISIONS (read before touching)
1. World = 9 km square: TerrainHeight.WORLD_HALF 3000 -> 4500 (CHUNK 250 and FAR_TILE 1000 divide it), CityLayout.PLAY_HALF 4460. Land grows N/E/W only (new class
   WorldExtent in scripts/world/world_extent.gd pushes TerrainHeight.coast_distance outward in the sectors W..N..E; the S / SE / SW coast, harbour, ships, airport stay).
2. Settlements are NEW ENTRIES OF OutskirtsSites (kind &"town", data in scripts/settlements/settlement_defs.gd, merged by one hook line in OutskirtsSites.ensure): so the pad
   carve, vegetation / wildlife / alien keep-out, map pins, HUD compass, mission hooks, discovery reward all work without touching those systems.
3. A town stands on a regional road (TerrainRoads.DEFS gets extra roads from SettlementRoads, one hook): that road is its main street and carries RoadTraffic cars; side streets,
   sidewalks, driveways are ground meshes of the town kit; parked cars use ParkedCars slots (hook), houses = merged chunk meshes + far LOD, one shader, vertex colour + UV in metres.
4. Doors: town doors are appended to Game.world.doors (id >= 100000, type from InteriorCountry.TYPES, 15+ new layouts, hook lines in InteriorKinds / InteriorData: the
   original TYPES arrays are NOT changed because 6 tests pin them at 16).
5. Anchors for the quantum snakes: SettlementAnchors.all_anchors() returns the AnchorSites format {id, kind, name, pos (top), base, height, radius}.

DONE
- (reading and design; nothing written to the game yet)

NEXT
1. WorldExtent + WORLD_HALF 4500 + TerrainMap RES 768 + shore map; render map; pick 7 town centres on flat dry land
2. settlement kit (house variants per style) + shader; look-dev bot; chunk streaming; doors; interiors; life; hooks; tests; perf

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- disk: 6.3 GB free at start (keep >= 4 GB); machine is shared with w112-landscape (software-GL renders take 2+ min per 3 frames while both run)
