# w114-weapons-art (builder: weapon ART and ANIMATION; Blender weapon kit, WeaponModels entry point, class handling and FX)

GOAL: a distinct, detailed model for EVERY weapon (230+ ids of WeaponDefs.all_ids()), built by a parametric Blender kit (godot/tools/blender/weapon_kit.py),
exported as glTF to godot/assets/models/weapons/, loaded through WeaponModels.path(id) / WeaponModels.build(id, lod) / WeaponModels.mesh(id[, lod]);
enemies carry the same models (FoeArms), per-class handling (grips/IK, part motion, reload), FX by class, tests + renders + size/memory report.

STATUS (start, 2026-11-14): restart notice read. The earlier agent died at the usage limit with no work (no files). Tree is wave 113 (f6c7ade), clean.
Parallel builder: w114-weapons-ui (menus; uses WeaponModels.build for icons). Budget this wave: added weight <= 30 MB (use <= 20), no draw/tri/tex growth over the gate.

DONE
- (nothing yet) surveyed: scripts/player/weapon_models*.gd (procedural ArrayMesh, one shared ShaderMaterial weapon_look.gdshader, vertex colour rgb paint + alpha glow),
  consumers: player_body.set_weapon_look, foe_arms._raw (reads WeaponModels.mesh surface arrays, sorts triangles into palette kinds by vertex colour), weapon_preview.gd,
  weapon_icons.gd, tools/icons/icon_maker.gd, weapon_roster.gd. Blender toolchain: godot/.venv-tools (bpy 5.2.3), tools/blender/helpers.py (Part, export_model), atlas.py, glbtool.py.

NEXT
1. WeaponModels.path/build/mesh(id, lod) entry point with fallback to the current procedural meshes (first 10 minutes).
2. weapon_kit.py parts library + spec table + material atlas + LOD0/LOD1 + glTF export (per class packs).
3. Loader, shader, muzzle/grip/eject/part nodes, FoeArms hook, preview/icon hooks.
4. Handling: class animation sets, part motion, reload; FX by class.
5. tests/test_weapon_models_v3.gd, lineups (6 batches), in-hand frames (12), enemy frames (8), perf gate x2, size/memory report, ARCHITECTURE.md + HANDOFF.md.

DECISIONS OTHER AGENTS DEPEND ON
- (to fill) WeaponModels.build(id, lod) -> Node3D; WeaponModels.mesh(id, lod := 0) -> ArrayMesh; WeaponModels.material() stays the one shared weapon material.

TESTS AND PERF: none yet.
OPEN PROBLEMS: none yet.
