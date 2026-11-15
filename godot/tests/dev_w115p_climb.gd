extends RefCounted
## Dev probe (wave 115 PLAY critic): WALL CLIMB at scale. The hero stands 1 m from the facade of a random building (street level, facing the wall), taps SNAKE, holds the stick up for 16 s. Counted per building class and height:
## the climb started, the roof was reached (mantle), seconds to the roof, stuck (no progress for 2 s in the climb), embedded ticks, and where it ended.
## env CL_N (buildings, 40), CL_SEED, CL_K
const TIMEOUT_SECONDS := 400.0
var host: Node
var p: Player
var sn: SnakeTraversal
var _caps := CapsuleShape3D.new()
var _q := PhysicsShapeQueryParameters3D.new()

func frames(n: int) -> void:
	await TestLib.frames(host, n)

func _embedded() -> bool:
	_caps.radius = Player.CAPSULE_RADIUS - 0.1
	_caps.height = Player.CAPSULE_HEIGHT - 0.25
	_q.shape = _caps
	_q.transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(0.0, Player.CAPSULE_HEIGHT * 0.5, 0.0))
	_q.collision_mask = Game.L_WORLD
	_q.margin = 0.0
	return not p.get_world_3d().direct_space_state.intersect_shape(_q, 1).is_empty()

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
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
	Difficulty.set_mode(1)
	var city := Game.world as City
	city.collision_chunks().activate_all()
	var k := float(int(OS.get_environment("CL_K")) if OS.get_environment("CL_K") != "" else 3)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	await frames(6)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("CL_SEED")) if OS.get_environment("CL_SEED") != "" else 3
	var n := int(OS.get_environment("CL_N")) if OS.get_environment("CL_N") != "" else 40
	var space := p.get_world_3d().direct_space_state
	var started := 0
	var roofed := 0
	var stuck_n := 0
	var emb_total := 0
	var tried := 0
	var times: Array[float] = []
	var by_h := {}
	var fails: Array[String] = []
	var pool: Array[CityLayout.Lot] = []
	for l: CityLayout.Lot in city.layout.lots:
		if l.h >= 26.0 and CityLayout.is_core_block(l.block_i, l.block_j):
			pool.append(l)
	print("CL %d core lots of 26 m and more" % pool.size())
	for i in n:
		var lot: CityLayout.Lot = pool[rng.randi() % pool.size()]
		# a spot 1 m outside one of the four walls, at the middle of the wall
		var side := rng.randi() % 4
		var out := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][side] as Vector3
		var half := (lot.w if side < 2 else lot.d) * 0.5
		var pos := Vector3(lot.cx, 0.0, lot.cz) + out * (half + 1.15)
		# the wall must really be there and the spot free
		var wq := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, 1.0, 0) - out * 2.5, Game.L_WORLD)
		var wh := space.intersect_ray(wq)
		if wh.is_empty():
			continue
		tried += 1
		sn.cancel()
		sn.energy = 100.0
		p.invuln = 0.0
		p.teleport_to(pos)
		var yaw := PlayerUtil.yaw_of(-out)
		p.camera_rig.reset_view(yaw, 0.1)
		p.yaw = yaw
		await frames(20)
		var c0 := sn.climbs
		var m0 := sn.climb.mantles
		Input.action_press(&"snake")
		await frames(7)
		Input.action_release(&"snake")
		await frames(10)
		var climbing := sn.mode == SnakeTraversal.Mode.CLIMB
		if climbing:
			started += 1
		else:
			fails.append("lot h %.0f %s: the tap did not start a climb (mode %s, climbs %d)" % [lot.h, str(wh["position"]), sn.mode_name(), sn.climbs - c0])
			continue
		Input.action_press(&"move_forward")
		var t0 := sn.time
		var best_y := p.global_position.y
		var last_progress := sn.time
		var roof_t := -1.0
		var stuck := false
		var emb := 0
		while sn.time - t0 < 16.0:
			await frames(1)
			if _embedded():
				emb += 1
			if p.global_position.y > best_y + 0.3:
				best_y = p.global_position.y
				last_progress = sn.time
			if sn.climb.mantles > m0 and roof_t < 0.0:
				roof_t = sn.time - t0
			if roof_t >= 0.0 and sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor():
				break
			if sn.mode == SnakeTraversal.Mode.CLIMB and sn.time - last_progress > 2.5:
				stuck = true
				break
			if sn.mode == SnakeTraversal.Mode.NONE and roof_t < 0.0 and sn.time - t0 > 1.0:
				break
		Input.action_release(&"move_forward")
		emb_total += emb
		var rooftop := roof_t >= 0.0
		if rooftop:
			roofed += 1
			times.append(roof_t)
		if stuck:
			stuck_n += 1
		var key := "h%.0f" % lot.h
		var rec: Array = by_h.get(key, [0, 0])
		rec[0] += 1
		rec[1] += 1 if rooftop else 0
		by_h[key] = rec
		if not rooftop:
			fails.append("lot h %.0f at %s: no roof (%s, best y %.1f of %.0f, mode %s, stuck %s)" % [lot.h, str(pos.snapped(Vector3(1, 1, 1))), "stuck" if stuck else "ended", best_y, lot.h, sn.mode_name(), str(stuck)])
	times.sort()
	print("CL %d buildings tried, climb started %d, roof reached %d, stuck %d, embedded ticks %d, median time to the roof %.1f s | by height %s" % [tried, started, roofed, stuck_n, emb_total, times[times.size() / 2] if not times.is_empty() else -1.0, str(by_h)])
	for f in fails.slice(0, 12):
		print("CL FAIL ", f)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)
