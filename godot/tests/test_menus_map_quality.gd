extends RefCounted
## Menus and map quality (real scene, main.tscn), owner round 3 ("menu not properly rendered, too clumsy; map needs to be much better").
## (1) LAYOUT SCAN of every menu screen (title, MORE, options x2, pause, hero tabs, loadout, gear, suit, safehouse, missions, heists, achievements, arena, dead): at 844x390 and at
##     2400x1080 aspect (the real phone) every queued text lies on screen, is not wider than the box it was given, is at least BODY_MIN base px (22 px at 1080p), overlaps no other
##     text and does not straddle a button edge; every button is on screen, >= 64 base px high and overlaps no other button.
## (2) MAP: layout scan of its controls (touch targets, no overlap, on screen), roads + districts + markers + route on the drawn map, GPS route along the road grid, pinch zoom,
##     fog that reveals fast, player heading, minimap route clip. Waits on counters and state, never on frame counts. Run: tools/test.sh tests/test_menus_map_quality.gd

const SCREENS := [
	["title", &"menu", []],
	["title_more", &"menu", [&"menu_gear"]],
	["title_options", &"menu", [&"options"]],
	["title_options2", &"menu", [&"options", &"opt_page"]],
	["pause", &"paused", []],
	["pause_more", &"paused", [&"menu_gear"]],
	["hero_upgrades", &"paused", [&"menu_gear", &"hero_open"]],
	["hero_weapons", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_weapons"]],
	["hero_skills", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_skills"]],
	["hero_craft", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_craft"]],
	["loadout", &"paused", [&"loadout"]],
	["gear", &"paused", [&"loadout", &"loadout_gear"]],
	["options", &"paused", [&"options"]],
	["options2", &"paused", [&"options", &"opt_page"]],
	["look", &"paused", [&"menu_gear", &"look_open"]],
	["safehouse", &"paused", [&"menu_gear", &"sh_open"]],
	["missions", &"paused", [&"menu_gear", &"side_open"]],
	["heists", &"paused", [&"menu_gear", &"heist_open"]],
	["achievements", &"paused", [&"menu_gear", &"ach"]],
	["arena", &"paused", [&"menu_gear", &"arena_open"]],
	["dead", &"dead", []],
]

var host: Node
var main: Node
var hud: Hud


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _scan(name: String, state: StringName, chain: Array, size: Vector2i) -> void:
	Game.state = &"play"
	Game.state = state
	hud._on_state(state)
	hud.screen_age = 5.0
	if Game.progress != null:
		Game.progress.credits = 700
	hud._layout_key = ""
	hud._ensure_layout()
	for id: StringName in chain:
		hud.press_button(id)
		hud._layout_key = ""
		hud._ensure_layout()
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
	for e0: Dictionary in hud.scan_log:                # the screen may have drawn more than once while we waited: one entry per text and place
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
		if float(e["size"]) < hud.BODY_MIN * s - 1.0:
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
		if br.size.y < 63.9 * s and not _small_ok(String(b["id"])):
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


func _small_ok(id: String) -> bool:
	return false


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
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1200, 540), Vector2i(1280, 720)]:        # 1200 x 540 is the 2400 x 1080 phone at half size: the same aspect, the same base px layout
		win.size = size
		await frames(4)
		for sc: Array in SCREENS:
			await _scan(String(sc[0]), sc[1], sc[2], size)
	win.size = old
	Game.state = &"play"
	await frames(2)
	await _map_tests()
	hud.touch.controls_on = false


func _map_tests() -> void:
	_route_unit()
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	if ms == null:
		TestLib.check(false, "the map screen exists")
		return
	var prog := Game.progress as Progress
	var win := host.get_window()
	var old := win.size
	var pp := Game.player.global_position
	# fog: a walk reveals a wide area at once
	ms._seen = PackedByteArray()
	ms._seen.resize(MapScreen.CELLS * MapScreen.CELLS)
	ms.discover(Vector3(-300.0, 0.0, 200.0))
	TestLib.check(ms.discovered_count() >= 40, "walking charts a wide area at once (%d cells)" % ms.discovered_count())
	ms.discover(pp)
	# danger zones
	if prog != null:
		Factions.add_rep(prog, Factions.primary(Districts_MARKET), -60.0)
		var dz := ms.danger_zones()
		var has_dist := false
		for z: Dictionary in dz:
			has_dist = has_dist or z["kind"] == &"district"
		TestLib.check(has_dist, "a district ruled by a camp hostile to you is a danger zone")
		Factions.add_rep(prog, Factions.primary(Districts_MARKET), 60.0)
	var heat0 := Game.heat
	Game.heat = 0.6
	var has_search := false
	for z: Dictionary in ms.danger_zones():
		has_search = has_search or z["kind"] == &"search"
	TestLib.check(has_search, "being wanted draws the search area")
	Game.heat = heat0
	# markers: several kinds exist in the world
	var kinds := {}
	for mk: Dictionary in ms.collect_markers():
		kinds[mk["kind"]] = true
	TestLib.check(kinds.size() >= 4, "the map has markers of at least four kinds (%s)" % str(kinds.keys()))
	for k in MapScreen.KINDS:
		TestLib.check(MapIcons.KINDS.has(k), "an icon exists for %s" % k)
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1200, 540)]:
		win.size = size
		await frames(3)
		Game.state = &"play"
		ms.set_waypoint(Vector3(pp.x + 250.0, 0.0, pp.z - 180.0))
		ms.open()
		ms.set_zoom(1)                                    # the map now opens at x2 on the hero: the whole-city checks below look at the overview
		ms.scan_on = true
		ms._map.queue_redraw()
		for i in 60:
			await frames(1)
			if bool(ms.drawn.get("route", false)):
				break
		var tag := "map @%dx%d" % [size.x, size.y]
		var d := ms.drawn
		TestLib.check(int(d["roads"]) >= 34, "%s: the road grid is drawn (%d road bars)" % [tag, d["roads"]])
		TestLib.check(int(d["lots"]) > 100, "%s: building footprints are drawn (%d)" % [tag, d["lots"]])
		TestLib.check(int(d["labels"]) >= 4, "%s: district names are drawn (%d)" % [tag, d["labels"]])
		TestLib.check(bool(d["you"]), "%s: the player arrow is drawn" % tag)
		TestLib.check(bool(d["route"]) and ms.route_points().size() >= 3, "%s: the GPS route is drawn along the roads (%d points)" % [tag, ms.route_points().size()])
		_scan_map_controls(ms, tag)
		# labels the map drew: on screen, none over another
		var bad: Array[String] = []
		var vpr := Rect2(Vector2.ZERO, ms._map.size).grow(2.0)
		for i in ms.scan_log.size():
			var a: Rect2 = ms.scan_log[i]["rect"]
			if not vpr.encloses(a) and String(ms.scan_log[i]["text"]) != "UNCHARTED":
				bad.append("label off screen '%s'" % ms.scan_log[i]["text"])
			for j in range(i + 1, ms.scan_log.size()):
				var b: Rect2 = ms.scan_log[j]["rect"]
				var inter := a.intersection(b)
				if inter.has_area() and inter.get_area() > 0.2 * minf(a.get_area(), b.get_area()):
					bad.append("labels overlap '%s' / '%s'" % [ms.scan_log[i]["text"], ms.scan_log[j]["text"]])
		TestLib.check(bad.is_empty(), "%s: map labels clean: %s" % [tag, "; ".join(bad.slice(0, 5))])
		# pinch zoom with two fingers, then pan
		ms.set_zoom(1)
		var c := ms._map.size * 0.5
		var t0 := InputEventScreenTouch.new()
		t0.index = 0
		t0.position = c + Vector2(-40, 0)
		t0.pressed = true
		ms._on_map_input(t0)
		var t1 := InputEventScreenTouch.new()
		t1.index = 1
		t1.position = c + Vector2(40, 0)
		t1.pressed = true
		ms._on_map_input(t1)
		for step in 8:
			var d0 := InputEventScreenDrag.new()
			d0.index = 0
			d0.position = c + Vector2(-40.0 - 20.0 * (step + 1), 0)
			ms._on_map_input(d0)
			var d1 := InputEventScreenDrag.new()
			d1.index = 1
			d1.position = c + Vector2(40.0 + 20.0 * (step + 1), 0)
			ms._on_map_input(d1)
		TestLib.check(ms.zoom_f > 2.0, "%s: pinching out zooms in (%.2f)" % [tag, ms.zoom_f])
		var t0u := InputEventScreenTouch.new()
		t0u.index = 0
		t0u.pressed = false
		ms._on_map_input(t0u)
		var t1u := InputEventScreenTouch.new()
		t1u.index = 1
		t1u.pressed = false
		ms._on_map_input(t1u)
		TestLib.check(not ms.has_waypoint() == false, "%s: a pinch is not a tap (the waypoint stays)" % tag)
		var zb := ms.zoom_f
		ms.zoom_by(0.5, c)
		TestLib.check(ms.zoom_f < zb and ms.zoom_f >= 1.0, "%s: pinching in zooms out, never below the whole city" % tag)
		ms.zoom_by(100.0, c)
		TestLib.check(is_equal_approx(ms.zoom_f, MapScreen.ZOOM_MAX), "%s: the zoom stops at the maximum" % tag)
		ms.set_zoom(1)
		# the minimap draws the same objective as a line along the roads
		ms.scan_on = false
		ms.close_screen()
		await frames(2)
		var mm := hud.minimap
		var gd := 0
		for i in 40:
			mm.queue_redraw()
			await frames(1)
			gd = mm.gps_drawn
			if gd > 0:
				break
		TestLib.check(gd > 0, "%s: the minimap draws the objective route (%d segments)" % [tag, gd])
	win.size = old
	ms.clear_waypoint()
	Game.state = &"play"
	await frames(2)


const Districts_MARKET := 0


## Controls of the map: every button on screen, >= 64 base px high, none overlapping, texts fit their buttons; the two labels clear the buttons.
func _scan_map_controls(ms: MapScreen, tag: String) -> void:
	var vp := ms.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var screen := Rect2(Vector2.ZERO, vp).grow(2.0)
	var bad: Array[String] = []
	var btns := ms._root.find_children("*", "Button", true, false)
	var rects: Array[Rect2] = []
	btns = btns.filter(func(n: Node) -> bool: return (n as Button).visible)            # a legend row with nothing to list is hidden (MapScreen._chip_shown)
	for b in btns:
		var bt := b as Button
		var r := bt.get_global_rect()
		rects.append(r)
		if not screen.encloses(r):
			bad.append("button off screen %s %s" % [bt.name, r])
		if r.size.y < 63.9 * s:
			bad.append("button under 64 %s" % bt.name)
		var fs := bt.get_theme_font_size("font_size")
		if fs < 14.9 * s:
			bad.append("button text too small %s" % bt.name)
		var tw := bt.get_theme_font("font").get_string_size(bt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var margin := 62.0 if bt.name.begins_with("F_") else 16.0
		if tw > r.size.x - margin:
			bad.append("text wider than %s" % bt.name)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				bad.append("buttons overlap %s / %s" % [btns[i].name, btns[j].name])
	TestLib.check(bad.is_empty(), "%s: controls clean (%d buttons): %s" % [tag, btns.size(), "; ".join(bad.slice(0, 5))])


func _route_unit() -> void:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 91
	var worst := ""
	for n in 60:
		var a := Vector3(rnd.randf_range(-620.0, 620.0), 0.0, rnd.randf_range(-620.0, 620.0))
		var b := Vector3(rnd.randf_range(-620.0, 620.0), 0.0, rnd.randf_range(-620.0, 620.0))
		var r := MapRoute.route(a, b)
		if r.size() < 2 or Vector2(r[0].x - a.x, r[0].z - a.z).length() > 0.3 or Vector2(r[r.size() - 1].x - b.x, r[r.size() - 1].z - b.z).length() > 0.3:
			worst = "ends %s -> %s" % [a, b]
			break
		# every inner leg (between the snap points) runs along a road centre line
		for i in range(1, r.size() - 2):
			var p: Vector3 = r[i]
			var q: Vector3 = r[i + 1]
			var vertical := absf(p.x - q.x) < 0.3
			var horizontal := absf(p.z - q.z) < 0.3
			var on_road := (vertical and absf(CityLayout.road_offset(p.x)) < 0.3) or (horizontal and absf(CityLayout.road_offset(p.z)) < 0.3)
			if not on_road:
				worst = "leg off the roads %s -> %s (from %s to %s)" % [p, q, a, b]
		var man := absf(a.x - b.x) + absf(a.z - b.z)
		if MapRoute.length(r) > man + 4.0 * CityLayout.PITCH:
			worst = "route much longer than the Manhattan distance %s -> %s" % [a, b]
	TestLib.check(worst == "", "the GPS route runs along the road grid and is short (%s)" % worst)
	var r2 := MapRoute.route(Vector3(-320.0, 0.0, -100.0), Vector3(-320.0, 0.0, 300.0))
	TestLib.check(r2.size() <= 4 and absf(MapRoute.length(r2) - 400.0) < 1.0, "two points on one road: a straight line (%d points, %.0f m)" % [r2.size(), MapRoute.length(r2)])
	# clip to the rim
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(300, 0)])
	var cl := MapRoute.clip_to_circle(pts, Vector2.ZERO, 100.0)
	TestLib.check(cl.size() == 1 and cl[0].size() == 2 and absf(cl[0][1].x - 100.0) < 0.01, "a line leaving the circle is cut at the rim")
	var chord := MapRoute.clip_to_circle(PackedVector2Array([Vector2(-300, 50), Vector2(300, 50)]), Vector2.ZERO, 100.0)
	TestLib.check(chord.size() == 1 and absf(chord[0][0].x + sqrt(100.0 * 100.0 - 50.0 * 50.0)) < 0.01, "a line crossing the circle keeps only its chord")
	var out := MapRoute.clip_to_circle(PackedVector2Array([Vector2(300, 300), Vector2(400, 300)]), Vector2.ZERO, 100.0)
	TestLib.check(out.is_empty(), "a line outside the circle is dropped")
	var enter := MapRoute.clip_to_circle(PackedVector2Array([Vector2(300, 0), Vector2(0, 0), Vector2(0, 60)]), Vector2.ZERO, 100.0)
	TestLib.check(enter.size() == 1 and enter[0].size() == 3 and absf(enter[0][0].x - 100.0) < 0.01, "a line entering the circle starts at the rim")
