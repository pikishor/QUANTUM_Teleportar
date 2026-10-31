class_name Hud
extends CanvasLayer
## The HUD and every screen around the game (ARCHITECTURE.md, hud / ui). Reads Game.* and Game.player only, never node paths.
## While playing: integrity / coherence / hull bars, ammo or km/h, heat stars, credits, objective with the distance to the nearest core, centre messages,
## vehicle hint, crosshair with the weapon spread, hit marker, damage vignette and direction, quantum power hints, the minimap and (on touchscreens) the
## touch controls (a TouchControls child). Screens: title/menu, pause, dead (DECOHERED), win (SECTOR STABILIZED). Settings and the best score persist
## through UiSettings (user://settings.cfg). Pausing sets Game.state = &"paused" only, never get_tree().paused.

const LOCK := 0.8                   ## seconds after dying / winning before a tap continues (a firing finger must not skip the screen)
const REACH := 4.2                  ## metres: a vehicle this close can be entered (interact)
const TIER_NAMES: Array[String] = ["LOW", "MED", "HIGH"]
const CONTROLS_DESKTOP := "WASD MOVE    MOUSE LOOK    LMB FIRE    RMB AIM    SHIFT SPRINT    SPACE JUMP    R RELOAD    Q BLINK    E LINK    G SUPERPOSE    F USE    ESC PAUSE"
const CONTROLS_TOUCH := "LEFT THUMB MOVE (PUSH FAR TO SPRINT)    RIGHT THUMB LOOK    HOLD FIRE TO SHOOT AND AIM AT ONCE"

@export var settings_path := UiSettings.DEFAULT_PATH
var settings: UiSettings
var minimap: Minimap
var touch: TouchControls
## Active screen buttons: {id: StringName, rect: Rect2, label: String, on: bool}. Rebuilt whenever the state or the viewport changes.
var buttons: Array[Dictionary] = []
var screen_age := 0.0               ## seconds since the current state began
var message_text := ""
var message_left := 0.0
var new_best := false

var _hud: Control
var _screen: Control
var _msg_total := 1.0
var _hover := &""
var _layout_key := ""
var _obj_text := ""
var _cred_text := ""
var _hint_text := ""
var _text_t := 0.0
var _ammo_key := -1
var _ammo_text := ""
var _star := PackedVector2Array()
var _vignette: GradientTexture2D
var _mouse_captured := false
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = UiSettings.new(settings_path)
	_hud = _make_canvas("Hud")
	_screen = _make_canvas("Screen")
	_hud.draw.connect(_draw_hud)
	_screen.draw.connect(_draw_screen)
	minimap = Minimap.new()
	minimap.name = "Minimap"
	_hud.add_child(minimap)
	touch = get_node_or_null("Touch") as TouchControls
	if touch != null:
		touch.pause_requested.connect(pause_game)
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		_star.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.45))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.55, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.0, 0.05, 0.0), Color(0.9, 0.0, 0.05, 0.6)])
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 0.5)
	_vignette.width = 128
	_vignette.height = 128
	Game.message.connect(_on_message)
	Game.state_changed.connect(_on_state)
	Game.new_game.connect(func() -> void: new_best = false)
	var tool_quality := false
	for a in OS.get_cmdline_user_args():
		tool_quality = tool_quality or a.begins_with("--quality=")
	if not Game.autostart and not tool_quality and settings.quality >= 0:
		Game.quality = settings.quality             # main.gd applies it to the world and the atmosphere after composing the modules
	if not Game.autostart:
		apply_settings(false)
	_on_state(Game.state)


func _exit_tree() -> void:
	if _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _make_canvas(node_name: String) -> Control:
	var c := Control.new()
	c.name = node_name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


## Pushes the saved choices to the services that own them: post-process, mute, and (when `with_quality`) the graphics tier.
func apply_settings(with_quality := true) -> void:
	if is_instance_valid(Game.atmosphere):
		Game.atmosphere.set(&"enabled", settings.post)
	Sfx.muted = settings.muted
	if with_quality and settings.quality >= 0:
		Game.set_quality(settings.quality)


# ---------------------------------------------------------------------------------------------------------------------
# state, pause, best score, mouse
# ---------------------------------------------------------------------------------------------------------------------

func _on_state(s: StringName) -> void:
	screen_age = 0.0
	_hover = &""
	if s == &"dead" or s == &"win":
		record_best()
	_hud.visible = s != &"menu"
	_screen.visible = s != &"play"
	minimap.visible = _hud.visible
	_layout_key = ""
	_apply_mouse()


func record_best() -> void:
	if Game.score > settings.best:
		settings.best = Game.score
		new_best = true
		settings.save()


func pause_game() -> void:
	if Game.state == &"play":
		Game.state = &"paused"


func toggle_pause() -> void:
	if Game.state == &"play":
		Game.state = &"paused"
	elif Game.state == &"paused":
		Game.state = &"play"


func touch_ui_on() -> bool:
	return touch != null and touch.controls_on


## Desktop: the mouse is captured while playing (mouse look), released in every other state. Never under tools/tests or with the touch overlay.
func wants_mouse_capture() -> bool:
	return Game.state == &"play" and not touch_ui_on() and not Game.autostart and DisplayServer.get_name() != "headless"


func _apply_mouse() -> void:
	var want := wants_mouse_capture()
	if want != _mouse_captured:
		_mouse_captured = want
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) and not Game.autostart:
		pause_game()


# ---------------------------------------------------------------------------------------------------------------------
# input on the screens
# ---------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.is_action_pressed(&"pause"):
				if Game.state == &"play" or Game.state == &"paused":
					toggle_pause()
					get_viewport().set_input_as_handled()
			elif Game.state != &"play" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE):
				_confirm()
	elif Game.state == &"play":
		return
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tap(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tap(st.position)
	elif event is InputEventMouseMotion:
		var h := _button_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			_screen.queue_redraw()


## Enter / Space on a screen: DEPLOY, RESUME, respawn, next sector.
func _confirm() -> void:
	match Game.state:
		&"menu": press_button(&"deploy")
		&"paused": press_button(&"resume")
		&"dead": press_button(&"respawn")
		&"win": press_button(&"next")


## A press (mouse or finger) on a screen. Returns true when it did something. On the dead and win screens a tap anywhere continues after LOCK seconds.
func tap(pos: Vector2) -> bool:
	if Game.state == &"play":
		return false
	_ensure_layout()
	var id := _button_at(pos)
	if id != &"":
		return press_button(id)
	if Game.state == &"dead":
		return press_button(&"respawn")
	if Game.state == &"win":
		return press_button(&"next")
	return false


func _button_at(pos: Vector2) -> StringName:
	_ensure_layout()
	for b: Dictionary in buttons:
		if (b["rect"] as Rect2).grow(4.0).has_point(pos):
			return b["id"]
	return &""


## The effect of every screen button (the tests press them through here).
func press_button(id: StringName) -> bool:
	match id:
		&"deploy":
			if Game.state != &"menu":
				return false
			Game.start_new_game()
		&"resume":
			if Game.state != &"paused":
				return false
			Game.state = &"play"
		&"menu":
			if Game.state != &"paused":
				return false
			Game.state = &"menu"
		&"respawn":
			if Game.state != &"dead" or screen_age < LOCK:
				return false
			Game.do_respawn()
		&"next":
			if Game.state != &"win" or screen_age < LOCK:
				return false
			Game.do_next_sector()
		&"q0", &"q1", &"q2":
			settings.quality = int(String(id).substr(1))
			Game.set_quality(settings.quality)
			settings.save()
		&"post":
			settings.post = not settings.post
			apply_settings(false)
			settings.save()
		&"mute":
			settings.muted = not settings.muted
			apply_settings(false)
			settings.save()
		_:
			return false
	_layout_key = ""
	_screen.queue_redraw()
	return true


# ---------------------------------------------------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------------------------------------------------

func _on_message(text: String, seconds: float) -> void:
	message_text = text
	message_left = seconds
	_msg_total = maxf(seconds, 0.1)


## "QUANTUM CORES  2 / 6   NEAREST  143 M" with the horizontal distance to the nearest core (the Missions module may not exist).
func objective_text() -> String:
	var m: Object = Game.missions if is_instance_valid(Game.missions) else null
	if m == null:
		return "NO ACTIVE OBJECTIVE"
	var total := roundi(UiUtil.num(m, &"total", 0.0))
	if total <= 0:
		return "NO ACTIVE OBJECTIVE"
	var t := "QUANTUM CORES  %d / %d" % [roundi(UiUtil.num(m, &"got", 0.0)), total]
	if m.has_method(&"nearest_core") and is_instance_valid(Game.player):
		var n: Dictionary = m.call(&"nearest_core", Game.player.global_position)
		if not n.is_empty():
			t += "   NEAREST  %d M" % roundi(float(n.get("dist", 0.0)))
	return t


## "27 / 30", "RELOADING" on foot, "84 KM/H" in a vehicle (cached: rebuilt only when a number changes).
func ammo_text() -> String:
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p == null:
		return ""
	var veh: Object = p.get("vehicle")
	var key: int
	if veh != null:
		key = 1 + roundi(absf(UiUtil.num(veh, &"speed", 0.0)) * 3.6) * 4
	elif p.get("reloading") == true:
		key = 2
	else:
		key = 3 + (roundi(UiUtil.num(p, &"ammo", 0.0)) * 100 + roundi(UiUtil.num(p, &"mag", 30.0))) * 4
	if key != _ammo_key:
		_ammo_key = key
		if veh != null:
			_ammo_text = "%d KM/H" % roundi(absf(UiUtil.num(veh, &"speed", 0.0)) * 3.6)
		elif p.get("reloading") == true:
			_ammo_text = "RELOADING"
		else:
			_ammo_text = "%d / %d" % [roundi(UiUtil.num(p, &"ammo", 0.0)), roundi(UiUtil.num(p, &"mag", 30.0))]
	return _ammo_text


func hint_text() -> String:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player):
		return ""
	var key := "" if touch_ui_on() else "[F]  "
	if Game.player.get("vehicle") != null:
		return key + "EXIT VEHICLE"
	if Game.vehicles.has_method(&"nearest") and Game.vehicles.call(&"nearest", Game.player.global_position, REACH) != null:
		return key + "ENTER VEHICLE"
	return ""


func _process(delta: float) -> void:
	_t += delta
	screen_age += delta
	message_left = maxf(message_left - delta, 0.0)
	_text_t -= delta
	if _text_t <= 0.0:
		_text_t = 0.2
		_obj_text = objective_text()
		_cred_text = "CREDITS  %d" % Game.score
		_hint_text = hint_text()
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var side := 176.0 * s
	minimap.position = Vector2(ins.x + 16.0 * s, 14.0 * s)
	minimap.size = Vector2(side, side)
	if _hud.visible:
		_hud.queue_redraw()
	if _screen.visible:
		_screen.queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------
# HUD drawing
# ---------------------------------------------------------------------------------------------------------------------

func _text(c: Control, font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, col: Color, shadow := 0.0) -> void:
	if shadow > 0.0:
		c.draw_string(font, pos + Vector2(shadow, shadow), text, align, width, size, Color(0, 0, 0, col.a * 0.8))
	c.draw_string(font, pos, text, align, width, size, col)


func _bar(c: Control, font: Font, x: float, y: float, w: float, h: float, frac: float, col: Color, label: String, value: String, s: float) -> void:
	var r := Rect2(x, y, w, h)
	c.draw_rect(r.grow(2.0 * s), Color(0.0, 0.03, 0.05, 0.55))
	c.draw_rect(Rect2(x, y, w * clampf(frac, 0.0, 1.0), h), col)
	c.draw_rect(r, Color(col, 0.55), false, 1.0 * s)
	_text(c, font, Vector2(x - 8.0 * s - 90.0 * s, y + h - 0.5 * s), label, HORIZONTAL_ALIGNMENT_RIGHT, 90.0 * s, int(12.0 * s), Color(UiUtil.CYAN, 0.85))
	_text(c, font, Vector2(x + w + 7.0 * s, y + h - 0.5 * s), value, HORIZONTAL_ALIGNMENT_LEFT, 44.0 * s, int(12.0 * s), Color(1, 1, 1, 0.85))


func _draw_hud(_ignored: Control = null) -> void:
	var c := _hud
	var vp := c.size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var ins := UiUtil.insets(vp)
	var right := vp.x - ins.y - 16.0 * s
	var playing := Game.state == &"play"
	var p: Node3D = Game.player if is_instance_valid(Game.player) else null
	var veh: Object = p.get("vehicle") if p != null else null
	var now := PlayerUtil.now()
	# damage vignette first so everything else sits on top of it
	if p != null:
		var since_hurt := now - UiUtil.num(p, &"last_hurt_time", -100.0)
		var a := clampf(1.0 - since_hurt / 0.6, 0.0, 1.0) * 0.8
		var hp_f := UiUtil.num(p, &"hp", 100.0) / maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		if hp_f < 0.3 and playing:
			a = maxf(a, (0.3 - hp_f) / 0.3 * (0.3 + 0.1 * sin(_t * 6.0)))
		if a > 0.01:
			c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(1, 1, 1, a))
		if since_hurt < 1.0 and playing:
			_draw_hurt_direction(c, p, vp, s, 1.0 - since_hurt)
	# top centre: integrity, coherence, (hull), objective
	if p != null:
		var bw := 220.0 * s
		var bx := vp.x * 0.5 - bw * 0.5 + 12.0 * s
		var hp := UiUtil.num(p, &"hp", 100.0)
		var mhp := maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		var f := clampf(hp / mhp, 0.0, 1.0)
		var hp_col := Color(0.4, 1.0, 0.72, 0.95) if f > 0.35 else Color(1.0, 0.3, 0.3, 0.95)
		_bar(c, font, bx, 16.0 * s, bw, 8.0 * s, f, hp_col, "INTEGRITY", str(ceili(hp)), s)
		var en := UiUtil.num(p, &"energy", 100.0)
		var men := maxf(UiUtil.num(p, &"max_energy", 100.0), 1.0)
		_bar(c, font, bx, 34.0 * s, bw, 8.0 * s, en / men, Color(0.35, 0.8, 1.0, 0.95), "COHERENCE", str(floori(en)), s)
		var row := 52.0
		if veh != null and UiUtil.num(veh, &"hp", -1.0) >= 0.0:
			var vh := UiUtil.num(veh, &"hp", 0.0)
			_bar(c, font, bx, row * s, bw, 8.0 * s, vh / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0), Color(1.0, 0.65, 0.25, 0.95), "HULL", str(ceili(vh)), s)
			row += 18.0
		_text(c, font, Vector2(0.0, (row + 22.0) * s), _obj_text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(16.0 * s), Color(UiUtil.MAGENTA.lerp(Color.WHITE, 0.35), 0.95), 1.0 * s)
	# top right: heat stars and credits
	var heat := Game.heat
	for i in 5:
		var centre := Vector2(right - (4 - i) * 27.0 * s - 10.0 * s, 26.0 * s)
		c.draw_set_transform(centre, 0.0, Vector2(10.5, 10.5) * s)
		c.draw_colored_polygon(_star, Color(1, 1, 1, 0.12))
		var fill := clampf(heat - i, 0.0, 1.0)
		if fill > 0.0:
			var col := UiUtil.AMBER if heat < 3.0 else UiUtil.RED
			var pulse := 1.0 if heat < 3.0 else 0.8 + 0.2 * sin(_t * 8.0)
			c.draw_colored_polygon(_star, Color(col, (0.35 + 0.65 * fill) * pulse))
	c.draw_set_transform(Vector2.ZERO)
	_text(c, font, Vector2(right - 220.0 * s, 62.0 * s), _cred_text, HORIZONTAL_ALIGNMENT_RIGHT, 220.0 * s, int(17.0 * s), Color(1, 1, 1, 0.92), 1.0 * s)
	if p == null:
		_draw_message(c, vp, s, font)
		return
	# bottom centre: ammo or speed, power hints
	var ammo := ammo_text()
	var ab := Rect2(vp.x * 0.5 - 92.0 * s, vp.y - 66.0 * s, 184.0 * s, 40.0 * s)
	c.draw_rect(ab, Color(0.0, 0.03, 0.05, 0.5))
	c.draw_rect(ab, Color(UiUtil.CYAN, 0.35), false, 1.0 * s)
	_text(c, font, Vector2(ab.position.x, ab.position.y + 30.0 * s), ammo, HORIZONTAL_ALIGNMENT_CENTER, ab.size.x, int(26.0 * s), Color(1, 1, 1, 0.95) if p.get("reloading") != true else Color(UiUtil.AMBER, 0.95))
	if p.get("quantum") != null and not touch_ui_on():
		for i in 3:
			var info: Dictionary = UiUtil.ABILITIES[i]
			var st := UiUtil.ability_state(p, info)
			var r := Rect2(vp.x * 0.5 - 130.0 * s + i * 90.0 * s, vp.y - 100.0 * s, 80.0 * s, 26.0 * s)
			var tint := UiUtil.AMBER if st["active"] else UiUtil.CYAN
			var dim := 1.0 if (st["ready"] or st["active"]) else 0.4
			c.draw_rect(r, Color(0.0, 0.03, 0.05, 0.5))
			if float(st["cd"]) > 0.0:
				c.draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 - float(st["cd"])), r.size.y)), Color(tint, 0.2))
			elif st["active"]:
				c.draw_rect(r, Color(tint, 0.18))
			c.draw_rect(r, Color(tint, 0.6 * dim), false, 1.0 * s)
			_text(c, font, Vector2(r.position.x, r.position.y + 18.0 * s), "%s  %s" % [info["key"], info["label"]], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(13.0 * s), Color(1, 1, 1, 0.92 * dim))
	if playing and veh == null:
		_draw_crosshair(c, p, vp, s, now)
	if playing and _hint_text != "":
		_text(c, font, Vector2(0.0, vp.y * 0.64), _hint_text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.CYAN, 0.95), 1.5 * s)
	_draw_message(c, vp, s, font)


func _draw_message(c: Control, vp: Vector2, s: float, font: Font) -> void:
	if message_left <= 0.0 or message_text == "" or Game.state != &"play":
		return
	var fade := clampf(minf(message_left / 0.4, (_msg_total - message_left) / 0.12 + 0.3), 0.0, 1.0)
	_text(c, font, Vector2(0.0, vp.y * 0.30), message_text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(26.0 * s), Color(1, 1, 1, 0.97 * fade), 2.0 * s)


func _draw_crosshair(c: Control, p: Node3D, vp: Vector2, s: float, now: float) -> void:
	var mid := vp * 0.5
	var spread_px := float(p.call(&"spread_in_pixels", vp.y)) if p.has_method(&"spread_in_pixels") else 0.0
	var gap := maxf(7.0 * s, spread_px)
	var col := Color(1, 1, 1, 0.85)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(mid + dir * gap, mid + dir * (gap + 10.0 * s), col, 1.6 * s, true)
	c.draw_circle(mid, 1.2 * s, Color(1, 1, 1, 0.9))
	var since := now - UiUtil.num(p, &"last_hit_time", -100.0)
	if since < 0.18:
		var hc := Color(1.0, 0.3, 0.25, 0.95) if (p.get("last_hit_kill") == true or p.get("last_hit_crit") == true) else Color(1, 1, 1, 0.95)
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			c.draw_line(mid + d * 9.0 * s, mid + d * 17.0 * s, hc, 2.2 * s, true)


## A red arc around the crosshair that points at where the last hit came from (relative to the view direction).
func _draw_hurt_direction(c: Control, p: Node3D, vp: Vector2, s: float, alpha: float) -> void:
	var from: Variant = p.get("last_hurt_from")
	if not (from is Vector3) or (from as Vector3) == Vector3.ZERO or not is_instance_valid(Game.camera):
		return
	var d := (from as Vector3) - p.global_position
	var b := Game.camera.global_transform.basis
	var fwd := Vector2(-b.z.x, -b.z.z)
	if fwd.length() < 0.001 or Vector2(d.x, d.z).length() < 0.01:
		return
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var flat := Vector2(d.x, d.z)
	var ang := atan2(flat.dot(right), flat.dot(fwd)) - PI * 0.5
	c.draw_arc(vp * 0.5, 120.0 * s, ang - 0.32, ang + 0.32, 10, Color(1.0, 0.2, 0.2, 0.9 * alpha), 6.0 * s, true)


# ---------------------------------------------------------------------------------------------------------------------
# screens
# ---------------------------------------------------------------------------------------------------------------------

func _ensure_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var key := "%s|%d|%d|%d|%d|%s%s" % [Game.state, int(vp.x), int(vp.y), Game.quality, int(settings.quality), settings.post, settings.muted]
	if key == _layout_key:
		return
	_layout_key = key
	buttons.clear()
	var s := UiUtil.ui_scale(vp)
	var cx := vp.x * 0.5
	match Game.state:
		&"menu":
			_add(&"deploy", Rect2(cx - 170.0 * s, 318.0 * s, 340.0 * s, 64.0 * s), "DEPLOY", false)
			_settings_rows(cx, 430.0, s)
		&"paused":
			_add(&"resume", Rect2(cx - 170.0 * s, 238.0 * s, 340.0 * s, 64.0 * s), "RESUME", false)
			_settings_rows(cx, 350.0, s)
			_add(&"menu", Rect2(cx - 154.0 * s, 484.0 * s, 308.0 * s, 40.0 * s), "ABORT TO MENU", false)
		&"dead":
			_add(&"respawn", Rect2(cx - 170.0 * s, 430.0 * s, 340.0 * s, 64.0 * s), "RESPAWN", false)
		&"win":
			_add(&"next", Rect2(cx - 170.0 * s, 430.0 * s, 340.0 * s, 64.0 * s), "NEXT SECTOR", false)


func _settings_rows(cx: float, y: float, s: float) -> void:
	for i in 3:
		_add(StringName("q%d" % i), Rect2(cx - 154.0 * s + i * 106.0 * s, y * s, 96.0 * s, 40.0 * s), TIER_NAMES[i], Game.quality == i)
	_add(&"post", Rect2(cx - 154.0 * s, (y + 56.0) * s, 150.0 * s, 40.0 * s), "POST FX  " + ("ON" if settings.post else "OFF"), settings.post)
	_add(&"mute", Rect2(cx + 4.0 * s, (y + 56.0) * s, 150.0 * s, 40.0 * s), "SOUND  " + ("OFF" if settings.muted else "ON"), not settings.muted)


func _add(id: StringName, r: Rect2, label: String, on: bool) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "on": on})


func _draw_screen(_ignored: Control = null) -> void:
	var c := _screen
	var vp := c.size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var cx := vp.x * 0.5
	_ensure_layout()
	var st := Game.state
	var ink := UiUtil.INK
	match st:
		&"menu":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.62))
		&"paused":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.7))
		&"dead":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.12, 0.0, 0.02, 0.82))
		&"win":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.08, 0.1, 0.82))
	# thin horizontal frame lines
	var frame_col := Color(UiUtil.CYAN, 0.35)
	c.draw_line(Vector2(0.0, 74.0 * s), Vector2(vp.x, 74.0 * s), Color(frame_col, 0.12), 1.0 * s)
	c.draw_line(Vector2(0.0, vp.y - 74.0 * s), Vector2(vp.x, vp.y - 74.0 * s), Color(frame_col, 0.12), 1.0 * s)
	match st:
		&"menu":
			_text(c, font, Vector2(0.0, 196.0 * s), "QUANTUM TELEPORTAR", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(76.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
			c.draw_line(Vector2(cx - 240.0 * s, 222.0 * s), Vector2(cx + 240.0 * s, 222.0 * s), Color(UiUtil.MAGENTA, 0.8), 2.0 * s)
			_text(c, font, Vector2(0.0, 258.0 * s), "OBSERVER CORP INCURSION  //  SECTOR 01", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(19.0 * s), Color(UiUtil.CYAN, 0.9))
			_text(c, font, Vector2(0.0, 424.0 * s), "GRAPHICS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(UiUtil.CYAN, 0.7))
			_footer(c, vp, s, font)
		&"paused":
			_text(c, font, Vector2(0.0, 190.0 * s), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(64.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
			_text(c, font, Vector2(0.0, 344.0 * s), "GRAPHICS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(UiUtil.CYAN, 0.7))
			_footer(c, vp, s, font)
		&"dead":
			_text(c, font, Vector2(0.0, 270.0 * s), "DECOHERED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(84.0 * s), Color(UiUtil.RED, 0.97), 3.0 * s)
			_score_lines(c, vp, s, font, 332.0)
			var blink := 0.55 + 0.45 * sin(_t * 4.0) if screen_age >= LOCK else 0.25
			_text(c, font, Vector2(0.0, 540.0 * s), "TAP TO RESPAWN", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(24.0 * s), Color(1, 1, 1, blink))
		&"win":
			_text(c, font, Vector2(0.0, 270.0 * s), "SECTOR STABILIZED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(76.0 * s), Color(UiUtil.CYAN, 0.97), 3.0 * s)
			_score_lines(c, vp, s, font, 332.0)
			var blink2 := 0.55 + 0.45 * sin(_t * 4.0) if screen_age >= LOCK else 0.25
			_text(c, font, Vector2(0.0, 540.0 * s), "TAP TO CONTINUE", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(24.0 * s), Color(1, 1, 1, blink2))
	for b: Dictionary in buttons:
		var r: Rect2 = b["rect"]
		var big := r.size.y > 50.0 * s
		var on: bool = b["on"]
		var hot: bool = _hover == b["id"]
		var tint := UiUtil.MAGENTA if (big and b["id"] != &"next" and b["id"] != &"resume") else UiUtil.CYAN
		c.draw_rect(r, Color(tint, 0.30 if (on or hot) else 0.10))
		c.draw_rect(r, Color(tint, 0.95 if (on or hot or big) else 0.5), false, 2.0 * s if big else 1.5 * s)
		_text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + (9.0 if big else 6.0) * s), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int((28.0 if big else 15.0) * s), Color(1, 1, 1, 0.97 if (on or hot or big) else 0.75))


func _score_lines(c: Control, vp: Vector2, s: float, font: Font, y: float) -> void:
	_text(c, font, Vector2(0.0, y * s), "CREDITS  %d" % Game.score, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(30.0 * s), Color(1, 1, 1, 0.95), 1.5 * s)
	var line := "NEW BEST" if new_best else "BEST  %d" % settings.best
	_text(c, font, Vector2(0.0, (y + 36.0) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.AMBER, 0.95))


func _footer(c: Control, vp: Vector2, s: float, font: Font) -> void:
	_text(c, font, Vector2(0.0, vp.y - 40.0 * s), CONTROLS_TOUCH if touch_ui_on() else CONTROLS_DESKTOP, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(1, 1, 1, 0.55))
	if Game.state == &"menu":
		_text(c, font, Vector2(0.0, vp.y - 90.0 * s), "BEST  %d" % settings.best, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(16.0 * s), Color(UiUtil.AMBER, 0.9))
