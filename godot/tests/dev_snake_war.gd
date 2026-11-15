extends RefCounted
## Dev probe of the snake combat (not a test): boots the real scene, spawns enemies in front of the hero, casts a verb and a bomb, prints what happened.

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
	print("DEV war ", SnakeWar.instance, " swarm ", SnakeSwarm.current, " pool cap ", SnakeSwarm.current.cap() if SnakeSwarm.current != null else -1)
	(Game.enemies as EnemyManager).clear()
	Game.state = &"play"
	TestMode.god = true
	var war := SnakeWar.of(p)
	print("DEV rows ", SnakeRows.ids().size(), " bombs registered ", BlastTable.ids_in(&"snake").size())
	var fwd := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
	var foes: Array[Drone] = []
	for k in 3:
		var at := p.global_position + fwd * 10.0 + fwd.cross(Vector3.UP) * (float(k) - 1.0) * 2.5
		var f := (Game.enemies as EnemyManager).spawn(&"operative", at, true)
		if f != null:
			f.set_physics_process(false)
			f.global_position = at
			foes.append(f)
	print("DEV foes ", foes.size())
	for id in SnakeRows.VERB_IDS:
		var ok := war.cast(id, true)
		print("DEV verb ", id, " -> ", ok)
		await frames(20)
	for id in SnakeRows.BOMB_IDS:
		var ok2 := war.cast(id, true)
		print("DEV bomb ", id, " -> ", ok2)
		await frames(90)
	print("DEV counters casts ", war.casts, " counts ", war.counts)
	print("DEV bombs by_id ", war.bombs.by_id, " bites ", war.bombs.bites, " hops ", war.bombs.hops, " bolts ", war.bombs.bolts)
	print("DEV swarm spawned ", SnakeSwarm.current.spawned, " peak ", SnakeSwarm.current.peak)
	main.queue_free()
	await frames(3)
