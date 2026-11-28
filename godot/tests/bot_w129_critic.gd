extends RefCounted
## w129-critic REVIEW BOT: plays the wave 129 machines with REAL FINGERS (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event) in the real main scene with
## Game.force_touch and the phone-only layers on, and saves frames from the GAME camera (what the player sees) plus a few side views of the same tick, with draws and script time.
## The only set-up by code: a vehicle is parked and the hero is put a few metres from it; boarding, driving, flying and shooting are fingers.
##   C_OUT=<dir> C_MODE=heli|planes|ground|sit|night QUALITY=1 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w129_critic.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var p: Player
var vm: VehicleManager
var fg: Fingers
var out := ""
var at := Vector3.ZERO
var tree: SceneTree


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func _f(n: int) -> void:
	for i in n:
		await tree.physics_frame
		await tree.process_frame


func _stats() -> String:
	var dr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var sc := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	return "draws=%d prims=%dk script=%.1fms fps=%.0f" % [dr, pr / 1000, sc, Engine.get_frames_per_second()]


## A frame of what the player sees now.
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT %s %s q=%d" % [name, _stats(), Game.quality])


## A side view of `v` in the same tick (time frozen, the game camera moved, then put back).
func _side(v: Vehicle, name: String, local_dir: Vector3, dist: float, up := 0.4) -> void:
	var cam := Game.camera
	var keep := cam.global_transform
	var ts := Engine.time_scale
	Engine.time_scale = 0.0
	p.camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	var c := v.global_position + Vector3(0.0, float(v.spec.get("hgt", 3.0)) * up, 0.0)
	cam.global_position = c + (v.global_transform.basis * local_dir).normalized() * dist
	cam.look_at(c, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT %s %s" % [name, _stats()])
	p.camera_rig.process_mode = Node.PROCESS_MODE_INHERIT
	cam.global_transform = keep
	Engine.time_scale = ts


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		print("NO BUTTON ", action)
		return false
	await _f(3)
	fg.up(6)
	await _f(3)
	return true


func _board(kind: StringName, where: Vector3, h := 0.0) -> Vehicle:
	vm._release_farthest(where)
	vm._release_farthest(where)
	var v := vm.spawn_parked(kind, where, h)
	if v == null:
		print("NO PARK ", kind)
		return null
	await _f(6)
	var side := minf(float(v.spec["wid"]) * 0.5 + 1.2, 3.0 if VehicleSpecs.cls_of(kind) == &"plane" else 9.0)
	p.teleport_to(v.global_position + v.right() * side + Vector3(0.0, 0.3, 0.0))
	await _f(20)
	for i in 50:
		if fg.button_label(&"interact") == "ENTER":
			break
		fg.stick(Vector2(-1.0, 0.0))
		await _f(2)
	fg.stick(Vector2.ZERO)
	await _f(2)
	await _tap(&"interact")
	await _f(25)
	print("BOARD %s -> %s" % [kind, p.vehicle == v])
	return v if p.vehicle == v else null


func _leave() -> void:
	fg.up_all()
	await _f(2)
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(20)
	if p.vehicle != null:
		vm.exit_vehicle()
		await _f(5)


func _run() -> void:
	out = OS.get_environment("C_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	Game.force_touch = true
	Game.state = &"play"
	CrateReveal._quiet = 0
	fg = Fingers.new(tree.root)
	TestMode.god = true
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	var dn: DayNight = (Game.world as City).day_night
	dn.frozen = true
	var mode := OS.get_environment("C_MODE")
	dn.set_hour(22.5 if mode == "night" else 11.0)
	for w in tree.root.find_children("*", "Weather", true, false):
		w.call("set_state", &"clear", true)
	at = Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	p.teleport_to(at + Vector3(-40.0, 0.5, 0.0))
	await _f(60)
	await call("_" + mode)
	_done = true
	tree.quit()


func _heli() -> void:
	for k: StringName in [&"h_police", &"h_attack"]:
		var v := await _board(k, at + Vector3(0.0, 0.0, -30.0))
		if v == null:
			continue
		var c := v.craft
		fg.press(1, &"jump")
		await _f(40)
		await _shot("%s_spool" % k)
		await _side(v, "%s_spool_side" % k, Vector3(1.0, 0.3, -0.3), 14.0)
		await _f(80)
		fg.up(1)
		await _shot("%s_hover" % k)
		await _side(v, "%s_hover_side" % k, Vector3(1.0, 0.2, 0.2), 14.0)
		await _side(v, "%s_hover_tail" % k, Vector3(0.5, 0.2, 1.0), 12.0)
		fg.stick(Vector2(0.0, -1.0))
		await _f(90)
		await _shot("%s_forward" % k)
		await _side(v, "%s_forward_side" % k, Vector3(1.0, 0.1, 0.0), 14.0)
		fg.stick(Vector2(1.0, 0.0))
		await _f(60)
		await _shot("%s_turn" % k)
		fg.stick(Vector2.ZERO)
		print("HELI %s alt=%.1f spool=%.2f speed=%.1f" % [k, VehicleCraft.altitude(v), c.spool, v.speed])
		fg.press(2, &"crouch")
		for i in 500:
			if not c.airborne:
				break
			await _f(1)
		fg.up(2)
		await _f(30)
		await _shot("%s_landed" % k)
		await _leave()
		vm._release(v)
		await _f(5)


func _planes() -> void:
	var th := Airport.thresholds()
	var t09: Vector3 = th[0]["pos"]
	var t27: Vector3 = th[1]["pos"]
	var dir := (t27 - t09).normalized()
	for k: StringName in [&"p_fighter", &"p_narrow"]:
		var where := Vector3(t09.x, TerrainHeight.height_at(t09.x, t09.z), t09.z) + dir * 60.0
		var v := await _board(k, where + Vector3(-dir.z, 0.0, dir.x) * 40.0, float(th[0]["heading"]))
		if v == null:
			continue
		v.global_position = Vector3(where.x, v.base_y, where.z)          # set-up: on runway 09
		v.heading = float(th[0]["heading"])
		v.vel = Vector3.ZERO
		v.speed = 0.0
		await _f(10)
		var c := v.craft
		await _shot("%s_cockpit_rest" % k)
		fg.stick(Vector2(1.0, 0.0))
		fg.press(1, &"jump")
		await _f(30)
		await _side(v, "%s_surfaces" % k, Vector3(0.6, 0.6, 1.0), float(v.spec["len"]) * 0.9, 0.3)
		fg.up(1)
		fg.stick(Vector2(0.0, -1.0))
		var n := 0
		for i in 1400:
			if c.airborne and VehicleCraft.altitude(v) > 25.0:
				break
			if v.speed > float(v.spec.get("stall", 30.0)) * 1.05 and not fg.held.has(1):
				fg.press(1, &"jump")
			if i % 200 == 100:
				await _shot("%s_roll_%d" % [k, n])
				n += 1
			await _f(1)
		await _shot("%s_liftoff" % k)
		await _side(v, "%s_liftoff_under" % k, Vector3(0.6, -0.4, -0.7), float(v.spec["len"]) * 0.9, 0.0)
		await _f(120)
		await _shot("%s_climb" % k)
		await _side(v, "%s_gear_up" % k, Vector3(0.6, -0.4, -0.7), float(v.spec["len"]) * 0.9, 0.0)
		fg.up(1)
		fg.stick(Vector2(-1.0, 0.0))
		await _f(80)
		await _shot("%s_bank" % k)
		await _side(v, "%s_bank_rear" % k, Vector3(0.0, 0.3, 1.0), float(v.spec["len"]) * 1.0, 0.2)
		print("PLANE %s alt=%.1f speed=%.1f gear=%.2f" % [k, VehicleCraft.altitude(v), v.speed, MachAnim.st(c).pose["gear"]])
		fg.stick(Vector2.ZERO)
		await _leave()
		await _f(60)
		vm._release(v)
		p.teleport_to(at + Vector3(-40.0, 0.5, 0.0))
		await _f(30)


func _ground() -> void:
	var base := Airport.to_world(Vector3(1300.0, 0.0, -560.0))
	base.y = TerrainHeight.height_at(base.x, base.z)
	for k: StringName in [&"t_heavy", &"sedan", &"bike"]:
		p.teleport_to(base + Vector3(-10.0, 0.5, 0.0))
		await _f(20)
		var v := await _board(k, base)
		if v == null:
			continue
		await _shot("%s_in" % k)
		fg.stick(Vector2(0.0, -1.0))
		if k != &"t_heavy":
			fg.press(1, &"move_forward")
		await _f(70)
		await _shot("%s_drive" % k)
		await _side(v, "%s_drive_side" % k, Vector3(1.0, 0.25, 0.3), maxf(float(v.spec["len"]) * 1.4, 5.0))
		await _side(v, "%s_drive_rear" % k, Vector3(0.2, 0.3, 1.0), maxf(float(v.spec["len"]) * 1.4, 5.0))
		fg.stick(Vector2(0.8, -1.0))
		await _f(60)
		await _shot("%s_turn" % k)
		fg.up_all()
		await _f(30)
		if k == &"t_heavy":
			fg.press(1, &"fire")
			await _f(4)
			await _shot("tank_fire_a")
			await _side(v, "tank_fire_side", Vector3(1.0, 0.25, -0.4), 12.0)
			await _f(10)
			await _shot("tank_fire_b")
			fg.up(1)
			await _f(40)
			await _shot("tank_fire_c")
		await _leave()
		vm._release(v)
		await _f(5)


## Sit in a vehicle on the airfield apron and at the ARMY BASE and read draws / script time (run with QUALITY=0 and 1).
func _sit() -> void:
	var bp := Airport.to_world(TankRoster.BASE_LOCAL + Vector3(-25.0, 0.0, 40.0))
	bp.y = TerrainHeight.height_at(bp.x, bp.z)
	for spot: Array in [["apron_heli", &"h_police", at + Vector3(0.0, 0.0, -30.0)], ["apron_jet", &"p_fighter", at + Vector3(10.0, 0.0, 40.0)], ["apron_tank", &"t_heavy", at + Vector3(20.0, 0.0, 10.0)], ["base_tank", &"t_heavy", bp], ["base_car", &"sedan", bp + Vector3(0.0, 0.0, -20.0)]]:
		p.teleport_to((spot[2] as Vector3) + Vector3(-10.0, 0.5, 0.0))
		await _f(40)
		var v := await _board(spot[1], spot[2])
		if v == null:
			continue
		await _f(60)
		var dmax := 0
		var dsum := 0
		var smax := 0.0
		for i in 60:
			await _f(1)
			var d := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			dmax = maxi(dmax, d)
			dsum += d
			smax = maxf(smax, (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		print("SIT %s q=%d draws avg=%d max=%d script max=%.1fms" % [spot[0], Game.quality, dsum / 60, dmax, smax])
		await _shot("sit_%s_q%d" % [spot[0], Game.quality])
		fg.look(300.0, 0.0, 8)
		await _f(20)
		await _shot("sit_%s_q%d_look" % [spot[0], Game.quality])
		await _leave()
		vm._release(v)
		await _f(5)


func _night() -> void:
	var v := await _board(&"p_fighter", at + Vector3(10.0, 0.0, 40.0))
	if v != null:
		fg.stick(Vector2(0.0, -0.3))
		await _f(60)
		fg.stick(Vector2.ZERO)
		await _f(20)
		await _shot("night_jet_in")
		await _side(v, "night_jet_side", Vector3(1.0, 0.4, 0.3), 22.0)
		await _side(v, "night_jet_rear", Vector3(0.0, 0.3, 1.0), 22.0)
		await _leave()
	var h := await _board(&"h_police", at + Vector3(-30.0, 0.0, -30.0))
	if h != null:
		fg.press(1, &"jump")
		await _f(150)
		fg.up(1)
		await _shot("night_heli_in")
		await _side(h, "night_heli_side", Vector3(1.0, 0.3, 0.3), 16.0)
		await _leave()
	# a burning wreck: a car blown up next to the hero
	p.teleport_to(at + Vector3(-60.0, 0.5, 60.0))
	await _f(20)
	var w := vm.spawn_parked(&"sedan", at + Vector3(-50.0, 0.0, 60.0), 0.0)
	await _f(10)
	if w != null:
		w.damage(99999.0)
		for t in [30, 120, 400]:
			await _f(t)
			await _side(w, "night_wreck_%d" % t, Vector3(1.0, 0.3, 0.5), 12.0)
		dn.set_hour(11.0)
		await _f(5)
		await _side(w, "day_wreck", Vector3(1.0, 0.3, 0.5), 12.0)


var dn: DayNight:
	get:
		return (Game.world as City).day_night


## The tank's gun by finger: frames of what the player sees after one shot (C_TAG names the run, e.g. old / new).
func _tankfire() -> void:
	var tag := OS.get_environment("C_TAG")
	var base := Airport.to_world(Vector3(1300.0, 0.0, -560.0))
	base.y = TerrainHeight.height_at(base.x, base.z)
	p.teleport_to(base + Vector3(-10.0, 0.5, 0.0))
	await _f(20)
	var v := await _board(&"t_heavy", base)
	if v == null:
		return
	await _f(40)
	fg.look(0.0, -60.0)
	await _f(20)
	fg.press(1, &"fire")
	await _f(4)
	fg.up(1)
	for i in 6:
		await _f(12)
		await _shot("tf_%s_%d" % [tag, i])
	await _side(v, "tf_%s_side" % tag, Vector3(1.0, 0.4, 0.2), 14.0)


## A car blown up 12 m from the hero (by day): the husk burns, then smoulders.
func _wreck() -> void:
	var c := Vector3(30.0, 0.0, 10.0)
	c.y = TerrainHeight.height_at(c.x, c.z)
	p.teleport_to(c + Vector3(-12.0, 0.5, 0.0))
	await _f(30)
	vm._release_farthest(c)
	var w := vm.spawn_parked(&"sedan", c, 0.0)
	await _f(10)
	print("WRECK spawned %s at %s" % [w, w.global_position if w else Vector3.ZERO])
	if w == null:
		return
	w.explode()
	for t in [20, 60, 150, 300]:
		await _f(t)
		print("WRECK valid %s wreck %s visible %s burn %s pos %s list %s" % [is_instance_valid(w), w.wreck if is_instance_valid(w) else false, w.is_visible_in_tree() if is_instance_valid(w) else false, w.get_meta(&"burn", -1.0) if is_instance_valid(w) else -1.0, w.global_position if is_instance_valid(w) else Vector3.ZERO, vm.wreck_count()])
		if is_instance_valid(w):
			await _shot("wreck_game_%d" % t)
			await _side(w, "wreck_side_%d" % t, Vector3(1.0, 0.35, 0.6), 13.0)
