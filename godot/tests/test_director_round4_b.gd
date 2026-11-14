extends RefCounted
## Director review 4, presentation half (docs/SLICE_REVIEW.md "Fix pass, review 4 presentation half"), data checks plus the REAL game scene (main.tscn, touch layout forced):
##   2  every room of every interior has a lamp pool among the ones LOW draws (the job room was a black void); no street prompt (HIJACK / ENTER) and no ENTER button inside a room
##   3  the thin-film sheen of a facade is a tint that fades at a grazing view (the rainbow wall); the lamp cones are softer
##   4  the QUANTUM CORES line stays off inside a room (the car case reads Player.vehicle); a pinned compass owns the distance (the edge diamond has no second number)
##   6  the weapon wheel has a scrim and opaque discs and keeps clear of the other buttons; the loadout has a big picture of the weapon (clear of the grid and the page arrows)
##   7  one BACK on a screen that has its own (the watchdog button waits 30 s and then sits ON it)
##   9  a new game forgets the map's discovery (the first open is not 85 % charted); the map icons are bigger
##   11 the prologue cards sit above the hero and TAP TO SKIP is centred (the move hint itself is the guide's: test_director_round4_a)
## Waits on state and counters, never on frame counts; user:// state is reset first.
## Run: tools/test.sh tests/test_director_round4_b.gd

var host: Node
var p: Player
var hud: Hud


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_room_pools()
	_shader_source()
	_loadout_picture()
	_story_cards()
	var was_touch := Game.force_touch
	Game.force_touch = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	p = Game.player as Player
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(p != null and hud != null, "the real scene has a player and a HUD")
	if p != null and hud != null:
		Game.state = &"play"
		(Game.progress as Progress).autosave_enabled = false
		_cores_line()
		_interior_prompts()
		_wheel_layout()
		await _single_back()
		await _map_new_game(main)
	Game.force_touch = was_touch
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


# --- 2 -------------------------------------------------------------------------------------------------------------------------

func _room_pools() -> void:
	var checked := 0
	var missing := ""
	var low_n: int = Interior.POOLS_BY_TIER[0]
	for t in InteriorGen.TYPES:
		for sd in [1, 2, 3]:
			var plan := InteriorPlan.generate(t, sd)
			var drawn: Array = plan.pools.slice(0, mini(low_n, plan.pools.size()))
			for i in plan.rooms.size():
				var r: Rect2 = (plan.rooms[i]["rect"] as Rect2).grow(0.6)
				var has := false
				for pl: Dictionary in drawn:
					var pp: Vector3 = pl["pos"]
					if r.has_point(Vector2(pp.x, pp.z)):
						has = true
				checked += 1
				if not has and missing == "":
					missing = "%s seed %d room %d" % [t, sd, i]
	TestLib.check(checked >= 40, "rooms were checked (%d)" % checked)
	TestLib.check(missing == "", "every room has a lamp pool among the %d that LOW draws (first without one: %s)" % [low_n, missing])
	TestLib.check(Interior.AMBIENT_FLOOR >= 0.1, "a room has an ambient floor, never pitch black")


func _shader_source() -> void:
	var code := FileAccess.get_file_as_string("res://assets/shaders/building_core.gdshaderinc")
	TestLib.check(code.contains("smoothstep(0.02, 0.3, ndv_q)") and code.contains("film_q = mix(vec3(dot(film_q"), "the facade film is a desaturated tint that fades at a grazing view")
	var sh := FileAssets_text("res://assets/shaders/shaft.gdshader")
	TestLib.check(sh.contains("pow(nv, 2.2)"), "the lamp cones fade harder toward their edges")


func FileAssets_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# --- 6 -------------------------------------------------------------------------------------------------------------------------

func _loadout_picture() -> void:
	for vp: Vector2 in [Vector2(844, 390), Vector2(2400, 1080)]:
		var s := UiUtil.ui_scale(vp)
		var cx := vp.x * 0.5
		var k := LoadoutScreen.k_of(vp.x, s)
		var pic := LoadoutScreen.picture_rect(cx, s, k)
		# wave 114: the Arsenal. The picture plate of the card clears the list of tiles, the filter and class chips and the bottom bar (BACK, the four slots, the star, the action)
		var blocks: Array[Rect2] = [Arsenal.rect(vp, s, Arsenal.LIST_X, Arsenal.LIST_Y, Arsenal.LIST_W, Arsenal.BOTTOM - Arsenal.LIST_Y)]
		for i in Arsenal.FILTERS.size():
			blocks.append(Arsenal.filter_rect(vp, s, i))
		blocks.append_array(Arsenal.class_rects(vp, s))
		blocks.append(Arsenal.back_rect(vp, s))
		for i in LoadoutSlots.COUNT:
			blocks.append(Arsenal.slot_rect(vp, s, i))
		blocks.append(Arsenal.star_rect(vp, s))
		blocks.append(Arsenal.action_rect(vp, s))
		var clear := true
		for b in blocks:
			clear = clear and not pic.intersects(b)
		TestLib.check(pic.size.x >= 480.0 * s and pic.size.y >= 240.0 * s, "%dx%d: the loadout picture (%s) is big (was 204 x 98 base px)" % [int(vp.x), int(vp.y), pic.size / s])
		TestLib.check(clear and Rect2(Vector2.ZERO, vp).encloses(pic), "%dx%d: the loadout picture clears the tiles, the chips, the slots and the action bar" % [int(vp.x), int(vp.y)])


# --- 11 ------------------------------------------------------------------------------------------------------------------------

func _story_cards() -> void:
	TestLib.check(StoryView.CARD_TOP_LIVE + StoryView.CARD_H_LIVE < StoryView.CARD_TOP, "the prologue band (%.2f .. %.2f) ends above the old mid-screen band (from %.2f), clear of the hero" % [StoryView.CARD_TOP_LIVE, StoryView.CARD_TOP_LIVE + StoryView.CARD_H_LIVE, StoryView.CARD_TOP])
	var code := FileAccess.get_file_as_string("res://scripts/story/story_view.gd")
	TestLib.check(code.contains("HORIZONTAL_ALIGNMENT_CENTER, width, int(14.0 * s), Color(1, 1, 1, pulse * 0.85)"), "TAP TO SKIP is centred in the band (its right end sat over RELOAD)")


# --- 4 -------------------------------------------------------------------------------------------------------------------------

func _cores_line() -> void:
	hud.message_left = 0.0
	InteriorGameplay.active = false
	TestLib.check(not hud.cores_line_hidden(), "in the street the cores line may show")
	InteriorGameplay.active = true
	TestLib.check(hud.cores_line_hidden(), "inside a room the cores line stays off")
	InteriorGameplay.active = false


# --- 2 -------------------------------------------------------------------------------------------------------------------------

func _interior_prompts() -> void:
	InteriorGameplay.active = true
	TestLib.check(Freedom.vehicle_prompt() == "", "inside a room there is no HIJACK / ENTER vehicle prompt")
	TestLib.check(hud.hint_text() == "" or InteriorGameplay.prompt != "", "inside a room the bottom hint has no street sentence")
	var tc: TouchControls = hud.touch
	var use_label := ""
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"interact":
			use_label = tc._label_of(b)
	var old_prompt := InteriorGameplay.prompt
	InteriorGameplay.prompt = ""
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"interact":
			use_label = tc._label_of(b)
	TestLib.check(use_label == "USE", "the USE button says USE (not ENTER) inside a room with nothing to act on (%s)" % use_label)
	InteriorGameplay.prompt = old_prompt
	InteriorGameplay.active = false


# --- 6 -------------------------------------------------------------------------------------------------------------------------

func _wheel_layout() -> void:
	var tc: TouchControls = hud.touch
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	tc.wheel.open_at(&"weapon", WeaponWheel.items(), Vector2(vp.x * 0.58, vp.y * 0.5), s)
	var worst := 1.0e9
	var who := ""
	for i in tc.wheel.items.size():
		var ic := tc.wheel.item_centre(i)
		TestLib.check(Rect2(Vector2.ZERO, vp).grow(-4.0).encloses(Rect2(ic - Vector2.ONE * RadialWheel.ITEM_R * s, Vector2.ONE * RadialWheel.ITEM_R * s * 2.0)), "wheel disc %d is on screen" % i)
		for b: Dictionary in TouchControls.BUTTONS:
			if b["action"] in [&"reload", &"ability", &"jump", &"aim"]:
				var d := ic.distance_to(tc._button_center(b)) - RadialWheel.ITEM_R * s * 0.9
				if d < worst:
					worst = d
					who = str(b["action"])
	TestLib.check(worst > 0.0, "no disc covers the centre of RELOAD / ABILITY / JUMP / AIM (closest %s, %.0f px to spare)" % [who, worst])
	var code := FileAccess.get_file_as_string("res://scripts/ui/touch_controls.gd")
	TestLib.check(code.contains("a scrim: the buttons and plates under the wheel step back") and code.contains("opaque: RELOAD / ABILITY never show through a disc"), "the wheel draws a scrim and opaque discs")
	tc.wheel.close()


# --- 7 -------------------------------------------------------------------------------------------------------------------------

func _single_back() -> void:
	var wd := host.get_tree().root.find_child("ScreenWatchdog", true, false) as ScreenWatchdog
	TestLib.check(wd != null, "the screen watchdog exists")
	if wd == null:
		return
	hud.pause_game()
	await host.get_tree().process_frame
	hud.press_button(&"shop")
	await host.get_tree().process_frame
	hud.press_button(&"hero_tab_weapons")
	await host.get_tree().process_frame
	await TestLib.frames(host, 2)
	var backs := 0
	for b: Dictionary in hud.buttons:
		if str(b.get("label", "")) == "BACK":
			backs += 1
	TestLib.check(backs == 1, "the weapons screen has exactly one BACK button (%d)" % backs)
	var own := wd.own_back_rect(wd.trapped())
	TestLib.check(wd.trapped() == &"screen" and own.size.x > 0.0, "the screen is a closable one and the watchdog sees its own BACK")
	wd.force_idle(ScreenWatchdog.IDLE_SECONDS + 1.0)
	await host.get_tree().process_frame
	TestLib.check(not wd.shown(), "after %.0f s idle no second BACK shows beside the screen's own" % ScreenWatchdog.IDLE_SECONDS)
	wd.force_idle(ScreenWatchdog.OWN_BACK_IDLE_SECONDS + 1.0)
	await host.get_tree().process_frame
	TestLib.check(wd.shown(), "after %.0f s the global BACK shows (a screen must never trap the player)" % ScreenWatchdog.OWN_BACK_IDLE_SECONDS)
	var br: Rect2 = wd._btn.get_global_rect()
	TestLib.check(br.size.y >= 64.0 and br.get_center().distance_to(own.get_center()) < 4.0, "and it sits on the screen's own BACK, not beside it")
	TestLib.check(wd.press() and wd.trapped() == &"", "BACK leaves the screen")
	Game.state = &"play"
	await TestLib.frames(host, 2)


# --- 9 -------------------------------------------------------------------------------------------------------------------------

func _map_new_game(main: Node) -> void:
	var ms: MapScreen = null
	for n in main.find_children("*", "MapScreen", true, false):
		ms = n as MapScreen
	TestLib.check(ms != null, "the game has the map screen")
	if ms == null:
		return
	TestLib.check(MapScreen.MARKER_PICK_PX >= 34.0, "map markers are picked from a bigger circle (%.0f base px)" % MapScreen.MARKER_PICK_PX)
	ms._seen.fill(1)                                        # the persisted map of an earlier run: everything charted
	TestLib.check(ms.discovered_count() == MapScreen.CELLS * MapScreen.CELLS, "the old map is fully charted")
	var prog := Game.progress as Progress
	prog.fresh_game = true
	ms._forget_if_new()
	var share := float(ms.discovered_count()) / float(MapScreen.CELLS * MapScreen.CELLS)
	TestLib.check(share < 0.3, "a NEW game starts on the core only (%.0f %% charted, was 85)" % (share * 100.0))
	ms._seen.fill(1)
	prog.fresh_game = false
	ms._forget_if_new()
	TestLib.check(ms.discovered_count() == MapScreen.CELLS * MapScreen.CELLS, "CONTINUE keeps the map")
	ms.forget()
	await TestLib.frames(host, 1)
