extends RefCounted
## WAVE 118 probe (not a test): why does the tank stop on its way out of the yard. Prints positions and what it touches.
const TIMEOUT_SECONDS := 100
func run(h: Node) -> void:
	Sfx.muted = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	h.add_child(main)
	await TestLib.frames(h, 20)
	Game.state = &"play"
	var p := Game.player as Player
	var vm := Game.vehicles as VehicleManager
	TestMode.god = true
	TrafficField.bare_street()
	p.teleport_to(Vector3(-143.0, 0.2, -75.0))
	vm._spawn_t = 0.0
	for i in 150:
		await h.get_tree().physics_frame
	var tank: Vehicle = vm._spawned.get(&"depot")
	print("PROBE tank ", tank, " list ", vm.list.size())
	vm.enter(tank)
	Input.action_press(&"move_forward")
	for i in 8:
		for k in 60:
			await h.get_tree().physics_frame
		var cols := []
		for c in tank.get_slide_collision_count():
			var col := tank.get_slide_collision(c)
			cols.append("%s@%s" % [col.get_collider(), col.get_position().snapped(Vector3(0.1, 0.1, 0.1))])
		print("PROBE t%d pos %s speed %.1f cols %s" % [i, tank.global_position.snapped(Vector3(0.1, 0.1, 0.1)), tank.speed, cols])
	Input.action_release(&"move_forward")
	var kc := tank.move_and_collide(Vector3(0.0, 0.0, -0.6), true)
	if kc != null:
		var o := kc.get_collider() as Node
		print("PROBE hit ", o, " path ", o.get_path(), " at ", kc.get_position(), " shape ", kc.get_collider_shape(), " shape pos ", (kc.get_collider_shape() as Node3D).global_position)
	for v in vm.list:
		print("PROBE veh ", v.kind, " ", v.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
	main.queue_free()
	await TestLib.frames(h, 2)
