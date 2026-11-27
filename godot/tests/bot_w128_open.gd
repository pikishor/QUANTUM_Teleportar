extends RefCounted
## w128-open LOOK BOT: frames of the wave 128 open-item fixes as the phone player sees them: a tank driven by the stick (REAL fingers, tests/w116_fingers.gd) through a street lamp,
## and the demo menu's VEHICLES / AIRCRAFT tabs and a plane put on the runway from a finger on its entry. The bot places the hero only to set up a view.
##   OB_OUT=<dir> OB_TAG=q0 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w128_open.gd /tmp/x 100000 1
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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	(Engine.get_main_loop() as SceneTree).root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, tag])
	print("OB SHOT %s" % name)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _pf(4)
	fg.up(6)
	await _pf(4)
	return true


func _touch(pos: Vector2) -> void:
	fg.down(7, pos)
	await _pf(3)
	fg.up(7)
	await _pf(3)


func _run(tree: SceneTree) -> void:
	out = OS.get_environment("OB_OUT")
	if out == "":
		out = "/tmp"
	tag = OS.get_environment("OB_TAG")
	Game.force_touch = true
	CrateReveal._quiet = 0
	Game.state = &"play"
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(tree.root)
	TestMode.god = true
	await _pf(30)
	# --- tank through a street lamp
	var lamp := Vector3(-10.6, 0.0, -10.6)
	var fwd := Vector3(0.0, 0.0, 1.0)
	p.teleport_to(lamp - fwd * 20.0 + Vector3(0.0, 0.4, 0.0))
	await _pf(10)
	vm._fixed_n += 1
	var tk := vm.spawn_parked(&"tank", lamp - fwd * 12.0, atan2(-fwd.x, -fwd.z))
	tk.set_meta(&"hold", true)
	vm._count_fixed()
	p.yaw = atan2(-fwd.x, -fwd.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	await _pf(20)
	fg.stick(Vector2(0.0, -0.7))
	for i in 200:
		await _pf(1)
		if fg.button_label(&"interact") == "ENTER" and tk.edge_distance(p.global_position) < 2.0:
			break
	fg.stick(Vector2.ZERO)
	await _tap(&"interact")
	await _pf(40)
	await _shot("lamp_before")
	fg.stick(Vector2(0.0, -1.0))
	var hit := false
	for i in 400:
		await _pf(1)
		if not hit and tk.global_position.z > lamp.z - 3.0:
			hit = true
			await _pf(4)
			await _shot("lamp_hit")
		if tk.global_position.z > lamp.z + 8.0:
			break
	fg.stick(Vector2.ZERO)
	await _pf(30)
	await _shot("lamp_after")
	# look back at the place of the lamp from the tank (the right thumb turns the view)
	fg.look(380.0, 0.0, 12)
	await _pf(20)
	await _shot("lamp_back")
	await _tap(&"interact")
	await _pf(20)
	# --- demo tabs
	Game.state = &"menu"
	await _pf(4)
	DemoMode.enter()
	Game.state = &"play"
	await _pf(10)
	var dp := tree.root.find_children("*", "DemoPanel", true, false)[0] as DemoPanel
	for tab: String in ["VEHICLES", "AIRCRAFT"]:
		await _touch(dp.entry_rect().get_center())
		await _touch((dp.call(&"_tab_rects") as Array)[DemoPanel.TABS.find(tab)].get_center())
		await _pf(6)
		await _shot("demo_" + tab.to_lower())
		dp.close()
		await _pf(4)
	print("OB status jumbo: %s" % DemoMode.spawn_any(&"p_jumbo"))
	await _pf(40)
	await _shot("demo_jumbo_runway")
	print("OB status heli: %s" % DemoMode.spawn_any(&"h_attack"))
	await _pf(40)
	await _shot("demo_heli")
	DemoMode.quit()
	_done = true
