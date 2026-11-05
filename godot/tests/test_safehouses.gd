extends RefCounted
## The four safehouses (scripts/progress/safehouses.gd, scripts/ui/safehouse_screen.gd) in the REAL scene (main.tscn): data and Economy prices, buy gated by sector and credits, free claim of an
## EARN goal, upgrades that grant look items and weapon parts, REST (heal, time of day, heat, energy), the fast-save point and GO, the save round trip (and a save without the section),
## the pause menu SAFEHOUSE button, the screen with 64 px buttons, WARDROBE / BENCH / TROPHIES opening and returning, the HOME markers on the map and the DEMO entries.
## Progress writes to a throw-away file; waits are on state. Not run: a phone, the feel of the screens.
## Run: tools/test.sh tests/test_safehouses.gd

const TMP := "user://test_safehouses_save.cfg"

var host: Node
var main: Node
var prog: Progress
var p: Player
var hud: Hud


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	p = Game.player as Player
	prog = Game.progress as Progress
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	TestLib.check(p != null and prog != null and hud != null, "main.tscn composes the player, progress and the HUD")
	if p == null or prog == null or hud == null:
		return
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	_rules()
	_upgrades()
	_rest_and_go()
	_save_roundtrip()
	await _screen()
	await _map()
	await _demo()
	Game.state = &"play"
	prog.new_campaign()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _data() -> void:
	TestLib.check(Safehouses.IDS.size() == 4, "four safehouses")
	var last := -1
	for id: StringName in Safehouses.IDS:
		var d: Dictionary = Safehouses.DEFS[id]
		TestLib.check(Economy.SAFEHOUSE_PRICE.has(id) and Economy.SAFEHOUSE_CHAPTER.has(id), "%s is priced by Economy" % id)
		TestLib.check(InteriorData.TYPES.has(d["room"] as StringName), "%s uses an existing interior kind" % id)
		TestLib.check(int(Economy.SAFEHOUSE_CHAPTER[id]) > last, "%s needs a later sector than the one before" % id)
		last = int(Economy.SAFEHOUSE_CHAPTER[id])
		TestLib.check((d["locker"] as Array).size() == Safehouses.MAX_LEVEL and (d["bench"] as Array).size() == Safehouses.MAX_LEVEL, "%s has a grant for every upgrade level" % id)
		for k: String in d["locker"]:
			TestLib.check(HeroLook.valid_key(k), "%s locker item %s is a real look item" % [id, k])
		for part: StringName in d["bench"]:
			TestLib.check(Attachments.PARTS.has(part), "%s bench part %s exists" % [id, part])
	TestLib.check(int(Economy.SAFEHOUSE_PRICE[&"loft"]) < int(Economy.SAFEHOUSE_PRICE[&"bunker"]), "prices rise with the house")


func _rules() -> void:
	prog.credits = 0
	TestLib.check(not Safehouses.buy(prog, &"loft"), "no credits, no house")
	prog.credits = 100000
	TestLib.check(not Safehouses.buy(prog, &"bunker") and not Safehouses.is_owned(prog, &"bunker"), "a later sector is refused even with the credits")
	TestLib.check(Safehouses.buy(prog, &"loft") and Safehouses.is_owned(prog, &"loft") and prog.credits == 100000 - int(Economy.SAFEHOUSE_PRICE[&"loft"]), "the loft is bought at its price")
	TestLib.check(not Safehouses.buy(prog, &"loft"), "a house is bought once")
	TestLib.check(not Safehouses.claim(prog, &"depot"), "the depot cannot be claimed before its goal")
	prog.side_done = {&"courier": 3, &"photo": 2}
	TestLib.check(Safehouses.earned(prog, &"depot") and Safehouses.claim(prog, &"depot") and Safehouses.is_owned(prog, &"depot"), "5 side jobs claim the depot free")
	var before := prog.credits
	prog.unlock(6)
	TestLib.check(Safehouses.buy(prog, &"bunker") and prog.credits == before - int(Economy.SAFEHOUSE_PRICE[&"bunker"]), "an unlocked sector allows the bunker")
	prog.bosses_cleared = [0, 1, 2]
	TestLib.check(Safehouses.claim(prog, &"penthouse"), "3 overseers claim the penthouse")
	TestLib.check(Safehouses.owned_count(prog) == 4, "all four are owned")


func _upgrades() -> void:
	prog.credits = 50000
	var id := &"loft"
	TestLib.check(Safehouses.up_price(prog, id, &"bed") == int(Economy.SAFEHOUSE_UPGRADE[&"bed"]), "level 1 costs the base price")
	TestLib.check(Safehouses.upgrade(prog, id, &"bed") and Safehouses.level(prog, id, &"bed") == 1, "BED level 1")
	TestLib.check(Safehouses.up_price(prog, id, &"bed") == 2 * int(Economy.SAFEHOUSE_UPGRADE[&"bed"]), "level 2 costs double")
	TestLib.check(Safehouses.upgrade(prog, id, &"bed") and Safehouses.up_price(prog, id, &"bed") == -1 and not Safehouses.upgrade(prog, id, &"bed"), "BED tops out at level 2")
	TestLib.check(not prog.hero.owned.has("suit:stealth"), "the stealth suit is not owned yet")
	TestLib.check(Safehouses.upgrade(prog, id, &"locker") and prog.hero.owned.has("suit:stealth"), "LOCKER 1 grants a suit")
	TestLib.check(Safehouses.upgrade(prog, id, &"locker") and prog.hero.owned.has("scheme:1"), "LOCKER 2 grants a scheme")
	TestLib.check(Safehouses.upgrade(prog, id, &"bench") and Attachments.is_owned(&"reddot"), "BENCH 1 grants a weapon part")
	prog.credits = 0
	TestLib.check(not Safehouses.can_upgrade(prog, &"depot", &"bed"), "an upgrade needs credits")
	prog.credits = 100000
	prog.safehouses_owned.erase(&"depot")
	TestLib.check(not Safehouses.upgrade(prog, &"depot", &"bed"), "an unowned house cannot be upgraded")
	prog.safehouses_owned.append(&"depot")


func _rest_and_go() -> void:
	Game.state = &"play"
	var dn := Game.world.get("day_night") as DayNight
	TestLib.check(dn != null, "the city has a day-night cycle")
	p.hp = 10.0
	p.energy = 5.0
	Game.heat = 3.0
	Safehouses.rest_to = 1
	TestLib.check(Safehouses.rest(prog, &"loft"), "REST works in an owned house")
	TestLib.check(is_equal_approx(p.hp, p.max_hp) and is_equal_approx(dn.hour, Safehouses.REST_HOURS[1]), "REST heals and sets the time of day")
	TestLib.check(Game.heat == 0.0 and is_equal_approx(p.energy, p.max_energy), "BED 2 clears heat and restores energy")
	Game.heat = 2.0
	p.energy = 5.0
	TestLib.check(Safehouses.rest(prog, &"depot") and Game.heat == 2.0 and p.energy < 50.0, "without a bed upgrade REST only heals")
	Safehouses.cycle_time()
	TestLib.check(Safehouses.rest_to == 2, "TIME cycles the hour")
	Safehouses.rest_to = 0
	prog.safehouses_owned.erase(&"bunker")
	TestLib.check(not Safehouses.rest(prog, &"bunker") and not Safehouses.travel(prog, &"bunker") and not Safehouses.fast_save(prog, &"bunker"), "an unowned house offers nothing")
	prog.safehouses_owned.append(&"bunker")
	p.teleport_to(Vector3(0.0, 0.1, 0.0))
	TestLib.check(Safehouses.travel(prog, &"depot"), "GO moves the hero")
	var d2 := Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(Safehouses.door_pos(&"depot").x, Safehouses.door_pos(&"depot").z))
	TestLib.check(d2 < 45.0, "the hero stands near the depot door (%.1f m)" % d2)
	prog.safehouse_save = &""
	TestLib.check(Safehouses.fast_save(prog, &"depot") and prog.safehouse_save == &"depot" and FileAccess.file_exists(TMP), "the fast-save point writes the save file")
	Game.heat = 0.0


func _save_roundtrip() -> void:
	prog.safehouse_save = &"depot"
	TestLib.check(prog.save_file(), "the save is written")
	var owned := prog.safehouses_owned.duplicate()
	var lv := prog.safehouse_lv.duplicate()
	prog.safehouses_owned.clear()
	prog.safehouse_lv.clear()
	prog.safehouse_save = &""
	TestLib.check(prog.load_file(), "the save loads")
	TestLib.check(prog.safehouses_owned.size() == owned.size() and prog.safehouses_owned.has(&"depot") and prog.safehouse_lv == lv and prog.safehouse_save == &"depot", "houses, upgrade levels and the save point come back")
	var cf := ConfigFile.new()
	cf.load(TMP)
	cf.set_value("safehouse", "own_loft", "junk")
	cf.set_value("safehouse", "lv_depot_bed", 999)
	cf.set_value("safehouse", "save_at", "nowhere")
	cf.save(TMP)
	prog.load_file()
	TestLib.check(not prog.safehouses_owned.has(&"loft") and prog.safehouse_save == &"", "a damaged section is ignored and an unknown save point cleared")
	var cf2 := ConfigFile.new()
	cf2.load(TMP)
	cf2.erase_section("safehouse")
	cf2.save(TMP)
	TestLib.check(prog.load_file() and prog.safehouses_owned.is_empty() and prog.safehouse_lv.is_empty(), "a save without the section loads with no houses")
	prog.new_campaign()
	prog.unlock(6)
	prog.credits = 100000
	for id: StringName in Safehouses.IDS:
		Safehouses.buy(prog, id)
	TestLib.check(Safehouses.owned_count(prog) == 4, "the houses are bought again for the screen test")


func _reset_ui() -> void:
	Game.state = &"play"
	await TestLib.frames(host, 2)
	Game.state = &"paused"
	await TestLib.frames(host, 4)


func _ids() -> Dictionary:
	var ids := {}
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	for bt: Dictionary in hud.buttons:
		var bid := String(bt["id"])
		if bid.begins_with("sh_"):
			ids[bid] = true
			TestLib.check((bt["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * s - 1.0, "%s is at least 64 px tall" % bid)
	return ids


func _screen() -> void:
	await _reset_ui()
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var open_btn := false
	hud._gear_open = true                                          # SAFEHOUSE lives on the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	for bt: Dictionary in hud.buttons:
		if bt["id"] == &"sh_open":
			open_btn = (bt["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * s - 1.0
	TestLib.check(open_btn, "the pause menu has a 64 px SAFEHOUSE button")
	TestLib.check(hud.press_button(&"sh_open") and hud._safe_open, "SAFEHOUSE opens the screen")
	await TestLib.frames(host, 3)
	var ids := _ids()
	TestLib.check(ids.has("sh_pick_loft") and ids.has("sh_wardrobe") and ids.has("sh_bench") and ids.has("sh_garage") and ids.has("sh_trophy") and ids.has("sh_rest") and ids.has("sh_save") and ids.has("sh_go") and ids.has("sh_up_bed") and ids.has("sh_back"), "an owned house lays out its services and upgrades (%d buttons)" % ids.size())
	TestLib.check(hud.panel_cover(), "the screen covers the gameplay HUD")
	TestLib.check(hud.press_button(&"sh_pick_penthouse") and Safehouses.sel == &"penthouse", "a house is picked")
	Safehouses.rest_to = 0
	p.hp = 20.0
	TestLib.check(hud.press_button(&"sh_rest") and is_equal_approx(p.hp, p.max_hp), "REST from the screen heals")
	TestLib.check(hud.press_button(&"sh_time") and Safehouses.rest_to == 1, "TIME from the screen cycles")
	Safehouses.rest_to = 0
	TestLib.check(hud.press_button(&"sh_save") and prog.safehouse_save == &"penthouse", "SAVE from the screen sets the save point")
	var c0 := prog.credits
	TestLib.check(hud.press_button(&"sh_up_bed") and Safehouses.level(prog, &"penthouse", &"bed") == 1 and prog.credits < c0, "an upgrade is bought from the screen")
	# sub-screens return to the house
	TestLib.check(hud.press_button(&"sh_wardrobe") and hud._look_open, "WARDROBE opens the look screen")
	TestLib.check(hud.press_button(&"look_back") and not hud._look_open and hud._safe_open, "the look screen returns to the house")
	TestLib.check(hud.press_button(&"sh_bench") and hud._loadout_open, "WEAPON BENCH opens the loadout")
	TestLib.check(hud.press_button(&"loadout_back") and not hud._loadout_open and hud._safe_open, "the loadout returns to the house")
	TestLib.check(hud.press_button(&"sh_trophy") and hud._ach_open, "TROPHIES opens the achievements")
	TestLib.check(hud.press_button(&"ach_back") and not hud._ach_open and hud._safe_open, "the achievements return to the house")
	TestLib.check(hud.press_button(&"sh_go"), "GO from the screen works")
	# an unowned house offers buy / claim only
	prog.safehouses_owned.erase(&"bunker")
	Safehouses.sel = &"bunker"
	hud._layout_key = ""
	await TestLib.frames(host, 3)
	ids = _ids()
	TestLib.check(ids.has("sh_buy") and ids.has("sh_claim") and not ids.has("sh_rest") and not hud.press_button(&"sh_rest"), "a locked house offers BUY and CLAIM only")
	prog.credits = 0
	TestLib.check(not hud.press_button(&"sh_buy"), "BUY without credits is refused")
	prog.credits = 100000
	TestLib.check(hud.press_button(&"sh_buy") and Safehouses.is_owned(prog, &"bunker"), "BUY from the screen buys it")
	TestLib.check(hud.press_button(&"sh_back") and not hud._safe_open, "BACK returns to the pause menu")
	TestLib.check(not hud.press_button(&"sh_rest"), "a closed screen ignores its buttons")


func _map() -> void:
	var maps := main.find_children("*", "MapScreen", true, false)
	TestLib.check(not maps.is_empty() and MapScreen.KINDS.has(&"home"), "the map has a HOME kind")
	if maps.is_empty():
		return
	var ms := maps[0] as MapScreen
	var n := int(ms.marker_counts().get(&"home", 0))
	TestLib.check(n == Safehouses.owned_count(prog), "the map shows every owned house (%d)" % n)
	prog.safehouses_owned.erase(&"loft")
	TestLib.check(int(ms.marker_counts().get(&"home", 0)) == n - 1, "a house you do not own has no marker")
	prog.safehouses_owned.append(&"loft")


func _demo() -> void:
	TestLib.check(DemoPanel.TABS.has("SAFEHOUSE"), "the DEMO panel has a SAFEHOUSE tab")
	var cat := DemoMode.catalog()
	var found := false
	for g: Dictionary in cat:
		if g["kind"] == &"safehouse":
			found = (g["items"] as Array).size() == 4
	TestLib.check(found, "the DEMO catalogue lists the four houses")
	TestLib.check(DemoPanel.TABS.size() == cat.size() + 2, "a DEMO tab per group plus SPAWN and TOOLS")
	var was := DemoMode.active
	DemoMode.active = true
	Game.state = &"play"
	await TestLib.frames(host, 3)
	var r := DemoMode.launch(&"safehouse", &"bunker")
	TestLib.check(r != "" and Game.state == &"paused" and hud._safe_open and Safehouses.sel == &"bunker", "the DEMO entry opens the bunker (%s)" % r)
	DemoMode.active = was
	Game.state = &"play"
	await TestLib.frames(host, 2)
