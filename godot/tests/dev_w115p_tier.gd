extends RefCounted
## Dev probe (wave 115 PLAY critic): the graphics tier changes in the middle of a swing, a flight and with snakes out (the auto-quality governor does it on phones): errors, lost ropes, stuck states?
const TIMEOUT_SECONDS := 120.0
var host: Node
var p: Player
var sn: SnakeTraversal

func frames(n: int) -> void:
	await TestLib.frames(host, n)

func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"fire"]:
		Input.action_release(a)

func prep(pos: Vector3, yaw := -PI * 0.5, pitch := 0.0) -> void:
	release_all()
	sn.cancel()
	p.invuln = 0.0
	p.hp = p.max_hp
	sn.energy = 100.0
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(12)

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	var war := SnakeWar.of(p)
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	(Game.enemies as EnemyManager).clear()
	TrafficField.bare_street()
	for a in p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(a as AutoQuality).enabled = false
	var e0 := Dev.errors.total
	var tiers := [2, 0, 1, 2, 0]
	# 1 a swing
	await prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
	Input.action_press(&"snake")
	await frames(60)
	var swing_ok := sn.mode == SnakeTraversal.Mode.SWING or sn.swings >= 1
	var counts: Array[int] = []
	for t in tiers:
		Game.set_quality(t)
		await frames(20)
		counts.append(SnakeTendrilPool.current.count() if SnakeTendrilPool.current != null else -1)
	Input.action_release(&"snake")
	await frames(60)
	print("TR swing: started %s, tendrils per tier switch %s, mode after %s, errors %d" % [str(swing_ok), str(counts), sn.mode_name(), Dev.errors.total - e0])
	# 2 a flight with wings
	await prep(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.1)
	Input.action_press(&"fly")
	await frames(5)
	Input.action_release(&"fly")
	await frames(30)
	var wings_before := 0
	for w in sn.flight.wings:
		if w != null and w.is_alive():
			wings_before += 1
	for t in tiers:
		Game.set_quality(t)
		await frames(20)
	var wings_after := 0
	for w in sn.flight.wings:
		if w != null and w.is_alive():
			wings_after += 1
	print("TR flight: wings alive before %d, after the tier switches %d, mode %s, energy %.0f, errors %d" % [wings_before, wings_after, sn.mode_name(), sn.energy, Dev.errors.total - e0])
	# 3 snakes out: a shield and a net
	Game.set_quality(1)
	await prep(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.0)
	war.cast(&"sv_shield", true)
	await frames(20)
	var n0 := SnakeSwarm.current.count()
	for t in tiers:
		Game.set_quality(t)
		await frames(20)
	print("TR shield: snakes before %d, after %d, shield up %s, errors %d" % [n0, SnakeSwarm.current.count(), str(not war.verbs.shield.is_empty()), Dev.errors.total - e0])
	release_all()
	Game.set_quality(1)
	main.queue_free()
	await frames(3)
