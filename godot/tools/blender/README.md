# Generated assets (models, textures, audio)

Everything under `assets/models`, `assets/textures` and `assets/audio` is produced by scripts, so it is reproducible and reviewable.

```
tools/build_assets.sh                  # textures (512 px, committed) -> audio -> models -> Godot import (+ import settings)
tools/build_assets.sh --hires          # also writes 1K texture sets to assets/generated/textures (git-ignored, .gdignore'd)
tools/blender/build_all.sh player car_sport   # only some models (needs BLENDER_PY or tools/blender/ensure_bpy.sh)
python3 tools/audio/make_audio.py --only shot,boom --preview /tmp/audio.png
tools/test.sh tests/test_assets.gd     # contract test: node names, orientation, budgets, formats, loop
QT_VIEW=car_sport,10,30,8 tools/shot.sh /tmp/car.png res://tests/assets_showcase.tscn 25   # look-dev stage, see tests/assets_showcase.gd
```

## Conventions (all models)
1 unit = 1 m, origin at ground contact, Y up, **front = -Z** (authored with the front on +Y in Blender, `export_yup` converts), no collision.
The GLB files contain geometry and materials only: textures are referenced by relative URI (`../textures/<set>_<map>.png`), so every
model shares one copy of each texture (one GPU texture per set). `glbtool.externalize_images` does this after the Blender export.

| Model | Nodes (direct children of the scene root) | Materials | Tris |
|---|---|---|---|
| `player`, `operative` | `Body` (torso, armour, helmet, arms, rifle), `LegL`/`LegR` (origin = hip joint, swing about X), `Muzzle` (Node3D at the rifle tip) | Fabric, Armor, Gunmetal, Visor, Glow | ~9k |
| `drone_sentinel`, `drone_striker`, `drone_heavy` | `Body`, `RotorFL/FR/RL/RR` (origin = hub, spin about local Y), `Eye` (emissive mesh at the optic), `Muzzle` (sentinel, heavy) | Armor, Carbon, Gunmetal, Glow (+HoverGlow heavy) | 4.4k-5.8k |
| `car_sedan`, `car_sport`, `car_suv` | `Body`, `WheelFL/FR/RL/RR` (origin = axle centre; steer by Y rotation, roll about X) | `Body` (recolourable paint), Glass (blended), Trim, Wheel, Headlights, Taillights, Underglow | ~11.5k |
| `pickup_health`, `pickup_energy`, `core_gem` | `Body` | Armor/Fabric/Gunmetal/Glass + Glow | 1.2k-2k |

Authored at final size (human 1.82 m, sedan 4.75 x 1.86 x 1.48 m, sport 4.45 x 1.92 x 1.20 m, SUV 4.85 x 1.98 x 1.83 m,
drones: body centre at y = 0.95 / 0.82 / 1.40 m for sentinel / striker / heavy), so do not scale them.

Recolour a car: duplicate the surface material whose `resource_name == "Body"` and set `albedo_color` (the texture only carries
wear and clear-coat detail; vertex colours hold baked ambient occlusion and grime). Emissive parts are `Headlights`, `Taillights`,
`Underglow`, `Glow` (KHR_materials_emissive_strength, i.e. `emission_energy_multiplier` > 1 so bloom picks them up).

## Texture sets (`assets/textures`, tileable)
`plating, metal_painted, fabric, carbon, rubber, concrete, asphalt, steel, glass` each as `<set>_albedo.png` (neutral grey L8, tint it with
the material colour / vertex colour), `<set>_orm.png` (R = AO, G = roughness, B = metallic, glTF packing) and `<set>_normal.png`
(OpenGL, +Y up). `make_textures.py` is numpy only and deterministic. Committed size is 512 px (~7.7 MB); `--hires` writes 1K.
`patch_imports.py` pins the Godot import settings (VRAM-compressed textures, normal-map flag, PCM16 audio) in the committed `.import` files.

## Audio (`assets/audio`)
`make_audio.py` synthesises 44.1 kHz mono 16-bit WAVs with numpy only: layered transient + body + tail through a synthetic convolution reverb,
soft-limited and normalised to -3 dBFS. `music_ambient.wav` is a 30 s seamless loop (64 BPM x 32 beats, every oscillator uses whole cycles,
circular reverb, `smpl` loop chunk so Godot loops it by default; play it at a lower bus volume than the effects).

## Rebuilding the models needs Blender as a Python module
`export BLENDER_PY="$(tools/blender/ensure_bpy.sh)"` creates `~/.cache/qt-bpyenv` with `pip install bpy` (about 10 minutes, tested with bpy 5.2.3).
Files: `helpers.py` (materials, bmesh `Part` builder, vertex AO, export), `humanoid.py`, `dronelib.py`, `carlib.py` (parametric builders),
`model_*.py` (one script per model), `glbtool.py` (GLB post-processing and triangle counting), `make_textures.py`.
