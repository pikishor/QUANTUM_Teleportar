# Third-party assets

All scanned materials are CC0 (no attribution required, listed for provenance). The real sets in use (Poly Haven, wave 99) are in the section 'Scanned world materials and sky probes' at the end; the rows below are the older, unused per-kind placeholder slots.

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

## Scanned world materials and sky probes (wave 99)

All CC0 1.0 (Poly Haven, https://polyhaven.com; licence text and per-asset author and URL in art_sources/polyhaven_pbr/). Packed by godot/tools/materials/pack_world_materials.py (1024 px WebP, slot format of the city shaders) and pack_sky_probes.py (256 x 128 probes).

| Surface (use) | Poly Haven set | Author |
|---|---|---|
| road market (city) | clean_asphalt (Clean Asphalt) | Dimitrios Savva |
| road foundry (city) | asphalt_pit_lane (Asphalt Pit Lane) | Dimitrios Savva |
| road slums (city) | asphalt_02 (Asphalt 02) | Rob Tuytel |
| road towers (city) | worn_asphalt (Worn Asphalt) | Amal Kumar |
| walk market (city) | pavement_04 (Pavement 04) | Jan Burghardt |
| walk foundry (city) | metal_plate (Metal Plate) | Rob Tuytel |
| walk slums (city) | concrete_pavement_02 (Concrete Pavement 02) | Charlotte Baglioni |
| walk towers (city) | pavement_01 (Pavement 01) | Rob Tuytel |
| brick (city) | brick_wall_005 (Brick Wall 005) | Dario Barresi, Dimitrios Savva |
| wall (city) | dirty_concrete (Dirty Concrete) | Rob Tuytel |
| metal (city) | metal_plate_02 (Metal Plate 02) | Rob Tuytel |
| corr (city) | corrugated_iron (Corrugated Iron) | Jenelle van Heerden, Dimitrios Savva |
| i plaster (interior) | white_plaster_02 (White Plaster 02) | Rob Tuytel |
| i brick (interior) | brick_wall_02 (Brick Wall 02) | Dimitrios Savva |
| i tile (interior) | floor_tiles_02 (Floor Tiles 02) | Rob Tuytel |
| i check (interior) | floor_tiles_06 (Floor Tiles 06) | Rob Tuytel |
| i concrete (interior) | concrete_floor_worn_001 (Concrete Floor Worn 001) | Dimitrios Savva, Rico Cilliers |
| i wood (interior) | wood_floor_worn (Wood Floor Worn) | Dimitrios Savva |
| sky probe dusk | sunset_jhbcentral (Joburg Central Sunset) | Greg Zaal, Dimitrios Savva |
| sky probe night | cobblestone_street_night (Cobblestone Street Night) | Greg Zaal, Jenelle van Heerden |
| sky probe overcast | potsdamer_platz (Potsdamer Platz) | Greg Zaal |

## Audio (round 4: real recordings, all CC0)

The weapon shots, impacts, explosions, footsteps, vehicle sounds, UI cues and ambience beds are built from CC0 recordings fetched from OpenGameArt.org (pages checked for the licence CC0). The full table
(every sample: file, source URL, author, licence, and the game sounds it feeds) is docs/AUDIO_SOURCES.md; each pack keeps its licence text and SOURCE.md in art_sources/audio_<group>/.
Credit is not required by CC0 and is given anyway:

| Pack | Author | Used for |
|---|---|---|
| The Free Firearm Sound Library (Prepared SFX Library) | The Free Firearm Sound Library team, uploaded by Ylmir | all gun shots (AR-15, AK-47, SKS, Savage, 1911, Walther PPQ, Bersa, S&W 642, Ruger Single Six, Marlin 336, Mossberg, Nova, Model 12, PPSh-41, Carl Gustav M45, Mosin, Springfield) and the distant fire |
| Sci-Fi Sounds, Interface Sounds | Kenney (kenney.nl) | pulse-weapon lasers, force fields, crunch explosions, UI cues |
| 50 / 60 CC0 Sci-Fi SFX, Explosion, Laser weapon burst fire | number99 | pulse-weapon layers, explosions, terminal beeps |
| 100 CC0 SFX, 100 CC0 SFX #2 | aijikl, geekygnome | glass, metal, stone hits, footsteps, highway |
| 75 CC0 breaking / falling / hit sfx | frances | crashes, impacts, glass |
| Impact, Punch, Swishes, Different steps, racing car engine loops, Sci-Fi Vehicle Sound | qubodup | flesh / stone / metal impacts, swishes, steps, engine loops |
| Fantozzi's Footsteps, Metal footsteps on concrete, Footsteps (subway) | Fantozzi, anonymous | footsteps per surface |
| Gunshots, Gunshot Sounds, Hollywood-style pistol silencer | LarkPay, Raassh, bart | black-powder boom, suppressed shot |
| Gun reload sounds, Gun Reload Sound Effects, 2 Gun Reloads, Equipment Clicks II | Joaken, Brian MacIntosh, starninjas, anonymous | reloads, dry fire |
| Chunky Explosion, Muffled Distant Explosion, Explosion somewhere far, 25 CC0 bang / firework SFX | looneybits, NenadSimic, ripple182, Snabisch | explosions and distant booms |
| Metal Impact Sounds, Crash Collision, Glass Break, Car engine start, Car Sound Effects Pack, Car_door_SFX | Brian MacIntosh, Luca Pixel, MedicineStorm, anonymous | metal hits, crashes, engine start, horn, door |
| 51 UI sound effects | gopherapps | UI cues |
| Rain (loopable), High traffic road sounds, Scifi City Ambient Loop, windy ambient noise | Snabisch, 2DPIXX, anonymous | ambience beds |

## Open-source vehicles and guns (round 4)

All CC0 1.0. Fetched from OpenGameArt.org (the authors' own sites are not reachable from the build sandbox). Licence text and URLs are kept with the packs in art_sources/.

| Asset | Author | Source | Use |
|---|---|---|---|
| Kenney Car Kit 3.1 (14 vehicles: sedan, sedan-sports, hatchback-sports, suv, suv-luxury, taxi, police, ambulance, van, delivery, truck, firetruck, garbage-truck, race) | Kenney, www.kenney.nl | https://opengameart.org/content/car-kit, art_sources/kenney_car_kit | godot/tools/open_models/convert_vehicles.py -> assets/models/ov_*.glb: stretched to realistic proportions, colour-map baked into vertex colours (no texture), paint / details / lamp surfaces, wheels as separate nodes, LOD1; VehicleSpecs key `ov` |
| Ultimate Gun Pack (19 guns used) | Quaternius | https://opengameart.org/content/low-poly-guns-pack, art_sources/open_weapons | godot/tools/open_models/convert_weapons.py -> assets/models/ow_*.glb (pistol, burst, revolver, akimbo, flux, carbine, marksman, arc, scatter, breacher, rail; round 4 part 2: swarm, vector, battle, sawn, auto, bolt, dmr, knife), WeaponModels |
| RPG-7 (Low Poly Weapon Pack) | byzmod3d | https://opengameart.org/content/low-poly-weapon-pack | the `rocket` launcher model (ow_rocket.glb) |
| Kenney Furniture Kit 1.0 (38 pieces: sofas, armchairs, tables, chairs, stools, beds, bookcases, kitchen units, fridge, sink, TVs, monitors, lamps, rugs, plants, boxes, bathroom pieces) | Kenney, www.kenney.nl | https://opengameart.org/content/furniture-kit (CC0), art_sources/kenney_furniture_kit (licence and SOURCE.md only, the 5.6 MB archive is not committed) | godot/tools/open_models/convert_furniture.py -> assets/models/furn_<piece>.glb (0.9 MB, flat-colour vertex data, 0.2 m per kit unit, no textures); drawn by godot/scripts/interiors/interior_furniture.gd into the interiors' merged surface mesh (no draw call) |
