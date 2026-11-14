# w114-weapons-art (builder: weapon ART and ANIMATION; Blender weapon kit, WeaponModels entry point, class handling and FX)

GOAL: a distinct, detailed model for EVERY weapon (229 ids of WeaponDefs.all_ids()), built by a parametric Blender kit (godot/tools/blender/weapon_kit.py),
exported as glTF to godot/assets/models/weapons/, loaded through WeaponModels.path(id) / WeaponModels.build(id, lod) / WeaponModels.mesh(id[, lod]);
enemies carry the same models (FoeArms), per-class handling (grips/IK, part motion, reload), FX by class, tests + renders + size/memory report.

STATUS (2026-11-14 ~14:50 UTC): the earlier agent left nothing. Kit built, all 229 ids have a glb (LOD0 avg 1.8k tris, LOD1 avg 0.6k), imported, hero holds them, enemies carry them (LOD1).

DONE (files)
- godot/tools/blender/: weaponlib.py (numpy geometry core: sections/loft/lathe/extrude/sweep, weighted-normal style, weld, vertex AO via bpy BVH, GLB writer with quantized normals),
  weapon_mats.py (32 swatches 128px: albedo/ORM/normal packed 4x8 into 3 png, texture arrays), wparts.py (palettes/factions, muzzle devices, optics, stocks, grips, magazines, rails),
  wguns.py (long guns, pistols, revolvers), wexotic.py (energy, launchers, rotary, flamer, bows), wmelee.py (melee + grenades/mines/strike devices), weapon_specs.py (ONE row per id),
  weapon_index.json (id/name/class/look from the game), weapon_preview.py (numpy sheets), weapon_kit.py (CLI: --ids --class --atlas --sheet --report --jobs).
- assets/shaders/weapon_pbr.gdshader (texture arrays + object-space projection, per-part vertex animation uniforms, edge wear from derivatives, dbg uniform for debug views);
  assets/models/weapons/<id>.glb(+.import) x229, weapon_atlas_{alb,orm,nrm}.png(+.import 2d_array_texture), weapons_meta.json.
- scripts/player/weapon_models.gd: path/build/point/kit_meta/has_model/material_for/hand_material/pbr_material/look_scale, mesh(id, lod), muzzle_shift(id, sc)/grip_offsets(id, sc);
  SPEC merged with the kit's grips (reach = right hand + hold, butt at the shoulder for stocks).
- hooks: player_body.gd (own PBR copy, glow, kit look scale 1.2/1.2/1.08, scaled grips), foe_arms.gd (LOD1 mesh + enemy scale), weapon_preview.gd + tools/icons/icon_maker.gd (material_for).
- tests/weapon_lineup.gd(.tscn) + tools/weapon_lineup.sh (Godot lineup: batch=N per=40 cols=8 view=side|q34|top lod=0|1 ids=a,b dbg=1..5).

NEXT
1. model quality passes (energy/quantum guns detached emitters and slab bodies, melee proportions (axes, scythe, chain whip, gauntlet), bow riser, pistol brick look, katana blade material)
2. handling: part motion in the hero's hand (slide recoil, pump, rotor spin, hammer, mag drop on reload), class FX (shell eject, muzzle flash shapes, laser, scope reticle), see ARCHITECTURE
3. tests/test_weapon_models_v3.gd, 6 lineup batches + 12 in-hand + 8 enemy frames (docs/shots/round6/), size/memory report, perf gate twice, ARCHITECTURE.md + HANDOFF.md

DECISIONS OTHER AGENTS DEPEND ON
- WeaponModels.build(id, lod) -> Node3D "Weapon_<id>" with MeshInstance3D "Body" + Marker3D Muzzle GripR GripL Eject Aim Mag (Optic Laser for kit models); mesh frame: origin = FRONT tip of the weapon, barrel to -Z, +Y up.
- WeaponModels.material_for(id): kit models use the shared PBR ShaderMaterial (texture arrays); use it instead of WeaponModels.material() for anything that shows a weapon mesh.
- WeaponModels.mesh(id, 1) = LOD1 (vertex colour rgb = base albedo, a = glow) for enemies/pickups.
- weapons_meta.json per id: gr gl reach eject aim mag optic laser parts tris0 tris1 aabb rotor hinge.

TESTS AND PERF: weapon_view/foe_view/weapon_lineup renders OK; test_weapons_available_display passes on stubs; perf gate not run yet.
OPEN PROBLEMS: see NEXT 1. weapons-ui builder: I edited ONE line each in weapon_preview.gd and icon_maker.gd (material_for).
