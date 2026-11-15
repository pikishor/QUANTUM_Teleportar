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
	var r := SnakeAim.ray(p)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	print("DEV ray ", o, d, " hero ", p.global_position, " yaw ", p.camera_rig.yaw)
	var at := p.global_position + Vector3(d.x, 0, d.z).normalized() * 10.0
	var f := (Game.enemies as EnemyManager).spawn(&"operative", at, false)
	print("DEV spawned ", f, " pos ", f.global_position if f != null else Vector3.ZERO)
	await frames(5)
	print("DEV living ", Gear.living_enemies(p.get_tree()).size(), " friendly ", f.get(&"friendly"), " active ", f.get(&"active"), " dead ", f.get(&"dead"))
	var t := SnakeAim.pick(p, 38.0, [&"enemy"])
	print("DEV pick ", t)
	var o2: Vector3 = SnakeAim.ray(p)[0]
	var to := SnakeAim.center_of(f) - o2
	print("DEV center ", SnakeAim.center_of(f), " angle ", d.angle_to(to.normalized()), " dot ", to.dot(d), " dist ", SnakeAim.center_of(f).distance_to(SnakeAim.chest(p)))
	main.queue_free()
	await frames(3)
