# w112-critic-play (independent critic + fixer, lens FUNCTION / FEEL / MEASURED BEHAVIOUR; started 2026-11-13 19:25Z)

GOAL: harsh review of the wave 112 work (landscape, waterfalls, shores, 7 towns, 9 km map, cars v2 pass 2, hero look v3) with bots and measurements in the real scene at the real
touch layout (844x390); write the 8 worst defects; fix them most severe first in render-look-fix loops; regression tests for functional defects; perf gate if rendering changed.
A second critic (LOOK lens) works in the same tree: read each file again right before editing it, small edits, never revert others.

STATUS (20:55Z): fixes F1-F3, R1 (junction), R2 (viaduct piers), R3 (avenue tree) and F5 landed in the working tree; regression test + perf gate + docs still to do.

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

FIXED SO FAR (files)
 F1 scripts/roam/roam_data.gd (harbour pad moved to (-282, 1334))
 F2 scripts/terrain/terrain_world.gd: ensure_ground -> settle_ground (hero chunk + neighbours within GROUND_MARGIN 150 m, 23-150 ms instead of 800-1250 ms); settle() now blocks on in-flight jobs (_collect(budget, block))
 F3 scripts/ui/map_screen.gd lod_markers: far pins (sites, towns, glyphs) count only inside the view (test_director_fixes_b passes again)
 F5 tests/test_vehicle_roster.gd (process_mode line removed), tests/test_free_roam_world.gd (raid check uses active.has(raid); race length threshold 700 m)
 R1 SUMMIT ROAD / PASS ROAD junction: scripts/terrain/terrain_roads.gd (branch takes the parent's profile where it runs on it, `bridge_spans` key, SUMMIT ROAD branches at 1270 = end of the PASS ROAD deck),
    scripts/world/bridges.gd reads bridge_spans. Before: the branch ran 80 m on the parent's deck with a second deck 0.3-0.75 m off: a car was stuck at 7-16 m of the observatory road.
 R2 scripts/rail/rail_kit.gd: a viaduct bent whose columns would stand in a carriageway slides to the next sample (piers stood in PASS ROAD / RING ROAD lanes)
 R3 scripts/terrain/veg_scatter.gd: avenue trees closer than 11 m to any road are dropped (a poplar trunk stood in the DESERT ROAD lane at 1748, 563)
 audits (mine, new): tests/drive_audit.gd + tools/drive_audit.sh (real car, curvature-aware pilot, every road), tests/road_clearance_audit.gd + tools/road_audit.sh (car box in 3 lanes against every static body)

NEXT
1. tests/test_play_critic_w112.gd (all pads clear + landing, teleport builds <= 6 chunks, road stretches clear, no overlapping bridge decks), run neighbours (terrain_world, outskirts_sites, landscape, bridges_harbour, free_roam, vehicle roster when the machine is quiet)
2. perf gate PERF_CHECK=1 tools/perf_report.sh 0 1 2 (remove user://roam_world.cfg first), frame spikes at car speed (FOREST ROAD 452 ms @502 m, PASS ROAD 276 ms @55 m: repeat in real time, PerfTimers)
3. towns: houses/props/cars inside buildings audit, interiors reachability for country types, settlement script errors; hero suit screen at 844x390; outskirts LOW draws (F4)
4. docs: ARCHITECTURE.md + HANDOFF.md short wave-112-critic-play sections

DECISIONS (other agents depend on these)
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- (none yet)
