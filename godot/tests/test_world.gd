extends RefCounted
## World module tests (headless): layout fidelity with the JS prototype, the public API of City, colliders, MultiMesh instance counts and
## the quality tiers. Run: tools/test.sh tests/test_world.gd

const BM := preload("res://scripts/world/building_meshes.gd")


func run(host: Node) -> void:
	_test_layout_port()
	var scene := load("res://scenes/world.tscn") as PackedScene
	TestLib.check(scene != null, "scenes/world.tscn loads")
	var city := scene.instantiate() as City
	TestLib.check(city != null, "world.tscn root is a City")
	host.add_child(city)
	await TestLib.frames(host, 4)
	TestLib.check(Game.world == city, "Game.world is the City")
	_test_api(city)
	_test_road_queries(city)
	_test_inside(city)
	await _test_colliders(host, city)
	_test_multimeshes(city)
	await _test_quality(host, city)
	_test_stats(city)


## The layout must reproduce src/world.js exactly (same mulberry32 stream): 232 lots, same first lots and height histogram.
func _test_layout_port() -> void:
	var layout := CityLayout.new()
	TestLib.check(layout.lots.size() == 232, "layout has 232 buildings like the prototype (got %d)" % layout.lots.size())
	var expected := [[-295, -295, 26, 18, 16], [-265, -295, 26, 18, 16], [-265, -265, 26, 26, 28], [-295, -215, 26, 18, 16], [-265, -215, 26, 18, 28], [-265, -185, 18, 26, 28]]
	var same := true
	for k in expected.size():
		var l: CityLayout.Lot = layout.lots[k]
		var e: Array = expected[k]
		if not (is_equal_approx(l.cx, e[0]) and is_equal_approx(l.cz, e[1]) and is_equal_approx(l.w, e[2]) and is_equal_approx(l.d, e[3]) and is_equal_approx(l.h, e[4])):
			same = false
	TestLib.check(same, "first six lots match the JS prototype")
	var last: CityLayout.Lot = layout.lots[layout.lots.size() - 1]
	TestLib.check(is_equal_approx(last.cx, 295.0) and is_equal_approx(last.cz, 295.0) and is_equal_approx(last.h, 16.0), "last lot matches the JS prototype")
	var hist := {}
	for l: CityLayout.Lot in layout.lots:
		hist[int(l.h)] = int(hist.get(int(l.h), 0)) + 1
	TestLib.check(hist.get(16) == 42 and hist.get(28) == 80 and hist.get(44) == 62 and hist.get(62) == 37 and hist.get(88) == 11,
			"height histogram matches the prototype (16:42 28:80 44:62 62:37 88:11), got %s" % str(hist))
	TestLib.check(layout.plazas.size() + layout.lots.size() == 256, "lots + plazas fill all 64 blocks x 4")
	# lots never leave their block and never touch a road
	var clean := true
	for l: CityLayout.Lot in layout.lots:
		for corner: Vector2 in [l.rect.position, l.rect.end, Vector2(l.rect.position.x, l.rect.end.y), Vector2(l.rect.end.x, l.rect.position.y)]:
			if CityLayout.on_road(corner.x, corner.y):
				clean = false
	TestLib.check(clean, "no building footprint touches a road")


func _test_api(city: City) -> void:
	TestLib.check(city.intersections.size() == 49, "49 inner intersections (got %d)" % city.intersections.size())
	var ok := true
	for p in city.intersections:
		if p.y != 0.0 or absf(p.x) > 240.0 or absf(p.z) > 240.0:
			ok = false
		if not (is_equal_approx(fposmod(p.x + 320.0, 80.0), 0.0) and is_equal_approx(fposmod(p.z + 320.0, 80.0), 0.0)):
			ok = false
	TestLib.check(ok, "intersections are inner road junctions at y = 0")
	TestLib.check(city.building_rects.size() >= 200 and city.building_rects.size() <= 256, "building count in the expected range (%d)" % city.building_rects.size())
	TestLib.check(city.sun is DirectionalLight3D and city.sun.is_inside_tree(), "sun is a DirectionalLight3D in the tree")
	TestLib.check(city.get_children().any(func(n: Node) -> bool: return n is WorldEnvironment), "a WorldEnvironment exists")
	var env := (city.get_children().filter(func(n: Node) -> bool: return n is WorldEnvironment)[0] as WorldEnvironment).environment
	TestLib.check(env.fog_enabled and env.glow_enabled and env.tonemap_mode == Environment.TONE_MAPPER_ACES, "environment: fog, glow, ACES tonemap")
	TestLib.check(env.background_mode == Environment.BG_SKY and env.sky != null, "environment draws the procedural sky")


func _on_any_rect(city: City, p: Vector3, margin := 0.0) -> bool:
	for r in city.building_rects:
		if p.x > r.position.x - margin and p.x < r.end.x + margin and p.z > r.position.y - margin and p.z < r.end.y + margin:
			return true
	return false


func _test_road_queries(city: City) -> void:
	var bad := 0
	for i in 800:
		var p := city.random_road_point()
		if p.y != 0.0 or not CityLayout.on_road(p.x, p.z) or _on_any_rect(city, p):
			bad += 1
	TestLib.check(bad == 0, "800 random_road_point() samples are on a road and outside every building rect (%d bad)" % bad)
	# road_point_near respects [rmin, rmax] (XZ distance) and stays on roads
	var cases := [[Vector3(-30, 0, 4), 38.0, 75.0], [Vector3(0, 0, 0), 10.0, 30.0], [Vector3(150, 40, -90), 60.0, 140.0],
			[Vector3(-300, 0, 300), 100.0, 250.0], [Vector3(20, 88, 20), 0.0, 50.0], [Vector3(40, 0, 40), 38.0, 39.0]]
	var violations := 0
	var misses := 0
	for c in cases:
		for i in 150:
			var p := city.road_point_near(c[0], c[1], c[2])
			if p == Vector3.INF:
				misses += 1
				continue
			var d := Vector2(p.x - c[0].x, p.z - c[0].z).length()
			if d < c[1] - 0.001 or d > c[2] + 0.001 or not CityLayout.on_road(p.x, p.z) or _on_any_rect(city, p):
				violations += 1
	TestLib.check(violations == 0, "road_point_near stays within [rmin, rmax] on roads outside buildings (%d violations)" % violations)
	TestLib.check(misses == 0, "road_point_near finds a point whenever the ring crosses roads (%d misses)" % misses)
	TestLib.check(city.road_point_near(Vector3(0, 0, 0), 1000.0, 1100.0) == Vector3.INF, "road_point_near returns Vector3.INF when the ring misses the city")
	TestLib.check(city.road_point_near(Vector3(9000, 0, 9000), 10.0, 50.0) == Vector3.INF, "road_point_near returns Vector3.INF far outside the city")
	TestLib.check(city.road_point_near(Vector3(0, 0, 0), 50.0, 20.0) == Vector3.INF, "road_point_near returns Vector3.INF for rmax < rmin")


func _test_inside(city: City) -> void:
	var good := 0
	var total := 0
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		total += 1
		var centre_in := city.is_inside_building(Vector3(lot.cx, lot.h * 0.5, lot.cz))
		var above := city.is_inside_building(Vector3(lot.cx, lot.h + 0.05, lot.cz))
		var below := city.is_inside_building(Vector3(lot.cx, -0.5, lot.cz))
		var low_corner := city.is_inside_building(Vector3(lot.rect.position.x + 0.3, 1.0, lot.rect.position.y + 0.3))
		var outside := city.is_inside_building(Vector3(lot.rect.end.x + 0.3, 1.0, lot.cz))
		if centre_in and not above and not below and low_corner and not outside:
			good += 1
	TestLib.check(good == total, "is_inside_building: inside at mid height, outside above the roof, below ground and beside the footprint (%d/%d)" % [good, total])
	var layout := city.layout
	var on_road := true
	for i in 200:
		var p := city.random_road_point()
		for y in [0.5, 10.0, 60.0]:
			if city.is_inside_building(Vector3(p.x, y, p.z)):
				on_road = false
	TestLib.check(on_road, "no point above a road is inside a building")
	var plaza_ok := true
	for pz in layout.plazas:
		if city.is_inside_building(Vector3(pz.x, 5.0, pz.y)):
			plaza_ok = false
	TestLib.check(plaza_ok, "plazas are open ground")
	# stepped crowns: the ledge beside a crown is open air above the lower part
	var ledge_ok := true
	var checked := 0
	for b in city.building_data:
		var parts: Array = BM.CLASSES[b.cls]
		if parts.size() < 2:
			continue
		var lot: CityLayout.Lot = b.lot
		var p0: Array = parts[0]
		var p1: Array = parts[1]
		# a point over the lower part's footprint but outside the next part's footprint
		var gx: float = lot.cx + (p0[1] - 0.04) * lot.w
		var gz: float = lot.cz + (p0[3] - 0.04) * lot.d
		if gx > lot.cx + p1[1] * lot.w and gz > lot.cz + p1[3] * lot.d:
			checked += 1
			var y_ledge: float = p0[5] * lot.h
			if city.is_inside_building(Vector3(gx, y_ledge + 0.5, gz)) or not city.is_inside_building(Vector3(gx, y_ledge - 0.5, gz)):
				ledge_ok = false
	TestLib.check(ledge_ok and checked > 20, "stepped crowns have open ledges (%d crowns checked)" % checked)


func _test_colliders(host: Node, city: City) -> void:
	var body := city.collision_body
	TestLib.check(body != null and body.collision_layer == Game.L_WORLD and body.collision_mask == 0, "one StaticBody3D on layer world, mask 0")
	var shapes := 0
	var boxes := 0
	for c in body.get_children():
		if c is CollisionShape3D:
			shapes += 1
			if (c as CollisionShape3D).shape is BoxShape3D:
				boxes += 1
	TestLib.check(shapes == boxes and shapes >= city.building_rects.size() + 1 + 4, "collision shapes exist: %d boxes for %d buildings, a ground and four border walls" % [shapes, city.building_rects.size()])
	var space := (host as Node).get_viewport().world_3d.direct_space_state
	# rays straight down onto every roof hit at the building's roof height
	var good := 0
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		var q := PhysicsRayQueryParameters3D.create(Vector3(lot.cx, 300.0, lot.cz), Vector3(lot.cx, -5.0, lot.cz), Game.L_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf(hit.position.y - lot.h) < 0.01 and hit.collider == body:
			good += 1
	TestLib.check(good == city.building_data.size(), "a ray cast down onto a roof hits at the building height (%d/%d)" % [good, city.building_data.size()])
	# ledges are walkable too: the highest point under a ledge sample equals the part top
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(10.0, 300.0, 4.0), Vector3(10.0, -5.0, 4.0), Game.L_WORLD)
	var road_hit := space.intersect_ray(q2)
	TestLib.check(not road_hit.is_empty() and absf(road_hit.position.y) < 0.01, "a ray onto a road hits the ground at y = 0")
	# the border walls stand at HALF + 30
	var qe := PhysicsRayQueryParameters3D.create(Vector3(0.0, 20.0, 5.0), Vector3(600.0, 20.0, 5.0), Game.L_WORLD)
	var wall := space.intersect_ray(qe)
	TestLib.check(not wall.is_empty() and absf(wall.position.x - 350.0) < 0.05, "invisible wall at x = HALF + 30 (hit at %s)" % str(wall.get("position", "none")))
	var qw := PhysicsRayQueryParameters3D.create(Vector3(0.0, 20.0, 5.0), Vector3(0.0, 20.0, -600.0), Game.L_WORLD)
	var wall2 := space.intersect_ray(qw)
	TestLib.check(not wall2.is_empty() and absf(wall2.position.z + 350.0) < 0.05, "invisible wall at z = -(HALF + 30)")
	# a ray along the avenue between two buildings is not blocked by buildings (roads are open)
	var qa := PhysicsRayQueryParameters3D.create(Vector3(-300.0, 1.5, 0.0), Vector3(300.0, 1.5, 0.0), Game.L_WORLD)
	TestLib.check(space.intersect_ray(qa).is_empty(), "the avenue along z = 0 is clear of colliders")
	# masks: the world body does not react to the player layer (mask 0) but is hit by rays on layer world only
	var qp := PhysicsRayQueryParameters3D.create(Vector3(0.0, 300.0, 0.0), Vector3(0.0, -5.0, 0.0), Game.L_ENEMY | Game.L_PLAYER)
	TestLib.check(space.intersect_ray(qp).is_empty(), "the world body lives only on the world layer")
	# City.ground_height agrees with the colliders
	var agree := true
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if absf(city.ground_height(lot.cx, lot.cz) - lot.h) > 0.01:
			agree = false
	TestLib.check(agree and city.ground_height(10.0, 4.0) == 0.0, "ground_height reports roof heights and 0 on roads")


func _test_multimeshes(city: City) -> void:
	var by_name := {}
	for n in city.multimesh_nodes:
		by_name[String(n.name)] = n
	var building_total := 0
	for cls: StringName in BM.ORDER:
		var key := "Buildings_" + String(cls)
		if by_name.has(key):
			building_total += (by_name[key] as MultiMeshInstance3D).multimesh.instance_count
	TestLib.check(building_total == city.building_rects.size(), "building MultiMesh instances add up to the building count (%d)" % building_total)
	TestLib.check(by_name.has("Lamps") and by_name.has("Glow") and by_name.has("Signals"), "lamps, signals and glow sprites are MultiMeshes")
	var expected_lamps: int = preload("res://scripts/world/city_props.gd").lamp_list().size()
	TestLib.check((by_name["Lamps"] as MultiMeshInstance3D).multimesh.instance_count == expected_lamps, "one lamp instance per lamp position (%d)" % expected_lamps)
	TestLib.check((by_name["Signals"] as MultiMeshInstance3D).multimesh.instance_count >= 150, "traffic signals at the junctions")
	TestLib.check((by_name["Glow"] as MultiMeshInstance3D).multimesh.instance_count > expected_lamps, "glow sprites for lamps, signals and signs")
	for key in ["BladeSigns", "RoofAC", "Dumpsters", "Awnings", "Steam"]:
		TestLib.check(by_name.has(key) and (by_name[key] as MultiMeshInstance3D).multimesh.instance_count > 0, "%s has instances" % key)
	# every MultiMesh buffer is consistent with its instance count
	var consistent := true
	for n in city.multimesh_nodes:
		var mm := n.multimesh
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		if mm.buffer.size() != mm.instance_count * stride:
			consistent = false
	TestLib.check(consistent, "every MultiMesh buffer matches its instance count")
	# the first building instance carries the layout transform (scale = size, origin = lot centre)
	var first_lot: CityLayout.Lot = city.building_data[0].lot
	var mmb: MultiMesh = (by_name["Buildings_" + String(city.building_data[0].cls)] as MultiMeshInstance3D).multimesh
	var buf := mmb.buffer          # row-major 3x4 transform: scale on the diagonal, origin in column 4
	TestLib.check(is_equal_approx(buf[0], first_lot.w) and is_equal_approx(buf[5], first_lot.h) and is_equal_approx(buf[10], first_lot.d)
			and is_equal_approx(buf[3], first_lot.cx) and is_equal_approx(buf[7], 0.0) and is_equal_approx(buf[11], first_lot.cz),
			"building instance transform = lot centre and (w, h, d) scale")
	# mirrored city copies share the same MultiMesh resources (no duplicated data)
	var shares := city.mirror_nodes.size() > 0
	for m in city.mirror_nodes:
		var real: MultiMeshInstance3D = by_name.get(String(m.name).trim_suffix("_mirror"))
		if real == null or real.multimesh != m.multimesh:
			shares = false
	TestLib.check(shares, "mirrored copies reuse the real MultiMesh data (%d mirrored families)" % city.mirror_nodes.size())
	# no node creation per building: the whole city is a handful of nodes
	TestLib.check(city.multimesh_nodes.size() <= 60, "the city is %d MultiMesh families (draw-call budget)" % city.multimesh_nodes.size())


func _test_quality(host: Node, city: City) -> void:
	var mirror_root: Node3D = city.get_node("Mirror")
	for level in [0, 1, 2, 0, 2, 1]:
		city.set_quality(level)
		await TestLib.frames(host, 1)
		TestLib.check(city.quality == level, "set_quality(%d) is applied" % level)
		TestLib.check(city.sun.shadow_enabled == (level >= 1), "quality %d: moon shadows %s" % [level, "on" if level >= 1 else "off"])
		TestLib.check(mirror_root.visible == (level >= 1), "quality %d: mirrored reflection pass %s" % [level, "on" if level >= 1 else "off"])
	city.set_quality(-5)
	TestLib.check(city.quality == 0, "set_quality clamps below 0")
	city.set_quality(99)
	TestLib.check(city.quality == 2, "set_quality clamps above 2")
	city.set_quality(1)


func _test_stats(city: City) -> void:
	var s := city.stats()
	print("WORLD STATS ", s)
	TestLib.check(s["buildings"] == 232 and s["colliders"] >= 237, "stats report the city contents")
