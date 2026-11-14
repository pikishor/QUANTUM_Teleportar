# w114-weapons-art (builder: weapon ART and ANIMATION; Blender weapon kit, WeaponModels entry point, class handling and FX)

STATUS: DONE (2026-11-14 15:52 UTC). Everything is in the working tree, nothing is committed (the integrator commits). Details: godot/ARCHITECTURE.md "Weapon kit", docs/HANDOFF.md "Wave 114".
GOAL: a distinct, detailed model for EVERY weapon (229 ids of WeaponDefs.all_ids()) from a parametric Blender kit, one PBR material, hero + enemies carry the same models, class handling, tests, renders, size report.

DONE (files)
- godot/tools/blender/: weaponlib.py (numpy geometry core, weighted-normal style, vertex AO, GLB writer), weapon_mats.py (32 swatches 128 px, albedo/ORM/normal in 3 png), wparts.py (factions, palettes, parts),
  wguns.py, wexotic.py (energy, launchers, rotary, flamer, bows), wmelee.py (melee, grenades, mines, strikes), weapon_specs.py (ONE row per id), weapon_kit.py (CLI), weapon_preview.py, weapon_index.json.
  Rebuild: .venv-tools/bin/python tools/blender/weapon_kit.py --jobs 3 (about 35 s), then tools/import.sh.
- assets/shaders/weapon_pbr.gdshader (texture arrays, object-space projection, edge wear from derivatives, part animation uniforms, dbg views); assets/models/weapons/ (229 glb + .import, 3 atlas png, weapons_meta.json).
- scripts/player/weapon_models.gd (path/build/mesh(id, lod)/material_for/hand_material/grip_offsets/muzzle_shift/stub_mesh), weapon_handling.gd (NEW: slide, bolt, pump, hammer, cylinder, rotor, coil pulse, magazine out/in keyed to the real reload).
- hooks (small): player_body.gd (own material copy, kit look scale 1.3/1.3/1.1, scaled grips, laser beam), player_weapon.gd (shell from the Eject marker, size by calibre), fx/casings.gd (size_k),
  roster/foe_arms.gd (LOD1 mesh + enemy scale), ui/weapon_preview.gd + tools/icons/icon_maker.gd (ONE line each: material_for; weapons-ui builder's area).
- tests: tests/test_weapon_models_v3.gd (NEW, 3850 checks, 30 s, real scene), tests/weapon_lineup.gd/.tscn + tools/weapon_lineup.sh, tests/bot_weapon_art.gd (hero), tests/bot_weapon_foes.gd (enemies).
- honest test updates: test_weapons_available_display (size bound 0.06 m, grips measured on the drawn scale), test_combat_feel (same bounds), test_open_models (uses WeaponModels.stub_mesh).
- sheets (10 jpg, q80): docs/shots/round6/weapon_kit_{lineup_0..5,before_after,in_hand,enemies,enemies_game}.jpg.

NUMBERS
- triangles: LOD0 min 256 / avg 1872 / max 4344 (budget 4500), LOD1 min 60 / avg 636 / max 2018; 0.90 vertices per triangle (28 B per vertex).
- size: glb 18.97 MB raw (avg 84.8 KB, 5.5 MB gzip), atlas png 2.13 MB, meta 86 KB, .import 238 KB, shader 6.6 KB -> repo weight about 21.4 MB raw / 7.6 MB compressed (limit 30 MB, 20 planned).
- APK effect: imported weapon scenes 5.73 MB + ETC2 texture arrays 1.05 MB (the S3TC copies are desktop only) = about 6.8 MB before deflate (about 6.6 MB after), no new audio, no other assets.
- texture memory: the 3 arrays (32 layers each, 128 px, ETC2 with mips) are about 1.05 MB of VRAM in total; perf tex_mb LOW 110 / MED 141 / HIGH 206 (limits 200 / 260 / 360), the kit adds +1 MB.
- perf gate (run twice; the second run is the final): LOW OK (draws 72, total 88, 134k tris, tex 110, death spike 101), MED OK (96 / 122, 270k, 141, 143), HIGH OK (112 / 142, 376k, 206, 164).
  The first run (middle of the wave) had MED 151 > 150 and HIGH 172 > 170 on the 4-enemy death spike; an A/B with QT_WEAPON_KIT=0 gave the same 151, so that was other builders' changes, gone in the second run.
  The kit itself: +0 draws (one material, one draw per weapon), about +620 triangles in the street scene.

TESTS PASS after the last change: test_weapon_models_v3 (3850), test_weapons_available_display (2212), test_combat_feel (68), test_open_models (670), test_enemy_look_v3 (95), test_ui_kit_screens (190),
test_hero_look2 (24), test_hero_polish (18).

DECISIONS OTHER AGENTS DEPEND ON
- WeaponModels.build(id, lod) -> Node3D "Weapon_<id>" with MeshInstance3D "Body" + Marker3D Muzzle GripR GripL Eject Aim Mag (Optic, Laser when present); origin = FRONT tip, barrel to -Z, +Y up.
- Anything that shows a weapon mesh uses WeaponModels.material_for(id) (shared PBR ShaderMaterial); enemies use LOD1 through FoeArms.pieces; QT_WEAPON_KIT=0 forces the old stubs (A/B and fallback).
- To change a weapon: edit its row in weapon_specs.py, run the kit with --ids, run tools/import.sh. Wear and colour come from the faction palette (wparts.py).

OPEN PROBLEMS (honest)
- LOD0 averages 1.9k triangles, not 3-4k: the 30 MB weight limit and the 128 px swatches were the trade. Detail is in the parts, not in the triangle count.
- The over-the-shoulder camera sees the hero's weapon mostly end-on from behind (stock and receiver): the models are good from the side (lineups) but not in the real frame; needs a camera or hero scope item.
- Weakest looks: ceramic / quantum energy shells (pale), magnum chrome, s_gale, bows are thin from the side; wood reads orange-tan in bright light; 21 same-family silhouette pairs have IoU > 0.9 (different details, near the same outline).
- Not done: scope reticle and lens look, a falling magazine (the magazine collapses into the receiver on reload), heat shimmer, class-specific muzzle flash shapes (the existing QuantumVfx flashes are used), a one-hand pistol grip mode of the rig.
- Enemy weapons read small at 5 to 13 m in the real camera (see weapon_kit_enemies_game.jpg); the close views are in weapon_kit_enemies.jpg (look-dev viewer).
