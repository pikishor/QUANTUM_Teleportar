# w115-snake-traversal (running)

agent id ae95c122bf87a5b35, 1220 events, first activity 2026-11-14T23:13:49.366Z, last activity 2026-11-15T04:50:05.956Z

## Last notes of the agent

- 23:43:16 Now the core traversal orchestrator and the swing state.
- 02:38:31 Now apply the super jump change (longer hold, standing start only) and extend the test.
- 03:29:32 Now implement the three improvements (free-fall baseline for the arc test, a wide second pass for chain scans, and an earlier flight fallback).

## Recent steps (last 40)

- 02:54:50 Reel the rope in when the lowest point of the swing would be near the ground
- 02:55:08 Run the NORMAL chain probe three times with the reel-in and clearance filter
- 02:58:31 Add the clearance filter to the finder and rerun the NORMAL chain probe with the swing log
- 02:59:30 See the half-second trace of the NORMAL chain probe
- 03:00:46 Add dev switches for the reel, the filter and the penalty so variants can be compared
- 03:01:04 /home/user/QUANTUM_Teleportar/godot/tests/dev_snake_routes.gd
- 03:01:09 Baseline reliability of the swing chain over 8 random routes at NORMAL (reel off)
- 03:03:46 Run the routes probe at 4x time scale for the baseline (reel off)
- 03:04:40 Baseline (reel off) over viable routes at real time, two seeds of four trials
- 03:09:16 Same routes with the clearance reel and anchor filter on
- 03:14:20 Read the ground 5 and 12 m out from the facade instead of straight under the anchor, then rerun the routes
- 03:18:45 Trace one failing route (77, 235, yaw 0) in detail
- 03:19:37 Run eight more routes with the cause of each swing end printed
- 03:24:37 Print the finder statistics at the moment the chain gives up
- 03:26:41 Dump the last scans before the hero touches the street in a failing chain
- 03:29:28 Find the chain scan call sites in the traversal
- 03:29:37 Inspect the exact text around the picks stats line to patch it safely
- 03:29:54 Add the free-fall baseline, the wide second pass for chain scans, then rerun the routes
- 03:32:10 More seeds at NORMAL with the new finder
- 03:39:04 Repeat the fixed test route at STORY and NORMAL three times each
- 03:44:27 Run the swing-run test three times to see its reliability
- 03:47:52 Same routes with the stick held forward (a thumb that steers) at NORMAL
- 03:57:06 Repeat the swing-run test's own route eight times at NORMAL to measure reliability
- 04:01:02 See what other builders added to the shared tree and who references SnakeUi
- 04:01:12 See the current quantum scripts and any dictionary .kind access
- 04:01:34 Refresh the class cache so new class_name scripts from both builders resolve
- 04:01:53 Rerun the fixed-route reliability probe after the import (unique script errors counted)
- 04:04:25 Look at what TrafficField.bare_street does
- 04:04:29 Find TrafficField.bare_street
- 04:04:35 Fixed route at NORMAL with the street cleared of traffic, eight trials
- 04:08:35 Reward long ropes in the anchor score and compare on the fixed route (two bonus values)
- 04:16:39 Random viable routes at NORMAL with the long rope bonus, three seeds
- 04:23:00 The fixed route at STORY twice and HARD once
- 04:28:30 Rerun the swing-run test three times with the bare street
- 04:32:08 Perf gate run 1 (mid-way), tier 0 (LOW)
- 04:34:09 Perf gate run 1 (mid-way), tiers 1 and 2
- 04:44:19 A/B the MED gate with the snake nodes not created (temporary env switch)
- 04:47:34 View the bind function to add a finer temporary A/B switch
- 04:47:39 A/B the MED gate without SnakeFx only
- 04:50:05 Compare idle draws with and without SnakeFx in my own perf bot (MED)

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- docs/sprint/progress/w115-snake-traversal.md
- godot/assets/shaders/snake_tendril.gdshader
- godot/scripts/quantum/snake_tendril.gd
- godot/scripts/quantum/snake_tendril_pool.gd
- godot/tests/bot_snake.gd
- godot/scripts/quantum/snake_power.gd
- godot/scripts/quantum/snake_anchor.gd
- godot/scripts/quantum/snake_swing.gd
- godot/scripts/quantum/snake_zip.gd
- godot/scripts/quantum/snake_climb.gd
- godot/scripts/quantum/snake_flight.gd
- godot/scripts/quantum/snake_traversal.gd
- godot/scripts/quantum/snake_camera.gd
- godot/scripts/quantum/snake_pose.gd
- godot/tests/dev_snake_chain.gd
- godot/tests/test_snake_traversal.gd
- godot/tests/test_snake_swing_run.gd
- godot/scripts/ui/touch_controls.gd
- godot/tests/bot_snake_perf.gd
- godot/tests/dev_snake_routes.gd
