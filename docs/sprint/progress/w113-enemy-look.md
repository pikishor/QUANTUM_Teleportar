# w113-enemy-look (builder: ENEMY ROSTER LOOK, 22 enemy types in faction silhouettes, Blender armour kit + creature generator, weapon attach by id)

GOAL: 16+ visually distinct enemy types (mercenaries, authority troopers, aliens, mechs), 3 colour variants, 3 LODs, health pips, weak-point glow, telegraphs, ONE weapon-attach function
(weapon id), damage-builder hooks, test tests/test_enemy_look_v3.gd, lineup + combat frames at 15/40/80 m (LOW + MED), 6+ render-look-fix loops, contact sheets in docs/shots/round6/.
Restarts: the first agent with this label did nothing; the second (03:11-04:58Z) did loops 1-7; the third (me, from 05:00Z) is on loop 8+. Updated 2026-11-14 05:40 UTC.

DONE (files)
- HUMANS (13 looks, 376 kit parts, one skinned draw each): tools/blender/enemykit/{lib,parts}.py + tools/blender/model_enemy_kit.py -> assets/models/enemy_kit.glb;
  scripts/roster/{foe_kit,foe_arms,foe_looks,foe_human,roster_human}.gd, assets/shaders/foe_body.gdshader; hooks in characters/hero_character.gd (is_foe paths) and humanoid_variants.gd (CLASS_LOOK).
  Looks: merc_rifle merc_shotgun merc_rocket merc_medic merc_officer merc_sniper auth_rifle auth_riot auth_heavy auth_breacher auth_ghost auth_drone auth_engineer.
- CREATURES (9, animated GLB, alien shader): tools/blender/creaturekit/{lib,species}.py + tools/blender/model_foes.py -> assets/models/foes/*.glb
  vael_grunt vael_jackal vael_brute vael_hunter vael_elite vael_stalker vael_bloater grid_walker grid_heavy.
- ROSTER WIRING: scripts/roster/foe_species.gd (17 rows, 13 encounters), hooks in roster_species/roster_director/roster_kit/roster_foe, aliens/alien_species + alien_creature.
- TESTS: tests/test_enemy_look_v3.gd (PASS, about 50 s); look-dev tests/foe_viewer.{gd,tscn} + tools/foe_view.sh; tests/bot_foe_look.gd (real-game frames, prints the state of every human body).
- DOCS: ARCHITECTURE.md "Enemy look v3", THIRD_PARTY.md row.
- LOOP 8 (this restart), all in my scope:
  * AlienFx telegraph lines (aliens/alien_fx.gd): the 12 cm additive box was a screen-wide translucent sheet when a line passed the camera (every combat frame showed pink/cyan/yellow wedges). Now the width
    follows the distance of the nearest point to the camera (max 0.9 deg of view) and the line fades out within 2.5 m of the lens (AlienFx._place_line, line_width()).
  * FLOATING HEALTH PIPS for every damaged roster enemy (humans, aliens, walkers): scripts/roster/foe_pips.gd + assets/shaders/foe_pips.gdshader, ONE MultiMesh (60 instances, one draw, none while nobody
    is hurt), owned by AlienFx (fx.pips), 5 pips green/amber/red, readable size at any distance, depth-tested. API: FoePips.lit_of / color_of / wants / top_of, pips.rows (tests).
  * FoeHuman LOD ranges scale by tier (TIER_K 0.72 / 0.9 / 1.0: LOW mid mesh from 11.5 m, far from 33 m); RosterHuman drives the rig every 2nd frame beyond 26 m and every 3rd beyond 50 m
    (crowds of 8+ cost 2-3 bodies of CPU; h.tick / h.drives are counted for tests).
  * Loading-time warm-up: FoeHuman.warm_begin/warm_end (merc_rifle, auth_riot + vael_grunt, grid_walker bodies shown for the warm-up frames), two hook lines in scripts/common/shader_warmup.gd.
  * Creature kit: angular armour plates (sloped pauldrons with spikes, faceted knee guards, knuckle blocks) for brute / elite / hunter instead of balls, brute armour in dark chitin (species.py `armor`,
    `angular`); rebuilt vael_brute / vael_elite / vael_hunter GLBs.
  * Test: new checks for pips (rows, lit count, one MultiMesh), line width + fade, tier LOD, throttled rigs, warm-up.

NEXT
1. Judge game frames of this state (scratch e1/ LOW, then MED e2/), fix what is weak (defect list below), at least 2 more loops; look at action poses (aim/fire/windup/hit/die) in the viewer.
2. Contact sheets -> docs/shots/round6/enemy_look_*.jpg (<= 12 jpg q80): lineup 22 types, before/after, action, combat 15/40/80 m LOW + MED.
3. test_enemy_look_v3 + test_enemy_roster2 + test_humanoid_variants + test_real_fight again; perf gate once at the end (PERF_CHECK=1 tools/perf_report.sh 0 1 2).
4. HANDOFF.md entry, ARCHITECTURE.md update (pips, throttle, warm, thin lines), final log, delete scratch frames and tests/dev_foe_dbg.*, SubagentHandback (< 150 words + three perf verdict lines).

DECISIONS OTHER AGENTS DEPEND ON
- FoeArms.pieces(weapon_id, rifle_bone, lod) is THE weapon attach point of enemies (WeaponModels.mesh / spec / grip_offsets / muzzle_shift: wave 114 models swap in by themselves).
- FoeHuman.build(look, variant, weapon) -> {root, rig, loco, hanim, body, material, ...}; human RosterFoe exposes humanoid_body, camp=&"merc", hp/max_hp, model, center(), stagger(), died.
- Enemy ids: FoeLooks.IDS (13 humans), FoeSpecies.IDS (17 rows), RosterSpecies.ENCOUNTERS = ENCOUNTERS0 merged with FoeSpecies.ENCOUNTERS.
- AlienFx.line(a, b, secs, color) keeps its signature (the width cap is inside); FoePips reads RosterFoe.hp/max_hp/spec/vis/crouch/lift.

TESTS AND PERF
- test_enemy_look_v3 PASS after loop 8 (90 checks). test_enemy_roster2, test_humanoid_variants, test_humanoid_wiring, test_real_fight, test_director_round2_b, test_companion, test_enemies,
  test_enemy_types, test_slice_fight, test_character_motion, test_combat_feel PASSed before loop 8: re-run the ones that touch the changed files at the end. Perf gate not run yet (at most twice).

OPEN PROBLEMS
- The test run prints "Parent node is busy setting up children" from scripts/combat/blast_ops.gd:81 (blast builder's code, a rocket of a roster foe in the headless harness): not mine, harmless.
- First body of a look costs about 0.3 s unless warmed (two looks and two creatures are warmed at load); no MultiMesh impostors for far crowds (rig throttle only); the riot shield cannot break off;
  creature faces and hands are simple; at 40-80 m the figures are small (camera, not mine).
