extends RefCounted
## Dev helper (not a test): how long City takes to build and what its camera windows cost. tools/test.sh tests/dev_world_timing.gd


func run(host: Node) -> void:
	var scene := load("res://scenes/world.tscn") as PackedScene
	var t0 := Time.get_ticks_usec()
	var city := scene.instantiate() as City
	var t1 := Time.get_ticks_usec()
	host.add_child(city)
	var t2 := Time.get_ticks_usec()
	print("instantiate %.1f ms, _ready (build everything) %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	await TestLib.frames(host, 2)
	print("static memory after build: %.1f MB, objects %d" % [OS.get_static_memory_usage() / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	# camera windows (city_stream.gd): a full rebuild of every family (first frame, quality change, teleport) ...
	var worst := 0.0
	for level in [0, 1, 2]:
		city.set_quality(level)
		var a := Time.get_ticks_usec()
		city.update_streaming(Vector2(-30.0, 4.0), true)
		worst = maxf(worst, (Time.get_ticks_usec() - a) / 1000.0)
	print("full window rebuild (all %d families): up to %.2f ms" % [city.stream_families().size(), worst])
	# ... and the cost of driving 600 m along the avenue at one update per metre (what _process does each frame)
	city.set_quality(1)
	var total := 0.0
	var peak := 0.0
	for step in 600:
		var a := Time.get_ticks_usec()
		city.update_streaming(Vector2(-300.0 + float(step), 4.0), false)
		var dt := (Time.get_ticks_usec() - a) / 1000.0
		total += dt
		peak = maxf(peak, dt)
	print("driving 600 m (1 update per metre): %.3f ms per update on average, %.2f ms worst frame" % [total / 600.0, peak])
