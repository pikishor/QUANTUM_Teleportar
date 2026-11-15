extends RefCounted
## Dev probe (wave 115): where a coil bomb lands against three troopers 10 m ahead and what it holds.
var host: Node
func frames(n: int) -> void:
	await TestLib.frames(host, n)
func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	var em := Game.enemies as EnemyManager
	em.clear()
	Game.state = &"play"
	TestMode.god = true
	WeaponDefs.hero_mode = true
	var war := SnakeWar.of(p)
	var d: Vector3 = SnakeAim.ray(p)[1]
	var fwd := Vector3(d.x, 0, d.z).normalized()
	var right := fwd.cross(Vector3.UP)
	var foes: Array[Drone] = []
	for k in 3:
		var at := p.global_position + fwd * (10.0 + float(k % 2) * 2.0 - 0.8) + right * float(k - 1) * 2.4
		var f := em.spawn(&"operative", at, false)
		f.set_physics_process(false)
		f.global_position = at
		f.max_hp = 1.0e6
		f.hp = 1.0e6
		foes.append(f)
	await frames(6)
	p.camera_rig.aim_at(p.global_position + fwd * 8.0 + Vector3(0, 1.3, 0))
	await frames(3)
	var ops := BlastOps.shared(p.get_tree())
	var det := [Vector3.INF]
	ops.detonated.connect(func(id: StringName, pos: Vector3) -> void:
		if String(id).begins_with("sb_"):
			det[0] = pos
			print("DEV detonated ", id, " at ", pos, " foes ", foes.map(func(f: Drone) -> float: return snappedf(f.global_position.distance_to(pos), 0.1))))
	print("DEV hero ", p.global_position, " foes ", foes.map(func(f: Drone) -> Vector3: return f.global_position))
	war.arm(&"sb_coil")
	var ok := war.cast(&"sb_coil", true)
	print("DEV cast ", ok)
	for i in 8:
		await frames(15)
		print("DEV t=", (i + 1) * 0.25, " bodies ", war.swarm.count(), " holds ", war.holds.count(), " wraps ", war.bombs.wraps, " last hits ", (war.bombs.last_res.get("enemy_hits", {}) as Dictionary).size(), " det ", det[0])
	WeaponDefs.hero_mode = false
	main.queue_free()
	await frames(3)
