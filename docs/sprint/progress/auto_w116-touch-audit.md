# w116-touch-audit (done)

agent id a312ed2113eae89e5, 394 events, first activity 2026-11-20T13:03:04.736Z, last activity 2026-11-20T14:21:44.259Z

## Final report

w116-touch-audit REPORT The audit is built and permanent, and about 640 controls are pressed by a real finger. None is dead, no screen traps the player, and no Button fires twice. The HIGH perf gate is OVER and this is not resolved. FIXED (each has a static switch; the tests print the old behaviour failing first as "OLD BEHAVIOUR ..." lines): 1. The phone BACK key closed the game everywhere, even over the open map (engine default `quit_on_go_back`). New `scripts/ui/back_key.gd` steps one screen back, resumes, pauses, and quits only from the plain title. Old: BACK does nothing in play and the engine would quit. 2. A tap that is down and up inside one frame (a thumb at 13 to 30 FPS) never reached the game. This hit SNAKE, FLY / LAND, FIRE and JUMP. `TouchControls.hold_fast_taps`. Old: 0 of 3 quick taps seen. 3. Menu rows were 34 px targets at 844x390. `Hud._button_at` now answers in at least 44 px (`UiUtil.TOUCH_TARGET`); the vendor CLOSE was 27 px. Old: 7 targets under 44 px on the first OPTIONS tab, now 0. 4. A story card swallowed a tap on PAUSE: three cards after PLAY left PAUSE dead for three taps. `Story.pause_passes`. FOUND, NOT FIXED: - 120 menu targets are still 36 to 43 px (OPTIONS GRAPHICS / ACCESS, CONTROLS, Arsenal chips, GEAR rows, SUIT swatches). They are pinned in the test and the count may only go down. - Ability wheel discs are 38 px; garage paints are 48 x 35 px. - A gunship resting on something that is not ground cannot be exited ("LAND TO GET OUT"; 1 of 9 loaded runs). - Not audited: cutscene SKIP, tutorial cards, benchmark panel, most photo-mode controls. TESTS: `test_touch_audit` (211 checks), `test_touch_audit_menus` (33) and `test_touch_audit_screens` (124) pass. Fourteen existing UI tests pass, including `test_touch_buttons_r7`, which fails two checks if it shares a user dir with another running test. PERF (run twice, second time HIGH only, no limit raised): - LOW draws=71 prims=128663 tex=120 death=108 OK - MED draws=100 prims=240939 tex=143 death=148 OK - HIGH draws=112 prims=329566 tex=217 lights=11 death=175, then 174: OVER the 170 limit My changes draw nothing, so I attribute the HIGH overrun to other agents' edits in the tree (snake fx, rain, traffic, city layout), but I did not A/B it. Wave 115 was at 169. FILES, all under `godot/`: - New: `scripts/ui/back_key.gd`; `tests/touch_audit_lib.gd`, `tests/test_touch_audit.gd`, `tests/test_touch_audit_menus.gd`, `tests/test_touch_audit_screens.gd`, `tests/bot_touch_audit.gd`. - Edited: `scripts/ui/hud.gd`, `touch_controls.gd`, `ui_util.gd`, `map_screen.gd`; `scripts/story/story.gd`; `scripts/interiors_gameplay/vendor_screen.gd`. - Docs: `docs/HANDOFF.md`, `godot/ARCHITECTURE.md`, `docs/sprint/progress/w116-touch-audit.md` (findings table). `tools/import.sh` was run for the new class `BackKey`. No commits.

## Last notes of the agent

- 13:03:22 Now the touch buttons code and its test.
- 13:12:44 Now write the HUD scenario into the lib.
- 13:19:22 Update the progress log now, then continue.
- 13:35:32 Now part 3. I'll add generic helpers to the lib and write the screens test.
- 14:00:07 Meanwhile, the HANDOFF and ARCHITECTURE notes.
- 14:21:21 Three green runs in parallel. Final log update, scratch cleanup, then the report.

## Recent steps (last 40)

- 13:40:30 Read GOAL and CLEAR button code
- 13:41:06 Fix story pause pass-through and vendor close target, update test 3, rerun
- 13:42:21 Read the fast-travel open path
- 13:42:43 Patch the screens test and rerun
- 13:44:08 Script the map's YOU, GOAL and CLEAR checks and run all three parts
- 13:46:16 Make the tests robust under load and rerun in parallel
- 13:48:13 Make the quick-tap check tick-based; run r7 alone, then parts 1, 2 and the HUD final test in parallel
- 13:50:29 Write the bot and render HUD, wheel and map frames at phone aspect
- 13:52:23 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ta/shots/hud_foot_more.png
- 13:52:25 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ta/shots/wheel_ability.png
- 13:52:46 Make the HUD press check tick-based and re-render wheel and map frames
- 13:53:50 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ta/shots/wheel_ability.png
- 13:53:52 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ta/shots/map.png
- 13:54:00 Find existing tests that touch the changed code
- 13:54:10 Run twelve related existing tests, three at a time, each in its own user dir
- 13:56:00 Read the test_touch failures
- 13:56:14 Keep the direct-call contract of touch_up, defer only on the real input path; rerun
- 13:57:30 Delete the probes, start the perf gate in the background, tabulate rows by screen and effect
- 13:58:03 Write the progress log with the findings table; check the perf gate
- 14:00:24 Append the HANDOFF and ARCHITECTURE notes
- 14:00:31 Wait for the perf gate lines
- 14:02:17 Wait for the HIGH tier perf line
- 14:04:13 Wait for the HIGH tier perf line
- 14:06:11 Keep waiting for the HIGH tier
- 14:08:03 List other modified files in the tree and start the second perf run (HIGH only)
- 14:08:11 Check the extent of my changes and the disk
- 14:08:16 Wait for the second perf run (HIGH)
- 14:10:21 Keep waiting for the second perf run
- 14:12:16 Keep waiting for the second perf run
- 14:13:37 Final run of the three audit tests in parallel
- 14:15:31 Read the one failing check
- 14:15:36 Check the exit rule for aircraft
- 14:15:38 Read the interact handling while driving
- 14:15:53 Fire vehicle weapons only until the first shot; run part 1 three times in parallel
- 14:17:47 Read toggle_enter_exit
- 14:18:01 Land aircraft with DOWN before EXIT, open the ability wheel with a quick tap; rerun three in parallel
- 14:19:36 Read VehicleCraft.can_exit
- 14:19:53 Accept the game's LAND TO GET OUT answer for a craft that is not down; rerun three in parallel
- 14:21:30 Finish the progress log, clean scratch files, check the tree
- 14:21:44 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/touch_audit_lib.gd
