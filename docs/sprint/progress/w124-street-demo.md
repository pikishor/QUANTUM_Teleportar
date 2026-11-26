# w124-street-demo progress
- step 1: plan = Part 2 first (demo WEAPONS tab + MAX MONEY / UNLOCK ALL toggles + test_demo_god_w124.gd), then Part 1 street items as time allows.
- step 2 DONE: demo WEAPONS tab (every id, stays open, lit = in hand), TOOLS gets MAX MONEY + UNLOCK ALL; DemoMode.equip_weapon/max_money/unlock_all. tests/test_demo_god_w124.gd PASS (old code: FAIL 3 checks).
- step 3 DONE: bug found by tests/test_demo_god_w124_missions.gd: after a CHASE the hero stayed at the wheel and every STEALTH entry refused; DemoMode._prepare now exits the vehicle. PASS (old: STEALTH FAIL).
- next: Part 1 street items (not started).
- step 4 DONE: class headings in WEAPONS (labels no longer clipped), frames looked at 2400x1080 LOW + 1200x540 MED. Part 1 street NOT started; perf gate not run (UI-only change). Handing back.
