GOAL: w129-tankmis: every tank mission (TANK BATTLE, CONVOY ESCORT, ARTILLERY STRIKE) finishes by normal finger play; convoy driving, amphib swim, hover/walker physics, booths/fences; test_tankmis_w129*.gd.
DONE:
- read ROUND7, PLAN, ROUND6 rules, HANDOFF last sections, w127-tanks log
- TankMissions.near_steps (scripts/missions/tank_missions.gd): staged in the ARMY YARD, fought on street z=-80 west of it (consts BATTLE_FIELD/SPAWNS, CONVOY_ROAD, ART_FIRE/TARGETS); W129TM_OLD=1 = old far fields
- TankSteps (tank_steps.gd): `ride` held, step WAITS while hero is out (crews hold still + hold fire, beacon on tank, HUD GET BACK IN THE TANK); battle `spawns`; artillery `spots`; driven convoy (`road`): lane_line with rounded corners, trucks Vehicle.scripted, order/gap/corner speed, join + keep-up, waves up the road
- TankCrews (scripts/enemies/tank_crews.gd): roads_on: mission crews always engaged, road_goal() round the blocks without LOS, set_hold()
- vehicle.gd: tank_puppet branch skips only non-scripted puppets
- MissionGuide.auto_recover static (false = no SKIP offer / no self-recovery)
- TankArms.indirect_aim: howitzer crosshair reaches gun range (old: 220 m player aim ray -> shells short); used by marker_point + VehicleWeapons._shell
- CameraRig tank gun sight: after a swipe in a tank the view stays (no recentre to hull/chase pitch) while < 4 m/s (old: swung back, turret off target)
- tests: tests/tankmis_w129_bot.gd (bot) + test_tankmis_w129.gd (battle+wait), _b (convoy), _c (artillery)
- TankMoves (scripts/vehicles/tank_moves.gd, class_name, import done): hover drift + glides over water, walker gait pulse + steps in pivots (tank_models.gd st g), amphib floats/swims/climbs out; hooks in VehicleCraft._tank
- tests/test_tankmoves_w129.gd PASS; OLD 7 FAIL
- focused checks: GUN SIGHT (test_tankmis_w129 after()), HOVITZER marker 290 m (_c after()) fail on OLD
- tests/bot_w129_tankmis.gd look bot (one mission per run: TM_MISSIONS)
- TankPlaces (tank_places.gd, hook VehicleManager) + test_tankplaces_w129 PASS (OLD FAIL); CameraRig first-swipe fix (test_tank_arms_w127 swipe check)
- frames looked at: convoy/battle/artillery (scratchpad frames), HANDOFF section written
- regression runs PASS: tank_arms_w127 a/b/c, tanks_w127 a/b, tanks, w127_critic, w128_open, hud_camera_final, controls_w118, mission_board, world_missions, armour_w118
- places frames looked at (fences/booms read; booths out of the camera's view in those frames)
- PERF_CHECK=1 perf_report 0 1 2 (once): LOW draws=72 death=110 OK; MED draws=99 total=131 prims=275k death=146 OK; HIGH draws=118 total=154 death=163 OK
NEXT:
- done (report sent)
DECISIONS:
- env switch W129TM_OLD=1 = every old behaviour of this task
TESTS AND PERF:
- test_tankmis_w129 PASS (battle 32-66 game s); W129TM_OLD=1: 6 FAIL
- _b PASS (convoy 87-90 s), _c PASS (artillery 30 s)
OPEN PROBLEMS:
