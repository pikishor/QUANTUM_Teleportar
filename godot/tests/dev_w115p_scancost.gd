extends RefCounted
## Dev probe (wave 115 PLAY critic): the CPU cost of one anchor search (what a phone pays every 0.09 s in an auto chain and every 0.25-0.4 s for the preview): 300 random spots over the city.
const TIMEOUT_SECONDS := 120.0
var host: Node

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	var p := Game.player as Player
	var sn := p.snake
	var city := Game.world as City
	city.collision_chunks().activate_all()
	TrafficField.bare_street()
	await TestLib.frames(host, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for mode in ["full", "wide", "quick", "zip", "wall"]:
		var times: Array[float] = []
		var rays_sum := 0
		var hits := 0
		for i in 300:
			var rp := city.random_core_road_point()
			var pos := rp + Vector3(0.0, rng.randf_range(2.0, 55.0), 0.0)
			p.global_position = pos
			p.velocity = Vector3(rng.randf_range(-20, 20), rng.randf_range(-15, 5), rng.randf_range(-20, 20))
			var yaw := rng.randf() * TAU
			p.camera_rig.yaw = yaw
			p.camera_rig.pitch = rng.randf_range(-0.2, 0.5)
			var head := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var aim := PlayerUtil.forward_of(yaw, p.camera_rig.pitch)
			var t0 := Time.get_ticks_usec()
			var r := {}
			match mode:
				"full": r = sn.anchors.find_swing(p, head, aim, SnakePower.range_m(), true)
				"wide": r = sn.anchors.find_swing(p, head, aim, SnakePower.range_m(), true, Vector3.INF, false, true)
				"quick": r = sn.anchors.find_swing(p, head, aim, SnakePower.range_m(), true, Vector3.INF, true)
				"zip": r = sn.anchors.find_zip(p, aim, SnakePower.range_m(), true)
				"wall": r = sn.anchors.find_wall(p, head, 1.15)
			times.append(float(Time.get_ticks_usec() - t0))
			rays_sum += sn.anchors.rays
			if not r.is_empty():
				hits += 1
		times.sort()
		var mean := 0.0
		for t in times:
			mean += t
		mean /= float(times.size())
		print("SC %-5s: mean %.0f us, median %.0f, p95 %.0f, max %.0f us | rays %.0f per search | found %d of 300" % [mode, mean, times[150], times[285], times[299], float(rays_sum) / 300.0, hits])
	main.queue_free()
	await TestLib.frames(host, 3)
