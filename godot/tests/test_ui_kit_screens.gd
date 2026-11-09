extends RefCounted
## The UI kit and every screen built on it (owner round 5: "much better, more detailed UI for menus, options and weapons"; scripts/ui/ui_kit.gd, weapon_preview.gd). Real scene (main.tscn).
## (1) KIT: spacing grid, type scale, enter transition, class colours, cut-corner polygon, word wrap, kit constants.
## (2) LAYOUT SCAN of every screen at 844x390, 1200x540 (the 2400x1080 phone at half size) and 1280x720: every queued text lies on screen, fits its box, is at least BODY_MIN, overlaps no other text and
##     does not straddle a button edge; every button is on screen, >= 64 base px and overlaps no other button. Screens: title, EXTRAS, the five options tabs, pause, UPGRADES cards, the weapon catalogue
##     (a weapon that is not in hand, so the compare marks show), LOADOUT with the 3D preview, GEAR, SUIT, MISSIONS, dead.
## (3) WEAPON PREVIEW: the 3D turntable shows a weapon model, a drag turns it, a tap swings it back, a throwable has no model (its picture is drawn instead); the loadout and the catalogue register the
##     preview rect so Hud routes a drag into it; stat bars compare with the weapon in hand.
## (4) The options rows: switches for yes / no options with a hint line; the upgrade cards fit; the garage screen on the kit (buttons >= 64, on screen at phone size).
## Waits on counters and state, never on frame counts. Run: tools/test.sh tests/test_ui_kit_screens.gd

const SCREENS := [
	["title", &"menu", []],
	["title_more", &"menu", [&"menu_gear"]],
	["title_options", &"menu", [&"options"]],
	["opt_controls", &"paused", [&"options", &"opt_tab_0"]],
	["opt_graphics", &"paused", [&"options", &"opt_tab_1"]],
	["opt_sound", &"paused", [&"options", &"opt_tab_2"]],
	["opt_access", &"paused", [&"options", &"opt_tab_3"]],
	["opt_game", &"paused", [&"options", &"opt_tab_4"]],
	["pause", &"paused", []],
	["pause_more", &"paused", [&"menu_gear"]],
	["board", &"paused", [&"board_open"]],
	["hero_upgrades", &"paused", [&"hero_open"]],
	["hero_weapons", &"paused", [&"hero_open", &"hero_tab_weapons", &"wsel_vector"]],
	["hero_weapons_snipers", &"paused", [&"hero_open", &"hero_tab_weapons", &"wpg_next", &"wpg_next"]],
	["hero_weapons_gadgets", &"paused", [&"hero_open", &"hero_tab_weapons", &"wpg_prev"]],
	["loadout", &"paused", [&"loadout"]],
	["loadout_class2", &"paused", [&"loadout", &"wheelpg_next"]],
	["gear", &"paused", [&"loadout", &"loadout_gear"]],
	["look", &"paused", [&"menu_gear", &"look_open"]],
	["dead", &"dead", []],
]

var host: Node
var main: Node
var hud: Hud


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _open(state: StringName, chain: Array) -> void:
	Game.state = &"play"
	Game.state = state
	hud._on_state(state)
	hud.screen_age = 5.0
	hud._sub_t = 5.0
	if Game.progress != null:
		Game.progress.credits = 700
	hud._layout_key = ""
	hud._ensure_layout()
	for id: StringName in chain:
		hud.press_button(id)
		hud._layout_key = ""
		hud._ensure_layout()


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


# --- 1 kit -----------------------------------------------------------------------------------------------------------------------

func _kit_unit() -> void:
	TestLib.check(UiKit.UNIT == 8.0 and is_equal_approx(UiKit.sp(3.0, 2.0), 48.0), "the spacing grid is 8 base px (3 units at scale 2 = 48 px)")
	TestLib.check(UiKit.T_CAP >= Hud.BODY_MIN and UiKit.T_CAP < UiKit.T_BODY and UiKit.T_BODY < UiKit.T_LABEL and UiKit.T_LABEL < UiKit.T_TITLE and UiKit.T_TITLE < UiKit.T_HERO, "the type scale rises and never goes below BODY_MIN")
	TestLib.check(is_equal_approx(UiKit.ease_out(0.0), 0.0) and is_equal_approx(UiKit.ease_out(1.0), 1.0) and UiKit.ease_out(0.5) > 0.5, "the enter ease starts at 0, ends at 1 and is front-loaded")
	TestLib.check(UiKit.enter_offset(0.0, 1.5) > 0.0 and is_equal_approx(UiKit.enter_offset(UiKit.ENTER_TIME, 1.5), 0.0) and UiKit.ENTER_TIME <= 0.3, "a screen slides in within %.2f s and rests at offset 0" % UiKit.ENTER_TIME)
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		TestLib.check(UiKit.CLASS_TINT.has(cls), "weapon class %s has its kit colour" % cls)
	var r := Rect2(10.0, 20.0, 200.0, 80.0)
	var poly := UiKit.cut_poly(r, 12.0)
	var inside := true
	for p: Vector2 in poly:
		inside = inside and r.grow(0.01).has_point(p)
	TestLib.check(poly.size() == 6 and inside, "the cut-corner panel polygon has six points, all inside its rect")
	var font := UiUtil.font()
	var lines := UiKit.wrap_text(hud, font, "ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN", 120.0, 20, 3)
	TestLib.check(lines.size() >= 2 and lines.size() <= 3 and " ".join(lines) == "ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN", "wrap_text keeps every word and at most max_lines lines (%d)" % lines.size())


# --- 3 preview -------------------------------------------------------------------------------------------------------------------

func _preview() -> void:
	WeaponPreview.freeze = true
	var pv := WeaponPreview.of(hud)
	TestLib.check(pv != null and pv.get_parent() == hud, "one preview serves the Hud")
	TestLib.check(pv.show_weapon(&"carbine") and pv.weapon == &"carbine" and pv.framed_size > 0.2, "the carbine's own model is on the turntable (framed at %.2f)" % pv.framed_size)
	TestLib.check(not pv.show_weapon(&"frag") and pv.weapon == &"", "a throwable has no model: the screens draw its picture instead")
	TestLib.check(pv.show_weapon(&"railgun") and pv.framed_size > 0.2, "a roster weapon frames too")
	pv.show_weapon(&"carbine")
	var y0 := pv.yaw
	pv.rotate_by(40.0)
	TestLib.check(not is_equal_approx(pv.yaw, y0) and pv.drag_hold > 0.0, "a drag turns the weapon and holds the idle spin")
	pv.reset_view()
	TestLib.check(is_equal_approx(pv.yaw, WeaponPreview.SIDE_YAW), "a tap swings it back to the side view")
	# every weapon of the game has a model the preview can frame
	var missing: Array[String] = []
	for id: StringName in WeaponDefs.IDS:
		if not pv.show_weapon(id):
			missing.append(String(id))
	TestLib.check(missing.is_empty(), "every weapon has a 3D model for the preview (%s)" % ", ".join(missing))
	# the loadout registers the rect and the Hud routes a drag into it
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	_open(&"paused", [&"loadout"])
	hud._screen.queue_redraw()
	for i in 60:
		await frames(1)
		if hud.preview_rect.has_area():
			break
	TestLib.check(hud.preview_rect.has_area(), "the loadout draws the preview and registers its rect")
	var vp := hud.get_viewport().get_visible_rect().size
	TestLib.check(Rect2(Vector2.ZERO, vp).encloses(hud.preview_rect), "the preview is on screen")
	var clash := ""
	for b: Dictionary in hud.buttons:
		if (b["rect"] as Rect2).intersects(hud.preview_rect):
			clash = String(b["id"])
	TestLib.check(clash == "", "no button lies over the preview (%s)" % clash)
	var pv2 := WeaponPreview.of(hud)
	pv2.reset_view()
	var yb := pv2.yaw
	var mid := hud.preview_rect.get_center()
	TestLib.check(hud.tap(mid) and hud._pv_drag, "a finger on the preview starts a drag")
	hud._pv_turn(mid.x + 60.0)
	hud.end_drag()
	TestLib.check(not is_equal_approx(pv2.yaw, yb) and not hud._pv_drag, "dragging across the preview turns the weapon, releasing ends the drag")
	hud.tap(mid)
	hud.end_drag()
	TestLib.check(is_equal_approx(pv2.yaw, WeaponPreview.SIDE_YAW), "a tap without a drag swings it back to the side view")
	# the compare: a selected weapon that is not in hand is judged against the one that is
	WeaponDefs.last_used = &"carbine"
	TestLib.check(LoadoutScreen.compare_id(&"carbine") == &"" and LoadoutScreen.compare_id(&"railgun") == &"carbine", "stat bars compare with the weapon in hand (and not with itself)")
	var bars: Dictionary = WeaponStats.card(&"railgun", Attachments.effective(&"railgun"))["bars"]
	var base: Dictionary = WeaponStats.card(&"carbine", Attachments.effective(&"carbine"))["bars"]
	TestLib.check(bars.has(&"damage") and base.has(&"damage"), "both weapons have the bars the compare reads")
	# the catalogue
	_open(&"paused", [&"hero_open", &"hero_tab_weapons", &"wpg_next", &"wpg_next", &"wsel_amr"])
	hud._screen.queue_redraw()
	for i in 60:
		await frames(1)
		if hud.preview_rect.has_area():
			break
	TestLib.check(hud.preview_rect.has_area(), "the weapon catalogue draws the preview too")
	_open(&"paused", [&"hero_open", &"hero_tab_weapons", &"wpg_prev"])         # the gadgets page: a gadget has no 3D model, its picture is drawn
	hud._screen.queue_redraw()
	await frames(3)
	TestLib.check(not hud.preview_rect.has_area(), "a gadget page registers no preview rect (its picture is drawn)")
	WeaponDefs.reset_unlocked()
	WeaponDefs.last_used = &"carbine"


# --- 4 options, upgrade cards, garage -------------------------------------------------------------------------------------------------

func _options_rows() -> void:
	_open(&"paused", [&"options", &"opt_tab_0"])
	var toggles := 0
	var hints := 0
	for b: Dictionary in hud.buttons:
		if b.get("toggle", false):
			toggles += 1
			if String(b.get("hint", "")) != "":
				hints += 1
	TestLib.check(toggles >= 3 and hints >= 3, "the options page draws yes / no options as switches with a hint line (%d switches, %d hints)" % [toggles, hints])
	for id: StringName in OptionsScreen.HINTS:
		TestLib.check(String(OptionsScreen.HINTS[id]).length() <= 36, "the hint of %s is one short line (%d chars)" % [id, String(OptionsScreen.HINTS[id]).length()])
	_open(&"paused", [&"options", &"opt_tab_1"])
	var tiers := 0
	for b: Dictionary in hud.buttons:
		if String(b["id"]).begins_with("opt_tierset_"):
			tiers += 1
	TestLib.check(tiers == 4 and hud.buttons.any(func(b: Dictionary) -> bool: return b.get("prev", false)), "the graphics tab keeps its four presets and the live preview card")


func _upgrade_cards() -> void:
	for vp: Vector2 in [Vector2(844.0, 390.0), Vector2(1200.0, 540.0), Vector2(1280.0, 720.0)]:
		var s := UiUtil.ui_scale(vp)
		for n in [5, 9]:
			var rects: Array[Rect2] = []
			for i in n:
				rects.append(ShopScreen.card_rect(hud, vp.x * 0.5, s, i, n))
			var bad := ""
			for i in n:
				if rects[i].size.y < 64.0 * s or rects[i].position.x < 0.0 or rects[i].end.x > vp.x + 1.0:
					bad = "card %d %s off screen or short" % [i, rects[i]]
				for j in range(i + 1, n):
					if rects[i].intersects(rects[j]):
						bad = "cards %d and %d overlap" % [i, j]
			TestLib.check(bad == "", "%dx%d: %d upgrade cards fit and do not overlap (%s)" % [int(vp.x), int(vp.y), n, bad])


func _garage() -> void:
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1200, 540)]:
		win.size = size
		await frames(3)
		Game.state = &"play"
		var gs := GarageScreen.new()
		host.add_child(gs)
		gs.open()
		await frames(2)
		var k := gs.fit(gs.get_viewport().get_visible_rect().size)
		var vp := gs.get_viewport().get_visible_rect().size
		var bad := ""
		for nm in ["Save", "Close", "Paint0", "Paint7", "Up_speed", "Up_armour", "Up_grip", "Up_weapon"]:
			var b := gs.find_child(nm, true, false) as Button
			if b == null:
				bad = "%s missing" % nm
				continue
			if b.custom_minimum_size.y < 64.0:
				bad = "%s under 64" % nm
			var r := Rect2(b.global_position, b.size * k)
			if not Rect2(Vector2.ZERO, vp).grow(2.0).encloses(r):
				bad = "%s off screen %s" % [nm, r]
		TestLib.check(bad == "", "%dx%d: the garage on the kit has every button, touch sized and on screen (%s)" % [size.x, size.y, bad])
		var up := gs.find_child("Up_speed", true, false) as Button
		var face := up.get_child(0)
		TestLib.check(face != null and face.get("kind") == "up", "an upgrade row is a Button with a kit face")
		gs.close_screen()
		gs.queue_free()
	win.size = old


func _transition() -> void:
	_open(&"paused", [&"loadout"])
	hud._sub_t = 5.0
	hud._screen_sig = "x"
	hud._process(0.01)                                  # a change of screen restarts the enter clock
	TestLib.check(hud._sub_t < UiKit.ENTER_TIME, "opening another screen restarts the enter transition (%.2f)" % hud._sub_t)
	hud._sub_t = 5.0


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
	if hud.touch != null:
		hud.touch.controls_on = true                        # the phone: no desktop key footer
	_kit_unit()
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1200, 540), Vector2i(1280, 720)]:        # 1200 x 540 is the 2400 x 1080 phone at half size: the same aspect, the same base px layout
		win.size = size
		await frames(4)
		for sc: Array in SCREENS:
			if String(sc[0]).begins_with("hero_weapons") or String(sc[0]).begins_with("loadout"):
				for id: StringName in WeaponDefs.IDS:
					WeaponDefs.unlock(id)                   # every weapon owned: the busiest tabs
			await _scan(String(sc[0]), sc[1], sc[2], size)
		WeaponDefs.reset_unlocked()
	win.size = old
	await frames(3)
	await _preview()
	_options_rows()
	_upgrade_cards()
	_transition()
	await _garage()
	Game.state = &"play"
	hud.touch.controls_on = false
	await frames(2)
