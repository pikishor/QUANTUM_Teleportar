# w112-landscape (builder notes; started 2026-11-12 ~21:00Z; first session stopped 22:55Z by the usage limit; restarted 2026-11-13 09:11Z; FINISHED 2026-11-13 ~14:50Z)

STATUS: done, report handed back. Nothing committed or pushed (the integrator does that). Details: godot/ARCHITECTURE.md "Landscape dressing", docs/HANDOFF.md "Wave 112: landscape".

GOAL: round 6 landscape pass: 6+ tree species by biome, 3 LODs + impostors in MultiMesh chunks (no per-tree nodes), undergrowth, waterfalls, shorelines, mountain detail,
tall anchors for the quantum snakes, 3+ flat drivable grass airstrips with windsocks, wind from the weather, rain-wet response; test; renders at 3 times of day.

BASELINE DEFECTS (round 5 build; owner r5_21..23): faceted low-poly trees + hexagon far LOD | shore a flat lilac plain, flat sea, no wet band | terrain navy-black in shade | road flat black |
bare ground, sparse spiky tufts | mountains smooth blobs | no anchors, strips or falls | wind not tied to the weather. All addressed (sheet docs/shots/round6/landscape_before_after.jpg).

DONE
- 9 species (oak birch poplar pine fir palm acacia dead alien) x LOD full / lite / mid + shared cross impostor, VegScatter by biome, avenues, ancient groves (35-42 m), fallen trunks, flowers, ferns,
  reeds, bushes, boulder fields, dune grass, pebbles + driftwood; ONE MultiMesh per species and LOD (36 slots at most); LandClimate wind from Weather.current; rain-wet in every new shader.
- Ground: 11 terrain layers (Poly Haven CC0 sand + forest ground), tan dry sand with ragged edge, wet band, foam line, strata (warped), scree, snow paled; dirt tracks (earth / scree), asphalt detail.
- LandscapeSites: 6 waterfalls + 7 grass airstrips FOUND by search (hints + full fallback), carved at the end of height_at (smooth S-profile face, plunge pool, trenches, graded strips).
  FallWorld (animated sheet, wet band, pool, streams, mist, spray, roar), StripWorld (hangar, windsock, markers), AnchorSites/AnchorWorld (14 turbines, 3 pylon lines, 3 masts, 2 quarry cranes,
  3 rock arches, falls' lips, harbour cranes, ancient trees): static `AnchorWorld.anchors_at(pos, r)` for the snakes.
- LAZY + STAGED: Landscape and VegetationWorld sleep until the hero is beyond 470 m of the city centre (the city start pays 0 draws, 0 triangles, no textures, 0 nodes); the wake is 22 steps
  of at most 27 ms (strip per step, anchors in 11 stages, a fall is built on approach in 26 ms); avenue trees are validated per cell on demand (warm 650 -> 11 ms); arch + mast hints.
- This session also: height_at carve early-out by a 128 m grid (carve was +20-50 % of a height_at call, now noise, identical heights), fall sheet normals from the grid (65 -> 13 ms),
  verge thinning (no hedge of tufts at the road edge), hint checks and a staged-wake check in the test.

TESTS (all in the real scene, user:// reset)
- tests/test_landscape_dressing.gd PASS (about 60 s, 203 checks: species, LODs, nodes, falls, strips, anchors, hints, wake steps, shores, groves, shaders, tiers, sleep at the city start).
- test_ambient PASS (it failed before because the landscape made nodes while the city lived), test_animals_biomes PASS, test_water_world PASS, test_outskirts_sites PASS (then its own 60 s watchdog line prints when the machine is loaded).
- NOT mine, seen failing: test_terrain_world "all 80 far tiles are built" (51 of 80 in 45 s under load), test_outskirts_settlements "SALT QUAY has parked cars",
  test_free_roam_world "the raid runs while they live" (flaky: passes 2 of 3 runs, also with my systems on).

PERF GATE (PERF_CHECK=1 tools/perf_report.sh 0 1 2, run by me, one tier per call):
 final tree, stale user://roam_world.cfg removed first:
 LOW  OK   draws 73 / total 95, 137.9 k triangles, tex 146 MB, death 108
 MED  OK   draws 97 / total 129, 277.2 k triangles, tex 177 MB, death 144
 HIGH OK   draws 113 / total 149, 386.3 k triangles, tex 242 MB, death 167
 earlier runs of the same landscape code (profile file present, before the others' last changes): MED OVER 288 454 triangles, HIGH OVER death 171 - both IDENTICAL with
 QT_NO_LANDSCAPE=1 QT_NO_VEGETATION=1 (288 454 / 136 draws / 177 MB and 171 / 155 / 242 MB), so not mine.
 Texture limits 200 / 260 / 360 MB untouched. Added assets 4.1 MB in the repo, about 6.5 MB in an APK (ASTC / ETC2 textures), no raw archive committed.

RENDERS (scratch frames deleted, 1600x720 phone aspect, bot tests/bot_landscape.gd): coast, forest road, mountain pass (SUMMIT ROAD switchbacks), waterfall at 06:00 / 12:00 / 19:00;
sheets docs/shots/round6/landscape_before_after.jpg and landscape_times_of_day.jpg. 8+ render-look-fix iterations (it1-it8, then i1-i5, r1-r3, f0-f4), each with frames opened and defects listed.

HONEST GAPS: no trails or road tunnels, no tree shadows on LOW and MED, sea foam is the old shader's, no map pins for falls and strips, sheet is streaky blue-white (not white water),
cliff face reads as smooth clay, the cut bank at the end of PASS ROAD is a flat brown slab, phone timing of the wake not measured.

DEFECTS OUTSIDE MY SCOPE: sky at dawn and dusk shows blocky cloud shapes; hero shadow is a hard dark parallelogram on dirt (ShadowProxy 16 k triangles also pushes MED over); settlement_kit /
settlement_world script errors in render logs ("Invalid access ... settlement_kit.gd:33/100, settlement_world.gd:306"); a mint-green creature blob on PASS ROAD s=900; observatory light cone.
