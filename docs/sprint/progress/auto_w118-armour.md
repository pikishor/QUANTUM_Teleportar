# w118-armour (done)

agent id aaf75a93b77dcedc7, 128 events, first activity 2026-11-22T04:28:46.404Z, last activity 2026-11-22T05:21:53.769Z

## Final report

w118-armour report (resumed after the restart; nothing committed or pushed) WHY THE PLAYER NEVER MET THEM (found by finger play before the restart): the nearest fixed vehicle was 137 m from the start and only existed within 100 m; the tanks stood in ring-road traffic lanes 300 m out; map markers were fogged GARAGE car glyphs; on LOW+ each tank released the one beside it. FIXED, each proved by godot/tests/test_armour_w118.gd (real fingers, real main scene; now 43 checks, PASS): - Fixed places: ARMY YARD (2 tanks + armoured carrier, 120 m from spawn), two city helipads, airport helicopters and planes; kept outside the car cap while the hero is near. - Map and minimap icons (tank, helicopter, plane), never fogged, GPS on tap, legend chip TANKS + AIR. - DEMO / TEST menu SPAWN list starts with tanks, helicopters, planes, placed next to the hero. - CALL-IN list from MORE > CALL (CAR, TANK, HELICOPTER, PLANE; cooldown). - Tank: walk, ENTER, drive 30 m, FIRE, EXIT. Helicopter: ENTER, UP, fly, FIRE, DOWN, EXIT. - `ARMOUR_OLD=1` (wave 118 parts off): 12 checks fail. - New this session, seen in my own frame: beside a delivered tank the prompt read HIJACK SEDAN and ENTER took the car. `VehicleManager.reach_car` now prefers a called / fixed vehicle. `ARMOUR_PICK_OLD=1 ARMOUR_PARTS=call` fails (hero ends in the sedan); passes on the new code. Related tests: 26 pass and 3 flaky in a 3-job batch; big_city, map_no_freeze, outskirts_sites and flight_view_w116 failed in the batch (timeouts under load) and pass alone. PERF (run once, after all edits): - LOW draws=74 total_draws=96 death_draws=107 verdict=OK - MED draws=97 total_draws=129 death_draws=149 verdict=OK - HIGH draws=113 total_draws=149 death_draws=170 verdict=OK NOT FIXED: - Planes are not in the finger test (take-off and landing unproven by finger). - The city plane still stands on the avenue at (340, 0, 0) in traffic. - A called vehicle loses the ENTER preference once driven. - The CALL button still reads CALL CAR (label belongs to w118-controls). - The yard has no guards or mission. - Tank models look flat and pale at noon on LOW. FILES (godot/): - New: scripts/vehicles/armour_sites.gd, scripts/ui/call_in.gd, tests/test_armour_w118.gd, tests/bot_w118_armour.gd, tests/dev_w118_armour.gd, tests/dev_w118_plazas.gd. - Hooks: scripts/vehicles/vehicle_manager.gd, vehicle_spawns.gd; scripts/world/city_props.gd, city_kit.gd, city_landmarks.gd; scripts/ui/map_icons.gd, map_screen.gd, minimap.gd, test_menu.gd, demo_panel.gd, touch_controls.gd (one line). - Docs: docs/HANDOFF.md, godot/ARCHITECTURE.md, docs/sprint/progress/w118-armour.md. - Frames: /home/user/QUANTUM_Teleportar/docs/shots/round7/armour_w118/armour_w118_sheet2.jpg

## Last notes of the agent

- 04:41:51 Run the most related subset (vehicles, map, menus, world placement) in the background, and note progress.

## Recent steps (last 40)

- 04:28:47 Read progress log and git status
- 04:28:51 Check existing files, tools, rules, running processes
- 04:28:54 List tools and check doc notes
- 04:28:58 Run the armour test
- 04:31:00 Show armour test output and old-code failing count
- 04:31:41 Read frame bot header
- 04:31:45 Render look frames of yard, map, call-in, vehicles
- 04:41:27 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/f/enter_0_yard.png
- 04:41:28 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/f/map_1_open.png
- 04:41:29 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/f/call_1_list.png
- 04:41:30 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/f/enter_4_in_heli.png
- 04:41:34 Find related tests
- 04:41:55 Run related tests in parallel
- 04:42:00 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/f/call_2_tank.png
- 04:42:00 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/f/enter_3_fire.png
- 04:42:04 Find enter-target selection code
- 04:42:06 Read reach_car
- 04:42:12 Inspect test tail and old-code switches
- 04:42:35 Add called/fixed vehicle preference and its check
- 04:42:45 Run call part with preference off then on
- 04:43:59 Read spawn_parked and spawn_beside
- 04:44:05 Fix test setup and rerun old/new
- 04:45:08 Read toggle_enter_exit
- 04:45:20 Move the pick check before the first entry and rerun
- 04:46:29 Step back before placing the car; rerun
- 04:47:33 Tune step-back distance; rerun
- 04:48:36 Check related batch result
- 04:48:39 Wait for the related test batch
- 04:56:02 Show failing test lines
- 04:56:06 Rerun the four failing tests alone
- 04:59:23 Run the performance gate on LOW, MED, HIGH
- 04:59:26 Read existing doc sections
- 04:59:35 Update HANDOFF and ARCHITECTURE notes
- 04:59:38 Wait for the perf gate
- 05:09:41 Keep waiting for the perf gate
- 05:19:25 Read perf verdict lines
- 05:19:31 Save contact sheet and run final tests
- 05:21:31 Finalize progress log
- 05:21:53 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- (none)
