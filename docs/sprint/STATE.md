# Sprint state (kept current by the main session; the automatic digest is in docs/sprint/progress/)

Updated 2026-11-13 15:55Z.

## What happened
- 2026-11-12 22:55Z: the usage limit was reached ("resets 4am UTC"). All sprint agents stopped (59 of 60 failed with the limit message, only the cars second pass had finished). Nothing was lost.
- 2026-11-13 09:11Z: the owner chose "max effort, as planned". Workflow wodc9atdz (script round6d_sprint.js, waves 112 to 121, every agent at max effort) was started. At 11:11Z wave 112 had two builders running (landscape, outskirts-map), hero-look queued, then the critic-fixers (look and play), the integrator and the CI watcher.
- The first max-effort run used about 2.0 million agent tokens and 1,213 tool calls in 5.1 hours before the limit hit. Expect the limit again after roughly 5 hours of agent work (about 14:00Z on 11-13).

## On main (tested, pushed): main = 2b4c37b, CI green
- Wave 111 (cars v2, vehicle collisions, traffic density) plus CI fixes. Android build: https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/43322670833
- Cars second pass (43 defects fixed; near, kerb and road cars with the v2 look; real cars cost 3 draws instead of 10) plus the alien separation fix (freed pack members). Android build: https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/43402151717 (artifact android-debug-apk, 289,853,261 bytes). The owner has not tested it yet.

## Only in the working tree and on the backup branch claude/determined-bardeen-mvwr5u (about 300 files; tested by the builders, not yet by an integrator)
- Landscape (w112-landscape) DONE 14:59Z: 9 tree species x 3 LODs, 11 terrain layers, 6 waterfalls, 7 airstrips, anchors, lazy staged wake. Perf gate OK on LOW, MED, HIGH.
- Outskirts-map (w112-outskirts-map) DONE 15:46Z: 9 km world, 7 towns, 19 country interiors, new roads, test_outskirts_settlements (390 checks). Perf gate OK on LOW, MED, HIGH.
- Known test issues for the integrator (full builder reports are in the workflow journal wf_7e2eb443-14b): test_terrain_world "all 80 far tiles are built by the worker threads" (slow under load), test_outskirts_settlements SALT QUAY (1 of 388 checks), test_free_roam_world raid (flaky), test_ambient, test_vehicle_roster process_mode message. The hero builder's files intermittently break compile (re-run tools/import.sh).
- Hero look (w112-hero-look): running since 14:59Z. Not started: wave 112 critic-fixers, integrator and CI watcher, and waves 113 to 121 (the full plan is docs/ROUND6.md).

## Next
- If the limit hits again: wait for the reset, then follow docs/sprint/RESUME.md (startWave 112, skipTags ["cars-pass2"], plus whatever the progress files say is already done).
- When wave 112 finishes: the integrator commits to main after the full suite, the perf gate (LOW, MED, HIGH) and visual QA. APK points: waves 113, 115, 116, 119, 121.
- Backup: godot/tools/wip_snapshot.sh. The 2-hour background loop ended at its time limit and is not restarted; snapshots now happen at every check-in (about every 100 minutes) and every time the Stop hook asks.
