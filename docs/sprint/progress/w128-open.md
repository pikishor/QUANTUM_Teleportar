GOAL: w128-open: finish open items of waves 124-127 (tanks missions/props/perf, demo VEHICLES/AIRCRAFT tabs + god mode, hull height contacts, script errors, flakes, perf headroom), each with a check failing on old code.
DONE:
- (start 2026-11-27) read ROUND7, PLAN, ROUND6 rules, HANDOFF 124-127, w127-*/w128-* logs
- PROPS vs TANKS: city_colliders.gd knock()/down/_restore_far (KNOCKABLE street families), city_stream.gd hide_near/_refresh, city.gd _knock_prop hook, vehicle.gd _move/_knock_prop (cls tank)
- HULL HEIGHT: vehicle_manager.gd hulls_meet_y + hull_height_on in _collide_all
- DEMO: demo_mode.gd god_on_enter (god+ammo on at enter), vehicle_groups/spawn_any (plane -> runway south threshold, one demo vehicle at a time meta demo_v); demo_panel.gd TABS now static var (ALL_TABS filtered), VEHICLES + AIRCRAFT tabs
- tests/test_w128_open.gd parts props/hulls/demo: NEW PASS; W128O_OLD=1 FAIL (props 4, hulls 2, demo 4)
- tank_crews.gd: freed crew vehicle guard (freed_guard_on) + crews part (OLD: SCRIPT ERROR every frame, FAIL)
- DEMO badge moved to the top right of the minimap (demo_panel.gd top_badge_on): it lay on FLY/CROUCH chips; check in demo part
- look bot tests/bot_w128_open.gd frames looked at (lamp knocked + debris, demo tabs, jumbo on runway, heli)
- related PASS: w127_critic, w127_ci, demo_mode, vehicle_overlap, tanks, campaign_runner, demo_menu; test_w128_open full PASS 104 s (3-job load)
- KIT pieces knockable too (city_colliders KIT_MAX_Y 1.5, city_kit_window.gd hidden/hide_at/is_hidden, city.gd kit branch); props part rams a lamp AND a kit piece
- PLAYER: player_weapon.gd poll_switch cached number keys (number_keys, num_cache_on): probe tests/probe_w128_player.gd physics body 666 -> 223 us/tick, poll 174 -> 2.7 us; check part player (OLD 205 us FAIL)
- tank battle probe (probe_w127_critic PARTS=fight): after lamp fix still stuck on Kit props + on a building corner at (38,13) (probe steering along sidewalk); step 1 finished by MissionGuide skip
- test_demo_mode.gd god check updated (starts on; toggles off/on); test_campaign_runner.gd line 980 SCRIPT ERROR fixed (rects read while MORE open) PASS
NEXT:
- done (HANDOFF section "Wave 128 open items" written, report sent)
DECISIONS:
- switch W128O_OLD=1 = old code (knock, hull height, demo god, demo tabs)
TESTS AND PERF:
- PERF_CHECK=1 perf_report 0 1 2 (once): LOW OK death 107; MED draws 99 total 131 prims 274k death 146 OK; HIGH draws 118 total 154 death 164 OK
- 2nd fight probe: no PropCollider stucks left (TowerShell 7, buildings 14, cars 3); step 1 still skipped by MissionGuide
OPEN PROBLEMS:
- tank missions by normal play, LOW airfield draws, MED prims, flight draws, booths/fences, amphib, hover/walker, convoy, parapet lift, cargo flake, device_fixes/damage_everywhere flakes; street wires remain over a knocked lamp
