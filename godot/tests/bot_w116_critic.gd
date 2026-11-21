extends RefCounted
## WAVE 116 CRITIC BOT: one continuous phone session, fingers only (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, window coordinates). It only READS
## where a control is drawn; every act is a finger. One line per step ("CRITIC step | verdict | facts") and one PNG per step in CR_OUT.
##   CR_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=900 tools/bot.sh res://tests/bot_w116_critic.gd /tmp/x 100000 1
## CR_PARTS (comma list, default all): foot, screens, car, snake, demo
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


func vp() -> Vector2:
	return root.get_visible_rect().size


func btn(action: StringName, label := "") -> Vector2:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b) and (label == "" or tc._label_of(b) == label):
			return tc._button_center(b)
	return Vector2.INF


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
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])


func overlay() -> String:
	var s := ""
	if CrateReveal.is_showing():
		s += " CARD"
	if MapScreen.up:
		s += " MAP"
	if tc.wheel.is_open:
		s += " WHEEL"
	if tc.more_open:
		s += " MORE"
	return s


func say(step_name: String, ok: bool, facts: String) -> void:
	print("CRITIC %s | %s | %s | state=%s%s" % [step_name, "ok" if ok else "BAD", facts, Game.state, overlay()])


func _run() -> void:
	root = tree.root
	out = OS.get_environment("CR_OUT")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	var parts := OS.get_environment("CR_PARTS").split(",", false)
	for q in root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	Game.force_touch = true
	CrateReveal._quiet = 0
	Sfx.muted = true
	hud = tree.get_first_node_in_group(&"hud")
	tc = root.find_children("*", "TouchControls", true, false)[0] as TouchControls
	await frames(20)
	# ---- title
	say("title", Game.state == &"menu", "buttons: " + menu_ids())
	await shot("00_title")
	var start_id: StringName = &"deploy" if menu_btn(&"deploy") != Vector2.INF else &"continue"
	await tap_menu(start_id)
	var t0 := Time.get_ticks_msec()
	while Game.state != &"play" and Time.get_ticks_msec() - t0 < 20000:
		await frames(5)
		if Game.state == &"cutscene":                           # a finger anywhere: does the intro let go?
			await tap(vp() * Vector2(0.5, 0.5))
	say("start", Game.state == &"play", "%s tapped, %.1f s to play, hud: %s" % [start_id, (Time.get_ticks_msec() - t0) / 1000.0, labels()])
	await secs(1.5)
	await shot("01_play")
	var p := Game.player as Player
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	if parts.is_empty() or parts.has("foot"):
		await _foot(p)
	if parts.is_empty() or parts.has("screens"):
		await _screens()
	if parts.is_empty() or parts.has("car"):
		await _car(p)
	if parts.is_empty() or parts.has("snake"):
		await _snake(p)
	if parts.has("fly2"):
		await _fly2(p)
	if parts.has("photo"):
		await _photo()
	if parts.is_empty() or parts.has("demo"):
		await _demo()
	if parts.has("fresh"):
		await _fresh()
	print("CRITIC END")
	_done = true
	tree.quit()


func _foot(p: Player) -> void:
	# walk: left thumb down, dragged up
	var a := p.global_position
	var sp := vp() * Vector2(0.14, 0.72)
	down(sp, 0)
	await frames(2)
	move(sp + Vector2(0, -vp().y * 0.16), 0)
	await secs(2.0)
	await shot("02_walk")
	up(0)
	say("walk", p.global_position.distance_to(a) > 2.0, "moved %.1f m in 2 s" % p.global_position.distance_to(a))
	# look: right thumb drag
	var y0 := p.rotation.y
	var cam := root.get_viewport().get_camera_3d()
	var cy := cam.global_rotation.y
	var lp := vp() * Vector2(0.62, 0.38)
	down(lp, 1)
	for i in 10:
		await frames(1)
		move(lp + Vector2(12.0 * (i + 1), 0), 1)
	up(1)
	await frames(3)
	say("look", absf(angle_difference(cam.global_rotation.y, cy)) > 0.1 or absf(angle_difference(p.rotation.y, y0)) > 0.1, "camera yaw moved %.2f rad" % angle_difference(cam.global_rotation.y, cy))
	# fire
	var am := p.ammo
	down(btn(&"fire"), 1)
	await secs(1.0)
	var am1 := p.ammo
	await shot("03_fire")
	up(1)
	say("fire", am1 < am, "ammo %d -> %d (%s)" % [am, am1, p.weapon.current])
	# reload
	await tap(btn(&"reload"), 1)
	await secs(2.5)
	say("reload", p.ammo >= am, "ammo %d" % p.ammo)
	# weapon: a tap cycles
	var w0 := p.weapon.current
	await tap(btn(&"swap"), 1, 1)
	await secs(0.8)
	say("swap_tap", p.weapon.current != w0, "%s -> %s" % [w0, p.weapon.current])
	# weapon wheel: hold, slide to a disc, release; a ring opens: tap a disc
	w0 = p.weapon.current
	var sb := btn(&"swap")
	down(sb, 1)
	var t := Time.get_ticks_msec()
	while not tc.wheel.is_open and Time.get_ticks_msec() - t < 3000:
		await frames(1)
	await frames(4)
	await shot("04_wheel")
	var n := tc.wheel.items.size()
	var names: Array[String] = []
	for i in n:
		names.append(str((tc.wheel.items[i] as Dictionary).get("label", "")))
	say("wheel_open", tc.wheel.is_open and n > 1, "%d discs: %s" % [n, ",".join(names)])
	if tc.wheel.is_open and n > 1:
		var pick := 3 % n
		move(tc.wheel.item_centre(pick), 1)
		await frames(4)
		up(1)
		await frames(6)
		await shot("05_wheel_ring")
		var guard := 0
		while tc.wheel.is_open and guard < 3:                    # the class ring: tap a weapon
			guard += 1
			var m := tc.wheel.items.size()
			await tap(tc.wheel.item_centre(mini(1, m - 1)), 1)
			await frames(6)
		await secs(0.8)
		say("wheel_pick", not tc.wheel.is_open and p.weapon.current != w0, "%s -> %s after %d ring taps" % [w0, p.weapon.current, guard])
	else:
		up(1)
	if tc.wheel.is_open:
		await tap(vp() * Vector2(0.5, 0.15), 1)
		say("wheel_close_outside", not tc.wheel.is_open, "tap outside")
	# ability wheel: quick tap opens, tap outside closes
	if btn(&"ability") != Vector2.INF:
		await tap(btn(&"ability"), 1, 1)
		await frames(5)
		var was := tc.wheel.is_open
		await shot("06_ability")
		await tap(vp() * Vector2(0.5, 0.12), 1)
		say("ability_wheel", was and not tc.wheel.is_open, "opened %s, closed by a tap outside %s" % [was, not tc.wheel.is_open])
	# MORE tray
	await tap(btn(&"more"), 1)
	await frames(6)
	var lm := labels()
	await shot("07_more")
	await tap(btn(&"more"), 1)
	say("more", not tc.more_open, "tray held: " + lm)
	# jump
	var y := p.global_position.y
	await tap(btn(&"jump"), 1, 4)
	var top := y
	for i in 20:
		await frames(1)
		top = maxf(top, p.global_position.y)
	say("jump", top - y > 0.5, "rose %.2f m" % (top - y))
	await secs(1.5)


func _screens() -> void:
	# pause
	await tap(tc._pause_center())
	await frames(10)
	say("pause", Game.state == &"paused", "buttons: " + menu_ids())
	await shot("10_pause")
	var ids := menu_ids().split(",")
	for id in ids:
		if id in ["resume", "menu", "deploy", "continue", "demo"]:
			continue
		if Game.state != &"paused":
			break
		var sig0 := menu_ids()
		await tap_menu(StringName(id))
		await frames(10)
		var inside := menu_ids()
		var opened := inside != sig0 or MapScreen.up or Game.state != &"paused"
		await shot("11_pause_" + id)
		# leave: the drawn BACK / CLOSE if there is one
		var left := false
		var how := ""
		if MapScreen.up:
			var ms := root.find_child("MapScreen", true, false) as MapScreen
			var cls := ms.find_child("Close", true, false) as Button
			await tap(cls.get_global_rect().get_center())
			await frames(10)
			how = "map CLOSE"
			left = not MapScreen.up
		else:
			for bid in [&"back", &"board_back", &"close", &"opt_back", &"done"]:
				if menu_btn(bid) != Vector2.INF:
					await tap_menu(bid)
					how = String(bid)
					break
			if how == "":
				for c in root.find_children("*", "Button", true, false):
					var bt := c as Button
					if bt.is_visible_in_tree() and bt.text.to_upper() in ["BACK", "CLOSE", "X", "DONE"]:
						await tap(bt.get_global_rect().get_center())
						how = "Button " + bt.text
						break
			await frames(10)
			left = menu_ids() == sig0 and Game.state == &"paused"
		say("pause>" + id, opened and left, "opened %s, left by [%s] %s; now: %s" % [opened, how, left, menu_ids().left(80)])
		if not left:
			await shot("12_stuck_" + id)
			break
	if Game.state == &"paused":
		await tap_menu(&"resume")
	say("resume", Game.state == &"play", "")
	# the map from the minimap
	await tap(tc._minimap_rect().get_center())
	await frames(30)
	var mup := MapScreen.up
	await shot("13_map")
	var ms2 := root.find_child("MapScreen", true, false) as MapScreen
	var cl := ms2.find_child("Close", true, false) as Button
	await tap(cl.get_global_rect().get_center())
	await frames(15)
	say("map", mup and not MapScreen.up and Game.state == &"play", "opened %s, closed %s" % [mup, not MapScreen.up])
	await shot("14_after_map")


func _car(p: Player) -> void:
	var vm := Game.vehicles as VehicleManager
	var best: Vehicle = null
	for v in root.find_children("*", "Vehicle", true, false):
		var vv := v as Vehicle
		if best == null or vv.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position):
			best = vv
	if best == null:
		say("car", false, "no vehicle in the scene")
		return
	var d0 := best.global_position.distance_to(p.global_position)
	p.global_position = best.global_position + best.global_transform.basis.x * 2.4 + Vector2.ZERO.x * Vector3.UP + Vector3.UP * 0.6      # set-up only: stand beside it
	p.velocity = Vector3.ZERO
	await secs(1.0)
	var use := btn(&"interact")
	say("car_prompt", use != Vector2.INF, "nearest car was %.0f m away; hud: %s" % [d0, labels()])
	await shot("20_car_beside")
	if use == Vector2.INF:
		return
	await tap(use, 1)
	await secs(2.0)
	say("car_enter", vm.driven != null, "hud: " + labels())
	await shot("21_car_in")
	if vm.driven == null:
		return
	var a := vm.driven.global_position
	var sp := vp() * Vector2(0.14, 0.72)
	down(sp, 0)
	await frames(2)
	move(sp + Vector2(0, -vp().y * 0.16), 0)
	await secs(3.0)
	await shot("22_car_drive")
	up(0)
	say("car_drive", vm.driven.global_position.distance_to(a) > 3.0, "drove %.1f m in 3 s" % vm.driven.global_position.distance_to(a))
	if btn(&"veh_view") != Vector2.INF:
		await tap(btn(&"veh_view"), 1)
	await secs(2.0)
	use = btn(&"interact")
	if use != Vector2.INF:
		await tap(use, 1)
	await secs(2.0)
	say("car_leave", vm.driven == null, "USE on screen %s; hud: %s" % [use != Vector2.INF, labels()])
	await shot("23_car_out")


func wait_btn(action: StringName, max_s := 2.0) -> Vector2:
	var t := Time.get_ticks_msec()
	while btn(action) == Vector2.INF and Time.get_ticks_msec() - t < max_s * 1000.0:
		await frames(1)
	return btn(action)


func _lab(action: StringName) -> String:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b):
			return tc._label_of(b)
	return ""


func _mode(p: Player) -> String:
	return SnakeTraversal.Mode.keys()[(p.snake as SnakeTraversal).mode]


func _snake(p: Player) -> void:
	await secs(1.0)
	say("snake_hud", btn(&"snake") != Vector2.INF, "hud: " + labels())
	# zip from the ground: hold SNAKE
	var a := p.global_position
	var sb := btn(&"snake")
	var lab := ""
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"snake" and tc.button_visible(b):
			lab = tc._label_of(b)
	if sb != Vector2.INF:
		down(sb, 1)
		await secs(0.6)
		var m := _mode(p)
		await shot("30_zip")
		await secs(1.4)
		up(1)
		say("zip_ground", m == "ZIP" or p.global_position.distance_to(a) > 4.0, "button read %s, mode %s, moved %.1f m" % [lab, m, p.global_position.distance_to(a)])
	await secs(2.5)
	say("zip_end", _mode(p) == "NONE", "mode %s 2.5 s after release, floor %s" % [_mode(p), p.is_on_floor()])
	# jump, then SWING in the air
	await tap(btn(&"jump"), 1, 1)
	var tj := Time.get_ticks_msec()
	while _lab(&"snake") != "SWING" and Time.get_ticks_msec() - tj < 1500:
		await frames(1)
	sb = btn(&"snake")
	var lab2 := _lab(&"snake")
	if sb != Vector2.INF:
		down(sb, 1)
		await secs(0.5)
		var m2 := _mode(p)
		await shot("31_swing")
		await secs(1.0)
		up(1)
		say("swing_air", m2 == "SWING", "button read %s, mode %s" % [lab2, m2])
	await secs(3.0)
	say("swing_end", _mode(p) == "NONE" and p.is_on_floor(), "mode %s, floor %s 3 s after release" % [_mode(p), p.is_on_floor()])
	# fly: jump, FLY
	await tap(btn(&"jump"), 1, 1)
	var fb: Vector2 = await wait_btn(&"fly", 2.0)
	say("fly_button", fb != Vector2.INF, "in the air the hud is: " + labels())
	if fb != Vector2.INF:
		await tap(fb, 1)
	await secs(0.8)
	say("fly_takeoff", _mode(p) == "FLY", "mode " + _mode(p) + "; hud: " + labels())
	if _mode(p) != "FLY":
		return
	# steer: stick up, JUMP held = climb
	var sp := vp() * Vector2(0.14, 0.72)
	down(sp, 0)
	await frames(2)
	move(sp + Vector2(0, -vp().y * 0.16), 0)
	var y0 := p.global_position.y
	down(btn(&"jump"), 1)
	await secs(2.5)
	up(1)
	await shot("32_fly_climb")
	say("fly_climb", p.global_position.y - y0 > 3.0, "rose %.1f m in 2.5 s with JUMP held; speed %.0f m/s" % [p.global_position.y - y0, p.velocity.length()])
	await secs(3.0)
	await shot("33_fly_cruise")
	say("fly_cruise", _mode(p) == "FLY", "height %.0f, speed %.0f, hud: %s" % [p.global_position.y, p.velocity.length(), labels()])
	# pause and the map while flying
	await tap(tc._pause_center(), 1)
	await frames(8)
	var paused := Game.state == &"paused"
	if paused:
		await tap_menu(&"resume")
	say("fly_pause", paused and Game.state == &"play" and _mode(p) == "FLY", "paused %s, back in flight %s" % [paused, _mode(p)])
	up(0)
	# land
	fb = btn(&"fly")
	var fl := ""
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"fly" and tc.button_visible(b):
			fl = tc._label_of(b)
	var t := Time.get_ticks_msec()
	if fb != Vector2.INF:
		await tap(fb, 1)
	while not (p.is_on_floor() and _mode(p) == "NONE") and Time.get_ticks_msec() - t < 25000:
		await frames(2)
	var took := (Time.get_ticks_msec() - t) / 1000.0
	await shot("34_landed")
	say("fly_land", p.is_on_floor() and _mode(p) == "NONE", "button read %s; on the ground after %.1f s, mode %s, y %.1f" % [fl, took, _mode(p), p.global_position.y])
	await secs(4.0)
	await shot("35_after_land")
	say("after_land", _mode(p) == "NONE" and not CrateReveal.is_showing(), "4 s later: mode %s, hud: %s" % [_mode(p), labels()])


func _demo() -> void:
	await tap(tc._pause_center(), 1)
	await frames(10)
	await tap_menu(&"menu_gear")
	say("extras", menu_btn(&"menu") != Vector2.INF, "buttons: " + menu_ids())
	await shot("39_extras")
	await tap_menu(&"menu")
	await frames(20)
	if Game.state != &"menu":                                    # a confirm?
		await shot("40_abort_confirm")
		say("to_title", false, "after MENU: " + menu_ids())
		for bid in [&"confirm", &"yes", &"menu"]:
			if menu_btn(bid) != Vector2.INF:
				await tap_menu(bid)
				break
		await frames(20)
	say("title_again", Game.state == &"menu", "buttons: " + menu_ids())
	await shot("41_title_again")
	await tap_menu(&"menu_gear")
	await shot("41b_title_extras")
	say("title_extras", menu_btn(&"demo") != Vector2.INF, "buttons: " + menu_ids())
	await tap_menu(&"demo")
	var t := Time.get_ticks_msec()
	while Game.state != &"play" and Time.get_ticks_msec() - t < 15000:
		await frames(5)
		if Game.state == &"cutscene":
			await tap(vp() * Vector2(0.5, 0.5))
	await secs(2.0)
	say("demo_on", DemoMode.active and Game.state == &"play", "active %s, hud: %s" % [DemoMode.active, labels()])
	await shot("42_demo")
	await secs(4.0)
	say("demo_cards", not CrateReveal.is_showing() and CrateReveal._queue.is_empty(), "card %s queue %d" % [CrateReveal.is_showing(), CrateReveal._queue.size()])
	await shot("43_demo_4s")
	# the demo menu: where is it? list the panel and quit by finger
	var dp := tree.get_first_node_in_group(&"demo_panel")
	say("demo_panel", dp != null, "panel %s visible %s" % [dp, dp != null and (dp as CanvasItem if dp is CanvasItem else null) != null])
	await tap(tc._pause_center(), 1)
	await frames(10)
	say("demo_pause", Game.state == &"paused", "buttons: " + menu_ids())
	await shot("44_demo_pause")
	await tap_menu(&"menu_gear")
	await tap_menu(&"menu")
	await frames(30)
	say("demo_off", not DemoMode.active and Game.state == &"menu", "active %s; title buttons: %s" % [DemoMode.active, menu_ids()])
	await shot("45_demo_left")
	# and a normal game starts again after the demo
	await tap_menu(&"continue" if menu_btn(&"continue") != Vector2.INF else &"deploy")
	var t2 := Time.get_ticks_msec()
	while Game.state != &"play" and Time.get_ticks_msec() - t2 < 15000:
		await frames(5)
		if Game.state == &"cutscene":
			await tap(vp() * Vector2(0.5, 0.5))
	await secs(2.0)
	say("play_after_demo", Game.state == &"play" and not DemoMode.active, "hud: " + labels())
	await shot("46_play_after_demo")


func _fly2(p: Player) -> void:
	p.global_position += Vector3.UP * 70.0                      # set-up only: high over the street, falling
	p.velocity = Vector3.ZERO
	var fb: Vector2 = await wait_btn(&"fly", 3.0)
	if fb == Vector2.INF:
		say("fly2_button", false, "no FLY in a fall; hud " + labels())
		return
	await tap(fb, 1, 1)
	await secs(1.0)
	say("fly2_takeoff", _mode(p) == "FLY", "mode %s height %.0f" % [_mode(p), p.global_position.y])
	var sp := vp() * Vector2(0.14, 0.72)
	down(sp, 0)
	await frames(2)
	move(sp + Vector2(0, -vp().y * 0.16), 0)
	var a := p.global_position
	await secs(2.0)
	say("fly2_forward", p.global_position.distance_to(a) > 10.0, "stick forward 2 s: %.0f m, speed %.0f m/s, energy %.0f" % [p.global_position.distance_to(a), p.velocity.length(), (p.snake as SnakeTraversal).energy])
	await shot("50_fly2")
	up(0)
	await tap(tc._pause_center(), 1)
	await frames(8)
	var paused := Game.state == &"paused"
	await shot("51_fly2_paused")
	await tap_menu(&"resume")
	await frames(5)
	say("fly2_pause", paused and Game.state == &"play" and _mode(p) == "FLY", "paused %s, after RESUME mode %s height %.0f" % [paused, _mode(p), p.global_position.y])
	# the map in flight
	await tap(tc._minimap_rect().get_center(), 1)
	await frames(20)
	var mup := MapScreen.up
	var ms := root.find_child("MapScreen", true, false) as MapScreen
	await tap((ms.find_child("Close", true, false) as Button).get_global_rect().get_center(), 1)
	await frames(10)
	say("fly2_map", mup and not MapScreen.up and _mode(p) == "FLY", "map opened %s closed %s, mode %s height %.0f" % [mup, not MapScreen.up, _mode(p), p.global_position.y])
	if _mode(p) != "FLY":
		return
	# LAND, and LAND again half a second later
	var h := p.global_position.y
	await tap(btn(&"fly"), 1, 1)
	await secs(0.5)
	var l2 := _lab(&"fly")
	if btn(&"fly") != Vector2.INF:
		await tap(btn(&"fly"), 1, 1)
	var t := Time.get_ticks_msec()
	while not (p.is_on_floor() and _mode(p) == "NONE") and Time.get_ticks_msec() - t < 12000:
		await frames(2)
	say("fly2_land_twice", p.is_on_floor() and _mode(p) == "NONE", "from %.0f m; the button read [%s] at the second press; %.1f s later mode %s, floor %s, height %.0f" % [h, l2, (Time.get_ticks_msec() - t) / 1000.0, _mode(p), p.is_on_floor(), p.global_position.y])
	await shot("52_fly2_end")
	if _mode(p) == "FLY":
		await tap(btn(&"fly"), 1, 1)
		await secs(6.0)


func _photo() -> void:
	await tap(tc._pause_center(), 1)
	await frames(10)
	await tap_menu(&"menu_gear")
	await tap_menu(&"photo_open")
	await frames(15)
	await shot("60_photo")
	var photo := bool(hud.call(&"photo_open"))
	say("photo_open", photo, "state %s; menu: %s" % [Game.state, menu_ids()])
	# a finger on the view (orbit), then find a way out: any Button, any drawn button
	await tap(vp() * Vector2(0.5, 0.5), 1)
	await frames(10)
	await shot("61_photo_tapped")
	var names: Array[String] = []
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).is_visible_in_tree():
			names.append((c as Button).text)
	say("photo_controls", true, "after a tap on the view: photo %s; Buttons: %s; menu: %s" % [hud.call(&"photo_open"), ",".join(names), menu_ids()])
	var out_ok := false
	for c in root.find_children("*", "Button", true, false):
		var bt := c as Button
		if bt.is_visible_in_tree() and bt.text.to_upper() in ["BACK", "CLOSE", "EXIT", "DONE", "X"]:
			await tap(bt.get_global_rect().get_center(), 1)
			await frames(10)
			out_ok = not bool(hud.call(&"photo_open"))
			break
	if not out_ok:
		for bid in [&"photo_close", &"photo_back", &"back", &"close"]:
			if menu_btn(bid) != Vector2.INF:
				await tap_menu(bid)
				out_ok = not bool(hud.call(&"photo_open"))
				break
	say("photo_leave", out_ok, "photo %s state %s menu %s" % [hud.call(&"photo_open"), Game.state, menu_ids()])
	await shot("62_photo_left")
	var guard := 0
	while Game.state == &"paused" and guard < 4:
		guard += 1
		if menu_btn(&"resume") != Vector2.INF:
			await tap_menu(&"resume")
		elif menu_btn(&"more_back") != Vector2.INF:
			await tap_menu(&"more_back")
		else:
			break
	say("photo_resume", Game.state == &"play", "")


func _fresh() -> void:
	# to the title, then a NEW GAME by finger: what does the first minute ask of a thumb?
	if Game.state == &"play":
		await tap(tc._pause_center(), 1)
		await frames(10)
		await tap_menu(&"menu_gear")
		await tap_menu(&"menu")
		await frames(20)
	await shot("70_title")
	say("fresh_title", Game.state == &"menu", "buttons: " + menu_ids())
	if menu_btn(&"deploy") == Vector2.INF:
		await tap_menu(&"menu_gear")
		say("fresh_extras", menu_btn(&"deploy") != Vector2.INF, "buttons: " + menu_ids())
	await tap_menu(&"deploy")
	await frames(6)
	if Game.state == &"menu":
		await shot("71_newgame_confirm")
		say("fresh_confirm", true, "still the menu: " + menu_ids())
		for bid in [&"deploy", &"confirm", &"yes", &"new_yes"]:
			if menu_btn(bid) != Vector2.INF:
				await tap_menu(bid)
				break
	for line in ["+30 INTEGRITY", "NEW MOD  RED DOT  (LOADOUT TO EQUIP)", "+60 FLUX SMG", "+1 SCRAP"]:      # set-up: four pickups, the feed is up in the first frames
		Game.say(line, 2.0)
	var t := Time.get_ticks_msec()
	var last := &""
	var i := 0
	while Time.get_ticks_msec() - t < 30000:
		await frames(2)
		if Game.state != last:
			last = Game.state
			print("CRITIC fresh state %s at %.1f s%s" % [last, (Time.get_ticks_msec() - t) / 1000.0, overlay()])
		if (Time.get_ticks_msec() - t) / 2500 >= i:
			await shot("72_fresh_%02d" % i)
			i += 1
			if Game.state == &"cutscene" and i >= 2:               # after 2.5 s of watching: a finger on the middle, then on any SKIP drawn
				await tap(vp() * Vector2(0.5, 0.5), 1)
		if Game.state == &"play" and (Time.get_ticks_msec() - t) > 14000:
			break
	say("fresh_play", Game.state == &"play", "%.1f s after NEW GAME; hud: %s" % [(Time.get_ticks_msec() - t) / 1000.0, labels()])
	# can the thumb act at once? walk and fire
	var p := Game.player as Player
	var a := p.global_position
	var sp := vp() * Vector2(0.14, 0.72)
	down(sp, 0)
	await frames(2)
	move(sp + Vector2(0, -vp().y * 0.16), 0)
	var am := p.ammo
	down(btn(&"fire"), 1)
	await secs(1.5)
	await shot("73_fresh_act")
	say("fresh_act", p.global_position.distance_to(a) > 2.0 and p.ammo < am, "walked %.1f m, ammo %d -> %d in the first 1.5 s" % [p.global_position.distance_to(a), am, p.ammo])
	up(0)
	up(1)
	await tap(tc._pause_center(), 1)
	await frames(8)
	say("fresh_pause", Game.state == &"paused", "PAUSE in the first seconds")
	await shot("74_fresh_pause")
