# w129-critic progress log
GOAL: independent review of wave 129 (machanim, tankmis, airdraws) with a finger-only bot; list the 8 worst defects; fix the worst, each with a check that fails on the old code.
DONE:
- read ROUND7, PLAN, ROUND6 rules, HANDOFF tail.
- builder tests at start: machanim_w129 PASS, airfield_w129 PASS, tankmis_w129 PASS, tankmis_w129_b PASS, tankmis_w129_c FAIL 2/8 (artillery: 18 shells on one tank, rounds ran out).
- review bot godot/tests/bot_w129_critic.gd (fingers; C_MODE=heli|planes|ground|sit|night|wreck|taxi|hood|tankfire), frames in the scratchpad (c129/).
- FIX 1 howitzer crosshair locks on a target within RAY_LOCK 0.035 rad (TankArms._ray_lock, lock_on). part howitzer: old 6 px low -> 40 m off, 23 px high -> 235 m off, no hit; new 0 m, hit.
- FIX 2 tank missions made the hero WANTED (TANK BATTLE heat 2.8-5.0, 3 police cars): TankSteps.heat_hold, TASK_HEAT_CAP = 0.8 * COP_STAND_DOWN. part battle: new heat 0.23-0.29, 0 police.
- FIX 3 held enemy crews coasted 1.0-1.6 m with the throttle cut: TankCrews.hold_brakes. part battle: old 1.1-1.3 m, new 0.0 m.
- FIX 4 a husk was cleared at 25 s in full flame (fire 28 s, 42 s armour): VehicleManager.husk_burns_out clamps the fire to respawn_time - HUSK_SMOULDER (6 s). part husk: old cleared at 24.9 s with 3 s of fire left, new fire out at 19 s, husk still standing.
- Dropped: "ENTER boards the yard APC" (bot placement artifact; reach_car already prefers mission_ride). Reverted.
- tests/test_w129_critic.gd: W129C_OLD=1 FAIL 6 of 16 (all six [old fails]); new PASS (about 40 s).
- Regression PASS: test_vehicles, test_vehicle_logic, test_stability, tank_arms_w127 a/b/c, tanks_w127 a/b, w127_critic, tankmis_w129 a/b/c (c twice, 6 shells for 3 targets), machanim_w129.
NEXT: perf gate once (PERF_AIR=0), HANDOFF note, report.
DECISIONS: switch W129C_OLD=1 (TankArms.lock_on, TankSteps.heat_hold, TankCrews.hold_brakes, VehicleManager.husk_burns_out).
OPEN PROBLEMS (found, not fixed):
- Airfield draws in a vehicle: LOW 113-151 (budget 100), MED 149-175 (140) (SIT views); the air gate airdraws added makes PERF_CHECK exit 1.
- Fighter on the apron: stick forward 0.3 = full throttle, 251 km/h into the terminal in seconds, hero thrown out on foot inside the terminal (flight model, not w129).
- Alien fauna (DUNE MAW worm, spiders) rises on the apron beside parked aircraft and fills the view (not w129).
- Fighter hood view: pilot helmet dome bottom centre; helicopters have no nav lights at night; LOD1 control-surface double (builder).
- Builder bot placement for planes on the runway side: ENTER never shows (bot side, my planes mode).
