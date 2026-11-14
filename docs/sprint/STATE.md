# Sprint state (kept current by the main session; the automatic digest is in docs/sprint/progress/)

Updated 2026-11-14 00:55Z.

## What happened
- 2026-11-12 22:55Z: the usage limit was reached ("resets 4am UTC"). All sprint agents stopped (59 of 60 failed with the limit message, only the cars second pass had finished). Nothing was lost.
- 2026-11-13 09:11Z: the owner chose "max effort, as planned". Workflow wodc9atdz (script round6d_sprint.js) ran wave 112: builders landscape (done 14:59Z), outskirts-map (15:46Z), hero-look (19:24Z), then the critic-fixers look (21:17Z) and play (22:12Z).
- OWNER DECISION 2026-11-13 ~21:00Z: STOP AFTER WAVE 116 so the owner can test (docs/ROUND6.md has the numbers). Waves 117 to 121 stay planned and start only when the owner says so.
- 22:13Z SWITCH (zero loss): both critics had finished, their reports and the builders' reports were copied to docs/sprint/progress/reports_w112.md, the old workflow wodc9atdz was stopped one minute after its integrator had started, and the new run started: task w7c2hb60e, run wf_0cbd62eb-bea, script scratchpad/round6e_sprint.js (= docs/sprint/round6_sprint.js), args {"startWave":112,"skipTags":["cars-pass2","landscape","outskirts-map","hero-look"],"skipCritic":true,"reports":{...pointers into reports_w112.md...}}. It stops by itself after wave 116 (args.stopAfter, default 116). Do NOT stop it and do not start a second workflow.
- 23:32Z the wave 112 integrator pushed wave 112 to main: fb49813 (352 files). Full suite 256 tests: 247 pass, 7 flaky (named in docs/HANDOFF.md "Wave 112 integration"), 2 first-run fails fixed and re-run green. Perf gate OK on LOW, MED and HIGH (death spike 108, 144, 167 draws against the limits 115, 150, 170; textures 110, 141, 207 MB against 200, 260, 360). full_bot PASS, visual_qa 27/27.

## On main (tested, pushed): main = 18d874e = wave 112 (fb49813, 23:32Z) + CI fix of test_ambient (00:11Z, by the CI watcher: the node count ran while the 9 km terrain still streamed; the CI of fb49813 had that one red job). CI run 43532431658 (on 18d874e) finished green at 00:37Z.
- Wave 111 (cars v2, vehicle collisions, traffic density) plus CI fixes. Android build: https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/43322670833
- Cars second pass (43 defects fixed; near, kerb and road cars with the v2 look; real cars cost 3 draws instead of 10) plus the alien separation fix. Android build: https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/43402151717 (artifact android-debug-apk, 289,853,261 bytes). The owner has not tested it yet.
- Wave 112 (fb49813): landscape (9 tree species x 3 LODs, 11 terrain layers, 6 waterfalls, 7 airstrips), outskirts (9 km world, 7 roads, 7 towns with 19 country interiors, folk, pets, map pins), hero look v3 (armour kit, 6 suits, glow, rebuilt SUIT screen with a live turntable), the critics' fixes (every bridge deck was a back face = black, the cape board, sky probes, waterfall tint, branch road junction, fast travel freeze, road crossings, harbour pad). Android build of main 18d874e (wave 112 plus the CI fix; includes the cars second pass too): https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/43535415234 (artifact android-debug-apk, 299,429,314 bytes, built 00:37-00:49Z on 2026-11-14; CI run 43532431658 on 18d874e was green, all 4 shards). The owner has not tested it yet.

## Running now (00:40Z on 2026-11-14)
- SERVER RESTART at 00:29Z: the container restarted and stopped the run wf_0cbd62eb-bea (task w7c2hb60e, with the CI watcher agent w112-ci-apk and the wave 113 roster builder in the middle of their work) and the watcher bsekjdmte. Files on disk survived. At 00:31Z the sprint was started again from wave 113: task ws0et84n0, run wf_4e87485e-db7, script scratchpad/round6e_sprint.js, args {"startWave":113} (the builders get the RESTART NOTICE and continue from docs/sprint/progress/w113-*.md and the files in the tree). It stops by itself after wave 116. Do NOT stop it and do not start a second workflow. After a further restart: startWave = the first wave not on main, skipTags = builders whose progress notes say DONE (docs/sprint/RESUME.md).
- Wave 112 extra APK: DONE 00:49Z (script scratchpad/ci_then_apk.sh, no agent): run 43535415234, link in the section above.
- Do NOT push to main while a CI run is in progress: the CI has a concurrency group with cancel-in-progress, so a push cancels the run that is waited for. Docs-only pushes wait until the script has finished. Snapshots to the backup branch are fine.
- Next check-in: send_later trig_01B8CczcL3RvBjPCEKbR4iDN fires about 02:06Z (its prompt was updated for the new run).

## Open follow-ups from the wave 112 integrator (details in docs/HANDOFF.md, "Wave 112 integration")
- test_vehicle_roster stops at its line 94 (NearTraffic.instance.process_mode, NearTraffic is a RefCounted since wave 111): only the data checks run while it says PASS. With the line fixed 79 checks pass and 4 fail (tank rolls, plane lands and brakes, plane hero gets out, tank readout names cannon and coax). Wave 113 (tank, vehicle damage) and wave 116 (planes) should fix the line and the four checks together.
- Visual QA has no outskirts frames: add spots (coast, forest road, a town street, a waterfall) to tests/bot_visual_qa.gd.
- Frames: wide empty night plazas, QUANTUM CORES 0 / 6 banner on free frames, boss frame CONTRACT FAILED ABANDONED over the objective line, the hero's cloak from behind reads as a stiff grey panel.
- test_audio (tests/test_audio.gd:90) and test_campaign_runner (:980) log script errors in untouched areas.

## Plan
- Waves 113 (weapons roster 200+, blast arsenal, damage, enemy looks; APK), 114 (weapon art and screens), 115 (quantum snakes; APK), 116 (aircraft roster, interiors; APK), then the run ends. APK points: wave 112 (extra), 113, 115, 116.
- Waves 117 to 121 only if the owner says so: start with {"startWave":117,"stopAfter":121} (docs/sprint/RESUME.md).
- If the usage limit hits again: wait for the reset, then follow docs/sprint/RESUME.md (startWave = the first wave not on main; skipTags = the builders whose progress notes say done).
- Backup: godot/tools/wip_snapshot.sh at every check-in and every time the Stop hook asks. The 2-hour background backup loop is not restarted.
