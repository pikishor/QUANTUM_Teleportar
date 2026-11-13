# w112-landscape (builder notes; started 2026-11-12 ~21:00Z; first session stopped 22:55Z by the usage limit; RESTARTED 2026-11-13 09:11Z)

RESTART 09:11Z: read these notes, git status (landscape files untracked/modified, nothing committed), continuing from the files. Order now: import + load check, look at frames, fix, tests, perf gate, contact sheet, docs.

GOAL: landscape pass for round 6: 6+ tree species by biome with 3 LODs + impostors in MultiMesh chunks (zero per-tree nodes), undergrowth, waterfalls,
shorelines (wet sand, foam, shallow-to-deep ramp), mountain detail, tall anchors (turbines, masts, pylons, cranes), 3+ grass airstrips, wind + rain-wet.

BASELINE DEFECTS (frames: scratchpad landscape/base/*; owner r5_21..23)
 D1 faceted low-poly trees, hexagon far LOD | D2 shore: 260 m flat pink plain, no wet band, flat sea | D3 shaded terrain navy-black | D4 road flat black
 D5 bare ground, sparse spiky tufts | D6 mountains smooth blobs, no strata/scree | D7 no anchors / airstrips | D8 no waterfalls | D9 wind not tied to weather

DONE (all files load; import clean)
- TREES: tools/landscape/{foliage,species,mb,impostor,rocks,build_land_trees,pack_bark,patch_imports}.py -> assets/models/land_trees.glb (9 species x LOD full / lite / mid + 4 rocks x 2 LODs,
  atlas rects in meta), land_foliage.webp (2048x1024 sprites), land_impostor.webp (cross impostors), land_bark_*.webp (Poly Haven CC0 + procedural birch/alien).
  scripts/landscape/{land_kit,land_climate}.gd; shaders land_tree / land_impostor / land_rock / land_common.gdshaderinc. VegKit delegates names to LandKit; VegScatter has 9 species by biome
  (oak pine fir birch palm acacia poplar dead alien), roadside avenues (poplar / palm), flowers, reeds; VegetationWorld: LOD0 full|lite, LOD1, shared impostor slot, per-tier radii, wind node.
- GROUND COVER: g_grass1/2, g_dry, g_tall, g_daisy/poppy/lav/clover, g_fern1/2, g_reed, g_bush1/2 (LandKit card pieces from the atlas).
- TERRAIN: terrain.gdshader (11 layers: wetsand, strata, scree, darkrock; sky fill; derivative bump; wet sand band + pebble line); TerrainBase beach profile (swash + dunes);
  terrain_road.gdshader (grain, cracks, patches, puddles, gravel verge); road ribbon has a verge strip; pack_terrain_textures.py has 11 layers (beach = coast_sand_01).
- LandscapeSites (waterfalls found on cliffs + 3 airstrips found on flat corridors), hooks: TerrainHeight.height_at -> LandscapeSites.carve(height_pre), water_level_for -> pool_level.
- FallWorld (sheet, pool, streams, mist, spray, roar), AnchorSites/AnchorWorld (turbines, pylons+wires, masts, cranes; tools/landscape/props.py -> land_props.glb), StripWorld (strip, hangar, windsock, markers).
- Landscape node attached by City (hook line, QT_NO_LANDSCAPE=1 leaves it out). tests/bot_landscape.gd + tests/landscape_viewer.gd look-dev.

NEXT
1. look at waterfall + anchors + strip frames, fix; terrain/road/sea frames (road still near black: raise asphalt albedo); rocks in frames; mountains (strata) frames; night / rain frames.
2. ocean shader tune; tests/test_landscape_dressing.gd; update test_outskirts_sites limits (slots <= 17) with reason; run affected tests (terrain, water, outskirts, wildlife).
3. PERF_CHECK=1 tools/perf_report.sh 0 1 2; contact sheet docs/shots/round6/landscape_before_after.jpg; ARCHITECTURE.md section; HANDOFF.md; THIRD_PARTY.md (Poly Haven textures).

DECISIONS (APIs other agents depend on)
- AnchorWorld.instance.anchors_near(pos, radius) -> [{id, kind (turbine|pylon|mast|crane), name, pos (top), base, height, radius}] for quantum snake anchors.
- LandscapeSites.falls() / strips() / hooks() / pool_level() / inside_strip() / near_feature(); StripWorld.hooks() lists the airstrips (centre, u, len, wid, y) for the aircraft wave.
- LandClimate.vec() = (dir x, strength, dir z); global shader parameter `wind` (vec4); LandClimate.override(strength, deg) pins it for tests.
- VegScatter species ids: FIR 8, BIRCH 9, PALM 10, ALIEN 11, POPLAR 12, ACACIA 13, FLOWER 14, REED 15; layers LAYERS = 6 (T_LINES 4, T_REEDS 5).

TESTS AND PERF
- 09:35Z test_landscape_dressing.gd PASS (58 s) on the restored tree. 09:50Z perf gate (all 3 tiers) OK: LOW 76/98 draws, death 105, tex 157 MB; MED 101/133, death 143, tex 180; HIGH 112/147, death 164, tex 266.
- NOTE: the parallel builder w112-outskirts-map made the world 9 km (TerrainHeight.WORLD_HALF 4500, scripts/world/world_extent.gd pushes the coast out W/N/E) and adds towns as OutskirtsSites entries: all my sites are FOUND by search so they follow; re-run the probe + test after their changes.

ITERATION LOG (frames in scratchpad ls/, 1600x720 MED, bot tests/bot_landscape.gd views road:/beach:/pool:/airstrip:/fall:/fallv:/anchor:)
- it1 (09:30-10:40Z): defects seen: orange-clay verge + lime blobs on dirt tracks, big sparse neon tufts, olive 'beach' with white popcorn pebbles, waterfalls at snow altitude (washed out, saw-tooth sheet foot, outflow ribbon floating like a plank), river water with dark dimples, white tray rim on pools.
  fixed so far: terrain layer 6 = forest_ground_04 (dark earth) + layer 3 = coast_sand_02 (tan), wider dry-sand band (TerrainBase.shade_weights), road shader dirt track (earth below, scree above 95-185 m, dark grass strip), tufts smaller/denser/darker (veg_scatter SPACING + COVER_LOOK), pebbles 48 tris, rounder, scree/dark colours.
  NEXT: waterfalls redesign (pool altitude < 190 m, smooth sheet corridor in the carve, sheet/pool/stream shaders, mist), river water shader, tree dither, rocks, strips, night/rain, LOW, tests.

OPEN PROBLEMS
- ambientCG downloads are BLOCKED; Poly Haven api + dl.polyhaven.org work (cdn.polyhaven.com thumbnails are blocked): all bark / ground textures come from there.
- tests/zz_probe_landscape.gd is a TEMPORARY probe: delete before finishing.
- the hero's shadow looks like a hard dark parallelogram on dirt (coarse skinned shadow proxy; not my scope).
