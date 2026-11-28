# w129-machanim (done)

agent id a5e476072013f2847, 470 events, first activity 2026-11-28T03:10:33.361Z, last activity 2026-11-28T04:44:37.459Z

## Final report

w129-machanim report. Log: docs/sprint/progress/w129-machanim.md. No commits. What I fixed, and the check that proves each. The new test tests/test_machanim_w129.gd uses real touches on main.tscn with the phone-only layers on. It passes 36/36. With W129_OLD=1 it fails 25/36: all 25 checks marked [old fails] fail, and the 11 boarding/flying checks pass. - **AWACS showing only its wheels:** caused by Godot's visibility-range hysteresis. A newly spawned plane drew neither Body nor LOD1 between 39 and 45 m. Cars had the same 6 m gap. Fix: MachAnim.lod_margin sets the margin to 0. Check: gap 6.0 m → 0.0 m for AWACS, heli and sedan. Frames confirm it at 44 m. - **Tail rotor vanished at full spin:** it had no blur disc. It now has one. The main rotor gets a streaked blur disc, blades that cone and flap, cyclic tilt, skid flex on touchdown, and the wash now blows outward. Each has its own check. - **Planes:** new PlaneRig (skinned Detail, so no new draw calls). Ailerons, elevators, rudder and flaps move with the stick, and the gear folds away with its doors after take-off. Also: nav and strobe lights at night, jet heat glow and afterburner, and wingtip vortices and contrails. All checked by touch. - **Tanks:** barrel recoil and hull rock, muzzle flash, blast smoke, ground dust, track dust and exhaust. - **Cars:** tail-pipe exhaust. Parked engines do not smoke. - **Wrecks:** a wreck burns (flames and a black column), then smoulders. - **Old jet and cargo models:** new nose leg, tail wheel removed. - **Pale squares round every smoke puff (blasts included):** the fog colour was being added over the whole quad. Fix: blast_cloud shader fog_disabled plus a distance fade. Frames checked: AWACS, three helis, fighter and narrowbody (day and night), tank, car, both old jets, burning wrecks. Found, not fixed: - Between 42 and 70 m a deflected control surface shows twice, because LOD1 keeps the surface fixed. - The bot frames don't show vortices or contrails clearly. The check only counts trail segments. - Helicopters have no nav lights. - tests/test_helis_w125.gd timed out once and missed one walk-up while the machine load was 11. The affected kinds pass alone, with and without my change. - Headless runs print a harmless "material is null" message (dummy renderer). Files: - New: scripts/vehicles/mach_anim.gd, scripts/vehicles/plane_rig.gd, 5 shaders (rotor_disc, rotor_blade, nav_lights, jet_flame, contrail), tests/test_machanim_w129.gd, tests/bot_w129.gd, tests/probe_w129.gd. - Hooks in: plane_models, heli_models, vehicle_visual, vehicle_craft, aircraft_flight, car_v2, vehicle.gd, vehicle_manager, vehicle_weapons, blast_fx, blast_cloud.gdshader. - Ran tools/import.sh. w129-tankmis edits vehicle.gd and vehicle_weapons.gd at the same time; my changes there are single-line hooks. Other tests: airlook_w128, airport_aircraft, blastfx_w128 and tanks_w127 pass. Perf (final run, PERF_CHECK=1): no limit raised, MED triangles still under 280k. | Tier | Draws | Death | Pri...

## Last notes of the agent

- 03:17:52 Now write my look bot, starting with the AWACS mode.
- 03:24:50 Now let me add a low-priority machine puff path to the shared BlastFx cloud (no new draw call).
- 03:25:07 Now the shaders: rotor blur disc, rotor blades (coning/flap), nav lights, and contrail ribbon.
- 03:32:26 Now the PlaneModels changes: rig collector, sub-panels, cut wings/tail, retractable gear.
- 03:35:16 Now the plane frames mode in the bot.
- 03:50:04 Now bot modes for tank, car, GLB jets, night lights, wrecks, contrails.

## Recent steps (last 40)

- 03:59:32 Disable fog on premul/additive shaders
- 03:59:47 Rerender misc frames after fog fix
- 04:03:08 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/mi4.jpg
- 04:03:22 Tune car exhaust; start night render
- 04:03:40 Read Fingers helper
- 04:03:44 See how plane test flies by finger
- 04:03:46 Read plane takeoff by finger
- 04:03:48 Read plane test setup helpers
- 04:04:54 /home/user/QUANTUM_Teleportar/godot/tests/test_machanim_w129.gd
- 04:05:00 Check night render
- 04:05:02 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/ni1.jpg
- 04:05:07 Crop night narrowbody
- 04:05:09 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/crop3.png
- 04:05:18 Bigger nav lights; run the new test
- 04:06:22 Fix lambda capture and flex strength; rerun test
- 04:07:12 Count passes new; run old-code variant
- 04:08:46 Rerun new and show non-ok output
- 04:09:39 Find material null error backtrace
- 04:09:46 Find tests depending on things I changed
- 04:09:48 See how other tests use Burner/Detail
- 04:09:50 See airport test burner check
- 04:09:57 Keep Burner part name mapped to new flame
- 04:10:03 Run airlook and airport aircraft tests
- 04:12:02 Run heli, blastfx and tank tests
- 04:14:26 Show results of heli and tank tests
- 04:14:30 Check heli test progress and load
- 04:14:34 Rerun heli test alone
- 04:16:33 Check heli test env switches
- 04:16:38 Run fire and trainer heli kinds new vs old
- 04:18:06 Update log; render heli and night frames
- 04:19:52 Render heli and night frames sequentially
- 04:23:01 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/he2.jpg
- 04:23:05 Read perf_report usage
- 04:23:08 Run the perf gate (1st of max 2)
- 04:31:41 No smoke from parked engines; rerun test
- 04:32:38 Render fighter frames once more
- 04:34:54 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/pl3.jpg
- 04:35:01 Wider vortices; final perf gate run
- 04:43:37 Final test run, disk check, log update
- 04:44:37 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/bot_w129.gd
- godot/scripts/vehicles/mach_anim.gd
- godot/scripts/vehicles/plane_rig.gd
- godot/tests/test_machanim_w129.gd
