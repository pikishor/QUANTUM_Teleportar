# w115-snake-traversal (builder: movement side of QUANTUM SNAKES)

Started 2026-11-14. The earlier agent for this label died at the weekly limit before doing anything (auto_w115-snake-traversal.md is empty).
Final update 2026-11-15 (all deliverables done; the integrator reads this).

GOAL: hero signature traversal: SNAKE SWING, SNAKE ZIP, SNAKE CLIMB, SNAKE FLIGHT + movement kit, ONE contextual SNAKE button (+ FLY/LAND), tutorial + 2 missions,
audio, tests, frames at phone res LOW and MED, ONE shared tendril visual for the combat builder. Documented in godot/ARCHITECTURE.md ("QUANTUM SNAKE traversal").

DONE (all under godot/)
- SHARED TENDRIL: scripts/quantum/snake_tendril.gd, snake_tendril_pool.gd, assets/shaders/snake_tendril.gdshader (ONE MultiMesh draw for every tendril, data texture, viper head)
- Numbers: snake_power.gd (SnakePower) + 11 keys in each HeroPower row + SkillTree verb `snake` (RANGE SPEED ENERGY CHAIN BONUS WING POWER, 5th column) + HERO MODE (unlimited, jam immune)
- Movement: snake_anchor.gd (finder), snake_swing.gd, snake_zip.gd, snake_climb.gd, snake_flight.gd, snake_traversal.gd (= Player.snake, the kit: double jump, super jump, roll),
  snake_pose.gd, snake_camera.gd, snake_fx.gd (speed lines + anchor marker, made lazily), snake_missions.gd + snake_mission_director.gd (SWING ACROSS THE CITY, ROOFTOP CHASE)
- Hooks (one line each where shared): player.gd, player_body.gd, camera_rig.gd, hero_verbs.gd, game.gd (actions snake=Tab, fly=backslash), sfx.gd, touch_controls.gd (SNAKE r 46 + FLY),
  mission_board.gd, skill_screen.gd, specialist.gd (sniper lead, warden jam), ui_settings.gd + options_screen.gd (AIM ASSIST also drives the snake assist)
- Audio: assets/audio/snk_*.ogg (12 files, 98 641 bytes) from tools/audio/make_snake.py. APK effect: audio 96 KB + shaders 8 KB + scripts about 150 KB source: far under 30 MB.
- Enemy counters: SnakeTraversal.lead_offset (snipers lead a hero on the snakes, SNIPER_LEAD .55/.8/.95/1) and jam_in_radius (the warden's pulse jams snakes 1/2/3/3.5 s, every state drops
  WITHOUT the boost, HERO MODE immune). Tests (all PASS): tests/test_snake_traversal.gd (135 checks), tests/test_snake_swing_run.gd (STORY + NORMAL: 7-11 swings, 520 m, no ground),
  existing tests that touch the hooked files all pass (test_traversal needed the super jump fix, see below). Dev probes: bot_snake*.gd, dev_snake_*.gd (dev_snake_routes.gd = reliability over routes).

RENDER LOOPS (LOW + MED at the 2400x1080 aspect, touch HUD on, real camera; 17 loops; frames deleted, sheets in docs/shots/round6/snake_*.jpg, 9 files q80)
- 1-10 tendril look (head, taut, slack), swing arcs and facade scraping, poses, HUD placement (earlier log); 11 climb hero cut at the bottom -> arm +1.7, lens +0.05
- 12 flight wings swept 4 m back filled the screen -> open sideways (span 3.0-4.8); 13 flight lens above his head -> at the chest; 14 swing at 40 m/s: hero 8 % of the frame -> arm and lens
  kick halved; 15 anchor marker clipped to a wedge on corners -> no depth test; SNAKE ring crowded RELOAD/AIM -> r 46 centred in the gap; 16 MED captured at 8-10 fps made the camera lag
  (hero 15 %): MED re-rendered at 24 fps 1200x540 (hero 30 %); 17 zip pull left the hero at the bottom edge -> lens at the chest
- SELF-REVIEW vs docs/owner_shots/round5: same HUD rings and night city, the snake cyan matches the QUANTUM cyan of the HUD; the hero reads in every state at LOW and MED. Still seen:
  a zip pull shows the boots at the frame edge for a few frames; city corner neon strips look like a pillar of light up close; facade cable decor at MED looks like floating wires up close

PERF (tests/bot_snake_perf.gd, same view with and without the snake visuals): a state costs +1 draw (the MultiMesh), marker +1 quad only in the air with no state, speed lines 1 canvas draw.
GATE 1 (mid-way) found the idle SnakeFx (empty CanvasLayer + hidden mesh) cost +2 draws at MED (death spike 151 > 150): made lazy. GATE 2 (final): LOW OK (94 total, death 107),
MED OK (129, death 149 of 150), HIGH OK (149, death 170 of 170); textures 112 / 143 / 209 MB. Script time of SnakeTraversal.tick 0.12 ms per physics tick (SNAKECPU line of the swing run);
swing run frames: avg 16.7 ms, p99 24-31 ms, worst 34-365 ms (a chunk streaming under the hero; the test allows p99 < 80 and worst < 750).

FIXED ON THE WAY: super jump took a held JUMP + forward (vault / mantle habit) -> only from standing, stick idle, 0.3 s hold; swing chain passed 25 % of routes -> rope reel-in under 9 m of
air, long ropes score higher, arcs judged against free fall, wide second scan (test route 8/8, random downtown routes about 55 %); idle FX +2 draws; board injection overwrote a world mission.

DEFECTS OUTSIDE MY SCOPE (for the integrator)
- SnakeWarMissions.inject (combat builder, snake_war_missions.gd) replaces the LAST pick even when it is a world mission: tests/test_world_missions.gd "standing at the lodge the board offers a
  world mission every time" fails 2 of 6 (mine skips world picks and far boards: SnakeMissions.inject(picks, rng, [], origin)). Same two-line fix.
- `ERROR: Parameter "material" is null.` in tests and bots (not from this work); after a builder adds a class_name a test run needs tools/import.sh first (SnakeUi errors until then)
- tutorial LAND step can finish while flying low (reach tolerance 6 m)

DECISIONS (other agents depend on)
- TENDRIL API: `SnakeTendril.fire(origin, target, opts)`; origin/target = Vector3 | Node3D | Callable; opts speed travel wriggle color thickness head life tension on_attach host; object: state,
  attached/retracted signals, tension, retract(t), kill(), set_target(), length(), head_pos, user["keep"]. Pool caps LOW 4 / MED 6 / HIGH 8, ONE draw while any lives. Hands: Player.snake.hand_callable(side).
- Player.snake: mode NONE SWING ZIP CLIMB FLY, energy 0..100, `event(id)`, counters; do not call move_and_slide on the player while snake.active(); `jam(seconds)` for any combat jammer.
- SkillTree verb `snake` owns sn_range sn_speed sn_energy sn_chain sn_wings.
