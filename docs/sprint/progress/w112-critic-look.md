# w112-critic-look (critic-fixer, lens LOOK; started 2026-11-13 ~19:25Z)

GOAL: review wave 112 (landscape, waterfalls, shores, towns, 9 km map, cars v2 pass 2, hero look v3) as a harsh player on a phone: render 25+ frames at 1600x720 (phone aspect) from the real game
camera (LOW and MED), OPEN each, write the 8 worst defects, FIX them in render-look-fix loops, test, perf gate if rendering changed.
Second critic (PLAY lens) works in the same tree: read each file again right before editing, small edits, never revert others.
MACHINE RULE LEARNED: ONE Godot render job at a time (each is ~4.7 GB; two of mine plus the other critic's got OOM-killed at the last frames). Scratch: .../scratchpad/crit (run_ls.sh, run_bot.sh, run_drive.sh).

STATUS (20:05Z): baseline renders A (landscape MED), B (7 towns LOW), C (highway/village LOW), D (bridges, falls MED), E (LOW checks + airport) done and OPENED (about 45 frames); fixes below are in the
tree and verified by frames unless marked "to verify"; F (drive out of the city, LOW) running.

DEFECTS (what / evidence / file / status)
 1 BRIDGE DECKS PITCH BLACK (every bridge incl. HARBOUR GATE, SUMMIT ROAD viaduct, PASS ROAD bridge): BridgeKit.road_ribbon wound its triangles counter-clockwise from above (back face, the engine flipped the
   normal, no sun) since wave 105; invisible while the asphalt was 0.085 albedo, black after wave 112 lightened it. FIXED scripts/world/bridge_kit.gd (index order of TerrainRoads.build_ribbon). Verified in frames E_low_001/002.
 2 HERO CAPE = FLAT BLACK BOARD in every frame from behind (owner round 2 "black rectangle patch on the hero"): FIXED tools/blender/herosuit/parts.py (cape 14 x 12 quads, folds, scalloped hem; rebuilt
   hero_suit.glb + 3 atlas textures with tools/blender/model_hero_suit.py, 10 s) + hero_body.gdshader kind 13 tint (plate colour * 0.42 + trim * 0.22 + cloth2 * 0.5: dark teal slate per suit). To verify in game at noon.
 3 SKY PASTED BUILDING RECTANGLES at dawn/dusk (hard-edged pink-brown block with a vertical edge over the sea): the 256x128 HDRI probes were read at full detail. FIXED assets/shaders/sky.gdshader
   (textureLod PROBE_BLUR 3.4, mip filter). Verified E_low_000 (smooth dawn sky).
 4 WATERFALL: sheet was a grey-blue streaked banner, pool a grey glary mirror, stream ribbons pale planks: FIXED (partly) assets/shaders/fall_water.gdshader (whiter sheet, pool roughness 0.16, darker ribbons).
   Verified E_low_005 (white water, foamy foot). Still: the cliff is a smooth clay slope (terrain), mist sprite at the lip.
 5 JUNCTION: SUMMIT ROAD starts as a hard-edged brown dirt patch on the PASS ROAD asphalt, its centre line crosses the highway: FIXED (to verify) terrain_road.gdshader junction_fade (dirt alpha + marks fade
   in over 20 m; bridge decks set 0).
 6 LOW TERRAIN CORDUROY: strata layer stretched into regular ripples over a whole mountain at LOW (no tri-planar): PATCHED (to verify) terrain.gdshader (noise warp + 0.45 share).
 7 NOT FIXED: old villages PINE HOLLOW / DUST WELLS still plain boxes next to the new towns (ids are wired into pads, missions, tests: not touched); palm fronds black wedges at LOD0 from below; tree LOD
   dither reads as a net at mid distance; river ends in hard rectangular slabs high in the mountains; kerb cars close to the camera at LOW are faceted.
 8 NOT MINE: translucent "BLACK MARKET DROP" label overlaps the compass in every street frame (city event label / HUD).

DONE (files)
- scripts/world/bridge_kit.gd (ribbon winding, junction_fade 0), assets/shaders/{sky,fall_water,terrain,terrain_road,hero_body}.gdshader, tools/blender/herosuit/parts.py (+ rebuilt assets/models/hero_suit.glb,
  assets/textures/hero_suit_{albedo,orm,normal}), tests/test_critic_look_fixes.gd (10 checks, PASS), tests/bot_critic_drive.gd (drive out of the city with script-frame spike log), tests/dev_critic_probe.gd.

NEXT
1. F drive frames (streaming, traffic, cars on the road, spikes). 2. Map screen + minimap bot, hero suits turntable + action, cars close up day/night. 3. Verify cape at noon, junction, LOW terrain in frames.
4. Run tests of every touched system (test_hero_look_v3, test_landscape_dressing, test_bridges*, test_outskirts_sites ...). 5. Perf gate PERF_CHECK=1 tools/perf_report.sh 0 1 2. 6. Contact sheets under
docs/shots/round6/critic_look_*.jpg (<= 12 files), delete scratch.

DECISIONS / APIs: terrain_road.gdshader has a new uniform `junction_fade` (1 on terrain ribbons, 0 on bridge decks). sky.gdshader: PROBE_BLUR const. Cape tint uses plate_col (suit palette).
TESTS AND PERF: tests/test_critic_look_fixes.gd PASS (10 checks). Perf gate not run yet.
OPEN PROBLEMS: see 7 and 8.
