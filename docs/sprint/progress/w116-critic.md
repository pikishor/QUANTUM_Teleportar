# w116-critic
GOAL: independent finger-only review of wave 116, list 10 worst defects, fix most severe first.
DONE:
- (restart 2) read docs; no earlier work existed.
NEXT:
- write own finger bot godot/tests/bot_w116_critic.gd, play, look at frames.
- own bot godot/tests/bot_w116_critic.gd (fingers only; CR_OUT, CR_PARTS=foot,screens,car,snake,demo,fly2,photo,fresh). Runs 1-3 on LOW 1200x540:
  walk, look, fire, reload, swap tap, weapon wheel, ability wheel, MORE, jump, car enter/drive/leave, zip, swing, fly, pause+map in flight, photo in/out,
  title -> DEMO -> ABORT TO MENU -> CONTINUE, NEW GAME: all answer a finger.
DEFECTS FOUND (evidence = bot line):
- D1 LAND tapped twice 0.5 s apart cancels the landing: 12 s later still flying at 51 m, label read LAND both times (fly2_land_twice BAD).
NEXT: look at cr3 frames (fresh start, photo), then fix D1 with tests/test_critic_w116.gd, hunt more (zip hang on wall, energy end, cards over HUD).
- D2 (worst) NEW GAME, hands off: every 2 s a traffic car in reach of its door is made real (VehicleManager.reach_car, called each frame by the ENTER prompt) and then slides
  back to the lane's middle INTO the standing hero: pushed 8.5 to 10 m in 14 s, pressed 0.2 m into the road, the picture loses him (frames cr3/72_fresh_02, _04).
FIXED (tests/test_critic_w116.gd PASS 11/11; CRITIC_OLD=shove fails 2, CRITIC_OLD=land fails 3):
- D2 scripts/vehicles/vehicle.gd _ai_step: a car beside the hero keeps its side and passes (Vehicle.hero_pass, HERO_PASS_MIN/CLEAR/TAIL). New: pushed 0.00 m, 7 cars passed.
- D1 scripts/quantum/snake_flight.gd: SnakeFlight.land_guard 0.8 s (a double tap on LAND lands); button_label(): reads FLY once a press would call the landing off
  (scripts/ui/touch_controls.gd _label_of, one line).
NEXT: run old tests of touched files (vehicles, traffic_ai, traffic_density, vehicles_city, snake_traversal, flight_view_w116, touch_audit), re-render fresh start, hunt more.
- D3 pickup feed lay across GRAB (cr1/30_zip.png): scripts/ui/hud.gd (Hud.feed_clear) stops the feed left of every visible button and of the GRAB / FLY spots;
  scripts/ui/hud_feed.gd last_rects. Test part 3; CRITIC_OLD=feed fails 1 (on: GRAB). Test now 13/13 PASS at 1200x540.
- old tests after D1+D2: vehicles, traffic_ai, traffic_density, vehicles_city, vehicle_logic, snake_traversal, flight_view_w116, touch_audit PASS.
NEXT: re-render fresh start + flight (bot parts fresh,fly2) and LOOK; run test_hud*, then perf gate once, HANDOFF note, report.
- frames after the fixes looked at (cr4 fresh start: hero in view in all 6 frames, cars pass beside him; feed left of the buttons). test_hud, test_hud_declutter,
  test_hud_camera_final, test_touch_buttons_r7 PASS. HANDOFF section "Wave 116 critic" written.
TESTS AND PERF (gate run once, after all fixes): LOW draws=74 death=107 OK; MED draws=97 death=150 (limit 150) OK; HIGH draws=113 lights=7 death=170 (limit 170) OK.
THE 10 WORST (1-3 fixed, 4-10 open):
 1 D2 idle hero shoved by traffic after NEW GAME (fixed)   2 D1 double tap on LAND flies on (fixed)   3 D3 pickup feed over GRAB (fixed)
 4 ZIP ends hanging on a wall in CLIMB in about half the presses (flight agent's list #1-2)   5 ZIP with no anchor: nothing happens, no cue
 6 flight energy ends with no warning   7 objective marker + distance ("61 M") drawn on the MORE button (cr1/31_swing.png)
 8 ability wheel: 11 discs of 38 px with unreadable labels (cr1/06_ability.png)   9 the wanted line "HIDDEN FOOT PATROLS" touches the PAUSE disc
 10 MED and HIGH death spikes sit exactly on their limits (150/150, 170/170); test_critic_look_w115 still red on the old wing span (needs a decision).
DONE. Files: godot/scripts/vehicles/vehicle.gd, quantum/snake_flight.gd, ui/touch_controls.gd (one label line), ui/hud.gd, ui/hud_feed.gd,
 tests/test_critic_w116.gd, tests/bot_w116_critic.gd, tests/dev_w116_critic_spawn.gd (probe), docs/HANDOFF.md, this log.
