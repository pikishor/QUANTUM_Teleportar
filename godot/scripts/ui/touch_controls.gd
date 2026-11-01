class_name TouchControls
extends CanvasLayer
## On-screen controls for phones (shown on touchscreens, or with --touch): a floating move stick (full push = sprint), a look drag (also from the FIRE
## finger), buttons FIRE / AIM / JUMP / RELOAD, the quantum powers BLINK / LINK / SUPER and USE (each only when its module exists), a pause button and a
## perf readout (FPS, draws, tris, texture memory; tap it to cycle the graphics tier). It only presses the input actions the keyboard drives and calls
## CameraRig.add_look, so the Player needs no changes. The HUD (scripts/ui/hud.gd) owns everything else on screen and instances this node as a child.

signal pause_requested

const LOOK_SENS := 0.003            ## radians per canvas pixel of finger travel
const STICK_RADIUS := 100.0         ## canvas px at the 720 px base height
const STICK_DEAD := 0.12
const SPRINT_AT := 0.94             ## pushing the stick this far means sprint
const BASE_H := 720.0
const USE_REACH := 4.2              ## metres: a vehicle this close enables USE
## Buttons: action, centre offset from the bottom-right corner and radius (canvas px at the base height), label, and what they need to be shown.
const BUTTONS := [
	{"action": &"fire", "dx": 160.0, "dy": 170.0, "r": 88.0, "fs": 28, "label": "FIRE", "need": &""},
	{"action": &"aim", "dx": 170.0, "dy": 345.0, "r": 60.0, "label": "AIM", "need": &""},
	{"action": &"jump", "dx": 345.0, "dy": 130.0, "r": 66.0, "label": "JUMP", "need": &""},
	{"action": &"reload", "dx": 360.0, "dy": 295.0, "r": 52.0, "fs": 20, "label": "RELOAD", "need": &""},
	{"action": &"swap", "dx": 345.0, "dy": 440.0, "r": 46.0, "fs": 22, "label": "SWAP", "need": &""},
	{"action": &"blink", "dx": 515.0, "dy": 110.0, "r": 56.0, "label": "BLINK", "need": &"quantum", "ability": 0},
	{"action": &"entangle", "dx": 530.0, "dy": 228.0, "r": 52.0, "label": "LINK", "need": &"quantum", "ability": 1},
	{"action": &"superpose", "dx": 500.0, "dy": 340.0, "r": 52.0, "label": "SUPER", "need": &"quantum", "ability": 2},
	{"action": &"interact", "dx": 175.0, "dy": 480.0, "r": 54.0, "label": "USE", "need": &"vehicle"},
]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]
const TIER_NAMES: Array[String] = ["LOW", "MED", "HIGH"]
const LONG_PRESS := 0.6             ## seconds: holding the FPS box this long toggles the error panel (a short tap cycles the graphics tier)
const ERROR_ROWS := 9               ## newest error lines shown in the panel

var controls_on := false            ## the touch controls are drawn and active
var perf_on := false                ## the perf readout is drawn (always with the controls, or with --perf)
var errors_on := false              ## the on-device error panel is shown (long-press the FPS box)

var _canvas: Control
var _last_state: StringName = &""
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_id := -1
var _held := {}                     ## finger index -> button dictionary
var _perf_text := ""
var _perf_t := 0.0
var _win_t := 0.0
var _win_n := 0
var _win_worst := 0.0
var _avg_fps := 0.0
var _min_fps := 0.0
var _use_near := false
var _use_t := 0.0
var _perf_finger := -1              ## the finger held on the FPS box, or -1
var _perf_held := 0.0
var _perf_long := false             ## the current press already toggled the panel (so its release does not cycle the tier)


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	controls_on = Game.force_touch or DisplayServer.is_touchscreen_available()
	perf_on = controls_on or OS.get_cmdline_user_args().has("--perf")
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_ui)
	Game.state_changed.connect(func(_s: StringName) -> void: release_all())
	set_process(controls_on or perf_on)


## A held finger never survives losing the app (no touch-up event comes): everything is let go when the app is paused or loses focus.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _exit_tree() -> void:
	release_all()


func _process(delta: float) -> void:
	if _perf_finger != -1 and not _perf_long:
		_perf_held += delta / maxf(Engine.time_scale, 0.05)
		if _perf_held >= LONG_PRESS:
			_perf_long = true
			var menu := get_tree().get_first_node_in_group(&"test_menu") if TestMode.available() else null
			if menu != null:
				menu.call(&"open")                       # test mode: the TEST MENU (it has the error panel switch); a release build keeps the error panel
			else:
				errors_on = not errors_on
			_canvas.queue_redraw()
	_win_t += delta
	_win_n += 1
	_win_worst = maxf(_win_worst, delta)
	if _win_t >= 1.0:
		_avg_fps = _win_n / _win_t
		_min_fps = 1.0 / maxf(_win_worst, 0.0001)
		_win_t = 0.0
		_win_n = 0
		_win_worst = 0.0
	_perf_t -= delta
	if _perf_t <= 0.0:
		_perf_t = 0.5
		_refresh_perf()
	_use_t -= delta
	if _use_t <= 0.0:
		_use_t = 0.15
		_use_near = _vehicle_in_reach()
	if Game.state == &"play" or Game.state == &"paused" or _last_state == &"play" or _last_state == &"paused":
		_canvas.queue_redraw()      # one extra redraw after leaving play, so the dead screen does not keep the dimmed buttons
	_last_state = Game.state


## Lets go of every action this layer pressed (state changes, exit, tests).
func release_all() -> void:
	for a: StringName in MOVE_ACTIONS:
		Input.action_release(a)
	for b: Dictionary in BUTTONS:
		Input.action_release(b["action"])
	_held.clear()
	_stick_id = -1
	_look_id = -1
	_perf_finger = -1
	_perf_long = false


# ---------------------------------------------------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not controls_on and not perf_on:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			touch_down(t.index, t.position)
		else:
			touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		touch_move(d.index, d.position, d.relative)


func touch_down(id: int, pos: Vector2) -> void:
	if perf_visible() and _perf_box().has_point(pos):
		_perf_finger = id                               # decided on release: a tap cycles the tier, a long press toggles the error panel
		_perf_held = 0.0
		_perf_long = false
		return
	if not controls_on or not Game.is_playing():
		return
	if pos.distance_to(_pause_center()) <= 30.0 * _scale() * 1.3:
		pause_requested.emit()
		return
	for b: Dictionary in BUTTONS:
		if button_visible(b) and pos.distance_to(_button_center(b)) <= float(b["r"]) * _scale() * 1.15:
			_held[id] = b
			Input.action_press(b["action"])
			if b["action"] == &"interact":
				Sfx.play(&"ui_tap")                                    # USE (enter / exit a car) answers with a soft tap
			return
	if pos.x < _vp_size().x * 0.42 and _stick_id == -1:
		_stick_id = id
		_stick_origin = pos
		_stick_pos = pos
	elif _look_id == -1:
		_look_id = id


func touch_move(id: int, pos: Vector2, rel: Vector2) -> void:
	if id == _stick_id:
		_stick_pos = pos
		_apply_stick()
	elif id == _look_id or (_held.has(id) and (_held[id] as Dictionary)["action"] == &"fire"):
		_look(rel)


func touch_up(id: int) -> void:
	if id == _perf_finger:
		_perf_finger = -1
		if not _perf_long:
			Game.set_quality((Game.quality + 1) % 3)
			_perf_t = 0.0
		_perf_long = false
		return
	if id == _stick_id:
		_stick_id = -1
		_stick_pos = _stick_origin
		_apply_stick()
	if id == _look_id:
		_look_id = -1
	if _held.has(id):
		Input.action_release((_held[id] as Dictionary)["action"])
		_held.erase(id)


func _apply_stick() -> void:
	var radius := STICK_RADIUS * _scale()
	var raw := _stick_pos - _stick_origin
	if raw.length() > radius:                       # a floating stick: the origin follows a finger that goes past the rim
		_stick_origin += raw.normalized() * (raw.length() - radius)
		raw = _stick_pos - _stick_origin
	var v := raw / radius
	if v.length() < STICK_DEAD:
		v = Vector2.ZERO
	_press(&"move_right", maxf(v.x, 0.0))
	_press(&"move_left", maxf(-v.x, 0.0))
	_press(&"move_back", maxf(v.y, 0.0))
	_press(&"move_forward", maxf(-v.y, 0.0))
	_press(&"sprint", 1.0 if v.length() >= SPRINT_AT else 0.0)


func _press(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _look(rel: Vector2) -> void:
	var p: Node = Game.player
	if not is_instance_valid(p) or not Game.is_playing():
		return
	var rig: Object = p.get("camera_rig")
	if rig != null and rig.has_method("add_look"):
		rig.call("add_look", rel.x * LOOK_SENS, rel.y * LOOK_SENS)


# ---------------------------------------------------------------------------------------------------------------------
# which buttons exist
# ---------------------------------------------------------------------------------------------------------------------

## A button is shown only when what it needs exists: the quantum powers need `player.quantum`, USE needs the vehicle module and a car in reach (or being in one).
func button_visible(b: Dictionary) -> bool:
	match b["need"]:
		&"quantum":
			return is_instance_valid(Game.player) and Game.player.get("quantum") != null
		&"vehicle":
			return is_instance_valid(Game.vehicles) and (_use_near or _driving())
	return true


func _driving() -> bool:
	return is_instance_valid(Game.player) and Game.player.get("vehicle") != null


func _vehicle_in_reach() -> bool:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player) or not Game.vehicles.has_method(&"nearest"):
		return false
	return Game.vehicles.call(&"nearest", Game.player.global_position, USE_REACH) != null


# ---------------------------------------------------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------------------------------------------------

func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _scale() -> float:
	return UiUtil.ui_scale(_vp_size())


func _insets() -> Vector2:
	return UiUtil.insets(_vp_size())


func _button_center(b: Dictionary) -> Vector2:
	var s := _scale()
	return Vector2(_vp_size().x - _insets().y - float(b["dx"]) * s, _vp_size().y - UiUtil.insets_v(_vp_size()).y - float(b["dy"]) * s)


func _pause_center() -> Vector2:
	var s := _scale()
	return Vector2(_vp_size().x - _insets().y - 50.0 * s, 128.0 * s + UiUtil.insets_v(_vp_size()).x)


## The perf readout sits under the minimap and is only shown while playing or paused.
func perf_visible() -> bool:
	return perf_on and (Game.state == &"play" or Game.state == &"paused")


func _perf_box() -> Rect2:
	var s := _scale()
	return Rect2(Vector2(16.0 * s + _insets().x, 168.0 * s + UiUtil.insets_v(_vp_size()).x), Vector2(300.0, 70.0) * s)


func _refresh_perf() -> void:
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var tex_mb := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576
	_perf_text = "FPS %d  (avg %d  worst %d)\nDraws %d   Tris %dk   Tex %d MB\nTier %s - tap to change" % [
		roundi(Engine.get_frames_per_second()), roundi(_avg_fps), roundi(_min_fps), draws, prims / 1000, tex_mb, TIER_NAMES[clampi(Game.quality, 0, 2)]]


# ---------------------------------------------------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------------------------------------------------

func _draw_ui() -> void:
	var c := _canvas
	var size := _vp_size()
	var s := _scale()
	var font := UiUtil.font()
	if perf_visible():
		var box := _perf_box()
		c.draw_rect(box, Color(0, 0.03, 0.05, 0.6))
		c.draw_multiline_string(font, box.position + Vector2(8, 20) * s, _perf_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15 * s), -1, Color(0.85, 1, 0.9, 0.95))
	if perf_visible() and errors_on:
		_draw_errors(c, font, s)
	if not controls_on or Game.state != &"play":
		return
	# move stick: a hint ring while idle, base and thumb while a finger is down
	if _stick_id == -1:
		c.draw_arc(Vector2(190 * s + _insets().x, size.y - 170 * s - UiUtil.insets_v(size).y), STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.16), 2.0 * s, false)
	else:
		c.draw_circle(_stick_origin, STICK_RADIUS * s, Color(1, 1, 1, 0.07))
		c.draw_arc(_stick_origin, STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * s, false)
		c.draw_circle(_stick_pos.limit_length(1e5), 38.0 * s, Color(0.5, 0.95, 1, 0.5))
	var labels: Array = []   # text is drawn after all shapes: glyph and plain draws alternating would break canvas batching
	var sprites: Array = []  # every button is ONE sprite (dark disc + bright rim): draw_circle + draw_arc per button cost two draw calls each, sprites of one texture batch
	var arcs: Array = []
	var glows: Array = []
	var down: Array = []
	for b: Dictionary in _held.values():
		down.append(b["action"])
	for b: Dictionary in BUTTONS:
		if not button_visible(b):
			continue
		var centre := _button_center(b)
		var r := float(b["r"]) * s
		var on := down.has(b["action"])
		var tint := UiUtil.CYAN
		var dim := 1.0
		if b.has("ability"):
			var st := UiUtil.ability_state(Game.player, UiUtil.ABILITIES[int(b["ability"])])
			if st["active"]:
				tint = UiUtil.AMBER
			elif not st["ready"]:
				dim = 0.45
			if float(st["cd"]) > 0.0:
				arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * float(st["cd"]), Color(tint, 0.9)])
		if on:
			glows.append([Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), Color(tint, 0.35)])
		sprites.append([Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), Color(tint, (1.0 if on else 0.85) * dim)])
		var fs := int(b.get("fs", 22))
		labels.append([centre + Vector2(-r, float(fs) * 0.36 * s), str(b["label"]), r * 2.0, dim, fs])
	for g: Array in glows:
		c.draw_texture_rect(UiUtil.sprite(&"disc"), g[0], false, g[1])
	for sp: Array in sprites:
		c.draw_texture_rect(UiUtil.sprite(&"button"), sp[0], false, sp[1])
	for a: Array in arcs:
		c.draw_arc(a[0], a[1], -PI * 0.5, a[2], 32, a[3], 3.0 * s, false)
	var sizes := {}
	for l: Array in labels:
		sizes[l[4]] = true
	for fsz: int in sizes.keys():                       # shadows, then text, one size at a time (glyph atlases are per size)
		for l: Array in labels:
			if l[4] == fsz:
				c.draw_string(font, (l[0] as Vector2) + Vector2(1.5, 1.5) * s, l[1], HORIZONTAL_ALIGNMENT_CENTER, l[2], int(float(fsz) * s), Color(0, 0, 0, 0.8 * float(l[3])))
		for l: Array in labels:
			if l[4] == fsz:
				c.draw_string(font, l[0], l[1], HORIZONTAL_ALIGNMENT_CENTER, l[2], int(float(fsz) * s), Color(1, 1, 1, 0.97 * float(l[3])))
	# pause
	var pc := _pause_center()
	var pr := 30.0 * s
	c.draw_arc(pc, pr, 0.0, TAU, 28, Color(1, 1, 1, 0.45), 2.0 * s, false)
	c.draw_rect(Rect2(pc + Vector2(-8, -10) * s, Vector2(5, 20) * s), Color(1, 1, 1, 0.8))
	c.draw_rect(Rect2(pc + Vector2(3, -10) * s, Vector2(5, 20) * s), Color(1, 1, 1, 0.8))


## The on-device error log (Dev.errors, also in user://last_errors.txt): the newest lines, small, under the perf readout.
func _draw_errors(c: Control, font: Font, s: float) -> void:
	var lines: PackedStringArray = Dev.error_lines()
	var box := _perf_box()
	var vp := _vp_size()
	var rect := Rect2(Vector2(box.position.x, box.end.y + 6.0 * s), Vector2(minf(vp.x - box.position.x - 12.0 * s, 620.0 * s), (ERROR_ROWS * 15.0 + 22.0) * s))
	c.draw_rect(rect, Color(0.05, 0.0, 0.0, 0.62))
	c.draw_rect(rect, Color(1.0, 0.35, 0.3, 0.6), false, 1.0 * s)
	var head := "ERRORS %d  (long-press FPS to hide, file: last_errors.txt)" % Dev.errors.total
	c.draw_string(font, rect.position + Vector2(6.0, 14.0) * s, head, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0 * s, int(11.0 * s), Color(1.0, 0.7, 0.6, 0.95))
	if lines.is_empty():
		c.draw_string(font, rect.position + Vector2(6.0, 32.0) * s, "no errors", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(11.0 * s), Color(0.6, 1.0, 0.7, 0.9))
		return
	var first := maxi(0, lines.size() - ERROR_ROWS)
	for i in range(first, lines.size()):
		c.draw_string(font, rect.position + Vector2(6.0, 30.0 + (i - first) * 15.0) * s, lines[i], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0 * s, int(10.0 * s), Color(1, 0.92, 0.88, 0.92))
