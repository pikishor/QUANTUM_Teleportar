# w128-anim (done)

agent id a86db08c44c9a315e, 483 events, first activity 2026-11-27T15:03:47.762Z, last activity 2026-11-27T16:21:47.983Z

## Final report

w128-anim report (plan line 128). Nothing was committed. Log: docs/sprint/progress/w128-anim.md What was missing: the hero was hidden in every vehicle, so helicopters, planes and tanks moved with nobody at the controls. The "glider pilot on top" was really the motor pylon. Aircraft glass was opaque. No quantum verb had a body gesture. Combat snakes slid straight in with no strike. FIXED. Check: godot/tests/test_anim_w128.gd, all real fingers on main.tscn, Game.force_touch on, CrateReveal._quiet = 0. New code: PASS, 52 checks, about 40 s. W128_OLD=1 (the old code): 9 FAIL. 1. Seated pilots, new SeatPose in scripts/characters/seat_pose.gd. The seat is measured on the built model (cockpit glass, hull floor, turret roof), so it follows the airlook agent's redesigns. - Cockpits: pilot reclines when the canopy is low (glider 0.26 rad). Right hand on the cyclic or stick, left on the collective or throttle. Wide cockpits use a yoke. - Tanks: commander in the hatch, turns with the turret, hands on the rim. - Quad, scooter, jet ski: rider astride, hands on the grips. - The rig got a seated leg/hand solver; the controls follow the stick. - The canopy turns see-through while the hero is aboard; the cockpit view hides the body. - The body is placed again after the vehicle's visual update, so the feet don't slide. - Checks: seen in seat (failed on old), pelvis on seat, head under canopy or out of hatch, wrists on controls, stick moves the hand, feet don't slide, EXIT restores the dark glass and the weapon. 2. Cast gestures for all 9 quantum verbs, new HeroCast in hero_cast.gd: wind-up, release, hold, back to the weapon. The right hand stays on the gun (frames showed it floating when both hands let go). Check: a finger on ABILITY, then a verb in the ring, starts a gesture; wind-up comes before release; the verbs differ (failed on old). 3. Snake strike in snake_swarm.gd: the neck coils into an S, then lunges (failed on old). Frames looked at, LOW and MED: helicopter, glider, fighter, cub, trainer, jumbo, heavy tank, quad, jet ski, casts. Related tests PASS: hero_animation_polish, quantum, quantum_teleport, snake_combat, snake_traversal, helis_w125, tanks_w127, planes_w126_b. superhero_hero failed once on the known flaky "female floor" check, then passed 2 of 2. NOT fixed: - Cars keep their painted dummy driver. - Art bikes (bike, qbike, hoverbike) still have no rider. - Glide, take-off and landing poses were not reworked. - The heli side view shows the pilot poorly. - tank_crews.gd:246 casts a freed vehicle before its validity check and spams SCRIPT ERROR after a tank is released (not my file; the test avoids it). - I did not work on the user's 30-40 weapon switching or blast realism; those are outside this label. Files: new godot/scripts/characters/seat_pose.gd, hero_cast.gd, godot/tests/test_anim_w128.gd, bot_w128_anim.gd, probe_w128.gd. Edited character_rig.gd, player_body.gd, snake_swarm.gd. Perf (PERF_CHECK=1, no limit touched): - LOW: draws 74, total 96...

## Last notes of the agent

- 15:03:55 Fresh start. Reading the docs.
- 15:14:01 Now a probe to measure the hero rig and list the cab types.
- 15:16:48 Now the apply() hooks: legs/pelvis before the torso pose, head counter, arms.
- 15:36:28 Now the permanent test.
- 15:37:10 Good. Run the test (new code).
- 16:21:31 Cleaning up scratch frames and finalizing the log.

## Recent steps (last 40)

- 15:37:07 /home/user/QUANTUM_Teleportar/godot/tests/test_anim_w128.gd
- 15:37:09 Read swarm spawn
- 15:37:11 Run new anim test
- 15:37:48 Locate freed-object error and tail results
- 15:39:17 Inspect quantum button gating and tank crews line
- 15:39:22 Find quantum button definition and gating
- 15:39:42 Fix inputs, late placement, snake strike timing, test tweaks
- 15:39:46 Rerun anim test
- 15:40:41 How vehicle reads steering input
- 15:40:48 Debug heli stick and feet
- 15:41:33 Sample after frame end and debug hand
- 15:44:01 Use deferred flush for end-of-frame sampling
- 15:44:34 Read ability button tap handling
- 15:44:37 Find wheel finger usage in tests
- 15:44:39 Locate wheel script and tests
- 15:44:42 How the audit picks the ability wheel
- 15:44:49 Pick a verb on the ability ring by finger
- 15:45:29 Fix cast metric and snake lunge timing
- 15:46:03 Run full test new and old
- 15:47:27 Remove weakening and list related tests
- 15:47:30 Run related existing tests
- 15:56:39 Compare superhero test old vs new
- 15:58:41 Render seats and casts at MED
- 16:02:21 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/w128a_f5/sheetB.png
- 16:02:35 Keep the right hand on the weapon in all casts
- 16:02:37 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/w128a_f5/sheetA.png
- 16:02:50 Tune canopy and render LOW frames
- 16:04:30 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/w128a_f6/sheet.png
- 16:04:39 Check how plane glass is built and bound
- 16:04:45 Read airlook agent's aircraft glass
- 16:04:56 Double-sided canopy, LOD1 swap, render MED
- 16:06:56 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/w128a_f7/sheet.png
- 16:06:59 Rerun anim test after canopy changes
- 16:07:51 Update log and run perf gate
- 16:17:58 Wait for perf gate output
- 16:19:52 Find perf report logs for LOW result
- 16:19:54 Read perf report exit logic
- 16:19:58 Perf gate LOW numbers
- 16:21:35 Clean scratch and finalize progress log
- 16:21:47 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/scripts/characters/seat_pose.gd
- godot/scripts/characters/character_rig.gd
- godot/scripts/player/player_body.gd
- godot/scripts/characters/hero_cast.gd
- godot/tests/test_anim_w128.gd
