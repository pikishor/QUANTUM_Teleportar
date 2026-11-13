# w112-critic-play (independent critic + fixer, lens FUNCTION / FEEL / MEASURED BEHAVIOUR; started 2026-11-13 19:25Z)

GOAL: harsh review of the wave 112 work (landscape, waterfalls, shores, 7 towns, 9 km map, cars v2 pass 2, hero look v3) with bots and measurements in the real scene at the real
touch layout (844x390); write the 8 worst defects; fix them most severe first in render-look-fix loops; regression tests for functional defects; perf gate if rendering changed.
A second critic (LOOK lens) works in the same tree: read each file again right before editing it, small edits, never revert others.

STATUS (19:55Z): survey in progress; defects found so far listed under FINDINGS; no fix landed yet.

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

NEXT
1. Read ARCHITECTURE.md wave 112 sections + HANDOFF wave 112 notes, open owner_shots/round5 frames.
2. Run scripted play: drive out of the city (60 s), forest road, mountain pass, coast, highway, airport, towns, map screen, hero; measure frames, draws, texture memory.
3. Write the 8 defects here, then fix.

DECISIONS (other agents depend on these)
- (none yet)

TESTS AND PERF
- (none yet)

OPEN PROBLEMS
- (none yet)
