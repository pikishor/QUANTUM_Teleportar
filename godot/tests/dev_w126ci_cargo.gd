extends "res://tests/test_air_w126.gd"
## dev probe (w126-ci-apk): only the CARGO DROP boarding, logged per frame.
func _missions() -> void:
	board.take_over = false
	if OS.get_environment("STEPS") != "":
		Engine.max_physics_steps_per_frame = int(OS.get_environment("STEPS"))
	if OS.get_environment("CARGO_FULL") == "1":
		await _dogfight()
		await _escort()
		await _bomb_run()
	await _cargo()

func _enter(v: Vehicle) -> bool:
	var side := v.right() * (float(v.spec["wid"]) * 0.5 + 9.0)
	print("PROBE plane %s at %s h %.2f strip %s hero %s" % [v.kind, v.global_position, v.heading, WorldSites.airport()["strip"], p.global_position])
	await _stand_at(v.global_position + side, v.global_position)
	print("PROBE after stand hero %s yaw %.2f cam %s" % [p.global_position, p.yaw, p.camera_rig.global_basis.z])
	fg.stick(Vector2(0.0, -0.6))
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 8000:
		n += 1
		if n % 10 == 0 or v.edge_distance(p.global_position) < 4.0:
			print("PROBE f%d label '%s' edge %.2f flat %.1f hero %s plane %s fps %.0f" % [n, fg.button_label(&"interact"), v.edge_distance(p.global_position), _flat(p.global_position, v.global_position), p.global_position, v.global_position, Engine.get_frames_per_second()])
		if fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6:
			break
		await host.get_tree().physics_frame
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 1.5)
	print("PROBE in %s" % (p.vehicle == v))
	return p.vehicle == v
