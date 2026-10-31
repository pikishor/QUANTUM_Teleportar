extends RefCounted
## HUD / UI module: state screens (menu, pause, dead, win), screen buttons and what they call, settings and best score persisted in a temp file,
## objective / ammo / message texts, the minimap (cached static layer, rotation, cores pinned to the rim), touch controls inside the HUD, and
## the guards (no player, no missions, no vehicles, no quantum, no atmosphere). Run: tools/test.sh tests/test_hud.gd

const TMP := "user://test_hud_settings.cfg"

class StubPlayer extends Node3D:
	var hp := 100.0
	var max_hp := 100.0
	var energy := 100.0
	var max_energy := 100.0
	var ammo := 30
	var mag := 30
	var reloading := false
	var vehicle: Node3D
	var quantum: Node
	var camera_rig: Node
	var last_hurt_time := -100.0
	var last_hurt_from := Vector3.ZERO


class StubMissions extends Node:
	var total := 6
	var got := 2
	var cores: Array = []
	var pickups: Array = []
	func nearest_core(pos: Vector3) -> Dictionary:
		if cores.is_empty():
			return {}
		var cp: Vector3 = cores[0].pos
		return {pos = cp, dist = Vector2(cp.x - pos.x, cp.z - pos.z).length()}


class StubWorld extends Node3D:
	var building_rects: Array[Rect2] = [Rect2(-30, -30, 26, 26), Rect2(10, 10, 18, 18)]


class StubAtmosphere extends Node:
	var enabled := true


class StubVehicles extends Node:
	var near: Node3D
	func nearest(_pos: Vector3, _r := 4.2) -> Node3D:
		return near


var _hud: Hud
var _events: Array[String] = []


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.state = &"menu"
	var atmo := StubAtmosphere.new()
	host.add_child(atmo)
	Game.atmosphere = atmo
	Game.new_game.connect(func() -> void: _events.append("new_game"))
	Game.respawn.connect(func() -> void: _events.append("respawn"))
	Game.next_sector.connect(func() -> void: _events.append("next"))
	var scene := load("res://scenes/hud.tscn") as PackedScene
	TestLib.check(scene != null, "scenes/hud.tscn loads")
	_hud = scene.instantiate() as Hud
	_hud.settings_path = TMP
	host.add_child(_hud)
	await TestLib.frames(host, 3)
	TestLib.check(_hud is CanvasLayer and _hud.touch != null and _hud.minimap != null, "the HUD is a CanvasLayer with the touch controls and the minimap inside")

	await _menu(host)
	await _pause()
	await _dead_and_win()
	await _settings(host, atmo)
	await _texts(host)
	await _minimap(host)
	await _guards(host)
	await _layouts(host)

	_hud.queue_free()
	atmo.queue_free()
	Game.atmosphere = null
	Game.state = &"play"
	await TestLib.frames(host, 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Sfx.muted = false


func _ids() -> Array:
	return _hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])


func _menu(host: Node) -> void:
	_hud._on_state(Game.state)
	_hud._ensure_layout()
	var ids := _ids()
	TestLib.check(ids.has(&"deploy") and ids.has(&"q0") and ids.has(&"q1") and ids.has(&"q2") and ids.has(&"post") and ids.has(&"mute"), "the menu has DEPLOY, LOW / MED / HIGH, post FX and sound (%s)" % str(ids))
	TestLib.check(_hud.get_node("Screen").visible and not _hud.get_node("Hud").visible, "the menu shows its screen and hides the play HUD")
	_hud.screen_age = 5.0
	var deploy: Rect2 = _hud.buttons[0]["rect"]
	TestLib.check(_hud.tap(deploy.get_center()), "tapping DEPLOY works")
	TestLib.check(Game.state == &"play" and _events.has("new_game"), "DEPLOY starts a new game (Game.start_new_game)")
	TestLib.check(not _hud.get_node("Screen").visible and _hud.get_node("Hud").visible, "playing shows the HUD and hides the screens")
	TestLib.check(not _hud.press_button(&"deploy"), "DEPLOY does nothing outside the menu")


func _pause() -> void:
	_hud.pause_game()
	TestLib.check(Game.state == &"paused" and not _hud.get_tree().paused, "pause sets Game.state = paused and never the tree pause")
	_hud._ensure_layout()
	TestLib.check(_ids().has(&"resume") and _ids().has(&"menu"), "the pause screen has RESUME and ABORT TO MENU")
	TestLib.check(_hud.press_button(&"resume") and Game.state == &"play", "RESUME plays again")
	_hud.touch.pause_requested.emit()
	TestLib.check(Game.state == &"paused", "the touch pause button pauses")
	_hud.toggle_pause()
	TestLib.check(Game.state == &"play", "the pause action toggles back")
	_hud.pause_game()
	TestLib.check(_hud.press_button(&"menu") and Game.state == &"menu", "ABORT TO MENU returns to the title screen")
	Game.start_new_game()
	_events.clear()


func _dead_and_win() -> void:
	Game.score = 0
	Game.state = &"dead"
	TestLib.check(_hud.get_node("Screen").visible, "the dead screen is shown")
	TestLib.check(not _hud.tap(Vector2(300, 300)) and Game.state == &"dead", "a tap right after dying is ignored (lock %.1f s)" % Hud.LOCK)
	_hud.screen_age = Hud.LOCK + 0.1
	TestLib.check(_hud.tap(Vector2(300, 300)) and Game.state == &"play" and _events.has("respawn"), "tap to respawn calls Game.do_respawn()")
	_events.clear()
	Game.state = &"win"
	TestLib.check(not _hud.press_button(&"next"), "the win screen also has a short lock")
	_hud.screen_age = Hud.LOCK + 0.1
	TestLib.check(_hud.press_button(&"next") and Game.state == &"play" and _events.has("next"), "NEXT SECTOR calls Game.do_next_sector()")


func _settings(host: Node, atmo: StubAtmosphere) -> void:
	TestLib.check(_hud.press_button(&"q2") and Game.quality == 2 and _hud.settings.quality == 2, "HIGH sets Game.set_quality(2)")
	TestLib.check(_hud.press_button(&"q0") and Game.quality == 0, "LOW sets Game.set_quality(0)")
	_hud._on_state(&"menu")
	_hud.press_button(&"post")
	TestLib.check(not atmo.enabled and not _hud.settings.post, "the post-process toggle drives atmosphere.enabled")
	_hud.press_button(&"mute")
	TestLib.check(Sfx.muted and _hud.settings.muted, "mute sets Sfx.muted")
	var fresh := UiSettings.new(TMP)
	TestLib.check(fresh.quality == 0 and not fresh.post and fresh.muted, "quality, post-process and mute persist in the config file (%d %s %s)" % [fresh.quality, fresh.post, fresh.muted])
	# applying saved settings at startup
	atmo.enabled = true
	Sfx.muted = false
	Game.set_quality(1)
	_hud.apply_settings()
	TestLib.check(Game.quality == 0 and not atmo.enabled and Sfx.muted, "apply_settings re-applies the saved choices")
	_hud.press_button(&"post")
	_hud.press_button(&"mute")
	_hud.press_button(&"q1")
	# best score
	Game.state = &"play"
	Game.score = 1250
	Game.state = &"dead"
	TestLib.check(_hud.settings.best == 1250 and _hud.new_best, "dying with a record saves the best score")
	TestLib.check(UiSettings.new(TMP).best == 1250, "the best score is in the file")
	Game.state = &"play"
	Game.score = 400
	Game.state = &"win"
	TestLib.check(_hud.settings.best == 1250, "a lower score keeps the best")
	Game.state = &"play"
	Game.score = 0


func _texts(host: Node) -> void:
	TestLib.check(_hud.objective_text() == "NO ACTIVE OBJECTIVE", "objective without Missions: '%s'" % _hud.objective_text())
	TestLib.check(_hud.ammo_text() == "", "ammo text without a player is empty")
	var p := StubPlayer.new()
	host.add_child(p)
	Game.player = p
	var m := StubMissions.new()
	host.add_child(m)
	Game.missions = m
	TestLib.check(_hud.objective_text() == "QUANTUM CORES  2 / 6", "objective without cores shows the count only: '%s'" % _hud.objective_text())
	m.cores = [{"pos": Vector3(0, 0, -100.0)}]
	TestLib.check(_hud.objective_text() == "QUANTUM CORES  2 / 6   NEAREST  100 M", "objective with the distance to the nearest core: '%s'" % _hud.objective_text())
	p.position = Vector3(30, 0, -100)
	TestLib.check(_hud.objective_text().ends_with("NEAREST  30 M"), "the distance follows the player")
	TestLib.check(_hud.ammo_text() == "30 / 30", "ammo '30 / 30'")
	p.ammo = 7
	TestLib.check(_hud.ammo_text() == "7 / 30", "ammo follows the player")
	p.reloading = true
	TestLib.check(_hud.ammo_text() == "RELOADING", "RELOADING while reloading")
	var car := StubVehicleBody.new()
	car.speed = -10.0
	host.add_child(car)
	p.vehicle = car
	TestLib.check(_hud.ammo_text() == "36 KM/H", "km/h while driving (%s)" % _hud.ammo_text())
	var vs := StubVehicles.new()
	host.add_child(vs)
	Game.vehicles = vs
	TestLib.check(_hud.hint_text() == "[F]  EXIT VEHICLE", "hint while driving: '%s'" % _hud.hint_text())
	p.vehicle = null
	TestLib.check(_hud.hint_text() == "", "no hint without a vehicle in reach")
	vs.near = car
	TestLib.check(_hud.hint_text() == "[F]  ENTER VEHICLE", "hint near a vehicle: '%s'" % _hud.hint_text())
	Game.vehicles = null
	vs.queue_free()
	car.queue_free()
	# messages
	Game.say("TELEPORTED", 1.5)
	TestLib.check(_hud.message_text == "TELEPORTED" and _hud.message_left > 1.4, "Game.say shows a centre message")
	_hud.message_left = 0.0
	await TestLib.frames(host, 6)                  # the draw functions run against the stub player without errors
	p.hp = 20.0
	p.last_hurt_time = PlayerUtil.now()
	p.last_hurt_from = Vector3(10, 0, 10)
	await TestLib.frames(host, 4)
	TestLib.check(true, "the HUD draws with low health and a hurt flash")
	p.queue_free()
	m.queue_free()
	Game.player = null
	Game.missions = null
	await TestLib.frames(host, 2)


class StubVehicleBody extends Node3D:
	var speed := 0.0
	var hp := 80.0
	var max_hp := 100.0


func _minimap(host: Node) -> void:
	var mm := _hud.minimap
	TestLib.check(not mm.ensure_static(), "no static layer without a world")
	var w := StubWorld.new()
	host.add_child(w)
	Game.world = w
	TestLib.check(mm.ensure_static() and mm.tex != null, "the static layer is rendered once from building_rects")
	var t0 := mm.tex
	mm.ensure_static()
	TestLib.check(mm.tex == t0, "the cached texture is reused while the world is unchanged")
	var img := mm.tex.get_image()
	var ppm := float(Minimap.TEX_PX) / (2.0 * Minimap.EXTENT)
	var inside := img.get_pixel(int((-17.0 + Minimap.EXTENT) * ppm), int((-17.0 + Minimap.EXTENT) * ppm))
	var street := img.get_pixel(int((-40.0 + Minimap.EXTENT) * ppm), int((-40.0 + Minimap.EXTENT) * ppm))
	TestLib.check(inside.b > street.b + 0.1, "building footprints are brighter than the street")
	# rotation: whatever is in front of the view ends up above the centre
	var p := StubPlayer.new()
	host.add_child(p)
	Game.player = p
	mm._update_view(80.0)
	var a := mm.to_map(0.0, -65.0)
	TestLib.check(a.y < -30.0 and absf(a.x) < 0.01, "facing -Z, a point ahead is up on the map (%s)" % str(a))
	p.rotation.y = PI * 0.5
	mm._update_view(80.0)
	var b := mm.to_map(-65.0, 0.0)
	TestLib.check(b.y < -30.0 and absf(b.x) < 0.01, "after turning 90 degrees the new forward is up (%s)" % str(b))
	var r := mm.to_map(0.0, -65.0)
	TestLib.check(r.x > 30.0, "the old forward is now to the right (%s)" % str(r))
	# markers: enemies, pickups and a far core pinned to the rim
	var m := StubMissions.new()
	m.cores = [{"pos": Vector3(0, 0, -400.0)}, {"pos": Vector3(20, 0, 0)}]
	m.pickups = [{"pos": Vector3(10, 0, 10), "kind": &"health"}]
	host.add_child(m)
	Game.missions = m
	var e := Node3D.new()
	e.add_to_group(&"enemy")
	host.add_child(e)
	e.position = Vector3(15, 0, 15)
	mm.size = Vector2(176, 176)
	await TestLib.frames(host, 8)
	TestLib.check(mm.core_markers == 2, "both cores are drawn, the far one pinned to the rim (%d)" % mm.core_markers)
	TestLib.check(mm.markers_drawn >= 2, "an enemy and a pickup in range are drawn (%d)" % mm.markers_drawn)
	e.queue_free()
	m.queue_free()
	p.queue_free()
	w.queue_free()
	Game.world = null
	Game.player = null
	Game.missions = null
	await TestLib.frames(host, 2)


func _guards(host: Node) -> void:
	Game.player = null
	Game.missions = null
	Game.vehicles = null
	Game.world = null
	Game.state = &"play"
	await TestLib.frames(host, 8)
	TestLib.check(true, "the HUD runs with no player, world, missions, vehicles or quantum")
	var p := StubPlayer.new()                       # a player that lacks most properties
	host.add_child(p)
	Game.player = p
	await TestLib.frames(host, 6)
	TestLib.check(_hud.hint_text() == "" and not _hud.touch.button_visible(_find(&"blink")), "no vehicles or quantum: no hint, no BLINK button")
	p.free()
	Game.player = null
	Game.state = &"menu"
	await TestLib.frames(host, 3)
	TestLib.check(not _hud.wants_mouse_capture(), "no mouse capture in the menu (or under tools)")
	Game.state = &"play"


func _find(action: StringName) -> Dictionary:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action:
			return b
	return {}


## Buttons stay inside the screen and big enough to touch at 16:9 and 20:9.
func _layouts(host: Node) -> void:
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(960, 540)]:
		win.size = size
		await TestLib.frames(host, 3)
		var vp := host.get_viewport().get_visible_rect().size
		for st: StringName in [&"menu", &"paused", &"dead", &"win"]:
			Game.state = st
			_hud._ensure_layout()
			var ok := not _hud.buttons.is_empty()
			var min_h := 9999.0
			for b: Dictionary in _hud.buttons:
				var r: Rect2 = b["rect"]
				ok = ok and Rect2(Vector2.ZERO, vp).encloses(r)
				min_h = minf(min_h, r.size.y)
			TestLib.check(ok and min_h >= 36.0 * vp.y / 720.0 - 0.01, "%s buttons fit a %dx%d screen (min height %.0f px)" % [st, size.x, size.y, min_h])
	win.size = old
	Game.state = &"play"
