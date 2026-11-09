extends RefCounted
## Mountain and outskirt sites and vegetation (wave 105) in the REAL game scene: the eleven site pads (flat, dry, clear of the roads), the switchback roads that reach the observatory and the
## radio tower, the deterministic scatter (forests, tree line, nothing on roads, water and pads), the multimesh vegetation around the hero (draw and triangle budgets per tier, LODs, trunk
## colliders), the sites built on approach (meshes, colliders, discovery, rewards, activities), the cave (in, stash, out), guard rails on the hairpins, the cloud deck / snow / fog of the
## mountains, the parked rides, the map pins.
## Run: tools/test.sh tests/test_outskirts_sites.gd   (about 90 s; waits on counters, positions and game time, never on frame counts)

const K := 4
const TIMEOUT_SECONDS := 60.0

var city: City
var p: Player


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	OutskirtsSites.reset_found()
	Sfx.muted = true
	_data()
	_roads()
	_scatter()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	TestLib.check(city != null and p != null and city.vegetation != null and city.sites != null, "the real scene has a city with the vegetation and the sites")
	if city == null or p == null or city.vegetation == null or city.sites == null:
		_restore()
		return
	p.set_physics_process(true)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await _city_is_untouched(host)
	await _forest(host)
	await _tiers(host)
	await _sites_built(host)
	await _discovery_and_activities(host)
	await _cave(host)
	await _rails(host)
	await _weather(host)
	await _rides(host)
	_map()
	Input.action_release(&"move_forward")
	_restore()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _wait_counter(host: Node, what: Callable, secs: float) -> bool:
	var t0 := Engine.get_physics_frames()
	while float(Engine.get_physics_frames() - t0) / 60.0 < secs:
		if what.call():
			return true
		await host.get_tree().process_frame
	return what.call()


# --- data -------------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	var list := OutskirtsSites.list
	TestLib.check(list.size() == 11, "eleven sites (%d)" % list.size())
	var kinds := {}
	for s in list:
		kinds[s["kind"]] = true
	for k in [&"observatory", &"tower", &"mine", &"crash", &"cave", &"cabins", &"village", &"farm"]:
		TestLib.check(kinds.has(k), "a site of kind %s exists" % k)
	var flat_bad := 0
	var wet_bad := 0
	var wet_ids := ""
	var road_bad := 0
	var apart_bad := 0
	for i in list.size():
		var s: Dictionary = list[i]
		var c: Vector3 = s["pos"]
		var r: float = s["r"]
		var crater: bool = s["kind"] == &"crash"
		for k in 9:
			var a := TAU * float(k) / 8.0
			var rr := 0.0 if k == 8 else r * 0.7
			var q := Vector2(c.x + cos(a) * rr, c.z + sin(a) * rr)
			var h := TerrainHeight.height_at(q.x, q.y)
			if not crater and absf(h - float(s["pad_y"])) > 0.35:
				flat_bad += 1
			if crater and (h > float(s["pad_y"]) + 3.0 or h < TerrainHeight.SEA_LEVEL + 0.5):
				flat_bad += 1
			if TerrainHeight.is_water(q.x, q.y) or WaterLayout.surface_at(q.x, q.y) != TerrainHeight.NO_WATER:
				wet_bad += 1
				wet_ids += " %s" % String(s["id"])
		if not s.has("road"):
			var reach: float = s["reach"]                             # no road runs through the pad or its blend (a road bench and a pad would fight)
			for road in TerrainRoads.roads():
				var rp: PackedVector2Array = road["pos"]
				for k in range(0, rp.size(), 2):
					if rp[k].distance_to(Vector2(c.x, c.z)) < reach + 6.0:
						road_bad += 1
						break
		for j in range(i + 1, list.size()):
			var o: Vector3 = (list[j] as Dictionary)["pos"]
			if Vector2(o.x - c.x, o.z - c.z).length() < r + float((list[j] as Dictionary)["r"]) + 30.0:
				apart_bad += 1
	var sky_bad := 0
	for s2 in list:
		var c2: Vector3 = s2["pos"]
		if TerrainHeight.city_distance(c2.x, c2.z) - float(s2["r"]) < 190.0:
			sky_bad += 1                                              # the far skyline of towers reaches about 180 m beyond the plateau
	TestLib.check(sky_bad == 0, "no site pad reaches into the skyline of towers beyond the city (%d)" % sky_bad)
	TestLib.check(flat_bad == 0, "every pad is flat at its height (the crash site a bowl above the sea) (%d samples off)" % flat_bad)
	TestLib.check(wet_bad == 0, "no pad stands in water (%d samples wet:%s)" % [wet_bad, wet_ids])
	TestLib.check(road_bad == 0, "the free-standing sites keep clear of the roads (%d)" % road_bad)
	TestLib.check(apart_bad == 0, "the pads do not overlap (%d)" % apart_bad)
	TestLib.check(OutskirtsSites.inside(c_of(&"mine").x, c_of(&"mine").z, 0.0) >= 0 and OutskirtsSites.inside(0.0, 0.0, 0.0) == -1, "inside() knows the pads")
	TestLib.check(OutskirtsSites.carve(0.0, 0.0, 0.0) == 0.0, "the city plateau is untouched by the pads")
	var hooks := OutskirtsSites.hooks()
	TestLib.check(hooks.size() == 11 and int(hooks[0]["reward"]) > 0 and String(hooks[0]["tag"]) != "", "every site is a mission hook with a reward and a line of text (%d)" % hooks.size())
	var markers := OutskirtsSites.map_markers()
	TestLib.check(markers.size() == 10, "ten pins on the map at the start: the hidden cave is not one of them (%d)" % markers.size())
	var vp := OutskirtsSites.vehicle_points()
	TestLib.check(vp.size() >= 12, "rides wait at the sites (%d)" % vp.size())
	var ids := {}
	for v in vp:
		ids[v["id"]] = true
	TestLib.check(ids.size() == vp.size(), "every ride has its own id")


func c_of(id: StringName) -> Vector3:
	return OutskirtsSites.by_id(id)["pos"]


func _roads() -> void:
	var by_name := {}
	for r in TerrainRoads.roads():
		by_name[String(r["name"])] = r
	TestLib.check(by_name.has("SUMMIT ROAD") and by_name.has("RIDGE TRACK"), "the two mountain roads exist")
	for nm in ["SUMMIT ROAD", "RIDGE TRACK"]:
		var r: Dictionary = by_name[nm]
		var pts: PackedVector2Array = r["pos"]
		var prof: PackedFloat32Array = r["prof"]
		TestLib.check(float(r["len"]) > 700.0 and prof[prof.size() - 1] - prof[0] > 90.0, "%s climbs: %.0f m long, %.0f m of height" % [nm, float(r["len"]), prof[prof.size() - 1] - prof[0]])
		var worst := 0.0
		for i in range(1, pts.size()):
			worst = maxf(worst, absf(prof[i] - prof[i - 1]) / maxf(pts[i].distance_to(pts[i - 1]), 1.0))
		TestLib.check(worst <= 0.145, "%s keeps its grade (%.3f)" % [nm, worst])
		# switchbacks: the heading turns through a large angle over the climb
		var turn := 0.0
		for i in range(2, pts.size()):
			turn += absf(angle_difference((pts[i - 1] - pts[i - 2]).angle(), (pts[i] - pts[i - 1]).angle()))
		TestLib.check(rad_to_deg(turn) > 200.0, "%s winds up the hillside (%.0f degrees of turning)" % [nm, rad_to_deg(turn)])
	var obs := OutskirtsSites.by_id(&"observatory")
	var summit: PackedVector2Array = (by_name["SUMMIT ROAD"] as Dictionary)["pos"]
	var op: Vector3 = obs["pos"]
	TestLib.check(Vector2(op.x, op.z).distance_to(summit[summit.size() - 1]) < 40.0, "the observatory stands where the summit road ends")
	TestLib.check(op.y > 120.0, "the observatory is high up (%.0f m)" % op.y)
	var tw := OutskirtsSites.by_id(&"radio_tower")
	var ridge: PackedVector2Array = (by_name["RIDGE TRACK"] as Dictionary)["pos"]
	TestLib.check(Vector2((tw["pos"] as Vector3).x, (tw["pos"] as Vector3).z).distance_to(ridge[ridge.size() - 1]) < 40.0, "the radio tower stands where the ridge track ends")
	var segs := GuardRails.segments()
	var on_hairpins := 0
	for s: Dictionary in segs:
		if s["road"] == "SUMMIT ROAD" or s["road"] == "RIDGE TRACK":
			on_hairpins += 1
	TestLib.check(on_hairpins > 20, "guard rails line the drops of the mountain roads (%d pieces on the two climbs, %d in all)" % [on_hairpins, segs.size()])


# --- the scatter ------------------------------------------------------------------------------------------------------------------------------

func _scatter() -> void:
	VegScatter.warm()
	var a := VegScatter.cell(VegScatter.T_TREES, -40, -14)
	var b := VegScatter.cell(VegScatter.T_TREES, -40, -14)
	TestLib.check(a == b and not a.is_empty(), "the scatter is deterministic and a forest cell has trees (%d)" % (a.size() / VegScatter.STRIDE))
	var counts := {"forest": 0, "plains": 0, "desert": 0, "city": 0, "mountain": 0, "high": 0}
	var bad_wet := 0
	var bad_road := 0
	var bad_pad := 0
	var bad_line := 0
	var species := {}
	var n_cells := 0
	for ci in range(-94, 94, 3):
		for cj in range(-94, 94, 3):
			var cx := (float(ci) + 0.5) * VegScatter.CELL
			var cz := (float(cj) + 0.5) * VegScatter.CELL
			var d := TerrainHeight.city_distance(cx, cz)
			var arr := VegScatter.cell(VegScatter.T_TREES, ci, cj)
			var n := arr.size() / VegScatter.STRIDE
			n_cells += 1
			if d <= 0.0:
				counts["city"] += n
			elif TerrainBase.forest_weight(cx, cz) > 0.7 and TerrainHeight.height_at(cx, cz) < 100.0:
				counts["forest"] += n
			elif TerrainBase.desert_weight(cx, cz) > 0.7 and TerrainBase.forest_weight(cx, cz) < 0.2:
				counts["desert"] += n
			if TerrainHeight.height_at(cx, cz) > 250.0:
				counts["high"] += n
			for k in n:
				var o := k * VegScatter.STRIDE
				var x := arr[o]
				var z := arr[o + 2]
				species[int(arr[o + 5])] = int(species.get(int(arr[o + 5]), 0)) + 1
				if TerrainHeight.is_water(x, z):
					bad_wet += 1
				var rd := TerrainRoads.nearest(x, z)
				if int(rd[1]) >= 0 and float(rd[0]) < 8.0:
					bad_road += 1
				if OutskirtsSites.inside(x, z, 3.0) >= 0:
					bad_pad += 1
				if arr[o + 1] > VegScatter.TREE_LINE + 60.0:
					bad_line += 1
	TestLib.check(int(counts["city"]) == 0, "no tree grows on the city plateau")
	TestLib.check(int(counts["forest"]) > 600, "the forest hills are full of trees (%d in the sampled cells)" % int(counts["forest"]))
	TestLib.check(int(counts["forest"]) > 3 * maxi(int(counts["desert"]), 1), "the forest is much denser than the desert (%d vs %d)" % [int(counts["forest"]), int(counts["desert"])])
	TestLib.check(int(counts["high"]) == 0, "nothing grows above the tree line (%d on ground above 250 m)" % int(counts["high"]))
	TestLib.check(bad_wet == 0 and bad_road == 0 and bad_pad == 0 and bad_line == 0, "no tree stands in water (%d), on a road (%d), on a pad (%d) or above the line (%d)" % [bad_wet, bad_road, bad_pad, bad_line])
	TestLib.check(species.has(VegScatter.PINE) and species.has(VegScatter.BROAD) and species.has(VegScatter.DEAD), "pines, broadleaf trees and dead trunks all grow (%s)" % str(species))
	var rocks := 0
	var big := 0
	for ci in range(-60, -40):
		for cj in range(-90, -60):
			var ra := VegScatter.cell(VegScatter.T_ROCKS, ci, cj)
			rocks += ra.size() / VegScatter.STRIDE
			for k in ra.size() / VegScatter.STRIDE:
				if ra[k * VegScatter.STRIDE + 4] > 2.4:
					big += 1
	TestLib.check(rocks > 100 and big > 1, "rocks and boulders lie on the hills (%d, %d big)" % [rocks, big])
	TestLib.check(VegKit.available(), "the vegetation kit loads")
	var worst_tris := 0
	for nm in ["pine_a", "pine_b", "broad_a", "broad_b", "dead_a", "bush", "rock_c"]:
		worst_tris = maxi(worst_tris, VegKit.tris(nm))
	TestLib.check(worst_tris <= 900, "every near piece is light (%d triangles at most)" % worst_tris)
	TestLib.check(VegKit.tris("pine_l1") < 100 and VegKit.tris("pine_l2") < 30 and VegKit.tris("broad_l2") < 60, "the far LODs are tiny (%d / %d / %d)" % [VegKit.tris("pine_l1"), VegKit.tris("pine_l2"), VegKit.tris("broad_l2")])


# --- the real scene ---------------------------------------------------------------------------------------------------------------------------

func _teleport(pos: Vector3) -> void:
	var y := TerrainHeight.height_at(pos.x, pos.z) + 1.0 if pos.y < -900.0 else pos.y
	p.teleport_to(Vector3(pos.x, y, pos.z))


func _city_is_untouched(host: Node) -> void:
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 12)
	var st := city.vegetation.stats()
	TestLib.check(int(st["instances"]) == 0, "in the middle of the city there is no vegetation at all (%d instances)" % int(st["instances"]))
	TestLib.check(int(city.sites.stats()["built"]) == 0, "and no site is built there")


func _forest(host: Node) -> void:
	city.vegetation.set_quality(1)
	var spot := Vector3(-1320.0, -900.0, -520.0)
	p.teleport_to(Vector3(spot.x, TerrainHeight.height_at(spot.x, spot.z) + 1.0, spot.z))
	var ok := await _wait_counter(host, func() -> bool: return int(city.vegetation.stats()["instances"]) > 300 and int(city.vegetation.stats()["jobs"]) >= 1, TIMEOUT_SECONDS)
	var st := city.vegetation.stats()
	TestLib.check(ok, "walking into the forest fills the multimeshes from the worker thread (%d plants, %d jobs)" % [int(st["instances"]), int(st["jobs"])])
	TestLib.check(int(st["slots"]) <= 17 and int(st["slots"]) >= 4, "the whole forest is a handful of draw calls (%d multimeshes)" % int(st["slots"]))
	var sc: Dictionary = city.vegetation.slot_counts()
	var near_trees := int(sc.get("pine_a", 0)) + int(sc.get("broad_a", 0)) + int(sc.get("pine_b", 0)) + int(sc.get("broad_b", 0))
	var mid_trees := int(sc.get("pine_l1", 0)) + int(sc.get("broad_l1", 0))
	var far_trees := int(sc.get("pine_l2", 0)) + int(sc.get("broad_l2", 0))
	TestLib.check(mid_trees > 0 and far_trees > 0, "the forest has its mid and far LODs (%d near, %d mid, %d far)" % [near_trees, mid_trees, far_trees])
	TestLib.check(int(st["tris"]) < 120000, "the forest stays under the triangle budget at MED (%d)" % int(st["tris"]))
	TestLib.check(int(st["colliders"]) > 3, "trunks and boulders around the hero are solid (%d colliders)" % int(st["colliders"]))
	# a collider really is a tree: its position lies on a plant of the scatter
	var pos := p.global_position
	var found_tree := false
	for ci in range(int(floor((pos.x - 40.0) / VegScatter.CELL)), int(floor((pos.x + 40.0) / VegScatter.CELL)) + 1):
		for cj in range(int(floor((pos.z - 40.0) / VegScatter.CELL)), int(floor((pos.z + 40.0) / VegScatter.CELL)) + 1):
			var arr := VegScatter.cell(VegScatter.T_TREES, ci, cj)
			if arr.size() > 0:
				found_tree = true
	TestLib.check(found_tree, "there are trees within 40 m of the hero in the scatter")
	# walk: the multimeshes follow (the focus moves, the jobs keep coming)
	var jobs0 := int(st["jobs"])
	p.teleport_to(Vector3(spot.x - 120.0, TerrainHeight.height_at(spot.x - 120.0, spot.z) + 1.0, spot.z))
	var moved := await _wait_counter(host, func() -> bool: return int(city.vegetation.stats()["jobs"]) > jobs0, TIMEOUT_SECONDS)
	TestLib.check(moved, "the plants are re-arranged around the hero when he moves (%d jobs)" % int(city.vegetation.stats()["jobs"]))
	# the shader: wind and snow parameters exist on the material
	var mat := VegKit.material("pine_a")
	TestLib.check(mat.shader != null and mat.get_shader_parameter(&"atlas") != null, "the vegetation shader has its atlas")


func _tiers(host: Node) -> void:
	var spot := Vector3(-1320.0, 0.0, -520.0)
	var res := {}
	for t in 3:
		city.vegetation.set_quality(t)
		city.vegetation.settle(Vector3(spot.x, TerrainHeight.height_at(spot.x, spot.z) + 1.0, spot.z))
		await TestLib.frames(host, 2)
		res[t] = city.vegetation.stats()
	TestLib.check(int(res[0]["tris"]) < int(res[1]["tris"]) and int(res[1]["tris"]) < int(res[2]["tris"]), "density scales by tier: %d < %d < %d triangles" % [int(res[0]["tris"]), int(res[1]["tris"]), int(res[2]["tris"])])
	TestLib.check(int(res[0]["tris"]) < 65000, "LOW keeps the forest under 65 k triangles (%d)" % int(res[0]["tris"]))
	TestLib.check(int(res[1]["tris"]) < 120000 and int(res[2]["tris"]) < 210000, "MED and HIGH stay under their budgets (%d, %d)" % [int(res[1]["tris"]), int(res[2]["tris"])])
	TestLib.check(int(res[0]["colliders"]) <= int(res[2]["colliders"]), "fewer trunk colliders on LOW")
	city.vegetation.set_quality(1)


func _sites_built(host: Node) -> void:
	var total_tris := 0
	for s in OutskirtsSites.list:
		var id: StringName = s["id"]
		var sp: Vector3 = s["pos"]
		_teleport_near(sp, s)
		city.sites.call(&"settle", p.global_position)
		await TestLib.frames(host, 2)
		var ok: bool = city.sites.is_built(id)
		TestLib.check(ok, "%s is built on approach" % String(s["name"]))
		if ok:
			var node: Node3D = city.sites.site_node(id)
			var body := node.get_node_or_null("Collision") as StaticBody3D
			var kit := node.get_node_or_null("Kit") as MeshInstance3D
			var tris := OutskirtsWorld.tri_count(kit.mesh)
			total_tris += tris
			TestLib.check(body != null and body.get_child_count() >= 1 and kit != null and tris > 200 and tris < 16000, "%s has a mesh (%d triangles) and %d collision boxes" % [String(s["name"]), tris, body.get_child_count() if body != null else 0])
			TestLib.check(kit.visibility_range_end > 0.0 and kit.visibility_range_end < 1500.0, "%s is distance culled" % String(s["name"]))
	TestLib.check(total_tris < 90000, "all the sites together stay light (%d triangles)" % total_tris)
	# free again when far away
	_teleport(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 2)
	var freed := await _wait_counter(host, func() -> bool: return not city.sites.is_built(&"observatory") and not city.sites.is_built(&"radio_tower") and not city.sites.is_built(&"cave"), 20.0)
	TestLib.check(freed and int(city.sites.stats()["built"]) <= 6, "the sites are freed when the hero is far away (%d left, the villages near the city stay)" % int(city.sites.stats()["built"]))


func _teleport_near(_sp: Vector3, s: Dictionary) -> void:
	var front := OutskirtsSites.to_world(s, Vector3(0.0, 0.0, -float(s["r"]) - 8.0))
	p.teleport_to(Vector3(front.x, TerrainHeight.height_at(front.x, front.z) + 1.0, front.z))


func _discovery_and_activities(host: Node) -> void:
	OutskirtsSites.reset_found()                         # the earlier phase may have touched some sites on its way past (the arrival tick is timing dependent)
	city.sites.used.clear()
	var pg := Game.progress as Progress
	var c0 := pg.credits
	# the radio tower: arrive, then use the console
	var s := OutskirtsSites.by_id(&"radio_tower")
	_teleport_near(s["pos"], s)
	var arrived := await _wait_counter(host, func() -> bool: return OutskirtsSites.is_found(&"radio_tower"), TIMEOUT_SECONDS)
	TestLib.check(arrived and pg.credits > c0, "arriving at the radio tower discovers it and pays (%d credits)" % (pg.credits - c0))
	var c1 := pg.credits
	var up: Vector3 = city.sites.use_point(&"radio_tower")
	p.teleport_to(Vector3(up.x, TerrainHeight.height_at(up.x, up.z) + 1.0, up.z))
	var used := await _wait_counter(host, func() -> bool: return city.sites.used.has(&"radio_tower"), TIMEOUT_SECONDS)
	TestLib.check(used and pg.credits > c1, "the radio console restores the signal and pays the rest (%d)" % (pg.credits - c1))
	var c2 := pg.credits
	await TestLib.frames(host, 90)
	TestLib.check(pg.credits == c2 and int(city.sites.stats()["activities"]) >= 1, "an activity pays only once")
	# the observatory marks every site, the cave pin appears
	TestLib.check(OutskirtsSites.map_markers().size() == 10, "the cave pin is still hidden before the sky scan")
	var o := OutskirtsSites.by_id(&"observatory")
	_teleport_near(o["pos"], o)
	await _wait_counter(host, func() -> bool: return OutskirtsSites.is_found(&"observatory"), TIMEOUT_SECONDS)
	var ou: Vector3 = city.sites.use_point(&"observatory")
	p.teleport_to(Vector3(ou.x, TerrainHeight.height_at(ou.x, ou.z) + 1.0, ou.z))
	var scanned := await _wait_counter(host, func() -> bool: return city.sites.used.has(&"observatory"), TIMEOUT_SECONDS)
	TestLib.check(scanned and OutskirtsSites.is_found(&"cave") and OutskirtsSites.map_markers().size() == 11, "the sky scan puts every site, the hidden cave included, on the map")
	# a cabin rests the hero: hurt, then restored
	var lodge := OutskirtsSites.by_id(&"lodge")
	_teleport_near(lodge["pos"], lodge)
	await TestLib.frames(host, 6)
	p.hp = 20.0
	p.max_hp = 100.0
	var lu: Vector3 = city.sites.use_point(&"lodge")
	p.teleport_to(Vector3(lu.x, TerrainHeight.height_at(lu.x, lu.z) + 1.0, lu.z))
	var rested := await _wait_counter(host, func() -> bool: return p.hp >= 99.0, TIMEOUT_SECONDS)
	TestLib.check(rested, "the lodge heals the hero (%.0f hp)" % p.hp)
	p.max_hp = 1.0e6
	p.hp = p.max_hp


func _cave(host: Node) -> void:
	var s := OutskirtsSites.by_id(&"cave")
	_teleport_near(s["pos"], s)
	city.sites.call(&"settle", p.global_position)
	await TestLib.frames(host, 4)
	var cave: CaveSystem = city.sites.cave
	TestLib.check(cave != null and not cave.inside(), "the cave exists and the hero is outside")
	if cave == null:
		return
	var up: Vector3 = city.sites.use_point(&"cave")
	p.teleport_to(Vector3(up.x, TerrainHeight.height_at(up.x, up.z) + 1.0, up.z))
	var inside := await _wait_counter(host, func() -> bool: return cave.inside(), TIMEOUT_SECONDS)
	TestLib.check(inside and InteriorSpace.active, "walking into the mouth takes the hero into the cave (the interior space is registered)")
	await TestLib.frames(host, 30)
	var gy := TerrainHeight.height_at(p.global_position.x, p.global_position.z)
	TestLib.check(cave.inside() and p.global_position.y < gy - 100.0 and p.global_position.y > -50.0, "he stays in the cave under the mountain, not rescued out (y %.0f, ground %.0f)" % [p.global_position.y, gy])
	var st := cave.stats()
	TestLib.check(int(st["tris"]) > 1500 and int(st["tris"]) < 9000 and int(st["chambers"]) == 4, "four chambers in about %d triangles" % int(st["tris"]))
	# the floor holds: stand still and do not fall through
	var y0 := p.global_position.y
	await TestLib.frames(host, 60)
	TestLib.check(absf(p.global_position.y - y0) < 1.0 and p.is_on_floor(), "the cave floor holds him")
	# the stash
	var cr := Game.progress as Progress
	var c0 := cr.credits
	var sp := cave.stash_point()
	p.teleport_to(Vector3(sp.x + 1.2, sp.y + 1.0, sp.z))
	var took := await _wait_counter(host, func() -> bool: return cave.stash_taken, TIMEOUT_SECONDS)
	TestLib.check(took and cr.credits > c0, "the stash in the last chamber pays (%d)" % (cr.credits - c0))
	# out: walk to the exit ring
	var ex := cave.exit_ring()
	p.teleport_to(Vector3(ex.x, ex.y + 1.0, ex.z))
	await TestLib.frames(host, 4)
	Input.action_press(&"move_forward")
	var out := await _wait_counter(host, func() -> bool: return not cave.inside(), TIMEOUT_SECONDS)
	Input.action_release(&"move_forward")
	TestLib.check(out and not InteriorSpace.active, "the exit ring brings him out")
	var back := p.global_position
	var mouth: Vector3 = s["pos"]
	TestLib.check(Vector2(back.x - mouth.x, back.z - mouth.z).length() < 30.0 and back.y > TerrainHeight.height_at(back.x, back.z) - 1.0, "he stands in front of the mouth again (%.0f m away)" % Vector2(back.x - mouth.x, back.z - mouth.z).length())


func _rails(host: Node) -> void:
	var segs := GuardRails.segments()
	var pick: Dictionary = {}
	for s: Dictionary in segs:
		if s["road"] == "SUMMIT ROAD":
			pick = s
			break
	TestLib.check(not pick.is_empty(), "a rail piece lies on the summit road")
	if pick.is_empty():
		return
	var a: Vector3 = pick["a"]
	p.teleport_to(Vector3(a.x, a.y + 2.0, a.z))
	await TestLib.frames(host, 4)
	var near := false
	var ok := await _wait_counter(host, func() -> bool:
		for b: StaticBody3D in city.sites._rail_bodies:
			if b.global_position.distance_to(a) < 6.0:
				return true
		return false, TIMEOUT_SECONDS)
	near = ok
	TestLib.check(near, "a rail collider follows the hero to the hairpin")
	TestLib.check(int(city.sites.stats()["rail_tris"]) > 0 and city.sites._rail_chunks.size() >= 1, "the rails are merged into a few chunk meshes (%d chunks, %d triangles)" % [city.sites._rail_chunks.size(), int(city.sites.stats()["rail_tris"])])


func _weather(host: Node) -> void:
	var mw := MountainWeather.instance
	TestLib.check(mw != null, "the mountain weather node exists")
	if mw == null:
		return
	# over the city: no cloud deck, no snow, no extra fog
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 6)
	TestLib.check(mw.cloud_alpha < 0.01 and mw.snow_rate < 0.01 and MountainWeather.fog_boost < 0.01, "no cloud deck, snow or extra fog over the city")
	# in the high mountains: on the observatory pad (about 150 m up) the deck is close, higher up it snows
	var o := OutskirtsSites.by_id(&"observatory")
	var op: Vector3 = o["pos"]
	p.teleport_to(Vector3(op.x, op.y + 40.0, op.z))
	await _wait_counter(host, func() -> bool: return mw.cloud_alpha > 0.05, 8.0)
	TestLib.check(mw.cloud_alpha > 0.05 and MountainWeather.fog_boost > 0.05, "near the cloud deck on the ridge: clouds (%.2f) and thicker fog (%.2f)" % [mw.cloud_alpha, MountainWeather.fog_boost])
	TestLib.check(MountainWeather.snow_for(op.x, 290.0, op.z) > 0.9 and MountainWeather.snow_for(0.0, 290.0, 0.0) == 0.0 and MountainWeather.snow_for(op.x, 20.0, op.z) == 0.0, "snow falls high in the mountains only")
	# the vegetation shader dusts snow by height
	TestLib.check(VegKit.material("pine_a").shader.code.contains("snow_start"), "trees get their snow dusting from the shader")
	var mat := OutskirtsKit.material()
	TestLib.check(mat.shader.code.contains("snow_start"), "the site roofs get their snow too")


func _rides(host: Node) -> void:
	var mgr := Game.vehicles as VehicleManager
	var pts := VehicleSpawns.all_points()
	var mine_ids: Array = []
	for pt in pts:
		if String(pt["id"]).begins_with("site_pine_hollow"):
			mine_ids.append(pt["id"])
	TestLib.check(mine_ids.size() == 2, "two rides wait at Pine Hollow (%d)" % mine_ids.size())
	var pt0 := VehicleSpawns.point(mine_ids[0])
	var pos: Vector3 = pt0["pos"]
	p.teleport_to(Vector3(pos.x, pos.y + 1.0, pos.z - 20.0))
	var spawned := await _wait_counter(host, func() -> bool: return is_instance_valid(mgr._spawned.get(mine_ids[0])), TIMEOUT_SECONDS)
	TestLib.check(spawned, "a pickup truck appears at Pine Hollow when the hero comes near")


func _map() -> void:
	var ms := Game.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	TestLib.check(ms != null, "the map screen exists")
	if ms == null:
		return
	var sites := 0
	for mk in ms.collect_markers():
		if mk["kind"] == &"site":
			sites += 1
	TestLib.check(sites == 11, "the map shows the sites as pins (%d)" % sites)
	TestLib.check(MapScreen.KINDS.has(&"site") and MapScreen.KIND_COLOR.has(&"site") and MapScreen.KIND_LABEL.has(&"site"), "the SITES legend row exists")
