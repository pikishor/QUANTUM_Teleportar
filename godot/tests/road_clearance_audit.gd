extends RefCounted
## RoadClearanceAudit (wave 112 critic, PLAY lens): is anything solid standing IN a road? The hero is moved along every road of TerrainRoads (the world settles round him: terrain, vegetation, landscape, towns,
## rails, bridges), and at every 6 m sample of the stretch around him a car-sized box (2.0 x 1.4 x 4.4 m, 0.45 m above the road surface, pitched with the grade, turned along the road) is tested against every
## static body of the world layer in three lanes (left, centre, right). A blocked sample is a place a car cannot pass: a tree trunk, a rock, a rail body, a pylon, a sign, a house, a bridge rail ...
## The report lists runs of blocked samples per road with the bodies that block them (names with digits stripped).
##   tools/test.sh tests/road_clearance_audit.gd        (about 2 minutes for the whole world; env RC_ROADS="0,5" index list, RC_STEP=100 metres between stops)
## Exit 0 = nothing blocks any road. Prints ROADCLEAR lines.

const TIMEOUT_SECONDS := 140
const LANES: Array[float] = [-2.4, 0.0, 2.4]

var host: Node
var failures: Array[String] = []


func _family(n: Node) -> String:
	var s := str(n.name)
	while s.length() > 0 and (s[s.length() - 1] >= "0" and s[s.length() - 1] <= "9" or s[s.length() - 1] == "_"):
		s = s.substr(0, s.length() - 1)
	var par := n.get_parent()
	return "%s/%s" % [str(par.name).rstrip("0123456789_") if par != null else "", s]


## The families (parent/name, digits stripped) of the static bodies a car-sized box (2.0 x 1.4 x 4.4 m, 0.45 m above the road surface `py`, pitched with `grade`, turned along `dir`) overlaps at the road
## point `pt` (x, z) when it stands `lane` metres to the right of the centre line. Empty = a car passes. (Used by tests/test_play_critic_w112.gd.)
static func blockers(space: PhysicsDirectSpaceState3D, pt: Vector2, dir: Vector2, py: float, grade: float, lane: float) -> Array[String]:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.4, 4.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var side := Vector2(-dir.y, dir.x)
	var lp := pt + side * lane
	var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y)) * Basis(Vector3.RIGHT, atan(grade))
	q.transform = Transform3D(basis, Vector3(lp.x, py + 0.45 + 0.7, lp.y))
	var out: Array[String] = []
	for hit in space.intersect_shape(q, 8):
		var col := hit["collider"] as Node
		if col == null:
			continue
		var s := str(col.name)
		while s.length() > 0 and (s[s.length() - 1] >= "0" and s[s.length() - 1] <= "9" or s[s.length() - 1] == "_"):
			s = s.substr(0, s.length() - 1)
		var par := col.get_parent()
		var fam := "%s/%s" % [str(par.name).rstrip("0123456789_") if par != null else "", s]
		if not out.has(fam):
			out.append(fam)
	return out


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.quality = int(OS.get_environment("RC_QUALITY")) if OS.get_environment("RC_QUALITY") != "" else 0
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	var city := Game.world as City
	var roads := TerrainRoads.roads()
	var sel: Array[int] = []
	var env := OS.get_environment("RC_ROADS")
	if env == "":
		for i in roads.size():
			sel.append(i)
	else:
		for t in env.split(",", false):
			sel.append(int(t))
	var step := float(OS.get_environment("RC_STEP")) if OS.get_environment("RC_STEP") != "" else 120.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.4, 4.4)
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for ri in sel:
		var road: Dictionary = roads[ri]
		var pos: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var name := String(road["name"])
		var half_w := float(road["w"]) * 0.5
		var blocked_runs: Array[String] = []
		var run_start := -1
		var run_fams := {}
		var n_blocked := 0
		var n_samples := 0
		var last_blocked_s := -100.0
		var s := 0.0
		var len := float(road["len"])
		while s < len:
			var si := clampi(int(s / TerrainRoads.STEP), 0, pos.size() - 2)
			var c := pos[si]
			var cy := prof[si]
			var hp3 := Vector3(c.x, cy + 1.0, c.y)
			p.global_position = hp3
			p.velocity = Vector3.ZERO
			if city.terrain != null:
				city.terrain.settle(hp3)
			if city.vegetation != null:
				city.vegetation.settle(hp3)
			if city.sites != null and city.sites.has_method(&"settle"):
				city.sites.call(&"settle", hp3)
			if city.towns != null and city.towns.has_method(&"settle"):
				city.towns.call(&"settle", hp3)
			var ls = city.get_node_or_null("Landscape")
			if ls != null and ls.has_method(&"settle"):
				ls.call(&"settle", hp3)
			p.teleport_to(hp3)
			await host.get_tree().physics_frame
			await host.get_tree().physics_frame
			var s_end := minf(s + step, len)
			var t := s
			while t < s_end:
				var ti := clampi(int(t / TerrainRoads.STEP), 0, pos.size() - 2)
				var a := pos[ti]
				var b := pos[ti + 1]
				var f := (t - float(ti) * TerrainRoads.STEP) / TerrainRoads.STEP
				var pt := a.lerp(b, f)
				var dir := (b - a).normalized()
				var side := Vector2(-dir.y, dir.x)
				var py := lerpf(prof[ti], prof[ti + 1], f)
				var grade := (prof[ti + 1] - prof[ti]) / TerrainRoads.STEP
				var blocked_here := false
				var fams: Array[String] = []
				for lane in LANES:
					if absf(lane) > half_w - 0.8:
						continue
					var lp := pt + side * lane
					var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y)) * Basis(Vector3.RIGHT, atan(grade))
					q.transform = Transform3D(basis, Vector3(lp.x, py + 0.45 + 0.7, lp.y))
					var hits := space.intersect_shape(q, 8)
					for hit in hits:
						var col := hit["collider"] as Node
						if col == null:
							continue
						var fam := _family(col)
						if fam.begins_with("Terrain") and false:
							continue
						if not fams.has(fam):
							fams.append(fam)
						blocked_here = true
				n_samples += 1
				if blocked_here:
					n_blocked += 1
					if run_start < 0:
						run_start = int(t)
					last_blocked_s = t
					for fm in fams:
						run_fams[fm] = int(run_fams.get(fm, 0)) + 1
				elif run_start >= 0 and t - last_blocked_s > 12.0:
					blocked_runs.append("s %d..%d (%.0f, %.0f): %s" % [run_start, int(last_blocked_s), pt.x, pt.y, str(run_fams)])
					run_start = -1
					run_fams = {}
				t += 6.0
			s += step
		if run_start >= 0:
			blocked_runs.append("s %d..%d: %s" % [run_start, int(last_blocked_s), str(run_fams)])
		print("ROADCLEAR %-16s %4.0f m, %d samples, %d blocked, %d runs" % [name, len, n_samples, n_blocked, blocked_runs.size()])
		for r in blocked_runs:
			print("ROADCLEAR   ", r)
			failures.append("%s %s" % [name, r])
	TestLib.check(failures.is_empty(), "no solid body stands in any road (%d blocked runs)" % failures.size())
	Game.state = &"menu"
	main.queue_free()
