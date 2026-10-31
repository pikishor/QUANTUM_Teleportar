class_name TouchControls
extends CanvasLayer
## On-screen controls and a light HUD for phones (shown on touchscreens, or with --touch): a floating move stick, a look drag, FIRE / AIM / JUMP /
## RELOAD buttons, crosshair, health and ammo, and a perf readout (tap it to cycle the graphics tier LOW / MED / HIGH).
## It only presses the input actions the keyboard already drives, so the Player needs no changes. This is a stop-gap owned by the orchestrator:
## the HUD module of wave 2 takes over the layout and keeps this input mapping (see ARCHITECTURE.md, hud / ui).

const LOOK_SENS := 0.003            ## radians per canvas pixel of finger travel
const STICK_RADIUS := 100.0         ## canvas px at the 720 px base height
const STICK_DEAD := 0.12
const SPRINT_AT := 0.94             ## pushing the stick this far means sprint
const BASE_H := 720.0
## Buttons: action, centre offset from the bottom-right corner and radius (canvas px at the base height), label.
const BUTTONS := [
	{"action": &"fire", "dx": 160.0, "dy": 170.0, "r": 84.0, "label": "FIRE"},
	{"action": &"aim", "dx": 170.0, "dy": 340.0, "r": 58.0, "label": "AIM"},
	{"action": &"jump", "dx": 345.0, "dy": 130.0, "r": 60.0, "label": "JUMP"},
	{"action": &"reload", "dx": 360.0, "dy": 290.0, "r": 46.0, "label": "R"},
]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]
const TIER_NAMES: Array[String] = ["LOW", "MED", "HIGH"]

var controls_on := false            ## the touch controls and HUD are drawn and active
var perf_on := false                ## the perf readout is drawn (always with the controls, or with --perf)

var _canvas: Control
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


func _ready() -> void:
	layer = 10
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


func _exit_tree() -> void:
	release_all()


func _process(delta: float) -> void:
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
	_canvas.queue_redraw()


## Lets go of every action this layer pressed (state changes, exit, tests).
func release_all() -> void:
	for a: StringName in MOVE_ACTIONS:
		Input.action_release(a)
	for b: Dictionary in BUTTONS:
		Input.action_release(b["action"])
	_held.clear()
	_stick_id = -1
	_look_id = -1


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
	if perf_on and _perf_box().has_point(pos):
		Game.set_quality((Game.quality + 1) % 3)
		_perf_t = 0.0
		return
	if not controls_on:
		return
	if Game.state == &"dead":
		Game.do_respawn()
		return
	if not Game.is_playing():
		return
	for b: Dictionary in BUTTONS:
		if pos.distance_to(_button_center(b)) <= float(b["r"]) * _scale() * 1.15:
			_held[id] = b
			Input.action_press(b["action"])
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
# layout
# ---------------------------------------------------------------------------------------------------------------------

func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _scale() -> float:
	return maxf(_vp_size().y / BASE_H, 0.1)


## Notch and rounded-corner insets (left, right) in canvas px.
func _insets() -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return Vector2.ZERO
	var sa := DisplayServer.get_display_safe_area()
	if sa.size.x <= 0:
		return Vector2.ZERO
	var k := _vp_size().x / float(win.x)
	return Vector2(maxf(sa.position.x, 0.0) * k, maxf(float(win.x - sa.end.x), 0.0) * k)


func _button_center(b: Dictionary) -> Vector2:
	var s := _scale()
	return Vector2(_vp_size().x - _insets().y - float(b["dx"]) * s, _vp_size().y - float(b["dy"]) * s)


func _perf_box() -> Rect2:
	var s := _scale()
	return Rect2(Vector2(16.0 * s + _insets().x, 12.0 * s), Vector2(330.0, 92.0) * s)


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
	var font := ThemeDB.fallback_font
	if perf_on:
		var box := _perf_box()
		c.draw_rect(box, Color(0, 0, 0, 0.45))
		c.draw_multiline_string(font, box.position + Vector2(8, 22) * s, _perf_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(17 * s), -1, Color(0.85, 1, 0.9, 0.95))
	if not controls_on:
		return
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	if p != null:
		_draw_hud(c, p, size, s, font)
	if Game.state == &"dead":
		c.draw_string(font, Vector2(0, size.y * 0.5), "DECOHERED  -  TAP TO RESPAWN", HORIZONTAL_ALIGNMENT_CENTER, size.x, int(36 * s), Color(1, 0.45, 0.5, 0.95))
		return
	# move stick: a hint ring while idle, base and thumb while a finger is down
	if _stick_id == -1:
		c.draw_arc(Vector2(190, size.y - 170) * s + Vector2(_insets().x, 0), STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.16), 3.0 * s, true)
	else:
		c.draw_circle(_stick_origin, STICK_RADIUS * s, Color(1, 1, 1, 0.07))
		c.draw_arc(_stick_origin, STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0 * s, true)
		c.draw_circle(_stick_pos.limit_length(1e5), 38.0 * s, Color(0.5, 0.95, 1, 0.5))
	var down: Array = []
	for b: Dictionary in _held.values():
		down.append(b["action"])
	for b: Dictionary in BUTTONS:
		var centre := _button_center(b)
		var r := float(b["r"]) * s
		var on := down.has(b["action"])
		c.draw_circle(centre, r, Color(0.4, 0.9, 1.0, 0.34 if on else 0.14))
		c.draw_arc(centre, r, 0.0, TAU, 40, Color(0.7, 0.97, 1.0, 0.85 if on else 0.45), 3.0 * s, true)
		c.draw_string(font, centre + Vector2(-r, 7.0 * s), str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(22 * s), Color(1, 1, 1, 0.9))


## Reads a numeric property of the player, or `fallback` when it is missing (a stand-in player in tests, a player that is still loading).
func _num(o: Object, prop: StringName, fallback: float) -> float:
	var v: Variant = o.get(prop)
	return float(v) if (v is float or v is int) else fallback


func _draw_hud(c: Control, p: Node, size: Vector2, s: float, font: Font) -> void:
	var hp := _num(p, &"hp", 100.0)
	var max_hp := maxf(_num(p, &"max_hp", 100.0), 1.0)
	var bar := Rect2(Vector2(size.x * 0.5 - 150.0 * s, 16.0 * s), Vector2(300.0, 10.0) * s)
	c.draw_rect(bar, Color(0, 0, 0, 0.5))
	var f := clampf(hp / max_hp, 0.0, 1.0)
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(1.0 - f, 0.3 + 0.7 * f, 0.35, 0.95))
	var ammo_text := "RELOADING" if p.get("reloading") == true else "%d / %d" % [roundi(_num(p, &"ammo", 0.0)), roundi(_num(p, &"mag", 30.0))]
	c.draw_string(font, Vector2(size.x - 240.0 * s - _insets().y, 40.0 * s), ammo_text, HORIZONTAL_ALIGNMENT_RIGHT, 220.0 * s, int(28 * s), Color(1, 1, 1, 0.92))
	# crosshair: the gap is the weapon's current spread
	var mid := size * 0.5
	var spread_px := float(p.call("spread_in_pixels", size.y)) if p.has_method("spread_in_pixels") else 0.0
	var gap := maxf(7.0 * s, spread_px)
	var col := Color(1, 1, 1, 0.85)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(mid + dir * gap, mid + dir * (gap + 11.0 * s), col, 2.0 * s, true)
	var since := PlayerUtil.now() - _num(p, &"last_hit_time", -100.0)
	if since < 0.18:
		var hc := Color(1.0, 0.3, 0.25, 0.95) if (p.get("last_hit_kill") == true or p.get("last_hit_crit") == true) else Color(1, 1, 1, 0.95)
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			c.draw_line(mid + d * 9.0 * s, mid + d * 17.0 * s, hc, 2.5 * s, true)
	var hurt := PlayerUtil.now() - _num(p, &"last_hurt_time", -100.0)
	if hurt < 0.4:
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.1, 0.1, 0.22 * (1.0 - hurt / 0.4)))
