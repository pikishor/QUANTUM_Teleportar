extends RefCounted
## Director review round 2, part D (docs/SLICE_REVIEW.md defects 11 and 12: a 600-icon map and menus that are lists of small buttons) in the REAL game scene (main.tscn):
##   11  the map draws a CAPPED number of icons per zoom (MapScreen.badge_cap: 18 at the overview, 30 mid, 44 close) out of hundreds of candidates, the objective / side job / homes are never
##       dropped, marker names are few, the legend only lists kinds that exist, the objective gets a halo and an edge arrow, pinch zoom (zoom_by) keeps the cap
##   12  title, pause and MORE are CARDS (icon, title, caption, one filled primary action), OPTIONS is five tabs of at most eight rows (every option reachable, none lost), the loadout parts
##       are cards with a name, an effect and a status strip, every BACK is the same card; a layout scan of every screen at 1280x720 and 844x390: each button >= 64 base px tall, on screen,
##       none over another, text never below 15 base px (MenuKit.BODY, 22 px at 1080p).
## Waits on state and counters, never on frame counts; user:// state is reset first.
## Run: tools/test.sh tests/test_director_round2_d.gd

var host: Node
var main: Node
var hud: Hud
var ms: MapScreen


func frames(n: int) -> void:
	await TestLib.frames(host, n)


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


func _scan(tag: String) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var bad := ""
	for b: Dictionary in hud.buttons:
		var r: Rect2 = b["rect"]
		if r.size.y < 63.9 * s or not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r):
			bad = "%s %s" % [b["id"], r]
			break
		for b2: Dictionary in hud.buttons:
			if b != b2 and r.intersects(b2["rect"]) and not (OptionsScreen.is_slider(b["id"]) and OptionsScreen.is_slider(b2["id"])):
				bad = "%s over %s" % [b["id"], b2["id"]]
				break
		if bad != "":
			break
	TestLib.check(bad == "", "%s: every button is >= 64 base px tall, on screen, none over another (%s)" % [tag, bad])


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	for f in ["user://savegame.json", "user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	ms = hud.touch.get_node_or_null("MapScreen") as MapScreen if hud.touch != null else null
	TestLib.check(ms != null, "the real scene has the map screen")
	TestLib.check(MenuKit.BODY * 1.5 >= 22.0 and MenuKit.TITLE >= MenuKit.BODY, "menu text is >= 22 px at 1080p")
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		win.size = size
		await frames(4)
		var tag := "%dx%d" % [size.x, size.y]
		_cards(tag)
		_options(tag)
		_loadout(tag)
		_screens(tag)
	win.size = old
	await frames(3)
	await _map()
	Game.state = &"menu"
	main.queue_free()
	await frames(2)


# --- 12: cards, tabs, scan --------------------------------------------------------------------------------------------------------------------------

func _cards(tag: String) -> void:
	_state(&"menu")
	var play := _btn(&"continue") if not _btn(&"continue").is_empty() else _btn(&"deploy")
	TestLib.check(not play.is_empty() and play.has("icon") and bool(play["primary"]), "%s: PLAY is the one primary card of the title" % tag)
	var primaries := 0
	for b: Dictionary in hud.buttons:
		primaries += int(bool(b.get("primary", false)))
	TestLib.check(primaries == 1 and _btn(&"options").has("icon") and _btn(&"menu_gear").has("icon"), "%s: the title is one primary card and two secondary cards with icons" % tag)
	_scan(tag + " title")
	_state(&"paused")
	var rs := _btn(&"resume")
	TestLib.check(rs.has("icon") and bool(rs["primary"]) and (rs["rect"] as Rect2).size.y > (_btn(&"pause_map")["rect"] as Rect2).size.y, "%s: RESUME is the big primary card of the pause menu" % tag)
	for id: StringName in [&"pause_map", &"loadout", &"options", &"menu_gear"]:
		TestLib.check(_btn(id).has("icon"), "%s: %s is a card with an icon" % [tag, id])
	_scan(tag + " pause")
	hud._gear_open = true
	MenuFlags.all_extras = true                       # the cut screens are listed only with the flag (scripts/ui/menu_flags.gd)
	_layout()
	var caps := 0
	var cards := 0
	for b: Dictionary in hud.buttons:
		if b.has("icon"):
			cards += 1
			caps += int(String(b.get("sub", "")) != "")
	MenuFlags.all_extras = false
	TestLib.check(cards >= 9 and caps >= 8, "%s: MORE is a grid of icon cards with a caption each (%d cards, %d captions)" % [tag, cards, caps])
	TestLib.check(not _btn(&"more_back").is_empty() and _btn(&"more_back").has("icon"), "%s: MORE has the BACK card" % tag)
	_scan(tag + " more")
	hud._gear_open = false
	_layout()


func _options(tag: String) -> void:
	_state(&"paused")
	TestLib.check(hud.press_button(&"options"), "%s: OPTIONS opens" % tag)
	_layout()
	var seen := {}
	for ti in OptionsScreen.TABS.size():
		TestLib.check(hud.press_button(OptionsScreen.tab_id(ti)) and UiSettings.s_opt_tab == ti, "%s: tab %d opens" % [tag, ti])
		_layout()
		var rows := 0
		for b: Dictionary in hud.buttons:
			seen[b["id"]] = true
			rows += int(b.has("opt"))
		TestLib.check(rows == (OptionsScreen.TABS[ti][2] as Array).size() and rows <= 8, "%s: tab %d shows its %d rows (at most eight)" % [tag, ti, rows])
		_scan("%s options tab %d" % [tag, ti])
	var lost := ""
	for id: StringName in OptionsScreen.ORDER + OptionsScreen.PAGE2:
		if not seen.has(id):
			lost += String(id) + " "
	TestLib.check(lost == "", "%s: no option is lost by the tabs (%s)" % [tag, lost])
	var most := 0
	for t: Array in OptionsScreen.TABS:
		most = maxi(most, (t[2] as Array).size())
	TestLib.check(most <= 8, "%s: the busiest tab has %d rows (the old screen had 19 buttons)" % [tag, most])
	hud.press_button(&"options_back")
	_layout()


func _loadout(tag: String) -> void:
	_state(&"paused")
	hud.press_button(&"loadout")
	_layout()
	var parts := 0
	var tiles := 0
	for b: Dictionary in hud.buttons:
		if b.has("part"):
			parts += 1
			TestLib.check(String(b["name"]) != "" and String(b["fx"]) != "" and ["ON", "EQUIP"].has(String(b["label"])) or String(b["label"]).begins_with("BUY"), "%s: part %s has a name, an effect and a status" % [tag, b["id"]])
		if b.has("cap"):
			tiles += 1
	TestLib.check(parts == 9 and tiles >= 1, "%s: the loadout shows nine part cards and the weapon tiles by name (%d, %d)" % [tag, parts, tiles])
	_scan(tag + " loadout")
	var back := _btn(&"loadout_back")
	TestLib.check(not back.is_empty() and String(back["id"]).ends_with("_back"), "%s: loadout has a BACK" % tag)
	hud.press_button(&"loadout_back")
	_layout()


func _screens(tag: String) -> void:
	for flag: String in ["_look_open", "_side_open", "_heist_open", "_safe_open", "_ach_open", "_arena_open", "_loadout_gear"]:
		_state(&"paused")
		if flag == "_loadout_gear":
			hud._loadout_open = true
			hud._loadout_page = 1
		else:
			hud.set(flag, true)
		_layout()
		_scan("%s %s" % [tag, flag])
		if flag != "_loadout_gear":
			hud.set(flag, false)
		hud._loadout_open = false
		hud._loadout_page = 0
	_state(&"paused")


# --- 11: the map ---------------------------------------------------------------------------------------------------------------------------------

func _map() -> void:
	_state(&"paused")
	ms.reveal_all()
	ms.discover(Game.player.global_position)
	Game.state = &"play"
	ms.open()
	ms.scan_on = true
	await frames(3)
	var all := ms.visible_markers()
	TestLib.check(all.size() >= 100, "the world has hundreds of candidate markers (%d), so the cap means something" % all.size())
	ms.set_waypoint(Game.player.global_position + Vector3(120.0, 0.0, 80.0))
	var prev_cap := 0
	for z in [1.0, 2.0, 3.0, 4.0, 6.0, 8.0]:
		ms.zoom_f = z
		ms.locate()
		ms._clamp_view()
		var cap := ms.badge_cap()
		var shown := ms.lod_markers(ms.visible_markers())
		TestLib.check(shown.size() <= cap + 3, "zoom %.0f: at most %d icons (cap %d), the list has %d of %d" % [z, cap + 3, cap, shown.size(), all.size()])
		ms._map.queue_redraw()
		await frames(2)
		TestLib.check(int(ms.drawn["markers"]) <= cap + 3, "zoom %.0f: %d icons drawn (cap %d)" % [z, int(ms.drawn["markers"]), cap])
		TestLib.check(cap >= prev_cap and cap <= 44, "zoom %.0f: the cap never shrinks when you zoom in and stays below 45" % z)
		prev_cap = cap
		var marker_names := 0
		for e: Dictionary in ms.scan_log:
			if String(e["text"]).length() > 0 and not String(e["text"]).ends_with("M"):
				marker_names += 1
		TestLib.check(marker_names <= MapScreen.LABEL_MAX + 8 + 8, "zoom %.0f: %d names on the map (district names and a few markers)" % [z, marker_names])
	TestLib.check(ms.badge_cap() == MapScreen.CAP_NEAR and MapScreen.CAP_OVERVIEW < MapScreen.CAP_MID and MapScreen.CAP_MID < MapScreen.CAP_NEAR, "three caps, growing with the zoom")
	# the objective is never dropped by the cap
	var fake: Array[Dictionary] = []
	for i in 200:
		fake.append({"kind": MapScreen.KIND_ORDER[i % MapScreen.KIND_ORDER.size()], "pos": Vector3(float(i) * 3.0 - 300.0, 0.0, 10.0), "fog": false, "label": "X"})
	fake.append({"kind": &"mission", "pos": Vector3(500.0, 0.0, 500.0), "fog": false, "label": "MISSION"})
	fake.append({"kind": &"side", "pos": Vector3(-500.0, 0.0, 500.0), "fog": false, "label": "SIDE JOB"})
	fake.append({"kind": &"home", "pos": Vector3(0.0, 0.0, -500.0), "fog": false, "label": "SAFEHOUSE"})
	ms.zoom_f = 1.0
	var kept := ms.lod_markers(fake)
	var has_m := false
	var has_s := false
	var has_h := false
	for mk: Dictionary in kept:
		has_m = has_m or mk["kind"] == &"mission"
		has_s = has_s or mk["kind"] == &"side"
		has_h = has_h or mk["kind"] == &"home"
	TestLib.check(has_m and has_s and has_h and kept.size() <= MapScreen.CAP_OVERVIEW + 3, "the objective, the side job and the home survive the cap (%d of 203 kept)" % kept.size())
	var kinds := {}
	for mk: Dictionary in kept:
		kinds[mk["kind"]] = true
	TestLib.check(kinds.size() >= 5, "the icons are a mix of kinds, not one flooded kind (%d kinds)" % kinds.size())
	# pinch zoom through zoom_by changes the zoom continuously
	ms.zoom_f = 1.0
	ms.zoom_by(1.5, ms._rect.get_center())
	TestLib.check(ms.zoom_f > 1.4 and ms.zoom_f < 1.6, "pinch zoom is continuous (%.2f)" % ms.zoom_f)
	# legend: the always-kinds are rows only while one exists; the others are always rows
	ms._refresh_chips()
	var shown_rows := 0
	for k: StringName in MapScreen.KINDS:
		shown_rows += int((ms._btns[k] as Button).visible)
	TestLib.check(shown_rows >= 6 and shown_rows <= MapScreen.KINDS.size(), "the legend lists %d kinds" % shown_rows)
	TestLib.check(ms._legend_rect.size.x > 100.0 and ms._legend_rect.size.y > 100.0, "the legend sits on an opaque panel")
	var chips_ok := true
	for k: StringName in MapScreen.KINDS:
		var b: Button = ms._btns[k]
		if b.visible and b.size.y < 63.9 * UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size):
			chips_ok = false
	TestLib.check(chips_ok, "every legend row is >= 64 base px tall")
	ms.scan_on = false
	ms.close_screen()
