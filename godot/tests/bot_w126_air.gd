extends RefCounted
## WAVE 126 air (w126-air): frames to LOOK at, by fingers (tests/w116_fingers.gd) in the real main scene: the gunship's flight HUD with the arm, ARMS, FLARE and VIEW buttons, a rocket
## salvo, the missile seeker LOCKED on a bandit, the jet's bomb ring and a bomb going off, a cargo crate under its chute, the airport traffic from the gates, the Mission Board's air cards.
##   AIR_OUT=<dir> AIR_TAG=q0 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w126_air.gd /tmp/x 100000 1
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
	print("AIR SHOT %s" % name)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _pf(4)
	fg.up(6)
	await _pf(4)
	return true


func _spawn(kind: StringName, at: Vector3, h: float) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, h)
	if v != null:
		v.set_meta(&"hold", true)
		v.set_meta(&"air_target", true)
	vm._count_fixed()
	return v


func _enter(v: Vehicle) -> bool:
	var side := v.right() * (float(v.spec["wid"]) * 0.5 + 9.0)
	var at := v.global_position + side
	p.teleport_to(at + Vector3(0.0, 0.3, 0.0))
	var d := v.global_position - at
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	await _pf(10)
	fg.stick(Vector2(0.0, -0.6))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6, 480)
	fg.stick(Vector2.ZERO)
	await _pf(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 90)
	return p.vehicle == v


func _place(v: Vehicle, at: Vector3, face: Vector3, spd: float) -> void:
	var d := face - at
	v.global_position = at
	v.heading = atan2(-d.x, -d.z)
	v.rotation.y = v.heading
	v.craft.airborne = true
	v.craft.vy = 0.0
	v.speed = spd
	v.vel = v.forward() * spd
	if v.cls == &"plane":
		v.craft.lever = 0.8 if spd > 1.0 else 0.0


func _puppet(kind: StringName, at: Vector3) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, 0.0)
	if v == null:
		vm._count_fixed()
		return null
	v.set_meta(&"air_puppet", true)
	v.set_meta(&"hold", true)
	vm._count_fixed()
	v.global_position = at
	v.craft.airborne = true
	return v


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("AIR_OUT")
	if out == "":
		out = "/tmp"
	tag = OS.get_environment("AIR_TAG")
	if tag == "":
		tag = "q%d" % Game.quality
	DirAccess.make_dir_recursive_absolute(out)
	Game.force_touch = true
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(tree.root)
	TestMode.god = true
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if is_instance_valid(Game.world) and Game.world.has_method(&"set_hour"):
		Game.world.call(&"set_hour", 11.0)
	TerrainHeight.warm()
	# 1. the traffic from the gates
	var gate := Airport.to_world(Vector3(1180.0, 0.0, -520.0))
	var rwy := Airport.to_world(Vector3(1262.0, 0.0, -760.0))
	p.teleport_to(gate + Vector3(0.0, 0.3, 0.0))
	var d0 := rwy - gate
	p.yaw = atan2(-d0.x, -d0.z)
	p.camera_rig.reset_view(p.yaw, 0.05)
	await _pf(120)
	await _shot("traffic_gates")
	# 2. the gunship: HUD buttons, a rocket salvo, the seeker
	var rw := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -1000.0))
	var gs := _spawn(&"gunship", rw, Airport.heading_world(0.0))
	if gs != null and await _enter(gs):
		fg.press(1, &"jump")
		await _until(func() -> bool: return VehicleCraft.altitude(gs) > 30.0, 900)
		fg.up(1)
		await _pf(30)
		await _shot("gunship_hud")
		var tgt := _spawn(&"sedan", gs.global_position + gs.forward() * 90.0 - Vector3(0.0, VehicleCraft.altitude(gs), 0.0), gs.heading)
		if tgt != null:
			gs.set_meta(&"aim_at", tgt.global_position + Vector3(0.0, 0.8, 0.0))
		fg.press(2, &"aim")
		await _pf(10)
		await _shot("rocket_salvo")
		fg.up(2)
		await _pf(18)
		await _shot("rocket_hit")
		await _tap(&"ammo_type")
		var b := _puppet(&"plane", gs.global_position + gs.forward() * 160.0 + Vector3(0.0, 8.0, 0.0))
		if b != null:
			gs.set_meta(&"aim_at", b.global_position)
		await _until(func() -> bool: return fg.button_label(&"aim").begins_with("LOCKED"), 300)
		await _shot("missile_locked")
		await _tap(&"flare")
		await _pf(6)
		await _shot("flares")
		gs.remove_meta(&"aim_at")
		if b != null:
			b.remove_meta(&"air_puppet")
			vm._release(b)
		_place(gs, Vector3(gs.global_position.x, rw.y + 0.5, gs.global_position.z), gs.global_position + gs.forward() * 50.0, 0.0)
		gs.craft.airborne = false
		await _pf(20)
		await _tap(&"interact")
		await _pf(20)
	# 3. the jet: the bomb ring and a bomb
	var jet := _spawn(&"jet", rw + Airport.FRAME.basis * Vector3(60.0, 0.0, 0.0), Airport.heading_world(0.0))
	if jet != null and await _enter(jet):
		for i in 3:
			if fg.button_label(&"aim").begins_with("BOMB"):
				break
			await _tap(&"ammo_type")
		var at := jet.global_position + jet.forward() * 500.0
		for i in 3:
			_spawn(&"apc", at + jet.right() * (float(i) * 7.0 - 7.0), jet.heading)
		_place(jet, at + Vector3(0.0, 120.0, 0.0) - jet.forward() * 420.0, at + Vector3(0.0, 120.0, 0.0) + jet.forward() * 400.0, 60.0)
		await _pf(20)
		await _shot("bomb_ring")
		await _tap(&"aim")
		await _pf(30)
		await _shot("bomb_falling")
		await _until(func() -> bool: return AirRockets.instance == null or AirRockets.instance.live_count() == 0, 600)
		await _pf(2)
		await _shot("bomb_blast")
	# 4. the cargo crate
	var cg := _spawn(&"cargo", Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -400.0)), Airport.heading_world(0.0))
	if cg != null and await _enter(cg):
		var c0 := cg.global_position + Vector3(0.0, 90.0, 0.0)
		_place(cg, c0, c0 + cg.forward() * 400.0, 45.0)
		await _pf(10)
		await _tap(&"aim")
		for i in 90:
			_place(cg, c0, c0 + cg.forward() * 400.0, 45.0)
			await _pf(1)
		await _shot("cargo_crate")
	else:
		print("AIR cargo not boarded")
	# 5. the board's air cards
	if p.vehicle != null:
		_place(p.vehicle, Vector3(p.vehicle.global_position.x, rw.y + 0.5, p.vehicle.global_position.z), p.vehicle.global_position + p.vehicle.forward() * 50.0, 0.0)
		(p.vehicle as Vehicle).craft.airborne = false
		await _pf(20)
		await _tap(&"interact")
		await _pf(20)
	p.teleport_to(gate + Vector3(0.0, 0.3, 0.0))
	await _pf(20)
	var board := MissionBoardScreen.board()
	board.world_offers = true
	board.generate()
	var hud := tree.get_first_node_in_group(&"hud") as Hud
	if hud != null:
		hud.open_board()
		await _pf(10)
		await _shot("board_air")
		Game.state = &"play"
	_done = true
	tree.quit()
