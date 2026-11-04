extends RefCounted
## City variety test (headless, real world scene): the eleven facade / rooftop / sidewalk dressing kinds (city_kit_dress.gd, Quaternius Downtown City MegaKit pieces plus procedural
## parts) build lean geometry with quantum glow accents, are placed by distinct per-district composition rules (market, foundry, slums and towers each get their own mix), stay
## deterministic, stand on the right surfaces, add no draw call (everything is still ONE surface of the street-kit window) and no texture. Run: tools/test.sh tests/test_city_variety.gd

const Kit := preload("res://scripts/world/city_kit.gd")
const KitWorld := preload("res://scripts/world/city_kit_world.gd")
const Dress := preload("res://scripts/world/city_kit_dress.gd")
const Districts := preload("res://scripts/world/city_districts.gd")

const FIRST := Kit.KC_FIRST + KitWorld.DRESS_FIRST


func run(host: Node) -> void:
	_pieces()
	_geometry()
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	var kit := city.street_kit() as Kit
	var counts := _counts(kit)
	_placement(city, kit, counts)
	_districts(counts)
	_rooftops_differ()
	_window(city, kit)
	city.queue_free()


func _pieces() -> void:
	for name in ["column", "column_small", "stoop", "stoop_flat", "shopwall", "slate_cap", "slate_roof", "trim_brick", "trim_half", "cornice_trim"]:
		var d := KitWorld.piece(name)
		TestLib.check(not d.is_empty(), "dressing piece kit_city_%s loads" % name)
		if d.is_empty():
			continue
		var tris := int(d["count"]) / 3
		TestLib.check(tris >= 2 and tris <= 160, "dressing piece %s is light (%d tris)" % [name, tris])
		var scene := load("res://assets/models/kit_city_%s.glb" % name) as PackedScene
		var root := scene.instantiate()
		var textured := false
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var m := (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var mat := m.surface_get_material(s) as BaseMaterial3D
				if mat != null and mat.albedo_texture != null:
					textured = true
		root.free()
		TestLib.check(not textured, "dressing piece %s carries no texture (texture memory unchanged)" % name)


func _geometry() -> void:
	for k in Dress.COUNT:
		for d in 4:
			var g := Dress.make_geo(k, d, 1, true, KitWorld.piece)
			var n: int = g["count"] if not g.is_empty() else 0
			TestLib.check(n > 0 and n % 3 == 0, "%s builds near geometry in district %d (%d tris)" % [Dress.NAMES[k], d, n / 3])
			if n == 0:
				continue
			TestLib.check((g["v"] as PackedVector3Array).size() == n and (g["n"] as PackedVector3Array).size() == n and (g["uv"] as PackedVector2Array).size() == n
					and (g["uv2"] as PackedVector2Array).size() == n and (g["c"] as PackedColorArray).size() == n, "%s arrays line up" % Dress.NAMES[k])
			TestLib.check(n / 3 <= 300, "%s stays light (%d tris)" % [Dress.NAMES[k], n / 3])
			if d == 0 or d == 3:
				var glow := 0
				for c in (g["c"] as PackedColorArray):
					if c.a > 0.2:
						glow += 1
				if k != Dress.STOOP and not (k == Dress.PARAPET and d == 0):
					TestLib.check(glow > 0, "%s has quantum glow accents in district %d" % [Dress.NAMES[k], d])
	for k in Dress.FAR:
		var near := Dress.make_geo(k, 2, 0, true, KitWorld.piece)
		var far := Dress.make_geo(k, 2, 0, false, KitWorld.piece)
		TestLib.check(not far.is_empty() and int(far["count"]) <= int(near["count"]), "%s has a simplified far level (%d <= %d)" % [Dress.NAMES[k], int(far["count"]) / 3, int(near["count"]) / 3])
	TestLib.check(Dress.make_geo(Dress.STOOP, 0, 0, false, KitWorld.piece).is_empty(), "small kinds have no far level")


func _counts(kit: Kit) -> Array:
	var counts := []
	for d in 4:
		var row := PackedInt32Array()
		row.resize(Dress.COUNT)
		counts.append(row)
	for p in kit.placements:
		var k := int(p["kind"]) - FIRST
		if k >= 0 and k < Dress.COUNT:
			var row: PackedInt32Array = counts[int(p["district"])]
			row[k] += 1
			counts[int(p["district"])] = row
	return counts


func _placement(city: City, kit: Kit, counts: Array) -> void:
	for k in Dress.COUNT:
		var total := 0
		for d in 4:
			total += (counts[d] as PackedInt32Array)[k]
		TestLib.check(total >= 8, "%s is placed at least 8 times (%d)" % [Dress.NAMES[k], total])
	var a := Dress.layout(city.layout.lots)
	var b := Dress.layout(city.layout.lots)
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if a[i] != b[i]:
				same = false
				break
	TestLib.check(same and a.size() > 100, "the dressing layout is deterministic (%d items)" % a.size())
	var bad_wall := 0
	var bad_roof := 0
	var bad_walk := 0
	for it in a:
		var x: float = it["x"]
		var z: float = it["z"]
		var kind: int = it["kind"]
		match kind:
			Dress.ROOFTOP:
				var lot := city.layout.lot_at(x, z, 0.1)
				if lot == null or absf(lot.h - float(it["y"])) > 0.01:
					bad_roof += 1
			Dress.CLUSTER:
				if CityLayout.on_road(x, z, 0.0) or city.layout.lot_at(x, z, 0.2) != null:
					bad_walk += 1
			_:
				if city.layout.lot_at(x, z, 0.8) == null:
					bad_wall += 1
	TestLib.check(bad_wall == 0, "every facade piece stands against a building (%d off)" % bad_wall)
	TestLib.check(bad_roof == 0, "every rooftop structure stands on its building's roof (%d off)" % bad_roof)
	TestLib.check(bad_walk == 0, "every sidewalk cluster stands on the sidewalk (%d off)" % bad_walk)
	var sources := kit.collider_sources()
	TestLib.check(sources.has("KitDrCluster") and not sources.has("KitDrAwning"), "clusters block the sidewalk, awnings and balconies do not")


func _districts(counts: Array) -> void:
	var m: PackedInt32Array = counts[Districts.MARKET]
	var f: PackedInt32Array = counts[Districts.FOUNDRY]
	var s: PackedInt32Array = counts[Districts.SLUMS]
	var t: PackedInt32Array = counts[Districts.TOWERS]
	TestLib.check(m[Dress.AWNING] > f[Dress.AWNING] and m[Dress.AWNING] >= s[Dress.AWNING] * 0.8, "the market has the most awnings (%d vs foundry %d)" % [m[Dress.AWNING], f[Dress.AWNING]])
	TestLib.check(f[Dress.SHUTTER] > m[Dress.SHUTTER] * 3 and f[Dress.SHUTTER] > t[Dress.SHUTTER] * 3, "the foundry is the district of roll shutters (%d vs market %d, towers %d)" % [f[Dress.SHUTTER], m[Dress.SHUTTER], t[Dress.SHUTTER]])
	TestLib.check(t[Dress.COLONNADE] > 3 * maxi(m[Dress.COLONNADE], s[Dress.COLONNADE]), "colonnades belong to the towers (%d vs market %d, slums %d)" % [t[Dress.COLONNADE], m[Dress.COLONNADE], s[Dress.COLONNADE]])
	TestLib.check(s[Dress.STOOP] > 2 * maxi(f[Dress.STOOP], 1) and s[Dress.STOOP] > 2 * maxi(m[Dress.STOOP], 1), "stoops are a slums habit (%d)" % s[Dress.STOOP])
	TestLib.check(f[Dress.BALCONY] == 0 and s[Dress.BALCONY] > m[Dress.BALCONY], "the foundry has no balconies, the slums the most (%d vs market %d)" % [s[Dress.BALCONY], m[Dress.BALCONY]])
	TestLib.check(t[Dress.FIRE_ESCAPE] == 0 and f[Dress.FIRE_ESCAPE] > m[Dress.FIRE_ESCAPE], "fire escapes: none in the towers, most in the foundry (%d)" % f[Dress.FIRE_ESCAPE])
	TestLib.check(f[Dress.PARAPET] > 2 * t[Dress.PARAPET], "brick parapets are foundry roofs (%d vs towers %d)" % [f[Dress.PARAPET], t[Dress.PARAPET]])
	TestLib.check(t[Dress.LEDGE] > f[Dress.LEDGE] and m[Dress.LEDGE] > s[Dress.LEDGE], "ledges: towers and market over foundry and slums")
	# each district's composition vector differs from every other one
	var vecs := []
	for d in 4:
		var row: PackedInt32Array = counts[d]
		var sum := 0.0
		for v in row:
			sum += float(v)
		var nv := []
		for v in row:
			nv.append(float(v) / maxf(sum, 1.0))
		vecs.append(nv)
	var min_dist := 9.0
	for i in 4:
		for j in range(i + 1, 4):
			var dist := 0.0
			for k in Dress.COUNT:
				dist += absf(float(vecs[i][k]) - float(vecs[j][k]))
			min_dist = minf(min_dist, dist)
	TestLib.check(min_dist > 0.3, "every pair of districts has a clearly different mix of dressing (closest L1 distance %.2f)" % min_dist)


## The four districts build four different rooftop silhouettes (different geometry, not just a tint).
func _rooftops_differ() -> void:
	var sigs := {}
	for d in 4:
		for v in 2:
			var g := Dress.make_geo(Dress.ROOFTOP, d, v, true, KitWorld.piece)
			var top := 0.0
			var wide := 0.0
			for p in (g["v"] as PackedVector3Array):
				top = maxf(top, p.y)
				wide = maxf(wide, maxf(absf(p.x), absf(p.z)))
			sigs["%d_%d_%d_%d" % [d, v, int(top * 10.0), int(wide * 10.0)]] = int(g["count"])
	var shapes := {}
	for key: String in sigs:
		var parts := key.split("_")
		shapes["%s_%s_%d" % [parts[2], parts[3], sigs[key]]] = true
	TestLib.check(shapes.size() >= 7, "rooftop structures differ by district and variant (%d distinct of 8)" % shapes.size())


func _window(city: City, kit: Kit) -> void:
	var win = city.kit_window()
	win.show_all()
	TestLib.check(win.mesh.get_surface_count() == 1, "the dressing adds no draw call: still ONE surface")
	var cam := Vector2(Game.SPAWN.x, Game.SPAWN.z)
	var near_dress := 0
	for p in kit.placements:
		var pos: Vector3 = p["pos"]
		if int(p["kind"]) >= FIRST and Vector2(pos.x, pos.z).distance_to(cam) < win.near_radius():
			near_dress += int(kit.geo(int(p["kind"]), true, int(p["district"]), int(p["variant"])).get("count", 0)) / 3
	TestLib.check(near_dress > 500 and near_dress < 7000, "dressing triangles near the spawn stay in budget (%d)" % near_dress)
	# a far view still shows rooftop structures through the simplified level (the window holds rooftops beyond the near radius)
	var far_cam := Vector2(-150.0, -150.0)
	win.update(far_cam, true)
	var tris_far: int = win.triangles
	win.update(Vector2(1.0e4, 1.0e4), true)
	TestLib.check(tris_far > win.triangles, "the window around a far camera holds the dressing of that area (%d tris)" % tris_far)
	win.update(cam, true)
	var med_tris: int = win.triangles
	city.set_quality(0)
	city.update_streaming(cam, true)
	TestLib.check(win.triangles < med_tris and win.triangles < 6000, "the LOW tier skips the dressing (%d tris vs MED %d)" % [win.triangles, med_tris])
	city.set_quality(1)
	city.update_streaming(cam, true)
