extends RefCounted
## World module tests (headless): layout fidelity with the JS prototype, the public API of City, colliders, MultiMesh instance counts and
## the quality tiers. Run: tools/test.sh tests/test_world.gd

const BM := preload("res://scripts/world/building_meshes.gd")
const Stream := preload("res://scripts/world/city_stream.gd")


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
	await _test_prop_colliders(host, city)
	_test_multimeshes(city)
	_test_prop_colours(city)
	_test_skyline(city)
	await _test_quality(host, city)
	await _test_surfaces(host, city)
	await _test_streaming(host, city)
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


## The pooled prop colliders: constant shape count, lamps block the player, low props are cover for rays at knee height but not at head height.
func _test_prop_colliders(host: Node, city: City) -> void:
	var pc := city.prop_colliders()
	TestLib.check(pc.bodies.size() == 56 and pc.shape_count() == 56, "the prop collider pool has 56 bodies and a constant %d shapes" % pc.shape_count())
	TestLib.check(pc.source_count > 1500, "collidable prop instances exist (%d)" % pc.source_count)
	for fam in ["Lamps", "Signals", "Dumpsters", "Kiosks", "Hydrants", "Barriers", "Planters", "RoofHouses", "RoofAC", "RoofCover", "RoofVents"]:
		TestLib.check(pc.instances_of(fam).size() > 0, "%s have collider instances" % fam)
	for fam in ["RoofVents", "RoofPipes", "RoofSkylights", "RoofCover", "Planters"]:
		var found := false
		for n in city.multimesh_nodes:
			if n.name == fam:
				found = true
		TestLib.check(found, "the %s family is drawn" % fam)
	var on_layers := true
	for b in pc.bodies:
		if b.collision_layer != Game.L_WORLD or b.collision_mask != 0:
			on_layers = false
	TestLib.check(on_layers, "pool bodies sit on the world layer")
	var shapes_before := pc.shape_count()
	# a lamp in the open: the pool must cover it, a walking capsule is stopped by the pole
	var lamp: Transform3D = pc.instances_of("Lamps")[40]
	var lp := lamp.origin
	city.update_colliders(Vector3(lp.x, 1.0, lp.z))
	TestLib.check(pc.in_use > 0 and pc.in_use <= 56, "refill assigns instances to the pool (%d in use)" % pc.in_use)
	TestLib.check(pc.shape_count() == shapes_before, "refilling never changes the shape count")
	await TestLib.frames(host, 2)               # moved bodies enter the physics space on the next step
	var space := (host as Node).get_viewport().world_3d.direct_space_state
	var dir := Vector3(1, 0, 0)
	var rq := PhysicsRayQueryParameters3D.create(lp - dir * 3.0 + Vector3(0, 1.0, 0), lp + dir * 3.0 + Vector3(0, 1.0, 0), Game.L_WORLD)
	var hit := space.intersect_ray(rq)
	TestLib.check(not hit.is_empty() and absf((hit.position as Vector3).x - (lp.x - 0.2)) < 0.05, "a ray at chest height hits the lamp pole (%s)" % str(hit.get("position", "none")))
	var walker := CharacterBody3D.new()
	walker.collision_layer = Game.L_PLAYER
	walker.collision_mask = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	walker.add_child(cs)
	host.add_child(walker)
	walker.global_position = Vector3(lp.x - 3.0, 0.95, lp.z)
	for i in 70:
		walker.velocity = Vector3(5.0, 0.0, 0.0)
		walker.move_and_slide()
		await host.get_tree().physics_frame
	TestLib.check(walker.global_position.x < lp.x - 0.2 - 0.4 + 0.1, "walking into a lamp post is blocked (stopped at %.2f m, pole at %.2f)" % [walker.global_position.x, lp.x])
	# the same walker walks freely where nothing stands (a position on the open avenue)
	walker.global_position = Vector3(-200.0, 0.95, 0.0)
	city.update_colliders(Vector3(-200.0, 1.0, 0.0))
	for i in 20:
		walker.velocity = Vector3(5.0, 0.0, 0.0)
		walker.move_and_slide()
		await host.get_tree().physics_frame
	TestLib.check(walker.global_position.x > -200.0 + 0.8, "the open avenue is not blocked by the pool (moved to x = %.2f)" % walker.global_position.x)
	walker.queue_free()
	# cover: a dumpster is knee / waist high, so a low ray is stopped and a head-high ray passes over it
	var dump: Transform3D = pc.instances_of("Dumpsters")[3]
	var dp := dump.origin
	city.update_colliders(Vector3(dp.x, 1.0, dp.z))
	await TestLib.frames(host, 2)
	var along := dump.basis * Vector3(0, 0, 1)
	var low := PhysicsRayQueryParameters3D.create(dp - along * 4.0 + Vector3(0, 0.6, 0), dp + along * 4.0 + Vector3(0, 0.6, 0), Game.L_WORLD)
	var high := PhysicsRayQueryParameters3D.create(dp - along * 4.0 + Vector3(0, 1.7, 0), dp + along * 4.0 + Vector3(0, 1.7, 0), Game.L_WORLD)
	TestLib.check(not space.intersect_ray(low).is_empty(), "a ray at waist height is stopped by a dumpster (cover)")
	TestLib.check(space.intersect_ray(high).is_empty(), "a ray at head height passes over a dumpster")
	# roofs: the pool follows the player up onto a roof and takes the cover walls there
	var cover: Transform3D = pc.instances_of("RoofCover")[5]
	city.update_colliders(cover.origin + Vector3(0, 1.0, 0))
	var roof_seen := false
	for k in pc.bodies.size():
		if pc.family_of(k).begins_with("Roof"):
			roof_seen = true
	TestLib.check(roof_seen, "on a roof the pool holds rooftop colliders")
	var street_has_roof := false
	city.update_colliders(Vector3(-200.0, 1.0, 0.0))
	for k in pc.bodies.size():
		if pc.family_of(k).begins_with("Roof"):
			street_has_roof = true
	TestLib.check(not street_has_roof, "on the street the pool ignores rooftop colliders")
	city.update_colliders(Vector3(0.0, -2000.0, 0.0))
	TestLib.check(pc.in_use == 0, "far from the city every body is parked")
	var parked := true
	for b in pc.bodies:
		if b.position.y > -900.0:
			parked = false
	TestLib.check(parked, "parked bodies wait far below the city")


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
	TestLib.check(city.multimesh_nodes.size() <= 66, "the city is %d MultiMesh families (draw-call budget)" % city.multimesh_nodes.size())


## The Compatibility (GL) renderer reads a mesh's vertex COLOR as 0 when its MultiMesh has no instance colours (flat slabs, green poles,
## lost emission codes). Every family whose mesh carries vertex colours must therefore enable instance colours (written white).
func _test_prop_colours(city: City) -> void:
	var bad: Array[String] = []
	var with_colours := 0
	for n in city.multimesh_nodes:
		var mm := n.multimesh
		var has_vertex_colour := false
		for si in mm.mesh.get_surface_count():
			var arr := mm.mesh.surface_get_arrays(si)
			if arr[Mesh.ARRAY_COLOR] != null and (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0:
				has_vertex_colour = true
		if has_vertex_colour:
			with_colours += 1
			if not mm.use_colors:
				bad.append(String(n.name))
			else:
				# the instance colour must be white, or the vertex colour is tinted
				var stride := 12 + 4 + (4 if mm.use_custom_data else 0)
				var buf := mm.buffer
				if n.name != &"LampShafts" and n.name != &"Glow" and buf.size() >= stride and not (is_equal_approx(buf[12], 1.0) and is_equal_approx(buf[15], 1.0)):
					bad.append(String(n.name) + " (instance colour not white)")
	TestLib.check(with_colours >= 15 and bad.is_empty(), "families with vertex colours (%d) enable white instance colours for the GL renderer: %s" % [with_colours, str(bad)])


## The far skyline is visual only (no colliders): no tower may reach into the walkable square or the invisible border walls.
func _test_skyline(city: City) -> void:
	var keep := CityLayout.WALK + CityLayout.WALL_T
	var inside := 0
	for r in city.skyline_rects:
		if r.end.x > -keep and r.position.x < keep and r.end.y > -keep and r.position.y < keep:
			inside += 1
	TestLib.check(city.skyline_rects.size() > 800, "the far skyline still has its towers (%d)" % city.skyline_rects.size())
	TestLib.check(inside == 0, "no far-skyline tower reaches into the walkable square or the border walls (%d do)" % inside)
	var counted := 0
	for n in city.multimesh_nodes:
		if String(n.name).begins_with("Skyline_"):
			counted += n.multimesh.instance_count
	TestLib.check(counted == city.skyline_rects.size(), "skyline MultiMesh instances match the placed towers (%d)" % counted)
	# a physics capsule-sized probe at the wall line finds no tower (they are 4 m or more behind the wall) and the ring road side is open
	var wall_clear := true
	for r in city.skyline_rects:
		if r.grow(1.0).has_point(Vector2(CityLayout.WALK + 1.0, 0.0)) or r.grow(1.0).has_point(Vector2(0.0, CityLayout.WALK + 1.0)):
			wall_clear = false
	TestLib.check(wall_clear, "no tower stands against the wall faces")


func _family(city: City, family_name: String) -> Stream.Family:
	for f: Stream.Family in city.stream_families():
		if f.name == family_name:
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


## The prop and skyline families only draw the instances near the camera (a MultiMesh of the whole city has one bounding box and can
## never be frustum culled): the window must be complete, follow the camera, and keep the triangle budget.
func _test_streaming(host: Node, city: City) -> void:
	var families := city.stream_families()
	TestLib.check(families.size() >= 20, "%d families are windowed around the camera" % families.size())
	var names: Array[String] = []
	for f: Stream.Family in families:
		names.append(f.name)
	for need in ["Lamps", "Trash", "FireEscapes", "Dumpsters", "Signals", "LampShafts", "RoofAC", "Skyline_tiered", "Billboards"]:
		TestLib.check(need in names, "%s is windowed" % need)
	city.set_quality(1)
	var spawn := Vector2(Game.SPAWN.x, Game.SPAWN.z)
	city.update_streaming(spawn, true)
	var lamps := _family(city, "Lamps")
	var trash := _family(city, "Trash")
	TestLib.check(lamps.shown > 0 and lamps.shown < lamps.total, "at the spawn the lamps are windowed (%d of %d drawn)" % [lamps.shown, lamps.total])
	TestLib.check(trash.shown > 0 and trash.shown < trash.total * 0.35, "short-range clutter is windowed hard (%d of %d trash heaps drawn)" % [trash.shown, trash.total])
	var complete := true
	for f: Stream.Family in families:
		if not _window_complete(f, spawn):
			complete = false
			printerr("window of ", f.name, " is missing instances")
	TestLib.check(complete, "every instance within a family's fade distance of the camera is drawn")
	var drawn := city.stats()
	var tris: int = int(drawn["triangles_drawn"]) + int(drawn["triangles_drawn_mirror"])
	TestLib.check(tris < 160000, "medium tier at the spawn draws %d triangles (all families and the mirrored copies; budget 300k for the whole frame)" % tris)
	# the camera moves: the window follows, the instances near it are always there (non-forced updates, one per frame, like _process)
	var covered := true
	var rebuilt := 0
	var last := lamps.built_at
	for step in 600:
		var x := -300.0 + float(step) * 1.0
		var cam := Vector2(x, 4.0 + 0.4 * float(step % 9))
		city.update_streaming(cam, false)
		if lamps.built_at != last:
			rebuilt += 1
			last = lamps.built_at
		if step % 7 == 0:
			for fname in ["Lamps", "Signals", "Dumpsters", "Awnings", "Skyline_tiered", "RoofAC"]:
				if not _window_complete(_family(city, fname), cam):
					covered = false
	TestLib.check(covered, "while the camera drives 600 m along the avenue (1 m per update) no instance near it is ever missing")
	TestLib.check(rebuilt > 5 and rebuilt < 120, "the window is rebuilt every few metres, not every frame (%d rebuilds in 600 updates)" % rebuilt)
	# a teleport (respawn, blink, camera cut) is caught up at once
	city.update_streaming(Vector2(250.0, -250.0), false)
	TestLib.check(_window_complete(_family(city, "Lamps"), Vector2(250.0, -250.0)) and _window_complete(_family(city, "Trash"), Vector2(250.0, -250.0)),
			"after a 500 m jump every window is complete in the same update")
	# far outside the city nothing but the always-on families (buildings, glow, steam, holograms) is drawn
	city.update_streaming(Vector2(9000.0, 9000.0), true)
	var none := true
	for f: Stream.Family in families:
		if f.shown != 0:
			none = false
	TestLib.check(none, "far from the city the windowed families draw nothing")
	# quality scales the radii
	city.set_quality(0)
	city.update_streaming(spawn, true)
	var low_shown := lamps.shown
	city.set_quality(2)
	city.update_streaming(spawn, true)
	var high_shown := lamps.shown
	TestLib.check(low_shown < high_shown, "the low tier draws a smaller window than the high tier (lamps %d < %d)" % [low_shown, high_shown])
	var tiers: Array[int] = []
	for level in [0, 1, 2]:
		city.set_quality(level)
		city.update_streaming(spawn, true)
		var st := city.stats()
		tiers.append(int(st["triangles_drawn"]) + int(st["triangles_drawn_mirror"]))
	TestLib.check(tiers[0] < tiers[1] and tiers[1] < tiers[2] and tiers[2] < 260000, "triangles per tier at the spawn: LOW %d < MED %d < HIGH %d (budget MED 300k, HIGH 800k)" % [tiers[0], tiers[1], tiers[2]])
	# switching the windows off shows everything again
	city.stream_enabled = false
	var all_shown := true
	for f: Stream.Family in families:
		if f.mm.visible_instance_count != f.total or f.mm.buffer.size() != f.total * f.stride:
			all_shown = false
	TestLib.check(all_shown, "stream_enabled = false draws every instance again")
	city.stream_enabled = true
	city.set_quality(1)
	await TestLib.frames(host, 1)


func _test_quality(host: Node, city: City) -> void:
	var mirror_root: Node3D = city.get_node("Mirror")
	for level in [0, 1, 2, 0, 2, 1]:
		city.set_quality(level)
		await TestLib.frames(host, 1)
		TestLib.check(city.quality == level, "set_quality(%d) is applied" % level)
		TestLib.check(city.sun.shadow_enabled == (level >= 1), "quality %d: moon shadows %s" % [level, "on" if level >= 1 else "off"])
		TestLib.check(mirror_root.visible == (level >= 1), "quality %d: mirrored reflection pass %s" % [level, "on" if level >= 1 else "off"])
	# tier rules: families that only exist from a given tier up, steam density by tier
	var by_name := {}
	for n in city.multimesh_nodes:
		by_name[String(n.name)] = n
	for n in city.mirror_nodes:
		by_name[String(n.name)] = n
	city.set_quality(0)
	var steam: MultiMeshInstance3D = by_name["Steam"]
	var steam_low := steam.multimesh.visible_instance_count
	TestLib.check(not (by_name["Trash"] as Node3D).visible and (by_name["LampShafts"] as Node3D).visible, "quality 0 drops trash (the lamp light shafts stay, windowed smaller)")
	city.set_quality(1)
	var steam_med := steam.multimesh.visible_instance_count
	TestLib.check((by_name["Trash"] as Node3D).visible and (by_name["LampShafts"] as Node3D).visible, "quality 1 shows trash and light shafts")
	TestLib.check(not (by_name["Skyline_block_mirror"] as Node3D).visible, "quality 1 skips the far-skyline reflections")
	city.set_quality(2)
	TestLib.check((by_name["Skyline_block_mirror"] as Node3D).visible and (by_name["Holograms_mirror"] as Node3D).visible, "quality 2 reflects the far skyline and holograms")
	TestLib.check(steam_low < steam_med and steam_med < steam.multimesh.visible_instance_count, "steam density grows with the quality tier (%d < %d < %d)" % [steam_low, steam_med, steam.multimesh.visible_instance_count])
	city.set_quality(-5)
	TestLib.check(city.quality == 0, "set_quality clamps below 0")
	city.set_quality(99)
	TestLib.check(city.quality == 2, "set_quality clamps above 2")
	city.set_quality(1)


## Tier-scaled PBR surfaces (SurfaceTextures, assets/shaders/surface_tex.gdshaderinc): files, import settings, per-tier taps, samplers, memory estimate.
func _test_surfaces(host: Node, city: City) -> void:
	var stems := ["asphalt", "sidewalk", "brick", "concrete", "corrugated", "painted_metal", "roof_tar", "trim"]
	var all_there := true
	var packed := true
	for st in stems:
		for suffix in ["albedo", "normal"]:
			var path := "res://assets/textures/surface_%s_%s.png" % [st, suffix]
			all_there = all_there and ResourceLoader.exists(path)
			var imp := FileAccess.get_file_as_string(path + ".import")
			packed = packed and imp.contains("compress/mode=2") and imp.contains("mipmaps/generate=true") and imp.contains("compress/normal_map=2")
	TestLib.check(all_there and ResourceLoader.exists("res://assets/textures/surface_decals.png"), "the 8 surface sets and the decal mask are imported")
	TestLib.check(packed, "surface textures are VRAM compressed with mipmaps, packed normals stay colour textures")
	TestLib.check(PerfTiers.surface_taps(0) == 0 and PerfTiers.surface_taps(1) == 1 and PerfTiers.surface_taps(2) == 2, "taps per tier: LOW 0, MED 1, HIGH 2")
	TestLib.check(PerfTiers.surface_mip_bias(2) < PerfTiers.surface_mip_bias(1), "HIGH samples the surfaces sharper than MED")
	var ground: ShaderMaterial = city._ground.material
	var bmat: ShaderMaterial = city._building_mat
	var want := {0: [0.0, 0.0], 1: [1.0, 0.0], 2: [1.0, 1.0]}
	for level in [0, 1, 2]:
		city.set_quality(level)
		await TestLib.frames(host, 2)
		var ok := is_equal_approx(float(ground.get_shader_parameter(&"srf_k")), want[level][0]) and is_equal_approx(float(ground.get_shader_parameter(&"srf_hi")), want[level][1])
		ok = ok and is_equal_approx(float(bmat.get_shader_parameter(&"srf_k")), want[level][0])
		TestLib.check(ok, "quality %d: surface taps k=%s hi=%s on ground and buildings" % [level, want[level][0], want[level][1]])
		var road = ground.get_shader_parameter(&"srf_road_a")
		var brick = bmat.get_shader_parameter(&"srf_brick_n")
		TestLib.check((road == null) == (level == 0) and (brick == null) == (level == 0), "quality %d: surface textures %s" % [level, "not loaded" if level == 0 else "bound"])
		var decal = ground.get_shader_parameter(&"srf_decal")
		TestLib.check((decal != null) == (level == 2), "quality %d: decal mask %s" % [level, "bound" if level == 2 else "not bound"])
	var med := SurfaceTextures.estimate_bytes(1)
	var high := SurfaceTextures.estimate_bytes(2)
	TestLib.check(SurfaceTextures.estimate_bytes(0) == 0 and med > 0 and med < 40_000_000 and high < 90_000_000 and med < high,
			"surface texture memory: LOW 0, MED %.1f MB (limit 40), HIGH %.1f MB (limit 90)" % [med / 1e6, high / 1e6])
	for m: ShaderMaterial in city._prop_mats:
		TestLib.check(is_equal_approx(float(m.get_shader_parameter(&"srf_k")), 1.0), "prop material carries the surface taps at the last tier (HIGH)")
		break
	city.set_quality(1)


func _test_stats(city: City) -> void:
	var s := city.stats()
	print("WORLD STATS ", s)
	TestLib.check(s["buildings"] == 232 and s["colliders"] >= 237, "stats report the city contents")
