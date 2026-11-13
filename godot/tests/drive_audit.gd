extends RefCounted
## DriveAudit (wave 112 critic, PLAY lens): "are the roads drivable end to end?" A real car in the real scene is driven with the phone's own inputs (the pure-pursuit Pilot of tests/traffic_audit.gd) along EVERY
## road of TerrainRoads from its first to its last sample, with the whole world alive (streaming, landscape, towns, traffic, wildlife). Per road it prints one line: metres driven, seconds, average speed, the
## stuck spots (a car that crawls under 0.6 m/s for 2.5 s: position and what stands there), crashes and damage of the car, the car's height above the road surface (floating / sunk), script errors of the
## run, and the frame times of the main thread (mean, p95, p99, worst, the number of frames over 50 ms and over 100 ms, where the three worst spikes happened along the road).
##   tools/drive_audit.sh                      all roads, 3x speed (about 8 minutes)
##   env DA_ROADS="0,9,10" or "PASS ROAD,RING ROAD"   only these roads (index or name), DA_K (time scale, default 3), DA_MAXLEN (stop after this many metres, default the whole road),
##       DA_QUALITY (0 LOW, 1 MED, 2 HIGH; default 0), DA_SEED, DA_REVERSE=1 (drive the road from its end), DA_VERBOSE=1
## Exit code 0 = no stuck spot, no wreck and no script error on any road (frame times are reported, not judged).

const TA := preload("res://tests/traffic_audit.gd")
const TIMEOUT_SECONDS := 140

var host: Node
var main: Node
var p: Player
var mgr: VehicleManager
var rows: Array[String] = []
var failures: Array[String] = []


func _select() -> Array[int]:
	var out: Array[int] = []
	var roads := TerrainRoads.roads()
	var env := OS.get_environment("DA_ROADS")
	if env == "":
		for i in roads.size():
			out.append(i)
		return out
	for tok in env.split(",", false):
		var t := tok.strip_edges()
		if t.is_valid_int():
			out.append(int(t))
		else:
			for i in roads.size():
				if String(roads[i]["name"]) == t:
					out.append(i)
	return out


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	seed(int(OS.get_environment("DA_SEED")) if OS.get_environment("DA_SEED") != "" else 11)
	Sfx.muted = true
	CarRadio.auto_headless = true
	Game.quality = int(OS.get_environment("DA_QUALITY")) if OS.get_environment("DA_QUALITY") != "" else 0
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(p != null and mgr != null, "the real scene is up")
	if p == null or mgr == null:
		return
	p.set_physics_process(true)
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	var k := int(OS.get_environment("DA_K")) if OS.get_environment("DA_K") != "" else 3
	Engine.time_scale = k
	Engine.physics_ticks_per_second = 60 * k
	TrafficField.reset()
	for ri in _select():
		await _drive_road(ri, k)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("DRIVEAUDIT summary")
	for r in rows:
		print(r)
	for f in failures:
		print("DRIVEAUDIT FAIL ", f)
	TestLib.check(failures.is_empty(), "every road can be driven end to end without a stuck spot, a wreck or a script error (%d problems)" % failures.size())
	CarRadio.auto_headless = false
	main.queue_free()


func _what_is_near(x: float, z: float) -> String:
	var parts: Array[String] = []
	var space := p.get_world_3d().direct_space_state
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var gy := TerrainHeight.height_at(x, z) + 1.0
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, gy, z), Vector3(x + d.x * 6.0, gy, z + d.y * 6.0), 1 | 16)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n := hit["collider"] as Node
			parts.append("%s@%.1fm" % [str(n.name).left(24), Vector2(x, z).distance_to(Vector2((hit["position"] as Vector3).x, (hit["position"] as Vector3).z))])
	return ",".join(parts) if not parts.is_empty() else "nothing within 6 m"


## The route along road `ri` between s0 and s1 (every sample, STEP 10 m): `lane` metres to the right of the centre line (3 m on a highway, none on a 5 m track).
static func _route(ri: int, s0: float, s1: float, forward: bool, lane: float) -> PackedVector2Array:
	var pos: PackedVector2Array = TerrainRoads.roads()[ri]["pos"]
	var n := pos.size()
	var a := clampi(int(s0 / TerrainRoads.STEP), 0, n - 2)
	var b := clampi(int(s1 / TerrainRoads.STEP), a + 1, n - 1)
	var idxs: Array[int] = []
	for i in range(a, b + 1):
		idxs.append(i)
	if not forward:
		idxs.reverse()
	var out := PackedVector2Array()
	for k in idxs.size():
		var nxt: int = idxs[mini(k + 1, idxs.size() - 1)]
		var prv: int = idxs[maxi(k - 1, 0)]
		var d := pos[nxt] - pos[prv]
		if d.length() < 0.01:
			continue
		d = d.normalized()
		out.append(pos[idxs[k]] + Vector2(-d.y, d.x) * lane)
	return out


## Speed limit along a route: what a careful driver takes the bend at (lateral acceleration 4.5 m/s2 from the radius of three points 12 m apart), looking 5 points ahead, never above `cruise`.
static func _limits(route: PackedVector2Array, cruise: float) -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	raw.resize(route.size())
	for i in route.size():
		var a := route[maxi(i - 1, 0)]
		var b := route[i]
		var c := route[mini(i + 1, route.size() - 1)]
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ca := c.distance_to(a)
		var area2 := absf((b - a).cross(c - a))
		var r := 1.0e6 if area2 < 0.01 else (ab * bc * ca) / (2.0 * area2)
		raw[i] = clampf(sqrt(4.5 * r), 4.0, cruise)
	var out := PackedFloat32Array()
	out.resize(route.size())
	for i in route.size():
		var m := raw[i]
		for j in range(i, mini(i + 6, route.size())):
			m = minf(m, raw[j])
		out[i] = m
	return out


func _drive_road(ri: int, k: int) -> void:
	var road: Dictionary = TerrainRoads.roads()[ri]
	var name := String(road["name"])
	var len := float(road["len"])
	var maxlen := float(OS.get_environment("DA_MAXLEN")) if OS.get_environment("DA_MAXLEN") != "" else len
	var rev := OS.get_environment("DA_REVERSE") == "1"
	var is_hw := String(road["kind"]) == "highway"
	var lane := 3.0 if is_hw else 0.0
	var route := _route(ri, 0.0, minf(len, maxlen), true, lane)
	if rev:
		route = _route(ri, maxf(len - maxlen, 0.0), len, false, lane)
	if route.size() < 4:
		failures.append("%s: no route" % name)
		return
	if mgr.driven != null:
		mgr.exit_vehicle()
	var start := route[0]
	var prof0: float = (road["prof"] as PackedFloat32Array)[clampi(int((maxf(len - maxlen, 0.0) if rev else 0.0) / TerrainRoads.STEP), 0, (road["prof"] as PackedFloat32Array).size() - 1)]
	var gy0 := TerrainHeight.drive_height_at(start.x, start.y, prof0)
	var car := mgr.spawn_parked(&"sedan", Vector3(start.x, gy0, start.y), 0.0)
	if car == null:
		mgr._free_slot()
		car = mgr.spawn_parked(&"sedan", Vector3(start.x, gy0, start.y), 0.0)
	if car == null:
		failures.append("%s: the audit car cannot be placed" % name)
		return
	var d := route[1] - route[0]
	car.heading = atan2(-d.x, -d.y)
	car.rotation.y = car.heading
	car._heading_set = car.heading
	car.global_position = Vector3(start.x, gy0, start.y)
	p.teleport_to(car.global_position + Vector3(0.0, 1.0, 0.0))
	await TestLib.frames(host, 10)
	mgr.enter(car)
	await TestLib.frames(host, 4)
	var pilot := TA.Pilot.new()
	pilot.loop = false
	pilot.careful = true
	var cruise := 22.0 if is_hw else 12.0
	var limits := _limits(route, cruise)
	pilot.look_ahead = 16.0 if is_hw else 9.0
	pilot.start(car, route, cruise)
	var crashes0 := car.crashes
	var crash_log: Array[String] = []
	var err0: int = Dev.errors.total
	var frames_ms := PackedFloat32Array()
	var spikes: Array = []                                       # [ms, travelled]
	var stuck_t := 0.0
	var stuck_spots: Array[String] = []
	var wrecks := 0
	var min_rel := 1.0e9
	var max_rel := -1.0e9
	var t_game := 0.0
	var last := Time.get_ticks_usec()
	var guard := 0
	var cap_game := (maxlen / 5.0) + 30.0
	var ended := "end"
	var hp0 := car.hp
	while true:
		guard += 1
		await host.get_tree().physics_frame
		var now := Time.get_ticks_usec()
		var wall := float(now - last) / 1000.0
		last = now
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		t_game += dt
		if guard % 2 == 0:                                      # one sample per rendered-frame-ish: every second physics tick
			frames_ms.append(wall * 2.0 if wall < 2000.0 else 2000.0)
			if wall * 2.0 > 50.0:
				spikes.append([wall * 2.0, pilot.travelled])
		if not Game.is_playing():
			Game.state = &"play"
		p.hp = p.max_hp
		if not is_instance_valid(car) or car.dead:
			wrecks += 1
			ended = "WRECKED at %.0f m" % pilot.travelled
			break
		if mgr.driven != car:
			ended = "the car is no longer driven at %.0f m" % pilot.travelled
			break
		pilot.cruise = limits[mini(pilot.idx, limits.size() - 1)]
		pilot.step(dt)
		if car.crashes > crashes0 + crash_log.size():
			crash_log.append("(%.0f, %.0f) at %.0f m, %.1f m/s, limit %.1f, off the line %.1f m" % [car.global_position.x, car.global_position.z, pilot.travelled, car.speed, pilot.cruise, Vector2(car.global_position.x, car.global_position.z).distance_to(route[mini(pilot.idx, route.size() - 1)])])
		var cx := car.global_position.x
		var cz := car.global_position.z
		var gy := TerrainHeight.drive_height_at(cx, cz, car.global_position.y)
		var rel := car.global_position.y - gy
		min_rel = minf(min_rel, rel)
		max_rel = maxf(max_rel, rel)
		if absf(car.speed) < 0.6:
			stuck_t += dt
			if stuck_t > 2.5 and stuck_t - dt <= 2.5:
				stuck_spots.append("(%.0f, %.0f) at %.0f m: %s" % [cx, cz, pilot.travelled, _what_is_near(cx, cz)])
		else:
			stuck_t = 0.0
		var finished := pilot.idx >= route.size() - 1 and Vector2(cx, cz).distance_to(route[route.size() - 1]) < 25.0
		if finished:
			break
		if t_game > cap_game:
			ended = "TIME CAP at %.0f of %.0f m" % [pilot.travelled, maxlen]
			break
	pilot.release()
	var n := frames_ms.size()
	var sorted := frames_ms.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in frames_ms:
		mean += v
	mean /= maxf(float(n), 1.0)
	var p95 := sorted[int(float(n) * 0.95)] if n > 0 else 0.0
	var p99 := sorted[int(float(n) * 0.99)] if n > 0 else 0.0
	var worst := sorted[n - 1] if n > 0 else 0.0
	var over50 := 0
	var over100 := 0
	for v in frames_ms:
		if v > 50.0:
			over50 += 1
		if v > 100.0:
			over100 += 1
	spikes.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var sp_txt := ""
	for s in spikes.slice(0, 3):
		sp_txt += " %.0fms@%.0fm" % [float(s[0]), float(s[1])]
	var errs: int = Dev.errors.total - err0
	var line := "DRIVEAUDIT %-16s %s len %4.0f m driven %4.0f m in %3.0f s (avg %.1f m/s) stuck %d crashes %d hp %.0f->%.0f height over road %.2f..%.2f script_errors %d | frames mean %.1f p95 %.1f p99 %.1f worst %.0f ms, >50ms %d, >100ms %d, spikes:%s" % [
			name, ended, len, pilot.travelled, t_game, pilot.travelled / maxf(t_game, 0.1), stuck_spots.size(), car.crashes if is_instance_valid(car) else -1, hp0, car.hp if is_instance_valid(car) else 0.0,
			min_rel, max_rel, errs, mean, p95, p99, worst, over50, over100, sp_txt]
	rows.append(line)
	print(line)
	for cl in crash_log.slice(0, 6):
		print("DRIVEAUDIT   crash ", cl)
	for s in stuck_spots:
		print("DRIVEAUDIT   stuck ", s)
		failures.append("%s stuck at %s" % [name, s])
	if wrecks > 0:
		failures.append("%s: the car was wrecked" % name)
	if errs > 0:
		failures.append("%s: %d script errors during the drive" % [name, errs])
	if ended.begins_with("TIME CAP") or ended.begins_with("the car"):
		failures.append("%s: %s" % [name, ended])
