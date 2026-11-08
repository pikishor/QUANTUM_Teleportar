extends RefCounted
## Menu cut, loadout, weapon wheel and map (docs/DESIGN.md "Cut or hide"; real scene, main.tscn). Checks:
##  1. control counts: the title shows PLAY / CONTINUE, OPTIONS, EXTRAS; the pause menu RESUME, MISSIONS, MAP, LOADOUT, UPGRADES, OPTIONS, EXTRAS (nothing else); the EXTRAS page lists the
##     kept extras only, the cut screens (side jobs, heists, safehouse, achievements, boss rush) join it behind MenuFlags (Options > GAME > ALL EXTRAS, the DEMO); the HERO hub has two tabs
##     (UPGRADES, WEAPONS), four behind the flag.
##  2. exactly one BACK (or RESUME) on every screen that has one, never two (also after the watchdog's idle time), 64 px targets, on screen, none overlapping, at three window sizes.
##  3. the LOADOUT has a LARGE picture of the weapon (its own 384 x 192 render), four stat bars, a "where to get it" line, and nothing overlaps the picture.
##  4. the weapon wheel is laid out around the thumb (the button that opened it), every disc is on screen and clear of the others, every other button is hidden and inactive while it is
##     open, it closes on release and picks what the thumb dragged to; the ability wheel fans out over the free side of the screen.
##  5. the map starts mostly uncharted, reveals fast (a wide radius, wider when fast), has a ground texture (never a black field), big icons and legend chips with room for the icon.
## Waits on state, never on frame counts. Run: tools/test.sh tests/test_menu_cut.gd

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
	var bad := ""
	for b: Dictionary in hud.buttons:
		var r: Rect2 = b["rect"]
		if r.size.y < 63.9 * s or not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r):
			bad = "%s %s" % [b["id"], r]
		for b2: Dictionary in hud.buttons:
			if b != b2 and r.intersects(b2["rect"]):
				bad = "%s over %s" % [b["id"], b2["id"]]
	TestLib.check(bad == "", "%s: every button is 64 base px, on screen, none overlaps (%s)" % [tag, bad])


## How many buttons close the screen: ids ending in _back, plus a button labelled BACK / RESUME.
func _backs() -> int:
	var n := 0
	for b: Dictionary in hud.buttons:
		var id := String(b["id"])
		var lab := String(b["label"])
		if id.ends_with("_back") or lab == "BACK" or lab == "RESUME" or id == "resume" or id == "shop_back":
			n += 1
	return n


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	var saved_flag := MenuFlags.all_extras
	MenuFlags.all_extras = false
	Upgrades.show_all = false
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	hud.settings.all_extras = false
	MenuFlags.all_extras = false
	if hud.touch != null:
		hud.touch.controls_on = true
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390), Vector2i(1200, 540)]:
		win.size = size
		await frames(4)
		var tag := "%dx%d" % [size.x, size.y]
		_counts(tag)
		_extras(tag)
		_hub(tag)
		await _single_back(tag)
		await _loadout(tag)
		await _wheel(tag)
	win.size = old
	await frames(3)
	_flag_option()
	await _map()
	MenuFlags.all_extras = saved_flag
	hud.settings.all_extras = saved_flag
	hud.settings.save()
	Game.state = &"play"
	hud._gear_open = false
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


# --- 1 -------------------------------------------------------------------------------------------------------------------------

func _counts(tag: String) -> void:
	_state(&"menu")
	var ids := _ids()
	TestLib.check(ids.size() == 3 and ids.has(&"options") and ids.has(&"menu_gear") and (ids.has(&"deploy") or ids.has(&"continue")), "%s: the title has 3 buttons: PLAY / CONTINUE, OPTIONS, EXTRAS (%s)" % [tag, str(ids)])
	TestLib.check(String(_btn(&"menu_gear")["label"]) == "EXTRAS", "%s: the old MORE button is called EXTRAS" % tag)
	_sane(tag + " title")
	_state(&"paused")
	ids = _ids()
	var want: Dictionary = {&"resume": "RESUME", &"pause_map": "MAP", &"loadout": "LOADOUT", &"hero_open": "UPGRADES", &"options": "OPTIONS", &"menu_gear": "EXTRAS"}
	if MissionBoardScreen.board() != null:
		want[&"board_open"] = "MISSIONS"
	TestLib.check(ids.size() == want.size(), "%s: the pause menu has %d buttons (%s)" % [tag, want.size(), str(ids)])
	for id: StringName in want:
		TestLib.check(ids.has(id) and String(_btn(id).get("label", "")) == want[id], "%s: the pause menu shows %s" % [tag, want[id]])
	_sane(tag + " pause")
	var tm := main.find_children("*", "TestMenu", true, false)
	TestLib.check(tm.is_empty() or (tm[0] as TestMenu).entry_rect().size.x == 0.0, "%s: no TEST badge on the pause menu" % tag)


func _extras(tag: String) -> void:
	MenuFlags.all_extras = false
	_state(&"paused")
	TestLib.check(hud.press_button(&"menu_gear") and hud._gear_open, "%s: EXTRAS opens from the pause menu" % tag)
	_layout()
	var ids := _ids()
	for keep: StringName in [&"look_open", &"photo_open", &"menu", &"more_back"]:
		TestLib.check(ids.has(keep), "%s: EXTRAS keeps %s" % [tag, keep])
	for cut: StringName in MenuFlags.CUT:
		TestLib.check(not ids.has(cut), "%s: EXTRAS hides the cut screen %s by default" % [tag, cut])
	TestLib.check(ids.size() <= 6, "%s: the default EXTRAS page is short (%d cells)" % [tag, ids.size()])
	_sane(tag + " extras")
	hud.press_button(&"more_back")
	MenuFlags.all_extras = true
	_state(&"paused")
	hud.press_button(&"menu_gear")
	_layout()
	ids = _ids()
	for id: StringName in [&"side_open", &"heist_open", &"sh_open", &"ach", &"arena_open", &"look_open", &"photo_open", &"menu", &"more_back"]:
		TestLib.check(ids.has(id), "%s: with the flag on EXTRAS lists %s" % [tag, id])
	TestLib.check(ids.size() <= 12, "%s: the full EXTRAS page is one grid (%d cells)" % [tag, ids.size()])
	_sane(tag + " extras (all)")
	hud.press_button(&"more_back")
	for id: StringName in [&"heist_open", &"sh_open", &"arena_open", &"ach", &"side_open"]:                 # the code stays: a screen opens when its button is pressed, flag or not
		TestLib.check(hud.press_button(id), "%s: the cut screen %s still opens by its id (code kept)" % [tag, id])
		_close_all()
	MenuFlags.all_extras = false
	_state(&"menu")
	TestLib.check(hud.press_button(&"menu_gear"), "%s: EXTRAS opens on the title" % tag)
	_layout()
	ids = _ids()
	TestLib.check(ids.has(&"demo") and ids.has(&"more_back") and not ids.has(&"arena_open"), "%s: the title EXTRAS lists DEMO, not the boss rush (%s)" % [tag, str(ids)])
	_sane(tag + " title extras")
	hud.press_button(&"more_back")


func _close_all() -> void:
	hud._heist_open = false
	hud._safe_open = false
	hud._arena_open = false
	hud._ach_open = false
	hud._side_open = false
	hud._gear_open = false
	hud._layout_key = ""


func _hub(tag: String) -> void:
	MenuFlags.all_extras = false
	_state(&"paused")
	TestLib.check(hud.press_button(&"hero_open") and hud._hero_hub and hud._shop_open, "%s: UPGRADES opens the hub on the upgrades page" % tag)
	_layout()
	var tabs := _ids().filter(func(i: StringName) -> bool: return String(i).begins_with("hero_tab_"))
	TestLib.check(tabs.size() == 2 and tabs.has(&"hero_tab_up") and tabs.has(&"hero_tab_weapons"), "%s: the hub has two tabs by default (%s)" % [tag, str(tabs)])
	hud.press_button(&"shop_back")
	MenuFlags.all_extras = true
	_state(&"paused")
	hud.press_button(&"hero_open")
	_layout()
	tabs = _ids().filter(func(i: StringName) -> bool: return String(i).begins_with("hero_tab_"))
	TestLib.check(tabs.size() == 4, "%s: with the flag the hub also has SKILLS and CRAFT (%s)" % [tag, str(tabs)])
	hud.press_button(&"shop_back")
	MenuFlags.all_extras = false
	TestLib.check(MenuFlags.offered(&"side_open") == false and MenuFlags.offered(&"look_open"), "%s: MenuFlags.offered follows the flag" % tag)


# --- 2 -------------------------------------------------------------------------------------------------------------------------

func _single_back(tag: String) -> void:
	var wd := host.get_tree().root.find_child("ScreenWatchdog", true, false) as ScreenWatchdog
	var screens: Array = [
		["extras", [&"menu_gear"], 1], ["upgrades", [&"hero_open"], 1], ["weapons p1", [&"hero_open", &"hero_tab_weapons"], 1], ["weapons p2", [&"hero_open", &"hero_tab_weapons", &"wpg_next"], 1],
		["weapons p3", [&"hero_open", &"hero_tab_weapons", &"wpg_next", &"wpg_next"], 1], ["loadout", [&"loadout"], 1], ["gear", [&"loadout", &"loadout_gear"], 1], ["options", [&"options"], 1],
		["suit", [&"menu_gear", &"look_open"], 1],
	]
	if MissionBoardScreen.board() != null:
		screens.append(["board", [&"board_open"], 1])
	for sc: Array in screens:
		MenuFlags.all_extras = false
		_state(&"paused")
		for id: StringName in sc[1]:
			hud.press_button(id)
			_layout()
		var n := _backs()
		TestLib.check(n == int(sc[2]), "%s: %s has exactly one BACK (%d)" % [tag, sc[0], n])
		if wd != null:
			wd.force_idle(10.0)                                   # a long idle on a screen with its own BACK adds no second one
			await frames(2)
			TestLib.check(not wd.shown(), "%s: %s: the watchdog adds no second BACK after 10 s" % [tag, sc[0]])
			wd.force_idle(0.0)
		_sane("%s %s" % [tag, sc[0]])
		hud._shop_open = false
		hud._hero_hub = false
		hud._loadout_open = false
		hud._loadout_page = 0
		hud._options_open = false
		hud._look_open = false
		hud._board_open = false
		hud._gear_open = false
		ShopScreen.weapon_page = 0
	MenuFlags.all_extras = false


# --- 3 -------------------------------------------------------------------------------------------------------------------------

func _loadout(tag: String) -> void:
	MenuFlags.all_extras = false
	WeaponDefs.reset_unlocked()
	_state(&"paused")
	TestLib.check(hud.press_button(&"loadout") and hud._loadout_open, "%s: LOADOUT opens" % tag)
	_layout()
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var cx := vp.x * 0.5
	var pic := LoadoutScreen.picture_rect(cx, s, LoadoutScreen.k_of(vp.x, s))
	TestLib.check(pic.size.x >= 480.0 * s and pic.size.y >= 240.0 * s, "%s: the loadout picture plate is LARGE (%.0f x %.0f base px)" % [tag, pic.size.x / s, pic.size.y / s])
	TestLib.check(Rect2(Vector2.ZERO, vp).encloses(pic), "%s: the picture is on screen" % tag)
	var clash := ""
	for b: Dictionary in hud.buttons:
		if pic.intersects(b["rect"]):
			clash = String(b["id"])
	TestLib.check(clash == "", "%s: no button overlaps the weapon picture (%s)" % [tag, clash])
	for w: StringName in WeaponDefs.owned_ordered():
		var big := ItemIcons.weapon_large(w)
		TestLib.check(big != null and big.get_size().x >= 380.0, "%s: %s has its large picture (%s)" % [tag, w, str(big.get_size()) if big != null else "none"])
		var card := WeaponStats.card(w, Attachments.effective(w))
		for key: StringName in [&"damage", &"rate", &"range", &"accuracy"]:
			TestLib.check(card["bars"].has(key), "%s: %s has the %s bar" % [tag, w, key])
		TestLib.check(WeaponStats.where(w).size() >= 1, "%s: %s says where to get it" % [tag, w])
	# the picture changes with the selection
	var owned := WeaponDefs.owned_ordered()
	var other: StringName = owned[owned.size() - 1]
	TestLib.check(hud.press_button(StringName("wheel_%s" % other)) and hud._loadout_w == other, "%s: tapping a tile selects its weapon (%s)" % [tag, other])
	# a text scan of the screen: nothing off screen, no text over text
	hud.scan_log.clear()
	hud.scan_text = true
	hud._screen.queue_redraw()
	for i in 90:
		await frames(1)
		if not hud.scan_log.is_empty():
			break
	await frames(1)
	hud.scan_text = false
	var bad: Array[String] = []
	var seen := {}
	var log: Array[Dictionary] = []
	for e0: Dictionary in hud.scan_log:
		var key := "%s|%s" % [e0["text"], e0["rect"]]
		if not seen.has(key):
			seen[key] = true
			log.append(e0)
	var screen := Rect2(Vector2.ZERO, vp).grow(2.0)
	var wheres := 0
	for e: Dictionary in log:
		if not screen.encloses(e["rect"]):
			bad.append("off screen '%s'" % e["text"])
		if String(e["text"]).begins_with("WHERE"):
			wheres += 1
	for i in log.size():
		for j in range(i + 1, log.size()):
			var a: Rect2 = log[i]["rect"]
			var b: Rect2 = log[j]["rect"]
			if a.intersection(b).get_area() > 0.25 * minf(a.get_area(), b.get_area()):
				bad.append("text overlap '%s' / '%s'" % [log[i]["text"], log[j]["text"]])
	TestLib.check(bad.is_empty(), "%s: the loadout texts are clean (%d texts): %s" % [tag, log.size(), "; ".join(bad.slice(0, 5))])
	TestLib.check(wheres >= 1, "%s: the loadout prints a WHERE line" % tag)
	hud.press_button(&"loadout_back")


# --- 4 -------------------------------------------------------------------------------------------------------------------------

func _wheel(tag: String) -> void:
	var tc := hud.touch
	var vp := tc._vp_size()
	var s := tc._scale()
	_state(&"play")
	tc.controls_on = true
	await frames(2)
	var weapon := {}
	var fire := {}
	var ability := {}
	for b: Dictionary in TouchControls.BUTTONS:
		match b["action"]:
			&"swap":
				weapon = b
			&"fire":
				fire = b
			&"ability":
				ability = b
	for kind: StringName in [&"weapon", &"ability"]:
		var btn: Dictionary = weapon if kind == &"weapon" else ability
		var thumb := tc._button_center(btn)
		tc.touch_down(90, thumb)
		if kind == &"weapon":
			tc._swap_held = TouchControls.WHEEL_HOLD
			tc._process(0.0)
		TestLib.check(tc.wheel.is_open and tc.wheel.kind == kind, "%s: holding %s opens its wheel" % [tag, kind])
		TestLib.check(tc.wheel.centre.distance_to(thumb) < 1.0, "%s: the %s wheel is centred on the thumb (the button), not on the screen" % [tag, kind])
		var rr := RadialWheel.ITEM_R * s
		var inside := true
		var apart := true
		var n := tc.wheel.items.size()
		for i in n:
			var c := tc.wheel.item_centre(i)
			inside = inside and c.x - rr >= 0.0 and c.x + rr <= vp.x and c.y - rr >= 0.0 and c.y + rr <= vp.y
			for j in range(i + 1, n):
				apart = apart and c.distance_to(tc.wheel.item_centre(j)) >= 2.0 * rr - 1.0
		TestLib.check(inside and n >= 5, "%s: every %s disc is on screen (%d discs)" % [tag, kind, n])
		TestLib.check(apart, "%s: no two %s discs touch" % [tag, kind])
		# the other buttons are not drawn and do not answer while the wheel is up
		var fired := false
		tc.touch_down(91, tc._button_center(fire))
		fired = Input.is_action_pressed(&"fire")
		tc.touch_up(91)
		TestLib.check(not fired, "%s: FIRE does not answer under the open %s wheel" % [tag, kind])
		# drag to the last disc and release: it picks and the wheel closes
		var target := n - 1
		var at := tc.wheel.item_centre(target)
		tc._wheel_held = 0.6
		tc.touch_move(90, at, at - thumb)
		TestLib.check(tc.wheel.sel == target, "%s: dragging to disc %d highlights it" % [tag, target])
		tc.touch_up(90)
		TestLib.check(not tc.wheel.is_open, "%s: releasing closes the %s wheel" % [tag, kind])
		tc.release_all()
		await frames(2)
		TestLib.check(tc.layer == 9, "%s: the touch layer is back under the HUD after the wheel" % tag)
	TestLib.check(RadialWheel.min_step_deg() <= 36.0, "wheel discs of one radius can sit 36 degrees apart")
	# a thumb at the bottom edge: the discs fan over the free side
	var w2 := RadialWheel.new()
	var items: Array = []
	for i in 7:
		items.append({"id": StringName("x%d" % i)})
	var bounds := Rect2(Vector2(80, 80), vp - Vector2(160, 160))
	w2.open_at(&"ability", items, Vector2(vp.x * 0.7, vp.y - 60.0), s, false, bounds)
	TestLib.check(w2.span_deg < 359.0, "%s: a thumb at the bottom edge fans the wheel out (%.0f degrees)" % [tag, w2.span_deg])
	var all_in := true
	for i in 7:
		var c := w2.item_centre(i)
		all_in = all_in and c.y <= vp.y - 40.0 + 1.0
	TestLib.check(all_in, "%s: no disc of a bottom-edge wheel falls below the screen" % tag)


# --- flag ----------------------------------------------------------------------------------------------------------------------

func _flag_option() -> void:
	MenuFlags.all_extras = false
	hud.settings.all_extras = false
	_state(&"paused")
	TestLib.check(hud.press_button(&"options"), "OPTIONS opens")
	UiSettings.s_opt_tab = OptionsScreen.tab_of(&"opt_extras")
	_layout()
	TestLib.check(_ids().has(&"opt_extras"), "ALL EXTRAS is a row of the GAME tab")
	TestLib.check(hud.press_button(&"opt_extras") and hud.settings.all_extras and MenuFlags.all_extras, "pressing ALL EXTRAS turns the flag on")
	TestLib.check(MenuFlags.show_cut(), "the cut screens are offered")
	hud.press_button(&"opt_extras")
	TestLib.check(not hud.settings.all_extras and not MenuFlags.all_extras, "and off again")
	hud.press_button(&"options_back")


# --- 5 -------------------------------------------------------------------------------------------------------------------------

func _map() -> void:
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	TestLib.check(ms != null, "the map exists")
	if ms == null:
		return
	ms.forget()
	var share := 100.0 * float(ms.discovered_count()) / float(MapScreen.CELLS * MapScreen.CELLS)
	TestLib.check(share <= 8.0, "a fresh map is mostly uncharted (%.1f %% charted)" % share)
	TestLib.check(ms.reveal_radius() >= MapScreen.DISCOVER_R and ms.reveal_radius() <= MapScreen.DISCOVER_R_MAX, "the reveal radius is %.0f m (on foot at least %.0f)" % [ms.reveal_radius(), MapScreen.DISCOVER_R])
	var p := Game.player as Node3D
	var n0 := ms.discovered_count()
	ms.discover(p.global_position + Vector3(400.0, 0.0, 0.0), ms.reveal_radius())
	var n1 := ms.discovered_count()
	TestLib.check(n1 - n0 >= 60, "one reveal charts at least 60 cells (%d new)" % (n1 - n0))
	ms.forget()
	_state(&"paused")
	ms.open()
	await frames(4)
	TestLib.check(ms.is_open(), "the map opens")
	var open_share := 100.0 * float(ms.discovered_count()) / float(MapScreen.CELLS * MapScreen.CELLS)
	TestLib.check(open_share <= 25.0, "at the first open the map is still mostly uncharted (%.1f %%)" % open_share)
	var tex := MapScreen.ground_texture()
	TestLib.check(tex != null and tex.get_width() == MapScreen.GROUND_N, "the map has a ground texture")
	var img := tex.get_image()
	var darkest := 1.0
	for y in range(0, MapScreen.GROUND_N, 4):
		for x in range(0, MapScreen.GROUND_N, 4):
			darkest = minf(darkest, img.get_pixel(x, y).get_luminance())
	TestLib.check(darkest > 0.07, "the ground is never black (darkest sample %.2f)" % darkest)
	ms.set_zoom(1)
	await frames(3)
	TestLib.check(int(ms.drawn.get("roads", 0)) > 20 and int(ms.drawn.get("lots", 0)) > 100, "the whole-city view draws the street grid and the buildings (%s)" % str(ms.drawn))
	TestLib.check(MapScreen.BADGE_R >= 24.0 and MapScreen.BADGE_R_NEAR >= MapScreen.BADGE_R, "the marker icons are big (%.0f base px radius)" % MapScreen.BADGE_R)
	# the legend: every chip is a 64 px button tall enough for the icon and keeps a text margin
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var chips := 0
	for k in MapScreen.KINDS:
		var b := ms._btns.get(k) as Button
		if b != null and b.visible:
			chips += 1
			TestLib.check(b.size.y >= 63.5 * s * 0.99 or b.size.y >= 63.5, "legend chip %s is a 64 px target" % k)
			var sb := b.get_theme_stylebox("pressed") as StyleBoxFlat
			TestLib.check(sb != null and sb.content_margin_left >= 46.0, "legend chip %s leaves room for its icon" % k)
			TestLib.check(b.get_theme_font_size("font_size") >= int(20.0 * s), "legend chip %s text is readable (%d px)" % [k, b.get_theme_font_size("font_size")])
	TestLib.check(chips >= 4, "the legend lists the kinds on the map (%d)" % chips)
	ms.close_screen()
	ms.forget()
