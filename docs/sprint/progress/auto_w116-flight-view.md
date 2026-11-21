# w116-flight-view (done)

agent id a13995a5f68af899d, 123 events, first activity 2026-11-20T22:22:37.291Z, last activity 2026-11-20T23:03:51.433Z

## Final report

w116-flight-view: REPORT (resumed after restart; nothing committed, nothing pushed). NOT fully green: 3 open reds below. FIXED, each with an old-behaviour trial that fails the same measure (static switches): - View (a): short wings (1.3 m out, was 3.5 m), lens over the hero's head, speed streaks only in the outer band at alpha 0.2 (was from 0.35 at 0.5), small reward card at the left edge in the air (was full card + dim + rays), rain no longer stretched into 2 m rays. Proof: tests/test_flight_view_w116.gd PASS (32 checks, real fingers); tools/flight_view.sh pixel gate LOW 13/13 shots (centre 0.2 to 3.1 %, limit 4; crosshair 0.00 %), before: 9 of 13 FAIL (wings 4.6 to 8.2 %, card 99 %). Frames looked at: docs/shots/round7/flight_view (after_low.jpg). - Vehicles in flight (b): road search outside the grid, spawn table rebuilt each second, 512 lane searches in a frame. VEHICLES 0.6 to 6.7 ms (peaks 29) -> 0.16 to 0.53 ms (desktop). Proof: tests/test_flight_cost_w116.gd PASS (15): 0 passes vs OLD 1632. - Controls (c): FLY pressed low now takes off; FLY window 0.53 s (was 0.38); take-off closes MORE tray; roof zips land 7/7 (old 5/7); held ZIP no longer starts a flight (old 7/7). - 15 measured swing / zip / land defects under "FOR WAVE 117" in docs/sprint/progress/w116-flight-view.md. FOUND, NOT FIXED: 1. MED rain in flight fails my own gate: 13 to 14 % of the centre (limit 4; LOW 0.4 %). Thin drops, not rays. MED 11/13. 2. tests/test_critic_look_w115.gd red on 4 checks: three pin the old wing span (1.6 m; now 1.3 m on purpose). I did not edit the test (an edit was refused as weakening): needs a decision. Fourth, "a parked sedan stands beside the hero", cause not found (also red with my vehicle switches set to old). 3. Perf HIGH OVER, reproduced: death spike 176 and 175 of 170 (wave 115: 169; lights 7 -> 11). Touch-audit agent measured the same. Cause not isolated; my diff adds no node or light but changes traffic spawn timing. 4. NearTraffic.step 0.4 to 0.65 ms over the city at 70 m; FLY absent on the ground (pinned by old test); BOOST touches RELOAD. Other old tests PASS: snake_traversal, snake_swing_run, snake_combat, play_critic_w115, atmosphere, touch_buttons_r7 (alone), rewards_progression, traffic_ai, traffic_density, vehicles, vehicles_city, vehicle_logic, big_city. PERF: LOW draws=71 death=110 OK; MED draws=100 death=148 OK; HIGH draws=112 death=176/175 OVER. FILES (godot/): scripts/quantum/flight_view.gd (new), snake_flight.gd, snake_camera.gd, snake_fx.gd, snake_traversal.gd, snake_zip.gd, assets/shaders/snake_speed_lines.gdshader, scripts/ui/crate_reveal.gd, scripts/fx/atmosphere_rain.gd, scripts/world/city_layout.gd, scripts/vehicles/vehicle_manager.gd, scripts/ambient/road_traffic.gd, tests/{test_flight_view_w116,test_flight_cost_w116,bot_w116_flight_view,w116_fingers,dev_w116_air_touch,dev_w116_vehicle_air}.gd, tools/flight_view.sh, ARCHITECTURE.md; docs/HANDOFF.md, docs/shots/round7/flight_view, the progress log.

## Last notes of the agent

- 22:22:43 Both tests are written. Run them.

## Recent steps (last 40)

- 22:22:38 Read progress log and git status
- 22:22:42 Inspect existing w116 tests and auto log
- 22:22:44 Run the flight view touch test
- 22:24:54 Run both w116 tests with filtered output
- 22:27:32 List rendered frames and doc state
- 22:27:37 Render after frames on LOW and MED with pixel test
- 22:27:38 List related old tests
- 22:27:42 Run related older tests
- 22:27:44 Read the touch probe header and outputs
- 22:27:54 Run the finger probe for the defect list
- 22:31:25 See how the probe measures the FLY window
- 22:31:40 Wait for the old tests to finish
- 22:37:23 Show the failing checks
- 22:37:26 Read the wing checks of the wave 115 test
- 22:37:33 Read wing check code and rerun the two failing tests
- 22:38:41 Inspect vehicle manager diff and the sedan check
- 22:38:50 Rerun the wave 115 test with my vehicle switches set to old
- 22:39:54 Check whether the sedan failure is known
- 22:40:02 Debug why the parked sedan is refused
- 22:40:52 Adapt the stale wing span numbers and rerun
- 22:41:02 Wait for the frame render and show coverage
- 22:46:29 Render the remaining MED zip and rain shots
- 22:46:32 Build a contact sheet of LOW after frames
- 22:46:33 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/fv_low_sheet.jpg
- 22:47:01 Update the progress log with state and the wave 117 defect list
- 22:47:06 Wait for MED shots then run the perf gate
- 22:57:12 Inspect the failing MED rain shot
- 22:57:14 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/rain_med_now.jpg
- 22:57:20 Wait for the perf gate result
- 22:59:40 Second perf gate run for the HIGH tier
- 23:03:13 Find the baseline HIGH perf numbers
- 23:03:16 Check whether my diff adds lights or nodes
- 23:03:37 Shrink frames, write HANDOFF section and final log state
- 23:03:51 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- (none)
