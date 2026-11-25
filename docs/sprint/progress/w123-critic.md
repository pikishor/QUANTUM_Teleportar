GOAL: w123-critic: independent review of wave 123 (clutter + street life), list 8 worst defects, fix most severe first with failing-first checks.
DONE:
- probe tests/dev_w123c_probe.gd, tests/dev_w123c_q.gd (dev), LOOK bot tests/bot_w123c_look.gd (frames /tmp/claude-0/w123c/a)
- D1 walkers walk through kerb props (old 3.8% of samples near hero, new kerb row made benches/kiosks worse): new scripts/ambient/crowd_dodge.gd (preload, no class_name), hook in ambient_crowd.gd (_dodge). New: 0.1%.
- D2 sitters on 35/638 benches inside kiosks/kit clusters, waiters on 6/96 spots inside lamps/poles: StreetLife.solid_at + _bad_b/_bad_w skip.
- Switch: StreetLife.critic (env W123C_OLD=1 = wave 123 as built).
NEXT: tests/test_critic_w123.gd (fingers), more defects (car crash into clutter, bus), perf at end.
- D3 sidewalk bench set (StreetDress) had no collider: hero walked through benches people sit on. SPECS StreetDress box (city_colliders.gd), off when W123C_OLD=1; bench sets in a door lane dropped (city_props.gd, 109 before).
- D4 sitter standing up / scared walked on along the bench row (14.2 m from road centre, through shop fronts): ambient_crowd._unpin -> _reline (back to line, eased by _dodge, max 1.8 m/s).
- tests/test_critic_w123.gd: new PASS 7/7, W123C_OLD=1 FAIL 5 of 7.
NEXT: run test_clutter_w123, test_life_w123; more defects; perf at end.
