extends RefCounted
## Dev probe (wave 115 PLAY critic): a boosted low flight over the outskirts (the terrain colliders exist only for the 3 x 3 chunks round the hero): does he ever meet ground that has no collider (fall through)?
## env TF_SECS (30), TF_ALT (altitude above the land, 22), TF_DIR (east|south|north|west), TF_K
const TIMEOUT_SECONDS := 200.0
var host: Node
var p: Player

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
	var sn := p.snake
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	WeaponDefs.hero_mode = true                         # unlimited snake energy and open flight: the probe is about the ground under the wings
	var dirs := {"east": Vector3(1, 0, 0), "south": Vector3(0, 0, 1), "north": Vector3(0, 0, -1), "west": Vector3(-1, 0, 0)}
	var dname := OS.get_environment("TF_DIR") if OS.get_environment("TF_DIR") != "" else "east"
	var dir: Vector3 = dirs[dname]
	var alt := float(OS.get_environment("TF_ALT")) if OS.get_environment("TF_ALT") != "" else 22.0
	var secs := float(OS.get_environment("TF_SECS")) if OS.get_environment("TF_SECS") != "" else 30.0
	var k := float(int(OS.get_environment("TF_K")) if OS.get_environment("TF_K") != "" else 2)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	var start := dir * 700.0
	var tw := Game.get_tree().root.find_child("Terrain", true, false) as TerrainWorld
	if tw != null:
		tw.settle(start)
	await frames(30)
	var gy := TerrainHeight.height_at(start.x, start.z)
	p.teleport_to(Vector3(start.x, gy + 2.0, start.z))
	var yaw := PlayerUtil.yaw_of(dir)
	p.camera_rig.reset_view(yaw, 0.0)
	p.yaw = yaw
	await frames(40)
	Input.action_press(&"fly")
	await frames(4)
	Input.action_release(&"fly")
	await frames(30)
	var t0 := sn.time
	var last := sn.time
	var min_clear := 1.0e9
	var min_y := 1.0e9
	var worst_t := 0.0
	var crashes0 := sn.flight.crashes
	var max_v := 0.0
	var fell := false
	var travelled := 0.0
	var prev := p.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"snake")
	while sn.time - t0 < secs:
		await frames(1)
		var dt := sn.time - last
		last = sn.time
		if dt <= 0.0:
			continue
		var pos := p.global_position
		var ground := TerrainHeight.height_at(pos.x, pos.z)
		# aim at `alt` metres over the land 80 m ahead: the hero skims the terrain at speed
		var ahead := pos + dir * 80.0
		var gah := TerrainHeight.height_at(ahead.x, ahead.z)
		p.camera_rig.aim_at(Vector3(ahead.x, gah + alt, ahead.z))
		var clear := pos.y - ground
		if clear < min_clear:
			min_clear = clear
			worst_t = sn.time - t0
		min_y = minf(min_y, pos.y)
		max_v = maxf(max_v, p.velocity.length())
		travelled += pos.distance_to(prev)
		prev = pos
		if pos.y < ground - 3.0 and not fell:
			fell = true
			print("TF FELL THROUGH at t %.1f: hero y %.1f, land y %.1f, mode %s, v %.1f" % [sn.time - t0, pos.y, ground, sn.mode_name(), p.velocity.length()])
	Input.action_release(&"move_forward")
	Input.action_release(&"snake")
	print("TF %s %.0f s: travelled %.0f m, top speed %.0f m/s, lowest clearance over the land %.1f m (at t %.1f), lowest y %.1f, crashes %d, fell through %s, mode %s" % [dname, secs, travelled, max_v, min_clear, worst_t, min_y, sn.flight.crashes - crashes0, str(fell), sn.mode_name()])
	WeaponDefs.hero_mode = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)
