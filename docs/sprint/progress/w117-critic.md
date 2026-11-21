# w117-critic
GOAL: independent finger-only review of wave 117 swing/rope/zip, list 8 worst defects, fix with failing-first checks. Nothing committed.
TOOLS (mine): godot/tests/dev_w117_critic.gd (headless probe, CR_PARTS=streets,hold0..2,press0..2,early,relift,jump,wall,noanchor,ziproof,zipwall,fly,ground),
  godot/tests/bot_w117_critic.gd (frame strips, CRB_SCENE=hold|jump|wall|ziproof|zipwall|fly|noanchor; run ONE at a time: two renders at once were OOM-killed).
DEFECTS FOUND (measured by real fingers, 3 streets: (-30,0,4) yaw -PI/2 and +PI/2, (240,0,-305) yaw 0):
1. Held chain climbs about +10 m a swing: 32 to 47 m up after 5 swings on all three streets; ropes of 7-10 m (0.57 s twitches), free falls of 1.5-2 s; over half the time off the rope.
2. JUMP out of a swing: one tick later HeroVerbs' QUANTUM GLIDE burst takes the same press: 14.6 -> 27.1 m/s, vy flattened to 4 (swing momentum thrown away).
3. Roof ZIP peaks at 101 m/s (1.69 m a tick; street to roof in 8 frames at 30 fps): a teleport.
4. Roof ZIP arrival: hero turns flat, then HEAD DOWN over the roof edge (frames; pull pose aims at dest below him).
5. ZIP rope is drawn hanging DOWN from the hand during the pull (frames), not up to the roof. (cause not yet known)
6. Arc bottom 1.2 m over the street at 36 m/s when the rope bites in a fast fall (hold2 at 8.1 s).
7. Between two ropes the hero stands upright in the air (frames).
8. In a chain, lifting the thumb 0.12 s after an auto-fired bite lets go 1.05 s later (counted as a tap = whole swing).
ALSO: a SNAKE press in the first ticks after touching down fires a rope that lets go after 0.12 s; a wall ZIP aimed low hauls to a 74 m roof; FLY button absent on the ground (old).
DONE (nothing committed):
- fix 1+6 chain levels off: swing_motion.gd (level_chain, rel_front(height), dive score with scan_h), snake_anchor.gd (scan_h ray; scan_h 0 when falling faster than 14 m/s),
  snake_swing.gd (height, fresh_press). 12 s holds now top 20-21 m (was 34-47), 71-75 % on a rope, least air on a rope >= 2 m.
- fix 2 JUMP: snake_traversal.gd (_jump_taken keeps jump_consumed true until the thumb lifts; static jump_takes).
- fix 3+5 zip: snake_zip.gd (peak_speed 44 -> longer dur; rope_to_edge: roof zip rope bites the roof edge). fix 4: snake_pose.gd zip_upright.
- fix 7 thrown pose: snake_pose.gd throw_pose + SnakeTraversal.thrown(). fix 8 relift: SwingMotion.tap_needs_press.
- a pull-up fix for defect 6 was written and REMOVED: no constructed fall reproduced the sag (5.5 m both ways); the sag is gone with fix 1 (check in the chain part).
- check: godot/tests/test_critic_w117.gd PASS 17/17; CRITIC_OLD=1 (all switches off): 9 FAIL.
- the flat release only for ropes the held chain fired (SnakeSwing.fresh_press false): a pressed swing keeps the 0.62 rad arc (test_swing_w117 manual part needs it).
- zip pull time capped at 2.2 s (test_flight_cost_w116 gives a zip 3 s): zips over 46 m exceed 44 m/s again (56 m: about 54).
- SnakePose.zip_upright only in phase pull (the rope agent's OLD haul trial needs the old pull pose in the haul).
TESTS (each alone): test_critic_w117 17/17 PASS (CRITIC_OLD=1: 9 FAIL), test_swing_w117 38/38, test_rope_w117 25/25, test_snake_traversal 133, test_snake_swing_run 18,
  test_flight_cost_w116 15, test_critic_w116 13, test_play_critic_w115 76, test_snake_combat 137, test_flight_view_w116 32 PASS.
  RED before me (rope agent reported it): test_critic_look_w115 "the trial reproduces the old fling".
  FLAKY under load (1 of 4 when three tests run at once, 5 of 5 alone): test_swing_w117 wall part "no unasked CLIMB": SNAKE lands while still on the floor -> ZIP -> haul ->
  the late JUMP leaps off -> a second SNAKE edge in the air at the wall -> CLIMB by the designed "hold on to a wall" path. Cause of the second edge not found.
FRAMES looked at (1200x540 LOW): docs/shots/round7/critic_w117/{hold_before,hold_after,zip_before,zip_after}.jpg. After: he stays in the street canyon with a rope in
  nearly every frame; the zip rope goes up to the roof edge and he arrives upright.
PERF (one run, clean user dir): LOW draws=74 total=96 death=107 OK; MED 97/129 death=149 OK; HIGH 113/149 death=170 OK.
HANDOFF: section "Wave 117 critic" written. TASK ENDED. Nothing committed.
NEXT: (none)
