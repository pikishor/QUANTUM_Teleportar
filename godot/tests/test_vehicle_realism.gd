extends RefCounted
## Vehicles that feel like cars (owner round 3) in the REAL game scene: the gearbox + tyre model (acceleration with shifts, speed sensitive steering, grip and slide, braking,
## handbrake drift, weight transfer on the body), collisions that answer with impulses (walls, glancing hits, car against car with masses) and damage that follows the closing speed
## along the contact normal (bumps do nothing, normal crashes do not wreck, only a hard hit does; the driver is hurt only by the hardest), visible damage (dents in the panel mesh,
## cracked glass, smoke, fire, an explosion only when the hull is gone), repair at a mechanic bay, and the driving camera (speed FOV and distance, look behind, hood view, drift
## follow, wall collision) plus the touch buttons. Waits on game time, positions and counters, never on frame counts; every wall is a box the test adds on the world layer.
## Run: tools/test.sh tests/test_vehicle_realism.gd   (about 40 s)

const K := 4
const DT := 1.0 / 60.0
const AVE_Z := 5.0                    ## the east-west avenue lane (z), a clear straight at x -600 .. 600

var city: City
var p: Player
var mgr: VehicleManager
var walls: Array[StaticBody3D] = []
var host: Node


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(city != null and p != null and mgr != null, "the real scene has a city, a player and a vehicle manager")
	if city == null or p == null or mgr == null:
		_restore()
		return
	p.set_physics_process(true)
	p.max_hp = 1000.0
	p.hp = 1000.0
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	for k: StringName in [&"sedan", &"sport", &"suv", &"truck", &"bus"]:         # create every body that is used below now: a body made this frame is not in the physics space yet
		mgr.spawn_parked(k, Vector3(-700.0 + float(mgr.list.size()) * 10.0, 0.0, 400.0), 0.0)
		await TestLib.frames(host, 2)
		for v in mgr.list.duplicate():
			if v != mgr.starter:
				mgr._release(v)
	await TestLib.frames(host, 4)
	_numbers()
	_handling()
	await _collisions_and_damage()
	_car_against_car()
	_damage_looks()
	await _repair_bay()
	await _camera()
	await _touch_buttons()
	_restore()
	for w in walls:
		w.queue_free()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Input.action_release(&"move_forward")
	Input.action_release(&"look_back")


# --- helpers -------------------------------------------------------------------------------------------------------------------------------------------

func _clear() -> void:
	if mgr.driven != null:
		mgr.exit_vehicle()
	for v in mgr.list.duplicate():
		mgr._release(v)
	mgr.starter = null
	if NearTraffic.instance != null:                    # the near (MultiMesh) cars become real ones in the way of a driven car: these tests are about an empty avenue
		NearTraffic.instance.count = 0
		NearTraffic.instance.reset()


## A fresh car of `kind` at x on the avenue, facing east, parked and ready for manual stepping (the manager's own physics is switched off while a test steps by hand).
func _car(kind: StringName, x: float, z := AVE_Z, heading := -PI * 0.5, collide := false) -> Vehicle:
	while mgr.list.size() >= mgr.cap():
		mgr._release(mgr.list[0])
	var v := mgr.spawn_parked(kind, Vector3(x, 0.0, z), heading)
	v.global_position = Vector3(x, 0.0, z)
	v.heading = heading
	v.rotation = Vector3(0.0, heading, 0.0)
	v._heading_set = heading
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.yaw_rate = 0.0
	v._dist = 0.0
	v.collision_mask = Game.L_WORLD if collide else 0                   # the handling tests are pure physics: nothing on the avenue may get in the way
	return v


func _launch(v: Vehicle, speed: float) -> void:
	v.vel = v.forward() * speed
	v.speed = speed


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	host.add_child(b)
	b.global_position = center
	walls.append(b)
	return b


func _drive(v: Vehicle, secs: float, thr: float, steer: float, hb := false) -> void:
	for i in int(ceil(secs / DT)):
		v.step_drive(DT, thr, steer, hb)
		v._sync(DT)


## Drive a car at `speed` into the wall at x = wall_x and report the damage fraction of the hull it took (0..1+). `heading_off` turns the car away from head-on (radians).
func _hit(kind: StringName, speed: float, heading_off := 0.0, wall_x := -300.0) -> Dictionary:
	_clear()
	mgr.set_physics_process(false)
	var gap := 4.6
	var v := _car(kind, wall_x - gap, AVE_Z, -PI * 0.5 + heading_off, true)
	_launch(v, speed)
	var hp0 := v.hp
	var t := 0.0
	while t < 2.5 and v.crashes == 0 and v.last_impact <= 0.0:
		v.step_drive(DT, 0.0, 0.0, false)
		v._sync(DT)
		t += DT

	var after := 0.5
	var speed_after := 0.0
	while after > 0.0:
		v.step_drive(DT, 0.0, 0.0, false)
		v._sync(DT)
		after -= DT

	speed_after = v.vel.length()
	return {"car": v, "lost": hp0 - v.hp, "frac": (hp0 - v.hp) / VehicleSpecs.CRASH_REF_HP, "impact": v.last_impact, "speed_after": speed_after}


## Drive at `speed` along the avenue turning `angle` toward the wall beside it (z = 8.5) from 40 m away, 1.8 s, report the damage fraction and the speed left.
func _scrape(kind: StringName, speed: float, angle: float) -> Dictionary:
	_clear()
	mgr.set_physics_process(false)
	var v := _car(kind, -566.0, AVE_Z, -PI * 0.5 - angle, true)
	_launch(v, speed)
	var hp0 := v.hp
	var t := 0.0
	while t < 1.8:
		v.step_drive(DT, 0.4, 0.0, false)
		v._sync(DT)
		t += DT
	return {"car": v, "lost": hp0 - v.hp, "frac": (hp0 - v.hp) / VehicleSpecs.CRASH_REF_HP, "speed_after": v.vel.length()}


# --- the numbers ---------------------------------------------------------------------------------------------------------------------------------------

func _numbers() -> void:
	var cars: Array[StringName] = []
	for k: StringName in VehicleSpecs.SPECS:
		if VehicleSpecs.cls_of(k) == &"car":
			cars.append(k)
	var ok_speed := true
	for k in cars:
		var m := float(VehicleSpecs.SPECS[k]["max"])
		ok_speed = ok_speed and m >= 14.0 and m <= 30.0
	TestLib.check(ok_speed and cars.size() >= 8, "every car kind (%d) tops out between 50 and 108 km/h: the city scale (2 km map, minutes to cross)" % cars.size())
	TestLib.check(float(VehicleSpecs.SPECS[&"bus"]["max"]) < float(VehicleSpecs.SPECS[&"sedan"]["max"]) and float(VehicleSpecs.SPECS[&"sport"]["max"]) > float(VehicleSpecs.SPECS[&"sedan"]["max"]), "a bus is slower than a sedan, a sport car faster")
	TestLib.check(float(VehicleSpecs.SPECS[&"sedan"]["hp"]) >= 250.0 and float(VehicleSpecs.SPECS[&"truck"]["hp"]) > float(VehicleSpecs.SPECS[&"sedan"]["hp"]) * 1.8, "hit points are scaled up, a truck is much tougher than a sedan")
	TestLib.check(Vehicle.crash_fraction(3.0) == 0.0 and Vehicle.crash_fraction(VehicleSpecs.CRASH_SAFE) == 0.0, "a bump below %.1f m/s does nothing" % VehicleSpecs.CRASH_SAFE)
	var f10 := Vehicle.crash_fraction(10.0)
	var f20 := Vehicle.crash_fraction(20.0)
	TestLib.check(f10 > 0.0 and f10 < 0.12 and f20 > 0.3 and f20 < 0.7 and Vehicle.crash_fraction(VehicleSpecs.CRASH_WRECK) > 0.95 and f20 > f10 * 3.0, "damage grows steeply with the impact speed (10 m/s %.2f, 20 m/s %.2f, wreck at %.0f m/s)" % [f10, f20, VehicleSpecs.CRASH_WRECK])
	TestLib.check(Vehicle.steer_limit(30.0) < Vehicle.steer_limit(2.0) * 0.3 and Vehicle.steer_limit(0.0) >= 0.5, "steering narrows with speed (lock %.2f rad standing, %.2f at 30 m/s)" % [Vehicle.steer_limit(0.0), Vehicle.steer_limit(30.0)])
	var c := Vehicle.tyre_curve(1.0)
	TestLib.check(c > Vehicle.tyre_curve(0.4) and Vehicle.tyre_curve(4.0) < c - 0.2 and Vehicle.tyre_curve(-1.0) == -c and Vehicle.tyre_curve(4.0) > 0.4, "the tyre curve peaks then slides, keeping most of its grip")


# --- handling ------------------------------------------------------------------------------------------------------------------------------------------

func _handling() -> void:
	_clear()
	mgr.set_physics_process(false)
	# acceleration with a gearbox: shifts up through five gears, the engine note (rpm) drops at every shift and the car never leaps
	var v := _car(&"sport", -560.0)
	var max_v := float(v.spec["max"])
	var t := 0.0
	var gears: Array[int] = [1]
	var shift_drops := 0
	var prev_rpm := v.rpm
	var t60 := -1.0
	var worst_jerk := 0.0
	var prev_speed := 0.0
	while t < 14.0 and v.speed < max_v * 0.97:
		v.step_drive(DT, 1.0, 0.0, false)
		v._sync(DT)
		t += DT
		if gears[gears.size() - 1] != v.gear:
			gears.append(v.gear)
		if v.rpm < prev_rpm - 0.012:
			shift_drops += 1
		prev_rpm = v.rpm
		worst_jerk = maxf(worst_jerk, (v.speed - prev_speed) / DT)
		prev_speed = v.speed
		if t60 < 0.0 and v.speed >= 16.7:
			t60 = t
	TestLib.check(gears == [1, 2, 3, 4, 5] and shift_drops >= 3, "the sport car shifts through 5 gears and the rpm falls at each shift (%s, %d drops)" % [str(gears), shift_drops])
	TestLib.check(t60 > 1.8 and t60 < 4.5 and v.speed >= max_v * 0.95, "0-60 km/h in %.1f s (sport), top speed %.1f of %.0f m/s reached in %.1f s" % [t60, v.speed, max_v, t])
	TestLib.check(worst_jerk < 14.0, "acceleration is bounded (%.1f m/s2 at most)" % worst_jerk)
	TestLib.check(v.rpm > 0.55 and v.rpm <= 1.1, "the rpm at the top is high (%.2f)" % v.rpm)
	# braking: from 100 km/h to a stop in under 3.5 s and 60 m, nose down on the way
	_launch(v, 27.8)
	var dist := 0.0
	var tb := 0.0
	var min_pitch := 0.0
	while v.speed > 0.4 and tb < 6.0:
		var s0 := v.global_position
		v.step_drive(DT, -1.0, 0.0, false)
		v._sync(DT)
		min_pitch = minf(min_pitch, v.visual.model.rotation.x)
		dist += s0.distance_to(v.global_position)
		tb += DT
	TestLib.check(tb > 1.4 and tb < 3.6 and dist > 20.0 and dist < 62.0, "100 km/h to a stop takes %.1f s and %.0f m" % [tb, dist])
	TestLib.check(min_pitch < -0.006, "the nose dives under braking (pitch %.3f rad)" % min_pitch)
	var max_pitch := 0.0
	var v2 := _car(&"sport", -500.0)
	for i in 100:
		v2.step_drive(DT, 1.0, 0.0, false)
		v2._sync(DT)
		max_pitch = maxf(max_pitch, v2.visual.model.rotation.x)
	TestLib.check(max_pitch > 0.003, "and the tail squats under power (pitch %.3f rad)" % max_pitch)
	# cornering: a steady turn pulls about one g and the body leans out of the corner
	var sed := _car(&"sedan", -420.0)
	_launch(sed, 0.6 * float(sed.spec["max"]))
	var lat := 0.0
	var roll_sign := 0.0
	for i in 150:
		sed.step_drive(DT, 0.25, 0.5, false)
		sed._sync(DT)
		lat = maxf(lat, absf(sed.lat_acc))
		if i == 140:
			roll_sign = sed.visual.model.rotation.z
	TestLib.check(lat > 5.0 and lat < 12.5, "half stick at 60 %% speed corners at %.1f m/s2 (%.2f g)" % [lat, lat / 9.8])
	TestLib.check(roll_sign > 0.004, "the body leans to the outside of a right turn (roll %.3f)" % roll_sign)
	# stability: full lock at 90 % speed does not spin the car, it understeers and settles when the stick is released
	var sp := _car(&"sport", -380.0)
	_launch(sp, 0.9 * float(sp.spec["max"]))
	var h0 := sp.heading
	var peak_yaw := 0.0
	for i in 60:
		sp.step_drive(DT, 0.6, 1.0, false)
		peak_yaw = maxf(peak_yaw, absf(sp.yaw_rate))
	var turned := absf(sp.heading - h0)
	for i in 150:
		sp.step_drive(DT, 0.6, 0.0, false)

	TestLib.check(turned < 0.9 and peak_yaw < 1.6 and absf(sp.yaw_rate) < 0.1 and absf(sp.slip) < 1.0, "full lock at 90 %% speed understeers (%.0f deg in 1 s) and settles (yaw %.2f, slip %.2f)" % [rad_to_deg(turned), sp.yaw_rate, sp.slip])
	# handbrake drift: the rear lets go, the car rotates and slides (tyres smoke / squeal), then it is caught again
	var dr := _car(&"sport", -340.0)
	_launch(dr, 0.6 * float(dr.spec["max"]))
	var hb0 := dr.heading
	var smoked := false
	var skid_max := 0.0
	var slip_max := 0.0
	for i in 45:
		dr.step_drive(DT, 0.5, 0.8, true)
		dr._sync(DT)
		smoked = smoked or dr.drifting
		skid_max = maxf(skid_max, dr.skid)
		slip_max = maxf(slip_max, absf(dr.slip))
	var rot := absf(dr.heading - hb0)
	for i in 240:
		dr.step_drive(DT, 0.4, -0.3, false)
		dr._sync(DT)
	TestLib.check(rot > 0.4 and slip_max > 4.0 and smoked and skid_max > 0.4, "the handbrake breaks the rear loose (%.0f deg, slip %.1f m/s, skid %.2f)" % [rad_to_deg(rot), slip_max, skid_max])
	TestLib.check(absf(dr.slip) < 2.5 and absf(dr.yaw_rate) < 0.8, "and a slide ends gradually, the car is controllable again (slip %.1f, yaw %.2f)" % [dr.slip, dr.yaw_rate])
	# heavy vehicles corner and brake differently
	var bus := _car(&"bus", -300.0)
	_launch(bus, 0.6 * float(bus.spec["max"]))
	var bl := 0.0
	for i in 120:
		bus.step_drive(DT, 0.3, 0.5, false)
		bl = maxf(bl, absf(bus.lat_acc))
	TestLib.check(bl < lat, "a bus pulls less lateral g than a sedan (%.1f vs %.1f)" % [bl, lat])
	# reverse and standing turns
	var rv := _car(&"sedan", -250.0)
	_drive(rv, 2.5, -1.0, 0.0)
	TestLib.check(rv.speed < -3.0 and rv.speed >= -float(rv.spec["max"]) * VehicleSpecs.REVERSE_FRACTION - 0.1, "reverse works and is capped (%.1f m/s)" % rv.speed)
	var st := _car(&"sedan", -200.0)
	var hs := st.heading
	_drive(st, 1.0, 0.0, 1.0)
	TestLib.check(absf(st.heading - hs) < 0.01, "no steering on the spot")


# --- collisions and damage -----------------------------------------------------------------------------------------------------------------------------

func _collisions_and_damage() -> void:
	_wall(Vector3(-299.5, 3.0, AVE_Z), Vector3(1.0, 6.0, 160.0))
	await TestLib.frames(host, 4)
	p.invuln = 0.0
	var bump := _hit(&"sedan", 4.5)
	TestLib.check(bump["lost"] == 0.0, "a 4.5 m/s bump does nothing to the hull (lost %.1f)" % bump["lost"])
	var soft := _hit(&"sedan", 10.0)
	var soft_frac: float = soft["frac"]
	TestLib.check(soft_frac > 0.0 and soft_frac < 0.12 and (soft["car"] as Vehicle).hp > 0.85 * (soft["car"] as Vehicle).max_hp, "a 36 km/h crash dents the car but is nowhere near a wreck (%.0f %% of a sedan lost)" % (soft_frac * 100.0))
	var hard := _hit(&"sedan", 20.0)
	var hcar: Vehicle = hard["car"]
	TestLib.check(float(hard["frac"]) > 0.25 and not hcar.dead and hcar.hp > 0.0, "a 72 km/h crash hurts badly but the car survives (%.0f %% lost, hp %.0f)" % [float(hard["frac"]) * 100.0, hcar.hp])
	TestLib.check(float(hard["impact"]) > 15.0 and hcar.crashes >= 1 and float(hard["speed_after"]) < 12.0, "the wall stops it and bounces it (impact %.1f m/s, speed after %.1f)" % [float(hard["impact"]), float(hard["speed_after"])])
	var wreck := _hit(&"sedan", 34.0)
	TestLib.check((wreck["car"] as Vehicle).dead or float(wreck["lost"]) > 0.4 * (wreck["car"] as Vehicle).max_hp, "a wall hit at the sedan's top speed (79 km/h) takes about half its hull or more (impact %.1f, lost %.0f, dead %s, hp %.0f)" % [wreck["impact"], wreck["lost"], str((wreck["car"] as Vehicle).dead), (wreck["car"] as Vehicle).hp])
	var truck := _hit(&"truck", 20.0)
	TestLib.check(float(truck["lost"]) > 0.0 and (truck["car"] as Vehicle).hp / (truck["car"] as Vehicle).max_hp > hcar.hp / hcar.max_hp + 0.1, "the same crash costs a truck a much smaller share of its hull")
	# the angle counts: a glancing hit along a wall takes a fraction of a head-on hit and the car slides on
	var head := _hit(&"sport", 22.0, 0.0)
	_wall(Vector3(-520.0, 3.0, 9.0), Vector3(120.0, 6.0, 1.0))                 # a long wall beside the avenue, its face at z = 8.5
	await TestLib.frames(host, 4)
	var glance := _scrape(&"sport", 22.0, deg_to_rad(18.0))
	TestLib.check(float(glance["frac"]) < float(head["frac"]) * 0.3, "a glancing hit hurts far less than a head-on one at the same speed (%.2f vs %.2f)" % [glance["frac"], head["frac"]])
	var gcar: Vehicle = glance["car"]
	TestLib.check(float(glance["speed_after"]) > 12.0 and absf(gcar.global_position.z - 8.5) < 3.0, "and the car keeps going, scraping along the wall (%.1f m/s)" % float(glance["speed_after"]))
	var wide := _scrape(&"sport", 22.0, deg_to_rad(40.0))
	TestLib.check(float(wide["frac"]) > float(glance["frac"]) and float(wide["frac"]) < float(head["frac"]), "a steeper angle costs more than a shallow one but less than head-on (%.2f < %.2f < %.2f)" % [glance["frac"], wide["frac"], head["frac"]])
	# the driver: only the hardest impacts hurt him
	_clear()
	mgr.set_physics_process(false)
	var d1 := _car(&"sedan", -304.4, AVE_Z, -PI * 0.5, true)
	mgr.enter(d1)
	p.hp = 1000.0
	p.invuln = 0.0
	_launch(d1, 11.0)
	var t := 0.0
	while d1.crashes == 0 and t < 2.0:
		d1.step_drive(DT, 0.0, 0.0, false)
		t += DT
	TestLib.check(p.hp == 1000.0 and d1.crashes == 1, "the hero is not hurt by a normal crash (hp %.0f)" % p.hp)
	mgr.exit_vehicle()
	_clear()
	var d2 := _car(&"sedan", -304.4, AVE_Z, -PI * 0.5, true)
	mgr.enter(d2)
	p.invuln = 0.0
	_launch(d2, 27.0)
	t = 0.0
	while d2.crashes == 0 and t < 2.0:
		d2.step_drive(DT, 0.0, 0.0, false)
		t += DT
	TestLib.check(p.hp < 1000.0 and p.hp > 900.0 or d2.dead, "a really hard crash hurts the driver a little (hp %.0f)" % p.hp)
	mgr.exit_vehicle()
	p.hp = 1000.0
	_clear()
	# the old rules are gone: a sedan survives hitting a wall at 50 km/h many times in a row
	var tough := _car(&"sedan", -304.4, AVE_Z, -PI * 0.5, true)
	var n := 0
	while n < 4 and not tough.dead:
		tough.vel = tough.forward() * 12.0
		tough.speed = 12.0
		tough.global_position = Vector3(-304.4, 0.0, AVE_Z)
		var t2 := 0.0
		var c0 := tough.crashes
		while tough.crashes == c0 and t2 < 2.0:
			tough.step_drive(DT, 0.0, 0.0, false)
			t2 += DT
		n += 1
	TestLib.check(not tough.dead and n == 4, "four 43 km/h crashes in a row do not wreck a sedan (hp %.0f of %.0f)" % [tough.hp, tough.max_hp])


func _car_against_car() -> void:
	_clear()
	mgr.set_physics_process(false)
	p.teleport_to(Vector3(-133.0, 0.0, AVE_Z - 12.0))                  # the manager only tests the pairs near the player
	# a sedan into the middle of a parked SUV: the SUV is shoved and the sedan (lighter) loses more
	var a := _car(&"sedan", -140.0, AVE_Z, -PI * 0.5, true)
	var b := _car(&"suv", -126.0, AVE_Z, -PI * 0.5, true)
	b.ai = false
	_launch(a, 16.0)
	var hp_a := a.hp
	var hp_b := b.hp
	var max_b_speed := 0.0
	for i in 120:
		a.step_drive(DT, 0.0, 0.0, false)
		b.sim(DT)
		mgr._collide_all()
		max_b_speed = maxf(max_b_speed, b.speed)
	var lost_a := hp_a - a.hp
	var lost_b := hp_b - b.hp
	TestLib.check(max_b_speed > 3.0 and a.speed < 6.0, "the parked SUV is shoved forward (%.1f m/s) and the sedan stops (%.1f)" % [max_b_speed, a.speed])
	TestLib.check(lost_a > 0.0 and lost_b > 0.0 and lost_a > lost_b, "both cars are hurt, the lighter one more (%.0f vs %.0f hp)" % [lost_a, lost_b])
	TestLib.check(a.global_position.distance_to(b.global_position) > 3.0, "the hulls do not stay inside each other (%.1f m apart)" % a.global_position.distance_to(b.global_position))
	# off the centre line the hit spins the other car
	_clear()
	var c := _car(&"sedan", -140.0, AVE_Z, -PI * 0.5, true)
	var d := _car(&"sedan", -126.0, AVE_Z + 1.3, -PI * 0.5, true)
	_launch(c, 16.0)
	var max_spin := 0.0
	for i in 90:
		c.step_drive(DT, 0.0, 0.0, false)
		d.sim(DT)
		mgr._collide_all()
		max_spin = maxf(max_spin, absf(d.yaw_rate))
	TestLib.check(max_spin > 0.3, "an off-centre hit spins the other car (%.2f rad/s)" % max_spin)
	# a gentle touch breaks nothing
	_clear()
	var e1 := _car(&"sedan", -140.0, AVE_Z, -PI * 0.5, true)
	var e2 := _car(&"sedan", -133.5, AVE_Z, -PI * 0.5, true)
	_launch(e1, 4.0)
	for i in 60:
		e1.step_drive(DT, 0.0, 0.0, false)
		e2.sim(DT)
		mgr._collide_all()
	TestLib.check(e1.hp == e1.max_hp and e2.hp == e2.max_hp, "a 14 km/h tap between two cars does no damage")


# --- what damage looks like ----------------------------------------------------------------------------------------------------------------------------

func _damage_looks() -> void:
	for w in walls:
		w.queue_free()
	walls.clear()
	_clear()
	mgr.set_physics_process(false)
	var v := _car(&"sedan", -90.0)
	var vis := v.visual
	var orig_mesh := vis.body.mesh
	TestLib.check(vis.dents.is_empty() and vis.cracks == 0.0 and v.dmg_state == 0, "a new car is sound: no dents, no cracks, no smoke")
	# a hard crash leaves a dent in the actual panel mesh around the contact
	var before: PackedVector3Array = orig_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	v.crash(20.0, v.global_position + v.forward() * 2.3 + Vector3(0.0, 0.7, 0.0), -v.forward(), INF)
	var after_mesh := vis.body.mesh
	var after: PackedVector3Array = after_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var moved := 0
	var deepest := 0.0
	if after.size() == before.size():
		for i in before.size():
			var d := before[i].distance_to(after[i])
			if d > 0.01:
				moved += 1
				deepest = maxf(deepest, d)
	TestLib.check(vis.dents.size() >= 1 and after_mesh != orig_mesh and moved > 20 and deepest > 0.05 and deepest < 0.6, "a crash dents the body mesh (%d vertices pushed in, deepest %.2f m)" % [moved, deepest])
	TestLib.check(orig_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == before, "the shared model mesh itself is never touched")
	TestLib.check(vis.damage_look > 0.1 and vis.cracks > 0.0, "the paint scuffs and the glass cracks after a hard crash (look %.2f, glass %.2f)" % [vis.damage_look, vis.cracks])
	# smoke below 40 %, fire below 15 %, an explosion only when the hull is gone
	v.hp = v.max_hp * 0.3
	v._hurt(0.001)
	TestLib.check(v.dmg_state == 1 and not v.dead, "below 40 %% hull the engine smokes (state %d)" % v.dmg_state)
	v.hp = v.max_hp * 0.1
	v._hurt(0.001)
	TestLib.check(v.dmg_state == 2 and not v.dead and v.hp > 0.0, "below 15 %% it burns, and it has not exploded (hp %.0f)" % v.hp)
	var burn_t := 0.0
	var fx0 := FX._pi
	while not v.dead and burn_t < 60.0:
		v._damage_fx(DT)
		burn_t += DT
	TestLib.check(v.dead and burn_t > 6.0 and burn_t < 40.0, "a burning car gives the driver time to get out before it blows (%.1f s)" % burn_t)
	TestLib.check(FX._pi != fx0, "the fire is drawn from the pooled FX bursts")
	_clear()
	# the hits of weapons still count, against the larger hit points
	var w := _car(&"sedan", -90.0)
	w.damage(14.0)
	TestLib.check(is_equal_approx(w.hp, w.max_hp - 14.0), "a rifle round takes its 14 hp off the hull")
	# a dented car goes back into the pool sound
	w.crash(22.0, w.global_position + w.forward() * 2.3 + Vector3(0.0, 0.7, 0.0), -w.forward(), INF)
	mgr._release(w)
	var w2 := _car(&"sedan", -90.0)
	TestLib.check(w2.hp == w2.max_hp and w2.visual.dents.is_empty() and w2.visual.cracks == 0.0 and w2.visual._orig_mesh == null, "a pooled car comes back repaired: no dents, no cracks")


# --- the mechanic ----------------------------------------------------------------------------------------------------------------------------------------

func _repair_bay() -> void:
	var fr := Freedom.current
	TestLib.check(fr != null and fr.repairs != null and RepairStations.count() >= 8, "the real scene has mechanic bays (%d)" % RepairStations.count())
	if fr == null or fr.repairs == null:
		return
	_clear()
	mgr.set_physics_process(true)
	var bay := RepairStations.pos(0)
	TestLib.check(bay.distance_to(Game.SPAWN) < 30.0, "the first bay is next to the spawn (%.0f m)" % bay.distance_to(Game.SPAWN))
	var v := _car(&"sedan", bay.x, bay.z - 3.0, -PI * 0.5, true)
	v.crash(20.0, v.global_position + v.forward() * 2.3 + Vector3(0.0, 0.7, 0.0), -v.forward(), INF)
	var hurt_hp := v.hp
	TestLib.check(RepairStations.needs_repair(v) and v.hp < v.max_hp, "the car needs the mechanic (hp %.0f of %.0f)" % [v.hp, v.max_hp])
	p.teleport_to(Vector3(bay.x, 0.0, bay.z - 6.0))
	mgr.enter(v)
	await TestLib.frames(host, 4)
	var n0 := fr.repairs.repaired_count
	# driving through at speed repairs nothing
	v.vel = v.forward() * 20.0
	v.speed = 20.0
	v.global_position = Vector3(bay.x, 0.0, bay.z)
	await TestLib.frames(host, 2)
	TestLib.check(fr.repairs.repaired_count == n0 and v.hp <= hurt_hp + 0.01, "driving through a bay at 70 km/h does not stop for repairs")
	# stopping inside the ring does
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.global_position = Vector3(bay.x, 0.0, bay.z)
	var waited := 0.0
	while fr.repairs.repaired_count == n0 and waited < 8.0:
		await host.get_tree().physics_frame
		waited += DT
	TestLib.check(fr.repairs.repaired_count == n0 + 1 and v.hp == v.max_hp and v.visual.dents.is_empty() and v.visual.cracks == 0.0 and v.dmg_state == 0, "stopping in the bay repairs the car: full hull, no dents, no cracks, no smoke")
	TestLib.check(not fr.repairs.is_ready(0) and Freedom.markers().size() > 0, "the bay rests afterwards and shows on the minimap")
	# the garage car arrives repaired too
	mgr.exit_vehicle()
	await TestLib.frames(host, 2)


# --- the driving camera --------------------------------------------------------------------------------------------------------------------------------

func _camera() -> void:
	_clear()
	mgr.set_physics_process(true)
	mgr.stream_every = 1.0e9
	var v := _car(&"sedan", -560.0, AVE_Z, -PI * 0.5, false)     # camera test: nothing on the avenue may stop the run to speed
	p.teleport_to(Vector3(-560.0, 0.0, AVE_Z - 3.0))
	await TestLib.frames(host, 8)
	mgr.enter(v)
	var rig := p.camera_rig
	rig.veh_view = 0
	await TestLib.frames(host, 90)
	var fov0 := rig.camera.fov
	var d0 := rig._veh_dist_now
	TestLib.check(rig.mode == &"vehicle" and absf(fov0 - CameraRig.VEH_FOV_REST) < 4.0, "the chase camera is a normal lens at a standstill (fov %.0f)" % fov0)
	var behind := (rig.camera.global_position - v.global_position)
	behind.y = 0.0
	TestLib.check(behind.length() > 4.0 and behind.length() < 12.0 and behind.normalized().dot(v.forward()) < -0.7, "it sits behind the car at a sensible distance (%.1f m)" % behind.length())
	Input.action_press(&"move_forward")
	var t := 0.0
	while v.speed < 22.0 and t < 12.0:
		await host.get_tree().physics_frame
		t += DT
	var settle := 0
	while (rig.camera.fov < fov0 + 12.0 or rig._veh_dist_now < d0 + 1.5) and settle < 400:     # the lens eases in: wait on the state, not a frame count (a slow runner renders fewer frames per tick)
		await TestLib.frames(host, 5)
		settle += 5
	var fov1 := rig.camera.fov
	TestLib.check(fov1 > fov0 + 8.0, "the field of view widens with speed (%.0f to %.0f; car %.1f m/s, mode %s, hp %.0f, t %.1f, settle %d)" % [fov0, fov1, v.speed, rig.mode, v.hp, t, settle])
	TestLib.check(rig._veh_dist_now > d0 + 1.0, "and the camera pulls back (%.1f to %.1f m)" % [d0, rig._veh_dist_now])
	# look behind: hold BACK and the view swings round, release and it returns
	Input.action_press(&"look_back")
	await TestLib.frames(host, 120)
	var cf := -rig.camera.global_transform.basis.z
	cf.y = 0.0
	TestLib.check(cf.normalized().dot(v.forward()) < -0.4, "holding BACK looks behind the car (dot %.2f)" % cf.normalized().dot(v.forward()))
	Input.action_release(&"look_back")
	Input.action_release(&"move_forward")
	await TestLib.frames(host, 160)
	cf = -rig.camera.global_transform.basis.z
	cf.y = 0.0
	TestLib.check(cf.normalized().dot(v.forward()) > 0.6, "and letting go brings it back (dot %.2f)" % cf.normalized().dot(v.forward()))
	# views: far, hood, chase
	var chase_d := rig._veh_dist_now
	rig.cycle_vehicle_view()
	await TestLib.frames(host, 30)
	var far_ok := rig.veh_view == 1 and rig._veh_dist_now > chase_d + 1.0
	rig.cycle_vehicle_view()
	await TestLib.frames(host, 60)
	var hood_pos := rig.camera.global_position
	var hood_flat := Vector2(hood_pos.x - v.global_position.x, hood_pos.z - v.global_position.z).length()
	TestLib.check(far_ok and rig.veh_view == 2 and hood_flat < 2.6 and hood_pos.y > 0.7 and hood_pos.y < 2.2, "the VIEW button cycles chase, far and a hood view (hood camera %.1f m from the middle of the car, %.1f m up)" % [hood_flat, hood_pos.y])
	rig.cycle_vehicle_view()
	TestLib.check(rig.veh_view == 0, "and back to the chase view")
	Input.action_release(&"move_forward")
	# the view follows a slide: a car sliding to the right turns the view toward where it goes
	v.slip = 8.0
	var off := rig._drift_offset(20.0)
	v.slip = 0.0
	TestLib.check(off < -0.15 and rig._drift_offset(20.0) == 0.0, "the camera follows the direction of travel in a drift (%.2f rad)" % off)
	# a wall right behind the car pulls the camera in instead of putting it inside the wall
	mgr.exit_vehicle()
	_clear()
	var w := _car(&"sedan", -200.0, AVE_Z, -PI * 0.5, true)
	_wall(Vector3(-200.0 - 4.5, 3.0, AVE_Z), Vector3(1.0, 6.0, 30.0))
	p.teleport_to(Vector3(-200.0, 0.0, AVE_Z - 3.0))
	await TestLib.frames(host, 6)
	mgr.enter(w)
	rig.veh_view = 0
	await TestLib.frames(host, 80)
	var cdist := Vector2(rig.camera.global_position.x - w.global_position.x, rig.camera.global_position.z - w.global_position.z).length()
	TestLib.check(cdist < 4.4 and rig.camera.global_position.x > -204.6, "the camera is pulled in by the wall behind the car (%.1f m from the car)" % cdist)
	mgr.exit_vehicle()
	await TestLib.frames(host, 2)


func _touch_buttons() -> void:
	var tc := (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	host.add_child(tc)
	await TestLib.frames(host, 2)
	var view_b := {}
	var back_b := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"veh_view":
			view_b = b
		if b["action"] == &"look_back":
			back_b = b
	TestLib.check(not view_b.is_empty() and not back_b.is_empty() and float(view_b["r"]) >= 32.0 and float(back_b["r"]) >= 32.0, "VIEW and BACK buttons are defined (64 px targets or more)")
	if not view_b.is_empty():
		tc.controls_on = true
		TestLib.check(not tc.button_visible(view_b) and not tc.button_visible(back_b), "on foot the driving camera buttons stay hidden")
		_clear()
		var v := _car(&"sedan", -90.0)
		p.vehicle = v
		TestLib.check(tc.button_visible(view_b) and not tc.button_visible(back_b), "while driving VIEW shows and BACK waits behind MORE")
		tc.more_open = true
		TestLib.check(tc.button_visible(back_b), "BACK shows once MORE is open")
		tc.more_open = false
		p.vehicle = null
	tc.queue_free()
