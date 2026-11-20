# w116-touch-audit progress log
GOAL: a touch-only audit of every pressable control in the real main scene, every dead / wrong / trapped control fixed, the audit kept as permanent tests.
DONE (all files under godot/):
- tests/touch_audit_lib.gd: the engine (no class_name: `const Audit := preload(...)`). Boots main.tscn as a phone (844x390, force_touch, CrateReveal._quiet = 0), a real finger
  (finger_down / finger_up / finger_move / tap / fast_tap / drag / back_key: InputEventScreenTouch + Drag through Input.parse_input_event, window coordinates; the BACK key walks the
  window notification in the engine's order), controls() = Hud.buttons + the TouchControls discs + pause + minimap + wheel discs + every Godot Control; crawl() walks the menu graph
  breadth first by finger (one row per control: nav / state / sound / dead / gone), geometry() = the area that answers in real px + overlaps + off screen, press_hud_frame(),
  press_nodes(), panel_controls() (TEST / DEMO menus), hud_target() (measured hit area).
- tests/test_touch_audit.gd (part 1, the play HUD, 208 checks, 35 s), tests/test_touch_audit_menus.gd (part 2, title + pause crawl, 33 checks, 70 s),
  tests/test_touch_audit_screens.gd (part 3, first minute, map, ALL EXTRAS, photo, TEST, DEMO, vendor, fast travel, result card, death, 124 checks, 60 s; TA_ONLY=map,demo runs steps).
- tests/bot_touch_audit.gd: the same engine with a PNG per screen (TA_OUT, TA_PARTS, TA_EXTRAS; header of the file has the command line).
FIXES (each has a static A/B switch; the tests show the old behaviour first, lines "OLD BEHAVIOUR ..."):
1. scripts/ui/back_key.gd (new class BackKey, hook in Hud._ready): the phone BACK key CLOSED THE GAME everywhere (engine default quit_on_go_back; only the map listened, and the game
   still quit). Now: closes the top screen, one step back in menus, resume from pause, pause from play, leaves the app only from the plain title. map_screen.gd: its own handler
   stands down (one owner). Switch BackKey.enabled.
2. scripts/ui/touch_controls.gd: a tap that goes down and up inside one frame (a thumb at 13 to 30 FPS) released its action before any physics tick: SNAKE, FLY / LAND, FIRE, JUMP
   polled nothing. The release of such a tap waits one physics tick + one process frame (_late, _flush_late; only on the real input path, touch_up(id) called directly is as before).
   Switch TouchControls.hold_fast_taps. Old: 0 of 3 quick taps reach the game.
3. scripts/ui/hud.gd _button_at + UiUtil.TOUCH_TARGET (82 base px = 44 px at 844x390): every drawn menu button answers in an area at least 44 px across, the nearer plate wins.
   Switch Hud.finger_targets. Old: 7 targets of the first OPTIONS tab under 44 px (34 px rows), new 0. scripts/interiors_gameplay/vendor_screen.gd: CLOSE was a 27 px target.
4. scripts/story/story.gd: a story card swallowed a tap on PAUSE (3 cards after PLAY and after DEMO: PAUSE dead for 3 taps). PAUSE passes. Switch Story.pause_passes.
FINDINGS TABLE (640 controls pressed by finger; rows: context | controls | result):
- HUD foot 5, MORE 11, car 2+4, heli 4, plane 4, gunship 5, tank 4, snake flight 5, interior 4: all actions down and up; vehicle guns fire; DOWN / UP / VIEW / RADIO answer.
- wheels: weapon wheel level 1 (classes) -> level 2 (ring) -> weapon in hand; ability wheel tap, cast, close: OK. Ability wheel: 11 discs of 38 px (42 px hit): under 44, NOT fixed.
- garage 17 Buttons (SAVE, 12 paints, 4 upgrades): one press each, CLOSE + BACK key OK; paints 48 x 35 px: under 44, NOT fixed (Godot Buttons, layout).
- title 8 screens / 91 controls, pause 14 screens / 213 controls (LOADOUT + WEAPONS tiles, GEAR, UPGRADES, SUIT, MISSIONS, OPTIONS 5 tabs + CONTROLS): 0 dead, 0 trapped,
  BACK key leaves every screen, no Button double-fire, no overlap. Still under 44 px after fix 3 (rows packed tighter than 82 base px): 38 title + 82 pause targets of 36 to 43 px
  (OPTIONS > GRAPHICS / ACCESS rows, CONTROLS rows, Arsenal chips, GEAR loadout rows, SUIT hue swatches). Pinned in the test (KNOWN_SMALL), may only go down. Wave 137 owns it.
- ALL EXTRAS: skills, craft, side, heists, safehouse, achievements, arena, suit: 150 controls, 0 dead, 0 trapped, BACK key OK.
- map: 12 buttons / chips one press each, tap = waypoint, drag = pan, pinch = zoom, YOU, GOAL, CLEAR, CLOSE (back to the pause menu it came from), MISSIONS -> board, BACK key.
- TEST menu 9 tabs + rows + scroll, DEMO menu 21 tabs / rows + QUIT DEMO, demo: tile -> EQUIP -> weapon in hand, no reward card; vendor BUY rows + CLOSE; fast travel list
  (one press, travels 1372 m); result card NEXT; RESPAWN: all OK.
- not a defect, noted: GOAL / CLEAR / YOU on the map do nothing when there is no route / waypoint / pan (no sound either); story cards still eat a tap on FIRE (by design).
NEXT / NOT DONE: photo mode only 2 of its controls were pressed (the first press hides the rest: extend); cutscene SKIP, tutorial cards, benchmark panel, the watchdog BACK
  (r7 test covers it), the FPS box in the pause menu (a tap under the minimap cycles the tier while paused, only when the FPS readout is shown) are not in the audit.
DECISIONS: UiUtil.TOUCH_TARGET = 82 base px. BackKey.last / handled / quits (tests). The tests never set Engine.time_scale. test.sh runs must not share a user dir in parallel
  (test_touch_buttons_r7 failed 2 checks when run beside my tests in one user dir; alone PASS): use XDG_DATA_HOME per run.
TESTS AND PERF: test_touch_audit PASS, test_touch_audit_menus PASS, test_touch_audit_screens PASS (three at once: PASS), test_touch_buttons_r7 PASS, test_touch, test_hud,
  test_hud_camera_final, test_hud_declutter, test_menu_cut, test_menu_declutter, test_options, test_title_buttons, test_demo_mode, test_radio_ui, test_interior_gameplay_vendors,
  test_weapon_ui_v3, test_ui_debt3 PASS. Perf gate: see the end of this file.
PERF GATE (PERF_CHECK=1 tools/perf_report.sh, run twice, the second time HIGH only):
- LOW draws=71 prims=128663 tex_mb=120 death_draws=108 verdict=OK; MED draws=100 prims=240939 tex_mb=143 death_draws=148 verdict=OK
- HIGH draws=112 prims=329566 tex_mb=217 lights=11 death_draws=175 verdict=OVER (death spike 175 > 170); second run death_draws=174 OVER.
  NOT from this agent: its changes draw nothing (input and hit tests, BackKey is a plain Node). Wave 115 had HIGH death 169 of 170, tex 209 MB, lights 7; the tree holds other
  agents' edits (snake_fx, snake_speed_lines shader, atmosphere_rain, road_traffic, city_layout, vehicle_manager, crate_reveal). No limit was raised. The integrator must find the 5 draws.
OPEN PROBLEMS:
- HIGH perf gate OVER by 4 to 5 death draws (see above).
- A gunship that rests on something that is not ground stays "airborne": EXIT says LAND TO GET OUT and DOWN cannot land it (1 of 9 loaded runs; test prints a NOTE line). Not fixed.
- Under three parallel copies part 1 is green 3 of 3 after the last changes (quick-tap check counts physics ticks, the ability wheel opens by a quick tap, vehicle guns fire to the first shot).
