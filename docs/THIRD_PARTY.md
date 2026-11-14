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
| Ultimate Monsters (eleven rigs for the alien wildlife and camps: Alien, BlueDemon, Yeti, Ninja, Dino, MushroomKing, GreenBlob, Armabee, Dragon_Evolved, Goleling_Evolved, Squidle) | Quaternius, quaternius.com (owner-supplied zip, art_sources/quaternius_ultimate_monsters, licence text in License.txt there) | CC0 1.0 (no attribution required, credited anyway) | Wave 107b alien creatures (godot/assets/models/aliens/*.scn): `tools/open_models/convert_monsters.sh` merges each rig into one surface, bakes the atlas colour into vertex colours (re-graded to the alien palette, eyes and teeth become the glow mask), simplifies with Godot's meshoptimizer LODs and keeps the Idle / Walk / Run / attack / hit / Death clips; no texture is shipped |
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
| 40 CC0 water / splash / slime SFX; Beach Ocean Waves | OpenGameArt uploaders (the first pack as listed on its page); qubodup (upload) of the 'alkaibeach' recording by jasinski | water splashes, wading, swim strokes, bubble, river loop, surf loop (art_sources/audio_water, CC0 1.0) |

## Music (MIDI + SoundFont)

The music is composed in code (godot/tools/music/compose.py, original) and rendered with the **FluidR3 GM SoundFont by Frank Wen (MIT licence)** through FluidSynth (a build tool only). Licence text and SOURCE.md: art_sources/soundfont_fluidr3_gm/. Details and numbers: docs/AUDIO_SOURCES.md ("Music"). The 148 MB SoundFont is not in the repository.

## Open-source vehicles and guns (round 4)

All CC0 1.0. Fetched from OpenGameArt.org (the authors' own sites are not reachable from the build sandbox). Licence text and URLs are kept with the packs in art_sources/.

| Asset | Author | Source | Use |
|---|---|---|---|
| Kenney Car Kit 3.1 (14 vehicles: sedan, sedan-sports, hatchback-sports, suv, suv-luxury, taxi, police, ambulance, van, delivery, truck, firetruck, garbage-truck, race) | Kenney, www.kenney.nl | https://opengameart.org/content/car-kit, art_sources/kenney_car_kit | godot/tools/open_models/convert_vehicles.py -> assets/models/ov_*.glb: stretched to realistic proportions, colour-map baked into vertex colours (no texture), paint / details / lamp surfaces, wheels as separate nodes, LOD1; VehicleSpecs key `ov` |
| Ultimate Gun Pack (19 guns used) | Quaternius | https://opengameart.org/content/low-poly-guns-pack, art_sources/open_weapons | godot/tools/open_models/convert_weapons.py -> assets/models/ow_*.glb (pistol, burst, revolver, akimbo, flux, carbine, marksman, arc, scatter, breacher, rail; round 4 part 2: swarm, vector, battle, sawn, auto, bolt, dmr, knife; roster round: magnum = Pistol_5, mpistol = SubmachineGun_2, ranger = AssaultRifle2_2, bullpup = Bullpup_2, lmg = Bullpup_3 plus a procedural bipod and magazine, amr = SniperRifle_5 plus a procedural bipod and brake), WeaponModels. The crossbow, flamethrower, stun gun, katana, bat and the six quantum weapons are procedural (weapon_models.gd), the roster sounds are rebuilt from clips already credited in docs/AUDIO_SOURCES.md (tools/audio/make_real.py build_roster) |
| RPG-7 (Low Poly Weapon Pack) | byzmod3d | https://opengameart.org/content/low-poly-weapon-pack | the `rocket` launcher model (ow_rocket.glb) |
| Kenney Furniture Kit 1.0 (38 pieces: sofas, armchairs, tables, chairs, stools, beds, bookcases, kitchen units, fridge, sink, TVs, monitors, lamps, rugs, plants, boxes, bathroom pieces) | Kenney, www.kenney.nl | https://opengameart.org/content/furniture-kit (CC0), art_sources/kenney_furniture_kit (licence and SOURCE.md only, the 5.6 MB archive is not committed) | godot/tools/open_models/convert_furniture.py -> assets/models/furn_<piece>.glb (0.9 MB, flat-colour vertex data, 0.2 m per kit unit, no textures); drawn by godot/scripts/interiors/interior_furniture.gd into the interiors' merged surface mesh (no draw call) |
| Universal Animation Library (Standard, 45 clips) and Universal Animation Library 2 (Standard, 43 clips) | Quaternius, quaternius.com | https://opengameart.org/content/universal-animation-library and https://opengameart.org/content/universal-animation-library-2 (CC0; licence texts and SOURCE.md in art_sources/quaternius_universal_animation_library, the 24 MB zips are not committed) | CC0 1.0 (no attribution required, credited anyway) | The hero's captured locomotion: 14 clips (idle, pistol-ready idle, walk, jog, sprint, crouch idle / walk, jump start / loop / land, aim up / neutral / down, walk carry) retargeted onto the hero skeleton by godot/tools/hero/build_clips.py + bake_clips.gd (`tools/hero/clips.sh`) into godot/assets/anim/hero_clips.res (115 KB), played by godot/scripts/characters/hero_clips.gd |
| Free Low Poly Vehicles Pack (13 vehicles used: Sedan, Sports, Hatchback, SUV, Taxi, Van, Limousine, Roadster, Police Sedan, Ambulance, Bus, Muscle, Pickup; the sedan is also decimated into the near-traffic car) | Raphael Goncalves (Rgsdev) | https://opengameart.org/content/free-low-poly-vehicles-pack (CC0; licence and SOURCE.md in art_sources/rgsdev_vehicles, the FBX files are not committed) | godot/tools/open_models/convert_rgs_vehicles.py -> assets/models/rv_<id>.glb (1.2 MB: scaled to the spec length, width slimmed, wheels pushed out to the flank, nose to -Z, paint / trim / glass / lamp surfaces, flat colours and no textures); VehicleSpecs key `rv`; `car_parts.gd` adds the generated wheels, plates, glass and beams |

## Vehicle roster: helicopter, plane, boat, tank (round 5)

All CC0 1.0, fetched from OpenGameArt.org with plain curl and a descriptive user agent. The CC0 statement of each page, the URL and the author are kept in art_sources/open_craft/<pack>/ (LICENSE.txt + SOURCE.md); the source files are not committed. godot/tools/open_models/convert_craft.py (bpy) turns them into godot/assets/models/xv_<id>.glb: nose to -Z, the paint surface named Body, animated parts as their own nodes (Rotor, TailRotor, Prop, Turret), every texture sampled per face into flat colours (no texture memory, 0.2 MB in all).

| Asset | Author | Source | Use |
|---|---|---|---|
| Half-finished Chopper | Ouren | https://opengameart.org/content/half-finished-chopper, art_sources/open_craft/chopper | `heli` (xv_heli.glb) |
| Light Aircraft | weirdybeardyman | https://opengameart.org/content/light-aircraft, art_sources/open_craft/light_aircraft | `plane` (xv_plane.glb) |
| Heavy Tank [extra low poly, RTS] | 32kda | https://opengameart.org/content/heavy-tankextra-low-poly-rts, art_sources/open_craft/heavy_tank | `tank` (xv_tank.glb) |
| Watercraft Kit (boat-speed-a) | Kenney, www.kenney.nl | https://opengameart.org/content/watercraft-kit, art_sources/open_craft/kenney_watercraft | `boat` (xv_boat.glb) |

The quad, the scooter and the armour plates of the armoured truck are procedural (godot/scripts/vehicles/vehicle_craft_models.gd); the armoured truck's body is the Rgsdev van already credited above. Candidates judged on renders and rejected: the other OpenGameArt helicopters (blobs and toy RC models), the Abrams tank (44k triangles), the patrol boat (5k triangles at a toy scale).

## Terrain world textures (round 5, terrain foundation)

All CC0 1.0 (Poly Haven, https://polyhaven.com; licence text and per-asset URL in art_sources/polyhaven_terrain/). Diffuse maps only (1K JPG) packed by godot/tools/materials/pack_terrain_textures.py into godot/assets/textures/terrain_<layer>.webp (1024 px, lossy WebP, VRAM compressed with mipmaps) and read as ONE Texture2DArray by godot/assets/shaders/terrain.gdshader (scripts/terrain/terrain_textures.gd). ambientCG was tried first: its API answers but the download host is refused by the session network policy, so Poly Haven is used instead.

| Terrain layer (use) | Poly Haven set | Author |
|---|---|---|
| grass (meadows, plains) | forrest_ground_01 (Forest Ground 01) | Rob Tuytel |
| forest (forest floor, hills) | rocky_terrain_02 (Rocky Terrain 02) | Amal Kumar |
| desert (dry plains, dunes) | dry_ground_rocks (Dry Ground Rocks) | Rob Tuytel |
| beach (dry shore sand; wave 112) | coast_sand_02 (Coast Sand 02) | Rob Tuytel |
| rock (cliffs, high ground; tri-planar) | rock_boulder_dry (Rock Boulder Dry) | Dimitrios Savva, Rico Cilliers |
| snow (peaks, ledges) | snow_02 (Snow 02) | Rob Tuytel |
| dirt (road verge, track surface; wave 112) | forest_ground_04 (Forest Ground 04) | Rob Tuytel |
| wetsand, strata, scree, darkrock (wave 112: the swash zone, orange cliffs, loose stones, dark ridges) | damp_beach_sand, cliff_side, rocks_ground_01, rock_face_04 | Poly Haven artists (see art_sources/polyhaven_terrain/SOURCE.md) |

## Landscape dressing (round 6, wave 112: trees, rocks, ground cover, waterfalls, airstrips, tall anchors)

All geometry is our own (procedural, fixed seeds: `godot/tools/landscape/*.py`): nine tree species with three levels of detail and impostors (`assets/models/land_trees.glb`, foliage atlas `land_foliage.webp`, impostors `land_impostor.webp`), rocks, pebbles, driftwood, rock arches, wind turbines, pylons, radio masts, cranes, hangar, windsock (`assets/models/land_props.glb`). The bark of the seven real species is CC0 1.0 from Poly Haven (https://polyhaven.com; licence text and per-asset URL in art_sources/polyhaven_land/): oak bark_brown_01, pine pine_bark, fir chinese_cedar_bark, birch tree_bark_03 (painted over), poplar / dead / driftwood bark_brown_02, palm palm_tree_bark, acacia bark_willow; packed by `godot/tools/landscape/pack_bark.py` into `assets/textures/land_bark_<species>.webp` (512 px). Raw downloads stay in the git-ignored `godot/assets_incoming/land_raw/`.

## Vegetation of the outskirts (wave 105, mountain sites and vegetation)

CC0 1.0, fetched from OpenGameArt.org with plain curl and a descriptive user agent. The licence text, the URL and the author are kept in art_sources/quaternius_stylized_nature_megakit/ (License.txt + SOURCE.md); the 104 MB archive is not committed.

| Asset | Author | Source | Use |
|---|---|---|---|
| Stylized Nature MegaKit (Standard, free version): pines, broadleaf and dead trees, bush, fern, grass, rocks, pebble and the leaf sprite sheets | Quaternius, quaternius.com | https://opengameart.org/content/stylized-nature-megakit (CC0), art_sources/quaternius_stylized_nature_megakit | godot/tools/open_models/convert_nature.py (bpy) -> godot/assets/models/nature_kit.glb (16 pieces, 6 500 triangles in all, 1.1 MB, flat vertex colours) and godot/assets/textures/nature_atlas.webp (1024 x 512 alpha atlas, 28 KB); drawn as MultiMesh instances by godot/scripts/terrain/vegetation_world.gd with assets/shaders/vegetation.gdshader (wind, snow, dissolve between LODs); the mid and far tree LODs are generated in code (veg_kit.gd) |

Everything else of that wave (the sites, the cave, the guard rails, the clouds) is procedural.

## Railways and ships (wave 106)
No third-party assets: every mesh is generated in code (`scripts/rail`, `scripts/ships`) and the eight sounds (train horn, maglev chime, wheel clatter, maglev hum, crossing bell, ship horn, ship engine, brake squeal) are synthesised by `godot/tools/audio/make_rail.py` (numpy, ffmpeg); nothing to credit.

## Airport and aircraft (wave 106)
Four CC0 1.0 aircraft from OpenGameArt.org (plain curl, descriptive user agent). The CC0 statement of each page, the URL and the author are kept in art_sources/open_aircraft/<pack>/ (LICENSE.txt + SOURCE.md); the raw .blend files are not committed. godot/tools/open_models/convert_aircraft.py (bpy) turns them into godot/assets/models/xv_<id>.glb (nose to -Z, the paint surface named Body, no texture: colours sampled from the materials, 0.55 MB in all; the airliner and the business jet keep the landing gear of the source's gear-down variant, the cargo plane and the fighter get a simple gear added by the converter).

| Asset | Author | Source | Use |
|---|---|---|---|
| Jet airplane | weirdybeardyman (uploaded by MedicineStorm) | https://opengameart.org/content/jet-airplane, art_sources/open_aircraft/jet_airplane | AIRLINER, scenery at the gates and in the AI air traffic (xv_airliner.glb) |
| Private Jet | weirdybeardyman | https://opengameart.org/content/private-jet, art_sources/open_aircraft/private_jet | BUSINESS JET, scenery and AI air traffic (xv_bizjet.glb) |
| Jumbo Jet, Wide Body | NuclearOsmosis | https://opengameart.org/content/jumbo-jetwide-body, art_sources/open_aircraft/jumbo_jet | CARGO PLANE, flyable (xv_cargo.glb) |
| Mig | Sketlux | https://opengameart.org/content/mig, art_sources/open_aircraft/mig | JET FIGHTER, flyable (xv_jet.glb) |

The attack helicopter (GUNSHIP), the transport helicopter (HAULER), the airport (runway, terminal, tower, hangars, tanks, pads) and all the airport markings are procedural (godot/scripts/world/airport_kit.gd, godot/scripts/vehicles/aircraft_models.gd). Candidates judged and rejected: the other OpenGameArt helicopters (box and toy models), "Black Bird / Warthog" (a 10k-triangle hand model with 42 loose parts).

## Wildlife (wave 107)
| Asset | Author | Source | Use |
|---|---|---|---|
| Farm Animals Pack (Horse, Cow, Sheep, Llama, Pig, Zebra) | Quaternius | https://opengameart.org/content/lowpoly-animated-farm-animal-pack (CC0), art_sources/open_animals | deer, goat, boar, sheep, cow, horse, zebra (godot/assets/models/animals/*.scn via godot/tools/open_models/convert_animals.sh) |
| Animals Pack (Bird, Fish, Whale, Red Fox) | Quaternius | https://opengameart.org/content/5-low-poly-animals (CC0) | songbird, seagull, eagle, fish, shark, dolphin, whale, fox |
| Animal Pack Vol.2 (Wolf) | Quaternius | https://opengameart.org/content/animated-animales-low-poly (CC0) | wolf, coyote |
| Wolf monster sound | OpenGameArt uploader | https://opengameart.org/content/wolf-monster-sound (CC0) | animal_wolf, animal_coyote (pitched) |
| Solo Seagull Sound Effects | OpenGameArt uploader | https://opengameart.org/content/solo-seagull-sound-effects (CC0) | animal_gull |
| Sheep baa | OpenGameArt uploader | https://opengameart.org/content/sheep-baa (CC0) | animal_sheep, animal_goat (pitched) |
| Ambient bird sounds, Forest bird sounds, Bird chirping sounds | OpenGameArt uploaders | https://opengameart.org/content/ambient-bird-sounds , /forest-bird-sounds , /bird-chirping-sounds (CC0) | animal_bird |
| qubodup sci-fi cow alien soundpack | qubodup | https://opengameart.org/content/sci-fi-aliens-and-cows-pack (CC0) | animal_cow, animal_horse (pitched) |

Eagle cry, dolphin chirps and snorts are synthesized (godot/tools/audio/make_animals.py). Licence texts and URLs: art_sources/open_animals/, art_sources/audio_animals/.

## Energy and destructive weapons, grenades, gadgets, tanks (wave 108)
No new third-party asset. The 15 weapon models, the 5 gear models and the 4 tank bodies are procedural (`WeaponModelsEnergy`, `Gadgets.mesh_of`, `Throwables.mesh_of`, `VehicleCraftModels.build_tank`); the 42 new sounds are rebuilt from clips already credited in docs/AUDIO_SOURCES.md (`tools/audio/make_real.py build_energy`: Kenney sci-fi and interface sounds, field-recorded firearms, explosion and impact singles, swishes, all CC0); the battle tank keeps its CC0 open model (art_sources/open_craft). Weapon names are original (no trademarked names).


## Cars v2 (round 6 ART)
`assets/models/cv2_*.glb`, `assets/textures/carv2_*.png` and the `car_*` shaders are generated by `godot/tools/blender/carv2/` and `godot/tools/materials/make_carv2_textures.py` from numbers and noise: no third-party art, no licence to carry. Blender (bpy) is used as a tool only (GPL / LGPL tool, its output is ours). The older CC0 car models (Rgsdev pack, `rv_*` / `ov_*`) stay in the repository as the fallback of `QT_CARS_V2=0` and keep their entries above.

## Enemy roster look v3 (round 6, wave 113)
No new third-party asset. The Quaternius Universal Base Characters kit (CC0, the hero's body, credited above) is reused as the body of the 13 armoured human enemy looks; the armour kit (`godot/assets/models/enemy_kit.glb`) and the nine alien and walker bodies (`godot/assets/models/foes/*.glb`) are our own Blender builds from numbers (`godot/tools/blender/enemykit`, `godot/tools/blender/creaturekit`, run with bpy as a tool only: its output is ours); the weapons in their hands are the weapon registry's models (open-source weapon packs credited above). `FoeKit`, `FoeArms`, `FoeHuman` and `foe_body.gdshader` merge them into one skinned surface per enemy, no texture is shipped. The floating health pips and threat markers (`foe_pips.gdshader`) are drawn from numbers too.
