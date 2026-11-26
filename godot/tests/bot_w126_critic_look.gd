extends RefCounted
## WAVE 126 critic look bot (w126-critic): frames at phone aspect + frame time / draws in flight. Fingers only for ENTER / UP / stick; set-up places the hero and the aircraft.
##   CL_OUT=<dir> CL_TAG=q0 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=1200 tools/bot.sh res://tests/bot_w126_critic_look.gd /tmp/x 100000 1
## CL_PARTS: views,board,fly (default all)
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
	var parts := OS.get_environment("CL_PARTS").split(",", false)
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
	var pr := 0.0
	for i in 30:
		await (Engine.get_main_loop() as SceneTree).process_frame
		ft += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		dr += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("CL PERF %s %s process_ms=%.2f draws=%.0f prims=%.0fk" % [tag, label, ft / 30.0, dr / 30.0, pr / 30000.0])


func _view(name: String, at: Vector3, look: Vector3, pitch := -0.12, wait := 300) -> void:
	var w := Airport.to_world(at)
	var lw := Airport.to_world(look)
	var d := lw - w
	var yaw := atan2(-d.x, -d.z)
	p.teleport_to(w + Vector3(0.0, 0.3, 0.0))
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, pitch)
	vm._spawn_t = 0.0
	await _pf(wait)
	await _shot(name)


## Board the fixed plane `id` from 4 m in front of its nose (walk by the stick, ENTER by finger).
func _board_fixed(k: StringName) -> Vehicle:
	var pl: Array = PlaneRoster.PLACES[k]
	var line: bool = PlaneRoster.DEFS[k]["place"] == &"line"
	var id := StringName(("pl_" if line else "hg_") + String(k))
	var pos := Airport.to_world(pl[0])
	var hw := Airport.heading_world(float(pl[1]))
	var fwd := Vector3(-sin(hw), 0.0, -cos(hw))
	var stand := pos + fwd * (float(VehicleSpecs.SPECS[k]["len"]) * 0.5 + 3.5)
	if vm.driven != null:
		await _tap(&"interact")
	p.teleport_to(stand + Vector3(0.0, 0.3, 0.0))
	var d := pos - stand
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	vm._spawn_t = 0.0
	await _until(func() -> bool: return is_instance_valid(vm._spawned.get(id)), 1500)
	var v: Vehicle = vm._spawned.get(id)
	if v == null:
		print("CL no %s" % k)
		return null
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 600)
	fg.stick(Vector2.ZERO)
	await _pf(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 60)
	print("CL BOARD %s in=%s" % [k, p.vehicle == v])
	return v if p.vehicle == v else null


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("CL_OUT")
	tag = OS.get_environment("CL_TAG")
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
		city.day_night.set_hour(11.0)
	for k in 6:
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		fg.down(7, fg.vp() * Vector2(0.5, 0.3))
		await _pf(3)
		fg.up(7)
		await _pf(6)
	if _on("views"):
		await _view("line_from_runway", Vector3(1262.0, 0.0, -840.0), Vector3(1307.0, 3.0, -700.0))
		await _view("hangar_a_in", Vector3(1156.0, 0.0, -934.0), Vector3(1132.0, 1.0, -944.0))
		await _view("shelter_exit", Vector3(1360.0, 0.0, -700.0), Vector3(1300.0, 2.0, -740.0))
		await _view("heli_line", Vector3(1322.0, 0.0, -870.0), Vector3(1334.0, 2.0, -800.0))
	if _on("board"):
		for k: StringName in [&"p_glider", &"p_biplane", &"p_jumbo"]:
			var v := await _board_fixed(k)
			if v != null:
				await _pf(60)
				await _shot("board_" + String(k))
	if _on("fly"):
		var v := await _board_fixed(&"p_fighter")
		if v != null:
			# set-up: the fighter put in the air over the airport heading west over the city, 250 m up
			v.global_position = Airport.to_world(Vector3(1262.0, 250.0, -600.0))
			v.heading = Airport.heading_world(PI * 0.5)
			v.rotation.y = v.heading
			v.craft.airborne = true
			v.craft.lever = 0.8
			v.craft.spool = 1.0
			v.speed = 70.0
			v.vel = v.forward() * 70.0
			fg.stick(Vector2(0.0, -0.3))
			await _pf(90)
			await _shot("fly_fighter_hud")
			await _perf("fly_fighter_airport")
			await _pf(400)
			await _perf("fly_fighter_city")
			await _shot("fly_fighter_city")
			fg.press(2, &"fire")
			await _pf(20)
			await _shot("fly_fighter_guns")
			fg.up(2)
			fg.stick(Vector2.ZERO)
	fg.up_all()
	_done = true
	tree.quit()
