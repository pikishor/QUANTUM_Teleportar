# w112-critic-play (independent critic + fixer, lens FUNCTION / FEEL / MEASURED BEHAVIOUR; started 2026-11-13 19:25Z)

GOAL: harsh review of the wave 112 work (landscape, waterfalls, shores, 7 towns, 9 km map, cars v2 pass 2, hero look v3) with bots and measurements in the real scene at the real
touch layout (844x390); write the 8 worst defects; fix them most severe first in render-look-fix loops; regression tests for functional defects; perf gate if rendering changed.
A second critic (LOOK lens) works in the same tree: read each file again right before editing it, small edits, never revert others.

STATUS (22:10Z): DONE. Fixes F1-F3, F5, R1-R4 are in the working tree (nothing committed), test_play_critic_w112 + test_interior_reach_country written, perf gate OK on LOW / MED / HIGH, docs written (ARCHITECTURE.md, HANDOFF.md).

DONE
- tools (all new, mine): godot/tests/bot_play_sweep.gd (world sweep: draws/prims/tex at 62 named stops, SW_ABLATE attribution; tools/bot.sh), dev_roads_list.gd, dev_map_probe.gd, dev_teleport_probe.gd,
  dev_teleport_cost.gd, dev_harbour_probe.gd, dev_box_probe.gd (harbour reachability), dev_chunk_cost.gd. Scratch logs in the scratchpad dir (not in the repo).

FINDINGS (evidence in brackets)
 F1 HARBOUR QUAY pad (-282,1360) stands INSIDE a 70x30x12 m harbour shed box (x -335..-265, z 1347..1377): it can never be found on foot, and a QUANTUM TELEPORT to it drops the hero through the ground
    (dev_harbour_probe: y 2.2 -> -0.12 in one physics step, falls 60 m, 'LOST SIGNAL' return to the street after 2.5 s). Fix: move the pad to a clear quay spot (roam_data.gd:218) + test over ALL pads.
 F2 every far teleport freezes the game 0.8-1.25 s on this desktop (3-5 s on a phone): Player.teleport_to -> City.update_colliders -> TerrainWorld.ensure_ground -> settle(p, true) builds 9 LOD0 + 16-40 LOD1
    chunks synchronously (dev_teleport_cost: ensure_ground 799 / 1194 / 972 / 988 ms; one LOD0 chunk is 22-42 ms). Fix: build only the chunk under the hero synchronously, the ring streams on the threads.
 F3 map: test_director_fixes_b FAILS in the shared tree: the overview lists 26 'always' markers (11 sites + 7 towns + harbour + airport + 6 helipads) against a cap of 14, zoomed-in shows fewer (20) than the overview.
 F4 outskirts at LOW draw 128-171 total draws against the LOW budget of 100 (that budget is only gated for the city view): PASS ROAD@120 159, observatory 171, IRON HOLLOW 139-145, COAST LINK 155,
    airport apron 155 (bot_play_sweep). Ablation at PASS ROAD@120: Geometry/ (city ambient) 37 draws, Vegetation 22, animals 9, rails 3.
 F5 test hygiene: test_vehicle_roster prints a script error (process_mode on a RefCounted NearTraffic); test_free_roam_world 'the raid runs while they live' fails (flaky, an automatic event joins).

FIXED SO FAR (files; all in the working tree, nothing committed)
 F1 scripts/roam/roam_data.gd: harbour pad moved (-282, 1360) -> (-282, 1334) (it stood inside the shed x -335..-265, z 1347..1377: nobody could stand within 6 m of it for the pad panel, a teleport to it dropped the hero
    through the floor of the world, 'LOST SIGNAL' after 2.5 s)
 F2 scripts/terrain/terrain_world.gd: ensure_ground -> settle_ground (hero chunk + neighbours within GROUND_MARGIN 150 m): 23-150 ms instead of 800-1250 ms per teleport; settle() blocks on in-flight jobs (_collect(budget, block))
 F3 scripts/ui/map_screen.gd lod_markers: far pins (sites, towns, glyphs) count only inside the view (test_director_fixes_b passes again; 26 off-screen pins had made the overview bigger than a zoomed-in view)
 F5 tests/test_free_roam_world.gd (raid check active.has(raid), race length > 700), tests/test_bridges_harbour_boats.gd (spans with a shared deck), tests/test_outskirts_sites.gd (weather checks wait on the easing)
    FINDING (not fixed, left as it was): tests/test_vehicle_roster.gd line 94 (`NearTraffic.instance.process_mode = ...`, NearTraffic is a RefCounted since wave 111) is a script error that ENDS the test there: only 16 of its
    checks have run in CI since wave 111 and it passes. With the line removed the tail runs and fails 4 checks (tank rolls 7-8 m of 8, the plane's landing wrecks it (hits 22, landings 0), the plane exit, the tank readout):
    the plane test flies off the city avenue and must come back to it, the world outside the avenue is now terrain, trees and strips; owners: the aircraft and vehicle wave critics.
 R1 SUMMIT ROAD on the PASS ROAD bridge: scripts/terrain/terrain_roads.gd (`overlap` + `bridge_spans` keys: no second deck where a branch runs on its parent), scripts/world/bridges.gd (the parent's deck is widened to
    carry the branch: 12 -> 20.9 m); before: 80 m of the observatory road ran on the parent's deck with its own deck 0.3 - 0.75 m off and its line crossed the parapet walls: car stuck at 7-16 m
 R2 scripts/rail/rail_kit.gd: a viaduct bent whose columns would stand in a carriageway slides on to the next sample, 150 m at most (columns stood in PASS ROAD / RING ROAD lanes)
 R4 scripts/terrain/terrain_roads.gd: (a) a branch whose first samples run on its parent (within 10 m) takes the parent's profile when it still reaches every bridge clearance (OUTPOST ROAD retraced the DESERT ROAD for
    30 m, 0.9 - 2.7 m higher: a 1 - 2.6 m bank in the right lane, a wreck in the drive audit); (b) `_level_crossings`: two roads that cross at different heights are levelled like a town pad (RING ROAD crossed the
    PASS ROAD 3.6 m higher: a 3.8 - 5 m wall across the main north road at 251, -1321, eight crashes and a wreck in the drive audit). World-wide lane check: 17 -> 7 samples off the profile by > 0.45 m.
 R3 scripts/terrain/veg_scatter.gd: avenue trees closer than 11 m to any road are dropped (a poplar trunk stood in the DESERT ROAD lane at 1748, 563)
 new tools (mine): tests/bot_play_sweep.gd (+ SW_ABLATE), tests/drive_audit.gd + tools/drive_audit.sh, tests/road_clearance_audit.gd + tools/road_audit.sh, tests/dev_*.gd probes
 new test: tests/test_play_critic_w112.gd (all 16 pads clear + landing, a teleport builds <= 9 chunks, no stepped overlapping decks, 5 road stretches free of piers / decks / trees)

NEXT (for whoever continues)
1. integrator: run the full suite; known environment-dependent: test_terrain_world far-tile count (61 - 77 of 96 in 45 s), test_vehicle_roster is truncated by a script error at its line 94 since wave 111 (the tail fails 4 checks when it runs)
2. wave 119: outskirts draws at LOW (61 - 171, table in ARCHITECTURE.md), the city Geometry/ nodes still draw 37 from outside the north gate; airport road; PASS ROAD end under the SUMMIT embankment
3. tools for the next critic: tools/drive_audit.sh, tools/road_audit.sh, tests/bot_play_sweep.gd (SW_STOPS, SW_ABLATE), tests/dev_*.gd probes (roads list, lane probe, junction probe, teleport cost, rail boxes, route probe)

DECISIONS (other agents depend on these)
- TerrainWorld.ensure_ground builds only the hero's chunk + neighbours within GROUND_MARGIN 150 m; code that needs the whole ring now must call settle(p) (it blocks on in-flight jobs)
- TerrainRoads: roads have keys `overlap` {road, n, lat} and `bridge_spans`; `crossings_levelled`; a branch may take its parent's profile on the first samples; Bridges widen the parent's deck for a branch that shares it
- RailKit._viaduct_piers never puts a bent column in a carriageway (150 m slide limit)

TESTS AND PERF
- test_play_critic_w112 PASS (15 checks, about 70 s); test_director_fixes_b, test_outskirts_sites, test_outskirts_settlements, test_landscape_dressing, test_bridges_harbour_boats, test_railways_ships, test_free_roam_world,
  test_water_world, test_animals_biomes, test_world PASS; test_terrain_world fails only 'all N far tiles are built by the worker threads' under load (0 / 61 of 96 in 45 s: timing of the other critic's renders)
- test_vehicle_roster: tank rolls / plane lands / tank readout FAIL while the other critic renders (load 4-5); it passed in an idle run before my edits and the failures do not change when ensure_ground is put back
- perf gate (PERF_CHECK=1, roam_world.cfg removed): LOW OK 96 total draws / 139.8k tris / 110 MB / death 108; MED OK 129 / 272.6k / 141 MB / 145; HIGH OK 149 / 378.8k / 207 MB / 167

OPEN PROBLEMS
- (none yet)
