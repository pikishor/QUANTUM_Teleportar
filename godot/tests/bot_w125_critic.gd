extends RefCounted
## WAVE 125 critic (w125-critic): a FINGER-ONLY review bot in the real main scene. Every action is a real InputEventScreenTouch / ScreenDrag (tests/w116_fingers.gd);
## only the setup (a helicopter parked in front of the hero, the hero placed, the hour) is done by code. Per kind: ENTER, hold UP, stick forward, shot (chase), VIEW x2 (cockpit) shot,
## frame time and draws printed, DOWN, EXIT. Then pads: board, placed 30 m over a pad, DOWN to land, shot. Then a crash into a building.
##   CR_OUT=<dir> CR_TAG=q0 OUT_HOUR=11 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=1200 tools/bot.sh res://tests/bot_w125_critic.gd /tmp/x 100000 1
## CR_PARTS: kinds,pads,crash (default all). CR_KINDS: comma list.
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var fg: Fingers
var p: Player
var vm: VehicleManager
var out := ""
var tag := ""


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _on(part: String) -> bool:
	var parts := OS.get_environment("CR_PARTS").split(",", false)
	return parts.is_empty() or parts.has(part)


func _pf(n: int) -> void:
	for i in n:
		await (Engine.get_main_loop() as SceneTree).physics_frame


func _until(c: Callable, n: int) -> bool:
	for i in n:
		if c.call():
			return true
		await (Engine.get_main_loop() as SceneTree).physics_frame
	return c.call()


func _shot(name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _pf(4)
	fg.up(6)
	await _pf(4)
	return true


func _perf(label: String) -> void:
	var ft := 0.0
	var dr := 0.0
	for i in 20:
		await (Engine.get_main_loop() as SceneTree).process_frame
		ft += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		dr += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("CR PERF %s %s process_ms=%.2f draws=%.0f prims=%.0f" % [tag, label, ft / 20.0, dr / 20.0, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])


func _board(kind: StringName, at: Vector3) -> Vehicle:
	if vm.driven != null:
		await _tap(&"interact")
		await _pf(10)
	p.teleport_to(at)
	p.velocity = Vector3.ZERO
	p.yaw = 0.0
	p.camera_rig.reset_view(0.0, -0.15)
	await _pf(20)
	DemoMenu.spawn_vehicle(kind)
	var v: Vehicle = null
	for c: Vehicle in vm.list:
		if is_instance_valid(c) and c.kind == kind and (v == null or c.global_position.distance_to(p.global_position) < v.global_position.distance_to(p.global_position)):
			v = c
	if v == null:
		print("CR %s: no spawn" % kind)
		return null
	fg.stick(Vector2(0.0, -1.0))
	var ok := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 400)
	fg.stick(Vector2.ZERO)
	await _pf(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 60)
	print("CR BOARD %s reach=%s in=%s (%s)" % [kind, ok, p.vehicle == v, p.vehicle.kind if p.vehicle else &"-"])
	return v if p.vehicle == v else null


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("CR_OUT")
	tag = OS.get_environment("CR_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	Game.force_touch = true
	var prog := Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	Game.state = &"play"
	CrateReveal._quiet = 0
	await _pf(30)
	fg = Fingers.new(tree.root.get_child(0))
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	TestMode.god = true
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	var city: Node = Game.world
	if city != null and city.get(&"day_night") != null:
		city.day_night.frozen = true
		city.day_night.set_hour(float(OS.get_environment("OUT_HOUR")) if OS.get_environment("OUT_HOUR") != "" else 11.0)
	for k in 6:
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		fg.down(7, fg.vp() * Vector2(0.5, 0.3))
		await _pf(3)
		fg.up(7)
		await _pf(6)
	if OS.get_environment("CR_PARTS") == "draws":
		await _draws()
		fg.up_all()
		_done = true
		tree.quit()
		return
	if _on("kinds"):
		var pick := OS.get_environment("CR_KINDS").split(",", false)
		for k: StringName in HeliRoster.KINDS:
			if not pick.is_empty() and not pick.has(String(k)):
				continue
			var v := await _board(k, _open())
			if v == null:
				continue
			fg.press(1, &"jump")
			var up := await _until(func() -> bool: return VehicleCraft.altitude(v) > 25.0, 900)
			fg.up(1)
			fg.stick(Vector2(0.0, -1.0))
			var from := v.global_position
			var sp := []
			for j in 6:
				await _pf(60)
				sp.append("%.0f" % (v.speed * 3.6))
			print("CR SPEEDS %s kmh %s max %.0f" % [k, ",".join(sp), float(v.spec.get("max", -1.0)) * 3.6])
			await _shot("chase_" + String(k))
			fg.stick(Vector2.ZERO)
			print("CR FLY %s up=%s alt=%.1f moved=%.0f speed=%.1f hp=%.0f" % [k, up, VehicleCraft.altitude(v), Vector2(v.global_position.x - from.x, v.global_position.z - from.z).length(), v.speed, v.hp])
			await _perf("chase " + String(k))
			for i in 2:
				await _tap(&"veh_view")
				await _pf(10)
			print("CR VIEW %s veh_view=%d label=%s" % [k, p.camera_rig.veh_view, fg.button_label(&"veh_view")])
			await _shot("cockpit_" + String(k))
			await _perf("cockpit " + String(k))
			await _tap(&"veh_view")
			fg.press(1, &"crouch")
			var landed := await _until(func() -> bool: return not v.craft.airborne and absf(v.speed) < 6.0, 1500)
			fg.up(1)
			print("CR LAND %s landed=%s" % [k, landed])
			await _tap(&"interact")
			await _pf(10)
			vm._release(v)
			await _pf(4)
	if _on("pads"):
		var want := OS.get_environment("CR_PADS").split(",", false)
		var n := 0
		for pd in Helipads.all():
			if not want.is_empty() and not want.has(String(pd["id"])):
				continue
			if want.is_empty() and (pd["src"] != &"w125" or n >= 6):
				continue
			n += 1
			var c: Vector3 = pd["pos"]
			var v := await _board_pad(pd)
			if v == null:
				print("CR PAD %s board failed (no helicopter in reach)" % pd["id"])
				await _shot("padfail_" + String(pd["id"]))
				continue
			fg.press(1, &"jump")
			await _until(func() -> bool: return VehicleCraft.altitude(v) > 8.0, 600)
			fg.up(1)
			v.global_position = c + Vector3(0.0, 30.0, 0.0)          # setup: over the pad (the pad's own helicopter, lifted off it)
			v.heading = 0.0
			await _pf(5)
			var parks := Helipads.parks
			fg.press(1, &"crouch")
			await _until(func() -> bool: return not v.craft.airborne and absf(v.speed) < 6.0, 1500)
			fg.up(1)
			await _pf(30)
			print("CR PAD %s %s role=%s landed_dy=%.2f flat=%.1f parked=%s waiting_heli=%s" % [pd["id"], pd["name"], pd["role"], v.global_position.y - c.y, Vector2(v.global_position.x - c.x, v.global_position.z - c.z).length(), Helipads.parks > parks, str(vm.list.filter(func(x: Vehicle) -> bool: return x != v and x.global_position.distance_to(c) < 16.0).map(func(x: Vehicle) -> String: return String(x.kind)))])
			await _shot("pad_" + String(pd["id"]))
			await _tap(&"interact")
			await _pf(20)
			p.camera_rig.reset_view(PI, -0.4)
			await _pf(10)
			await _shot("padfoot_" + String(pd["id"]))
	if _on("crash"):
		var v := await _board(&"h_utility", Vector3(-30.0, 0.0, 4.0))
		if v != null:
			fg.press(1, &"jump")
			await _until(func() -> bool: return VehicleCraft.altitude(v) > 14.0, 900)
			fg.up(1)
			# setup: point it at the nearest wall found by a ray at its height
			var space := v.get_world_3d().direct_space_state
			var best := -1.0
			for i in 16:
				var a := TAU * float(i) / 16.0
				var dir := Vector3(-sin(a), 0.0, -cos(a))
				var q := PhysicsRayQueryParameters3D.create(v.global_position, v.global_position + dir * 120.0)
				q.exclude = [v.get_rid()]
				var r := space.intersect_ray(q)
				if not r.is_empty() and r.position.distance_to(v.global_position) > 30.0 and (best < 0.0 or r.position.distance_to(v.global_position) < best):
					best = r.position.distance_to(v.global_position)
					v.heading = a
			var hp0 := v.hp
			print("CR CRASH wall at %.0f m heading %.2f" % [best, v.heading])
			fg.stick(Vector2(0.0, -1.0))
			await _pf(600)
			fg.stick(Vector2.ZERO)
			print("CR CRASH hp %.0f -> %.0f alive=%s in=%s" % [hp0, v.hp if is_instance_valid(v) else -1.0, is_instance_valid(v), p.vehicle != null])
			await _shot("crash")
	fg.up_all()
	_done = true
	tree.quit()


func _open() -> Vector3:
	var o := OS.get_environment("CR_AT")
	if o == "city":
		return Vector3(-30.0, 0.0, 4.0)
	return Airport.to_world(Vector3(1310.0, 0.0, -700.0))


## The hero on the pad, 7 m from its centre; the stick walks him to the pad's own waiting helicopter, a finger on ENTER boards it.
func _board_pad(pd: Dictionary) -> Vehicle:
	if vm.driven != null:
		await _tap(&"interact")
		await _pf(10)
	var c: Vector3 = pd["pos"]
	p.teleport_to(c + Vector3(0.0, 0.6, 0.0))
	p.velocity = Vector3.ZERO
	await _pf(90)
	var v: Vehicle = null
	for x: Vehicle in vm.list:
		if is_instance_valid(x) and x.cls == &"heli" and x.global_position.distance_to(c) < 14.0:
			v = x
	if v == null:
		print("CR PAD %s: no helicopter waits on it (vehicles near: %d)" % [pd["id"], vm.list.filter(func(x: Vehicle) -> bool: return x.global_position.distance_to(c) < 40.0).size()])
		await _shot("padempty_" + String(pd["id"]))
		return null
	var off := v.global_position - c
	off.y = 0.0
	var dir := off.normalized() if off.length() > 0.5 else Vector3(0, 0, 1)
	var stand := v.global_position - dir * (float(v.spec.get("len", 10.0)) * 0.5 + 5.0)
	stand.y = c.y + 0.6
	p.teleport_to(stand)
	var yaw := atan2(dir.x, dir.z) + PI
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, -0.15)
	p.velocity = Vector3.ZERO
	await _pf(30)
	await _shot("padheli_" + String(pd["id"]))
	fg.stick(Vector2(0.0, -1.0))
	var ok := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 400)
	fg.stick(Vector2.ZERO)
	await _pf(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 60)
	print("CR PADBOARD %s kind=%s reach=%s in=%s hero_dy=%.1f" % [pd["id"], v.kind, ok, p.vehicle == v, p.global_position.y - c.y])
	return v if p.vehicle == v else null


## CHECK (CR_PARTS=draws, real renderer): the cockpit view costs at most 10 draw calls more than the chase view of the same helicopter in the same hover (it hides the
## machine's own model). w125-critic defect: the cockpit painted each gauge circle, arc and polygon as its own draw (+30 at LOW). W125C_OLD=1 = the old painting.
func _draws() -> void:
	var worst := 0.0
	for k: StringName in [&"h_scout", &"h_heavy", &"h_attack"]:
		var v := await _board(k, _open())
		if v == null:
			print("W125C DRAWS FAIL: %s not boarded" % k)
			continue
		fg.press(1, &"jump")
		await _until(func() -> bool: return VehicleCraft.altitude(v) > 25.0, 900)
		fg.up(1)
		await _pf(60)
		var ch := await _draw_avg()
		for i in 2:
			await _tap(&"veh_view")
			await _pf(10)
		var ck := await _draw_avg()
		await _shot("drawcheck_cockpit_" + String(k))
		print("W125C DRAWS %s chase=%.0f cockpit=%.0f delta=%.0f view=%d" % [k, ch, ck, ck - ch, p.camera_rig.veh_view])
		worst = maxf(worst, ck - ch)
		await _tap(&"veh_view")
		fg.press(1, &"crouch")
		await _until(func() -> bool: return not v.craft.airborne, 1500)
		fg.up(1)
		await _tap(&"interact")
		await _pf(10)
		vm._release(v)
		await _pf(4)
	print("W125C DRAWS %s: the cockpit adds at most 10 draws (worst %.0f)" % ["ok" if worst <= 10.0 else "FAIL", worst])


func _draw_avg() -> float:
	var dr := 0.0
	for i in 30:
		await (Engine.get_main_loop() as SceneTree).process_frame
		dr += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	return dr / 30.0
