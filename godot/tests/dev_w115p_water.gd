extends RefCounted
## Dev probe (wave 115 PLAY critic): the snakes over WATER: a swing that sinks into a river, a flight that dives into the sea, SNAKE pressed while swimming. Stuck states? (the hero must end swimming or flying, never frozen)
const TIMEOUT_SECONDS := 140.0
var host: Node
var p: Player
var sn: SnakeTraversal
func frames(n: int) -> void:
	await TestLib.frames(host, n)
func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	WeaponDefs.hero_mode = true
	# find the sea
	var spot := Vector3.INF
	for r in range(500, 3400, 60):
		for k in 16:
			var a := TAU * float(k) / 16.0
			var x := cos(a) * float(r)
			var z := sin(a) * float(r)
			if TerrainHeight.is_water(x, z) and TerrainHeight.depth_at(x, z) > 3.0:
				spot = Vector3(x, TerrainHeight.water_level_at(x, z), z)
				break
		if spot.is_finite():
			break
	print("WT water found at %s" % str(spot.snapped(Vector3(1, 1, 1))))
	if not spot.is_finite():
		main.queue_free()
		return
	var tw := Game.get_tree().root.find_child("Terrain", true, false) as TerrainWorld
	if tw != null:
		tw.settle(spot)
	await frames(30)
	# 1 a flight that dives into the sea
	p.teleport_to(spot + Vector3(0.0, 25.0, 0.0))
	p.camera_rig.reset_view(0.0, -0.3)
	await frames(30)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	await frames(40)
	Input.action_press(&"crouch")
	Input.action_press(&"move_forward")
	var t := 0
	var swam := false
	while t < 420:
		await frames(1)
		t += 1
		if sn.mode != SnakeTraversal.Mode.FLY:
			break
	Input.action_release(&"crouch")
	Input.action_release(&"move_forward")
	await frames(60)
	print("WT dive: after %.1f s the mode is %s, y %.1f (water %.1f), swimming %s, on floor %s, hp %.0f" % [float(t) / 60.0, sn.mode_name(), p.global_position.y, spot.y, str(p.swim.active if "active" in p.swim else p.swim.get(&"swimming")), str(p.is_on_floor()), p.hp])
	# 2 SNAKE while swimming: does a swing / zip / flight start from the water? is the hero stuck?
	var s0 := sn.swings
	var f0 := sn.flights
	var z0 := sn.zips
	p.camera_rig.reset_view(0.0, 0.3)
	Input.action_press(&"snake")
	await frames(60)
	Input.action_release(&"snake")
	await frames(30)
	print("WT SNAKE held in the water: swings %d, zips %d, flights %d, mode %s, y %.1f" % [sn.swings - s0, sn.zips - z0, sn.flights - f0, sn.mode_name(), p.global_position.y])
	# is the hero free: a few steps move him
	var p0 := p.global_position
	Input.action_press(&"move_forward")
	await frames(90)
	Input.action_release(&"move_forward")
	print("WT swims on: moved %.1f m in 1.5 s" % p.global_position.distance_to(p0))
	WeaponDefs.hero_mode = false
	main.queue_free()
	await frames(3)
