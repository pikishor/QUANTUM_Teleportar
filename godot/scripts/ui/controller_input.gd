class_name ControllerInput
extends Node
## Gamepad support (Bluetooth or wired, desktop and handhelds). Child "Pad" of the Hud. It polls the first connected joypad and
##  - in play: presses the same input actions the keyboard and the touch overlay drive (ControlMap.pad_binds, LB = the second layer), left stick = move (analog),
##    right stick = look (curve, look X / Y and ADS sensitivity, stronger AimAssist while it is used), triggers = fire / aim, START pauses, hold SWAP opens the weapon wheel;
##  - in menus: focus navigation (D-pad or left stick) over the Hud buttons with a visible focus ring, A presses, B goes back, LB / RB adjust a slider, START resumes;
##  - switches the UI by itself: the first pad input hides the touch overlay and shows the focus ring, a touch / key / mouse brings the touch overlay back;
##  - engine haptics while driving (UiSettings.buzz covers hits, hurt, explosions and abilities through GameFeel).
## `sim` (tests) replaces the device: set sim_buttons {JOY_BUTTON_x: true} / sim_axes {JOY_AXIS_x: v}.

signal scheme_changed(pad: bool)

const STICK_DEAD := 0.18
const LOOK_RATE := 3.4              ## rad/s at full deflection
const LOOK_CURVE := 1.7
const ADS_LOOK := 0.6
const WHEEL_HOLD := 0.4             ## seconds SWAP is held before the weapon wheel opens
const NAV_FIRST := 0.35
const NAV_REPEAT := 0.14
const STICK_AIM_HOLD := 0.5         ## seconds the stronger assist lasts after the right stick was last used
const ENGINE_PERIOD := 0.3
const PREFERRED: Array[StringName] = [&"continue", &"deploy", &"resume", &"respawn", &"next"]
const WATCHED: Array[int] = [
	JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_BACK, JOY_BUTTON_START,
]

static var pad_ui := false          ## the controller is the active scheme (touch overlay hidden, focus ring shown)
static var device := -1             ## the joypad in use, -1 none
static var stick_aim := false       ## the right stick aimed within the last STICK_AIM_HOLD seconds (AimAssist reads it)

var hud: Hud
var focus: StringName = &""
var sim := false
var sim_buttons := {}
var sim_axes := {}
var engine_rumbles := 0             ## engine haptic pulses issued (tests)
var looked := 0.0                   ## radians of yaw turned by the stick (tests)

var _btn := {}
var _prev := {}
var _axes := {}
var _down := {}                     ## action -> strength pressed by the pad
var _stick_t := 0.0
var _swap_held := 0.0
var _swap_on := false
var _swap_wheeled := false
var _swap_pulse := 0.0
var _nav_t := 0.0
var _nav_dir := Vector2.ZERO
var _eng_t := 0.0
var _focus_rect := Rect2()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = get_parent() as Hud
	var pads := Input.get_connected_joypads()
	device = pads[0] if not pads.is_empty() else -1
	Input.joy_connection_changed.connect(_on_joy)
	Game.state_changed.connect(func(_s: StringName) -> void:
		release_all()
		focus = &""
		_focus_rect = Rect2())


func _exit_tree() -> void:
	release_all()
	pad_ui = false
	stick_aim = false


func _on_joy(id: int, connected: bool) -> void:
	if connected:
		if device < 0:
			device = id
	elif id == device:
		var rest := Input.get_connected_joypads()
		rest.erase(id)
		device = rest[0] if not rest.is_empty() else -1
		if device < 0 and pad_ui:
			set_pad_ui(false)


## The scheme follows the last input: pad input turns the controller UI on, a touch, key or mouse turns it off.
func note_event(e: InputEvent) -> void:
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.5):
		device = e.device
		set_pad_ui(true)
	elif e is InputEventScreenTouch or e is InputEventKey or e is InputEventMouseButton or (e is InputEventMouseMotion and (e as InputEventMouseMotion).relative.length() > 3.0):
		set_pad_ui(false)


func set_pad_ui(on: bool) -> void:
	if on == pad_ui:
		return
	pad_ui = on
	if not on:
		release_all()
		stick_aim = false
	if hud != null:
		if hud.touch != null:
			hud.touch.set_pad_mode(on)
		hud._screen.queue_redraw()
	scheme_changed.emit(on)


func _input(e: InputEvent) -> void:
	if ControlsScreen.listening != &"" and e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and hud != null:
		if ControlsScreen.capture_key(hud.settings, int((e as InputEventKey).physical_keycode)):
			_after_capture()
			get_viewport().set_input_as_handled()
	note_event(e)


func _after_capture() -> void:
	hud.settings.publish(false)
	hud.settings.save()
	hud._layout_key = ""
	hud._screen.queue_redraw()


func release_all() -> void:
	for a: StringName in _down:
		Input.action_release(a)
	_down.clear()
	_swap_on = false
	_swap_held = 0.0
	_swap_wheeled = false
	if _swap_pulse > 0.0:
		_swap_pulse = 0.0
		Input.action_release(&"swap")


# ---------------------------------------------------------------------------------------------------------------------
# polling
# ---------------------------------------------------------------------------------------------------------------------

func _poll() -> void:
	_prev = _btn.duplicate()
	_btn = {}
	_axes = {}
	if sim:
		for b: Variant in sim_buttons:
			_btn[int(b)] = bool(sim_buttons[b])
		for a: Variant in sim_axes:
			_axes[int(a)] = float(sim_axes[a])
		return
	if device < 0:
		return
	for b: int in WATCHED:
		_btn[b] = Input.is_joy_button_pressed(device, b as JoyButton)
	for a: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		_axes[a] = Input.get_joy_axis(device, a as JoyAxis)


func _down_b(b: int) -> bool:
	return bool(_btn.get(b, false))


func _edge(b: int) -> bool:
	return bool(_btn.get(b, false)) and not bool(_prev.get(b, false))


func _ax(a: int) -> float:
	return float(_axes.get(a, 0.0))


func _any_activity() -> bool:
	for b: Variant in _btn:
		if bool(_btn[b]):
			return true
	for a: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		if absf(_ax(a)) > 0.5:
			return true
	return _ax(JOY_AXIS_TRIGGER_LEFT) > 0.5 or _ax(JOY_AXIS_TRIGGER_RIGHT) > 0.5


## Radial dead zone: the stick vector rescaled so the edge of the dead zone reads 0 and a full push 1.
static func dead_zone(v: Vector2, dead := STICK_DEAD) -> Vector2:
	var m := v.length()
	if m <= dead:
		return Vector2.ZERO
	return v / m * clampf((m - dead) / (1.0 - dead), 0.0, 1.0)


## Engine rumble strength (0..1) for a speed in m/s, 0 when vibration is off, under reduce-motion, or too slow to feel.
static func engine_rumble(speed: float) -> float:
	if not UiSettings.s_vibration or UiSettings.s_reduce_motion or absf(speed) < 2.0:
		return 0.0
	return clampf(absf(speed) / 45.0, 0.0, 1.0) * 0.35 * UiSettings.HAPTIC_SCALE[clampi(UiSettings.s_haptic, 0, 2)]


func _process(dt: float) -> void:
	if not sim and device < 0 and not pad_ui:
		_haptics(dt)
		return
	_poll()
	if _any_activity():
		set_pad_ui(true)
	if _stick_t > 0.0:
		_stick_t -= dt
		stick_aim = _stick_t > 0.0 and pad_ui
	if not pad_ui:
		stick_aim = false
		return
	if Game.state == &"play":
		_play(dt)
	else:
		_menu(dt)
	_haptics(dt)


# ---------------------------------------------------------------------------------------------------------------------
# play
# ---------------------------------------------------------------------------------------------------------------------

func _play(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.05)
	var slots := ControlMap.pressed_slots(_btn, _axes)
	var lb := _down_b(JOY_BUTTON_LEFT_SHOULDER)
	var want := ControlMap.actions_for(ControlMap.pad_binds, slots, 1 if lb else 0)
	var mv := dead_zone(Vector2(_ax(JOY_AXIS_LEFT_X), _ax(JOY_AXIS_LEFT_Y)))
	if mv.x > 0.0:
		want[&"move_right"] = mv.x
	elif mv.x < 0.0:
		want[&"move_left"] = -mv.x
	if mv.y > 0.0:
		want[&"move_back"] = mv.y
	elif mv.y < 0.0:
		want[&"move_forward"] = -mv.y
	# SWAP: a tap cycles the weapon, a hold opens the wheel (like the touch SWAP button)
	if want.has(&"swap"):
		want.erase(&"swap")
		_swap_on = true
		_swap_held += real_dt
		if _swap_held >= WHEEL_HOLD and not _swap_wheeled:
			_swap_wheeled = true
			if hud != null:
				hud.open_wheel()
			return
	elif _swap_on:
		if not _swap_wheeled and _swap_held < WHEEL_HOLD:
			Input.action_press(&"swap")
			_swap_pulse = 0.12
		_swap_on = false
		_swap_held = 0.0
		_swap_wheeled = false
	if _swap_pulse > 0.0:
		_swap_pulse -= real_dt
		if _swap_pulse <= 0.0:
			Input.action_release(&"swap")
	_apply(want)
	_look(real_dt)
	if _edge(JOY_BUTTON_START) and hud != null:
		if lb and hud.touch != null:
			hud.touch.open_map()
		else:
			hud.pause_game()


func _apply(want: Dictionary) -> void:
	for a: StringName in _down.keys():
		if not want.has(a):
			Input.action_release(a)
			_down.erase(a)
	for a: StringName in want:
		if InputMap.has_action(a) and not is_equal_approx(float(_down.get(a, -1.0)), float(want[a])):
			Input.action_press(a, float(want[a]))
			_down[a] = float(want[a])


func _look(dt: float) -> void:
	var v := dead_zone(Vector2(_ax(JOY_AXIS_RIGHT_X), _ax(JOY_AXIS_RIGHT_Y)))
	if v == Vector2.ZERO:
		return
	_stick_t = STICK_AIM_HOLD
	stick_aim = true
	var p: Player = Game.player if is_instance_valid(Game.player) else null
	if p == null or not is_instance_valid(p.camera_rig):
		return
	var mag := v.length()
	var dir := v / mag
	var curved := pow(mag, LOOK_CURVE)
	var k := LOOK_RATE * dt * (ADS_LOOK * UiSettings.s_ads if Input.is_action_pressed(&"aim") else 1.0)
	var dyaw := dir.x * curved * k * UiSettings.s_look_x
	var dpitch := dir.y * curved * k * UiSettings.s_look_y
	p.camera_rig.add_look(dyaw, dpitch)
	looked += absf(dyaw)


# ---------------------------------------------------------------------------------------------------------------------
# menus
# ---------------------------------------------------------------------------------------------------------------------

func _menu(dt: float) -> void:
	if hud == null:
		return
	if ControlsScreen.listening != &"" and ControlsScreen.tab == 1:
		var lb := _down_b(JOY_BUTTON_LEFT_SHOULDER)
		for n: String in ControlMap.pressed_slots(_btn, _axes):
			if bool(_prev.get(ControlMap.SLOTS[n][1], false)) and ControlMap.SLOTS[n][0] == "b":
				continue
			if ControlsScreen.capture_pad(hud.settings, ("1:" if lb else "0:") + n):
				_after_capture()
				return
		return
	ensure_focus()
	var dir := Vector2.ZERO
	if _edge(JOY_BUTTON_DPAD_UP):
		dir = Vector2.UP
	elif _edge(JOY_BUTTON_DPAD_DOWN):
		dir = Vector2.DOWN
	elif _edge(JOY_BUTTON_DPAD_LEFT):
		dir = Vector2.LEFT
	elif _edge(JOY_BUTTON_DPAD_RIGHT):
		dir = Vector2.RIGHT
	else:
		var st := Vector2(_ax(JOY_AXIS_LEFT_X), _ax(JOY_AXIS_LEFT_Y))
		if st.length() > 0.6:
			var d := Vector2(signf(st.x), 0.0) if absf(st.x) > absf(st.y) else Vector2(0.0, signf(st.y))
			if d != _nav_dir:
				_nav_dir = d
				_nav_t = NAV_FIRST
				dir = d
			else:
				_nav_t -= dt
				if _nav_t <= 0.0:
					_nav_t = NAV_REPEAT
					dir = d
		else:
			_nav_dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		move_focus(dir)
	if _edge(JOY_BUTTON_LEFT_SHOULDER):
		nudge(-1)
	if _edge(JOY_BUTTON_RIGHT_SHOULDER):
		nudge(1)
	if _edge(JOY_BUTTON_A):
		confirm()
	elif _edge(JOY_BUTTON_B):
		back()
	elif _edge(JOY_BUTTON_START):
		start()


func _buttons() -> Array:
	hud._ensure_layout()
	return hud.buttons


func _find(id: StringName) -> Dictionary:
	for b: Dictionary in _buttons():
		if b["id"] == id:
			return b
	return {}


func focus_visible() -> bool:
	return pad_ui and Game.state != &"play" and focus != &""


## Keeps the focus on a live button: after a screen change it goes to the primary button or the one nearest to where it was.
func ensure_focus() -> void:
	var bs := _buttons()
	if bs.is_empty():
		focus = &""
		return
	var cur := _find(focus) if focus != &"" else {}
	if not cur.is_empty():
		_focus_rect = cur["rect"]
		return
	var pick: Dictionary = {}
	if _focus_rect.size == Vector2.ZERO:
		for id: StringName in PREFERRED:
			pick = _find(id)
			if not pick.is_empty():
				break
	if pick.is_empty():
		var best := INF
		for b: Dictionary in bs:
			var d := ((b["rect"] as Rect2).get_center() - _focus_rect.get_center()).length() if _focus_rect.size != Vector2.ZERO else 0.0
			if d < best:
				best = d
				pick = b
	_set_focus(pick["id"])


func _set_focus(id: StringName) -> void:
	focus = id
	var b := _find(id)
	if not b.is_empty():
		_focus_rect = b["rect"]
	hud._screen.queue_redraw()


## Moves the focus to the nearest button in a direction (up / down / left / right). Returns true when it moved.
func move_focus(dir: Vector2) -> bool:
	var cur := _find(focus)
	if cur.is_empty():
		ensure_focus()
		return false
	var from: Vector2 = (cur["rect"] as Rect2).get_center()
	var best := INF
	var pick := &""
	for b: Dictionary in _buttons():
		if b["id"] == focus:
			continue
		var to: Vector2 = (b["rect"] as Rect2).get_center() - from
		var along := to.dot(dir)
		if along <= 4.0:
			continue
		var across := absf(to.dot(Vector2(-dir.y, dir.x)))
		if across > along * 1.6 + 40.0:
			continue
		var score := along + across * 2.0
		if score < best:
			best = score
			pick = b["id"]
	if pick == &"":
		return false
	_set_focus(pick)
	Sfx.play(&"ui_tap")
	return true


## LB / RB on a slider: one 10 % step.
func nudge(dir: int) -> bool:
	var b := _find(focus)
	if b.is_empty():
		return false
	var id: StringName = b["id"]
	var f := 0.0
	if Hud.SLIDERS.has(id):
		f = hud.volume_of(id)
	elif OptionsScreen.is_slider(id) and hud._options_open:
		f = OptionsScreen.fraction(hud.settings, id)
	else:
		return false
	f = clampf(f + 0.1 * dir, 0.0, 1.0)
	var r: Rect2 = b["rect"]
	var inset := minf(8.0, r.size.x * 0.05)
	hud._drag = id
	hud.slide(id, r.position.x + inset + (r.size.x - 2.0 * inset) * f)
	hud.end_drag()
	return true


## A on the focused button.
func confirm() -> bool:
	if Game.state == &"dead" or Game.state == &"win":
		if focus == &"" or _find(focus).is_empty():
			hud._confirm()
			return true
	if focus == &"" or _find(focus).is_empty():
		return false
	var ok := hud.press_button(focus)
	hud._layout_key = ""
	return ok


## B: the BACK button of the open screen, else RESUME from a pause screen.
func back() -> bool:
	for b: Dictionary in _buttons():
		var sid := String(b["id"])
		if sid.ends_with("back") or sid == "ctl_back" or sid == "photo_exit":
			Sfx.play(&"ui_back")
			var ok := hud.press_button(b["id"])
			hud._layout_key = ""
			return ok
	if Game.state == &"paused":
		hud.toggle_pause()
		return true
	return false


## START: resume from the pause screen, deploy / continue from the title.
func start() -> bool:
	if Game.state == &"paused":
		hud.toggle_pause()
		return true
	for id: StringName in PREFERRED:
		if not _find(id).is_empty():
			return hud.press_button(id)
	return false


# ---------------------------------------------------------------------------------------------------------------------
# haptics
# ---------------------------------------------------------------------------------------------------------------------

## Engine rumble while driving: a weak-motor pulse on the controller, a tiny tick on a handheld. Off under reduce-motion and with vibration off.
func _haptics(dt: float) -> void:
	if Game.state != &"play":
		return
	if not is_instance_valid(Game.player):
		_eng_t = 0.0
		return
	var p = Game.player
	if not (p is Player) or not is_instance_valid(p.vehicle):
		_eng_t = 0.0
		return
	_eng_t -= dt
	if _eng_t > 0.0:
		return
	_eng_t = ENGINE_PERIOD
	var amp := engine_rumble(float(p.vehicle.get(&"speed")))
	if amp <= 0.0:
		return
	engine_rumbles += 1
	if device >= 0:
		Input.start_joy_vibration(device, amp, 0.0, ENGINE_PERIOD + 0.05)
	elif DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(12, minf(amp, 0.5))
