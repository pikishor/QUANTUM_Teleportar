extends RefCounted
## Menu declutter (real scene, main.tscn): the title shows PLAY / CONTINUE, OPTIONS and MORE (nothing else); the pause menu shows RESUME, MAP, LOADOUT, OPTIONS and MORE;
## everything else is on the MORE page (BACK returns there from every screen opened from it); the HERO hub joins UPGRADES, WEAPONS, SKILLS and CRAFT as tabs of one screen;
## an upgrade is one tap on its whole row (affordable rows light up); the TEST button is a cell of the MORE page only; every button is >= 64 base px and on screen at 1280x720
## and 844x390. Waits on state, never on frame counts. Run: tools/test.sh tests/test_menu_declutter.gd

var host: Node
var main: Node
var hud: Hud


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _ids() -> Array:
	return hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])


func _layout() -> void:
	hud._layout_key = ""
	hud._ensure_layout()


func _state(st: StringName) -> void:
	Game.state = &"play"
	Game.state = st
	hud._on_state(st)
	hud.screen_age = 5.0
	_layout()


func _btn(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


func _sane(tag: String) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var ok := true
	var clash := ""
	for b: Dictionary in hud.buttons:
		var r: Rect2 = b["rect"]
		if r.size.y < 63.9 * s or not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r):
			ok = false
			clash = "%s %s" % [b["id"], r]
		for b2: Dictionary in hud.buttons:
			if b != b2 and r.intersects(b2["rect"]):
				ok = false
				clash = "%s over %s" % [b["id"], b2["id"]]
	TestLib.check(ok, "%s: every button is 64 base px, on screen, none overlaps (%s)" % [tag, clash])


func run(h: Node) -> void:
	Upgrades.show_all = true                 # the advanced upgrade rows and the SKILLS / CRAFT tabs are behind this flag (scripts/progress/upgrades.gd)
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		win.size = size
		await frames(4)
		var tag := "%dx%d" % [size.x, size.y]
		_title(tag)
		_pause(tag)
		_more(tag)
	win.size = old
	await frames(3)
	await _hero()
	await _map()
	_back_navigation()
	Game.state = &"play"
	hud._gear_open = false
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


func _title(tag: String) -> void:
	_state(&"menu")
	var ids := _ids()
	TestLib.check(ids.size() == 3 and ids.has(&"options") and ids.has(&"menu_gear") and (ids.has(&"deploy") or ids.has(&"continue")), "%s: the title shows PLAY / CONTINUE, OPTIONS and MORE only (%s)" % [tag, str(ids)])
	var main_label := String((_btn(&"continue") if ids.has(&"continue") else _btn(&"deploy"))["label"])
	TestLib.check(main_label == "PLAY" or main_label == "CONTINUE", "%s: the first button reads %s" % [tag, main_label])
	_sane(tag + " title")
	var tm := main.find_children("*", "TestMenu", true, false)
	TestLib.check(tm.is_empty() or (tm[0] as TestMenu).entry_rect().size.x == 0.0, "%s: no TEST badge on the title" % tag)
	TestLib.check(hud.press_button(&"menu_gear") and hud._gear_open, "%s: MORE opens" % tag)
	_layout()
	ids = _ids()
	TestLib.check(ids.has(&"demo") and ids.has(&"arena_open") and ids.has(&"more_back") and not ids.has(&"options"), "%s: the title MORE page lists DEMO and ARENA and a BACK (%s)" % [tag, str(ids)])
	_sane(tag + " title MORE")
	if not tm.is_empty() and TestMode.available():
		var te: Rect2 = (tm[0] as TestMenu).entry_rect()
		TestLib.check(te.size.x > 0.0 and te.size.y >= 63.9 * UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size), "%s: the TEST button is a 64 px cell of the MORE page" % tag)
		for b: Dictionary in hud.buttons:
			TestLib.check(not te.intersects(b["rect"]), "%s: TEST does not overlap %s" % [tag, b["id"]])
	TestLib.check(hud.press_button(&"more_back") and not hud._gear_open, "%s: BACK closes MORE" % tag)


func _pause(tag: String) -> void:
	var prog := Game.progress as Progress
	TestLib.check(prog != null, "the campaign exists")
	_state(&"paused")
	var ids := _ids()
	TestLib.check(ids.size() == 6 and ids.has(&"board_open") and ids.has(&"resume") and ids.has(&"pause_map") and ids.has(&"loadout") and ids.has(&"options") and ids.has(&"menu_gear"), "%s: the pause menu shows RESUME, MAP, LOADOUT, OPTIONS and MORE (%s)" % [tag, str(ids)])
	_sane(tag + " pause")
	var tm := main.find_children("*", "TestMenu", true, false)
	TestLib.check(tm.is_empty() or (tm[0] as TestMenu).entry_rect().size.x == 0.0, "%s: no TEST badge on the pause menu" % tag)


func _more(tag: String) -> void:
	_state(&"paused")
	hud.press_button(&"menu_gear")
	_layout()
	var ids := _ids()
	for want: StringName in [&"hero_open", &"side_open", &"heist_open", &"look_open", &"sh_open", &"ach", &"photo_open", &"arena_open", &"menu", &"more_back"]:
		TestLib.check(ids.has(want), "%s: the pause MORE page has %s" % [tag, want])
	TestLib.check(ids.size() <= 12, "%s: the MORE page is one grid (%d cells)" % [tag, ids.size()])
	_sane(tag + " pause MORE")
	hud.press_button(&"more_back")


## The HERO hub: UPGRADES / WEAPONS / SKILLS / CRAFT are tabs of one screen; an upgrade is one tap on its row; BACK leaves the hub.
func _hero() -> void:
	var prog := Game.progress as Progress
	WeaponDefs.reset_unlocked()
	prog.credits = 0
	_state(&"paused")
	hud.press_button(&"menu_gear")
	TestLib.check(hud.press_button(&"hero_open") and hud._hero_hub and hud._shop_open, "HERO opens the hub on UPGRADES")
	_layout()
	var ids := _ids()
	for t: StringName in [&"hero_tab_up", &"hero_tab_weapons", &"hero_tab_skills", &"hero_tab_craft"]:
		TestLib.check(ids.has(t), "the UPGRADES tab shows the tab %s" % t)
	TestLib.check(Upgrades.IDS.all(func(u: StringName) -> bool: return ids.has(StringName("buy_%s" % u))), "every upgrade has its row")
	TestLib.check(not ids.has(&"loadout") and not ids.has(&"side_open") and not ids.has(&"look_open") and not ids.has(&"heist_open"), "the shop is not a menu of menus any more")
	TestLib.check(not bool(_btn(&"buy_damage")["on"]), "without credits no row is lit")
	TestLib.check(not hud.press_button(&"buy_damage") and prog.level(&"damage") == 0, "a row that is not affordable does nothing")
	var price := prog.price(&"damage")
	prog.credits = price + 5
	_layout()
	TestLib.check(bool(_btn(&"buy_damage")["on"]), "an affordable row lights up")
	var rect: Rect2 = _btn(&"buy_damage")["rect"]
	TestLib.check(hud.tap(rect.get_center()) and prog.level(&"damage") == 1 and prog.credits == 5, "one tap anywhere on the row buys the upgrade")
	TestLib.check(hud.press_button(&"hero_tab_skills") and hud._skills_open and not hud._craft_open, "the SKILLS tab shows the skill tree")
	_layout()
	TestLib.check(_ids().has(&"hero_tab_up") and _ids().has(&"sk_back") and _btn(&"hero_tab_skills")["on"], "the tab bar stays on the skills screen with SKILLS lit")
	TestLib.check(hud.press_button(&"hero_tab_craft") and hud._craft_open and not hud._skills_open, "the CRAFT tab shows the workbench")
	_layout()
	TestLib.check(_ids().has(&"hero_tab_up") and _ids().has(&"cr_back"), "the tab bar stays on the workbench")
	TestLib.check(hud.press_button(&"hero_tab_weapons") and ShopScreen.weapon_page == 1 and not hud._craft_open, "the WEAPONS tab shows the weapon page")
	TestLib.check(hud.press_button(&"hero_tab_up") and ShopScreen.weapon_page == 0, "the UPGRADES tab returns")
	TestLib.check(hud.press_button(&"shop_back") and not hud._hero_hub and not hud._shop_open and Game.state == &"paused", "BACK leaves the hub for the pause menu")
	TestLib.check(not hud.press_button(&"hero_tab_skills"), "the tabs do nothing outside the hub")
	prog.credits = 0


## MAP on the pause menu opens the real map and closing it returns to the pause menu.
func _map() -> void:
	_state(&"paused")
	TestLib.check(hud.press_button(&"pause_map"), "MAP is handled")
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	TestLib.check(ms != null and ms.is_open(), "the map screen is open")
	if ms != null:
		ms.close_screen()
		TestLib.check(not ms.is_open() and Game.state == &"paused", "closing the map returns to the paused game")


## A screen opened from MORE returns to MORE; a screen opened from the pause menu returns to the pause menu.
func _back_navigation() -> void:
	_state(&"paused")
	hud.press_button(&"menu_gear")
	TestLib.check(hud.press_button(&"side_open") and hud._side_open, "MISSIONS opens from MORE")
	TestLib.check(hud.press_button(&"side_back") and not hud._side_open and hud._gear_open, "BACK from MISSIONS returns to the MORE page")
	TestLib.check(hud.press_button(&"more_back") and not hud._gear_open, "BACK from MORE returns to the pause menu")
	TestLib.check(hud.press_button(&"loadout") and hud._loadout_open, "LOADOUT opens from the pause menu")
	TestLib.check(hud.press_button(&"loadout_back") and not hud._loadout_open and not hud._gear_open and Game.state == &"paused", "BACK from LOADOUT returns to the pause menu")
	TestLib.check(hud.press_button(&"options") and hud._options_open, "OPTIONS opens from the pause menu")
	TestLib.check(hud.press_button(&"options_back") and not hud._options_open and Game.state == &"paused", "BACK from OPTIONS returns to the pause menu")
	hud.press_button(&"resume")
	TestLib.check(Game.state == &"play" and not hud._gear_open, "RESUME plays and MORE is closed")
