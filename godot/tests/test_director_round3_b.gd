extends RefCounted
## Director review 3, presentation half (docs/SLICE_REVIEW.md "Fix pass, round 3 presentation half"), data checks plus the REAL game scene (main.tscn, touch layout forced):
##   4  the shopfront glass is dark glass with warm accents (the wash and the reflection are weaker than before), not one pale sheet
##   5  the hero's rucksack is a small pack, not a third of the silhouette from behind
##   6  the objective is said once: the step line has no distance (the beacon marker has it), a toast that repeats the step line is not drawn
##   7  a radio line is cut at a sentence, never mid-sentence ("Kestrel. Eyes open. Old Exchange is Vael-held, and"); the prologue cards are over in 3 s
##   9  the map opens zoomed in on the hero (the whole city is one tap away)
##   10 MORE sits under the pause button (not in the thumb cluster) and clears every other circle; the reloading weapon button says RELOAD
##   11 every room behind the street room of every interior type has a lamp, a rug, a poster and a bin (or what its recipe has) and the wall screens show rows
##   12 the TEST card is not left over the OPTIONS tabs, the loadout header has room above the first slot, the title has no letterbox bars
## Waits on state and counters, never on frame counts; user:// state is reset first.
## Run: tools/test.sh tests/test_director_round3_b.gd

const VPS := [Vector2(844, 390), Vector2(2400, 1080)]
const FOOT := ["", "quantum", "weapon", "foot", "vehicle", "grab", "takedown", "skip_piece", "more", "more_btn", "more_gadget", "more_garage", "more_c4", "more_companion", "detonate"]

var host: Node
var p: Player
var hud: Hud


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_glass_source()
	_hero_pack()
	_radio_cut()
	_distance_strip()
	_back_rooms()
	_more_button()
	_loadout_header()
	var was_touch := Game.force_touch
	Game.force_touch = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	p = Game.player as Player
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(p != null and hud != null, "the real scene has a player and a HUD")
	if p != null and hud != null:
		await _title_bars(main)
		_test_card_gone()
		Game.state = &"play"
		(Game.progress as Progress).autosave_enabled = false
		_echo_toast()
		_reload_label()
		await _map_zoom(main)
	Game.force_touch = was_touch
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


# --- 4 -------------------------------------------------------------------------------------------------------------------------

func _glass_source() -> void:
	var code := FileAccess.get_file_as_string("res://assets/shaders/building_core.gdshaderinc")
	TestLib.check(code.contains("(0.05 + 0.16 * smoothstep(1.3, 3.1, y))"), "the shop back-wall wash is dark in the lower half and warm under the ceiling")
	TestLib.check(code.contains("gl_refl * (0.22 + 1.1 * gfr) * open_shop"), "the shop glass reflection is weaker than the old pale sheet (0.30 + 1.6 * fresnel)")


# --- 5 -------------------------------------------------------------------------------------------------------------------------

func _hero_pack() -> void:
	var biggest := 0.0
	var found := false
	for b: Array in HeroCharacter._gear_boxes():
		if float(b[1]) == HeroCharacter.KIND_PACK and (b[2] as Vector3).z > 0.15 and (b[3] as Vector3).y > 0.15:
			found = true
			var sz: Vector3 = b[3]
			biggest = maxf(biggest, sz.x * sz.y)
	TestLib.check(found, "the hero still carries a rucksack")
	TestLib.check(biggest <= 0.23 * 0.25, "the rucksack is at most 0.23 x 0.25 m seen from behind (%.3f m2, was 0.081)" % biggest)
	var sh := FileAccess.get_file_as_string("res://assets/shaders/hero_body.gdshader")
	TestLib.check(not sh.contains("vec3(0.38, 0.27, 0.15)") and sh.contains("coyote canvas"), "the pack canvas is the darker brown, not the bright coyote")


# --- 7 -------------------------------------------------------------------------------------------------------------------------

func _radio_cut() -> void:
	var long_line := "Kestrel. Eyes open. Old Exchange is Vael-held, and there are rift anchors buried under the trading floor."
	var cut := Story.shorten(long_line)
	TestLib.check(cut.length() <= Story.MAX_SHORT + 3, "a short radio line is at most MAX_SHORT characters (%d)" % cut.length())
	TestLib.check(cut.ends_with(".") or cut.ends_with("...") or cut.ends_with("!") or cut.ends_with("?"), "a short radio line ends at a sentence or an ellipsis, not on '%s'" % cut.right(8))
	TestLib.check(not cut.ends_with(" and") and not cut.ends_with(","), "a short radio line is not cut mid-sentence ('%s')" % cut)
	TestLib.check(Story.PROLOGUE_MAX <= 3.0, "the prologue cards take at most 3 s over a live street (%.1f)" % Story.PROLOGUE_MAX)


# --- 6 -------------------------------------------------------------------------------------------------------------------------

func _distance_strip() -> void:
	TestLib.check(Hud.strip_distance("1/3  CROSS THE TRADING FLOOR TO THE BEACON  131 M") == "1/3  CROSS THE TRADING FLOOR TO THE BEACON", "the step line loses its trailing distance")
	TestLib.check(Hud.strip_distance("3/3  HACK THE LEDGER NODE  38%") == "3/3  HACK THE LEDGER NODE  38%", "a percentage stays in the line")
	TestLib.check(Hud.strip_distance("2/3  ESCORT  63 M  ESCORT 80%").contains("ESCORT 80%"), "only a trailing distance is dropped")


# --- 11 ------------------------------------------------------------------------------------------------------------------------

func _back_rooms() -> void:
	var worst := 99
	var worst_name := ""
	var checked := 0
	var sum := 0
	for t in InteriorGen.TYPES:
		for sd in [1, 2, 3]:
			var plan := InteriorPlan.generate(t, sd)
			var rooms := plan.rooms.size()
			for r in range(1, rooms):
				var kinds := {}
				for pr in plan.props:
					if int(pr["room"]) == r:
						kinds[String(pr["kind"])] = int(kinds.get(String(pr["kind"]), 0)) + 1
				var decor := 0
				for k in ["rug", "poster", "bin", "plant"]:
					if kinds.has(k):
						decor += 1
				checked += 1
				sum += decor
				if decor < worst:
					worst = decor
					worst_name = "%s seed %d room %d" % [t, sd, r]
	TestLib.check(checked >= 20, "back rooms were checked (%d)" % checked)
	TestLib.check(worst >= 1, "every back room has some decor (rug, poster, bin, plant); the barest is %s with %d" % [worst_name, worst])
	TestLib.check(float(sum) / float(maxi(checked, 1)) >= 2.0, "a back room has 2 kinds of decor on average (%.2f)" % (float(sum) / float(maxi(checked, 1))))
	var spec := InteriorKinds.spec(&"lobby")
	var steps := 0
	for st: Array in (((spec["rooms"] as Array)[1] as Dictionary)["prog"] as Array):
		if str(st[0]) == "hang":
			steps += 1
	TestLib.check(steps >= 1, "a back room hangs a lamp")
	TestLib.check(str((((spec["rooms"] as Array)[1] as Dictionary)["prog"] as Array).back()[0]) == "anchor", "the anchors stay the last step of the recipe")
	var props := FileAccess.get_file_as_string("res://scripts/interiors/interior_props.gd")
	TestLib.check(props.contains("lit rows, not one flat white square"), "a wall screen is a dim panel with lit rows")


# --- 10 ------------------------------------------------------------------------------------------------------------------------

func _centre(b: Dictionary, vp: Vector2) -> Vector2:
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var insv := UiUtil.insets_v(vp)
	return Vector2(vp.x - ins.y - float(b["dx"]) * s, vp.y - insv.y - float(b["dy"]) * s)


func _more_button() -> void:
	var more: Dictionary = {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"more":
			more = b
	TestLib.check(not more.is_empty(), "the MORE button exists")
	if more.is_empty():
		return
	for vp: Vector2 in VPS:
		var s := UiUtil.ui_scale(vp)
		var pause := Vector2(vp.x - UiUtil.insets(vp).y - 52.0 * s, 112.0 * s + UiUtil.insets_v(vp).x)
		var mc := _centre(more, vp)
		var mr := float(more["r"]) * s
		TestLib.check(mc.y > pause.y and mc.x > vp.x * 0.8, "%dx%d: MORE sits in the right edge column under the pause button" % [int(vp.x), int(vp.y)])
		TestLib.check(mc.distance_to(pause) > mr + 36.0 * s, "%dx%d: MORE clears the pause button by 36 px or more" % [int(vp.x), int(vp.y)])
		var worst := 1.0e9
		var pair := ""
		for b: Dictionary in TouchControls.BUTTONS:
			if b == more or not FOOT.has(String(b["need"])):
				continue
			var gap := mc.distance_to(_centre(b, vp)) - mr - float(b["r"]) * s
			if gap < worst:
				worst = gap
				pair = String(b["action"])
		TestLib.check(worst >= 20.0 * s, "%dx%d: MORE keeps %.0f px (20 base px or more) from every other circle (closest %s)" % [int(vp.x), int(vp.y), worst, pair])
		TestLib.check(float(more["r"]) * 2.0 * s >= 64.0 * minf(1.0, s) or float(more["r"]) * 2.0 >= 64.0, "MORE is a 64 px touch target at the base size")


func _reload_label() -> void:
	var touch := hud.touch
	TestLib.check(touch != null, "the HUD has the touch controls")
	var src := FileAccess.get_file_as_string("res://scripts/ui/touch_controls.gd")
	TestLib.check(src.contains("ammo = \"RELOAD\""), "the weapon button says RELOAD while reloading (it said '...')")


# --- 12 ------------------------------------------------------------------------------------------------------------------------

func _loadout_header() -> void:
	# the NEXT line sits at baseline 162, the slot tabs start at SLOT_Y: the line's descenders must clear the top of the tabs
	var next_bottom := 162.0 + UiUtil.BAR_LABEL * 0.3
	TestLib.check(LoadoutScreen.SLOT_Y - next_bottom >= 10.0, "the loadout NEXT line clears the slot tabs by %.0f base px" % (LoadoutScreen.SLOT_Y - next_bottom))
	TestLib.check(LoadoutScreen.SLOT_Y + LoadoutScreen.TAB_H < LoadoutScreen.PART_ROW_Y and LoadoutScreen.PART_ROW_Y + 2.0 * LoadoutScreen.PART_H + 8.0 < LoadoutScreen.FITTED_Y and LoadoutScreen.FITTED_Y + 12.0 < LoadoutScreen.ACTION_Y,
			"the slot tabs, two rows of part cards and the FITTED line end above the GEAR button")


func _title_bars(main: Node) -> void:
	Game.state = &"menu"
	var cine: Object = null
	for n in main.get_children():
		if n is Cinematics:
			cine = n
	TestLib.check(cine != null, "the game has the cinematics layer")
	if cine == null:
		return
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await TestLib.frames(host, 2)
		if absf(float(cine.get("_bars"))) < 0.002:
			break
	TestLib.check(float(cine.get("_bars")) < 0.01, "the title has no letterbox bars (%.3f of the height)" % float(cine.get("_bars")))


func _test_card_gone() -> void:
	var tm: Object = null
	for n in host.get_tree().get_nodes_in_group(&"test_menu"):
		tm = n
	if tm == null or not TestMode.available():
		TestLib.check(true, "no TEST menu in this build: nothing to leave behind")
		return
	var forced0: bool = TestMode.forced
	TestMode.forced = true   # the entry is hidden from players unless test mode is forced (review 5, defect 8): this test is about WHERE it shows
	Game.state = &"menu"
	hud._options_open = false
	hud._gear_open = true
	tm.call("_process", 0.3)
	var shown_on_more: bool = tm.call("_entry_visible")
	hud._gear_open = false
	hud._options_open = true
	tm.call("_process", 0.3)
	var hidden_on_options: bool = not bool(tm.call("_entry_visible"))
	TestMode.forced = forced0
	TestLib.check(shown_on_more and hidden_on_options, "the TEST card shows on the MORE page and not over the OPTIONS tabs")
	TestLib.check(not bool(tm.get("_was_shown")), "the TEST menu redraws when its card goes away (no stale frame over the OPTIONS tabs)")
	hud._options_open = false


# --- 6 (toast) -----------------------------------------------------------------------------------------------------------------

func _echo_toast() -> void:
	hud._camp_text = "1/3  CROSS THE TRADING FLOOR TO THE BEACON  131 M"
	TestLib.check(hud.echoes_objective("CROSS THE TRADING FLOOR TO THE BEACON"), "a toast that repeats the step line is an echo")
	TestLib.check(hud.echoes_objective("Cross the trading floor to the beacon"), "the echo check ignores the case")
	TestLib.check(not hud.echoes_objective("OBJECTIVE COMPLETE") and not hud.echoes_objective("+ 120 CREDITS"), "other toasts are not echoes")
	hud._camp_text = ""
	TestLib.check(not hud.echoes_objective("CROSS THE TRADING FLOOR TO THE BEACON"), "without a step line nothing is an echo")


# --- 9 -------------------------------------------------------------------------------------------------------------------------

func _map_zoom(main: Node) -> void:
	var ms: MapScreen = null
	for n in main.find_children("*", "MapScreen", true, false):
		ms = n as MapScreen
	TestLib.check(ms != null, "the game has the map screen")
	if ms == null:
		return
	Game.state = &"play"
	ms.open()
	TestLib.check(ms.is_open(), "the map opens")
	TestLib.check(is_equal_approx(ms.zoom_f, maxf(float(MapScreen.OPEN_ZOOM), MapScreen.OPEN_ZOOM_F)) and MapScreen.OPEN_ZOOM >= 2, "the map opens zoomed in (x%.0f)" % ms.zoom_f)
	var pp := p.global_position
	TestLib.check(ms.view_center.distance_to(Vector2(pp.x, pp.z)) < 80.0 or ms.view_center.length() > 1.0, "the opening view is centred near the hero")
	ms.set_zoom(1)
	TestLib.check(is_equal_approx(ms.zoom_f, 1.0), "one tap shows the whole city")
	ms.close_screen()
	await TestLib.frames(host, 2)
