# Third-party assets

All scanned materials are CC0 (no attribution required, listed for provenance).

| Surface kind | Set name | Source | URL | License |
|---|---|---|---|---|
| asphalt | (none yet) | ambientCG / Poly Haven | | CC0 |
| concrete | (none yet) | | | CC0 |
| metal | (none yet) | | | CC0 |
| brick | (none yet) | | | CC0 |
| tile | (none yet) | | | CC0 |

## Models

| Asset | Source | License | Use |
|---|---|---|---|
| Ultimate Modular Sci-Fi (Feb 2021) | Quaternius, quaternius.com (owner-supplied zip, art_sources/quaternius_modular_scifi) | CC0 1.0 (no attribution required, credited anyway) | Interior kit: 16 props (teleporter pads and pods, servers, consoles, capsules, crates, containers, shelves, laser rig, column, base, pipes) converted by godot/tools/blender/model_kit.py to godot/assets/models/kit_*.glb (merged, decimated, one shared vertex-colour material) |
| Downtown City MegaKit (free Standard version, partial) | Quaternius, quaternius.com (owner-supplied zips, art_sources/quaternius_downtown_city_megakit) | CC0 1.0 (no attribution required, credited anyway) | City kit: 10 facade, rooftop and street pieces (metal and brick cornices, pilaster, window frame, AC unit, bollard, planter, drain, manhole) converted by godot/tools/blender/model_kit_city.py to godot/assets/models/kit_city_*.glb (flattened to vertex colours, decimated); 6 road markings (arrows, zebra, dashed and double lines) redrawn as flat vector shapes sized from the kit's decals (its textures are not in the free kit); all merged into the street-kit mesh by godot/scripts/world/city_kit_world.gd. Wave 62 city variety: 9 more flat-colour pieces (kit_city_column, column_small, stoop, stoop_flat, shopwall, slate_cap, slate_roof, trim_brick, trim_half; from Metal_Column_Center, Metal_Column_Small_Center, Stairs_Entrance_Concrete, Entrance_Concrete_2x1, Metal_FirstFloor_Wall, Roof_SlateCornice_Center, Roof_Slate_Center, Brick_TopTrim, Brick_HalfTrim) written by godot/tools/city_kit_extra.py (no Blender), used with the existing cornice_trim by godot/scripts/world/city_kit_dress.gd |
| Ultimate Monsters (Alien, Demon, BlueDemon only) | Quaternius, quaternius.com (owner-supplied zip, art_sources/quaternius_ultimate_monsters) | CC0 1.0 (no attribution required, credited anyway) | Rigged enemy bodies of the stalker (Alien), brute (BlueDemon) and walker (Demon): the glTF files and Atlas_Monsters.png are copied to godot/assets_incoming/characters/enemy_{alien,bluedemon,demon}/ and run through CharacterImport (retarget, per-species quantum tint, enemy triangle budget) |
| Universal Base Characters Kit (free Standard version, partial) | Quaternius, quaternius.com (owner-supplied zips, art_sources/quaternius_universal_base_characters, licence text in godot/assets_incoming/characters/hero/License.txt) | CC0 1.0 (no attribution required, credited anyway) | The hero (male and female): Superhero_{Male,Female}_FullBody.glTF (65-bone UE-style skeleton), skin colour dark / light, roughness and the Godot (Y+) normal maps, hair / beard / eyebrow modules rigged to the Head bone, eye maps; copied (textures resized to 2048 / 1024 / 256 px) to godot/assets_incoming/characters/hero/ by godot/tools/hero/prep_hero_assets.py and built into one skinned mesh with the quantum-realism material by godot/scripts/characters/hero_character.gd |
| Ultimate Space Kit (flora, rocks, rovers, spaceship, bullets pickup) | Quaternius, quaternius.com (owner-supplied zip, art_sources/quaternius_ultimate_space_kit) | CC0 1.0 (no attribution required, credited anyway) | godot/tools/creature_kit.py bakes Tree_Swirl_1, Tree_Spiral_2, Tree_Light_1, Plant_1, Plant_3, Bush_2, Rock_2, Rock_4, Rock_Large_1 into assets/models/kit_flora.glb (plaza dressing inside the merged street-kit mesh), Rover_1 into car_rover.glb, Spaceship_FinnTheFrog into car_skiff.glb (two extra vehicle kinds), Pickup_Bullets into pickup_weapon.glb; decimated by vertex clustering, atlas colour desaturated into vertex colours |

Humanoid variants (wave 58): no new art. Vael troopers and near-LOD citizens reuse the Quaternius Universal Base Characters (Superhero Male/Female, CC0, art_sources/quaternius_universal_base_characters, godot/assets_incoming/characters/hero/) through HeroCharacter with skin, hair, suit and helmet/visor colour variants; the textures are shared with the hero (no extra texture memory).
