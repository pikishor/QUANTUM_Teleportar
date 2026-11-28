extends "res://tests/tankmis_w129_bot.gd"
## w129-critic: the defects the independent review of wave 129 found, each checked with REAL FINGERS in the real main scene (Game.force_touch, the phone-only layers on,
## InputEventScreenTouch / Drag through Input.parse_input_event: tests/w116_fingers.gd via tests/tankmis_w129_bot.gd), the guide's stuck recovery off.
## W129C_OLD=1 = the code before the fixes: every check marked [old fails] fails with it. C129_PARTS=howitzer,... (default all).
##   howitzer  the ARTILLERY STRIKE: from the yard gate the street to the targets is a grazing line, a thumb a few pixels low or high put the marker 40+ m off the tank (outside
##             SNAP_R) and the shell on the empty street: 18 shells on one tank, the rounds ran out, the mission could not be finished (test_tankmis_w129_c FAILED 2 of 8 that way)
##   battle    the TANK BATTLE played by fingers to its end: the fight (hulls blowing up, husks and shells killing people on the pavement, witnesses calling it in) lifted the
##             heat to 3.7 and sent 3 police cars after the hero during the army's own mission (TankSteps.heat_hold)
##   ride      ARTILLERY STRIKE "GET IN THE MOBILE ARTILLERY": walking up to it past the APC in the next yard bay, ENTER boarded the APC (VehicleManager.mission_ride_first)
##   husk      a car shot to a husk by the tank's gun: the husk was cleared at 25 s while its fire (28 s) still burned: it vanished in full flame
## Run: tools/test.sh tests/test_w129_critic.gd
const TIMEOUT_SECONDS := 140


func play(_t: StringName) -> void:
	var parts := OS.get_environment("C129_PARTS")
	for part in ["howitzer", "battle", "ride", "husk"]:
		if parts == "" or parts.contains(part):
			var t0 := Time.get_ticks_msec()
			await call("_part_" + part)
			fg.up_all()
			if p.vehicle != null:
				await _tap(&"interact")
				await _f(10)
			print("part %s %.1f s" % [part, (Time.get_ticks_msec() - t0) / 1000.0])


func after(_t0: StringName) -> void:
	pass


func _park(kind: StringName, at: Vector3, h: float) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, h)
	vm._count_fixed()
	if v != null:
		v.set_meta(&"hold", true)
		v.global_position = at
	return v


## The right thumb lays the crosshair; a first short swipe settles the tank's gun sight (it lays from the view behind the hull) before the swipe scale is measured.
func _calibrate() -> void:
	fg.look(40.0, 0.0)
	await _f(6)
	_k = 0.0


func _part_howitzer() -> void:
	var gun := await _own_tank(&"artillery")                                  # parked at the yard gate, nose west down the street, boarded by finger
	TestLib.check(gun != null, "HOWITZER: a finger boards the mobile artillery")
	if gun == null:
		return
	var fwd := gun.forward()
	for i in 3:
		vm._release_farthest(gun.global_position)
	await _f(2)
	var tgt := _park(&"ltank", gun.global_position + fwd * 285.0, 0.0)
	if tgt == null:
		TestLib.check(false, "HOWITZER: the target parks")
		return
	tgt.set_meta(&"tank_target", true)
	await _f(6)
	await _calibrate()
	var tp := tgt.global_position
	var eye := p.camera_rig.camera.global_position
	# a thumb a few pixels off: the ground 40 m short of the tank (8 px under it on a 1200 px view), and the air 3 m over its roof
	var cases := [["low", tp - fwd * 40.0], ["high", tp + Vector3(0.0, 5.5, 0.0)]]
	for c: Array in cases:
		await _aim_finger(c[1], 0.0015, 20)
		await _wait(0.4)
		var cf := -p.camera_rig.camera.global_basis.z
		var px := cf.angle_to(tp + Vector3(0.0, 1.0, 0.0) - eye) * 1200.0 / deg_to_rad(p.camera_rig.camera.fov)
		var m := TankArms.marker_point(gun)
		var off := _flat(m, tp) if m.is_finite() else 9999.0
		print("HOWITZER %s: crosshair %.0f px from the tank, marker %.1f m off it (%d m away)" % [c[0], px, off, roundi(_flat(gun.global_position, tp))])
		TestLib.check(px < 40.0 and off < 3.0, "[old fails] HOWITZER: the thumb %.0f px %s the tank 285 m down the street still puts the marker on it (%.1f m off)" % [px, "below" if c[0] == "low" else "above", off])
	var hp0 := tgt.hp
	var s0 := gun.weapons.shots
	await _until(func() -> bool: return gun.weapons.can_fire(), 5.0)
	if fg.press(2, &"fire"):
		await _until(func() -> bool: return gun.weapons.shots > s0, 1.5)
		fg.up(2)
	await _until(func() -> bool: return not is_instance_valid(tgt) or tgt.hp < hp0, 6.0)
	var hit := not is_instance_valid(tgt) or tgt.hp < hp0
	TestLib.check(hit, "[old fails] HOWITZER: a finger on FIRE drops the shell on the tank (hp %.0f -> %.0f)" % [hp0, tgt.hp if is_instance_valid(tgt) else -1.0])
	if is_instance_valid(tgt):
		for mm: StringName in [&"hold", &"tank_target"]:
			if tgt.has_meta(mm):
				tgt.remove_meta(mm)


# --- the TANK BATTLE by fingers: what the city makes of it ------------------------------------------------------------------------------

var heat_max := 0.0
var cops_max := 0
var _sampling := false


func _heat_watch() -> void:
	_sampling = true
	while _sampling:
		heat_max = maxf(heat_max, Game.heat)
		var cops := 0
		for v: Vehicle in vm.list:
			if v.chasing and v.active and not v.dead:
				cops += 1
		cops_max = maxi(cops_max, cops)
		await _f(5)


func _part_battle() -> void:
	Game.heat = 0.0
	heat_max = 0.0
	mission = &"tank_battle"
	_heat_watch()
	await super.play(&"tank_battle")
	await _wait(3.0)
	_sampling = false
	print("BATTLE: heat max %.2f, police cars chasing the hero max %d" % [heat_max, cops_max])
	TestLib.check(heat_max < 1.0 and cops_max == 0, "[old fails] TANK BATTLE: the army's own fight on the street does not make the hero WANTED (heat max %.2f, police cars chasing %d)" % [heat_max, cops_max])


func _part_ride() -> void:
	var ok := await _board_start(&"tank_artillery")
	TestLib.check(ok, "RIDE: the ARTILLERY STRIKE starts by a finger")
	if not ok:
		return
	var k := _camp()
	await _until(func() -> bool: return not k.ws.provided.is_empty(), 4.0)
	var art: Vehicle = k.ws.provided[0] if not k.ws.provided.is_empty() else null
	if art == null:
		TestLib.check(false, "RIDE: the mission provides the howitzer")
		return
	var apc: Vehicle = null
	for v: Vehicle in vm.list:
		if v != art and v.active and _flat(v.global_position, art.global_position) < 10.0:
			apc = v
	print("RIDE: provided %s at %s, beside it %s at %s" % [art.kind, art.global_position, apc.kind if apc else "-", apc.global_position if apc else Vector3.ZERO])
	# the hero walks up to the howitzer from the yard side (the APC's bay is on his way) and taps ENTER when it shows
	var stand := art.global_position - art.right() * (float(art.spec["wid"]) * 0.5 + 4.0)
	await _place_hero(stand, art.global_position)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 10.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.5)
	print("RIDE: ENTER boarded %s" % (p.vehicle.kind if p.vehicle else "nothing"))
	TestLib.check(apc != null, "RIDE: a yard vehicle stands in the next bay (%s)" % (apc.kind if apc else "-"))
	TestLib.check(p.vehicle == art, "[old fails] RIDE: walking up to the mission's howitzer, a finger on ENTER boards the howitzer, not the %s beside it (boarded %s)" % [apc.kind if apc else "-", p.vehicle.kind if p.vehicle else "nothing"])
	if board.is_running():
		board.abandon("TEST")
	await _f(4)


func _part_husk() -> void:
	var tank := await _own_tank(&"tank")
	TestLib.check(tank != null, "HUSK: a finger boards the tank")
	if tank == null:
		return
	vm._release_farthest(tank.global_position)
	var car := _park(&"sedan", tank.global_position + tank.forward() * 32.0, 0.0)
	if car == null:
		TestLib.check(false, "HUSK: a car parks in front of the tank")
		return
	car.remove_meta(&"hold")
	await _f(6)
	await _calibrate()
	for i in 8:
		if not is_instance_valid(car) or car.dead:
			break
		await _aim_finger(car.global_position + Vector3(0.0, 0.7, 0.0), 0.01)
		var s0 := tank.weapons.shots
		await _until(func() -> bool: return tank.weapons.can_fire(), 4.0)
		if fg.press(2, &"fire"):
			await _until(func() -> bool: return tank.weapons.shots > s0, 1.5)
			fg.up(2)
		await _wait(0.8)
	TestLib.check(is_instance_valid(car) and car.wreck, "HUSK: the tank's shells blow the car up")
	if not (is_instance_valid(car) and car.wreck):
		return
	var t0 := _t
	var gone_burning := -1.0
	var burnt_out := false
	while _t - t0 < 60.0:
		if not is_instance_valid(car) or not car.wreck:
			break
		if float(car.get_meta(&"burn", 0.0)) <= 0.0:
			burnt_out = true
			break
		await _step()
	var burn_left := float(car.get_meta(&"burn", 0.0)) if is_instance_valid(car) else 0.0
	if not burnt_out:
		gone_burning = _t - t0
	print("HUSK: %s after %.1f s (fire left %.1f s)" % ["burnt out, still standing" if burnt_out else "cleared", _t - t0, burn_left])
	TestLib.check(burnt_out, "[old fails] HUSK: the husk stands until its fire is out (cleared after %.1f s with %.1f s of fire left)" % [gone_burning, burn_left])
