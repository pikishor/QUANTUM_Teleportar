# w127-arms (done)

agent id a3054ec684df59b45, 445 events, first activity 2026-11-27T05:08:56.738Z, last activity 2026-11-27T06:37:33.569Z

## Final report

w127-arms report (no commits, no pushes) Built: - Weapons by class (TankArms; AIM button, ARMS chip, SMOKE button). Main gun stays FIRE: AP/HE/cluster shells on SHELL, the carrier's autocannon, the howitzer firing on a target marker (snaps to armour within 22 m of the crosshair, range text, pin), flak. Arms: COAX, HMG, ATGM with lock-on, 6-rocket SALVO, SAM, SMOKE (cloud hides the tank from crews and seekers). Reload rings on FIRE, the arm button and SMOKE. Turret follows the camera drag. New blast table entries: ord_atgm, ord_tank_rocket, veh_smoke. - Armour (TankArmour): direct hits land on front x0.55, side x1, rear x1.6, turret x0.75, tracks. Machine guns do x0.12. A damaged track halves speed, a broken one stops the tank (crew repair after 12 s). A rear hit below 50% hull sets the tank on fire; it burns and blows up. - Enemy crews (TankCrews, pooled, distance-throttled, max 2/3/4 by tier): one at the ARMY AIRBASE that fights at 1 star or when hit, tanks at 4 and 5 stars, mission crews. - Missions (TankMissions/TankSteps, step kind tank_task): TANK BATTLE, CONVOY ESCORT, ARTILLERY STRIKE, offered for sure in the ARMY YARD. - Fixes found by the checks: tanks past 140 m were invisible (now drawn to 560 m); my board injection was replacing air mission cards; a recycled tank kept its last arm. Checks (all real touch, phone 1200x540 viewport): tests/test_tank_arms_w127.gd (weapons + armour), _b (crews + battle), _c (convoy + artillery). All PASS. With W127A_OLD=1: 28 of 43, 2 of 4 and 2 of 2 checks fail. Also PASS: test_tanks, test_vehicle_weapons, test_armour_w118, test_controls_w118 (one GAS flake under load, passes alone), test_campaign_runner (count 17 to 18), test_mission_board, test_air_w126 and _b, test_touch_buttons_r7, test_airport_aircraft. Frames looked at, LOW and MED (tests/bot_w127_arms.gd): HUD clear, lock box, smoke, marker, salvo, enemy firing, board card. Not fixed: - test_campaign_runner prints its own SCRIPT ERROR at line 980 (not from this work). - No per-zone hit text; no cannon aim assist. - Convoy trucks are puppets on straight lines. - Base crew uses the airbase helipads, not w127-tanks' base line. Files: new scripts/vehicles/tank_armour.gd, tank_arms.gd, scripts/enemies/tank_crews.gd, scripts/missions/tank_missions.gd, tank_steps.gd, tests/test_tank_arms_w127{,_b,_c}.gd, tests/bot_w127_arms.gd. Hooks in vehicle_weapons.gd, air_rockets.gd, vehicle.gd, vehicle_craft.gd, vehicle_manager.gd, touch_controls.gd, hud.gd, world_steps.gd, campaign_runner.gd, campaign_steps.gd, mission_board.gd, mission_board_screen.gd, tests/test_campaign_runner.gd. Log: docs/sprint/progress/w127-arms.md Perf (run once, no limit touched): LOW draws=75 total=99 death=109 OK; MED draws=99 total=133 prims=275k death=147 OK; HIGH draws=118 total=156 death=166 OK.

## Last notes of the agent

- 05:18:42 Now TankCrews.
- 05:22:51 Now TankSteps.

## Recent steps (last 40)

- 05:54:45 Run tests B and C
- 05:57:12 Find enemy LOS computation
- 05:57:15 Read LOS throttling context
- 05:57:31 TankCrews own wanted dispatch timer; simplify test
- 05:57:37 Rerun test B with timing
- 05:59:56 Open-ground wanted spawn and battle kill debug
- 06:00:57 Run the three files with the old behaviour switch
- 06:03:12 Run related existing tests two at a time
- 06:06:10 Inspect runner script error; fix injection slot
- 06:06:18 Rerun air missions test and tank C
- 06:08:17 Read the rest of the air bot pattern
- 06:08:20 See how air bot finishes
- 06:08:52 /home/user/QUANTUM_Teleportar/godot/tests/bot_w127_arms.gd
- 06:08:56 Render tank arms frames at LOW phone aspect
- 06:12:26 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/tank_hud_q0.png
- 06:12:27 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/tank_fire_reload_q0.png
- 06:12:32 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/atgm_locked_q0.png
- 06:12:34 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/smoke_q0.png
- 06:12:35 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/artillery_marker_q0.png
- 06:12:48 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/artillery_hit_q0.png
- 06:12:49 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/salvo_q0.png
- 06:12:50 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/enemy_fires_q0.png
- 06:12:52 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/board_tank_q0.png
- 06:13:02 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/enemy_hit_q0.png
- 06:13:20 Show tanks far, reset arm on recycle, marker pin, add check
- 06:13:26 Rerun test A, render MED frames
- 06:20:59 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/atgm_locked_q1.png
- 06:21:00 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/frames/artillery_marker_q1.png
- 06:21:11 Rename roof MG label to HMG; check perf tool
- 06:21:15 Run the perf gate (first of at most two)
- 06:28:54 Show the three perf verdict lines
- 06:29:00 Final runs of new and related tests
- 06:32:46 Robust kill check; rerun B and controls test
- 06:34:23 Find far despawn rules
- 06:34:38 Make the bot's kill loop reposition on misses; rerun B and C
- 06:35:38 Time each new test file alone
- 06:35:42 Time test A and B alone
- 06:37:11 Check diff stat of hooked files and disk
- 06:37:21 Finalise progress log
- 06:37:33 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/scripts/vehicles/tank_armour.gd
- godot/scripts/vehicles/tank_arms.gd
- godot/scripts/enemies/tank_crews.gd
- godot/scripts/missions/tank_steps.gd
- godot/scripts/missions/tank_missions.gd
- godot/tests/test_tank_arms_w127.gd
- godot/tests/bot_w127_arms.gd
