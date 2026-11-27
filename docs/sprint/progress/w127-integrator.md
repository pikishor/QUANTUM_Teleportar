GOAL: integrate wave 127 (tanks, arms, critic): import, full suite, perf, visual_qa, touch reruns, HANDOFF, commit+push.
DONE:
NEXT: import; full suite in background (scratchpad/suite127, runner scratchpad/suite.sh, res.txt); triage vs HEAD copy; perf; visual_qa; touch reruns; handoff; commit.
- suite running (scratchpad/suite127/res.txt). HEAD copy at scratchpad/head127 (imported).
- FIX 1: test_blast_arsenal flake (old since w126: fails 1/3 on HEAD too): AirArms/TankArms registered runtime blasts at make(); now each joins BlastTable when it first goes off (ensure_blast in air_arms.gd, tank_arms.gd, air_rockets.gd _detonate, fire_smoke). Check tests/test_blast_registry_w127.gd (old: 2 FAIL; new PASS). arsenal probe 3/3 PASS after.
- TODO after suite: rerun air_w126 a/b, tank_arms_w127 a/b/c, blast_arsenal (my fix touches them).
- FIX 2: test_planes_w126 FAIL (3/3 on wave tree, PASS on HEAD): ARMY BASE row (x 1362) stood in ARMY SHELTER 1's exit lane; the fighter rolled out into t_heavy and blew up. BASE_X 1376 in tools/gen_tank_roster.py, regenerated tank_roster.gd (only BASE_LOCAL changed). Rerun planes_w126 + tanks_w127/_b pending.
- test_integration FAIL both tries = 120 s timeout under load (node count 3069 OK); compare alone vs HEAD later.
