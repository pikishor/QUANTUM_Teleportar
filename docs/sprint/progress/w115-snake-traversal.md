# w115-snake-traversal (builder: movement side of QUANTUM SNAKES)

Started 2026-11-14. The earlier agent for this label died at the weekly limit before doing anything (auto_w115-snake-traversal.md is empty).

GOAL: hero signature traversal: SNAKE SWING, SNAKE ZIP, SNAKE CLIMB, SNAKE FLIGHT + movement kit (double jump, air dash, super jump,
wall-run, ledge grab, slam, safe landing roll), one contextual SNAKE button (+ one FLY/LAND button), tutorial + 2 missions, audio,
tests (tests/test_snake_traversal.gd), frames at phone res LOW and MED. ONE shared tendril visual for the combat builder.

DONE (all files under godot/)
- SHARED TENDRIL: scripts/quantum/snake_tendril.gd (SnakeTendril), snake_tendril_pool.gd (SnakeTendrilPool), assets/shaders/snake_tendril.gdshader (one MultiMesh draw, data texture, viper head, scales)
- scripts/quantum/snake_power.gd (SnakePower: numbers by difficulty / skill / HERO MODE), HeroPower rows got snake_* / climb_speed / fly_* / air_jumps keys, SkillTree verb `snake` (5 nodes, 5th column in skill_screen.gd)
- scripts/quantum/snake_anchor.gd (anchor finder: fan of rays, scoring, arc simulation, roof snap, zip target, wall probe), snake_swing.gd, snake_zip.gd, snake_climb.gd, snake_flight.gd, snake_traversal.gd (orchestrator, Player.snake), snake_pose.gd, snake_camera.gd
- Hooks: player.gd (snake.tick before traversal.tick, air_k_scale, facing_yaw, cancel on reset/teleport/vehicle/die), player_body.gd (pose update + apply_body), camera_rig.gd (snk.cam outputs), hero_verbs.gd (jump_consumed), game.gd actions `snake` (Tab) and `fly` (backslash)
- Dev tools: tests/bot_snake.gd (look-dev bot, SNK_SCENES=tendril,swing,zip,climb,fly), tests/dev_snake_chain.gd (swing run probe), dev_snake_fly.gd, dev_snake_anchors.gd
- MEASURED (real city, STORY, assist on, hand-off swing run from 40 m): 10 swings, 558 m in 26 s, no ground touch, max 49 m/s. First render of a swing: works, hero hangs from a scaled cyan snake.

NEXT
1. Render loops: swing / zip / climb / fly sequences at LOW + MED (tests/bot_snake.gd), fix defects (arm/legs poses, camera framing, tendril look, hero at frame edge).
2. Touch: SNAKE + FLY buttons in touch_controls.gd BUTTONS (+ look-drag from SNAKE button, ring for energy), prompts, hint labels.
3. Sounds (tools/audio/make_snake.py, names snk_fire snk_attach snk_strain snk_release snk_miss snk_zip snk_land snk_wings snk_boost snk_roll), speed lines (snake_fx.gd), anchor marker.
4. HUD/tutorial + 2 missions (swing across the city, rooftop chase), enemy counters (sniper aim, jammer), options toggle for assist.
5. tests/test_snake_traversal.gd (real scene), fix existing tests that pin things, perf gate (twice), docs/ARCHITECTURE.md section, contact sheets docs/shots/round6/.

DECISIONS (other agents depend on)
- TENDRIL API (combat builder use this, do not fork): `var t := SnakeTendril.fire(origin, target, opts)`; origin/target = Vector3 | Node3D (follows it, `origin_offset`/`target_offset`
  local) | Callable -> Vector3. opts: speed (m/s, 95) | travel (s), wriggle (0.45 m), color, thickness (0.075 m radius), head (true), life (auto retract s after attach),
  tension (0..1), on_attach (Callable), host (Node for the pool). Object: state (TRAVEL, ATTACHED, RETRACT, DONE), attached/retracted signals, tension (set every frame),
  retract(time), kill(), set_target(), length(), head_pos, user (Dictionary; user["keep"]=true keeps it from being retired when the pool is full).
  Pool: SnakeTendrilPool.get_pool() creates one node under Game.player; caps LOW 4 / MED 6 / HIGH 8 tendrils; ONE draw call while any lives, none otherwise.
- Hand position for tendril origins: `Player.snake.hand_callable(side)` (side -1 left, 1 right; also foot_callable, back_callable).
- Player.snake (SnakeTraversal): `mode` (NONE SWING ZIP CLIMB FLY), `energy` 0..100, `event(id)` signal (swing_attach, zip, climb, flight, land, ...), counters swings zips climbs flights double_jumps.
  The combat builder must not call move_and_slide on the player while snake.active(); use snake.event for hooks.
- SkillTree verb `snake` has the nodes sn_range sn_speed sn_energy sn_chain sn_wings (combat builder: add your nodes under another verb or the same verb with new ids, re-read skill_tree.gd first).
- HeroPower row keys added: snake_range snake_cost snake_regen snake_speed snake_release climb_speed fly_cruise fly_boost fly_drain fly_free air_jumps.

TESTS AND PERF
- test_hero_verbs passes with the hooks. test_skill_tree expectations moved to 5 verbs / 25 nodes (design changed, not weakened). Perf gate not run yet.

OPEN PROBLEMS
- Swing arcs next to facades (fixed by arc simulation + wall steering, re-check in frames); hero rifle stays shouldered while swinging (check pose); tendril looks like a laser rope at distance (more undulation, head visible).
