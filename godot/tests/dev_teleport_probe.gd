extends RefCounted
## Dev helper (not a test): the hero teleports to every quantum pad (what the fast travel does) and the probe watches, in real frames, whether he lands and stays on the ground, how long the ground
## takes, the worst frame time and the far terrain tiles built. tools/test.sh tests/dev_teleport_probe.gd   (TP_SECS = seconds watched per pad, default 3)

const TIMEOUT_SECONDS := 140


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
	var city := Game.world as City
	var secs := float(OS.get_environment("TP_SECS")) if OS.get_environment("TP_SECS") != "" else 3.0
	var skip := OS.get_environment("TP_SKIP").split(",", false)
	for pad: Dictionary in RoamData.pads():
		if String(pad["id"]) in skip:
			continue
		var pp: Vector3 = pad["pos"]
		var t0 := Time.get_ticks_usec()
		p.teleport_to(pp + Vector3(0.0, 1.0, 0.0))
		var tp_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var worst := 0.0
		var min_rel := 1.0e9
		var landed_at := -1.0
		var t := 0.0
		var last := Time.get_ticks_usec()
		var fell := 0
		while t < secs:
			await host.get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := float(now - last) / 1.0e6
			last = now
			t += dt
			worst = maxf(worst, dt * 1000.0)
			var gy := TerrainHeight.height_at(p.global_position.x, p.global_position.z)
			min_rel = minf(min_rel, p.global_position.y - gy)
			if p.is_on_floor() and landed_at < 0.0:
				landed_at = t
			if p.global_position.y < gy - 3.0:
				fell += 1
			p.hp = p.max_hp
		var st: Dictionary = city.terrain.stats() if city.terrain != null else {}
		print("TPPROBE %s (%.0f, %.0f, %.1f) teleport_call=%.0f ms worst_frame=%.0f ms min_rel_y=%.2f landed_at=%.2f s fell_frames=%d far_tiles=%s chunks=%s jobs=%s ground_ready=%s" % [pad["id"], pp.x, pp.z, pp.y, tp_ms, worst, min_rel, landed_at, fell, str(st.get("far_tiles")), str(st.get("chunks")), str(st.get("jobs")), str(city.terrain.is_ground_ready(pp.x, pp.z))])
	Game.state = &"menu"
	main.queue_free()
