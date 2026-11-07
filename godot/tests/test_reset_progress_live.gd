extends RefCounted
## RESET PROGRESS in the live composed game (scenes/main.tscn): title -> OPTIONS -> MORE -> RESET PROGRESS, armed by one press, disarmed by anything else, erased by the second.
## The save and its .bak (and the map / interior / activity files) are removed, the title stops offering CONTINUE and the game starts a fresh campaign. The DEMO slot is only
## erased by its own separate confirm. Spanish and Hindi carry the reset and crafting labels.
## Run: tools/test.sh tests/test_reset_progress_live.gd

const SAVE := "user://test_reset_live_save.cfg"
const SIDE: Array[String] = ["user://map.cfg", "user://interiors.cfg", "user://activities.cfg"]

var host: Node
var hud: Hud
var prog: Progress
var _msgs: Array[String] = []


func _exists(p: String) -> bool:
	return FileAccess.file_exists(p)


func _touch(p: String, text := "[x]\na=1\n") -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _rect(id: StringName) -> Rect2:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b["rect"]
	return Rect2()


func _tap(id: StringName) -> bool:
	var r := _rect(id)
	if r.size == Vector2.ZERO:
		return false
	return hud.tap(r.get_center())


func _has_button(id: StringName) -> bool:
	return _rect(id).size != Vector2.ZERO


func _wait_state(st: StringName, secs := 8.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Game.state != st and Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await host.get_tree().process_frame


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	for f: String in [SAVE, SAVE + ".bak", SAVE + ".tmp"]:
		if _exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	prog = Game.progress as Progress
	var huds := main.find_children("*", "Hud", true, false)
	TestLib.check(prog != null and huds.size() == 1, "the live game has a Progress and a HUD")
	if prog == null or huds.size() != 1:
		return
	hud = huds[0] as Hud
	Game.message.connect(func(t: String, _d: float) -> void: _msgs.append(t))

	# a profile worth keeping: its own save path (never the player's), a backup, and the side files
	prog.path = SAVE
	prog.autosave_enabled = true
	prog.credits = 777
	prog.sector = 3
	prog.unlocked = 4
	prog.tutorial_done = true
	TestLib.check(prog.save_file() and prog.save_file() and _exists(SAVE) and _exists(SAVE + ".bak"), "a save and its backup exist")
	var had_side := {}
	for f: String in SIDE:
		had_side[f] = _exists(f)
		_touch(f)
	_touch("user://demo_save.cfg", "[meta]\nversion=2\n[wallet]\ncredits=999999\n")
	_touch("user://demo_save.cfg.bak", "[meta]\nversion=2\n[wallet]\ncredits=999999\n")
	_touch("user://demo_map.cfg")
	TestLib.check(Progress.demo_slot_exists(), "the demo slot exists")

	# title screen with a save
	Game.state = &"menu"
	await TestLib.frames(host, 3)
	TestLib.check(_has_button(&"continue") and _has_button(&"options"), "the title offers CONTINUE and OPTIONS")
	TestLib.check(_tap(&"options") and hud._options_open, "OPTIONS opens from the title")
	TestLib.check(_tap(&"opt_tab_4") and UiSettings.s_opt_tab == 4, "the DATA tab opens")
	TestLib.check(_has_button(&"opt_reset") and _has_button(&"opt_reset_demo"), "RESET PROGRESS and RESET DEMO SLOT are on the DATA tab")
	for id: StringName in [&"opt_reset", &"opt_reset_demo"]:
		TestLib.check(_rect(id).size.y >= 63.9 * UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size), "%s is a 64 px target" % id)

	# arming then cancelling
	TestLib.check(_tap(&"opt_reset") and OptionsScreen.reset_armed and _exists(SAVE) and prog.credits == 777, "the first press only arms the reset")
	TestLib.check(_tap(&"opt_tab_0") and not OptionsScreen.reset_armed, "flipping the tab disarms it")
	TestLib.check(_tap(&"opt_tab_4") and _tap(&"opt_reset") and OptionsScreen.reset_armed, "armed again")
	TestLib.check(_tap(&"opt_reset_demo") and not OptionsScreen.reset_armed and OptionsScreen.reset_demo_armed and _exists(SAVE) and prog.credits == 777, "the demo button disarms the main reset and arms its own")
	TestLib.check(_tap(&"opt_reset") and OptionsScreen.reset_armed and not OptionsScreen.reset_demo_armed, "and the main reset disarms the demo one")

	# the confirmed reset: save, backup and side files gone, demo slot untouched
	_msgs.clear()
	TestLib.check(_tap(&"opt_reset") and not OptionsScreen.reset_armed, "the second press resets")
	TestLib.check(not _exists(SAVE) and not _exists(SAVE + ".bak") and not _exists(SAVE + ".tmp"), "the save and its backup are removed")
	for f: String in SIDE:
		TestLib.check(not _exists(f), "%s is removed" % f)
	TestLib.check(_msgs.has("PROGRESS RESET"), "the player is told")
	TestLib.check(prog.credits == 0 and prog.sector == 0 and prog.unlocked == 1 and not prog.tutorial_done and not prog.has_save(), "the profile is a fresh campaign")
	TestLib.check(Progress.demo_slot_exists() and _exists("user://demo_save.cfg"), "the demo slot was NOT reset by RESET PROGRESS")
	TestLib.check(Game.state == &"menu" and hud._options_open, "still on the title, options open")

	# back to the title: no CONTINUE, DEPLOY there
	TestLib.check(_tap(&"options_back") and not hud._options_open, "BACK returns to the title")
	await TestLib.frames(host, 2)
	TestLib.check(not _has_button(&"continue") and _has_button(&"deploy"), "the title offers DEPLOY only")

	# the demo slot with its own separate confirm
	TestLib.check(_tap(&"options") and _tap(&"opt_tab_4"), "options page 2 again")
	TestLib.check(_tap(&"opt_reset_demo") and Progress.demo_slot_exists(), "the first demo press only arms")
	TestLib.check(_tap(&"options_back") and not OptionsScreen.reset_demo_armed, "leaving options disarms it")
	TestLib.check(_tap(&"options") and _tap(&"opt_tab_4") and _tap(&"opt_reset_demo") and _tap(&"opt_reset_demo"), "armed and confirmed")
	TestLib.check(not Progress.demo_slot_exists() and not _exists("user://demo_save.cfg.bak") and not _exists("user://demo_map.cfg"), "the demo slot files and backups are removed")
	TestLib.check(_msgs.has("DEMO SLOT RESET"), "the demo reset is announced")
	TestLib.check(_tap(&"options_back"), "back to the title")

	# a fresh campaign starts from the title
	await TestLib.frames(host, 2)
	TestLib.check(_tap(&"deploy"), "DEPLOY is pressable")
	await _wait_state(&"play")
	TestLib.check(Game.state == &"play" and prog.credits == 0 and is_instance_valid(Game.player), "a new campaign starts from zero (state %s)" % Game.state)

	# during play the buttons do nothing
	Game.state = &"paused"
	TestLib.check(not OptionsScreen.press(hud.settings, &"opt_reset") and not OptionsScreen.reset_armed and not OptionsScreen.press(hud.settings, &"opt_reset_demo"), "not allowed outside the title")
	Game.state = &"play"

	# localisation of the labels
	var keys: Array[String] = ["RESET PROGRESS", "TAP AGAIN: ERASE ALL", "RESET DEMO SLOT", "TAP AGAIN: ERASE DEMO", "PROGRESS RESET", "DEMO SLOT RESET", "WORKBENCH", "CRAFT", "INVENTORY", "SUPPLY", "DISMANTLE", "EQUIP", "UNEQUIP",
		"SCRAP", "ALLOY", "QUANTUM CORE", "COMMON", "LEGENDARY", "CHAIN ARC", "PHASE ROUNDS", "SINGULARITY ON CRIT", "NO PERK", "NEED MORE PARTS", "INVENTORY FULL", "FIRE RATE", "SAVE FAILED - CHECK STORAGE"]
	var old_lang := Tr.lang
	for l: String in ["es", "hi"]:
		Tr.lang = l
		var missing: Array[String] = []
		for k: String in keys:
			if Tr.t(k) == k:
				missing.append(k)
		TestLib.check(missing.is_empty(), "%s translates the reset and crafting labels (missing %s)" % [l, str(missing)])
	Tr.lang = old_lang

	for f: String in SIDE:
		if _exists(f) and not had_side[f]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	prog.autosave_enabled = false
	prog.path = Progress.DEFAULT_PATH
	Sfx.muted = false
	OptionsScreen.reset_armed = false
	OptionsScreen.reset_demo_armed = false
	UiSettings.s_opt_page = 0
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 3)
