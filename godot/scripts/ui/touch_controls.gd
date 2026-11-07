class_name TouchControls
extends CanvasLayer
## On-screen controls for phones (shown on touchscreens, or with --touch): a floating move stick (full push = sprint), a look drag (also from the FIRE
## finger), buttons FIRE / AIM / JUMP / RELOAD, the quantum powers BLINK / LINK / SUPER and USE (each only when its module exists), a pause button and a
## perf readout (FPS, draws, tris, texture memory; tap it to cycle the graphics tier). It only presses the input actions the keyboard drives and calls
## CameraRig.add_look, so the Player needs no changes. The HUD (scripts/ui/hud.gd) owns everything else on screen and instances this node as a child.

signal pause_requested
signal wheel_requested              ## kept for the controller path (Hud.open_wheel); the touch WEAPON button opens its own radial wheel

const LOOK_SENS := 0.003            ## radians per canvas pixel of finger travel
const STICK_RADIUS := 100.0         ## canvas px at the 720 px base height
const STICK_DEAD := 0.12
const SPRINT_AT := 0.94             ## pushing the stick this far means sprint
const BASE_H := 720.0
const USE_REACH := 4.2              ## metres: a vehicle this close enables USE
## Buttons: action, centre offset from the bottom-right corner and radius (canvas px at the base height), label, and what they need to be shown.
## Default frame (on foot): FIRE, AIM, JUMP, RELOAD, ABILITY (opens the radial wheel), WEAPON (tap cycles, hold opens the weapon wheel) and MORE (opens the secondary
## cluster). USE / GRAB / TAKEDOWN / SKIP / RADIO / GARAGE appear only when they apply; ALT, MELEE, THROW, CROUCH, GADGET, CALL CAR and the ally orders live in MORE.
const BUTTONS := [
	{"action": &"fire", "dx": 160.0, "dy": 170.0, "r": 88.0, "fs": 32, "label": "FIRE", "need": &""},
	{"action": &"aim", "dx": 170.0, "dy": 345.0, "r": 60.0, "label": "AIM", "need": &""},
	{"action": &"jump", "dx": 345.0, "dy": 130.0, "r": 66.0, "label": "JUMP", "need": &""},
	{"action": &"reload", "dx": 360.0, "dy": 295.0, "r": 54.0, "fs": 24, "label": "RELOAD", "need": &""},
	{"action": &"ability", "dx": 515.0, "dy": 120.0, "r": 58.0, "fs": 22, "label": "ABILITY", "need": &"quantum", "fn": &"wheel_ability"},
	{"action": &"swap", "dx": 520.0, "dy": 262.0, "r": 58.0, "fs": 22, "label": "WEAPON", "need": &"weapon"},
	{"action": &"more", "dx": 505.0, "dy": 395.0, "r": 40.0, "fs": 22, "label": "MORE", "need": &"foot", "fn": &"more"},
	{"action": &"altfire", "dx": 650.0, "dy": 100.0, "r": 40.0, "fs": 22, "label": "ALT", "need": &"more"},
	{"action": &"melee", "dx": 650.0, "dy": 212.0, "r": 46.0, "fs": 22, "label": "MELEE", "need": &"more"},
	{"action": &"throw_item", "dx": 650.0, "dy": 322.0, "r": 44.0, "fs": 20, "label": "THROW", "need": &"more"},
	{"action": &"crouch", "dx": 650.0, "dy": 434.0, "r": 46.0, "fs": 22, "label": "CROUCH", "need": &"more"},
	{"action": &"gadget", "dx": 650.0, "dy": 544.0, "r": 44.0, "fs": 20, "label": "GADGET", "need": &"more_gadget"},
	{"action": &"garage_call", "dx": 750.0, "dy": 110.0, "r": 46.0, "fs": 20, "label": "CALL CAR", "need": &"more_garage", "fn": &"summon"},
	{"action": &"charge_place", "dx": 750.0, "dy": 425.0, "r": 44.0, "fs": 22, "label": "C4", "need": &"more_c4"},
	{"action": &"detonate", "dx": 590.0, "dy": 650.0, "r": 50.0, "fs": 20, "label": "DETONATE", "need": &"detonate"},
	{"action": &"companion_hold", "dx": 750.0, "dy": 215.0, "r": 46.0, "fs": 22, "label": "HOLD", "need": &"more_companion", "fn": &"ally_hold"},
	{"action": &"companion_attack", "dx": 750.0, "dy": 320.0, "r": 46.0, "fs": 20, "label": "ATTACK", "need": &"more_companion", "fn": &"ally_attack"},
	{"action": &"interact", "dx": 175.0, "dy": 480.0, "r": 54.0, "label": "USE", "need": &"vehicle"},
	{"action": &"grab", "dx": 320.0, "dy": 470.0, "r": 50.0, "fs": 22, "label": "GRAB", "need": &"grab"},
	{"action": &"takedown", "dx": 175.0, "dy": 602.0, "r": 50.0, "fs": 20, "label": "TAKEDOWN", "need": &"takedown"},
	{"action": &"garage_open", "dx": 385.0, "dy": 580.0, "r": 46.0, "fs": 22, "label": "GARAGE", "need": &"garage_open", "fn": &"garage"},
	{"action": &"skip_piece", "dx": 505.0, "dy": 575.0, "r": 46.0, "fs": 16, "label": "SKIP SET PIECE", "need": &"skip_piece", "fn": &"skip"},
	{"action": &"radio_next", "dx": 270.0, "dy": 560.0, "r": 46.0, "fs": 22, "label": "RADIO", "need": &"radio", "call": true},
	{"action": &"veh_view", "dx": 520.0, "dy": 262.0, "r": 46.0, "fs": 22, "label": "VIEW", "need": &"driving"},     # driving camera: chase / far / hood
	{"action": &"look_back", "dx": 505.0, "dy": 395.0, "r": 46.0, "fs": 22, "label": "BACK", "need": &"driving"},       # held: look behind the car
]
## The ABILITY wheel: the seven quantum verbs, plain names. `ui` indexes UiUtil.ABILITIES (the four classic verbs), `verb` is a QuantumVerbs id.
const WHEEL_ABILITIES := [
	{"id": &"blink", "label": "QUANTUM TELEPORT", "ui": 0},
	{"id": &"superpose", "label": "SUPERPOSITION", "ui": 2},
	{"id": &"entangle", "label": "ENTANGLE", "ui": 1},
	{"id": &"collapse", "label": "COLLAPSE", "ui": 3},
	{"id": &"shield", "label": "PHASE SHIELD", "verb": &"shield"},
	{"id": &"slip", "label": "TIME SLIP", "verb": &"slip"},
	{"id": &"arc", "label": "ARC", "verb": &"arc"},
]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]
const TIER_NAMES: Array[String] = ["LOW", "MED", "HIGH"]
const LONG_PRESS := 0.6             ## seconds: holding the FPS box this long toggles the error panel (a short tap cycles the graphics tier)
const GRAB_SHOW := 9.0              ## metres: an enemy or a car this close in front shows GRAB
const GRAB_SHOW_PROP := 3.5
const PULSE := 0.14                ## seconds a wheel pick holds its action
const WHEEL_HOLD := 0.4             ## seconds SWAP is held before the wheel opens (a short tap cycles the weapon)
const ERROR_ROWS := 9               ## newest error lines shown in the panel

var more_open := false              ## the collapsed secondary cluster (ALT, MELEE, THROW, CROUCH, GADGET, CALL CAR, ally orders) is shown
var wheel := RadialWheel.new()      ## the ABILITY / WEAPON radial wheel
var controls_on := false            ## the touch controls are drawn and active
var touch_capable := false          ## the device has a touchscreen (controls_on while no controller is in use)
var perf_on := false                ## the perf readout is drawn (always with the controls, or with --perf)
var errors_on := false              ## the on-device error panel is shown (long-press the FPS box)
var perf_shown := false             ## the FPS readout is on screen: hidden by default, a long-press on its corner (under the minimap) shows it, long-press again opens the report panel, once more hides both

var _canvas: Control
var _last_state: StringName = &""
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_id := -1
var _held := {}                     ## finger index -> button dictionary
var _perf_text := ""
var _copied_t := 0.0                ## seconds the COPY REPORT button shows COPIED
var _perf_t := 0.0
var _win_t := 0.0
var _win_n := 0
var _win_worst := 0.0
var _avg_fps := 0.0
var _min_fps := 0.0
var _use_near := false
var _use_t := 0.0
var _swap_finger := -1              ## the finger on SWAP, or -1
var _swap_held := 0.0
var _swap_from := Vector2.ZERO
var _wheel_finger := -1             ## the finger dragging a wheel open from its button, or -1
var _wheel_held := 0.0
var _wheel_from_pos := Vector2.ZERO
var _wheel_moved := false
var _pulse_action: StringName = &""   ## the action a wheel pick holds pressed for PULSE seconds
var _pulse_t := 0.0
var _grab_near := false             ## something to GRAB is in front of the hero
var _grab_t := 0.0
var _swap_pulse := 0.0              ## seconds the swap action stays pressed after a tap
var _perf_finger := -1              ## the finger held on the FPS box, or -1
var _perf_held := 0.0
var _hot_finger := -1               ## the finger held on the hidden readout's corner (it still drives the stick or the look, the readout only listens)
var _hot_held := 0.0
var _hot_from := Vector2.ZERO
var _perf_long := false             ## the current press already toggled the panel (so its release does not cycle the tier)


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	controls_on = Game.force_touch or DisplayServer.is_touchscreen_available()
	touch_capable = controls_on
	perf_on = controls_on or OS.get_cmdline_user_args().has("--perf")
	perf_shown = OS.get_cmdline_user_args().has("--perf")
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_ui)
	Game.state_changed.connect(func(_s: StringName) -> void: release_all())
	var ms := MapScreen.new()                       # H3: tracks discovered cells even while closed; opened by a minimap tap or key M
	ms.name = "MapScreen"
	add_child(ms)
	set_process(controls_on or perf_on)


## A controller took over (true) or a finger / key came back (false): the touch overlay hides and shows itself (ControllerInput calls this).
func set_pad_mode(on: bool) -> void:
	controls_on = touch_capable and not on
	if on:
		release_all()
	if _canvas != null:
		_canvas.queue_redraw()


## A held finger never survives losing the app (no touch-up event comes): everything is let go when the app is paused or loses focus.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _exit_tree() -> void:
	release_all()


var _redraw_t := 0.0
var _fit_cache := {}                  ## button action -> [radius, scale, label, font size]: measuring a label is text shaping, it must not run for every button on every redraw


## The font size of a button label (fitted inside the disc), measured once per radius / scale / label.
func _label_size(b: Dictionary, font: Font, r: float, s: float) -> int:
	var label := _label_of(b)
	var e: Variant = _fit_cache.get(b["action"])
	if e != null and e[0] == r and e[1] == s and e[2] == label:
		return e[3]
	var fs := int(b.get("fs", 26))
	fs = mini(fs, int(UiUtil.fit_size(font, label, r * 2.0 - 6.0 * s, int(float(fs) * s)) / s))
	_fit_cache[b["action"]] = [r, s, label, fs]
	return fs


func _process(delta: float) -> void:
	if _swap_pulse > 0.0:
		_swap_pulse -= delta
		if _swap_pulse <= 0.0:
			Input.action_release(&"swap")
	if _swap_finger != -1:
		_swap_held += delta / maxf(Engine.time_scale, 0.05)
		if _swap_held >= WHEEL_HOLD:
			var f := _swap_finger
			_swap_finger = -1
			_open_wheel(&"weapon", f, _swap_from)
	if _wheel_finger != -1:
		_wheel_held += delta / maxf(Engine.time_scale, 0.05)
	if _pulse_t > 0.0:
		_pulse_t -= delta
		if _pulse_t <= 0.0 and _pulse_action != &"":
			Input.action_release(_pulse_action)
			_pulse_action = &""
	_grab_t -= delta
	if _grab_t <= 0.0:
		_grab_t = 0.25
		_grab_near = _grab_in_front()
	if _hot_finger != -1:
		_hot_held += delta / maxf(Engine.time_scale, 0.05)
		if _hot_held >= LONG_PRESS and not perf_shown and Game.state == &"play":
			_hot_finger = -1
			show_perf(true)
	if _perf_finger != -1 and not _perf_long:
		_perf_held += delta / maxf(Engine.time_scale, 0.05)
		if _perf_held >= LONG_PRESS:
			_perf_long = true
			var menu := get_tree().get_first_node_in_group(&"test_menu") if TestMode.available() else null
			if errors_on:
				errors_on = false                        # the panel is open: this press closes it and the readout
				show_perf(false)
			elif menu != null:
				menu.call(&"open")                       # test mode: the TEST MENU (it has the error panel switch); a release build keeps the error panel
			else:
				errors_on = true
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
	_copied_t = maxf(_copied_t - delta, 0.0)
	_perf_t -= delta
	if _perf_t <= 0.0:
		_perf_t = 0.5
		_refresh_perf()
	_use_t -= delta
	if _use_t <= 0.0:
		_use_t = 0.15
		_use_near = _vehicle_in_reach() or InteriorGameplay.prompt != ""
	_redraw_t -= delta
	if Game.state == &"play" or Game.state == &"paused" or _last_state == &"play" or _last_state == &"paused":
		if _redraw_t <= 0.0 or Game.state != _last_state:         # LOW redraws the touch layer 20 times a second, LOW+ 12; a state change always redraws
			_redraw_t = LowPlus.hud_interval()
			_canvas.queue_redraw()      # one extra redraw after leaving play, so the dead screen does not keep the dimmed buttons
	_last_state = Game.state


## Lets go of every action this layer pressed (state changes, exit, tests).
func release_all() -> void:
	_swap_finger = -1
	for a: StringName in MOVE_ACTIONS:
		Input.action_release(a)
	for b: Dictionary in BUTTONS:
		if not b.get("call", false) and not b.has("fn"):   # call and fn buttons (RADIO) press no action, and its action only exists once a radio does
			Input.action_release(b["action"])
	if _pulse_action != &"":
		Input.action_release(_pulse_action)
		_pulse_action = &""
	wheel.close()
	_wheel_finger = -1
	_swap_pulse = 0.0
	_held.clear()
	_stick_id = -1
	_look_id = -1
	_perf_finger = -1
	_perf_long = false
	_hot_finger = -1


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
	if not perf_visible() and perf_on and controls_on and Game.state == &"play" and _perf_box().has_point(pos):
		_hot_finger = id                                # hidden readout: a long hold here shows it (the press is NOT taken, the finger keeps playing)
		_hot_held = 0.0
		_hot_from = pos
	if perf_visible() and errors_on and _copy_rect().has_point(pos):
		var po := get_tree().get_first_node_in_group(&"perf_overlay")      # COPY REPORT (debug panel): the device report to the clipboard and user://perf_log.txt
		if po != null:
			_copied_t = 2.0
			(po as PerfOverlay).copy_report()
		return
	if perf_visible() and _perf_box().has_point(pos):
		_perf_finger = id                               # decided on release: a tap cycles the tier, a long press toggles the error panel
		_perf_held = 0.0
		_perf_long = false
		return
	if not controls_on or not Game.is_playing():
		return
	if wheel.is_open and wheel.sticky:                                 # a wheel a tap left open: a disc picks, anything else closes it (and is not a stick or look touch)
		var wi := wheel.hit(pos)
		if wi >= 0:
			_wheel_pick(wi)
		wheel.close()
		return
	if pos.distance_to(_pause_center()) <= 36.0 * _scale() * 1.3:
		pause_requested.emit()
		return
	var mm := _minimap_rect()
	if mm.has_point(pos):                                              # H3: a tap on the minimap opens the full map
		Sfx.play(&"ui_tap")
		open_map()
		return
	for b: Dictionary in BUTTONS:
		if button_visible(b) and pos.distance_to(_button_center(b)) <= maxf(float(b["r"]) * UiSettings.s_button_size, UiUtil.TOUCH_MIN * 0.5) * _scale() * 1.15:
			if b.get("fn", &"") == &"wheel_ability":                   # ABILITY: press opens the wheel, drag and release picks, a quick tap leaves it open
				_open_wheel(&"ability", id, pos)
				return
			if b.has("fn"):                                            # CALL CAR / GARAGE / MORE: one tap, no action press
				Sfx.play(&"ui_tap")
				if b["fn"] == &"skip":
					get_parent().call(&"skip_set_piece")
				elif b["fn"] == &"more":
					more_open = not more_open
				elif b["fn"] == &"ally_hold":
					Companion.current.command(&"hold")
				elif b["fn"] == &"ally_attack":
					Companion.current.command(&"attack")
				elif b["fn"] == &"summon":
					Game.vehicles.call(&"summon_any")        # the garage car, or a free quantum hover-bike while the garage is empty
				else:
					_open_garage()
				return
			if b.get("call", false):                                   # RADIO: one tap = Game.vehicles.radio.cycle() (no action press, so the key path cannot double-cycle)
				Game.vehicles.radio.cycle()
				Sfx.play(&"ui_tap")
				return
			if b["action"] == &"swap":                                 # a tap cycles (on release), a hold opens the wheel
				_swap_finger = id
				_swap_held = 0.0
				_swap_from = pos
				return
			_held[id] = b
			Input.action_press(b["action"])
			if b["action"] == &"interact":
				Sfx.play(&"ui_tap")                                    # USE (enter / exit a car) answers with a soft tap
			return
	var stick_side := pos.x > _vp_size().x * 0.58 if UiSettings.s_left_hand else pos.x < _vp_size().x * 0.42
	if stick_side and _stick_id == -1:
		_stick_id = id
		_stick_origin = pos
		_stick_pos = pos
	elif _look_id == -1:
		_look_id = id


func touch_move(id: int, pos: Vector2, rel: Vector2) -> void:
	if id == _hot_finger and pos.distance_to(_hot_from) > 48.0 * _scale():
		_hot_finger = -1                                # a stick drag or a look swipe is not a long press
	if id == _wheel_finger:
		wheel.sel = wheel.wedge(pos)
		if pos.distance_to(_wheel_from_pos) > 24.0 * _scale():
			_wheel_moved = true
		return
	if id == _stick_id:
		_stick_pos = pos
		_apply_stick()
	elif id == _look_id or (_held.has(id) and (_held[id] as Dictionary)["action"] == &"fire"):
		_look(rel)


func touch_up(id: int) -> void:
	if id == _hot_finger:
		_hot_finger = -1
	if id == _wheel_finger:
		_wheel_finger = -1
		if wheel.is_open:
			if wheel.kind == &"ability" and _wheel_held < RadialWheel.TAP_TIME and not _wheel_moved:
				wheel.sticky = true                                    # a tap: the wheel stays, the next tap picks
				wheel.sel = -1
			else:
				if wheel.sel >= 0:
					_wheel_pick(wheel.sel)
				wheel.close()
		return
	if id == _swap_finger:
		_swap_finger = -1
		Input.action_press(&"swap")
		_swap_pulse = 0.12
		return
	if id == _perf_finger:
		_perf_finger = -1
		if not _perf_long:
			Game.set_tier_index((Game.tier_index() + 1) % 4)
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
		var ak := lerpf(1.0, UiSettings.s_ads, clampf(float(rig.call("get_ads_amount")), 0.0, 1.0)) if rig.has_method("get_ads_amount") else 1.0
		rig.call("add_look", rel.x * LOOK_SENS * UiSettings.s_look_x * ak, rel.y * LOOK_SENS * UiSettings.s_look_y * ak)


# ---------------------------------------------------------------------------------------------------------------------
# which buttons exist
# ---------------------------------------------------------------------------------------------------------------------

## A button is shown only when what it needs exists: the quantum powers need `player.quantum`, USE needs the vehicle module and a car in reach (or being in one).
func button_visible(b: Dictionary) -> bool:
	match b["need"]:
		&"quantum":
			return is_instance_valid(Game.player) and Game.player.get("quantum") != null and not _driving()
		&"weapon":
			return is_instance_valid(Game.player) and not _driving()
		&"more":
			return more_open and is_instance_valid(Game.player) and not _driving()
		&"more_c4":
			return more_open and is_instance_valid(Game.player) and not _driving() and Charges.current != null
		&"detonate":
			return Charges.current != null and Charges.current.armed()
		&"more_gadget":
			return more_open and is_instance_valid(Game.player) and not _driving() and Gear.gadget != &""
		&"more_garage":
			return more_open and is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"summon_any") and not _driving() and not InteriorGameplay.active
		&"more_companion":
			return more_open and not _driving() and Companion.controllable()
		&"grab":
			return is_instance_valid(Game.player) and not _driving() and (_grab_near or _grab_held())
		&"vehicle":
			return is_instance_valid(Game.vehicles) and (_use_near or _driving())
		&"driving":
			return is_instance_valid(Game.vehicles) and _driving()
		&"foot":
			return is_instance_valid(Game.player) and not _driving()
		&"takedown":
			var pc: Object = Game.player.get("cover") if is_instance_valid(Game.player) else null
			return pc != null and pc.get("target") != null and is_instance_valid(pc.get("target"))
		&"garage_open":      # GARAGE: while driving
			return is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"get_garage") and _driving()
		&"skip_piece":       # SKIP SET PIECE: only inside an optional set piece
			var hud := get_parent()
			return hud != null and hud.has_method(&"skip_available") and bool(hud.call(&"skip_available"))
		&"radio":
			return is_instance_valid(Game.vehicles) and Game.vehicles.get("radio") != null and _driving()
	return true


## The label a button shows: USE reads ENTER on foot and EXIT in a car.
func _label_of(b: Dictionary) -> String:
	if b["action"] == &"interact":
		if not _driving() and InteriorGameplay.active and InteriorGameplay.prompt != "":
			return str(InteriorGameplay.prompt).split(" ")[0]         # inside a building the button says what it does: LEAVE, TALK, CRACK, FREE (not ENTER)
		return "EXIT" if _driving() else "ENTER"
	if b["action"] == &"skip_piece":
		var hud := get_parent()
		if hud != null and hud.has_method(&"step_skip_offered") and bool(hud.call(&"step_skip_offered")):
			return "SKIP STEP"
	return str(b["label"])


## True while the hero holds something (the GRAB button stays so it can be released).
func _grab_held() -> bool:
	var vb: Object = Game.player.get("verbs") if is_instance_valid(Game.player) else null
	return vb != null and vb.get("holding") == true


## Something the hero could GRAB is in front (polled 4 times a second: it scans the enemy, vehicle and prop groups).
func _grab_in_front() -> bool:
	if not controls_on or Game.state != &"play" or not is_instance_valid(Game.player) or _driving():
		return false
	var vb: Object = Game.player.get("verbs")
	if vb == null or not vb.has_method(&"find_target"):
		return false
	var t: Dictionary = vb.call(&"find_target")
	if t.is_empty():
		return false
	var d := ((t["pos"] as Vector3) - (Game.player as Node3D).global_position).length()
	return d <= (GRAB_SHOW if t["kind"] != &"prop" else GRAB_SHOW_PROP)           # a prop has to be close: the button must not sit on screen all the time


## Opens the radial wheel for `kind` while `finger` holds its button at `pos`.
func _open_wheel(kind: StringName, finger: int, pos: Vector2) -> void:
	var vp := _vp_size()
	var at := Vector2(vp.x * (0.38 if UiSettings.s_left_hand else 0.62), vp.y * 0.56)
	wheel.open_at(kind, wheel_items(kind), at, _scale(), false)
	_wheel_finger = finger if wheel.is_open else -1
	_wheel_held = 0.0
	_wheel_moved = false
	_wheel_from_pos = pos
	Sfx.play(&"ui_tap")
	_canvas.queue_redraw()


## The discs of a wheel: {id, label, ready, active, cd, current}.
func wheel_items(kind: StringName) -> Array:
	var out: Array = []
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	if p == null:
		return out
	if kind == &"weapon":
		return WeaponWheel.items()
	var qv: Object = p.get("qverbs")
	for d: Dictionary in WHEEL_ABILITIES:
		var st := {"ready": true, "active": false, "cd": 0.0}
		if d.has("ui"):
			if p.get("quantum") == null:
				continue
			st = UiUtil.ability_state(p, UiUtil.ABILITIES[int(d["ui"])])
		else:
			if qv == null:
				continue
			st = (qv as QuantumVerbs).ui_state(d["verb"])
		out.append({"id": d["id"], "label": d["label"], "ready": bool(st["ready"]), "active": bool(st["active"]), "cd": float(st["cd"]), "current": false})
	return out


## A wheel pick: an ability holds its action for a moment (the same press the key makes), a weapon switches at once.
func _wheel_pick(i: int) -> void:
	var id := wheel.item_id(i)
	if id == &"":
		return
	if wheel.kind == &"weapon":
		var p: Node = Game.player if is_instance_valid(Game.player) else null
		if p != null and p.get("weapon") is PlayerWeapon:
			WeaponWheel.pick(id, p.get("weapon") as PlayerWeapon)
	else:
		if _pulse_action != &"":
			Input.action_release(_pulse_action)
		Input.action_press(id)
		_pulse_action = id
		_pulse_t = PULSE
	Sfx.play(&"ui_tap")


## The WEAPON button face: the weapon's silhouette and "30 / 30" (reload shows RELOADING) instead of a text label.
func _weapon_face(c: Control, font: Font, centre: Vector2, r: float, s: float, labels: Array) -> void:
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	if p == null or not (p.get("weapon") is PlayerWeapon):
		return
	var hud := get_parent()
	var ammo := str(hud.call(&"ammo_text")) if hud != null and hud.has_method(&"ammo_text") else ""
	if ammo == "RELOADING":
		ammo = "..."
	WeaponIcons.draw(c, (p.get("weapon") as PlayerWeapon).current, Rect2(centre.x - r * 0.8, centre.y - r * 0.78, r * 1.6, r * 0.8), Color(UiUtil.CYAN, 0.95))
	labels.append([centre + Vector2(-r, r * 0.62), ammo, r * 2.0, 1.0, int(18.0)])


## The radial wheel: a faint disc behind, one button sprite per item (name or weapon silhouette), the picked wedge bright.
func _draw_wheel(c: Control, font: Font, s: float) -> void:
	var n := wheel.items.size()
	c.draw_texture_rect(UiUtil.sprite(&"disc"), Rect2(wheel.centre - Vector2.ONE * (RadialWheel.RADIUS + RadialWheel.ITEM_R + 14.0) * s, Vector2.ONE * (RadialWheel.RADIUS + RadialWheel.ITEM_R + 14.0) * s * 2.0), false, Color(0, 0.02, 0.04, 0.45))
	var r := RadialWheel.ITEM_R * s
	var texts: Array = []
	for i in n:
		var it: Dictionary = wheel.items[i]
		var ic := wheel.item_centre(i)
		var tint := UiUtil.CYAN
		var dim := 1.0
		if bool(it["active"]) or i == wheel.sel:
			tint = UiUtil.AMBER
		elif not bool(it["ready"]):
			dim = 0.45
		if i == wheel.sel:
			c.draw_texture_rect(UiUtil.sprite(&"disc"), Rect2(ic - Vector2.ONE * r * 1.12, Vector2.ONE * r * 2.24), false, Color(tint, 0.35))
		c.draw_texture_rect(UiUtil.sprite(&"button"), Rect2(ic - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(tint, 0.95 * dim))
		if float(it["cd"]) > 0.0:
			c.draw_arc(ic, r + 4.0 * s, -PI * 0.5, -PI * 0.5 + TAU * float(it["cd"]), 28, Color(tint, 0.9), 3.0 * s, false)
		if wheel.kind == &"weapon":
			WeaponIcons.draw(c, StringName(it.get("icon", it["id"])), Rect2(ic.x - r * 0.8, ic.y - r * 0.62, r * 1.6, r * 0.8), Color(tint, 0.95))
			texts.append([ic + Vector2(-r, r * 0.62), str(it["label"]), r * 2.0, 20.0, dim])
		else:
			var words := str(it["label"]).split(" ")
			var fsz := 18.0
			for w: String in words:
				fsz = minf(fsz, float(UiUtil.fit_size(font, w, r * 2.0 - 10.0 * s, int(18.0 * s))) / s)
			var y0 := ic.y + fsz * s * 0.34 - (float(words.size() - 1) * fsz * s * 0.55)
			for k in words.size():
				texts.append([Vector2(ic.x - r, y0 + float(k) * fsz * s * 1.1), words[k], r * 2.0, fsz, dim])
	for t: Array in texts:
		c.draw_string(font, (t[0] as Vector2) + Vector2(1.2, 1.2) * s, t[1], HORIZONTAL_ALIGNMENT_CENTER, t[2], int(float(t[3]) * s), Color(0, 0, 0, 0.8 * float(t[4])))
		c.draw_string(font, t[0], t[1], HORIZONTAL_ALIGNMENT_CENTER, t[2], int(float(t[3]) * s), Color(1, 1, 1, 0.97 * float(t[4])))


## The touch controls on screen right now: the stick, every visible button (by action) and the pause button. Empty unless the controls are on and the game is playing.
func visible_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if not controls_on or Game.state != &"play":
		return out
	out.append(&"stick")
	for b: Dictionary in BUTTONS:
		if button_visible(b):
			out.append(b["action"])
	out.append(&"pause")
	return out


func _minimap_rect() -> Rect2:
	var vp := _vp_size()
	var s := _scale()
	return Rect2(Vector2(UiUtil.insets(vp).x + 16.0 * s, 14.0 * s + UiUtil.insets_v(vp).x), Vector2(Hud.MINIMAP, Hud.MINIMAP) * s)


func open_map() -> void:
	var ms := get_node_or_null("MapScreen") as MapScreen
	if ms == null:
		ms = MapScreen.new()
		ms.name = "MapScreen"
		add_child(ms)
	ms.open()


func _open_garage() -> void:
	var gs := get_node_or_null("GarageScreen") as GarageScreen
	if gs == null:
		gs = GarageScreen.new()
		gs.name = "GarageScreen"
		add_child(gs)
	gs.open()


func _driving() -> bool:
	return is_instance_valid(Game.player) and Game.player.get("vehicle") != null


func _vehicle_in_reach() -> bool:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player) or not Game.vehicles.has_method(&"nearest"):
		return false
	if Game.vehicles.has_method(&"reach_car"):
		return Game.vehicles.call(&"reach_car", Game.player.global_position) != null
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
	var x := _vp_size().x - _insets().y - float(b["dx"]) * s
	if UiSettings.s_left_hand:
		x = _insets().x + float(b["dx"]) * s
	return Vector2(x, _vp_size().y - UiUtil.insets_v(_vp_size()).y - float(b["dy"]) * s)


func _pause_center() -> Vector2:
	var s := _scale()
	return Vector2(_vp_size().x - _insets().y - 52.0 * s, 112.0 * s + UiUtil.insets_v(_vp_size()).x)     # the right edge under the heat stars: the faction / wanted plate used to sit on the old spot (director review)


## The perf readout sits under the minimap and is only shown while playing or paused.
func perf_visible() -> bool:
	return perf_on and perf_shown and (Game.state == &"play" or Game.state == &"paused")


## Shows or hides the FPS readout (and with it the renderer's CPU / GPU frame timing, which costs a little).
func show_perf(on: bool) -> void:
	perf_shown = on
	if not on:
		errors_on = false
	var po := get_tree().get_first_node_in_group(&"perf_overlay") if is_inside_tree() else null
	if po != null:
		(po as PerfOverlay).set_measure(on)
	_perf_t = 0.0
	if _canvas != null:
		_canvas.queue_redraw()


func _perf_box() -> Rect2:
	var s := _scale()
	return Rect2(Vector2(16.0 * s + _insets().x, 168.0 * s + UiUtil.insets_v(_vp_size()).x), Vector2(360.0, 90.0) * s)


func _refresh_perf() -> void:
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var tex_mb := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576
	_perf_text = "FPS %d  (avg %d  worst %d)\nDraws %d   Tris %dk   Tex %d MB\nTier %s - tap to change\n%s" % [
		roundi(Engine.get_frames_per_second()), roundi(_avg_fps), roundi(_min_fps), draws, prims / 1000, tex_mb, PerfOverlay.tier_label(), PerfTimers.top_line()]


# ---------------------------------------------------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------------------------------------------------

func _draw_ui() -> void:
	var t0 := PerfTimers.start()
	_draw_ui_body()
	PerfTimers.stop(PerfTimers.TOUCH, t0)


func _draw_ui_body() -> void:
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
		_draw_report(c, font, s)
	if not controls_on or Game.state != &"play":
		return
	# move stick: a hint ring while idle, base and thumb while a finger is down
	if _stick_id == -1:
		c.draw_arc(Vector2(size.x - 190 * s - _insets().y if UiSettings.s_left_hand else 190 * s + _insets().x, size.y - 170 * s - UiUtil.insets_v(size).y), STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.16), 2.0 * s, false)
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
		var r := float(b["r"]) * s * UiSettings.s_button_size
		var on := down.has(b["action"])
		var tint := UiUtil.CYAN
		var dim := 1.0
		if b["action"] == &"more":
			tint = UiUtil.AMBER if more_open else UiUtil.CYAN
		if b["action"] == &"ability":
			tint = UiUtil.AMBER if (wheel.is_open and wheel.kind == &"ability") else UiUtil.CYAN
		if b.has("verb"):
			var vs := ((Game.player.get("qverbs") as QuantumVerbs).ui_state(b["verb"]) as Dictionary) if Game.player.get("qverbs") != null else {"active": false, "ready": true, "cd": 0.0}
			if vs["active"]:
				tint = UiUtil.AMBER
			elif not vs["ready"]:
				dim = 0.45
			if float(vs["cd"]) > 0.0:
				arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * float(vs["cd"]), Color(tint, 0.9)])
		if b.has("ability"):
			var st := UiUtil.ability_state(Game.player, UiUtil.ABILITIES[int(b["ability"])])
			if st["active"]:
				tint = UiUtil.AMBER
			elif not st["ready"]:
				dim = 0.45
			if float(st["cd"]) > 0.0:
				arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * float(st["cd"]), Color(tint, 0.9)])
		if b["action"] == &"companion_hold" and Companion.current != null and Companion.current.mode == Companion.Mode.HOLD:
			tint = UiUtil.AMBER
			on = true
		elif b["action"] == &"companion_attack" and Companion.current != null and Companion.current.mode == Companion.Mode.ATTACK:
			tint = UiUtil.AMBER
			on = true
		if on:
			glows.append([Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), Color(tint, 0.35)])
		sprites.append([Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), Color(tint, (1.0 if on else 0.85) * dim)])
		var fs := _label_size(b, font, r, s)
		if b["action"] == &"swap":                      # WEAPON: the weapon's silhouette over the ammo count (no separate ammo plate)
			_weapon_face(c, font, centre, r, s, labels)
			continue
		labels.append([centre + Vector2(-r, float(fs) * 0.36 * s), _label_of(b), r * 2.0, dim, fs])
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
	if wheel.is_open:
		_draw_wheel(c, font, s)
	# pause
	var pc := _pause_center()
	var pr := 36.0 * s
	c.draw_arc(pc, pr, 0.0, TAU, 28, Color(1, 1, 1, 0.45), 2.0 * s, false)
	c.draw_rect(Rect2(pc + Vector2(-8, -10) * s, Vector2(5, 20) * s), Color(1, 1, 1, 0.8))
	c.draw_rect(Rect2(pc + Vector2(3, -10) * s, Vector2(5, 20) * s), Color(1, 1, 1, 0.8))


func _report_rect() -> Rect2:
	var box := _perf_box()
	var s := _scale()
	var top := box.end.y + 6.0 * s + (ERROR_ROWS * 15.0 + 22.0) * s + 6.0 * s
	return Rect2(Vector2(box.position.x, top), Vector2(minf(_vp_size().x - box.position.x - 12.0 * s, 620.0 * s), 150.0 * s))


func _copy_rect() -> Rect2:
	var r := _report_rect()
	var s := _scale()
	return Rect2(r.position + Vector2(r.size.x - 204.0 * s, 4.0 * s), Vector2(200.0, 64.0) * s)      # a 64 px touch target


## Debug panel part two: the live device report (same text the COPY REPORT button sends) and the button.
func _draw_report(c: Control, font: Font, s: float) -> void:
	var po := get_tree().get_first_node_in_group(&"perf_overlay")
	if po == null:
		return
	var r := _report_rect()
	c.draw_rect(r, Color(0.0, 0.04, 0.06, 0.7))
	c.draw_rect(r, Color(0.4, 0.9, 1.0, 0.6), false, 1.0 * s)
	var cr := _copy_rect()
	c.draw_rect(cr, Color(0.1, 0.35, 0.45, 0.9))
	c.draw_string(font, cr.position + Vector2(12, 42) * s, "COPIED" if _copied_t > 0.0 else "SEND REPORT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(18.0 * s), Color(1, 1, 1, 0.95))
	var lines := (po as PerfOverlay).report().split("\n")
	for i in range(1, mini(lines.size(), 9)):
		c.draw_string(font, r.position + Vector2(6.0, 14.0 + (i - 1) * 16.0 + (30.0 if i > 5 else 0.0)) * s, lines[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12.0 * s, int(10.0 * s), Color(0.85, 1, 0.95, 0.95))


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
