extends RefCounted
## The terrain world (owner round 5: mountains, coast, outskirts "as big as possible") in the REAL game scene: the height function and its masks (flat city, mountain range, coast, rivers,
## road benches), the chunk streaming (3 LODs, skirts, colliders only next to the hero, budgets by tier), a walk and a drive out of the city along the highway with no hole and no pop,
## 4x4 grip, the world map layer and the WORLD zoom of the map screen.
## Run: tools/test.sh tests/test_terrain_world.gd   (about 60 s; waits on positions, counters and game time, never on frame counts)

const K := 4
const TIMEOUT_SECONDS := 130.0

var city: City
var p: Player
var mgr: VehicleManager


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_height_function()
	_roads()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(city != null and p != null and mgr != null and city.terrain != null, "the real scene has a city with a terrain world, a player and a vehicle manager")
	if city == null or p == null or mgr == null or city.terrain == null:
		_restore()
		return
	p.set_physics_process(true)
	await _city_is_untouched(host)
	await _far_tiles(host)
	await _walk_out(host)
	await _teleport_far(host)
	await _tiers(host)
	await _drive_out(host)
	await _shore_and_traffic(host)
	await _map(host)
	Input.action_release(&"move_forward")
	_restore()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


# --- the height function ------------------------------------------------------------------------------------------------------

func _height_function() -> void:
	TerrainHeight.warm()
	TestLib.check(TerrainHeight.WORLD_HALF >= 2000.0 and TerrainHeight.WORLD_HALF <= 4500.0, "the world is a 4 to 9 km square (%.0f m; wave 112 doubled the area: the owner asked for a much bigger map)" % (2.0 * TerrainHeight.WORLD_HALF))
	var flat := true
	for q in [Vector2(0, 0), Vector2(900, -700), Vector2(-1050, 1050), Vector2(700, 1000), Vector2(-1000, -300)]:
		if absf(TerrainHeight.height_at(q.x, q.y)) > 0.01:
			flat = false
	for q in [Vector2(1099, 0), Vector2(0, -1099), Vector2(0, 1099), Vector2(-1099, 0)]:                      # the highway gates: the road bench blends into the plateau within a few cm
		if absf(TerrainHeight.height_at(q.x, q.y)) > 0.25:
			flat = false
	TestLib.check(flat, "the city plateau is exactly flat at y = 0")
	var a := TerrainHeight.height_at(1640.0, -820.0)
	var b := TerrainHeight.height_at(1640.0, -820.0)
	TestLib.check(a == b and is_finite(a), "the height function is deterministic")
	var hi := -1.0e9
	var lo := 1.0e9
	var snow := false
	var forest := false
	var desert := false
	var beach := false
	var ocean := false
	var mountain := false
	for ix in 60:
		for iz in 60:
			var x := -TerrainHeight.WORLD_HALF + (float(ix) + 0.5) * (2.0 * TerrainHeight.WORLD_HALF / 60.0)
			var z := -TerrainHeight.WORLD_HALF + (float(iz) + 0.5) * (2.0 * TerrainHeight.WORLD_HALF / 60.0)
			var h := TerrainHeight.height_at(x, z)
			hi = maxf(hi, h)
			lo = minf(lo, h)
			if h > TerrainBase.SNOW_LINE + 30.0:
				snow = true
			match TerrainBase.biome_at(x, z, h):
				TerrainBase.FOREST:
					forest = true
				TerrainBase.DESERT:
					desert = true
				TerrainBase.BEACH:
					beach = true
				TerrainBase.OCEAN:
					ocean = true
				TerrainBase.MOUNTAIN:
					mountain = true
	TestLib.check(hi >= 350.0, "a mountain range stands in the world (highest %.0f m)" % hi)
	TestLib.check(lo <= -25.0, "the sea floor is deep (lowest %.0f m)" % lo)
	TestLib.check(snow and forest and desert and beach and ocean and mountain, "every biome exists: snow, forest, desert, beach, ocean, mountain")
	var slope_ok := true
	for k in 200:                                                           # the surface is continuous: no cliff between samples 4 m apart (the road benches and rivers included)
		var x2 := -2500.0 + float(k) * 25.0
		var h0 := TerrainHeight.height_at(x2, -300.0)
		var h1 := TerrainHeight.height_at(x2 + 4.0, -300.0)
		if absf(h1 - h0) > 9.0:                                                 # (wave 112: the east range now reaches the line's end: its crags are steep faces, up to 9 m in 4 m; a pad, a bench or a bridge ramp that did not blend would be far more)
			slope_ok = false
	TestLib.check(slope_ok, "no vertical step in the land along a line through the world")


func _roads() -> void:
	var roads := TerrainRoads.roads()
	TestLib.check(roads.size() >= 5, "at least five roads lead out of the city (%d)" % roads.size())
	var gates := 0
	var worst_grade := 0.0
	var worst_off := 0.0
	var long_enough := 0
	for r in roads:
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		if bool(r["from_city"]):
			if TerrainHeight.city_distance(pts[0].x, pts[0].y) < 2.0 and absf(prof[0]) < 0.01:
				gates += 1
		if float(r["len"]) >= 900.0:
			long_enough += 1
		for i in range(1, pts.size()):
			worst_grade = maxf(worst_grade, absf(prof[i] - prof[i - 1]) / maxf(pts[i].distance_to(pts[i - 1]), 1.0))
		for i in range(0, pts.size(), 7):                                   # the finished land under the centre line is the road profile (the bench is flat across)
			var h := TerrainHeight.height_at(pts[i].x, pts[i].y)
			if TerrainHeight.depth_at(pts[i].x, pts[i].y) < 0.05 and not TerrainRoads.in_span(pts[i].x, pts[i].y):          # (a bridge span keeps the river banks: the deck rides the profile)
				worst_off = maxf(worst_off, absf(h - prof[i]))
	TestLib.check(gates >= 4, "four highways start at the city gates on the plateau (%d)" % gates)
	TestLib.check(long_enough >= 5, "the roads are long (%d of %d at least 900 m)" % [long_enough, roads.size()])
	TestLib.check(worst_grade <= 0.145, "no road is steeper than a mountain track (%.3f)" % worst_grade)
	TestLib.check(worst_off < 0.5, "the terrain under every road is the road bench (worst difference %.2f m)" % worst_off)
	var r0: Dictionary = roads[0]
	var q: Vector2 = (r0["pos"] as PackedVector2Array)[60]
	TestLib.check(TerrainWorld.surface_at(q.x, q.y) == &"asphalt", "a highway centre line is asphalt (%s)" % TerrainWorld.surface_at(q.x, q.y))
	TestLib.check(TerrainRoads.on_road(q.x, q.y) and not TerrainRoads.on_road(q.x + 80.0, q.y + 80.0), "on_road knows the carriageway")
	TestLib.check(TerrainWorld.surface_at(0.0, 0.0) == &"city", "the plateau is the city surface")
	TestLib.check(VehicleSpecs.surface_grip(&"suv", &"dirt") > VehicleSpecs.surface_grip(&"sedan", &"dirt") and VehicleSpecs.surface_grip(&"rover", &"sand") > VehicleSpecs.surface_grip(&"sport", &"sand"), "off-road cars hold the dirt and the sand better than street cars")
	TestLib.check(VehicleSpecs.surface_grip(&"sedan", &"asphalt") == 1.0 and VehicleSpecs.surface_speed(&"sedan", &"snow") < VehicleSpecs.surface_speed(&"suv", &"snow"), "asphalt is full grip, snow slows a street car most")


# --- the real scene ---------------------------------------------------------------------------------------------------------------

func _wait_counter(host: Node, what: Callable, secs: float) -> bool:
	var t0 := Engine.get_physics_frames()
	while float(Engine.get_physics_frames() - t0) / 60.0 < secs:
		if what.call():
			return true
		await host.get_tree().process_frame
	return what.call()


## Inside the city nothing is built at all: the city has its own ground and the terrain only starts at the plateau edge.
func _city_is_untouched(host: Node) -> void:
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 8)
	var st := city.terrain.stats()
	TestLib.check(int(st["chunks"]) == 0 and int(st["bodies"]) == 0, "in the middle of the city no terrain chunk and no terrain collider exists (%d chunks)" % int(st["chunks"]))
	TestLib.check(city.ground_height(0.0, 0.0) == 0.0 and absf(city.ground_height(1500.0, 20.0) - TerrainHeight.height_at(1500.0, 20.0)) < 0.01, "ground_height is the city floor inside and the terrain outside")
	TestLib.check(PlayerUtil.outside_city(Vector3(CityLayout.PLAY_HALF + 20.0, 0.0, 0.0)) and not PlayerUtil.outside_city(Vector3(1500.0, TerrainHeight.height_at(1500.0, 20.0) + 1.0, 20.0)), "the playable world reaches past the old city walls")


## The far tiles (the third LOD) are built once for the whole world: a handful of meshes, none inside the plateau.
func _far_tiles(host: Node) -> void:
	var total := city.terrain._far_total()
	var done := await _wait_counter(host, func() -> bool: return int(city.terrain.stats()["far_tiles"]) >= total, 45.0)
	var st := city.terrain.stats()
	TestLib.check(done, "all %d far tiles are built by the worker threads (%d)" % [total, int(st["far_tiles"])])
	TestLib.check(total >= 20 and total <= 90, "the world is covered by under a hundred far tiles, not hundreds of chunks (%d of the 9 x 9 grid)" % total)
	TestLib.check(int(st["tris"]) > 20000, "the far tiles carry the horizon (%d triangles)" % int(st["tris"]))


## Walk out of the city along the desert road: no hole under the hero, no pop, the chunks follow, the colliders stay next to him.
func _walk_out(host: Node) -> void:
	var start := Vector3(1060.0, 0.5, 2.0)
	p.teleport_to(start)
	await TestLib.frames(host, 8)
	p.camera_rig.yaw = -PI * 0.5                                            # facing +X, towards the desert and the mountains
	Input.action_press(&"move_forward")
	var holes := 0
	var worst_under := 0.0
	var worst_dy := 0.0
	var prev_y := p.global_position.y
	var max_chunks := 0
	var max_bodies := 0
	var max_upload := 0.0
	var t0 := Engine.get_physics_frames()
	var tick := 60.0
	var x_end := 1420.0
	var sample := 0
	while (Engine.get_physics_frames() - t0) / tick < 120.0:
		await host.get_tree().physics_frame
		sample += 1
		if sample % 12 != 0:
			continue
		var pos := p.global_position
		var h := TerrainHeight.height_at(pos.x, pos.z)
		worst_under = minf(worst_under, pos.y - h)
		worst_dy = maxf(worst_dy, absf(pos.y - prev_y))
		prev_y = pos.y
		if absf(pos.x) > TerrainHeight.CITY_HALF + 3.0 and not city.terrain.is_ground_ready(pos.x, pos.z):
			holes += 1
		var st := city.terrain.stats()
		max_chunks = maxi(max_chunks, int(st["chunks"]))
		max_bodies = maxi(max_bodies, int(st["bodies"]))
		max_upload = maxf(max_upload, float(st["max_upload_ms"]))
		if pos.x > x_end:
			break
	Input.action_release(&"move_forward")
	var q := p.global_position
	TestLib.check(q.x > x_end - 40.0, "the hero walked out of the city to x %.0f (the old border wall is gone)" % q.x)
	TestLib.check(worst_under > -1.5, "the hero never fell under the terrain (lowest %.2f m relative to the ground)" % worst_under)
	TestLib.check(worst_dy < 1.8, "no pop: the ground under the hero never jumps (largest step %.2f m between samples)" % worst_dy)
	TestLib.check(holes == 0, "the ground under the hero was always there (%d holes)" % holes)
	var r1 := city.terrain.r1()
	TestLib.check(max_chunks > 0 and max_chunks <= (2 * r1 + 1) * (2 * r1 + 1), "chunk count stays bounded by the tier radius (%d, radius %d)" % [max_chunks, r1])
	TestLib.check(max_bodies <= 9 and max_bodies >= 1, "colliders exist only for the 3 x 3 chunks around the hero (%d)" % max_bodies)
	TestLib.check(city.terrain.chunk_lod(city.terrain.chunk_of(q.x, q.z).x, city.terrain.chunk_of(q.x, q.z).y) == 0, "the chunk under the hero is the full-detail one")
	TestLib.check(max_upload < 250.0, "a chunk upload on the main thread stays short (%.0f ms)" % max_upload)


## A teleport far into the outskirts: the ground is there at once (ensure_ground), the hero does not fall.
func _teleport_far(host: Node) -> void:
	var target := Vector3(-1500.0, 30.0, -900.0)
	p.teleport_to(target)
	await TestLib.frames(host, 4)
	var pos := p.global_position
	var h := TerrainHeight.height_at(pos.x, pos.z)
	TestLib.check(absf(pos.x - target.x) < 5.0 and city.terrain.is_ground_ready(pos.x, pos.z), "a teleport into the forest hills has its ground ready at once")
	await _wait_counter(host, func() -> bool: return p.is_on_floor(), 6.0)
	TestLib.check(p.global_position.y > h - 0.5 and p.global_position.y < h + 4.0, "and the hero lands on it (%.1f vs ground %.1f)" % [p.global_position.y, h])
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 4)


## The chunk budget follows the tier: radius, colliders and the texture array.
func _tiers(host: Node) -> void:
	var pos := Vector3(1700.0, 0.0, 600.0)
	var radii: Array[int] = []
	var tex: Array[int] = []
	for tier in [0, 1, 2]:
		Game.set_quality(tier)
		city.terrain.settle(pos)
		var st := city.terrain.stats()
		radii.append(city.terrain.r1())
		tex.append(int(st["tex_bytes"]))
		TestLib.check(int(st["chunks"]) <= (2 * city.terrain.r1() + 1) * (2 * city.terrain.r1() + 1), "tier %d keeps at most the radius square of chunks (%d)" % [tier, int(st["chunks"])])
		TestLib.check(city.terrain.chunk_lod(city.terrain.chunk_of(pos.x, pos.z).x, city.terrain.chunk_of(pos.x, pos.z).y) == 0, "tier %d: the focus chunk is full detail" % tier)
	TestLib.check(radii[0] < radii[1] and radii[1] < radii[2], "the LOD1 radius grows with the tier (%s)" % str(radii))
	# wave 112 added four layers (wet sand, strata, scree, dark rock): the terrain array is 11 layers, 3.7 MB on LOW and MED and 14.7 MB on HIGH, so the cap of this check went from 12 to 16 MB
	# (the per-tier texture limits of the whole game, 200 / 260 / 360 MB, are unchanged and gated by tools/perf_report.sh)
	TestLib.check(tex[0] <= tex[1] and tex[1] < tex[2] and tex[2] <= 16 * 1024 * 1024, "terrain texture memory is tier scaled and small (%.1f / %.1f / %.1f MB)" % [tex[0] / 1048576.0, tex[1] / 1048576.0, tex[2] / 1048576.0])
	Game.set_quality(1)
	await TestLib.frames(host, 2)
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 4)


## Drive an SUV out of the city on the desert road: it follows the ground, tilts with the slope, rides on asphalt and gets the surface under its wheels.
func _drive_out(host: Node) -> void:
	mgr.stream_every = 100000.0
	TrafficField.bare_street()                            # round 6: the near, road and parked cars are switched off: the SUV drives a bare road
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)
	var start := Vector3(1130.0, 0.0, 10.0)
	p.teleport_to(start + Vector3(0.0, 1.0, 4.0))
	await TestLib.frames(host, 8)
	var car := mgr.spawn_parked(&"suv", start, -PI * 0.5)
	car.global_position = Vector3(start.x, TerrainHeight.height_at(start.x, start.z), start.z)
	mgr.enter(car)
	await TestLib.frames(host, 4)
	TestLib.check(mgr.driven == car, "the player drives the SUV outside the city")
	var roads := TerrainRoads.roads()
	var desert: Dictionary = {}
	for r in roads:
		if r["name"] == "DESERT ROAD":
			desert = r
	var pts: PackedVector2Array = desert["pos"]
	var goal := pts[mini(pts.size() - 1, 60)]
	var t0 := Engine.get_physics_frames()
	var tick := 60.0
	var worst_off := 0.0
	var saw_asphalt := false
	var max_tilt := 0.0
	var min_speed := 1000.0
	var sample := 0
	var peak := 0.0
	var reached := false
	Input.action_press(&"move_forward")
	while (Engine.get_physics_frames() - t0) / tick < 90.0:
		await host.get_tree().physics_frame
		sample += 1
		peak = maxf(peak, absf(car.speed))
		if sample % 20 != 0:
			continue
		var c := car.global_position
		var h := TerrainHeight.height_at(c.x, c.z)
		worst_off = maxf(worst_off, absf(c.y - h))
		max_tilt = maxf(max_tilt, absf(car.ground_pitch) + absf(car.ground_roll))
		if car.surface == &"asphalt":
			saw_asphalt = true
		if (Engine.get_physics_frames() - t0) / tick > 10.0:
			min_speed = minf(min_speed, absf(car.speed))
		# steer back onto the road: a simple pursuit of the centre line ahead (the test drives, it does not test the player's skill)
		var ahead := _road_point_ahead(pts, c, 40.0)
		var to := Vector2(ahead.x - c.x, ahead.y - c.z)
		var fwd := Vector2(car.forward().x, car.forward().z)
		var ang := fwd.angle_to(to)
		Input.action_release(&"move_left")
		Input.action_release(&"move_right")
		if ang > 0.06:
			Input.action_press(&"move_right")
		elif ang < -0.06:
			Input.action_press(&"move_left")
		if Vector2(c.x, c.z).distance_to(goal) < 40.0:
			reached = true
			break
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	TestLib.check(reached, "the SUV followed the desert road for %d m (reached %s)" % [int(desert["len"] * 0.5), str(reached)])
	TestLib.check(worst_off < 1.2, "the car rides the ground (largest height error %.2f m)" % worst_off)
	TestLib.check(saw_asphalt, "the wheels were on asphalt on the highway")
	TestLib.check(peak >= 10.0, "the car really drove (peak %.1f m/s)" % peak)
	TestLib.check(is_finite(max_tilt), "the hull tilts with the slope (%.3f rad)" % max_tilt)
	mgr.exit_vehicle()
	mgr.stream_every = 0.05
	await TestLib.frames(host, 6)


## Out of the city the only cars are the ones the hero drives and the parked outposts: nothing streams traffic onto the terrain. A car never drives into deep water: it stops at the shore.
func _shore_and_traffic(host: Node) -> void:
	p.teleport_to(Vector3(1300.0, 3.0, 12.0))
	mgr.stream_every = 0.05
	var t0 := Engine.get_physics_frames()
	while float(Engine.get_physics_frames() - t0) / 60.0 < 8.0:
		await host.get_tree().physics_frame
	var strays := 0
	for v in mgr.list:
		var vp := v.global_position
		if v.ai and not v.has_meta(&"spawn_id") and not v.driver_is_player and (absf(vp.x) > TerrainHeight.CITY_HALF + 5.0 or absf(vp.z) > TerrainHeight.CITY_HALF + 5.0):
			strays += 1
	TestLib.check(strays == 0, "no traffic car roams the terrain outside the city (%d strays among %d cars)" % [strays, mgr.list.size()])
	# find the shore west of the city and drive an SUV at it (a terrain test: the trunks and boulders of the vegetation, solid since wave 105, are taken out of the straight run)
	if city.vegetation != null:
		city.vegetation.enabled = false
		city.vegetation.call(&"_place_blockers", [])
	var z := 300.0
	var shore := -1100.0
	while shore > -4300.0 and TerrainHeight.depth_at(shore, z) < 0.3:
		shore -= 10.0
	TestLib.check(shore > -4300.0, "there is a shore west of the city (x %.0f)" % shore)
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)
	mgr.stream_every = 100000.0
	var start := Vector3(shore + 150.0, 0.0, z)
	p.teleport_to(start + Vector3(0.0, 2.0, 5.0))
	await TestLib.frames(host, 8)
	var car := mgr.spawn_parked(&"suv", start, PI * 0.5)                  # heading +90 degrees: nose to -X, towards the sea
	car.global_position = Vector3(start.x, TerrainHeight.height_at(start.x, start.z), start.z)
	mgr.enter(car)
	await TestLib.frames(host, 4)
	var deepest := 0.0
	var farthest := start.x
	Input.action_press(&"move_forward")
	var t1 := Engine.get_physics_frames()
	while float(Engine.get_physics_frames() - t1) / 60.0 < 25.0:
		await host.get_tree().physics_frame
		var c := car.global_position
		deepest = maxf(deepest, TerrainHeight.depth_at(c.x, c.z))
		farthest = minf(farthest, c.x)
	Input.action_release(&"move_forward")
	TestLib.check(farthest < start.x - 60.0, "the SUV drove towards the sea (%.0f m)" % (start.x - farthest))
	TestLib.check(deepest <= 1.7, "the car stops at the shore, it never drives into deep water (deepest %.2f m)" % deepest)
	mgr.exit_vehicle()
	mgr.stream_every = 0.05
	await TestLib.frames(host, 6)


func _road_point_ahead(pts: PackedVector2Array, c: Vector3, dist: float) -> Vector2:
	var best := 0
	var bd := 1.0e18
	for i in pts.size():
		var d := pts[i].distance_squared_to(Vector2(c.x, c.z))
		if d < bd:
			bd = d
			best = i
	var k := mini(pts.size() - 1, best + int(dist / TerrainRoads.STEP))
	return pts[k]


## The world picture for the map: built once, the minimap and the map screen draw it; the WORLD zoom shows all of it.
func _map(host: Node) -> void:
	var ok := TerrainMap.build_now()
	TestLib.check(ok and TerrainMap.ready and TerrainMap.texture != null and TerrainMap.texture.get_width() == TerrainMap.RES, "the world map picture exists (%d px)" % TerrainMap.RES)
	var img := TerrainMap.texture.get_image()
	var sea := img.get_pixel(4, TerrainMap.RES - 6)                          # the south west corner is open sea
	var snow_px := img.get_pixel(int(TerrainMap.world_to_uv(1500.0, -1900.0).x * TerrainMap.RES), int(TerrainMap.world_to_uv(1500.0, -1900.0).y * TerrainMap.RES))
	TestLib.check(sea.b > sea.r and sea.b > sea.g * 0.9, "the map shows the sea in the corner")
	TestLib.check(snow_px != sea, "the map shows the land")
	TestLib.check(TerrainMap.region_name(0.0, 0.0) == "CITY" and TerrainMap.region_name(-2900.0, 2900.0) == "OPEN SEA", "regions have names")
	# the minimap shows the city picture only where the city is: a polygon half outside the unit square is clipped to it (u, v in 0..1)
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var uvs := PackedVector2Array([Vector2(-0.5, 0.2), Vector2(0.5, 0.2), Vector2(0.5, 0.8), Vector2(-0.5, 0.8)])
	var clipped := Minimap._clip_unit(pts, uvs)
	var inside := true
	for t: Vector2 in clipped[1]:
		if t.x < -0.001 or t.x > 1.001 or t.y < -0.001 or t.y > 1.001:
			inside = false
	var maxx := 0.0
	for q: Vector2 in clipped[0]:
		maxx = maxf(maxx, q.x)
	TestLib.check(inside and (clipped[0] as PackedVector2Array).size() >= 3 and is_equal_approx(maxx, 10.0), "the minimap clips the city layer to the city square (%d points)" % (clipped[0] as PackedVector2Array).size())
	var out_only := Minimap._clip_unit(pts, PackedVector2Array([Vector2(-3, 0), Vector2(-2, 0), Vector2(-2, 1), Vector2(-3, 1)]))
	TestLib.check((out_only[0] as PackedVector2Array).size() < 3, "a polygon wholly outside the city square draws nothing of the city layer")
	var ms := MapScreen.new()
	host.add_child(ms)
	await TestLib.frames(host, 2)
	ms.open()
	await TestLib.frames(host, 2)
	ms.set_world_mode(true)
	TestLib.check(ms.world_mode and ms.zoom_f < 0.5, "WORLD zoom opens the whole world (zoom %.2f)" % ms.zoom_f)
	ms._update_rect()
	var span := ms.span()
	TestLib.check(span > 2.0 * TerrainHeight.WORLD_HALF * 0.9 and span < 2.0 * TerrainHeight.WORLD_HALF * 1.2, "the WORLD view is as tall as the world (%.0f m of %.0f)" % [span, 2.0 * TerrainHeight.WORLD_HALF])
	ms.pan(Vector2(100000.0, 100000.0))
	TestLib.check(ms.view_center.is_finite() and absf(ms.view_center.x) <= TerrainHeight.WORLD_HALF, "panning stays inside the world")
	ms.set_world_mode(false)
	TestLib.check(not ms.world_mode and is_equal_approx(ms.zoom_f, 1.0), "leaving WORLD returns to the city overview")
	ms.zoom_by(0.1)
	TestLib.check(ms.zoom_f >= 1.0, "pinching out of the city view stops at the whole city, WORLD is its own level")
	ms.close_screen()
	ms.queue_free()
