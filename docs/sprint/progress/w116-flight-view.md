# w116-flight-view progress log
GOAL: a clear view and honest controls in the air (overlays out of the centre, vehicle script cost in flight, touch audit of SNAKE / ZIP / FLY / LAND / BOOST / UP).

## DONE
- read ROUND7, PLAN_116_150, ROUND6 rules, HANDOFF tail; owner frames: the "radial rays" are the REWARD CARD's rays + dim (scripts/ui/crate_reveal.gd), the light-blue bands are the wing snakes.
- godot/scripts/quantum/flight_view.gd (class FlightView, NEW; tools/import.sh run): wing shape / bow / flutter / thickness, speed-line uniforms, view_needed(); `FlightView.old_look` = wave 115 look.
- godot/scripts/quantum/snake_flight.gd: wings read FlightView (1.45 to 1.9 m a side, was 3 to 4.8); LOW_START: FLY pressed under 3.2 m over the ground is a take-off (was: flight ended on the floor after 15 ticks).
- godot/assets/shaders/snake_speed_lines.gdshader + snake_fx.gd: box-distance mask (outer band only), alpha 0.2, uniforms pushed from FlightView.lines_params().
- godot/scripts/ui/crate_reveal.gd: `air` card (FlightView.view_needed): scale 0.5 flush left, no dim, no rays; card_rect().
- godot/scripts/quantum/snake_traversal.gd: FLY_SHOW_AIR 0.15 (was 0.3).
- tests/bot_w116_flight_view.gd + tools/flight_view.sh (freeze + layer diff pixel test), tests/w116_fingers.gd (real finger helper), tests/dev_w116_air_touch.gd (probe).

## NEXT
1. (a) look at before / after frames (scratchpad fv/low_old, fv/low), tune wings, run MED, copy sheets to docs/shots/round7.
2. (b) measure VEHICLES script time in the air (ambient_city near_traffic / road_traffic / parked + VehicleManager), cut.
3. (c) zip failures (roof zip that ends on the street 3 of 7, wall zip = hangs on the wall), label ZIP -> fly; MORE tray closes at take-off.
4. tests/test_flight_view_w116.gd (touch driven, old-behaviour trials via FlightView.old_look / SnakeFlight.low_start), related tests, perf gate once at the end.

## DECISIONS
## TESTS AND PERF
## OPEN PROBLEMS
## FOR WAVE 117
