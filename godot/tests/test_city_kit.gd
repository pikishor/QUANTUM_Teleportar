extends RefCounted
## City kit test (headless): the converted Quaternius Downtown City MegaKit pieces (assets/models/kit_city_*.glb) exist and stay lean, road decals are flat vector markings, the city
## generator places facade bands, rooftop units, street furniture and road markings deterministically, everything rides in the ONE merged street-kit mesh (no extra draw call),
## the near window stays inside a triangle allowance, and the credits are in docs/THIRD_PARTY.md. Run: tools/test.sh tests/test_city_kit.gd

const Kit := preload("res://scripts/world/city_kit.gd")
const KitWorld := preload("res://scripts/world/city_kit_world.gd")


func run(host: Node) -> void:
	_pieces()
	_geometry()
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	_placement(city)
	_window(city)
	_credits()
	city.queue_free()


func _pieces() -> void:
	var total := 0
	for name: String in KitWorld.all_pieces():
		var path := "res://assets/models/kit_city_%s.glb" % name
		TestLib.check(ResourceLoader.exists(path), "city kit piece %s exists" % name)
		var d := KitWorld.piece(name)
		TestLib.check(not d.is_empty(), "city kit piece %s loads with mesh data" % name)
		if d.is_empty():
			continue
		var tris := int(d["count"]) / 3
		total += tris
		TestLib.check(tris >= 2 and tris <= 160, "city kit piece %s is light (%d tris)" % [name, tris])
		var sz: Vector3 = d["size"]
		TestLib.check(sz.x < 7.0 and sz.y < 3.5 and sz.z < 7.0, "city kit piece %s has a sane size %s" % [name, sz])
		TestLib.check((d["c"] as PackedColorArray).size() == int(d["count"]), "city kit piece %s carries vertex colours" % name)
	TestLib.check(total < 1200, "the whole city kit is under 1200 triangles (%d)" % total)


func _geometry() -> void:
	for k in KitWorld.COUNT:
		var g := KitWorld.make_geo(k, 0, 0, Color.WHITE)
		TestLib.check(not g.is_empty() and int(g["count"]) % 3 == 0, "%s builds geometry" % KitWorld.NAMES[k])
		if g.is_empty():
			continue
		var n: int = g["count"]
		TestLib.check((g["v"] as PackedVector3Array).size() == n and (g["uv2"] as PackedVector2Array).size() == n and (g["c"] as PackedColorArray).size() == n, "%s arrays line up" % KitWorld.NAMES[k])
		if KitWorld.is_flat(k):
			var flat := true
			var up := true
			for i in n:
				if absf((g["v"] as PackedVector3Array)[i].y) > 0.001:
					flat = false
				if (g["n"] as PackedVector3Array)[i].y < 0.9:
					up = false
			TestLib.check(flat and up, "%s is a flat marking facing up" % KitWorld.NAMES[k])
	for v in 3:
		TestLib.check(not KitWorld.make_geo(KitWorld.ARROW, 1, v, Color.WHITE).is_empty(), "arrow variant %d builds" % v)
	TestLib.check(int(KitWorld.make_geo(KitWorld.DASH, 0, 0, Color.WHITE)["count"]) == 12, "a dash line tile is two quads")


func _placement(city: City) -> void:
	var kit := city.street_kit() as Kit
	for k in KitWorld.COUNT:
		TestLib.check(kit.kind_count[Kit.KC_FIRST + k] >= 8, "%s is placed at least 8 times (%d)" % [KitWorld.NAMES[k], kit.kind_count[Kit.KC_FIRST + k]])
	var a := KitWorld.layout_items(city.layout)
	var b := KitWorld.layout_items(city.layout)
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if a[i] != b[i]:
				same = false
				break
	TestLib.check(same, "the city-kit layout is deterministic (%d items)" % a.size())
	var bad_roof := 0
	var bad_facade := 0
	var bad_mark := 0
	for it in a:
		var kind: int = it["kind"]
		var x: float = it["x"]
		var z: float = it["z"]
		if kind == KitWorld.ACUNIT:
			var lot := city.layout.lot_at(x, z, 0.1)
			if lot == null or absf(lot.h - float(it["y"])) > 0.01:
				bad_roof += 1
		elif kind == KitWorld.CORNICE or kind == KitWorld.WINDOW or kind == KitWorld.PILASTER:
			if city.layout.lot_at(x, z, 0.5) == null:
				bad_facade += 1
		elif KitWorld.is_flat(kind):
			if not CityLayout.on_road(x, z, -0.1):
				bad_mark += 1
	TestLib.check(bad_roof == 0, "every rooftop unit stands on its building's roof (%d off)" % bad_roof)
	TestLib.check(bad_facade == 0, "every facade piece is against a building (%d off)" % bad_facade)
	TestLib.check(bad_mark == 0, "every road marking lies on the road (%d off)" % bad_mark)
	var bollards := 0
	for p in kit.placements:
		if int(p["kind"]) == Kit.KC_FIRST + KitWorld.BOLLARD:
			bollards += 1
			var pos: Vector3 = p["pos"]
			if CityLayout.on_road(pos.x, pos.z, 0.0) or city.layout.lot_at(pos.x, pos.z, 0.2) != null:
				TestLib.check(false, "bollard at %s is on the sidewalk" % pos)
	var sources := kit.collider_sources()
	TestLib.check(sources.has("KitKcBollard") and sources.has("KitKcPlanter"), "bollards and planters have pooled colliders")
	TestLib.check(not (sources.has("KitKcCrosswalk") or sources.has("KitKcCornice")), "markings and bands have no colliders")
	TestLib.check(bollards > 0, "bollards line the kerbs (%d)" % bollards)


func _window(city: City) -> void:
	var win = city.kit_window()
	win.show_all()
	var mi := win.node as MeshInstance3D
	TestLib.check(mi != null and win.mesh.get_surface_count() == 1, "everything is still ONE surface, one draw call")
	var all_tris: int = win.triangles
	win.update(Vector2(Game.SPAWN.x, Game.SPAWN.z), true)
	var kit := city.street_kit() as Kit
	var near_kc := 0
	var cam := Vector2(Game.SPAWN.x, Game.SPAWN.z)
	for p in kit.placements:
		var pos: Vector3 = p["pos"]
		if int(p["kind"]) >= Kit.KC_FIRST and Vector2(pos.x, pos.z).distance_to(cam) < win.near_radius():
			var g := kit.geo(int(p["kind"]), true, int(p["district"]), int(p["variant"]))
			near_kc += int(g.get("count", 0)) / 3
	TestLib.check(win.kc_props > 0, "city-kit pieces are in the window near the spawn (%d)" % win.kc_props)
	TestLib.check(near_kc < 9000, "city-kit triangles near the spawn stay under 9000 (%d)" % near_kc)
	TestLib.check(win.triangles > 0 and all_tris > win.triangles, "the window rebuilds around the camera (%d of %d tris)" % [win.triangles, all_tris])
	# a placement at height: a rooftop unit's vertices sit at the roof height in the filled mesh
	win.show_all()
	var arr: Array = win.mesh.surface_get_arrays(0)
	var maxy := 0.0
	for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
		maxy = maxf(maxy, v.y)
	TestLib.check(maxy > 15.0, "rooftop units reach roof height (top %.1f m)" % maxy)


func _credits() -> void:
	var f := FileAccess.open("res://../docs/THIRD_PARTY.md", FileAccess.READ)
	var txt := f.get_as_text() if f != null else ""
	TestLib.check(txt.contains("Downtown City MegaKit") and txt.contains("kit_city_"), "the Downtown City MegaKit is credited in docs/THIRD_PARTY.md")
