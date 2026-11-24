extends RefCounted
## Wave 121 (w121-lifts): LIFTS in the tall buildings and the wave 120 leftovers. The real main scene, the phone HUD (Game.force_touch), the phone-only layers on (CrateReveal._quiet = 0),
## REAL FINGERS only (InputEventScreenTouch / Drag through Input.parse_input_event, tests/w116_fingers.gd via tests/w120_reach_lib.gd). Start points by teleport (setup only).
##   lift   at a tall building: the context slot reads LIFT at the call spot, a finger calls the cabin, its doors open, the stick walks in, LIFT opens the floor panel,
##          a finger on ROOF rides up (under 3 s, the cabin really moves through the floors), the HUD and the map show the floor, the stick walks out onto the roof; the same
##          way back to the ground. Panel buttons at least 44 px at 844x390 and at 2400x1080.          [old fails: no lift, no LIFT word, no floor]
##   tower  in a walk-in tower of w121-floors: the stick walks in at the street door, LIFT at the lift bay calls the cabin, the panel lists every floor, a finger on the top
##          floor rides up (under 3 s) and the doors open onto that floor (the stick walks out), the HUD and the map read the floor; GROUND rides back down.   [old fails]
##   edge   the invisible world-edge walls reach above the 1000 m plane ceiling (were 0 .. 400 m)    [W121_EDGE_OLD=1 fails]
##   boatdt the boat / aircraft edge turn-back slows a craft by the second, not by the frame         [W121_EDGE_OLD=1 fails]
##   gps    (wave 120 open item) a finger on the minimap opens the map, a finger on the 559 m peak puts the GPS waypoint there, the route leads to it
##   zip    (wave 120 open item) a finger on ZIP aimed at a tower's roof edge takes the hero up onto the roof (zip, climb, mantle by the game itself)
##   roofs  (wave 120 open item) roofs in the outskirts (a village house), the airport (terminal) and the ARMY YARD hold a hero who drops on them, and the stick walks on them
## LIFT_PARTS=lift,edge,boatdt picks parts.
const TIMEOUT_SECONDS := 150
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib


func run(h: Node) -> void:
	L = Lib.new()
	await L.start(h)
	h.get_tree().root.size = Vector2i(844, 390)                     # the owner's phone
	await L.f(6)
	var parts := (OS.get_environment("LIFT_PARTS") if OS.get_environment("LIFT_PARTS") != "" else "edge,boatdt,tower,lift,gps,zip,roofs").split(",")
	for part in parts:
		match part:
			"edge": _edge()
			"boatdt": await _boatdt()
			"lift": await _lift()
			"tower": await _tower()
			"gps": await _gps()
			"zip": await _zip()
			"roofs": await _roofs()
	await L.finish()


func _edge() -> void:
	var top := -1.0e9
	var bottom := 1.0e9
	for nm in ["WallE", "WallW", "WallN", "WallS"]:
		var cs := L.main.find_child(nm, true, false) as CollisionShape3D
		if cs == null:
			continue
		var bs := cs.shape as BoxShape3D
		top = maxf(top, cs.global_position.y + bs.size.y * 0.5)
		bottom = minf(bottom, cs.global_position.y - bs.size.y * 0.5)
	TestLib.check(top >= 1100.0 and bottom <= -100.0, "the world-edge walls stand from under the sea floor to above the 1000 m plane ceiling (%.0f .. %.0f m) [old: 0 .. 400]" % [bottom, top])


func _boatdt() -> void:
	var vm := Game.vehicles as VehicleManager
	var boat: Vehicle = null
	await L.place(Vector3(CityLayout.PLAY_HALF - 250.0, TerrainHeight.SEA_LEVEL + 0.5, 1790.0), 0.0)      # out at sea: the city cars go, the car cap has room
	await L.secs(2.0)
	for k in 4:                                                     # a free spot at sea just inside the soft edge (k small: a slow, partial damping)
		var s := Vector3(CityLayout.PLAY_HALF - 245.0, TerrainHeight.SEA_LEVEL - 0.5, 1800.0 + 60.0 * k)
		boat = vm.spawn_parked(&"boat", s, -PI * 0.5)
		if boat != null:
			break
	TestLib.check(boat != null, "setup: a boat out at sea by the east edge")
	if boat == null:
		return
	var kept: Array[float] = []
	for rate in [30.0, 120.0]:
		boat.vel = Vector3(20.0, 0.0, 0.0)
		for i in int(rate * 0.5):
			AircraftFlight.edge_turn(boat, 1.0 / rate)
		kept.append(boat.vel.x)
	TestLib.check(absf(kept[0] - kept[1]) < 0.15 * maxf(absf(kept[0]), 1.0) + 0.3, "the edge slows a boat the same at 30 and 120 fps (outward speed after 0.5 s: %.2f vs %.2f m/s) [old: frame-rate bound]" % [kept[0], kept[1]])
	boat.vel = Vector3.ZERO


## The tall lot nearest the spawn, and its lift built.
func _pick() -> int:
	var best := -1
	var bd := 1.0e9
	var lay := TowerLift._layout()
	for i in TowerLift.tall_lots():
		var lot: CityLayout.Lot = lay.lots[i]
		var d := Vector2(lot.cx - Game.SPAWN.x, lot.cz - Game.SPAWN.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _tap(pos: Vector2) -> void:
	L.fg.down(7, pos)
	await L.f(3)
	L.fg.up(7)
	await L.f(3)


func _press_lift(wait := 0.6) -> bool:
	var t := 0.0
	while L.fg.button_label(&"interact") != "LIFT" and t < 2.0:
		await L.secs(0.1)
		t += 0.1
	if L.fg.button_label(&"interact") != "LIFT":
		return false
	await L.press(&"interact", 4)
	await L.secs(wait)
	return true


func _close(tl: TowerLift) -> void:
	for b in tl.panel_buttons():
		if b.name == "LiftClose":
			await _tap(b.get_global_rect().get_center())
	TestLib.check(not tl.panel_open(), "a finger on CLOSE closes the lift panel")


func _sizes(tl: TowerLift, tag: String) -> void:
	await L.f(3)                                                       # containers lay out on process frames
	var sc := L.host.get_tree().root.get_final_transform().get_scale()
	var small := ""
	var n := 0
	for b in tl.panel_buttons():
		if not b.is_visible_in_tree():
			continue
		n += 1
		var px := b.get_global_rect().size * sc
		if px.x < 44.0 or px.y < 44.0:
			small += " %s %dx%d" % [b.name, int(px.x), int(px.y)]
		var r := b.get_global_rect()
		if not Rect2(Vector2.ZERO, L.fg.vp()).encloses(r):
			small += " %s off screen" % b.name
	TestLib.check(n >= 3 and small == "", "%s: every lift panel button (%d) is at least 44 px and on screen (%s)" % [tag, n, small])


func _lift() -> void:
	var tl := TowerLift.instance
	TestLib.check(tl != null, "the city has a lift node [old fails: no lifts]")
	if tl == null:
		return
	var idx := _pick()
	TestLib.check(idx >= 0, "the city has tall buildings (%d)" % TowerLift.tall_lots().size())
	if idx < 0:
		return
	var lay := TowerLift._layout()
	var lot: CityLayout.Lot = lay.lots[idx]
	var sp := TowerLift.spot(lot)
	var n: Vector3 = sp["normal"]
	var start := Vector3(sp["pos"]) + n * 4.0 + Vector3(0.0, 1.0, 0.0)
	await L.tp(start, Lib.yaw_to(start, Vector3(sp["pos"])))
	await L.secs(1.2)
	TestLib.check(tl.lot_idx == idx and tl.stops.size() >= 2, "the lift of the tall building next to the hero is built (lot %d, stops %s)" % [tl.lot_idx, tl.stops])
	if tl.lot_idx != idx:
		return
	var w := await L.walk(tl.call_point(0), 6.0, 0.8, 0.5)
	TestLib.check(L.fg.button_label(&"interact") == "LIFT", "at the call spot the context slot reads LIFT (reads %s, %.1f m off)" % [L.fg.button_label(&"interact"), w["dist"]])
	var called := await _press_lift(1.0)
	TestLib.check(called and tl.door_k >= 0.99 and tl.at_stop == 0, "a finger on LIFT calls the cabin and its street door opens (door %.2f, stop %d)" % [tl.door_k, tl.at_stop])
	var inside_pt := Vector3(sp["pos"]) + Vector3(0.0, tl.stops[0], 0.0)
	await L.walk(inside_pt, 5.0, 0.35, 0.45)
	TestLib.check(tl.in_cabin(L.p.global_position), "the stick walks the hero into the cabin (%.1f m from its centre)" % Lib.flat(L.p.global_position, inside_pt))
	var opened := await _press_lift(0.3)
	TestLib.check(opened and tl.panel_open(), "inside, a finger on LIFT opens the floor panel")
	await _sizes(tl, "844x390")
	var roof_btn: Button = null
	var names := []
	for b in tl.panel_buttons():
		names.append(b.text)
		if b.name == "Floor_ROOF":
			roof_btn = b
	TestLib.check(roof_btn != null and names.size() == tl.stops.size() + 1, "the panel lists every floor and CLOSE (%s)" % [names])
	if roof_btn == null:
		return
	var y0 := L.p.global_position.y
	var r0 := tl.rides
	await _tap(roof_btn.get_global_rect().get_center())
	TestLib.check(not tl.panel_open(), "a finger on ROOF closes the panel")
	var ys: Array[float] = []
	var t := 0.0
	while t < 5.0 and not (tl.rides >= r0 + 1 and tl.state != &"moving" and tl.state != &"closing"):
		await L.secs(0.1)
		t += 0.1
		ys.append(tl.cab_y)
	var mid := 0
	for y in ys:
		if y > tl.stops[0] + 2.0 and y < tl.stops[-1] - 2.0:
			mid += 1
	TestLib.check(tl.rides == r0 + 1 and tl.at_stop == tl.stops.size() - 1, "the cabin arrives at the roof (stop %d of %d)" % [tl.at_stop, tl.stops.size()])
	TestLib.check(tl.last_ride_s < 3.0 and mid >= 5, "the ride is under 3 s (%.2f s) and the cabin really moves between the floors (%d samples on the way)" % [tl.last_ride_s, mid])
	TestLib.check(L.p.global_position.y > tl.stops[-1] - 0.5 and tl.in_cabin(L.p.global_position), "the hero rode up in the cabin (y %.1f -> %.1f, roof %.1f)" % [y0, L.p.global_position.y, tl.stops[-1]])
	var hud := L.main.find_child("LiftFloor", true, false) as Label
	TestLib.check(hud != null and hud.visible and hud.text.contains("ROOF"), "the HUD shows the floor in the cabin (%s)" % (hud.text if hud != null else "none"))
	await L.secs(0.6)
	var roof_pt := tl.call_point(tl.stops.size() - 1)
	await L.walk(roof_pt, 6.0, 0.6, 0.5)
	var on_roof := L.p.global_position.y > tl.stops[-1] - 1.0 and lot.contains_xz(L.p.global_position.x, L.p.global_position.z)
	TestLib.check(on_roof, "the stick walks the hero out of the back door onto the roof (at %s)" % L.p.global_position)
	TestLib.check(tl.hud_floor() == "ROOF" and hud.visible, "the HUD reads ROOF on the roof (%s)" % tl.hud_floor())
	# the map: a finger on the minimap opens it, the building outline and the floor are drawn
	var tc := L.fg.tc
	await _tap(tc._minimap_rect().get_center())
	await L.f(6)
	var ms := L.main.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(MapScreen.up and ms != null and ms.tower_floor == "ROOF", "a finger on the minimap opens the map and it shows the floor (%s)" % (ms.tower_floor if ms != null else "?"))
	if MapScreen.up and ms != null:
		var cls := ms.find_child("Close", true, false) as Button
		await _tap(cls.get_global_rect().get_center())
	await L.f(4)
	# and back down
	await L.walk(roof_pt, 3.0, 0.5, 0.4)
	var again := await _press_lift(0.8)
	TestLib.check(again and tl.door_k > 0.9, "on the roof a finger on LIFT opens the waiting cabin (door %.2f)" % tl.door_k)
	await L.walk(Vector3(sp["pos"]) + Vector3(0.0, tl.stops[-1], 0.0), 5.0, 0.35, 0.45)
	TestLib.check(tl.in_cabin(L.p.global_position), "back in the cabin on the roof")
	var root := L.host.get_tree().root
	var old_size := root.size
	root.size = Vector2i(2400, 1080)
	await L.f(8)
	var big := await _press_lift(0.3)
	TestLib.check(big and tl.panel_open(), "2400x1080: a finger on LIFT opens the panel")
	await _sizes(tl, "2400x1080")
	await _close(tl)
	root.size = old_size
	await L.f(8)
	await _press_lift(0.3)
	TestLib.check(tl.panel_open(), "844x390 again: the panel is open")
	var g_btn: Button = null
	for b in tl.panel_buttons():
		if b.name == "Floor_G":
			g_btn = b
	if g_btn != null:
		await _tap(g_btn.get_global_rect().get_center())
	t = 0.0
	while t < 5.0 and not (tl.rides >= r0 + 2 and tl.state != &"moving" and tl.state != &"closing"):
		await L.secs(0.1)
		t += 0.1
	TestLib.check(tl.rides == r0 + 2 and tl.at_stop == 0 and L.p.global_position.y < tl.stops[0] + 1.0 and tl.last_ride_s < 3.0, "a finger on GROUND rides back down (stop %d, y %.1f, %.2f s)" % [tl.at_stop, L.p.global_position.y, tl.last_ride_s])
	await L.secs(0.6)
	var out_pt := tl.call_point(0) + n * 1.5
	await L.walk(out_pt, 5.0, 0.6, 0.5)
	TestLib.check(not tl.in_cabin(L.p.global_position) and tl.hud_floor() == "", "the hero walks out onto the sidewalk and the floor leaves the HUD (%s)" % tl.hud_floor())


func _ride(tl: TowerLift, btn_name: String, n_rides: int) -> void:
	var b: Button = null
	for x in tl.panel_buttons():
		if x.name == btn_name:
			b = x
	TestLib.check(b != null, "the panel has %s" % btn_name)
	if b == null:
		return
	await _tap(b.get_global_rect().get_center())
	var t := 0.0
	while t < 6.0 and not (tl.rides >= n_rides and tl.state == &"open"):
		await L.secs(0.1)
		t += 0.1


func _tower() -> void:
	var tf := TowerFloors.instance
	TestLib.check(tf != null and TowerFloors.enabled, "the walk-in towers of w121-floors are on")
	if tf == null:
		return
	var tw := tf.nearest(Game.SPAWN)
	TestLib.check(not tw.is_empty(), "a walk-in tower exists")
	if tw.is_empty():
		return
	var door := TowerFloors.door_pos(tw, 4.0) + Vector3(0.0, 1.0, 0.0)
	var inside := TowerFloors.door_pos(tw, -2.5)
	await L.tp(door, Lib.yaw_to(door, inside))
	await L.secs(1.5)
	await L.walk(inside, 8.0, 0.8, 0.6)
	await L.secs(0.6)
	var tl := TowerLift.instance
	var lot: CityLayout.Lot = tw["lot"]
	TestLib.check(tl != null and tl.mode == &"in" and tl.lot_idx == lot.index and tl.stops.size() >= 4, "inside the tower its lift is built with a stop on every floor (%s)" % [tl.stops if tl != null else []])
	if tl == null or tl.mode != &"in":
		return
	var cp := tl.call_point(0)
	var w := await L.walk(cp, 10.0, 0.8, 0.5)
	TestLib.check(L.fg.button_label(&"interact") == "LIFT", "at the lift bay the context slot reads LIFT (reads %s, %.1f m off)" % [L.fg.button_label(&"interact"), w["dist"]])
	await _press_lift(1.0)
	TestLib.check(tl.door_k > 0.99 and tl.at_stop == 0, "a finger on LIFT opens the cabin on the street floor")
	var cab := tl.base.origin + Vector3(0.0, tl.stops[0], 0.0)
	await L.walk(cab, 5.0, 0.3, 0.45)
	TestLib.check(tl.in_cabin(L.p.global_position), "the stick walks into the cabin (%.1f m from its centre)" % Lib.flat(L.p.global_position, cab))
	await _press_lift(0.3)
	TestLib.check(tl.panel_open() and tl.panel_buttons().size() == tl.stops.size() + 1, "LIFT opens the panel with every floor (%d buttons for %d stops)" % [tl.panel_buttons().size(), tl.stops.size()])
	await _sizes(tl, "tower 844x390")
	var top := tl.stops.size() - 2
	var r0 := tl.rides                                      # the top FLOOR (the roof is the last stop)
	await _ride(tl, "Floor_%d" % top, r0 + 1)
	TestLib.check(tl.at_stop == top and tl.last_ride_s < 3.0 and absf(L.p.global_position.y - tl.stops[top]) < 0.6, "a finger on FLOOR %d rides up in %.2f s (hero y %.1f, floor %.1f)" % [top, tl.last_ride_s, L.p.global_position.y, tl.stops[top]])
	TestLib.check(tl.hud_floor() == "LIFT  FLOOR %d" % top, "the HUD reads the floor (%s)" % tl.hud_floor())
	var out := tl.call_point(top) + (tl.base.basis * Vector3.BACK) * 1.0
	await L.walk(out, 5.0, 0.6, 0.5)
	TestLib.check(not tl.in_cabin(L.p.global_position) and absf(L.p.global_position.y - tl.stops[top]) < 0.6 and tl.hud_floor() == "FLOOR %d" % top, "the stick walks out onto floor %d through the open doors (%s, y %.1f)" % [top, tl.hud_floor(), L.p.global_position.y])
	await _tap(L.fg.tc._minimap_rect().get_center())
	await L.f(6)
	var ms := L.main.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(MapScreen.up and ms.tower_floor == "FLOOR %d" % top, "the map opened by a finger shows the floor (%s)" % ms.tower_floor)
	if MapScreen.up:
		await _tap((ms.find_child("Close", true, false) as Button).get_global_rect().get_center())
	await L.f(4)
	await L.walk(tl.call_point(top), 4.0, 0.6, 0.4)
	await L.walk(tl.base.origin + Vector3(0.0, tl.stops[top], 0.0), 5.0, 0.3, 0.45)
	await _press_lift(0.3)
	TestLib.check(tl.in_cabin(L.p.global_position) and tl.panel_open(), "back in the cabin, the panel is open")
	await _ride(tl, "Floor_G", r0 + 2)
	TestLib.check(tl.at_stop == 0 and tl.last_ride_s < 3.0 and L.p.global_position.y < tl.stops[0] + 0.6, "a finger on GROUND rides back down (%.2f s, y %.1f)" % [tl.last_ride_s, L.p.global_position.y])
	await L.walk(tl.call_point(0) + (tl.base.basis * Vector3.BACK) * 1.0, 5.0, 0.6, 0.5)
	TestLib.check(not tl.in_cabin(L.p.global_position) and tl.hud_floor() == "GROUND", "out on the street floor (%s)" % tl.hud_floor())


const PEAK := Vector3(-200.0, 0.0, -2950.0)


func _gps() -> void:
	var start := PEAK + Vector3(0.0, 0.0, 320.0)
	await L.tp(Vector3(start.x, TerrainHeight.height_at(start.x, start.z) + 1.0, start.z), 0.0)
	var tw := 0.0
	while not TerrainMap.ready and tw < 20.0:                          # the world picture is built on a worker after the start
		await L.secs(0.5)
		tw += 0.5
	TestLib.check(TerrainMap.ready, "the world picture of the map is ready (%.1f s)" % tw)
	var tc := L.fg.tc
	await _tap(tc._minimap_rect().get_center())
	await L.f(20)
	var ms := L.main.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(MapScreen.up, "a finger on the minimap opens the map near the mountain")
	if not MapScreen.up:
		return
	var zb := ms.find_child("Zoom", true, false) as Button
	await _tap((ms.find_child("Locate", true, false) as Button).get_global_rect().get_center())      # YOU: the view on the hero
	await L.f(4)
	var you := ms._map.get_global_transform() * ms.world_to_map(L.p.global_position.x, L.p.global_position.z)
	TestLib.check(ms._map.get_global_rect().has_point(you), "the open map (and a finger on YOU) shows the hero in the outskirts (%s) [old fails: the view stayed clamped to the city]" % you)
	var at := Vector2.INF
	var vis := false
	for k in 6:                                                         # zoom out by finger until the peak is in the view
		await L.f(4)
		at = ms._map.get_global_transform() * ms.world_to_map(PEAK.x, PEAK.z)
		vis = ms._map.get_global_rect().grow(-40.0).has_point(at)
		if false: print("gps map k=%d zoom=%s peak=%s you=%s" % [k, zb.text, at, ms._map.get_global_transform() * ms.world_to_map(L.p.global_position.x, L.p.global_position.z)])
		if vis:
			break
		await _tap(zb.get_global_rect().get_center())
	TestLib.check(vis, "the peak is on the map view (%s in %s)" % [at, ms._map.get_global_rect()])
	await L.secs(0.4)                                                   # the map ignores taps for INPUT_QUIET after opening
	await _tap(at)
	await L.f(6)
	var wp := ms.waypoint
	TestLib.check(wp.is_finite() and Vector2(wp.x - PEAK.x, wp.z - PEAK.z).length() < 40.0, "a finger on the peak puts the GPS waypoint on the mountain (%s)" % wp)
	TestLib.check(MapRoute.goal(ms.waypoint).is_finite(), "the GPS goal is the mountain")
	await _tap((ms.find_child("Close", true, false) as Button).get_global_rect().get_center())
	await L.f(4)
	TestLib.check(not MapScreen.up, "CLOSE closes the map, the waypoint stays (%s)" % ms.has_waypoint())
	# walk by the stick toward it for a while: the distance to the peak shrinks
	var d0 := Lib.flat(L.p.global_position, PEAK)
	await L.walk(PEAK, 8.0, 5.0, 1.0)
	var d1 := Lib.flat(L.p.global_position, PEAK)
	TestLib.check(d1 < d0 - 10.0, "walking toward the GPS goal up the mountain gets closer (%.0f -> %.0f m)" % [d0, d1])
	ms.clear_waypoint()


func _zip() -> void:
	var lay := TowerLift._layout()
	var lot: CityLayout.Lot = null
	var bd := 1.0e9
	for i in TowerLift.tall_lots():
		var l: CityLayout.Lot = lay.lots[i]
		if l.h > 45.0 or l.h < 26.0:
			continue
		var d := Vector2(l.cx - Game.SPAWN.x, l.cz - Game.SPAWN.z).length()
		if d < bd:
			bd = d
			lot = l
	if lot == null:
		TestLib.check(false, "a tower of 26 to 45 m for the zip")
		return
	var sp := TowerLift.spot(lot)
	var n: Vector3 = sp["normal"]
	var t := Basis(Vector3.UP, float(sp["yaw"])) * Vector3.RIGHT
	var wall := Vector3(sp["pos"]) - n * TowerLift.OUT + t * 6.0
	var stand := wall + n * 12.0
	await L.tp(stand + Vector3(0.0, 1.0, 0.0), Lib.yaw_to(stand, wall))
	await L.secs(0.8)
	L.p.camera_rig.aim_at(wall + Vector3(0.0, lot.h - 0.5, 0.0))      # setup: the view on the roof edge (the action below is a finger)
	await L.f(3)
	var pressed := false
	for k in 3:
		if L.fg.press(6, &"snake_zip"):
			pressed = true
			await L.f(4)
			L.fg.up(6)
			break
		await L.secs(0.3)
	TestLib.check(pressed, "the ZIP button is on screen at the tower")
	var t0 := 0.0
	while t0 < 20.0 and not (L.p.global_position.y > lot.h * 0.6 and L.p.is_on_floor() and L.p.snake.mode == SnakeTraversal.Mode.NONE):
		await L.secs(0.25)
		t0 += 0.25
	var gp := L.p.global_position
	TestLib.check(gp.y > lot.h * 0.6 and L.p.is_on_floor() and lot.contains_xz(gp.x, gp.z, 0.5), "a finger on ZIP at the roof edge takes the hero up onto the building's roof (y %.1f, top %.1f, stepped crowns stand lower, %.1f s)" % [gp.y, lot.h, t0])


## The highest flat roof point within r of c: a grid of rays from above (Vector3.INF when none above ground + 2.5 m).
func _roof_near(c: Vector3, r: float) -> Vector3:
	var ss := L.p.get_world_3d().direct_space_state
	var best := Vector3.INF
	var g := TerrainHeight.height_at(c.x, c.z)
	for ix in range(-8, 9):
		for iz in range(-8, 9):
			var x := c.x + ix * r / 8.0
			var z := c.z + iz * r / 8.0
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, g + 80.0, z), Vector3(x, g - 5.0, z), Game.L_WORLD)
			q.exclude = [L.p.get_rid()]
			var hit := ss.intersect_ray(q)
			if hit.is_empty() or (hit["normal"] as Vector3).y < 0.9:
				continue
			var hp: Vector3 = hit["position"]
			if hp.y > g + 2.5 and hp.y < g + 40.0 and (not best.is_finite() or hp.y > best.y):
				best = hp
	return best


func _roofs() -> void:
	var sites := {}
	var towns := SettlementData.towns()
	if not towns.is_empty():
		var dd := SettlementData.doors_of(StringName(towns[0]["id"]))
		if not dd.is_empty():
			sites["outskirts house"] = Vector3(dd[0]["pos"])
	sites["airport terminal"] = Airport.to_world(Vector3(1118.0, 0.0, -630.0))
	sites["army yard"] = ArmourSites.YARD
	for nm: String in sites:
		var c: Vector3 = sites[nm]
		await L.tp(c + Vector3(0.0, 2.0, 0.0), 0.0)
		await L.secs(1.5)
		var roof := _roof_near(c, 22.0)
		TestLib.check(roof.is_finite(), "%s: a roof is found near %s" % [nm, c])
		if not roof.is_finite():
			continue
		L.p.global_position = roof + Vector3(0.0, 6.0, 0.0)              # setup: dropped over the roof
		L.p.velocity = Vector3.ZERO
		await L.secs(2.0)
		var on := absf(L.p.global_position.y - roof.y) < 0.7
		TestLib.check(on, "%s: the hero lands on the roof and stays (y %.1f, roof %.1f)" % [nm, L.p.global_position.y, roof.y])
		L.fg.stick(Vector2(0.0, -0.4))
		await L.secs(0.8)
		L.fg.stick(Vector2.ZERO)
		await L.secs(0.6)
		var after := L.p.global_position.y
		TestLib.check(after > roof.y - 3.0 and after < roof.y + 1.0 or after > TerrainHeight.height_at(L.p.global_position.x, L.p.global_position.z) - 0.3, "%s: the stick walks on the roof without sinking into it (y %.1f)" % [nm, after])
