extends RefCounted
## Options (H1/H2): every setting persists, clamps, publishes to the live mirrors, and the options screen is reachable by touch (every button >= 64 px).
## Run: tools/test.sh tests/test_options.gd


func run(host: Node) -> void:
	var path := "user://test_options.cfg"
	var s := UiSettings.new(path)
	TestLib.check(s.look_x == 1.0 and s.hud_scale == 1.0 and not s.left_hand and s.vibration and s.subtitles and not s.cb_safe and s.fps_cap == 60, "defaults")
	s.aim_assist = false
	s.auto_fire = true
	s.look_x = 1.5
	s.look_y = 0.6
	s.ads_sens = 0.5
	s.hud_scale = 1.1
	s.left_hand = true
	s.button_size = 1.2
	s.fps_cap = 120
	s.vibration = false
	s.subtitles = false
	s.cb_safe = true
	TestLib.check(s.save(), "saves")
	var s2 := UiSettings.new(path)
	TestLib.check(not s2.aim_assist and s2.auto_fire and is_equal_approx(s2.look_x, 1.5) and is_equal_approx(s2.look_y, 0.6) and is_equal_approx(s2.ads_sens, 0.5), "controls persist")
	TestLib.check(is_equal_approx(s2.hud_scale, 1.1) and s2.left_hand and is_equal_approx(s2.button_size, 1.2) and s2.fps_cap == 120, "layout and fps persist")
	TestLib.check(not s2.vibration and not s2.subtitles and s2.cb_safe, "vibration, subtitles, colour-safe persist")
	s2.look_x = 99.0
	s2.fps_cap = 77
	s2.save()
	var s3 := UiSettings.new(path)
	TestLib.check(s3.look_x == UiSettings.SENS_MAX and s3.fps_cap == 60, "out-of-range values clamp")
	s2.fps_cap = 0
	TestLib.check(s2.next_fps_cap() == 30, "fps cap cycles and wraps")
	s2.publish(false)
	TestLib.check(UiSettings.s_left_hand and UiSettings.s_cb_safe and not UiSettings.s_subtitles and UiUtil.hostile_col() == UiUtil.CB_HOSTILE, "publish mirrors the choices")
	TestLib.check(UiUtil.ui_scale(Vector2(1280, 720)) > 1.0, "HUD scale applies")
	var dflt := UiSettings.new("user://test_options_none.cfg")
	dflt.publish(false)
	TestLib.check(UiUtil.hostile_col() == UiUtil.RED and is_equal_approx(UiUtil.ui_scale(Vector2(1280, 720)), 1.0), "defaults restore")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var o := UiSettings.new("user://test_options_ui.cfg")
	TestLib.check(is_equal_approx(OptionsScreen.set_fraction(o, &"opt_look_x", 1.0), UiSettings.SENS_MAX) and OptionsScreen.fraction(o, &"opt_look_x") == 1.0, "slider maps to its range")
	OptionsScreen.press(o, &"opt_left")
	OptionsScreen.press(o, &"opt_fps")
	TestLib.check(o.left_hand and o.fps_cap == 90, "toggle and cycle")

	var hud := Hud.new()
	hud.settings_path = "user://test_options_hud.cfg"
	host.add_child(hud)
	await TestLib.frames(host, 2)
	Game.state = &"menu"
	await TestLib.frames(host, 2)
	TestLib.check(hud.press_button(&"options"), "OPTIONS opens from the title")
	hud._ensure_layout()
	var ids := {}
	var small := 0
	for b: Dictionary in hud.buttons:
		ids[b["id"]] = true
		if (b["rect"] as Rect2).size.y < 63.9 * UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size):
			small += 1
	TestLib.check(small == 0, "every options button is >= 64 px")
	for id: StringName in OptionsScreen.ORDER:
		TestLib.check(ids.has(id), "row " + String(id))
	TestLib.check(ids.has(&"options_back"), "BACK present")
	TestLib.check(hud.press_button(&"opt_cb") and hud.settings.cb_safe and UiSettings.s_cb_safe, "colour-safe toggles and publishes")
	hud.press_button(&"opt_aim")
	TestLib.check(not AimAssist.enabled, "aim assist toggle reaches AimAssist")
	var r: Rect2 = Rect2()
	for b: Dictionary in hud.buttons:
		if b["id"] == &"opt_ads":
			r = b["rect"]
	hud.tap(r.get_center())
	hud.end_drag()
	TestLib.check(absf(hud.settings.ads_sens - 1.15) < 0.1, "tapping a slider sets it")
	TestLib.check(hud.press_button(&"options_back") and not hud._options_open, "BACK closes")
	var reload := UiSettings.new("user://test_options_hud.cfg")
	TestLib.check(reload.cb_safe and not reload.aim_assist, "HUD changes saved")
	hud.settings.cb_safe = false
	hud.settings.aim_assist = true
	hud.settings.ads_sens = 1.0
	hud.settings.publish()
	for f in ["test_options_ui.cfg", "test_options_hud.cfg", "test_options_none.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
	hud.queue_free()
