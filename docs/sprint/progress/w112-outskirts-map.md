# w112-outskirts-map (builder notes; started 2026-11-13 ~09:15Z, FINISHED ~15:46Z)

GOAL: outskirts settlements + a bigger map: 7 settlements of different character (farm village, harbour town, mountain lodge hamlet, mining works, desert outpost, suburban
estates, beach resort), 20-80 houses each, gardens, fences, parked + moving cars, shops, churches, farms, interiors (15+ layouts), NPCs, pets, livestock, hooks, 2+ snake
anchors, helipads, wave-111 traffic; world >= 2x playable area, road network (ring road, highways), map/minimap/GPS/fast travel updated.

DONE (all of it, in the real game, tests green)
- World 9 km (area x2.25, land x1.88: N/E/W only), 7 roads (ring road, west highway, links, tracks), SILVER MERE, map 768 px, shore map 768, far-tile grid aligned to 1 km.
- 7 towns = OutskirtsSites kind town, elliptical pad ON a road (main street = the road, RoadTraffic drives through): scripts/settlements/* (plan, kit, one shader, world).
  26 - 69 homes each, 22 tall anchors, roof + field helipad with helicopters, parked cars, pets, 88 folk at posts (pinned city-crowd slots), notice-board activity, QUANTUM PAD,
  map pins without clutter, hooks. 254 doors, 19 country interiors (scripts/interiors/interior_country.gd), shops sell.
- tests/test_outskirts_settlements.gd (390 checks), look-dev bots tests/bot_towns.gd + bot_country_interiors.gd, docs (ARCHITECTURE + HANDOFF), sheets docs/shots/round6/outskirts_*.jpg.
- Perf gate (final): LOW OK 94 draws / 135.4 k tris / 146 MB; MED OK 129 / 277.2 k / 177 MB; HIGH OK 149 / 386.3 k / 242 MB. Clean HEAD worktree MED: 130 / 276.9 k / 175 MB.
- Found and fixed on the way: far-tile grid made MED OVER (+9.9 k): edges now at multiples of 1 km; officer scale race (Drone.set_size) that the towns exposed.

DECISIONS: see ARCHITECTURE "Outskirts towns and the 9 km world". Towns hide/skip far meshes inside the city and while an interior is active; MED/HIGH shadows only near.
TESTS MOVED WITH A REASON: test_terrain_world, test_water_world, test_animals_biomes, test_world, test_free_roam_world, test_outskirts_sites (the coast moved 1.2 km, pad count, towns).
NOT MINE: test_ambient fails by the landscape builder's nodes (QT_NO_LANDSCAPE=1 passes); test_vehicle_roster prints a process_mode script error from its own line 94.
GAPS: wide highway street profile in towns, folk and pets do not walk, no harbour pier, towns are not mission-recipe targets, land 1.88x (area 2.25x).
