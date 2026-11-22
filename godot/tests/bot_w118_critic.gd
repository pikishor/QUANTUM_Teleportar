extends RefCounted
## WAVE 118 CRITIC bot: an independent finger-only play of the real main scene from a fresh save, the way the owner plays (traffic, enemies, no god mode unless CRITIC_GOD=1).
## Nothing here calls a game function to act: every action is a finger (tests/w116_fingers.gd). It only READS where things are.
##   find   map icon (finger on the minimap, finger on the tank icon), GPS, WALK the route with the stick, ENTER the tank, drive, FIRE, EXIT
##   heli   the same to CITY HELIPAD EAST: ENTER, UP, fly, FIRE, DOWN, EXIT
##   demo   DEMO mode: the DEMO badge, SPAWN, TANK / HELICOPTER; walk to it, ENTER
##   call   MORE > CALL > each row; ENTER what came
##   modes  one frame per mode and a finger on every circle
##   CRITIC_OUT=<dir> CRITIC_PARTS=find,heli BOT_RES=844x390 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=580 tools/bot.sh res://tests/bot_w118_critic.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var tree: SceneTree
var root: Window
var fg: Fingers
var p: Player
var vm: VehicleManager
var out := ""
var ms: MapScreen


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func say(ok: bool, what: String) -> void:
	print("CRITIC ", "ok   " if ok else "FAIL ", what)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("CRITIC shot ", name, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " veh ", (p.vehicle.kind if p.vehicle != null else &"-"), " hp ", int(p.hp), " state ", Game.state, " buttons ", fg.tc.visible_ids())


func tap(pos: Vector2) -> void:
	fg.down(7, pos)
	await frames(3)
	fg.up(7)
	await frames(3)


func tap_action(act: StringName) -> bool:
	var at := fg.button(act)
	if at == Vector2.INF:
		print("CRITIC no button ", act)
		return false
	await tap(at)
	return true


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	root = tree.root
	out = OS.get_environment("CRITIC_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(root)
	for n in root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	TestMode.god = OS.get_environment("CRITIC_GOD") == "1"
	CrateReveal._quiet = 0
	var city := Game.world as City
	if city != null and city.day_night != null and OS.get_environment("CRITIC_NIGHT") != "1":
		city.day_night.frozen = true
		city.day_night.set_hour(13.0)
	await frames(30)
	ms = root.find_child("MapScreen", true, false) as MapScreen
	print("CRITIC setup touch ", Game.force_touch, " controls ", fg.tc != null and fg.tc.controls_on, " quality ", Game.quality, " vp ", fg.vp(), " pos ", p.global_position)
	var parts := OS.get_environment("CRITIC_PARTS")
	for part in (parts if parts != "" else "find").split(",", false):
		print("CRITIC part ", part)
		await call("_part_" + part)
	fg.up_all()
	print("CRITIC DONE")
	_done = true


## Open the big map by a finger on the minimap, put a finger on the icon at world (x, z), close by a finger. True when the GPS goal is near it.
func gps_to(target: Vector3, name: String) -> bool:
	await tap(fg.tc._minimap_rect().get_center())
	await frames(30)
	say(MapScreen.up, "a finger on the minimap opens the map")
	if not MapScreen.up:
		return false
	await shot(name + "_map")
	var at: Vector2 = ms._map.get_global_transform() * ms.world_to_map(target.x, target.z)
	say(ms._map.get_global_rect().has_point(at), "%s icon is on the map view at %s" % [name, str(at)])
	await tap(at)
	await frames(8)
	var ok := ms.has_waypoint() and flat(ms.waypoint, target) < 15.0
	say(ok, "a finger on the %s icon sets the GPS (waypoint %s label %s route %d pts)" % [name, str(ms.waypoint), str(ms.selected.get("label", "")), ms.route_points().size()])
	await shot(name + "_map_gps")
	var c := ms.find_child("Close", true, false) as Button
	await tap(c.get_global_rect().get_center())
	await frames(10)
	say(not MapScreen.up and Game.state == &"play", "CLOSE closes the map (state %s)" % Game.state)
	return ok


## The stick vector that moves towards `to`, for the camera as it looks now.
func stick_to(to: Vector3) -> Vector2:
	var d := Vector2(to.x - p.global_position.x, to.z - p.global_position.z).normalized()
	var yaw: float = p.camera_rig.yaw
	var f := Vector2(-sin(yaw), -cos(yaw))
	var r := Vector2(cos(yaw), -sin(yaw))
	return Vector2(d.dot(r), -d.dot(f))


## Walk (or drive) along the GPS route by the stick; the right thumb turns the view along the way. `stop` ends it early. Returns true when `stop` or the goal is reached.
func follow(goal: Vector3, stop: Callable, max_frames: int, reach := 6.0, use_route := false) -> bool:
	var pts: Array[Vector3] = []
	if use_route:
		for q in ms.route_points():
			pts.append(q)
	if pts.is_empty() or flat(pts[pts.size() - 1], goal) > 3.0:
		pts.append(goal)
	var i := 0
	var last := p.global_position
	var stuck := 0
	var hp0 := p.hp
	for n in max_frames:
		if stop.call():
			fg.stick(Vector2.ZERO)
			return true
		while i < pts.size() - 1 and flat(p.global_position, pts[i]) < 5.0:
			i += 1
		if flat(p.global_position, goal) < reach:
			fg.stick(Vector2.ZERO)
			return true
		var sv := stick_to(pts[i])
		fg.stick(sv)
		if n % 20 == 10 and absf(sv.x) > 0.35:                        # the right thumb turns the view towards the way
			fg.look(signf(sv.x) * 70.0 * (1.0 if sv.y < 0.0 else 2.0), 0.0)
		if n % 60 == 59:
			if flat(p.global_position, last) < 1.0:
				stuck += 1
				print("CRITIC stuck at ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " heading to ", pts[i], " (", stuck, ")")
				fg.press(5, &"jump")
				await frames(4)
				fg.up(5)
				if stuck % 2 == 0:                                   # side step
					fg.stick(Vector2(1, 0))
					await frames(40)
			last = p.global_position
			if p.hp < hp0 - 1.0:
				print("CRITIC hurt on the way: hp ", int(p.hp))
				hp0 = p.hp
		if Game.state != &"play":
			print("CRITIC state left play: ", Game.state)
			fg.stick(Vector2.ZERO)
			return false
		await tree.process_frame
	fg.stick(Vector2.ZERO)
	return false


func _enter_label() -> bool:
	return fg.button(&"interact") != Vector2.INF and fg.button_label(&"interact") in ["ENTER", "HIJACK"]


func _part_find() -> void:
	await shot("find_0_start")
	var mm := root.find_children("*", "Minimap", true, false)[0] as Minimap
	say(mm.armour_drawn >= 1, "the minimap at the start shows armour (%d)" % mm.armour_drawn)
	var yard := ArmourSites.YARD
	await gps_to(yard, "tank")
	await shot("find_1_gps_hud")
	var bay: Vector3 = ArmourSites.YARD_BAYS[&"depot"]
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_process_frames()
	var got := await follow(yard, func() -> bool: return flat(p.global_position, yard) < 24.0, 3600, 20.0, true)
	say(got, "walked the GPS route to the yard (%d frames, now %.0f m away, hp %d)" % [Engine.get_process_frames() - f0, flat(p.global_position, yard), int(p.hp)])
	await shot("find_2_near_yard")
	var tanks: Array[String] = []
	for v in vm.list:
		if flat(v.global_position, yard) < 16.0:
			tanks.append("%s@%s" % [v.kind, str(v.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	say(tanks.size() >= 3, "vehicles on the yard: %s" % str(tanks))
	var tank: Vehicle = null
	for v in vm.list:
		if v.kind == &"tank" and flat(v.global_position, yard) < 16.0:
			tank = v
	var tgt := tank.global_position if tank != null else bay
	got = await follow(tgt, func() -> bool: return _enter_label() and tank != null and flat(p.global_position, tank.global_position) < 6.0, 900, 1.5)
	await frames(4)
	say(_enter_label(), "beside the tank the door slot reads '%s' (%.1f m from the tank)" % [fg.button_label(&"interact"), flat(p.global_position, tgt)])
	await shot("find_3_at_tank")
	await tap_action(&"interact")
	await frames(40)
	say(p.vehicle != null and p.vehicle.kind == &"tank", "ENTER puts the hero in the tank (in %s)" % (str(p.vehicle.kind) if p.vehicle != null else "nothing"))
	await shot("find_4_in_tank")
	if p.vehicle == null:
		return
	var v0 := p.vehicle.global_position
	fg.stick(Vector2(0, -1))
	await frames(150)
	await shot("find_5_tank_drive")
	say(flat(p.vehicle.global_position, v0) > 10.0, "the stick drives the tank (%.1f m in 5 s)" % flat(p.vehicle.global_position, v0))
	fg.stick(Vector2(-1, -0.3))
	await frames(60)
	fg.look(160.0, 0.0)
	await frames(20)
	fg.press(6, &"fire")
	await frames(6)
	await shot("find_6_tank_fire")
	fg.up(6)
	fg.stick(Vector2.ZERO)
	await frames(40)
	await shot("find_7_tank_after")
	for a: StringName in fg.tc.visible_ids():
		print("CRITIC tank button ", a)
	await tap_action(&"interact")
	await frames(40)
	say(p.vehicle == null, "EXIT leaves the tank")
	await shot("find_8_out")
	print("CRITIC find took ", (Time.get_ticks_msec() - t0) / 1000, " s wall")


func _part_heli() -> void:
	var pad := ArmourSites.PAD_EAST
	await gps_to(pad, "heli")
	var got := await follow(pad, func() -> bool: return flat(p.global_position, pad) < 20.0, 5400, 16.0, true)
	say(got, "walked the GPS route to the helipad (now %.0f m away, hp %d)" % [flat(p.global_position, pad), int(p.hp)])
	await shot("heli_0_near_pad")
	var heli: Vehicle = null
	for v in vm.list:
		if flat(v.global_position, pad) < 14.0 and v.kind in [&"heli", &"gunship"]:
			heli = v
	say(heli != null, "a helicopter stands on the pad")
	if heli == null:
		return
	await follow(heli.global_position, func() -> bool: return _enter_label() and flat(p.global_position, heli.global_position) < 6.0, 900, 1.5)
	await frames(4)
	say(_enter_label(), "beside the helicopter the door slot reads '%s'" % fg.button_label(&"interact"))
	await shot("heli_1_at")
	await tap_action(&"interact")
	await frames(40)
	say(p.vehicle != null and p.vehicle == heli, "ENTER puts the hero in the helicopter (in %s)" % (str(p.vehicle.kind) if p.vehicle != null else "nothing"))
	await shot("heli_2_in")
	if p.vehicle == null:
		return
	fg.press(1, &"jump")
	await frames(150)
	await shot("heli_3_up")
	say(p.vehicle.global_position.y > 6.0, "UP lifts it (%.1f m)" % p.vehicle.global_position.y)
	fg.up(1)
	var v0 := p.vehicle.global_position
	fg.stick(Vector2(0, -1))
	await frames(120)
	await shot("heli_4_fwd")
	say(flat(p.vehicle.global_position, v0) > 10.0, "the stick flies it forward (%.1f m in 4 s)" % flat(p.vehicle.global_position, v0))
	fg.press(6, &"fire")
	await frames(10)
	await shot("heli_5_fire")
	fg.up(6)
	fg.stick(Vector2.ZERO)
	for a: StringName in [&"aim", &"veh_view"]:
		if fg.button(a) != Vector2.INF:
			await tap_action(a)
			await frames(10)
			await shot("heli_6_%s" % a)
	for a: StringName in fg.tc.visible_ids():
		print("CRITIC heli button ", a)
	var down_act: StringName = &"crouch"
	if fg.button(down_act) == Vector2.INF:
		print("CRITIC no crouch (DOWN) button; visible ", fg.tc.visible_ids())
	fg.press(2, down_act)
	var landed := await until(func() -> bool: return p.vehicle != null and p.vehicle.global_position.y < 1.6, 600)
	fg.up(2)
	await frames(30)
	say(landed, "DOWN lands it (%.1f m)" % (p.vehicle.global_position.y if p.vehicle != null else -1.0))
	await shot("heli_7_landed")
	await tap_action(&"interact")
	await frames(40)
	say(p.vehicle == null, "EXIT leaves the helicopter")
	await shot("heli_8_out")


func _demo_tap_row(dp: DemoPanel, label: String) -> bool:
	dp.layout()
	for it in dp.items:
		if not it.get("head", false) and String(it["label"]) == label:
			var r: Rect2 = it["rect"]
			var at := Vector2(r.get_center().x, r.get_center().y + dp._top() - dp.scroll)
			if at.y > fg.vp().y - 4.0 or at.y < dp._top():
				print("CRITIC demo row ", label, " is off the screen at ", at)
				return false
			await tap(at)
			return true
	print("CRITIC demo row ", label, " missing")
	return false


func _part_demo() -> void:
	Game.state = &"menu"                                               # setup: the title screen
	await frames(20)
	var hud := tree.get_first_node_in_group(&"hud") as Hud
	await shot("demo_t0_title")
	for id: StringName in [&"menu_gear", &"demo"]:
		for b: Dictionary in hud.buttons:
			if b["id"] == id and not DemoMode.active:
				print("CRITIC title button ", id, " ", b["rect"])
				await tap((b["rect"] as Rect2).get_center())
				await frames(12)
				await shot("demo_t1_%s" % id)
	say(DemoMode.active and Game.state == &"play", "DEMO started from the title by fingers (active %s state %s)" % [DemoMode.active, Game.state])
	await frames(90)
	p = Game.player as Player
	await shot("demo_0_hud")
	var dp := root.find_children("*", "DemoPanel", true, false)[0] as DemoPanel
	await tap(dp.entry_rect().get_center())
	await frames(10)
	say(dp.is_open, "a finger on the DEMO badge opens the DEMO menu")
	await shot("demo_1_menu")
	await tap(dp._tab_rects()[DemoPanel.TABS.find("SPAWN")].get_center())
	await frames(6)
	await shot("demo_2_spawn")
	var before := vm.list.size()
	say(await _demo_tap_row(dp, VehicleSpecs.name_of(&"tank")), "finger on the TANK row")
	await frames(6)
	await shot("demo_3_after_tank")
	say(await _demo_tap_row(dp, VehicleSpecs.name_of(&"heli")), "finger on the HELICOPTER row")
	await frames(6)
	await tap(dp._close_rect().get_center())
	await frames(10)
	say(not dp.is_open and Game.state == &"play", "CLOSE closes the DEMO menu (state %s)" % Game.state)
	await frames(30)
	await shot("demo_4_world")
	var got: Array[String] = []
	var tank: Vehicle = null
	for v in vm.list:
		if v.has_meta(&"called"):
			got.append("%s %.0f m" % [v.kind, flat(v.global_position, p.global_position)])
			if v.kind == &"tank":
				tank = v
	say(tank != null, "the demo list delivered: %s (%d -> %d)" % [str(got), before, vm.list.size()])
	if tank == null:
		return
	fg.look(0.0, 0.0)
	await follow(tank.global_position, func() -> bool: return _enter_label() and flat(p.global_position, tank.global_position) < 6.0, 600, 1.5)
	await frames(4)
	await shot("demo_5_at_tank")
	await tap_action(&"interact")
	await frames(40)
	say(p.vehicle == tank, "ENTER takes the demo tank (in %s)" % (str(p.vehicle.kind) if p.vehicle != null else "nothing"))
	await shot("demo_6_in_tank")
	if p.vehicle != null:
		await tap_action(&"interact")
		await frames(40)


func _call(row: String, name: String) -> Vehicle:
	if not fg.tc.more_open:
		await tap_action(&"more")
		await frames(6)
	await shot("call_%s_0_more" % name)
	var okc := await tap_action(&"garage_call")
	await frames(8)
	say(okc and CallIn.is_open(), "MORE > CALL opens the list")
	await shot("call_%s_1_list" % name)
	if not CallIn.is_open():
		return null
	var b := CallIn.instance.find_child(row, true, false) as Button
	var n0 := vm.list.duplicate()
	await tap(b.get_global_rect().get_center())
	await frames(30)
	var v: Vehicle = null
	for q in vm.list:
		if not n0.has(q) or (q.has_meta(&"called") and flat(q.global_position, p.global_position) < 30.0 and v == null):
			v = q
	say(v != null, "CALL %s delivered %s at %.0f m; list open %s; MORE open %s" % [name, (str(v.kind) if v != null else "nothing"), (flat(v.global_position, p.global_position) if v != null else -1.0), CallIn.is_open(), fg.tc.more_open])
	await shot("call_%s_2_came" % name)
	return v


func _board(v: Vehicle, name: String) -> bool:
	await follow(v.global_position, func() -> bool: return _enter_label() and flat(p.global_position, v.global_position) < 7.0, 600, 1.5)
	await frames(4)
	say(_enter_label(), "beside the %s the door slot reads '%s' (%.1f m)" % [name, fg.button_label(&"interact"), flat(p.global_position, v.global_position)])
	await shot("board_%s_0" % name)
	await tap_action(&"interact")
	await frames(40)
	say(p.vehicle == v, "ENTER takes the %s (in %s)" % [name, (str(p.vehicle.kind) if p.vehicle != null else "nothing")])
	return p.vehicle == v


## A finger on every circle of the mode, one after the other; prints what is on screen.
func _press_all(name: String) -> void:
	await shot("mode_%s" % name)
	var ids := fg.tc.visible_ids()
	for a: StringName in ids:
		if a in [&"interact", &"more", &"pause", &"fly", &"stick"]:
			continue
		var at := fg.button(a)
		if at == Vector2.INF:
			continue
		var veh := p.vehicle
		var pos0 := p.global_position
		fg.down(6, at)
		await frames(12)
		var held := Input.is_action_pressed(a)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/mode_%s_press_%s.png" % [out, name, a])
		fg.up(6)
		await frames(20)
		print("CRITIC press %s/%s label '%s' at %s action_held %s moved %.1f veh_same %s state %s" % [name, a, fg.button_label(a), str(at.round()), held, p.global_position.distance_to(pos0), p.vehicle == veh, Game.state])
		if Game.state != &"play":
			print("CRITIC ", a, " left play: ", Game.state)
			return


func _part_modes() -> void:
	await _press_all("foot")
	if not fg.tc.more_open:
		await tap_action(&"more")
		await frames(6)
	await shot("mode_foot_more")
	await tap_action(&"more")
	await frames(6)
	# snake flight
	await tap_action(&"fly")
	await frames(60)
	say(fg.button_label(&"fly") == "LAND", "FLY takes off: the door slot reads '%s' at height %.1f" % [fg.button_label(&"fly"), p.global_position.y])
	await _press_all("flight")
	# CALL from the air (hovering low over the street)
	var vair := await _call("Call_Tank", "air_tank")
	say(vair != null, "CALL > TANK works while hovering in snake flight at %.1f m" % p.global_position.y)
	if CallIn.is_open():
		CallIn.close()
	if fg.tc.more_open:
		await tap_action(&"more")
		await frames(4)
	if fg.button_label(&"fly") == "LAND":
		await tap_action(&"fly")
	say(await until(func() -> bool: return p.is_on_floor() and fg.button_label(&"fly") == "FLY", 300), "LAND lands (y %.1f, slot '%s')" % [p.global_position.y, fg.button_label(&"fly")])
	await frames(30)
	await shot("mode_after_land")
	ArmourSites.reset_calls()                                          # setup: no cooldown left from the air call
	for row: Array in [["Call_Car", "car"], ["Call_Tank", "tank"], ["Call_Helicopter", "heli"], ["Call_Plane", "plane"]]:
		var v := await _call(row[0], row[1])
		if fg.tc.more_open:
			await tap_action(&"more")
			await frames(4)
		if v == null:
			continue
		if await _board(v, row[1]):
			await frames(30)
			await _press_all(row[1])
			if not fg.tc.more_open:
				await tap_action(&"more")
				await frames(6)
				await shot("mode_%s_more" % row[1])
				await tap_action(&"more")
				await frames(6)
			if p.vehicle != null and p.vehicle.global_position.y > 3.0 and fg.button(&"crouch") != Vector2.INF:
				fg.press(2, &"crouch")
				await until(func() -> bool: return p.vehicle == null or p.vehicle.global_position.y < 1.6, 500)
				fg.up(2)
				await frames(20)
			await tap_action(&"interact")
			await frames(50)
			say(p.vehicle == null, "EXIT leaves the %s" % row[1])
			fg.stick(Vector2(1, 0))                                   # step away
			await frames(60)
			fg.stick(Vector2.ZERO)
