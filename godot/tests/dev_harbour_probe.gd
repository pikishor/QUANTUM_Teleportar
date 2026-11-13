extends RefCounted
## Dev helper (not a test): watches the hero after a teleport to the harbour pad (frame by frame: y, ground height, what a ray down hits). tools/test.sh tests/dev_harbour_probe.gd
const TIMEOUT_SECONDS := 100


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	var id := StringName(OS.get_environment("TP_PAD")) if OS.get_environment("TP_PAD") != "" else &"harbour"
	var pad := RoamData.pad(id)
	var pp: Vector3 = pad["pos"]
	print("HARB pad %s at %s ground %.2f water %.2f" % [id, str(pp), TerrainHeight.height_at(pp.x, pp.z), TerrainHeight.water_level_at(pp.x, pp.z)])
	p.teleport_to(pp + Vector3(0.0, 1.0, 0.0))
	print("HARB after teleport hero at %s" % str(p.global_position))
	var space := p.get_world_3d().direct_space_state
	for k in 12:
		await host.get_tree().physics_frame
		var q0 := PhysicsRayQueryParameters3D.create(Vector3(p.global_position.x, 20.0, p.global_position.z), Vector3(p.global_position.x, -40.0, p.global_position.z), 1)
		var h0 := space.intersect_ray(q0)
		print("HARB phys%d y=%.2f vy=%.2f floor=%s ray_from_above=%s" % [k, p.global_position.y, p.velocity.y, str(p.is_on_floor()), "none" if h0.is_empty() else "y=%.2f %s" % [(h0["position"] as Vector3).y, str((h0["collider"] as Node).name)]])
	for k in 20:
		await host.get_tree().process_frame
		p.hp = p.max_hp
		if k % 40 == 0 or k < 2:
			var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 2, 0), p.global_position + Vector3(0, -90, 0), 1)
			var hit := space.intersect_ray(q)
			var hs := "none" if hit.is_empty() else "%s at y=%.2f" % [str((hit["collider"] as Node).get_path()).get_slice("/", -1), (hit["position"] as Vector3).y]
			print("HARB f%d y=%.2f floor=%s vy=%.1f gy=%.2f ray %s state=%s" % [k, p.global_position.y, str(p.is_on_floor()), p.velocity.y, TerrainHeight.height_at(p.global_position.x, p.global_position.z), hs, str(Game.state)])
	Game.state = &"menu"
	main.queue_free()
