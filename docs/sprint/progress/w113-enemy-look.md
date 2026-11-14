# w113-enemy-look (builder: ENEMY ROSTER LOOK, 22 enemy types in faction silhouettes, Blender armour kit + creature generator, weapon attach by id)

GOAL: 16+ visually distinct enemy types (mercenaries, authority troopers, aliens, mechs), 3 colour variants, 3 LODs, health pips, weak-point glow, telegraphs, ONE weapon-attach function
(weapon id), damage-builder hooks, test tests/test_enemy_look_v3.gd, lineup + combat frames at 15/40/80 m (LOW + MED), 6+ render-look-fix loops, contact sheets in docs/shots/round6/.
Restart notice: the earlier agent with this label did nothing; everything below is mine. Updated 2026-11-14 04:55 UTC.

DONE (files)
- HUMANS (13 looks, 376 kit parts, one skinned draw each): tools/blender/enemykit/{lib,parts}.py + tools/blender/model_enemy_kit.py -> assets/models/enemy_kit.glb;
  scripts/roster/{foe_kit,foe_arms,foe_looks,foe_human,roster_human}.gd, assets/shaders/foe_body.gdshader; hooks in characters/hero_character.gd (is_foe paths) and humanoid_variants.gd (CLASS_LOOK).
  Looks: merc_rifle merc_shotgun merc_rocket merc_medic merc_officer merc_sniper auth_rifle auth_riot auth_heavy auth_breacher auth_ghost auth_drone auth_engineer.
- CREATURES (9, animated GLB, alien shader): tools/blender/creaturekit/{lib,species}.py + tools/blender/model_foes.py -> assets/models/foes/*.glb
  vael_grunt vael_jackal vael_brute vael_hunter vael_elite vael_stalker vael_bloater grid_walker grid_heavy.
- ROSTER WIRING: scripts/roster/foe_species.gd (17 rows, 13 encounters), hooks in roster_species/roster_director/roster_kit/roster_foe, aliens/alien_species + alien_creature.
- TESTS: tests/test_enemy_look_v3.gd; look-dev tests/foe_viewer.{gd,tscn} + tools/foe_view.sh; tests/bot_foe_look.gd (real-game frames, prints the state of every human body).
- DOCS: ARCHITECTURE.md "Enemy look v3", THIRD_PARTY.md row.
- Loop 7 (real game 2400x1080 LOW, runway of EASTFIELD): the humans were flat saturated silhouettes (far_k and the wind-up pulse flooded the dark kit with the accent colour: thin limbs are all
  edge). Fixed in foe_body.gdshader (edge glow only, 0.8*rim; pulse 0.08+0.5*rim). Hunter looked like a naked tan beanpole -> amber carapace, black plates, ribs, ringed glowing cannon.
  Mechs looked like toys -> pauldrons, glacis, vents, canopy head with antenna, twin autocannon, knee pads, three-part feet, exhaust stacks, reactor in a frame (visible from behind).

NEXT
1. Judge the new LOW frames (gl2/), fix, then MED frames; lineup (22 types, 3 variants), action poses, before/after sheets -> docs/shots/round6/enemy_look_*.jpg (<= 12 jpg q80).
2. test_enemy_look_v3 + test_enemy_roster2 + test_humanoid_variants + test_real_fight again (shader and GLBs changed), perf gate once (PERF_CHECK=1 tools/perf_report.sh 0 1 2).
3. HANDOFF.md entry, final log update, delete scratch frames and tests/dev_foe_dbg.*, SubagentHandback (< 150 words + the three perf verdict lines).

DECISIONS OTHER AGENTS DEPEND ON
- FoeArms.pieces(weapon_id, rifle_bone, lod) is THE weapon attach point of enemies (WeaponModels.mesh / spec / grip_offsets / muzzle_shift: wave 114 models swap in by themselves).
- FoeHuman.build(look, variant, weapon) -> {root, rig, loco, hanim, body, material, ...}; human RosterFoe exposes humanoid_body, camp=&"merc", hp/max_hp, model, center(), stagger(), died.
- Enemy ids: FoeLooks.IDS (13 humans), FoeSpecies.IDS (17 rows), RosterSpecies.ENCOUNTERS = ENCOUNTERS0 merged with FoeSpecies.ENCOUNTERS.

TESTS AND PERF
- Earlier: test_enemy_look_v3 PASS (about 32 s), test_enemy_roster2, test_humanoid_variants, test_humanoid_wiring, test_real_fight, test_director_round2_b, test_director_fixes_b, test_companion,
  test_enemies, test_enemy_types, test_slice_fight, test_character_motion, test_combat_feel all PASS. To re-run after loop 7. Perf gate not run yet (at most twice).

OPEN PROBLEMS
- First body of a look costs about 0.3 s (no prewarm); no crowd instancing of far bodies (a far human is one skinned draw, caps 4 / 6 / 9 by tier); pips only on humans; the riot shield
  cannot break off; creature faces and hands are simple; at 40-80 m the figures are small (camera, not mine); scripts/damage/foe_fx.gd treats `en is Operative` only for visor chips and body sparks.
