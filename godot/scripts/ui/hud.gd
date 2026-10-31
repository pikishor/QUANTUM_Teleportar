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
const VIGNETTE_MAX := 0.35          ## hard cap of the one damage vignette's alpha: the world stays readable, never a screen fill
const HURT_TIME := 0.45             ## seconds the hit vignette lasts
const MARKER_TIME := 0.7            ## seconds the attacker marker lasts
const DEAD_DIM := 0.30              ## alpha of the DECOHERED / SECTOR STABILIZED dimming (never above 0.35)
## Base-px baseline of the centre message: below the top stack and the radio subtitle lane, above the crosshair.
const MSG_Y := 276.0
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
var _q: Array = []                  ## queued draws (see _text): text, rectangles, sprites, outlines
var _fills: Array = []
var _frames: Array = []
var _sprites: Array = []


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
	g.offsets = PackedFloat32Array([0.62, 1.0])        # clear in the middle 60 %, the colour gathers only at the very edge
	g.colors = PackedColorArray([Color(0.85, 0.02, 0.06, 0.0), Color(0.85, 0.02, 0.06, 1.0)])
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


## True when the HUD and screen layers show what the state asks for (HUD hidden only in the menu, the screen layer hidden only while playing).
func layers_consistent() -> bool:
	return _hud.visible == (Game.state != &"menu") and _screen.visible == (Game.state != &"play") and minimap.visible == _hud.visible


## Puts the layers back in line with the state (the stability audit calls it when they drifted).
func refresh_layers() -> void:
	_on_state(Game.state)


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
	var real := delta / maxf(Engine.time_scale, 0.05)       # screens and locks count real seconds, so a slow-motion death never delays the respawn button
	_t += real
	screen_age += real
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
	minimap.position = Vector2(ins.x + 16.0 * s, 14.0 * s + UiUtil.insets_v(vp).x)
	minimap.size = Vector2(side, side)
	if _hud.visible:
		_hud.queue_redraw()
	if _screen.visible:
		_screen.queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------
# HUD drawing
# ---------------------------------------------------------------------------------------------------------------------

## Everything the HUD draws every frame is queued and flushed in batch-friendly order: plain rectangles, then sprites (grouped by texture), then outlines, then text
## (grouped by size). Canvas draws only batch when consecutive commands share their kind and texture, so the order of calls in the code is NOT the draw order.
func _text(c: Control, font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, col: Color, shadow := 0.0) -> void:
	_q.append([c, font, pos, text, align, width, size, col, shadow])


func _rect(c: Control, r: Rect2, col: Color) -> void:
	_fills.append([c, r, col])


func _frame(c: Control, r: Rect2, col: Color, w: float) -> void:
	_frames.append([c, r, col, w])


func _sprite(c: Control, kind: StringName, r: Rect2, col: Color) -> void:
	_sprites.append([c, kind, r, col])


func _flush_text() -> void:
	for f: Array in _fills:
		(f[0] as Control).draw_rect(f[1], f[2])
	_fills.clear()
	if not _sprites.is_empty():
		var kinds := {}
		for sp: Array in _sprites:
			kinds[sp[1]] = true
		for k: StringName in kinds.keys():
			for sp: Array in _sprites:
				if sp[1] == k:
					(sp[0] as Control).draw_texture_rect(UiUtil.sprite(k), sp[2], false, sp[3])
		_sprites.clear()
	for f: Array in _frames:
		(f[0] as Control).draw_rect(f[1], f[2], false, f[3])
	_frames.clear()
	var sizes := {}
	for q: Array in _q:
		sizes[q[6]] = true
	for sz: int in sizes.keys():
		for q: Array in _q:
			if q[6] == sz and float(q[8]) > 0.0:
				var col: Color = q[7]
				(q[0] as Control).draw_string(q[1], (q[2] as Vector2) + Vector2(q[8], q[8]), q[3], q[4], q[5], q[6], Color(0, 0, 0, col.a * 0.85))
		for q: Array in _q:
			if q[6] == sz:
				(q[0] as Control).draw_string(q[1], q[2], q[3], q[4], q[5], q[6], q[7])
	_q.clear()


## A backing plate (dark translucent rectangle with a thin accent line on its lower edge).
func _plate(c: Control, r: Rect2, s: float, accent := Color(UiUtil.CYAN, 0.45)) -> void:
	_rect(c, r, UiUtil.PLATE)
	_rect(c, Rect2(r.position.x, r.end.y - 2.0 * s, r.size.x, 2.0 * s), accent)


func _text_width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A centred line of text on its own plate; returns the plate.
func _plate_text(c: Control, font: Font, cx: float, y: float, text: String, size: int, col: Color, s: float, accent := Color(UiUtil.CYAN, 0.45), min_w := 0.0) -> Rect2:
	var w := maxf(_text_width(font, text, size) + 36.0 * s, min_w)
	var r := Rect2(cx - w * 0.5, y, w, float(size) * 1.45 + 6.0 * s)
	_plate(c, r, s, accent)
	_text(c, font, Vector2(r.position.x, y + float(size) * 1.1 + 2.0 * s), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col, 1.5 * s)
	return r


func _bar(c: Control, font: Font, x: float, y: float, w: float, h: float, frac: float, col: Color, label: String, value: String, s: float) -> void:
	var r := Rect2(x, y, w, h)
	_rect(c, r.grow(2.0 * s), Color(0.0, 0.03, 0.05, 0.6))
	_rect(c, Rect2(x, y, w * clampf(frac, 0.0, 1.0), h), col)
	_frame(c, r, Color(col, 0.7), 1.0 * s)
	_text(c, font, Vector2(x - 8.0 * s - 132.0 * s, y + h + 3.0 * s), label, HORIZONTAL_ALIGNMENT_RIGHT, 132.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	_text(c, font, Vector2(x + w + 8.0 * s, y + h + 4.0 * s), value, HORIZONTAL_ALIGNMENT_LEFT, 56.0 * s, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.95), 1.0 * s)


func _draw_hud(_ignored: Control = null) -> void:
	_draw_hud_body()
	_flush_text()


func _draw_hud_body() -> void:
	var c := _hud
	var vp := c.size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var ins := UiUtil.insets(vp)
	var insv := UiUtil.insets_v(vp)
	var right := vp.x - ins.y - 16.0 * s
	var playing := Game.state == &"play"
	var p: Node3D = Game.player if is_instance_valid(Game.player) else null
	var veh: Object = p.get("vehicle") if p != null else null
	var now := PlayerUtil.now()
	# damage vignette first so everything else sits on top of it
	if p != null:
		var since_hurt := now - UiUtil.num(p, &"last_hurt_time", -100.0)
		var hp_f := UiUtil.num(p, &"hp", 100.0) / maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		var a := vignette_alpha(since_hurt, hp_f, playing, _t)
		if a > 0.01:
			c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(1, 1, 1, a))
		if since_hurt < MARKER_TIME and playing:
			_draw_hurt_direction(c, p, vp, s, 1.0 - since_hurt / MARKER_TIME)
	# top centre, one stack: integrity / coherence (/ hull) bars on a plate, the objective line on a plate under them. The story layer starts below it.
	var top := insv.x + 6.0 * s
	var stack_end := top
	if p != null:
		var bw := 220.0 * s
		var total := 132.0 * s + 8.0 * s + bw + 8.0 * s + 56.0 * s
		var bx := vp.x * 0.5 - total * 0.5 + 140.0 * s
		var hp := UiUtil.num(p, &"hp", 100.0)
		var mhp := maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		var f := clampf(hp / mhp, 0.0, 1.0)
		var hp_col := Color(0.4, 1.0, 0.72, 0.95) if f > 0.35 else Color(1.0, 0.3, 0.3, 0.95)
		var has_hull := veh != null and UiUtil.num(veh, &"hp", -1.0) >= 0.0
		var rows := 3 if has_hull else 2
		var plate := Rect2(vp.x * 0.5 - total * 0.5 - 12.0 * s, top, total + 24.0 * s, (12.0 + 24.0 * (rows - 1) + 14.0 + 8.0) * s)
		_plate(c, plate, s)
		var y0 := top + 10.0 * s
		_bar(c, font, bx, y0, bw, 14.0 * s, f, hp_col, "INTEGRITY", str(ceili(hp)), s)
		var en := UiUtil.num(p, &"energy", 100.0)
		var men := maxf(UiUtil.num(p, &"max_energy", 100.0), 1.0)
		_bar(c, font, bx, y0 + 24.0 * s, bw, 14.0 * s, en / men, Color(0.35, 0.8, 1.0, 0.95), "COHERENCE", str(floori(en)), s)
		if has_hull:
			var vh := UiUtil.num(veh, &"hp", 0.0)
			_bar(c, font, bx, y0 + 48.0 * s, bw, 14.0 * s, vh / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0), Color(1.0, 0.65, 0.25, 0.95), "HULL", str(ceili(vh)), s)
		var obj := _plate_text(c, font, vp.x * 0.5, plate.end.y + 4.0 * s, _obj_text, int(UiUtil.TEXT_MIN * s), Color(UiUtil.MAGENTA.lerp(Color.WHITE, 0.45), 1.0), s, Color(UiUtil.MAGENTA, 0.6), 300.0 * s)
		stack_end = obj.end.y
	UiUtil.stack_bottom = stack_end / s
	# top right: heat stars and credits on one plate
	_plate(c, Rect2(right - 176.0 * s, top, 184.0 * s, 76.0 * s), s)
	var heat := Game.heat
	for i in 5:
		var centre := Vector2(right - (4 - i) * 30.0 * s - 14.0 * s, top + 22.0 * s)
		var sr := Rect2(centre - Vector2(12.0, 12.0) * s, Vector2(24.0, 24.0) * s)
		_sprite(c, &"star", sr, Color(1, 1, 1, 0.16))
		var fill := clampf(heat - i, 0.0, 1.0)
		if fill > 0.0:
			var col := UiUtil.AMBER if heat < 3.0 else UiUtil.RED
			var pulse := 1.0 if heat < 3.0 else 0.8 + 0.2 * sin(_t * 8.0)
			_sprite(c, &"star", sr, Color(col, (0.35 + 0.65 * fill) * pulse))
	_text(c, font, Vector2(right - 172.0 * s, top + 64.0 * s), _cred_text, HORIZONTAL_ALIGNMENT_RIGHT, 170.0 * s, int(24.0 * s), Color(1, 1, 1, 0.97), 1.5 * s)
	if p == null:
		_draw_message(c, vp, s, font)
		return
	if not playing and Game.state != &"paused":                # dead and win: the middle and the bottom belong to the world and the screen's own button
		_draw_message(c, vp, s, font)
		return
	# bottom: ammo or speed (on phones left of the touch buttons), power hints (desktop), vehicle hint above the ammo
	var base_y := vp.y - insv.y
	var touch_on := touch_ui_on()
	var aw := 230.0 * s
	var ax := vp.x * 0.5
	if touch_on:
		ax = minf(ax, vp.x - ins.y - 600.0 * s - aw * 0.5 - 10.0 * s)
	var ab := Rect2(ax - aw * 0.5, base_y - 70.0 * s, aw, 54.0 * s)
	_plate(c, ab, s)
	_text(c, font, Vector2(ab.position.x, ab.position.y + 41.0 * s), ammo_text(), HORIZONTAL_ALIGNMENT_CENTER, ab.size.x, int(38.0 * s), Color(1, 1, 1, 0.97) if p.get("reloading") != true else Color(UiUtil.AMBER, 0.97), 1.5 * s)
	if p.get("quantum") != null and not touch_on:
		for i in 3:
			var info: Dictionary = UiUtil.ABILITIES[i]
			var st := UiUtil.ability_state(p, info)
			var r := Rect2(ax - 188.0 * s + i * 128.0 * s, base_y - 118.0 * s, 120.0 * s, 36.0 * s)
			var tint := UiUtil.AMBER if st["active"] else UiUtil.CYAN
			var dim := 1.0 if (st["ready"] or st["active"]) else 0.5
			_rect(c, r, UiUtil.PLATE)
			if float(st["cd"]) > 0.0:
				_rect(c, Rect2(r.position, Vector2(r.size.x * (1.0 - float(st["cd"])), r.size.y)), Color(tint, 0.25))
			elif st["active"]:
				_rect(c, r, Color(tint, 0.22))
			_frame(c, r, Color(tint, 0.8 * dim), 1.5 * s)
			var label := "%s  %s" % [info["key"], info["label"]]
			if st["active"]:
				label += "  %d" % ceili(float(st["left"]))
			_text(c, font, Vector2(r.position.x, r.position.y + 27.0 * s), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(UiUtil.TEXT_MIN * 0.9 * s), Color(1, 1, 1, 0.97 * dim), 1.0 * s)
	if playing:
		_draw_quantum_readout(c, vp, s, font)
	if playing and veh == null:
		_draw_crosshair(c, p, vp, s, now)
	if playing and _hint_text != "":
		_plate_text(c, font, ab.get_center().x, ab.position.y - (46.0 * s if (p.get("quantum") == null or touch_on) else 98.0 * s), _hint_text, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 1.0), s)
	_draw_message(c, vp, s, font)


## THE damage vignette (the only full-screen hurt overlay in the game): a short red gathering at the screen edge after a hit, plus a slow faint pulse when
## health is low. Hard cap VIGNETTE_MAX, so it can never hide the world. `since_hurt` seconds since the last hit, `hp_f` health fraction 0..1.
static func vignette_alpha(since_hurt: float, hp_f: float, playing: bool, t: float) -> float:
	var a := clampf(1.0 - since_hurt / HURT_TIME, 0.0, 1.0) * 0.3
	if hp_f < 0.3 and playing:
		a = maxf(a, (0.3 - hp_f) / 0.3 * (0.14 + 0.05 * sin(t * 5.0)))
	return minf(a, VIGNETTE_MAX)


## What the last blink told: Alice's two classical bits and the correction Bob applies. {visible, m0, m1, fix, alpha}; empty of meaning until a teleport.
func quantum_readout() -> Dictionary:
	var q: Object = Game.player.get("quantum") if is_instance_valid(Game.player) else null
	var left := UiUtil.num(q, &"bits_left", 0.0)
	return {
		"visible": q != null and left > 0.0,
		"m0": int(UiUtil.num(q, &"last_m0", 0.0)), "m1": int(UiUtil.num(q, &"last_m1", 0.0)),
		"fix": str(q.get("last_fix")) if q != null else "", "alpha": clampf(left / 0.8, 0.0, 1.0),
	}


## Thin-line teleport readout under the centre message: m1 -> X gate, m0 -> Z gate, a gate lights when Bob has to apply it.
func _draw_quantum_readout(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var ro := quantum_readout()
	if not ro["visible"]:
		return
	var a: float = ro["alpha"]
	var w := 340.0 * s
	var box := Rect2(vp.x * 0.5 - w * 0.5, MSG_Y * s + 10.0 * s, w, 56.0 * s)
	_rect(c, box, Color(UiUtil.PLATE, UiUtil.PLATE.a * a))
	_frame(c, box, Color(UiUtil.CYAN, 0.55 * a), 1.0 * s)
	_text(c, font, Vector2(box.position.x, box.position.y + 18.0 * s), "ALICE SENDS 2 BITS  >  BOB CORRECTS", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, int(16.0 * s), Color(UiUtil.CYAN, 0.95 * a), 1.0 * s)
	for i in 2:
		var bit: int = ro["m1"] if i == 0 else ro["m0"]
		var gate := "X" if i == 0 else "Z"
		var x := box.position.x + 20.0 * s + i * 158.0 * s
		var y := box.position.y + 26.0 * s
		var on := bit == 1
		var rb := Rect2(x, y, 28.0 * s, 28.0 * s)
		_rect(c, rb, Color(UiUtil.CYAN, (0.3 if on else 0.08) * a))
		_frame(c, rb, Color(UiUtil.CYAN, 0.85 * a), 1.0 * s)
		_text(c, font, Vector2(rb.position.x, rb.position.y + 22.0 * s), str(bit), HORIZONTAL_ALIGNMENT_CENTER, rb.size.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, a), 1.0 * s)
		_text(c, font, Vector2(rb.end.x + 4.0 * s, rb.position.y + 21.0 * s), "m%d >" % (1 - i), HORIZONTAL_ALIGNMENT_LEFT, 44.0 * s, int(16.0 * s), Color(1, 1, 1, 0.85 * a), 1.0 * s)
		var rg := Rect2(x + 84.0 * s, y, 28.0 * s, 28.0 * s)
		_rect(c, rg, Color(UiUtil.MAGENTA, (0.5 if on else 0.06) * a))
		_frame(c, rg, Color(UiUtil.MAGENTA, (0.9 if on else 0.4) * a), 1.0 * s)
		_text(c, font, Vector2(rg.position.x, rg.position.y + 22.0 * s), gate, HORIZONTAL_ALIGNMENT_CENTER, rg.size.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, (1.0 if on else 0.5) * a), 1.0 * s)


func _draw_message(c: Control, vp: Vector2, s: float, font: Font) -> void:
	if message_left <= 0.0 or message_text == "" or Game.state != &"play":
		return
	var fade := clampf(minf(message_left / 0.4, (_msg_total - message_left) / 0.12 + 0.3), 0.0, 1.0)
	var size := int(30.0 * s)
	var w := minf(_text_width(font, message_text, size) + 40.0 * s, vp.x - 40.0 * s)
	var r := Rect2(vp.x * 0.5 - w * 0.5, (MSG_Y - 34.0) * s, w, 46.0 * s)
	_rect(c, r, Color(UiUtil.PLATE, UiUtil.PLATE.a * fade))
	_rect(c, Rect2(r.position.x, r.end.y - 2.0 * s, r.size.x, 2.0 * s), Color(UiUtil.CYAN, 0.5 * fade))
	_text(c, font, Vector2(r.position.x, MSG_Y * s), message_text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.98 * fade), 2.0 * s)


func _draw_crosshair(c: Control, p: Node3D, vp: Vector2, s: float, now: float) -> void:
	var mid := vp * 0.5
	var spread_px := float(p.call(&"spread_in_pixels", vp.y)) if p.has_method(&"spread_in_pixels") else 0.0
	var gap := maxf(7.0 * s, spread_px)
	var col := Color(1, 1, 1, 0.9)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:       # arms are axis-aligned rectangles (they batch with the plates), dark edge under white
		var a0 := mid + dir * gap
		var a1 := mid + dir * (gap + 11.0 * s)
		var arm := Rect2(Vector2(minf(a0.x, a1.x), minf(a0.y, a1.y)), Vector2(absf(a1.x - a0.x), absf(a1.y - a0.y)))
		arm = arm.grow_individual(0.0, 1.0 * s, 0.0, 1.0 * s) if dir.x != 0.0 else arm.grow_individual(1.0 * s, 0.0, 1.0 * s, 0.0)     # 2 px thick
		_rect(c, arm.grow(1.0 * s), Color(0, 0, 0, 0.5))
		_rect(c, arm, col)
	_sprite(c, &"disc", Rect2(mid - Vector2(1.6, 1.6) * s, Vector2(3.2, 3.2) * s), Color(1, 1, 1, 0.9))
	var since := now - UiUtil.num(p, &"last_hit_time", -100.0)
	if since < 0.18:
		var hc := Color(1.0, 0.3, 0.25, 0.95) if (p.get("last_hit_kill") == true or p.get("last_hit_crit") == true) else Color(1, 1, 1, 0.95)
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			c.draw_line(mid + d * 9.0 * s, mid + d * 17.0 * s, hc, 2.2 * s, false)


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
	c.draw_arc(vp * 0.5, 150.0 * s, ang - 0.22, ang + 0.22, 8, Color(1.0, 0.25, 0.2, 0.8 * alpha), 5.0 * s, true)    # a small arc toward the attacker


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
			_add(&"respawn", Rect2(cx - 170.0 * s, 560.0 * s, 340.0 * s, 64.0 * s), "RESPAWN", false)      # low on the screen: the middle stays free for the world
		&"win":
			_add(&"next", Rect2(cx - 170.0 * s, 560.0 * s, 340.0 * s, 64.0 * s), "NEXT SECTOR", false)


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
	_draw_screen_body(c, vp, s, font, cx)
	_flush_text()


func _draw_screen_body(c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var st := Game.state
	var ink := UiUtil.INK
	match st:
		&"menu":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.62))
		&"paused":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.7))
		&"dead":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.0, 0.02, DEAD_DIM * clampf(screen_age / 0.6, 0.0, 1.0)))      # a light dim fading in: the world stays visible
		&"win":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.06, 0.08, DEAD_DIM * clampf(screen_age / 0.6, 0.0, 1.0)))
	# thin horizontal frame lines
	var frame_col := Color(UiUtil.CYAN, 0.35)
	c.draw_line(Vector2(0.0, 74.0 * s), Vector2(vp.x, 74.0 * s), Color(frame_col, 0.12), 1.0 * s)
	c.draw_line(Vector2(0.0, vp.y - 74.0 * s), Vector2(vp.x, vp.y - 74.0 * s), Color(frame_col, 0.12), 1.0 * s)
	match st:
		&"menu":
			_text(c, font, Vector2(0.0, 196.0 * s), "QUANTUM TELEPORTAR", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(76.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
			c.draw_line(Vector2(cx - 240.0 * s, 222.0 * s), Vector2(cx + 240.0 * s, 222.0 * s), Color(UiUtil.MAGENTA, 0.8), 2.0 * s)
			_text(c, font, Vector2(0.0, 258.0 * s), "OBSERVER CORP INCURSION  //  SECTOR 01", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
			if is_instance_valid(Game.story) and Game.story.has_method(&"tagline"):
				_text(c, font, Vector2(0.0, 294.0 * s), str(Game.story.call(&"tagline")), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.85), 1.0 * s)
			_text(c, font, Vector2(0.0, 424.0 * s), "GRAPHICS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
			_footer(c, vp, s, font)
		&"paused":
			_text(c, font, Vector2(0.0, 190.0 * s), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(64.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
			_text(c, font, Vector2(0.0, 344.0 * s), "GRAPHICS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
			_footer(c, vp, s, font)
		&"dead":
			_text(c, font, Vector2(0.0, 170.0 * s), "DECOHERED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(84.0 * s), Color(UiUtil.RED, 0.97), 3.0 * s)
			_score_lines(c, vp, s, font, 226.0)
			var blink := 0.55 + 0.45 * sin(_t * 4.0) if screen_age >= LOCK else 0.25
			_text(c, font, Vector2(0.0, 664.0 * s), "TAP TO RESPAWN", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(24.0 * s), Color(1, 1, 1, blink))
		&"win":
			_text(c, font, Vector2(0.0, 170.0 * s), "SECTOR STABILIZED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(76.0 * s), Color(UiUtil.CYAN, 0.97), 3.0 * s)
			_score_lines(c, vp, s, font, 226.0)
			var blink2 := 0.55 + 0.45 * sin(_t * 4.0) if screen_age >= LOCK else 0.25
			_text(c, font, Vector2(0.0, 664.0 * s), "TAP TO CONTINUE", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(24.0 * s), Color(1, 1, 1, blink2))
	for b: Dictionary in buttons:
		var r: Rect2 = b["rect"]
		var big := r.size.y > 50.0 * s
		var on: bool = b["on"]
		var hot: bool = _hover == b["id"]
		var tint := UiUtil.MAGENTA if (big and b["id"] != &"next" and b["id"] != &"resume") else UiUtil.CYAN
		c.draw_rect(r, Color(tint, 0.30 if (on or hot) else 0.10))
		c.draw_rect(r, Color(tint, 0.95 if (on or hot or big) else 0.5), false, 2.0 * s if big else 1.5 * s)
		_text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + (10.0 if big else 7.0) * s), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int((30.0 if big else 20.0) * s), Color(1, 1, 1, 0.97 if (on or hot or big) else 0.75))


func _score_lines(c: Control, vp: Vector2, s: float, font: Font, y: float) -> void:
	_text(c, font, Vector2(0.0, y * s), "CREDITS  %d" % Game.score, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(30.0 * s), Color(1, 1, 1, 0.95), 1.5 * s)
	var line := "NEW BEST" if new_best else "BEST  %d" % settings.best
	_text(c, font, Vector2(0.0, (y + 36.0) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.AMBER, 0.95))


func _footer(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var line := CONTROLS_TOUCH if touch_ui_on() else CONTROLS_DESKTOP
	var size := int(18.0 * s)
	while size > int(12.0 * s) and _text_width(font, line, size) > vp.x - 40.0 * s:      # a wider fallback font must still fit the screen
		size -= 1
	_text(c, font, Vector2(0.0, vp.y - 40.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, Color(1, 1, 1, 0.75), 1.0 * s)
	if Game.state == &"menu":
		_text(c, font, Vector2(0.0, vp.y - 90.0 * s), "BEST  %d" % settings.best, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
