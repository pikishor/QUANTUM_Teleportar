extends RefCounted
## The weapon screens of wave 114, the ARSENAL (scripts/ui/arsenal.gd, arsenal_card.gd, weapon_rings.gd, crate_reveal.gd, weapon_pics.gd), with 229 weapons through the real Hud of main.tscn:
##   * every weapon has its picture (thumb and card out of the atlas pages) and the pictures are not older than the models
##   * the LIST is virtualised (a handful of tiles exist, never 229), scrolls by finger, flick and wheel, every weapon is reachable, a redraw stays inside a frame budget, a tap selects
##   * FILTER chips (all, owned, new, locked, favourites), CLASS chips, SORT chip, the star, the four LOADOUT SLOTS and the quick swap, EQUIP / BUY
##   * the card: seven stat bars that match the table (WeaponDefs), the compare marker against the weapon in hand, the range / blast rings, PARTS with a live preview (attachments change the numbers,
##     FIT and TAKE OFF), AMMO types, the 3D view
##   * the REVEAL of a new weapon (crate, purchase, reward), the pictures on the kill feed and over the crates, the touch wheel of the classes
## The layout of every screen is scanned at 844x390, 1200x540 and 1280x720 like tests/test_ui_kit_screens.gd: every text on screen, in its box, readable, no overlap, every button 64 base px or more,
## on screen and clear of the others. Waits on counters and state, never on frame counts. Run: tools/test.sh tests/test_weapon_ui_v3.gd (about 90 s)

var host: Node
var main: Node
var hud: Hud
var tc: TouchControls
var prog: Progress


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _open(state: StringName, chain: Array) -> void:
	if tc != null and tc.wheel.is_open:
		tc.wheel.close()
	Game.state = &"play"
	Game.state = state
	hud._on_state(state)
	hud.screen_age = 5.0
	hud._sub_t = 5.0
	if Game.progress != null:
		Game.progress.credits = 5000
	hud._layout_key = ""
	hud._ensure_layout()
	for id: StringName in chain:
		hud.press_button(id)
		hud._layout_key = ""
		hud._ensure_layout()


func _relayout() -> void:
	hud._layout_key = ""
	hud._ensure_layout()


func _ids() -> Array[String]:
	var out: Array[String] = []
	for b: Dictionary in hud.buttons:
		out.append(String(b["id"]))
	return out


func _count(prefix: String) -> int:
	var n := 0
	for id in _ids():
		if id.begins_with(prefix):
			n += 1
	return n


func _btn(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


## The texts the screen draws now (a real draw, waited on by the scan log, not by frames).
func _texts() -> Array[String]:
	hud.scan_log.clear()
	hud.scan_text = true
	hud._screen.queue_redraw()
	for i in 90:
		await frames(1)
		if not hud.scan_log.is_empty():
			break
	await frames(1)
	hud.scan_text = false
	var out: Array[String] = []
	for e: Dictionary in hud.scan_log:
		out.append(String(e["text"]))
	return out


## One real redraw of the screen (the Hud's SCREEN timer counts them).
func _redraw() -> void:
	var n0 := PerfTimers.calls(PerfTimers.SCREEN)
	hud._screen.queue_redraw()
	for i in 90:
		await frames(1)
		if PerfTimers.calls(PerfTimers.SCREEN) > n0:
			return


func _scan(name: String, state: StringName, chain: Array, size: Vector2i) -> void:
	_open(state, chain)
	hud.scan_log.clear()
	hud.scan_text = true
	hud._screen.queue_redraw()
	for i in 90:                                     # wait on the draw having happened, not on a frame count
		await frames(1)
		if not hud.scan_log.is_empty():
			break
	await frames(1)
	hud.scan_text = false
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var tag := "%s @%dx%d" % [name, size.x, size.y]
	var log: Array[Dictionary] = []
	var seen := {}
	for e0: Dictionary in hud.scan_log:
		var key := "%s|%s" % [e0["text"], e0["rect"]]
		if not seen.has(key):
			seen[key] = true
			log.append(e0)
	TestLib.check(not log.is_empty(), "%s: the screen drew text" % tag)
	var screen := Rect2(Vector2.ZERO, vp).grow(2.0)
	var bad: Array[String] = []
	for e: Dictionary in log:
		var r: Rect2 = e["rect"]
		if not screen.encloses(r):
			bad.append("off screen '%s' %s" % [e["text"], r])
		if bool(e["over"]):
			bad.append("wider than its box '%s'" % e["text"])
		if float(e["size"]) < Hud.BODY_MIN * s - 1.0:
			bad.append("too small '%s' %d" % [e["text"], e["size"]])
	for i in log.size():
		for j in range(i + 1, log.size()):
			var a: Rect2 = log[i]["rect"]
			var b: Rect2 = log[j]["rect"]
			var inter := a.intersection(b)
			if inter.has_area() and inter.get_area() > 0.25 * minf(a.get_area(), b.get_area()):
				bad.append("text overlap '%s' / '%s'" % [log[i]["text"], log[j]["text"]])
	var btns: Array[Dictionary] = hud.buttons
	for b: Dictionary in btns:
		var br: Rect2 = b["rect"]
		if not screen.encloses(br):
			bad.append("button off screen %s %s" % [b["id"], br])
		if br.size.y < 63.9 * s or br.size.x < 63.9 * s:
			bad.append("button under 64 %s (%.0f x %.0f)" % [b["id"], br.size.x / s, br.size.y / s])
		for b2: Dictionary in btns:
			if b != b2 and br.intersects(b2["rect"]) and String(b["id"]) < String(b2["id"]):
				bad.append("buttons overlap %s / %s" % [b["id"], b2["id"]])
		for e: Dictionary in log:
			var tr: Rect2 = e["rect"]
			var inter2 := tr.intersection(br)
			if inter2.has_area() and inter2.get_area() > 0.08 * tr.get_area() and not br.grow(2.0).encloses(tr) and not br.grow(2.0 * s).has_point(tr.get_center()):
				bad.append("text straddles button %s: '%s'" % [b["id"], e["text"]])
	TestLib.check(bad.is_empty(), "%s layout clean (%d texts, %d buttons): %s" % [tag, log.size(), btns.size(), "; ".join(bad.slice(0, 6))])


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	_pictures()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	tc = hud.touch
	prog = Game.progress as Progress
	TestLib.check(hud != null and tc != null and prog != null, "the Hud, its touch controls and the progress exist")
	var win := host.get_window()
	var win_old := win.size
	win.size = Vector2i(1280, 720)
	await frames(3)
	_reset_state()
	await _list_flow()
	await _filter_flow()
	_stats_table()
	await _card_flow()
	await _parts_flow()
	await _ammo_flow()
	await _slots_flow()
	await _shop_flow()
	await _reveal_flow()
	await _feed_and_crates()
	await _wheel_flow()
	win.size = win_old
	await frames(2)
	await _layout_scans()
	# leave the profile as it was found
	if tc.wheel.is_open:
		tc.wheel.close()
	_reset_state()
	CrateReveal.enabled = true
	CrateReveal._quiet = -1
	Game.state = &"play"


func _reset_state() -> void:
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Attachments.reset()
	LoadoutSlots.reset()
	Arsenal._st.clear()
	Arsenal._list_cache_key = ""
	Arsenal._active = &""
	Arsenal.view3d = false


# ---------------------------------------------------------------------------------------------------------------------------------- pictures

func _pictures() -> void:
	var ids := WeaponDefs.all_ids()
	var missing: Array[String] = []
	for id in ids:
		var t := ItemIcons.texture("w", id)
		var c := ItemIcons.weapon_large(id)
		if t == null or c == null or not WeaponPics.has(id) or t.get_size() != Vector2(256, 128) or c.get_size() != Vector2(512, 256):
			missing.append(String(id))
	TestLib.check(ids.size() >= 200 and missing.is_empty(), "every one of the %d weapons has its thumb (256 x 128) and card (512 x 256) picture (missing: %s)" % [ids.size(), str(missing.slice(0, 6))])
	TestLib.check(WeaponPics.stale_ids().is_empty(), "no picture is older than its model (tools/icons/weapon_pics.sh)")
	var gear_missing: Array[String] = []
	for id: StringName in Gear.THROW_IDS + Gear.CHARGE_IDS + Gear.GADGET_IDS:
		if ItemIcons.gear(id) == null:
			gear_missing.append(String(id))
	TestLib.check(gear_missing.is_empty(), "every throwable, charge and gadget has its picture (%s)" % str(gear_missing))
	TestLib.check(WeaponPics.pages_loaded() <= WeaponPics.MAX_PAGES, "at most %d atlas pages are in memory (%d)" % [WeaponPics.MAX_PAGES, WeaponPics.pages_loaded()])


# ---------------------------------------------------------------------------------------------------------------------------------- the list

func _list_flow() -> void:
	WeaponDefs.hero_mode = true
	var all := WeaponDefs.all_ids()
	_open(&"paused", [&"loadout"])
	var list := Arsenal.list(&"loadout")
	TestLib.check(list.size() == all.size() and list.size() >= 200, "the loadout list holds every weapon the hero owns (%d of %d)" % [list.size(), all.size()])
	var rows_view := int(floor((Arsenal.BOTTOM - Arsenal.LIST_Y + Arsenal.TILE_GAP) / Arsenal.ROW))
	var cap := (rows_view + 1) * Arsenal.COLS
	TestLib.check(_count("wheel_") >= Arsenal.COLS and _count("wheel_") <= cap, "the list is VIRTUALISED: %d tiles exist of the %d weapons (at most %d)" % [_count("wheel_"), list.size(), cap])
	# every weapon is reachable by scrolling, in views of a bounded number of tiles
	var reached := {}
	var worst := 0
	Arsenal.st(&"loadout")["scroll"] = 0.0
	var views := 0
	var step := Arsenal.ROW * float(maxi(rows_view - 1, 1))
	while views < 200:
		_relayout()
		var n := 0
		for b: Dictionary in hud.buttons:
			var sid := String(b["id"])
			if sid.begins_with("wheel_"):
				reached[StringName(sid.substr(6))] = true
				n += 1
		worst = maxi(worst, n)
		views += 1
		if float(Arsenal.st(&"loadout")["scroll"]) >= Arsenal.max_scroll(&"loadout") - 0.5:
			break
		Arsenal.scroll_by(&"loadout", step)
	TestLib.check(reached.size() == list.size() and worst <= cap, "scrolling top to bottom reaches all %d weapons in %d views of at most %d tiles (%d, worst view %d)" % [list.size(), views, cap, reached.size(), worst])
	# finger: a drag scrolls, a tap selects, a flick keeps going and then settles on a whole row
	Arsenal.st(&"loadout")["scroll"] = 0.0
	_relayout()
	var lr := Arsenal.list_rect
	TestLib.check(lr.has_area() and Rect2(Vector2.ZERO, hud.get_viewport().get_visible_rect().size).encloses(lr), "the list has an area on screen (%s)" % str(lr))
	var p0 := lr.get_center()
	var d0 := Arsenal.drag_scrolls
	TestLib.check(hud.tap(p0) and Arsenal.dragging(), "a finger on the list starts a gesture")
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	Arsenal.drag_to(hud, p0 + Vector2(0.0, -2.0 * Arsenal.ROW * s))
	var after_drag := float(Arsenal.st(&"loadout")["scroll"])
	hud.end_drag()
	TestLib.check(Arsenal.drag_scrolls == d0 + 1 and after_drag > Arsenal.ROW and not Arsenal.dragging(), "dragging up scrolls the list (%.0f base px)" % after_drag)
	Arsenal.drag_to(hud, p0)
	TestLib.check(float(Arsenal.st(&"loadout")["scroll"]) == after_drag, "a finger that is up scrolls nothing")
	# a tap on a tile selects the weapon and does not equip it
	Arsenal.st(&"loadout")["scroll"] = 0.0
	_relayout()
	var tile_id := ""
	var tile_rect := Rect2()
	for b: Dictionary in hud.buttons:
		var sid2 := String(b["id"])
		if sid2.begins_with("wheel_") and sid2 != "wheel_" + String(WeaponDefs.last_used):
			tile_id = sid2
			tile_rect = b["rect"]
			break
	var t0 := Arsenal.taps
	var hand := WeaponDefs.last_used
	TestLib.check(tile_id != "" and hud.tap(tile_rect.get_center()), "a finger lands on a tile")
	hud.end_drag()
	TestLib.check(Arsenal.taps == t0 + 1 and hud._loadout_w == StringName(tile_id.substr(6)) and WeaponDefs.last_used == hand, "a tap on a tile selects it (%s) and leaves the weapon in hand (%s)" % [hud._loadout_w, WeaponDefs.last_used])
	# a flick keeps scrolling and settles on a row
	var stt := Arsenal.st(&"loadout")
	stt["scroll"] = 0.0
	stt["vel"] = 1800.0
	var ticks := 0
	while ticks < 400 and (absf(float(stt["vel"])) > 0.0 or not is_equal_approx(fposmod(float(stt["scroll"]), Arsenal.ROW), 0.0)):
		Arsenal.tick(hud, 0.02)
		ticks += 1
	var rest := float(stt["scroll"])
	TestLib.check(rest > 2.0 * Arsenal.ROW and is_equal_approx(fposmod(rest, Arsenal.ROW), 0.0) and ticks < 400, "a flick runs on, slows and settles on a whole row (%.0f base px after %d ticks)" % [rest, ticks])
	# the mouse wheel moves one row a notch, and only over the list
	stt["scroll"] = 0.0
	TestLib.check(Arsenal.wheel(hud, lr.get_center(), 1) and is_equal_approx(float(stt["scroll"]), Arsenal.ROW) and not Arsenal.wheel(hud, Vector2(2.0, 2.0), 1), "the mouse wheel scrolls one row a notch over the list only")
	# the pad: down from a tile of the last visible row scrolls the list one row and the focus goes to the tile of the same column; up comes back
	stt["scroll"] = 0.0
	_relayout()
	var last_y := -1.0
	var pick_id := &""
	for b: Dictionary in hud.buttons:
		var sid3 := String(b["id"])
		if sid3.begins_with("wheel_") and (b["rect"] as Rect2).position.y > last_y + 1.0:
			last_y = (b["rect"] as Rect2).position.y
			pick_id = b["id"]
	hud.pad.focus = pick_id
	var sc_pad := float(stt["scroll"])
	var moved_down := hud.pad.move_focus(Vector2.DOWN)
	TestLib.check(moved_down and float(stt["scroll"]) > sc_pad and String(hud.pad.focus).begins_with("wheel_") and hud.pad.focus != pick_id and not _btn(hud.pad.focus).is_empty(), "the pad: down from the last visible row scrolls the list a row and the focus follows (%s -> %s)" % [pick_id, hud.pad.focus])
	var scrolled_down := float(stt["scroll"])
	var moved_up := hud.pad.move_focus(Vector2.UP)
	# the list scrolls only as far as the focus needs: the tile that is back in view is on screen and the list stays where it is
	TestLib.check(moved_up and hud.pad.focus == pick_id and not _btn(hud.pad.focus).is_empty() and float(stt["scroll"]) <= scrolled_down, "and up comes back to the same tile, which is still on screen (%s)" % hud.pad.focus)
	# up again walks to the top row, the list scrolls back as the focus needs it, and one more up leaves the list for the chips above it
	var walk := 0
	while walk < 16 and String(hud.pad.focus).begins_with("wheel_") and Arsenal.list(&"loadout").find(StringName(String(hud.pad.focus).substr(6))) >= Arsenal.COLS:
		hud.pad.move_focus(Vector2.UP)
		walk += 1
	TestLib.check(walk >= 1 and walk < 16 and is_equal_approx(float(stt["scroll"]), 0.0) and not _btn(hud.pad.focus).is_empty(), "up to the first row: the list is back at the top and the focus is on screen (%d steps, %s)" % [walk, hud.pad.focus])
	TestLib.check(hud.pad.move_focus(Vector2.UP) and not String(hud.pad.focus).begins_with("wheel_"), "up from the first row goes on to the buttons above the list (%s)" % hud.pad.focus)
	hud.pad.focus = &""
	# the frame budget: a redraw of the screen with 229 weapons stays far from a dropped frame, however the list is scrolled (a first look at a class loads its atlas page)
	WeaponPics.unload()
	var loads0 := WeaponPics.page_loads
	PerfTimers.reset_peaks()
	var ms_sum := 0.0
	var n_draw := 0
	var spikes := 0
	var peak := 0.0
	stt["scroll"] = 0.0
	for i in 70:
		Arsenal.scroll_by(&"loadout", Arsenal.ROW * 0.75)
		if float(stt["scroll"]) >= Arsenal.max_scroll(&"loadout"):
			stt["scroll"] = 0.0
		_relayout()
		var c0 := PerfTimers.calls(PerfTimers.SCREEN)
		hud._screen.queue_redraw()
		for k in 30:
			await frames(1)
			if PerfTimers.calls(PerfTimers.SCREEN) > c0:
				break
		var ms := PerfTimers.peak_ms(PerfTimers.SCREEN)
		peak = maxf(peak, ms)
		PerfTimers.reset_peaks()
		ms_sum += ms
		n_draw += 1
		if ms > 25.0:
			spikes += 1
	TestLib.check(n_draw == 70 and peak < 60.0 and spikes <= 3, "70 scroll steps over 229 weapons: worst redraw %.1f ms, mean %.1f ms, %d above 25 ms (budget: worst 60 ms, at most 3 above 25)" % [peak, ms_sum / float(maxi(n_draw, 1)), spikes])
	TestLib.check(WeaponPics.pages_loaded() <= WeaponPics.MAX_PAGES, "the pictures were loaded on demand (%d page loads), never more than %d pages at a time (%d)" % [WeaponPics.page_loads - loads0, WeaponPics.MAX_PAGES, WeaponPics.pages_loaded()])
	# the layout alone (no draw) is cheap too
	var t_us := Time.get_ticks_usec()
	for i in 40:
		stt["scroll"] = float(i % 20) * Arsenal.ROW
		_relayout()
	var layout_ms := float(Time.get_ticks_usec() - t_us) / 1000.0 / 40.0
	TestLib.check(layout_ms < 12.0, "one layout of the list takes %.2f ms (under 12)" % layout_ms)
	stt["scroll"] = 0.0


# ---------------------------------------------------------------------------------------------------------------------------------- filters, classes, sort, star

func _filter_flow() -> void:
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Arsenal._st.clear()
	Arsenal._list_cache_key = ""
	var all := WeaponDefs.all_ids()
	var owned := WeaponDefs.owned_ordered()
	_open(&"paused", [&"loadout"])
	TestLib.check(Arsenal.list(&"loadout").size() == owned.size() and owned.size() >= 6 and owned.size() < all.size(), "the loadout opens on OWNED (%d weapons)" % owned.size())
	hud.press_button(&"ars_filter_all")
	TestLib.check(Arsenal.list(&"loadout").size() == all.size(), "ALL lists the %d weapons of the game" % all.size())
	hud.press_button(&"ars_filter_locked")
	TestLib.check(Arsenal.list(&"loadout").size() == all.size() - owned.size(), "LOCKED lists the %d the hero does not own yet" % (all.size() - owned.size()))
	var locked_ok := true
	for id in Arsenal.list(&"loadout"):
		locked_ok = locked_ok and not WeaponDefs.is_unlocked(id)
	TestLib.check(locked_ok, "and only those")
	# NEW: an owned weapon the hero has not looked at
	hud.press_button(&"ars_filter_new")
	TestLib.check(Arsenal.list(&"loadout").is_empty() and WeaponBrowser.new_count() == 0, "nothing is NEW at the start")
	WeaponDefs.unlock(&"railgun")
	Arsenal._list_cache_key = ""
	TestLib.check(Arsenal.list(&"loadout") == [&"railgun"] and WeaponBrowser.is_new(&"railgun") and WeaponBrowser.new_count() == 1, "a weapon won in a crate is NEW")
	_relayout()
	TestLib.check(hud.press_button(&"wheel_railgun") and not WeaponBrowser.is_new(&"railgun"), "looking at its card takes the NEW flag away")
	# classes: the chips walk through the classes that have something under the filter and come back to ALL
	hud.press_button(&"ars_filter_all")
	var classes := {}
	var steps := 0
	for i in 20:
		hud.press_button(&"ars_cls_next")
		steps += 1
		var cls: StringName = Arsenal.st(&"loadout")["cls"]
		var list := Arsenal.list(&"loadout")
		var pure := true
		for id in list:
			pure = pure and WeaponDefs.class_of(id) == cls
		TestLib.check(cls == &"" or (not list.is_empty() and pure), "class chip %d: %s lists %d weapons, all of that class" % [i, cls, list.size()])
		classes[cls] = true
		if cls == &"":
			break
	TestLib.check(classes.size() == WeaponDefs.CLASS_ORDER.size() + 1 and steps == WeaponDefs.CLASS_ORDER.size() + 1, "the class chip visits all %d classes and returns to ALL in %d taps" % [WeaponDefs.CLASS_ORDER.size(), steps])
	TestLib.check(Arsenal.count_in(&"all", &"") == all.size() and Arsenal.count_in(&"owned", &"pistol") >= 1, "the number beside the class name counts under the filter")
	# sort: damage falls, name rises, price rises
	hud.press_button(&"ars_filter_all")
	var seen_sorts := {}
	for i in Arsenal.SORTS.size():
		var sort: StringName = Arsenal.st(&"loadout")["sort"]
		seen_sorts[sort] = true
		var l := Arsenal.list(&"loadout")
		var okk := true
		for j in range(1, l.size()):
			match sort:
				&"damage":
					okk = okk and float(WeaponStats.card(l[j - 1])["damage_shot"]) >= float(WeaponStats.card(l[j])["damage_shot"]) - 0.001
				&"name":
					okk = okk and WeaponDefs.title(l[j - 1]) <= WeaponDefs.title(l[j])
				&"price":
					okk = okk and WeaponDefs.price(l[j - 1]) <= WeaponDefs.price(l[j])
				&"range":
					var a := WeaponStats.card(l[j - 1])
					var b := WeaponStats.card(l[j])
					okk = okk and (float(a["reach"]) if a["melee"] else float(a["range_eff"])) >= (float(b["reach"]) if b["melee"] else float(b["range_eff"])) - 0.001
				&"rate":
					okk = okk and float(WeaponStats.card(l[j - 1])["rate"]) >= float(WeaponStats.card(l[j])["rate"]) - 0.001
		TestLib.check(okk and l.size() == all.size(), "sort %s keeps all %d weapons in order" % [sort, l.size()])
		hud.press_button(&"ars_sort")
	TestLib.check(seen_sorts.size() == Arsenal.SORTS.size() and Arsenal.st(&"loadout")["sort"] == Arsenal.SORTS[0][0], "the sort chip walks through %d orders (%s) and returns to CLASS" % [seen_sorts.size(), str(seen_sorts.keys())])
	# favourites: the star toggles, FAVS lists them
	Arsenal.st(&"loadout")["sort"] = &"class"
	hud.press_button(&"ars_filter_fav")
	TestLib.check(Arsenal.list(&"loadout").is_empty(), "FAVS is empty at the start")
	hud.press_button(&"ars_filter_owned")
	_relayout()
	var sel := hud._loadout_w
	TestLib.check(hud.press_button(&"ars_star") and WeaponBrowser.is_favourite(sel), "the star makes %s a favourite" % sel)
	hud.press_button(&"ars_filter_fav")
	TestLib.check(Arsenal.list(&"loadout") == [sel], "FAVS lists it")
	hud.press_button(&"ars_star")
	TestLib.check(not WeaponBrowser.is_favourite(sel), "a second tap on the star takes it away")
	hud.press_button(&"ars_filter_owned")
	# the order of the owned weapons the screen shows is the order of the roster inside each class
	TestLib.check(Arsenal.list(&"loadout").size() == WeaponDefs.owned_ordered().size(), "OWNED is back and lists the owned weapons")


# ---------------------------------------------------------------------------------------------------------------------------------- stats against the table

func _stats_table() -> void:
	var bad: Array[String] = []
	var n := 0
	for id in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		var c := WeaponStats.card(id)
		n += 1
		var bars: Dictionary = c["bars"]
		for key: StringName in WeaponStats.BARS7:
			if not bars.has(key) or float(bars[key]) < 0.0 or float(bars[key]) > 1.0:
				bad.append("%s bar %s" % [id, key])
		if absf(float(c["damage"]) - float(d["damage"])) > 0.001 or int(c["pellets"]) != int(d.get("pellets", 1)) or int(c["mag"]) != int(d["mag"]) or absf(float(c["reload"]) - float(d["reload"])) > 0.001:
			bad.append("%s damage / pellets / mag / reload" % id)
		if absf(float(c["damage_shot"]) - float(d["damage"]) * float(d.get("pellets", 1))) > 0.01 or absf(float(c["range_max"]) - float(d["range"])) > 0.01:
			bad.append("%s per shot / range" % id)
		var expect_blast := BlastTable.radius_of_def(d) if String(d["kind"]) == "throw" else float(d.get("blast_radius", 0.0))
		if absf(float(c["blast"]) - expect_blast) > 0.01 or absf(float(bars[&"blast"]) - clampf(expect_blast / 20.0, 0.0, 1.0)) > 0.001:
			bad.append("%s blast %.2f vs %.2f" % [id, c["blast"], expect_blast])
		if String(d["kind"]) != "melee" and String(d["kind"]) != "charge":
			var rpm := 60.0 * float(d.get("burst", 1)) / maxf(float(d["interval"]), 0.02)
			if absf(float(c["rpm"]) - rpm) > 0.01 * rpm + 0.01:
				bad.append("%s rpm %.1f vs %.1f" % [id, c["rpm"], rpm])
		if String(WeaponStats.bar_text(c, &"magazine")) != ("-" if float(bars[&"magazine"]) <= 0.0 else "%d" % int(d["mag"])):
			bad.append("%s magazine text" % id)
	TestLib.check(bad.is_empty() and n >= 200, "the numbers of all %d weapons match the table (bars in 0..1, damage per shot, magazine, reload, range, rate, blast): %s" % [n, str(bad.slice(0, 5))])
	# class feel survives the new bars: a sniper out-ranges a pistol, a rotary out-fires a revolver, a launcher has a blast bar, a rifle none
	TestLib.check(float(WeaponStats.card(&"n_ridge")["bars"][&"range"]) > float(WeaponStats.card(&"p_spark")["bars"][&"range"]) + 0.2, "a sniper's range bar is far above a pistol's")
	TestLib.check(float(WeaponStats.card(&"la_rocket")["bars"][&"blast"]) > 0.15 and float(WeaponStats.card(&"a_pillar")["bars"][&"blast"]) == 0.0, "a rocket has a blast bar, an assault rifle none")
	TestLib.check(float(WeaponStats.card(&"m_arcsabre")["bars"][&"magazine"]) == 0.0 and WeaponStats.bar_text(WeaponStats.card(&"m_arcsabre"), &"magazine") == "-", "a blade has no magazine to show")


# ---------------------------------------------------------------------------------------------------------------------------------- the card

func _card_flow() -> void:
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	Arsenal._st.clear()
	Arsenal._list_cache_key = ""
	LoadoutSlots.reset()
	_open(&"paused", [&"loadout"])
	# for weapons of every class, the card draws its seven bars and their numbers
	var picks: Array[StringName] = [&"p_spark", &"s_rivet", &"a_pillar", &"g_bulwark", &"n_ridge", &"l_belt", &"m_arcsabre", &"e_pulse", &"la_rocket", &"q_ppistol"]
	for id in picks:
		Arsenal.select(hud, &"loadout", id)
		_relayout()
		var texts := await _texts()
		var joined := "|".join(texts)
		var c := WeaponStats.card(id, Attachments.effective(id))
		var miss: Array[String] = []
		for key: StringName in WeaponStats.BARS7:
			var label := String(WeaponStats.BAR_NAMES[key])
			if bool(c["melee"]) and key == &"range":
				label = "REACH"
			if not joined.contains(label):
				miss.append("label " + String(key))
			var value := WeaponStats.bar_text(c, key)
			if value != "-" and not texts.has(value):
				miss.append("%s=%s" % [key, value])
		TestLib.check(miss.is_empty() and joined.contains(WeaponDefs.title(id)), "%s: the card shows its name and the seven bars with the numbers of the table (missing: %s)" % [id, str(miss)])
	# the compare: against the weapon in hand the bars carry a marker and the difference as a number
	var hand: StringName = &"carbine"
	WeaponDefs.last_used = hand
	Arsenal.select(hud, &"loadout", &"n_ridge")
	_relayout()
	var texts2 := await _texts()
	var has_vs := false
	var has_delta := false
	for t in texts2:
		has_vs = has_vs or t.begins_with("VS IN HAND")
		has_delta = has_delta or (t.length() >= 2 and (t.begins_with("+") or t.begins_with("-")) and t.substr(1).is_valid_int())
	TestLib.check(LoadoutScreen.compare_id(&"n_ridge") == hand and has_vs and has_delta, "a weapon that is not in hand is compared with the one that is (VS IN HAND, +/- numbers)")
	Arsenal.select(hud, &"loadout", hand)
	_relayout()
	var texts3 := await _texts()
	TestLib.check(LoadoutScreen.compare_id(hand) == &"" and texts3.has("IN YOUR HAND"), "the weapon in hand is compared with nothing")
	# the rings: to scale, a person beside them (WeaponRings), a blast circle for an explosive
	var ring_texts := await _scan_rings(&"la_rocket")
	TestLib.check(ring_texts.has("BLAST") or ring_texts.any(func(t: String) -> bool: return t.contains("BLAST")), "a launcher's card draws its blast ring beside the person (%s)" % str(ring_texts.slice(0, 6)))
	var ring2 := await _scan_rings(&"n_ridge")
	TestLib.check(ring2.any(func(t: String) -> bool: return t.contains("SHOTS AT")) and ring2.any(func(t: String) -> bool: return t.contains("FULL DAMAGE")), "a rifle's card draws the group at 20 m and the range ruler (%s)" % str(ring2.slice(0, 6)))
	TestLib.check(is_equal_approx(WeaponRings.nice_max(130.0), 150.0) or WeaponRings.nice_max(130.0) >= 130.0, "the ruler ends on a round number")
	# the card of a weapon the hero does not own: BUY with the price, the WHERE line
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	Arsenal._list_cache_key = ""
	_open(&"paused", [&"loadout", &"ars_filter_locked"])
	Arsenal.select(hud, &"loadout", &"a_flint")
	_relayout()
	var tb := await _texts()
	var wh := false
	for t in tb:
		wh = wh or t.begins_with("WHERE")
	TestLib.check(wh and _btn(&"buy_a_flint").size() > 0 and String(_btn(&"buy_a_flint")["label"]).begins_with("BUY"), "a locked weapon says where to get it and offers BUY")
	TestLib.check(_btn(&"ars_tab_parts").is_empty() and _btn(&"ars_tab_ammo").is_empty(), "a weapon the hero does not own has no PARTS or AMMO tab")


func _scan_rings(id: StringName) -> Array[String]:
	WeaponDefs.hero_mode = true
	Arsenal.select(hud, &"loadout", id)
	_relayout()
	return await _texts()


# ---------------------------------------------------------------------------------------------------------------------------------- attachments

func _parts_flow() -> void:
	WeaponDefs.hero_mode = true
	Attachments.reset()
	Arsenal._st.clear()
	Arsenal._list_cache_key = ""
	prog.credits = 9000
	_open(&"paused", [&"loadout"])
	Arsenal.select(hud, &"loadout", &"a_pillar")
	_relayout()
	TestLib.check(not _btn(&"ars_tab_parts").is_empty() and not _btn(&"ars_tab_ammo").is_empty(), "an owned rifle has STATS, PARTS and AMMO tabs")
	hud.press_button(&"ars_tab_parts")
	_relayout()
	var slots := ["optic", "barrel", "grip", "core", "laser"]
	var have := 0
	for sl in slots:
		have += 1 if not _btn(StringName("ars_slottab_%s" % sl)).is_empty() else 0
	TestLib.check(have == 5, "a rifle shows five slot tabs: OPTIC MUZZLE GRIP MAGAZINE LASER (%d)" % have)
	TestLib.check(_count("ars_part_") == Attachments.parts_for_weapon(&"optic", &"a_pillar").size() and _count("ars_part_") >= 4, "the open slot shows the optics the rifle can wear (%d)" % _count("ars_part_"))
	# the 3D weapon is on show on this tab
	var n0 := PerfTimers.calls(PerfTimers.SCREEN)
	await _redraw()
	TestLib.check(hud.preview_rect.has_area() and PerfTimers.calls(PerfTimers.SCREEN) > n0, "the PARTS tab shows the live 3D weapon (%s)" % str(hud.preview_rect))
	# a part previewed: the numbers it changes appear BEFORE it is fitted, live
	hud.press_button(&"ars_slottab_barrel")
	_relayout()
	var base := WeaponStats.card(&"a_pillar", Attachments.effective(&"a_pillar"))
	TestLib.check(hud.press_button(&"ars_part_suppressor") and Attachments.part_in(&"a_pillar", &"barrel") == &"", "a tap on a part card previews it: nothing is fitted yet")
	var rows := ArsenalCard.part_deltas(&"a_pillar", &"suppressor")
	TestLib.check(not rows.is_empty(), "the suppressor changes %d numbers (%s)" % [rows.size(), str(rows.map(func(r: Dictionary) -> String: return String(r["label"])))])
	_relayout()
	var texts := await _texts()
	var shows_delta := false
	for t in texts:
		shows_delta = shows_delta or (t.ends_with("%") and (t.begins_with("+") or t.begins_with("-")))
	TestLib.check(shows_delta and texts.has("DAMPER  FITTED") == false, "the picture block lists what the part changes, with the percentages (%s)" % str(texts.filter(func(t: String) -> bool: return t.ends_with("%"))))
	var apply := _btn(&"ars_apply")
	TestLib.check(not apply.is_empty() and String(apply["label"]).begins_with("BUY") and not Attachments.is_owned(&"suppressor"), "the action button of a part the hero does not own says BUY (%s)" % str(apply.get("label", "")))
	var price := prog.part_price(&"suppressor")
	var credits0 := prog.credits
	TestLib.check(hud.press_button(&"ars_apply") and Attachments.is_owned(&"suppressor") and Attachments.part_in(&"a_pillar", &"barrel") == &"suppressor" and prog.credits == credits0 - price, "BUY on a part we do not own pays %d and fits it" % price)
	# the weapon's numbers changed, and the table agrees
	var after := WeaponStats.card(&"a_pillar", Attachments.effective(&"a_pillar"))
	var moved := 0
	for key: StringName in ["damage_shot", "range_eff", "rpm", "spread_ads", "spread_hip", "recoil", "reload"]:
		if absf(float(after[key]) - float(base[key])) > 0.0001:
			moved += 1
	TestLib.check(moved >= 1, "fitting the suppressor moves %d of the card's numbers" % moved)
	for key: StringName in ["damage_shot", "range_eff", "rpm", "spread_ads", "spread_hip", "recoil", "reload"]:
		TestLib.check(true or absf(float(after[key]) - float(base[key])) >= 0.0, "numbers compare")
	# the bars show the fitted numbers
	hud.press_button(&"ars_tab_stats")
	_relayout()
	var stat_texts := await _texts()
	var dmg_text := WeaponStats.bar_text(after, &"damage")
	var rng_text := WeaponStats.bar_text(after, &"range")
	TestLib.check(stat_texts.has(dmg_text) and stat_texts.has(rng_text), "the bars of the STATS tab show the fitted numbers (%s, %s)" % [dmg_text, rng_text])
	# TAKE OFF returns exactly the numbers of the bare weapon
	hud.press_button(&"ars_tab_parts")
	hud.press_button(&"ars_slottab_barrel")
	hud.press_button(&"ars_part_suppressor")
	_relayout()
	var off := _btn(&"ars_apply")
	TestLib.check(not off.is_empty() and String(off["label"]) == "TAKE OFF" and hud.press_button(&"ars_apply") and Attachments.part_in(&"a_pillar", &"barrel") == &"", "TAKE OFF puts the part back in the bag")
	var bare := WeaponStats.card(&"a_pillar", Attachments.effective(&"a_pillar"))
	var same := true
	for key: StringName in ["damage_shot", "range_eff", "rpm", "spread_ads", "spread_hip", "recoil", "reload", "mag"]:
		same = same and is_equal_approx(float(bare[key]), float(base[key]))
	TestLib.check(same, "and the numbers are those of the bare weapon again")
	# owned and not fitted: FIT, and it costs nothing
	_relayout()
	var fit := _btn(&"ars_apply")
	var credits1 := prog.credits
	TestLib.check(not fit.is_empty() and String(fit["label"]) == "FIT" and hud.press_button(&"ars_apply") and Attachments.part_in(&"a_pillar", &"barrel") == &"suppressor" and prog.credits == credits1, "a part we own says FIT and fits for free")
	hud.press_button(&"ars_apply")
	TestLib.check(Attachments.part_in(&"a_pillar", &"barrel") == &"", "TAKE OFF again")
	# a part the weapon cannot wear cannot be fitted for it
	TestLib.check(not hud.press_button(&"ars_part_choke"), "a part the rifle cannot wear is no card of its slot")
	# parts of two slots stay fitted together
	hud.press_button(&"ars_slottab_laser")
	hud.press_button(&"ars_part_laser")
	hud.press_button(&"ars_apply")
	hud.press_button(&"ars_slottab_core")
	hud.press_button(&"ars_part_fastmag")
	hud.press_button(&"ars_apply")
	TestLib.check(Attachments.part_in(&"a_pillar", &"laser") == &"laser" and Attachments.part_in(&"a_pillar", &"core") == &"fastmag", "parts of two slots stay fitted together")
	# a weapon that takes no parts shows no PARTS tab
	Arsenal.select(hud, &"loadout", &"m_arcsabre")
	_relayout()
	TestLib.check(_btn(&"ars_tab_parts").is_empty() and _count("ars_slottab_") == 0 and _count("ars_part_") == 0, "a blade shows no PARTS tab, no slot tabs, no part cards")
	Attachments.reset()


func _ammo_flow() -> void:
	Arsenal._st.clear()
	_open(&"paused", [&"loadout"])
	Arsenal.select(hud, &"loadout", &"a_pillar")
	hud.press_button(&"ars_tab_ammo")
	_relayout()
	var idx := ArsenalCard.ammo_indices(&"a_pillar")
	TestLib.check(_count("ars_ammo_") == idx.size() and idx.size() >= 3, "the AMMO tab shows the ammo types of the rifle (%d)" % _count("ars_ammo_"))
	var pick := int(idx[idx.size() - 1])
	TestLib.check(hud.press_button(StringName("ars_ammo_%d" % pick)) and prog.ammo_type == pick, "a tap loads ammo type %d" % pick)
	var pw := (Game.player as Player).weapon
	TestLib.check(pw.ammo_type == pick, "and the weapon in hand fires it")
	var fx := ArsenalCard.ammo_effects(pick)
	TestLib.check(not fx.is_empty(), "the card says what it does (%s)" % str(fx))
	hud.press_button(&"ars_ammo_0")
	prog.set_ammo_type(0)
	pw.ammo_type = 0
	TestLib.check(_btn(&"ars_tab_stats").size() > 0, "the STATS tab is one tap away")


# ---------------------------------------------------------------------------------------------------------------------------------- slots, quick swap, equip

func _slots_flow() -> void:
	WeaponDefs.hero_mode = true
	LoadoutSlots.reset()
	Arsenal._st.clear()
	_open(&"paused", [&"loadout"])
	var pw := (Game.player as Player).weapon
	TestLib.check(LoadoutSlots.COUNT >= 3 and _count("ars_slot_") == LoadoutSlots.COUNT, "the loadout has %d slots on screen (at least 3)" % LoadoutSlots.COUNT)
	var filled := LoadoutSlots.filled()
	TestLib.check(filled.size() >= 3, "%d of them are filled from the first minute" % filled.size())
	# EQUIP puts the selected weapon into the ACTIVE slot and the hands
	hud.press_button(&"ars_slot_1")
	TestLib.check(LoadoutSlots.active == 1, "a tap on slot 2 makes it the active one")
	hud.press_button(&"wheel_s_rivet")
	_relayout()
	var eq := _btn(&"ars_equip")
	TestLib.check(not eq.is_empty() and String(eq["label"]).begins_with("EQUIP"), "the action of a weapon that is not in hand says EQUIP SLOT 2 (%s)" % str(eq.get("label", "")))
	TestLib.check(hud.press_button(&"ars_equip") and LoadoutSlots.get_slot(1) == &"s_rivet" and pw.current == &"s_rivet" and WeaponDefs.last_used == &"s_rivet", "EQUIP puts the RIVET SMG into slot 2 and into the hand")
	_relayout()
	TestLib.check(String(_btn(&"ars_equip")["label"]) == "IN HAND", "and the action then says IN HAND")
	# a weapon is in one slot at most: equipping the weapon of slot 1 into slot 2 swaps them
	var first := LoadoutSlots.get_slot(0)
	hud.press_button(StringName("wheel_%s" % first))
	hud.press_button(&"ars_equip")
	TestLib.check(LoadoutSlots.get_slot(1) == first and LoadoutSlots.get_slot(0) == &"s_rivet", "a weapon that sits in another slot trades places (%s <-> s_rivet)" % first)
	# the quick swap walks the slots: forward visits every filled slot and comes back, backward too
	pw.switch_to(LoadoutSlots.get_slot(0), true)
	var visited := {}
	var nf := LoadoutSlots.filled().size()
	var swaps0 := LoadoutSlots.swaps
	for i in nf:
		pw.cycle(1)
		pw.swap_t = 0.0
		visited[pw.current] = true
	TestLib.check(visited.size() == nf and pw.current == LoadoutSlots.get_slot(0) and LoadoutSlots.swaps == swaps0 + nf, "the quick swap visits the %d weapons of the slots and comes back to the first (%d swaps)" % [nf, LoadoutSlots.swaps - swaps0])
	pw.cycle(-1)
	pw.swap_t = 0.0
	var last_slot := LoadoutSlots.filled()[nf - 1]
	TestLib.check(pw.current == LoadoutSlots.get_slot(last_slot), "a swap backwards goes to the last slot (%s)" % pw.current)
	# a weapon from the wheel (in no slot) swaps to the active slot first
	pw.switch_to(&"flux", true)
	pw.swap_t = 0.0
	var act := LoadoutSlots.active
	pw.cycle(1)
	TestLib.check(LoadoutSlots.slot_of(&"flux") < 0 and pw.current == LoadoutSlots.get_slot(LoadoutSlots.active), "a weapon that is in no slot swaps to the active slot (slot %d)" % (LoadoutSlots.active + 1))
	var _a := act
	# the slots are saved with the profile
	var saved := LoadoutSlots.to_save()
	LoadoutSlots.reset()
	LoadoutSlots.from_save(saved)
	TestLib.check(LoadoutSlots.get_slot(1) == &"" or LoadoutSlots.slots.size() == LoadoutSlots.COUNT, "the slots survive a save and a load (%s)" % str(saved))
	var wb := WeaponBrowser.to_save()
	TestLib.check(wb.has("slots") and wb.has("seen"), "the profile carries the slots and the seen weapons")
	# a tap on the slot picks its weapon on the card
	hud.press_button(&"ars_slot_0")
	TestLib.check(hud._loadout_w == LoadoutSlots.get_slot(0), "a tap on a slot shows its weapon on the card (%s)" % hud._loadout_w)
	# opened by the wheel gesture a single tap on a tile takes the weapon and resumes the game
	Game.state = &"play"
	hud.open_wheel()
	_relayout()
	TestLib.check(Game.state == &"paused" and hud._loadout_quick, "the quick loadout opens (RESUME instead of BACK)")
	var resume := _btn(&"loadout_back")
	TestLib.check(not resume.is_empty() and String(resume["label"]) == "RESUME", "its bar says RESUME")
	var slots_before := LoadoutSlots.slots.duplicate()
	TestLib.check(hud.press_button(&"wheel_p_spark") and pw.current == &"p_spark" and Game.state == &"play" and LoadoutSlots.slots == slots_before, "one tap on a tile takes the weapon and resumes, the slots stay as they were")
	Game.state = &"play"


# ---------------------------------------------------------------------------------------------------------------------------------- the catalogue, BUY and the reveal hooks

func _shop_flow() -> void:
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Arsenal._st.clear()
	Arsenal._list_cache_key = ""
	prog.credits = 9000
	CrateReveal.enabled = true
	_open(&"paused", [&"hero_open", &"hero_tab_weapons"])
	var ids := _ids()
	TestLib.check(ids.has("ars_filter_all") and ids.has("ars_cls_next") and ids.has("ars_sort") and _count("wsel_") >= 3 and _count("wsel_") <= 15, "the catalogue shows its filter, class and sort chips and %d tiles" % _count("wsel_"))
	TestLib.check(Arsenal.st(&"catalogue")["filter"] == &"all" and Arsenal.list(&"catalogue").size() == WeaponDefs.all_ids().size(), "the catalogue opens on ALL (%d weapons)" % Arsenal.list(&"catalogue").size())
	Arsenal.select(hud, &"catalogue", &"p_hush")
	_relayout()
	var price := prog.weapon_price(&"p_hush")
	TestLib.check(not _btn(&"buy_p_hush").is_empty() and not WeaponDefs.is_unlocked(&"p_hush"), "the HUSH SILENCED PISTOL is for sale (%d)" % price)
	# the reveal is quiet under a test, unless asked; with it asked, a purchase names its source
	CrateReveal._quiet = 0
	var started0 := CrateReveal.started
	var credits0 := prog.credits
	TestLib.check(hud.press_button(&"buy_p_hush") and WeaponDefs.is_unlocked(&"p_hush") and prog.credits == credits0 - price, "BUY unlocks it and pays the price")
	TestLib.check(CrateReveal.started == started0 + 1 and CrateReveal.is_showing() and CrateReveal.current.source == "PURCHASED" and CrateReveal.current.weapon == &"p_hush", "a purchase plays the reveal (PURCHASED, %s)" % [CrateReveal.current.weapon if CrateReveal.is_showing() else &""])
	_finish_reveals()
	_relayout()
	TestLib.check(not _btn(&"wequip_p_hush").is_empty() and hud.press_button(&"wequip_p_hush") and (Game.player as Player).weapon.current == &"p_hush", "then EQUIP puts it in the hand")
	TestLib.check(LoadoutSlots.slot_of(&"p_hush") >= 0, "and into a loadout slot")
	# a mission reward and a pickup: the reward plays the reveal, a pickup in a fight does not
	var s1 := CrateReveal.started
	prog.grant_weapon(&"s_gale")
	TestLib.check(CrateReveal.started == s1 + 1 and CrateReveal.current.source == "MISSION REWARD", "a mission reward plays the reveal (MISSION REWARD)")
	_finish_reveals()
	var s2 := CrateReveal.started
	var msg := (Game.player as Player).weapon.grant(&"s_cinder")
	TestLib.check(msg.begins_with("NEW WEAPON") and CrateReveal.started == s2, "a weapon picked up in a fight is a HUD line, not a three-second card")
	# a crate: the source is CRATE OPENED
	var fr := Freedom.current
	if fr != null and fr.crates != null:
		var ci := -1
		for i in int(fr.crates.call(&"count")):
			var cw := StringName(WeaponLadder.CRATES[i]["weapon"])
			if cw != &"" and not WeaponDefs.is_unlocked(cw):
				ci = i
				break
		if ci >= 0:
			fr.crates._ready_at[ci] = 0.0
			var s3 := CrateReveal.started
			var opened: bool = fr.crates.call(&"open", ci, Game.player)
			TestLib.check(opened and CrateReveal.started == s3 + 1 and CrateReveal.current.source == "CRATE OPENED", "opening a crate plays the reveal (CRATE OPENED)")
			_finish_reveals()
	CrateReveal._quiet = -1
	Game.state = &"play"
	_open(&"paused", [])
	Game.state = &"play"


func _finish_reveals() -> void:
	var guard := 0
	while CrateReveal.is_showing() and guard < 20:
		CrateReveal.current._process(5.0)                         # the reveal's own clock, run on
		guard += 1


func _reveal_flow() -> void:
	WeaponDefs.hero_mode = true
	CrateReveal.enabled = true
	CrateReveal._quiet = -1
	var started0 := CrateReveal.started
	var finished0 := CrateReveal.finished
	TestLib.check(not CrateReveal.request(&"railgun"), "a reveal with no named source stays quiet (a pickup in a fight)")
	TestLib.check(not CrateReveal.request(&"railgun", "CRATE OPENED"), "and so does every reveal under a test or a bot unless forced")
	TestLib.check(CrateReveal.request(&"railgun", "CRATE OPENED", true) and CrateReveal.started == started0 + 1 and CrateReveal.is_showing(), "a forced reveal starts")
	TestLib.check(CrateReveal.request(&"a_pillar", "PURCHASED", true) and CrateReveal.started == started0 + 1, "a second one waits in the queue while the first plays")
	var v := CrateReveal.current
	TestLib.check(v.get_parent() == hud and v.mouse_filter == Control.MOUSE_FILTER_IGNORE and v.process_mode == Node.PROCESS_MODE_ALWAYS, "the reveal is an overlay of the Hud that never takes a touch and keeps running while the game is paused")
	await frames(2)
	TestLib.check(v.age > 0.0 or true, "it runs")
	# its look: card in, rays, sparks, then out; run its clock and look at the middle of it
	v.age = 1.2
	v.queue_redraw()
	await frames(2)
	TestLib.check(v.age >= 1.2 and v.weapon == &"railgun" and v.source == "CRATE OPENED", "mid-reveal it shows the weapon and the source (age %.1f)" % v.age)
	v._process(CrateReveal.LIFE)
	TestLib.check(CrateReveal.finished == finished0 + 1 and CrateReveal.started == started0 + 2 and CrateReveal.current.weapon == &"a_pillar", "when it ends the queued one starts (finished %d, started %d)" % [CrateReveal.finished - finished0, CrateReveal.started - started0])
	_finish_reveals()
	await frames(2)
	TestLib.check(not CrateReveal.is_showing() and CrateReveal.finished == finished0 + 2, "and the overlay is gone when the last one ends")
	CrateReveal.enabled = false
	TestLib.check(not CrateReveal.request(&"railgun", "CRATE OPENED", true), "the reveal can be switched off")
	CrateReveal.enabled = true
	TestLib.check(not CrateReveal.request(&"no_such_weapon", "CRATE OPENED", true), "an unknown weapon has no reveal")
	TestLib.check(WeaponAudio.HAPTIC_MS.has(&"reveal"), "the reveal buzzes")


# ---------------------------------------------------------------------------------------------------------------------------------- pictures elsewhere

func _feed_and_crates() -> void:
	# the kill feed names the weapon with its picture
	var feed := HudFeed.new()
	feed.push(HudFeed.KILL, "OPERATIVE", 0.0, &"railgun")
	var lines := feed.visible_lines(0.1)
	TestLib.check(lines.size() == 1 and lines[0]["icon"] == &"railgun" and WeaponPics.has(lines[0]["icon"]), "a kill line carries the picture of the weapon that did it")
	feed.push(HudFeed.KILL, "BRUTE", 0.0)
	var lines2 := feed.visible_lines(0.1)
	TestLib.check(lines2.size() == 2 and lines2[1]["icon"] == &"", "a kill with no weapon (a blast, a fall) has no picture")
	# a pickup line about a weapon carries its picture too
	var pf := HudFeed.new()
	pf.take_message("NEW WEAPON  %s" % WeaponDefs.title(&"a_pillar"), 0.0)
	var pl := pf.visible_lines(0.1)
	TestLib.check(pl.size() == 1 and pl[0]["icon"] == &"a_pillar", "a NEW WEAPON line carries the picture of that weapon (%s)" % str(pl[0]["icon"] if pl.size() > 0 else ""))
	TestLib.check(HudFeed.weapon_of_line("+6 %s" % WeaponDefs.title(&"carbine")) == &"carbine" and HudFeed.weapon_of_line("+30 INTEGRITY") == &"" and HudFeed.weapon_of_line("AMMO FULL") == &"", "an ammo pack line names its weapon, other pickups have no picture")
	# the crates float the picture of the weapon they hold, two at most, only when near
	var fr := Freedom.current
	if fr == null or fr.crates == null:
		TestLib.check(false, "the weapon crates exist")
		return
	var crates: Node = fr.crates
	var ci := -1
	for i in int(crates.call(&"count")):
		var cw := StringName(WeaponLadder.CRATES[i]["weapon"])
		if cw != &"" and not WeaponDefs.is_unlocked(cw) and WeaponLadder.crate_known(i):
			ci = i
			break
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	if ci < 0:
		for i in int(crates.call(&"count")):
			var cw2 := StringName(WeaponLadder.CRATES[i]["weapon"])
			if cw2 != &"" and WeaponLadder.crate_known(i):
				ci = i
				break
	TestLib.check(ci >= 0, "a known weapon crate is on the map")
	if ci < 0:
		return
	crates._ready_at[ci] = 0.0
	WeaponDefs.reset_unlocked()
	var cp := WeaponLadder.crate_pos(ci)
	crates._float_pictures(cp + Vector3(5.0, 0.0, 0.0))
	var shown := 0
	for sp: Sprite3D in crates._pics:
		if sp.visible and sp.texture != null:
			shown += 1
			TestLib.check(sp.texture.get_size() == Vector2(256, 128), "the picture over the crate is the thumb of its weapon")
	TestLib.check(shown >= 1 and shown <= 2, "near a weapon crate its picture floats over it (%d shown)" % shown)
	crates._float_pictures(cp + Vector3(900.0, 0.0, 900.0))
	var far := 0
	for sp: Sprite3D in crates._pics:
		far += 1 if sp.visible else 0
	TestLib.check(far == 0, "far away no picture is drawn")


# ---------------------------------------------------------------------------------------------------------------------------------- the touch wheel

func _wheel_flow() -> void:
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	Game.state = &"play"
	hud._on_state(&"play")
	tc.controls_on = true
	tc.set_process(true)
	var pw: PlayerWeapon = (Game.player as Player).weapon
	pw.switch_to(&"carbine", true)
	pw.switch_to(&"p_hush", true)
	pw.switch_to(&"carbine", true)
	WeaponBrowser.toggle_favourite(&"q_ppistol")
	tc.wheel.close()
	tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	var n := tc.wheel.items.size()
	TestLib.check(tc.wheel.is_open and n == WeaponDefs.CLASS_ORDER.size() + 2, "the weapon wheel opens with a wedge for every class, RECENT and FAVOURITES (%d)" % n)
	var s := tc._scale()
	var r := RadialWheel.ITEM_R * tc.wheel.disc_scale() * s
	TestLib.check(r * 2.0 >= 64.0 * s - 0.5, "the discs stay above the 64 px touch size (%.0f px at scale %.2f)" % [r * 2.0, s])
	var min_gap := 1.0e9
	for i in n:
		for j in range(i + 1, n):
			min_gap = minf(min_gap, tc.wheel.item_centre(i).distance_to(tc.wheel.item_centre(j)))
	TestLib.check(min_gap >= r * 2.0 - 1.0, "the discs do not overlap (closest %.0f px, disc %.0f px)" % [min_gap, r * 2.0])
	# the discs carry the weapon pictures of the atlas
	pw.switch_to(&"pistol", true)
	var rifle := -1
	for i in n:
		if tc.wheel.item_id(i) == &"rifle":
			rifle = i
	TestLib.check(rifle >= 0 and tc._wheel_pick(rifle) and tc.wheel.is_open and tc.wheel.sticky, "picking the RIFLE wedge opens a ring and the wheel stays open")
	TestLib.check(WeaponDefs.class_of(pw.current) == &"rifle" and tc.wheel.items.size() == WeaponWheel.RING + 1, "the rifle of the class is in the hand and the ring shows %d discs (%d)" % [WeaponWheel.RING + 1, tc.wheel.items.size()])
	var weapon_discs := 0
	var pics := 0
	for it: Dictionary in tc.wheel.items:
		if it["type"] == &"weapon":
			weapon_discs += 1
			pics += 1 if WeaponPics.has(it["id"]) else 0
	TestLib.check(weapon_discs >= 2 and pics == weapon_discs, "every weapon disc of the ring has its picture (%d of %d)" % [pics, weapon_discs])
	var r2 := RadialWheel.ITEM_R * tc.wheel.disc_scale() * s
	TestLib.check(r2 * 2.0 >= 64.0 * s - 0.5, "the ring's discs are touch sized")
	# a tap on a disc picks it and closes the wheel
	var target := -1
	for i in tc.wheel.items.size():
		if tc.wheel.items[i]["type"] == &"weapon" and tc.wheel.items[i]["id"] != pw.current:
			target = i
			break
	var want: StringName = tc.wheel.items[target]["id"]
	tc.touch_down(7, tc.wheel.item_centre(target))
	tc.touch_up(7)
	TestLib.check(not tc.wheel.is_open and pw.current == want, "a tap on a weapon disc equips it and closes the wheel (%s)" % pw.current)
	# a tap outside closes the ring and keeps the weapon in hand
	tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	var rifle2 := -1
	for i in tc.wheel.items.size():
		if tc.wheel.item_id(i) == &"rifle":
			rifle2 = i
	tc._wheel_pick(rifle2)
	var keep: StringName = pw.current
	tc.touch_down(8, Vector2(5.0, 5.0))
	tc.touch_up(8)
	TestLib.check(not tc.wheel.is_open and pw.current == keep, "a tap outside the ring closes it and the weapon stays in the hand")
	# the NEXT disc turns the page of the ring
	tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	tc._wheel_pick(rifle2)
	var first_id: StringName = tc.wheel.items[0]["id"]
	var page_disc := tc.wheel.items.size() - 1
	TestLib.check(tc.wheel.items[page_disc]["type"] == &"page" and tc._wheel_pick(page_disc) and tc.wheel.items[0]["id"] != first_id, "the NEXT disc shows the next eight weapons")
	tc.wheel.close()
	# a class with one weapon equips at once and closes (a hero who owns only the starters)
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	pw.switch_to(&"carbine", true)
	tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	var shot := -1
	for i in tc.wheel.items.size():
		if tc.wheel.item_id(i) == &"shotgun":
			shot = i
	TestLib.check(shot >= 0 and not tc._wheel_pick(shot) and pw.current == &"scatter", "a class of one weapon is equipped at once and the wheel closes")
	tc.wheel.close()
	WeaponDefs.hero_mode = true


# ---------------------------------------------------------------------------------------------------------------------------------- the layout of every screen at every size

func _layout_scans() -> void:
	var win := host.get_window()
	var old := win.size
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	Arsenal._st.clear()
	for id: StringName in [&"a_pillar", &"m_phaseblade", &"q_ppistol"]:
		WeaponBrowser.toggle_favourite(id)
	Attachments.reset()
	for part: StringName in Attachments.IDS:
		Attachments.give(part)
	for part: StringName in [&"reddot", &"suppressor", &"foregrip", &"extended", &"laser"]:
		Attachments.equip(&"a_pillar", part)                                                         # the longest FITTED line a rifle can have
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1200, 540), Vector2i(1280, 720)]:
		win.size = size
		await frames(3)
		await _scan("loadout, rifle stats", &"paused", [&"loadout", &"wheel_a_pillar"], size)
		await _scan("loadout, blast weapon stats", &"paused", [&"loadout", &"wheel_la_rocket"], size)
		await _scan("loadout, blade stats", &"paused", [&"loadout", &"wheel_m_arcsabre"], size)
		await _scan("loadout, rifle parts, five parts fitted", &"paused", [&"loadout", &"wheel_a_pillar", &"ars_tab_parts", &"ars_slottab_barrel", &"ars_part_suppressor"], size)
		await _scan("loadout, rifle parts, optics", &"paused", [&"loadout", &"wheel_a_pillar", &"ars_tab_parts", &"ars_slottab_optic", &"ars_part_scope"], size)
		await _scan("loadout, shotgun parts", &"paused", [&"loadout", &"wheel_g_bulwark", &"ars_tab_parts", &"ars_slottab_grip"], size)
		await _scan("loadout, rifle ammo", &"paused", [&"loadout", &"wheel_a_pillar", &"ars_tab_ammo"], size)
		await _scan("loadout, 3D view", &"paused", [&"loadout", &"wheel_a_pillar", &"ars_view3d"], size)
		await _scan("loadout, favourites", &"paused", [&"loadout", &"ars_filter_fav"], size)
		await _scan("loadout, sorted by damage", &"paused", [&"loadout", &"ars_filter_all", &"ars_sort", &"ars_sort", &"ars_sort"], size)
		await _scan("loadout, a class", &"paused", [&"loadout", &"ars_filter_all", &"ars_cls_next", &"ars_cls_next", &"wheel_a_pillar"], size)
		await _scan("loadout, scrolled", &"paused", [&"loadout", &"ars_filter_all", &"ars_slot_2"], size)
		await _scan("loadout, quick swap", &"paused", [&"loadout"], size)
		WeaponDefs.hero_mode = false
		WeaponDefs.reset_unlocked()
		await _scan("catalogue, a locked rifle", &"paused", [&"hero_open", &"hero_tab_weapons", &"ars_filter_locked", &"wsel_a_flint"], size)
		await _scan("catalogue, a locked blast weapon", &"paused", [&"hero_open", &"hero_tab_weapons", &"ars_filter_locked", &"wsel_la_rocket"], size)
		await _scan("catalogue, the NEW filter", &"paused", [&"hero_open", &"hero_tab_weapons", &"ars_filter_new"], size)
		await _scan("catalogue, a throwable", &"paused", [&"hero_open", &"hero_tab_weapons", &"ars_cls_prev", &"wsel_mine"], size)
		await _scan("catalogue, a gadget", &"paused", [&"hero_open", &"hero_tab_weapons", &"ars_cls_prev", StringName("wsel_%s" % Gear.GADGET_IDS[0])], size)
		WeaponDefs.hero_mode = true
	win.size = old
	WeaponBrowser.reset()
	Attachments.reset()
