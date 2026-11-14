extends RefCounted
## The weapon screens with 200+ weapons, through the real Hud in main.tscn (wave 113): the LOADOUT (class chips, pages of eight, the star and the FAVOURITES and RECENT tabs, slot tabs and part cards, BUY and
## EQUIP of the five attachment slots, a weapon that takes no parts), the HERO hub CATALOGUE (class chips, nine tiles a page, BUY of a new weapon) and the two-level WEAPON wheel of the touch controls (twelve discs,
## a class ring, a tap on a disc, a tap outside). The layout of the new screens is scanned at 844x390, 1200x540 and 1280x720 like tests/test_ui_kit_screens.gd: every text on screen, in its box, readable, no
## overlap, every button 64 base px or more and on screen. Waits on counters and state, never on frame counts. Run: tools/test.sh tests/test_weapon_ui_v3.gd (about 45 s)

var host: Node
var main: Node
var hud: Hud
var tc: TouchControls


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
		if br.size.y < 63.9 * s:
			bad.append("button under 64 %s" % b["id"])
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
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	tc = hud.touch
	TestLib.check(hud != null and tc != null, "the Hud and its touch controls exist")
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	Attachments.reset()
	LoadoutScreen.reset_page()
	LoadoutScreen.slot_tab = &"optic"
	await _loadout_flow()
	await _catalogue_flow()
	await _wheel_flow()
	await _layout_scans()
	# leave the profile as it was found
	if tc.wheel.is_open:
		tc.wheel.close()
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Attachments.reset()
	LoadoutScreen.reset_page()
	LoadoutScreen.slot_tab = &"optic"
	Game.state = &"play"


func _loadout_flow() -> void:
	_open(&"paused", [&"loadout", &"wheel_a_pillar"])
	TestLib.check(_count("wheel_") >= 1 and _count("wheel_") <= WeaponBrowser.PAGE and hud._loadout_w == &"a_pillar", "the loadout shows at most %d weapon tiles of a page (%d) and the PILLAR is selected" % [WeaponBrowser.PAGE, _count("wheel_")])
	var ids := _ids()
	TestLib.check(ids.has("wheelcls_prev") and ids.has("wheelcls_next") and ids.has("wheelpg_prev") and ids.has("wheelpg_next") and ids.has("fav_toggle"), "class chips, page arrows and the star are on screen")
	var slot_ids := ["slot_optic", "slot_barrel", "slot_grip", "slot_core", "slot_laser"]
	var have_slots := true
	for sid in slot_ids:
		have_slots = have_slots and ids.has(sid)
	TestLib.check(have_slots and _count("slot_") == 5, "a rifle shows five slot tabs: OPTIC MUZZLE GRIP MAGAZINE LASER (%d)" % _count("slot_"))
	var optic_parts := _count("part_")
	TestLib.check(optic_parts == Attachments.parts_for_weapon(&"optic", &"a_pillar").size() and optic_parts >= 4, "the open slot shows the optics the rifle can wear (%d)" % optic_parts)
	# the class chips visit every tab and come back
	var start := LoadoutScreen.page_name()
	var seen := {}
	for i in LoadoutScreen.tab_count():
		seen[LoadoutScreen.page_name()] = true
		hud.press_button(&"wheelcls_next")
	TestLib.check(seen.size() == LoadoutScreen.tab_count() and LoadoutScreen.page_name() == start, "the class chips visit all %d tabs and return to %s" % [LoadoutScreen.tab_count(), start])
	# a slot tab shows its own cards
	_open(&"paused", [&"loadout", &"wheel_a_pillar", &"slot_laser"])
	var cards := _ids().filter(func(i: String) -> bool: return i.begins_with("part_"))
	TestLib.check(cards.has("part_laser") and cards.has("part_precision") and cards.has("part_marker") and not cards.has("part_reddot"), "the LASER tab shows the three laser parts only (%s)" % str(cards))
	# buy, equip, take off
	var prog := Game.progress as Progress
	prog.credits = 5000
	Attachments.reset()
	var price := prog.part_price(&"precision")
	TestLib.check(hud.press_button(&"part_precision") and Attachments.is_owned(&"precision") and Attachments.part_in(&"a_pillar", &"laser") == &"precision" and prog.credits == 5000 - price,
			"BUY on a part card buys it for %d and puts it on the weapon" % price)
	TestLib.check(hud.press_button(&"part_precision") and Attachments.part_in(&"a_pillar", &"laser") == &"", "tapping the fitted part takes it off")
	TestLib.check(not hud.press_button(&"part_choke") and not Attachments.is_owned(&"choke"), "a part the weapon cannot wear cannot be bought for it")
	hud.press_button(&"part_laser")
	hud.press_button(&"slot_core")
	hud.press_button(&"part_fastmag")
	TestLib.check(Attachments.part_in(&"a_pillar", &"laser") == &"laser" and Attachments.part_in(&"a_pillar", &"core") == &"fastmag", "parts of two slots stay fitted together")
	# the favourite star
	WeaponBrowser.reset()
	var tabs0 := LoadoutScreen.tab_count()
	TestLib.check(hud.press_button(&"fav_toggle") and WeaponBrowser.is_favourite(&"a_pillar") and LoadoutScreen.tab_count() == tabs0 + 1, "the star makes a favourite and opens a FAVOURITES tab")
	LoadoutScreen.goto(&"a_pillar")
	var fav_page := WeaponBrowser.page_of(&"a_pillar")
	TestLib.check(fav_page >= 0 and LoadoutScreen.pages()[fav_page]["tab"] == &"rifle", "the page follows the weapon into its class tab, not into FAVOURITES")
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"fav_toggle") and not WeaponBrowser.is_favourite(&"a_pillar"), "a second tap on the star takes it away")
	# a weapon of the hand takes no parts
	_open(&"paused", [&"loadout", &"wheel_m_arcsabre"])
	TestLib.check(_count("slot_") == 0 and _count("part_") == 0 and Game.player.weapon.current == &"m_arcsabre", "a blade shows no slot tabs and no part cards")
	# RECENT fills as weapons are used
	WeaponBrowser.reset()
	for id: StringName in [&"s_rivet", &"a_flint", &"g_cyclone"]:
		hud.press_button(StringName("wheel_%s" % id))
	TestLib.check(WeaponBrowser.recent.size() == 3 and WeaponBrowser.recent[0] == &"g_cyclone" and LoadoutScreen.pages()[0]["tab"] == WeaponBrowser.RECENT, "the weapons put in the hand fill RECENT, the newest first (%s)" % str(WeaponBrowser.recent))


func _catalogue_flow() -> void:
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	_open(&"paused", [&"hero_open", &"hero_tab_weapons"])
	var ids := _ids()
	TestLib.check(ids.has("wcls_prev") and ids.has("wcls_next") and ids.has("wpg_prev") and ids.has("wpg_next") and _count("wsel_") >= 3 and _count("wsel_") <= WeaponsScreen.PER_PAGE,
			"the catalogue shows its class chips, page arrows and at most %d tiles (%d)" % [WeaponsScreen.PER_PAGE, _count("wsel_")])
	var p0 := ShopScreen.weapon_page
	hud.press_button(&"wcls_next")
	TestLib.check(ShopScreen.weapon_page != p0 and WeaponsScreen.page_list()[ShopScreen.weapon_page - 1]["tab"] != WeaponsScreen.page_list()[p0 - 1]["tab"], "the class chip jumps to the next class")
	hud.press_button(&"wcls_prev")
	TestLib.check(ShopScreen.weapon_page == p0, "and back")
	# buy a weapon of the roster through the HERO hub
	var prog := Game.progress as Progress
	prog.credits = 5000
	WeaponsScreen.select(&"p_hush")
	hud._layout_key = ""
	hud._ensure_layout()
	var price := prog.weapon_price(&"p_hush")
	TestLib.check(_ids().has("buy_p_hush") and not WeaponDefs.is_unlocked(&"p_hush"), "the HUSH SILENCED PISTOL is for sale on its page (%d)" % price)
	TestLib.check(hud.press_button(&"buy_p_hush") and WeaponDefs.is_unlocked(&"p_hush") and prog.credits == 5000 - price, "BUY unlocks it and pays the price")
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(_ids().has("wequip_p_hush") and hud.press_button(&"wequip_p_hush") and Game.player.weapon.current == &"p_hush", "then EQUIP puts it in the hand")
	# every page of the catalogue stays within the screen (the three sizes are scanned below)
	var worst := 0
	for pg in WeaponsScreen.PAGES:
		ShopScreen.weapon_page = 1 + pg
		hud._layout_key = ""
		hud._ensure_layout()
		worst = maxi(worst, _count("wsel_"))
	TestLib.check(worst <= WeaponsScreen.PER_PAGE, "no page of the %d has more than %d tiles (%d)" % [WeaponsScreen.PAGES, WeaponsScreen.PER_PAGE, worst])
	WeaponDefs.reset_unlocked()


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
	# a flick onto the RIFLE wedge: its weapon is in the hand and the wheel stays open as a ring
	pw.switch_to(&"pistol", true)
	var rifle := -1
	for i in n:
		if tc.wheel.item_id(i) == &"rifle":
			rifle = i
	TestLib.check(rifle >= 0 and tc._wheel_pick(rifle) and tc.wheel.is_open and tc.wheel.sticky, "picking the RIFLE wedge opens a ring and the wheel stays open")
	TestLib.check(WeaponDefs.class_of(pw.current) == &"rifle" and tc.wheel.items.size() == WeaponWheel.RING + 1, "the rifle of the class is in the hand and the ring shows %d discs (%d)" % [WeaponWheel.RING + 1, tc.wheel.items.size()])
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


func _layout_scans() -> void:
	var win := host.get_window()
	var old := win.size
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	for id: StringName in [&"a_pillar", &"m_phaseblade", &"q_ppistol"]:
		WeaponBrowser.toggle_favourite(id)
	for id: StringName in [&"e_pulse", &"g_bulwark", &"c_scout"]:
		WeaponBrowser.note_used(id)
	Attachments.reset()
	for part: StringName in Attachments.IDS:
		Attachments.give(part)
	for part: StringName in [&"reddot", &"suppressor", &"foregrip", &"extended", &"laser"]:
		Attachments.equip(&"a_pillar", part)                                                         # the longest FITTED line a rifle can have
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1200, 540), Vector2i(1280, 720)]:
		win.size = size
		await frames(3)
		await _scan("loadout rifle, five parts fitted", &"paused", [&"loadout", &"wheel_a_pillar", &"slot_barrel"], size)
		await _scan("loadout rifle, second page of optics", &"paused", [&"loadout", &"wheel_a_pillar", &"slot_optic"], size)
		await _scan("loadout shotgun muzzle", &"paused", [&"loadout", &"wheel_g_bulwark", &"slot_barrel"], size)
		await _scan("loadout pistol grip", &"paused", [&"loadout", &"wheel_p_spark", &"slot_grip"], size)
		await _scan("loadout blade", &"paused", [&"loadout", &"wheel_m_arcsabre"], size)
		await _scan("loadout quantum page", &"paused", [&"loadout", &"wheel_q_ppistol", &"wheelpg_next"], size)
		await _scan("loadout favourites", &"paused", [&"loadout", &"wheelpg_prev", &"wheelpg_next"], size)
		await _scan("catalogue rifles", &"paused", [&"hero_open", &"hero_tab_weapons", &"wcls_next", &"wcls_next", &"wsel_a_pillar"], size)
		await _scan("catalogue melee second page", &"paused", [&"hero_open", &"hero_tab_weapons", &"wcls_next", &"wcls_next", &"wcls_next", &"wcls_next", &"wcls_next", &"wpg_next", &"wsel_m_arcsabre"], size)
		await _scan("catalogue energy", &"paused", [&"hero_open", &"hero_tab_weapons", &"wsel_e_ioncan"], size)
	win.size = old
	WeaponBrowser.reset()
	Attachments.reset()
