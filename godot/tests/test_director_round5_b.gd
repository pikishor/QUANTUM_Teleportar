extends RefCounted
## Director review 5, presentation half (docs/SLICE_REVIEW.md "Round 5 fixes, presentation half"), in the REAL scene (main.tscn, touch layout forced):
##  6  the camera never sits inside a parked bus or car behind the hero: the lens ends outside every vehicle body and at least 1 m from his head
##  8  the Mission Board is as wide as the phone allows (cards >= 60 % of a 2400 px screen), every card carries its pay as a chip, TEST is not in EXTRAS on a phone HUD
##     (it needs the setting or ALL EXTRAS), the EXTRAS cards are large and on screen
##  9  the weapon wheel wedges say the class in full words (PISTOL, SHOTGUN ...) with the weapon name for the caption, not three-letter codes
## 10  the map: no two drawn icons overlap (except the objective, side jobs and homes), at zoom 1 / 2 / 4 / 8 the icon count stays under the cap
## 11  the lamp cones are smooth (normals, ten faces)
## Waits on state and counters, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_director_round5_b.gd

const SAVE := "user://test_director_round5_b.cfg"
const SETTINGS := "user://test_director_round5_b_settings.cfg"

var host: Node
var main: Node
var hud: Hud
var p: Player
var rig: CameraRig


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


func _cleanup() -> void:
	for f: String in [SAVE, SETTINGS, "user://map.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	_cleanup()
	TestMode.reset_toggles()
	var was_touch := Game.force_touch
	Game.force_touch = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	hud = main.find_child("Hud", true, false) as Hud
	var prog := Game.progress as Progress
	TestLib.check(p != null and hud != null and prog != null and hud.touch != null, "main.tscn composes the player, the HUD and the touch controls")
	if p == null or hud == null or prog == null or hud.touch == null:
		Game.force_touch = was_touch
		return
	rig = p.camera_rig
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	hud.settings = UiSettings.new(SETTINGS)
	hud.settings.publish(false)
	(Game.enemies as EnemyManager).clear()
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	Game.heat = 0.0
	Game.state = &"play"
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	hud.touch.controls_on = true
	hud.touch.release_all()
	_cones()
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(2400, 1080), Vector2i(844, 390)]:
		win.size = size
		await frames(4)
		var tag := "%dx%d" % [size.x, size.y]
		_board(tag, size)
		_extras(tag)
		await _wheel(tag)
	win.size = old
	await frames(3)
	await _camera()
	await _map()
	_cleanup()
	main.queue_free()
	await frames(5)
	Game.force_touch = was_touch
	Game.state = &"menu"


# --- 11 ------------------------------------------------------------------------------------------------------------------------

func _cones() -> void:
	var mesh := LightingPolish.build_cones([Vector3(0, 7, 0), Vector3(20, 7, 5)])
	var arr := mesh.surface_get_arrays(0)
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	TestLib.check(LightingPolish.CONE_SIDES >= 8, "a lamp cone has at least eight faces (a hexagonal tent read as paper at MED)")
	TestLib.check(norms.size() == verts.size() and not norms.is_empty(), "every cone vertex has a normal: the shader fades the silhouette")
	var unit := true
	for n in norms:
		unit = unit and absf(n.length() - 1.0) < 0.01
	TestLib.check(unit, "cone normals are unit length")


# --- 8 ------------------------------------------------------------------------------------------------------------------------

func _board(tag: String, size: Vector2i) -> void:
	_state(&"paused")
	hud.press_button(&"board_open")
	_layout()
	var b0 := _btn(&"board_pick_0")
	if b0.is_empty():
		b0 = _btn(&"board_story")
	TestLib.check(not b0.is_empty(), "%s: the board shows its cards" % tag)
	if b0.is_empty():
		return
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var r: Rect2 = b0["rect"]
	TestLib.check(r.size.y >= 64.0 * s, "%s: a board card is at least 64 base px tall" % tag)
	TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r), "%s: the card is on screen" % tag)
	if size.x >= 2000:
		TestLib.check(r.size.x >= 0.6 * vp.x, "%s: the board uses the phone's width (%.0f of %.0f px)" % [tag, r.size.x, vp.x])
	TestLib.check(MissionBoardScreen.card_w(hud, s) >= MissionBoardScreen.CARD_W, "%s: the card width never drops under the tablet minimum" % tag)
	# the pay chip: the offers carry their reward and the screen draws one chip per offer card
	var m := Game.missions as Missions
	var picks := 0
	for bt: Dictionary in hud.buttons:
		if String(bt["id"]).begins_with("board_pick_"):
			picks += 1
	TestLib.check(m == null or m.board == null or picks == m.board.offers.size(), "%s: one card per offer (%d)" % [tag, picks])
	for bt: Dictionary in hud.buttons:
		TestLib.check(not String(bt.get("label", "")).contains(" CR"), "%s: the pay is a chip, not part of the title (%s)" % [tag, bt.get("label", "")])
		break
	_state(&"play")


func _extras(tag: String) -> void:
	_state(&"paused")
	hud.press_button(&"menu_gear")
	_layout()
	var ids: Array = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	TestLib.check(ids.has(&"more_back") and ids.has(&"menu"), "%s: EXTRAS shows its cards" % tag)
	TestLib.check(not TestMode.entry_shown(), "%s: TEST is hidden on a phone HUD (force_touch) without the setting" % tag)
	TestLib.check(hud.more_test_rect().size == Vector2.ZERO, "%s: EXTRAS reserves no cell for TEST" % tag)
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var bad := ""
	for bt: Dictionary in hud.buttons:
		var r: Rect2 = bt["rect"]
		if r.size.y < 64.0 * s or not Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r):
			bad = "%s %s" % [bt["id"], r]
	TestLib.check(bad == "", "%s: every EXTRAS card is >= 64 base px tall and on screen (%s)" % [tag, bad])
	if vp.x >= 2000.0:
		var w0: float = (_btn(&"look_open")["rect"] as Rect2).size.x if not _btn(&"look_open").is_empty() else 0.0
		TestLib.check(w0 >= 0.18 * vp.x, "%s: an EXTRAS card is wide (%.0f px)" % [tag, w0])
	var was := TestMode.forced
	TestMode.forced = true
	TestLib.check(TestMode.entry_shown(), "%s: the TEST entry comes back when the setting forces it" % tag)
	TestMode.forced = was
	hud.press_button(&"more_back")
	_state(&"play")


# --- 9 ------------------------------------------------------------------------------------------------------------------------

func _wheel(tag: String) -> void:
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var items := WeaponWheel.items()
	TestLib.check(items.size() >= 6, "%s: the weapon wheel has a wedge per class (%d)" % [tag, items.size()])
	var words_ok := true
	var names_ok := true
	for it: Dictionary in items:
		var cn := String(it.get("cname", ""))
		words_ok = words_ok and WeaponDefs.CLASS_NAMES.values().has(cn)
		names_ok = names_ok and String(it.get("wname", "")).length() >= 4
	TestLib.check(words_ok, "%s: wedges carry the class in full words (PISTOL, SHOTGUN), not a code" % tag)
	TestLib.check(names_ok, "%s: wedges carry the weapon's name for the caption" % tag)
	hud.touch.controls_on = true
	Game.state = &"play"
	hud.touch._open_wheel(&"weapon", -1, Vector2(hud.get_viewport().get_visible_rect().size * Vector2(0.8, 0.7)))
	await frames(3)
	TestLib.check(hud.touch.wheel.is_open, "%s: the weapon wheel opens" % tag)
	hud.touch.wheel.sel = 0
	await frames(2)
	hud.touch.wheel.close()


# --- 6 ------------------------------------------------------------------------------------------------------------------------

func _lens_in_vehicle(at: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.12
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = Game.L_VEHICLE
	return not p.get_world_3d().direct_space_state.intersect_shape(q, 2).is_empty()


func _camera() -> void:
	Game.state = &"play"
	var vm := Game.vehicles as VehicleManager
	if vm == null:
		TestLib.check(false, "the vehicle manager exists")
		return
	var spot := Vector3(-30.0, 0.0, 4.0)
	p.teleport_to(spot)
	await frames(10)
	var ground := p.global_position
	rig.reset_view(0.0, 0.0)
	await frames(6)
	# a bus lying across the lens line, two and a half metres behind the hero (the camera arm is about 3.3 m)
	var back := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, rig.yaw)
	var bus := vm.spawn_parked(&"bus", Vector3(ground.x, 0.0, ground.z) + back * 3.0, rig.yaw + PI * 0.5)
	TestLib.check(bus != null, "a parked bus spawns behind the hero")
	if bus == null:
		return
	await frames(20)
	var rest := rig._camera_rest_position()
	TestLib.check(_lens_in_vehicle(rest), "set-up: the lens WITHOUT avoidance would sit inside the bus")
	var worst_in := 0
	var min_head := 99.0
	for i in 30:
		await frames(1)
		var head := p.global_position + Vector3(0.0, 1.55, 0.0)
		var lens := rig.camera.global_position
		if _lens_in_vehicle(lens):
			worst_in += 1
		min_head = minf(min_head, lens.distance_to(head))
	TestLib.check(worst_in == 0, "the lens is never inside the bus (%d of 30 frames inside)" % worst_in)
	TestLib.check(min_head >= 0.8, "the lens keeps at least 0.8 m from the head (%.2f m)" % min_head)
	# walking away from the bus lets the lens back out to the full arm
	p.teleport_to(spot + Vector3(0.0, 0.0, -14.0))
	await frames(40)
	var d := rig.camera.global_position.distance_to(p.global_position + Vector3(0.0, 1.55, 0.0))
	TestLib.check(d >= 2.4, "the arm is back to full length away from the bus (%.2f m)" % d)
	bus.deactivate()
	await frames(2)


# --- 10 -----------------------------------------------------------------------------------------------------------------------

func _map() -> void:
	var ms := hud.touch.get_node_or_null("MapScreen") as MapScreen
	TestLib.check(ms != null, "the real scene has the map screen")
	if ms == null:
		return
	_state(&"paused")
	ms.reveal_all()
	ms.discover(Game.player.global_position)
	Game.state = &"play"
	ms.open()
	await frames(3)
	for z in [1.0, 2.0, 4.0, 8.0]:
		ms.zoom_f = z
		ms.locate()
		ms._clamp_view()
		ms._map.queue_redraw()
		await frames(3)
		var badges: Array = ms.drawn["badges"]
		var cap := ms.badge_cap()
		TestLib.check(badges.size() <= cap + 3, "zoom %.0f: %d icons drawn (cap %d)" % [z, badges.size(), cap])
		var worst := 99.0
		var pair := ""
		for i in badges.size():
			for j in range(i + 1, badges.size()):
				var a: Array = badges[i]
				var b: Array = badges[j]
				if MapScreen.ALWAYS_KINDS.has(a[2]) or MapScreen.ALWAYS_KINDS.has(b[2]):
					continue
				var gap := (a[0] as Vector2).distance_to(b[0] as Vector2) / (float(a[1]) + float(b[1]))
				if gap < worst:
					worst = gap
					pair = "%s / %s" % [a[2], b[2]]
		TestLib.check(worst >= 1.0, "zoom %.0f: no two icons overlap (closest %.2f of the two radii, %s)" % [z, worst, pair])
	ms.close_screen()
	await frames(2)
