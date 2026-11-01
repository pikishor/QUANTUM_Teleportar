extends RefCounted
## Interior generator tests (headless): the type library, determinism by seed (and independence of the graphics tier), the room graph, walkability (an independent flood fill plus
## physics capsule queries at the door, the anchors and the doorways), collision presence (rays hit the floor, ceiling, walls and the closed street door), the guaranteed anchors,
## the interface of docs/interiors_interface.md, draw / triangle / light budgets per type and tier, build time, ambience hooks and the InteriorSpace queries.
## Leaks, the camera and the enemies are in tests/test_interiors_world.gd. Run: tools/test.sh tests/test_interiors.gd

const ORIGIN := Vector3(900.0, 600.0, 900.0)
const SEEDS := [1, 2, 3, 7, 11, 23]
const INTERFACE_TYPES: Array[StringName] = [&"weapons", &"clinic", &"tech", &"bar", &"club", &"lobby", &"apartment", &"checkpoint"]
const WANT_ANCHORS := {
	&"weapons": {&"vendor": 1, &"civilian": 4, &"safe": 1}, &"clinic": {&"vendor": 1, &"civilian": 4}, &"tech": {&"vendor": 1, &"civilian": 4, &"guard": 4, &"terminal": 1},
	&"bar": {&"vendor": 1, &"civilian": 4}, &"club": {&"civilian": 4, &"guard": 4, &"officer": 1}, &"lobby": {&"civilian": 4, &"guard": 4, &"safe": 1},
	&"apartment": {&"civilian": 4, &"guard": 4, &"safe": 1, &"hostage": 1}, &"checkpoint": {&"guard": 4, &"terminal": 1},
}

var root: Node3D


func run(host: Node) -> void:
	root = Node3D.new()
	root.name = "InteriorTestRoot"
	host.add_child(root)
	_types()
	_determinism()
	_room_graph()
	_walkability()
	await _physics(host)
	_anchors()
	_interface()
	await _budgets(host)
	_ambience()
	await _space(host)
	_quality_scaling(host)


# ---------------------------------------------------------------------------------------------------------------------

func _types() -> void:
	TestLib.check(InteriorGen.TYPES.size() >= 8, "the library has at least 8 interior types (%d)" % InteriorGen.TYPES.size())
	for t in INTERFACE_TYPES:
		TestLib.check(InteriorGen.TYPES.has(t), "interface type %s is in TYPES" % t)
	for t in InteriorGen.TYPES:
		TestLib.check(InteriorKinds.has_type(t), "%s has a spec" % t)
		var spec := InteriorKinds.spec(t)
		TestLib.check((spec["rooms"] as Array).size() >= 1 and (spec["rooms"] as Array).size() <= 4, "%s: 1-4 room recipes" % t)
	TestLib.check(InteriorGen.type_for_id(7) == InteriorGen.TYPES[7 % InteriorGen.TYPES.size()], "type_for_id is a stable hash")
	TestLib.check(InteriorKinds.TYPES == InteriorGen.TYPES, "InteriorKinds.TYPES matches InteriorGen.TYPES")


func _determinism() -> void:
	var all_same := true
	var diverse := true
	for t in InteriorGen.TYPES:
		var sigs := {}
		for sd in SEEDS:
			var a := InteriorPlan.generate(t, sd).signature()
			var b := InteriorPlan.generate(t, sd).signature()
			if a != b:
				all_same = false
				TestLib.check(false, "%s seed %d generates the same plan twice" % [t, sd])
			sigs[a] = true
		if sigs.size() < 4:
			diverse = false
			TestLib.check(false, "%s: seeds give different rooms (%d distinct of %d)" % [t, sigs.size(), SEEDS.size()])
	TestLib.check(all_same, "the same (type, seed) always gives the identical plan (10 types x %d seeds)" % SEEDS.size())
	TestLib.check(diverse, "different seeds give different interiors")
	# the tier must not change the layout, the colliders or the anchors
	var tier_same := true
	for t in InteriorGen.TYPES:
		InteriorGen.clear_cache()
		var n0 := InteriorGen.build(t, 5, ORIGIN, 0) as Interior
		var n2 := InteriorGen.build(t, 5, ORIGIN, 2) as Interior
		if n0.plan.signature() != n2.plan.signature() or n0.door_pos != n2.door_pos or n0.bounds != n2.bounds or n0.stats()["shapes"] != n2.stats()["shapes"]:
			tier_same = false
		n0.free()
		n2.free()
	TestLib.check(tier_same, "LOW and HIGH build the same rooms, colliders, door and bounds")
	InteriorGen.clear_cache()
	var u1 := InteriorGen.build(&"club", 9, ORIGIN, 1) as Interior
	var u2 := InteriorGen.build(&"club", 9, ORIGIN, 1) as Interior
	TestLib.check(u1.stats()["tris"] == u2.stats()["tris"] and u1.door_pos == u2.door_pos, "two builds of one door are identical (cache hit)")
	u1.free()
	u2.free()


func _room_graph() -> void:
	var counts := {}
	var connected := true
	var doors_ok := true
	var one_street_door := true
	var in_span := true
	for t in InteriorGen.TYPES:
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd)
			var n := plan.rooms.size()
			counts[n] = true
			TestLib.check(n >= 1 and n <= 4, "%s/%d has 1-4 rooms (%d)" % [t, sd, n])
			# BFS over the doors
			var seen := {0: true}
			var queue := [0]
			while not queue.is_empty():
				var cur: int = queue.pop_front()
				for dd: Dictionary in plan.doors:
					var other := -2
					if int(dd["a"]) == cur:
						other = int(dd["b"])
					elif int(dd["b"]) == cur:
						other = int(dd["a"])
					if other >= 0 and not seen.has(other):
						seen[other] = true
						queue.append(other)
			if seen.size() != n:
				connected = false
				TestLib.check(false, "%s/%d: every room reachable through doors (%d of %d)" % [t, sd, seen.size(), n])
			var street := 0
			for dd: Dictionary in plan.doors:
				if float(dd["w"]) < 1.2:
					doors_ok = false
				if int(dd["b"]) < 0:
					street += 1
			if street != 1:
				one_street_door = false
			if InteriorPlan.DOOR_H < 2.2:
				doors_ok = false
			if plan.bounds.size.x > 36.0 or plan.bounds.size.y > 36.0:
				in_span = false
			for r: Dictionary in plan.rooms:
				if float(r["h"]) < 2.7 or float(r["h"]) > 6.5:
					in_span = false
	TestLib.check(connected, "the room graph is connected for every type and seed")
	TestLib.check(doors_ok, "every doorway is at least 1.2 m wide and 2.2 m tall")
	TestLib.check(one_street_door, "exactly one street door per interior")
	TestLib.check(in_span, "footprints fit 36 m, ceilings 2.7-6.5 m")
	TestLib.check(counts.size() >= 3, "room counts vary across seeds and types (%s)" % str(counts.keys()))


func _walkability() -> void:
	var bad := 0
	var checked := 0
	var removed := 0
	for t in InteriorGen.TYPES:
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd)
			removed += plan.removed_props
			var unreachable := _flood(plan)
			checked += 1
			if not unreachable.is_empty():
				bad += 1
				TestLib.check(false, "%s/%d: entrance reaches every room and anchor with a 0.3 m body (unreachable: %s)" % [t, sd, str(unreachable)])
	TestLib.check(bad == 0, "every interior is walkable from the door to every room and anchor (%d plans, independent 0.25 m flood fill)" % checked)
	TestLib.check(removed <= checked, "the walkability repair rarely has to drop furniture (%d props in %d plans)" % [removed, checked])


## Independent flood fill (0.25 m cells, body radius 0.3) over the plan's colliders: what is unreachable from the door position.
func _flood(plan: InteriorPlan) -> Array:
	var cell := 0.25
	var b := plan.bounds.grow(0.5)
	var nx := int(ceil(b.size.x / cell))
	var nz := int(ceil(b.size.y / cell))
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	var floor_ok := PackedByteArray()
	floor_ok.resize(nx * nz)
	for bx: AABB in plan.colliders:
		if bx.end.y < 0.2 or bx.position.y > 1.6:
			continue
		_fill(blocked, nx, nz, b, cell, Rect2(bx.position.x - 0.3, bx.position.z - 0.3, bx.size.x + 0.6, bx.size.z + 0.6))
	for dd: Dictionary in plan.doors:   # the street door is closed (its plug is a collider): nothing to add
		pass
	var start := Vector2(plan.entry.x, plan.entry.z)
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var q := PackedInt32Array()
	var si := int((start.x - b.position.x) / cell) + int((start.y - b.position.y) / cell) * nx
	q.append(si)
	seen[si] = 1
	var head := 0
	while head < q.size():
		var cur := q[head]
		head += 1
		var cx := cur % nx
		var cz := cur / nx
		for k in 4:
			var ax := cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var az := cz + (1 if k == 2 else (-1 if k == 3 else 0))
			if ax < 0 or az < 0 or ax >= nx or az >= nz:
				continue
			var ni := ax + az * nx
			if seen[ni] == 1 or blocked[ni] == 1:
				continue
			seen[ni] = 1
			q.append(ni)
	var out: Array = []
	if blocked[si] == 1:
		out.append("entry blocked")
	for i in plan.rooms.size():
		var r: Rect2 = (plan.rooms[i]["rect"] as Rect2).grow(-0.4)
		var found := false
		var x := r.position.x
		while x < r.end.x and not found:
			var z := r.position.y
			while z < r.end.y:
				var ci := int((x - b.position.x) / cell) + int((z - b.position.y) / cell) * nx
				if seen[ci] == 1:
					found = true
					break
				z += cell
			x += cell
		if not found:
			out.append("room %d" % i)
	for kind in plan.anchors:
		for a: Dictionary in plan.anchors[kind]:
			var p: Vector3 = a["pos"]
			var ci := int((p.x - b.position.x) / cell) + int((p.z - b.position.y) / cell) * nx
			if seen[ci] != 1:
				out.append("%s at (%.1f, %.1f)" % [kind, p.x, p.z])
	return out


func _fill(grid: PackedByteArray, nx: int, nz: int, b: Rect2, cell: float, rect: Rect2) -> void:
	var x0 := maxi(int(floor((rect.position.x - b.position.x) / cell)), 0)
	var x1 := mini(int(ceil((rect.end.x - b.position.x) / cell)), nx - 1)
	var z0 := maxi(int(floor((rect.position.y - b.position.y) / cell)), 0)
	var z1 := mini(int(ceil((rect.end.y - b.position.y) / cell)), nz - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var cx := b.position.x + (float(x) + 0.5) * cell
			var cz := b.position.y + (float(z) + 0.5) * cell
			if cx >= rect.position.x and cx < rect.end.x and cz >= rect.position.y and cz < rect.end.y:
				grid[x + z * nx] = 1


func _physics(host: Node) -> void:
	var space_checked := 0
	var rays_ok := true
	var caps_ok := true
	var floor_ok := true
	var plug_ok := true
	var no_collision_types := []
	for t in InteriorGen.TYPES:
		var it := InteriorGen.build(t, 4, ORIGIN, 1) as Interior
		root.add_child(it)
		await TestLib.frames(host, 2)
		var space := root.get_world_3d().direct_space_state
		var body := it.collider_body()
		if body == null or body.collision_layer != 1 or body.get_child_count() < 12:
			no_collision_types.append(t)
		var plan := it.plan
		var r0: Rect2 = plan.rooms[0]["rect"]
		# rays from points of every room in 8 directions hit a wall or prop within the footprint; floor and ceiling are at the right heights
		for ri in plan.rooms.size():
			var rc: Rect2 = plan.rooms[ri]["rect"]
			var floor_hit := false
			var ceil_hit := false
			for off in [Vector2(0, 0), Vector2(1.3, 0), Vector2(-1.3, 0), Vector2(0, 1.2), Vector2(0, -1.2), Vector2(1.3, 1.2), Vector2(-1.3, -1.2)]:
				var cc := rc.get_center() + (off as Vector2)
				var c := ORIGIN + Vector3(cc.x, 1.1, cc.y)
				var hh := float(plan.rooms[ri]["h"])
				var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(ORIGIN + Vector3(cc.x, hh - 0.3, cc.y), c - Vector3(0, 3.0, 0), 1))
				if not down.is_empty() and absf((down["position"] as Vector3).y - ORIGIN.y) < 0.05:
					floor_hit = true
				var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(ORIGIN + Vector3(cc.x, 0.15, cc.y), c + Vector3(0, 12.0, 0), 1))
				if not up.is_empty() and absf((up["position"] as Vector3).y - (ORIGIN.y + hh)) < 0.05:
					ceil_hit = true
				if off == Vector2.ZERO:
					for k in 8:
						var a := float(k) * TAU / 8.0
						var q := PhysicsRayQueryParameters3D.create(c, c + Vector3(cos(a), 0.0, sin(a)) * 40.0, 1)
						if space.intersect_ray(q).is_empty():
							rays_ok = false
			if not floor_hit or not ceil_hit:
				floor_ok = false
		# the closed street door: a ray from the door position straight at the street hits the plug before the outside
		var from := ORIGIN + Vector3(plan.entry.x, 1.0, plan.entry.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 0, 6.0), 1))
		if hit.is_empty() or (hit["position"] as Vector3).z > ORIGIN.z + r0.end.y + 0.2:
			plug_ok = false
		# a 0.35 m x 1.8 m capsule fits at the door position, every anchor and the middle of every inner doorway
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		var spots: Array[Vector3] = [it.door_pos]
		for kind in plan.anchors:
			for a: Dictionary in it.anchors(kind):
				spots.append(a["pos"])
		for dd: Dictionary in plan.doors:
			if int(dd["b"]) >= 0:
				var pos := Vector3(float(dd["c"]), 0.0, float(dd["line"])) if int(dd["axis"]) == 0 else Vector3(float(dd["line"]), 0.0, float(dd["c"]))
				spots.append(ORIGIN + pos)
		for s: Vector3 in spots:
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.collision_mask = 1
			qp.transform = Transform3D(Basis(), s + Vector3(0, 0.92, 0))
			space_checked += 1
			if not space.intersect_shape(qp, 1).is_empty():
				caps_ok = false
				TestLib.check(false, "%s: a hero capsule fits at (%.1f, %.1f)" % [t, s.x - ORIGIN.x, s.z - ORIGIN.z])
		it.queue_free()
		await TestLib.frames(host, 1)
	TestLib.check(no_collision_types.is_empty(), "every interior has a world-layer StaticBody3D with box shapes (missing: %s)" % str(no_collision_types))
	TestLib.check(rays_ok, "rays from the middle of every room hit a wall in all 8 directions (the interiors are closed)")
	TestLib.check(floor_ok, "floor and ceiling colliders are at the right heights in every room")
	TestLib.check(plug_ok, "the street door is closed: the way out is the door interaction, never a walk-through")
	TestLib.check(caps_ok, "a hero capsule fits at the door, every anchor and every inner doorway (%d physics queries)" % space_checked)


func _anchors() -> void:
	var ok := true
	for t in WANT_ANCHORS:
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd)
			var want: Dictionary = WANT_ANCHORS[t]
			for kind: StringName in want:
				var have := (plan.anchors.get(kind, []) as Array).size()
				if have < int(want[kind]):
					ok = false
					TestLib.check(false, "%s/%d has %d '%s' anchors (want %d)" % [t, sd, have, kind, int(want[kind])])
	TestLib.check(ok, "every interface type guarantees its anchors (vendor, civilian, guard, safe, hostage, terminal, officer)")
	var extra_ok := true
	for t in [&"bodega", &"warehouse"]:
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd)
			extra_ok = extra_ok and (plan.anchors.get(&"civilian", []) as Array).size() >= 4
			extra_ok = extra_ok and (t != &"bodega" or (plan.anchors.get(&"vendor", []) as Array).size() >= 1)
			extra_ok = extra_ok and (t != &"warehouse" or (plan.anchors.get(&"guard", []) as Array).size() >= 4)
	TestLib.check(extra_ok, "bodega has a vendor and civilians, warehouse guards and workers")
	# a counter or barrier stands between the vendor and the door (the vendor is behind the counter)
	var vend_ok := true
	for t in [&"weapons", &"clinic", &"tech", &"bar", &"bodega"]:
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd)
			var v: Vector3 = (plan.anchors[&"vendor"] as Array)[0]["pos"]
			var found := false
			for p: Dictionary in plan.props:
				if p["kind"] in ["counter", "bar"]:
					var pos: Vector3 = p["pos"]
					var to_v := Vector2(v.x - pos.x, v.z - pos.z)
					var to_door := Vector2(plan.entry.x - pos.x, plan.entry.z - pos.z)
					if to_v.length() < 2.5 and to_v.dot(to_door) < 0.0:
						found = true
			if not found:
				vend_ok = false
				TestLib.check(false, "%s/%d: a counter stands between the vendor and the door" % [t, sd])
	TestLib.check(vend_ok, "the vendor stands behind a counter, on the far side from the door")


func _interface() -> void:
	var ok := true
	var yaw_ok := true
	var wall_clear := true
	var exit_ok := true
	var rect_ok := true
	for t in InteriorGen.TYPES:
		for sd in [1, 2, 3]:
			InteriorGen.clear_cache()
			var it := InteriorGen.build(t, sd, ORIGIN, 1) as Interior
			ok = ok and it.type == t and it.seed == sd and it.bounds.has_point(Vector2(it.door_pos.x, it.door_pos.z)) and absf(it.door_pos.y - ORIGIN.y) < 0.01
			ok = ok and it.position == ORIGIN and is_equal_approx(it.exit_pos.y, ORIGIN.y)
			# arrives >= 0.8 m from any wall; faces into the room (-Z forward means yaw 0 looks toward the back wall)
			var dp := Vector2(it.door_pos.x, it.door_pos.z)
			for wr: Rect2 in it.wall_rects:
				var dx := maxf(maxf(wr.position.x - dp.x, 0.0), dp.x - wr.end.x)
				var dz := maxf(maxf(wr.position.y - dp.y, 0.0), dp.y - wr.end.y)
				var ig := wr.size.y > 0.3 and wr.size.x > 0.3 and wr.size.x * wr.size.y > 0.3          # big furniture rects are checked by the capsule test
				if sqrt(dx * dx + dz * dz) < 0.8 and not ig:
					wall_clear = false
			yaw_ok = yaw_ok and absf(it.door_yaw) < 0.01
			exit_ok = exit_ok and it.exit_pos.distance_to(it.door_pos) <= 2.5 and it.exit_pos.distance_to(it.door_pos) > 0.5
			rect_ok = rect_ok and it.floor_rects.size() >= it.plan.rooms.size() and it.wall_rects.size() >= 8 and it.wall_segments().size() >= 16
			rect_ok = rect_ok and it.anchors(&"does_not_exist").is_empty()
			it.free()
	TestLib.check(ok, "Interior carries type, seed, bounds, door_pos and exit_pos in world coordinates at the origin")
	TestLib.check(wall_clear, "door_pos is at least 0.8 m from every wall")
	TestLib.check(yaw_ok, "door_yaw faces into the room")
	TestLib.check(exit_ok, "exit_pos is within 2.5 m of door_pos (the USE reach of the interface)")
	TestLib.check(rect_ok, "floor_rects, wall_rects and wall_segments are filled for the minimap")


func _budgets(host: Node) -> void:
	var worst_ms := 0.0
	var max_tris := [0, 0, 0]
	var max_draws := 0
	var tier_ok := true
	var light_ok := true
	var mono_ok := true
	for t in InteriorGen.TYPES:
		for sd in [1, 2, 3]:
			var drawn := [0, 0, 0]
			for q in 3:
				InteriorGen.clear_cache()
				var t0 := Time.get_ticks_usec()
				var it := InteriorGen.build(t, sd, ORIGIN, q) as Interior
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				worst_ms = maxf(worst_ms, ms)
				var st := it.stats()
				max_tris[q] = maxi(max_tris[q], int(st["tris"]))
				max_draws = maxi(max_draws, int(st["draws"]))
				drawn[q] = int(st["props_drawn"])
				if int(st["lights"]) > (1 if q == 0 else 2) or int(st["lights"]) < 1:
					light_ok = false
				if int(st["draws"]) > 4:
					tier_ok = false
				it.free()
			if not (drawn[0] <= drawn[1] and drawn[1] <= drawn[2]):
				mono_ok = false
	TestLib.check(max_draws <= 4, "an interior is at most 4 draw calls (%d)" % max_draws)
	TestLib.check(max_tris[0] <= 40000 and max_tris[1] <= 60000 and max_tris[2] <= 120000, "triangles stay inside the budgets: LOW %d / 40k, MED %d / 60k, HIGH %d / 120k" % [max_tris[0], max_tris[1], max_tris[2]])
	TestLib.check(tier_ok, "draw calls never exceed 4 on any tier")
	TestLib.check(light_ok, "at most two real lights (LOW one), no shadows")
	TestLib.check(mono_ok, "a lower tier draws fewer or equal props than a higher one")
	TestLib.check(worst_ms < 500.0, "building an interior (plan + meshes + nodes, cold caches) takes %.0f ms worst case, under the 0.5 s budget" % worst_ms)
	# the cached re-entry is much cheaper
	var it1 := InteriorGen.build(&"club", 3, ORIGIN, 1) as Interior
	var t1 := Time.get_ticks_usec()
	var it2 := InteriorGen.build(&"club", 3, ORIGIN, 1) as Interior
	var warm := (Time.get_ticks_usec() - t1) / 1000.0
	TestLib.check(warm < 100.0, "re-entering the same door builds in %.0f ms (plan and mesh cache)" % warm)
	it1.free()
	it2.free()
	# no real light casts a shadow, nothing in an interior is a camera, environment or sun
	var it := InteriorGen.build(&"lobby", 2, ORIGIN, 2) as Interior
	var bad_nodes := 0
	for n in it.find_children("*", "", true, false):
		if n is Camera3D or n is WorldEnvironment or n is DirectionalLight3D or n is AudioStreamPlayer or n is AudioStreamPlayer3D:
			bad_nodes += 1
		if n is Light3D and (n as Light3D).shadow_enabled:
			bad_nodes += 1
		if n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			bad_nodes += 1
	TestLib.check(bad_nodes == 0, "no camera, environment, sun, audio or shadow caster inside an interior")
	it.free()
	await TestLib.frames(host, 1)


func _ambience() -> void:
	var ok := true
	for t in InteriorGen.TYPES:
		var amb := InteriorKinds.ambience(t)
		if (amb["loops"] as Array).is_empty() or not amb.has("dedicated") or float(amb["muffle"]) <= 0.0:
			ok = false
		for lp: Array in amb["loops"]:
			if Sfx.variants_of(lp[0]).is_empty():
				ok = false
				TestLib.check(false, "%s: loop '%s' exists in assets/audio" % [t, lp[0]])
		for os: Array in amb["oneshots"]:
			if Sfx.variants_of(os[0]).is_empty():
				ok = false
				TestLib.check(false, "%s: one-shot '%s' exists in assets/audio" % [t, os[0]])
	TestLib.check(ok, "every interior type has ambience hooks that name real Sfx sounds, and a dedicated-loop name for later")
	TestLib.check(InteriorKinds.ambience(&"club")["loops"].size() >= 3, "the club plays the beat stems")


func _space(host: Node) -> void:
	TestLib.check(not InteriorSpace.active and not InteriorSpace.contains(ORIGIN), "no interior registered before one is in the tree")
	var it := InteriorGen.build(&"checkpoint", 2, ORIGIN, 1) as Interior
	root.add_child(it)
	await TestLib.frames(host, 2)
	TestLib.check(InteriorSpace.active and InteriorSpace.contains(it.door_pos + Vector3(0, 1.0, 0)), "an interior in the tree registers itself in InteriorSpace")
	TestLib.check(not InteriorSpace.contains(Vector3(0, 1.0, 0)) and not InteriorSpace.contains(it.door_pos + Vector3(0, 400.0, 0)), "the street map and the sky are not the interior")
	TestLib.check(not PlayerUtil.outside_city(it.door_pos + Vector3(0, 0.1, 0)), "the city rescue leaves a hero inside the interior alone")
	TestLib.check(PlayerUtil.outside_city(Vector3(900.0, 0.1, 900.0)), "...and still rescues one outside both")
	var sp := PlayerUtil.safe_spot(it.door_pos, null, null)
	TestLib.check(sp.distance_to(it.door_pos) < 0.01, "a teleport inside the interior is not clamped to the street map")
	# resolve: walking into a wall slides or stops, never passes
	var plan := it.plan
	var r0: Rect2 = plan.rooms[0]["rect"]
	var o2 := Vector2(ORIGIN.x, ORIGIN.z)
	var from := o2 + Vector2(plan.entry.x, r0.end.y - 1.0)
	var cur := from
	for i in 25:                                                    # an enemy walks 0.2 m per step: straight into the front wall / the closed door ...
		cur = InteriorSpace.resolve(cur.x, cur.y, cur.x, cur.y + 0.2, 0.3)
	TestLib.check(cur.y < o2.y + r0.end.y + 0.05, "enemy steps through the front wall are stopped (z %.2f, wall at %.2f)" % [cur.y - o2.y, r0.end.y])
	cur = from
	for i in 25:                                                    # ... and diagonally along it
		cur = InteriorSpace.resolve(cur.x, cur.y, cur.x + 0.14, cur.y + 0.14, 0.3)
	TestLib.check(cur.x > from.x + 1.0 and cur.y < o2.y + r0.end.y + 0.05, "a diagonal step along the wall slides (x %.2f -> %.2f)" % [from.x - o2.x, cur.x - o2.x])
	# cover: a spot behind a tall prop as seen from the threat, never inside a solid
	var cover_found := 0
	var cover_ok := true
	for sd in SEEDS:
		it.queue_free()
		await TestLib.frames(host, 1)
		it = InteriorGen.build(&"checkpoint", sd, ORIGIN, 1) as Interior
		root.add_child(it)
		await TestLib.frames(host, 1)
		var threat := it.door_pos
		var who := it.door_pos + Vector3(0, 0, -6.0)
		var spot := InteriorSpace.cover_spot(who, threat, 20.0)
		if spot != Vector3.INF:
			cover_found += 1
			if InteriorSpace.blocked(spot.x, spot.z, 0.34) or absf(spot.y - ORIGIN.y) > 0.01:
				cover_ok = false
	TestLib.check(cover_found >= 4, "a cover spot is found in most checkpoint rooms (%d of %d)" % [cover_found, SEEDS.size()])
	TestLib.check(cover_ok, "cover spots are free standing spots on the floor")
	it.queue_free()
	await TestLib.frames(host, 2)
	TestLib.check(not InteriorSpace.active, "freeing the interior unregisters it")
	TestLib.check(PlayerUtil.outside_city(Vector3(ORIGIN.x, ORIGIN.y, ORIGIN.z)), "after it is gone the city rescue works again")


func _quality_scaling(_host: Node) -> void:
	InteriorGen.clear_cache()
	var it := InteriorGen.build(&"bar", 6, ORIGIN, 2) as Interior
	var hi := it.stats()
	it.set_quality(0)
	var lo := it.stats()
	TestLib.check(int(lo["props_drawn"]) < int(hi["props_drawn"]) and int(lo["tris"]) < int(hi["tris"]), "set_quality(LOW) draws fewer props and triangles than HIGH (%d -> %d props)" % [hi["props_drawn"], lo["props_drawn"]])
	TestLib.check(int(lo["lights"]) == 1 and int(hi["lights"]) == 2, "LOW keeps one real light, HIGH two")
	it.set_quality(1)
	TestLib.check(int(it.stats()["props_drawn"]) >= int(lo["props_drawn"]) and int(it.stats()["shapes"]) == int(hi["shapes"]), "set_quality can be called any time and never changes the colliders")
	it.free()
	InteriorGen.clear_cache()
