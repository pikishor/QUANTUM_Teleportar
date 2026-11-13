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
- (none run yet)

OPEN PROBLEMS
- ambientCG downloads are BLOCKED (acg-download.struffelproductions.com 403 from the proxy); Poly Haven (api + dl.polyhaven.org) works: all bark / ground textures come from there.
- disk ~3.9 GB free (ci_clone scratch of the main session holds 4.8 GB); my scratch frames are converted to jpg and deleted at once.
- tests/zz_probe_landscape.gd is a TEMPORARY probe: delete before finishing.
