# w128-critic (done)

agent id a4990adbcfb806018, 525 events, first activity 2026-11-27T17:12:08.754Z, last activity 2026-11-27T18:21:23.793Z

## Final report

w128-critic report. Nothing committed or pushed. Log: docs/sprint/progress/w128-critic.md I fixed 4 defects. Each has a check in godot/tests/test_w128_critic.gd that failed on the old code first. The test now passes in full. 1. Near fireballs showed hard 20 px "staircase" squares. fx_flipbook.png was block-compressed (DXT1/ETC2). Its import is now lossless, about +4.7 MB of video memory, and the frames now look smooth. Check part fire: old FAIL (format 17). 2. The thermobaric blast still drew a crisp, see-through orange sphere. blast_fx.gd no longer draws it when the realistic look is on; the STILL POD keeps its bubble. Check part thermo: old FAIL (1 dome). 3. The seated pilot's shadow proxy kept casting shadows inside the cockpit. player_body.gd _seat_shadows now turns it off in the seat and back on at EXIT; SEAT_SHADOW_OLD=1 gives the old behaviour. Check part seat (finger on ENTER and EXIT): old FAIL. 4. test_anim_w128 failed under load (2 of 52 checks). The cast checks sampled after a fixed number of frames; they now use the gesture's own clock. Nothing was weakened: W128_OLD=1 still fails, and the new code passes. Found and not fixed: 5. A tank mission does not reach its normal end by finger. The probe got the drive order at 1584 m, the fight step started 1509 m away with the hero out of the tank, and the mission was unfinished after 423 s. Fixing it needs a mission redesign: a nearer field or staging point. 6. A parked AWACS sometimes draws only its wheels (2 of 4 runs, after a tanker in the same pooled vehicle). Headless node state is fine; cause unknown. Probe: tests/probe_w128_critic.gd. 7. The old jet and cargo models have a tail wheel and no nose leg. Each is a single mesh, so this needs new geometry. 8. Inside a vehicle on the airfield, draws exceed the budget: MED 155-171 (budget 140), LOW 116-131 (budget 100). - Not a defect, design limit: 36 weapons are carried and the swap button visits all of them. A carried weapon is reached by finger in 2 touches through its class wheel. There is no single carried ring. - Zebras and big cats wander on the airport apron. Seen working: all 23 helicopter kinds at MED (tail rotor at the back on the fin, proper tails), the plane kinds, the demo VEHICLES and AIRCRAFT tabs with god mode (finger test PASS), the hero seated in a helicopter, plane and tank. Files: scripts/combat/blast_fx.gd, scripts/player/player_body.gd, assets/textures/fx_flipbook.png.import, tests/test_anim_w128.gd; new: tests/test_w128_critic.gd, bot_w128_critic.gd, probe_w128_critic.gd. Tests passing: test_blastfx_w128, blast_table, blast_arsenal, vfx, anim_w128, arsenal_w128, w128_open (demo part). Perf, run once, no limit touched: - LOW: draws 72, total 94, death 109, OK - MED: draws 99, total 131, triangles 274k, death 146, OK - HIGH: draws 118, total 154, death 164, OK

## Last notes of the agent

- 17:12:43 Let me render all helicopter kinds side and rear-3/4 at MED quickly with the viewer, for a first close look.
- 17:13:11 Meanwhile I'll start the rest, and make contact sheets.
- 17:23:33 Meanwhile, let me read the arsenal changes and test.
- 17:24:32 Start blast render in background (10 types × 3 distances, MED) while I write the aircraft bot.
- 17:30:01 Now the test file, starting with the two blast parts.
- 18:00:48 Now add the seat-shadow check to my test, run it (should fail), then implement.

## Recent steps (last 40)

- 17:40:26 Log progress, wait for aircraft bot
- 17:50:31 Sheet plane front views so far
- 17:50:34 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ac4.jpg
- 17:50:41 Sheet awacs and tanker
- 17:50:43 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/awacs.jpg
- 17:50:50 Rerender awacs alone
- 17:52:09 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/aw/p_awacs_f3q_q1.png
- 17:52:17 Check for async or cached model builds
- 17:52:23 Look for body mesh/LOD manipulation
- 17:52:33 Reproduce awacs after tanker
- 17:53:52 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/aw2.jpg
- 17:54:01 Probe pooled vehicle body meshes
- 17:54:33 Probe body materials too
- 17:55:12 Render awacs near and far after tanker
- 17:56:28 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/aw3.jpg
- 17:56:37 Find code hiding vehicle bodies
- 17:56:42 Sheet blasts after fixes
- 17:56:44 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/bx2s.jpg
- 17:56:50 Start tank probe and in-vehicle perf runs
- 17:56:53 Run demo part of open-items test
- 17:57:34 Log progress and wait for LOW perf
- 18:00:26 Sheet seated hero frames
- 18:00:28 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/seat.jpg
- 18:00:34 Find seat handling in player body
- 18:00:37 Read seat enter/leave code
- 18:00:39 Read player body shadow setup
- 18:00:47 Read finger helper API
- 18:00:59 Add seat shadow check and run on old code
- 18:01:36 Implement seat shadow off; run new and old
- 18:02:28 Check ShadowProxy handling elsewhere
- 18:02:31 Check rig shadow toggle API
- 18:02:35 Check tank probe and perf logs
- 18:02:40 Check perf run and stuck skip in fight log
- 18:02:43 Run full critic test
- 18:03:10 Run related tests
- 18:04:25 Run blast arsenal and vfx tests, read MED perf
- 18:05:30 Log and wait for MED perf
- 18:15:15 Run perf gate once
- 18:21:12 Finalize progress log
- 18:21:23 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/bot_w128_critic.gd
- godot/tests/test_w128_critic.gd
