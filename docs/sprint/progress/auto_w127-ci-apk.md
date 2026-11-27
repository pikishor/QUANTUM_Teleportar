# w127-ci-apk (done)

agent id acb736ae8541e5916, 271 events, first activity 2026-11-27T10:57:39.261Z, last activity 2026-11-27T13:06:29.146Z

## Final report

GREEN cc44cd5 APK https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/46002123985 ARTIFACT 15200920062 320549699 Round 1: CI run 45986429383 on bdab8a8 was red on one shard. - Shard 5 failed on both attempts: test_w127_critic "the stick drives the heavy tank across MOUNTAIN TRACK BRIDGE (mountain_track_4, 68 m, curved / steep): 25 m of 68". The other 5 shards, visual QA, Three.js and Unreal were green. - Reproducing it locally (DejaVu fonts.conf, a fresh XDG_DATA_HOME per run): it never failed alone, but failed about 1 run in 6 with 4 to 6 copies of `CRITIC_PARTS=bridge` running in parallel. - Cause (a real game bug, found with a per-tick probe that was not committed): `Vehicle.activate()` ignored the height it was given and put every car on the terrain. - RoadTraffic promoted an oncoming van on the deck at its lane height (40.3 m). activate() put it on the gully floor instead (36.9 m), 3.4 m under the deck. - More than 3 m under a deck counts as "under the bridge" (`Bridges.deck_y`), so the van stayed down there. - Car-to-car hull contacts (`VehicleManager._collide_all`) only compare x and z. So the van hit the tank on the deck above it: tank speed fell from 8.9 to 1.3 m/s, it was pushed 1.1 m sideways into the parapet, and its hull caught on the parapet's top edge. - It only happened when a road car was near the bridge at that moment, which is why it depended on load and timing. - Fix: new `Vehicle._spawn_y` in godot/scripts/vehicles/vehicle.gd. activate() now uses the bridge deck when the given height is within reach of one (the same rule `_terrain_step` drives by), and the terrain otherwise as before. `W127CI_OLD=1` switches back to the old code. - New check godot/tests/test_w127_ci.gd, failing before and passing after: - With the old code it fails 2 checks: the promoted van starts at 36.74 m under a 40.27 m deck. - With the fix it passes: the van starts on the deck and drives on along it. - A car put down off the bridge, and one asked for at ground level under the deck, both stay on the ground. - After the fix: - The loaded bridge run passed 36 of 36, with a van near the tank in all 36. - These pass: test_w127_critic (full), test_bridges_harbour_boats, test_cars_v2_traffic, test_reach_w120, test_play_critic_w112, test_tanks_w127 and _b, test_tank_arms_w127, test_railways_ships, test_open_world_freedom, test_critic_w120, test_outskirts_settlements, test_vehicles_city, test_planes_w126, test_airport_aircraft, test_terrain_world, and the three traffic tests (test_traffic_ai, test_traffic_density, test_traffic_police_feel). - Locally, test_air_w126 failed once while 3 tests ran in parallel ("a finger on FLARE pulls the missile off", decoyed 2). It passed on the next 4 runs; it is an aircraft test with no bridge involved. - Pushed as cc44cd5, with the same trailers as the last commit and only my own paths. Round 2: CI run 45998060143 on cc44cd5 was all green, with no FLAKY or FAIL annotation. The Android build (android.yml run 46002123...

## Last notes of the agent

- 10:58:01 Now waiting for the monitor.
- 10:58:04 Waiting for CI now.
- 11:28:09 Start progress notes and reproduce locally.
- 11:53:20 Log nearby vehicles on drops.
- 13:05:27 Add the round 2 / APK note to progress and HANDOFF (docs only, no CI retrigger needed beyond a docs commit).

## Recent steps (last 40)

- 11:53:18 Read car-car collision pass
- 11:53:27 Log nearby vehicles on drops, loop
- 11:57:39 Check PathDriver height handling
- 11:57:41 Locate PathDriver and RoadTraffic
- 11:57:44 Check how promoted cars get their height
- 11:57:48 Find where road traffic heights are set
- 11:57:52 Read road traffic height sampling and promotion
- 11:57:57 Read RoadLanes.sample height source
- 11:58:05 Identify road 4 near the stall point
- 11:58:27 Trace nearby vehicle history, loop until fail
- 12:02:35 Check road traffic height updates and promoted spawn
- 12:02:38 Read spawn_promoted_path
- 12:02:45 Find _place_at callers and activate height
- 12:02:48 Read road traffic step and vehicle activate
- 12:02:54 Read rest of activate
- 12:03:05 List activate callers
- 12:03:16 See static switches in vehicle.gd
- 12:03:24 Apply deck-aware spawn height fix
- 12:03:52 /home/user/QUANTUM_Teleportar/godot/tests/test_w127_ci.gd
- 12:03:54 Check TestLib and runner conventions
- 12:04:18 Run new check with new and old code
- 12:05:06 Fix test sampling and rerun old and new
- 12:05:50 Run 36 loaded bridge runs with the fix
- 12:13:41 Remove dev probes, find related tests
- 12:13:50 Run related tests 3 at a time
- 12:13:57 Run related tests 3 at a time
- 12:19:44 Inspect air_w126 failure and rerun alone
- 12:20:39 Rerun air_w126 under load, check known flake
- 12:21:41 Read last commit trailers
- 12:21:59 Write progress notes and HANDOFF section
- 12:22:07 Commit own paths and push to main
- 12:22:13 Find new CI run
- 12:22:37 Watch CI run up to 10 min
- 12:32:36 Watch CI run up to 10 min
- 12:42:38 Watch CI run up to 10 min
- 12:51:11 Check flaky annotations, start Android build
- 12:51:36 Watch Android build
- 13:01:36 Finish watching Android build, read artifact
- 13:05:31 Commit docs notes and push
- 13:06:28 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/test_w127_ci.gd
