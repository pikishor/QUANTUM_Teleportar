# w127-ci-apk: CI watch and phone APK for wave 127

## Round 1 (CI 45986429383 on bdab8a8)
- Green: Three.js, Unreal, visual QA, shards 0, 1, 2, 3, 4. Red: shard 5.
- Shard 5 FAIL (both attempts): `test_w127_critic` "[old fails] the stick drives the heavy tank across MOUNTAIN TRACK BRIDGE (mountain_track_4, 68 m, curved / steep): 25 m of 68,
  never more than 0.54 m under the deck" (HIGHLINE BRIDGE passed, 66 of 70).
- FLAKY (passed on the retry, not touched): `test_device_fixes` "a solid world wall still shortens the arm (3.37 m)" (shard 1), `test_damage_everywhere` "a Cars v2 sedan stands
  in the arena" (shard 1).
- REPRODUCED locally (DejaVu fonts.conf, fresh XDG_DATA_HOME, 4 to 6 copies of `CRITIC_PARTS=bridge` in parallel): 1 of 4, then about 1 of 6 runs: "22 m of 68". Alone it always passed.
- CAUSE (traced with a per-tick probe, not committed): an oncoming road van is promoted to a real vehicle by RoadTraffic as the tank nears the bridge. `RoadTraffic.promote` passes the lane height
  (40.3, the deck), but `Vehicle.activate()` ignored `pos.y` and put every car at the TERRAIN height: the gully floor, 36.9, 3.4 m under the deck. More than 3 m under a deck counts as
  "under the bridge" (`Bridges.deck_y`), so the van stayed down there. Hull-to-hull contacts (`VehicleManager._collide_all`) are flat (x / z), so the van under the deck hit the tank on it
  (tank crashes 1, speed 8.9 -> 1.3), shoved it 1.1 m sideways into the left parapet, and the tank hull caught on the parapet's top edge (normal (0.72, 0.41, -0.56)) for the rest of the
  check. Timing-dependent: only when a road car was near the bridge at that moment.
- FIX: `Vehicle._spawn_y` (vehicle.gd): activate() puts a car on a bridge deck when the given height is within reach of one (the same `Bridges.deck_y` rule `_terrain_step` drives by), else on
  the terrain as before; `Vehicle.deck_spawn_on` / `W127CI_OLD=1` is the old code. New check `tests/test_w127_ci.gd`: a van promoted on the MOUNTAIN TRACK deck starts on the deck (old 36.74,
  new 40.27, deck 40.27) and drives on along it (old 36.48 under a 40.32 deck); a car off the bridge and one asked for at ground level under the deck stay on the ground. OLD FAIL 2, new PASS.
- After the fix: the loaded bridge run 36 of 36 PASS (a van was near the tank in all 36). Also PASS: test_w127_critic (full), test_bridges_harbour_boats, test_cars_v2_traffic, test_reach_w120,
  test_play_critic_w112, test_tanks_w127 + _b, test_tank_arms_w127, test_railways_ships, test_open_world_freedom, test_critic_w120, test_outskirts_settlements, test_vehicles_city,
  test_planes_w126, test_airport_aircraft, test_terrain_world, test_traffic_ai, test_traffic_density, test_traffic_police_feel. test_air_w126 failed once at 3-way load ("a finger on FLARE
  pulls the missile off", decoyed 2) and passed 4 of 4 after (aircraft, no bridge involved).
- Not fixed (open): hull contacts between cars stay flat (a car really driving under a bridge would still touch one on the deck above); the tank hull can catch on a parapet top edge.
