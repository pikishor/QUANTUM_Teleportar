extends RefCounted
## WAVE 118 CRITIC (independent review): a finger-only player in the real main scene from a fresh save.
##   journey  the minimap -> the big map -> a finger on the tank icon (GPS) -> CLOSE -> walk the GPS route by stick and look drags -> ENTER the tank, drive, FIRE, EXIT;
##            then the same to CITY HELIPAD EAST: ENTER the helicopter, UP, fly, FIRE, DOWN, EXIT
##   demo     pause > EXTRAS > TEST > SPAWN (frames only) and MORE > CALL (the CALL-IN list)
## Every action is a finger (InputEventScreenTouch / Drag); teleports only set up the scene where the part says so. Frames at the window size.
##   CR_OUT=<dir> CR_PARTS=journey,heli QUALITY=0 BOT_RES=844x390 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w118_critic.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var tree: SceneTree
var fg: Fingers
var p: Player
var vm: VehicleManager
var out := ""
var look_sign := 0.0


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func _on(part: String) -> bool:
	var parts := OS.get_environment("CR_PARTS").split(",", false)
	return parts.is_empty() or parts.has(part)


func _f(n: int) -> void:
	for i in n:
		await tree.physics_frame
		await tree.process_frame


func _shot(name: String) -> void:
	await _f(2)
	var img := tree.root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("SHOT %s | buttons %s" % [name, str(fg.tc.visible_ids())])


func _tap_at(pos: Vector2, frames := 3) -> void:
	fg.down(7, pos)
	await _f(frames)
	fg.up(7)
	await _f(3)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		print("NOTE no button %s (on screen: %s)" % [action, str(fg.tc.visible_ids())])
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Turn the view toward world point `to` with look drags of the right thumb.
func _face(to: Vector3) -> void:
	var rig := p.camera_rig
	for k in 4:
		var d := to - p.global_position
		var want := atan2(-d.x, -d.z)
		var err := wrapf(want - rig.yaw, -PI, PI)
		if absf(err) < 0.12:
			return
		if look_sign == 0.0:
			var y0 := rig.yaw
			fg.look(60.0, 0.0)
			await _f(3)
			look_sign = -1.0 if rig.yaw < y0 else 1.0
			continue
		var px := clampf(err / TouchControls.LOOK_SENS * look_sign, -500.0, 500.0)
		fg.look(px, 0.0, 8)
		await _f(3)


## Walks (or drives) the GPS route to `goal` with the stick; stops when `done` is true or after `secs`.
func _travel(goal: Vector3, done: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < secs * 1000.0:
		if done.call():
			fg.stick(Vector2.ZERO)
			return true
		var route := WorldRoute.route(p.global_position, goal, &"walk") if p.vehicle == null else WorldRoute.route(p.global_position, goal, &"drive")
		var next := goal
		if Engine.get_process_frames() % 4 == 0:
			print("POS %s route_end %s n %d" % [str(p.global_position.round()), str(route[route.size() - 1].round()) if route.size() > 0 else "-", route.size()])
		for q in route:
			if _flat(q, p.global_position) > 6.0:
				next = q
				break
		fg.stick(Vector2.ZERO)
		await _face(next)
		var at := p.global_position
		fg.stick(Vector2(0.0, -1.0))
		await _f(30)
		if _flat(at, p.global_position) < 1.0:                 # blocked (a parked car, a prop): a step to the side and a JUMP, as a player would
			fg.stick(Vector2(1.0 if randf() < 0.5 else -1.0, -0.3))
			await _tap(&"jump")
			await _f(25)
	fg.stick(Vector2.ZERO)
	return done.call()


func _run() -> void:
	out = OS.get_environment("CR_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	fg = Fingers.new(tree.root)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	Game.force_touch = true
	CrateReveal._quiet = 0
	var msx := tree.root.find_child("MapScreen", true, false) as MapScreen
	if msx != null:
		msx.clear_waypoint()                                          # a fresh save: no GPS left from an earlier run (setup, not an action)
	var prog := Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	Game.state = &"play"
	await _f(30)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	TestMode.god = true
	for k in 6:                                                       # story / reward cards: a finger closes them
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		await _tap_at(fg.vp() * Vector2(0.5, 0.3))
	await _shot("00_start")
	if _on("journey"):
		await _journey()
	if _on("heli"):
		await _heli()
	if _on("demo"):
		await _demo()
	_done = true
	tree.quit()


func _journey() -> void:
	await _tap_at(fg.tc._minimap_rect().get_center())
	await _f(30)
	var ms := tree.root.find_child("MapScreen", true, false) as MapScreen
	print("MAP open %s" % str(ms != null and MapScreen.up))
	if ms == null or not MapScreen.up:
		return
	await _shot("01_map")
	var yard := ArmourSites.YARD
	await _tap_at(ms._map.get_global_transform() * ms.world_to_map(yard.x, yard.z))
	await _f(10)
	print("GPS waypoint %s picked %s route %d" % [str(ms.waypoint) if ms.has_waypoint() else "none", str(ms.selected.get("label", "")), ms.route_points().size()])
	await _shot("02_map_gps_tank")
	var cls := ms.find_child("Close", true, false) as Button
	await _tap_at(cls.get_global_rect().get_center())
	await _f(10)
	print("MAP closed %s state %s" % [str(not MapScreen.up), Game.state])
	await _shot("03_gps_on_street")
	if OS.get_environment("CR_NEAR") == "1":
		p.teleport_to(ArmourSites.YARD + Vector3(40.0, 0.2, -30.0))             # set-up for a short run: 50 m from the yard
		await _f(30)
	var t0 := Time.get_ticks_msec()
	var reached := await _travel(yard, func() -> bool: return Freedom.vehicle_prompt().contains("TANK"), 300.0)
	print("WALK yard reached %s in %.0f s, %.1f m from the yard" % [reached, (Time.get_ticks_msec() - t0) / 1000.0, _flat(p.global_position, yard)])
	await _shot("04_yard_enter")
	await _tap(&"interact")
	await _f(20)
	print("IN %s" % (str(p.vehicle.kind) if p.vehicle != null else "nothing"))
	if p.vehicle == null:
		return
	var v := p.vehicle as Vehicle
	await _shot("05_tank_hud")
	var from := v.global_position
	fg.stick(Vector2(0.0, -1.0))
	await _f(240)
	fg.stick(Vector2.ZERO)
	print("TANK drove %.1f m" % _flat(v.global_position, from))
	if v.weapons == null:
		return
	var ammo0: int = v.weapons.ammo
	fg.press(6, &"fire")
	await _f(30)
	await _shot("06_tank_fire")
	fg.up(6)
	print("TANK fire %d -> %d" % [ammo0, v.weapons.ammo])
	for id: StringName in [&"aim", &"ammo_type", &"veh_view", &"jump", &"more"]:
		var lab := fg.button_label(id)
		var ok := await _tap(id)
		print("TANK press %s '%s' on screen %s" % [id, lab, ok])
	await _shot("07_tank_after_presses")
	if fg.tc.more_open:
		await _tap(&"more")
	await _f(60)
	await _tap(&"interact")
	await _f(20)
	print("TANK exit: on foot %s" % str(p.vehicle == null))
	await _shot("08_tank_out")


func _heli() -> void:
	var pad := ArmourSites.PAD_EAST
	if _flat(p.global_position, pad) > 40.0:                             # set-up: a short walk (the long walks are the journey part)
		p.teleport_to(Vector3(pad.x + 2.6, 0.2, pad.z - 30.0))
		await _f(30)
	var t0 := Time.get_ticks_msec()
	var reached := await _travel(pad, func() -> bool: return Freedom.vehicle_prompt().contains("HELI") or Freedom.vehicle_prompt().contains("GUNSHIP"), 240.0)
	print("WALK pad reached %s in %.0f s, %.1f m" % [reached, (Time.get_ticks_msec() - t0) / 1000.0, _flat(p.global_position, pad)])
	await _shot("10_pad_enter")
	await _tap(&"interact")
	await _f(20)
	print("IN %s" % (str(p.vehicle.kind) if p.vehicle != null else "nothing"))
	if p.vehicle == null:
		return
	var v := p.vehicle as Vehicle
	await _shot("11_heli_ground")
	fg.press(1, &"jump")
	await _f(200)
	fg.up(1)
	print("HELI alt %.1f" % VehicleCraft.altitude(v))
	fg.stick(Vector2(0.0, -1.0))
	await _f(120)
	fg.stick(Vector2.ZERO)
	await _shot("12_heli_air")
	var ammo0: int = v.weapons.ammo
	fg.press(6, &"fire")
	await _f(30)
	fg.up(6)
	print("HELI fire %d -> %d" % [ammo0, v.weapons.ammo])
	for id: StringName in [&"aim", &"veh_view", &"interact"]:
		var lab := fg.button_label(id)
		var ok := await _tap(id)
		print("HELI press %s '%s' on screen %s, in %s" % [id, lab, ok, str(p.vehicle != null)])
	await _shot("13_heli_air_presses")
	fg.press(1, &"crouch")
	await _f(600)
	fg.up(1)
	print("HELI landed %s alt %.1f" % [str(not v.craft.airborne), VehicleCraft.altitude(v)])
	await _tap(&"interact")
	await _f(20)
	print("HELI exit: on foot %s" % str(p.vehicle == null))
	await _shot("14_heli_out")


func _demo() -> void:
	if not fg.tc.more_open:
		await _tap(&"more")
	await _shot("20_more")
	await _tap(&"garage_call")
	await _f(10)
	await _shot("21_call_in")
	var b := CallIn.instance.find_child("Call_Plane", true, false) as Button if is_instance_valid(CallIn.instance) else null
	if b != null:
		await _tap_at(b.get_global_rect().get_center())
		await _f(30)
		await _shot("22_plane_called")
