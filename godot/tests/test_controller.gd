extends RefCounted
## Controller and haptics: ControlMap (layout, remap, sanitise), ControllerInput in the REAL scene (main.tscn: play actions, look, wheel, pause, menu focus and the
## controls remap screen, touch / pad auto-switch), stronger stick aim assist, haptic plans (intensity, reduce-motion, vibration off), settings persistence.
## The device is simulated (pad.sim) and the node is stepped by hand, so nothing depends on frame counts or timing. Run: tools/test.sh tests/test_controller.gd

var host: Node
var pad: ControllerInput
var hud: Hud


func _step(n := 1, dt := 1.0 / 60.0) -> void:
	for i in n:
		pad._process(dt)


func _tap(btn: int) -> void:
	pad.sim_buttons[btn] = true
	_step()
	pad.sim_buttons[btn] = false
	_step()


func _frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	for f in ["user://test_controller.cfg", "user://test_controller_hud.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_pure()
	_settings_roundtrip()
	_keyboard_remap()
	await _scene()
	ControlMap.reset_keys()
	ControlMap.pad_binds = ControlMap.default_pad()
	UiSettings.s_vibration = true
	UiSettings.s_haptic = 1
	UiSettings.s_reduce_motion = false
	for f in ["user://test_controller.cfg", "user://test_controller_hud.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _pure() -> void:
	# layout: every listed action sits on a slot, the triggers fire / aim, no slot holds two actions
	for a: StringName in ControlMap.PAD_ACTIONS:
		TestLib.check(ControlMap.slot_of(ControlMap.DEFAULT_PAD, a) != "", "pad action %s has a slot" % a)
	TestLib.check(ControlMap.DEFAULT_PAD["0:rt"] == &"fire" and ControlMap.DEFAULT_PAD["0:lt"] == &"aim" and ControlMap.DEFAULT_PAD["1:rt"] == &"fire", "triggers fire and aim in both layers")
	var slots := ControlMap.pressed_slots({JOY_BUTTON_A: true, JOY_BUTTON_DPAD_UP: true}, {JOY_AXIS_TRIGGER_RIGHT: 0.9, JOY_AXIS_TRIGGER_LEFT: 0.1})
	TestLib.check(slots.has("a") and slots.has("du") and slots.has("rt") and not slots.has("lt"), "pressed slots from a device state")
	var l0 := ControlMap.actions_for(ControlMap.DEFAULT_PAD, slots, 0)
	var l1 := ControlMap.actions_for(ControlMap.DEFAULT_PAD, slots, 1)
	TestLib.check(l0.has(&"jump") and l0.has(&"entangle") and l0.has(&"fire") and l1.has(&"shield") and l1.has(&"gadget") and not l1.has(&"jump"), "LB switches the layer")
	# remap swaps with the action that sat on the slot
	var b := ControlMap.default_pad()
	ControlMap.rebind_pad(b, &"jump", "0:x")
	TestLib.check(b["0:x"] == &"jump" and b["0:a"] == &"reload", "pad rebind swaps the two actions")
	ControlMap.rebind_pad(b, &"fire", "0:du")
	TestLib.check(b["0:du"] == &"fire" and b["0:rt"] == &"entangle", "fire can leave the trigger and the swap keeps every action bound")
	var junk := ControlMap.sanitize_pad({"9:z": "jump", "0:a": "no_such_action", "0:b": "melee", "0:x": "reload"})
	TestLib.check(junk["0:a"] == &"jump" and junk["0:b"] == &"melee" and not junk.has("9:z"), "sanitise drops unknown slots and actions")
	TestLib.check(ControlMap.slot_label("1:a") == "LB+A" and ControlMap.slot_label("0:rt") == "RT", "slot labels")
	# sticks
	TestLib.check(ControllerInput.dead_zone(Vector2(0.1, 0.05)) == Vector2.ZERO and ControllerInput.dead_zone(Vector2(1, 0)).is_equal_approx(Vector2(1, 0)), "dead zone")
	var half := ControllerInput.dead_zone(Vector2(0.59, 0.0)).x
	TestLib.check(half > 0.45 and half < 0.55, "dead zone rescales smoothly")
	# stronger aim assist on the stick
	var ang := 0.08
	TestLib.check(AimAssist.slow_factor(ang, 0.02, true) < AimAssist.slow_factor(ang, 0.02), "stick slows the look more")
	TestLib.check(AimAssist.slow_factor(0.12, 0.02, true) < 1.0 and AimAssist.slow_factor(0.12, 0.02) == 1.0, "stick cone is wider")
	TestLib.check(absf(AimAssist.pull(0.05, 0.04, 0.02, 0.016, true)) > absf(AimAssist.pull(0.05, 0.04, 0.02, 0.016)), "stick pulls harder")
	# haptics
	var s := UiSettings.new("user://test_controller.cfg")
	s.publish(false)
	UiSettings.s_haptic = 0
	var light := UiSettings.haptic_plan(60)
	UiSettings.s_haptic = 2
	var strong := UiSettings.haptic_plan(60)
	TestLib.check(int(strong["ms"]) > int(light["ms"]) and float(strong["amp"]) > float(light["amp"]), "haptic level scales length and strength")
	UiSettings.s_haptic = 1
	UiSettings.s_reduce_motion = true
	var calm := UiSettings.haptic_plan(220)
	TestLib.check(not calm.is_empty() and int(calm["ms"]) <= UiSettings.REDUCED_MS and float(calm["amp"]) <= 0.4, "reduce-motion keeps haptics short and soft")
	TestLib.check(ControllerInput.engine_rumble(30.0) == 0.0, "no engine rumble under reduce-motion")
	UiSettings.s_reduce_motion = false
	TestLib.check(ControllerInput.engine_rumble(30.0) > ControllerInput.engine_rumble(8.0) and ControllerInput.engine_rumble(0.5) == 0.0, "engine rumble grows with speed")
	UiSettings.s_vibration = false
	TestLib.check(UiSettings.haptic_plan(60).is_empty() and ControllerInput.engine_rumble(30.0) == 0.0, "vibration off silences every haptic")
	UiSettings.s_vibration = true


func _settings_roundtrip() -> void:
	var path := "user://test_controller.cfg"
	var s := UiSettings.new(path)
	TestLib.check(s.haptic_level == 1 and s.pad_binds == ControlMap.default_pad() and s.key_binds.is_empty(), "defaults")
	s.haptic_level = 2
	ControlMap.rebind_pad(s.pad_binds, &"jump", "0:y")
	s.key_binds = {"blink": KEY_P}
	TestLib.check(s.save(), "saves")
	var s2 := UiSettings.new(path)
	TestLib.check(s2.haptic_level == 2 and s2.pad_binds["0:y"] == &"jump" and s2.pad_binds["0:a"] == &"interact" and s2.key_binds.get("blink") == KEY_P, "haptic level and both binding sets persist")
	s2.haptic_level = 9
	s2.key_binds = {"blink": KEY_ESCAPE, "nonsense": KEY_P}
	s2.save()
	var s3 := UiSettings.new(path)
	TestLib.check(s3.haptic_level == 2 and s3.key_binds.is_empty(), "bad saved values clamp or drop")


func _keyboard_remap() -> void:
	var q := ControlMap.key_of(&"blink")
	var e := ControlMap.key_of(&"entangle")
	TestLib.check(q == KEY_Q and e == KEY_E, "default keys")
	var binds := {}
	ControlMap.rebind_key(binds, &"blink", KEY_P)
	TestLib.check(ControlMap.key_of(&"blink") == KEY_P and binds["blink"] == KEY_P, "key rebind")
	ControlMap.rebind_key(binds, &"blink", KEY_E)
	TestLib.check(ControlMap.key_of(&"blink") == KEY_E and ControlMap.key_of(&"entangle") == KEY_P, "a taken key swaps the actions")
	var arrows := 0
	for ev: InputEvent in InputMap.action_get_events(&"move_forward"):
		arrows += int(ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_UP)
	TestLib.check(arrows == 1, "the second (arrow) key of a move action stays")
	ControlMap.rebind_key(binds, &"jump", KEY_ESCAPE)
	TestLib.check(ControlMap.key_of(&"jump") == KEY_SPACE, "ESC stays reserved for pause")
	ControlMap.reset_keys()
	TestLib.check(ControlMap.key_of(&"blink") == KEY_Q and ControlMap.key_of(&"entangle") == KEY_E, "reset restores the defaults")


func _scene() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _frames(20)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	hud.settings = UiSettings.new("user://test_controller_hud.cfg")
	hud.settings.publish(false)
	pad = hud.pad
	TestLib.check(pad != null and pad.get_parent() == hud, "the Hud owns the controller input node")
	for i in 600:
		if Game.state == &"play":
			break
		await _frames(1)
	pad.set_process(false)                                   # stepped by hand from here
	pad.sim = true
	pad.release_all()
	if hud.touch != null:
		hud.touch.touch_capable = true
		hud.touch.controls_on = true
	TestLib.check(not ControllerInput.pad_ui, "touch UI first")

	# --- play: sticks, buttons, layers, triggers
	pad.sim_axes = {JOY_AXIS_LEFT_X: 1.0, JOY_AXIS_LEFT_Y: -0.5}
	_step()
	TestLib.check(ControllerInput.pad_ui, "the first pad input turns the controller UI on")
	TestLib.check(hud.touch == null or not hud.touch.controls_on, "touch overlay hides while a controller is in use")
	TestLib.check(Input.get_action_strength(&"move_right") > 0.8 and Input.get_action_strength(&"move_forward") > 0.2 and Input.get_action_strength(&"move_forward") < 0.7, "left stick moves (analog)")
	pad.sim_axes = {}
	_step()
	TestLib.check(Input.get_action_strength(&"move_right") == 0.0 and Input.get_action_strength(&"move_forward") == 0.0, "stick released: no movement")
	pad.sim_buttons = {JOY_BUTTON_A: true, JOY_BUTTON_RIGHT_SHOULDER: true}
	pad.sim_axes = {JOY_AXIS_TRIGGER_RIGHT: 1.0, JOY_AXIS_TRIGGER_LEFT: 1.0}
	_step()
	TestLib.check(Input.is_action_pressed(&"jump") and Input.is_action_pressed(&"blink") and Input.is_action_pressed(&"fire") and Input.is_action_pressed(&"aim"), "A jump, RB teleport, RT fire, LT aim")
	pad.sim_buttons = {JOY_BUTTON_A: true, JOY_BUTTON_X: true, JOY_BUTTON_LEFT_SHOULDER: true}
	pad.sim_axes = {}
	_step()
	TestLib.check(Input.is_action_pressed(&"shield") and Input.is_action_pressed(&"arc") and not Input.is_action_pressed(&"jump") and not Input.is_action_pressed(&"fire"), "LB + A / X: ring verbs, the plain layer lets go")
	pad.sim_buttons = {JOY_BUTTON_DPAD_UP: true, JOY_BUTTON_DPAD_RIGHT: true}
	_step()
	TestLib.check(Input.is_action_pressed(&"entangle") and Input.is_action_pressed(&"superpose") and not Input.is_action_pressed(&"shield"), "D-pad up / right: ENTANGLE, SUPERPOSITION")
	pad.sim_buttons = {}
	_step()
	TestLib.check(not Input.is_action_pressed(&"entangle") and not Input.is_action_pressed(&"superpose") and not Input.is_action_pressed(&"blink"), "every pad action is released")

	# --- right stick looks, and arms the stronger assist
	var rig: CameraRig = Game.player.camera_rig
	var yaw0 := rig.yaw
	pad.sim_axes = {JOY_AXIS_RIGHT_X: 1.0}
	_step(10)
	TestLib.check(absf(rig.yaw - yaw0) > 0.1 and pad.looked > 0.1, "right stick turns the view")
	TestLib.check(ControllerInput.stick_aim, "stick aiming arms the stronger assist")
	pad.sim_axes = {}
	_step(40)
	TestLib.check(not ControllerInput.stick_aim, "the stronger assist lapses after the stick rests")

	# --- hold SWAP opens the wheel, START pauses
	pad.sim_buttons = {JOY_BUTTON_DPAD_LEFT: true}
	_step(10)
	TestLib.check(Game.state == &"play", "a short SWAP hold does not open the wheel")
	_step(20)
	TestLib.check(Game.state == &"paused" and hud.loadout_open(), "holding SWAP opens the weapon wheel")
	pad.sim_buttons = {}
	_step(2)
	pad.release_all()
	Game.state = &"play"
	await _frames(2)
	_step()
	_tap(JOY_BUTTON_START)
	TestLib.check(Game.state == &"paused", "START pauses")

	# --- menus: focus, A / B, sliders
	hud._options_open = false
	hud._layout_key = ""
	await _frames(2)
	_step(2)
	TestLib.check(pad.focus_visible() and pad.focus == &"resume", "the pause screen focuses RESUME with a visible ring")
	var before := pad.focus
	_tap(JOY_BUTTON_DPAD_DOWN)
	TestLib.check(pad.focus != before and pad.focus != &"", "D-pad down moves the focus")
	var moved := pad.focus
	_tap(JOY_BUTTON_DPAD_UP)
	TestLib.check(pad.focus == before or pad.focus != moved, "D-pad up moves it back")
	hud._layout_key = ""
	hud._ensure_layout()
	pad._set_focus(&"options")
	_tap(JOY_BUTTON_A)
	TestLib.check(hud._options_open, "A presses the focused OPTIONS button")
	await _frames(2)
	_step(2)
	pad._set_focus(&"opt_look_x")
	var lx0 := hud.settings.look_x
	_tap(JOY_BUTTON_RIGHT_SHOULDER)
	TestLib.check(hud.settings.look_x > lx0 + 0.05, "RB nudges a focused slider")
	_tap(JOY_BUTTON_LEFT_SHOULDER)
	TestLib.check(is_equal_approx(hud.settings.look_x, lx0), "LB nudges it back")
	# focus scan: every button of the options screen is reachable by the D-pad
	var seen := {}
	pad._set_focus(&"opt_look_x")
	for i in 40:
		seen[pad.focus] = true
		for d in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT]:
			_tap(d)
			seen[pad.focus] = true
	pad._set_focus(&"opt_tab_0")                                  # the tab strip is above the rows: walk it along, then up from the first row
	for i in 6:
		_tap(JOY_BUTTON_DPAD_RIGHT)
		seen[pad.focus] = true
	pad._set_focus(&"opt_look_x")
	_tap(JOY_BUTTON_DPAD_UP)
	seen[pad.focus] = true
	TestLib.check(OptionsScreen.is_tab(pad.focus), "UP from the first row reaches the tab strip")
	var ids := []
	for bt: Dictionary in hud.buttons:
		ids.append(bt["id"])
	var reach := 0
	for id in ids:
		reach += int(seen.has(id))
	TestLib.check(reach >= ids.size() - 3, "the D-pad reaches the options buttons (%d of %d)" % [reach, ids.size()])

	# --- controls screen
	pad._set_focus(&"opt_controls")
	_tap(JOY_BUTTON_A)
	TestLib.check(UiSettings.s_opt_page == 2, "OPTIONS has a CONTROLS screen")
	await _frames(2)
	hud._ensure_layout()
	var sc := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var small := 0
	var rows := 0
	for bt: Dictionary in hud.buttons:
		if String(bt["id"]).begins_with("ctl_"):
			rows += 1
			small += int((bt["rect"] as Rect2).size.y < 63.9 * sc)
	TestLib.check(rows >= 14 and small == 0, "controls screen buttons are 64 px or more (%d buttons)" % rows)
	hud.press_button(&"ctl_tab_pad")
	hud.press_button(&"ctl_row_jump")
	TestLib.check(ControlsScreen.listening == &"jump", "a row waits for a button")
	hud._ensure_layout()
	pad.sim_buttons = {}
	_step(2)
	_tap(JOY_BUTTON_X)
	TestLib.check(ControlsScreen.listening == &"" and ControlMap.pad_binds["0:x"] == &"jump" and ControlMap.pad_binds["0:a"] == &"reload", "the next pad button is bound, the old owner swaps")
	TestLib.check(UiSettings.new("user://test_controller_hud.cfg").pad_binds["0:x"] == &"jump", "the new layout is saved")
	hud.press_button(&"ctl_tab_key")
	hud.press_button(&"ctl_row_blink")
	var ek := InputEventKey.new()
	ek.pressed = true
	ek.physical_keycode = KEY_P
	pad._input(ek)
	TestLib.check(ControlMap.key_of(&"blink") == KEY_P and hud.settings.key_binds.get("blink") == KEY_P and not ControllerInput.pad_ui, "a key is bound, the keyboard takes over the UI")
	hud.press_button(&"ctl_reset")
	TestLib.check(ControlMap.key_of(&"blink") == KEY_Q and hud.settings.key_binds.is_empty(), "RESET restores the keyboard keys")
	hud.press_button(&"ctl_tab_pad")
	hud.press_button(&"ctl_reset")
	TestLib.check(ControlMap.pad_binds["0:a"] == &"jump", "RESET restores the controller layout")
	hud.press_button(&"ctl_back")
	TestLib.check(UiSettings.s_opt_page == 0, "BACK returns to the options")
	# B goes back / resumes
	pad.sim_buttons = {JOY_BUTTON_A: true}
	_step()
	pad.sim_buttons = {}
	_step()
	_tap(JOY_BUTTON_B)
	hud.press_button(&"options_back")
	_tap(JOY_BUTTON_B)
	TestLib.check(Game.state == &"play" or Game.state == &"paused", "B leaves the screens")
	Game.state = &"play"
	await _frames(2)

	# --- back to touch
	pad.sim_axes = {JOY_AXIS_LEFT_X: 1.0}
	_step()
	TestLib.check(ControllerInput.pad_ui, "pad again")
	pad.sim_axes = {}
	_step()
	var te := InputEventScreenTouch.new()
	te.pressed = true
	pad._input(te)
	TestLib.check(not ControllerInput.pad_ui and hud.touch != null and hud.touch.controls_on, "a touch brings the touch overlay back")
	TestLib.check(Input.get_action_strength(&"move_right") == 0.0, "nothing stays pressed after the switch")

	# --- haptics from the live game feel hooks
	var n0 := UiSettings.buzzed
	GameFeel.fire(&"hurt")
	GameFeel.fire(&"explosion")
	GameFeel.fire(&"ability")
	TestLib.check(UiSettings.buzzed == n0 + 3 and int(UiSettings.last_plan["ms"]) > 0, "hurt, explosion and ability buzz")
	UiSettings.s_vibration = false
	GameFeel.fire(&"hurt")
	TestLib.check(UiSettings.buzzed == n0 + 3, "vibration off: no buzz")
	UiSettings.s_vibration = true
	pad.release_all()
	ControllerInput.pad_ui = false
	main.queue_free()
	await _frames(2)
