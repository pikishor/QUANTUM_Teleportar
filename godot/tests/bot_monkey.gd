extends RefCounted
## MONKEY BOT: a seeded random-input monkey on the REAL composed game (scenes/main.tscn). docs/QA.md has the full description.
##
## It throws touch events (down / drag / up, several fingers, biased toward the stick, the look zone, every touch button, the pause button, the FPS box and every button of the
## current screen), mouse clicks and moves, key presses (ESC, ENTER, SPACE, F10, movement, weapons, powers ... and random keys), raw action presses, window resizes (phone
## portrait, landscape, tablet), focus loss, and a little game chaos (damage, death, enemies, a win, quality tier, the test menu, doors, cars) at the game for N simulated
## minutes. The same seed plays the same game (the input stream is a pure function of the seed and the clock, the game itself runs at its own pace).
## It must never crash (no script / engine error) and never soft lock: every PROBE_EVERY seconds the monkey stops, lets go of everything and plays like a person who wants out:
## only legitimate taps (RESPAWN, NEXT SECTOR, RESUME, DEPLOY, CLOSE of the test menu or the vendor window, tap through cards and cutscenes). The state must be play within
## RECOVER_LIMIT game seconds (the title screen counts as alive but must itself lead to play), no input may stay held outside play, the time scale must be back to normal,
## no interior transition may hang, and the HUD layers must match the state. A failed probe prints the whole UI state.
##
## Run it:  tools/soak.sh --monkey [--minutes=5] [--seed=1] [--rate=14] [--render]      (touch controls on)
## or from a test: var bot := preload("res://tests/bot_monkey.gd").new(); bot.minutes = 1.0; await bot.run(host); bot.report["verdict"]
## Options (command line after `--`): --minutes=N --seed=N --rate=events per game second --speed=N (time scale) --no-chaos (input events only) --no-resize --real --quiet

const Lib := preload("res://tests/soak_lib.gd")

const PROBE_EVERY := 20.0                  ## game seconds between soft-lock probes
const RECOVER_LIMIT := 30.0                ## game seconds a probe may take to get back to play
const STALL_REAL_SECONDS := 90.0
const KEYS: Array[Key] = [KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_TAB, KEY_F10, KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_R, KEY_Q, KEY_E, KEY_G,
		KEY_F, KEY_X, KEY_1, KEY_2, KEY_3, KEY_4, KEY_B, KEY_BACKSPACE, KEY_DELETE, KEY_F1, KEY_F5, KEY_F12, KEY_Z, KEY_C, KEY_V, KEY_M, KEY_P]
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(360, 800), Vector2i(800, 360), Vector2i(1170, 540), Vector2i(2400, 1080), Vector2i(1024, 768), Vector2i(320, 480), Vector2i(1920, 1080)]
const MODES: Array[StringName] = [&"wild", &"play", &"ui", &"keys", &"chaos"]
const ENEMY_TYPES: Array[StringName] = [&"sentinel", &"striker", &"heavy", &"operative", &"shield", &"flanker", &"sniper", &"brute"]

var minutes := 5.0
var speed := 4
var seed_value := 1
var rate := 14.0                            ## input events per game second
var chaos := true
var verbose := true
var max_events := 0                         ## 0: until `minutes` have passed
var resize := DisplayServer.get_name() == "headless"   ## window size changes among the events (phone portrait, tablet ...). Headless only: under a real display server (xvfb) a resized window hangs Godot at exit
var real := false                           ## cutscenes, scripted campaign and tutorial on (Lib.enable_real); off by default like every tool run
var quit_on_finish := false

var finished := false
var report: Dictionary = {}
var fails: PackedStringArray = PackedStringArray()
var counts: Dictionary = {}                 ## events sent by kind, probes, recoveries, states seen

var _tree: SceneTree
var rng := RandomNumberGenerator.new()
var _tap: Lib.ErrorTap
var _clock := 0.0
var _started := false
var _stall_real := 0
var _stall_clock := 0.0
var _next_probe := PROBE_EVERY
var _p: Player
var _hud: Hud
var _ig: InteriorGameplay
var _touch: TouchControls
var _tm: TestMenu
var _fingers := {}                          ## index -> position of every finger that is down
var _keys_down := {}                        ## keycode -> true
var _mouse_down := false
var _mode: StringName = &"wild"
var _mode_until := 0.0
var _events := 0
var _old_scale := 1.0
var _old_ticks := 60
var _old_muted := false
var _old_size := Vector2i.ZERO
var _err_seen := 0
var _last_event := ""
var _state_seen := {}
var _settings_path := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else "true"
		match kv[0]:
			"minutes": minutes = float(v)
			"seed": seed_value = int(v)
			"speed": speed = int(v)
			"rate": rate = float(v)
			"no-chaos": chaos = false
			"no-resize": resize = false
			"resize": resize = true
			"real": real = true
			"quiet": verbose = false
			"events": max_events = int(v)


func step(_t: float, _delta: float) -> bool:
	if not _started:
		_started = true
		quit_on_finish = true
		run((Engine.get_main_loop() as SceneTree).root)
	return finished


func run(host: Node) -> void:
	_tree = host.get_tree()
	_tap = Lib.ErrorTap.new()
	OS.add_logger(_tap)
	_old_scale = Engine.time_scale
	_old_ticks = Engine.physics_ticks_per_second
	_old_muted = Sfx.muted
	Sfx.muted = true
	if speed > 0:
		Engine.physics_ticks_per_second = 60 * speed
		Engine.time_scale = float(speed)
	rng.seed = seed_value
	_stall_real = Time.get_ticks_msec()
	for i in 40:
		await _tick()
		if is_instance_valid(Game.player) and Game.state == &"play" and is_instance_valid(Game.world):
			break
	_p = Game.player as Player
	_hud = Lib.find_hud()
	_ig = InteriorGameplay.instance
	_touch = _hud.touch if _hud != null else null
	var tms := _tree.get_nodes_in_group(&"test_menu")
	_tm = tms[0] as TestMenu if not tms.is_empty() else null
	if _p == null or _hud == null or not is_instance_valid(Game.world):
		fails.append("setup: the composed game is not there (player %s, hud %s, world %s)" % [_p, _hud, Game.world])
		await _finish()
		return
	_old_size = _tree.root.size
	_settings_path = "user://soak_settings.cfg"
	_hud.settings.path = _settings_path                                # the settings buttons save: never into the player's own file
	if real:
		Lib.enable_real(_hud)
	_err_seen = _tap.total
	await _wait(2.0)
	_log("MONKEY start: seed=%d minutes=%.1f rate=%.0f/s speed=%d chaos=%s real=%s touch=%s test_menu=%s renderer=%s" % [seed_value, minutes, rate, speed, str(chaos), str(real), str(_touch != null and _touch.controls_on),
			str(_tm != null), "software" if Lib.renders() else "headless"])
	_new_mode()
	var per_tick := rate / 60.0                                        # events per physics tick (a tick is 1/60 game second at every speed)
	var acc := 0.0
	while fails.is_empty() and (max_events > 0 and _events < max_events or max_events == 0 and _clock < minutes * 60.0):
		acc += per_tick
		while acc >= 1.0:
			acc -= 1.0
			_event()
		if _clock >= _mode_until:
			_new_mode()
		await _tick()
		if _clock >= _next_probe:
			_next_probe = _clock + PROBE_EVERY
			await _probe()
	if fails.is_empty():
		await _probe()
	await _finish()


# --- clock and guards -------------------------------------------------------------------------------------------------------

func _tick() -> void:
	await _tree.physics_frame
	_clock += _tree.root.get_physics_process_delta_time()
	var now := Time.get_ticks_msec()
	if _clock > _stall_clock + 0.5:
		_stall_clock = _clock
		_stall_real = now
	elif float(now - _stall_real) / 1000.0 > STALL_REAL_SECONDS:
		fails.append("stall: no game time passed for %.0f real seconds (state %s, last event: %s)" % [STALL_REAL_SECONDS, Game.state, _last_event])
		_stall_real = now
	if _tap != null and _tap.total != _err_seen:
		_err_seen = _tap.total
		var el := _tap.snapshot()
		_log("  ! error #%d at t=%.1fs after '%s' (state %s): %s" % [_err_seen, _clock, _last_event, Game.state, el[el.size() - 1] if not el.is_empty() else "?"])
	if _p != null:
		var s := String(Game.state)
		if not _state_seen.has(s):
			_state_seen[s] = 0.0
		_state_seen[s] = float(_state_seen[s]) + 1.0 / 60.0
		if not Lib.STATES.has(Game.state):
			fails.append("unknown game state '%s' after '%s'" % [Game.state, _last_event])


func _wait(sec: float) -> void:
	var end := _clock + sec
	while _clock < end and fails.is_empty():
		await _tick()


func _count(key: String, n := 1) -> void:
	counts[key] = int(counts.get(key, 0)) + n


func _log(s: String) -> void:
	if verbose:
		print(s)


func _new_mode() -> void:
	_mode = MODES[rng.randi() % MODES.size()]
	_mode_until = _clock + rng.randf_range(4.0, 9.0)
	_count("mode_" + String(_mode))


# --- the events -------------------------------------------------------------------------------------------------------------

func _vp() -> Vector2:
	return _tree.root.get_visible_rect().size


## A screen position: a random one, a hot spot (button, zone) or a spot just outside the screen.
func _pos() -> Vector2:
	var vp := _vp()
	var r := rng.randf()
	if r < 0.04:
		return Vector2(rng.randf_range(-80.0, vp.x + 80.0), rng.randf_range(-80.0, vp.y + 80.0))
	if r < 0.35:
		var spots := _hot_spots()
		if not spots.is_empty():
			return spots[rng.randi() % spots.size()] + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
	if r < 0.55:
		return Vector2(rng.randf_range(0.0, vp.x * 0.4), rng.randf_range(vp.y * 0.4, vp.y))       # the move stick zone
	return Vector2(rng.randf_range(0.0, vp.x), rng.randf_range(0.0, vp.y))


## Centres of everything tappable right now: touch buttons, pause button, FPS box, the screen's buttons, the TEST button and menu items, the vendor rows.
func _hot_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _hud != null:
		_hud.call(&"_ensure_layout")
		for b: Dictionary in _hud.buttons:
			out.append((b["rect"] as Rect2).get_center())
		if _touch != null and _touch.controls_on:
			for b: Dictionary in TouchControls.BUTTONS:
				out.append(_touch.call(&"_button_center", b))
			out.append(_touch.call(&"_pause_center"))
			out.append((_touch.call(&"_perf_box") as Rect2).get_center())
	if _tm != null:
		if _tm.is_open:
			_tm.layout()
			for it in _tm.items:
				if not it.get("head", false):
					var r: Rect2 = it["rect"]
					out.append(Vector2(r.get_center().x, r.get_center().y + _tm._top() - _tm.scroll))
			out.append(_tm._close_rect().get_center())
			for t in _tm._tab_rects():
				out.append(t.get_center())
		else:
			out.append(_tm.entry_rect().get_center())
			for i in TestMenu.QUICK_IDS.size():
				out.append(_tm.quick_rect(i).get_center())
	if _ig != null and is_instance_valid(_ig.vendor_screen) and _ig.vendor_screen.is_open:
		for r: Rect2 in _ig.vendor_screen.rects:
			out.append(r.get_center())
		out.append(_ig.vendor_screen.close_rect.get_center())
	return out


func _event() -> void:
	_events += 1
	var w := _weights()
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	var pick := rng.randf() * total
	var kind := "touch"
	for k: String in w:
		pick -= float(w[k])
		if pick <= 0.0:
			kind = k
			break
	_count("ev_" + kind)
	match kind:
		"touch": _ev_touch()
		"drag": _ev_drag()
		"lift": _ev_lift()
		"click": _ev_click()
		"mouse_move": _ev_mouse_move()
		"key": _ev_key()
		"action": _ev_action()
		"resize": _ev_resize()
		"focus": _ev_focus()
		"chaos": _ev_chaos()


func _weights() -> Dictionary:
	match _mode:
		&"play":
			return {"touch": 18.0, "drag": 40.0, "lift": 16.0, "click": 1.0, "mouse_move": 1.0, "key": 3.0, "action": 4.0, "resize": 0.05, "focus": 0.1, "chaos": 2.0 if chaos else 0.0}
		&"ui":
			return {"touch": 20.0, "drag": 4.0, "lift": 14.0, "click": 30.0, "mouse_move": 4.0, "key": 6.0, "action": 1.0, "resize": 0.2, "focus": 0.2, "chaos": 1.0 if chaos else 0.0}
		&"keys":
			return {"touch": 2.0, "drag": 1.0, "lift": 2.0, "click": 2.0, "mouse_move": 1.0, "key": 60.0, "action": 12.0, "resize": 0.1, "focus": 0.2, "chaos": 0.5 if chaos else 0.0}
		&"chaos":
			return {"touch": 8.0, "drag": 8.0, "lift": 8.0, "click": 6.0, "mouse_move": 1.0, "key": 8.0, "action": 3.0, "resize": 0.3, "focus": 0.5, "chaos": 14.0 if chaos else 0.0}
	return {"touch": 14.0, "drag": 14.0, "lift": 12.0, "click": 12.0, "mouse_move": 3.0, "key": 14.0, "action": 4.0, "resize": 0.2, "focus": 0.3, "chaos": 4.0 if chaos else 0.0}


func _ev_touch() -> void:
	var idx := rng.randi() % 5
	var pos := _pos()
	_last_event = "touch down %d at %s" % [idx, str(pos.round())]
	_fingers[idx] = pos
	Lib.touch_event(idx, pos, true)


func _ev_drag() -> void:
	if _fingers.is_empty():
		_ev_touch()
		return
	var keys := _fingers.keys()
	var idx: int = keys[rng.randi() % keys.size()]
	var from: Vector2 = _fingers[idx]
	var rel := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
	if rng.randf() < 0.03:
		rel *= 40.0                                                  # a violent flick
	var to := from + rel
	_fingers[idx] = to
	_last_event = "drag %d to %s" % [idx, str(to.round())]
	Lib.drag_event(idx, to, rel)


func _ev_lift() -> void:
	if _fingers.is_empty():
		return
	var keys := _fingers.keys()
	var idx: int = keys[rng.randi() % keys.size()]
	var pos: Vector2 = _fingers[idx]
	_fingers.erase(idx)
	_last_event = "touch up %d at %s" % [idx, str(pos.round())]
	Lib.touch_event(idx, pos, false)


func _ev_click() -> void:
	var pos := _pos()
	_last_event = "click at %s" % str(pos.round())
	if _mouse_down:
		Lib.mouse_event(pos, false)
		_mouse_down = false
	else:
		Lib.mouse_event(pos, true)
		_mouse_down = true
		if rng.randf() < 0.7:                                        # most clicks are quick
			Lib.mouse_event(pos, false)
			_mouse_down = false


func _ev_mouse_move() -> void:
	var e := InputEventMouseMotion.new()
	e.position = _pos()
	e.relative = Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _mouse_down else 0
	_last_event = "mouse move"
	Lib.send(e)


func _ev_key() -> void:
	var k: Key = KEYS[rng.randi() % KEYS.size()] if rng.randf() < 0.85 else (rng.randi_range(KEY_A, KEY_Z) as Key)
	var down := not _keys_down.has(k) or rng.randf() < 0.3
	_last_event = "key %s %s" % [OS.get_keycode_string(k), "down" if down else "up"]
	if down:
		_keys_down[k] = true
	else:
		_keys_down.erase(k)
	Lib.key_event(k, down)
	if down and rng.randf() < 0.5:
		_keys_down.erase(k)
		Lib.key_event(k, false)                                      # a quick tap


func _ev_action() -> void:
	var actions := InputMap.get_actions().filter(func(a: StringName) -> bool: return not String(a).begins_with("ui_"))
	var a: StringName = actions[rng.randi() % actions.size()]
	_last_event = "action %s" % a
	if Input.is_action_pressed(a):
		Input.action_release(a)
	else:
		Input.action_press(a, rng.randf_range(0.2, 1.0))


func _ev_resize() -> void:
	if not resize:
		return
	var s: Vector2i = SIZES[rng.randi() % SIZES.size()]
	_last_event = "resize %s" % str(s)
	_tree.root.size = s


func _ev_focus() -> void:
	_last_event = "focus out / in"
	_tree.root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if rng.randf() < 0.7:
		_tree.root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)


## Game chaos: things a session throws up that no single input does. Direct API calls, each one a legal gameplay event.
func _ev_chaos() -> void:
	var c := rng.randi() % 14
	var em := Game.enemies as EnemyManager
	var vm := Game.vehicles as VehicleManager
	match c:
		0:
			_last_event = "chaos: heavy damage"
			if is_instance_valid(_p):
				_p.damage(rng.randf_range(20.0, 140.0), _p.global_position + Vector3(rng.randf_range(-5, 5), 0.0, rng.randf_range(-5, 5)))
		1:
			_last_event = "chaos: lethal damage"
			if is_instance_valid(_p) and rng.randf() < 0.8:
				_p.invuln = 0.0
				_p.damage(10000.0)
		2:
			_last_event = "chaos: enemy"
			if em != null and is_instance_valid(_p):
				em.spawn(ENEMY_TYPES[rng.randi() % ENEMY_TYPES.size()], _p.global_position + Vector3(rng.randf_range(-15, 15), 0.0, rng.randf_range(-15, 15)), true)
		3:
			_last_event = "chaos: win"
			if rng.randf() < 0.5:
				Game.win()
		4:
			_last_event = "chaos: quality"
			Game.set_quality(rng.randi() % 3)
		5:
			_last_event = "chaos: heat"
			Game.add_heat(rng.randf_range(0.5, 3.0))
		6:
			_last_event = "chaos: door"
			if _ig != null and Game.is_playing() and not InteriorGameplay.active:
				var list := _ig.doors()
				if not list.is_empty():
					var d: Dictionary = list[rng.randi() % list.size()]
					_p.teleport_to(d["pos"])
					_ig.enter(d, rng.randf() < 0.5)
		7:
			_last_event = "chaos: leave interior"
			if _ig != null and InteriorGameplay.active:
				_ig.leave(rng.randf() < 0.5)
		8:
			_last_event = "chaos: car"
			if vm != null and Game.is_playing() and is_instance_valid(_p):
				var car := vm.nearest(_p.global_position, 120.0)
				if car != null:
					_p.teleport_to(car.global_position + car.global_basis.x * 2.6)
					vm.toggle_enter_exit()
		9:
			_last_event = "chaos: teleport"
			if is_instance_valid(_p) and not InteriorGameplay.active:
				var pt := (Game.world as City).random_road_point()
				_p.teleport_to(Vector3(pt.x, 0.0, pt.z))
		10:
			_last_event = "chaos: explosion"
			if is_instance_valid(_p):
				Game.explode(_p.global_position + Vector3(rng.randf_range(-12, 12), 0.0, rng.randf_range(-12, 12)), rng.randf_range(4.0, 9.0), {"player_dmg": 25.0})
		11:
			_last_event = "chaos: weather"
			if is_instance_valid(Game.atmosphere):
				(Game.atmosphere as Atmosphere).set_weather(rng.randf(), rng.randf())
		12:
			_last_event = "chaos: pause, then ABORT TO MENU"                      # the run is abandoned wherever it is (prologue cards, interior, vehicle, fight)
			if Game.state == &"play":
				_hud.pause_game()
			if Game.state == &"paused":
				_hud.press_button(&"menu")
		13:
			_last_event = "chaos: DEPLOY / CONTINUE from the title screen"
			if Game.state == &"menu":
				_hud.press_button(&"deploy" if rng.randf() < 0.7 else &"continue")


# --- the soft-lock probe ----------------------------------------------------------------------------------------------------

func _let_go() -> void:
	for idx in _fingers.keys():
		Lib.touch_event(idx, _fingers[idx], false)
	_fingers.clear()
	for k in _keys_down.keys():
		Lib.key_event(k, false)
	_keys_down.clear()
	if _mouse_down:
		Lib.mouse_event(Vector2(10, 10), false)
		_mouse_down = false
	Lib.release_everything()
	_tree.root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)


func _click(pos: Vector2) -> void:
	Lib.mouse_event(pos, true)
	await _tick()
	Lib.mouse_event(pos, false)
	await _tick()


func _click_button(id: StringName) -> bool:
	_hud.call(&"_ensure_layout")
	for b: Dictionary in _hud.buttons:
		if b["id"] == id:
			await _click((b["rect"] as Rect2).get_center())
			return true
	return false


## One attempt of a person who wants to get on with the game, whatever is on the screen.
func _human_step() -> void:
	if _tm != null and _tm.is_open:
		await _click(_tm._close_rect().get_center())
		return
	if _ig != null and is_instance_valid(_ig.vendor_screen) and _ig.vendor_screen.is_open:
		await _click(_ig.vendor_screen.close_rect.get_center())
		Lib.key_event(KEY_ESCAPE, true)
		await _tick()
		Lib.key_event(KEY_ESCAPE, false)
		return
	match Game.state:
		&"dead":
			if not await _click_button(&"respawn"):
				await _click(Vector2(100, 100))
		&"win":
			if not await _click_button(&"next"):
				await _click(Vector2(100, 100))
		&"paused":
			if not await _click_button(&"resume"):
				Lib.key_event(KEY_ESCAPE, true)
				await _tick()
				Lib.key_event(KEY_ESCAPE, false)
		&"menu":
			if not await _click_button(&"deploy"):
				if not await _click_button(&"continue"):
					Lib.key_event(KEY_ENTER, true)
					await _tick()
					Lib.key_event(KEY_ENTER, false)
		&"cutscene":
			await _click(Vector2(200, 200))
		&"play":
			if _hud.get("_chapters_open") == true or _hud.get("_shop_open") == true:
				await _click_button(&"shop_back")
			var story := Game.story
			if story != null and not story.cards.is_empty():
				await _click(Vector2(300, 300))                          # cards swallow the first taps by design: they advance
	await _wait(0.25)


func _probe() -> void:
	_count("probes")
	_let_go()
	var restore := Engine.time_scale
	await _wait(0.5)
	var t0 := _clock
	var tries := 0
	# a probe wants the game in play, nothing open, nothing busy
	while fails.is_empty() and _clock - t0 < RECOVER_LIMIT:
		var vendor: bool = _ig != null and is_instance_valid(_ig.vendor_screen) and _ig.vendor_screen.is_open
		var menu_open: bool = _tm != null and _tm.is_open
		var cards: bool = Game.story != null and not Game.story.cards.is_empty()
		if Game.state == &"play" and not vendor and not menu_open and not cards:
			break
		tries += 1
		await _human_step()
	if not fails.is_empty():
		return
	if Game.state != &"play":
		fails.append("soft lock: state '%s' after %d recovery taps over %.0f game seconds (last event: %s). %s" % [Game.state, tries, _clock - t0, _last_event, _ui_dump()])
		return
	if tries > 0:
		_count("recoveries")
		if tries > 12:
			_count("slow_recoveries")
	# the interior transition must end by itself
	if _ig != null and _ig.busy:
		var e := _clock + 6.0
		while _ig.busy and _clock < e:
			await _tick()
		if _ig.busy:
			fails.append("soft lock: the interior transition never ended (active=%s, last event: %s)" % [InteriorGameplay.active, _last_event])
			return
	await _wait(1.0)
	# nothing may be held or stuck now
	if Game.state != &"play":
		await _ensure_back()
	if Game.state == &"play":
		if absf(Engine.time_scale - float(maxi(speed, 1) if speed > 0 else restore)) > 0.01 and speed > 0:
			fails.append("time scale stuck at %.2f after a probe (expected %d; slow motion never ended?)" % [Engine.time_scale, speed])
			return
		if not is_instance_valid(_p) or not _p.global_position.is_finite():
			fails.append("the player's position is not finite or the player is gone")
			return
		if not _hud.layers_consistent():
			fails.append("the HUD layers do not match the state '%s' after a probe" % Game.state)
			return
		if is_instance_valid(Game.camera) and not Game.camera.current:
			fails.append("no current gameplay camera after a probe")
			return
		if _p.vehicle == null and not _p.visible and not InteriorGameplay.active:
			fails.append("the player is on foot but invisible after a probe")
			return
	# the player must be able to act: a pause and resume works
	Lib.key_event(KEY_ESCAPE, true)
	await _tick()
	Lib.key_event(KEY_ESCAPE, false)
	await _wait(0.3)
	if Game.state != &"paused" and Game.state == &"play":
		_count("pause_ignored")
	await _ensure_back()


## Back to play after a probe's own pause.
func _ensure_back() -> void:
	var t0 := _clock
	while Game.state != &"play" and _clock - t0 < RECOVER_LIMIT and fails.is_empty():
		await _human_step()
	if Game.state != &"play" and fails.is_empty():
		fails.append("soft lock: could not resume from '%s' (last event: %s). %s" % [Game.state, _last_event, _ui_dump()])


func _ui_dump() -> String:
	var ids: Array = []
	for b: Dictionary in _hud.buttons:
		ids.append("%s@%s" % [b["id"], str((b["rect"] as Rect2).get_center().round())])
	return "UI: viewport %s, buttons %s, test menu open %s, vendor open %s, interior active %s busy %s, cards %d, screen_age %.1f, chapters_open %s, shop_open %s, mouse_mode %d" % [_vp(), ids,
			_tm != null and _tm.is_open, InteriorGameplay.vendor_open, InteriorGameplay.active, _ig != null and _ig.busy, Game.story.cards.size() if Game.story != null else -1, _hud.screen_age,
			_hud.get("_chapters_open"), _hud.get("_shop_open"), Input.mouse_mode]


# --- the verdict ------------------------------------------------------------------------------------------------------------

func _finish() -> void:
	_let_go()
	_tree.root.size = _old_size if _old_size != Vector2i.ZERO else _tree.root.size
	await _tick()
	var stab := Lib.find_node_of("Stability")
	var repairs: Array = stab.get("repairs") if stab != null else []
	TestMode.reset_toggles()
	if _settings_path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
	var new_errors := _tap.total
	if new_errors > 0:
		fails.append("%d new error(s) in the error log" % new_errors)
	var verdict := "PASS" if fails.is_empty() else "FAIL"
	report = {"verdict": verdict, "minutes": _clock / 60.0, "events": _events, "errors": new_errors, "fails": fails, "counts": counts, "repairs": repairs.size()}
	_log("MONKEY events: %d  counts: %s" % [_events, str(counts)])
	_log("MONKEY seconds per state: %s" % str(_state_seen))
	_log("MONKEY stability repairs: %d %s" % [repairs.size(), str(repairs.slice(0, 6))])
	if new_errors > 0:
		for l in _tap.snapshot():
			printerr("MONKEY error log: ", l)
	if _tap.noise > 0:
		_log("MONKEY note: %d headless dummy-renderer error(s) ignored (HEADLESS_NOISE in tests/soak_lib.gd, docs/QA.md)" % _tap.noise)
	OS.remove_logger(_tap)
	for f in fails:
		printerr("MONKEY FAIL: ", f)
	print("MONKEY RESULT verdict=%s minutes=%.1f events=%d probes=%d errors=%d seed=%d renderer=%s" % [verdict, _clock / 60.0, _events, int(counts.get("probes", 0)), new_errors, seed_value,
			"software" if Lib.renders() else "headless"])
	Engine.time_scale = _old_scale
	Engine.physics_ticks_per_second = _old_ticks
	Sfx.muted = _old_muted
	finished = true
	if quit_on_finish:
		_tree.quit(0 if verdict == "PASS" else 1)
