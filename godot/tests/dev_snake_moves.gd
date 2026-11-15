extends RefCounted
## Dev probe: zip, climb (to the roof), double jump, super jump, landing roll in the real city. Run: tools/test.sh tests/dev_snake_moves.gd
const TIMEOUT_SECONDS := 120.0
var host: Node
var p: Player


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func run(hst: Node) -> void:
	host = hst
	Sfx.muted = true
	TestMode.reset_toggles()
	if OS.get_environment("MV_TOUCH") == "1":
		Game.force_touch = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	var sn := p.snake
	# ---- double jump
	p.teleport_to(Game.SPAWN)
	await frames(30)
	p.camera_rig.reset_view(-PI * 0.5, 0.0)
	Input.action_press(&"jump")
	await frames(3)
	Input.action_release(&"jump")
	await until(func() -> bool: return p.air_time > 0.2 and p.velocity.y > 1.0, 1.0)
	var y0 := p.global_position.y
	Input.action_press(&"jump")
	await frames(2)
	Input.action_release(&"jump")
	await frames(30)
	print("MV double jump: count %d, rose to %.2f m (from %.2f), vy now %.1f" % [sn.double_jumps, p.global_position.y, y0, p.velocity.y])
	await until(func() -> bool: return p.is_on_floor(), 3.0)
	await frames(10)
	# ---- super jump (hold)
	Input.action_press(&"jump")
	var top := 0.0
	for i in 60:
		await frames(1)
		top = maxf(top, p.global_position.y)
	Input.action_release(&"jump")
	print("MV super jump: count %d, top %.2f m" % [sn.super_jumps, top])
	await until(func() -> bool: return p.is_on_floor(), 4.0)
	await frames(20)
	# ---- zip at the south building from the avenue
	p.teleport_to(Vector3(-30.0, 0.0, 4.0))
	await frames(20)
	p.camera_rig.reset_view(PI, 0.38)
	await frames(5)
	var z0 := p.global_position
	Input.action_press(&"snake")
	await frames(4)
	Input.action_release(&"snake")
	var ok := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 1.0)
	print("MV zip started: %s kind %s dest %s from %s anchor %s" % [ok, String(sn.zip.kind), str(sn.zip.dest), str(sn.zip.from), str(sn.zip.anchor)])
	for i in 40:
		await frames(3)
		if sn.mode != SnakeTraversal.Mode.ZIP:
			break
		if i % 4 == 0:
			print("MV   zip t %.2f phase %s pos %s v %.1f stuck %.2f" % [sn.zip.t, String(sn.zip.phase), str(p.global_position), p.velocity.length(), sn.zip._stuck_t])
	await until(func() -> bool: return sn.mode != SnakeTraversal.Mode.ZIP, 4.0)
	print("MV zip done: mode %s pos %s (moved %.1f m, up %.1f) zips %d floor %s" % [sn.mode_name(), str(p.global_position), p.global_position.distance_to(z0), p.global_position.y - z0.y, sn.zips, p.is_on_floor()])
	# ---- a climb: stand at the wall and stick
	await frames(40)
	sn.cancel()
	p.teleport_to(Vector3(-13.2, 0.0, 15.0))
	await frames(20)
	p.camera_rig.reset_view(PI, 0.1)
	await frames(5)
	Input.action_press(&"snake")
	await frames(4)
	Input.action_release(&"snake")
	ok = await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.CLIMB, 1.0)
	print("MV climb started: %s at %s normal %s" % [ok, str(p.global_position), str(sn.climb.n)])
	Input.action_press(&"move_forward")
	var t := 0.0
	var last_y := p.global_position.y
	while t < 12.0 and sn.mode == SnakeTraversal.Mode.CLIMB:
		await frames(30)
		t += 0.5
		if int(t * 2.0) % 2 == 0:
			print("MV climbing t %.1f y %.1f pos %s v %.1f n %s lost %.2f" % [t, p.global_position.y, str(p.global_position), p.velocity.length(), str(sn.climb.n), sn.climb._lost])
	Input.action_release(&"move_forward")
	await frames(60)
	print("MV climb end: mode %s mantles %d climbed %.1f m, pos %s floor %s" % [sn.mode_name(), sn.climb.mantles, sn.climb.climbed_m, str(p.global_position), p.is_on_floor()])

	# leap
	sn.cancel()
	p.teleport_to(Vector3(-13.2, 0.0, 15.0))
	await frames(20)
	p.camera_rig.reset_view(PI, 0.1)
	await frames(5)
	Input.action_press(&"snake")
	await frames(4)
	Input.action_release(&"snake")
	await frames(10)
	Input.action_press(&"move_forward")
	await frames(60)
	print("MV before leap: mode %s y %.1f" % [sn.mode_name(), p.global_position.y])
	Input.action_press(&"jump")
	for i in 14:
		await frames(1)
		print("MV   leap f%d mode %s v (%.1f %.1f %.1f) |v| %.1f pos %s" % [i, sn.mode_name(), p.velocity.x, p.velocity.y, p.velocity.z, p.velocity.length(), str(p.global_position)])
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
