# w118-controls (done)

agent id aec14e87cd141a290, 109 events, first activity 2026-11-22T04:28:47.000Z, last activity 2026-11-22T05:11:06.896Z

## Final report

w118-controls report (resumed after a restart; no commit, no push) The per-mode control sets are built and pass by real fingers, except that menu and garage targets under 44 px are not fixed and ENTER beside a plane is not proven by finger (below). FIXED (godot/scripts/ui/touch_controls.gd, table BUTTONS; one set per mode, switched automatically) - On foot: FIRE (big), AIM, JUMP, SWING, ZIP, FLY, ENTER beside a vehicle; small CROUCH, RELOAD, ABILITY above the stick; WEAPON, MORE, PAUSE on top. - Snake flight: FIRE, AIM, UP, DOWN, BOOST, LAND. - Car / boat: GAS, BRAKE (then reverse), HAND BRAKE, EXIT, FIRE only when armed; small HORN, VIEW. - Tank: FIRE, COAX, BRAKE, EXIT; small VIEW, SHELL; drag turns the turret. - Helicopter / plane: FIRE, ROCKET, UP, DOWN, EXIT, VIEW. - Indoors: FIRE, AIM, JUMP, USE, LEAVE. - The way out (ENTER / EXIT / LAND / LEAVE) is the same slot in every mode. MORE holds only extras. - Wave 116 / 117 items: FLY is on the ground set; snake flight has DOWN; SWING and ZIP are separate buttons (snake_traversal.gd, action snake_zip); ability discs are 55 px (were 38); PAUSE and MORE are 44 px; HORN works. - The armour builder's CallIn.toggle() hook is kept; the label is now CALL. CHECKS - godot/tests/test_controls_w118.gd was written first: 67 FAIL lines on the old code, PASS now. - test_touch_audit is extended (drawn 56 / 44 px sizes, no geometry finding on any play HUD frame) and passes. - test_armour_w118 and the 24 other touch tests I reran pass. test_hud_declutter failed once on "a parked car can be placed next to the hero" and passed on rerun. - About 17 old tests were updated to the new layout, each with a "wave 118" comment. test_hud_declutter and test_world_hud MAX_CONTROLS went 13 -> 16, because ZIP, FLY and CROUCH are now buttons; that loosens an older cap, so please confirm it. - Frames rerendered and looked at, 844x390 and 2400x1080, in docs/shots/round7/controls_w118/ (sheet_844.jpg): they read clean. NOT FIXED - Menu rows under 44 px (38 title, 82 pause) and garage paint swatches at 48x35. - On foot the right cluster is 6 circles, 7 with ENTER. - ENTER beside a spawned plane boarded a nearer traffic car, so the test boards the plane by a direct call (with a NOTE). - Labels are words, not icons; the small ones are tiny at 844 px. - Swimming uses the on-foot set. - es / hi snake mission texts still describe the old single button. - A world "ZIP ROOF" marker can sit over the ABILITY disc. - On 4:3 tablets GRAB / TAKEDOWN come near the stick. FILES scripts/ui/touch_controls.gd, scripts/quantum/snake_traversal.gd, tests/test_controls_w118.gd, tests/bot_controls_w118.gd, tests/touch_audit_lib.gd, tests/test_touch_audit.gd, tests/interior_bot.gd, the stale tests listed in docs/HANDOFF.md ("Wave 118 controls"), godot/ARCHITECTURE.md, docs/sprint/progress/w118-controls.md. PERF (one run) LOW draws=74 prims=137301 verdict=OK; MED draws=97 prims=240262 verdict=OK; HIGH draws=113 prims=327132 verdict=OK.

## Last notes of the agent

- 04:32:00 Meanwhile I look at the phone-size frames.
- 04:44:24 Install the frames (2400 as jpg, like before), rebuild the sheet, then start the batch of touch tests.

## Recent steps (last 40)

- 04:28:48 Read progress log and repo status
- 04:28:52 Locate earlier scratch results, shots and tools
- 04:29:14 Find tools dir and prior scratch
- 04:29:19 Check file times, handoff notes, test runner
- 04:29:22 /home/user/QUANTUM_Teleportar/docs/shots/round7/controls_w118/sheet_844.jpg
- 04:29:24 Run the wave 118 controls test
- 04:31:11 Rerun controls test and summarize
- 04:31:59 Run the four uncertain tests plus armour and audit
- 04:32:00 /home/user/QUANTUM_Teleportar/docs/shots/round7/controls_w118/foot_enter_844.png
- 04:32:01 /home/user/QUANTUM_Teleportar/docs/shots/round7/controls_w118/tank_844.png
- 04:32:02 Read the button table
- 04:32:08 Update log, read bot header, check test progress
- 04:35:31 Wait for remaining tests
- 04:35:34 Wait for the six tests to finish
- 04:37:49 Rerender per-mode frames at 844x390
- 04:39:42 Rerender per-mode frames at 2400x1080
- 04:39:43 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/shots/foot_more_844.png
- 04:39:44 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/shots/flight_844.png
- 04:39:45 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/shots/heli_844.png
- 04:39:52 Wait for the 2400 render
- 04:44:30 Install frames, build sheet, start test batch
- 04:44:31 /home/user/QUANTUM_Teleportar/docs/shots/round7/controls_w118/car_2400.jpg
- 04:44:38 Log state and wait for the test batch
- 04:54:41 Wait for the test batch
- 04:58:45 Inspect the declutter failure and rerun
- 04:59:18 Run the perf gate on all three tiers
- 04:59:22 Check audit findings about small menu targets
- 04:59:26 Wait for the perf gate
- 05:09:30 Wait for the perf gate
- 05:10:54 Final log entry
- 05:11:06 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- (none)
