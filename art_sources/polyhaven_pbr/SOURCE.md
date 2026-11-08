# Poly Haven PBR materials and HDRIs (CC0)

Source: Poly Haven (https://polyhaven.com), API https://api.polyhaven.com, files https://dl.polyhaven.org. Every Poly Haven asset is CC0 1.0 (public domain dedication, no attribution required; credited anyway). See LICENSE.txt.
Downloaded with plain curl and the user agent `QuantumTeleportar-asset-fetch/1.0` by `godot/tools/materials/fetch_polyhaven.py` (1K JPG: diffuse, arm = AO / roughness / metal, GL normal).
ambientCG (https://ambientcg.com) was tried first: its API answers, but the download host (acg-download.struffelproductions.com) is refused by this session's network policy, so it is NOT used. kenney.nl returns 403.
The raw downloads are not committed (`godot/assets_incoming/polyhaven_raw/`, git-ignored; re-fetch with the script). Only the packed, size-reduced result is in the repo.

## Materials -> `godot/assets/textures/world_<name>_a.webp` / `_n.webp` (1024 px, lossy WebP, VRAM compressed at import)
Packed by `godot/tools/materials/pack_world_materials.py` from `godot/tools/materials/world_materials.json` into the slot format of the city shaders (albedo as detail modulator with median luminance 0.5 + dry roughness; RG normal, cavity, wet roughness). `flat` sets (interiors, `i_*`) carry the cavity in the albedo (one tap).

| Use (name) | Poly Haven slug | Title | Author | URL |
|---|---|---|---|---|
| road_market | clean_asphalt | Clean Asphalt | Dimitrios Savva | https://polyhaven.com/a/clean_asphalt |
| road_foundry | asphalt_pit_lane | Asphalt Pit Lane | Dimitrios Savva | https://polyhaven.com/a/asphalt_pit_lane |
| road_slums | asphalt_02 | Asphalt 02 | Rob Tuytel | https://polyhaven.com/a/asphalt_02 |
| road_towers | worn_asphalt | Worn Asphalt | Amal Kumar | https://polyhaven.com/a/worn_asphalt |
| walk_market | pavement_04 | Pavement 04 | Jan Burghardt | https://polyhaven.com/a/pavement_04 |
| walk_foundry | metal_plate | Metal Plate | Rob Tuytel | https://polyhaven.com/a/metal_plate |
| walk_slums | concrete_pavement_02 | Concrete Pavement 02 | Charlotte Baglioni | https://polyhaven.com/a/concrete_pavement_02 |
| walk_towers | pavement_01 | Pavement 01 | Rob Tuytel | https://polyhaven.com/a/pavement_01 |
| brick | brick_wall_005 | Brick Wall 005 | Dario Barresi, Dimitrios Savva | https://polyhaven.com/a/brick_wall_005 |
| wall | dirty_concrete | Dirty Concrete | Rob Tuytel | https://polyhaven.com/a/dirty_concrete |
| metal | metal_plate_02 | Metal Plate 02 | Rob Tuytel | https://polyhaven.com/a/metal_plate_02 |
| corr | corrugated_iron | Corrugated Iron | Jenelle van Heerden, Dimitrios Savva | https://polyhaven.com/a/corrugated_iron |
| i_plaster | white_plaster_02 | White Plaster 02 | Rob Tuytel | https://polyhaven.com/a/white_plaster_02 |
| i_brick | brick_wall_02 | Brick Wall 02 | Dimitrios Savva | https://polyhaven.com/a/brick_wall_02 |
| i_tile | floor_tiles_02 | Floor Tiles 02 | Rob Tuytel | https://polyhaven.com/a/floor_tiles_02 |
| i_check | floor_tiles_06 | Floor Tiles 06 | Rob Tuytel | https://polyhaven.com/a/floor_tiles_06 |
| i_concrete | concrete_floor_worn_001 | Concrete Floor Worn 001 | Dimitrios Savva, Rico Cilliers | https://polyhaven.com/a/concrete_floor_worn_001 |
| i_wood | wood_floor_worn | Wood Floor Worn | Dimitrios Savva | https://polyhaven.com/a/wood_floor_worn |

## HDRIs -> `godot/assets/textures/sky_probe_{dusk,night,overcast}.png` (256 x 128, Reinhard-encoded)
Packed by `godot/tools/materials/pack_sky_probes.py` (1K .hdr, box-downsampled) and read by `godot/assets/shaders/sky.gdshader` as horizon / street-glow / ground-bounce light of the visible sky and the radiance cubemap (ambient + reflections).

| Probe | Poly Haven slug | Title | Author | URL |
|---|---|---|---|---|
| dusk | sunset_jhbcentral | Joburg Central Sunset | Greg Zaal, Dimitrios Savva | https://polyhaven.com/a/sunset_jhbcentral |
| night | cobblestone_street_night | Cobblestone Street Night | Greg Zaal, Jenelle van Heerden | https://polyhaven.com/a/cobblestone_street_night |
| overcast | potsdamer_platz | Potsdamer Platz | Greg Zaal | https://polyhaven.com/a/potsdamer_platz |
