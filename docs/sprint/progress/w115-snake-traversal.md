# w115-snake-traversal (builder: movement side of QUANTUM SNAKES)

Started 2026-11-14. The earlier agent for this label died at the weekly limit before doing anything (auto_w115-snake-traversal.md is empty).
Updated 2026-11-15 02:55 (enemy counters, assist option, render loops 11-16, swing reliability, perf gate 1).

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

RENDER LOOPS (LOW + MED, 2400x1080, touch HUD on, real camera; frames in the scratchpad only, sheets go to docs/shots/round6 at the end)
- 11 climb: hero cut off at the bottom of the frame (lens +1 m, arm +1.3 m) -> arm +1.7, lens +0.05, pitch 0.1: whole hero in frame
- 12 flight: wings swept 4 m back came at the lens and filled the screen -> wings open sideways (span 3.0-4.8, back 0.6-2.4), lens +14 deg -> +8 deg, arm 7 m -> 5.5 m
- 13 flight camera sat above his head (hero at 78 % of the frame, boots cut) -> lens at chest height (-0.35 m): hero 57-90 %
- 14 swing camera at 40 m/s was 7.5 m back with +17 deg (hero 8 % of the frame) -> arm 0.5 + 0.03 v, lens +0.3 v (max 12 deg)
- 15 anchor marker clipped to a wedge on a corner (depth test) -> no depth test, a third larger; SNAKE button crowded RELOAD/AIM (tangent rings) -> r 46 at the centre of the gap (6 px each)
- seen, not mine: the building-corner neon strips read as a huge glowing pillar when the camera passes; thin violet cable loops on facades at MED look like floating wires up close
PERF (tests/bot_snake_perf.gd): a snake state costs +1 draw (the MultiMesh), marker +1 quad only in the air, speed lines 1 canvas draw above 22 m/s; the idle SnakeFx cost +2 draws at MED in the
gate (empty canvas layer + hidden mesh): now created lazily -> gate MED 129 total, death 149 (budget 150). Gate 1: LOW OK (98, death 109), MED OK after the fix (151 before), HIGH OK (death 170)
SWING RELIABILITY (tests/dev_snake_routes.gd, random downtown routes + the test route): the old chain passed 25 % of routes; now the rope is reeled in when the lowest point would be within
9 m of the street (SnakeSwing.max_rope), a long rope scores higher, the arc test is judged against free fall, a chain scan that finds nothing ahead looks beside and behind: test route 8/8
(STORY and NORMAL), random routes about 55 %. The swing run test needs TrafficField.bare_street (cars are anchors too).
OLD TEST FIX: the super jump took a held JUMP + forward (vault / mantle habit) -> only from standing, stick idle, 0.3 s hold (test_traversal passes again)

NEXT
1. final renders at LOW + MED after the last camera / marker changes -> contact sheets (<= 12) in docs/shots/round6, delete scratch frames
2. ARCHITECTURE.md section; perf gate 2 (final); full re-run of my two tests and the shared-file tests; self-review against docs/owner_shots/round5

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
