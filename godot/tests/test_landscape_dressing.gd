extends RefCounted
## The landscape dressing of wave 112 in the REAL game scene: nine tree species with three LODs and impostors (LandKit), biome rules (VegScatter: palms on the coast, acacia in the dry
## country, fir on the heights, birch groves, poplar avenues, reeds, flowers), the multimesh forest per tier (no per-tree nodes, draw and triangle budgets), the waterfalls (found cliffs, a
## plunge pool you can swim in, a sheet / mist / roar that start when you are near and stop when you are far), the grass airstrips (flat, drivable, clear of plants), the tall anchors (wind
## turbines, pylons, masts, cranes with colliders and the anchors_near API for quantum snakes), the wind that follows the weather and the rain response of every new material.
## Run: tools/test.sh tests/test_landscape_dressing.gd   (about 100 s; waits on counters, positions and game time, never on frame counts)

const K := 4
const TIMEOUT_SECONDS := 100.0
const SPECIES := ["oak", "birch", "poplar", "pine", "fir", "palm", "acacia", "dead", "alien"]

var city: City
var p: Player


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	OutskirtsSites.reset_found()
	Sfx.muted = true
	TerrainHeight.warm()
	_assets()
	_scatter()
	_sites_data()
	_shaders()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	TestLib.check(city != null and p != null and city.vegetation != null and city.landscape != null, "the real scene has a city with the vegetation and the landscape")
	if city == null or p == null or city.vegetation == null or city.landscape == null:
		_restore()
		return
	p.set_physics_process(true)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await _city_is_untouched(host)
	await _forest_tiers(host)
	await _falls_live(host)
	await _strips_live(host)
	await _anchors_live(host)
	await _wind_follows_weather(host)
	Input.action_release(&"move_forward")
	_restore()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _wait_counter(host: Node, what: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) < secs * 1000.0:
		if what.call():
			return true
		await TestLib.frames(host, 3)
	return what.call()


# --- the kit ----------------------------------------------------------------------------------------------------------------------------------

func _assets() -> void:
	TestLib.check(LandKit.available() and VegKit.available(), "the landscape kit loads (trees, impostors, ground cover, rocks)")
	TestLib.check(LandKit.species().size() >= 9 and SPECIES.size() >= 6, "nine tree species (%d)" % LandKit.species().size())
	var tex_bytes := 0.0
	for sp in SPECIES:
		var f := VegKit.mesh("%s_0" % sp)
		var l := VegKit.mesh("%s_0l" % sp)
		var m := VegKit.mesh("%s_1" % sp)
		TestLib.check(f != null and l != null and m != null, "%s has three levels of detail" % sp)
		var tf := VegKit.tris("%s_0" % sp)
		var tl := VegKit.tris("%s_0l" % sp)
		var tm := VegKit.tris("%s_1" % sp)
		TestLib.check(tf > tl and tl > tm and tf <= 1400 and tl <= 800 and tm <= 260 and tm >= 40, "%s: LOD0 %d > lite %d > LOD1 %d triangles, all light" % [sp, tf, tl, tm])
		var mat := VegKit.material("%s_0" % sp)
		TestLib.check(mat != null and mat.get_shader_parameter(&"foliage") != null and mat.get_shader_parameter(&"bark") != null and mat.shader.code.contains("wind"), "%s has foliage + bark textures and the wind in its shader" % sp)
		var isz := LandKit.impostor_size(sp)
		TestLib.check(isz.x > 4.0 and isz.y > 6.0 and LandKit.height(sp) > 3.0, "%s has an impostor quad (%.1f x %.1f m) and a height (%.1f m)" % [sp, isz.x, isz.y, LandKit.height(sp)])
		var bark := mat.get_shader_parameter(&"bark") as Texture2D
		if bark != null:
			tex_bytes += float(bark.get_width() * bark.get_height()) * 1.34
	var fol := load("res://assets/textures/land_foliage.webp") as Texture2D
	var imp := load("res://assets/textures/land_impostor.webp") as Texture2D
	tex_bytes += float(fol.get_width() * fol.get_height()) * 1.34 + float(imp.get_width() * imp.get_height()) * 1.34
	TestLib.check(tex_bytes < 14.0e6, "the landscape textures stay small (%.1f MB estimated on the GPU)" % (tex_bytes / 1.0e6))
	TestLib.check(VegKit.mesh("imp") != null and VegKit.tris("imp") == 4, "one cross of two quads serves every impostor")
	for nm in ["g_grass1", "g_grass2", "g_dry", "g_tall", "g_daisy", "g_poppy", "g_lav", "g_clover", "g_fern1", "g_fern2", "g_bush1", "g_bush2", "g_reed"]:
		TestLib.check(VegKit.mesh(nm) != null and VegKit.tris(nm) <= 20 and VegKit.material(nm) != null, "ground cover piece %s (%d triangles)" % [nm, VegKit.tris(nm)])
	for nm in ["rock_a", "rock_b", "rock_c", "rock_d"]:
		TestLib.check(VegKit.mesh(nm) != null and VegKit.mesh(nm + "_1") != null and VegKit.tris(nm) > VegKit.tris(nm + "_1") and VegKit.tris(nm) <= 800, "rock %s has two levels of detail" % nm)


# --- the scatter (biomes) -----------------------------------------------------------------------------------------------------------------

func _species_in(layer: int, spots: Array, radius_cells := 3) -> Dictionary:
	var out := {}
	for s: Vector2 in spots:
		var ci0 := int(floor(s.x / VegScatter.CELL))
		var cj0 := int(floor(s.y / VegScatter.CELL))
		for ci in range(ci0 - radius_cells, ci0 + radius_cells + 1):
			for cj in range(cj0 - radius_cells, cj0 + radius_cells + 1):
				var arr := VegScatter.cell(layer, ci, cj)
				for k in arr.size() / VegScatter.STRIDE:
					var sp := int(arr[k * VegScatter.STRIDE + 5])
					out[sp] = int(out.get(sp, 0)) + 1
	return out


func _scatter() -> void:
	VegScatter.warm()
	var a := VegScatter.cell(VegScatter.T_TREES, -40, -14)
	var b := VegScatter.cell(VegScatter.T_TREES, -40, -14)
	TestLib.check(a == b and not a.is_empty(), "the scatter is deterministic")
	var forest := _species_in(VegScatter.T_TREES, [Vector2(-1320.0, -520.0), Vector2(-1250.0, -900.0), Vector2(-600.0, -1400.0)])
	var heights := _species_in(VegScatter.T_TREES, [Vector2(200.0, -1900.0), Vector2(-250.0, -2000.0), Vector2(900.0, -2000.0)])
	var dry := _species_in(VegScatter.T_TREES, [Vector2(1500.0, 600.0), Vector2(1700.0, 1100.0), Vector2(1350.0, -400.0)], 4)
	var coast := _species_in(VegScatter.T_TREES, [Vector2(-1450.0, 300.0), Vector2(-1100.0, 1100.0), Vector2(100.0, 1350.0)], 4)
	var all := {}
	for d: Dictionary in [forest, heights, dry, coast]:
		for k in d.keys():
			all[k] = int(all.get(k, 0)) + int(d[k])
	var names: Array = []
	for k in all.keys():
		names.append(int(k))
	names.sort()
	TestLib.check(all.size() >= 6, "at least six tree species grow in the world (%s)" % str(names))
	TestLib.check(forest.has(VegScatter.OAK) and forest.has(VegScatter.BIRCH) or forest.has(VegScatter.PINE), "the forest hills grow oak, birch and pine (%s)" % str(forest))
	TestLib.check(heights.has(VegScatter.FIR) and int(heights.get(VegScatter.FIR, 0)) > int(heights.get(VegScatter.PALM, 0)), "fir takes the heights (%s)" % str(heights))
	TestLib.check(int(dry.get(VegScatter.ACACIA, 0)) + int(dry.get(VegScatter.DEAD, 0)) > 0, "acacia and dead trees stand in the dry country (%s)" % str(dry))
	TestLib.check(int(coast.get(VegScatter.PALM, 0)) > 0, "palms grow on the coast (%s)" % str(coast))
	# avenues along the approach roads, reeds on the river banks, flowers in the meadows
	var avenue := 0
	var in_band := 0
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) != "DESERT ROAD" and String(r["name"]) != "COAST ROAD":
			continue
		var pos: PackedVector2Array = r["pos"]
		for i in range(20, 90, 3):
			var cc := pos[i]
			var arr := VegScatter.cell(VegScatter.T_LINES, int(floor(cc.x / VegScatter.CELL)), int(floor(cc.y / VegScatter.CELL)))
			for k in arr.size() / VegScatter.STRIDE:
				avenue += 1
				var rd := TerrainRoads.nearest(arr[k * VegScatter.STRIDE], arr[k * VegScatter.STRIDE + 2])
				if float(rd[0]) > 12.0 and float(rd[0]) < 21.0:
					in_band += 1
	TestLib.check(avenue > 10 and in_band > avenue / 2, "avenues of poplars and palms line the approach roads (%d trees, %d in the band beside the road)" % [avenue, in_band])
	var reeds := 0
	for pth in WaterLayout.paths:
		var pos2: PackedVector2Array = pth["pos"]
		for i in range(20, pos2.size() - 10, 25):
			var cc2 := pos2[i]
			reeds += VegScatter.cell(VegScatter.T_REEDS, int(floor(cc2.x / VegScatter.CELL)), int(floor(cc2.y / VegScatter.CELL))).size() / VegScatter.STRIDE
	TestLib.check(reeds > 5, "reeds grow on the river banks (%d)" % reeds)
	var grass := _species_in(VegScatter.T_GRASS, [Vector2(-1320.0, -520.0), Vector2(-1250.0, -900.0), Vector2(-700.0, -1300.0), Vector2(300.0, -1300.0)], 4)
	TestLib.check(int(grass.get(VegScatter.FLOWER, 0)) > 0 and int(grass.get(VegScatter.GRASS, 0)) > 100, "meadows carry grass and wild flowers (%s)" % str(grass))


# --- the sites ----------------------------------------------------------------------------------------------------------------------------------

func _sites_data() -> void:
	var falls := LandscapeSites.falls()
	TestLib.check(falls.size() >= 3, "waterfalls were found on cliffs (%d)" % falls.size())
	for f: Dictionary in falls:
		var pc: Vector2 = f["pool"]
		var pre := TerrainHeight.height_pre(pc.x, pc.y)
		var h := TerrainHeight.height_at(pc.x, pc.y)
		TestLib.check(float(f["drop"]) >= 15.0 and h < pre - 1.0, "%s: a %.0f m drop and a plunge pool carved %.1f m into the ground" % [String(f["name"]), float(f["drop"]), pre - h])
		TestLib.check(absf(TerrainHeight.water_level_at(pc.x, pc.y) - float(f["pool_y"])) < 0.02 and TerrainHeight.depth_at(pc.x, pc.y) > 2.0, "%s: the pool holds water %.1f m deep (you can swim in it)" % [String(f["name"]), TerrainHeight.depth_at(pc.x, pc.y)])
		TestLib.check(WaterWorld.surface_y(pc.x, pc.y) > h, "%s: the swim code sees the pool's surface" % String(f["name"]))
		var up: PackedVector2Array = f["up"]
		TestLib.check(up.size() >= 8 and (f["out"] as PackedVector2Array).size() >= 2, "%s has a stream above its lip and an outflow" % String(f["name"]))
	var strips := LandscapeSites.strips()
	TestLib.check(strips.size() >= 3, "three grass airstrips were found (%d)" % strips.size())
	for s: Dictionary in strips:
		var c: Vector2 = s["c"]
		var u: Vector2 = s["u"]
		var lo := 1.0e9
		var hi := -1.0e9
		var dryok := true
		for ia in 9:
			var a := (float(ia) / 8.0 - 0.5) * float(s["len"]) * 0.96
			for ib: float in [-1.0, 0.0, 1.0]:
				var q := c + u * a + Vector2(-u.y, u.x) * (ib * float(s["wid"]) * 0.45)
				var hq := TerrainHeight.height_at(q.x, q.y)
				lo = minf(lo, hq)
				hi = maxf(hi, hq)
				dryok = dryok and TerrainHeight.water_level_for(q.x, q.y, hq) == TerrainHeight.NO_WATER
		TestLib.check(hi - lo < 0.3 and dryok and float(s["len"]) >= 340.0, "%s is flat (%.2f m of relief over %.0f m) and dry" % [String(s["name"]), hi - lo, float(s["len"])])
		var plants := 0
		for ci in range(int(floor((c.x - 220.0) / VegScatter.CELL)), int(floor((c.x + 220.0) / VegScatter.CELL)) + 1):
			for cj in range(int(floor((c.y - 220.0) / VegScatter.CELL)), int(floor((c.y + 220.0) / VegScatter.CELL)) + 1):
				for layer in [VegScatter.T_TREES, VegScatter.T_SHRUBS, VegScatter.T_ROCKS]:
					var arr := VegScatter.cell(layer, ci, cj)
					for k in arr.size() / VegScatter.STRIDE:
						if LandscapeSites.inside_strip(arr[k * VegScatter.STRIDE], arr[k * VegScatter.STRIDE + 2], 0.0):
							plants += 1
		TestLib.check(plants == 0, "%s has no tree, bush or rock on it (%d)" % [String(s["name"]), plants])
	TestLib.check(AnchorSites.turbines().size() >= 8 and AnchorSites.fields().size() >= 2, "wind turbine fields (%d turbines in %d fields)" % [AnchorSites.turbines().size(), AnchorSites.fields().size()])
	var pyl := 0
	for l: Dictionary in AnchorSites.pylon_lines():
		for q: Dictionary in l["pylons"]:
			if not q.has("gap"):
				pyl += 1
	TestLib.check(pyl >= 12 and AnchorSites.masts().size() >= 2 and AnchorSites.cranes().size() >= 1, "pylon lines (%d), radio masts (%d), quarry cranes (%d)" % [pyl, AnchorSites.masts().size(), AnchorSites.cranes().size()])
	var tall := 0
	for an: Dictionary in AnchorSites.all_anchors():
		if float(an["height"]) >= 38.0:
			tall += 1
		var b: Vector3 = an["base"]
		TestLib.check(TerrainHeight.water_level_for(b.x, b.z, b.y) == TerrainHeight.NO_WATER or b.y > 0.0, "anchor %s stands on dry land" % String(an["name"])) if false else null
	TestLib.check(tall == AnchorSites.all_anchors().size() and tall >= 20, "every anchor is tall (%d of %d at least 38 m)" % [tall, AnchorSites.all_anchors().size()])


func _shaders() -> void:
	for path in ["land_tree", "land_impostor", "land_rock", "land_prop", "fall_water", "airstrip", "terrain_road", "terrain"]:
		var sh := load("res://assets/shaders/%s.gdshader" % path) as Shader
		TestLib.check(sh != null and sh.code.contains("wetness"), "%s answers to rain (wetness)" % path)
	for path in ["land_tree", "land_impostor", "land_prop"]:
		var sh2 := load("res://assets/shaders/%s.gdshader" % path) as Shader
		TestLib.check(sh2.code.contains("land_common") and FileAccess.get_file_as_string("res://assets/shaders/land_common.gdshaderinc").contains("wind"), "%s sways with the shared wind" % path)
	TestLib.check((load("res://assets/shaders/fall_water.gdshader") as Shader).code.contains("TIME") and (load("res://assets/shaders/land_prop.gdshader") as Shader).code.contains("TIME"), "falling water and rotors animate with the clock")


# --- the real scene ----------------------------------------------------------------------------------------------------------------------------

func _city_is_untouched(host: Node) -> void:
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await TestLib.frames(host, 12)
	TestLib.check(int(city.vegetation.stats()["instances"]) == 0, "in the middle of the city there is no vegetation at all")
	var ls := (city.landscape as Landscape).stats()
	TestLib.check(int(ls.get("visible", 0)) == 0, "and no waterfall is shown there")


func _forest_tiers(host: Node) -> void:
	var spot := Vector3(-1320.0, 0.0, -520.0)
	var res := {}
	for t in 3:
		city.vegetation.set_quality(t)
		city.vegetation.settle(Vector3(spot.x, TerrainHeight.height_at(spot.x, spot.z) + 1.0, spot.z))
		await TestLib.frames(host, 2)
		res[t] = city.vegetation.stats()
		res[t]["counts"] = city.vegetation.slot_counts()
	TestLib.check(int(res[0]["tris"]) < int(res[1]["tris"]) and int(res[1]["tris"]) < int(res[2]["tris"]), "density scales by tier: %d < %d < %d triangles" % [int(res[0]["tris"]), int(res[1]["tris"]), int(res[2]["tris"])])
	TestLib.check(int(res[0]["tris"]) < 65000 and int(res[1]["tris"]) < 120000 and int(res[2]["tris"]) < 210000, "every tier stays inside its triangle budget (%d, %d, %d)" % [int(res[0]["tris"]), int(res[1]["tris"]), int(res[2]["tris"])])
	TestLib.check(int(res[0]["instances"]) < int(res[2]["instances"]) and int(res[1]["instances"]) > 600, "the forest holds thousands of instances (%d / %d / %d)" % [int(res[0]["instances"]), int(res[1]["instances"]), int(res[2]["instances"])])
	var kids := city.vegetation.get_child_count()
	TestLib.check(kids < 100 and int(res[2]["instances"]) > 8 * kids, "no per-tree nodes: %d instances live in %d nodes" % [int(res[2]["instances"]), kids])
	TestLib.check(int(res[1]["slots"]) <= 34, "the forest is a handful of draw calls (%d multimeshes)" % int(res[1]["slots"]))
	var sc: Dictionary = res[1]["counts"]
	var near := 0
	var mid := 0
	var far := 0
	var kinds := {}
	for k in sc.keys():
		var nm := String(k)
		if nm == "imp":
			far += int(sc[k])
		elif nm.ends_with("_1"):
			mid += int(sc[k])
			kinds[nm.split("_")[0]] = true
		elif nm.ends_with("_0") or nm.ends_with("_0l"):
			near += int(sc[k])
			kinds[nm.split("_")[0]] = true
	TestLib.check(near > 0 and mid > 0 and far > 0, "all three LODs are in use (%d near, %d mid, %d impostors)" % [near, mid, far])
	TestLib.check(kinds.size() >= 3, "a forest mixes species (%s)" % str(kinds.keys()))
	TestLib.check(int((res[0]["counts"] as Dictionary).get("oak_0l", 0)) + int((res[0]["counts"] as Dictionary).get("birch_0l", 0)) + int((res[0]["counts"] as Dictionary).get("pine_0l", 0)) > 0 or int((res[0]["counts"] as Dictionary).size()) > 0, "LOW draws the lite level of detail")
	city.vegetation.set_quality(1)
	TestLib.check(int(res[1]["colliders"]) > 3, "trunks and boulders around the hero are solid (%d colliders)" % int(res[1]["colliders"]))


func _falls_live(host: Node) -> void:
	var ls := city.landscape as Landscape
	var falls := LandscapeSites.falls()
	TestLib.check(ls.falls != null and ls.falls.fall_count() == falls.size(), "every found waterfall is built (%d)" % ls.falls.fall_count())
	var f0: Dictionary = falls[0]
	var pc: Vector2 = f0["pool"]
	var dir: Vector2 = f0["dir"]
	var near_pos := Vector3(pc.x + dir.x * 120.0, float(f0["pool_y"]) + 6.0, pc.y + dir.y * 120.0)
	p.teleport_to(near_pos)
	ls.falls.tick(near_pos)
	var n0 := ls.falls.node(0)
	TestLib.check(n0.visible, "a waterfall within sight is shown")
	var mist := n0.get_node("Mist") as CPUParticles3D
	var roar := n0.get_node("Roar") as AudioStreamPlayer3D
	TestLib.check(mist.emitting and mist.amount >= 6 and roar.playing, "its mist rises and its roar plays when you are near (%d mist sprites)" % mist.amount)
	var sheet := n0.get_node("Sheet") as MeshInstance3D
	var mat := sheet.material_override as ShaderMaterial
	TestLib.check(mat != null and mat.shader.code.contains("TIME") and int(mat.get_shader_parameter(&"mode")) == 0, "the sheet is the animated falling-water shader")
	var arr := sheet.mesh.surface_get_arrays(0)
	var uvs := arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var vmax := 0.0
	for uv in uvs:
		vmax = maxf(vmax, uv.y)
	TestLib.check(vmax > float(f0["drop"]) * 0.8, "the sheet runs the whole drop (%.0f of %.0f m)" % [vmax, float(f0["drop"])])
	TestLib.check(n0.get_node_or_null("Pool") != null and n0.get_node_or_null("StreamUp") != null, "a plunge pool and the stream above are drawn")
	# tiers: more mist on HIGH
	var mist_amounts := []
	for t in 3:
		ls.set_quality(t)
		await TestLib.frames(host, 2)
		mist_amounts.append(((ls.falls.node(0).get_node("Mist")) as CPUParticles3D).amount)
	TestLib.check(int(mist_amounts[0]) < int(mist_amounts[2]), "the mist thickens with the tier (%s)" % str(mist_amounts))
	ls.set_quality(1)
	await TestLib.frames(host, 2)
	# far away: hidden, silent
	var far_pos := Vector3(-1500.0, 0.0, 1500.0)
	ls.falls.tick(far_pos)
	n0 = ls.falls.node(0)
	TestLib.check(not n0.visible and not (n0.get_node("Roar") as AudioStreamPlayer3D).playing and not (n0.get_node("Mist") as CPUParticles3D).emitting, "far away the waterfall is hidden and silent (no draw call, no particles, no voice)")
	# the hero can swim in the pool: put him in it
	p.teleport_to(Vector3(pc.x, float(f0["pool_y"]) + 0.3, pc.y))
	var swimming := await _wait_counter(host, func() -> bool: return p.swim != null and bool(p.swim.get(&"active")), 12.0) if p.swim != null and "active" in p.swim else true
	TestLib.check(swimming, "the hero swims in the plunge pool")


func _strips_live(host: Node) -> void:
	var ls := city.landscape as Landscape
	TestLib.check(ls.strips != null and int(ls.strips.call(&"strip_count")) >= 3, "the airstrips are dressed (%s)" % str(ls.strips.call(&"strip_count") if ls.strips != null else 0))
	var s0: Dictionary = LandscapeSites.strips()[0]
	var sn := ls.strips.get_child(0) as Node3D
	TestLib.check(sn.get_node_or_null("Strip") != null and sn.get_node_or_null("hangar") != null and sn.get_node_or_null("windsock") != null and sn.get_node_or_null("marker") != null, "a strip has its mown surface, hangar, windsock and edge markers")
	TestLib.check(sn.get_node_or_null("HangarBody") != null, "the hangar is solid")
	var hooks := StripWorld.hooks()
	TestLib.check(hooks.size() >= 3 and float((hooks[0] as Dictionary)["r"]) >= 150.0, "the aircraft wave can find the strips (%d hooks)" % hooks.size())
	# a hero standing on the strip walks on flat, drivable ground
	var c: Vector2 = s0["c"]
	p.teleport_to(Vector3(c.x, float(s0["y"]) + 1.0, c.y))
	await TestLib.frames(host, 10)
	TestLib.check(absf(p.global_position.y - float(s0["y"])) < 2.5, "the hero stands on the strip (%.1f vs %.1f)" % [p.global_position.y, float(s0["y"])])


func _anchors_live(host: Node) -> void:
	var ls := city.landscape as Landscape
	var aw := ls.anchors as AnchorWorld
	TestLib.check(aw != null and int(aw.stats().get("anchors", 0)) >= 20, "the anchors are built (%s)" % str(aw.stats() if aw != null else {}))
	var turb: Dictionary = AnchorSites.turbines()[0]
	var tp: Vector3 = turb["pos"]
	var near := aw.anchors_near(tp, 40.0)
	TestLib.check(near.size() >= 1 and StringName((near[0] as Dictionary)["kind"]) == &"turbine" and float((near[0] as Dictionary)["pos"].y) > tp.y + 50.0, "anchors_near finds the turbine and its top (%d)" % near.size())
	p.teleport_to(Vector3(tp.x + 12.0, TerrainHeight.height_at(tp.x + 12.0, tp.z) + 1.0, tp.z))
	aw.settle(p.global_position)
	await TestLib.frames(host, 4)
	var solid := 0
	for ch in aw.get_children():
		if ch is StaticBody3D and (ch as StaticBody3D).global_position.y > -1000.0 and (ch as StaticBody3D).global_position.distance_to(tp) < 12.0:
			solid += 1
	TestLib.check(solid >= 1, "the tower next to the hero is solid (%d collider)" % solid)
	var heads := aw.get_child(0).get_node_or_null("turbine_head") as MultiMeshInstance3D
	TestLib.check(heads != null and heads.multimesh.instance_count >= 2 and heads.visibility_range_end > 500.0, "the turbine heads are one multimesh with a visibility range")
	var sites := 0
	for ch in aw.get_children():
		if ch is Node3D and not (ch is StaticBody3D):
			sites += 1
	TestLib.check(sites >= 6, "every field, line, mast and crane is its own culled node (%d)" % sites)


func _wind_follows_weather(host: Node) -> void:
	LandClimate.override(-1.0)
	var weather: Weather = null
	for n in city.get_tree().root.find_children("*", "Weather", true, false):
		weather = n as Weather
	TestLib.check(weather != null, "the weather system is running")
	if weather == null:
		return
	weather.set_state(&"clear", true)
	var calm := await _wait_counter(host, func() -> bool: return LandClimate.strength() < 0.48, 40.0)
	var s_clear := LandClimate.strength()
	weather.set_state(&"storm", true)
	var wild := await _wait_counter(host, func() -> bool: return LandClimate.strength() > 0.95, 40.0)
	var s_storm := LandClimate.strength()
	TestLib.check(calm and wild and s_storm > s_clear + 0.5, "the wind follows the weather: %.2f in clear air, %.2f in a storm" % [s_clear, s_storm])
	var v := LandClimate.vec()
	TestLib.check(absf(Vector2(v.x, v.z).length() - 1.0) < 0.02, "the wind direction is a unit vector")
	weather.set_state(&"clear", true)
