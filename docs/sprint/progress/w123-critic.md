GOAL: w123-critic: independent review of wave 123 (clutter + street life), 8 worst defects, fix most severe first with failing-first checks.
SWITCH: StreetLife.critic (env W123C_OLD=1 = wave 123 as built).
DONE (check: godot/tests/test_critic_w123.gd, fingers, phone layers; new PASS 7/7, W123C_OLD=1 FAIL 5 of 7):
- D1 walkers walked through kerb props (old ~3.8% samples): scripts/ambient/crowd_dodge.gd (preload) + _dodge in ambient_crowd.gd. New 0.1%.
- D2 sitters in kiosks/kit clusters (35/638 seats), waiters on lamps (6/96 spots): StreetLife.solid_at, _bad_b/_bad_w; city_kit._clear_benches drops kit props on bench seats.
- D3 bench set (StreetDress) not solid: SPECS StreetDress box (city_colliders.gd); bench sets slid along the front out of door lanes (city_props.gd).
- D4 scared / standing sitter walked along the bench row: ambient_crowd._unpin -> _reline.
- Other tests: test_clutter_w123 PASS, test_life_w123 PASS once, then door-frame JUMP check failed (also fails with W123C_OLD=1: not mine, flaky).
OPEN: door-frame JUMP flaky (w123-life); car parked on the sidewalk in frame /tmp/claude-0/w123c/b/d_bench_1.png; "BLACK MARKET SHOP" label over NEON sign; node count 2995 at start vs 3000 limit; prop-prop clipping 35 pairs (old 44); bus never dwelled in 5 probe walks.
PERF: done once, LOW/MED/HIGH OK. Report sent.
