extends RefCounted
## WAVE 118 pictures: one frame per mode of the touch controls (tests/test_controls_w118.gd holds the checks), in the rendered game.
##   CW_OUT=<dir> CW_TAG=844 QUALITY=0 BOT_RES=844x390 BOT_USER_ARGS="--touch" BOT_TIMEOUT=600 tools/bot.sh res://tests/bot_controls_w118.gd /tmp/x 100000 1
## CW_PARTS (comma list, default all): foot, enter, flight, car, armed, tank, heli, plane, interior, more, wheel.
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
var _started := false
var _done := false
var a: Audit
var p: Player
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
	var parts := OS.get_environment("CW_PARTS").split(",", false)
	return parts.is_empty() or parts.has(part)


func _street() -> void:
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(STREET)
	p.camera_rig.reset_view(-PI * 0.5, 0.05)
	p.yaw = -PI * 0.5
	p.velocity = Vector3.ZERO
	await a.pframes(40)


func _spawn(kind: StringName) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	DemoMenu.spawn_vehicle(kind)
	var best: Vehicle = null
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.kind == kind and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	return best


func _vehicle(part: String, kind: StringName) -> void:
	if not _on(part):
		return
	var vm := Game.vehicles as VehicleManager
	await _street()
	var v := _spawn(kind)
	if v == null:
		return
	await a.pframes(20)
	vm.enter(v)
	await a.pframes(60)
	await a.shot("%s_%s" % [part, tag])
	print("SET %s: %s" % [part, str(a.hud_ids())])
	if part == "car" and _on("more"):
		await a.tap_hud("more")
		await a.shot("car_more_%s" % tag)
		await a.tap_hud("more")
	vm.exit_vehicle()
	await a.pframes(10)
	vm._release(v)
	await a.pframes(4)


func _run(tree: SceneTree) -> void:
	a = Audit.new()
	a.shot_dir = OS.get_environment("CW_OUT")
	tag = OS.get_environment("CW_TAG")
	DirAccess.make_dir_recursive_absolute(a.shot_dir)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	if not await a.boot(tree.root, "bot", false):
		print("CONTROLS BOT: no HUD")
		tree.quit()
		return
	var prog := Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	for k in 6:
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		await a.tap(a.vp() * Vector2(0.5, 0.3))
		await a.pframes(6)
	await _street()
	if _on("foot"):
		await a.shot("foot_%s" % tag)
		print("SET foot: %s" % str(a.hud_ids()))
	if _on("more"):
		await a.tap_hud("more")
		await a.shot("foot_more_%s" % tag)
		await a.tap_hud("more")
	if _on("wheel"):
		a.fast_tap(a.centre_of(a.hud_button("ability")))
		await a.frames(3)
		await a.shot("wheel_ability_%s" % tag)
		a.tc.release_all()
	if _on("enter"):
		var car := _spawn(&"sedan")
		if car != null:
			p.global_position = car.global_position + car.global_transform.basis.x * 2.2 + Vector3(0, 0.3, 0)
			await a.until(func() -> bool: return not a.hud_button("interact").is_empty(), 300)
			await a.shot("foot_enter_%s" % tag)
			(Game.vehicles as VehicleManager)._release(car)
	if _on("flight"):
		await _street()
		a.finger_down(a.centre_of(a.hud_button("fly")))
		await a.until(func() -> bool: return p.snake.mode == SnakeTraversal.Mode.FLY, 200)
		a.finger_up()
		a.finger_down(a.centre_of(a.hud_button("jump")))
		await a.pframes(90)
		a.finger_up()
		await a.pframes(10)
		await a.shot("flight_%s" % tag)
		print("SET flight: %s" % str(a.hud_ids()))
		p.snake.cancel()
	await _vehicle("car", &"sedan")
	await _vehicle("armed", &"sport")
	await _vehicle("tank", &"tank")
	await _vehicle("heli", &"gunship")
	await _vehicle("plane", &"plane")
	if _on("interior"):
		InteriorTestActions.enter(&"shop")
		await a.until(func() -> bool: return InteriorGameplay.active, 300)
		await a.pframes(60)
		await a.shot("interior_%s" % tag)
		print("SET interior: %s" % str(a.hud_ids()))
	_done = true
	tree.quit()
