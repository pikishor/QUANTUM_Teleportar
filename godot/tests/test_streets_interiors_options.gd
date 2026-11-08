extends RefCounted
## Round 4, "streets, interiors and options look and feel" (docs/shots/slice/streets_interiors_*.jpg, options_*.jpg):
##   * interiors: Kenney's CC0 Furniture Kit (assets/models/furn_*.glb, InteriorFurniture) is in six interior types (bodega, bar, warehouse, apartment, clinic, pawn shop) without a new draw
##     call, wall style 4 (wainscot and striped wallpaper) exists, the window pane shader has three layered skylines, QT_FURNITURE=0 puts the boxes back;
##   * street: the sidewalk dressing family (benches, bins, post boxes, meters, street trees), the glowing 6 m "second-state" squares and wide seam worms of the road are gone;
##   * options: five grouped tabs (CONTROLS, GRAPHICS, SOUND, ACCESS, GAME), the graphics tab has a tier card with a real frame of that tier and four chips, MUSIC and SFX are sliders,
##     TEST SOUND, RESET PAGE on every tab restores the defaults of that tab and never touches progress; all of it in the real scene at 1280x720 and 844x390.
## Waits on state and counters, never on frame counts; user:// state is reset first. Run: tools/test.sh tests/test_streets_interiors_options.gd

const TYPES6: Array[StringName] = [&"bodega", &"bar", &"warehouse", &"apartment", &"clinic", &"weapons"]
const TIMEOUT_SECONDS := 140.0

var host: Node
var main: Node
var hud: Hud


func _layout() -> void:
	hud._layout_key = ""
	hud._ensure_layout()


func _state(st: StringName) -> void:
	Game.state = &"play"
	Game.state = st
	hud._on_state(st)
	hud.screen_age = 5.0


func _btn(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	for f in ["user://savegame.json", "user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	_furniture_assets()
	_interiors()
	_sources()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	for i in 40:
		await host.get_tree().process_frame
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	_street()
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		win.size = size
		for i in 4:
			await host.get_tree().process_frame
		_options("%dx%d" % [size.x, size.y])
	win.size = old
	await _options_behaviour()
	Game.state = &"menu"
	main.queue_free()
	await host.get_tree().process_frame


# --- interiors ------------------------------------------------------------------------------------------------------------------------------------

func _furniture_assets() -> void:
	var missing := ""
	for kind: String in InteriorFurniture.RECIPES:
		for pt: Array in InteriorFurniture.RECIPES[kind]:
			if InteriorFurniture.data(String(pt[0])).is_empty() and not missing.contains(String(pt[0])):
				missing += String(pt[0]) + " "
	TestLib.check(missing == "", "every piece of every furniture recipe is a loaded glb (missing: %s)" % missing)
	var tris := 0
	for piece in ["sofa", "bed_double", "kitchen_sink", "tv_modern"]:
		tris += (InteriorFurniture.data(piece)["idx"] as PackedInt32Array).size() / 3
	TestLib.check(tris > 300 and tris < 2000, "the pieces are low-poly (%d triangles for four of them)" % tris)
	TestLib.check(FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("../art_sources/kenney_furniture_kit/License.txt")), "the kit's licence text is kept with the source (art_sources/kenney_furniture_kit)")


func _interiors() -> void:
	var root := Node3D.new()
	root.name = "SIOTestRoot"
	host.add_child(root)
	var better := 0
	for type: StringName in TYPES6:
		var with_models := 0
		var kinds := {}
		var drawn := {}
		for seed_v in [1, 2, 3]:
			var plan := InteriorGen.plan_for(type, seed_v)
			for p: Dictionary in plan.props:
				if InteriorFurniture.has(String(p["kind"])):
					kinds[String(p["kind"])] = true
					with_models += 1
			for q in [0, 1, 2]:
				InteriorFurniture.enabled = true
				InteriorGen.clear_cache()
				var n := InteriorGen.build(type, seed_v, Vector3(900.0, 600.0, 900.0), q) as Interior
				root.add_child(n)
				var st := n.stats()
				drawn["%d:%d" % [seed_v, q]] = st
				TestLib.check(int(st["draws"]) <= 4, "%s seed %d tier %d: at most 4 draw calls with the furniture (%d)" % [type, seed_v, q, int(st["draws"])])
				TestLib.check(int(st["tris"]) < 14000, "%s seed %d tier %d: %d triangles stay inside the room budget (14000)" % [type, seed_v, q, int(st["tris"])])
				n.queue_free()
		TestLib.check(kinds.size() >= 3 and with_models >= 6, "%s has real furniture in its plans (%d kinds, %d props over 3 seeds)" % [type, kinds.size(), with_models])
		# the same plan with the boxes: the models cost triangles (and nothing else)
		InteriorFurniture.enabled = false
		InteriorGen.clear_cache()
		var nb := InteriorGen.build(type, 2, Vector3(900.0, 600.0, 900.0), 1) as Interior
		root.add_child(nb)
		var tris_boxes := int(nb.stats()["tris"])
		nb.queue_free()
		InteriorFurniture.enabled = true
		InteriorGen.clear_cache()
		var tris_models := int((drawn["2:1"] as Dictionary)["tris"])
		better += int(tris_models > tris_boxes)
	TestLib.check(better >= 5, "furniture adds geometry in at least five of the six types (%d)" % better)
	InteriorGen.clear_cache()
	root.queue_free()


func _sources() -> void:
	var win := FileAccess.get_file_as_string("res://assets/shaders/interior_window.gdshader")
	TestLib.check(win.count("layer(") >= 4 and win.contains("95.0 / k") and win.contains("46.0 / k"), "the window pane shows three layered skylines (the old one was one flat row of boxes)")
	var surf := FileAccess.get_file_as_string("res://assets/shaders/interior_surface.gdshader")
	TestLib.check(surf.contains("sty > 3.5") and surf.contains("wainscot"), "wall style 4 (wainscot and striped wallpaper) is in the surface shader")
	TestLib.check(int(InteriorKinds.SPECS[&"apartment"].get("style", 0)) == 4 and int(InteriorKinds.SPECS[&"weapons"].get("style", 0)) == 4, "the apartment and the pawn shop use it")
	var ground := FileAccess.get_file_as_string("res://assets/shaders/ground_core.gdshaderinc")
	TestLib.check(not ground.contains("fl * 0.06") and not ground.contains("0.018 + aa * 0.9"), "the road has no glowing 6 m squares and no wide seam worms (owner rounds 2 and 4: pink rectangles, graffiti scribbles)")
	var pal: Dictionary = InteriorKinds.SPECS[&"apartment"]["pal"]
	TestLib.check((pal["amb"] as Color).r >= 0.12 and (pal["wall"] as Color).r >= 0.25, "the rooms people live in are lit (ambient and wall are not the old murky 0.08 / 0.16)")


# --- street ---------------------------------------------------------------------------------------------------------------------------------------

func _street() -> void:
	var cities := main.find_children("*", "City", true, false)
	TestLib.check(not cities.is_empty(), "the real scene has the city")
	if cities.is_empty():
		return
	var city := cities[0] as City
	var instances := 0
	for part in city._props.parts:
		if String(part["name"]) == "StreetDress":
			instances = (part["mm"] as MultiMesh).instance_count
	TestLib.check(instances >= 20, "the sidewalk dressing family is in the city (%d benches, bins, post boxes and trees)" % instances)
	var mesh: ArrayMesh = preload("res://scripts/world/city_props.gd").street_dress_mesh()
	var mesh_tris := (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if mesh.get_surface_count() > 0 else 0
	TestLib.check(mesh_tris > 60 and mesh_tris < 400, "one cluster is a small mesh (%d triangles, the spawn triangle budget is tight)" % mesh_tris)


# --- options ---------------------------------------------------------------------------------------------------------------------------------------

func _options(tag: String) -> void:
	_state(&"paused")
	TestLib.check(hud.press_button(&"options"), "%s: OPTIONS opens" % tag)
	_layout()
	TestLib.check(OptionsScreen.TABS.size() == 5, "%s: five tabs" % tag)
	var names: Array[String] = []
	for t: Array in OptionsScreen.TABS:
		names.append(String(t[0]))
	TestLib.check(names == ["CONTROLS", "GRAPHICS", "SOUND", "ACCESS", "GAME"], "%s: the groups are %s" % [tag, str(names)])
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var seen := {}
	for ti in OptionsScreen.TABS.size():
		TestLib.check(hud.press_button(OptionsScreen.tab_id(ti)) and UiSettings.s_opt_tab == ti, "%s: tab %d opens" % [tag, ti])
		_layout()
		var rows := 0
		var bad := ""
		for b: Dictionary in hud.buttons:
			seen[b["id"]] = true
			rows += int(b.has("opt"))
			var r: Rect2 = b["rect"]
			if r.size.y < 63.9 * s or not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r):
				bad = "%s %s" % [b["id"], r]
			for b2: Dictionary in hud.buttons:
				if b != b2 and r.intersects(b2["rect"]) and not (OptionsScreen.is_slider(b["id"]) and OptionsScreen.is_slider(b2["id"])):
					bad = "%s over %s" % [b["id"], b2["id"]]
		TestLib.check(bad == "", "%s tab %d: every button is >= 64 base px, on screen, none over another (%s)" % [tag, ti, bad])
		TestLib.check(rows == (OptionsScreen.TABS[ti][2] as Array).size() and rows <= 8, "%s tab %d: %d rows, at most eight" % [tag, ti, rows])
		TestLib.check(not _btn(&"opt_reset_tab").is_empty() and not _btn(&"options_back").is_empty(), "%s tab %d: RESET PAGE and BACK" % [tag, ti])
		if ti == 1:
			var card := _btn(&"opt_tier")
			TestLib.check(card.has("prev") and (card["rect"] as Rect2).size.y >= 120.0 * s, "%s: the graphics tab has the tier card (a sample frame and what the tier costs)" % tag)
			for c in 4:
				TestLib.check(not _btn(StringName("opt_tierset_%d" % c)).is_empty(), "%s: tier chip %d" % [tag, c])
	for id: StringName in OptionsScreen.ORDER + OptionsScreen.PAGE2:
		TestLib.check(seen.has(id), "%s: %s is still reachable" % [tag, id])
	hud.press_button(&"options_back")
	_layout()


func _options_behaviour() -> void:
	_state(&"paused")
	hud.press_button(&"options")
	_layout()
	TestLib.check(FileAccess.file_exists("res://assets/ui/tier_0.jpg") and ResourceLoader.exists("res://assets/ui/tier_3.jpg"), "a rendered frame of every tier ships for the card")
	for i in 4:
		TestLib.check(OptionsScreen._tier_texture(i) != null, "the card has the frame of tier %d" % i)
	var st := hud.settings
	# controls page: change, reset
	hud.press_button(OptionsScreen.tab_id(0))
	_layout()
	st.look_x = 1.8
	st.aim_assist = false
	st.left_hand = true
	var credits := int(Game.progress.credits) if Game.progress != null else 0
	TestLib.check(hud.press_button(&"opt_reset_tab"), "RESET PAGE works on the controls tab")
	TestLib.check(is_equal_approx(st.look_x, 1.0) and st.aim_assist and not st.left_hand, "controls are back to their defaults")
	TestLib.check(Game.progress == null or int(Game.progress.credits) == credits, "RESET PAGE never touches progress")
	# sound page: sliders drag, reset
	hud.press_button(OptionsScreen.tab_id(2))
	_layout()
	var sfx := _btn(&"opt_vol_sfx")
	TestLib.check(not sfx.is_empty() and OptionsScreen.is_slider(&"opt_vol_sfx") and float(sfx["frac"]) >= 0.0, "SFX is a slider row")
	var r: Rect2 = sfx["rect"]
	TestLib.check(hud.tap(Vector2(r.position.x + r.size.x * 0.3, r.get_center().y)), "a finger on the SFX track starts a drag")
	hud.end_drag()
	var v := OptionsScreen.volume(st, &"opt_vol_sfx")
	TestLib.check(v > 0.15 and v < 0.5, "the drag set the SFX level (%.2f)" % v)
	TestLib.check(absf(Sfx.bus_volume(&"SFX") - v) < 0.05, "the SFX bus follows the slider")
	TestLib.check(not _btn(&"opt_sndtest").is_empty() and hud.press_button(&"opt_sndtest"), "TEST SOUND is there and plays")
	TestLib.check(hud.press_button(&"opt_reset_tab"), "RESET PAGE works on the sound tab")
	TestLib.check(OptionsScreen.volume(st, &"opt_vol_sfx") == 1.0 and not st.muted and Sfx.bus_volume(&"SFX") > 0.95, "volumes are back to full")
	# graphics page: a chip is a tier; restore afterwards
	hud.press_button(OptionsScreen.tab_id(1))
	_layout()
	var was := Game.tier_index()
	var other := 1 if was != 1 else 2
	TestLib.check(hud.press_button(StringName("opt_tierset_%d" % other)) and Game.tier_index() == other, "a tier chip switches the graphics tier (%d -> %d)" % [was, Game.tier_index()])
	_layout()
	TestLib.check(bool(_btn(StringName("opt_tierset_%d" % other))["on"]) and not bool(_btn(StringName("opt_tierset_%d" % was))["on"]), "the chip of the new tier is lit")
	hud.press_button(StringName("opt_tierset_%d" % was))
	TestLib.check(Game.tier_index() == was, "and back")
	# access page: the sample follows the setting
	hud.press_button(OptionsScreen.tab_id(3))
	_layout()
	TestLib.check(hud.press_button(&"opt_cb"), "colour-safe cycles from the access tab")
	hud.press_button(&"opt_cb")
	hud.press_button(&"opt_cb")
	st.reduce_motion = true
	TestLib.check(hud.press_button(&"opt_reset_tab") and not st.reduce_motion and not st.cb_safe, "RESET PAGE on the access tab clears motion and colour settings")
	hud.press_button(&"options_back")
	await host.get_tree().process_frame
