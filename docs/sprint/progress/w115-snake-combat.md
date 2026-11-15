# w115-snake-combat (builder: combat side of QUANTUM SNAKES)

Started 2026-11-15. Shares the tree with w115-snake-traversal (movement; owns scripts/quantum/snake_tendril*.gd, snake_power.gd, Player.snake). STATUS: DONE, waiting for the integrator (nothing committed).

GOAL: SNAKE verbs (PULL, GRAB-AND-THROW, DISARM, YANK COVER, NET, LASH, SHIELD, DECOY, TRAP, GUARD), 12 SNAKE BOMBS registered in BlastTable (cat `snake`), SNAKE class in the weapon wheel + ability wheel,
energy/cooldown, skill tree column SNAKE COMBAT, enemy reactions (panic, cut, jam, hunter, crowd), 2 Mission Board missions, tutorial hints, audio, tests/test_snake_combat.gd (real scene),
22 sequences at phone res (LOW + MED), 8+ loops, budget at LOW.

DONE (all under godot/)
- Data and engine: scripts/quantum/snake_rows.gd (22 powers, BlastTable.register via SnakeRows.ensure(), cat `snake`, internal sv_slam / sv_lash_finish / sb_bomblet), snake_swarm.gd (ONE MultiMesh draw for all
  free snakes; shapes crawl coil orbit ball ring rise; caps LOW 16 / MED 28 / HIGH 44; thinner near the lens), snake_aim.gd, snake_holds.gd, snake_verbs.gd (10 verbs), snake_bombs.gd (12 bombs; flare marks
  MultiMesh), snake_react.gd (panic, cut, jam, crowd film + cheer, hunter spawn + static net), snake_war.gd (controller under Player), snake_icons.gd (22 drawn pictures), snake_ui.gd (wedges, rings, quick
  casts, HUD texts), snake_war_missions.gd (SNAKE ARENA, ROOFTOP SNAKE HUNT, hints, bonus); scripts/common/strings_snake_war.gd (ES / HI)
- Hooks: player.gd, player_weapon.gd, game.gd (4 actions), sfx.gd (snw_), enemy_manager.gd (decoy), weapon_wheel.gd (ring_items, activate), weapon_icons.gd, touch_controls.gd (wheel_items appends the two
  wedges, SNAKE_ABILITIES), hud.gd, mission_board.gd, blast_fx.gd (recipe snake), skill_tree.gd (column, LEVEL_CAP 46), specialist.gd + enemy_types.gd (hunter), strings.gd, assets/icons/e_hunter.png
- Sounds: tools/audio/make_snake_war.py -> 24 snw_*.ogg (250 KB). Look-dev: tests/bot_snake_war.gd, bot_snake_ui.gd, bot_snake_war_perf.gd; probes tests/dev_snake_*.gd (mine: war pick grab swarm coil decoy seeker)

TESTS
- tests/test_snake_combat.gd: PASS, 130 checks, about 70 s (verbs, bombs by table radius, status, preview rings, energy, caps per tier, wheels, reactions, hints, missions)
- 36 related tests run twice (wheels, HUD, skill tree, blasts, localisation, enemies, campaign, quantum): all PASS; test_snake_traversal / new_verbs / weapon_ui_v3 flaked only under load (another agent rendering)
- Fixed from the first batch (no test weakened): the wedges are appended in TouchControls (WeaponWheel.items stays weapons only), WHEEL_ABILITIES keeps its seven, the touch tests measure the drawn disc
  (RadialWheel.disc_scale, >= 64 px), test_blast_arsenal fires the snake bombs through the table, ES / HI strings for the skill column

LOOKS: 12 loops at LOW and MED (list: docs/shots/round6/snake_combat_iterations.md); sheets docs/shots/round6/snake_combat_*.jpg (10 files, 8 MB, q80)
PERF GATE (once, PERF_CHECK=1 tools/perf_report.sh 0 1 2): LOW draws 70 / 128k tris / 112 MB OK; MED 97 / 241k / 143 MB OK; HIGH 113 / 327k / 209 MB OK
BUDGET AT LOW (bot_snake_war_perf): armed +3 draws, shield +2, net +3, guard +5, flare marks +11, mega +19; one body 216 triangles, 16 bodies = 1 draw / 3.5k triangles; no new texture

DECISIONS (other agents depend on)
- `SnakeSwarm.get_swarm(p).spawn(shape, pos, opts)` for free-moving snakes; `SnakeTendril` for ropes from the hand (untouched traversal API)
- BlastTable ids sb_coil sb_swarm sb_flare sb_freeze sb_seeker sb_chain sb_cluster sb_constrict sb_burrow sb_gravity sb_storm sb_mega (cat `snake`), registered when the Player gets its SnakeWar;
  sb_bomblet, sv_slam, sv_lash_finish are cat `internal`
- `SnakeWar.instance` / `SnakeWar.of(player)` / `SnakeWar.holding()` / `SnakeWar.absorb()`; `war.cast(id, force)`; the energy pool is Player.snake.energy (shared with the traversal)
- Enemy type `hunter` (Specialist role) exists in EnemyTypes: only SnakeReact spawns it

OPEN PROBLEMS (none blocks)
- fx_threat.gdshader (not mine): stealth pips (mode 4) are caught by the health-bar branch and drawn as white plates over suspicious enemies; fix `v_data.w > 2.5 && v_data.w < 3.5`
- snake_pose.gd:182 (traversal) prints "Basis must be normalized" after a zip to a car; pooled enemies keep a freeze overlay for its remaining seconds after EnemyManager.clear() (bots reset it)
- No cast animation for the hero (arms keep the rifle hold, the hands glow); no SNAKE screen with the stats; nothing measured on a phone
