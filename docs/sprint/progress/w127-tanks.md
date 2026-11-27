GOAL: w127-tanks: 20+ military ground vehicle kinds (own model, driving numbers, animated tracks/wheels, turret, icon), parked at army base / depot / checkpoints outside the car cap, test_tanks_w127.gd by real touch.
DONE:
- read ROUND7, PLAN 127, ROUND6 rules, HANDOFF last sections, w125-helis / w126-planes logs, armour_sites.gd, vehicle_craft(_models).gd, gen_plane_roster.py
- COUNT BEFORE: 5 military ground kinds on tank physics (tank, ltank, apc, artillery, aatank) + the civilian cash truck "armoured" (car physics, not counted). No track or wheel animation on any of them (VehicleCraft.sync returns before visual.spin).
- NOW 25: 20 new t_* kinds. godot/tools/gen_tank_roster.py (source table) -> scripts/vehicles/tank_roster.gd (TankRoster) + "w127-tanks BEGIN/END" blocks in vehicle_specs.gd (SPECS/PALETTES/NAMES/WEAPONS) + ROSTER/TANK_KINDS arrays + audio_director.gd ENGINES
- scripts/vehicles/tank_models.gd (TankModels: Body/Turret/Gun + Run/Run2 MultiMesh running gear (cleats, road wheels, tyres, legs) + Flail + Glow, shared meshes per kind, animate(), pose_of())
- hooks: vehicle_craft_models.build (TankRoster dispatch), vehicle_craft._tank (wheeled turn rate), vehicle_craft.sync tank branch (TankModels.animate), armour_sites.is_fixed + map_markers, vehicle_spawns.all_points
- tests/test_tanks_w127.gd + _b (even / odd kinds), tests/bot_w127_tanks.gd (lineup + places look bot)
- icons assets/icons/v_t_*.png (20, looked at); lineup + places frames LOW and MED looked at (hover/walker blown white on LOW -> darker palettes; fuel tank caps; hero hidden in lineup)
- army base frame looked at (LOW + MED) after moving the camera off ARMY SHELTER 2
NEXT: done (report sent)
DECISIONS (other agents may use):
- kinds t_heavy t_destroyer t_spg t_rocket t_apc8 t_apct t_ifv t_scout t_mrap t_jeep t_truck t_fuel t_recovery t_bridge t_mine t_amphib t_aa8 t_hover t_walker t_halftrack; cls "tank", craft
- spec keys new: "plate" (front armour mm, for w127-arms hit zones), "wheeled" (turn rate scales with speed), "hover", "legs"; TankRoster.DEFS[k]["wclass"] = main gun class (heavy_cannon, long_cannon, howitzer, rockets, autocannon, light_auto, hmg, mg, aa_missiles, rail, phase, none)
- WEAPONS rows for t_* are generated (t_recovery has none): w127-arms may add "tank_arms" lists or replace rows (edit the WEAPON table in tools/gen_tank_roster.py, then run it)
- places: ARMY BASE airport LOCAL x 1362, z -690 + 13.5 i (nose west; 7 kinds), VEHICLE DEPOT world (230 + 14 i, 1.2, 1575) harbour east headland nose north (7), CHECKPOINTS PASS / DESERT / FOREST ROAD 380-420 m out, one per shoulder; point ids "mv_<kind>" FIXED (TankRoster.owns)
- switch W127_TANKS_OLD=1 (TankRoster.on / TankModels.on false)
TESTS AND PERF:
- PERF_CHECK=1 perf_report 0 1 2 (final): LOW draws=75 death=107 OK; MED draws=99 total_prims=275039 death=146 OK; HIGH draws=118 death=164 OK (no limit touched)
- test_tanks_w127 PASS (57 s), test_tanks_w127_b PASS (77 s); W127_TANKS_OLD=1: 10 [old fails] FAIL in each file
- test_tanks, test_armour_w118, test_vehicle_roster (old NearTraffic SCRIPT ERROR, not mine), test_airport_aircraft, test_helis_w125 PASS
- probe: tris 352..4620 per kind; test_tanks_w127 TANKS_KINDS=t_heavy,t_jeep,t_hover,t_walker,t_halftrack: all drive checks PASS (icons missing -> data checks FAIL until icons built)
OPEN PROBLEMS:
- checkpoints are vehicles only (no booth / barrier props); army base row stands on the bare east strip of the airfield (no fence or signs)
- army base vehicles nose west toward the HELI LINE (x 1334): a long drive west reaches the helicopters (the test drives 9-21 m)
- t_amphib does not swim (land only); the hover tank and walker use the tracked physics (no strafing, no step climbing); walker legs are a swing cycle, no foot IK
- vehicle colours: lower trim reads slightly purple under the sky light (shared Trim metal 0.3)
