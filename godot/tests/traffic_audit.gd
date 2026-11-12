extends RefCounted
## TrafficAudit (owner round 6: "cars are going inside other cars"). Two parts:
##  * `Audit`: samples every pair of vehicle hulls in the TrafficField (real cars, near traffic, road traffic, bridge cars, parked decor cars, wrecks) and keeps the pairs that stay
##    interpenetrated: it FAILS on any pair that overlaps by more than `min_depth` for longer than `fail_after` seconds (default 0.3 s). Short touches while a crash is being resolved are fine.
##  * `Pilot`: a bot that drives a real car along a route with the phone's own inputs (pure pursuit + a safe-distance rule, so it does not ram on purpose), in the city lanes or along the highways.
## The run: `tools/traffic_audit.sh` (5 minutes of game time at 4x speed, city then outskirts, prints the report and exits non-zero on a violation), tests/test_vehicle_overlap.gd uses the same classes
## for a shorter slice. Entry: `run(host)` (the runner scene awaits it); AUDIT_SECS, AUDIT_CITY_SHARE (0..1) and AUDIT_SEED are read from the environment.

const TIMEOUT_SECONDS := 140


class Audit extends RefCounted:
	var min_depth := 0.12
	var fail_after := 0.3
	var linger := 0.12                      ## a pair unseen for this long closes its event
	var sample_every := 0.05
	var ticks := 0
	var t := 0.0
	var pair_seconds := 0.0
	var max_hulls := 0
	var by_kind := {}                       ## "near/near" -> violation count
	var violations: Array[Dictionary] = []
	var brief: Array[Dictionary] = []            ## short but deep overlaps (a crash being resolved, a car that appeared inside another): listed in the report, they do not fail the run
	var longest := 0.0
	var deepest := 0.0
	var events := 0                         ## all overlap events, short ones too
	var _open := {}
	var _acc := 0.0
	var _out: Array = []
	var near_samples := 0
	var near_total := 0
	var near_moving := 0

	func tick(dt: float) -> void:
		t += dt
		_acc += dt
		if _acc < sample_every:
			return
		var step := _acc
		_acc = 0.0
		ticks += 1
		_out.clear()
		TrafficField.pairs(min_depth, _out)
		max_hulls = maxi(max_hulls, TrafficField.live_count())
		var fl := TrafficField.flow(TrafficField.NEAR)
		near_samples += 1
		near_total += fl.x
		near_moving += fl.y
		for p: Array in _out:
			var key := (int(p[0]) * 1000 + int(p[1])) * 1000000 + int(p[2]) * 1000 + int(p[3])
			var e: Dictionary = _open.get(key, {})
			if e.is_empty():
				e = {"first": t, "last": t, "depth": float(p[4]), "a": TrafficField.describe(int(p[0]), int(p[1])), "b": TrafficField.describe(int(p[2]), int(p[3])), "key": key, "counted": false}
				e["xa"] = _extra(e["a"])
				e["xb"] = _extra(e["b"])
				_open[key] = e
				events += 1
			e["last"] = t
			e["depth"] = maxf(float(e["depth"]), float(p[4]))
			e["b2"] = TrafficField.describe(int(p[2]), int(p[3]))
			e["a2"] = TrafficField.describe(int(p[0]), int(p[1]))
			pair_seconds += step
			if not bool(e["counted"]) and t - float(e["first"]) > fail_after:
				e["counted"] = true
				_violate(e)
		var gone: Array = []
		for key in _open:
			if t - float((_open[key] as Dictionary)["last"]) > linger:
				gone.append(key)
		for key in gone:
			var e2: Dictionary = _open[key]
			longest = maxf(longest, float(e2["last"]) - float(e2["first"]))
			deepest = maxf(deepest, float(e2["depth"]))
			if not bool(e2["counted"]) and float(e2["depth"]) > 0.6:
				brief.append(e2)
			_open.erase(key)

	func _extra(d: Dictionary) -> String:
		if d["src"] == "near" and NearTraffic.instance != null:
			var st := NearTraffic.instance.debug_state(int(d["i"]))
			return " " + str(st)
		if d["src"] == "real" and Game.vehicles != null:
			for c: Vehicle in (Game.vehicles as VehicleManager).list:
				if is_instance_valid(c) and c.field_slot == int(d["i"]):
					var f := c.forward()
					var ld := TrafficField.lead(c.global_position.x, c.global_position.z, f.x, f.z, float(c.spec["len"]) * 0.5, float(c.spec["wid"]) * 0.5, TrafficBrain.look_for(maxf(c.speed, 0.0)) + 6.0, TrafficField.REAL, c.field_slot, 0.3)
					return " real %s driven %s ai %s ai_speed %.1f ovl %.2f path %d s %.0f dir %d spd %.1f thr %.2f stun %.1f hp %.0f lead %s -> %s" % [c.kind, str(c == (Game.vehicles as VehicleManager).driven), str(c.ai), c.ai_speed, c.lane_ovl, c.path_road, c.path_s, c.path_dir, c.speed, c.script_thr, c.ai_stun, c.hp, str(ld), str(TrafficField.describe_id(ld.z)).substr(0, 70)]
		if d["src"] == "bridge" and BridgeWorld.instance != null:
			for t: BridgeTraffic in BridgeWorld.instance.traffic:
				if is_instance_valid(t) and t._slot == int(d["i"]):
					var l := TrafficField.lead(t.global_position.x, t.global_position.z, t._fwd.x, t._fwd.y, t._hl, t._hw, TrafficBrain.look_for(t.v), TrafficField.BRIDGE, t._slot)
					return " bridge %s dir %d u %.1f/%.0f v %.1f waiting %s lead %s" % [t.name, t.dir, t.u, t._len, t.v, str(t.waiting), str(l)]
		return ""

	func _violate(e: Dictionary) -> void:
		var a: Dictionary = e["a"]
		var b: Dictionary = e["b"]
		var names := [String(a["src"]), String(b["src"])]
		names.sort()
		var k := "%s/%s" % names
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		violations.append(e)
		e["around"] = _around(float(a["x"]), float(a["z"]), 28.0)

	## Every hull within `r` m of a point, nearest first, as text lines (the report of a violation shows what stood around it).
	func _around(x: float, z: float, r: float) -> Array:
		var rows: Array = []
		for src in TrafficField.SRC_N:
			for i in TrafficField._n[src]:
				var k: int = TrafficField._base[src] + i
				if TrafficField._hl[k] <= 0.0:
					continue
				var dx: float = TrafficField._x[k] - x
				var dz: float = TrafficField._z[k] - z
				var d := sqrt(dx * dx + dz * dz)
				if d < r:
					var dd := TrafficField.describe(src, i)
					rows.append([d, "%s#%d (%.1f, %.1f) v%.1f f(%.2f,%.2f) hl %.1f hw %.1f%s" % [dd["src"], i, dd["x"], dd["z"], dd["v"], dd["fx"], dd["fz"], TrafficField._hl[k], TrafficField._hw[k], _extra(dd)]])
		rows.sort_custom(func(m: Array, n: Array) -> bool: return float(m[0]) < float(n[0]))
		return rows

	func passed() -> bool:
		return violations.is_empty()

	## Overlaps that are still open and already older than the limit (called at the end of a run).
	func finish() -> void:
		for key in _open:
			var e: Dictionary = _open[key]
			if not bool(e["counted"]) and float(e["last"]) - float(e["first"]) > fail_after:
				e["counted"] = true
				_violate(e)
			longest = maxf(longest, float(e["last"]) - float(e["first"]))
			deepest = maxf(deepest, float(e["depth"]))

	func report(max_lines := 14) -> String:
		var s := "TRAFFIC AUDIT  %.0f s sampled, %d hulls at most, %d overlap events, %d longer than %.2f s (longest %.2f s, deepest %.2f m)\n" % [t, max_hulls, events, violations.size(), fail_after, longest, deepest]
		s += "  flow: %.1f near cars on average, %.0f %% of them moving\n" % [float(near_total) / maxf(float(near_samples), 1.0), 100.0 * float(near_moving) / maxf(float(near_total), 1.0)]
		for k in by_kind:
			s += "  %s: %d\n" % [k, int(by_kind[k])]
		if not brief.is_empty():
			s += "  brief deep overlaps (%d, not failures):\n" % brief.size()
			for e in brief.slice(0, 6):
				var a: Dictionary = e["a"]
				var b: Dictionary = e["b"]
				s += "    t=%.1f %.2fs depth %.2f  %s#%d (%.1f, %.1f) v%.1f f(%.2f,%.2f)  x  %s#%d (%.1f, %.1f) v%.1f f(%.2f,%.2f)\n" % [float(e["first"]), float(e["last"]) - float(e["first"]), float(e["depth"]),
						a["src"], int(a["i"]), float(a["x"]), float(a["z"]), float(a["v"]), float(a["fx"]), float(a["fz"]), b["src"], int(b["i"]), float(b["x"]), float(b["z"]), float(b["v"]), float(b["fx"]), float(b["fz"])]
				s += "      A%s\n      B%s\n" % [e.get("xa", ""), e.get("xb", "")]
		var n := 0
		for e in violations:
			if n >= max_lines:
				break
			n += 1
			var a: Dictionary = e["a"]
			var b: Dictionary = e["b"]
			s += "  t=%.1f %.2fs depth %.2f  %s#%d (%.1f, %.1f) v%.1f f(%.2f,%.2f)  x  %s#%d (%.1f, %.1f) v%.1f f(%.2f,%.2f)\n" % [float(e["first"]), float(e["last"]) - float(e["first"]), float(e["depth"]),
					a["src"], int(a["i"]), float(a["x"]), float(a["z"]), float(a["v"]), float(a["fx"]), float(a["fz"]), b["src"], int(b["i"]), float(b["x"]), float(b["z"]), float(b["v"]), float(b["fx"]), float(b["fz"])]
			s += "      A%s\n      B%s\n" % [e.get("xa", ""), e.get("xb", "")]
			for row: Array in (e.get("around", []) as Array).slice(0, 9):
				s += "        %.1f m  %s\n" % [float(row[0]), str(row[1])]
		return s


## Drives a real Vehicle along `route` (XZ points) with the touch inputs: pure pursuit, speed from the target and the safe-distance rule against the TrafficField.
class Pilot extends RefCounted:
	var car: Vehicle
	var route := PackedVector2Array()
	var loop := true
	var cruise := 16.0
	var idx := 0
	var laps := 0
	var stuck_t := 0.0
	var teleports := 0
	var look_ahead := 16.0
	var travelled := 0.0
	var careful := true
	var _last := Vector2.ZERO

	func start(c: Vehicle, r: PackedVector2Array, speed: float) -> void:
		car = c
		route = r
		cruise = speed
		idx = _nearest_index()
		_last = Vector2(car.global_position.x, car.global_position.z)

	func _nearest_index() -> int:
		var best := 0
		var bd := INF
		var p := Vector2(car.global_position.x, car.global_position.z)
		for i in route.size():
			var d := p.distance_squared_to(route[i])
			if d < bd:
				bd = d
				best = i
		return best

	func release() -> void:
		for a in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
			Input.action_release(a)

	func step(dt: float) -> void:
		if not is_instance_valid(car) or car.dead or route.size() < 2:
			return
		var p := Vector2(car.global_position.x, car.global_position.z)
		travelled += p.distance_to(_last)
		_last = p
		# advance the target point
		var guard := 0
		while guard < 40 and p.distance_to(route[idx]) < look_ahead:
			idx += 1
			guard += 1
			if idx >= route.size():
				if loop:
					idx = 0
					laps += 1
				else:
					idx = route.size() - 1
					break
		var tgt := route[idx]
		var to := tgt - p
		var err := wrapf(atan2(-to.x, -to.y) - car.heading, -PI, PI)
		var steer := clampf(err * 1.6, -1.0, 1.0)
		var want := cruise * (1.0 - clampf(absf(err) * 0.9, 0.0, 0.7))
		if careful:
			var f := car.forward()
			var l := TrafficField.lead(p.x, p.y, f.x, f.z, float(car.spec["len"]) * 0.5, float(car.spec["wid"]) * 0.5, TrafficBrain.look_for(maxf(car.speed, 0.0)) + 6.0, TrafficField.REAL, car.field_slot, 0.5)
			if l.x < INF:
				want = minf(want, TrafficBrain.safe_speed(l.x, l.y, 5.5, 0.6, 3.0))
		for a in [&"move_left", &"move_right"]:
			Input.action_release(a)
		Input.action_press(&"move_left" if steer > 0.0 else &"move_right", absf(steer))
		if car.speed < want - 0.5:
			Input.action_release(&"move_back")
			Input.action_press(&"move_forward", clampf((want - car.speed) / 3.0, 0.25, 1.0))
		elif car.speed > want + 1.0:
			Input.action_release(&"move_forward")
			Input.action_press(&"move_back", clampf((car.speed - want) / 6.0, 0.2, 1.0))
		else:
			Input.action_release(&"move_forward")
			Input.action_release(&"move_back")
		if absf(car.speed) < 0.5:
			stuck_t += dt
			if stuck_t > 9.0:                                   # held up for good (a knocked car standing in the lane, a jam): put the car on the route at the next clear spot (the audit is about traffic, not the pilot)
				stuck_t = 0.0
				teleports += 1
				for k in range(1, 12):
					var j := (idx + k * 3) % route.size()
					var q := route[j]
					var nq := route[(j + 1) % route.size()]
					var dq := (nq - q).normalized()
					if TrafficField.clear(q.x, q.y, dq.x, dq.y, float(car.spec["len"]) * 0.5, float(car.spec["wid"]) * 0.5, 2.0, TrafficField.REAL, car.field_slot):
						idx = (j + 1) % route.size()
						car.global_position = Vector3(q.x, car.global_position.y, q.y)
						car.heading = atan2(-dq.x, -dq.y)
						car.rotation.y = car.heading
						car._heading_set = car.heading
						car.vel = Vector3.ZERO
						car.speed = 0.0
						break
		else:
			stuck_t = 0.0


# --- routes ------------------------------------------------------------------------------------------------------------------------------------

## A closed clockwise loop around the blocks between the roads x0..x1 and z0..z1 (road indices), in the right-hand lanes (axis 0 lane z = c + 5 * dir, axis 1 lane x = c - 5 * dir), points every 12 m.
static func city_loop(x0: int, x1: int, z0: int, z1: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var lane := CityLayout.LANE
	var xa := CityLayout.road_center(x0)
	var xb := CityLayout.road_center(x1)
	var za := CityLayout.road_center(z0)
	var zb := CityLayout.road_center(z1)
	_line(out, Vector2(xa + lane, za + lane), Vector2(xb - lane, za + lane))          # east along the north road (dir +1: z = c + 5)
	_line(out, Vector2(xb - lane, za + lane), Vector2(xb - lane, zb - lane))          # south along the east road (dir +1 on axis 1: x = c - 5)
	_line(out, Vector2(xb - lane, zb - lane), Vector2(xa + lane, zb - lane))          # west along the south road (dir -1: z = c - 5)
	_line(out, Vector2(xa + lane, zb - lane), Vector2(xa + lane, za + lane))          # north along the west road (dir -1 on axis 1: x = c + 5)
	return out


static func _line(out: PackedVector2Array, a: Vector2, b: Vector2) -> void:
	var n := maxi(int(a.distance_to(b) / 12.0), 1)
	for i in n:
		out.append(a.lerp(b, float(i) / float(n)))


## Along a highway of TerrainRoads from `s0` to `s1` metres (one carriageway: the right-hand side of the direction of travel), every 12 m.
static func road_route(road_i: int, s0: float, s1: float, forward := true) -> PackedVector2Array:
	var pos: PackedVector2Array = TerrainRoads.roads()[road_i]["pos"]
	var out := PackedVector2Array()
	var step := TerrainRoads.STEP
	var n := pos.size()
	var a := clampi(int(s0 / step), 0, n - 2)
	var b := clampi(int(s1 / step), a + 1, n - 1)
	var idxs: Array[int] = []
	for i in range(a, b + 1):
		idxs.append(i)
	if not forward:
		idxs.reverse()
	for k in idxs.size():
		var i: int = idxs[k]
		var nxt: int = idxs[mini(k + 1, idxs.size() - 1)]
		var prv: int = idxs[maxi(k - 1, 0)]
		var d := pos[nxt] - pos[prv]
		if d.length() < 0.01:
			continue
		d = d.normalized()
		out.append(pos[i] + Vector2(-d.y, d.x) * 3.0)
	return out


static func _out_and_back(road_i: int, length: float) -> PackedVector2Array:
	var r := road_route(road_i, 0.0, length, true)
	r.append_array(road_route(road_i, 0.0, length, false))
	return r


# --- the run -----------------------------------------------------------------------------------------------------------------------------------

var audit := Audit.new()
var verbose := OS.get_environment("AUDIT_VERBOSE") == "1"


func run(host: Node) -> void:
	var secs := float(OS.get_environment("AUDIT_SECS")) if OS.get_environment("AUDIT_SECS") != "" else 300.0
	var city_share := float(OS.get_environment("AUDIT_CITY_SHARE")) if OS.get_environment("AUDIT_CITY_SHARE") != "" else 0.5
	seed(int(OS.get_environment("AUDIT_SEED")) if OS.get_environment("AUDIT_SEED") != "" else 17)
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	CarRadio.auto_headless = true
	Game.quality = int(OS.get_environment("AUDIT_QUALITY")) if OS.get_environment("AUDIT_QUALITY") != "" else 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	var mgr := Game.vehicles as VehicleManager
	TestLib.check(p != null and mgr != null and Game.world != null, "the real scene is up")
	if p == null or mgr == null:
		return
	p.set_physics_process(true)
	var k := 4
	Engine.time_scale = k
	Engine.physics_ticks_per_second = 60 * k
	TrafficField.reset()
	var watch_secs := float(OS.get_environment("AUDIT_WATCH_SECS")) if OS.get_environment("AUDIT_WATCH_SECS") != "" else 0.0
	if watch_secs > 0.0:
		await _watch(host, p, mgr, watch_secs)
	var city_secs := secs * city_share
	var stages: Array = [["city core loop", city_secs * 0.5, city_loop(CityLayout.CORE0 + 1, CityLayout.CORE0 + CityLayout.CORE_N - 1, CityLayout.CORE0 + 1, CityLayout.CORE0 + CityLayout.CORE_N - 1), 15.0],
			["city outer loop", city_secs * 0.5, city_loop(3, CityLayout.N - 3, 3, CityLayout.N - 3), 20.0]]
	var road_secs := (secs - city_secs) / 2.0
	stages.append(["north highway out and back", road_secs, _out_and_back(0, 1500.0), 24.0])
	stages.append(["east highway out and back", road_secs, _out_and_back(1, 1500.0), 24.0])
	for st: Array in stages:
		if float(st[1]) < 1.0:
			continue
		await _stage(host, p, mgr, String(st[0]), float(st[1]), st[2], float(st[3]))
	audit.finish()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print(audit.report())
	TestLib.check(audit.passed(), "no two vehicle hulls overlap for longer than %.1f s (%d violations, longest %.2f s)" % [audit.fail_after, audit.violations.size(), audit.longest])
	CarRadio.auto_headless = false
	main.queue_free()


## The hero stands on a pavement corner of the core (on foot, out of every lane) and the traffic runs for `secs`: pure traffic dynamics, no pilot.
func _watch(host: Node, p: Player, mgr: VehicleManager, secs: float) -> void:
	var c := Vector3(CityLayout.road_center(CityLayout.CORE0 + 4) + 16.0, 0.0, CityLayout.road_center(CityLayout.CORE0 + 4) + 16.0)
	var xz := OS.get_environment("AUDIT_WATCH_XZ").split(",")
	if xz.size() == 2:
		c = Vector3(float(xz[0]), 0.0, float(xz[1]))
	var at := OS.get_environment("AUDIT_WATCH_AT").split(",")
	if at.size() == 2:
		c = Vector3(CityLayout.road_center(roundi((float(at[0]) + CityLayout.HALF) / CityLayout.PITCH)) + 16.0, 0.0, CityLayout.road_center(roundi((float(at[1]) + CityLayout.HALF) / CityLayout.PITCH)) + 16.0)
	if absf(c.x) > TerrainHeight.CITY_HALF or absf(c.z) > TerrainHeight.CITY_HALF:
		c.y = TerrainHeight.height_at(c.x, c.z) + 1.0                            # outskirts: stand on the ground (a road bridge, a village)
	p.teleport_to(c)
	await TestLib.frames(host, 8)
	var t0 := audit.t
	var guard := 0
	while audit.t - t0 < secs and guard < 400000:
		guard += 1
		await host.get_tree().physics_frame
		if not Game.is_playing():
			Game.state = &"play"
		p.hp = p.max_hp
		audit.tick(1.0 / float(Engine.physics_ticks_per_second))
		if verbose and fmod(audit.t, 10.0) < 1.0 / float(Engine.physics_ticks_per_second):
			print("  watch t=%.0f near %s jam breaks %d overlap kills %d" % [audit.t, str(TrafficField.flow(TrafficField.NEAR)), NearTraffic.instance.jam_breaks, NearTraffic.instance.overlap_kills])
			if audit.t > 30.0:
				_dump_jams()
	var near_n := 0
	var near_m := 0
	var nt := NearTraffic.instance
	for j in nt.count:
		if nt.car_alive(j) and Vector2(nt.car_position(j).x - c.x, nt.car_position(j).z - c.z).length() < 40.0:
			near_n += 1
			if nt.car_speed(j) > 3.0:
				near_m += 1
	print("AUDIT watch end: within 40 m of the hero %d cars, %d moving" % [near_n, near_m])
	if verbose:
		for rc: Vehicle in mgr.list:
			if is_instance_valid(rc) and Vector2(rc.global_position.x - p.global_position.x, rc.global_position.z - p.global_position.z).length() < 120.0:
				print("     REAL %s (%.1f, %.1f) spd %.1f ai %s path %d s %.0f thr %.2f stun %.1f hp %.0f" % [rc.kind, rc.global_position.x, rc.global_position.z, rc.speed, str(rc.ai), rc.path_road, rc.path_s, rc.script_thr, rc.ai_stun, rc.hp])
	var rt := RoadTraffic.instance if RoadTraffic.instance != null else null
	if verbose and rt != null:
		for j in RoadTraffic.CAP:
			if rt.car_alive(j):
				var q2 := rt.car_position(j)
				var l2 := TrafficField.lead(q2.x, q2.z, -sin(rt._yaw[j]), -cos(rt._yaw[j]), NearTraffic.KIND_HALF[rt._kind[j]], NearTraffic.KIND_HW[rt._kind[j]], 40.0, TrafficField.PATH, j, 0.3)
				print("     path#%d (%.1f, %.1f) %s lead %s -> %s" % [j, q2.x, q2.z, str(rt.debug_state(j)), str(l2), str(TrafficField.describe_id(l2.z)).substr(0, 70)])
	if verbose:
		for j in nt.count:
			var st := nt.debug_state(j)
			var q := nt.car_position(j)
			if int(st["alive"]) != 0 and Vector2(q.x - c.x, q.z - c.z).length() < float(OS.get_environment("AUDIT_DUMP_R") if OS.get_environment("AUDIT_DUMP_R") != "" else "40"):
				var ki := NearTraffic.KINDS.find(st["kind"])
				var yaw := nt.car_yaw(j)
				var f := Vector2(-sin(yaw), -cos(yaw))
				var l := TrafficField.lead(q.x, q.z, f.x, f.y, NearTraffic.KIND_HALF[ki], NearTraffic.KIND_HW[ki], 40.0, TrafficField.NEAR, j, 0.3)
				print("     near#%d (%.1f, %.1f) ax %d dir %d tmode %d spd %.1f why %s jam %.1f lead %.1f %s" % [j, q.x, q.z, int(st["axis"]), int(st["dir"]), int(st["tmode"]), float(st["spd"]), str(st["why"]), float(st["jam"]), l.x, str(TrafficField.describe_id(l.z)).substr(0, 80)])
	print("AUDIT stage 'watch on the pavement': %.0f s, flow %.0f %% moving, jam breaks %d, overlap kills %d" % [secs, 100.0 * float(audit.near_moving) / maxf(float(audit.near_total), 1.0), NearTraffic.instance.jam_breaks, NearTraffic.instance.overlap_kills])


## The cars that have stood still for a long time and what each one waits for.
func _dump_jams() -> void:
	var nt := NearTraffic.instance
	for j in nt.count:
		var st := nt.debug_state(j)
		if int(st["alive"]) == 0 or float(st["spd"]) > 0.2 or float(st["jam"]) < 5.0:
			continue
		var q := nt.car_position(j)
		var ki := NearTraffic.KINDS.find(st["kind"])
		var yaw := nt.car_yaw(j)
		var f := Vector2(-sin(yaw), -cos(yaw))
		var l := TrafficField.lead(q.x, q.z, f.x, f.y, NearTraffic.KIND_HALF[ki], NearTraffic.KIND_HW[ki], 40.0, TrafficField.NEAR, j, 0.3)
		print("     JAM near#%d (%.1f, %.1f) ax %d dir %d tmode %d jam %.1f why %s lead gap %.1f -> %s" % [j, q.x, q.z, int(st["axis"]), int(st["dir"]), int(st["tmode"]), float(st["jam"]), str(st["why"]), l.x, str(TrafficField.describe_id(l.z)).substr(0, 110)])


func _stage(host: Node, p: Player, mgr: VehicleManager, label: String, secs: float, route: PackedVector2Array, speed: float) -> void:
	if route.size() < 4:
		TestLib.check(false, "%s: the route exists" % label)
		return
	if mgr.driven != null:
		mgr.exit_vehicle()
	var start := route[0]
	var car := mgr.spawn_parked(&"sedan", Vector3(start.x, 0.0, start.y), 0.0)
	if car == null:
		mgr._free_slot()
		car = mgr.spawn_parked(&"sedan", Vector3(start.x, 0.0, start.y), 0.0)
	TestLib.check(car != null, "%s: the audit car is placed" % label)
	if car == null:
		return
	var d := route[1] - route[0]
	car.heading = atan2(-d.x, -d.y)
	car.rotation.y = car.heading
	car._heading_set = car.heading
	var gy := TerrainHeight.drive_height_at(start.x, start.y, 0.0) if (absf(start.x) > TerrainHeight.CITY_HALF or absf(start.y) > TerrainHeight.CITY_HALF) else 0.0
	car.global_position = Vector3(start.x, gy, start.y)
	p.teleport_to(car.global_position + Vector3(0.0, 1.0, 0.0))
	await TestLib.frames(host, 8)
	mgr.enter(car)
	await TestLib.frames(host, 4)
	var pilot := Pilot.new()
	pilot.start(car, route, speed)
	var t0 := audit.t
	var guard := 0
	while audit.t - t0 < secs and guard < 400000:
		guard += 1
		await host.get_tree().physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		if not Game.is_playing():
			Game.state = &"play"
		if p.hp < p.max_hp * 0.5:
			p.hp = p.max_hp
		if is_instance_valid(car) and not car.dead and car.hp < car.max_hp * 0.6:
			car.hp = car.max_hp                              # the audit is about traffic, not about the pilot's car surviving a wall
		if mgr.driven == null or not is_instance_valid(mgr.driven) or mgr.driven.dead:
			print("AUDIT stage '%s' ended early at %.0f s: the audit car %s" % [label, audit.t - t0, "was destroyed" if (is_instance_valid(car) and car.dead) else "is no longer driven"])
			break
		pilot.step(dt)
		audit.tick(dt)
		if verbose and fmod(audit.t, 10.0) < dt:
			var f := car.forward()
			var l := TrafficField.lead(car.global_position.x, car.global_position.z, f.x, f.z, float(car.spec["len"]) * 0.5, float(car.spec["wid"]) * 0.5, 40.0, TrafficField.REAL, car.field_slot, 0.5)
			if verbose and audit.t > 12.0 and audit.t < 28.0 and car.speed < 0.3:
				for j in NearTraffic.instance.count:
					var st := NearTraffic.instance.debug_state(j)
					var q := NearTraffic.instance.car_position(j)
					if int(st["alive"]) != 0 and Vector2(q.x - car.global_position.x, q.z - car.global_position.z).length() < 40.0:
						print("     near#%d (%.1f, %.1f) %s" % [j, q.x, q.z, str(st)])
			print("  t=%.0f car (%.0f, %.0f) h %.2f v %.1f lead gap %.1f v %.1f %s  near %s  jam breaks %d overlap kills %d" % [audit.t, car.global_position.x, car.global_position.z, car.heading, car.speed, l.x, l.y, str(TrafficField.describe_id(l.z)), str(TrafficField.flow(TrafficField.NEAR)), NearTraffic.instance.jam_breaks, NearTraffic.instance.overlap_kills])
	pilot.release()
	print("AUDIT stage '%s': %.0f m driven, %d laps, %d teleports, %d crashes of the audit car, hulls now %d (%d real, %d near, %d path, %d parked)" % [label, pilot.travelled, pilot.laps, pilot.teleports, car.crashes if is_instance_valid(car) else -1,
			TrafficField.live_count(), TrafficField.live_count(TrafficField.REAL), TrafficField.live_count(TrafficField.NEAR), TrafficField.live_count(TrafficField.PATH), TrafficField.live_count(TrafficField.PARKED)])
