# w127-ci-apk (running)

agent id acb736ae8541e5916, 217 events, first activity 2026-11-27T10:57:39.261Z, last activity 2026-11-27T12:05:50.249Z

## Last notes of the agent

- 10:58:01 Now waiting for the monitor.
- 10:58:04 Waiting for CI now.
- 11:28:09 Start progress notes and reproduce locally.
- 11:53:20 Log nearby vehicles on drops.

## Recent steps (last 40)

- 11:36:26 Read deck collider and hull setup
- 11:36:33 Dump mountain_track_4 bridge points
- 11:37:13 Read rest of _bounce and hull setup
- 11:37:47 Add drop-collision logging and loop until fail
- 11:43:27 Show first drops in failing and passing runs
- 11:43:35 List vehicle vars and functions
- 11:43:39 Find tank physics in vehicle_craft
- 11:43:42 Read tank drive code
- 11:43:48 Read finger stick helper and throttle source
- 11:43:50 Find throttle computation before _tank
- 11:43:52 Find caller of VehicleCraft.step
- 11:43:55 Read player drive input code
- 11:44:04 Log input axes on drops, loop until fail
- 11:48:22 Read TankArmour.speed_factor
- 11:48:32 Log tank armour state on drops, loop
- 11:50:19 Log per-tick collisions near the stall
- 11:53:15 Find vehicle list in manager
- 11:53:18 Read car-car collision pass
- 11:53:27 Log nearby vehicles on drops, loop
- 11:57:39 Check PathDriver height handling
- 11:57:41 Locate PathDriver and RoadTraffic
- 11:57:44 Check how promoted cars get their height
- 11:57:48 Find where road traffic heights are set
- 11:57:52 Read road traffic height sampling and promotion
- 11:57:57 Read RoadLanes.sample height source
- 11:58:05 Identify road 4 near the stall point
- 11:58:27 Trace nearby vehicle history, loop until fail
- 12:02:35 Check road traffic height updates and promoted spawn
- 12:02:38 Read spawn_promoted_path
- 12:02:45 Find _place_at callers and activate height
- 12:02:48 Read road traffic step and vehicle activate
- 12:02:54 Read rest of activate
- 12:03:05 List activate callers
- 12:03:16 See static switches in vehicle.gd
- 12:03:24 Apply deck-aware spawn height fix
- 12:03:52 /home/user/QUANTUM_Teleportar/godot/tests/test_w127_ci.gd
- 12:03:54 Check TestLib and runner conventions
- 12:04:18 Run new check with new and old code
- 12:05:06 Fix test sampling and rerun old and new
- 12:05:50 Run 36 loaded bridge runs with the fix

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/tests/test_w127_ci.gd
