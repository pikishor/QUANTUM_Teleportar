# w113-enemy-look (builder: ENEMY ROSTER LOOK, 22 enemy types in faction silhouettes, Blender armour kit + creature generator, weapon attach by id)

STATUS: DONE (third agent, 2026-11-14 07:00 UTC). Everything below is in the working tree, nothing is committed (the integrator commits).
GOAL: 16+ visually distinct enemy types (mercenaries, authority troopers, aliens, mechs), 3 colour variants, 3 LODs, health pips, weak-point glow, telegraphs, ONE weapon-attach function
(weapon id), damage-builder hooks, test tests/test_enemy_look_v3.gd, lineup + combat frames at 15/40/80 m (LOW + MED), 6+ render-look-fix loops, contact sheets in docs/shots/round6/.
Agents of this label: the first did nothing; the second (03:11-04:58Z) did loops 1-7; the third (05:00-07:00Z) loops 8-10, tests, perf, sheets, docs.

DONE (files)
- HUMANS (13 looks, 376 kit parts, one skinned draw each): tools/blender/enemykit/{lib,parts}.py + tools/blender/model_enemy_kit.py -> assets/models/enemy_kit.glb;
  scripts/roster/{foe_kit,foe_arms,foe_looks,foe_human,roster_human}.gd, assets/shaders/foe_body.gdshader; hooks in characters/hero_character.gd (is_foe paths) and humanoid_variants.gd (CLASS_LOOK, FOE_NO_KIT switch).
- CREATURES (9, animated GLB): tools/blender/creaturekit/{lib,species}.py + tools/blender/model_foes.py -> assets/models/foes/*.glb, assets/shaders/foe_creature.gdshader.
- ROSTER WIRING: scripts/roster/foe_species.gd (17 rows, 13 encounters), hooks in roster_species/roster_director/roster_kit/roster_foe, aliens/alien_species + alien_creature.
- LOOP 8-10 (third agent): AlienFx thin telegraph lines + dart bolts (aliens/alien_fx.gd); FoePips (scripts/roster/foe_pips.gd + assets/shaders/foe_pips.gdshader): floating health pips for every damaged
  roster enemy + threat markers for aware enemies 30-95 m away, ONE MultiMesh hidden while empty (an empty MultiMesh cost a draw in every tier); tier LOD ranges + throttled rigs of far bodies
  (foe_human.gd, roster_human.gd); loading-time warm-up (FoeHuman.warm_begin/end + 2 hook lines in scripts/common/shader_warmup.gd); creature wind-up flash as outline + glow flare;
  angular armour plates for brute / elite / hunter (species.py); lighter paints + readability floor + distance lift in foe_body.gdshader; look-dev switches FOE_OLD_LOOK=1 (roster_human.gd),
  FOE_NO_KIT=1 (humanoid_variants.gd), bot options hurt= keep=1 kill= (tests/bot_foe_look.gd).
- TESTS: tests/test_enemy_look_v3.gd (95 checks, PASS, about 50 s, real scene); look-dev tests/foe_viewer.{gd,tscn} + tools/foe_view.sh; tests/bot_foe_look.gd.
- DOCS: ARCHITECTURE.md "Enemy look v3", HANDOFF.md "Wave 113: enemy roster look v3", THIRD_PARTY.md paragraph, docs/shots/round6/enemy_look_iterations.md.
- SHEETS (10 jpg, 2.6 MB): docs/shots/round6/enemy_look_{lineup_humans,lineup_aliens,variants,action,creature_clips,combat_low,combat_med,aliens_low_med,sequence,before_after}.jpg

DECISIONS OTHER AGENTS DEPEND ON
- FoeArms.pieces(weapon_id, rifle_bone, lod) is THE weapon attach point of enemies (WeaponModels.mesh / spec / grip_offsets / muzzle_shift: wave 114 models swap in by themselves).
- FoeHuman.build(look, variant, weapon) -> {root, rig, loco, hanim, body, material, ...}; human RosterFoe exposes humanoid_body, camp=&"merc", hp/max_hp, model, center(), stagger(), died.
- Enemy ids: FoeLooks.IDS (13 humans), FoeSpecies.IDS (17 rows), RosterSpecies.ENCOUNTERS = ENCOUNTERS0 merged with FoeSpecies.ENCOUNTERS.
- AlienFx.line(a, b, secs, color) keeps its signature; FoePips reads RosterFoe.hp/max_hp/spec/vis/crouch/lift/aggro/cloak_k and is owned by AlienFx (fx.pips).

TESTS AND PERF
- PASS after the last change: test_enemy_look_v3 (95 checks), test_alien_world, test_enemy_roster2, test_humanoid_variants, test_humanoid_wiring, test_real_fight, test_enemy_look, test_damage_everywhere, test_hero_polish.
  test_perf_budget: 1 of 119 fails ("...and back within range it is drawn again", the hero's SkinnedMirror range tick: flaky, noted in HANDOFF waves 112/113, not touched by this wave).
- Perf gate (PERF_CHECK=1 tools/perf_report.sh), final tree: LOW OK total draws 96, 139.0 k triangles, tex 110 MB, death 107; MED OK 129, 272.1 k, 141 MB, death 149; HIGH OK 149, 378.0 k, 207 MB, death 170 (of 170).
  An earlier run was HIGH OVER (171): the empty pip MultiMesh cost a draw; fixed by hiding the node. FOE_NO_KIT=1 gave the same 171 then: the kit troopers add no draw.

OPEN PROBLEMS
- HIGH death spike has no headroom (170 of 170); MED 149 of 150.
- No MultiMesh impostors for far crowds (rig throttle only); the riot shield cannot break off; creature faces and hands are simple; at 40-80 m a figure is 20-45 px tall (camera, not mine): markers and pips carry the read.
- The test run prints "Parent node is busy setting up children" from scripts/combat/blast_ops.gd:81 (blast builder's code, a roster rocket in the headless harness): harmless.
- Weapons in hands are the registry's current models until wave 114.
