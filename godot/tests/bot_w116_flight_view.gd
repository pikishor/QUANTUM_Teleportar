extends RefCounted
## Wave 116 flight view: the real game, the real chase camera, the phone HUD, REAL FINGERS (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, window
## coordinates), reward cards ON (CrateReveal._quiet = 0). It flies, boosts, hovers, turns, swings and zips, and at every `shot` it FREEZES the game (tree pause + time scale 0)
## and renders the same instant several times, each time with one more overlay layer hidden: the pixels that change are that layer's pixels. Printed per shot:
##   FV COVER <label> wings=..% lines=..% rain=..% fx=..% card=..% (share of the CENTRAL 60 % x 60 % of the frame)  cross=..% (share of the disc of 8 % of the height round the crosshair)  hud=..%
## and FV VERDICT <label> PASS / FAIL against LIMIT_CENTRE and LIMIT_CROSS for the in-air layers (wings + lines + rain + fx + card). The frame with everything on is saved as <FV_OUT>/<label>.png.
## Run (see tools/flight_view.sh):  FV_OUT=/dir BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 tools/bot.sh res://tests/bot_w116_flight_view.gd /tmp/x/seq 100000 1
## FV_OLD=1 switches the old look back on (FlightView.old_look: the wide wings, the full-size speed lines, the full-screen reward card) for the before frames.

const LIMIT_CENTRE := 4.0            ## per cent of the central 60 % x 60 % that the in-air overlays may cover in any shot
const LIMIT_CROSS := 0.5             ## per cent of the crosshair disc
const DIFF := 10                     ## a pixel belongs to a layer when a colour channel changes by more than this (0..255) when the layer is hidden

var _out := ""
var _p: Player
var _tc: TouchControls
var _root: Window
var _setup_done := false
var _warm := 0.0
var _t := 0.0
var _plan: Array = []
var _pi := 0
var _scenes: Array[String] = []
var _si := -1
var _fingers := {}                   ## finger index -> canvas position
var _drags: Array = []               ## running drags: [finger, from, to, t0, dur]
var _cap := -1                       ## capture stage (-1: none)
var _cap_wait := 0
var _cap_label := ""
var _cap_imgs: Array[Image] = []
var _cap_restore: Array[Callable] = []
var _fails := 0
var _shots := 0
var _render_on := true
var _log_t := 0.0
var _step_t := 0.0
var _wait_t := 0.0
var _cond_done := false


func _init() -> void:
	_out = OS.get_environment("FV_OUT")
	for n in (OS.get_environment("FV_SCENES") if OS.get_environment("FV_SCENES") != "" else "fly,swing,zip,rain").split(",", false):
		_scenes.append(n)


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_root = _p.get_tree().root
	_root.get_node("Dev").process_mode = Node.PROCESS_MODE_ALWAYS          # the bot keeps stepping while the tree is frozen for a capture
	for n in _root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	var tcs := _root.find_children("*", "TouchControls", true, false)
	_tc = tcs[0] as TouchControls if not tcs.is_empty() else null
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	if Encounters.current != null:
		Encounters.current.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	CrateReveal._quiet = 0                                              # as on a phone: reward cards are allowed
	if OS.get_environment("FV_OLD") == "1":
		FlightView.old_look = true
	var city := Game.world as City
	if city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(float(OS.get_environment("FV_HOUR")) if OS.get_environment("FV_HOUR") != "" else 13.0)
	_weather(0.0)
	DirAccess.make_dir_recursive_absolute(_out)
	print("FV setup touch ", Game.force_touch, " controls ", _tc != null and _tc.controls_on, " quality ", Game.quality, " old ", FlightView.old_look, " canvas ", _root.get_visible_rect().size)


func _weather(rain: float) -> void:
	var at := Game.atmosphere as Atmosphere
	if at == null:
		return
	if at.weather != null:
		at.weather.set_process(false)                                    # the weather machine would change it again
	at.set_weather(rain, 0.3 + 0.6 * rain, true)


# --- fingers --------------------------------------------------------------------------------------------------------------------------------

func _send(e: InputEvent) -> void:
	Input.parse_input_event(e)


func _down(finger: int, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.position = _root.get_final_transform() * pos
	e.pressed = true
	_fingers[finger] = pos
	_send(e)


func _up(finger: int) -> void:
	if not _fingers.has(finger):
		return
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.position = _root.get_final_transform() * (_fingers[finger] as Vector2)
	e.pressed = false
	_fingers.erase(finger)
	_send(e)


func _move(finger: int, to: Vector2) -> void:
	if not _fingers.has(finger):
		return
	var from: Vector2 = _fingers[finger]
	var e := InputEventScreenDrag.new()
	e.index = finger
	e.position = _root.get_final_transform() * to
	e.relative = _root.get_final_transform().basis_xform(to - from)
	_fingers[finger] = to
	_send(e)


## The centre of the visible touch button of `action` (canvas coordinates), or Vector2.INF when it is not on screen.
func _button(action: StringName) -> Vector2:
	if _tc == null:
		return Vector2.INF
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and _tc.button_visible(b):
			return _tc._button_center(b)
	return Vector2.INF


func _vp() -> Vector2:
	return _root.get_visible_rect().size


# --- the plans ------------------------------------------------------------------------------------------------------------------------------

## A plan is a list of steps run in order; `dt` = game seconds to wait after the step before it, `until` = a condition to wait for first (at most `max` seconds).
## acts: tp (pos, yaw, pitch)  btn_down / btn_up (f finger, a action)  stick (v: Vector2 -1..1, y -1 = forward; ZERO lifts the thumb)  look (dx, dy canvas px over `dur` s)
##       shot (label)  card  rain (v)  end
func _takeoff() -> Array:
	return [{"dt": 0.7, "act": "btn_down", "f": 1, "a": &"jump"}, {"dt": 0.12, "act": "btn_up", "f": 1},
		{"until": "fly_btn", "max": 1.0, "act": "btn_down", "f": 1, "a": &"fly"}, {"dt": 0.12, "act": "btn_up", "f": 1},
		{"until": "fly", "max": 0.6, "act": "stick", "v": Vector2(0.0, -0.8)},
		{"dt": 0.2, "act": "btn_down", "f": 1, "a": &"jump"}, {"dt": 1.3, "act": "btn_up", "f": 1}]


func _plan_for(name: String) -> Array:
	match name:
		"fly":
			var pl: Array = [{"dt": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1}]
			pl.append_array(_takeoff())
			pl.append_array([
				{"dt": 1.1, "act": "shot", "label": "fly_cruise"},
				{"dt": 0.1, "act": "btn_down", "f": 1, "a": &"snake"},
				{"dt": 1.6, "act": "shot", "label": "fly_boost"},
				{"dt": 0.1, "act": "btn_up", "f": 1},
				{"dt": 0.1, "act": "look", "dx": 260.0, "dy": 0.0, "dur": 0.9},
				{"dt": 0.7, "act": "shot", "label": "fly_turn"},
				{"dt": 0.9, "act": "stick", "v": Vector2.ZERO},
				{"dt": 2.2, "act": "shot", "label": "fly_hover"},
				{"dt": 0.1, "act": "card"},
				{"dt": 0.9, "act": "shot", "label": "fly_card"},
				{"dt": 2.8, "act": "stick", "v": Vector2(0.0, -0.8)},
				{"dt": 0.1, "act": "look", "dx": 0.0, "dy": 110.0, "dur": 0.5},
				{"dt": 1.2, "act": "shot", "label": "fly_dive"},
				{"dt": 0.1, "act": "look", "dx": 0.0, "dy": -110.0, "dur": 0.4},
				{"dt": 0.7, "act": "stick", "v": Vector2.ZERO},
				{"dt": 0.2, "act": "btn_down", "f": 1, "a": &"fly"}, {"dt": 0.12, "act": "btn_up", "f": 1},
				{"until": "none", "max": 9.0, "act": "end"}])
			return pl
		"swing":
			return [{"dt": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.2},
				{"dt": 0.7, "act": "btn_down", "f": 1, "a": &"jump"}, {"dt": 0.12, "act": "btn_up", "f": 1},
				{"dt": 0.25, "act": "btn_down", "f": 1, "a": &"snake"},
				{"dt": 1.0, "act": "shot", "label": "swing_a"},
				{"dt": 1.4, "act": "shot", "label": "swing_b"},
				{"dt": 2.2, "act": "shot", "label": "swing_c"},
				{"dt": 1.3, "act": "btn_up", "f": 1},
				{"dt": 2.5, "act": "end"}]
		"zip":
			return [{"dt": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": PI, "pitch": 0.38},
				{"dt": 0.9, "act": "btn_down", "f": 1, "a": &"snake"}, {"dt": 0.12, "act": "btn_up", "f": 1},
				{"dt": 0.2, "act": "shot", "label": "zip_a"},
				{"dt": 0.25, "act": "shot", "label": "zip_b"},
				{"dt": 2.0, "act": "end"}]
		"rain":
			var pr: Array = [{"dt": 0.05, "act": "rain", "v": 1.0}, {"dt": 0.05, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1}]
			pr.append_array(_takeoff())
			pr.append_array([
				{"dt": 1.1, "act": "shot", "label": "rain_cruise"},
				{"dt": 0.1, "act": "btn_down", "f": 1, "a": &"snake"},
				{"dt": 1.5, "act": "shot", "label": "rain_boost"},
				{"dt": 0.1, "act": "btn_up", "f": 1},
				{"dt": 0.1, "act": "stick", "v": Vector2.ZERO},
				{"dt": 0.2, "act": "btn_down", "f": 1, "a": &"fly"}, {"dt": 0.12, "act": "btn_up", "f": 1},
				{"until": "none", "max": 9.0, "act": "rain", "v": 0.0},
				{"dt": 0.1, "act": "end"}])
			return pr
	return [{"dt": 0.1, "act": "end"}]


func _cond(c: String) -> bool:
	var sn := _p.snake
	match c:
		"fly_btn": return _button(&"fly") != Vector2.INF
		"fly": return sn.mode == SnakeTraversal.Mode.FLY
		"none": return sn.mode == SnakeTraversal.Mode.NONE and _p.is_on_floor()
		"swing": return sn.mode == SnakeTraversal.Mode.SWING
	return true


func _render(on: bool) -> void:
	if on != _render_on:
		RenderingServer.render_loop_enabled = on
		_render_on = on


func step(_tt: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null or Game.world == null:
		return false
	if not _setup_done:
		if _tt < 2.0:
			return false
		_setup()
		return false
	if _cap >= 0:
		_capture_step()
		return false
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 2.5:
		_warm += delta
		_render(false)
		return false
	if _si < 0 or _pi >= _plan.size():
		_si += 1
		if _si >= _scenes.size():
			_render(true)
			print("FV DONE shots %d  fails %d" % [_shots, _fails])
			_p.get_tree().quit()
			return true
		for f in _fingers.keys():
			_up(f)
		_drags.clear()
		if _p.snake != null:
			_p.snake.cancel()
		_plan = _plan_for(_scenes[_si])
		_pi = 0
		_t = 0.0
		_step_t = 0.0
		_wait_t = 0.0
		_cond_done = false
		_log_t = 0.0
		print("FV SCENE ", _scenes[_si])
		return false
	_t += delta
	# running drags
	var i := _drags.size() - 1
	while i >= 0:
		var d: Array = _drags[i]
		var k := clampf((_t - float(d[3])) / maxf(float(d[4]), 0.01), 0.0, 1.0)
		_move(int(d[0]), (d[1] as Vector2).lerp(d[2] as Vector2, k))
		if k >= 1.0:
			if bool(d[5]):
				_up(int(d[0]))
			_drags.remove_at(i)
		i -= 1
	var sn := _p.snake
	if _t >= _log_t:
		_log_t += 0.5
		print("FV t %.1f mode %s phase %s pos %s v %.1f e %.0f lines %.2f label %s fly_btn %s" % [_t, sn.mode_name(), sn.flight.phase, _p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), _p.velocity.length(), sn.energy, sn.cam.speed_lines, sn.button_label(), _button(&"fly") != Vector2.INF])
	# the next step: its condition, then its delay
	var a: Dictionary = _plan[_pi]
	if a.has("until") and not _cond_done:
		_wait_t += delta
		if _cond(a["until"]):
			_cond_done = true
		elif _wait_t >= float(a.get("max", 2.0)):
			print("FV CONDITION NOT MET %s after %.1f s (%s phase %s pos %s)" % [a["until"], _wait_t, sn.mode_name(), sn.flight.phase, _p.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
			_cond_done = true
		if not _cond_done:
			return false
		_step_t = 0.0
	var due := float(a.get("dt", 0.0))
	_render(a["act"] == "shot" and due - _step_t < 0.12)
	_step_t += delta
	if _step_t < due:
		return false
	_pi += 1
	_step_t = 0.0
	_wait_t = 0.0
	_cond_done = false
	match a["act"]:
		"tp":
			_p.teleport_to(a["pos"])
			_p.camera_rig.reset_view(a["yaw"], a["pitch"])
			_p.yaw = a["yaw"]
			_p.velocity = Vector3.ZERO
			sn.energy = SnakePower.max_energy()
		"btn_down":
			var at := _button(a["a"])
			if at == Vector2.INF:
				print("FV BUTTON MISSING ", a["a"], " at t ", _t, " mode ", sn.mode_name())
			else:
				_down(int(a["f"]), at)
		"btn_up":
			_up(int(a["f"]))
		"stick":
			var v: Vector2 = a["v"]
			if v == Vector2.ZERO:
				_up(0)
			else:
				var o := Vector2(_vp().x * 0.14, _vp().y * 0.72)
				if not _fingers.has(0):
					_down(0, o)
				_drags.append([0, _fingers[0], o + v * TouchControls.STICK_RADIUS * _tc._scale(), _t, 0.15, false])
		"look":
			var lo := Vector2(_vp().x * 0.5, _vp().y * 0.32)
			_down(3, lo)
			_drags.append([3, lo, lo + Vector2(float(a["dx"]), float(a["dy"])), _t, float(a["dur"]), true])
		"card":
			CrateReveal.request(WeaponDefs.IDS[5], "MISSION REWARD", true)
		"rain":
			_weather(float(a["v"]))
		"shot":
			_begin_capture(a["label"])
		"end":
			for f in _fingers.keys():
				_up(f)
			_pi = _plan.size()
	return false


# --- the frozen capture ------------------------------------------------------------------------------------------------------------------------

func _begin_capture(label: String) -> void:
	_cap_label = label
	_cap = 0
	_cap_wait = 2
	_cap_imgs.clear()
	_cap_restore.clear()
	_render(true)
	if CrateReveal.is_showing():
		CrateReveal.current.set_process(false)                           # (the card closes itself under a tree pause: it keeps its last picture instead)
	Engine.time_scale = 0.0
	_p.get_tree().paused = true


func _hide(n: Variant) -> void:
	if n == null or not is_instance_valid(n) or not bool((n as Object).get("visible")):
		return
	(n as Object).set("visible", false)
	_cap_restore.append(func() -> void:
		if is_instance_valid(n):
			(n as Object).set("visible", true))


## stage k: grab the picture, then hide layer k
func _capture_step() -> void:
	_cap_wait -= 1
	if _cap_wait > 0:
		return
	_cap_imgs.append(_root.get_texture().get_image())
	match _cap:
		0:
			_hide(SnakeTendrilPool.current)
		1:
			var fx := _p.get_node_or_null("SnakeFx")
			_hide(fx.get_node_or_null("SpeedLines") if fx != null else null)
		2:
			var at := Game.atmosphere as Atmosphere
			if at != null:
				_hide(at.rainfield)
				if at.post != null and at.rain_now > 0.0:
					at.post.set_rain(0.0)
					_cap_restore.append(func() -> void: at.post.set_rain(at.rain_now))
		3:
			for c in FX.get_children():
				if c is Node3D or c is CanvasItem or c is CanvasLayer:
					_hide(c)
		4:
			_hide(CrateReveal.current if CrateReveal.is_showing() else null)
		5:
			for h in _root.find_children("*", "Hud", true, false):
				_hide(h)
		_:
			_finish_capture()
			return
	_cap += 1
	_cap_wait = 2


func _finish_capture() -> void:
	for c in _cap_restore:
		c.call()
	_cap_restore.clear()
	if CrateReveal.is_showing():
		CrateReveal.current.set_process(true)
	_p.get_tree().paused = false
	Engine.time_scale = 1.0
	_cap = -1
	_shots += 1
	var names := ["wings", "lines", "rain", "fx", "card", "hud"]
	var full := _cap_imgs[0]
	full.save_png("%s/%s.png" % [_out, _cap_label])
	_cap_imgs[_cap_imgs.size() - 1].save_png("%s/%s_bare.png" % [_out, _cap_label])
	var w := full.get_width()
	var h := full.get_height()
	var datas: Array[PackedByteArray] = []
	for im in _cap_imgs:
		im.convert(Image.FORMAT_RGB8)
		datas.append(im.get_data())
	var x0 := int(w * 0.2)
	var x1 := int(w * 0.8)
	var y0 := int(h * 0.2)
	var y1 := int(h * 0.8)
	var cx := w * 0.5
	var cy := h * 0.5
	var cr := h * 0.08
	var centre := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var cross := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var centre_n := 0
	var cross_n := 0
	var mask := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	var cols := [Color(0.2, 0.9, 1.0), Color(1.0, 1.0, 0.3), Color(0.6, 0.6, 1.0), Color(1.0, 0.5, 0.2), Color(1.0, 0.3, 0.9), Color(0.25, 0.25, 0.25)]
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var o := (y * w + x) * 3
			var in_c := x >= x0 and x < x1 and y >= y0 and y < y1
			var in_x := (x - cx) * (x - cx) + (y - cy) * (y - cy) <= cr * cr
			if in_c:
				centre_n += 1
			if in_x:
				cross_n += 1
			for k in 6:
				var a := datas[k]
				var b := datas[k + 1]
				if absi(a[o] - b[o]) > DIFF or absi(a[o + 1] - b[o + 1]) > DIFF or absi(a[o + 2] - b[o + 2]) > DIFF:
					if in_c:
						centre[k] += 1
					if in_x:
						cross[k] += 1
					mask.set_pixel(x, y, cols[k])
					mask.set_pixel(x + 1 if x + 1 < w else x, y, cols[k])
					break
	mask.save_png("%s/%s_mask.png" % [_out, _cap_label])
	var parts: PackedStringArray = []
	var air_c := 0
	var air_x := 0
	for k in 6:
		parts.append("%s=%.2f%%" % [names[k], 100.0 * float(centre[k]) / maxf(centre_n, 1)])
		if k < 5:
			air_c += centre[k]
			air_x += cross[k]
	var pc := 100.0 * float(air_c) / maxf(centre_n, 1)
	var px := 100.0 * float(air_x) / maxf(cross_n, 1)
	var sn := _p.snake
	print("FV COVER %s %s  air_total=%.2f%%  cross=%.2f%%  (mode %s phase %s v %.1f lines %.2f spread %.2f)" % [_cap_label, " ".join(parts), pc, px, sn.mode_name(), sn.flight.phase, _p.velocity.length(), sn.cam.speed_lines, sn.flight.wing_spread])
	var ok := pc <= LIMIT_CENTRE and px <= LIMIT_CROSS
	if not ok:
		_fails += 1
	print("FV VERDICT %s %s  centre %.2f%% (limit %.1f)  crosshair %.2f%% (limit %.1f)" % [_cap_label, "PASS" if ok else "FAIL", pc, LIMIT_CENTRE, px, LIMIT_CROSS])
	_cap_imgs.clear()
