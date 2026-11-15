extends RefCounted
## Dev probe (wave 115): how fast the seeker snake leaves the hero.
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
	var at := p.global_position + fwd * 12.0
	var f := em.spawn(&"operative", at, false)
	f.set_physics_process(false)
	f.global_position = at
	f.max_hp = 1.0e6
	f.hp = 1.0e6
	await frames(6)
	p.camera_rig.aim_at(at + Vector3(0, 1.0, 0))
	await frames(4)
	war.arm(&"sb_seeker")
	print("DEV cast ", war.cast(&"sb_seeker", true), " hero ", p.global_position, " foe ", at)
	for i in 10:
		await frames(6)
		var b: SnakeSwarm.Body = null
		for x in war.swarm.bodies:
			b = x
		print("DEV t=", snappedf((i + 1) * 0.1, 0.01), " bodies ", war.swarm.count(), " pos ", b.pos if b != null else Vector3.INF, " speed ", b.speed if b != null else -1.0, " age ", b.age if b != null else -1.0, " seekers ", war.bombs.seekers, " det ", war.bombs.by_id.get(&"sb_seeker", 0))
	WeaponDefs.hero_mode = false
	main.queue_free()
	await frames(3)
