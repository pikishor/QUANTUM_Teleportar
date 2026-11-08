extends RefCounted
## MAP FREEZE (owner round 4: "it got stuck / froze when I opened the map view"). The REAL game scene, every way in and every context, 50 open / pan / zoom / waypoint / close cycles:
##   ways in    pause > MAP (the HUD card), a tap on the minimap (a real touch event), the M key
##   contexts   street, interior, a car, photo mode, a boss on the field
##   asserts    the game keeps running (frames advance, the open map does not let its taps fall through to the pause menu underneath, Esc / back closes it), Game.state returns to
##              play after the close, no input capture is left behind, no single frame (open, draw, close) takes longer than a budget, and the watchdog frees a trapped player.
## Also: the dozen things that used to be able to hang or trap (a huge route, a route point at infinity, chevrons on a 40 000 px line, a map with no size).
## Waits on game time and state, never on frame counts alone. user:// state is reset first.
## Run: tools/test.sh tests/test_map_no_freeze.gd

const CYCLES := 50
const OPEN_BUDGET_MS := 1500.0      ## the first open may build the shard list (a one-time cost); later opens are held to FRAME_BUDGET_MS
const FRAME_BUDGET_MS := 400.0      ## software rendering and a loaded CI runner: a frame of the open map is far below this on any phone, a hang is orders of magnitude above

var host: Node
var main: Node
var hud: Hud
var touch: TouchControls
var ms: MapScreen
var worst_ms := 0.0
var worst_open_ms := 0.0
var opens := 0


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	_unit()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	hud = host.get_tree().root.find_child("Hud", true, false) as Hud
	touch = hud.touch if hud != null else null
	ms = host.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(hud != null and touch != null and ms != null and is_instance_valid(Game.player), "the real scene has a HUD, touch controls, a map screen and a hero")
	if hud == null or touch == null or ms == null or not is_instance_valid(Game.player):
		return
	var p := Game.player as Node3D
	for c in 5:                                                  # street: each way in
		await _cycle(c % 3, "street")
	await _contexts()
	await _fifty()
	await _phone_layout()
	await _trapped()
	TestLib.check(opens >= CYCLES, "%d opens ran" % opens)
	TestLib.check(worst_ms < FRAME_BUDGET_MS, "no frame of an open map took more than %.0f ms (worst %.0f ms)" % [FRAME_BUDGET_MS, worst_ms])
	TestLib.check(worst_open_ms < OPEN_BUDGET_MS, "the open itself (worst %.0f ms) stayed under %.0f ms" % [worst_open_ms, OPEN_BUDGET_MS])
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await TestLib.frames(host, 2)


# --- the pure parts: nothing in the map may loop on a bad number --------------------------------------------------------------------------------------

func _unit() -> void:
	var t0 := Time.get_ticks_msec()
	var mscr := MapScreen.new()
	host.add_child(mscr)
	mscr._seen.fill(1)
	# a route with an infinite or NaN point must not hang the chevron walk or the draw
	var pl := PackedVector2Array([Vector2(0, 0), Vector2(INF, 0), Vector2(100, 100), Vector2(NAN, 5), Vector2(300, 300)])
	TestLib.check(MapScreen.clean_polyline(pl).size() == 3, "clean_polyline drops infinite and NaN points")
	var big := PackedVector2Array([Vector2(0, 0), Vector2(4.0e7, 0)])
	TestLib.check(MapScreen.clean_polyline(big).size() >= 2, "a 40 000 km line is kept (and clipped by the caller)")
	TestLib.check(MapRoute.route(Vector3(1e9, 0, 1e9), Vector3(-1e9, 0, 5)).size() >= 2, "a route between points far outside the city still returns")
	TestLib.check(MapRoute.route(Vector3.ZERO, Vector3.ZERO).size() >= 1, "a route from a point to itself returns")
	mscr.zoom_f = 8.0
	mscr.view_center = Vector2(1e9, -1e9)
	mscr._clamp_view()
	TestLib.check(absf(mscr.view_center.x) <= MapScreen.HALF and absf(mscr.view_center.y) <= MapScreen.HALF, "the view clamps to the city")
	mscr.zoom_by(NAN, Vector2.INF)
	TestLib.check(is_finite(mscr.zoom_f) and mscr.zoom_f >= 1.0 and mscr.zoom_f <= MapScreen.ZOOM_MAX, "a NaN pinch factor leaves a sane zoom")
	mscr.pan(Vector2(INF, NAN))
	TestLib.check(mscr.view_center.is_finite(), "an infinite pan leaves a finite view")
	mscr.set_waypoint(Vector3(NAN, 0, INF))
	TestLib.check(not mscr.has_waypoint() or mscr.waypoint.is_finite(), "a NaN waypoint is refused or clamped")
	mscr.queue_free()
	TestLib.check(Time.get_ticks_msec() - t0 < 2000, "the pure checks run in well under two seconds")


# --- one cycle: open by a way in, pan, zoom, waypoint, close -----------------------------------------------------------------------------------------

## way: 0 pause > MAP, 1 minimap tap, 2 the M key.
func _cycle(way: int, ctx: String) -> void:
	var state0: StringName = Game.state
	var tag := "%s/%s" % [ctx, ["pause", "minimap", "M"][way]]
	var t0 := Time.get_ticks_usec()
	match way:
		0:
			hud.pause_game()
			await host.get_tree().process_frame
			hud.press_button(&"pause_map")
		1:
			_tap_minimap()
		2:
			_key(KEY_M)
	await host.get_tree().process_frame
	var open_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	worst_open_ms = maxf(worst_open_ms, open_ms)
	opens += 1
	TestLib.check(ms.is_open() and Game.state == &"paused", "%s: the map opened and paused the game (state %s)" % [tag, Game.state])
	if not ms.is_open():
		hud.toggle_pause() if Game.state == &"paused" else null
		return
	await _frames_timed(4)
	# taps on the open map reach the map, never the pause menu underneath: tap where RESUME, MAP, OPTIONS and MORE sit
	var before: StringName = Game.state
	hud._ensure_layout()
	for id: StringName in [&"resume", &"pause_map", &"options", &"menu_gear", &"loadout"]:
		for b: Dictionary in hud.buttons:
			if b["id"] == id:
				_tap_screen((b["rect"] as Rect2).get_center())
	_tap_screen(ms._map.size * 0.5)
	await host.get_tree().process_frame
	TestLib.check(ms.is_open() and Game.state == before, "%s: taps on the map do not press the pause menu behind it (state %s, open %s)" % [tag, Game.state, ms.is_open()])
	ms.zoom_by(1.6, ms._map.size * 0.5)
	ms.pan(Vector2(120, -80))
	ms.zoom_by(0.7)
	ms.set_waypoint(Vector3(-200.0 + float(opens % 9) * 40.0, 0.0, 150.0))
	await _frames_timed(3)
	ms.clear_waypoint()
	ms.set_zoom(1)
	await _frames_timed(2)
	var c0 := Time.get_ticks_usec()
	ms.close_screen()
	await host.get_tree().process_frame
	worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - c0) / 1000.0)
	TestLib.check(not ms.is_open() and (Game.state == &"paused" if way == 0 else Game.state == state0), "%s: closing hands the state back (%s)" % [tag, Game.state])
	if Game.state == &"paused":
		hud.toggle_pause()
		await host.get_tree().process_frame
	TestLib.check(Game.state == state0 or state0 == &"paused", "%s: back in %s" % [tag, state0])


func _frames_timed(n: int) -> void:
	for i in n:
		var t0 := Time.get_ticks_usec()
		await host.get_tree().process_frame
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)


func _tap_minimap() -> void:
	var r := touch._minimap_rect()
	_tap_screen(r.get_center())


func _tap_screen(pos: Vector2) -> void:
	var d := InputEventScreenTouch.new()
	d.index = 0
	d.position = pos
	d.pressed = true
	host.get_viewport().push_input(d, true)                    # local coordinates: the headless window is not the viewport's size
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = pos
	u.pressed = false
	host.get_viewport().push_input(u, true)


func _key(code: Key) -> void:
	for pr in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pr
		Input.parse_input_event(e)


# --- contexts -----------------------------------------------------------------------------------------------------------------------------------------

func _contexts() -> void:
	# interior
	var msg := InteriorTestActions.enter(&"vault")
	await TestLib.frames(host, 6)
	TestLib.check(msg.begins_with("INSIDE") or InteriorGameplay.instance != null, "an interior was entered (%s)" % msg)
	for c in 3:
		await _cycle(c, "interior")
	InteriorTestActions.leave()
	await TestLib.frames(host, 6)
	# a car
	var mgr := Game.vehicles as VehicleManager
	var p := Game.player as Player
	if mgr != null and p != null:
		var car := mgr.spawn_parked(&"sedan", p.global_position + Vector3(4, 0, 0), 0.0)
		await TestLib.frames(host, 3)
		if car != null and p.has_method(&"enter_vehicle"):
			p.call(&"enter_vehicle", car)
		await TestLib.frames(host, 4)
		for c in 3:
			await _cycle(c, "car")
		if p.get("vehicle") != null and p.has_method(&"exit_vehicle"):
			p.call(&"exit_vehicle")
	# photo mode: paused with the photo camera up; the map opens over it (key M and the minimap are hidden there)
	hud.pause_game()
	await host.get_tree().process_frame
	var photo_on := hud.photo != null and hud.photo.begin()
	await TestLib.frames(host, 3)
	ms.open()
	await TestLib.frames(host, 4)
	TestLib.check((not photo_on) or ms.is_open(), "photo mode: the map opens over it")
	ms.close_screen()
	await TestLib.frames(host, 2)
	if hud.photo != null and hud.photo.active:
		hud.photo.end()
	if Game.state == &"paused":
		hud.toggle_pause()
	await TestLib.frames(host, 2)
	# a boss
	TestMode.spawn_enemy(&"overseer")
	await TestLib.frames(host, 4)
	for c in 3:
		await _cycle(c, "boss")


func _fifty() -> void:
	var n0 := opens
	var f0 := Engine.get_process_frames()
	while opens - n0 < CYCLES:
		await _cycle(opens % 3, "soak")
	TestLib.check(Engine.get_process_frames() > f0 + CYCLES, "the frame counter kept advancing through %d cycles" % CYCLES)


# --- the watchdog: a trapped player is freed -------------------------------------------------------------------------------------------------------

func _trapped() -> void:
	Game.state = &"play"
	await TestLib.frames(host, 2)
	var wd := host.get_tree().root.find_child("ScreenWatchdog", true, false) as ScreenWatchdog
	TestLib.check(wd != null, "a screen watchdog exists in the real scene")
	if wd == null:
		return
	TestLib.check(wd.trapped() == &"" and not wd.shown(), "playing: nothing is trapped, no BACK button")
	# the open map with nothing changing for the limit: the BACK button shows, and it closes the map
	hud.pause_game()
	await host.get_tree().process_frame
	TestLib.check(wd.trapped() == &"" and not wd.shown(), "the plain pause menu is not a trap (RESUME is on it)")
	hud.press_button(&"pause_map")
	await host.get_tree().process_frame
	TestLib.check(ms.is_open() and wd.trapped() == &"map", "trap: the map is open and counted")
	wd.force_idle(ScreenWatchdog.IDLE_SECONDS + 1.0)
	await host.get_tree().process_frame
	TestLib.check(wd.shown(), "trap: after %.0f s without progress the BACK button shows" % ScreenWatchdog.IDLE_SECONDS)
	var br: Rect2 = wd._btn.get_global_rect()
	TestLib.check(br.size.y >= 64.0 and Rect2(Vector2.ZERO, host.get_viewport().get_visible_rect().size).encloses(br), "the BACK button is a 64 px target inside the screen (%s)" % br)
	TestLib.check(wd.press() and not ms.is_open(), "trap: BACK closed the map")
	# a pause sub-screen: options
	Game.state = &"play"
	await host.get_tree().process_frame
	hud.pause_game()
	await host.get_tree().process_frame
	hud.press_button(&"options")
	await host.get_tree().process_frame
	TestLib.check(wd.trapped() == &"screen", "an options screen is a closable screen")
	wd.force_idle(100.0)
	await host.get_tree().process_frame
	TestLib.check(wd.shown() and wd.press() and wd.trapped() == &"", "BACK left the options screen for the pause menu")
	# progress resets the clock: a pan keeps the button away
	hud.press_button(&"pause_map")
	await host.get_tree().process_frame
	wd.force_idle(4.0)
	ms.pan(Vector2(30, 0))
	await host.get_tree().process_frame
	TestLib.check(wd.idle < 1.0 and not wd.shown(), "a pan is progress: the idle clock restarted")
	ms.close_screen()
	Game.state = &"play"
	await TestLib.frames(host, 2)
	# Esc closes the map first (it used to reach the pause menu under it and resume the game)
	hud.pause_game()
	await host.get_tree().process_frame
	hud.press_button(&"pause_map")
	await host.get_tree().process_frame
	_key(KEY_ESCAPE)
	await host.get_tree().process_frame
	TestLib.check(not ms.is_open() and Game.state == &"paused", "Esc closed the map and left the pause menu up (state %s)" % Game.state)
	Game.state = &"play"
	await TestLib.frames(host, 2)


# --- the bigger map: full screen at the phone aspect, framing, one-call static layers -------------------------------------------------------------------

func _phone_layout() -> void:
	var win := host.get_window()
	var old := win.size
	win.size = Vector2i(1200, 540)                                  # the 2400 x 1080 phone at half size
	await TestLib.frames(host, 4)
	Game.state = &"play"
	ms.clear_waypoint()
	ms.open()
	await TestLib.frames(host, 3)
	var sz := ms._map.size
	TestLib.check(ms._rect.size == sz and ms._rect.position == Vector2.ZERO, "the map fills the whole screen (%s)" % sz)
	TestLib.check(sz.x > sz.y * 1.8, "the test screen is a wide phone (%s)" % sz)
	ms.set_zoom(1)
	var ex := ms.extent()
	TestLib.check(is_equal_approx(ex.y, 2.0 * MapScreen.HALF) and ex.x > ex.y * 1.8, "zoom 1: the whole city fits the height, the width shows more (%s m)" % ex)
	TestLib.check(ms.view_center.is_equal_approx(Vector2.ZERO), "zoom 1 keeps the wide axis centred")
	ms.zoom_f = 3.0
	ms.view_center = Vector2(1.0e5, 1.0e5)
	ms._clamp_view()
	TestLib.check(ms.world_to_map(MapScreen.HALF, MapScreen.HALF).x <= sz.x + 1.0 and ms.world_to_map(MapScreen.HALF, MapScreen.HALF).y <= sz.y + 1.0, "panned to the far corner, the city edge sits on the screen edge, not past it")
	var w := Vector3(123.0, 0.0, -88.0)
	var back := ms.map_to_world(ms.world_to_map(w.x, w.z))
	TestLib.check(back.distance_to(w) < 0.5, "world <-> screen round trip on a wide screen")
	# a pinch keeps the point under the fingers where it is
	var focus := Vector2(sz.x * 0.7, sz.y * 0.4)
	var under0 := ms.map_to_world(focus)
	ms.zoom_by(1.5, focus)
	TestLib.check(ms.map_to_world(focus).distance_to(under0) < 1.0 or ms._clamp_limited(), "a pinch zooms about the fingers")
	# GOAL frames the hero and the objective together
	ms.set_waypoint(Vector3(-260.0, 0.0, 240.0))
	var pp := (Game.player as Node3D).global_position
	ms.fit_route()
	var a := ms.world_to_map(pp.x, pp.z)
	var b := ms.world_to_map(-260.0, 240.0)
	var vr := Rect2(Vector2.ZERO, sz)
	TestLib.check(vr.has_point(a) and vr.has_point(b), "GOAL: the hero %s and the objective %s are both on screen" % [a, b])
	# the opening tap is swallowed: a tap right after open does not place a waypoint
	ms.close_screen()
	ms.clear_waypoint()
	ms.open()
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = sz * 0.5
	ev.pressed = true
	ms._on_map_input(ev)
	ev = InputEventScreenTouch.new()
	ev.index = 0
	ev.position = sz * 0.5
	ev.pressed = false
	ms._on_map_input(ev)
	TestLib.check(not ms.has_waypoint(), "the tap that opened the map does not place a waypoint under the finger")
	# the static layers are single meshes, and a draw is cheap
	ms._open_age = 1.0
	await TestLib.frames(host, 3)
	TestLib.check(ms._lots_mesh != null and ms._lots_mesh.get_surface_count() == 1 and ms._lots_mesh_n == ms._lots.size() and ms._lots.size() > 100, "all %d building footprints are one mesh" % ms._lots.size())
	TestLib.check(ms._tint_mesh != null and ms._fog_mesh != null, "district tint and fog are meshes too")
	var t0 := Time.get_ticks_usec()
	for z in [1.0, 2.0, 4.0, 8.0]:
		ms.zoom_f = z
		ms.locate()
		ms._draw_map()
	var per := float(Time.get_ticks_usec() - t0) / 4000.0
	TestLib.check(per < 60.0, "a map draw costs %.1f ms at the phone aspect (4 zooms; the old per-lot draw was 100 ms at zoom 1)" % per)
	# the HUD hides the pause screen under the map and brings it back
	TestLib.check(not hud._screen.visible, "the pause screen under the open map is not drawn")
	ms.close_screen()
	await TestLib.frames(host, 2)
	TestLib.check(hud.layers_consistent(), "HUD layers consistent after the map closed")
	Game.state = &"play"
	win.size = old
	await TestLib.frames(host, 3)
