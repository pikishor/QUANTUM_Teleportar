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

## NEXT
1. look at scratchpad fv2/low frames (new camera + wings + rain), tune, run MED and the old look on MED, copy sheets to docs/shots/round7/.
2. tests/test_flight_view_w116.gd (touch driven; old-behaviour trials through the switches above) + tests/test_zip_roof_w116.gd; run them and the related old tests
   (test_snake_traversal, test_critic_look_w115, test_play_critic_w115, test_snake_swing_run, test_atmosphere, test_touch_buttons_r7, test_vehicles*, test_traffic*).
3. perf gate once at the end; ARCHITECTURE / HANDOFF notes; final report.

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

## FOR WAVE 117 (measured by real fingers, tests/dev_w116_air_touch.gd)
(filled at the end)
