extends RefCounted
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
	(Game.enemies as EnemyManager).clear()
	Game.state = &"play"
	TestMode.god = true
	var war := SnakeWar.of(p)
	var d: Vector3 = SnakeAim.ray(p)[1]
	var fwd := Vector3(d.x, 0, d.z).normalized()
	var foes: Array[Drone] = []
	for k in 3:
		var at := p.global_position + fwd * 12.0 + fwd.cross(Vector3.UP) * (float(k) - 1.0) * 2.4
		var f := (Game.enemies as EnemyManager).spawn(&"operative", at, false)
		f.set_physics_process(false)
		f.global_position = at
		f.max_hp = 1.0e6
		f.hp = 1.0e6
		foes.append(f)
	await frames(4)
	p.camera_rig.aim_at(SnakeAim.center_of(foes[1]))
	await frames(3)
	var ops := BlastOps.shared(p.get_tree())
	var det := [Vector3.INF]
	ops.detonated.connect(func(id: StringName, pos: Vector3) -> void: det[0] = pos; print("DEV detonated ", id, " at ", pos, " foes ", foes.map(func(f2: Drone) -> Vector3: return f2.global_position)))
	var ok := war.cast(&"sb_swarm", true)
	print("DEV cast ", ok, " aim point ", SnakeAim.point(p, 34.0), " hero ", p.global_position)
	for i in 8:
		await frames(30)
		print("DEV t=", (i + 1) * 0.5, " bodies ", SnakeSwarm.current.count(), " bites ", war.bombs.bites, " arrived ", SnakeSwarm.current.arrived_n, " by_id ", war.bombs.by_id, " hp lost ", foes.map(func(f3: Drone) -> float: return f3.max_hp - f3.hp))
	main.queue_free()
	await frames(3)
