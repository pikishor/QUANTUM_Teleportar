extends RefCounted
## Wave 112 critic (PLAY lens), the regressions of the defects that the audits found, in the REAL scene (main.tscn):
##   1  every QUANTUM PAD can be stood on and travelled to: a teleport to it leaves the hero on the ground, on the pad (the HARBOUR QUAY pad stood inside a 70 x 30 m shed: the hero dropped through the floor of the
##      world and was sent back to the city after 2.5 s), and a pad is clear of every solid body (a capsule at the pad overlaps nothing)
##   2  a teleport into the outskirts builds the ground under the hero and his near neighbours, not the whole ring of terrain chunks (every fast travel froze the game for 0.8 - 1.2 s on a desktop)
##   3  two roads that run on each other never carry two bridge decks at different heights (the SUMMIT ROAD began on the PASS ROAD bridge with a second deck 0.3 - 0.75 m off it: a car was stuck at once)
##   4  no solid body stands in the lanes of the stretches that had one: the viaduct piers over the PASS ROAD and the RING ROAD, the bridge junction of the SUMMIT ROAD, a poplar in the DESERT ROAD
## Waits on state and counters, not on frame counts; user:// state is reset first. Run: tools/test.sh tests/test_play_critic_w112.gd (about 60 s)

const TIMEOUT_SECONDS := 140
const RCA := preload("res://tests/road_clearance_audit.gd")

var host: Node
var main: Node
var p: Player
var city: City


func _reset() -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	_reset()
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	city = Game.world as City
	TestLib.check(p != null and city != null and city.terrain != null, "the real scene has a hero and the terrain world")
	if p == null or city == null or city.terrain == null:
		return
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await _pads()
	await _teleport_builds_little()
	_bridges()
	await _stretches()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	_reset()


func _settle(pos: Vector3) -> void:
	city.terrain.settle(pos)
	if city.vegetation != null:
		city.vegetation.settle(pos)
	if city.sites != null and city.sites.has_method(&"settle"):
		city.sites.call(&"settle", pos)
	if city.towns != null and city.towns.has_method(&"settle"):
		city.towns.call(&"settle", pos)
	var ls = city.get_node_or_null("Landscape")
	if ls != null and ls.has_method(&"settle"):
		ls.call(&"settle", pos)


## Real seconds of frames (a slow machine cannot make a frame count fail).
func _hold(secs: float) -> void:
	var t := 0.0
	var last := Time.get_ticks_usec()
	while t < secs:
		await host.get_tree().process_frame
		var now := Time.get_ticks_usec()
		t += minf(float(now - last) / 1.0e6, 0.1)
		last = now
		p.hp = p.max_hp


# --- 1 pads -----------------------------------------------------------------------------------------------------------------------

func _pads() -> void:
	var pads := RoamData.pads()
	TestLib.check(pads.size() >= 16, "the world has its quantum pads (%d)" % pads.size())
	var bad_clear: Array[String] = []
	var bad_land: Array[String] = []
	var bad_stay: Array[String] = []
	for pad: Dictionary in pads:
		var pp: Vector3 = pad["pos"]
		p.teleport_to(pp + Vector3(0.0, 1.0, 0.0))
		await _hold(0.4)
		# a capsule the size of the hero at the pad overlaps no solid body
		var shape := CapsuleShape3D.new()
		shape.radius = 0.4
		shape.height = 1.7
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.collision_mask = 1
		q.transform = Transform3D(Basis.IDENTITY, Vector3(pp.x, pp.y + 1.0, pp.z))
		var hits := p.get_world_3d().direct_space_state.intersect_shape(q, 8)
		var names: Array[String] = []
		for hit in hits:
			var col := hit["collider"] as Node
			if col != null and not str(col.name).begins_with("Collider_"):          # the terrain collider is the ground itself
				names.append("%s/%s" % [str(col.get_parent().name), str(col.name)])
		if not names.is_empty():
			bad_clear.append("%s: inside %s" % [pad["id"], str(names)])
		# lands and stays: on the floor within 1.5 s, never more than half a metre under the ground, still within ON_R of the pad
		var t := 0.0
		var landed := false
		var worst_under := 0.0
		var last := Time.get_ticks_usec()
		while t < 1.5:
			await host.get_tree().process_frame
			var now := Time.get_ticks_usec()
			t += minf(float(now - last) / 1.0e6, 0.1)
			last = now
			p.hp = p.max_hp
			landed = landed or p.is_on_floor()
			worst_under = minf(worst_under, p.global_position.y - TerrainHeight.height_at(p.global_position.x, p.global_position.z))
		if not landed:
			bad_land.append(String(pad["id"]))
		if worst_under < -0.5:
			bad_stay.append("%s (%.1f m under the ground)" % [pad["id"], worst_under])
		var off := Vector2(p.global_position.x - pp.x, p.global_position.z - pp.z).length()
		if off > RoamTravel.ON_R:
			bad_stay.append("%s (%.1f m off the pad)" % [pad["id"], off])
	TestLib.check(bad_clear.is_empty(), "no pad stands inside a building, rock or tree (%s)" % str(bad_clear))
	TestLib.check(bad_land.is_empty(), "a teleport to every pad lands the hero on the ground (%s)" % str(bad_land))
	TestLib.check(bad_stay.is_empty(), "and he stays on the pad, over the ground (%s)" % str(bad_stay))
	var harbour := RoamData.pad(&"harbour")
	var hp: Vector3 = harbour["pos"]
	TestLib.check(not (hp.x > -335.0 and hp.x < -265.0 and hp.z > 1347.0 and hp.z < 1377.0), "the harbour pad is not where the shed stands (%.0f, %.0f)" % [hp.x, hp.z])
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await _hold(0.3)


# --- 2 the cost of a teleport -------------------------------------------------------------------------------------------------------

func _teleport_builds_little() -> void:
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await _hold(0.3)
	var worst := 0
	var places: Array[Vector3] = [Vector3(1573.0, 0.0, 1200.0), Vector3(-2851.0, 0.0, -451.0), Vector3(-567.0, 0.0, -2240.0), Vector3(2000.0, 0.0, -3000.0)]
	for pl in places:
		pl.y = TerrainHeight.height_at(pl.x, pl.z) + 1.0
		var before := int(city.terrain.stats()["built_total"])
		p.teleport_to(pl)
		var built := int(city.terrain.stats()["built_total"]) - before
		worst = maxi(worst, built)
		TestLib.check(city.terrain.is_ground_ready(pl.x, pl.z), "the ground under (%.0f, %.0f) is there at once (%d chunks built by the teleport)" % [pl.x, pl.z, built])
		await _hold(0.5)
	TestLib.check(worst <= 9, "a teleport builds the hero's chunk and its near neighbours only, never the whole ring (%d chunks at most; the ring was 25 to 81)" % worst)
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await _hold(0.3)


# --- 3 bridges ------------------------------------------------------------------------------------------------------------------------

func _bridges() -> void:
	Bridges.ensure()
	var stepped: Array[String] = []
	for ai in Bridges.list.size():
		var a: Dictionary = Bridges.list[ai]
		if a["kind"] == &"rail" or a["kind"] == &"suspension":
			continue
		for bi in range(ai + 1, Bridges.list.size()):
			var b: Dictionary = Bridges.list[bi]
			if b["kind"] == &"rail" or b["kind"] == &"suspension" or String(a["road"]) == String(b["road"]):
				continue
			var pa: PackedVector3Array = a["pts"]
			var pb: PackedVector3Array = b["pts"]
			for i in pa.size():
				for j in range(pb.size() - 1):
					var v0 := Vector2(pb[j].x, pb[j].z)
					var v1 := Vector2(pb[j + 1].x, pb[j + 1].z)
					var c := Geometry2D.get_closest_point_to_segment(Vector2(pa[i].x, pa[i].z), v0, v1)
					var lat := c.distance_to(Vector2(pa[i].x, pa[i].z))
					if lat < (float(a["w"]) + float(b["w"])) * 0.5:
						var f := 0.0 if v0.is_equal_approx(v1) else clampf(v0.distance_to(c) / maxf(v0.distance_to(v1), 0.001), 0.0, 1.0)
						var yb := lerpf(pb[j].y, pb[j + 1].y, f)
						var dy := absf(pa[i].y - yb)
						if dy > 0.2 and dy < 4.5:
							stepped.append("%s x %s at (%.0f, %.0f): %.2f m" % [a["id"], b["id"], pa[i].x, pa[i].z, dy])
	TestLib.check(stepped.is_empty(), "no two road bridges overlap at different heights (%s)" % str(stepped.slice(0, 4)))
	var summit_first := ""
	for b: Dictionary in Bridges.list:
		if String(b["road"]) == "SUMMIT ROAD":
			summit_first = String(b["id"])
			var pts: PackedVector3Array = b["pts"]
			var pass_end := Vector2.ZERO
			for r: Dictionary in TerrainRoads.roads():
				if String(r["name"]) == "PASS ROAD":
					pass_end = (r["pos"] as PackedVector2Array)[(r["pos"] as PackedVector2Array).size() - 1]
			TestLib.check(Vector2(pts[0].x, pts[0].z).distance_to(pass_end) > 60.0, "the SUMMIT ROAD's first bridge is far from the PASS ROAD's end, not on its deck (%s)" % summit_first)
			break


# --- 4 stretches that had a body in the lane ---------------------------------------------------------------------------------------

func _stretches() -> void:
	var space := p.get_world_3d().direct_space_state
	var jobs: Array = [["PASS ROAD", 480.0, 620.0], ["PASS ROAD", 1120.0, 1219.0], ["SUMMIT ROAD", 0.0, 160.0], ["DESERT ROAD", 1440.0, 1540.0], ["RING ROAD", 2900.0, 3080.0]]
	var blocked: Array[String] = []
	var samples := 0
	for job: Array in jobs:
		var ri := -1
		var roads := TerrainRoads.roads()
		for i in roads.size():
			if String(roads[i]["name"]) == String(job[0]):
				ri = i
		if ri < 0:
			TestLib.check(false, "road %s exists" % job[0])
			continue
		var road: Dictionary = roads[ri]
		var pos: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var half_w := float(road["w"]) * 0.5
		var s0 := float(job[1])
		var s1 := minf(float(job[2]), float(road["len"]) - 1.0)
		var mid := clampi(int(((s0 + s1) * 0.5) / TerrainRoads.STEP), 0, pos.size() - 2)
		var hp3 := Vector3(pos[mid].x, prof[mid] + 1.0, pos[mid].y)
		p.global_position = hp3
		_settle(hp3)
		p.teleport_to(hp3)
		await host.get_tree().physics_frame
		await host.get_tree().physics_frame
		var t := s0
		while t < s1:
			var ti := clampi(int(t / TerrainRoads.STEP), 0, pos.size() - 2)
			var a := pos[ti]
			var b := pos[ti + 1]
			var f := (t - float(ti) * TerrainRoads.STEP) / TerrainRoads.STEP
			var dir := (b - a).normalized()
			var py := lerpf(prof[ti], prof[ti + 1], f)
			var grade := (prof[ti + 1] - prof[ti]) / TerrainRoads.STEP
			for lane: float in [-2.4, 0.0, 2.4]:
				if absf(lane) > half_w - 0.8:
					continue
				samples += 1
				for fam in RCA.blockers(space, a.lerp(b, f), dir, py, grade, lane):
					if not fam.begins_with("Terrain/"):                  # the terrain mesh against the profile on a crest is a separate, small item (the audit lists it)
						blocked.append("%s s=%d lane %.1f: %s" % [job[0], int(t), lane, fam])
			t += 6.0
	TestLib.check(samples > 60, "the stretches were sampled (%d car boxes)" % samples)
	TestLib.check(blocked.is_empty(), "no pier, deck, rail body or tree stands in the lanes of the stretches that had one (%s)" % str(blocked.slice(0, 5)))
	p.teleport_to(Vector3(0.0, 0.5, 4.0))
	await _hold(0.3)
