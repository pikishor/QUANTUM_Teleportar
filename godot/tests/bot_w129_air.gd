extends RefCounted
## WAVE 129 look bot (w129-airdraws): the airfield frames at phone aspect. The hero is placed at each view by code (a look bot, not a check); boarding and the VIEW button go by
## real finger events (tests/w116_fingers.gd).
##   AW_OUT=<dir> AW_TAG=new AW_ONLY=cockpit,doors QUALITY=1 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w129_air.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var p: Player
var fg: Fingers
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
	_run()
	return false


func _pf(n: int) -> void:
	for i in n:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await _pf(1)
	return cond.call()


func _shot(name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])
	print("AW SHOT %s draws %d" % [name, PerfProbe.snapshot(tree.root)["total_draws"]])


func _stand(at: Vector3, look: Vector3, pitch := -0.1) -> void:
	var w := Airport.to_world(at)
	w.y = TerrainHeight.height_at(w.x, w.z) + 0.3
	var lw := Airport.to_world(look)
	var d := lw - w
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(w)
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, pitch)
	vm._spawn_t = 0.0
	await _pf(60)


func _board_near(local: Vector3, cls: StringName) -> bool:
	var w := Airport.to_world(local)
	var best: Vehicle = null
	var bd := 80.0
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.active and VehicleSpecs.cls_of(v.kind) == cls:
			var dd := Vector2(v.global_position.x - w.x, v.global_position.z - w.z).length()
			if dd < bd:
				bd = dd
				best = v
	if best == null:
		print("AW nothing of %s near" % cls)
		return false
	var d := best.global_position - p.global_position
	p.camera_rig.reset_view(atan2(-d.x, -d.z), -0.1)
	await _pf(3)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 600)
	fg.stick(Vector2.ZERO)
	await _pf(3)
	fg.press(2, &"interact")
	await _pf(4)
	fg.up(2)
	await _until(func() -> bool: return p.vehicle == best, 90)
	return p.vehicle == best


func _tap(action: StringName) -> void:
	if fg.press(2, action):
		await _pf(4)
		fg.up(2)
	await _pf(6)


func _leave() -> void:
	if p.vehicle != null:
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == null, 90)
		if p.vehicle != null:
			vm.exit_vehicle()
	await _pf(10)


func _run() -> void:
	out = OS.get_environment("AW_OUT")
	tag = OS.get_environment("AW_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.state = &"play"
	CrateReveal._quiet = 0
	TestMode.god = true
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	DemoMenu.set_time(13.0)
	TestMode.set_weather("CLEAR")
	fg = Fingers.new(p)
	await _pf(30)
	var only := OS.get_environment("AW_ONLY").split(",", false)
	if only.is_empty() or only.has("cockpit"):
		await _stand(Vector3(1240.0, 0.0, -700.0), Vector3(1250.0, 3.0, -700.0))
		vm._fixed_n += 1
		var hk := StringName(OS.get_environment("AW_HELI")) if OS.get_environment("AW_HELI") != "" else &"h_police"
		var hv := vm.spawn_parked(hk, p.global_position + Vector3(0.0, 0.0, -9.0), 0.0)
		if hv != null:
			hv.set_meta(&"hold", true)
		vm._count_fixed()
		await _pf(10)
		if await _board_near(Airport.to_local(p.global_position + Vector3(0.0, 0.0, -9.0)), &"heli"):
			await _pf(30)
			await _shot("heli_chase")
			for i in 3:
				if p.camera_rig.veh_view == 2:
					break
				await _tap(&"veh_view")
			await _pf(30)
			await _shot("heli_cockpit")
			fg.stick(Vector2(0.0, -0.6))
			await _pf(20)
			await _shot("heli_cockpit_stick")
			fg.stick(Vector2.ZERO)
		await _leave()
	if only.is_empty() or only.has("plane"):
		await _stand(Vector3(1196.0, 0.0, -900.0), Vector3(1182.0, 0.0, -908.0))
		if await _board_near(Vector3(1182.0, 0.0, -908.0), &"plane"):
			await _pf(30)
			await _shot("jet_chase")
			for i in 3:
				await _tap(&"veh_view")
				await _pf(20)
				await _shot("jet_view%d" % i)
		await _leave()
	if only.is_empty() or only.has("picker"):
		await _stand(Vector3(1145.0, 0.0, -940.0), Vector3(1170.0, 3.0, -940.0), -0.05)
		await _pf(60)
		await _shot("picker_chip")
		var hp := HangarPicker.instance
		if hp != null and hp.chip.visible:
			fg.down(2, hp.chip.get_global_rect().get_center())
			await _pf(3)
			fg.up(2)
			await _pf(10)
			await _shot("picker_list")
			if hp.grid.get_child_count() > 0:
				var b := hp.grid.get_child(0) as Button
				fg.down(2, b.get_global_rect().get_center())
				await _pf(3)
				fg.up(2)
				await _pf(90)
				await _shot("picker_rolled")
	if only.is_empty() or only.has("doors"):
		await _stand(Vector3(1192.0, 0.0, -940.0), Vector3(1136.0, 6.0, -940.0), -0.02)
		await _pf(200)
		await _shot("hangar_a_open")
		await _stand(Vector3(1362.0, 0.0, -712.0), Vector3(1360.0, 4.0, -775.0), -0.02)
		await _pf(200)
		await _shot("shelter_open")
	if only.is_empty() or only.has("lines"):
		await _stand(Vector3(1262.0, 0.0, -760.0), Vector3(1320.0, 0.0, -760.0), -0.15)
		await _shot("runway_east_lines")
		await _stand(Vector3(1300.0, 0.0, -560.0), Vector3(1300.0, 0.0, -700.0), -0.15)
		await _shot("plane_line_north")
	if only.is_empty() or only.has("apron"):
		await _stand(Vector3(1205.0, 0.0, -700.0), Vector3(1150.0, 2.0, -640.0))
		await _shot("apron")
	_done = true
