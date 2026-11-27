# w128-open (done)

agent id a027ceeef33f6b013, 423 events, first activity 2026-11-27T16:21:48.007Z, last activity 2026-11-27T17:12:08.686Z

## Final report

I fixed 8 of the open items; the rest, including tank missions finishing by normal play, are still open. Every fix has a check in godot/tests/test_w128_open.gd. The checks drive main.tscn with real finger events and the phone-only layers on. W128O_OLD=1 switches the old code back on, and every check marked [old fails] failed with it before passing. The full file passes in 41 s alone and in 104 s with 3 tests running. FIXED, with the check that proves each: 1. Street props no longer stop tanks. A tank driven by the stick into a lamp, signal, hydrant, bench, bin or other street-kit piece knocks it down and drives on. Debris flies, the drawn prop and its glow disappear, and the prop comes back once the hero is 160 m away. Old code: the tank stopped after 8.4 m at the lamp and 0.1 m at the kit piece. I looked at the frames. 2. Car-to-car contacts respect height. A van on the ground under the MOUNTAIN TRACK bridge was shoved 2.48 m by a car on the deck above; now it does not move. 3. Demo mode: god mode and infinite ammo are on from the start and stay on after launches. New VEHICLES tab (55 kinds) and AIRCRAFT tab (56 kinds). A finger on an entry puts the vehicle next to the hero (planes go on the runway) and ENTER boards it. I also moved the DEMO badge, which covered the FLY and CROUCH buttons. In test_demo_mode.gd I updated the god-mode check to the new default: on at start, then a finger switches it off and on again. 4. A tank crew whose vehicle was freed caused a script error every frame; the crew is now dropped. 5. On-foot player script cost: the weapon number-key check per physics tick fell from 205 µs to 1.3 µs. The player physics step went from about 666 µs to 223 µs per tick (probe tests/probe_w128_player.gd). 6. test_campaign_runner script error at line 980: the check behind it now actually runs and passes. NOT DONE: - Tank missions still finish only through the stuck skip. A finger-play probe shows props no longer block the tank. The probe's own steering still hugs the sidewalk into building corners. The drive leg is 3.2 to 3.5 km. - Not attempted: LOW airfield draws, MED triangle headroom, outskirts flight draws, base and checkpoint booths and fences, amphibious swimming, hover tank and walker physics, convoy driving, tank hull catching on parapet tops, the cargo-plane boarding flake, and the two retry-only flaky tests. - Overhead street wires stay when their lamp is knocked down. Other tests: test_w127_critic, test_w127_ci, test_demo_mode, test_demo_menu, test_vehicle_overlap, test_tanks, test_weapons and test_campaign_runner all pass. Perf, run once, no limit changed: LOW OK (death draws 107). MED draws 99, total 131, triangles 274k, death 146, OK. HIGH draws 118, total 154, death 164, OK. Files touched (under godot/): - scripts/world/city_colliders.gd, city_stream.gd, city_kit_window.gd, city.gd - scripts/vehicles/vehicle.gd, vehicle_manager.gd - scripts/demo/demo_mode.gd, scripts/ui/demo_panel.gd - scripts/enemies/tank_crews.gd, scr...

## Last notes of the agent

- 16:25:47 Now writing the test (props and hull parts first).
- 16:26:39 Run old then new (props + hulls) in parallel.
- 16:30:22 Meanwhile, the demo mode work. Let me look at DemoMode.
- 16:32:51 Now add the demo part to the test.
- 16:54:08 Run the mission probe in the background (tank battle by finger with the new prop knock).

## Recent steps (last 40)

- 16:54:06 Check runner timeout option and stuck detection in probe
- 16:54:11 Run tank battle mission probe by finger
- 16:54:13 Read cpu_frame tool and PLAYER timer
- 16:54:17 Measure CPU per system on LOW
- 16:54:47 Find PLAYER timer spans
- 16:54:49 Read player physics process
- 16:54:54 Read player _process_body
- 16:54:59 Read camera rig/weapon spans and update_view
- 16:55:11 Probe player cost by part
- 16:55:39 Read physics body start
- 16:55:40 Read swim tick
- 16:55:49 Probe sub-parts of foot tick
- 16:56:16 Read poll_switch
- 16:56:24 Check weapon number actions
- 16:56:26 Find where weapon number actions are defined
- 16:56:29 Find dynamic action creation
- 16:56:38 Cache weapon number key actions
- 16:56:40 Read traversal tick and swim probe
- 16:56:48 Compare player parts old vs new
- 16:57:25 Show new probe and fight results
- 16:57:31 Read kit window structure
- 16:57:35 Read kit window fill and kit vars
- 16:57:42 List kit kinds with colliders
- 16:58:01 Make kit props knockable and hideable
- 16:58:23 Generalize ram check incl. kit pieces and run
- 16:59:13 Rerun tank battle probe with kit knock
- 16:59:14 Read probe route driving
- 16:59:19 Route lines from first probe
- 16:59:22 Read WorldRoute.route
- 16:59:24 Read _car route
- 16:59:26 Read rest of _car route
- 16:59:37 Find how step 1 completed
- 16:59:58 Add player cost check and run
- 17:00:29 CPU frame old vs new, weapons test
- 17:01:26 Update log; check second probe
- 17:01:39 Run perf gate once
- 17:10:52 Summarize perf and probe outcome
- 17:11:10 Write handoff and final log; check tree
- 17:11:15 Run full new test once
- 17:12:08 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/test_w128_open.gd
- godot/tests/bot_w128_open.gd
