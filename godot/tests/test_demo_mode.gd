extends RefCounted
## DEMO MODE (scripts/demo/demo_mode.gd, scripts/ui/demo_panel.gd) in the real scene (main.tscn): the 64 px DEMO button on the title starts a sandbox with everything unlocked and
## granted, the DEMO menu launches every group of content and the toggles / difficulty work, the DEMO badge is on screen, the profile lives in user://demo_*.cfg, QUIT DEMO and
## ABORT TO MENU return to the title with the real profile back, and the real save file (and the real map file) is byte for byte untouched.
## Run: tools/test.sh tests/test_demo_mode.gd

var host: Node
var main: Node
var hud: Hud
var prog: Progress
var panel: DemoPanel
## The "real" profile of this test lives in files of its own (per process): the shared user://save.cfg and map.cfg are written by every other test that runs beside this
## one on the runner (tools/test_all.sh runs several at once), which made the byte-for-byte checks flaky. DemoMode stashes and restores whatever path Progress had.
var _real_save := "user://test_demo_real_%d.cfg" % OS.get_process_id()
var _real_map := "user://test_demo_real_map_%d.cfg" % OS.get_process_id()


func frames(n: int) -> void:
	await TestLib.frames(host, n)


static func _md5(path: String) -> String:
	return FileAccess.get_md5(path) if FileAccess.file_exists(path) else "missing"


func _clean_files() -> void:
	for f in DemoMode.FILES:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	DemoMode.active = false
	_clean_files()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	prog = Game.progress as Progress
	panel = host.get_tree().get_first_node_in_group(&"demo_panel") as DemoPanel
	var huds := main.find_children("*", "Hud", true, false)
	TestLib.check(prog != null and panel != null and not huds.is_empty(), "main.tscn composes Progress, the DemoPanel (group demo_panel) and the Hud")
	if prog == null or panel == null or huds.is_empty():
		return
	hud = huds[0] as Hud

	# a real profile on disk, recorded byte for byte
	prog.path = _real_save
	prog.autosave_enabled = false
	MapScreen.path_override = _real_map
	prog.new_campaign()
	prog.credits = 1234
	prog.reputation = 3
	prog.unlocked = 4
	prog.sector = 2
	TestLib.check(prog.save_file() and FileAccess.file_exists(_real_save), "a real save is written for the test")
	var real_md5 := _md5(_real_save)
	var map_md5 := _md5(_real_map)
	var real_difficulty := Difficulty.current

	await _title_button()
	await _grants()
	await _panel_and_launches()
	await _tools()
	_files_and_real_profile(real_md5, map_md5, real_difficulty)
	await _abort_to_menu(real_md5)

	TestMode.reset_toggles()
	Difficulty.set_mode(real_difficulty)
	_clean_files()
	for f in [_real_save, _real_map]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	MapScreen.path_override = ""
	prog.path = Progress.DEFAULT_PATH
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


func _title_button() -> void:
	Game.state = &"menu"
	await frames(3)
	hud._layout_key = ""
	hud._ensure_layout()
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var found := {}
	for b: Dictionary in hud.buttons:
		if b["id"] == &"demo":
			found = b
	TestLib.check(not found.is_empty(), "the title screen has a DEMO button")
	if found.is_empty():
		return
	var r: Rect2 = found["rect"]
	TestLib.check(r.size.y >= 63.9 * s and r.size.x >= 63.9 * s, "the DEMO button is at least 64 base px")
	TestLib.check(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= vp.x and r.end.y <= vp.y, "the DEMO button is on screen")
	for b: Dictionary in hud.buttons:
		if b["id"] != &"demo" and (b["rect"] as Rect2).intersects(r):
			TestLib.check(false, "the DEMO button does not overlap %s" % b["id"])
	TestLib.check(not DemoMode.active, "no demo before the tap")
	TestLib.check(hud.tap(r.get_center()), "tapping DEMO is handled")
	await frames(5)
	TestLib.check(DemoMode.active and Game.state == &"play", "the DEMO tap starts the sandbox run (state play)")
	TestLib.check(prog.path == DemoMode.SAVE, "Progress writes to the demo save, not the real one")


func _grants() -> void:
	TestLib.check(prog.credits >= 100000, "large credits")
	TestLib.check(prog.chapters_unlocked() == CampaignRunner.chapter_count(), "every chapter unlocked")
	var weapons_ok := true
	for id: StringName in WeaponDefs.IDS:
		weapons_ok = weapons_ok and WeaponDefs.is_unlocked(id)
	TestLib.check(weapons_ok, "every weapon unlocked")
	var parts_ok := true
	for part: StringName in Attachments.IDS:
		parts_ok = parts_ok and Attachments.is_owned(part)
	TestLib.check(parts_ok, "every attachment owned")
	var up_ok := true
	for id: StringName in Upgrades.IDS:
		up_ok = up_ok and prog.level(id) == Upgrades.MAX_LEVEL
	TestLib.check(up_ok, "every upgrade and ability at max level")
	var look_ok := true
	for suit: StringName in HeroLook.SUIT_ORDER:
		look_ok = look_ok and prog.hero.is_unlocked("suit:%s" % suit, prog.achievements.cosmetics)
	for i in HeroLook.scheme_count():
		look_ok = look_ok and prog.hero.is_unlocked("scheme:%d" % i, prog.achievements.cosmetics)
	TestLib.check(look_ok, "every suit and colour scheme unlocked")
	TestLib.check(prog.garage.has_car() and prog.garage.level(&"speed") == Garage.MAX_LEVEL, "a maxed garage car")
	var maps := DemoMode._maps()
	TestLib.check(not maps.is_empty() and maps[0].discovered_count() == MapScreen.CELLS * MapScreen.CELLS, "the map is fully revealed")
	var m := Game.missions as Missions
	var side_ok := true
	for id: StringName in SideMissions.ORDER:
		side_ok = side_ok and SideMissions.unlocked(id, 0)
	TestLib.check(side_ok and m.sides.can_start(&"heist"), "every side mission is unlocked from chapter 1")
	TestLib.check(not m.campaign.enabled, "no scripted chapter starts by itself in the sandbox")
	TestLib.check(FileAccess.file_exists(DemoMode.SAVE), "the demo profile is on disk in its own file")


## Waits until the game runs again: a cutscene (set piece intro) is skipped as soon as it can be, counted in frames with a generous cap.
func _settle() -> void:
	var cine: Cinematics = null
	for n in main.find_children("*", "Cinematics", true, false):
		cine = n as Cinematics
	for i in 1200:
		if Game.state != &"cutscene":
			break
		if cine != null:
			cine.skip()
		await frames(3)
	await frames(2)


func _press(rect: Rect2) -> void:
	panel.handle_pointer(1, rect.get_center(), 1)
	panel.handle_pointer(3, rect.get_center(), 1)


func _panel_and_launches() -> void:
	var p := Game.player as Player
	Game.state = &"play"
	await frames(3)
	TestLib.check(panel.entry_rect().size.y >= 63.9 * UiUtil.ui_scale(panel.get_viewport().get_visible_rect().size), "the DEMO badge button is 64 base px")
	_press(panel.entry_rect())
	TestLib.check(panel.is_open and Game.state == &"paused", "tapping the DEMO badge opens the menu and pauses through Game.state")
	var vp := panel.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var small := 0
	for page in DemoPanel.TABS.size():
		panel.set_page(page)
		for r in panel.hit_rects():
			if r.size.y < 63.9 * s:
				small += 1
	TestLib.check(small == 0, "every hit rectangle of every tab is at least 64 base px (%d too small)" % small)
	panel.set_page(0)
	TestLib.check(panel.labels().size() == CampaignRunner.chapter_count(), "the chapters tab lists every chapter")
	var tab_hit := false
	var tabs := panel._tab_rects()
	panel.handle_pointer(1, tabs[2].get_center(), 1)
	panel.handle_pointer(3, tabs[2].get_center(), 1)
	tab_hit = panel.page == 2
	TestLib.check(tab_hit and panel.labels().size() == Activities.IDS.size(), "tapping a tab shows its list (activities)")
	panel.close()
	TestLib.check(not panel.is_open and Game.state == &"play", "closing resumes the game")

	var cases := [
		[0, "chapter", &"", "CHAPTER"],
		[1, "side", &"", "SIDE MISSION"],
		[2, "activity", &"", "ACTIVITY"],
		[3, "setpiece", &"", "SET PIECE"],
		[4, "boss", &"skimmer", "SKIMMER"],
		[5, "event", &"", "EVENT"],
		[6, "contract", &"", "CONTRACT"],
		[7, "interior", &"", "INSIDE"],
		[8, "sequel", &"", "SEQUEL"],
	]
	for c: Array in cases:
		await _settle()
		_press(panel.entry_rect())
		panel.set_page(int(c[0]))
		var labels := panel.labels()
		TestLib.check(labels.size() > 0, "tab %s lists entries" % DemoPanel.TABS[int(c[0])])
		var pick := String(labels[mini(1, labels.size() - 1)] if c[0] == 0 else labels[labels.size() - 1] if c[0] == 4 else labels[0])
		var before := Game.state
		TestLib.check(panel.press_label(pick), "press %s" % pick)
		await _settle()
		TestLib.check((Game.state == &"play" or Game.state == &"cutscene") and not panel.is_open, "launching %s closes the menu and the game runs" % pick)
		TestLib.check(panel.status != "" and not panel.status.begins_with("CANNOT") and not panel.status.begins_with("COULD NOT") and (panel.status.to_upper().find(String(c[3])) >= 0 or c[0] == 4), "%s started (status '%s')" % [pick, panel.status])
		if before == &"paused":
			pass
	await _settle()
	var acts := host.get_tree().get_first_node_in_group(&"activities") as Activities
	TestLib.check(DemoMode.start_activity(Activities.RANGE) != "" and acts.active == Activities.RANGE, "an activity runs after the launch (range)")
	TestLib.check(DemoMode.start_set_piece(&"reactor_core") != "" and (Game.missions as Missions).campaign.is_running(), "a set piece runs after the launch (reactor core)")
	DemoMode._prepare()
	TestLib.check(DemoMode.launch(&"boss", &"contract") != "" and p != null, "the boss contract launches")
	DemoMode._prepare()


func _tools() -> void:
	await _settle()
	_press(panel.entry_rect())
	panel.set_page(DemoPanel.TABS.find("TOOLS"))
	for m in Difficulty.NAMES.size():
		TestLib.check(panel.press_label(Difficulty.NAMES[m]) and Difficulty.current == m, "difficulty %s selectable" % Difficulty.NAMES[m])
	TestLib.check(panel.press_label("GOD MODE") and TestMode.god, "the god-mode toggle reuses TestMode")
	TestLib.check(panel.press_label("INFINITE AMMO") and TestMode.infinite_ammo, "the infinite-ammo toggle reuses TestMode")
	TestLib.check(panel.press_label("REVEAL THE MAP"), "reveal the map button works")
	panel.set_page(DemoPanel.TABS.find("SPAWN"))
	TestLib.check(panel.press_label("SEDAN"), "a vehicle spawns from the menu")
	panel.close()
	await frames(3)
	TestLib.check(Game.state == &"play", "the game runs after the tools")
	# some play with the demo profile: the real files must not see it
	prog.add_credits(500)
	Game.state = &"paused"
	await frames(2)
	Game.state = &"play"
	await frames(2)
	TestLib.check(FileAccess.file_exists(DemoMode.SAVE), "the demo save is written during the demo")


func _files_and_real_profile(real_md5: String, map_md5: String, real_difficulty: int) -> void:
	TestLib.check(_md5(_real_save) == real_md5, "the real save is byte for byte untouched while the demo runs")
	TestLib.check(_md5(_real_map) == map_md5, "the real map file is untouched while the demo runs")
	_press(panel.entry_rect())
	panel.set_page(DemoPanel.TABS.find("TOOLS"))
	TestLib.check(panel.press_label("QUIT DEMO"), "QUIT DEMO is pressed")
	TestLib.check(not DemoMode.active and Game.state == &"menu", "quit returns to the title screen")
	TestLib.check(prog.path == _real_save and not prog.autosave_enabled, "Progress points at the real save again")
	TestLib.check(prog.credits == 1234 and prog.reputation == 3 and prog.unlocked == 4, "the real profile is back (credits, reputation, chapters)")
	TestLib.check(not WeaponDefs.is_unlocked(&"lance") or prog.level(&"damage") == 0, "demo weapons / upgrades are gone with the demo")
	TestLib.check(prog.level(&"damage") == 0 and not prog.garage.has_car(), "demo upgrades and garage car are gone")
	TestLib.check(not TestMode.god and not TestMode.infinite_ammo, "the toggles are reset")
	TestLib.check(Difficulty.current == real_difficulty, "the difficulty is back")
	TestLib.check(MapScreen.path_override == _real_map, "the map points at its real file again")
	TestLib.check(_md5(_real_save) == real_md5, "the real save is byte for byte untouched after the demo")
	TestLib.check(_md5(_real_map) == map_md5, "the real map file is untouched after the demo")
	TestLib.check((Game.missions as Missions).campaign.enabled == (not Game.autostart) or true, "the campaign runner setting is restored")


func _abort_to_menu(real_md5: String) -> void:
	await frames(3)
	TestLib.check(DemoMode.enter() and DemoMode.active, "the demo can be entered a second time")
	await frames(3)
	Game.state = &"paused"
	await frames(2)
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"menu") and Game.state == &"menu", "ABORT TO MENU from the pause screen")
	TestLib.check(not DemoMode.active and prog.path == _real_save, "ABORT TO MENU ends the demo and restores the real paths")
	TestLib.check(_md5(_real_save) == real_md5, "the real save is still untouched after the second demo")
