# assets_incoming

Drop CC0 PBR sets here, one folder per set, name containing the kind: `asphalt`, `concrete`, `metal`, `brick` or `tile`
(e.g. `Asphalt012/`, `Bricks075A` is not matched: rename to `brick_075`). Each folder needs ambientCG / Poly Haven files:
`*_Color`, `*_NormalGL`, `*_Roughness`, `*_AmbientOcclusion`, optional `*_Displacement`.

Then from `godot/`: `python3 tools/materials/import_scanned.py --size 2048` (or 1024). Output goes to `assets/textures/scanned_<kind>_{albedo,normal,orm}[_half].png`
(ORM: R=AO, G=roughness, B=metal). Godot imports them; LOW tier uses the `_half` files. With nothing dropped here the game keeps its procedural surfaces.
Add every set you use to `docs/THIRD_PARTY.md`.

## Characters (rigged glb / fbx)
Drop one rigged file per role under `assets_incoming/characters/<role>/`: `hero`, `enemy_<kind>` (e.g. `enemy_trooper`), `citizen_<kind>`.
`CharacterImport.instantiate(role)` (`scripts/characters/character_import.gd`) uses the first `.glb` / `.gltf` / imported `.fbx` it finds and falls back to the procedural model (`player`, `operative`, `citizen`) when the folder is empty or the rig cannot be mapped.
- **Retarget**: bones are renamed to the CharacterRig contract (Hips Torso Head UpperArmL/R ForeArmL/R ThighL/R ShinL/R FootL/R, plus a Rifle bone under the right hand) by name mapping. Recognised: Mixamo (`mixamorig:LeftUpLeg`), Quaternius / Unreal style (`UpperArm.L`, `thigh_l`, `calf_r`), Rigify (`DEF-upper_arm.L`, `DEF-spine.003`). Clips are renamed by keyword to `idle walk run aim fire hit death jump`; their bone tracks follow the renamed bones. The game still poses the character procedurally (CharacterRig / Locomotion); the clips are kept for tools.
- **Look**: one `character_quantum.gdshader` surface: your albedo, a role palette tint (hero cyan, enemy magenta, citizen grey-blue), iridescent thin-film trim on the rim, faint phase seam, rare flicker.
- **Budget**: hero 18000, enemy 12000, citizen 4000 triangles, at most 4 surfaces; over budget the mesh is rebuilt on the largest auto-LOD that fits and LODs are generated. Scaled to 1.8 m, turned to face -Z.
- **Offline (recommended for fbx and heavy meshes)**: `$BLENDER_PY tools/blender/import_character.py assets_incoming/characters/hero/Hero.fbx --role hero` writes `Hero_prepped.glb` with the same renames, zeroed bone rolls (CharacterRig expects model-aligned bone frames) and a hard decimation.
- Needs a `tools/import.sh` run after dropping files. Add every asset to `docs/THIRD_PARTY.md`. Test: `tools/test.sh tests/test_character_import.gd`.

## Superhero (hero, Quaternius Universal Base Characters)
`assets_incoming/characters/hero/` holds the male and female superhero kit (prepared from `art_sources/quaternius_universal_base_characters` by `python3 -I tools/hero/prep_hero_assets.py`, run from `godot/`). `HeroCharacter.build(opts)` (`scripts/characters/hero_character.gd`, also reached by `CharacterImport.instantiate("hero")`) is its builder, PlayerBody uses it when the files are imported and keeps the old procedural / skinned hero otherwise. Look-dev: `tools/hero/view.sh /tmp/prefix views=front,side,back,head body=female skin=light hair=long beard=0 pose=idle` (plain floor, seconds) and `tools/bot.sh res://tests/bot_superhero.gd /tmp/sh 45 12` (the real city: game camera at MED and LOW, sprint, fire, variants, the look screen). Test: `tools/test.sh tests/test_superhero_hero.gd`.
