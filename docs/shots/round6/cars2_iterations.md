# Cars v2, second pass: render, look, fix loops (round 6, wave 112, independent critic)

Method: every loop renders frames at the phone resolution 2400x1080 (software Vulkan, MED and LOW, day and night, dry and wet) with `tools/carv2_lineup.sh`, `tools/vehicle_bot.sh` (BOT_SET=chase) and
`tests/bot_traffic.gd` (the real game camera, kerb cars at 4 - 10 m), OPENS them, writes the defects down, fixes, renders again. Before = the owner frames of `docs/owner_shots/round5` and the
renders of the wave 111 tree (146c20d); after = the final frames in `cars_before_after.jpg`.

Budgets at the start (perf gate, staged view): LOW 99 / 100 draws, 133k / 160k triangles, 144 / 200 MB, death spike 113 / 115; MED 134 / 140 draws, 276.6k / 280k triangles (3.4k left), 175 / 260 MB,
death 148 / 150; HIGH 155 / 160 draws, 384k / 430k, 236 / 360 MB, death 170 / 170 (nothing left).

## Baseline defects (fresh eyes, 22 found before any fix)
Near / kerb / road traffic (the one MultiMesh, `cv2_near.glb` + `prop_nearcar.gdshader`), seen at 4 - 40 m:
1. Folded-paper body: a 430 triangle mesh with a 22 degree crease threshold, hard facets on bonnet, roof and deck (LOW and MED, every car within 12 m).
2. Wheels are hexagonal drums with a pale lid: no tyre, no rim, the wheel arch is a black wedge that reads as a wing.
3. The rear and side glass is one flat black rectangle (raked glass is tagged as dark trim): no pillars, no cabin, a black box on the trunk.
4. Twelve kinds are one sedan scaled in the vertex shader: the van, truck, bus, delivery and ambulance have a sedan windscreen rake and a rounded roof; the pickup has no bed.
5. Pale ghost at MED: shared fog, a blue rim light and a flat `fill * 7.0` emission wash the paint out.
6. No lamp, grille, bumper or mirror detail; two emissive squares per end.
7. No contact shadow: the cars float on LOW (no shadows) and sit on nothing at MED.
8. The paint has no clear coat, no reflection of the wet street: flat plastic in the rain.
Real cars (`cv2_*.glb`, `car_*.gdshader`):
9. The player's car reads as emissive clay at night (paint glow floor 0.18 + key light), roofs and bonnets blow out to white in daylight (fresnel reflection of a bright sky).
10. The cabin seen through the glass is beige boxes and a doll driver, a mosaic from the rear three-quarter view.
11. LOD1 (26 - 64 m): the SUV's lower body is a black slab (cladding band too tall, arches removed), facets on bonnet and deck, flat grey glass, a visible pop against LOD0.
12. LOD2 (beyond 64 m, the shadow caster and the street reflection twin): facets, hexagonal wheels, an almost black SUV.
13. The hover car's windscreen is pure white at night (cabin glow plus reflection); the antennae and cables look toy-like.
14. Bus, box truck, van and armoured backs are flat slabs with one grey rectangle, plates floating on them, white squares for lamps.
15. Truck and bus wheels are plain steel discs.
16. Plates are two textured quads per car (two draw calls) with a pixel font.
17. A real car costs 10 draws (Paint, Details, Glass, 4 tyres, 2 plates, the mirror twin): the budget cannot afford more cars.
18. A coarse tyre mesh draws beyond 64 m on top of the baked wheels of LOD2: five draws for a far car.
19. LOW has no contact shadow under the starter car either (it sits on the road like a sticker).
20. Rain streak mesh crosses the paint as vertical lines (not this scope; reported).
21. The look-dev viewer hero could not be judged for "white rectangles on the legs" (the car hides them); not this scope.
22. A promoted taxi beside the camera fills a third of the frame (wave 111 integrator); lens clearance does not apply to a stopped car.

## Loops (render, open every picture, list, fix, render again)
Honest note on the record: this log was written from the tool history after the working context was compacted once; the defects and fixes are real and in order, the wording of the first loops is short.
The defect numbers continue the baseline list (1 - 22 above). Status of the baseline at the end: FIXED 1, 2, 3, 4, 7 (near cars; the real cars have their own blob), 8, 9, 10, 11, 12, 16, 17, 18, 22; PARTLY 5 (the pale ghost at MED is gone, the pastel read in heavy rain is not), 6 (lamps, grille, mirrors and plates are in the HI near car, no bumper detail), 13 (glass roughness and specular were lowered, the hover car's windscreen at night was not looked at again); NOT ADDRESSED 14 (the flat backs of the real bus, box truck, van and armoured car), 15 (truck and bus wheels use the same wheel kit), 19 (no contact shadow under a real car at LOW); NOT THIS SCOPE 20, 21.

### Loop 1: the first near cars (`tools/near_lineup.sh`, chase and side views, MED, day)
23. every near car was plain white (`step(kind, 5.5)` got an int, the whole kind table collapsed) -> `step(float(kind), 5.5)`;
24. vans, trucks, buses and ambulances wore the sedan's domed roof and raked glass in the side profile -> a second shell (the box family, flat roof ring, upright nose) chosen per kind in the vertex stage (mask 3464), anchors per kind in `prop_nearcar_tables.gdshaderinc`;
25. wheels floated at the wrong places and the two shells swapped for some kinds: Godot's importer un-flips the V of NEITHER uv set (dumped the imported arrays to see it) -> `near.py` writes both sets as 1 - V.

### Loop 2: real traffic at MED and the two families at three quarters, day and night
26. cars floated: nothing under the body between the wheels, no contact shadow at LOW -> dark under-body plates (1.52 x 3.9 m, 1.8 x 5.8 m for the box family);
27. near paint read pale at MED (ambient wash, street reflection too strong) -> ambient x 2.4 (was 6), albedo^1.12, reflection weight 0.5.

### Loop 3: wheels and plates into the Details surface (draw budget)
28. a real car cost 10 draws (Paint, Details, Glass, four tyres, two plates, the mirror twin) -> the four wheels and both plates are vertices of the Details surface (shader-rolled, steered and shed): 3 draws;
29. plates were two textured quads with a pixel font -> glyphs drawn by the Details shader from `plate_seed` (QT and five digits).

### Loop 4: the starter car from the chase camera at MED, plates close up
30. roofs and bonnets blew out to white by day, the paint read as emissive clay at night -> `PAINT_GLOW` 0.2 -> 0.12 (LOW 0.26 -> 0.18), `KEY_ENERGY` 2.6 -> 2.2, metal reflection scaled by (1 - 0.6 rough), a bright paint reflects 38 percent less, lighter shoulder and darker sill, glass roughness 0.04 -> 0.12 and specular 1 -> 0.8;
31. plates came out solid blue and tread bands flat: `kit.finalize` overwrote the uv2.x of every face with part / 32 -> only for faces of a part other than 0.

### Loop 5: the cabin through the glass
32. a doll driver and beige boxes, a mosaic from the rear three quarter view -> bolstered seats with head rests, a driver with hair, neck, shoulders and belt, dash binnacle, cluster, vents, arm rests, steering spokes, darker colours.

### Loop 6: LOD1 and LOD2 of six kinds
33. the SUV's lower body was a black slab at LOD1 (the cladding band is 3 slots at LOD0, 1 - 2 wall slots there) -> `trim_slot` at most 1 at LOD1 and 0 beyond;
34. LOD1 glass was flat grey (nothing behind it) -> a dark liner behind the glass at LOD1;
35. LOD2 wheels were hexagonal drums -> 12 sides at LOD1 and 8 at LOD2.

### Loop 7: detail of the near cars and the lens
36. the side glass of a near car was a black rectangle with nothing behind it -> head rest silhouettes;
37. no door seams or handles -> seams and handles in the base coordinates of the shell, first one pixel wide, then at least two pixels at any distance;
38. a taxi crawling beside the camera filled a third of the frame (defect 22) -> `VehicleManager.LENS_CLEAR` 4.6 m and the gate is 2.5 m/s (was 3.4 m, standing only).

### Found by the audits and the tests (not by looking)
- a real car or a police car could sit inside kerb cars (they were scenery to a creeping car) -> `ParkedCars.promote_touching` at any speed, `push_out_vehicle` as the fallback (city audit seed 11, highway seed 23: PASS);
- two bridge scenery cars stuck inside each other for a minute -> `BridgeTraffic._overlap_t` sends the car back to the start of the deck after 0.8 s;
- the crash code reached the damage states only through speeds I had guessed: `test_cars_v2` now derives them from `Vehicle.crash_fraction` and checks dents, cracked glass, torn parts, a lost wheel and fire after real car-to-car crashes.

### Loop 8: self-review with fresh eyes at the phone resolution (LOW night, MED day, both sides of a car)
39. THE BIG ONE: on the LEFT side of every car the doors were black glass at LOD1, LOD2 and in both near meshes (half the cars of every street frame showed a black slab from the sill to the roof; I had looked at one side in loops 6 and 7). `body.py` mapped the quads of the left half of the shell loft to the ring slot one too low (`2K-3-j`, it is `2K-2-j`), so the glass band, the cladding, the arch ceiling and the door part ids of the left side sat one slot off at every LOD (at LOD0 with 16 slots it hid in the noise). Found by a debug view of the surface tags (`near_lineup.sh dbg=2`) and a count of the glass triangles per side of the shipped files (HEAD: SUV Body 288 left / 256 right, LOD1 58 / 42). Fixed in the generator, all 20 models and both near meshes rebuilt; `test_cars_v2` now checks that the glass and the paint panels are the same on both sides of every Body and Body_LOD1 and of the sedan shell of both near meshes (the old files fail it);
40. the near cars were dark on the side away from the moon (no ambient to speak of) -> the two near MultiMesh nodes carry the key and fill light layers (`VehicleVisual.KEY_BIT`, `DynamicFill.FILL_BIT`): the lights of a real car now light a near car, a promoted car changes less at the swap;
41. the HI slots (6 / 4 / 10 per tier) went to the first cars written, not to the nearest: a van six metres from the camera was drawn with the flat far mesh while a car at 18 m had the HI mesh -> the nearest `HI_CAP` cars of the last step get it (`_update_hi_threshold`, unit-tested);
42. the van was one plain slab with no side window -> cab windows at the front doors (kind 3);
43. the real-scene audit tools leave `user://roam_world.cfg` behind, which makes the next `perf_report.sh` read +8 MB of textures at LOW and HIGH (152 / 244 MB instead of 144 / 236) and a few draws more: found when the texture number moved by itself (`QT_CARS_V2=0` and the HI cars off did not change it, moving the file away did). `test_cars_v2_traffic` removes what it causes; not fixed in the audit tools (not mine): remove the file before a perf gate.

## Budgets at the end (perf gate `PERF_CHECK=1 tools/perf_report.sh 0 1 2`, staged view, clean `user://`)
- LOW OK: total draws 94 / 100, triangles 135.2k / 160k, textures 144 / 200 MB, death spike 107 / 115 (PERF RESULT tier=0 ... total_draws=94 total_prims=135193 tex_mb=144 death_draws=107 verdict=OK)
- MED OK: total draws 130 / 140, triangles 276.9k / 280k, textures 175 / 260 MB, death spike 143 / 150 (tier=1 total_draws=130 total_prims=276878 tex_mb=175 death_draws=143 verdict=OK)
- HIGH OK: total draws 150 / 160, triangles 387.6k / 430k, textures 236 / 360 MB, death spike 165 / 170 (tier=2 total_draws=150 total_prims=387608 tex_mb=236 death_draws=165 verdict=OK)
Start of the pass (wave 111 tree): LOW 99 draws / 133.3k triangles / 144 MB / death spike 113, MED 134 / 276.6k / 175 MB / 148, HIGH 155 / 384.2k / 236 MB / 170. Added asset weight: +2.4 MB in the repo (22 glTF files, 11.9 MB; 82 KB for the HI near car), +1.3 MB in an APK (imported scenes 4.8 -> 6.1 MB), no new texture.

## What the pictures show now
- `cars_before_after.jpg`: owner round 5 frames (left) against the final tree (right): the starter car from the chase camera, the hero beside kerb cars, a patrol car and an ambulance with a taxi at night (a lineup of the HI near car: there is no police car in the real-game frames of this pass), a pickup with its load bed.
- `cars2_detail.jpg`: LOD0 / LOD1 / LOD2 of six kinds, the HI near car by day and at night in the wet, real cars at night in the wet at LOW.
- `cars2_streets.jpg`: nine real-game frames at 2400x1080 (MED day in rain, LOW night, LOW day dry with `OUT_WEATHER=CLEAR`, MED night chase).

## Not solved (honest list)
- close to the camera (3 m) the HI shell still shows creases at the roof and the deck edges: it has about 450 triangles and MED has 2.3k triangles left in its budget;
- the van and the box trucks have no wheel arches, the wheel hangs under the box with a gap;
- the near paint still reads pastel in heavy rain;
- LOD2 (beyond 64 m) is one flat colour per car;
- no real-game frame of a police car or a mission car was captured (the lineups and `test_cars_v2` cover them); no phone measurement;
- other builders' files, reported not edited: the rain streak mesh crosses the paint as vertical lines; `AlienCreature._separate` prints freed-instance errors in long drives; `tests/test_vehicle_roster.gd` printed a process_mode error before this pass; the audit tools write the player's real `user://roam_world.cfg` (item 43).

