extends RefCounted
## Dev helper (not a test): what a teleport to a far pad costs, part by part (safe_spot, the city's update_streaming, the prop / chunk colliders, the terrain's ensure_ground). tools/test.sh tests/dev_teleport_cost.gd
const TIMEOUT_SECONDS := 120


func _ms(t0: int) -> String:
	return "%.0f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0)


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	var city := Game.world as City
	for id: StringName in [&"mirage_point", &"salt_quay", &"airport", &"iron_hollow", &"hub"]:
		var pad := RoamData.pad(id)
		var pos: Vector3 = (pad["pos"] as Vector3) + Vector3(0, 1, 0)
		var t0 := Time.get_ticks_usec()
		var safe := PlayerUtil.safe_spot(pos, city, p.get_world_3d().direct_space_state)
		var t_safe := _ms(t0)
		p.global_position = safe
		t0 = Time.get_ticks_usec()
		city.update_streaming(Vector2(safe.x, safe.z), true)
		var t_stream := _ms(t0)
		t0 = Time.get_ticks_usec()
		city._colliders.refill(safe)
		var t_col := _ms(t0)
		t0 = Time.get_ticks_usec()
		city._chunks.refill(safe)
		var t_chunks := _ms(t0)
		t0 = Time.get_ticks_usec()
		var ready_before := city.terrain.is_ground_ready(safe.x, safe.z)
		city.terrain.ensure_ground(safe)
		var t_ground := _ms(t0)
		print("TPCOST %s safe_spot=%s update_streaming=%s colliders=%s chunk_colliders=%s ensure_ground=%s (ground ready before: %s)" % [id, t_safe, t_stream, t_col, t_chunks, t_ground, str(ready_before)])
		await TestLib.frames(host, 20)
	Game.state = &"menu"
	main.queue_free()
