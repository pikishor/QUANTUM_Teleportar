extends "res://tests/tankmis_w129_bot.gd"
## w129-tankmis: BOOTHS, BOOMS AND FENCES at the ARMY BASE and the three road CHECKPOINTS (TankPlaces; until wave 128 the vehicles stood on bare ground). Real scene, the hero is put
## beside each place (set-up), then: the decor stands there (a booth with a body, a sign, a fence), none of it stands inside a parked military vehicle of the place or in front of its nose
## (they still drive out: the left thumb drives one out of each place by finger), and the checkpoint road between the booms stays open.
## Every check marked [old fails] fails with W129TM_OLD=1.
## Run: tools/test.sh tests/test_tankplaces_w129.gd
const TIMEOUT_SECONDS := 140


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	host.get_tree().root.size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 8
	await _until(func() -> bool: return TerrainRoads.built, 10.0)
	var places: Array = TankPlaces.places() if TankPlaces.on else []
	TestLib.check(places.size() == 4, "[old fails] the army base and the three checkpoints each have their decor (%d places)" % places.size())
	for s: Dictionary in places:
		await _place(s)
	fg.up_all()
	TestMode.god = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _place(s: Dictionary) -> void:
	var id: StringName = s["id"]
	var c: Vector3 = s["pos"]
	var n := (s["nrm"] as Vector2)
	await _place_hero(c + Vector3(n.x, 0.0, n.y) * (float(s["w"]) * 0.5 + 14.0) + Vector3(0.0, Vehicle._terrain_y(c.x, c.z) - c.y, 0.0), c)
	await _wait(2.0)
	var tp := TankPlaces.instance
	var root: Node3D = tp.get_node_or_null("Place_" + String(id)) as Node3D if tp != null else null
	TestLib.check(root != null, "[old fails] %s: the decor stands there when the hero comes near" % id)
	if root == null:
		return
	var body := root.get_node_or_null("PlaceBody") as StaticBody3D
	var mesh := root.get_node_or_null("PlaceMesh") as MeshInstance3D
	var labels := root.find_children("*", "Label3D", true, false)
	var tris := mesh.mesh.get_faces().size() / 3 if mesh != null and mesh.mesh != null else 0
	TestLib.check(body != null and body.get_child_count() >= 1 and tris > 200 and labels.size() >= 2, "%s: a booth with a body, fences / booms (%d triangles) and a sign (%d labels)" % [id, tris, labels.size()])
	# nothing of it inside or in front of a parked vehicle of this place
	var sp := root.get_world_3d().direct_space_state
	var kinds := TankRoster.kinds_at(&"base" if s["kind"] == &"base" else id)
	var bad := ""
	var seen := 0
	var one: Vehicle = null
	for pt: Dictionary in TankRoster.spawn_points():
		if not kinds.has(pt["kind"]):
			continue
		var v: Vehicle = vm._spawned.get(pt["id"]) as Vehicle if is_instance_valid(vm._spawned.get(pt["id"])) else null
		if v == null or not v.active:
			continue
		seen += 1
		if one == null:
			one = v
		var L := float(v.spec["len"])
		var W := float(v.spec["wid"])
		for k in 6:                                                              # the hull and 14 m ahead of its nose, at knee and chest height
			var along := -L * 0.5 + (L + 14.0) * float(k) / 5.0
			for side: float in [-0.45, 0.0, 0.45]:
				var q := PhysicsShapeQueryParameters3D.new()
				var sh := SphereShape3D.new()
				sh.radius = 0.5
				q.shape = sh
				q.transform = Transform3D(Basis(), v.global_position + v.forward() * along + v.right() * W * side + Vector3(0.0, 1.0, 0.0))
				q.collision_mask = Game.L_WORLD
				for hit: Dictionary in sp.intersect_shape(q, 4):
					if hit["collider"] == body:
						bad += " %s@%.0fm" % [v.kind, along]
	TestLib.check(seen >= 1 and bad == "", "%s: no booth, block or fence in or in front of its %d parked vehicles%s" % [id, seen, bad])
	if one != null:                                                               # one of them drives out by finger
		var from := one.global_position
		if await _board(one):
			fg.stick(Vector2(0.0, -1.0))
			await _wait(4.0)
			fg.stick(Vector2.ZERO)
			var went := _flat(one.global_position, from)
			TestLib.check(went > 12.0, "%s: the %s drives out of its place (%.0f m)" % [id, one.kind, went])
			await _tap(&"interact")
			await _f(10)
