# w115-snake-traversal (builder: movement side of QUANTUM SNAKES)

Started 2026-11-14. The earlier agent for this label died at the weekly limit before doing anything (auto_w115-snake-traversal.md is empty).
Updated 2026-11-15 (after the enemy counters, the assist option and the mission work).

GOAL: hero signature traversal: SNAKE SWING, SNAKE ZIP, SNAKE CLIMB, SNAKE FLIGHT + movement kit, ONE contextual SNAKE button (+ FLY/LAND), tutorial + 2 missions,
audio, tests, frames at phone res LOW and MED, ONE shared tendril visual for the combat builder.

DONE (all under godot/)
- SHARED TENDRIL: scripts/quantum/snake_tendril.gd, snake_tendril_pool.gd, assets/shaders/snake_tendril.gdshader (ONE MultiMesh draw for every tendril, data texture, viper head)
- Numbers: snake_power.gd (SnakePower) + 11 keys in each HeroPower row + SkillTree verb `snake` (RANGE SPEED ENERGY CHAIN BONUS WING POWER, 5th column) + HERO MODE (unlimited)
- Movement: snake_anchor.gd (finder), snake_swing.gd, snake_zip.gd, snake_climb.gd (walls, ceilings, mantle, leap), snake_flight.gd, snake_traversal.gd (orchestrator = Player.snake, the kit:
  double jump, super jump, landing roll), snake_pose.gd, snake_camera.gd, snake_fx.gd (speed lines, anchor marker), snake_missions.gd + snake_mission_director.gd
- Hooks: player.gd, player_body.gd, camera_rig.gd, hero_verbs.gd, game.gd (actions snake=Tab, fly=backslash), sfx.gd (snk_ family), touch_controls.gd (SNAKE + FLY buttons),
  mission_board.gd (2 offers), skill_screen.gd (any column count), specialist.gd (2 one-line hooks), ui_settings.gd + options_screen.gd (AIM ASSIST also drives the snake assist)
- Audio: assets/audio/snk_*.ogg (12 files, ~98 KB) from tools/audio/make_snake.py
- Enemy counters: SnakeTraversal.lead_offset(t) (snipers lead a hero on the snakes; SnakePower.SNIPER_LEAD by difficulty .55/.8/.95/1), SnakeTraversal.jam_in_radius (the warden's
  phase pulse jams snakes: sideways 2x pulse radius, 6 m below to 45 m above; SnakePower.JAM_SECONDS 1/2/3/3.5, HERO MODE immune; every state drops WITHOUT the boost)
- Tests (all PASS): tests/test_snake_traversal.gd (~130 checks: tables, tendril, kit, zip+climb+mantle+ceiling, swing, flight, counters, buttons, missions, assist option),
  tests/test_snake_swing_run.gd (STORY and NORMAL: 9 swings, 520 m, no ground, peak 41/59 m/s). Dev probes: bot_snake.gd, dev_snake_*.gd
- MEASURED swing run (headless, real city): frame ms avg 16.6, p99 25, worst 39-94 (a chunk streaming frame); renders below

NEXT
1. Render-look-fix loops (need >= 8): swing, climb, zip, flight at LOW and MED, hero close-ups, HUD in the air; defects below, self-review vs docs/owner_shots/round5
2. Perf gate twice (PERF_CHECK=1 tools/perf_report.sh 0 1 2): mid-way and end; ARCHITECTURE.md section; contact sheets (<= 12) in docs/shots/round6/

DECISIONS (other agents depend on)
- TENDRIL API (combat builder, do not fork): `SnakeTendril.fire(origin, target, opts)`; origin/target = Vector3 | Node3D | Callable; opts speed travel wriggle color thickness head life
  tension on_attach host; object: state, attached/retracted signals, tension, retract(t), kill(), set_target(), length(), head_pos, user["keep"]. Pool: SnakeTendrilPool.get_pool(host),
  caps LOW 4 / MED 6 / HIGH 8, ONE draw while any lives. Hands: `Player.snake.hand_callable(side)`.
- Player.snake (SnakeTraversal): mode NONE SWING ZIP CLIMB FLY, energy 0..100, `event(id)` signal, counters swings zips climbs flights double_jumps; do not call move_and_slide on the
  player while snake.active(). Jam: `Player.snake.jam(seconds)` also works for any combat jammer you add.
- SkillTree verb `snake` owns sn_range sn_speed sn_energy sn_chain sn_wings (combat builder: other ids or another verb).

OPEN PROBLEMS
- Look-dev findings of the render loops go here (hero rifle pose while swinging, wing tips, tendril read at distance)
- Tutorial LAND step can complete while flying low (reach tolerance 6 m); `Parameter "material" is null` noise in tests and bots is not from this work
