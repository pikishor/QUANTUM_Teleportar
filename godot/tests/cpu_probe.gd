extends RefCounted
## Headless CPU frame-time probe (tools/cpu_frame.sh, not a CI test): the real main scene on the dummy renderer, one rendered frame = 1/30 game second (run with --fixed-fps 30,
## so the physics runs 2 ticks per frame like a phone at 30 FPS), the touch layout on, 4 aware enemies near the player who walks forward, the HUD and the minimap drawing.
## Prints `CPU frame ...` (wall time of the frames = script + physics + the dummy renderer's work, the part of a phone frame the GPU does not hide), the PerfTimers table
## and a `CPU RESULT` line. The draw submission and the GPU are NOT in these numbers: they only say what the CPU side of the game costs.
##   env CPU_NOTHROTTLE=1  no HUD redraw limits and no display-query cache (the numbers before this wave),  CPU_TIER=0|1|2  graphics tier (also --quality=N),  CPU_LOWPLUS=1  LOW+,  CPU_FRAMES=n  sampled frames (default 240),  CPU_ENEMIES=n  (default 4)

var host: Node


func run(h: Node) -> void:
	host = h
	Game.force_touch = true
	UiUtil.display_cache = OS.get_environment("CPU_NOTHROTTLE") == ""
	LowPlus.throttle = OS.get_environment("CPU_NOTHROTTLE") == ""         # CPU_NOTHROTTLE=1: the HUD, the touch layer and the minimap redraw every frame at every tier (the numbers before the redraw limits)
	var tier := int(OS.get_environment("CPU_TIER")) if OS.get_environment("CPU_TIER") != "" else Game.quality
	var frames_n := int(OS.get_environment("CPU_FRAMES")) if OS.get_environment("CPU_FRAMES") != "" else 240
	var enemies_n := int(OS.get_environment("CPU_ENEMIES")) if OS.get_environment("CPU_ENEMIES") != "" else 4
	seed(20260101)
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1
	Game.quality = tier
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	for i in 20:
		await host.get_tree().process_frame
	if OS.get_environment("CPU_LOWPLUS") != "" and Game.has_method(&"set_low_plus"):
		Game.call(&"set_low_plus", true)
	var p := Game.player as Player
	var em := Game.enemies as EnemyManager
	if p == null or em == null:
		printerr("CPU probe: no player or enemy manager")
		return
	em.patrol_groups().clear()
	em.clear()
	p.invuln = 1.0e6
	p.hp = p.max_hp
	p.teleport_to(Game.SPAWN)
	p.camera_rig.reset_view(-PI * 0.5, -0.1)
	p.yaw = -PI * 0.5
	var types: Array = [&"sentinel", &"operative", &"operative", &"sentinel", &"operative", &"striker"]
	for i in enemies_n:
		em.spawn(types[i % types.size()], Game.SPAWN + Vector3(14.0 + 3.0 * i, 0.0, -6.0 + 4.0 * i), true)
	Game.state = &"play"
	Input.action_press(&"move_forward")
	for i in 60:                                  # settle: shader compiles, pools, streaming
		await host.get_tree().process_frame
	PerfTimers.reset()
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in frames_n:
		await host.get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	Input.action_release(&"move_forward")
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	var avg := sum / float(times.size())
	var p95: float = times[int(times.size() * 0.95)]
	var low_plus := bool(Game.get(&"low_plus")) if Game.get(&"low_plus") != null else false
	print("CPU frame tier=%d low_plus=%s frames=%d avg=%.2f ms p50=%.2f p95=%.2f worst=%.2f" % [Game.quality, str(low_plus), times.size(), avg, times[times.size() / 2], p95, times[times.size() - 1]])
	print(PerfTimers.table())
	print("CPU RESULT tier=%d low_plus=%s avg_ms=%.2f p95_ms=%.2f timed_ms=%.2f nodes=%d" % [Game.quality, str(low_plus), avg, p95, PerfTimers.total_ms(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

