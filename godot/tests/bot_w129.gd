extends RefCounted
## WAVE 129 look bot (w129-machanim): frames of the machine and aircraft animation and effects, placed by code (the finger checks live in tests/test_machanim_w129.gd).
##   M_OUT=<dir> M_TAG=new M_MODE=awacs|heli|plane|tank|car|glb|night QUALITY=1 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w129.gd /tmp/x 100000 1
var _started := false
var _done := false
var p: Player
var vm: VehicleManager
var out := ""
var tag := ""
var at := Vector3.ZERO


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
	var ts := Engine.time_scale
	Engine.time_scale = 0.0                               # the camera was placed for this tick: freeze the world while the frame is drawn
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])
	Engine.time_scale = ts


func _cam(v: Node3D, local_dir: Vector3, dist: float, up := 0.45) -> void:
	var sp: Dictionary = (v as Vehicle).spec if v is Vehicle else {}
	var c := v.global_position + Vector3(0.0, float(sp.get("hgt", 3.0)) * up, 0.0)
	var dir: Vector3 = (v.global_transform.basis * local_dir).normalized()
	Game.camera.global_position = c + dir * dist
	Game.camera.look_at(c, Vector3.UP)


func _spawn(k: StringName, pos := Vector3.INF) -> Vehicle:
	var q := at if pos == Vector3.INF else pos
	vm._release_farthest(q)
	vm._release_farthest(q)
	var v := vm.spawn_parked(k, q, 0.0)
	await _pf(10)
	return v


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("M_OUT")
	tag = OS.get_environment("M_TAG")
	DirAccess.make_dir_recursive_absolute(out)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.state = &"play"
	TestMode.god = true
	var dn: DayNight = (Game.world as City).day_night
	dn.frozen = true
	var mode := OS.get_environment("M_MODE")
	dn.set_hour(22.5 if mode == "night" else 11.0)
	for w in tree.root.find_children("*", "Weather", true, false):
		w.call("set_state", &"clear", true)
	for h in tree.get_nodes_in_group(&"hud"):
		h.set("visible", false)
	at = Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	p.teleport_to(at + Vector3(-60.0, 0.5, 0.0))
	await _pf(90)
	p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	match mode:
		"awacs":
			await _awacs()
		"heli":
			await _heli()
		"plane":
			await _plane()
		"misc":
			await _glb()
			await _tank()
			await _car()
			await _wreck()
		"night":
			await _night()
		"puff":
			await _puff()
	_done = true
	tree.quit()


## A parked AWACS seen from 38, 41 and 44 m right after it was spawned (fresh instance each time).
func _awacs() -> void:
	for d in [30.0, 38.0, 41.0, 44.0, 50.0]:
		var v := await _spawn(&"p_tanker")
		await _pf(4)
		vm._release(v)
		await _pf(2)
		v = await _spawn(&"p_awacs")
		_cam(v, Vector3(0.8, 0.3, -0.7), d)
		await _pf(3)
		await _shot("awacs_%02d" % int(d))
		vm._release(v)
		await _pf(2)


## Helicopters: spooling up on the pad (blades and disc mixed), hovering low (wash), forward flight with the stick (tilt), from the side and from above.
func _heli() -> void:
	var kinds := OS.get_environment("M_KINDS").split(",", false)
	if kinds.is_empty():
		kinds = PackedStringArray(["h_police", "h_heavy", "h_attack"])
	for k in kinds:
		var v := await _spawn(StringName(k))
		if v == null:
			continue
		p.teleport_to(v.global_position + Vector3(8.0, 0.5, 8.0))
		await _pf(4)
		vm.enter(v)
		await _pf(10)
		p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
		var r := float(v.spec.get("rotor_r", 5.0))
		for i in 18:
			await _pf(1)
			_cam(v, Vector3(1.0, 0.25, -0.4), r * 2.6)
		await _shot("%s_spool" % k)
		Input.action_press(&"jump")
		await _pf(70)
		Input.action_release(&"jump")
		_cam(v, Vector3(1.0, 0.15, 0.2), r * 2.8, 0.2)
		await _shot("%s_hover_side" % k)
		_cam(v, Vector3(0.6, 0.6, 0.8), r * 3.0, 0.2)
		await _shot("%s_hover_r3q" % k)
		v.craft.thr_in = 1.0
		Input.action_press(&"move_forward")
		await _pf(40)
		_cam(v, Vector3(1.0, 0.1, 0.0), r * 2.6, 0.2)
		await _shot("%s_forward" % k)
		Input.action_release(&"move_forward")
		vm.exit_vehicle()
		await _pf(5)
		vm._release(v)
		await _pf(3)


## Aeroplanes on runway 09: parked (gear down, doors open), stick right + UP on the roll (ailerons, elevators, rudder, flaps), the climb-out (gear folding), the gear up from below.
func _plane() -> void:
	var kinds := OS.get_environment("M_KINDS").split(",", false)
	if kinds.is_empty():
		kinds = PackedStringArray(["p_fighter", "p_narrow", "p_twin"])
	var start := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, Airport.RUNWAY_S - 60.0))
	start.y = TerrainHeight.height_at(start.x, start.z)
	for k in kinds:
		p.teleport_to(start + Vector3(-30.0, 0.5, 0.0))
		await _pf(10)
		vm._release_farthest(start)
		vm._release_farthest(start)
		var v := vm.spawn_parked(StringName(k), start, Airport.heading_world(0.0))
		await _pf(10)
		if v == null:
			continue
		var size := maxf(float(v.spec["len"]), float(v.spec.get("span", v.spec["wid"])))
		_cam(v, Vector3(0.9, 0.2, -0.6), size * 0.75, 0.25)
		await _shot("%s_parked" % k)
		_cam(v, Vector3(0.5, -0.05, -0.85), size * 0.6, 0.1)
		await _shot("%s_gear" % k)
		vm.enter(v)
		await _pf(10)
		p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
		Input.action_press(&"move_right")
		Input.action_press(&"jump")
		await _pf(30)
		_cam(v, Vector3(0.0, 0.45, 1.0), size * 0.55, 0.3)
		await _shot("%s_surfaces_rear" % k)
		_cam(v, Vector3(0.9, 0.55, 0.5), size * 0.45, 0.3)
		await _shot("%s_surfaces_side" % k)
		Input.action_release(&"move_right")
		Input.action_release(&"jump")
		Input.action_press(&"move_forward")
		var t := 0
		while t < 900 and (not v.craft.airborne or v.craft.agl < 30.0):
			if v.speed > float(v.spec.get("stall", 30.0)):
				Input.action_press(&"jump")
			await _pf(1)
			t += 1
		Input.action_release(&"jump")
		await _pf(40)
		_cam(v, Vector3(0.7, -0.35, -0.6), size * 0.8, 0.0)
		await _shot("%s_retracting" % k)
		Input.action_press(&"jump")
		Input.action_press(&"move_left")
		await _pf(150)
		Input.action_release(&"move_left")
		_cam(v, Vector3(0.5, -0.5, -0.7), size * 0.8, 0.0)
		await _shot("%s_gear_up" % k)
		_cam(v, Vector3(0.25, 0.25, 1.0), size * 1.1, 0.0)
		await _shot("%s_exhaust" % k)
		Input.action_release(&"jump")
		print("MPLANE %s agl %.0f gear %.2f cycles %d" % [k, v.craft.agl, float(MachAnim.st(v.craft).pose["gear"]), MachAnim.st(v.craft).gear_cycles])
		Input.action_release(&"move_forward")
		vm.exit_vehicle()
		await _pf(5)
		vm._release(v)
		await _pf(3)


## The old art jet and cargo plane: the nose leg (and no tail wheel).
func _glb() -> void:
	for k in [&"jet", &"cargo"]:
		var v := await _spawn(k)
		if v == null:
			continue
		var size := float(v.spec["len"])
		_cam(v, Vector3(1.0, 0.05, -0.3), size * 0.8, 0.15)
		await _shot("glb_%s_side" % k)
		_cam(v, Vector3(0.6, 0.15, -1.0), size * 0.7, 0.15)
		await _shot("glb_%s_f3q" % k)
		vm._release(v)
		await _pf(2)


## A heavy tank on the field: driving (track dust, exhaust), then the main gun fired (recoil, flash, smoke, ground dust), seen from the side.
func _tank() -> void:
	var v := await _spawn(&"t_heavy")
	if v == null:
		v = await _spawn(&"ltank")
	if v == null:
		return
	p.teleport_to(v.global_position + Vector3(6.0, 0.5, 6.0))
	await _pf(4)
	vm.enter(v)
	await _pf(10)
	p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	Input.action_press(&"move_forward")
	await _pf(120)
	_cam(v, Vector3(0.7, 0.35, 1.0), 16.0, 0.4)
	await _shot("tank_drive")
	Input.action_release(&"move_forward")
	await _pf(60)
	v.set_meta(&"aim_at", v.global_position + v.forward() * 120.0 + Vector3(0.0, 2.0, 0.0))
	await _pf(40)
	if v.weapons != null:
		v.weapons._cd = 0.0
		v.weapons.tick(0.016, true)
	await _pf(2)
	_cam(v, Vector3(1.0, 0.25, -0.2), 18.0, 0.5)
	await _shot("tank_fire")
	await _pf(12)
	_cam(v, Vector3(1.0, 0.25, -0.2), 18.0, 0.5)
	await _shot("tank_fire_late")
	vm.exit_vehicle()
	await _pf(4)
	vm._release(v)


## A car pulling away (exhaust) from behind.
func _car() -> void:
	var v := await _spawn(&"sedan")
	if v == null:
		return
	p.teleport_to(v.global_position + Vector3(4.0, 0.5, 4.0))
	await _pf(4)
	vm.enter(v)
	await _pf(10)
	p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	Input.action_press(&"move_forward")
	await _pf(25)
	_cam(v, Vector3(0.45, 0.25, 1.0), 6.0, 0.3)
	await _shot("car_exhaust")
	Input.action_release(&"move_forward")
	vm.exit_vehicle()
	await _pf(4)
	vm._release(v)


## A car and a helicopter blown up on the field: the husks burn, then smoulder.
func _wreck() -> void:
	for k in [&"sedan", &"h_police"]:
		var v := await _spawn(k)
		if v == null:
			continue
		v.explode()
		await _pf(150)
		_cam(v, Vector3(0.9, 0.3, -0.6), 16.0, 0.5)
		await _shot("wreck_%s" % k)


## Night: a plane with its engines running (navigation lights, strobes), a heli hovering.
func _night() -> void:
	var start := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, Airport.RUNWAY_S - 60.0))
	start.y = TerrainHeight.height_at(start.x, start.z)
	p.teleport_to(start + Vector3(-30.0, 0.5, 0.0))
	await _pf(20)
	for k in [&"p_narrow", &"p_fighter"]:
		vm._release_farthest(start)
		var v := vm.spawn_parked(k, start, Airport.heading_world(0.0))
		await _pf(5)
		vm.enter(v)
		await _pf(10)
		p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
		Input.action_press(&"move_forward")
		await _pf(60)
		Input.action_release(&"move_forward")
		var size := maxf(float(v.spec["len"]), float(v.spec.get("span", v.spec["wid"])))
		for i in 3:
			_cam(v, Vector3(0.8, 0.4, -0.7), size * 0.9, 0.3)
			await _shot("night_%s_%d" % [k, i])
			await _pf(7)
		vm.exit_vehicle()
		await _pf(4)
		vm._release(v)


## Isolated puffs in the air: a blast puff (left) and a machine puff (right) with the same numbers.
func _puff() -> void:
	var fx := BlastFx.shared()
	var c := Game.camera.global_position + (-Game.camera.global_basis.z) * 14.0
	for i in 3:
		fx.puff(c + Vector3(-3.0, float(i) * 1.5 - 1.5, 0.0), Vector3.ZERO, 1.6, 2.0, 30.0, Color(0.37, 0.355, 0.34, 0.5), BlastFx.K_SMOKE, 0.0, 0.9)
		fx.machine_puff(c + Vector3(3.0, float(i) * 1.5 - 1.5, 0.0), Vector3.ZERO, 1.6, 2.0, 30.0, Color(0.37, 0.355, 0.34, 0.5), BlastFx.K_SMOKE, 0.0, 0.9)
	await _pf(20)
	await _shot("puffs")
