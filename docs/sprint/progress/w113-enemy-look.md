# w113-enemy-look (builder: ENEMY ROSTER LOOK, 16+ distinct enemy types, Blender armour kit, weapon attach by id)

GOAL: at least 16 visually distinct enemy types in faction silhouettes (mercenaries, authority troopers, aliens, mechs/walkers), readable at 40 m on a phone,
3 colour variants, 3 LODs, health pips, weak-point glow, telegraphs, ONE weapon-attach function (weapon id), compatible with the damage builder's hooks,
test tests/test_enemy_look_v3.gd, 16-type lineup + combat frames at 15/40/80 m (LOW + MED), 6+ render-look-fix loops, contact sheet in docs/shots/round6/.

STATUS (2026-11-14 ~03:50 UTC, restart notice: the earlier agent with this label did nothing, auto_ log empty).
Siblings: w113-damage (scripts/damage/*: FoeFx reads `hp max_hp camp faction id spec cfg humanoid_body model camp_speed scale_mult center() stagger()` and the `died` signal; sets
instance uniform `dmg_fx` on `humanoid_body`), w113-weapons-roster (WeaponDefs packs), w113-weapons-blast (BlastTable).

ARCHITECTURE (decided): humans = Quaternius base body (the hero's rig) + Blender armour kit, merged into ONE skinned surface by HeroCharacter.build (3 small hooks: opts foe_look /
weapon_id / kit_lod / variant), driven by CharacterRig + Locomotion + HumanoidAnim; shader foe_body.gdshader (no textures, vertex-colour kinds, AO + edge wear baked in UV).
Aliens / mechs: Blender-generated animated one-draw GLBs on the alien.gdshader path (next).

DONE (files)
- tools/blender/enemykit/{lib,parts}.py + tools/blender/model_enemy_kit.py -> assets/models/enemy_kit.glb (13 looks, 364 parts, 1.3 MB; run `.venv-tools/bin/python tools/blender/model_enemy_kit.py`, 8 s)
- scripts/roster/foe_kit.gd (FoeKit loader, pieces(look, bones, lod)), foe_arms.gd (FoeArms.pieces / setup / mount_class: weapon by registry id via WeaponModels, simplified per LOD),
  foe_looks.gd (13 looks: merc_rifle merc_shotgun merc_rocket merc_medic merc_officer merc_sniper auth_rifle auth_riot auth_heavy auth_breacher auth_ghost auth_drone auth_engineer;
  3 palettes per camp, FoeLooks.make_material), foe_human.gd (FoeHuman.build/set_lod/drive/fire/hit/die/windup/set_hp/set_tele; prototype cache + duplicate)
- assets/shaders/foe_body.gdshader; hooks in scripts/characters/hero_character.gd (is_foe paths, _fit_foe, _drop_bones, eyes removed)
- look-dev: tests/foe_viewer.{gd,tscn} + tools/foe_view.sh (`tools/foe_view.sh /tmp/p ids=a,b pose=aim|run|fire|hit|die|windup variants=0,1,2 views=front3q,back,side,face per=4 dist=6.5 lod=mid`)

NEXT
1. Fix defects of loop 1 (floating pips, blocky boots, tan plates, hat brim winding, clipboard plate), more loops on all 13 looks.
2. Wire into the game: RosterSpecies rows (merc_* use the new bodies, 8 new rows), RosterKit.setup_body branch, RosterFoe hooks (RosterHuman bridge: drive, LOD, hit, die, pips, telegraph),
   city troopers (HumanoidVariants classes -> kit looks), FoeFx compat (humanoid_body).
3. Aliens (7) + mechs (2): Blender creature generator.
4. tests/test_enemy_look_v3.gd, bot frames 15/40/80 m LOW+MED, perf gate (twice), ARCHITECTURE.md + HANDOFF, contact sheet.

DECISIONS OTHER AGENTS DEPEND ON
- FoeArms.pieces(weapon_id, rifle_bone, lod) is THE weapon attach point of enemies (reads WeaponModels.mesh/spec/grip_offsets/muzzle_shift: wave 114 models swap in by themselves).
- Look ids above; FoeLooks.IDS; FoeHuman.build(look, variant, weapon) returns a dict {root, rig, loco, hanim, body, material, ...}.

TESTS AND PERF: nothing run yet (viewer only). Near mesh 4.8-5.7k tris (budget 6000), mid ~2.55k, far ~1.45k; first build of a look costs ~0.8 s (prewarm needed).
OPEN PROBLEMS: build hitch per look, weapon meshes of the open models are 1.3-2.4k tris (reduced by FoeArms), far mesh above 1100 target.
