GOAL: w127-arms: vehicle weapons by class from the blast table (cannon AP/HE, MGs, ATGM lock, artillery marker, salvo, flak, smoke), hit zones + track damage, enemy tank crews, 3 tank missions, test_tank_arms_w127.gd by real touch.
DONE:
- started 2026-11-27; read ROUND7, PLAN line 127, ROUND6 rules, HANDOFF last sections, w126-air log
- NEW scripts/vehicles/tank_armour.gd (TankArmour: hit zones front/side/rear/turret/tracks, track hp, slow/stop, crew fix, engine fire)
- NEW scripts/vehicles/tank_arms.gd (TankArms: coax, roof MG, ATGM lock-on, rocket salvo, SAM, smoke; blasts ord_atgm / ord_tank_rocket / veh_smoke; artillery marker + snap; HUD box/marker; button reload arcs)
- NEW scripts/enemies/tank_crews.gd (TankCrews: base crew at ARMY AIRBASE, wanted 4-5 tanks, mission crews; pooled, distance-throttled)
- hooks: vehicle_weapons.gd (tarms, zone hits, artillery snap, enemy hero dmg), air_rockets.gd (zone hit on direct hits, dir param), vehicle.gd (reset metas in activate/repair, tank_puppet sim skip),
  vehicle_craft.gd (_tank track speed factor), vehicle_manager.gd (_count_fixed metas, TankCrews.attach), wanted.gd (dispatch_wanted at end), touch_controls.gd (ARMS chip arms_next, SMOKE MID slot,
  labels, reload arcs), world_steps.gd (veh "tank"), hud.gd (TankArms.draw_hud)
- tools/import.sh run after the 3 class_names
- NEW scripts/missions/tank_missions.gd (TankMissions: tank_battle / tank_convoy / tank_artillery, injected in the ARMY YARD within 60 m) + tank_steps.gd (TankSteps, step kind tank_task)
- hooks campaign_runner.gd (StepKinds + tank), campaign_steps.gd, mission_board.gd (inject + _build_tank), mission_board_screen.gd (icons), tests/test_campaign_runner.gd count 17 -> 18
- fix: enemy tanks / artillery targets / convoy trucks drawn to 560 m (Vehicle.update_lod hid every car beyond 140 m)
- TankCrews: own wanted timer (WANTED_EVERY 4 s, not blocked by Wanted's hide rule), open-ground spawn fallback; wanted.gd hook REMOVED again (file untouched now)
- tests/test_tank_arms_w127.gd (weapons+armour), _b (crews+battle), _c (convoy+artillery): all PASS (test ground found automatically beside a landing field)
- existing tests PASS after hooks: test_tanks, test_vehicle_weapons, test_armour_w118, test_controls_w118
- fix: tanks shown to 560 m (TankArmour.SHOW_FAR); arm selection resets on recycle; marker pin; roof MG label HMG; TankMissions injects into the LAST card away from the yard (it replaced the air mission: test_air_w126_b BOMB RUN)
- tests/bot_w127_arms.gd: frames LOW + MED 1200x540 looked at (tank HUD, reload ring, ATGM LOCKED, smoke, artillery marker + pin, salvo, enemy fires, board TANK BATTLE card)
- FINAL: test_tank_arms_w127 / _b / _c PASS (46 s / 36-115 s / ~90 s alone); W127A_OLD=1: 28 of 43 / 2 of 4 / 2 of 2 fail
- also PASS: test_tanks, test_vehicle_weapons, test_armour_w118, test_controls_w118 (one GAS flake under load, PASS alone), test_campaign_runner, test_mission_board, test_air_w126(+_b), test_touch_buttons_r7, test_airport_aircraft
NEXT:
- done (report sent)
DECISIONS:
- switch W127A_OLD=1 (TankArms.on / TankArmour.on / TankCrews.on / TankMissions.on)
- metas: enemy_tank (crew), tank_puppet (convoy truck), tank_target (artillery target), trk_l/trk_r/trk_fix/last_zone; new action arms_next (key G); SMOKE uses action flare
- w127-tanks: a new tank kind gets arms from spec "tank_arms" or by its main gun (indirect -> artillery kit, flak -> AA kit, dmg>=50 -> MBT kit, else APC kit)
TESTS AND PERF:
- PERF_CHECK=1 tools/perf_report.sh 0 1 2 (once): LOW draws=75 total=99 death=109 OK; MED draws=99 total=133 prims=243k/275k total death=147 OK; HIGH draws=118 total=156 death=166 OK
OPEN PROBLEMS:
- test_campaign_runner prints a SCRIPT ERROR in its own _chapter_select_ui (line 980, 'rect' on Dictionary) but PASSES: not from this work
- no hit feedback text per zone for the player; turret aim on a phone is the look drag (no lock assist for the cannon); convoy trucks are puppets on a straight road over open fields
- enemy crews have no infantry dismount; base crew patrols the ARMY AIRBASE pads (Helipads army), not w127-tanks' TankRoster.BASE_LOCAL line
