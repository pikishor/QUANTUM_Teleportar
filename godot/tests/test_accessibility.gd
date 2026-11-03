extends RefCounted
## Accessibility and localisation (H5/H6): Tr table, language and text scale, colour-blind palettes, reduce flash / motion, subtitle options, options page 2.
## Run: tools/test.sh tests/test_accessibility.gd

func run(host: Node) -> void:
	var path := "user://test_access.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var d := UiSettings.new(path)
	TestLib.check(d.language == "en" and d.text_scale == 1.0 and not d.reduce_flash and not d.reduce_motion and d.sub_size == 1.0 and d.sub_bg == 1, "accessibility defaults")
	d.language = "es"
	d.text_scale = 1.5
	d.cb_safe = true
	d.cb_variant = 1
	d.reduce_flash = true
	d.reduce_motion = true
	d.sub_size = 1.25
	d.sub_bg = 2
	TestLib.check(d.save(), "saves")
	var r := UiSettings.new(path)
	TestLib.check(r.language == "es" and r.text_scale == 1.5 and r.cb_variant == 1 and r.reduce_flash and r.reduce_motion and r.sub_size == 1.25 and r.sub_bg == 2, "persist")
	var bad := ConfigFile.new()
	bad.set_value("ui", "language", "xx")
	bad.set_value("ui", "text_scale", 1.3)
	bad.set_value("ui", "sub_bg", 77)
	bad.save(path)
	var b := UiSettings.new(path)
	TestLib.check(b.language == "en" and b.text_scale == 1.0 and b.sub_bg == 2, "bad values fall back or clamp")

	# Tr table
	Tr.set_lang("en")
	TestLib.check(Tr.t("NEW GAME") == "NEW GAME", "English passthrough")
	Tr.set_lang("es")
	TestLib.check(Tr.t("NEW GAME") == "NUEVA PARTIDA" and Tr.t("OPTIONS") == "OPCIONES" and Tr.t("84 KM/H") == "84 KM/H", "Spanish and unknown passthrough")
	TestLib.check(Tr.t("QUANTUM TELEPORT") == "QUANTUM TELEPORT" and Tr.t("ENTANGLE") == "ENTANGLE", "quantum names stay plain")
	var missing := 0
	for k: String in ["DEPLOY", "RESUME", "PAUSED", "INTEGRITY", "COHERENCE", "LANGUAGE", "REDUCE FLASH", "REDUCE MOTION", "TEXT SIZE", "SUBTITLES", "BACK"]:
		if not Tr.ES.has(k):
			missing += 1
	TestLib.check(missing == 0, "Spanish covers menus and HUD keys")
	Tr.set_lang("zz")
	TestLib.check(Tr.lang == "en", "unknown language falls back")

	# text scale never clips
	var font := UiUtil.font()
	Tr.text_scale = 1.5
	var w := 340.0
	var sz := Tr.scaled_size(font, "ACHIEVEMENTS", w, 30)
	TestLib.check(sz >= 30 and sz <= 45 and font.get_string_size("ACHIEVEMENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= w + 1.0, "scaled line fits its width")
	TestLib.check(Tr.scaled_size(font, "X", 200.0, 20) == 30 and Tr.scaled_size(font, "X", -1.0, 20) == 20, "scale applies when it fits; unbounded text untouched")
	Tr.text_scale = 1.0

	# palettes
	var s := UiSettings.new("user://test_access_pal.cfg")
	s.publish(false)
	var red := UiUtil.hostile_col()
	s.cb_safe = true
	s.cb_variant = 0
	s.publish(false)
	var c1 := UiUtil.hostile_col()
	s.cb_variant = 1
	s.publish(false)
	var c2 := UiUtil.hostile_col()
	TestLib.check(c1 != red and c2 != red and c1 != c2 and UiUtil.friend_col() == UiUtil.CB3_FRIEND, "colour-blind palettes differ")
	var o := UiSettings.new("user://test_access_o.cfg")
	OptionsScreen.press(o, &"opt_cb")
	var st1 := [o.cb_safe, o.cb_variant]
	OptionsScreen.press(o, &"opt_cb")
	var st2 := [o.cb_safe, o.cb_variant]
	OptionsScreen.press(o, &"opt_cb")
	TestLib.check(st1 == [true, 0] and st2 == [true, 1] and not o.cb_safe, "colour-safe cycles off / deutan / tritan")

	# reduce motion / flash
	s = UiSettings.new("user://test_access_pal.cfg")
	FX.shake_amount = 0.0
	s.reduce_motion = true
	s.publish(false)
	FX.shake(0.8)
	var slow_before := Engine.time_scale
	Stability.new().begin_slowmo()
	TestLib.check(FX.shake_amount == 0.0 and is_equal_approx(Engine.time_scale, slow_before), "reduce motion blocks shake and slow motion")
	s.reduce_motion = false
	s.publish(false)
	FX.shake(0.5)
	TestLib.check(FX.shake_amount > 0.4, "shake works when not reduced")
	FX.shake_amount = 0.0
	s.reduce_flash = true
	s.publish(false)
	TestLib.check(UiSettings.s_reduce_flash, "reduce flash published")

	# options page 2 through the HUD
	var hud := Hud.new()
	hud.settings_path = "user://test_access_hud.cfg"
	host.add_child(hud)
	await TestLib.frames(host, 2)
	Game.state = &"menu"
	await TestLib.frames(host, 2)
	hud.press_button(&"options")
	hud._ensure_layout()
	var ids := {}
	for bt: Dictionary in hud.buttons:
		ids[bt["id"]] = true
	TestLib.check(ids.has(&"opt_page") and not ids.has(&"opt_lang"), "page 1 has the page button, not the accessibility rows")
	TestLib.check(hud.press_button(&"opt_page"), "page flips")
	hud._ensure_layout()
	ids.clear()
	var small := 0
	for bt: Dictionary in hud.buttons:
		ids[bt["id"]] = true
		if (bt["rect"] as Rect2).size.y < 63.9 * UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size):
			small += 1
	for id: StringName in OptionsScreen.PAGE2:
		TestLib.check(ids.has(id), "access row " + String(id))
	TestLib.check(small == 0, "access rows are >= 64 px")
	TestLib.check(hud.press_button(&"opt_lang") and hud.settings.language == "es" and Tr.lang == "es", "language switches and publishes")
	TestLib.check(hud.press_button(&"opt_text") and hud.settings.text_scale == 1.25 and Tr.text_scale == 1.25, "text size cycles")
	hud._ensure_layout()
	var lab := ""
	for bt: Dictionary in hud.buttons:
		if bt["id"] == &"opt_lang":
			lab = bt["label"]
	TestLib.check(lab.begins_with("IDIOMA"), "labels follow the language")
	hud.press_button(&"opt_flash")
	hud.press_button(&"opt_subbg")
	TestLib.check(hud.settings.reduce_flash and UiSettings.s_reduce_flash and UiSettings.s_sub_bg == 2, "flash and subtitle bg apply")
	hud.press_button(&"options_back")
	TestLib.check(UiSettings.s_opt_page == 0, "back resets to page 1")
	await TestLib.frames(host, 2)

	# restore global state
	var clean := UiSettings.new("user://test_access_none.cfg")
	clean.publish(false)
	Tr.set_lang("en")
	Tr.text_scale = 1.0
	hud.queue_free()
	for f in ["test_access.cfg", "test_access_pal.cfg", "test_access_o.cfg", "test_access_hud.cfg", "test_access_none.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))
