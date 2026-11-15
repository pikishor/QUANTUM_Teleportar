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
	var at := p.global_position + fwd * 9.0
	var f := (Game.enemies as EnemyManager).spawn(&"operative", at, false)
	f.set_physics_process(false)
	f.global_position = at
	await frames(4)
	print("DEV hero ", p.global_position, " enemy ", f.global_position)
	var ok := war.cast(&"sv_grab", true)
	print("DEV cast ", ok, " grabbing ", war.verbs.is_grabbing(), " state ", Game.state)
	for i in 6:
		await frames(15)
		print("DEV t=", (i + 1) * 0.25, " enemy ", f.global_position, " grabbing ", war.verbs.is_grabbing(), " hold ", war.verbs._hold_point() if war.verbs.is_grabbing() else Vector3.ZERO, " grab lift ", war.verbs._grab.get("lift", -1))
	main.queue_free()
	await frames(3)
