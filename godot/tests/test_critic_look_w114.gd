extends RefCounted
## Wave 114 critic (LOOK) regression tests of the weapon SCREENS and the weapon in the hand, in the real Hud of main.tscn:
##   * the card tabs sit side by side (a weapon without parts left a hole between STATS and AMMO)
##   * the part card's numbers never run into their labels ("AIM SPREAD0.24 > 0.12"), at 844x390 and 1280x720
##   * the bar labels leave room before their bars (BLAST RADIUS touched its bar)
##   * the weapon wheel's scrim hides the objective line under its title box
##   * the riot shield's picture shows its face (it was an edge-on sliver) and the pictures are not older than the models
##   * an enemy's weapon is drawn with the same class-based scale as the hero's, the hands keep their hold distance (a pistol drawn 2x does not pull the arms off the body)
##   tools/test.sh tests/test_critic_look_w114.gd

var host: Node
var hud: Hud
var tc: TouchControls


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _open(chain: Array) -> void:
	if tc != null and tc.wheel.is_open:
		tc.wheel.close()
	Game.state = &"play"
	Game.state = &"paused"
	hud._on_state(&"paused")
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


func _btn(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


## The texts the screen draws now: [{text, rect, over, size}] without duplicates (a real draw, waited on by the scan log).
func _texts() -> Array[Dictionary]:
	hud.scan_log.clear()
	hud.scan_text = true
	hud._screen.queue_redraw()
	for i in 90:
		await frames(1)
		if not hud.scan_log.is_empty():
			break
	await frames(1)
	hud.scan_text = false
	var out: Array[Dictionary] = []
	var seen := {}
	for e: Dictionary in hud.scan_log:
		var key := "%s|%s" % [e["text"], e["rect"]]
		if not seen.has(key):
			seen[key] = true
			out.append(e)
	return out


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	_data()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	tc = hud.touch
	var win := host.get_window()
	var win_old := win.size
	WeaponDefs.hero_mode = true
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		win.size = size
		await frames(3)
		await _tabs(size)
		await _part_card(size)
	win.size = Vector2i(1280, 720)
	await frames(3)
	_wheel_scrim()
	win.size = win_old
	await frames(2)
	_hand()
	if tc != null and tc.wheel.is_open:
		tc.wheel.close()
	Game.state = &"play"
	WeaponDefs.hero_mode = false


func _data() -> void:
	TestLib.check(WeaponPics.stale_ids().is_empty(), "the weapon pictures are not older than the models (stale: %s)" % str(WeaponPics.stale_ids()))
	var view: Dictionary = (load("res://tools/icons/weapon_pics.gd") as GDScript).get_script_constant_map()["VIEW_BY_ID"]
	TestLib.check(view.has(&"m_shield") and (view[&"m_shield"] as Vector2).x < 60.0, "the picture renderer shows the riot shield face on (%s), not at the 3/4 view" % str(view.get(&"m_shield")))
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/icons/wp/manifest.json"))
	var t: Array = man["weapons"]["m_shield"]["t"]
	TestLib.check(float(t[3]) / maxf(float(t[4]), 1.0) >= 0.25, "the riot shield's thumbnail is not an edge-on sliver (%dx%d px)" % [int(t[3]), int(t[4])])


func _tabs(size: Vector2i) -> void:
	var tag := "@%dx%d" % [size.x, size.y]
	_open([&"loadout", &"ars_filter_all", &"wheel_la_rocket"])
	var st := _btn(&"ars_tab_stats")
	var am := _btn(&"ars_tab_ammo")
	TestLib.check(not st.is_empty() and not am.is_empty() and _btn(&"ars_tab_parts").is_empty(), "%s: a rocket launcher has STATS and AMMO tabs and no PARTS tab" % tag)
	if st.is_empty() or am.is_empty():
		return
	var gap: float = (am["rect"] as Rect2).position.x - (st["rect"] as Rect2).end.x
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	TestLib.check(gap >= 0.0 and gap < 20.0 * s, "%s: the two tabs sit side by side (gap %.0f px = %.0f base px)" % [tag, gap, gap / s])
	_open([&"loadout", &"ars_filter_all", &"wheel_a_pillar"])
	var order: Array[float] = []
	for t in [&"ars_tab_stats", &"ars_tab_parts", &"ars_tab_ammo"]:
		var b := _btn(t)
		if not b.is_empty():
			order.append((b["rect"] as Rect2).position.x)
	TestLib.check(order.size() == 3 and order[0] < order[1] and order[1] < order[2], "%s: an owned rifle has STATS, PARTS and AMMO in that order" % tag)


func _part_card(size: Vector2i) -> void:
	var tag := "@%dx%d" % [size.x, size.y]
	Attachments.reset()
	for part: StringName in [&"reddot", &"scope", &"suppressor", &"foregrip", &"laser"]:
		Attachments.give(part)
	_open([&"loadout", &"ars_filter_all", &"wheel_a_pillar", &"ars_tab_parts", &"ars_part_scope"])
	var log := await _texts()
	var label := {}
	for e: Dictionary in log:
		if String(e["text"]) == "AIM SPREAD":
			label = e
	TestLib.check(not label.is_empty(), "%s: the part card names AIM SPREAD" % tag)
	if not label.is_empty():
		var lr: Rect2 = label["rect"]
		var row_values: Array[Rect2] = []
		for e: Dictionary in log:
			var r: Rect2 = e["rect"]
			if String(e["text"]).contains(" > ") and absf(r.get_center().y - lr.get_center().y) < lr.size.y * 0.6:
				row_values.append(r)
		TestLib.check(not row_values.is_empty(), "%s: AIM SPREAD has its before > after numbers on the same row" % tag)
		for r in row_values:
			TestLib.check(lr.end.x <= r.position.x + 0.5, "%s: the label ends (%.0f) before its numbers start (%.0f)" % [tag, lr.end.x, r.position.x])
	var bad: Array[String] = []
	for i in log.size():
		for j in range(i + 1, log.size()):
			var a: Rect2 = log[i]["rect"]
			var b: Rect2 = log[j]["rect"]
			var inter := a.intersection(b)
			if inter.has_area() and inter.get_area() > 0.02 * minf(a.get_area(), b.get_area()):
				bad.append("'%s' / '%s'" % [log[i]["text"], log[j]["text"]])
	TestLib.check(bad.is_empty(), "%s: no two texts of the part screen overlap: %s" % [tag, "; ".join(bad.slice(0, 5))])
	# the bar labels: the longest (BLAST RADIUS) ends before its bar
	_open([&"loadout", &"ars_filter_all", &"wheel_la_rocket"])
	var log2 := await _texts()
	for e: Dictionary in log2:
		if String(e["text"]) == "BLAST RADIUS":
			var r: Rect2 = e["rect"]
			var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
			TestLib.check(not bool(e["over"]), "%s: BLAST RADIUS fits its label column" % tag)
			var hit := false
			for e2: Dictionary in log2:
				if String(e2["text"]).ends_with(" M") and absf((e2["rect"] as Rect2).get_center().y - r.get_center().y) < r.size.y:
					hit = true
					TestLib.check(r.end.x + 4.0 * s <= (e2["rect"] as Rect2).position.x, "%s: the BLAST RADIUS label leaves 4 base px or more before its value" % tag)
			TestLib.check(hit, "%s: BLAST RADIUS has a value" % tag)


func _wheel_scrim() -> void:
	if tc == null:
		return
	Game.state = &"play"
	hud._on_state(&"play")
	tc.controls_on = true
	tc.wheel.close()
	tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	TestLib.check(tc.wheel.is_open and tc.wheel.kind == &"weapon", "the weapon wheel opens")
	TestLib.check(hud.objective_text() != "", "the objective line exists behind the wheel ('%s')" % hud.objective_text())
	TestLib.check(TouchControls.SCRIM_WEAPON >= 0.8 and TouchControls.SCRIM_WEAPON > TouchControls.SCRIM, "the weapon wheel's scrim (%.2f) hides the line its title box cuts in half (the ability wheel keeps %.2f)" % [TouchControls.SCRIM_WEAPON, TouchControls.SCRIM])
	tc.wheel.close()


func _hand() -> void:
	var p := Game.player as Player
	if p == null:
		return
	for id: StringName in [&"pistol", &"flux", &"carbine", &"rocket", &"bw_recurve", &"m_shield"]:
		var sc := WeaponModels.look_scale(id)
		var esc := FoeArms.scale_of(id)
		TestLib.check(esc.is_equal_approx(sc * (Vector3(1.1, 1.1, 1.05) if FoeArms.HEAVY.has(id) else Vector3.ONE)), "%s: an enemy's weapon is drawn with the hero's class-based scale (%s)" % [id, str(esc)])
	var pistol := WeaponModels.look_scale(&"pistol")
	var carbine := WeaponModels.look_scale(&"carbine")
	var bow := WeaponModels.look_scale(&"bw_recurve")
	TestLib.check(pistol.z > carbine.z + 0.4 and pistol.z >= 1.6, "a pistol is drawn longer by far than a carbine (z %.2f against %.2f): the shorter the weapon the bigger" % [pistol.z, carbine.z])
	TestLib.check(carbine.x >= 1.3 and carbine.z >= 1.05, "a carbine is still drawn thicker and longer than true size (%s)" % str(carbine))
	TestLib.check(bow.x <= 1.2 and bow.y <= 1.2, "a bow is not scaled up like its short length says: it is 0.7 m across already (%s)" % str(bow))
	# the hands keep their hold distance: a weapon drawn bigger never moves the hands further out than the arms reach
	var worst := 0.0
	var worst_id := &""
	for id: StringName in WeaponDefs.all_ids():
		var g := WeaponModels.grip_offsets(id, WeaponModels.look_scale(id))
		var far := maxf(g[0].length(), g[1].length())
		if far > worst:
			worst = far
			worst_id = id
	TestLib.check(worst < 0.8, "no weapon pulls a hand further than 0.8 m from the carbine's grips (worst %s %.2f m)" % [worst_id, worst])
	var shift_ok := true
	for id: StringName in WeaponDefs.all_ids():
		var sh := WeaponModels.muzzle_shift(id, WeaponModels.look_scale(id))
		shift_ok = shift_ok and absf(sh) < 0.7
	TestLib.check(shift_ok, "the muzzle node of no weapon moves more than 0.7 m from the carbine's (the scythe, 1.5 m long, moves 0.62)")
