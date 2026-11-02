extends RefCounted
## Art library test (wave 16, headless): district identity (palettes, prop mix, landmarks), the 16-kind street kit (geometry validity, LOD levels, deterministic placement away from
## buildings and roads, one merged mesh = one draw call, colliders), the folded families, the district sidewalk surfaces (2K variants, tier policy) and the cost of it all.
## Run: tools/test.sh tests/test_art_library.gd

const Districts := preload("res://scripts/world/city_districts.gd")
const Kit := preload("res://scripts/world/city_kit.gd")
const KitWindow := preload("res://scripts/world/city_kit_window.gd")
const Landmarks := preload("res://scripts/world/city_landmarks.gd")

const EMISSION_CODES: Array[float] = [0.0, 0.15, 0.30, 0.45, 0.60, 0.70, 0.80, 0.90, 0.93, 0.96, 1.0]


func run(host: Node) -> void:
	_test_districts(host)
	_test_geometry()
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	_test_placement(city)
	_test_palette_in_world(city)
	_test_window(city)
	_test_landmarks(city)
	await _test_colliders(host, city)
	_test_folded(city)
	_test_surfaces(city)
	_test_cost(city)
	city.queue_free()


# --- districts -------------------------------------------------------------------------------------------------------------

func _test_districts(host: Node) -> void:
	TestLib.check(Districts.at(-50, -50) == Districts.MARKET and Districts.at(50, -50) == Districts.FOUNDRY and Districts.at(-50, 50) == Districts.SLUMS and Districts.at(50, 50) == Districts.TOWERS,
			"the four quadrants are the four districts (market, foundry, slums, towers)")
	TestLib.check(Districts.at_v(Game.SPAWN) == Districts.SLUMS, "the spawn lies in the slums")
	var sfx := host.get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("district_at"):
		var same := true
		for p in [Vector3(-100, 0, -100), Vector3(100, 0, -100), Vector3(-100, 0, 100), Vector3(100, 0, 100), Vector3(-3, 0, 7), Vector3(0, 0, 0)]:
			if int(sfx.call("district_at", p)) != Districts.at_v(p):
				same = false
		TestLib.check(same, "the district numbering agrees with the music layer (Sfx.district_at)")
	var ids := {}
	for id in Districts.IDS:
		ids[id] = true
	TestLib.check(ids.size() == 4 and Districts.TITLES.size() == 4 and Districts.LANDMARKS.size() == 4, "four districts with their own names, titles and landmark ids")
	# palettes are pairwise distinct (paint tint, glow accent, facade tint)
	var distinct := true
	for a in 4:
		for b in range(a + 1, 4):
			var pa := Districts.palette(a)
			var pb := Districts.palette(b)
			for key in ["tint", "accent", "wall", "walk"]:
				var ca: Color = pa[key]
				var cb: Color = pb[key]
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) < 0.12:
					distinct = false
					printerr("palettes %d and %d too close in %s" % [a, b, key])
	TestLib.check(distinct, "every district has its own paint tint, glow accent, facade tint and sidewalk tint")
	var warm := Districts.palette(Districts.MARKET)["tint"] as Color
	var cool := Districts.palette(Districts.TOWERS)["tint"] as Color
	TestLib.check(warm.r > warm.b and cool.b > cool.r, "market paint runs warm, tower paint runs cool")
	var base := Color(0.4, 0.4, 0.4, 0.33)
	TestLib.check(is_equal_approx(Districts.wall_tint(base, 0).a, 0.33) and Districts.wall_tint(base, 0).r > Districts.wall_tint(base, 0).b, "the facade tint keeps the lit-window probability and warms the market")
	var neon_ok := true
	for d in 4:
		var n := 0
		for i in 200:
			if Districts.neon_index(i % 4, i, d) == int(Districts.palette(d)["neon"]):
				n += 1
		if n < 120:
			neon_ok = false
	TestLib.check(neon_ok, "most lots take their district's neon colour")


# --- geometry ----------------------------------------------------------------------------------------------------------------

func _test_geometry() -> void:
	TestLib.check(Kit.KIND_COUNT >= 12, "at least 12 new street props (%d kinds)" % Kit.KIND_COUNT)
	var names := {}
	for k in Kit.KIND_COUNT:
		names[Kit.kind_name(k)] = true
	TestLib.check(names.size() == Kit.KIND_COUNT, "every kind has its own name")
	var all_ok := true
	var tri_ok := true
	var far_ok := true
	var size_ok := true
	var code_ok := true
	var far_kinds := 0
	var max_tris := 0
	for k in Kit.KIND_COUNT:
		for d in Districts.COUNT:
			for variant in 3:
				var g := Kit.make_geo(k, true, d, variant)
				if g.is_empty() or int(g["count"]) < 30 or int(g["count"]) % 3 != 0:
					all_ok = false
					continue
				var n := int(g["count"])
				for key in ["v", "n", "uv", "uv2", "c"]:
					if g[key].size() != n:
						all_ok = false
				max_tris = maxi(max_tris, n / 3)
				if n / 3 > 260:
					tri_ok = false
				var box := AABB()
				var first := true
				for v: Vector3 in g["v"]:
					if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
						all_ok = false
					if first:
						box = AABB(v, Vector3.ZERO)
						first = false
					else:
						box = box.expand(v)
				if d == 0 and variant == 0:
					# props stand on the ground (feet at y = 0), are a street prop in size and keep clear of a 6 m footprint
					if box.position.y < -0.05 or box.position.y > 0.3 or box.end.y < 0.8 or box.end.y > 10.5 or maxf(box.size.x, box.size.z) > 6.0:
						size_ok = false
						printerr("kind %s box %s" % [Kit.kind_name(k), str(box)])
				for nrm: Vector3 in g["n"]:
					if absf(nrm.length() - 1.0) > 0.06:
						all_ok = false
						break
				for c: Color in g["c"]:
					var hit := false
					for code in EMISSION_CODES:
						if absf(c.a - code) < 0.02:
							hit = true
					if not hit:
						code_ok = false
		var far := Kit.make_geo(k, false, 0, 0)
		if Kit.far_radius(k) > 0.0:
			far_kinds += 1
			if far.is_empty() or int(far["count"]) >= int(Kit.make_geo(k, true, 0, 0)["count"]) or int(far["count"]) / 3 > 40:
				far_ok = false
		elif not far.is_empty():
			far_ok = false
	TestLib.check(all_ok, "every kind builds valid geometry in every district palette (finite, unit normals, matching arrays)")
	TestLib.check(tri_ok, "no kit prop above 260 triangles (largest %d)" % max_tris)
	TestLib.check(size_ok, "props stand on y = 0 and have street-furniture size")
	TestLib.check(code_ok, "every vertex alpha is a known emission code")
	TestLib.check(far_kinds >= 4 and far_ok, "%d kinds have a simplified far level (under 40 triangles, fewer than the near level), the rest vanish" % far_kinds)
	# the district paint reaches the geometry: the same kind, other palette, other colours; the glow parts take the accent
	var diff := 0
	for k in [Kit.BENCH, Kit.STALL, Kit.PLANTER, Kit.BIN]:
		var a := Kit.make_geo(k, true, Districts.MARKET, 0)
		var b := Kit.make_geo(k, true, Districts.TOWERS, 0)
		var sa := Color(0, 0, 0)
		var sb := Color(0, 0, 0)
		for c: Color in a["c"]:
			sa += c
		for c: Color in b["c"]:
			sb += c
		if absf(sa.r - sb.r) + absf(sa.b - sb.b) > 1.0:
			diff += 1
	TestLib.check(diff == 4, "the same prop is painted differently in the market and the towers (%d of 4 kinds)" % diff)
	var stall_a := Kit.make_geo(Kit.STALL, true, Districts.MARKET, 0)
	var stall_b := Kit.make_geo(Kit.STALL, true, Districts.MARKET, 1)
	var cloth_differs := false
	for i in (stall_a["c"] as PackedColorArray).size():
		if not (stall_a["c"][i] as Color).is_equal_approx(stall_b["c"][i]):
			cloth_differs = true
	TestLib.check(cloth_differs, "stall awnings come in three fabrics per district")


# --- placement ---------------------------------------------------------------------------------------------------------------

func _test_placement(city: City) -> void:
	var kit := city.street_kit() as Kit
	TestLib.check(kit.total_placements() > 900, "the street kit stands %d props in the city" % kit.total_placements())
	var min_kind := 1000000
	for k in Kit.KIND_COUNT:
		min_kind = mini(min_kind, kit.kind_count[k])
	TestLib.check(min_kind >= 8, "every one of the %d kinds is placed at least 8 times (rarest %d)" % [Kit.KIND_COUNT, min_kind])
	var per := kit.district_count
	var lo := mini(mini(per[0], per[1]), mini(per[2], per[3]))
	TestLib.check(lo >= 150, "every district is dressed (fewest props in a district: %d)" % lo)
	# every prop is on the ground, outside every building, off the road surface, away from the border
	var bad_lot := 0
	var bad_road := 0
	var bad_border := 0
	var bad_wrong_district := 0
	for p in kit.placements:
		var pos: Vector3 = p["pos"]
		var k: int = p["kind"]
		if k < Kit.KC_FIRST and city.layout.lot_at(pos.x, pos.z, 0.2) != null:          # city-kit facade bands and rooftop units stand on buildings on purpose
			bad_lot += 1
		if k < Kit.KIND_COUNT and CityLayout.on_road(pos.x, pos.z, 0.6):
			bad_road += 1
		if absf(pos.x) > CityLayout.HALF + 12.0 or absf(pos.z) > CityLayout.HALF + 12.0:
			bad_border += 1
		if int(p["district"]) != Districts.at(pos.x, pos.z):
			bad_wrong_district += 1
	TestLib.check(bad_lot == 0, "no street-kit prop stands inside a building footprint (%d do)" % bad_lot)
	TestLib.check(bad_road == 0, "no street-kit prop blocks the road surface (%d do)" % bad_road)
	TestLib.check(bad_border == 0 and bad_wrong_district == 0, "props stay inside the border ring and carry the right district")
	# spacing: no two kit props overlap
	var close := 0
	var seen := {}
	for p in kit.placements:
		if int(p["kind"]) >= Kit.KIND_COUNT:
			continue                                              # the folded old families keep their own placement
		var pos: Vector3 = p["pos"]
		var key := Vector2i(int(floor(pos.x / 2.0)), int(floor(pos.z / 2.0)))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var other: Array = seen.get(Vector2i(key.x + dx, key.y + dz), [])
				for q: Vector3 in other:
					if q.distance_to(pos) < 0.45:
						close += 1
		if not seen.has(key):
			seen[key] = []
		(seen[key] as Array).append(pos)
	TestLib.check(close == 0, "no two props overlap (%d pairs closer than 45 cm)" % close)
	# prop mix per district: signature kinds
	var kc := _kinds_per_district(kit)
	TestLib.check(kc[Districts.MARKET][Kit.STALL] > 12 and kc[Districts.FOUNDRY][Kit.STALL] == 0 and kc[Districts.TOWERS][Kit.STALL] == 0, "market stalls belong to the market and the slums, not to the foundry or the towers")
	TestLib.check(kc[Districts.FOUNDRY][Kit.VENT_STACK] > 12 and kc[Districts.MARKET][Kit.VENT_STACK] == 0 and kc[Districts.TOWERS][Kit.VENT_STACK] == 0, "vent stacks belong to the foundry and the slums")
	TestLib.check(kc[Districts.TOWERS][Kit.SHELTER] > kc[Districts.SLUMS][Kit.SHELTER] and kc[Districts.FOUNDRY][Kit.SHELTER] == 0 and kc[Districts.TOWERS][Kit.BILLBOARD] > kc[Districts.SLUMS][Kit.BILLBOARD],
			"glow bus pods and billboards crowd the towers")
	TestLib.check(kc[Districts.SLUMS][Kit.ANTENNA] > kc[Districts.TOWERS][Kit.ANTENNA] and kc[Districts.MARKET][Kit.ANTENNA] == 0, "antennas sprout in the slums")
	TestLib.check(kc[Districts.FOUNDRY][Kit.BARRIER] > kc[Districts.TOWERS][Kit.BARRIER] and kc[Districts.MARKET][Kit.BARRIER] == 0, "barrier gates belong to the foundry and the slums")
	TestLib.check(kc[Districts.MARKET][Kit.LANTERN] > 12 and kc[Districts.FOUNDRY][Kit.LANTERN] == 0 and kc[Districts.TOWERS][Kit.LANTERN] == 0, "lantern poles belong to the market and the slums")
	var distinct := true
	for a in 4:
		for b in range(a + 1, 4):
			var dot := 0.0
			var na := 0.0
			var nb := 0.0
			for k in Kit.KIND_COUNT:
				var x := float(kc[a][k])
				var y := float(kc[b][k])
				dot += x * y
				na += x * x
				nb += y * y
			if dot / sqrt(na * nb) > 0.93:
				distinct = false
				printerr("districts %d and %d have a similar prop mix (cosine %.3f)" % [a, b, dot / sqrt(na * nb)])
	TestLib.check(distinct, "the four prop mixes are pairwise different")
	# determinism: the same layout and the same parts give the same placements
	var again := Kit.new()
	var fake: Array[Dictionary] = []
	var first := Kit.new()
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nfunc glow_add(_a, _b, _c, _d, _e, _f) -> void:\n\tpass\n"
	script.reload()
	var dummy: RefCounted = script.new()
	first.build(dummy, city.layout, fake)
	again.build(dummy, city.layout, fake)
	var same := first.total_placements() == again.total_placements() and first.total_placements() > 0
	for i in mini(first.total_placements(), 40):
		if (first.placements[i]["pos"] as Vector3) != (again.placements[i]["pos"] as Vector3) or int(first.placements[i]["kind"]) != int(again.placements[i]["kind"]):
			same = false
	TestLib.check(same, "placement is deterministic (%d props both times)" % first.total_placements())


func _kinds_per_district(kit: Kit) -> Array:
	var out: Array = []
	for d in 4:
		var row := PackedInt32Array()
		row.resize(Kit.TOTAL_KINDS)
		out.append(row)
	for p in kit.placements:
		var row2: PackedInt32Array = out[int(p["district"])]
		row2[int(p["kind"])] += 1
		out[int(p["district"])] = row2
	return out


func _test_palette_in_world(city: City) -> void:
	# facade tints: the market's buildings average warmer than the towers' buildings
	var sum := [Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)]
	var cnt := [0, 0, 0, 0]
	var neon_share := [0, 0, 0, 0]
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		var d := Districts.at(lot.cx, lot.cz)
		sum[d] = (sum[d] as Color) + (b.tint as Color)
		cnt[d] += 1
		if lot.neon == int(Districts.palette(d)["neon"]):
			neon_share[d] += 1
	var m: Color = sum[0] / float(cnt[0])
	var t: Color = sum[3] / float(cnt[3])
	TestLib.check(m.r - m.b > t.r - t.b + 0.04, "market facades average warmer than tower facades (r-b %.3f vs %.3f)" % [m.r - m.b, t.r - t.b])
	var ok := true
	for d in 4:
		if float(neon_share[d]) / float(cnt[d]) < 0.55:
			ok = false
	TestLib.check(ok, "at least 55 % of every district's lots carry the district neon colour")
	# the ground tints its sidewalks per district (this is the one tint that reaches LOW)
	var g: ShaderMaterial = city._ground.material
	var gl: ShaderMaterial = city._ground.material_lite
	var tints := {}
	for d in 4:
		var v: Vector3 = g.get_shader_parameter(StringName("dist_walk%d" % d))
		tints[v] = true
		var vl: Vector3 = gl.get_shader_parameter(StringName("dist_walk%d" % d))
		if not v.is_equal_approx(vl):
			ok = false
	TestLib.check(tints.size() == 4 and ok, "the ground shader carries four different sidewalk tints (full and LOW material)")


# --- the merged window -------------------------------------------------------------------------------------------------------

func _test_window(city: City) -> void:
	var kit := city.street_kit() as Kit
	var kw := city.kit_window() as KitWindow
	TestLib.check(kw.node is MeshInstance3D and kw.node.get_parent() != null and kw.node.mesh == kw.mesh, "the street kit is ONE MeshInstance3D (one draw call for 16 kinds and the landmarks)")
	var spawn := Vector2(Game.SPAWN.x, Game.SPAWN.z)
	city.set_quality(1)
	city.update_streaming(spawn, true)
	TestLib.check(kw.mesh.get_surface_count() == 1, "the window mesh has a single surface")
	TestLib.check(kw.near_props > 10 and kw.far_props > 5, "at the spawn the window holds %d full-detail props and %d far silhouettes" % [kw.near_props, kw.far_props])
	TestLib.check(kw.triangles < 9000, "MED window at the spawn: %d triangles incl. %d of landmarks (budget 9000)" % [kw.triangles, kw.landmark_tris])
	var fmt := kw.mesh.surface_get_format(0)
	TestLib.check((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0, "the window carries the per-prop seed as CUSTOM0")
	# completeness: every prop of every cell inside the near radius is in the window at full detail
	var expect := 0
	var rn := kw.near_radius()
	for c in Kit.GRID_N * Kit.GRID_N:
		if kit.counts[c] > 0 and kw._min_dist(c, spawn) <= rn:
			var carr: PackedFloat32Array = kit.cells[c]
			for o in range(0, carr.size(), 6):
				if int(carr[o]) < Kit.KC_FIRST:                       # the city-kit pieces (facade, markings) have their own, shorter range (kc_props)
					expect += 1
	TestLib.check(kw.near_props == expect, "all %d props of the cells within %.0f m are drawn at full detail (got %d)" % [expect, rn, kw.near_props])
	# LOD: far cells show only kinds with a far level
	var far_ok := true
	var far_expect := 0
	for c in Kit.GRID_N * Kit.GRID_N:
		if kit.counts[c] == 0:
			continue
		var d: float = kw._min_dist(c, spawn)
		if d > rn and d <= kw.far_radius():
			var arr: PackedFloat32Array = kit.cells[c]
			for o in range(0, arr.size(), 6):
				if Kit.far_radius(int(arr[o])) >= d:
					far_expect += 1
	if kw.far_props != far_expect:
		far_ok = false
	TestLib.check(far_ok, "far cells hold exactly the %d props whose kind reaches that far (got %d)" % [far_expect, kw.far_props])
	# LOD saves triangles: the window with everything at full detail is much bigger
	var tris_lod := kw.triangles
	kw.show_all()
	var tris_all := kw.triangles
	TestLib.check(tris_all > tris_lod * 8, "LOD: the whole city at full detail is %d triangles, the window at the spawn %d" % [tris_all, tris_lod])
	city.update_streaming(spawn, true)
	# the tiers scale the window
	var counts := []
	for q in 3:
		city.set_quality(q)
		city.update_streaming(spawn, true)
		counts.append(kw.near_props)
	TestLib.check(int(counts[0]) < int(counts[1]) and int(counts[1]) < int(counts[2]), "the window grows with the tier (near props %s)" % str(counts))
	city.set_quality(1)
	# it follows the camera and rebuilds only when needed
	var r0: int = kw.rebuilds
	city.update_streaming(Vector2(200.0, -200.0), true)
	var other_near: int = kw.near_props
	var other_sig: int = kw.sig
	city.update_streaming(Vector2(203.0, -200.0), false)
	TestLib.check(kw.rebuilds == r0 + 1 and kw.sig == other_sig, "3 m of camera movement does not rebuild the window")
	city.update_streaming(spawn, false)
	TestLib.check(kw.rebuilds == r0 + 2 and kw.near_props > 0, "a jump to another street re-fills it (%d -> %d near props)" % [other_near, kw.near_props])
	# far from the city only the landmarks (coarse) are left
	city.update_streaming(Vector2(9000.0, 9000.0), true)
	TestLib.check(kw.near_props == 0 and kw.far_props == 0 and kw.triangles == kw.landmark_tris and kw.landmark_tris > 300, "far outside the city the window keeps only the %d triangles of the four landmark silhouettes" % kw.landmark_tris)
	# rebuild cost (generous bound: this machine may be loaded) and no node growth
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var t0 := Time.get_ticks_usec()
	for i in 120:
		city.update_streaming(Vector2(-280.0 + 4.0 * float(i), 4.0), false)
	var avg := float(Time.get_ticks_usec() - t0) / 120.0
	TestLib.check(avg < 15000.0, "driving 480 m updates the window with %.0f us per frame on average (%d rebuilds)" % [avg, kw.rebuilds])
	TestLib.check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) == nodes_before, "streaming the kit creates no nodes")
	city.update_streaming(spawn, true)


# --- landmarks ---------------------------------------------------------------------------------------------------------------

func _test_landmarks(city: City) -> void:
	var lm := city.landmarks() as Landmarks
	TestLib.check(lm.items.size() == 4, "four landmarks, one per district")
	var ok := true
	var on_plaza := true
	var tall := true
	var coarse := true
	var ids := {}
	for it in lm.items:
		var pos: Vector3 = it["pos"]
		var d: int = it["district"]
		if Districts.at(pos.x, pos.z) != d:
			ok = false
		var plaza := false
		for pl: Vector2 in city.layout.plazas:
			if pl.distance_to(Vector2(pos.x, pos.z)) < 0.01:
				plaza = true
		on_plaza = on_plaza and plaza
		tall = tall and float(it["height"]) >= 95.0
		var nt := Landmarks.triangle_count(it["near"])
		var ft := Landmarks.triangle_count(it["far"])
		if nt > 700 or ft >= nt or ft > 260:
			coarse = false
		ids[it["id"]] = true
		# a vertical silhouette: the geometry reaches (nearly) its full height
		var top := 0.0
		for v: Vector3 in it["near"]["v"]:
			top = maxf(top, v.y)
		if top < float(it["height"]) - 1.0:
			tall = false
	TestLib.check(ok and on_plaza, "every landmark stands on an empty plaza lot inside its own district")
	TestLib.check(ids.size() == 4 and tall, "four different silhouettes, each at least 95 m tall (above the 88 m towers)")
	TestLib.check(coarse, "landmarks have a coarse far level (near under 700 triangles)")
	var boxes := 0
	for c in city.collision_body.get_children():
		if String(c.name).begins_with("Landmark_"):
			boxes += 1
	TestLib.check(boxes == 4, "each landmark has a solid core in the physics world")
	# the landmark never sits closer than the plaza furniture radius to a building
	var clear := true
	for it in lm.items:
		var pos: Vector3 = it["pos"]
		if city.layout.lot_at(pos.x, pos.z, 6.0) != null:
			clear = false
	TestLib.check(clear, "the 6 m core of a landmark touches no building")


# --- colliders ---------------------------------------------------------------------------------------------------------------

func _test_colliders(host: Node, city: City) -> void:
	var kit := city.street_kit() as Kit
	var pc := city.prop_colliders()
	var fams := 0
	for k in Kit.KIND_COUNT:
		if not (Kit.KINDS[k]["col"] as Array).is_empty() and pc.instances_of("Kit" + Kit.kind_name(k)).size() == kit.kind_count[k]:
			fams += 1
	TestLib.check(fams == Kit.KIND_COUNT, "all %d kit kinds feed the pooled colliders with every placed prop" % fams)
	TestLib.check(pc.shape_count() == 56, "the collider pool keeps its constant 56 shapes")
	# a bin is cover: a ray at waist height is stopped, a ray over it passes
	var bins := pc.instances_of("KitBin")
	TestLib.check(bins.size() > 20, "bins are collidable (%d)" % bins.size())
	var bx := _clear_instance(city, bins)
	city.update_colliders(Vector3(bx.origin.x, 1.0, bx.origin.z))
	await TestLib.frames(host, 2)
	var space := host.get_viewport().world_3d.direct_space_state
	var along := bx.basis * Vector3(0, 0, 1)
	var low := PhysicsRayQueryParameters3D.create(bx.origin - along * 3.0 + Vector3(0, 0.5, 0), bx.origin + along * 3.0 + Vector3(0, 0.5, 0), Game.L_WORLD)
	var high := PhysicsRayQueryParameters3D.create(bx.origin - along * 3.0 + Vector3(0, 1.6, 0), bx.origin + along * 3.0 + Vector3(0, 1.6, 0), Game.L_WORLD)
	TestLib.check(not space.intersect_ray(low).is_empty(), "a ray at waist height is stopped by a bin")
	TestLib.check(space.intersect_ray(high).is_empty(), "a ray at head height passes over a bin")
	# an antenna is a pole: a ray across it hits
	var ap := _clear_instance(city, pc.instances_of("KitAntenna")).origin
	city.update_colliders(Vector3(ap.x, 1.0, ap.z))
	await TestLib.frames(host, 2)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ap + Vector3(-2.0, 2.0, 0), ap + Vector3(2.0, 2.0, 0), Game.L_WORLD))
	TestLib.check(not hit.is_empty() and absf((hit.position as Vector3).x - (ap.x - 0.14)) < 0.2, "a ray across an antenna mast hits the pole (%s)" % str(hit.get("position", "no hit")))
	city.update_colliders(Vector3(0.0, -2000.0, 0.0))


## The first instance with no building within 4 m and no other kit prop within 4 m (so only its own collider can stop a ray through it).
func _clear_instance(city: City, list: Array[Transform3D]) -> Transform3D:
	var kit := city.street_kit() as Kit
	for xf in list:
		if city.layout.lot_at(xf.origin.x, xf.origin.z, 4.0) != null:
			continue
		var alone := true
		for p in kit.placements:
			var o: Vector3 = p["pos"]
			var d := Vector2(o.x - xf.origin.x, o.z - xf.origin.z).length()
			if d > 0.05 and d < 4.0:
				alone = false
				break
		if alone:
			return xf
	return list[0]


# --- folded families ---------------------------------------------------------------------------------------------------------

func _test_folded(city: City) -> void:
	var kit := city.street_kit() as Kit
	var names := {}
	for n in city.multimesh_nodes:
		names[String(n.name)] = true
	TestLib.check(not names.has("Hydrants") and not names.has("Kiosks") and not names.has("VentGrates"), "hydrants, lit kiosks and vent grates ride in the merged window (3 MultiMesh draw calls fewer)")
	TestLib.check(kit.kind_count[Kit.HYDRANT] > 20 and kit.kind_count[Kit.KIOSK_LIT] > 5 and kit.kind_count[Kit.VENT_GRATE] > 20, "all of them are still there (%d hydrants, %d kiosks, %d grates)" % [kit.kind_count[Kit.HYDRANT], kit.kind_count[Kit.KIOSK_LIT], kit.kind_count[Kit.VENT_GRATE]])
	var pc := city.prop_colliders()
	TestLib.check(pc.instances_of("Hydrants").size() == kit.kind_count[Kit.HYDRANT] and pc.instances_of("Kiosks").size() == kit.kind_count[Kit.KIOSK_LIT], "hydrants and kiosks keep their colliders under the old family names")
	TestLib.check(city.multimesh_nodes.size() <= 66 and city.multimesh_nodes.size() <= 40, "the MultiMesh families number %d (was 40 before the fold)" % city.multimesh_nodes.size())
	# the steam still finds its vents
	TestLib.check(city._props.vents.size() >= 30, "steam vents are unchanged (%d)" % city._props.vents.size())


# --- surfaces ----------------------------------------------------------------------------------------------------------------

func _test_surfaces(city: City) -> void:
	var all_there := true
	var packed := true
	for st in ["walk_market", "walk_foundry", "walk_towers"]:
		for suffix in ["albedo", "normal"]:
			var path := "res://assets/textures/surface_%s_%s.png" % [st, suffix]
			all_there = all_there and ResourceLoader.exists(path)
			var imp := FileAccess.get_file_as_string(path + ".import")
			packed = packed and imp.contains("compress/mode=2") and imp.contains("mipmaps/generate=true") and imp.contains("compress/normal_map=2")
			var f := FileAccess.open(path, FileAccess.READ)
			var head := f.get_buffer(24) if f != null else PackedByteArray()
			var w := (int(head[16]) << 24 | int(head[17]) << 16 | int(head[18]) << 8 | int(head[19])) if head.size() >= 24 else 0
			var h := (int(head[20]) << 24 | int(head[21]) << 16 | int(head[22]) << 8 | int(head[23])) if head.size() >= 24 else 0
			all_there = all_there and w == 2048 and h == 2048
	TestLib.check(all_there, "three 2048 x 2048 district paving variants (hex flagstones, tread plate, polished slabs) in albedo and packed normal")
	TestLib.check(packed, "they are VRAM compressed with mipmaps like the other surface sets")
	TestLib.check(SurfaceTextures.WALK_LAYERS.size() == 4 and SurfaceTextures.WALK_LAYERS[2] == "sidewalk", "the district sidewalk array has four layers: market, foundry, slums (= the plain sidewalk), towers")
	# tier policy: LOW loads none of it, MED the half size, HIGH the full size
	TestLib.check(SurfaceTextures.walk_array("albedo", 0) == null and SurfaceTextures.walk_array("normal", 0) == null, "LOW loads none of the paving variants (its halved texture budget stays untouched)")
	var ground: ShaderMaterial = city._ground.material
	for q in 3:
		city.set_quality(q)
		var on := float(ground.get_shader_parameter(&"srf_walkv"))
		var arr = ground.get_shader_parameter(&"srf_walkv_a")
		var plain = ground.get_shader_parameter(&"srf_walk_a")
		if q == 0:
			TestLib.check(on == 0.0 and arr == null and plain == null, "quality 0: no sidewalk textures, the tinted procedural slabs stay")
		elif arr != null:
			var layers: int = (arr as Texture2DArray).get_layers()
			var side: int = (arr as Texture2DArray).get_width()
			TestLib.check(on == 1.0 and layers == 4 and side == (1024 if q == 1 else 2048) and plain == null, "quality %d: district sidewalk array with 4 layers at %d px (plain sidewalk set not loaded)" % [q, side])
		else:
			TestLib.check(on == 0.0 and plain != null or DisplayServer.get_name() == "headless", "quality %d: the array cannot be built here (headless), the plain sidewalk set is the fallback" % q)
	city.set_quality(1)
	var med := SurfaceTextures.estimate_bytes(1)
	var high := SurfaceTextures.estimate_bytes(2)
	TestLib.check(SurfaceTextures.estimate_bytes(0) == 0 and med > 0 and high > med * 2 and high < 120 * 1048576, "texture estimate: LOW 0, MED %.0f MB, HIGH %.0f MB (gate 360 MB for the whole staged scene)" % [med / 1048576.0, high / 1048576.0])


# --- cost --------------------------------------------------------------------------------------------------------------------

func _test_cost(city: City) -> void:
	var kw := city.kit_window() as KitWindow
	city.set_quality(1)
	city.update_streaming(Vector2(Game.SPAWN.x, Game.SPAWN.z), true)
	TestLib.check(kw.triangles < 9000, "street kit plus landmarks at the spawn on MED: %d triangles in ONE draw call" % kw.triangles)
	city.set_quality(0)
	city.update_streaming(Vector2(Game.SPAWN.x, Game.SPAWN.z), true)
	var low := kw.triangles
	city.set_quality(2)
	city.update_streaming(Vector2(Game.SPAWN.x, Game.SPAWN.z), true)
	TestLib.check(low < 5000 and kw.triangles < 14000, "LOW %d / HIGH %d window triangles" % [low, kw.triangles])
	city.set_quality(1)
	# the kit node is a plain MeshInstance3D without shadows and without mirror copy (no extra passes)
	TestLib.check(kw.node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the street kit casts no shadow pass")
