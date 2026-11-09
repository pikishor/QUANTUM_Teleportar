extends RefCounted
## AIRPORT AND AIRCRAFT (wave 106). Data checks first, then the REAL game scene:
##  * Airport: the pad is cut flat at the height of the city plateau, the runway (east-west, south of the city) / taxiway / apron / gates / pads are where the data says, the landing guide lines a plane up on a runway end, the mission contract
##    (`Airport.hooks`) is complete, the aircraft roster (small plane, jet fighter, airliner, cargo plane, business jet, helicopter, gunship, transport helicopter) has specs, models and weapons;
##  * live: AirportWorld under the city within its draw / triangle budget, the aircraft wait on the apron, the helipads and the mountain pads, the AIR TRAFFIC runs (planes take off and land, helicopters
##    patrol) and a grounded one is hijacked;
##  * flight: a small plane takes off from the runway, flies a circuit, lines up on the landing guide and lands, a jet takes off with the afterburner, stalls and recovers, the helicopter takes off, hovers,
##    flies and lands on a helipad (and on the roof pad), the gunship fires rockets and the jet fires missiles at a target.
## Run: tools/test.sh tests/test_airport_aircraft.gd   (about 120 s; waits on positions, counters and GAME time, never on frame counts)

const K := 3
const TIMEOUT_SECONDS := 150.0

var _host: Node
var _p: Player
var _vm: VehicleManager
var _city: City


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://boat_run.cfg", "user://outskirts.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_data()
	await _scene(host)


# --- data ---------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TerrainHeight.warm()
	# the pad: flat at the city plateau height, the land beyond blends in, the roads and the sites are untouched
	var flat := true
	for q in [Vector3(1262.0, 0.0, -500.0), Vector3(1150.0, 0.0, -600.0), Vector3(1240.0, 0.0, -940.0), Vector3(1284.0, 0.0, -160.0), Vector3(1370.0, 0.0, -700.0)]:
		var wq := Airport.to_world(q)
		flat = flat and absf(TerrainHeight.height_at(wq.x, wq.z)) < 0.01
	TestLib.check(flat, "the airport pad is cut flat at y = 0, the height of the city plateau")
	TestLib.check(Airport.carve(300.0, 300.0, 7.0) == 7.0 and Airport.carve(1600.0, -500.0, 7.0) == 7.0, "the airport carve is local (the land outside its rectangle is left alone)")
	var rw := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -550.0))
	TestLib.check(absf(rw.z - 1255.0) < 1.0 and rw.x > 800.0 and rw.x < 950.0, "the field lies east-west on the plain south of the city (runway centre x %.0f z %.0f)" % [rw.x, rw.z])
	TestLib.check(TerrainHeight.depth_at(1400.0, 1300.0) >= 0.0 and Airport.inside(rw.x, rw.z) and not Airport.inside(500.0, 500.0), "Airport.inside marks the field (vegetation keeps out)")
	var roads_ok := true
	for rd in TerrainRoads.roads():
		var rp: PackedVector2Array = rd["pos"]
		for pt in rp:
			roads_ok = roads_ok and not Airport.inside(pt.x, pt.y)
	TestLib.check(roads_ok, "no road runs across the field")
	var rails_ok := true
	for rt in RailNet.routes():
		var rp2: PackedVector2Array = rt["pos"]
		for pt2 in rp2:
			rails_ok = rails_ok and not Airport.inside(pt2.x, pt2.y, 20.0)
	TestLib.check(rails_ok, "no railway runs across the field")
	# the places
	var ths := Airport.thresholds()
	TestLib.check(ths.size() == 2 and float((ths[0]["pos"] as Vector3).distance_to(ths[1]["pos"])) > 700.0 and ths[0]["id"] == "09" and ths[1]["id"] == "27", "a runway of 800 m with two numbered ends (%s / %s)" % [ths[0]["id"], ths[1]["id"]])
	TestLib.check(Airport.GATE_Z.size() >= 4 and Airport.CONNECTORS.size() >= 3 and Airport.BUILDINGS.size() >= 5 and Airport.TANKS.size() >= 4, "gates, connectors, terminal, tower, hangars and fuel tanks")
	var pads := Airport.pads()
	var kinds := {}
	for p in pads:
		kinds[p["kind"]] = true
	TestLib.check(kinds.has(&"apron") and kinds.has(&"roof") and kinds.has(&"mountain") and kinds.has(&"site"), "helipads: the apron, a city roof, the mountains and the two mountain sites (%d pads)" % pads.size())
	var dry := true
	for p in pads:
		if p["kind"] == &"mountain":
			var pp: Vector3 = p["pos"]
			dry = dry and TerrainHeight.depth_at(pp.x, pp.z) <= 0.0 and absf(TerrainHeight.height_at(pp.x, pp.z) - pp.y) < 0.6 and pp.y > 1.0
	TestLib.check(dry, "every mountain pad is dry flat land at its pad height")
	var rf := Airport.roof()
	TestLib.check(not rf.is_empty() and (rf["pos"] as Vector3).y > 30.0 and Vector2((rf["pos"] as Vector3).x, (rf["pos"] as Vector3).z).length() > 540.0, "the roof pad stands on a tall tower, at least 540 m from the start of the game")
	var hooks := Airport.hooks()
	var hk := {}
	for h in hooks:
		hk[h["kind"]] = true
	TestLib.check(hk.has(&"terminal") and hk.has(&"hangar") and hk.has(&"runway") and hk.has(&"helipad"), "the mission contract (terminal, hangar, runway, helipad) is complete")
	var ap := WorldSites.airport()
	TestLib.check(bool(ap["real"]) and absf((ap["strip"] as Vector3).z - 1255.0) < 30.0 and (ap["strip"] as Vector3).x > 400.0, "WorldSites.airport() reads the real airport")
	# the landing guide: an eastbound plane west of the field lines up on runway 09, a westbound one east of it on 27
	var thr := Airport.thresholds()
	var t09: Vector3 = thr[0]["pos"]
	var g_on := Airport.guide(Vector3(t09.x - 550.0, 60.0, t09.z), -PI * 0.5, 40.0, 60.0)
	TestLib.check(bool(g_on["on"]) and g_on["rwy"] == "09" and absf(float(g_on["dist"]) - 550.0) < 1.0 and absf(float(g_on["lat"])) < 1.0, "the landing guide lines an eastbound plane up on runway 09 (%s, %.0f m)" % [g_on.get("rwy", "?"), float(g_on.get("dist", 0.0))])
	TestLib.check(float(g_on["vert"]) > 0.0, "it is high on the glide path at 60 m and 550 m out (%+.0f m)" % float(g_on["vert"]))
	var t27: Vector3 = thr[1]["pos"]
	var g_s := Airport.guide(Vector3(t27.x + 1000.0, 70.0, t27.z), PI * 0.5, 40.0, 70.0)
	TestLib.check(bool(g_s["on"]) and g_s["rwy"] == "27", "and a westbound one on runway 27")
	TestLib.check(not bool(Airport.guide(Vector3(0.0, 80.0, 0.0), 0.0, 40.0, 80.0)["on"]) and not bool(Airport.guide(Vector3(t09.x - 550.0, 60.0, t09.z), 0.0, 40.0, 60.0)["on"]), "no guide over the city or when flying across the runway")
	# the roster
	for k: StringName in VehicleSpecs.AIRCRAFT_KINDS:
		var sp: Dictionary = VehicleSpecs.SPECS.get(k, {})
		var ok := not sp.is_empty() and bool(sp.get("craft", false)) and VehicleSpecs.cls_of(k) in [&"heli", &"plane"] and VehicleSpecs.name_of(k) != ""
		ok = ok and (sp.has("procedural") or ResourceLoader.exists("res://assets/models/%s.glb" % String(sp["model"])))
		if VehicleSpecs.cls_of(k) == &"plane":
			ok = ok and sp.has("stall") and float(sp["stall"]) < float(sp["max"]) * 0.6 and sp.has("ceil")
		TestLib.check(ok, "%s: craft spec, name, model and flight numbers (%s)" % [k, VehicleSpecs.name_of(k)])
	TestLib.check(VehicleSpecs.AIRCRAFT_KINDS.size() >= 8, "eight aircraft: small plane, jet fighter, airliner, cargo plane, business jet, helicopter, gunship, transport helicopter")
	for k: StringName in [&"gunship", &"hauler", &"jet"]:
		TestLib.check(VehicleWeapons.has_weapon(k), "%s carries guns" % k)
	TestLib.check(VehicleSpecs.ALT_WEAPONS.has(&"gunship") and VehicleSpecs.ALT_WEAPONS.has(&"jet"), "the gunship carries rockets and the jet missiles")
	var pts := VehicleSpawns.all_points()
	var by_kind := {}
	for pt in pts:
		by_kind[pt["kind"]] = int(by_kind.get(pt["kind"], 0)) + 1
	var all_kinds := true
	for k: StringName in VehicleSpecs.AIRCRAFT_KINDS:
		all_kinds = all_kinds and by_kind.has(k)
	TestLib.check(all_kinds, "every aircraft kind has a spawn point (apron, runway, hangar line, pads)")
	# the kit meshes build and stay small
	var tri_ground := BridgeWorld._tri_count(AirportKit.ground())
	var tri_kit := BridgeWorld._tri_count(AirportKit.kit())
	var tri_det := BridgeWorld._tri_count(AirportKit.detail())
	TestLib.check(tri_ground + tri_kit + tri_det > 3000 and tri_ground + tri_kit + tri_det < 40000, "the airport meshes: ground %d, kit %d, detail %d triangles" % [tri_ground, tri_kit, tri_det])
	# the aircraft models
	for kn in ["gunship", "hauler"]:
		var m := AircraftModels.build_air(kn, VehicleSpecs.SPECS[StringName(kn)])
		var body := m.get_node_or_null("Body") as MeshInstance3D
		TestLib.check(body != null and m.get_node_or_null("Rotor") != null and m.get_node_or_null("TailRotor") != null and body.mesh.get_surface_count() >= 3, "the procedural %s has a body, a rotor and a tail rotor" % kn)
		m.free()


# --- the real scene -----------------------------------------------------------------------------------------------------------------------

## Game seconds since the test started (physics frames / ticks per second): independent of the wall clock and of the time scale.
func _gt() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


func _until(cond: Callable, game_secs: float) -> bool:
	var t0 := _gt()
	var w0 := Time.get_ticks_msec()
	while _gt() - t0 < game_secs and float(Time.get_ticks_msec() - w0) / 1000.0 < game_secs * 8.0 + 20.0:
		if cond.call():
			return true
		await _host.get_tree().process_frame
	return cond.call()


func _hold(game_secs: float) -> void:
	var t0 := _gt()
	var w0 := Time.get_ticks_msec()
	while _gt() - t0 < game_secs and float(Time.get_ticks_msec() - w0) / 1000.0 < game_secs * 8.0 + 20.0:
		await _host.get_tree().process_frame


func _release() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"crouch", &"fire", &"aim"]:
		Input.action_release(a)


func _clear() -> void:
	_release()
	if _vm.driven != null:
		_vm.exit_vehicle()
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)
	_vm._spawned.clear()
	_vm._spawn_ready.clear()


func _scene(host: Node) -> void:
	CarRadio.auto_headless = true
	Game.quality = 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_city = Game.world as City
	TestLib.check(_p != null and _vm != null and _city != null, "the real scene has a city, a player and a vehicle manager")
	if _p == null or _vm == null or _city == null:
		main.queue_free()
		CarRadio.auto_headless = false
		return
	_p.set_physics_process(true)
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	_vm.stream_every = 1.0e9
	_vm._stream_t = 1.0e9
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	_live_nodes()
	await _hijack()
	await _plane_flight()
	await _jet_flight()
	await _heli_flight()
	await _pads()
	await _arms()
	_traffic()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_clear()
	CarRadio.auto_headless = false
	main.queue_free()
	await TestLib.frames(host, 2)


func _live_nodes() -> void:
	var aw := AirportWorld.instance
	TestLib.check(aw != null and aw.get_parent() == _city, "the city has an AirportWorld")
	if aw == null:
		return
	var st := aw.stats()
	var meshes := 0
	for n in aw.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	TestLib.check(meshes <= 3 + int(st["pads"]) + 20 and int(st["tris"]) < 40000 and int(st["boxes"]) > 10, "the field is %d meshes (three for the field, one per remote pad, the parked airliners), %d triangles, %d collision boxes" % [meshes, st["tris"], st["boxes"]])
	TestLib.check(int(st["parked"]) >= 3, "airliners and a business jet stand at the gates (%d)" % int(st["parked"]))
	TestLib.check(aw.traffic != null, "the airport owns the air traffic")


## Put the hero next to the spawn point `id`, let the terrain collider stream in and wait for the manager to put the aircraft there.
func _spawn_at(id: StringName) -> Vehicle:
	_clear()
	var pt := VehicleSpawns.point(id)
	if pt.is_empty():
		return null
	var pos: Vector3 = pt["pos"]
	_p.teleport_to(pos + Vector3(9.0, 0.3, 0.0))
	if _city.terrain != null:
		_city.terrain.settle(pos)
	await TestLib.frames(_host, 3)
	_vm._spawn_t = 0.0
	var got := await _until(func() -> bool:
		var v: Variant = _vm._spawned.get(id)
		return is_instance_valid(v) and (v as Vehicle).active, 8.0)
	if not got:
		return null
	var want := _vm._spawned[id] as Vehicle
	for v in _vm.list.duplicate():                                       # the other aircraft of the apron that spawned in the same second take the slots a test needs
		if v != _vm.starter and v != want:
			_vm._release(v)
	_vm._spawn_t = 1.0e9
	return want


func _board(v: Vehicle) -> void:
	_p.teleport_to(v.global_position + v.right() * (float(v.spec["wid"]) * 0.5 + 1.2) + Vector3(0.0, 0.3, 0.0))
	await TestLib.frames(_host, 2)
	_vm.enter(v)
	await TestLib.frames(_host, 2)


func _plane_flight() -> void:
	var plane := await _spawn_at(&"ap_runway")
	TestLib.check(plane != null and plane.kind == &"plane", "the runway has a small plane at the south threshold")
	if plane == null:
		return
	await _board(plane)
	TestLib.check(_vm.driven == plane and absf(plane.global_position.y) < 0.4, "the hero is in the plane on the runway (y %.2f)" % plane.global_position.y)
	var stall := float(plane.spec["stall"])
	var hp0 := plane.hp
	var x0 := plane.global_position.x
	Input.action_press(&"move_forward")
	var fast := await _until(func() -> bool: return plane.speed > stall * 1.05, 30.0)
	TestLib.check(fast and not plane.craft.airborne, "plane: rolls down the runway to takeoff speed (%.0f m/s, stall %.0f, %.0f m of runway used)" % [plane.speed, stall, absf(plane.global_position.x - x0)])
	Input.action_press(&"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(plane) > 40.0, 25.0)
	Input.action_release(&"jump")
	TestLib.check(up and plane.craft.airborne and plane.craft.takeoffs >= 1, "plane: takes off and climbs (%.0f m, pitch %.2f rad)" % [VehicleCraft.altitude(plane), AircraftFlight.air(plane.craft).pitch])
	TestLib.check(plane.hits == 0 and plane.hp >= hp0 - 1.0, "plane: the take-off is clean")
	_release()
	await _hold(1.2)
	# level flight: the pitch comes back to zero by itself, the altitude holds
	var a0 := VehicleCraft.altitude(plane)
	await _hold(2.0)
	TestLib.check(plane.craft.airborne and absf(AircraftFlight.air(plane.craft).pitch) < 0.1 and absf(VehicleCraft.altitude(plane) - a0) < 12.0, "plane: levels out when the buttons are released (pitch %.2f, %.0f -> %.0f m)" % [AircraftFlight.air(plane.craft).pitch, a0, VehicleCraft.altitude(plane)])
	var info := AircraftFlight.info(plane)
	TestLib.check(float(info["speed"]) > stall and float(info["agl"]) > 20.0 and info.has("hint") and info.has("guide"), "flight data for the HUD (speed %.0f, altitude %.0f)" % [float(info["speed"]), float(info["agl"])])
	# a bank turns it: stick right for a second, the heading follows the bank
	var h0 := plane.heading
	Input.action_press(&"move_right")
	await _hold(1.2)
	var rolled := AircraftFlight.air(plane.craft).roll
	Input.action_release(&"move_right")
	TestLib.check(rolled < -0.3 and absf(wrapf(plane.heading - h0, -PI, PI)) > 0.15, "plane: the stick banks it (roll %.2f rad) and the turn follows (%.2f rad)" % [rolled, absf(wrapf(plane.heading - h0, -PI, PI))])
	await _hold(1.5)
	TestLib.check(absf(AircraftFlight.air(plane.craft).roll) < 0.15, "plane: the wings come back level")
	# slow down below the stall: the nose falls and the plane recovers when the throttle comes up
	Input.action_press(&"move_back")
	await _until(func() -> bool: return plane.craft.lever < 0.02, 6.0)
	Input.action_release(&"move_back")
	Input.action_press(&"jump")
	var stalled := await _until(func() -> bool: return AircraftFlight.air(plane.craft).stalled, 40.0)
	Input.action_release(&"jump")
	TestLib.check(stalled and plane.hp >= hp0 - 1.0, "plane: pulling up with no throttle stalls it (%.0f m/s), nothing breaks" % plane.speed)
	Input.action_press(&"move_forward")
	var recovered := await _until(func() -> bool: return not AircraftFlight.air(plane.craft).stalled and plane.craft.airborne, 25.0)
	Input.action_release(&"move_forward")
	TestLib.check(recovered, "plane: a stall recovers by itself with the throttle up (%.0f m/s, altitude %.0f m)" % [plane.speed, VehicleCraft.altitude(plane)])
	# line up on runway 09 from the west and land: put it on the glide path 420 m out, throttle low; a pilot in the test keeps it on the path
	var rwy := Airport.thresholds()[0]
	var t0: Vector3 = rwy["pos"]
	plane.global_position = Vector3(t0.x - 420.0, 34.0, t0.z)
	plane.heading = float(rwy["heading"])
	plane.vel = Vector3(42.0, 0.0, 0.0)
	plane.speed = 42.0
	plane.craft.vy = -2.0
	plane.craft.lever = 0.35
	await _hold(0.3)
	var gd := AircraftFlight.info(plane)["guide"] as Dictionary
	TestLib.check(bool(gd.get("on", false)) and gd["rwy"] == "09" and float(gd["dist"]) > 100.0, "plane: the landing guide is on (RWY %s, %.0f m out, %+.0f m off the glide path)" % [gd.get("rwy", "-"), float(gd.get("dist", 0.0)), float(gd.get("vert", 0.0))])
	var hp1 := plane.hp
	# a pilot in the test: DOWN above the glide path, UP below it, nothing on it (the flare below 8 m is the plane's own)
	var landed := false
	var tl := _gt()
	while _gt() - tl < 60.0 and not landed:
		var gi := AircraftFlight.info(plane)["guide"] as Dictionary
		var ve := float(gi.get("vert", 0.0)) if bool(gi.get("on", false)) else 0.0
		Input.action_release(&"crouch")
		Input.action_release(&"jump")
		if ve > 5.0:
			Input.action_press(&"crouch")
		elif ve < -5.0 and VehicleCraft.altitude(plane) > 12.0:
			Input.action_press(&"jump")
		elif VehicleCraft.altitude(plane) < 9.0:
			Input.action_press(&"crouch")
		await _host.get_tree().process_frame
		landed = not plane.craft.airborne
	_release()
	TestLib.check(landed, "plane: comes down on the runway")
	TestLib.check(plane.hp >= hp1 - 1.0 and plane.craft.hard < VehicleCraft.LAND_SAFE, "plane: a normal landing does no damage (sink %.1f m/s, hp %.0f of %.0f)" % [plane.craft.hard, plane.hp, hp1])
	var on_rwy := absf(plane.global_position.z - t0.z) < Airport.RUNWAY_W * 0.5 + 2.0 and plane.global_position.x > t0.x - 10.0 and plane.global_position.x < t0.x + Airport.RUNWAY_LEN
	Input.action_press(&"move_back")
	var stopped := await _until(func() -> bool: return plane.speed < 4.0, 30.0)
	Input.action_release(&"move_back")
	TestLib.check(stopped and on_rwy, "plane: touches down on the runway (x %.0f z %.0f) and brakes to a stop (%.1f m/s)" % [plane.global_position.x, plane.global_position.z, plane.speed])
	var out := _vm.toggle_enter_exit()
	TestLib.check(out and _vm.driven == null, "plane: the hero gets out on the runway")


func _jet_flight() -> void:
	var jet := await _spawn_at(&"ap_jet_a")
	TestLib.check(jet != null and jet.kind == &"jet", "the hangar line has a jet fighter")
	if jet == null:
		return
	await _board(jet)
	var stall := float(jet.spec["stall"])
	Input.action_press(&"move_forward")
	var jt := Airport.thresholds()[0]
	var jp: Vector3 = jt["pos"]
	jet.global_position = Vector3(jp.x + 20.0, 0.0, jp.z)                                       # on the runway, nose east: the take-off run is the whole strip
	jet.heading = float(jt["heading"])
	jet.vel = Vector3.ZERO
	jet.speed = 0.0
	if _city.terrain != null:
		_city.terrain.settle(jet.global_position)
	await _hold(0.5)
	var t0 := _gt()
	Input.action_press(&"move_forward")
	var fast := await _until(func() -> bool: return jet.speed > stall * 1.08, 30.0)
	TestLib.check(fast and jet.speed < float(jet.spec["max"]) and not jet.craft.airborne, "jet: accelerates hard (%.0f m/s in %.1f s of game time, %.0f m of runway)" % [jet.speed, _gt() - t0, absf(jet.global_position.x - (jp.x + 20.0))])
	Input.action_press(&"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(jet) > 60.0, 25.0)
	TestLib.check(up and jet.craft.airborne, "jet: takes off (%.0f m)" % VehicleCraft.altitude(jet))
	var burner := jet.visual.parts.get("Burner") as Node3D
	TestLib.check(burner != null and burner.visible, "jet: the afterburner shows at full throttle")
	await _until(func() -> bool: return VehicleCraft.altitude(jet) > 220.0, 25.0)
	Input.action_release(&"jump")
	await _hold(3.0)
	TestLib.check(jet.craft.airborne and jet.speed > float(jet.spec["max"]) * 0.6 and jet.hp >= jet.max_hp - 1.0, "jet: reaches speed in the climb (%.0f m/s at %.0f m, hp %.0f)" % [jet.speed, VehicleCraft.altitude(jet), jet.hp])
	_release()
	_clear()


func _heli_flight() -> void:
	var heli := await _spawn_at(&"ap_heli_a")
	TestLib.check(heli != null and heli.kind == &"heli", "the apron helipad has a helicopter")
	if heli == null:
		return
	await _board(heli)
	var hp0 := heli.hp
	Input.action_press(&"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(heli) > 25.0, 30.0)
	Input.action_release(&"jump")
	TestLib.check(up and heli.craft.airborne, "heli: lifts off the pad (%.0f m)" % VehicleCraft.altitude(heli))
	await _hold(1.0)
	var a0 := VehicleCraft.altitude(heli)
	await _hold(2.0)
	TestLib.check(absf(VehicleCraft.altitude(heli) - a0) < 1.5, "heli: hover assist holds the height (%.1f -> %.1f m)" % [a0, VehicleCraft.altitude(heli)])
	var start := heli.global_position
	Input.action_press(&"move_forward")
	var flew := await _until(func() -> bool: return Vector2(heli.global_position.x - start.x, heli.global_position.z - start.z).length() > 60.0, 20.0)
	TestLib.check(flew and AircraftFlight.air(heli.craft).pitch < -0.03, "heli: flies forward with the nose down (%.2f rad)" % AircraftFlight.air(heli.craft).pitch)
	Input.action_release(&"move_forward")
	await _hold(4.0)
	TestLib.check(heli.speed < 3.0, "heli: the drift stops when the stick is released (%.1f m/s)" % heli.speed)
	Input.action_press(&"crouch")
	var landed := await _until(func() -> bool: return not heli.craft.airborne, 40.0)
	Input.action_release(&"crouch")
	TestLib.check(landed and heli.hp >= hp0 - 1.0 and heli.craft.hard < VehicleCraft.LAND_SAFE, "heli: lands softly (sink %.1f m/s, hp %.0f of %.0f)" % [heli.craft.hard, heli.hp, hp0])
	_clear()


## The pictures of the traffic: every kind makes a model with its paint, a helicopter gets its rotor and a blur disc.
func _scenery_models() -> void:
	for k: StringName in VehicleSpecs.AIRCRAFT_KINDS:
		var n := AircraftScenery.make(k, 1)
		TestLib.check(n != null and n.find_children("*", "MeshInstance3D", true, false).size() >= 1, "%s: a scenery model" % k)
		if n != null and VehicleSpecs.cls_of(k) == &"heli":
			var m := n.get_child(0)
			TestLib.check(m.get_node_or_null("Rotor") != null and m.get_node_or_null("RotorDisc") != null, "%s: the scenery helicopter has a rotor and its blur disc" % k)
		if n != null:
			n.queue_free()


## A grounded flight near the hero on foot becomes a real aircraft he can take: the pilot is thrown out, the flight is gone for a while.
func _hijack() -> void:
	_scenery_models()
	_clear()
	var at := AirportWorld.instance.traffic
	var f: AirTraffic.Flight = null
	for fl in at.flights:
		if fl.id == &"heli_a":
			f = fl
	TestLib.check(f != null and f.heli, "the air traffic has a helicopter on a pad")
	if f == null:
		return
	f.hold = 1.0e6
	f.idx = 0
	f.pos = Vector3(f.stand.x, 0.0, f.stand.z)
	f.phase = &"parked"
	f.vehicle = null
	f.gone = 0.0
	var fw := Airport.to_world(f.pos)
	_p.teleport_to(Vector3(fw.x + 14.0, 0.3, fw.z))
	if _city.terrain != null:
		_city.terrain.settle(fw)
	await TestLib.frames(_host, 3)
	var promoted := await _until(func() -> bool: return f.vehicle != null, 8.0)
	TestLib.check(promoted and f.vehicle.kind == &"heli" and f.vehicle.ai, "a parked helicopter near the hero becomes a real aircraft with a pilot (%s)" % (str(f.vehicle.kind) if f.vehicle != null else "none"))
	if f.vehicle == null:
		return
	var v := f.vehicle
	var sw := Airport.to_world(f.stand)
	TestLib.check(absf(v.global_position.x - sw.x) < 1.0 and absf(v.global_position.z - sw.z) < 1.0, "it stands exactly where the flight stood")
	_p.teleport_to(v.global_position + v.right() * 3.4 + Vector3(0.0, 0.3, 0.0))
	await TestLib.frames(_host, 2)
	var hj0 := Hijack.current.hijacks if Hijack.current != null else 0
	var taken := _vm.toggle_enter_exit()
	TestLib.check(taken and _vm.driven == v and not v.ai, "the hero takes the helicopter (ENTER)")
	if Hijack.current != null:
		TestLib.check(Hijack.current.hijacks == hj0 + 1 and Hijack.current.ejected_live() >= 1, "the pilot is thrown out: a hijack (%d)" % Hijack.current.hijacks)
	var gone := await _until(func() -> bool: return f.vehicle == null and f.gone > 0.0, 4.0)
	TestLib.check(gone and at.hijacked >= 1, "the flight is gone for a while (%.0f s)" % f.gone)
	Input.action_press(&"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(v) > 12.0, 25.0)
	Input.action_release(&"jump")
	TestLib.check(up, "the hijacked helicopter flies (%.0f m)" % VehicleCraft.altitude(v))
	Input.action_press(&"crouch")
	await _until(func() -> bool: return not v.craft.airborne, 30.0)
	Input.action_release(&"crouch")
	_clear()
	f.gone = 0.0
	f.hold = 1.0e6


## Helipads: a helicopter waits on the roof pad of the tower and on a mountain pad (flat ground at the pad height), takes off and lands back on it.
func _pads() -> void:
	var roof := Airport.pad(&"pad_roof")
	var heli := await _spawn_at(&"sp_pad_roof")
	TestLib.check(heli != null and heli.kind == &"heli" and absf(heli.global_position.y - (roof["pos"] as Vector3).y) < 1.0, "a helicopter waits on the roof pad (y %.1f)" % (heli.global_position.y if heli != null else -1.0))
	if heli != null:
		await _board(heli)
		Input.action_press(&"jump")
		var up := await _until(func() -> bool: return VehicleCraft.altitude(heli) > 18.0, 30.0)
		Input.action_release(&"jump")
		TestLib.check(up and heli.craft.airborne, "heli: lifts off the roof (%.0f m)" % VehicleCraft.altitude(heli))
		Input.action_press(&"crouch")
		var landed := await _until(func() -> bool: return not heli.craft.airborne, 40.0)
		Input.action_release(&"crouch")
		TestLib.check(landed and heli.global_position.y > (roof["pos"] as Vector3).y - 1.0, "heli: lands on the roof pad again (y %.1f, pad %.1f)" % [heli.global_position.y, (roof["pos"] as Vector3).y])
	var mp := Airport.pad(&"pad_peak")
	var g := await _spawn_at(&"sp_pad_peak")
	TestLib.check(g != null and g.kind == &"gunship" and absf(g.global_position.y - (mp["pos"] as Vector3).y) < 1.5, "a gunship waits on PEAK PAD (y %.1f, pad %.1f)" % [g.global_position.y if g != null else -1.0, (mp["pos"] as Vector3).y])
	if g != null:
		await _board(g)
		Input.action_press(&"jump")
		var up2 := await _until(func() -> bool: return VehicleCraft.altitude(g) > 20.0, 30.0)
		Input.action_release(&"jump")
		TestLib.check(up2, "gunship: lifts off the mountain pad (%.0f m above the ground)" % VehicleCraft.altitude(g))
		Input.action_press(&"crouch")
		var landed2 := await _until(func() -> bool: return not g.craft.airborne, 40.0)
		Input.action_release(&"crouch")
		TestLib.check(landed2 and absf(g.global_position.y - (mp["pos"] as Vector3).y) < 3.0, "gunship: lands back on the pad (y %.1f)" % g.global_position.y)
	_clear()


## The gunship fires rockets that fly and explode, the jet fires missiles that steer to a target.
func _arms() -> void:
	var g := await _spawn_at(&"ap_heli_b")
	TestLib.check(g != null and g.kind == &"gunship" and g.weapons != null and g.weapons.has_alt(), "the apron has a gunship with a rocket pod")
	if g == null:
		return
	await _board(g)
	g.global_position = Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -700.0))                 # on the runway: clear ground ahead
	g.heading = Airport.heading_world(0.0)
	await TestLib.frames(_host, 2)
	var target := _vm.spawn_parked(&"sedan", g.global_position + g.forward() * 70.0, g.heading)
	await TestLib.frames(_host, 2)
	var hp0 := target.hp if target != null else 0.0
	if target != null:
		g.set_meta(&"aim_at", target.global_position + Vector3(0.0, 0.8, 0.0))                  # the crosshair is on the car (the camera of a test has no look input)
	var ammo0 := g.weapons.alt_ammo
	var guns0 := g.weapons.ammo
	Input.action_press(&"aim")
	var fired := await _until(func() -> bool: return g.weapons.alt_shots >= 2, 4.0)
	Input.action_release(&"aim")
	TestLib.check(fired and g.weapons.alt_ammo < ammo0 and AirRockets.instance != null, "gunship: the AIM button fires rockets (%d -> %d)" % [ammo0, g.weapons.alt_ammo])
	var det0 := AirRockets.instance.detonations if AirRockets.instance != null else 0
	var boomed := await _until(func() -> bool: return AirRockets.instance != null and AirRockets.instance.detonations >= 2, 6.0)
	TestLib.check(boomed, "rockets fly and explode (%d detonations)" % (AirRockets.instance.detonations if AirRockets.instance != null else 0))
	if target != null and is_instance_valid(target):
		TestLib.check(target.hp < hp0 - 20.0 or target.dead or target.wreck, "a car 70 m ahead is hit by the salvo (hp %.0f of %.0f)" % [target.hp, hp0])
	Input.action_press(&"fire")
	await _hold(0.8)
	Input.action_release(&"fire")
	TestLib.check(g.weapons.ammo < guns0, "gunship: the chain gun fires too (%d -> %d)" % [guns0, g.weapons.ammo])
	var rows := Hud.new().vehicle_rows(g)
	var has_rocket := false
	for r in rows:
		has_rocket = has_rocket or String(r["text"]).begins_with("ROCKET POD")
	TestLib.check(has_rocket, "the HUD shows the rocket pod and its rounds")
	g.weapons.alt_ammo = 0
	TestLib.check(not g.weapons.can_fire_alt(), "no rockets left: the AIM button does nothing")
	_clear()
	# the jet: missiles that steer to what is in front of the nose
	var jet := await _spawn_at(&"ap_jet_b")
	TestLib.check(jet != null and jet.weapons != null and jet.weapons.has_alt() and float(jet.weapons.alt_def.get("homing", 0.0)) > 0.0, "the jet carries homing missiles")
	if jet != null:
		await _board(jet)
		var tgt := _vm.spawn_parked(&"sedan", jet.global_position + jet.forward() * 120.0, jet.heading)
		TestLib.check(tgt != null, "a target car stands 120 m in front of the jet")
		await TestLib.frames(_host, 2)
		var thp := tgt.hp if tgt != null else 0.0
		if tgt != null:
			jet.set_meta(&"aim_at", tgt.global_position + Vector3(0.0, 0.8, 0.0))
		var m0 := jet.weapons.alt_ammo
		TestLib.check(jet.weapons.fire_alt() and jet.weapons.alt_ammo == m0 - 1, "jet: a missile leaves the rail")
		var boom := await _until(func() -> bool: return AirRockets.instance.live_count() == 0, 6.0)
		TestLib.check(boom and tgt != null and (tgt.hp < thp - 30.0 or tgt.dead or tgt.wreck), "jet: the missile hits the car ahead (hp %.0f of %.0f)" % [tgt.hp if tgt != null else 0.0, thp])
	_clear()


## The air traffic: a plan for every flight, take-offs and landings, patrols, nobody underground or into a mountain.
func _traffic() -> void:
	var at := AirportWorld.instance.traffic
	var kinds := {}
	for f in at.flights:
		kinds[f.kind] = true
	TestLib.check(at.flights.size() >= 6 and kinds.has(&"airliner") and kinds.has(&"bizjet") and kinds.has(&"plane") and kinds.has(&"heli") and kinds.has(&"gunship") and kinds.has(&"hauler"), "the air traffic has airliners, a business jet, a small plane and three helicopters (%d flights)" % at.flights.size())
	for f in at.flights:                                         # nobody is in the middle of a promoted aircraft or a gone flight now: put them all back on their plan
		f.vehicle = null
		f.gone = 0.0
		f.hold = 2.0
	at.fast_forward(600.0)
	var st := at.stats()
	TestLib.check(int(st["takeoffs"]) >= 3 and int(st["landings"]) >= 3, "in ten minutes the planes take off and land (%d take-offs, %d landings)" % [st["takeoffs"], st["landings"]])
	TestLib.check(int(st["laps"]) >= 4, "and the helicopters and planes come back to their pads and stands (%d laps)" % st["laps"])
	TestLib.check(float(st["min_clear"]) > 12.0, "nobody flies lower than 12 m over the ground except on the runway and the pads (%.0f m)" % float(st["min_clear"]))
	var sane := true
	for f in at.flights:
		sane = sane and f.pos.is_finite() and f.pos.y >= 0.0 and f.pos.y < 400.0 and absf(f.pos.x) < 3000.0 and absf(f.pos.z) < 3000.0
	TestLib.check(sane, "every flight is somewhere on the map")
	for f in at.flights:                                         # the routes only use the airport's ground where the data says (a plane taxis on the apron, the taxiway and the runway)
		if f.heli:
			continue
		var okr := true
		for wp: Dictionary in f.route:
			if bool(wp["ground"]):
				var p: Vector3 = wp["p"]
				var pw := Airport.to_world(p)
				okr = okr and Airport.inside(pw.x, pw.z) and p.x < 1300.0
		TestLib.check(okr, "%s: every ground waypoint of its route is on the airport pad" % f.id)
