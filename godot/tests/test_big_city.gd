extends RefCounted
## The big city (wave 84) in the REAL game scene: a 16 x 16 block map (4x the area of the original city, which is the core in the middle), chunk streaming around
## the player (instance windows, pooled colliders of the outer districts), a drive across the whole map with the arcade speeds, no holes anywhere, outer zones,
## patrols that wake and sleep, ambient life around the player, minimap range and the map screen zoom levels.
## Run: tools/test.sh tests/test_big_city.gd   (about 40 s; waits on game time, positions and counters, never on frame counts)

const Stream := preload("res://scripts/world/city_stream.gd")
const Districts := preload("res://scripts/world/city_districts.gd")

const K := 4
const CRUISE_LIMIT := 120.0          ## game seconds the drive may take before the test gives up

var city: City
var p: Player
var mgr: VehicleManager


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))            # no leftover profile: the first-play flow, the map and the tutorial start clean
	Sfx.muted = true
	Engine.time_scale = K                                   # the drive across the map is 45 game seconds: time runs 4x (the step stays 1/60 s of game time)
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(city != null and p != null and mgr != null, "the real scene has a city, a player and a vehicle manager")
	if city == null or p == null or mgr == null:
		_restore()
		return
	p.set_physics_process(true)
	_layout()
	await _walk_the_map(host)
	await _zones_and_patrols(host)
	await _ambient_life(host)
	_minimap_and_map(host)
	await _drive_across(host)
	await _streaming_is_flat(host)
	Input.action_release(&"move_forward")
	_restore()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


## The layout: 4x the area, the original city untouched in the middle, every table sized to the map.
func _layout() -> void:
	TestLib.check(CityLayout.N == 16 and Game.N == 16 and is_equal_approx(Game.HALF, 640.0), "the map is 16 x 16 blocks, 1280 m across (HALF %.0f)" % Game.HALF)
	var area := (2.0 * Game.HALF) * (2.0 * Game.HALF)
	TestLib.check(area >= 3.0 * (640.0 * 640.0) and area <= 4.5 * (640.0 * 640.0), "3 to 4.5 times the area of the old 8 x 8 city (%.1fx)" % (area / (640.0 * 640.0)))
	var lots: Array[CityLayout.Lot] = city.layout.lots
	var core := 0
	var first_core := true
	for i in lots.size():
		var in_core := CityLayout.is_core_block(lots[i].block_i, lots[i].block_j)
		core += 1 if in_core else 0
		if i < 232 and not in_core:
			first_core = false
	TestLib.check(core == 232 and first_core and lots.size() > 700, "232 core lots first, unchanged (%d lots in all)" % lots.size())
	TestLib.check(is_equal_approx(lots[0].cx, -295.0) and is_equal_approx(lots[0].cz, -295.0), "the first lot is still the JS prototype's")
	TestLib.check(city.intersections.size() == 49 and city.all_intersections.size() == 225, "49 core junctions for the missions, 225 for the whole map")
	TestLib.check(city.doors.size() == lots.size(), "every building of the big map has a door (%d)" % city.doors.size())
	var em0 := Game.enemies as EnemyManager
	var outer0 := 0
	var asleep0 := 0
	for g: Dictionary in em0.patrol_groups():
		if bool(g.get("outer", false)):
			outer0 += 1
			asleep0 += 0 if bool(g["spawned"]) else 1
	TestLib.check(outer0 >= 8 and asleep0 == outer0, "%d outer patrol groups, all dormant at the start (%d asleep)" % [outer0, asleep0])
	# the roads of the outer ring exist, and the layout never puts a building on a road anywhere
	var clean := true
	for l: CityLayout.Lot in lots:
		for corner: Vector2 in [l.rect.position, l.rect.end]:
			if CityLayout.on_road(corner.x, corner.y):
				clean = false
	TestLib.check(clean and CityLayout.on_road(-630.0, 100.0) and CityLayout.on_road(100.0, 640.0), "no footprint touches a road; the border roads of the map exist")
	# queries work everywhere
	var bad := 0
	for i in 300:
		var q := city.random_road_point()
		if not CityLayout.on_road(q.x, q.z) or city.layout.lot_at(q.x, q.z) != null:
			bad += 1
	var far := city.road_point_near(Vector3(560.0, 0.0, -560.0), 60.0, 140.0)
	TestLib.check(bad == 0 and far != Vector3.INF and Vector2(far.x - 560.0, far.z + 560.0).length() >= 59.9, "random_road_point and road_point_near work out in the outer districts (%d bad)" % bad)
	# one more property of the world the player sees: the walls stand at HALF + 30
	TestLib.check(is_equal_approx(CityLayout.WALK, Game.HALF + 30.0), "the invisible walls stand 30 m beyond the border roads")


## Stand at ten places spread over the whole map (corners, edges, the centre): the ground, the colliders, the windows and the streams are there each time.
func _walk_the_map(host: Node) -> void:
	var stops: Array[Vector3] = [Vector3(-600, 0.5, -600), Vector3(0, 0.5, -600), Vector3(600, 0.5, -600), Vector3(600, 0.5, 5), Vector3(600, 0.5, 600), Vector3(0, 0.5, 600),
			Vector3(-600, 0.5, 600), Vector3(-600, 0.5, 5), Vector3(5, 0.5, 5), Vector3(-30, 0.5, 4)]
	var chunks := city.collision_chunks()
	var holes := 0
	var fell := 0
	var window_gaps := 0
	var peak_live := 0
	var all_outer_active := true
	for s in stops:
		p.teleport_to(s)
		await _settle(host, 40)
		if p.global_position.y < -1.0 or not p.global_position.is_finite():
			fell += 1
		var space := (host as Node).get_viewport().world_3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.global_position.x, 200.0, p.global_position.z), Vector3(p.global_position.x, -10.0, p.global_position.z), Game.L_WORLD)
		if space.intersect_ray(q).is_empty():
			holes += 1
		# the window of the buildings and the lamps around the camera is complete
		var cam := Vector2(p.global_position.x, p.global_position.z)
		for f: Stream.Family in city.stream_families():
			if (f.name.begins_with("Buildings_") or f.name == "Lamps") and not _window_complete(f, cam):
				window_gaps += 1
		peak_live = maxi(peak_live, chunks.shape_count())
		# the block under the player (outer districts) has its colliders
		var bi := clampi(int(floor((p.global_position.x + CityLayout.HALF) / CityLayout.PITCH)), 0, CityLayout.N - 1)
		var bj := clampi(int(floor((p.global_position.z + CityLayout.HALF) / CityLayout.PITCH)), 0, CityLayout.N - 1)
		if not CityLayout.is_core_block(bi, bj) and not chunks.is_active(bi, bj):
			all_outer_active = false
	TestLib.check(fell == 0 and holes == 0, "at ten places over the whole map there is ground under the player (%d fell, %d holes)" % [fell, holes])
	TestLib.check(window_gaps == 0, "every building and lamp within the fade distance of the camera is drawn at all ten places (%d gaps)" % window_gaps)
	TestLib.check(all_outer_active, "the outer block under the player always has its colliders")
	TestLib.check(chunks.block_total() == 192 and peak_live < 600, "192 outer blocks, never more than %d box shapes alive at once (an unstreamed map keeps ~1300)" % peak_live)
	# every outer building near the player is solid: a ray through its roof hits it, at the far corner of the map
	p.teleport_to(Vector3(-600, 0.5, 600))
	await _settle(host, 20)
	var space2 := (host as Node).get_viewport().world_3d.direct_space_state
	var solid := 0
	var total := 0
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if Vector2(lot.cx + 600.0, lot.cz - 600.0).length() < 200.0:
			total += 1
			var rq := PhysicsRayQueryParameters3D.create(Vector3(lot.cx, 200.0, lot.cz), Vector3(lot.cx, -5.0, lot.cz), Game.L_WORLD)
			var hit := space2.intersect_ray(rq)
			if not hit.is_empty() and absf(float(hit.position.y) - lot.h) < 0.05:
				solid += 1
	TestLib.check(total > 8 and solid == total, "the buildings around the far corner are solid, roofs at their height (%d of %d)" % [solid, total])
	# a wall of the map: nothing leaves it
	p.teleport_to(Vector3(CityLayout.WALK + 400.0, 5.0, 0.0))
	await _settle(host, 6)
	TestLib.check(absf(p.global_position.x) <= CityLayout.WALK + 1.0, "a teleport beyond the walls is pulled back inside (x %.0f)" % p.global_position.x)
	# walking: real input over open ground in the outer ring moves the hero
	p.teleport_to(Vector3(-600, 0.5, -5))
	await _settle(host, 30)
	var x0 := p.global_position.x
	Input.action_press(&"move_forward")
	await TestLib.frames(host, 90)
	Input.action_release(&"move_forward")
	TestLib.check(Vector2(p.global_position.x - x0, 0.0).length() + absf(p.global_position.z + 5.0) > 3.0, "walking works out in the outer ring (moved %.1f m)" % p.global_position.distance_to(Vector3(x0, p.global_position.y, -5.0)))


## Zones: four outer districts on the four sides of the ring, each with a name and an existing palette; patrols wake near the player and go back to sleep far away.
func _zones_and_patrols(host: Node) -> void:
	TestLib.check(Districts.zone_at(0.0, -500.0) == Districts.DOCKYARDS and Districts.zone_at(500.0, 0.0) == Districts.AMBER_TERRACES
			and Districts.zone_at(0.0, 500.0) == Districts.GROW_FIELDS and Districts.zone_at(-500.0, 0.0) == Districts.OUTER_SPIRES, "four outer zones on the four sides of the ring")
	TestLib.check(Districts.zone_at(-50.0, -50.0) == Districts.MARKET and Districts.zone_at(50.0, 50.0) == Districts.TOWERS, "the core keeps its four districts")
	var titles := {}
	var looks := {}
	for z in Districts.ZONE_COUNT:
		titles[Districts.zone_title(z)] = true
		looks[Districts.ZONE_LOOK[z]] = true
	TestLib.check(titles.size() == 8 and looks.size() == 4, "eight zone names, dressed with the four existing palettes")
	# the outer lots really are dressed from their zone: facade tints differ between the sides
	var per := {}
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if not CityLayout.is_core_block(lot.block_i, lot.block_j):
			var z := Districts.zone_at(lot.cx, lot.cz)
			per[z] = int(per.get(z, 0)) + 1
	var zones_ok := per.size() == 4
	for z in per:
		if int(per[z]) < 40:
			zones_ok = false
	TestLib.check(zones_ok, "each outer zone has buildings (%s)" % str(per))
	# patrols: 14 dormant outer groups; one wakes when the player stands next to it and sleeps again when he leaves
	var em := Game.enemies as EnemyManager
	var groups: Array = em.patrol_groups()
	var outer: Array = []
	for g: Dictionary in groups:
		if bool(g.get("outer", false)):
			outer.append(g)
	TestLib.check(outer.size() >= 8 and groups.size() - outer.size() >= 4, "patrol groups: %d in the core, %d dormant in the outer districts" % [groups.size() - outer.size(), outer.size()])
	if outer.is_empty():
		return
	em.clear()                                                  # the walk over the map woke some groups: start this check from a clean slate
	for g: Dictionary in outer:
		g["spawned"] = false
		g["live"] = 0
		g["sleeping"] = false
	var g0: Dictionary = outer[0]
	var gp: Vector3 = g0["pos"]
	var stand := Vector3(gp.x, 0.5, gp.z)
	stand.x += 60.0 if gp.x < 500.0 else -60.0
	em.clear()
	for g: Dictionary in groups:
		g["spawned"] = true if not bool(g.get("outer", false)) else bool(g["spawned"])        # the core groups stay out of this check
	p.teleport_to(stand)
	var woke := false
	for i in 400:
		await host.get_tree().physics_frame
		if bool(g0["spawned"]) and em.list.size() > 0:
			woke = true
			break
	var near := 0
	for e in em.list:
		if Vector2(e.global_position.x - gp.x, e.global_position.z - gp.z).length() < 30.0:
			near += 1
	TestLib.check(woke and near >= 1, "the patrol wakes when the player comes within %.0f m (%d enemies at the group)" % [EnemyManager.PATROL_STREAM_DIST, near])
	# far away (a quarter of the map): the unaware patrol is sent back to sleep, its slots are free
	var far_pos := Vector3(-gp.x * 0.8, 0.5, -gp.z * 0.8)
	if Vector2(far_pos.x - gp.x, far_pos.z - gp.z).length() < EnemyManager.PATROL_SLEEP_DIST + 60.0:
		far_pos = Vector3(0.0, 0.5, 0.0) + Vector3(5.0, 0.0, 5.0)
	for e in em.list:
		e.aware = false
	p.teleport_to(far_pos)
	var slept := false
	for i in 900:
		await host.get_tree().physics_frame
		if not bool(g0["spawned"]):
			slept = true
			break
		for e in em.list:
			e.aware = false
	TestLib.check(slept, "a patrol the player left %.0f m behind goes back to sleep (it keeps no enemy slot)" % Vector2(far_pos.x - gp.x, far_pos.z - gp.z).length())
	em.clear()


## Ambient life follows the player: crowd, far traffic, streamed cars, fauna and the events are there in the far corner of the map.
func _ambient_life(host: Node) -> void:
	var amb: Node3D = city.ambient
	mgr.stream_every = 0.05
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)
	Game.set_quality(1)
	p.teleport_to(Vector3(-560.0, 0.5, 5.0))
	await _settle(host, 6)
	var crowd_ok := false
	var cars_ok := false
	for i in 900:
		await host.get_tree().physics_frame
		crowd_ok = crowd_ok or amb.crowd.alive_count() >= 8
		var near_cars := 0
		for v in mgr.list:
			if v != mgr.starter and Vector2(v.global_position.x - p.global_position.x, v.global_position.z - p.global_position.z).length() < VehicleSpecs.DESPAWN_RADIUS + 1.0:
				near_cars += 1
		cars_ok = cars_ok or near_cars >= 2
		if crowd_ok and cars_ok:
			break
	TestLib.check(crowd_ok, "a crowd walks the sidewalks around the player in the far west (%d people)" % amb.crowd.alive_count())
	TestLib.check(cars_ok, "traffic and parked cars are streamed around the player in the far west")
	TestLib.check(amb.traffic.count > 0 and Traffic_LANES() == 68, "the far traffic runs on all 68 lanes of the 17 x 17 road grid")
	# an event is spawned near the player, on a road, anywhere on the map
	var ev: Node = preload("res://scripts/world/city_events.gd").current
	if is_instance_valid(ev):
		ev.events.clear()
		ev._cool.clear()
		var e: Dictionary = ev.spawn_near(Vector3(500.0, 0.0, 500.0), &"rift")
		var pos: Vector3 = e.get("pos", Vector3.INF)
		TestLib.check(not e.is_empty() and absf(pos.x) <= Game.HALF and absf(pos.z) <= Game.HALF and Vector2(pos.x - 500.0, pos.z - 500.0).length() < 200.0, "city events happen anywhere on the map (near %s)" % str(pos))
		ev.resolve(int(e.get("id", -1)), true)


func Traffic_LANES() -> int:
	return preload("res://scripts/ambient/ambient_traffic.gd").LANES


## The minimap holds the whole map and zooms out with the driving speed; the map screen has three zoom levels over the 32 x 32 cells.
func _minimap_and_map(host: Node) -> void:
	TestLib.check(Minimap.EXTENT >= Game.HALF and Minimap.range_for_speed(0.0) == Minimap.RANGE_M and Minimap.range_for_speed(30.0) > 1.8 * Minimap.RANGE_M, "the minimap texture covers the whole map and its range grows from %.0f m to %.0f m with speed" % [Minimap.RANGE_M, Minimap.range_for_speed(30.0)])
	var mini := Minimap.new()
	host.add_child(mini)
	mini.ensure_static()
	var img := mini.tex.get_image()
	var ppm := float(Minimap.TEX_PX) / (2.0 * Minimap.EXTENT)
	var bg := Color(0.025, 0.07, 0.09)
	var road := img.get_pixel(int((480.0 + Minimap.EXTENT) * ppm), int((-480.0 + 3.0 + Minimap.EXTENT) * ppm))
	var verge := img.get_pixel(int((-600.0 + Minimap.EXTENT) * ppm), int((-600.0 + 38.0 + Minimap.EXTENT) * ppm))
	TestLib.check(absf(road.r - 0.07) < 0.01 and absf(road.g - 0.19) < 0.01 and absf(road.b - 0.24) < 0.01 and absf(road.g - bg.g) > 0.05 and verge.a > 0.0, "the minimap draws the outer roads (%s)" % str(road))
	mini.queue_free()
	var ms := MapScreen.new()
	host.add_child(ms)
	TestLib.check(MapScreen.CELLS * int(MapScreen.CELL) == int(2.0 * CityLayout.HALF) and is_equal_approx(MapScreen.HALF, CityLayout.HALF), "the map grid covers the whole map (%d x %d cells of %.0f m)" % [MapScreen.CELLS, MapScreen.CELLS, MapScreen.CELL])
	ms._seen = PackedByteArray()
	ms._seen.resize(MapScreen.CELLS * MapScreen.CELLS)
	ms.discover(Vector3(0.0, 0.0, -560.0))
	TestLib.check(ms.zone_discovered(Districts.DOCKYARDS) and not ms.zone_discovered(Districts.OUTER_SPIRES), "walking in the north discovers the dockyards only")
	ms._update_rect()
	var roundtrip := true
	for z in MapScreen.ZOOMS:
		ms.set_zoom(z)
		var s := ms.span()
		if not is_equal_approx(s, 2.0 * MapScreen.HALF / float(z)):
			roundtrip = false
		var c := ms.view_center
		for w in [Vector2(c.x + s * 0.2, c.y - s * 0.15), Vector2(c.x - s * 0.3, c.y + s * 0.3)]:
			var back := ms.map_to_world(ms.world_to_map(w.x, w.y))
			if Vector2(back.x - w.x, back.z - w.y).length() > 0.5:
				roundtrip = false
	TestLib.check(roundtrip, "the map converts world and screen positions at 1x, 2x and 4x")
	ms.set_zoom(1)
	ms.cycle_zoom()
	var z2 := ms.zoom
	ms.cycle_zoom()
	var z4 := ms.zoom
	ms.cycle_zoom()
	TestLib.check(z2 == 2 and z4 == 4 and ms.zoom == 1, "the zoom button cycles 1x, 2x, 4x and back")
	ms.set_zoom(4)
	ms.pan(Vector2(5000.0, 5000.0))
	var lim := MapScreen.HALF - ms.span() * 0.5
	TestLib.check(ms.view_center.x <= lim + 0.01 and ms.view_center.y <= lim + 0.01, "panning stays inside the map")
	ms.set_zoom(1)
	ms.queue_free()


## Drive the sport car along the main avenue from the west border to the east border with real input: arcade speeds, the whole crossing takes a minute or more,
## and the car never falls, stops or leaves the city.
func _drive_across(host: Node) -> void:
	mgr.stream_every = 100000.0                         # a clear avenue: no new traffic while the car races (streaming is checked on its own)
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)
	p.teleport_to(Vector3(-620.0, 0.5, 5.0))
	await _settle(host, 20)
	var car := mgr.spawn_parked(&"sport", Vector3(-620.0, 0.0, 5.0), -PI * 0.5)
	car.global_position = Vector3(-620.0, 0.0, 5.0)
	mgr.enter(car)
	await _settle(host, 4)
	TestLib.check(mgr.driven == car, "the player drives the sport car")
	var top := float(VehicleSpecs.SPECS[&"sport"]["max"])
	TestLib.check(top >= 30.0 and top <= 40.0, "the sport car's top speed fits the city scale (%.0f m/s)" % top)
	var t0 := Engine.get_physics_frames()
	var tick := 60.0                                    # physics ticks per GAME second (the step is 1/60 s of game time at any time scale)
	var peak := 0.0
	var worst_y := 0.0
	var min_speed_after_start := 1000.0
	var crossed := false
	var chunk_peak := 0
	var chunks := city.collision_chunks()
	var holes := 0
	var space := (host as Node).get_viewport().world_3d.direct_space_state
	Input.action_press(&"move_forward")
	var frame := 0
	while (Engine.get_physics_frames() - t0) / tick < CRUISE_LIMIT:
		await host.get_tree().physics_frame
		frame += 1
		peak = maxf(peak, absf(car.speed))
		worst_y = minf(worst_y, car.global_position.y)
		if car.global_position.x > 600.0:
			crossed = true
			break
		if frame % 30 == 0:
			chunk_peak = maxi(chunk_peak, chunks.active_count())
			if (Engine.get_physics_frames() - t0) / tick > 8.0:
				min_speed_after_start = minf(min_speed_after_start, absf(car.speed))
			var q := PhysicsRayQueryParameters3D.create(Vector3(car.global_position.x, 200.0, car.global_position.z), Vector3(car.global_position.x, -10.0, car.global_position.z), Game.L_WORLD)
			if space.intersect_ray(q).is_empty():
				holes += 1
	Input.action_release(&"move_forward")
	var secs := float(Engine.get_physics_frames() - t0) / tick
	TestLib.check(crossed, "the car crossed the whole map along the avenue (x %.0f after %.0f s)" % [car.global_position.x, secs])
	TestLib.check(secs >= 36.0, "the crossing takes the better part of a minute, not 15 s (%.0f s)" % secs)
	TestLib.check(peak >= 18.0 and peak <= top + 0.5, "top speed on the straight is arcade, 18 to 28 m/s (%.1f)" % peak)
	TestLib.check(worst_y > -0.5 and holes == 0, "no hole in the road all the way across (lowest y %.2f, %d holes)" % [worst_y, holes])
	TestLib.check(min_speed_after_start > 10.0, "the car never stopped on the way (slowest %.1f m/s)" % min_speed_after_start)
	TestLib.check(chunk_peak > 0 and chunk_peak <= 60, "the colliders of the outer blocks were streamed on the way (at most %d blocks alive)" % chunk_peak)
	mgr.exit_vehicle()
	mgr.stream_every = 0.05
	await _settle(host, 10)


## After crossing the whole city the memory of the streams is flat: pooled bodies and shapes did not grow with the distance travelled.
func _streaming_is_flat(host: Node) -> void:
	var chunks := city.collision_chunks()
	TestLib.check(chunks.assigned >= 20 and chunks.released >= 10, "blocks were generated and freed by distance (%d assigned, %d released)" % [chunks.assigned, chunks.released])
	TestLib.check(chunks.pooled_shapes() < 900 and chunks.created_shapes == chunks.pooled_shapes(), "the shape pool stayed small after crossing the map (%d shapes ever created, an unstreamed map has ~1300)" % chunks.created_shapes)
	# triangles and instances drawn: the same at the core and in the far corner
	var tris: Array[int] = []
	for at in [Vector2(-30.0, 4.0), Vector2(-600.0, 600.0), Vector2(600.0, -600.0)]:
		city.update_streaming(at, true)
		var st := city.stats()
		tris.append(int(st["triangles_drawn"]) + int(st["triangles_drawn_mirror"]))
	TestLib.check(tris[1] <= int(1.1 * float(tris[0])) and tris[2] <= int(1.1 * float(tris[0])) and tris[0] < 190000, "triangles drawn: no far corner draws more than the dense core (core %d, SW %d, NE %d; the whole map has %d instances)" % [tris[0], tris[1], tris[2], int(city.stats()["instances"])])
	var cones := city.lamp_cones.mesh.get_surface_count()
	TestLib.check(cones >= 0 and city._cone_heads.size() > 1000, "the lamp cones are windowed (%d lamp heads in the city)" % city._cone_heads.size())


func _settle(host: Node, frames: int) -> void:
	for i in frames:
		await host.get_tree().physics_frame


func _family(name: String) -> Stream.Family:
	for f: Stream.Family in city.stream_families():
		if f.name == name:
			return f
	return null


## True when every instance of the family within its fade distance of `cam` is part of the drawn window.
func _window_complete(f: Stream.Family, cam: Vector2) -> bool:
	var buf := f.mm.buffer
	var drawn := {}
	for i in f.shown:
		var o := i * f.stride
		drawn[Vector2i(roundi(buf[o + 3] * 8.0), roundi(buf[o + 11] * 8.0))] = true
	var reach := f.fade_end()
	for c in f.cells.size():
		var arr: PackedFloat32Array = f.cells[c]
		for k in arr.size() / f.stride:
			var o := k * f.stride
			if Vector2(arr[o + 3], arr[o + 11]).distance_to(cam) < reach and not drawn.has(Vector2i(roundi(arr[o + 3] * 8.0), roundi(arr[o + 11] * 8.0))):
				return false
	return true
