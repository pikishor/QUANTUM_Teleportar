extends RefCounted
## Cars that stop reading as toys, on a map that takes minutes to cross (round 4, "cars not cartoon, GTA freedom"). In the REAL game scene plus the model contract:
##  * the world: 26 x 26 blocks (2080 m, 2.64x the area of the 1280 m city), chunk streaming of the outer colliders, top speeds so that every vehicle needs more than a minute
##    for the avenue and minutes for the corner-to-corner route;
##  * the Rgsdev CC0 models (assets/models/rv_*.glb): contract (Body + four wheel nodes, nose at -Z, flat colours without textures), size against the spec, triangle cap;
##  * `CarParts` on every built car: generated wheels (tyre, rim, brake disc) of the spec radius, a Glass surface split off the trim, a plate at each end, a headlight beam, the cabin
##    glow of the windows at night (and none by day);
##  * getting in and out: the door swings (`VehicleVisual.door_cycle`), the entry / exit ghost plays, a driver is pulled out of a traffic car (hijack), the radio tunes in on entering
##    (and stays off after the player switched it off);
##  * licence and credits kept with the pack.
## Run: tools/test.sh tests/test_cars_world_scale.gd   (after tools/import.sh; about 40 s; waits on counters and state, never on frame counts)

const RV_KINDS: Array[StringName] = [&"sedan", &"sport", &"compact", &"suv", &"taxi", &"van", &"luxury", &"racer", &"interceptor", &"ambulance", &"bus", &"muscle", &"pickup"]
const CAR_TRIS := 3200
const OLD_MAP := 1280.0


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_scale_and_speeds()
	OS.set_environment("QT_CARS_V2", "0")                  # these two parts test the Rgsdev pack and CarParts, which the older art (the fallback of Cars v2) keeps using; tests/test_cars_v2.gd covers the new set
	_models()
	await _built_cars(host)
	OS.set_environment("QT_CARS_V2", "")
	await _real_scene(host)
	_credits()


# --- the world ---------------------------------------------------------------------------------------------------------------------------------------

func _scale_and_speeds() -> void:
	var side := 2.0 * CityLayout.HALF
	TestLib.check(CityLayout.N == 26 and is_equal_approx(side, 2080.0), "the map is 26 x 26 blocks, 2080 m across")
	TestLib.check(side * side >= 2.5 * OLD_MAP * OLD_MAP, "at least 2.5x the area of the 1280 m city (%.2fx)" % (side * side / (OLD_MAP * OLD_MAP)))
	var slowest_avenue := 1.0e9
	var slowest_route := 1.0e9
	var worst := &""
	var cars_ok := true
	for kind: StringName in VehicleSpecs.SPECS:
		if VehicleSpecs.cls_of(kind) in [&"heli", &"plane"]:         # aircraft (round 5 roster) fly over the streets: the road-time rule is for ground vehicles
			continue
		var top := float(VehicleSpecs.SPECS[kind]["max"])
		var avenue := side / top
		var route := 2.0 * side / top                    # corner to corner on the road grid (the Manhattan distance)
		if avenue < slowest_avenue:
			slowest_avenue = avenue
			worst = kind
		slowest_route = minf(slowest_route, route)
		if VehicleSpecs.cls_of(kind) == &"car":
			cars_ok = cars_ok and top <= 29.0
	TestLib.check(slowest_avenue >= 60.0, "every vehicle needs at least a minute for the avenue at top speed (fastest: %s, %.0f s)" % [worst, slowest_avenue])
	TestLib.check(slowest_route >= 120.0, "every vehicle needs at least two minutes for the corner-to-corner route (%.0f s)" % slowest_route)
	TestLib.check(cars_ok and float(VehicleSpecs.SPECS[&"sedan"]["max"]) <= 24.0, "cars top out under 105 km/h, a sedan under 87 km/h")
	var sedan_route := 2.0 * side / float(VehicleSpecs.SPECS[&"sedan"]["max"])
	TestLib.check(sedan_route >= 170.0, "a sedan needs about three minutes across the whole map (%.0f s)" % sedan_route)


# --- the models ---------------------------------------------------------------------------------------------------------------------------------------

func _tris(mi: MeshInstance3D) -> int:
	var n := 0
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _models() -> void:
	OS.set_environment("QT_OPEN_MODELS", "1")
	OS.set_environment("QT_RV_MODELS", "1")
	for q in [0, 1, 2]:
		Game.quality = q
		var all_first := true
		for kind in RV_KINDS:
			all_first = all_first and VehicleSpecs.model_names(kind)[0] == "rv_" + String(VehicleSpecs.SPECS[kind]["rv"])
		TestLib.check(all_first, "tier %d: every Rgsdev kind tries its rv_ model first" % q)
	Game.quality = 1
	for kind in RV_KINDS:
		var spec: Dictionary = VehicleSpecs.SPECS[kind]
		var model := Game.load_model("rv_" + String(spec["rv"]))
		TestLib.check(model != null, "%s: assets/models/rv_%s.glb loads" % [kind, spec["rv"]])
		if model == null:
			continue
		var body := model.get_node_or_null("Body") as MeshInstance3D
		var wheels := 0
		for n: StringName in VehicleVisual.WHEEL_NAMES:
			wheels += 1 if model.get_node_or_null(NodePath(n)) is MeshInstance3D else 0
		TestLib.check(body != null and wheels == 4, "%s: a Body mesh and four wheel nodes" % kind)
		if body == null:
			model.free()
			continue
		var box := body.get_aabb()
		var ln := float(spec["len"])
		var wd := float(spec["wid"])
		TestLib.check(absf(box.size.z - ln) <= 0.06 * ln and absf(box.size.x - wd) <= 0.1 * wd, "%s: %.2f x %.2f m against the spec %.2f x %.2f" % [kind, box.size.z, box.size.x, ln, wd])
		TestLib.check(_tris(body) <= CAR_TRIS, "%s: %d triangles (cap %d)" % [kind, _tris(body), CAR_TRIS])
		var names: Array[String] = []
		var textured := false
		var head_z := 0.0
		var tail_z := 0.0
		for s in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(s)
			names.append(String(m.resource_name))
			if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
				textured = true
			var arr := body.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cz := 0.0
			for p in v:
				cz += p.z
			cz /= maxf(float(v.size()), 1.0)
			if m.resource_name == "Headlights":
				head_z = cz
			elif m.resource_name == "Taillights":
				tail_z = cz
		TestLib.check("Body" in names and "Glass" in names and "Headlights" in names and "Taillights" in names, "%s: surfaces Body, Glass, Headlights, Taillights (%s)" % [kind, ",".join(names)])
		TestLib.check(not textured, "%s: flat colours, no texture memory" % kind)
		TestLib.check(head_z < -0.5 and tail_z > 0.5, "%s: nose at -Z (headlights z %.2f, taillights z %.2f)" % [kind, head_z, tail_z])
		model.free()


# --- what CarParts adds to every built car -----------------------------------------------------------------------------------------------------------------

func _built_cars(host: Node) -> void:
	Game.quality = 1
	var holder := Node3D.new()
	host.add_child(holder)
	var kinds: Array[StringName] = [&"sedan", &"sport", &"taxi", &"suv", &"interceptor", &"truck", &"muscle"]       # the truck keeps its older art: the parts are on every four-wheeler
	for kind in kinds:
		var vv := VehicleVisual.new()
		var root := vv.build(kind, Color(0.3, 0.9, 1.0))
		holder.add_child(root)
		vv.set_paint(Color(0.56, 0.2, 0.24))
		var spec: Dictionary = VehicleSpecs.SPECS[kind]
		var gen_ok := vv.wheels.size() == 4
		for w in vv.wheels:
			var mi := w as MeshInstance3D
			gen_ok = gen_ok and mi != null and mi.mesh.get_surface_count() == 3 and mi.mesh.surface_get_material(0).resource_name == "Tyre" and mi.mesh.surface_get_material(1).resource_name == "Rim"
			if mi != null:
				var r := mi.mesh.get_aabb().size.y * 0.5
				gen_ok = gen_ok and absf(r - float(spec["wheel"])) <= 0.1 * float(spec["wheel"])
		TestLib.check(gen_ok, "%s: four generated wheels (tyre, rim, brake disc) of the spec radius %.2f" % [kind, float(spec["wheel"])])
		var glass := false
		for s in vv.body.mesh.get_surface_count():
			glass = glass or vv.body.mesh.surface_get_material(s).resource_name == "Glass"
		TestLib.check(glass, "%s: the windows are a Glass surface of their own" % kind)
		TestLib.check(vv.plates.size() == 2 and vv.plates[0].visibility_range_end > 10.0 and vv.plates[0].material_override != null, "%s: a plate at each end" % kind)
		TestLib.check(vv._beams != null and vv._beams.mesh != null and vv._beams.mesh.get_surface_count() == 1, "%s: a headlight beam" % kind)
		vv.set_lights(1.0, 1.0, 1.0)
		var night_glow := vv._glass_mat.emission_energy_multiplier if vv._glass_mat != null else 0.0
		vv.set_lights(0.1, 0.1, 0.1)
		var day_glow := vv._glass_mat.emission_energy_multiplier if vv._glass_mat != null else 0.0
		TestLib.check(night_glow > 0.01 and day_glow < 0.001, "%s: the cabin glows behind the glass at night, not by day (%.3f / %.3f)" % [kind, night_glow, day_glow])
		TestLib.check(vv.wheel_radius > 0.2, "%s: wheel radius %.2f" % [kind, vv.wheel_radius])
	# the plate textures are generated, distinct and small
	var distinct := {}
	for v in CarParts.PLATE_VARIANTS:
		distinct[hash(CarParts.plate_texture(v).get_image().get_data())] = true
	TestLib.check(distinct.size() == CarParts.PLATE_VARIANTS, "%d distinct generated plate textures" % distinct.size())
	var wm := CarParts.wheel_mesh(0.35, 0.22)
	TestLib.check(wm == CarParts.wheel_mesh(0.35, 0.22) and wm.get_aabb().size.y > 0.69 and wm.get_aabb().size.y < 0.71, "the wheel mesh is cached and 0.70 m across")
	var split := CarParts.split_indices(PackedVector3Array([Vector3(0, 0.1, 0), Vector3(1, 0.1, 0), Vector3(0, 0.2, 0), Vector3(0, 1.0, 0), Vector3(1, 1.0, 0), Vector3(0, 1.1, 0)]), PackedInt32Array([0, 1, 2, 3, 4, 5]), 0.7)
	TestLib.check((split[0] as PackedInt32Array).size() == 3 and (split[1] as PackedInt32Array).size() == 3, "windows (above the belt line) are told apart from bumpers and trim")
	holder.queue_free()
	await TestLib.frames(host, 2)


# --- getting in and out, in the real scene -----------------------------------------------------------------------------------------------------------------

func _real_scene(host: Node) -> void:
	CarRadio.auto_headless = true
	CarRadio.last_station = 2
	Game.quality = 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	var mgr := Game.vehicles as VehicleManager
	var city := Game.world as City
	TestLib.check(p != null and mgr != null and city != null and Hijack.current != null, "the real scene has a city, a player, a vehicle manager and the hijack layer")
	if p == null or mgr == null or city == null or Hijack.current == null:
		CarRadio.auto_headless = false
		main.queue_free()
		return
	p.set_physics_process(true)
	TestLib.check(city.collision_chunks().block_total() >= 560, "the colliders of the outer blocks are streamed in chunks (%d blocks)" % city.collision_chunks().block_total())
	mgr.stream_every = 1.0e9
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)
	# 1. the radio tunes in on entering, at the last station
	var car := mgr.spawn_parked(&"sedan", Vector3(-30.0, 0.0, 9.0), -PI * 0.5)
	TestLib.check(car != null, "a parked sedan stands on the avenue")
	if car == null:
		CarRadio.auto_headless = false
		main.queue_free()
		return
	car.update_lod(0.0)
	p.teleport_to(car.global_position + car.right() * 2.4)
	await TestLib.frames(host, 3)
	var hj := Hijack.current
	var doors0 := car.visual.door_cycles
	var entries0 := hj.entries
	mgr.radio.on = false
	mgr.radio.muted_by_player = false
	mgr.enter(car)
	TestLib.check(mgr.driven == car, "the hero gets in")
	TestLib.check(car.visual.door_cycles == doors0 + 1 and hj.entries == entries0 + 1, "the door swings and the entry ghost plays (doors %d, entries %d)" % [car.visual.door_cycles, hj.entries])
	TestLib.check(mgr.radio.on and mgr.radio.station == 2, "the radio tunes in on entering, at the last station (on %s, station %d)" % [str(mgr.radio.on), mgr.radio.station])
	# the door really opens and shuts again
	var opened := await _until(host, func() -> bool: return car.visual._door != null and car.visual._door.visible and absf(car.visual._door.rotation.y) > 0.5, 3.0)
	TestLib.check(opened, "the door panel swings out")
	var shut := await _until(host, func() -> bool: return car.visual._door != null and not car.visual._door.visible, 5.0)
	TestLib.check(shut, "and shuts again")
	# 2. getting out: the door, the ghost, the hero beside the car
	var exits0 := hj.exits
	var doors1 := car.visual.door_cycles
	mgr.exit_vehicle()
	TestLib.check(mgr.driven == null and hj.exits == exits0 + 1 and car.visual.door_cycles == doors1 + 1, "getting out plays the door and the exit ghost (exits %d)" % hj.exits)
	TestLib.check(p.global_position.distance_to(car.global_position) < 6.0 and p.global_position.distance_to(car.global_position) > 1.2, "the hero lands beside the car (%.1f m)" % p.global_position.distance_to(car.global_position))
	# 3. the radio stays off once the hero switched it off, and tunes in again after he turned it on
	var guard := 0
	while mgr.radio.on and guard < 8:                  # V / the RADIO button: through the stations to OFF
		mgr.radio.cycle()
		guard += 1
	TestLib.check(not mgr.radio.on and mgr.radio.muted_by_player, "the hero cycles the radio to OFF")
	p.teleport_to(car.global_position + car.right() * 2.4)
	mgr.enter(car)
	TestLib.check(not mgr.radio.on, "entering again does not switch a radio the hero turned off back on")
	mgr.exit_vehicle()
	# 4. hijack: a traffic car with a driver, the driver is pulled out
	for v in mgr.list.duplicate():
		if v != mgr.starter and v != car:
			mgr._release(v)
	var traffic := mgr.spawn_traffic(&"taxi", 0, 8, 1, 40.0)
	if traffic != null:
		traffic.global_position = Vector3(40.0, 0.0, 5.0)
		traffic.ai_speed = 0.0
		traffic.ai_stun = 3.0
		p.teleport_to(traffic.global_position + traffic.right() * 2.4)
		await TestLib.frames(host, 2)
		var jacked0 := hj.hijacks
		var heat0 := Game.heat
		mgr.enter(traffic)
		TestLib.check(mgr.driven == traffic and hj.hijacks == jacked0 + 1, "a traffic car with a driver is hijacked: the driver is thrown out (%d)" % hj.hijacks)
		TestLib.check(Game.heat >= heat0, "and it costs heat")
		mgr.exit_vehicle()
	else:
		TestLib.check(false, "a traffic taxi spawns")
	CarRadio.auto_headless = false
	CarRadio.last_station = 0
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _until(host: Node, cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if cond.call():
			return true
		await host.get_tree().process_frame
	return cond.call()


func _credits() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var base := root.path_join("art_sources/rgsdev_vehicles")
	if not DirAccess.dir_exists_absolute(base):
		return                                                # an export without the repository
	TestLib.check(FileAccess.file_exists(base.path_join("SOURCE.md")) and FileAccess.file_exists(base.path_join("License.txt")), "art_sources/rgsdev_vehicles keeps the licence and SOURCE.md")
	TestLib.check(FileAccess.get_file_as_string(base.path_join("License.txt")).contains("CC0"), "the licence text says CC0")
	var tp := root.path_join("docs/THIRD_PARTY.md")
	if FileAccess.file_exists(tp):
		TestLib.check(FileAccess.get_file_as_string(tp).contains("Rgsdev"), "docs/THIRD_PARTY.md credits the Rgsdev vehicles pack")
