# w115-critic-play (independent critic and fixer, lens PLAY = function, feel, measured behaviour)

Started 2026-11-15 07:50Z. Reviews the work of w115-snake-traversal and w115-snake-combat (both DONE, nothing committed yet; the integrator comes after the critics).
A second critic (LOOK lens) works in the same tree at the same time: read each file again right before editing, small edits, never revert others.
STATUS 09:00Z: reviewing by scripted play (probes in godot/tests/dev_w115p_*.gd, helper scratchpad run_probe.sh runs a probe with its own timeout); first fixes started.

GOAL: find the 8 worst FUNCTIONAL defects of the QUANTUM SNAKE work, fix them most severe first with tests.

DEFECTS FOUND SO FAR (measured)
D1 FEEL  a TAP of SNAKE in the air (0.05 to 0.20 s, a thumb) fires the snake and then CANCELS it before it bites (SnakeSwing._tick_travel: `if not hold: cancel()`); bitten 0 of 5 taps up to 0.20 s,
         only 0.30 s works (probe tests/dev_w115p_input.gd). No feedback. FIX PLAN: commit the shot, honour the release only after a minimum hang. File: snake_swing.gd.
D2 MISSION  SnakeWarMissions.inject replaced a world mission on the lodge board (test_world_missions FAILS 'a world mission every time (4 of 6)'): FIXED in snake_war_missions.gd (skips world and snake picks).
D3 MISSION  tutorial SWING ACROSS THE CITY steps FLY and LAND cannot be done on HARD and QUANTUM without a WING POWER rank (flight locked), yet the board offers the tutorial on every difficulty:
         the step waits for MissionGuide's recover (60 s+). PLAN: flight open while the tutorial runs. Files: snake_power.gd / snake_missions.gd / snake_mission_director.gd.
(tested OK) 427 roof rings of 122 built missions all lie on standable roofs (probe dev_w115p_rings.gd; first run misleading: outer colliders need a physics tick after activate_all()).
(tested OK) NORMAL flight: take-off 7.6 m in 1 s, cruise 34 m/s, LAND 2.1 s, no damage.

DONE (files)
- godot/scripts/quantum/snake_war_missions.gd (inject skips world / snake picks)
- probes godot/tests/dev_w115p_{rings,legs,input,clock}.gd (dev only)

NEXT
- fix D1 + D3 with tests; monkey run for stuck / embedded / NaN / script errors; combat verbs vs real enemies; bombs vs rings; touch layout 844x390; swing run frame time at LOW; perf gate once at the end.

DECISIONS (other agents depend on)
- (none yet)

TESTS AND PERF
- test_world_missions fails before D2 fix (1 of 113 checks), to be re-run.

OPEN PROBLEMS
- (none yet)
