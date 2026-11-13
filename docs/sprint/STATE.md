# Sprint state (kept current by the main session; the automatic digest is in docs/sprint/progress/)

Updated 2026-11-13 08:25Z.

## What happened
- 2026-11-12 22:55Z: the weekly usage limit was reached ("resets 4am UTC"). All sprint agents stopped: 59 of 60 failed with the limit message, only the cars second pass had finished. The container restarted at 08:12Z on 11-13. Nothing was lost.
- The run used about 2.0 million agent tokens and 1,213 tool calls in 5.1 hours at max effort before the limit hit.

## On main (tested, pushed)
- Wave 111 (cars v2, vehicle collisions, traffic density) plus the CI fixes: main = b343625, CI green (run 192), Android build run 44 succeeded:
  https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/43322670833 (artifact android-debug-apk, 289 MB; the wave 110 build was 284 MB).
- The CI fixes found a real game bug: a parked car beside a door could take the door's ENTER prompt away. Fixed with regression tests.

## Only in the working tree and on the backup branch claude/determined-bardeen-mvwr5u (233 files, untested as a whole)
- Cars second pass (DONE, not integrated): 43 defects fixed in 8 loops, near, kerb and road cars get the v2 look, real cars cost 3 draws instead of 10, its own perf gate was OK, audits pass. Files: docs/sprint/progress/auto_w112-cars-pass2.md.
- Landscape (w112-landscape): about 2 hours of work (trees, rocks, waterfall, shore, strips), partly done and untested: docs/sprint/progress/auto_w112-landscape.md.
- Not started: outskirts-map, hero-look, waves 113 to 121.
- The backup branch merges cleanly onto main b343625 (checked with git merge-tree, no conflicts). Local main (89a6298) is behind origin/main because the CI fixes were pushed from the watcher's clone.

## Next
- The owner chooses effort level and scope (the max-effort run used up the weekly allowance in about 5 hours). Then resume per docs/sprint/RESUME.md: startWave 112 with skipTags ["cars-pass2"], or a trimmed plan.
- Integration of the saved work: merge the backup branch onto origin/main, run the full suite, the perf gate on LOW, MED and HIGH and the visual check, then commit and push.
