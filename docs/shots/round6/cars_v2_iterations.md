# Cars v2: render, look, fix loops

Every loop: render (`tools/carv2_lineup.sh`, `tools/vehicle_view.sh`, `tools/vehicle_bot.sh` at LOW and MED, 2400x1080 software Vulkan), look at the pictures, list what is wrong, fix it in the generator or the shaders, rebuild (`build_cars_v2.py`, `tools/import.sh`), render again.
Contact sheet before / after: `cars_v2_before_after.jpg`; against the owner's round 5 pictures: `cars_v2_vs_owner_round5.jpg`.

Honest note on the record: loops 1 to 3 were done before this session's context was compacted. Only the defects that the hand-over kept are listed for them, so they do not count towards "eight concrete defects per loop". Loops 4 to 6 were logged defect by defect while they were fixed.

## Loops 1 to 3 (partial record)
- imported scene sat under a wrapper node (the exporter's root empty), so the contract nodes were not found by name -> no root empty, the importer's own root holds Body, wheels and anchors;
- nose and tail faces hollow and black (end cap fans missing or facing inwards) -> each fan is checked against the wanted normal direction;
- the look-dev lineup camera had front and rear swapped -> corrected;
- lamp patches stretched round the curved corners of the nose and tail -> lamps fitted to the flat end face (fractions of the face height, `fit_x` for the width);
- windscreens read as flat black holes -> own Glass surface with tint, reflection and a modelled cabin behind it (dash, seats, wheel, driver, liner);
- varying assigned in a helper function, `MODELVIEW_MATRIX` in the fragment stage: shader compile errors, fixed;
- the variants (wagon, limo, ambulance, armoured, delivery, garbage, fire truck, hover) needed their own proportions: garbage hopper moved to the tail, fire truck compartments, variant sizes registered in `VehicleSpecs`.

## Loop 4 (11 defects)
1. wheel hub and brake caliper were pure white (the importer's tangents are garbage on faces without uv area and the wheel shader used a conditional `NORMAL_MAP`) -> the tread frame is built from the axle in the vertex stage, no `NORMAL_MAP`;
2. the sports car's dashboard slab stood out of the cowl above the bonnet -> dash height clamped under the beltline;
3. the sports car's front wheel arches broke through the bonnet (dark wedges on the fenders; the arch was higher than the top surface) -> bonnet line raised, wheels 1.5 cm smaller, arch clamped to the top surface in the shell loft;
4. the engine bay and trunk fill boxes poked through low noses (dark blobs on the bonnet) -> boxes are fitted under the lowest shell point of their footprint;
5. the side intake patch became a black triangle (it overlapped the rear wheel arch) -> removed, the rear wing stands on two thin painted stays;
6. reverse lamps were white specks at the bumper corner -> moved beside the plate, later into the tail cluster (loop 6);
7. bus windows glowed tan and opaque (the cabin glow was added over the whole pane, 1.8 times over) -> cool weaker glow, clamped to 1, colour per kind;
8. buses and trucks had a pillow shading and an X-shaped crease on the flat end faces (angle-only smooth normals, fans sharing corner normals) -> normals weighted by angle x area^0.6, end fans in their own smoothing group;
9. the bus had no lamps, grille or plates at all (the surface rays started at 4 m, inside a 9.5 m body) -> ray origins computed from the model size;
10. van, box truck and delivery doors were glass from sill to roof (the belt keys ran nose to tail and `pchip` wants ascending keys: errors up to 1 m) -> keys sorted, every archetype's beltline is now the designed one;
11. headlamps of tall noses became huge round eyes -> lamp height capped (27 cm), later plain rectangles for utility vehicles (loop 5).
Also: LOD1 trimmed (3 ring slots on the upper wall, step 1.1 m): 1.5-2.2k triangles with wheels instead of 1.8-2.4k.

## Loop 5 (11 defects)
1. fire truck compartments rendered as dark bow-ties (patches on a curved flank) -> outlines and roller shutter slats that follow the surface;
2. utility vehicle headlamps still read as angry eyes (bezel, reflector bowl, swept hexagon) -> plain rectangular clear lamps for vans, trucks and buses;
3. sports tail lamps were large glossy hexagons -> height cap 25 cm for cars, a darker inner lens, amber indicator corner;
4. reverse lamps as white teeth under the tail lamps -> dark housing, small, beside the plate (utility) or inside the cluster (cars, loop 6);
5. the bus had no destination board, no door outline, no rear window -> amber board on the top of the windscreen, door outline and divider, dark rear glass;
6. the box truck's fuel tank was a glossy black brick -> a cylinder with two straps;
7. trucks had no cab steps -> a step under each door;
8. tyre sidewalls looked speckled (the tread normal map covered the whole profile) -> the blocks only on the tread band, a faint grain on the sidewall;
9. the cracked glass of a badly damaged car was a blocky black and white mosaic (hash cells) -> more stars of thin lines at other points of the pane;
10. the hover car had only 4.2k triangles (plain glow discs for thrusters) -> ducted fan pods (ring duct, inner wall, eight stator blades, hub, glow disc), diffuser strakes, two thrust nozzles, canopy rails: 6.7k;
11. delivery and garbage trucks overhung their spec length by 0.4-0.6 m (extras were placed for a 6.4 m truck) -> bumper, rails and hopper follow the car length.

## Loop 6 (9 defects)
1. near traffic cars looked like pale ghosts at MED (a smooth 430 triangle car under the shader's blue rim light, raked glass at grazing angles) -> crisper normals for the near mesh (22 degree threshold) and raked glass tagged as dark trim;
2. glass reflected too much at grazing angles (fresnel power 4, reflection 0.7) -> power 5, reflection 0.55, alpha up to 0.9;
3. the white hub of loop 4 left a flat dark disc -> a bright centre cap in the dark hub;
4. the dashboard was a flat box seen through the windscreen -> tilted so its top slopes up to the glass;
5. reverse lamps still stood apart under the tail lamps (cars) -> the reverse lens is the inner corner of the tail cluster;
6. tail lamp clusters of cars still too tall -> 25 cm cap;
7. the 12 paints sheet cut the last row -> wider framing;
8. `CarV2.repair()` already cleared the fire and the soot; `tests/test_cars_v2.gd` now checks it (a pooled car that burned would otherwise glow in its next life);
9. the interceptor's spec height (1.63 with the light bar) made "an ambulance is much taller than an interceptor" in `test_traffic_police_feel` fail by a hair -> spec height 1.52.
Also (tests that hold the proportions of the older art found spec numbers I had moved to fit the new models): sedan, taxi, patrol and wagon wheels are 0.35 m (archetype radius raised, spec `wheel` 0.35), sports tyres 0.335 / 0.355 m again (the bonnet was raised instead), SUV height 1.72, luxury 5.2 x 1.55 m, sedan height 1.42 and length 4.7: `test_director_round2_c`, `test_open_models` and `test_director_round3_a` (the crack is now measured as the glass shader's `crack_at`) pass again.

## What the pictures show now
- `cars_v2_lineup12_*`: the 12 street kinds, front and rear, LOW and MED; `cars_v2_lineup_variants_low.jpg` the other eight; `cars_v2_paints12.jpg` the 12 paints on one sedan; `cars_v2_damage_states.jpg` sound, 50 %, 97 %; `cars_v2_driving_low.jpg` / `_med.jpg` the starter car in the real city.
- Not solved, on purpose or for lack of time: the interiors are a driver and boxes for seats (readable through the glass, not a GTA cabin); the hero and the weapon in the look-dev viewer are not part of this work; near traffic at MED still reads paler than the older boxy cars because the shared fog and rim light of `prop_nearcar.gdshader` (not ours) brighten smooth shapes at grazing angles.
