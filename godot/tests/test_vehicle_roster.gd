extends RefCounted
## The vehicle roster (docs/DESIGN.md, GTA types): compact, sedan, sports, muscle, SUV, van, pickup, bus, taxi, police car, ambulance, fire truck, armoured truck, motorbike, quad, scooter,
## HELICOPTER, small PLANE, BOAT, TANK and the hover bike. In the REAL game scene each one is entered, driven (or flown, floated, rolled on tracks) for a few seconds and left again;
## the helicopter, the plane, the boats and the tank also come from their spawn points (VehicleSpawns), the aircraft take off, hover and land without a scratch, the boat floats and stays
## in the flooded quarter, the tank turns on the spot, aims the turret at the crosshair and fires. Plus the data contract: spec, model, picture, name, touch words and HUD rows.
## Run: tools/test.sh tests/test_vehicle_roster.gd   (after tools/import.sh; waits on state and counters, never on frame counts)

const TIMEOUT_SECONDS := 140.0
const Fixture := preload("res://tests/player_fixture.gd")
const GROUND: Array[StringName] = [&"compact", &"sedan", &"sport", &"muscle", &"suv", &"van", &"pickup", &"bus", &"taxi", &"interceptor", &"ambulance", &"firetruck", &"armoured", &"bike", &"quad", &"scooter", &"hoverbike"]
const REQUIRED: Array[StringName] = [&"compact", &"sedan", &"sport", &"muscle", &"suv", &"van", &"pickup", &"bus", &"taxi", &"interceptor", &"ambulance", &"firetruck", &"armoured", &"bike", &"quad", &"scooter",
	&"heli", &"plane", &"boat", &"tank", &"hoverbike"]

var _p: Player
var _vm: VehicleManager
var _host: Node


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_data()
	await _scene(host)


# --- data ------------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var ok := true
	var missing := []
	for k in REQUIRED:
		if not VehicleSpecs.SPECS.has(k) or not k in VehicleSpecs.ROSTER:
			ok = false
			missing.append(k)
	TestLib.check(ok, "every GTA vehicle type of the brief has a spec and is in the roster %s" % str(missing))
	var pics := true
	var names := true
	var models := true
	for k in REQUIRED:
		pics = pics and ResourceLoader.exists("res://assets/icons/v_%s.png" % k)
		names = names and VehicleSpecs.name_of(k) != "" and VehicleSpecs.NAMES.has(k)
		var spec: Dictionary = VehicleSpecs.SPECS[k]
		models = models and (VehicleSpecs.available_model(k) != "" or spec.has("procedural") or spec.has("shape") or VehicleSpecs.cls_of(k) in [&"car", &"bike", &"hover"])
	TestLib.check(pics, "each roster vehicle has a picture (assets/icons/v_<kind>.png)")
	TestLib.check(names, "each has a plain display name")
	TestLib.check(models, "each has an art model or a procedural body")
	for k: StringName in [&"heli", &"plane", &"boat", &"tank"]:
		TestLib.check(ResourceLoader.exists("res://assets/models/xv_%s.glb" % ("heli" if k == &"heli" else String(k))), "open-source model for the %s is converted" % k)
	var weapons := true
	for k: StringName in VehicleSpecs.CRAFT_KINDS:
		weapons = weapons and VehicleWeapons.has_weapon(k)
	TestLib.check(weapons, "the helicopter, plane, boat and tank carry a mounted weapon")
	TestLib.check(VehicleSpecs.STREAM_KINDS.size() == VehicleSpecs.STREAM_WEIGHTS.size(), "one spawn weight per streamed kind")
	for k: StringName in [&"armoured", &"quad", &"scooter"]:
		TestLib.check(k in VehicleSpecs.STREAM_KINDS, "%s is rare street traffic" % k)
	TestLib.check(VehicleSpawns.POINTS.size() >= 6 and VehicleSpawns.nearest_of(&"boat", FloodZone.center()) != Vector3.INF, "heli pad, airstrip, army depot and boat slips have spawn points")
	var in_flood := true
	for p in VehicleSpawns.POINTS:
		if p["kind"] == &"boat":
			var pos: Vector3 = p["pos"]
			in_flood = in_flood and FloodZone.contains(pos.x, pos.z, 8.0)
	TestLib.check(in_flood, "every boat spawn point is inside the flooded quarter")


# --- the real scene ----------------------------------------------------------------------------------------------------------------------------

func _scene(host: Node) -> void:
	CarRadio.auto_headless = true
	Game.quality = 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	var city := Game.world as City
	TestLib.check(_p != null and _vm != null and city != null, "the real scene has a city, a player and a vehicle manager")
	if _p == null or _vm == null or city == null:
		CarRadio.auto_headless = false
		main.queue_free()
		return
	_p.set_physics_process(true)
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	(Game.enemies as EnemyManager).clear()
	_vm.stream_every = 1.0e9
	_vm._stream_t = 1.0e9
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)
	if NearTraffic.instance != null:                      # no street traffic: the strip and the avenue are clear for the plane and the ground tests
		TrafficField.bare_street()                         # (wave 112 critic: NearTraffic is a RefCounted since wave 111, `process_mode` on it was a script error on every run)
		for i in NearTraffic.instance.count:
			NearTraffic.instance._alive[i] = 0
	Engine.time_scale = 2.0
	# 1. the ground vehicles
	for k in GROUND:
		await _ground(k)
	# 2. the flooded quarter and the boat
	await _boat()
	# 3. the tank
	await _tank()
	# 4. the helicopter and the plane
	await _heli()
	await _plane()
	Engine.time_scale = 1.0
	Fixture.release_inputs()
	# 5. touch words and HUD rows
	_words()
	CarRadio.auto_headless = false
	main.queue_free()
	await TestLib.frames(host, 2)


func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if cond.call():
			return true
		await _host.get_tree().process_frame
	return cond.call()


func _hold(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await _host.get_tree().process_frame


func _clear_world() -> void:
	Fixture.release_inputs()
	Input.action_release(&"crouch")
	if _vm.driven != null:
		_vm.exit_vehicle()
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)


func _ground(kind: StringName) -> void:
	_clear_world()
	var pos := Vector3(-120.0, 0.0, 8.3)
	var car := _vm.spawn_parked(kind, pos, -PI * 0.5)
	TestLib.check(car != null, "%s: spawned on the avenue" % kind)
	if car == null:
		return
	car.update_lod(0.0)
	_p.teleport_to(car.global_position + car.right() * 2.4)
	await TestLib.frames(_host, 2)
	_vm.enter(car)
	var in_car := _vm.driven == car and _p.vehicle == car
	var start := car.global_position
	Input.action_press(&"move_forward")
	var moved := await _until(func() -> bool: return Vector2(car.global_position.x - start.x, car.global_position.z - start.z).length() > 7.0, 12.0)
	Input.action_release(&"move_forward")
	var hp_ok := car.hp > car.max_hp * 0.8
	var out := _vm.toggle_enter_exit()
	await TestLib.frames(_host, 2)
	TestLib.check(in_car and moved and hp_ok and out and _vm.driven == null and _p.vehicle == null, "%s: enter, drive %.0f m, exit (in %s, moved %s, hp %.0f of %.0f, out %s)" % [
			kind, Vector2(car.global_position.x - start.x, car.global_position.z - start.z).length(), str(in_car), str(moved), car.hp, car.max_hp, str(out)])


func _spawn_at_point(id: StringName) -> Vehicle:
	_clear_world()
	var pt := VehicleSpawns.point(id)
	var pos: Vector3 = pt["pos"]
	_vm._spawned.clear()
	_vm._spawn_ready.clear()
	_p.teleport_to(pos + Vector3(7.0, 0.1, 0.0))
	await TestLib.frames(_host, 2)
	_vm._spawn_t = 0.0
	var got := await _until(func() -> bool:
		var v: Variant = _vm._spawned.get(id)
		return is_instance_valid(v) and (v as Vehicle).active, 6.0)
	if not got:
		return null
	return _vm._spawned[id] as Vehicle


func _boat() -> void:
	var boat := await _spawn_at_point(&"harbour_a")
	TestLib.check(boat != null and boat.kind == &"boat", "the boat slip puts a speedboat on the water when the player comes near")
	if boat == null:
		return
	var floats := absf(boat.global_position.y - boat.base_y) < 0.2 and boat.base_y > 0.0 and boat.global_position.y < FloodZone.LEVEL + 0.4
	TestLib.check(floats, "it floats at the flood level (y %.2f, water %.2f)" % [boat.global_position.y, FloodZone.LEVEL])
	_p.teleport_to(boat.global_position + boat.right() * 2.2 + Vector3(0.0, 0.1, 0.0))
	await TestLib.frames(_host, 2)
	_vm.enter(boat)
	var start := boat.global_position
	Input.action_press(&"move_forward")
	var moved := await _until(func() -> bool: return Vector2(boat.global_position.x - start.x, boat.global_position.z - start.z).length() > 25.0 and boat.speed > 8.0, 14.0)
	Input.action_press(&"move_right")
	var h0 := boat.heading
	await _hold(0.8)
	Input.action_release(&"move_right")
	var turned := absf(wrapf(boat.heading - h0, -PI, PI)) > 0.15
	var inside := FloodZone.contains(boat.global_position.x, boat.global_position.z)
	var level := absf(boat.global_position.y - boat.base_y) < 0.3
	Input.action_release(&"move_forward")
	TestLib.check(moved and turned and inside and level, "boat: drives %.0f m at %.0f m/s, turns, stays on the water (moved %s, turned %s, inside %s, level %s)" % [
			Vector2(boat.global_position.x - start.x, boat.global_position.z - start.z).length(), boat.speed, str(moved), str(turned), str(inside), str(level)])
	# driven at the shore it stays in the quarter
	boat.global_position = Vector3(FloodZone.RECT.end.x - 6.0, boat.global_position.y, boat.global_position.z)
	boat.heading = -PI * 0.5
	boat.rotation.y = boat.heading
	boat._heading_set = boat.heading
	boat.vel = boat.forward() * 20.0
	Input.action_press(&"move_forward")
	await _hold(1.5)
	Input.action_release(&"move_forward")
	TestLib.check(FloodZone.contains(boat.global_position.x, boat.global_position.z), "the boat is kept in the water at the edge of the quarter")
	var out := _vm.toggle_enter_exit()
	TestLib.check(out and _vm.driven == null, "boat: exit")


func _tank() -> void:
	var tank := await _spawn_at_point(&"depot")
	TestLib.check(tank != null and tank.kind == &"tank", "the army depot has a tank")
	if tank == null:
		return
	_p.teleport_to(tank.global_position + tank.right() * 3.0 + Vector3(0.0, 0.1, 0.0))
	await TestLib.frames(_host, 2)
	_vm.enter(tank)
	var start := tank.global_position
	var h0 := tank.heading
	Input.action_press(&"move_left")
	await _hold(1.0)
	Input.action_release(&"move_left")
	var spin := absf(wrapf(tank.heading - h0, -PI, PI))
	var stayed := Vector2(tank.global_position.x - start.x, tank.global_position.z - start.z).length()
	TestLib.check(spin > 0.5 and stayed < 1.0, "tank: turns on the spot (%.2f rad, %.2f m)" % [spin, stayed])
	Input.action_press(&"move_forward")
	var moved := await _until(func() -> bool: return Vector2(tank.global_position.x - start.x, tank.global_position.z - start.z).length() > 8.0, 14.0)
	Input.action_release(&"move_forward")
	TestLib.check(moved and tank.speed > 0.5 or moved, "tank: rolls %.0f m" % Vector2(tank.global_position.x - start.x, tank.global_position.z - start.z).length())
	# the turret follows the aim point and the cannon fires at it
	var aim := tank.global_position + Vector3(-60.0, 2.0, 0.0)
	tank.set_meta(&"aim_at", aim)
	var want := atan2(-(aim.x - tank.global_position.x), -(aim.z - tank.global_position.z))
	var aimed := await _until(func() -> bool: return absf(wrapf(tank.craft.turret_yaw - want, -PI, PI)) < 0.08, 10.0)
	TestLib.check(aimed, "tank: the turret slews to the aim point (off by %.2f rad)" % absf(wrapf(tank.craft.turret_yaw - want, -PI, PI)))
	var ammo0 := tank.weapons.ammo
	Input.action_press(&"fire")
	var fired := await _until(func() -> bool: return tank.weapons.ammo < ammo0, 5.0)
	Input.action_release(&"fire")
	TestLib.check(fired, "tank: the cannon fires (%d -> %d shells)" % [ammo0, tank.weapons.ammo])
	tank.remove_meta(&"aim_at")
	var out := _vm.toggle_enter_exit()
	TestLib.check(out and _vm.driven == null, "tank: exit")


func _heli() -> void:
	var heli := await _spawn_at_point(&"heli_pad")
	TestLib.check(heli != null and heli.kind == &"heli", "the helipad has a helicopter")
	if heli == null:
		return
	# fly it from a quiet outer crossing: low blocks all round
	var home := Vector3(800.0, 0.0, 800.0)
	heli.global_position = home
	_p.teleport_to(home + Vector3(5.0, 0.1, 0.0))
	await TestLib.frames(_host, 2)
	_vm.enter(heli)
	TestLib.check(_vm.driven == heli, "heli: the hero takes the controls")
	var hp0 := heli.hp
	# not yet in the air: no lift before the rotor is up, and getting out is fine on the ground
	Input.action_press(&"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(heli) > 30.0, 25.0)
	Input.action_release(&"jump")
	TestLib.check(up and heli.craft.airborne, "heli: lifts off and climbs (%.0f m)" % VehicleCraft.altitude(heli))
	var refused := _vm.toggle_enter_exit()
	TestLib.check(refused and _vm.driven == heli, "heli: LAND TO GET OUT: the door stays shut in the air")
	# hover: no input, the altitude holds
	await _hold(0.6)
	var a0 := VehicleCraft.altitude(heli)
	await _hold(1.2)
	TestLib.check(absf(VehicleCraft.altitude(heli) - a0) < 1.5 and heli.craft.airborne, "heli: hovers when the stick is left alone (%.1f -> %.1f m)" % [a0, VehicleCraft.altitude(heli)])
	var start := heli.global_position
	Input.action_press(&"move_forward")
	var flew := await _until(func() -> bool: return Vector2(heli.global_position.x - start.x, heli.global_position.z - start.z).length() > 40.0, 14.0)
	var h0 := heli.heading
	Input.action_press(&"move_right")
	await _hold(0.8)
	Input.action_release(&"move_right")
	Input.action_release(&"move_forward")
	TestLib.check(flew and absf(wrapf(heli.heading - h0, -PI, PI)) > 0.2, "heli: flies forward and yaws (%.0f m)" % Vector2(heli.global_position.x - start.x, heli.global_position.z - start.z).length())
	# land: hold DOWN until the skids touch, the flare makes it soft
	Input.action_press(&"crouch")
	var landed := await _until(func() -> bool: return not heli.craft.airborne, 30.0)
	Input.action_release(&"crouch")
	TestLib.check(landed, "heli: descends and lands")
	TestLib.check(heli.hp >= hp0 - 1.0 and heli.craft.hard < VehicleCraft.LAND_SAFE, "heli: a normal landing does no damage (sink %.1f m/s, hp %.0f of %.0f)" % [heli.craft.hard, heli.hp, hp0])
	await _until(func() -> bool: return VehicleCraft.can_exit(heli), 6.0)
	var out := _vm.toggle_enter_exit()
	TestLib.check(out and _vm.driven == null and _p.vehicle == null, "heli: the hero gets out on the ground (airborne %s, speed %.1f, agl %.1f, y %.1f)" % [str(heli.craft.airborne), heli.speed, heli.craft.agl, heli.global_position.y])

func _plane() -> void:
	var plane := await _spawn_at_point(&"airstrip")
	TestLib.check(plane != null and plane.kind == &"plane", "the airstrip has a small plane")
	if plane == null:
		return
	_p.teleport_to(plane.global_position + plane.right() * 3.5 + Vector3(0.0, 0.1, 0.0))
	await TestLib.frames(_host, 2)
	_vm.enter(plane)
	var hp0 := plane.hp
	var stall := float(plane.spec["stall"])
	# throttle up (stick forward): it accelerates down the road; UP once it is fast enough
	Input.action_press(&"move_forward")
	var fast := await _until(func() -> bool: return plane.speed > stall * 0.95, 20.0)
	TestLib.check(fast and not plane.craft.airborne, "plane: rolls down the strip to takeoff speed (%.0f m/s, stall %.0f)" % [plane.speed, stall])
	Input.action_press(&"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(plane) > 14.0, 15.0)
	await _until(func() -> bool: return VehicleCraft.altitude(plane) > 52.0, 15.0)      # above every roof of the outer blocks before it turns
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")                                                      # throttle lever back to zero: it slows down for the turn and the landing
	await _until(func() -> bool: return plane.craft.lever < 0.05, 6.0)
	Input.action_release(&"move_back")
	TestLib.check(up and plane.craft.airborne and plane.craft.takeoffs >= 1, "plane: takes off and climbs (%.0f m)" % VehicleCraft.altitude(plane))
	TestLib.check(plane.hits == 0, "plane: the climb out is clear of the buildings")
	var no_exit := _vm.toggle_enter_exit()
	TestLib.check(no_exit and _vm.driven == plane, "plane: cannot be left in the air")
	await _hold(1.0)
	TestLib.check(plane.craft.airborne and plane.speed > stall * 0.7, "plane: keeps flying level at speed (%.0f m/s)" % plane.speed)
	# turn (and back again: the strip is the only clear ground)
	var h0 := plane.heading
	Input.action_press(&"move_left")
	await _hold(0.2)
	Input.action_release(&"move_left")
	var bank := absf(wrapf(plane.heading - h0, -PI, PI))
	Input.action_press(&"move_right")
	await _until(func() -> bool: return absf(wrapf(plane.heading - h0, -PI, PI)) < 0.03, 4.0)
	Input.action_release(&"move_right")
	TestLib.check(bank > 0.15, "plane: banks into a turn (%.2f rad)" % bank)
	# descend (DOWN) and brake on the ground
	Input.action_press(&"crouch")
	var landed := await _until(func() -> bool:
		return not plane.craft.airborne, 40.0)
	Input.action_release(&"crouch")
	TestLib.check(landed, "plane: comes back down")
	Input.action_press(&"move_back")
	var slow := await _until(func() -> bool:
		return plane.speed < 8.0, 20.0)
	Input.action_release(&"move_back")
	TestLib.check(slow and plane.hp >= hp0 * 0.8, "plane: lands and brakes to a stop without wrecking (%.0f m/s, hp %.0f of %.0f, hard %.1f, hits %d, landings %d)" % [plane.speed, plane.hp, hp0, plane.craft.hard, plane.hits, plane.craft.landings])
	var out := _vm.toggle_enter_exit()
	TestLib.check(out and _vm.driven == null and _p.vehicle == null, "plane: the hero gets out")


# --- the words -------------------------------------------------------------------------------------------------------------------------------

func _words() -> void:
	var tc := TouchControls.new()
	var heli := Vehicle.new()
	_host.add_child(heli)
	heli.setup(&"heli", null)
	heli.activate(Vector3(0.0, 0.0, 0.0), 0.0)
	var hud := Hud.new()
	var rows := hud.vehicle_rows(heli)
	TestLib.check(rows.size() >= 1 and String(rows[0]["text"]).begins_with("ALT"), "the HUD readout of a helicopter starts with the altitude (%s)" % str(rows))
	heli.craft.airborne = true
	var plane := Vehicle.new()
	_host.add_child(plane)
	plane.setup(&"plane", null)
	plane.activate(Vector3(0.0, 0.0, 0.0), 0.0)
	var prow := hud.vehicle_rows(plane)
	TestLib.check(prow.size() >= 2 and String(prow[0]["text"]).contains("THROTTLE"), "the plane readout shows the throttle and a hint (%s)" % str(prow))
	var tank := Vehicle.new()
	_host.add_child(tank)
	tank.setup(&"tank", null)
	tank.activate(Vector3.ZERO, 0.0)
	var trow := hud.vehicle_rows(tank)
	TestLib.check(trow.size() == 1 and String(trow[0]["text"]).contains("TANK CANNON"), "the tank readout names the cannon and its shells (%s)" % str(trow))
	for v in [heli, plane, tank]:
		v.queue_free()
	hud.queue_free()
	tc.queue_free()
