extends RefCounted
## WAVE 128 critic look bot (w128-critic): every helicopter and plane kind parked on the airfield in daylight, shot close up from the front 3/4 and the rear 3/4 by the game camera (frames only;
## the kinds are placed by code, the checks with fingers live in tests/test_w128_critic.gd).
##   CR_OUT=<dir> CR_TAG=q1 CR_KINDS=h_scout,p_cub QUALITY=1 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=1500 tools/bot.sh res://tests/bot_w128_critic.gd /tmp/x 100000 1
var _started := false
var _done := false
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


func _shot(name: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("CR_OUT")
	tag = OS.get_environment("CR_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.state = &"play"
	TestMode.god = true
	var dn: DayNight = (Game.world as City).day_night
	dn.frozen = true
	dn.set_hour(11.0)
	for w in tree.root.find_children("*", "Weather", true, false):
		w.call("set_state", &"clear", true)
	for h in tree.get_nodes_in_group(&"hud"):
		h.set("visible", false)
	await _pf(30)
	if OS.get_environment("CR_ONLY") == "perf":
		await _perf()
		_done = true
		tree.quit()
		return
	var kinds := OS.get_environment("CR_KINDS").split(",", false)
	if kinds.is_empty():
		for k in HeliRoster.KINDS:
			kinds.append(String(k))
		for k in PlaneRoster.KINDS:
			kinds.append(String(k))
	var at := Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	p.teleport_to(at + Vector3(-60.0, 0.5, 0.0))
	await _pf(90)
	p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	for k in kinds:
		vm._release_farthest(at)
		vm._release_farthest(at)
		var v := vm.spawn_parked(StringName(k), at, 0.0)
		if v == null:
			print("CR no %s" % k)
			continue
		await _pf(20)
		var sp: Dictionary = v.spec
		var size := maxf(float(sp["len"]), float(sp.get("span", sp["wid"])))
		var c := v.global_position + Vector3(0.0, float(sp.get("hgt", 3.0)) * 0.45, 0.0)
		var b := v.global_transform.basis
		var views := [["f3q", Vector3(0.75, 0.32, -0.85), 1.05], ["r3q", Vector3(-0.8, 0.35, 0.9), 1.05]]
		if OS.get_environment("CR_NEAR") == "1":
			views.append(["near", Vector3(0.75, 0.32, -0.85), 0.55])
		for view in views:
			var dir: Vector3 = (b * (view[1] as Vector3)).normalized()
			Game.camera.global_position = c + dir * size * float(view[2])
			Game.camera.look_at(c, Vector3.UP)
			await _pf(3)
			await _shot("%s_%s" % [k, view[0]])
		vm._release(v)
		await _pf(2)
	_done = true
	tree.quit()


## CR_ONLY=perf: the hero aboard a helicopter, a plane and a tank on the airfield, the game's chase camera; draw calls and frame time with the seated pilot (SeatPose.on) and without.
func _perf() -> void:
	var at := Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	for k in ["h_scout", "p_fighter", "t_heavy"]:
		for seat in [false, true]:
			SeatPose.on = seat
			p.teleport_to(at + Vector3(-12.0, 0.5, 0.0))
			await _pf(10)
			vm._release_farthest(at)
			var v := vm.spawn_parked(StringName(k), at, 0.0)
			if v == null:
				continue
			await _pf(10)
			vm.enter(v)
			await _pf(60)
			var draws := 0
			var worst := 0.0
			var sum := 0.0
			for i in 60:
				var t0 := Time.get_ticks_usec()
				await RenderingServer.frame_post_draw
				var ms := float(Time.get_ticks_usec() - t0) / 1000.0
				sum += ms
				worst = maxf(worst, ms)
				draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			print("CRPERF q%d %s seat %s draws %d frame avg %.1f worst %.1f ms body visible %s" % [Game.quality, k, seat, draws, sum / 60.0, worst, p.body.visible])
			await _shot("perf_%s_%s" % [k, "seat" if seat else "hidden"])
			vm.exit_vehicle()
			await _pf(4)
			vm._release(v)
	SeatPose.on = true
