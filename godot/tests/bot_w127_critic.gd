extends RefCounted
## w127-critic LOOK BOT: frames of the wave 127 military vehicles as the phone player sees them. The hero boards each vehicle with REAL fingers (tests/w116_fingers.gd: stick, ENTER),
## drives it with the stick and turns the turret with the right thumb; the bot places the hero / camera only to set up a view.
##   CR_OUT=<dir> CR_TAG=q0 CR_ONLY=drive|perf CR_KINDS=t_apc8,t_mrap QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=1500 tools/bot.sh res://tests/bot_w127_critic.gd /tmp/x 100000 1
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
	await RenderingServer.frame_post_draw
	(Engine.get_main_loop() as SceneTree).root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])
	print("CR SHOT %s" % name)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _pf(4)
	fg.up(6)
	await _pf(4)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _stand(at: Vector3, face: Vector3) -> void:
	fg.up_all()
	if p.vehicle != null:
		await _tap(&"interact")
		await _pf(20)
	var d := face - at
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(at + Vector3(0.0, 0.4, 0.0))
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, -0.1)
	await _pf(20)


## Frame timing and draws over `n` frames: [avg ms, worst ms, draws, prims].
func _measure(n: int) -> Array:
	var tot := 0.0
	var worst := 0.0
	var draws := 0
	var prims := 0
	var last := Time.get_ticks_usec()
	for i in n:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		tot += ms
		worst = maxf(worst, ms)
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return [tot / float(n), worst, draws, prims]


func _run(_tree: SceneTree) -> void:
	out = OS.get_environment("CR_OUT")
	tag = OS.get_environment("CR_TAG")
	var only := OS.get_environment("CR_ONLY")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.state = &"play"
	Game.force_touch = true
	CrateReveal._quiet = 0
	TestMode.god = true
	fg = Fingers.new(p)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	await _pf(30)
	DemoMenu.set_time(13.0)
	TestMode.set_weather("CLEAR")
	TankRoster._points.clear()
	if only == "" or only == "drive":
		await _drive()
	if only == "perf":
		await _perf()
	_done = true


func _drive() -> void:
	var pick := OS.get_environment("CR_KINDS").split(",", false)
	for pt: Dictionary in TankRoster.spawn_points():
		var k: StringName = pt["kind"]
		if not pick.is_empty() and not String(k) in pick:
			continue
		var pos: Vector3 = pt["pos"]
		var hh := float(pt["h"])
		var fwd := Vector3(-sin(hh), 0.0, -cos(hh))
		await _stand(pos + fwd * (float(VehicleSpecs.SPECS[k]["len"]) * 0.5 + 3.5), pos)
		vm._spawn_t = 0.0
		var ok := await _until(func() -> bool: return is_instance_valid(vm._spawned.get(pt["id"])) and (vm._spawned.get(pt["id"]) as Vehicle).active, 900)
		if not ok:
			print("CR %s: nothing at its place" % k)
			continue
		var v: Vehicle = vm._spawned.get(pt["id"])
		await _pf(30)
		p.camera_rig.reset_view(hh + 2.4, -0.2)
		await _pf(30)
		await _shot("parked_%s" % k)
		var dd := v.global_position - p.global_position
		p.camera_rig.reset_view(atan2(-dd.x, -dd.z), -0.1)
		await _pf(5)
		fg.stick(Vector2(0.0, -1.0))
		await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 600)
		fg.stick(Vector2.ZERO)
		await _pf(3)
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == v, 60)
		if p.vehicle != v:
			print("CR %s: could not board" % k)
			continue
		fg.stick(Vector2(0.3, -1.0))
		await _pf(140)
		await _shot("drive_%s" % k)
		fg.stick(Vector2(0.0, 1.0))
		await _until(func() -> bool: return absf(v.speed) < 0.8, 300)
		fg.stick(Vector2.ZERO)
		fg.look(fg.vp().x * 0.35, 0.0)
		await _pf(90)
		await _shot("turret_%s" % k)
		var m := await _measure(20)
		print("CR %s: avg %.1f ms worst %.1f ms draws %d prims %d" % [k, m[0], m[1], m[2], m[3]])
		await _tap(&"interact")
		await _pf(20)


## Several tanks in view: six kinds parked in a fan 25-60 m in front of a boarded battle tank on the airport apron.
func _perf() -> void:
	var at := Airport.to_world(Vector3(1255.0, 0.0, -800.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	var h := Airport.heading_world(-PI * 0.5)
	var fwd := Vector3(-sin(h), 0.0, -cos(h))
	var rt := Vector3(cos(h), 0.0, -sin(h))
	vm._reset_all()
	await _pf(4)
	vm._fixed_n += 1
	var mine := vm.spawn_parked(&"t_heavy", at, h)
	mine.set_meta(&"hold", true)
	mine.set_meta(&"called", true)
	vm._count_fixed()
	var kinds := [&"t_heavy", &"t_apc8", &"t_walker", &"t_hover", &"t_mine", &"t_rocket", &"t_halftrack", &"tank"]
	var made := 0
	for i in kinds.size():
		var w := at + fwd * (25.0 + 8.0 * float(i)) + rt * (float(i % 4) - 1.5) * 12.0
		w.y = TerrainHeight.height_at(w.x, w.z)
		vm._fixed_n += 1
		var v := vm.spawn_parked(kinds[i], w, h + 0.6 * float(i))
		if v != null:
			v.set_meta(&"hold", true)
			v.set_meta(&"called", true)
			made += 1
		vm._count_fixed()
		vm._fixed_n += 0
	print("CR PERF %d of %d tanks stand in view" % [made, kinds.size()])
	await _stand(at - fwd * 9.0, at)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 600)
	fg.stick(Vector2.ZERO)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == mine, 60)
	p.camera_rig.reset_view(h, -0.08)
	await _pf(120)
	var m := await _measure(60)
	print("CR PERF parked view: avg %.1f ms worst %.1f ms draws %d prims %d (in tank %s)" % [m[0], m[1], m[2], m[3], p.vehicle != null])
	await _shot("perf_view")
	fg.stick(Vector2(0.0, -1.0))
	var m2 := await _measure(60)
	fg.stick(Vector2.ZERO)
	print("CR PERF driving: avg %.1f ms worst %.1f ms draws %d prims %d" % [m2[0], m2[1], m2[2], m2[3]])
	await _shot("perf_drive")
