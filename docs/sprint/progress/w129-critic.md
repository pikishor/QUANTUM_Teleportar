# w129-critic progress log
GOAL: independent review of wave 129 (machanim, tankmis, airdraws) with a finger-only bot; list 8 worst defects; fix most severe first, each with a check failing on old code.
DONE:
- read ROUND7, PLAN, ROUND6 rules, HANDOFF tail.
- builder tests: machanim_w129 PASS, airfield_w129 PASS, tankmis_w129 PASS, tankmis_w129_c FAIL 2/8 (artillery: 18 shells on one tank, rounds ran out).
- review bot godot/tests/bot_w129_critic.gd (finger only; C_MODE=heli|planes|ground|sit|night), frames in scratchpad c129/.
- FIX 1 howitzer marker lock (TankArms._ray_lock, RAY_LOCK 0.035 rad, lock_on; W129C_OLD=1 = old). Check tests/test_w129_critic.gd part howitzer: old FAIL 3/4 (6 px low -> 40.5 m off, 23 px high -> 235 m off, no hit), new PASS.
NEXT:
1. run builder tests (machanim, tankmis*, airfield_w129) to see they pass
2. review bot tests/bot_w129_critic.gd: heli + 2 planes, tank/car/bike, missions, draws, night, wreck
3. list defects, fix, check tests/test_w129_critic.gd (W129C_OLD=1 = old)
DECISIONS:
TESTS AND PERF:
OPEN PROBLEMS:
