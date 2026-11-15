# w115-critic-look (critic-fixer, lens LOOK, wave 115 quantum snakes)

Started 2026-11-15. A second critic (lens PLAY) works in the same tree. The two builders (w115-snake-traversal, w115-snake-combat) are done; their work is UNCOMMITTED in the tree.

GOAL: render the swing run, climb, flight, verbs and bombs from the real game camera at phone resolution (LOW and MED), OPEN every frame, list the 8 worst defects, fix them in render-look-fix loops.

DONE (review, no fix yet)
- godot/tests/bot_critic_snake.gd (NEW, mine): real game + real camera + phone HUD; CS_MODE=run (thumb policy swing run, render loop only on for saved frames, 5 fps) and CS_MODE=scenes (CS_SCENES=zip,climb,fly,dive_roll,landing,ceiling,hop_swing,hud,hud2). Needs BOT_RES, QUALITY, ENGINE_ARGS="--fixed-fps 30", BOT_USER_ARGS="--touch".
- godot/tests/dev_critic_snake_play.gd (NEW, mine): headless 60-90 s run (godot --headless --fixed-fps 60 ... --test=res://tests/dev_critic_snake_play.gd, CP_SECS CP_DIFF CP_START) measuring camera pops, lens in collider, hero hidden, hero jumps, swing jerk, stray vehicle prompt.
- godot/tests/dev_critic_slab.gd (NEW, mine): probe that found the teal slab = an empty PLAZA of the ground shader (not snake related).
- frames reviewed: LOW run 204 frames (zip, climb 70 m, mantle, swings, 14 s flight, chain), MED run 100 frames, scenes zip/climb/fly/landing/ceiling/hud at LOW, HUD at 844x390 (6 states + wheels), 10 verbs LOW, 12 bombs MED.

DEFECT LIST (evidence -> status)
1. Hero is flung up to 12 m in ONE frame during a swing (rope reel debt: the rope reels at 40 m/s while a facade or the street holds the hero, then the sphere correction applies it all at once). Probe: jumps of 6.4 m and 11.8 m, camera pops 4.6-5.1 m. snake_swing.gd _tick_hang. -> TODO fix
2. Camera arm is cut in one frame (3.7 m -> 1.2 m at 31 m/s: pops 2.5-3 m, 7-18 per 90 s run), lens inside a collider 114-144 frames (2 %). camera_rig.gd ratio snap. -> TODO fix (smooth only while the snake camera is active)
3. "ENTER VEHICLE" plate over a swinging / flying / zipping hero (223-760 frames of 4201-5401, shown in 3 of 6 HUD frames at 844x390): hud.gd hint_text fallback uses the 2D Vehicles.nearest. -> TODO fix
4. Flight wings pierce facades (LOW run frames 120-135) and read as flat film strips. snake_flight.gd _wing_tip. -> TODO fix the piercing
5. Touch layout at 844x390: SNAKE (r 46) and FLY crammed between RELOAD / AIM / FIRE, energy ring touches neighbours, BOOST label clipped by the FIRE ring. touch_controls.gd. -> TODO
6. ABILITY wheel with 11 discs: labels 7 px at 844x390 (SUPERPOSITION, COLLAPSE ...). -> report / maybe
7. Weapon card ("ION BATTLE RIFLE 20/20") pops over the hero's torso at every snake power end / disarm. -> TODO check
8. Hero boots read as two black blocks from behind in flight / zip; wings clip the screen edge. hero art. -> report

OUT OF SCOPE (report): empty flat plaza slab at (205, 0, 0); rooftop props (faceted glowing orb, flat teal wedges); near-field facades are flat black / cream panels at 2-3 m; MED facade cables.

FIXED SO FAR (09:55Z, all with tests/test_critic_look_w115.gd: 21 checks, PASS twice, each fix has an "old behaviour" trial that reproduces the defect)
- 1 hero fling: snake_swing.gd _tick_hang: the reel waits (static reel_slack 1 m), the sphere moves the body max_correction 1.5 m per tick. Old trial: rope debt 25.1 m, 26.4 m step in one tick; fixed: 1.1 m / 1.07 m.
- 2 camera cut: camera_rig.gd: static snake_pull_in 40/s, used only while snk.cam.active (the arm is drawn in over ~3 frames). Route probe: pops 12 -> 3 (max 2.2 -> 1.2 m); first-frame share 103 % -> 50 %; on foot unchanged (104 %).
- 3 vehicle plate in the air: hud.gd hint_text: the flat 2D `nearest` fallback only runs when the manager has no reach_car. Probe: 223-760 frames -> 0 (bare street) / 10-34.
- 4 wing tips: snake_flight.gd _wing_tip -> _keep_out_of_walls (one cached ray per wing and frame, static clip_wings switch). Test: tip stops 0.31 m short of a wall 1 m away.
- label: SnakeTraversal.button_label SWING reads LET GO (was RELEASE, drawn a fifth smaller).

NEXT: more hunting (landing/zip frames, MED), render before/after of the HUD at 844x390, contact sheets docs/shots/round6/critic115_look_*.jpg, tests of touched files (test_hud, test_snake_traversal, test_snake_swing_run, test_play_critic_w115), perf gate once, ARCHITECTURE/HANDOFF notes.

DECISIONS (others may rely on): SnakeSwing.reel_slack / max_correction, CameraRig.snake_pull_in, SnakeFlight.clip_wings are static vars (tests switch them to show the old behaviour). The vehicle plate in the air is fixed in Hud.hint_text.
TESTS AND PERF: none yet.
