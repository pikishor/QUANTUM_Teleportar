# w112-outskirts-map (done)

agent id ab9a223c65307f5bd, 1698 events, first activity 2026-11-13T09:11:14.655Z, last activity 2026-11-13T15:46:35.668Z

## Final report

Files: scripts/settlements/* (plan, kit, ONE shader, world, data, folk, seven styles), scripts/interiors/interior_country.gd (19 interiors), world_extent.gd (9 km world, 7 roads), hook lines in city, interior_*, parked_cars, crowd, anchors, roam pads, map; sheets docs/shots/round6/outskirts_*.jpg (6) + iterations.md; ARCHITECTURE, HANDOFF, progress log. Tests: new test_outskirts_settlements (390 checks) passes; about 60 regression tests pass; six old tests moved because the coast moved (reasons in HANDOFF). Fixed on the way: far-terrain tile grid (MED was 286.7k, over budget), officer-scale race in Drone (set_size). Gaps: land x1.88 (area x2.25); towns have a wide street profile; folk and pets stand still; no harbour pier; towns are not world-mission targets. Outside my scope: test_ambient fails from the landscape builder's nodes; test_vehicle_roster prints a process_mode error; the hero builder's files intermittently break compile (re-run tools/import.sh). PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=72 prims=134495 total_draws=94 total_prims=135361 nodes=2890 tex_mb=146 lights=3 hud_draws=19 death_draws=108 death_prims=135941 enemies=4 verdict=OK PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=97 prims=245310 total_draws=129 total_prims=277194 nodes=3030 tex_mb=177 lights=9 hud_draws=24 death_draws=145 death_prims=272748 enemies=4 verdict=OK PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=113 prims=340232 total_draws=149 total_prims=386298 nodes=3148 tex_mb=242 lights=12 hud_draws=25 death_draws=166 death_prims=379332 enemies=4 verdict=OK APK size effect: +0.24 MB (scripts and one shader; no model, texture or sound; the 3.9 MB of sheets are docs, not exported).

## Last notes of the agent

- 09:29:56 Now the two minimal edits to terrain_height.gd (world size constant and the coast hook).
- 09:47:58 Now the `end_on` support and the end-profile fix in `_build_road`.
- 09:48:03 Now the end-profile fix right after the cut-and-fill loop.
- 10:37:05 Now apply the three one-line hooks in city.gd.
- 10:37:23 Let me write a dev probe test that boots the real scene, settles each town and prints stats and timings.
- 10:47:53 Now implement the sea direction, budgeted rows, harbour re-layout, lawn colour tone-down, and the bot's street-relative positions.

## Recent steps (last 40)

- 14:28:24 Experiment: halve the far tile resolution and measure MED, then restore
- 14:32:20 Read how far tiles are tested and tracked
- 14:32:28 Read the far tile visibility loop and stats
- 14:32:34 Read the terrain world vis_dist logic
- 14:33:06 List the world-size and tile-grid uses in TerrainWorld
- 14:33:24 Align the far tile grid to multiples of 1 km and re-measure MED
- 14:36:43 Run the terrain world test with the aligned far tile grid
- 14:38:13 Run the full perf gate for all three tiers in the final state
- 14:47:18 Final regression batch 1
- 14:52:19 Final regression batch 2
- 14:58:01 Final regression batch 3
- 15:05:47 Check whether the officer-scale test is flaky with and without the towns
- 15:08:47 Read EnemyManager.spawn
- 15:08:56 Read the enemy acquire path and the drone model creation
- 15:09:13 Look for model scale writes and the test's go helper
- 15:09:19 Read how the drone model scale is driven every frame
- 15:09:32 Read the missions test helpers
- 15:09:52 Read how the base scale is declared and used
- 15:10:09 Read _look_scale handling and the release path
- 15:10:29 Run the officer test five times on the clean HEAD worktree
- 15:12:21 Read the operative crouch scale update and the LOD call sites
- 15:12:58 Run the officer test with the town node's work switched off but the data hooks live
- 15:14:32 Bisect which part of the town node affects the officer test
- 15:20:28 Stop the town streamer while an interior is active and re-run the officer test six times
- 15:23:32 Read the test run() setup to replicate it in a probe
- 15:23:53 Trace the officer scale, distance scale and camera distance over several runs
- 15:27:00 Check for global RNG use in my scripts and where the look scale comes from
- 15:27:38 Read Drone.deactivate and the scale members before editing
- 15:27:51 Make the interior officer's size persistent and re-run the officer test six times
- 15:29:56 Find the source of the HeroGlow parse error
- 15:30:04 Register the new hero class (shared tree) and re-run the officer test six times
- 15:33:19 Re-import and re-run the officer test six more times
- 15:35:39 Measure the added script and shader weight
- 15:35:59 Update HANDOFF and ARCHITECTURE with the final perf, far-tile and officer facts
- 15:36:06 Remove the scratch HEAD worktree and free the disk
- 15:36:16 Delete the scratch frames after the contact sheets are committed
- 15:36:26 Run the enemy tests after the drone scale change
- 15:40:06 Final confirmation of the main tests and three more officer runs
- 15:46:14 Write the final progress log and list my changed files
- 15:46:34 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- docs/sprint/progress/w112-outskirts-map.md
- godot/scripts/world/world_extent.gd
- godot/scripts/world/terrain_height.gd
- godot/scripts/world/city_layout.gd
- godot/tests/dev_world_scan.gd
- godot/tests/dev_height_grid.gd
- godot/tests/dev_roads_dump.gd
- godot/scripts/terrain/terrain_roads.gd
- godot/scripts/terrain/outskirts_sites.gd
- godot/scripts/settlements/settlement_mesh.gd
- godot/assets/shaders/settlement.gdshader
- godot/scripts/settlements/settlement_parts.gd
- godot/scripts/settlements/settlement_houses.gd
- godot/scripts/settlements/settlement_specials.gd
- godot/scripts/settlements/settlement_plan.gd
- godot/scripts/settlements/settlement_styles.gd
- godot/scripts/settlements/settlement_data.gd
