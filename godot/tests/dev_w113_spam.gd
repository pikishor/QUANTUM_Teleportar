extends RefCounted
## DEV PROBE 6: 90 blasts of every kind in 9 s at LOW: do the pools hold (nodes, marks, debris, clouds)? Run: tools/test.sh tests/dev_w113_spam.gd
const TIMEOUT_SECONDS := 140.0
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
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.missions.contracts.enabled = false
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	Game.set_quality(int(OS.get_environment("SPAM_TIER")) if OS.get_environment("SPAM_TIER") != "" else 0)
	var city := Game.world as City
	var spot: Vector3 = city.random_core_road_point()
	p.teleport_to(spot)
	await TestLib.frames(host, 30)
	var ops := BlastOps.shared(host.get_tree())
	var ids := BlastTable.ids().filter(func(id: StringName) -> bool: return StringName(BlastTable.entry(id)["cat"]) != &"ultimate" and not String(id).begins_with("st_emp") and BlastTable.entry(id)["pre"] == 0.0 or true)
	var n0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var o0 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var peak_nodes := n0
	var peak_marks := 0
	var peak_debris := 0
	var peak_cloud := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var made := 0
	for pass_i in 3:
		var np0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		for round in 45:
			var id: StringName = ids[rng.randi() % ids.size()]
			var at := spot + Vector3(rng.randf_range(-25.0, 25.0), 0.3, rng.randf_range(-25.0, 25.0))
			if rng.randf() < 0.4:
				var f := mgr.spawn(&"operative", at, true)
				if f != null:
					f.set_physics_process(false)
			BlastTable.apply(id, at, p, {"final": true})
			made += 1
			await TestLib.frames(host, 6)
			peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			peak_marks = maxi(peak_marks, FX.marks.struct_live() if FX.marks != null else 0)
			peak_debris = maxi(peak_debris, Breakables.current.debris_live if Breakables.current != null else 0)
			peak_cloud = maxi(peak_cloud, BlastFx.shared().cloud_live())
		await TestLib.frames(host, 60 * 6)
		mgr.clear()
		await TestLib.frames(host, 30)
		print("PROBE spam pass ", pass_i, ": nodes ", np0, " -> ", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	var n1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	await TestLib.frames(host, 60 * 12)
	mgr.clear()
	await TestLib.frames(host, 30)
	var n2 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var o2 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("PROBE spam tier ", Game.quality, ": ", made, " blasts; nodes ", n0, " -> peak ", peak_nodes, " -> end ", n1, " -> 12 s later ", n2, " | objects ", o0, " -> ", o2, " | peak struct marks ", peak_marks, " debris ", peak_debris, " cloud ", peak_cloud, " | items ", ops.live_count(), " zones ", ops.zones_live(), " pending ", ops.pending_count())
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
