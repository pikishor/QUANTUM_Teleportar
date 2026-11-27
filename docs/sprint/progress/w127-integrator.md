GOAL: integrate wave 127 (tanks, arms, critic): import, full suite, perf, visual_qa, touch reruns, HANDOFF, commit+push.
DONE:
NEXT: import; full suite in background (scratchpad/suite127, runner scratchpad/suite.sh, res.txt); triage vs HEAD copy; perf; visual_qa; touch reruns; handoff; commit.
- suite running (scratchpad/suite127/res.txt). HEAD copy at scratchpad/head127 (imported).
- FIX 1: test_blast_arsenal flake (old since w126: fails 1/3 on HEAD too): AirArms/TankArms registered runtime blasts at make(); now each joins BlastTable when it first goes off (ensure_blast in air_arms.gd, tank_arms.gd, air_rockets.gd _detonate, fire_smoke). Check tests/test_blast_registry_w127.gd (old: 2 FAIL; new PASS). arsenal probe 3/3 PASS after.
- TODO after suite: rerun air_w126 a/b, tank_arms_w127 a/b/c, blast_arsenal (my fix touches them).
- FIX 2: test_planes_w126 FAIL (3/3 on wave tree, PASS on HEAD): ARMY BASE row (x 1362) stood in ARMY SHELTER 1's exit lane; the fighter rolled out into t_heavy and blew up. BASE_X 1376 in tools/gen_tank_roster.py, regenerated tank_roster.gd (only BASE_LOCAL changed). Rerun planes_w126 + tanks_w127/_b pending.
- test_integration FAIL both tries = 120 s timeout under load (node count 3069 OK); compare alone vs HEAD later.
- planes_w126 PASS after fix 2 (fighter 133 m, hp 900).
- FIX 3: test_world_missions FAIL (5/6, 3/6; HEAD 6/6): TankMissions.inject overwrote the last card = the lodge's world mission. Now overwrites the last ordinary card only (tank_missions.gd); tidied a comment in mission_board.gd.
- suite DONE: FAIL integration, planes_w126 (fixed), world_missions (fixed); FLAKY blast_arsenal (fixed), flight_view_w116, floors_w121 (my mid-edit parse error), hud_camera_final, mission_audit, shooting_accuracy, touch_audit, w119_critic. NEXT rerun those.
- reruns all PASS (17 files incl. world_missions 6/6, tank_arms a/b/c, tanks_w127 a/b, air_w126 a/b, blast_arsenal, blast_registry, flakies). integration PASS alone (new and HEAD). NEXT perf.
- perf OK: LOW 72/94 death 109; MED 99/131 prims 275k death 146; HIGH 118/154 death 164. NEXT visual_qa
- visual_qa 27/27 PASS, latest.png looked at; army base frame (new x 1376) looked at LOW 1200x540. NEXT touch reruns (scratchpad/re127/b)
- touch reruns PASS (9 more); tidy done; HANDOFF section added. NEXT commit + push
- DONE: committed bdab8a8 and pushed
