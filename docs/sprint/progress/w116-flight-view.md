# w116-flight-view progress log
GOAL: a clear view and honest controls in the air (overlays out of the centre, vehicle script cost in flight, touch audit of SNAKE / ZIP / FLY / LAND / BOOST / UP).

## DONE (all uncommitted in the tree; paths under godot/)
- Owner frames read: the "radial rays" are (1) the REWARD CARD's rays + dim (scripts/ui/crate_reveal.gd) and (2) RAIN stretched to 2 m lines at flight speed; the light-blue bands are the wing snakes.
- scripts/quantum/flight_view.gd (class FlightView, NEW, tools/import.sh run): wing shape / bow / flutter / thickness, speed-line uniforms, fly_lens_height, view_needed(); `FlightView.old_look` = wave 115 look.
- scripts/quantum/snake_flight.gd: wings read FlightView (1.45 to 1.9 m a side, was 3 to 4.8); LOW_START: FLY under 3.2 m over the ground is a take-off (was: back on the floor after 15 ticks).
- scripts/quantum/snake_camera.gd: flight lens height from FlightView (+0.42 .. +0.6, was -0.35 .. -0.1): the crosshair looks over the hero's head, not through his back and the wing roots.
- assets/shaders/snake_speed_lines.gdshader + scripts/quantum/snake_fx.gd: box-distance mask (outer band only), alpha 0.2, uniforms from FlightView.lines_params().
- scripts/ui/crate_reveal.gd: `air` card (FlightView.view_needed): scale 0.5 flush left, no dim, no rays; card_rect().
- scripts/fx/atmosphere_rain.gd: streak stretch follows the camera up to 18 m/s only, streaks dim to 40 % at 70 m/s (`long_streaks` = old).
- scripts/quantum/snake_traversal.gd: FLY_SHOW_AIR 0.15 (was 0.3); the press that zipped starts no flight (`zip_takes_press`); a take-off closes the MORE tray.
- scripts/quantum/snake_zip.gd: roof zips rise early and come in over the edge (`roof_arc`); end_reason / blocked_by.
- (b) scripts/world/city_layout.gd road_point_near exits at once outside the grid (`far_exit`, counters searches / passes); scripts/vehicles/vehicle_manager.gd spawn point table kept 12 s
  (`cache_points`, point_builds); scripts/ambient/road_traffic.gd one free slot per respawn pass (`one_try`, spawn_calls).
- tests/bot_w116_flight_view.gd + tools/flight_view.sh (freeze + layer diff pixel test), tests/w116_fingers.gd (real finger helper), tests/dev_w116_air_touch.gd (touch probe),
  tests/dev_w116_vehicle_air.gd (VEHICLES probe).

## NEXT (restart 2 state)
- DONE after the restart: tests/test_flight_view_w116.gd PASS (32 checks), tests/test_flight_cost_w116.gd PASS (15 checks); tools/flight_view.sh LOW 13 of 13 shots PASS
  (centre 0.2 to 3.1 %, crosshair 0.00 %), MED 9 of 9 fly + swing PASS (bot timed out under load; zip + rain rendered apart into flight_view/zr); frames looked at (sheet
  docs/shots/round7/flight_view/after_low.jpg); old tests PASS: test_snake_traversal, test_snake_swing_run, test_snake_combat, test_play_critic_w115, test_atmosphere,
  test_touch_buttons_r7 (alone; 4 map checks fail when 2 other Godot jobs run), test_rewards_progression, test_traffic_ai, test_traffic_density, test_vehicles, test_vehicles_city,
  test_vehicle_logic, test_big_city.
- RED, NOT RESOLVED: tests/test_critic_look_w115.gd 4 checks: (1) "a parked sedan stands beside the hero" (also red with my three vehicle switches set to old; the list is 4 of cap 5
  before the prep and the streamer fills it; cause not found); (2) three wing checks pin the wave 115 span (tip more than 1.6 m out, unclipped tip 0.3 m through a wall 1.0 m away);
  the wings are 1.3 m out now on purpose. I did not edit that test (rule 3): the integrator / owner decides between the old span and the clear view.
- MED rain shots FAIL the picture gate: rain 13.2 / 13.9 % of the centre (limit 4 %), thin short drops, not rays; LOW rain 0.4 %. NOT FIXED (next: fewer / fainter drops on MED while FlightView.view_needed()).
- PERF (2 runs, the allowed number): LOW draws=71 death=110 OK; MED draws=100 death=148 OK; HIGH draws=112 death 176 then 175 of 170 OVER (wave 115: 169; lights 7 -> 11). Cause not isolated.
- HANDOFF section written. Frames converted to jpg (docs/shots/round7/flight_view, low + med, sheet after_low.jpg). TASK ENDED HERE; nothing committed.

## DECISIONS (numbers other agents depend on)
- Pixel limits of tools/flight_view.sh: in-air layers (wings + speed lines + rain + fx + reward card) <= 4 % of the central 60 % x 60 % of the frame, <= 0.5 % of the crosshair disc (radius 8 % of the height).
- Old-behaviour switches (all static, default = new): FlightView.old_look, SnakeFlight.low_start, SnakeZip.roof_arc, SnakeTraversal.zip_takes_press, CityLayout.far_exit,
  VehicleManager.cache_points, RoadTraffic.one_try, RainField.long_streaks.

## TESTS AND PERF (so far)
- Before (FV_OLD=1, LOW 1200x540): wings 4.6 to 8.2 % of the centre, 12 to 16 % of the crosshair disc; reward card 99 %; rain 1.5 % at boost. 9 of 13 shots FAIL.
- VEHICLES probe (desktop, LOW+, flying at 60 m/s over the hills): before avg 0.6 to 6.7 ms with peaks 4.7 to 28.9 ms per 3 s window; after avg 0.16 to 0.53, peaks 0.4 to 1.3 (one 4.2).
  Causes: road_point_near 204 passes every 0.4 s outside the grid (5 to 9 ms), RoadTraffic 512 lane searches in a frame (21 to 23 ms), spawn table rebuilt every second (1 to 1.9 ms).
- Touch probe before: FLY window after JUMP 0.38 s; FLY at 0.77 m falling = 15 ticks of flight; roof zips 4 of 7 and 8 of 12 land; SNAKE held on ZIP -> flight 2 of 10. After: roof zips 10 of 10, hold -> flight 0 of 10.

## OPEN PROBLEMS
- NearTraffic.step costs 0.4 to 0.65 ms a frame on a desktop (about 3 ms on a phone) over the city even 70 m up (the cars under the hero are simulated in full): wave 124.
- The FLY button is not on screen on the ground (pinned by test_snake_traversal "FLY is hidden on the ground"): take-off needs JUMP then FLY within 0.5 s, or SNAKE held 0.65 s with nothing to bite.
- No DOWN button in snake flight (CROUCH lives in the MORE tray; looking down + forward dives).

## FOR WAVE 117 (measured by real fingers, tests/dev_w116_air_touch.gd, headless, MED; W116_PROBE=fly,land,zip,swing,hold)
ZIP
1. The button reads ZIP but the result is not a zip in most presses: of 12 taps on the street looking level, 4 zipped, 6 ended hanging on a wall in CLIMB, 2 did nothing. The label does
   not say which of the three will happen and there is no target marker that tells a roof from a wall.
2. A zip at a wall (13 of 19 targets found from 10 street spots) ends hanging on the facade 3 to 11 m up (mode climb, 4 s later still there): the hero is not put on anything; the
   player must know to press JUMP / climb. Only targets whose roof edge is in reach (5 of 19) put him on a roof (fixed this wave: 10 of 10 land, was 4 of 7).
3. A roof zip covers 25 to 40 m and 22 to 28 m of height in 0.3 to 0.4 s (80 to 100 m/s, steps of 4 to 4.6 m per frame): it reads as a teleport, the camera cannot follow, no ease in / out.
4. SNAKE held 1.3 s on the street: 6 of 10 nothing visible while held and nothing on release, 4 of 10 climb. A hold has no meaning of its own on the ground (in the air a hold with
   nothing to bite starts the flight after 0.65 s).
5. One spot of 10 had no target at all in 56 m: the press does nothing and nothing tells the player why (no "no anchor" cue).
SWING
6. A 10 s hold from the same street gives 190 m in one trial and 45 m in the other (the chain turns back on itself; mean 16 to 20 m/s): the direction of the next anchor does not follow
   the stick / camera reliably.
7. Release speed is uneven: 6.7 m/s ("dead" swing, the chain ends) to 40 m/s in the same chain; rope lengths 24 to 61 m, hang times 0.55 to 3 s. No rhythm.
8. The hero touches the street 3 to 4 ticks in a chain (min height 7.8 m at the lowest point of a 61 m rope is not held) and the body moves up to 3.7 m in a frame.
9. Letting go at 30 m/s 26 m up: 2 s later he is 3 m over the street still at 34 m/s (flung, no air brake, no landing roll); in the other trial he lands on a wall in CLIMB unasked.
10. A tap (not a hold) in the air swings for 14 ticks and drops him on the street: a tap should either be a full swing or nothing.
FLY / LAND / BOOST / UP
11. FLY is not on screen on the ground. Take-off is JUMP then FLY within about 0.5 s (window 0.53 s now, was 0.38 s); a slow thumb (0.5 s) gets no button at all. A ground take-off
    (FLY always there, or JUMP held) is a layout decision pinned by test_snake_traversal "FLY is hidden on the ground".
12. LAND pressed a second time during the landing takes off again (phase power, 14 m/s forward at 0.1 m): the button toggles while its label still reads LAND; UP and the stick are
    ignored during a landing. From 42 m a landing takes 1.6 s (26 m/s down) and ends with the hero 0.4 to 0.5 m over the floor in mode none, falling the rest.
13. Energy: 1.5 s of BOOST costs 53 of 100, 5 s of hover the rest; the flight then ends by itself wherever the hero is. Nothing on screen warns before it ends.
14. No DOWN button in flight (CROUCH is in the MORE tray): descending is looking down + stick, or LAND.
15. BOOST sits on the rim of RELOAD and the weapon button at 1200x540 (frames docs/shots/round7/flight_view): a thumb on BOOST can hit RELOAD.
