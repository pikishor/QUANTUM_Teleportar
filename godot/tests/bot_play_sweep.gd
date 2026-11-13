extends RefCounted
## World sweep (wave 112 critic, PLAY lens): the REAL game with the real hero, the real game camera and (with --touch) the phone HUD, at a list of stops over the whole 9 km world. At every stop the hero is put on
## the ground, the world is settled, EVERY frames pass, and the draw calls, triangles, nodes and texture memory of the frame are printed next to the screenshot of that stop. perf_report.sh only measures the staged
## city view; the owner drives out of it, so this is the number the outskirts really cost.
##   QUALITY=0 BOT_RES=844x390 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_play_sweep.gd /path/prefix 14 40      (EVERY = frames per stop, COUNT = stops)
## env: SW_STOPS  semicolon list of stops (default: every named stop of the world, in the order SweepStops.list() gives below); a stop is one of
##        "name"                    a named stop (see list(): town ids, falls f0..f5, strips s0..s6, road names with @metres, airport, observatory, ...)
##        "xz:x,z[,yaw[,dist]]"     the real hero at (x, z) looking along yaw (radians, 0 = -Z north)
##      SW_ABLATE  "pat;pat;..." at the FIRST stop only: after the baseline window every further EVERY-frame window hides the geometry whose "parent/name" contains the next pattern (cumulative; "HUD" hides the
##                 HUD layers) and prints ABLATE lines with the draws that remain: where the draws of a frame come from
##      SW_FROM / SW_TO  restrict the default list to stops [from, to) (a number each), SW_HOUR (default 12), SW_CENSUS=1 prints the biggest draw families of every stop,
##      SW_LIST=1 prints the default list and ends.
## Prints: SWEEP i name x z y tier draws prims total_draws total_prims nodes tex_mb

var _stops: Array[Dictionary] = []
var _i := 0
var _f := 0
var _wait := 14
var _hud: CanvasItem = null
var _built := false
var _ablate: PackedStringArray = PackedStringArray()


func _build_stops() -> void:
	_built = true
	if OS.get_environment("SW_ABLATE") != "":
		_ablate = OS.get_environment("SW_ABLATE").split(";", false)
	var env := OS.get_environment("SW_STOPS")
	if env != "":
		for s in env.split(";", false):
			var st := _parse(s.strip_edges())
			if not st.is_empty():
				_stops.append(st)
		return
	var all := default_list()
	var from := int(OS.get_environment("SW_FROM")) if OS.get_environment("SW_FROM") != "" else 0
	var to := int(OS.get_environment("SW_TO")) if OS.get_environment("SW_TO") != "" else all.size()
	for k in range(from, mini(to, all.size())):
		_stops.append(all[k])
	if OS.get_environment("SW_LIST") == "1":
		for k in all.size():
			print("SWEEP_LIST %d %s (%.0f, %.0f)" % [k, all[k]["name"], (all[k]["pos"] as Vector2).x, (all[k]["pos"] as Vector2).y])


func _parse(s: String) -> Dictionary:
	if s.begins_with("xz:"):
		var a := s.substr(3).split(",")
		return {"name": s, "pos": Vector2(float(a[0]), float(a[1])), "yaw": float(a[2]) if a.size() > 2 else 0.0, "dist": float(a[3]) if a.size() > 3 else -1.0}
	for st in default_list():
		if String(st["name"]) == s:
			return st
	return {}


## Along road `name` at s metres: the point and the facing along the road.
static func road_stop(name: String, s: float) -> Dictionary:
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) == name:
			var pos: PackedVector2Array = r["pos"]
			var i := clampi(int(s / TerrainRoads.STEP), 0, pos.size() - 2)
			var d := (pos[i + 1] - pos[i]).normalized()
			return {"name": "%s@%d" % [name, int(s)], "pos": pos[i], "yaw": atan2(-d.x, -d.y), "dist": -1.0}
	return {}


static func default_list() -> Array[Dictionary]:
	TerrainHeight.warm()
	var out: Array[Dictionary] = []
	out.append({"name": "city_spawn", "pos": Vector2(Game.SPAWN.x, Game.SPAWN.z), "yaw": -PI * 0.5, "dist": -1.0})
	# the highways out of the city, 120 m outside the gate and further out
	for rn: String in ["PASS ROAD", "DESERT ROAD", "COAST ROAD", "FOREST ROAD"]:
		out.append(road_stop(rn, 120.0))
		out.append(road_stop(rn, 700.0))
	for rn2: String in ["RING ROAD", "WEST HIGHWAY", "MOUNTAIN TRACK", "SUMMIT ROAD", "LARK ROAD", "SHORE TRACK", "OUTPOST ROAD", "COAST LINK", "WEST COAST ROAD", "QUARRY TRACK", "RIDGE TRACK"]:
		for r: Dictionary in TerrainRoads.roads():
			if String(r["name"]) == rn2:
				out.append(road_stop(rn2, float(r["len"]) * 0.4))
	# the seven towns: in the main street at the middle and at the end
	for d: Dictionary in SettlementDefs.DEFS:
		var st := OutskirtsSites.by_id(StringName(d["id"]))
		if st.is_empty():
			continue
		var c3: Vector3 = st["pos"]
		var c := Vector2(c3.x, c3.z)
		var yaw := float(st["yaw"]) + PI
		out.append({"name": String(d["id"]), "pos": c, "yaw": yaw, "dist": -1.0})
		out.append({"name": String(d["id"]) + "_in", "pos": c - Vector2(sin(float(st["yaw"])), cos(float(st["yaw"]))) * (float(st["len"]) * 0.75), "yaw": float(st["yaw"]) + PI, "dist": -1.0})
	# the older sites
	for id: StringName in [&"pine_hollow", &"dust_wells", &"south_farm", &"north_farm", &"lodge", &"hunters", &"observatory", &"radio_tower", &"mine", &"crash"]:
		var s2 := OutskirtsSites.by_id(id)
		if not s2.is_empty():
			var s3: Vector3 = s2["pos"]
			out.append({"name": String(id), "pos": Vector2(s3.x, s3.z), "yaw": float(s2.get("yaw", 0.0)), "dist": -1.0})
	# waterfalls: the hero 40 m from the pool, facing the face
	var falls := LandscapeSites.falls()
	for k in falls.size():
		var fw: Dictionary = falls[k]
		var pp: Vector2 = (fw["pool"] as Vector2) + (fw["dir"] as Vector2) * 40.0
		var toward: Vector2 = ((fw["base"] as Vector2) - pp).normalized()
		out.append({"name": "f%d_%s" % [k, String(fw.get("name", "fall")).replace(" ", "_")], "pos": pp, "yaw": atan2(-toward.x, -toward.y), "dist": -1.0})
	var strips := LandscapeSites.strips()
	for k in strips.size():
		var sp: Dictionary = strips[k]
		var su: Vector2 = sp["u"]
		out.append({"name": "s%d_%s" % [k, String(sp.get("name", "strip")).replace(" ", "_")], "pos": (sp["c"] as Vector2) + su * -120.0, "yaw": atan2(-su.x, -su.y) + PI, "dist": -1.0})
	# the airport (runway middle, apron) and the harbour
	var rw := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -550.0))
	out.append({"name": "airport_runway", "pos": Vector2(rw.x, rw.z), "yaw": PI * 0.5, "dist": -1.0})
	var ap := Airport.to_world(Vector3(1150.0, 0.0, -650.0))
	out.append({"name": "airport_apron", "pos": Vector2(ap.x, ap.z), "yaw": PI * 0.5, "dist": -1.0})
	out.append({"name": "harbour", "pos": Vector2(-300.0, 1338.0), "yaw": 0.0, "dist": -1.0})
	# the west beach at z = 0 and z = 600 (the first dry sand)
	for bz: float in [0.0, 600.0]:
		var bx := -(TerrainHeight.WORLD_HALF - 120.0)
		while bx < -1000.0 and TerrainHeight.height_at(bx, bz) < TerrainHeight.SEA_LEVEL + 1.2:
			bx += 3.0
		out.append({"name": "beach_z%d" % int(bz), "pos": Vector2(bx + 14.0, bz), "yaw": PI * 0.5, "dist": -1.0})
	return out


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_wait = int(Dev.get(&"_args").get("every", "14")) if Dev.get(&"_args") is Dictionary else 14
	if not _built:
		_build_stops()
		if OS.get_environment("SW_LIST") == "1":
			return true
	if _f == 2:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		var city := Game.world as City
		var hour := float(OS.get_environment("SW_HOUR")) if OS.get_environment("SW_HOUR") != "" else 12.0
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(hour)
	if not _ablate.is_empty() and not _stops.is_empty():
		if _f >= 3:
			var w := (_f - 3) / maxi(_wait, 1)
			var k2 := (_f - 3) % maxi(_wait, 1)
			if w > _ablate.size():
				return true
			_apply(p, _stops[0], k2 if w == 0 else 1)
			if k2 == 0 and w >= 1:
				_hide(_ablate[w - 1])
			if k2 == maxi(_wait, 1) - 4:
				_i = 0
				_report(p, _stops[0], "ABLATE_RESULT w%d" % w)
		_f += 1
		return false
	if _f >= 3 and _i < _stops.size():
		var k := (_f - 3) % maxi(_wait, 1)
		_apply(p, _stops[_i], k)
		if k == maxi(_wait, 1) - 4:                                  # the frame of the screenshot (Dev saves at multiples of EVERY, three frames before this window ends)
			_report(p, _stops[_i])
	_f += 1
	if _f >= 3 and (_f - 3) % maxi(_wait, 1) == 0 and _f > 3:
		_i += 1
	return _i >= _stops.size()


func _settle(pos: Vector3) -> void:
	var city := Game.world as City
	if city == null:
		return
	if city.terrain != null:
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


func _apply(p: Player, st: Dictionary, k: int) -> void:
	if k == 0:
		var pos: Vector2 = st["pos"]
		var y := TerrainHeight.height_at(pos.x, pos.y)
		var pos3 := Vector3(pos.x, y + 0.8, pos.y)
		p.camera_rig.cine_clear()
		p.global_position = pos3
		p.velocity = Vector3.ZERO
		p.camera_rig.yaw = float(st["yaw"])
		_settle(pos3)
		p.teleport_to(pos3)
		p.camera_rig.yaw = float(st["yaw"])
		if float(st["dist"]) > 0.0 and "distance" in p.camera_rig:
			p.camera_rig.set("distance", float(st["dist"]))
		if OS.get_environment("SW_NOHUD") == "1":
			_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasItem
	if _hud != null:
		_hud.visible = false


func _hide(pat: String) -> void:
	var n_hidden := 0
	var stack: Array = [Game.player.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if pat == "HUD":
			if n is CanvasLayer and (n is Hud or str(n.name).contains("Hud") or str(n.name).contains("Touch")):
				(n as CanvasLayer).visible = false
				n_hidden += 1
			continue
		if n is GeometryInstance3D:
			var key := "%s/%s" % [str(n.get_parent().name).rstrip("0123456789"), str(n.name).rstrip("0123456789")]
			if key.contains(pat):
				(n as GeometryInstance3D).visible = false
				n_hidden += 1
	print("ABLATE hide '%s': %d nodes" % [pat, n_hidden])


func _in_frustum(planes: Array[Plane], g: GeometryInstance3D) -> bool:
	var bb: AABB = g.get_aabb()
	var gt := g.global_transform
	var c := gt * (bb.position + bb.size * 0.5)
	var sc := maxf(gt.basis.get_scale().x, maxf(gt.basis.get_scale().y, gt.basis.get_scale().z))
	var r := bb.size.length() * 0.5 * sc
	for pl in planes:
		if pl.distance_to(c) > r:
			return false
	return true


## The draw surfaces of the geometry that is inside the camera frustum, grouped by "parent/name" with the digits stripped: where the draws of the frame come from.
func _census() -> String:
	var agg := {}
	var cam: Camera3D = (Game.player as Player).camera_rig.camera
	var planes: Array[Plane] = []
	for pl in cam.get_frustum():
		planes.append(pl as Plane)
	var stack: Array = [Game.player.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree() and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			var g := n as GeometryInstance3D
			var surf := 1
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				surf = (n as MeshInstance3D).mesh.get_surface_count()
			if n is MultiMeshInstance3D:
				var mm := (n as MultiMeshInstance3D).multimesh
				if mm == null or mm.visible_instance_count == 0 or mm.instance_count == 0:
					continue
				surf = mm.mesh.get_surface_count() if mm.mesh != null else 1
			if g.visibility_range_end > 0.0 and g.global_position.distance_to(cam.global_position) > g.visibility_range_end + 1.0:
				continue
			if not _in_frustum(planes, g):
				continue
			var key := "%s/%s" % [str(n.get_parent().name).rstrip("0123456789"), str(n.name).rstrip("0123456789")]
			agg[key] = int(agg.get(key, 0)) + surf
	var rows: Array = []
	var total := 0
	for key in agg:
		rows.append([int(agg[key]), key])
		total += int(agg[key])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var s := "(%d in view) " % total
	for r in rows.slice(0, 14):
		s += "%s=%d " % [r[1], r[0]]
	return s


func _report(p: Player, st: Dictionary, tag := "SWEEP") -> void:
	var s := PerfProbe.snapshot(p.get_viewport())
	var pos := p.global_position
	print("%s %d %s x=%.0f z=%.0f y=%.1f tier=%d draws=%d prims=%d total_draws=%d total_prims=%d nodes=%d tex_mb=%.0f" % [tag, _i, st["name"], pos.x, pos.z, pos.y, Game.quality, s["draws"], s["prims"], s["total_draws"], s["total_prims"], s["nodes"], s["tex_mb"]])
	if OS.get_environment("SW_CENSUS") == "1":
		print("SWEEP_CENSUS %d %s %s" % [_i, st["name"], _census()])
