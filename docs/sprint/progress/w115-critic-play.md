# w115-critic-play (independent critic and fixer, lens PLAY = function, feel, measured behaviour)

Started 2026-11-15 07:50Z. Reviews the work of w115-snake-traversal and w115-snake-combat (both DONE, nothing committed yet; the integrator comes after the critics).
A second critic (LOOK lens) works in the same tree at the same time: read each file again right before editing, small edits, never revert others.
STATUS 09:25Z: 5 defects fixed with a regression test (tests/test_play_critic_w115.gd, 60 checks, mutation-checked), more being hunted. Probes: godot/tests/dev_w115p_*.gd, bot_w115p_run.gd; helper
scratchpad run_probe.sh runs a probe with its own timeout (direct godot call with --timeout=N).

DEFECTS (measured) AND STATUS
D1 FIXED  FEEL  a TAP of SNAKE in the air (0.05 - 0.20 s, a thumb) fired the snake and CANCELLED it before it bit (SnakeSwing._tick_travel `if not hold: cancel()`): 0 of 5 taps bit, no feedback; only a
          press of 0.3 s swung. Now the shot is committed and every swing hangs TAP_HANG 0.55 s before a released button counts (JUMP and the end of the arc still let go at once). snake_swing.gd.
D2 FIXED  MISSION SnakeWarMissions.inject replaced a world mission on the lodge board (test_world_missions failed 'a world mission every time (4 of 6)'): skips world and snake picks now (snake_war_missions.gd).
D3 FIXED  MISSION the tutorial SWING ACROSS THE CITY ends with FLY and LAND, impossible on HARD and QUANTUM without a WING POWER rank (5 skill points of prerequisites), yet offered on every difficulty:
          flight is open while the tutorial runs (SnakeMissions.tutorial_running set by SnakeMissionDirector, read by SnakePower.flight_unlocked).
D4 FIXED  FUNCTION (worst) arming a snake power from the weapon wheel put the gun away and NOTHING brought it back: the swap button, number keys and the wheel left holding() true, every new gun was holstered
          and silent, FIRE only cast the power (measured: ammo 15 -> 15). Fix: SnakeWar.holster() (static) from PlayerWeapon.poll_switch (the first tap on WEAPON puts the power away), WeaponWheel.activate
          (weapon disc, class pick, RECENT), and the weapon_changed signal; a one-time hint TAP WEAPON  YOUR GUN COMES BACK (ES, HI). The builders' test had a vacuous check for it (`pw.current != &""`).
D5 FIXED  ROBUSTNESS snake_pose.gd printed `Basis must be normalized` (builder's open item): the pose basis is now checked, orthonormalized, falls back to the yaw basis.
(measured OK) 427 roof rings of 122 built missions lie on standable roofs; NORMAL flight take-off / cruise 34 m/s / LAND 2.1 s no damage; boosted flight 60 m/s low over the outskirts (3500 m, no fall through);
  death and respawn in swing, climb, flight, shield, grab leave nothing behind; graphics tier switches mid swing / flight / snakes are clean; 50 verb x enemy-type trials against LIVE enemies: no error,
  no stuck hold, no sunk enemy; twelve bomb rings = table radii, hero outside the ring unhurt; anchor search 0.5 ms (full), 0.29 (preview); street start: 7-13 swings and 900-1500 m in 40 s, no position
  jump, no reversal; 59 of 60 street taps on SNAKE zip; monkey 22 episodes x 25 s with combat and traffic: no stuck state, no non-finite value, no script error of ours.
NOT FIXED / OPEN (see the final report): tutorial swing steps often cannot be done as written (7 of 12 roof legs: no anchor above a roof edge, the hold turns into a flight); mega bomb ring 20 m, damage ends near
  14-16 m; camera lens jumps against the hero 2-5 m in 2 % of frames in swing runs (arm 4-11 m); fx_threat.gdshader stealth pips drawn as white plates (not wave 115 code).

DONE (files)
- EDITED scripts/quantum/{snake_swing,snake_war,snake_war_missions,snake_power,snake_missions,snake_mission_director,snake_pose}.gd, scripts/player/player_weapon.gd (poll_switch), scripts/ui/weapon_wheel.gd,
  scripts/common/strings_snake_war.gd (one hint, ES + HI)
- NEW tests/test_play_critic_w115.gd; probes tests/dev_w115p_{rings,legs,input,clock,monkey,chain,verbs,bombs,arm,death,tier,zipcar,matwarn,terrain_fly,scancost,groundtap,lowwall}.gd, tests/bot_w115p_run.gd

NEXT
- more hunting (touch states, mission flows), ARCHITECTURE.md + HANDOFF.md notes, perf gate once (PERF_CHECK=1 tools/perf_report.sh 0 1 2), tests of every touched file, final report.

DECISIONS (other agents depend on)
- SnakeWar.holster() is the way to put a snake power away for a gun; anything that equips a gun should call it (or switch_to, which signals).
- SnakeSwing.TAP_HANG (0.55 s) is the minimum hang of every swing; a swing always bites once the head is out.
- SnakePower.flight_unlocked() is true while SnakeMissions.tutorial_running.

TESTS AND PERF
- tests/test_play_critic_w115.gd PASS (60 checks, ~40 s); mutation runs: removing each fix fails its checks. Also PASS after the edits: test_world_missions, test_snake_combat, test_snake_traversal, test_snake_swing_run.
- perf gate: not run yet (my edits draw nothing).

OPEN PROBLEMS
- see NOT FIXED above.
