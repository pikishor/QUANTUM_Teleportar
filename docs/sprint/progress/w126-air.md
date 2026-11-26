GOAL: w126-air: air traffic on the new roster (planes+helis), 6+ air missions on the board, aircraft weapons by class (guns/rockets/missiles lock-on/bombs/flares), test_air_w126.gd by real touch.
DONE (code written, first test runs pending):
- scripts/vehicles/air_arms.gd (AirArms): arms by class (LOADOUT / PlaneRoster role / spec "arms"), rocket, missile+lock-on, bomb, drop, flare; blasts ord_air_rocket / ord_air_missile registered (cat &"aircraft")
- hooks: vehicle_weapons.gd (arms, ticks_alt, _arms_sync), vehicle.gd (weapons for arms-only kinds, ticks_alt, air_puppet branch in sim), vehicle_manager.gd (_count_fixed counts air_puppet),
  air_rockets.gd (bomb gravity, crate chute + drops list, blast_id via BlastTable, flare decoy, looks), touch_controls.gd (FLARE OUT slot, ARMS chip top at WEAPON place, labels), flight_hud.gd (AirArms.draw_hud)
- scripts/missions/air_missions.gd (AirMissions, 6 types air_*), scripts/missions/air_steps.gd (AirSteps, step kind air_task), hooks campaign_runner.gd / campaign_steps.gd / mission_board.gd
- air_traffic.gd: roster kinds per lap, timetable (DEPART_EVERY), 4 crossers, model pool, MultiMesh specks beyond LOD_R; aircraft_scenery.gd spins Rotor2
- tests/test_campaign_runner.gd: StepKinds count 16 -> 17 (air_task added; meaning kept)
- tests/test_air_w126.gd (traffic + weapons, 47 s) and tests/test_air_w126_b.gd (6 missions, 88 s): PASS; W126A_OLD=1: 19 + 6 [old fails] checks fail
- game fixes found by the test: mission aircraft wins ENTER over a parked plane beside it (meta mission_ride in WorldSteps.provide + VehicleManager.nearest);
  bomb targets / puppets outside the car cap (air_target / air_puppet in _count_fixed); unlocked missiles aim at the crosshair from the rail
- touch layout: in the air FLARE takes the MID slot, VIEW moved to a top chip beside ARMS (test_controls_w118 caps the right cluster at 6 circles)
- traffic: first airliner, GA plane, bizjet and 3 helis keep their kinds (test_airport_aircraft premise); roster via 2nd airliner + 4 crossers
- tests PASS: test_air_w126, test_air_w126_b, test_airport_aircraft, test_campaign_runner, test_controls_w118, test_touch_audit, test_world_missions_air, test_mission_board
- tests/bot_w126_air.gd (frames: traffic, gunship HUD, rockets, lock, flares, bomb ring/blast, crate, board)
- frames looked at (LOW, 1200x540): gunship HUD clean (VIEW/ARMS top chips, ROCKET 28, FLARE 12 MID), lock box red, bomb falls, board shows DOGFIGHT card
- fixes from the frames: airborne aircraft drawn to 900 m (Vehicle.update_lod hid everything beyond 140 m: bandits invisible), bomb marker clamped to the screen edge, board icons/tints for air types
- MED frames looked at: bandit now visible inside the lock box; bomb chevron moved off the DOWN button (kept to the middle lane); board DOGFIGHT red target icon
- perf (PERF_CHECK=1, no limit touched): LOW draws=74 total=96 death=107 OK; MED 99/131 prims 275k death=146 OK; HIGH 118/154 death=164 OK
- final: test_air_w126 PASS, test_air_w126_b PASS
NEXT:
- done (report sent). Open: cargo crate frame not rendered (bot did not board the cargo plane at MED); crate has no chute mesh yet
- (old list) run test_airport_aircraft, test_campaign_runner, test_controls_w118, test_touch_audit, test_world_missions_air, test_mission_board
- renders (bot.sh) of flight HUD with new buttons, crate/bomb, traffic specks; perf at end
DECISIONS:
- switch W126A_OLD=1 (AirArms.on / AirMissions.on / AirTraffic.roster_on)
- w126-planes: arms come from PlaneRoster.DEFS role (AirArms.ROLES) unless spec has "arms"
TESTS AND PERF:
- test_airport_aircraft: 1 fail (jet unlocked missile missed) -> fixed by aiming unlocked missiles at the crosshair; rerun pending
OPEN PROBLEMS:
- test_helis_w125 FAILS h_scout/h_police "stands on the HELI LINE": caused by w126-planes' PLANE LINE (passes with W126_PLANES_OLD=1, fails with W126A_OLD=1) -> for w126-planes / integrator
