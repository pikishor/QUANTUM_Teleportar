# w112-landscape (builder notes; started 2026-11-12 ~21:00Z)

GOAL: landscape pass for round 6: 6+ tree species by biome with 3 LODs + impostors in MultiMesh chunks (zero per-tree nodes), undergrowth, waterfalls,
shorelines (wet sand, foam, shallow-to-deep ramp), mountain detail, tall anchors (turbines, masts, pylons, cranes), 3+ grass airstrips, wind + rain-wet.

BASELINE DEFECTS (frames: scratchpad landscape/base/b1_*, b2_*; owner r5_21..23)
 D1 trees are faceted low-poly Lego (flat dark cone pines, blob broadleaf), far LOD = translucent-looking hexagons (owner r5_22)
 D2 shore: 260 m wide flat pink sand plain, no wet band / berm / dunes / grass line / rocks / driftwood; sea a flat pale slab, faint foam, no depth ramp
 D3 terrain in shade goes navy-black (no sky fill) while lit parts are orange: cliffs read as dark streaky blue
 D4 roads: flat near-black ribbon, markings barely visible, no wear / shoulder detail (owner: "long empty dark road")
 D5 ground cover: bare orange/brown plain, sparse spiky tufts, no grass carpet, flowers, variation
 D6 mountains: smooth blobs with speckle snow, no strata / scree, cliff texture stretched vertically
 D7 no anchors in the outskirts (pylons, turbines, masts), no roadside furniture, no airstrips
 D8 no waterfalls; rivers are plain strips
 D9 wind is a fixed sway pattern, does not follow Weather; materials have no rain response beyond a flat darkening

DONE
- read ROUND6, DESIGN, WORLD_EXPANSION, ARCHITECTURE terrain / water / vegetation sections; baseline renders (MED + LOW, hero views).
- tests/bot_landscape.gd (look-dev bot: LS_VIEWS hero: road: cam: abs:, LS_HOUR, LS_WEATHER).

NEXT
1. Tree generator tools/landscape/ (numpy + PIL, GLB writer): oak, birch, pine, fir, palm, dead, alien, poplar, acacia; LOD0 (lite + full), LOD1, impostor cross quads; foliage + bark atlas.
2. VegKit / VegScatter / VegetationWorld / vegetation.gdshader: species, biomes, 3 LOD slots, wind global from Weather, rain-wet.
3. Ground cover, shore (terrain shader wet sand + sky fill, ocean ramp), waterfalls (new scripts/landscape/*), anchors, airstrips.
4. test_landscape_dressing.gd; perf gate PERF_CHECK=1 tools/perf_report.sh 0 1 2; contact sheet docs/shots/round6/landscape_before_after.jpg.

DECISIONS (APIs other agents depend on)
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- disk: only ~3.9 GB free at start (scratchpad ci_clone of the main session holds 4.8 GB, not mine); my scratch frames are deleted right after conversion to jpg.
- tests/zz_probe_landscape.gd is a TEMPORARY probe; delete before finishing.
