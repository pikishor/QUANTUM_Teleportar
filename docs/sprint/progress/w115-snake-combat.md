# w115-snake-combat (builder: combat side of QUANTUM SNAKES)

Started 2026-11-15. Shares the tree with w115-snake-traversal (movement; owns scripts/quantum/snake_tendril*.gd, snake_power.gd, Player.snake).

GOAL: SNAKE verbs (PULL, GRAB-AND-THROW, DISARM, YANK COVER, NET, LASH, SHIELD, DECOY, TRAP, GUARD), 12 SNAKE BOMBS registered in BlastTable (cat `snake`), SNAKE class in the weapon wheel + ability wheel,
energy/cooldown, skill tree column SNAKE COMBAT, enemy reactions (panic, cut, jam, hunter, crowd), 2 Mission Board missions, tutorial hints, audio, haptics, tests/test_snake_combat.gd (real scene),
12 verb/bomb sequences at phone res (LOW + MED), 8+ loops, active-snake/particle budget at LOW.

DONE (all under godot/; real-scene test tests/test_snake_combat.gd: 125 checks, ~60 s, 1 left to verify after the last fix)
- Data and engine: scripts/quantum/snake_rows.gd (22 powers, BlastTable.register via SnakeRows.ensure(), cat `snake`, internal sv_slam / sv_lash_finish / sb_bomblet), snake_swarm.gd (ONE MultiMesh draw for all
  free snakes; shapes crawl coil orbit ball ring rise; caps LOW 16 / MED 28 / HIGH 44; reuses assets/shaders/snake_tendril.gdshader), snake_aim.gd, snake_holds.gd (wrap/net/snare/drag/lift via Drone.disable),
  snake_verbs.gd (10 verbs), snake_bombs.gd (12 bombs; flare marks MultiMesh), snake_react.gd (panic, cut, jam, crowd film + cheer, hunter spawn + static net), snake_war.gd (controller under Player),
  snake_icons.gd (22 drawn pictures), snake_ui.gd (wheel wedges SNAKE + BOMBS, rings, ability quick casts, HUD texts), snake_war_missions.gd (SNAKE ARENA, ROOFTOP SNAKE HUNT, hints, bonus)
- Hooks (one or few lines each): player.gd (attach, Player.damage -> SnakeWar.absorb), player_weapon.gd tick (armed power: no gun fires), game.gd actions snake_pull/net/shield/bomb, sfx.gd family snw_,
  enemy_manager.gd (get_clone + hit_clone: the decoy), weapon_wheel.gd (items/ring_items/activate), weapon_icons.gd (draw + draw_flat), touch_controls.gd (4 ability entries + WEAPON face),
  hud.gd (ammo_text, weapon_text, alt_text, desktop pic), mission_board.gd (inject + build + _build_snake_war), blast_fx.gd (recipe `snake`: small pop, thin ring, no smoke), skill_tree.gd (verb snakewar:
  sw_bite sw_spread sw_quick sw_brood sw_grip; LEVEL_CAP 40 -> 46), specialist.gd + enemy_types.gd (the HUNTER: role hunter, static net launcher), assets/icons/e_hunter.png
- Tests moved for the additions: test_skill_tree (6 verbs, 30 nodes), test_hud_declutter (ability wheel 11 discs), test_energy_destructive_scene (weapon wheel <= 14 discs)
- Sounds: tools/audio/make_snake_war.py -> assets/audio/snw_*.ogg (24 files, ~250 KB)
- Look-dev: tests/bot_snake_war.gd (SW_IDS, SW_OUT, SW_DIST, SNAKE_GLOW; run with tools/bot.sh, QUALITY=0|1, --fixed-fps 12), dev probes tests/dev_snake_*.gd

NEXT
1. Render-look-fix loops (>= 8): coil/swarm/chain/seeker/guard are being reworked (bigger snakes, quieter blast fx); then flare, freeze, gravity, storm, mega, net, shield, lash, grab, yank at LOW and MED
2. Wheel + HUD frames with the touch layer (BOT_USER_ARGS=--touch): the two wedges, the ring of pictures, the WEAPON face, the ability wheel
3. Perf: PERF_CHECK=1 tools/perf_report.sh 0 1 2 twice (mid-way once the look is final, end), measure the active snakes and particles at LOW
4. ARCHITECTURE.md section, HANDOFF note, contact sheet docs/shots/round6/snake_combat_*.jpg, final report

DECISIONS (other agents depend on)
- `SnakeSwarm.get_swarm(p).spawn(shape, pos, opts)` for free-moving snakes; `SnakeTendril` for ropes from the hand (untouched traversal API)
- BlastTable ids: sb_coil sb_swarm sb_flare sb_freeze sb_seeker sb_chain sb_cluster sb_constrict sb_burrow sb_gravity sb_storm sb_mega (cat `snake`, registered lazily by SnakeRows.ensure()); sb_bomblet, sv_slam,
  sv_lash_finish are cat `internal`
- `SnakeWar.instance` / `SnakeWar.of(player)` / `SnakeWar.holding()` / `SnakeWar.absorb()`; `war.cast(id, force)`; the energy pool is Player.snake.energy (shared with the traversal)
- Enemy type `hunter` (Specialist role) exists in EnemyTypes: only SnakeReact spawns it

TESTS AND PERF
- tests/test_snake_combat.gd: 124 of 125 checks (the mega radius check was fixed by taking the result of BlastTable.apply); about 60 s
- Perf gate not run yet

OPEN PROBLEMS
- snake_pose.gd:182 (traversal builder's file) prints "Basis must be normalized in order to be casted to a Quaternion" after a zip to a car (PULL on a heavy target): their bug, to report
- Visual weak spots found by the first sweep (being fixed): snakes read as thin pale ghosts at 10 m, the default blast fx fogs the street (new recipe `snake`), the guard ring was a 25 m disc (removed)
