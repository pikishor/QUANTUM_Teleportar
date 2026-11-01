# Generated assets (models, textures, audio)

Everything under `assets/models`, `assets/textures` and `assets/audio` is produced by scripts, so it is reproducible and reviewable.

```
tools/build_assets.sh                  # tiling sets -> audio -> models + baked atlases -> Godot import (+ import settings)
tools/build_assets.sh --hires          # also writes the 1K tiling texture sets to assets/generated (git-ignored, .gdignore'd)
tools/build_assets.sh --skip-models    # textures + audio only (numpy is enough, no bpy)
tools/blender/build_all.sh player car_sport   # only some models (needs the bpy interpreter, see below)
python3 tools/audio/make_audio.py --only shot,boom --preview /tmp/audio.png   # prints the peaks and the firefight mix check
tools/test.sh tests/test_assets.gd     # contract test: nodes, orientation, budgets, lights, formats, levels, mix headroom, loop
QT_VIEW=car_sport,10,30,8 tools/shot.sh /tmp/car.png res://tests/assets_showcase.tscn 25   # look-dev stage, see tests/assets_showcase.gd
```

## Toolchain
One interpreter runs every Python step: Python 3.13 with `bpy==5.2.3` and `numpy==2.5.4` (`tools/requirements.txt`). `tools/setup_python.sh`
creates `godot/.venv-tools` and prints the path; `build_assets.sh` and `build_all.sh` use `$BLENDER_PY` if set, else that venv
(`build_assets.sh` creates it when missing). `tools/blender/ensure_bpy.sh` is a one-line wrapper that `exec`s `setup_python.sh` (the two used to differ; there is
now one environment recipe). The textures and the audio need only numpy (`--skip-models`).
`tools/verify_asset_build.sh` proves the pipeline end to end: it copies the committable files of the checkout to a temp directory, runs `build_assets.sh` there with an EMPTY
`HOME` and a scrubbed environment (it downloads the pinned Godot, creates the venv, pip-installs bpy, bakes everything, imports) and compares every generated file byte for byte
with the checkout. The bake of the 2K atlases takes about 10 minutes on 4 cores and `~/.cache/pip` is not shared, so expect 15 to 20 minutes the first time.

## Texture resolution and compression (install size, on purpose)
The model scripts ask `helpers.export_model` for a 1024 px atlas (512 for pickups); `atlas.DEFAULT_SCALE` (env `QT_ATLAS_SCALE`, `build_assets.sh --atlas-scale N`) multiplies it:
**the committed set is the 2x set, 2048 px atlases for the hero, the trooper, the three drones and the three cars (a neutral paint atlas and a details atlas each), 1024 px for the pickups
and the core.** Texel density is still capped by `max_ppm` (900 px/m). `patch_imports.py` imports those atlases VRAM-compressed with mipmaps, and in HIGH QUALITY (ASTC 4x4 / BPTC, 8 bit per pixel)
for albedo, normal and emission; ORM (smooth data) and the 512 px tiling sets use the cheap 8x8 / S3TC path. `post_import.gd` gives every textured model material anisotropic mipmap filtering and
`scripts/common/perf_tiers.gd` sets the level per tier (2x / 4x / 8x). Sizes: committed texture sources about 31 MB (JPG albedo / ORM, PNG normal), imported textures about 195 MB per platform (a 2048 px high-quality texture is 5.3 MB with its mipmaps; the
import cache holds the desktop BPTC and the phone ASTC copy, so `.godot/imported` shows about twice that), so the install is about 220 MB with audio and models
(`tools/size_report.sh` prints sources and imports after an import); the runtime texture memory of the staged scene is in `tools/perf_report.sh`. Install budget: BUDGETS.md.

## How a model is made (the baked atlas)
A tiling texture per material costs one draw call per material and cannot show wear. Instead every model script builds hard-surface
geometry with `helpers.Part` (bevelled boxes, lofts, tubes ...) tagged with a *surface kind*, and `helpers.export_model` does the rest:

1. `atlas.cull_hidden`  deletes faces buried inside other geometry (a quarter of the triangles of a character).
2. `Part.build`         weighted normals; each kind keeps its tint colour per face.
3. `atlas.bake`         planar UV islands (near-flat patches, uniform texel density, shelf packing), ray-traced ambient occlusion per
                        texel, distance to convex and concave creases, then `shade.KINDS` turn those into albedo, roughness, metallic,
                        emission and a height field: paint chips and brightens along bevelled edges, grime collects in cavities, near the
                        ground and under rain streaks, scratches and brushed metal, stencils and stripes from `shade.Decal` projections.
                        Output: `assets/textures/<model>_albedo.jpg`, `_orm.jpg` (R = AO, G = roughness, B = metallic), `_normal.png`
                        (OpenGL, +Y up; orientation verified with a lit dome test) and `_emit.png` when something glows.
4. glTF export; `glbtool.externalize_images` swaps the embedded images for relative URIs of those files (one GPU texture per model).

Surface kinds: `fabric plating steel rubber glass carbon glow solid chitin shell silk` go into ONE shared atlas material per model; `paint` (the car body)
is a second, neutral atlas that the material colour tints; "flat" materials (`make_material(name, emit=...)`: Eye, Headlights,
Taillights, Underglow) stay separate on purpose, because gameplay recolours or toggles them.

| Model | Nodes (direct children of the root) | Materials (draw calls) | Tris |
|---|---|---|---|
| `player` (Kestrel), `operative` (Vael trooper) | ONE skinned `Body` mesh under `Rig/Skeleton3D` (bones `Hips > Torso > Head, UpperArmL/R > ForeArmL/R, Rifle`; `Hips > ThighL/R > ShinL/R > FootL/R`, plus optional `Sec1 > Sec2 > Sec3` cloak / tail chain; rest rotation identity, origin = pivot) + root empties `Muzzle`, `WristL/R`, `MagWell`, `MagPouch` | one baked `Gear` (**1 draw call**) | 17.8k / 8.3k |
| `drone_sentinel/striker/heavy` (jelly / living bomb / beetle gunship) | `Body`, `Fins` (origin on the body axis: tendril frill, thorn ring, cilia skirt; the game turns and pulses it), `Eye` (flat emissive material, recolour a duplicate), `Muzzle` (sentinel, heavy) | baked `Hull` (Body + Fins) + flat `Eye` (**3 draw calls**) | 2.5k-3.9k |
| `car_sedan/sport/suv` | `Body`, `WheelFL/FR/RL/RR` (origin = axle centre; steer by Y rotation, roll about X) | `Body` (neutral paint, recolour), baked `Details` (trim, rubber, chrome, tinted opaque glass), flat `Headlights`, `Taillights`, `Underglow`; wheels use `Details` (**9 draw calls**) | ~8k |
| `car_taxi/wagon/van/truck`, `bike_street`, `car_hover`, `car_vael_patrol` (Wave 14 vehicles, 1K atlases) | `Body` (LOD0) and `Body_LOD1` (decimated copy, about 30 % of the triangles, same materials; shown beyond `VehicleVisual.LOD1_DIST`), cars `WheelFL/FR/RL/RR`, bike `WheelF/WheelR` (origin = axle), hover craft none (hull underside at `hover_h`: 0.55 m / 0.5 m) | as the cars (`Body`, `Details` with baked glow trim, flat `Headlights`, `Taillights`, `Underglow`; Body + 4 wheels = 9 draw calls, bike 7, hover craft 5) | 5-6k LOD0 + 1.5k LOD1 (wheels 3-5k) |
| `citizen` (pedestrian, no atlas) | two meshes `Citizen` (near) and `CitizenFar`, each ONE surface with COLOR_0 (R surface, G piece id / 20, B baked shadow, A part tag; see `model_citizen.py`), shaded by `prop_crowd_core.gdshaderinc` | vertex-colour only (**1 draw call per mesh**), 13 archetypes by vertex shader | 816 / 258 |
| `pickup_health`, `pickup_energy`, `core_gem` | `Body` | one baked material named `Glow` (duplicate it and change `emission` to retint) (**1 draw call**) | 1.2k-2.4k |

Authored at final size (human 1.82 m, sedan 4.75 x 1.86 x 1.48 m, sport 4.45 x 1.92 x 1.20 m, SUV 4.85 x 1.98 x 1.83 m,
drones: body centre at y = 0.95 / 0.82 / 1.40 m for sentinel / striker / heavy), so do not scale them.
The pickups are beacons (about 1 m tall cages, 1.15 m glowing ground ring) so they read from far away; `core_gem` is 1.62 m tall.

Recolour a car: duplicate the surface material whose `resource_name == "Body"` and set `albedo_color` (it is a `StandardMaterial3D`; the baked
texture is neutral and only carries wear, grime and clear-coat variation). Emissive parts are `Headlights`, `Taillights`, `Underglow` (flat
colours, strength 2-3) and the glowing details baked into `Gear` / `Hull` / `Glow` (emission strength 1.3-1.8). Emission is kept low on purpose:
the city's ACES tonemap turns anything hotter than about 2 into white and the colour code (green health, cyan energy, red / amber / purple
drones) would be lost; the colour is carried by saturated emitters and by the lights below.

## High-poly bake (`hipoly.py`)
`export_model(..., hipoly=dict(levels=2))` (hero and trooper): the built parts are subdivided (Catmull-Clark) and displaced with real per-kind relief (scutes, panel seams and rivets, cloak folds), then `atlas.bake` ray-casts every texel of the low-poly mesh onto that surface and bakes the tangent-space normal and a cavity term into the 2K normal / ORM / albedo atlases (UDN-blended with the procedural relief). pip `bpy` has no Cycles, so this is a numpy + mathutils BVH baker, deterministic and byte-identical. `QT_NOHIPOLY=1` disables it; options `levels`, `scale`, `kind_scale`.

## Lights, light layers and LOD tags (`post_import.gd`)
The model scripts place marker empties (`helpers.light(...)`, a `qt_light` JSON property); `tools/blender/post_import.gd` (the import script
`patch_imports.py` sets in every committed `.glb.import`) turns them into real nodes when Godot imports the GLB:

* every model ships its own readability lights: a **fill** (`mask: "own"`) that lights only that model, so a character is lifted at night
  without lighting the street (the model's meshes join **light layer 19**; layer 20 is the player's), a **rim** on characters, **Headlights**
  (spot) + **UnderglowLight** + fill on cars, an **EyeLight** on drones, a coloured **GlowLight** on pickups and the core;
* lights cast no shadows, fade out with the camera distance (`distance_fade`) and join the group `qt_model_lights`
  (`get_tree().call_group("qt_model_lights", "set_visible", false)` on the LOW graphics tier);
* `RotorXX` and `WheelXX` fade out beyond 45 / 60 m (`visibility_range_end`) and cast no shadow (draw calls for parts that are a few pixels).

Because the importer replaces the markers, `Game.load_model()` needs no extra code. The player module keeps the model (rig, `Muzzle`) and frees its `Fill` / `Rim` lights, so it keeps its own character lights.

## Texture sets (`assets/textures`, tileable)
`plating, metal_painted, fabric, carbon, rubber, concrete, asphalt, steel, glass` each as `<set>_albedo.png`, `<set>_orm.png` (R = AO,
G = roughness, B = metallic) and `<set>_normal.png` (OpenGL, +Y up). `make_textures.py` is numpy only and deterministic. Committed size is
512 px (~7.7 MB); `--hires` writes 1K. The models no longer use them (their textures are baked per model); they are kept for the city.
`patch_imports.py` pins the Godot import settings (VRAM-compressed textures, normal-map flag, PCM16 audio, the import script) in the committed
`.import` files and clears the cached import of whatever it patched.

## Audio (`assets/audio`)
`make_audio.py` synthesises 44.1 kHz mono 16-bit WAVs with numpy only: layered transient + body + tail through a synthetic convolution reverb.
The levels are mix levels (`LEVELS_DB`: shot -12, enemy_shot -13, hit -14, hurt -13, boom -10, blink -12, link -13, superpos -13, pickup/reload -14,
core -10 dBFS, music -17 dBFS), every file is high-passed (no infrasound: phone speakers cannot play it and it eats headroom), and the
sub-bass layers were moved up and saturated so the harmonics carry on small speakers. `mix_check` (also in `tests/test_assets.gd`) sums sustained
fire and a 3 s firefight through Sfx's 12-voice pool: -9 dBFS and -3 dBFS without any limiter. `music_ambient.wav` is a 30 s seamless loop
(64 BPM x 32 beats, whole-cycle oscillators, circular reverb and filter, `smpl` loop chunk): play it on its own bus at 0 dB, it already sits
about 5 dB under the effects' peaks. `default_bus_layout.tres` is a ready Master (limiter) / SFX / Music layout for the orchestrator to enable.

## Files
`helpers.py` (materials, `Part` builder, lights, export), `atlas.py` (hidden-face culling, UV islands, packing, bake), `shade.py` (surface kinds,
noise, decals), `alienlib.py` (character rig finalizer and loft helpers; `humanoid.py` only provides `RigPart` and the old human builder, `dronelib.py` is the old rotor helper), `carlib.py` (parametric builders; `lod1=` in a spec adds `Body_LOD1` through `lodlib.py`), `vehlib.py` (glow trim, wheel and light-rig helpers of the Wave 14 vehicles), `model_*.py` (one script per model), `glbtool.py` (GLB
post-processing and triangle counting), `post_import.gd` (import script), `patch_imports.py`, `make_textures.py`.
Scratch / experiments: `QT_MODELS_DIR` and `QT_TEX_DIR` redirect the output, `QT_ATLAS_SCALE=2` doubles the atlas sizes, `QT_NOCULL=1`
skips hidden-face culling, `QT_DEBUG_CULL=1` lists what was culled.
