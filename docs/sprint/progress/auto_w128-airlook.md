# w128-airlook (done)

agent id ae588dedfcc4e8cce, 420 events, first activity 2026-11-27T15:03:49.757Z, last activity 2026-11-27T16:01:21.115Z

## Final report

w128-airlook report. No commits and no pushes. Log: docs/sprint/progress/w128-airlook.md. ROOT CAUSE OF THE "KIDDISH" LOOK: VehicleCraftModels._tri wound every triangle counter-clockwise when seen from outside. Godot treats clockwise faces as the front. So every procedural craft was drawn inside out: the near skin was culled and you saw the inside of the far wall. That is why they looked flat, the canopies were see-through and the fins showed through the body ("fins in the middle"). This hit all helicopters, planes, tanks, the quad, scooter, jetski and patrol boat. Fixed in VehicleCraftModels._finish; W128_OLD=1 brings back the old code. FIXED (all proved by the new godot/tests/test_airlook_w128.gd: 52/52 PASS on the new code, 51/52 FAIL with W128_OLD=1): - 20 helicopter kinds, each its own check: right side out, framed windscreen with no glass ring under the nose, tail rotor behind the mast and outside the main rotor disc, no part of the body in the blade sweep, gear on the ground, a LOD1 (far model) lighter than the near one. New helicopter build: smooth skin, door and chin windows with seams, engine cowling with intakes and exhausts, swept fin at the end of the boom with the tail rotor on its left. The classic "heli" (its old model was an open frame with no glass) now uses this build too. - 28 plane kinds, each its own check: right side out, glass on top, fin behind the wing, propellers ahead of the engine, gear on the ground, LOD1. New: airliner cockpit band and passenger window rows, canopy frames, real wing area on the narrow-, wide-body and jumbo, jet engines clear of the ground. - Hangars lit inside (lamps on within 90 m), air traffic (6 crossers, and the pad helicopters now take turns flying the new kinds), parachute over cargo crates: one check each, all fail on the old code. FOUND, NOT FIXED: - Planes sinking under the field: not reproduced. 47-48 parked aircraft measured, all on the ground; the check is kept as a guard and does not fail on the old code. - Wingtips near the runway edge: only 50 m between the runway edge (x 1284) and the heli line (x 1334); spans reach 38 m. Needs a new layout. - Not started: cockpit panel and duplicate readouts, hangar plane picker. - Hangar door leaves still stick out past the side walls. Other tests passing: helis_w125, planes_w126, air_w126, airport_aircraft, tanks_w127, w126_critic. FILES: scripts/vehicles/{vehicle_craft_models, aircraft_models, heli_models, plane_models, vehicle_visual (2 hooks), air_rockets}.gd, scripts/world/{air_traffic, aircraft_scenery, hangars}.gd; new tests/test_airlook_w128.gd, tests/bot_w128_air.gd, docs/shots/aircraft_w128.jpg (all 56 kinds, before and after, MED). Frames looked at: viewer lineups and game frames at MED 1200x540. PERF (run once, no limit touched): LOW draws=75 total=97 death=107 OK; MED draws=99 total=131 prims=274k death=146 OK; HIGH draws=118 total=154 death=164 OK.

## Last notes of the agent

- 15:04:45 Now render the before lineup of all 56 kinds.
- 15:17:39 Now re-render the same four helicopters with the new glass.
- 15:26:19 Now write the test file.
- 15:41:22 Add the chute check into the test's field part.
- 15:44:20 Meanwhile, update the progress log.
- 15:54:33 Meanwhile I'll look at the hangar interior frame, which should be done now.

## Recent steps (last 40)

- 15:27:00 /home/user/QUANTUM_Teleportar/godot/tests/test_airlook_w128.gd
- 15:27:04 Run the new airlook test
- 15:27:16 Fix scope errors and rerun test
- 15:28:32 Check ultralight and trainer dimensions
- 15:29:03 Fix model faults found by the test and rerun
- 15:30:37 Run test on new code and on old code
- 15:33:24 Update log and render all helicopters after
- 15:33:50 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ha_3q.jpg
- 15:33:59 Find references to the classic heli model
- 15:34:01 Find how procedural spec key is used
- 15:34:05 Read model loading function
- 15:34:08 Read model loading lines
- 15:34:24 Route the classic heli to the new builder
- 15:34:28 Check model_names return type
- 15:34:33 Render classic heli, tanks, quad, planes
- 15:34:46 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/v3.jpg
- 15:34:53 Start after-bot and run heli/plane tests
- 15:37:31 Run air, airport, tank tests
- 15:40:49 Inspect crate drop code
- 15:40:50 Read crate mesh build code
- 15:40:56 Read projectile update loop
- 15:41:14 Add parachute mesh to cargo crates
- 15:41:20 Read launch function
- 15:41:29 Add parachute check and run test
- 15:43:03 Check after-bot frames
- 15:43:08 Make before/after game comparison sheet
- 15:43:10 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/game_ba.jpg
- 15:43:20 Render all planes after changes
- 15:44:09 Build before/after contact sheet
- 15:44:11 /home/user/QUANTUM_Teleportar/docs/shots/aircraft_w128.jpg
- 15:44:14 Check bot completion
- 15:44:19 Wait for bot then run perf gate
- 15:44:25 Update progress log
- 15:44:30 Wait for perf gate to finish
- 15:54:36 Compose hangar before/after
- 15:54:39 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/hangar_ba.jpg
- 15:54:43 Wait for HIGH perf result
- 15:58:27 Confirm old-code failures and run critic test
- 16:01:08 Finalize log and clean scratch frames
- 16:01:20 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/test_airlook_w128.gd
