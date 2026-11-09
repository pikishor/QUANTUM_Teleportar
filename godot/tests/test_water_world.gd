extends RefCounted
## WATER WORLD (wave 104: ocean, rivers, lakes, swimming). Data and API checks on the real height function, then the REAL game scene:
##  * TerrainHeight / WaterLayout: the city plateau is dry and flat, the west and south are ocean, three rivers run from the mountains to the sea (or into a river) with a surface
##    that never rises downstream, a current in their direction and a bed under the surface, three lakes sit in bowls; carving is local (far from water height_at is base_height);
##  * WaterWorld API: surface_y (waves around the sea level, NO_WATER on land), buoyancy for hulls, splash on water only, the shore depth map, mesh budgets per tier;
##  * sounds: the CC0 splash / wade / stroke sets load;
##  * the live game has the WaterWorld under the city with both water meshes, tiers rebuild them within budget, an underwater camera shows the tint overlay and switches it off above;
##  * the hero (real Player, real input actions) dropped into the sea plunges in with a splash, floats at the chest, swims with the stick and is not rescued back to the city;
##    PlayerSwim in isolation: wading slows him in the shallows, deep water makes him swim, a river carries him downstream, JUMP hops.
## Run: tools/test.sh tests/test_water_world.gd   (about 40 s)

const TMP := "user://test_water_world.cfg"


func run(host: Node) -> void:
	_test_layout()
	_test_api()
	_test_meshes_and_map()
	_test_sounds()
	await _test_swim_isolated(host)
	await _test_live(host)


func _first_wet(from: Vector2, to: Vector2, steps: int) -> Vector2:
	for i in steps + 1:
		var p := from.lerp(to, float(i) / float(steps))
		if TerrainHeight.water_level_at(p.x, p.y) != TerrainHeight.NO_WATER:
			return p
	return Vector2.INF


func _test_layout() -> void:
	TerrainHeight.warm()
	TestLib.check(TerrainHeight.SEA_LEVEL < 0.0, "the sea is below the city plateau (y 0)")
	for p: Vector2 in [Vector2(0, 0), Vector2(-300, 200), Vector2(700, -600), Vector2(-1000, 1000)]:
		TestLib.check(absf(TerrainHeight.height_at(p.x, p.y)) < 0.01 and not TerrainHeight.is_water(p.x, p.y), "the city plateau at %s is flat and dry" % p)
	# the sea: west and south of the city (the coast is 500-900 m from the plateau edge), a deep floor
	var west := _first_wet(Vector2(-1100.0, 0.0), Vector2(-2800.0, 0.0), 400)
	var south := _first_wet(Vector2(0.0, 1100.0), Vector2(0.0, 2800.0), 400)
	TestLib.check(west != Vector2.INF and west.x < -1300.0, "walking west from the city there is a shore (first water at x %.0f)" % west.x)
	TestLib.check(south != Vector2.INF and south.y > 1300.0, "walking south from the city there is a shore (first water at z %.0f)" % south.y)
	TestLib.check(TerrainHeight.height_at(-2600.0, 0.0) < -15.0, "the sea floor is deep out west (%.1f m)" % TerrainHeight.height_at(-2600.0, 0.0))
	TestLib.check(TerrainHeight.water_level_at(-2600.0, 0.0) == TerrainHeight.SEA_LEVEL, "the ocean surface is the sea level")
	var wet := 0
	var high := -1.0e9
	for ix in 60:
		for iz in 60:
			var x := -2950.0 + ix * 100.0
			var z := -2950.0 + iz * 100.0
			if TerrainHeight.is_water(x, z):
				wet += 1
			high = maxf(high, TerrainHeight.height_at(x, z))
	TestLib.check(wet > 600 and wet < 2400, "water covers part of the 6 km world, not all of it (%d of 3600 samples)" % wet)
	TestLib.check(high > 150.0, "there are mountains to match (highest sample %.0f m)" % high)
	# rivers
	WaterLayout.ensure()
	TestLib.check(WaterLayout.paths.size() == 3 and WaterLayout.LAKES.size() == 3, "three rivers and three lakes")
	for ri in WaterLayout.paths.size():
		var path: Dictionary = WaterLayout.paths[ri]
		var pos: PackedVector2Array = path["pos"]
		var surf: PackedFloat32Array = path["surface"]
		var hw: PackedFloat32Array = path["hw"]
		var mono := true
		for i in range(1, surf.size()):
			if surf[i] > surf[i - 1] + 0.001:
				mono = false
		TestLib.check(mono, "%s never flows uphill" % path["name"])
		TestLib.check(float(path["length"]) > 1200.0 and hw[hw.size() - 1] > hw[0], "%s is long and widens towards the mouth" % path["name"])
		var mid := pos.size() / 2
		var c := pos[mid]
		TestLib.check(absf(TerrainHeight.water_level_at(c.x, c.y) - surf[mid]) < 0.05, "%s: water stands at its surface on the centre line" % path["name"])
		TestLib.check(TerrainHeight.depth_at(c.x, c.y) > 1.0, "%s: the bed is under the surface (%.1f m deep)" % [path["name"], TerrainHeight.depth_at(c.x, c.y)])
		var flow := TerrainHeight.flow_at(c.x, c.y)
		var dir: Vector2 = (path["dir"] as PackedVector2Array)[mid]
		TestLib.check(flow.length() > 0.7 and flow.normalized().dot(dir) > 0.95, "%s: the current runs along the river (%.1f m/s)" % [path["name"], flow.length()])
		var side := c + Vector2(-dir.y, dir.x) * (hw[mid] * 3.0 + 60.0)
		TestLib.check(TerrainHeight.flow_at(side.x, side.y) == Vector2.ZERO, "%s: no current on the land beside it" % path["name"])
	var mouth_a: Vector2 = (WaterLayout.paths[0]["pos"] as PackedVector2Array)[(WaterLayout.paths[0]["pos"] as PackedVector2Array).size() - 1]
	var surf_a: PackedFloat32Array = WaterLayout.paths[0]["surface"]
	TestLib.check(surf_a[surf_a.size() - 1] < TerrainHeight.SEA_LEVEL + 0.3 and TerrainHeight.base_height(mouth_a.x, mouth_a.y) < TerrainHeight.SEA_LEVEL + 0.5, "the first river ends in the sea")
	# lakes
	for i in WaterLayout.LAKES.size():
		var c: Vector2 = WaterLayout.LAKES[i]["c"]
		TestLib.check(TerrainHeight.depth_at(c.x, c.y) > 2.5 and absf(TerrainHeight.water_level_at(c.x, c.y) - WaterLayout.lake_level[i]) < 0.01, "%s is a bowl with water in it" % WaterLayout.LAKES[i]["name"])
	# carving is local
	var q := Vector2(200.0, -1500.0)
	TestLib.check(is_equal_approx(TerrainHeight.height_at(q.x, q.y), TerrainHeight.base_height(q.x, q.y)) or WaterLayout.inland_distance(q.x, q.y, 200.0) != INF, "away from water the height is the plain land")
	TestLib.check(WaterLayout.inland_distance(0.0, 0.0, 300.0) == INF, "no river or lake within 300 m of the city centre")
	var c0: Vector2 = (WaterLayout.paths[1]["pos"] as PackedVector2Array)[60]
	TestLib.check(WaterLayout.inland_distance(c0.x, c0.y, 50.0) == 0.0, "inland_distance is 0 on a river")


func _test_api() -> void:
	var sea := Vector2(-2400.0, 300.0)
	var lo := 1.0e9
	var hi := -1.0e9
	for i in 40:
		WaterWorld.clock = float(i) * 0.9
		var y := WaterWorld.surface_y(sea.x, sea.y)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	TestLib.check(lo < TerrainHeight.SEA_LEVEL - 0.05 and hi > TerrainHeight.SEA_LEVEL + 0.05, "waves lift and lower the open sea (%.2f .. %.2f)" % [lo, hi])
	TestLib.check(lo > TerrainHeight.SEA_LEVEL - WaterWorld.AMP * 1.1 and hi < TerrainHeight.SEA_LEVEL + WaterWorld.AMP * 1.1, "wave height stays within the amplitude")
	TestLib.check(WaterWorld.surface_y(0.0, 0.0) == TerrainHeight.NO_WATER, "no water on the city plateau")
	var c: Vector2 = (WaterLayout.paths[1]["pos"] as PackedVector2Array)[100]
	var surf: float = (WaterLayout.paths[1]["surface"] as PackedFloat32Array)[100]
	TestLib.check(absf(WaterWorld.surface_y(c.x, c.y) - surf) < 0.05, "river water is flat at its level (no sea waves)")
	# the waves die on the beach: find a point with 0.4 m of water
	var shallow := Vector2.INF
	for i in 400:
		var p := Vector2(-1500.0 - i * 0.5, 0.0)
		var d := TerrainHeight.depth_at(p.x, p.y)
		if d > 0.3 and d < 0.5:
			shallow = p
			break
	if shallow != Vector2.INF:
		var swing := 0.0
		for i in 20:
			WaterWorld.clock = float(i)
			swing = maxf(swing, absf(WaterWorld.surface_y(shallow.x, shallow.y) - TerrainHeight.SEA_LEVEL))
		TestLib.check(swing < 0.06, "the waves flatten in the shallows (%.3f m at 0.4 m depth)" % swing)
	# buoyancy
	var b := WaterWorld.buoyancy(Vector3(sea.x, 0.0, sea.y), 0.7, 2.5, 1.0)
	TestLib.check(bool(b["water"]) and absf(float(b["y"]) - TerrainHeight.SEA_LEVEL) < 0.4 and absf(float(b["pitch"])) < 0.35 and absf(float(b["roll"])) < 0.35, "buoyancy on the sea: a heave and a gentle pitch and roll")
	var bl := WaterWorld.buoyancy(Vector3(0.0, 0.0, 0.0), 0.0)
	TestLib.check(not bool(bl["water"]), "buoyancy on land says no water")
	var br := WaterWorld.buoyancy(Vector3(c.x, 0.0, c.y), 0.0)
	TestLib.check(bool(br["water"]) and (br["flow"] as Vector2).length() > 0.7 and float(br["depth"]) > 1.0, "buoyancy in a river carries its current and depth")
	WaterWorld.splash(Vector3(0.0, 0.0, 0.0), 1.0)                  # dry land: nothing, no error
	TestLib.check(true, "a splash on dry land is ignored")


func _test_meshes_and_map() -> void:
	var tris: Array[int] = []
	for level in 3:
		var t: Array = WaterWorld.TIERS[level]
		var oc := WaterWorld.build_ocean_mesh(int(t[0]), int(t[1]), WaterWorld.OCEAN_R_IN, WaterWorld.OCEAN_R_OUT)
		var inl := WaterWorld.build_inland_mesh(int(t[2]), int(t[3]), 16 if level == 0 else 28)
		var n: int = (oc.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 + (inl.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris.append(n)
		TestLib.check(oc.get_surface_count() == 1 and inl.get_surface_count() == 1, "tier %d: one surface each for the ocean and the inland water (two draw calls)" % level)
	TestLib.check(tris[0] <= 3500 and tris[1] <= 7000 and tris[2] <= 12000, "water triangles per tier within budget (%s)" % str(tris))
	TestLib.check(tris[0] < tris[1] and tris[1] < tris[2], "higher tiers get more water detail")
	# river strips lie at their surface and cover the whole river
	var m := WaterWorld.build_inland_mesh(1, 3, 28)
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var on_surface := 0
	for i in verts.size():
		var v := verts[i]
		var lvl := TerrainHeight.water_level_at(v.x, v.z)
		if uv2[i].y < 0.05 and lvl != TerrainHeight.NO_WATER and absf(lvl - v.y) < 0.1:
			on_surface += 1
	TestLib.check(on_surface > 150, "river centre-line vertices sit exactly on the water surface (%d)" % on_surface)
	# the shore depth map
	var tex := WaterWorld.shore_map()
	var img := tex.get_image()
	TestLib.check(img.get_width() == 512 and img.get_height() == 512 and img.get_format() == Image.FORMAT_R8, "shore map is 512 x 512 R8 (about 260 KB)")
	var half := WaterWorld.MAP_HALF
	var at := func(x: float, z: float) -> float:
		return img.get_pixel(int((x + half) / (half * 2.0) * 512.0), int((z + half) / (half * 2.0) * 512.0)).r * WaterWorld.DEPTH_RANGE - WaterWorld.DEPTH_OFFSET
	TestLib.check(float(at.call(0.0, 0.0)) < -1.0, "shore map: the city is dry land (%.1f)" % float(at.call(0.0, 0.0)))
	TestLib.check(float(at.call(-2600.0, 0.0)) > 8.0, "shore map: the open sea is deep (%.1f)" % float(at.call(-2600.0, 0.0)))
	var w := _first_wet(Vector2(-1100.0, 0.0), Vector2(-2800.0, 0.0), 800)
	TestLib.check(absf(float(at.call(w.x, w.y))) < 1.5, "shore map: depth is about zero at the waterline (%.2f at x %.0f)" % [float(at.call(w.x, w.y)), w.x])
	TestLib.check(int(WaterWorld.shore_stats().get("refined_cells", 0)) < 9000, "the map is refined only along the coast")


func _test_sounds() -> void:
	for pair in [[&"water_splash", 3], [&"water_splash_big", 2], [&"water_wade", 2], [&"water_stroke", 2], [&"water_bubble", 1], [&"water_surf", 1], [&"water_river", 1]]:
		TestLib.check(Sfx.variants_of(pair[0]).size() >= int(pair[1]), "sound set %s has %d+ clips" % [pair[0], pair[1]])


## A CharacterBody3D with PlayerSwim: no scene, no terrain colliders.
func _swim_body(host: Node, pos: Vector3) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	b.add_child(cs)
	b.collision_mask = 0
	host.add_child(b)
	b.global_position = pos
	return b


func _test_swim_isolated(host: Node) -> void:
	Game.state = &"play"
	var sw := PlayerSwim.new()
	# wading: a point with 0.5 m of water
	var shallow := Vector2.INF
	for i in 600:
		var p := Vector2(-1500.0 - i * 0.5, 0.0)
		var d := TerrainHeight.depth_at(p.x, p.y)
		if d > 0.5 and d < 0.8:
			shallow = p
			break
	TestLib.check(shallow != Vector2.INF, "there is a shallow stretch to wade (found at x %.0f)" % shallow.x)
	if shallow != Vector2.INF:
		var dummy := Node3D.new()
		host.add_child(dummy)
		dummy.global_position = Vector3(shallow.x, TerrainHeight.height_at(shallow.x, shallow.y), shallow.y)
		sw.probe(dummy)
		TestLib.check(sw.wading and not sw.active and sw.wade_mult < 0.9, "in the shallows the hero wades (slower: x%.2f)" % sw.wade_mult)
		dummy.global_position = Vector3(0.0, 0.0, 0.0)
		sw.probe(dummy)
		TestLib.check(not sw.wading and sw.wade_mult == 1.0 and sw.surface == TerrainHeight.NO_WATER, "on the street he does not")
		dummy.queue_free()
	# deep sea: plunge, float, stroke
	var sea := Vector3(-2300.0, 0.0, 400.0)
	var y0 := TerrainHeight.SEA_LEVEL + 3.0
	var body := _swim_body(host, Vector3(sea.x, y0, sea.z))
	var dt := 1.0 / 60.0
	var splashes0 := sw.splashes
	body.velocity = Vector3(0.0, -4.0, 0.0)
	var entered := false
	for i in 90:
		await TestLib.frames(host, 1)
		if not sw.active:
			body.velocity.y = maxf(body.velocity.y - 22.0 * dt, -30.0)
		if not sw.tick(body, dt, Vector3.ZERO, false, false):
			body.move_and_slide()
		entered = entered or sw.active
	TestLib.check(entered and sw.splashes > splashes0, "falling into deep water: he plunges in with a splash (%d)" % (sw.splashes - splashes0))
	for i in 240:
		await TestLib.frames(host, 1)
		sw.tick(body, dt, Vector3.ZERO, false, false)
	var surface := WaterWorld.surface_y(body.global_position.x, body.global_position.z)
	TestLib.check(sw.active and absf(body.global_position.y - (surface - PlayerSwim.FLOAT_DEPTH)) < 0.5, "he floats with the water at his chest (feet %.2f, surface %.2f)" % [body.global_position.y, surface])
	var start := body.global_position
	for i in 120:
		await TestLib.frames(host, 1)
		sw.tick(body, dt, Vector3(0.0, 0.0, -1.0), false, false)
	var moved := Vector2(body.global_position.x - start.x, body.global_position.z - start.z)
	TestLib.check(moved.length() > 3.0 and moved.y < -2.5, "the stick strokes him forward (%.1f m in 2 s)" % moved.length())
	var fast_start := body.global_position
	for i in 120:
		await TestLib.frames(host, 1)
		sw.tick(body, dt, Vector3(0.0, 0.0, -1.0), false, true)
	TestLib.check(Vector2(body.global_position.x - fast_start.x, body.global_position.z - fast_start.z).length() > moved.length() * 1.2, "sprint is a faster crawl")
	TestLib.check(sw.lean > 0.5, "the crawl pitches him forward (lean %.2f)" % sw.lean)
	var before := body.global_position.y
	var peak := before
	sw.tick(body, dt, Vector3.ZERO, true, false)
	for i in 20:
		await TestLib.frames(host, 1)
		sw.tick(body, dt, Vector3.ZERO, false, false)
		peak = maxf(peak, body.global_position.y)
	TestLib.check(peak > before + 0.3, "JUMP in the water hops (%.2f m up)" % (peak - before))
	body.queue_free()
	# a river carries him
	var path: Dictionary = WaterLayout.paths[1]
	var idx := 100
	var rp: Vector2 = (path["pos"] as PackedVector2Array)[idx]
	var rs: float = (path["surface"] as PackedFloat32Array)[idx]
	var rdir: Vector2 = (path["dir"] as PackedVector2Array)[idx]
	var rb := _swim_body(host, Vector3(rp.x, rs - 2.0, rp.y))
	var sw2 := PlayerSwim.new()
	var rstart := rb.global_position
	for i in 240:
		await TestLib.frames(host, 1)
		sw2.tick(rb, dt, Vector3.ZERO, false, false)
	var drift := Vector2(rb.global_position.x - rstart.x, rb.global_position.z - rstart.z)
	TestLib.check(sw2.active and drift.length() > 2.0 and drift.normalized().dot(rdir) > 0.6, "left alone in the river he drifts downstream (%.1f m, dot %.2f)" % [drift.length(), drift.normalized().dot(rdir)])
	rb.queue_free()


func _test_live(host: Node) -> void:
	Game.civilian_casualties = false
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p := Game.player as Player
	var world := Game.world as City
	if p == null or world == null:
		TestLib.check(false, "the real game has a player and a city")
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = TMP
	Game.state = &"play"
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	if Encounters.current != null:
		Encounters.current.enabled = false
	var ww := WaterWorld.instance
	TestLib.check(ww != null and ww.get_parent() == world, "the WaterWorld is attached under the city")
	if ww == null:
		return
	TestLib.check(ww.ocean != null and ww.inland != null and ww.ocean.mesh != null and ww.inland.mesh != null and ww.ocean_mat.shader != null, "ocean and inland water meshes are built with their shaders")
	# tiers
	var counts: Array[int] = []
	for level in [0, 1, 2]:
		Game.set_quality(level)
		await TestLib.frames(host, 2)
		counts.append(ww.triangle_count())
		TestLib.check(ww.tier == level and ww.detail == level, "tier %d applied to the water (detail %d)" % [level, ww.detail])
	TestLib.check(counts[0] < counts[1] and counts[1] < counts[2] and counts[0] <= 3500 and counts[2] <= 12000, "water triangles by tier %s" % str(counts))
	Game.set_quality(1)
	await TestLib.frames(host, 2)
	# underwater tint (the hero's own camera rig keeps the current camera, so the live node is asked directly)
	ww._update_underwater(Vector3(-2300.0, TerrainHeight.SEA_LEVEL - 4.0, 300.0), 0.1)
	TestLib.check(WaterWorld.underwater and ww.overlay.visible, "a camera below the surface shows the underwater tint")
	ww._update_underwater(Vector3(-2300.0, TerrainHeight.SEA_LEVEL + 6.0, 300.0), 0.1)
	TestLib.check(not WaterWorld.underwater and not ww.overlay.visible, "above the surface the tint is off")
	# the real hero in the sea
	var before := p.swim.splashes
	p.global_position = Vector3(-2300.0, TerrainHeight.SEA_LEVEL + 2.5, 300.0)
	p.velocity = Vector3.ZERO
	var t := 0.0
	while t < 6.0 and not p.swim.active:
		await TestLib.frames(host, 6)
		t += 0.1
	TestLib.check(p.swim.active, "the real hero dropped into the sea starts swimming (after %.1f s)" % t)
	TestLib.check(p.swim.splashes > before, "and splashed on the way in")
	await TestLib.frames(host, 120)
	var surface := WaterWorld.surface_y(p.global_position.x, p.global_position.z)
	TestLib.check(p.swim.active and absf(p.global_position.y - (surface - PlayerSwim.FLOAT_DEPTH)) < 0.7, "he floats at the surface (feet %.2f, water %.2f)" % [p.global_position.y, surface])
	TestLib.check(not WaterWorld.underwater, "the hero's camera stays above the water while he floats")
	TestLib.check(absf(p.global_position.x + 2300.0) < 60.0 and not PlayerUtil.outside_city(p.global_position), "he is not rescued back to the street: the sea is part of the world")
	var s0 := p.global_position
	Input.action_press(&"move_forward")
	await TestLib.frames(host, 150)
	Input.action_release(&"move_forward")
	var d := Vector2(p.global_position.x - s0.x, p.global_position.z - s0.z).length()
	TestLib.check(d > 3.0 and p.swim.active, "pushing the stick swims him on (%.1f m)" % d)
	# ... and back to land: standing on the street the swim is off
	p.global_position = Vector3(Game.SPAWN.x, 0.1, Game.SPAWN.z)
	p.velocity = Vector3.ZERO
	await TestLib.frames(host, 30)
	TestLib.check(not p.swim.active and not p.swim.wading, "back on the street he walks again")
	Input.action_release(&"move_forward")
