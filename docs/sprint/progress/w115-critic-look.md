# w115-critic-look (independent critic and fixer, lens LOOK, wave 115 quantum snakes)

Started 2026-11-15 07:50Z, STATUS 11:25Z: DONE, waiting for the integrator (nothing committed). The PLAY critic (w115-critic-play) worked in the same tree and is done too.

GOAL: frames of the real game camera at phone resolution (LOW and MED) for every item of the focus list, OPEN every one, the 8 worst defects, fix them in render-look-fix loops, tests, perf.

DONE (all under godot/ unless noted)
- NEW look-dev: tests/bot_critic_snake.gd (CS_MODE=run swing run with a thumb policy at 5 fps / CS_MODE=scenes CS_SCENES=zip,climb,fly,fly_wall,dive_roll,landing,ceiling,hop_swing,hud,hud2,glow; CS_NOCLIP, CS_NOGLOW),
  tests/dev_critic_snake_play.gd (headless 60-90 s run: pops, lens in a collider, hero jumps, swing jerk, vehicle plate; CP_PULL, CP_GOALS, CP_BARE), tests/dev_critic_slab.gd.
- FIXED (each with an old-behaviour trial in tests/test_critic_look_w115.gd, 28 checks, about 60 s, PASS twice and under load):
  1 hero fling 6-12 m in one frame: scripts/quantum/snake_swing.gd (reel_slack, max_correction)   2 camera cut 2-5 m: scripts/player/camera_rig.gd (snake_pull_in)
  3 ENTER VEHICLE plate over a swinging / flying hero: scripts/ui/hud.gd hint_text   4 wing tips through facades: snake_flight.gd _keep_out_of_walls (clip_wings)
  5 black boots / pack / cloth from behind: assets/shaders/hero_body.gdshader (rim)   6 suit did not answer the snakes: snake_traversal.gd _glow_tick (swing 2.1, zip/climb 1.7, flight 1.8; suit_glow switch)
  7 button RELEASE -> LET GO   8 wings stayed level in a barrel roll: snake_flight.gd   9 rope / wing fat near the lens: assets/shaders/snake_tendril.gdshader
- docs: godot/ARCHITECTURE.md "Wave 115 critic, LOOK lens", docs/HANDOFF.md, docs/shots/round6/critic115_look_*.jpg (12) and critic115_look_iterations.md.

MEASURED (headless 75 s runs, same route, before -> after): hero jumps 1 (11.3 m) -> 0; camera pops over 0.9 m 7/14 -> 3/10 (max 1.75/3.55 -> 1.10/1.73 m); vehicle plate frames 223-760 -> 0;
  lens inside a collider 88/52 -> 102/62 frames (the lens needs 2-3 frames to leave a wall that appears suddenly; the longest run, 34/48 frames, is the same with or without the pull-in).
  Swing run test unchanged (7 and 8 swings, 520 m, p99 28-32 ms). Perf gate twice: LOW 70 draws / 112 MB, MED 97 / 143 MB (death 149 of 150), HIGH 113 / 209 MB (death 169-170 of 170): OK, nothing added.

TESTS RUN AND PASSING HERE: test_critic_look_w115, test_hud, test_hud_camera_final, test_snake_traversal, test_snake_combat, test_snake_swing_run, test_hero_look_v3, test_hero_look2, test_hero_customisation,
  test_critic_look_w113, test_critic_look_w114, test_visual_fixes3, test_balance2, test_cinematic, test_combat_feel, test_player_polish, test_traversal, test_hud_gameplay, test_open_world_freedom, test_interior_gameplay,
  test_hud_declutter, test_world_hud, test_touch, test_play_critic_w115 (one check failed in one of two runs: "none stands inside a building", the random hunter spawn of the PLAY critic's own test).

OPEN (not fixed, reasons in the report)
- SNAKE / FLY buttons sit in the gaps between RELOAD, AIM and FIRE (6 px of air, the energy ring touches, BOOST clipped by the FIRE ring at 844x390); ABILITY wheel with 11 tiny discs (7 px labels): layout is pinned by tests.
- HUD buttons are translucent: over a bright cream facade (frequent in a swing run) they read as grey discs with low-contrast labels (UiUtil button sprite, HUD-wide).
- wings and ropes read as film strips up close; city art seen from the swing: empty flat plaza at (205, 0, 0), faceted rooftop orb, flat near-field facades, MED facade cables; the weapon-change card covers the hero's torso.
- a swing that stalls against a facade (speed under 2 m/s for 1.2 s, 24-35 frames per 90 s run) and the lens in a collider for up to half a second at a thin ledge (34-48 frames): worth a look by the owners of SnakeSwing / CameraRig.
- the barrel roll needs a nearly pure sideways double tap (|stick x| > 0.8): with forward held (0.707) it never starts (PLAY lens).

DECISIONS others rely on: SnakeSwing.reel_slack / max_correction, CameraRig.snake_pull_in, SnakeFlight.clip_wings, SnakeTraversal.suit_glow are static vars (tests and bots switch them to show the old behaviour).
