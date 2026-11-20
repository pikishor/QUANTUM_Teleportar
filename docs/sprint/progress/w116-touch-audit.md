# w116-touch-audit progress log
GOAL: a touch-only audit of every pressable control in the real main scene (tests/bot_touch_audit.gd + tests/test_touch_audit*.gd), fix every dead / wrong / trapped control.
DONE:
- godot/tests/touch_audit_lib.gd: the engine (no class_name; preload it). Boots main.tscn as a phone (844x390, force_touch, CrateReveal._quiet = 0), real finger (finger_down / finger_up /
  finger_move / tap / drag / back_key through Input.parse_input_event, window coordinates), controls() lists every pressable (Hud.buttons, the TouchControls discs, pause, minimap,
  wheel discs, every Godot Control), crawl() walks the menu graph breadth first by finger and files one row per control (nav / state / sound / dead), geometry() = size in real px + overlaps,
  press_hud_frame() holds every HUD button and checks its action goes down and up.
- probes (delete at the end): godot/tests/dev_touch_audit_probe.gd (crawl title / pause), dev_touch_audit_probe2.gd (HUD on foot, MORE, car, heli, plane, gunship, tank, snake flight, interior).
- FIX 1 godot/scripts/ui/touch_controls.gd: `hold_fast_taps` (static, true). A tap that goes down and up inside one rendered frame released its action before any physics tick: SNAKE,
  FLY / LAND, FIRE in vehicles (everything that polls Input.is_action_pressed) never saw it. Release now waits one physics tick + one process frame (_late, _flush_late).
- FIX 2 godot/scripts/ui/back_key.gd (class BackKey, new; hook line in Hud._ready after TouchButtons.ensure): the phone BACK key QUIT THE GAME everywhere (engine default
  quit_on_go_back, only the map listened). Now: closes the top screen, one step back in menus, resume from pause, pause from play, quits only from the plain title.
  tools/import.sh was run for the new class.
NEXT:
- write tests/test_touch_audit.gd (HUD part) with the two old-behaviour trials (TouchControls.hold_fast_taps = false, BackKey.enabled = false)
- crawl with MenuFlags.all_extras (skills, craft, side, heists, safehouse, achievements, arena, chapters), map / garage / fast travel / vendor / TEST / DEMO / photo / result card
- sizes: nearly every menu row is 64 base px = 34 px at 844x390 (39 with Hud's 4 px slop): under 44. Plan: nearest-button slop in Hud._button_at, list what stays under 44.
- TEST SOUND (options > SOUND) made no sound in the crawl: check Sfx &"shot"
- bot tests/bot_touch_audit.gd + frames at 1200x540, perf gate (max twice), HANDOFF + ARCHITECTURE notes
DECISIONS:
- TouchControls.hold_fast_taps and BackKey.enabled are static A/B switches (old behaviour for the tests' "fails on old code" trials). BackKey.last / handled / quits for tests.
FINDINGS SO FAR (table goes here at the end):
- title + pause crawl (default flags): 300 controls pressed by finger, 0 dead except TEST SOUND; no Button double-fire.
- HUD: every action button goes down and up; fast tap lost (fixed); DOWN / UP / VIEW / RADIO / ROCKET / COAX answer.
TESTS AND PERF: none yet.
OPEN PROBLEMS: none blocking.
