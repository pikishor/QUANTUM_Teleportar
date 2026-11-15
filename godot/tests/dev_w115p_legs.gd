extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): can a player cross from one tutorial roof to the next with the INTENDED technique (run off the roof edge, hold SNAKE in the air, steer with the camera)?
## Every leg: the hero stands 4 m inside the roof edge that faces the next ring, runs off it (stick forward), SNAKE is held while he is in the air, the camera yaw steers toward the ring like a thumb.
## Reported per leg: reached the ring (the runner's own test: 9 m / 12 m horizontal, 6 m vertical), seconds, swings, the street touched, lowest point; summary per difficulty.
## env LG_N (missions, default 10), LG_DIFF (0..3, default 0), LG_SECS (budget per leg, default 40), LG_K (time scale, default 4), LG_SEED, LG_FLY=1 (allow FLY when falling with no snake), LG_LEGS ("ab,bc,cd")
## Run: tools/test.sh does not wait this long: scratchpad/run_probe.sh tests/dev_w115p_legs.gd 560 "^LG"

const TIMEOUT_SECONDS := 560.0

var host: Node
var p: Player
var sn: SnakeTraversal


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _edge_toward(roof: Vector3, goal: Vector3) -> Vector3:
	var space := p.get_world_3d().direct_space_state
	var dir := Vector3(goal.x - roof.x, 0.0, goal.z - roof.z).normalized()
	var pos := roof
	var last_ok := roof
	for i in 80:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.5, 0), pos + Vector3(0, -3.0, 0), Game.L_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return last_ok
		var hp: Vector3 = hit["position"]
		if absf(hp.y - roof.y) > 3.0:
			return last_ok
		last_ok = Vector3(pos.x, hp.y, pos.z)
		pos += dir
	return last_ok


func _in_ring(pos: Vector3, c: Vector3, r: float) -> bool:
	return Vector2(pos.x - c.x, pos.z - c.z).length() < r and absf(pos.y - c.y) < 6.0


func _leg(a: Vector3, b: Vector3, rad: float, secs: float, allow_fly: bool) -> Dictionary:
	sn.cancel()
	Input.action_release(&"snake")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	Input.action_release(&"fly")
	var dirh := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var edge := _edge_toward(Vector3(a.x, a.y - 0.6, a.z), b)
	var start := edge - dirh * 4.0 + Vector3(0.0, 0.15, 0.0)
	p.invuln = 0.0
	p.teleport_to(start)
	await frames(10)
	sn.energy = SnakePower.max_energy()
	var yaw := PlayerUtil.yaw_of(dirh)
	p.camera_rig.reset_view(yaw, 0.15)
	p.yaw = yaw
	await frames(6)
	var s0 := sn.swings
	var z0 := sn.zips
	var f0 := sn.flights
	var trace: Array[String] = []
	var t_ref := [0.0]
	var on_ev := func(id: StringName) -> void: trace.append("%.1f:%s" % [t_ref[0], str(id)])
	sn.event.connect(on_ev)
	var t := 0.0
	var ground_t := 0.0
	var min_y := 1.0e9
	var reached := false
	var fly_used := false
	var air_t := 0.0
	var no_snake_air := 0.0
	var started_run := false
	var energy_min := 100.0
	var chain_max := 0
	var res := {}
	var clock0 := sn.time
	var last_clock := sn.time
	var frame_dt := 0.0
	while t < secs:
		await frames(1)
		t = sn.time - clock0
		frame_dt = sn.time - last_clock
		last_clock = sn.time
		if frame_dt <= 0.0:
			continue
		t_ref[0] = t
		var pos := p.global_position
		min_y = minf(min_y, pos.y)
		energy_min = minf(energy_min, sn.energy)
		chain_max = maxi(chain_max, sn.swing.chain)
		if _in_ring(pos, b, rad):
			reached = true
			break
		var to_b := Vector3(b.x - pos.x, 0.0, b.z - pos.z)
		var want_yaw := PlayerUtil.yaw_of(to_b.normalized()) if to_b.length() > 1.0 else yaw
		p.camera_rig.yaw = PlayerUtil.damp_angle(p.camera_rig.yaw, want_yaw, 3.5, frame_dt)
		var on_floor := p.is_on_floor()
		if sn.mode == SnakeTraversal.Mode.FLY:
			p.camera_rig.pitch = clampf(atan2(b.y - pos.y, to_b.length()), -0.7, 0.7)
			Input.action_press(&"move_forward")
			Input.action_release(&"snake")
			if to_b.length() < 25.0 and pos.y > b.y - 3.0:
				Input.action_press(&"fly")                                 # LAND when over the ring
			else:
				Input.action_release(&"fly")
			continue
		Input.action_release(&"fly")
		if on_floor:
			ground_t += frame_dt
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
			if ground_t > 6.0 and not started_run:
				break
			if sn.mode == SnakeTraversal.Mode.NONE and air_t > 0.0:
				# back on the street / a roof after the chain ended
				Input.action_release(&"snake")
				if pos.y < b.y - 12.0 and ground_t > 1.0:
					break                                               # on the street far below the goal: the leg failed
		else:
			started_run = true
			air_t += frame_dt
			p.camera_rig.pitch = lerpf(p.camera_rig.pitch, 0.22, 0.2)
			Input.action_press(&"move_forward")
			if air_t > float(OS.get_environment("LG_REACT")) if OS.get_environment("LG_REACT") != "" else air_t > 0.25:
				Input.action_press(&"snake")
			if sn.mode == SnakeTraversal.Mode.NONE:
				no_snake_air += frame_dt
				if allow_fly and no_snake_air > 0.8 and p.velocity.y < -6.0:
					Input.action_press(&"fly")
					fly_used = true
					no_snake_air = 0.0
			else:
				no_snake_air = 0.0
	Input.action_release(&"snake")
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	Input.action_release(&"fly")
	sn.event.disconnect(on_ev)
	res = {"trace": " ".join(trace.slice(0, 40)), "flights2": sn.flights - f0, "reached": reached, "t": t, "swings": sn.swings - s0, "zips": sn.zips - z0, "flights": sn.flights - f0, "ground": ground_t, "min_y": min_y, "chain": chain_max, "energy_min": energy_min, "end_dist": Vector2(p.global_position.x - b.x, p.global_position.z - b.z).length(), "end_y": p.global_position.y, "fly_used": fly_used}
	return res


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = true
	var city := Game.world as City
	city.collision_chunks().activate_all()
	var k := float(int(OS.get_environment("LG_K")) if OS.get_environment("LG_K") != "" else 4)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	var n := int(OS.get_environment("LG_N")) if OS.get_environment("LG_N") != "" else 10
	var diff := int(OS.get_environment("LG_DIFF")) if OS.get_environment("LG_DIFF") != "" else 0
	var secs := float(OS.get_environment("LG_SECS")) if OS.get_environment("LG_SECS") != "" else 40.0
	var allow_fly := OS.get_environment("LG_FLY") == "1"
	var legs_s := OS.get_environment("LG_LEGS") if OS.get_environment("LG_LEGS") != "" else "ab,bc,cd"
	seed(int(OS.get_environment("LG_SEED")) if OS.get_environment("LG_SEED") != "" else 3)
	Difficulty.set_mode(diff)
	SnakeTraversal.assist = true
	var board := (Game.missions as Missions).board
	await frames(5)
	print("LG start: missions %d difficulty %d legs %s budget %.0f s fly %s k %.0f" % [n, diff, legs_s, secs, str(allow_fly), k])
	var tot := {"ab": [0, 0], "bc": [0, 0], "cd": [0, 0]}
	var swings_ok: Array[int] = []
	for mi in n:
		var origin := city.random_core_road_point()
		var rec := board.build(&"swing_city", origin)
		if rec.is_empty():
			continue
		var steps: Array = rec["steps"]
		var pa: Vector3 = steps[0]["pos"]
		var pb: Vector3 = steps[1]["pos"]
		var pc: Vector3 = steps[2]["pos"]
		var pd: Vector3 = steps[3]["pos"]
		var rb := float(steps[1]["radius"])
		var rc := float(steps[2]["radius"])
		var rd := float(steps[3]["radius"])
		var legs := {"ab": [pa, pb, rb], "bc": [pb, pc, rc], "cd": [pc, pd, rd]}
		for key in legs_s.split(",", false):
			var lg: Array = legs[key]
			var a: Vector3 = lg[0]
			var b: Vector3 = lg[1]
			var r := await _leg(a, b, float(lg[2]), secs, allow_fly)
			(tot[key] as Array)[1] += 1
			if bool(r["reached"]):
				(tot[key] as Array)[0] += 1
				swings_ok.append(int(r["swings"]))
			print("LG mission %d leg %s: %s  dist %.0f m, rise %+.0f m, t %.1f s, swings %d, chain %d, ground %.1f s, min y %.0f, end %.0f m from the ring (y %.0f), energy min %.0f, fly %s flights %d\n    trace %s" % [mi, key, "REACHED" if bool(r["reached"]) else "no", Vector2(b.x - a.x, b.z - a.z).length(), b.y - a.y, float(r["t"]), int(r["swings"]), int(r["chain"]), float(r["ground"]), float(r["min_y"]), float(r["end_dist"]), float(r["end_y"]), float(r["energy_min"]), str(r["fly_used"]), int(r["flights2"]), str(r["trace"])])
	var line := ""
	for key in tot:
		var v: Array = tot[key]
		line += " %s %d/%d" % [key, v[0], v[1]]
	print("LG SUMMARY difficulty %d (fly %s):%s" % [diff, str(allow_fly), line])
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)
