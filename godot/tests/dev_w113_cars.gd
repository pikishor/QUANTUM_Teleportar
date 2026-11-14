extends RefCounted
## DEV PROBE 3: parked cars take damage and chain-explode. Run: tools/test.sh tests/dev_w113_cars.gd
const TIMEOUT_SECONDS := 100.0
const DT := 1.0 / 60.0

func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	var vm := Game.vehicles as VehicleManager
	var city := Game.world as City
	var spot: Vector3 = city.random_core_road_point()
	p.teleport_to(spot)
	await TestLib.frames(host, 4)
	vm._reset_all()
	print("PROBE cars cap ", vm.cap(), " list ", vm.list.size())
	var cars: Array[Vehicle] = []
	for i in 6:
		var c := vm.spawn_parked(&"sedan", spot + Vector3(12.0 + 5.5 * i, 0.0, 12.0), 0.0)
		print("PROBE spawn ", i, " -> ", c, " ", (c.global_position if c != null else Vector3.ZERO))
		if c != null:
			cars.append(c)
	await TestLib.frames(host, 4)
	for c in cars:
		print("PROBE car active ", c.active, " dead ", c.dead, " hp ", c.hp, "/", c.max_hp, " pos ", c.global_position, " group ", c.is_in_group(&"vehicle"))
	var exploded := [0]
	for c in cars:
		c.exploded.connect(func(_v: Node) -> void: exploded[0] += 1)
	cars[0].damage(5000.0)
	print("PROBE after damage: hp ", cars[0].hp, " dead ", cars[0].dead, " exploded ", exploded[0])
	var t := 0.0
	var last := 0
	while t < 14.0 and exploded[0] < cars.size():
		await host.get_tree().physics_frame
		t += DT
		if exploded[0] != last:
			last = exploded[0]
			print("PROBE chain t=", snappedf(t, 0.01), " exploded ", last)
	print("PROBE chain end: ", exploded[0], "/", cars.size(), " t=", snappedf(t, 0.1))
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
