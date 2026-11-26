# w124-fps (done)

agent id acc2959237c01c64c, 23 events, first activity 2026-11-26T04:31:54.005Z, last activity 2026-11-26T04:32:11.404Z

## Final report

w124-fps report: only partly done. This session made one change. The frame-rate work was not started. Done: - Node limit raised as the owner asked. In godot/tests/test_integration.gd line 127, the check is now `nodes < 7000` instead of `nodes < 3000`. The message now says the limit is owner-set at 7000 and was raised from 3000 in wave 124. No other limit was touched. - Not yet checked: test_integration has not been run since the edit. - Progress log created at /home/user/QUANTUM_Teleportar/docs/sprint/progress/w124-fps.md. Step 1 is marked done and the remaining steps are listed so the next agent can pick up from there. Not done (still open, in order): 1. Measurement probe godot/tests/dev_w124_probe.gd: draw calls, triangles, lights and shadows, and script time per system, on foot, driving and in flight over the city and outskirts. None of this has been measured, so there are no top-cost numbers. 2. Fixes for the flight drop: view distance, LOD and impostors at altitude, culling street detail and interiors from the air, throttling traffic and pedestrians by distance, shadow distance at altitude. 3. Fixes on foot: merging draws, distance-throttling _process, cutting per-frame allocations. 4. Permanent test godot/tests/test_fps_w124.gd, with each check shown failing on the old code first. 5. Before/after numbers for every tier, on foot and in flight. There are none yet. 6. Final PERF_CHECK=1 tools/perf_report.sh 0 1 2 run. Not run, so there are no perf lines for LOW, MED or HIGH. Not in this task's scope: finishing plan line 123, and demo-mode "god mode" (every weapon and mission selectable) from the owner's request. Both still need an owner. Files touched: - /home/user/QUANTUM_Teleportar/godot/tests/test_integration.gd (line 127 only) - /home/user/QUANTUM_Teleportar/docs/sprint/progress/w124-fps.md (new) No commits, no pushes. Disk has 11 GB free.

## Last notes of the agent

- (none)

## Recent steps (last 40)

- 04:31:57 cd /home/user/QUANTUM_Teleportar; cat docs/sprint/progress/w124-fps.md 2>/dev/null | tail -20; grep -n "3000" godot/tests/test_integration.gd; df -h / | tail -1
- 04:32:03 cd /home/user/QUANTUM_Teleportar; sed -i '127s/nodes < 3000, "the composed game stays small: %d nodes (/nodes < 7000, "the composed game stays under the owner-set limi...
- 04:32:11 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- (none)
