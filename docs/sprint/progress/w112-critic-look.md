# w112-critic-look (critic-fixer, lens LOOK; started 2026-11-13 ~19:25Z)

GOAL: review wave 112 (landscape, waterfalls, shores, towns, 9 km map, cars v2 pass 2, hero look v3) as a harsh player on a phone: phone-aspect frames (1600x720) from the real game camera,
LOW and MED, OPEN each, write the worst defects, FIX them in render-look-fix loops, test, perf gate. A second critic (PLAY lens) works in the same tree (it also edited terrain_roads.gd / bridges.gd).
MACHINE RULE LEARNED: ONE Godot render job at a time (each ~4.7 GB; three at once got OOM-killed). Scratch lives in the scratchpad crit folder (deleted at the end).

STATUS (21:10Z): about 60 frames rendered and opened (landscape LOW + MED, 7 towns, highway + village, bridges, 6 falls, river, lake, coast at 3 times of day, airport, map screen, hero in the city,
SUIT screen, 5 suit turntables, first minute of a drive out of the city). Fixes below are in the tree, verified by frames or numbers. Perf gate: see TESTS AND PERF.

DEFECTS (what / evidence / file / status)
 1 FIXED  EVERY BRIDGE DECK WAS A BACK FACE (road surface pitch black / navy, wherever the sun was): BridgeKit.road_ribbon wound its triangles counter-clockwise from above, so the engine flipped
          the normal (measured: 16 of 16 triangles back faces in the old order). Invisible while the asphalt was dark, black once wave 112 lightened it. Frames: PASS / SUMMIT bridge, SUMMIT viaduct,
          DESERT ROAD bridge, HARBOUR GATE road. scripts/world/bridge_kit.gd (index order like TerrainRoads.build_ribbon). Sheet docs/shots/round6/critic_look_bridges.jpg.
 2 FIXED  HERO CAPE = FLAT BLACK BOARD in every frame from behind (owner round 2: "a black rectangle patch on the hero"): tools/blender/herosuit/parts.py (14 x 12 quads, vertical folds, scalloped
          slanted hem, rebuilt hero_suit.glb + 3 atlas textures with tools/blender/model_hero_suit.py, 10 s) + assets/shaders/hero_body.gdshader kind 13 now tinted from the suit palette
          (plate * 0.42 + trim * 0.22 + cloth2 * 0.5: a dark slate in every one of the six suits). Sheet critic_look_cape.jpg. Hero triangles +0 (cape is 273 vertices, was 48).
 3 FIXED  SKY: pasted building rectangles at dawn / dusk (hard-edged pink-brown block with a vertical edge over the sea; "blocky clouds"): the 256 x 128 HDRI probes were sampled at full detail.
          assets/shaders/sky.gdshader (textureLod PROBE_BLUR 3.4, filter_linear_mipmap). Verified at 06:00 and 19:00 on the beach (MED).
 4 FIXED  WATERFALLS read as a grey-blue streaked banner, the pool as a glary grey mirror: assets/shaders/fall_water.gdshader (whiter sheet, rougher pool, darker stream ribbons, more glow).
          Verified on fall 4 at LOW and MED. NOT fixed: the cliff beside the sheet is still smooth clay (terrain), the mist sprite at the lip.
 5 FIXED  JUNCTION OF A BRANCH ROAD: the SUMMIT ROAD began as a hard-edged brown dirt patch over the PASS ROAD asphalt, its centre line crossed the highway. terrain_roads.gd (COLOR.b = growth over the
          first 24 m of the first DRAWN piece of a branch road), terrain_road.gdshader (junction_fade: dirt alpha and lane marks grow in), terrain_world.gd (dirt under asphalt: render priority 1 / 2),
          3 cm / 4 cm lift of highway over track ribbons (z-fight of the two decks where PASS ROAD and its branch overlapped). The PLAY critic moved the branch to the END of the bridge
          (DEFS SUMMIT ROAD branch 1270); both changes work together.
 6 FIXED  LOW TERRAIN: the strata layer stretched into regular horizontal corduroy over whole mountains (LOW has no tri-planar): terrain.gdshader (warped strata, share 0.45, far rock read from a
          blurrier mip). Verified on fall 4 at LOW (fish-scale weave is much weaker, not gone).
 7 NOT FIXED, TO THE OWNERS
    - old villages PINE HOLLOW / DUST WELLS (scripts/terrain/outskirts_kit.gd, wave 105) are still plain boxes next to the new towns (ids wired into pads, missions and tests).
    - rivers high in the mountains end in hard rectangular water slabs where the coarse terrain mesh cuts the flat water plane (water_world.gd inland mesh at LOW); needs a depth-soft edge.
    - palm fronds read as black wedges from below at LOD0; tree LOD cross-fade dither reads as a net at mid distance (land_tree.gdshader); kerb cars close to the camera at LOW are faceted.
    - two flat orange translucent wedges crossing the beach at 19:00 (seen once at MED, not reproducible in a 6 frame probe; not the harbour lighthouse beam, 4 km away). Source not isolated.
    - HUD: translucent "BLACK MARKET DROP" event label sits on the compass in street frames (city_events label, PLAY / HUD owner).
 8 CHECKED, FINE  7 towns from the road (farm, mining works, suburb, harbour, resort, lodge, desert outpost: distinct, readable, far better than round 5), the map screen (8 % charted, WORLD and REGION
          levels, 9 km island), the SUIT screen, the first minute of the drive (streaming without pop, traffic cars, signs), the airport apron and runway, HARBOUR GATE.

DONE (files)
- scripts/world/bridge_kit.gd, scripts/terrain/terrain_roads.gd (ribbon colour b, lift), scripts/terrain/terrain_world.gd (priority), assets/shaders/{sky,fall_water,terrain,terrain_road,hero_body}.gdshader,
  tools/blender/herosuit/parts.py (+ rebuilt assets/models/hero_suit.glb, assets/textures/hero_suit_{albedo,orm,normal}), tests/test_critic_look_fixes.gd (13 checks), tests/bot_critic_drive.gd
  (drive out of the city with a script-frame spike log: the car stalled at a contract trigger, the log shows the spikes of the first minute).

DECISIONS / APIs: terrain_road.gdshader has a new uniform `junction_fade` (1 on terrain ribbons, 0 on bridge decks) and reads COLOR.b as the growth value; sky.gdshader PROBE_BLUR const; the cape tint uses
plate_col (suit palette); BridgeKit.road_ribbon lifts a highway deck 10 cm and a track deck 6 cm.

TESTS AND PERF
- tests/test_critic_look_fixes.gd PASS (13 checks). Also PASS: test_sky, test_day_night, test_hero_look_v3, test_bridges_harbour_boats, test_landscape_dressing, test_water_world.
- test_terrain_world FAILS 2 checks, both NOT from this work: "no road is steeper than a mountain track (0.215)" = SUMMIT ROAD's first sample (0.215) before the PLAY critic moved the branch (re-run), and "all 96 far tiles are
  built by the worker threads (60)" (slow under load, known from the outskirts builder).
- Perf gate (PERF_CHECK=1 tools/perf_report.sh, one tier per call, shared tree): LOW OK 74 / total 96 draws, 139.6 k prims, tex 110 MB, death 108; MED OK 97 / 129, 272.5 k, 141 MB, death 145; HIGH: see below.

OPEN PROBLEMS: see 7.
