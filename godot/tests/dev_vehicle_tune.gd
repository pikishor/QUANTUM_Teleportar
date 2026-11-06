extends RefCounted
## Developer probe (not part of the suite): prints the numbers of the car model, per kind. tools/test.sh tests/dev_vehicle_tune.gd

func run(host: Node) -> void:
	var root := Node3D.new()
	host.add_child(root)
	await host.get_tree().process_frame
	for k: StringName in [&"sedan", &"sport", &"suv", &"van", &"truck", &"bus", &"interceptor"]:
		var v := Vehicle.new()
		root.add_child(v)
		v.setup(k, null)
		v.activate(Vector3.ZERO, 0.0)
		var dt := 1.0 / 60.0
		var t := 0.0
		var t100 := -1.0
		var t60 := -1.0
		var dist := 0.0
		var gears := []
		for i in 60 * 40:
			v.step_drive(dt, 1.0, 0.0, false)
			t += dt
			if t60 < 0.0 and v.speed >= 16.7:
				t60 = t
			if t100 < 0.0 and v.speed >= 27.8:
				t100 = t
			if gears.is_empty() or gears[gears.size() - 1] != v.gear:
				gears.append(v.gear)
			if v.speed > float(v.spec["max"]) * 0.995:
				break
		var vtop := v.speed
		var tt := t
		# braking from top
		var bd := 0.0
		var bt := 0.0
		while v.speed > 0.5 and bt < 15.0:
			var s0 := v.speed
			v.step_drive(dt, -1.0, 0.0, false)
			bd += (s0 + v.speed) * 0.5 * dt
			bt += dt
		# steady turn at 60% top speed, half stick
		v.vel = v.forward() * float(v.spec["max"]) * 0.6
		v.speed = float(v.spec["max"]) * 0.6
		v.yaw_rate = 0.0
		var h0 := v.heading
		var lat_max := 0.0
		for i in 120:
			v.step_drive(dt, 0.3, 0.5, false)
			lat_max = maxf(lat_max, absf(v.lat_acc))
		var turn_r := 0.0
		var rate := absf(v.yaw_rate)
		if rate > 0.01:
			turn_r = v.speed / rate
		print("TUNE %-12s 0-60kmh %.1fs 0-100 %.1fs top %.1f (%.1fs, gears %s)  100->0 in %.0fm %.1fs  | turn@60%% half stick: lat %.1f m/s2 (%.2f g) radius %.0f m slip %.1f" % [
			String(k), t60, t100, vtop, tt, str(gears), bd, bt, lat_max, lat_max / 9.8, turn_r, v.slip])
		# stability: 90% top speed, full lock for 1 s, then straight: the yaw rate must die out (no spin)
		v.vel = v.forward() * float(v.spec["max"]) * 0.9
		v.speed = float(v.spec["max"]) * 0.9
		v.yaw_rate = 0.0
		var hh := v.heading
		var peak_slip := 0.0
		for i in 60:
			v.step_drive(dt, 0.6, 1.0, false)
			peak_slip = maxf(peak_slip, absf(v.slip))
		var dh := v.heading - hh
		for i in 120:
			v.step_drive(dt, 0.6, 0.0, false)
		print("TUNE %-12s full lock 1s at 90%%: turned %.0f deg, peak slip %.1f m/s, after 2 s straight: yaw %.2f rad/s slip %.2f speed %.1f" % [String(k), rad_to_deg(dh), peak_slip, v.yaw_rate, v.slip, v.speed])
		# handbrake drift: 60% speed, steer right + handbrake for 0.7 s, then release and steer into the slide
		v.vel = v.forward() * float(v.spec["max"]) * 0.6
		v.speed = float(v.spec["max"]) * 0.6
		v.yaw_rate = 0.0
		hh = v.heading
		peak_slip = 0.0
		for i in 42:
			v.step_drive(dt, 0.5, 0.8, true)
			peak_slip = maxf(peak_slip, absf(v.slip))
		var h1 := v.heading - hh
		var sp1 := v.speed
		for i in 90:
			v.step_drive(dt, 0.5, -0.3, false)
			peak_slip = maxf(peak_slip, absf(v.slip))
		print("TUNE %-12s handbrake drift: rotated %.0f deg in 0.7 s (speed %.1f), after release: heading change %.0f deg total, slip %.2f yaw %.2f speed %.1f peak slip %.1f" % [String(k), rad_to_deg(h1), sp1, rad_to_deg(v.heading - hh), v.slip, v.yaw_rate, v.speed, peak_slip])
		v.queue_free()
	TestLib.check(true, "probe done")
