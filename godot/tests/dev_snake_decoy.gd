extends RefCounted
## Dev probe (wave 115): what the enemy marks say while a SNAKE DECOY is out (the white boxes over the heads in the look-dev frames).
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
	var war := SnakeWar.of(p)
	var d: Vector3 = SnakeAim.ray(p)[1]
	var fwd := Vector3(d.x, 0, d.z).normalized()
	var foes: Array[Drone] = []
	for k in 3:
		var at := p.global_position + fwd * 10.0 + fwd.cross(Vector3.UP) * float(k - 1) * 2.4
		var f := em.spawn(&"operative", at, false)
		f.set_physics_process(false)
		f.global_position = at
		foes.append(f)
	await frames(10)
	for f in foes:
		print("DEV before pip ", f.alert_pip(), " bar ", f.bar_time(), " col ", f.mark_color(), " aware ", f.aware, " hp ", f.hp, "/", f.max_hp)
	print("DEV marks before ", em.marks.ring_count, " ", em.marks.bar_count, " ", em.marks.halos.visible_instance_count)
	war.cast(&"sv_decoy", true)
	for i in 5:
		await frames(15)
		for f in foes:
			f.hp = f.max_hp
			print("DEV t=", (i + 1) * 0.25, " pip ", f.alert_pip(), " bar ", f.bar_time(), " col ", f.mark_color(), " aware ", f.aware, " susp ", f.suspicion, " pos ", f.global_position)
		print("DEV marks ", em.marks.ring_count, " ", em.marks.bar_count, " vis ", em.marks.halos.visible_instance_count, " pips ", em.marks.halos.visible_instance_count - em.marks.ring_count - em.marks.bar_count)
	main.queue_free()
	await frames(3)
