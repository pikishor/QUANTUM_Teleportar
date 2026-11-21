extends RefCounted
## WAVE 117 SWING STRIP: one phone session, fingers only. Title -> play by a finger, the hero is put on the avenue, JUMP, a thumb held on SNAKE: one PNG every SW_EVERY frames
## through the first swing, the release (finger up at the front of the arc), the second rope (a new press) and the landing with hands off.
##   SW_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS="--touch" ENGINE_ARGS="--fixed-fps 30" BOT_TIMEOUT=600 QUALITY=0 tools/bot.sh res://tests/bot_w117_swing.gd /tmp/x 100000 1
## SWING_OLD=1 renders the wave 116 motion for the comparison strip.
var _started := false
var _done := false
var root: Window
var tree: SceneTree
var tc: TouchControls
var hud: Node
var out := ""
var held := {}


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func secs(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await tree.process_frame


func down(pos: Vector2, idx := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.pressed = true
	held[idx] = pos
	Input.parse_input_event(e)


func up(idx := 0) -> void:
	if not held.has(idx):
		return
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * (held[idx] as Vector2)
	e.pressed = false
	held.erase(idx)
	Input.parse_input_event(e)


func move(to: Vector2, idx := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * to
	e.relative = root.get_final_transform().basis_xform(to - (held[idx] as Vector2))
	held[idx] = to
	Input.parse_input_event(e)


func tap(pos: Vector2, idx := 0, hold := 3) -> void:
	down(pos, idx)
	await frames(hold)
	up(idx)
	await frames(3)






func labels() -> String:
	var a: Array[String] = []
	for b: Dictionary in TouchControls.BUTTONS:
		if tc.button_visible(b):
			a.append(tc._label_of(b))
	return ",".join(a)


func menu_btn(id: StringName) -> Vector2:
	hud.call(&"_ensure_layout")
	for b: Dictionary in hud.get("buttons"):
		if b["id"] == id:
			return (b["rect"] as Rect2).get_center()
	return Vector2.INF


func menu_ids() -> String:
	hud.call(&"_ensure_layout")
	var a: Array[String] = []
	for b: Dictionary in hud.get("buttons"):
		a.append(String(b["id"]))
	return ",".join(a)



func tap_menu(id: StringName) -> bool:
	var p := menu_btn(id)
	if p == Vector2.INF:
		return false
	await tap(p)
	await frames(8)
	return true


func shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])


func btn(action: StringName) -> Vector2:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b):
			return tc._button_center(b)
	return Vector2.INF


func vp() -> Vector2:
	return root.get_visible_rect().size


func _run() -> void:
	root = tree.root
	out = OS.get_environment("SW_OUT")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	var every := maxi(1, int(OS.get_environment("SW_EVERY")) if OS.get_environment("SW_EVERY") != "" else 4)
	for q in root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	Game.force_touch = true
	CrateReveal._quiet = 0
	Sfx.muted = true
	SnakeSwing.old_motion = OS.get_environment("SWING_OLD") == "1"
	hud = tree.get_first_node_in_group(&"hud")
	tc = root.find_children("*", "TouchControls", true, false)[0] as TouchControls
	await frames(20)
	var start_id: StringName = &"deploy" if menu_btn(&"deploy") != Vector2.INF else &"continue"
	await tap_menu(start_id)
	var t0 := Time.get_ticks_msec()
	while Game.state != &"play" and Time.get_ticks_msec() - t0 < 30000:
		await frames(5)
		if Game.state == &"cutscene":
			await tap(vp() * Vector2(0.5, 0.5))
	var p := Game.player as Player
	var sn := p.snake
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.teleport_to(Vector3(-30.0, 0.0, 4.0))
	p.camera_rig.reset_view(-PI * 0.5, 0.2)
	p.yaw = -PI * 0.5
	await frames(45)
	await shot("00_street")
	# JUMP, then the thumb goes down on SNAKE and stays
	await tap(btn(&"jump"), 2)
	for i in 6:
		await frames(1)
		if not p.is_on_floor() and p.air_time > 0.12:
			break
	down(btn(&"snake"), 1)
	var n := 1
	var f := 0
	var phase := "a"                                       # a first rope, b thrown, c second rope, d hands off
	var released := 0
	while f < 420 and n < 60:
		await frames(1)
		f += 1
		if phase == "a" and sn.swing.is_hanging() and sn.swing.rope_angle > 0.45 and p.velocity.y > 1.0:
			up(1)
			phase = "b"
			released = f
		elif phase == "b" and f - released > 6 and p.velocity.y < 1.5:
			down(btn(&"snake"), 1)
			phase = "c"
		elif phase == "c" and sn.swing.is_hanging() and sn.swing.rope_angle > 0.45 and p.velocity.y > 1.0:
			up(1)
			phase = "d"
			released = f
		elif phase == "d" and p.is_on_floor() and f - released > 20:
			phase = "e"
			released = f
		elif phase == "e" and f - released > 24:
			break
		if f % every == 0:
			print("SWSTRIP %02d phase %s mode %s %s angle %.2f rope %.1f v %.1f (vy %.1f) h %.1f label %s" % [n, phase, sn.mode_name(), sn.swing.phase, sn.swing.rope_angle, sn.swing.rope, p.velocity.length(), p.velocity.y, p.global_position.y, tc._label_of(_b(&"snake"))])
			await shot("%02d_%s" % [n, phase])
			n += 1
	up_all()
	print("SWSTRIP END")
	_done = true
	tree.quit()


func up_all() -> void:
	for k in held.keys():
		up(k)


func _b(action: StringName) -> Dictionary:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action:
			return b
	return {}
