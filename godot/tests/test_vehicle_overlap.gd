extends RefCounted
## Cars inside cars (owner round 6: "cars go inside other cars"): the hull registry (TrafficField) and every rule that keeps two vehicles apart, on the real scene.
##  * pure: the oriented-box test against an independent corner implementation, the corridor lead (a car ahead, the next lane, a parked car beside the lane, an oncoming car), the safe-distance
##    rule (a follower that obeys it never touches a leader that brakes as hard as it can);
##  * spawn placement on the real VehicleManager: cars asked for at the same spot, in the same lane, on a car already standing there;
##  * real crashes by hand-stepped physics: a sedan into a standing SUV (the hulls leave each other at once, both are hurt, the drivers hoot), a lane car that comes up behind a stopped car (it brakes
##    and never touches), two lane cars pushed into each other (the manager separates them);
##  * the live game at 4x speed in the market street and on the north highway, with the audit of tests/traffic_audit.gd (no pair of hulls overlaps for longer than 0.3 s) and the bridge cars.
## The long run is tools/traffic_audit.sh (5 minutes, city and highways, a bot that drives).
## Run: tools/test.sh tests/test_vehicle_overlap.gd

const TA := preload("res://tests/traffic_audit.gd")
const K := 4
const DT := 1.0 / 60.0
const TIMEOUT_SECONDS := 170

var host: Node
var p: Player
var mgr: VehicleManager
var city: City


func run(h: Node) -> void:
	host = h
	seed(11)
	Sfx.muted = true
	_geometry()
	_lead()
	_brain()
	await _real()


# --- pure: the hulls ---------------------------------------------------------------------------------------------------------------------------

## An independent overlap test (corners and the four edge normals): the depth of the shallowest axis, negative when the boxes are apart.
static func _sat(ax: float, az: float, afx: float, afz: float, ahl: float, ahw: float, bx: float, bz: float, bfx: float, bfz: float, bhl: float, bhw: float) -> float:
	var axes := [Vector2(afx, afz), Vector2(-afz, afx), Vector2(bfx, bfz), Vector2(-bfz, bfx)]
	var best := INF
	for u: Vector2 in axes:
		var ca := Vector2(ax, az).dot(u)
		var cb := Vector2(bx, bz).dot(u)
		var ra := 0.0
		var rb := 0.0
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pa: Vector2 = Vector2(afx, afz) * (ahl * sz) + Vector2(-afz, afx) * (ahw * sx)
				var pb: Vector2 = Vector2(bfx, bfz) * (bhl * sz) + Vector2(-bfz, bfx) * (bhw * sx)
				ra = maxf(ra, absf(pa.dot(u)))
				rb = maxf(rb, absf(pb.dot(u)))
		best = minf(best, ra + rb - absf(ca - cb))
	return best


func _geometry() -> void:
	TrafficField.reset()
	# hand-made pairs: nose to tail, side by side, a T bone
	var d1 := TrafficField.obb_depth(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 0.0, -4.0, 0.0, -1.0, 2.3, 0.95)
	var d2 := TrafficField.obb_depth(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 0.0, -4.7, 0.0, -1.0, 2.3, 0.95)
	var d3 := TrafficField.obb_depth(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 1.8, 0.0, 0.0, -1.0, 2.3, 0.95)
	var d4 := TrafficField.obb_depth(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 5.0, 0.0, 0.0, -1.0, 2.3, 0.95)
	var d5 := TrafficField.obb_depth(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 0.0, -3.2, 1.0, 0.0, 2.3, 0.95)
	var d6 := TrafficField.obb_depth(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 0.0, -3.4, 1.0, 0.0, 2.3, 0.95)
	TestLib.check(d1 > 0.55 and d1 < 0.65, "two cars 4 m apart nose to tail overlap by 0.6 m (%.2f)" % d1)
	TestLib.check(d2 <= 0.0 and d4 <= 0.0, "4.7 m nose to tail and 5 m side by side (the next lane) do not overlap (%.2f, %.2f)" % [d2, d4])
	TestLib.check(d3 > 0.05 and d3 < 0.15, "two cars 1.8 m side by side overlap by 10 cm (%.2f)" % d3)
	TestLib.check(d5 > 0.0 and d6 <= 0.0, "a car across the road 3.2 m ahead touches, 3.4 m does not (%.2f, %.2f)" % [d5, d6])
	# 600 random pairs against the independent test (the pairs very close to touching are skipped: rounding)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var wrong := 0
	var tested := 0
	var asym := 0.0
	for n in 600:
		var ya := rng.randf() * TAU
		var yb := rng.randf() * TAU
		var ax := rng.randf_range(-4.0, 4.0)
		var az := rng.randf_range(-4.0, 4.0)
		var ahl := rng.randf_range(1.8, 4.8)
		var ahw := rng.randf_range(0.8, 1.3)
		var bhl := rng.randf_range(1.8, 4.8)
		var bhw := rng.randf_range(0.8, 1.3)
		var afx := -sin(ya)
		var afz := -cos(ya)
		var bfx := -sin(yb)
		var bfz := -cos(yb)
		var got := TrafficField.obb_depth(0.0, 0.0, afx, afz, ahl, ahw, ax, az, bfx, bfz, bhl, bhw)
		var want := _sat(0.0, 0.0, afx, afz, ahl, ahw, ax, az, bfx, bfz, bhl, bhw)
		var back := TrafficField.obb_depth(ax, az, bfx, bfz, bhl, bhw, 0.0, 0.0, afx, afz, ahl, ahw)
		asym = maxf(asym, absf(got - back))
		if absf(want) > 0.03:
			tested += 1
			if (got > 0.0) != (want > 0.0):
				wrong += 1
	TestLib.check(tested > 300 and wrong == 0, "the hull test agrees with an independent corner test on %d random pairs (%d wrong)" % [tested, wrong])
	TestLib.check(asym < 0.001, "the depth does not depend on which hull is asked first (%.4f)" % asym)
	# the registry: put, find the pair, remove
	var a := TrafficField.alloc(TrafficField.NEAR)
	var b := TrafficField.alloc(TrafficField.REAL)
	TrafficField.put(TrafficField.NEAR, a, 100.0, 100.0, 0.0, -1.0, 2.3, 0.95, 5.0, TrafficField.F_AI)
	TrafficField.put(TrafficField.REAL, b, 100.0, 103.5, 0.0, -1.0, 2.3, 0.95, 5.0, TrafficField.F_AI)
	var out: Array = []
	TrafficField.pairs(0.1, out)
	TestLib.check(out.size() == 1 and float(out[0][4]) > 1.0, "the registry finds the one overlapping pair across two sources (%d)" % out.size())
	TrafficField.put(TrafficField.REAL, b, 100.0, 110.0, 0.0, -1.0, 2.3, 0.95, 5.0, TrafficField.F_AI)
	out.clear()
	TrafficField.pairs(0.1, out)
	TestLib.check(out.is_empty(), "moved apart the pair is gone")
	TestLib.check(not TrafficField.clear(100.0, 101.0, 0.0, -1.0, 2.3, 0.95, 0.5) and TrafficField.clear(100.0, 120.0, 0.0, -1.0, 2.3, 0.95, 0.5), "clear() sees the hull of a car and the free road behind it")
	TrafficField.release(TrafficField.NEAR, a)
	TrafficField.release(TrafficField.REAL, b)
	TestLib.check(TrafficField.live_count() == 0, "released hulls leave the registry")
	TrafficField.reset()


func _lead() -> void:
	TrafficField.reset()
	var ahead := TrafficField.alloc(TrafficField.NEAR)
	TrafficField.put(TrafficField.NEAR, ahead, 0.0, -15.0, 0.0, -1.0, 2.3, 0.95, 8.0, TrafficField.F_AI)
	var l := TrafficField.lead(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 40.0)
	TestLib.check(absf(l.x - 10.4) < 0.05 and absf(l.y - 8.0) < 0.05, "the car 15 m ahead is a lead 10.4 m bumper to bumper, going 8 m/s (gap %.2f, v %.2f)" % [l.x, l.y])
	TestLib.check(TrafficField.lead(0.0, -30.0, 0.0, 1.0, 2.3, 0.95, 40.0).x == INF or TrafficField.lead(0.0, -30.0, 0.0, 1.0, 2.3, 0.95, 4.0).x == INF, "nothing is ahead of a car that faces away (or beyond its look)")
	TrafficField.put(TrafficField.NEAR, ahead, 5.0, -15.0, 0.0, -1.0, 2.3, 0.95, 8.0, TrafficField.F_AI)
	TestLib.check(TrafficField.lead(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 40.0).x == INF, "a car in the next lane (5 m across) is not a lead")
	TrafficField.put(TrafficField.NEAR, ahead, 0.0, -20.0, 0.0, 1.0, 2.3, 0.95, 9.0, TrafficField.F_AI)
	var oc := TrafficField.lead(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 40.0)
	TestLib.check(oc.x < 16.0 and oc.y < -8.0, "a car coming head on in the same lane is a lead with a negative closing speed (gap %.1f, v %.1f)" % [oc.x, oc.y])
	TrafficField.put(TrafficField.NEAR, ahead, 2.7, -15.0, 0.0, -1.0, 2.3, 0.95, 0.0, TrafficField.F_STATIC)
	TestLib.check(TrafficField.lead(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 40.0).x == INF, "a parked car 2.7 m beside the lane is passed, not waited for")
	TrafficField.put(TrafficField.NEAR, ahead, 0.9, -15.0, 0.0, -1.0, 2.3, 0.95, 0.0, TrafficField.F_STATIC)
	TestLib.check(TrafficField.lead(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 40.0).x < 12.0, "a stopped car 0.9 m off the lane centre is in the way")
	TrafficField.put(TrafficField.NEAR, ahead, 0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 0.0, 0)
	var own := TrafficField.lead(0.0, 0.0, 0.0, -1.0, 2.3, 0.95, 40.0, TrafficField.NEAR, ahead)
	TestLib.check(own.x == INF, "a car does not see its own hull")
	TrafficField.reset()


# --- pure: the safe-distance rule ------------------------------------------------------------------------------------------------------------------

func _brain() -> void:
	var prev := 0.0
	var mono := true
	for g in range(0, 80, 2):
		var v := TrafficBrain.safe_speed(float(g), 0.0)
		if v < prev - 0.001:
			mono = false
		prev = v
	TestLib.check(mono and TrafficBrain.safe_speed(TrafficBrain.STANDSTILL - 0.1, 10.0) == 0.0, "the safe speed grows with the gap and is zero inside the standstill gap")
	TestLib.check(TrafficBrain.safe_speed(40.0, 12.0) > TrafficBrain.safe_speed(40.0, 0.0), "a leader that moves allows a higher speed than one that stands")
	# a follower obeys the rule for every tick while the leader brakes as hard as the rule assumes: the bumpers never meet
	var worst := INF
	var worst_case := ""
	for v0 in [8.0, 14.0, 22.0, 30.0]:
		for vl0 in [0.0, 5.0, 12.0]:
			var vl: float = minf(vl0, v0)
			var lo := 0.0
			var hi := 200.0
			for it in 40:                                              # the gap at which the rule allows exactly v0
				var mid := (lo + hi) * 0.5
				if TrafficBrain.safe_speed(mid, vl) < v0:
					lo = mid
				else:
					hi = mid
			var gap := hi + 0.3
			var vf: float = v0
			var vlead: float = vl
			var min_gap := gap
			for step in 2000:
				vlead = maxf(vlead - TrafficBrain.LEAD_BRAKE * 0.02, 0.0)         # the leader brakes at the rule's own assumption
				gap += (vlead - vf) * 0.02
				vf = TrafficBrain.approach(vf, TrafficBrain.safe_speed(gap, vlead), 0.02, TrafficBrain.ACCEL_TO)
				min_gap = minf(min_gap, gap)
			if min_gap < worst:
				worst = min_gap
				worst_case = "v %.0f behind %.0f" % [v0, vl]
	TestLib.check(worst > 0.5, "a follower that obeys the safe speed never touches a leader that brakes hard (closest %.2f m, %s)" % [worst, worst_case])


# --- the real scene -----------------------------------------------------------------------------------------------------------------------------------

func _real_pairs(min_depth := 0.05) -> int:
	var out: Array = []
	TrafficField.pairs(min_depth, out)
	var n := 0
	for q: Array in out:
		if int(q[0]) == TrafficField.REAL and int(q[2]) == TrafficField.REAL:
			n += 1
	return n


func _real() -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	MapScreen.path_override = "user://test_vehicle_overlap_map_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(MapScreen.path_override)
	CarRadio.auto_headless = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(city != null and p != null and mgr != null and city.ambient != null, "the real scene has a city, a player, a vehicle manager and the ambient traffic")
	if city == null or p == null or mgr == null or city.ambient == null:
		return
	p.set_physics_process(true)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	await _spawns()
	await _crashes()
	await _live_slices()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	CarRadio.auto_headless = false
	main.queue_free()


## A fresh real car of `kind`, standing at `pos` facing `heading`, placed exactly (the manager's own nudging is bypassed) and ready for manual stepping.
func _car(kind: StringName, pos: Vector3, heading: float) -> Vehicle:
	while mgr.list.size() >= mgr.cap():
		mgr._release(mgr.list[0])
	var v := mgr.spawn_parked(kind, pos, heading)
	if v == null:
		return null
	v.global_position = pos
	v.heading = heading
	v.rotation = Vector3(0.0, heading, 0.0)
	v._heading_set = heading
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.yaw_rate = 0.0
	v.publish_hull()
	return v


func _clear_cars() -> void:
	for v in mgr.list.duplicate():
		if v != mgr.starter and is_instance_valid(v) and not v.driver_is_player:
			mgr._release(v)


func _spawns() -> void:
	TrafficField.bare_street()
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	mgr.lights_on = false
	_clear_cars()
	var c0 := CityLayout.road_center(NearTraffic.AVENUE)               # the market avenue, z = 0 side
	var spot := Vector3(-300.0, 0.0, c0 + CityLayout.LANE)
	p.teleport_to(spot + Vector3(0.0, 0.1, -14.0))
	await TestLib.frames(host, 4)
	var made: Array[Vehicle] = []
	for n in 5:                                                      # five cars asked for at the very same spot
		var v := mgr.spawn_parked(&"sedan", spot, -PI * 0.5)
		if v != null:
			made.append(v)
	TestLib.check(made.size() >= 4, "five cars asked for at one spot: a place is found for at least four (%d)" % made.size())
	TestLib.check(_real_pairs() == 0, "and none of the cars placed overlaps another (%d overlapping pairs)" % _real_pairs())
	var far := 0.0
	for v in made:
		far = maxf(far, v.global_position.distance_to(spot))
	TestLib.check(far >= 4.5, "the later cars were nudged along the road (the farthest stands %.1f m from the spot)" % far)
	_clear_cars()
	# lane cars asked for at the same coordinate of the same lane: each slides along its lane to a free place
	var lane: Array[Vehicle] = []
	for n in 4:
		var t := mgr.spawn_traffic(&"sedan" if n % 2 == 0 else &"suv", 0, NearTraffic.AVENUE, 1, -300.0)
		if t != null:
			lane.append(t)
	var lane_ok := lane.size() >= 3
	for t in lane:
		lane_ok = lane_ok and absf(t.ai_line - (c0 + VehicleSpecs.lane_offset(0, 1, Game.LANE))) < 0.01
	TestLib.check(lane_ok and _real_pairs() == 0, "four lane cars asked for at one coordinate of one lane stand clear of each other, each in its own lane (%d placed, %d overlapping)" % [lane.size(), _real_pairs()])
	_clear_cars()
	# a car asked for on top of a standing truck is not placed inside it
	var blocker := _car(&"truck", spot + Vector3(40.0, 0.0, 0.0), -PI * 0.5)
	var onto := mgr.spawn_parked(&"sedan", blocker.global_position + Vector3(0.5, 0.0, 0.0), -PI * 0.5) if blocker != null else null
	TestLib.check(blocker != null and _real_pairs() == 0, "a car asked for on top of a standing truck is placed clear of it (%s, %d overlapping pairs)" % ["placed beside it" if onto != null else "refused", _real_pairs()])
	_clear_cars()


func _step_all(secs: float, a: Vehicle = null, b: Vehicle = null, on_step := Callable()) -> void:
	for i in int(ceil(secs / DT)):
		for v in mgr.list.duplicate():
			if is_instance_valid(v) and v.active:
				if v == a:
					v.step_drive(DT, 0.0, 0.0, false)
					v._sync(DT)
					v.publish_hull()
				else:
					v.sim(DT)
		mgr._collide_all()
		if on_step.is_valid():
			on_step.call()


func _crashes() -> void:
	TrafficField.bare_street()
	mgr.set_physics_process(false)
	var ave := 5.0
	p.teleport_to(Vector3(-133.0, 0.0, ave - 12.0))                # the manager only tests the pairs near the player
	await TestLib.frames(host, 2)
	# ---- ramming: a sedan at 16 m/s into the middle of a standing SUV
	_clear_cars()
	var a := _car(&"sedan", Vector3(-140.0, 0.0, ave), -PI * 0.5)
	var b := _car(&"suv", Vector3(-126.0, 0.0, ave), -PI * 0.5)
	if a == null or b == null:
		TestLib.check(false, "two cars for the ram")
		mgr.set_physics_process(true)
		return
	a.collision_mask = Game.L_WORLD
	b.collision_mask = Game.L_WORLD
	a.vel = a.forward() * 16.0
	a.speed = 16.0
	var hp_a := a.hp
	var hp_b := b.hp
	var ovl := {"t": 0.0, "worst_run": 0.0, "deepest": 0.0}
	var sample := func() -> void:
		var d := TrafficField.obb_depth(a.global_position.x, a.global_position.z, a.forward().x, a.forward().z, float(a.spec["len"]) * 0.5, float(a.spec["wid"]) * 0.5,
				b.global_position.x, b.global_position.z, b.forward().x, b.forward().z, float(b.spec["len"]) * 0.5, float(b.spec["wid"]) * 0.5)
		if d > 0.1:
			ovl["t"] = float(ovl["t"]) + DT
			ovl["worst_run"] = maxf(float(ovl["worst_run"]), float(ovl["t"]))
			ovl["deepest"] = maxf(float(ovl["deepest"]), d)
		else:
			ovl["t"] = 0.0
	_step_all(3.0, a, b, sample)
	TestLib.check(hp_a - a.hp > 1.0 and hp_b - b.hp > 1.0, "ramming hurts both cars (%.0f and %.0f hp lost)" % [hp_a - a.hp, hp_b - b.hp])
	TestLib.check(float(ovl["worst_run"]) <= 0.1, "the hulls leave each other at once: the longest run inside each other is %.2f s (deepest %.2f m)" % [float(ovl["worst_run"]), float(ovl["deepest"])])
	TestLib.check(a.horns + b.horns >= 1, "the drivers of a hard crash sound their horns (%d)" % (a.horns + b.horns))
	TestLib.check(b.global_position.x > -126.0 + 0.5 and a.speed < 6.0, "the SUV is shoved on and the sedan is stopped (SUV moved %.1f m, sedan %.1f m/s)" % [b.global_position.x + 126.0, a.speed])
	# ---- being rammed: a lane car comes up behind a stopped car in its lane: it brakes and never touches
	_clear_cars()
	mgr.lights_on = false
	var c0 := CityLayout.road_center(NearTraffic.AVENUE)
	var line := c0 + VehicleSpecs.lane_offset(0, 1, Game.LANE)
	p.teleport_to(Vector3(-205.0, 0.0, line - 14.0))
	await TestLib.frames(host, 2)
	var stopped := _car(&"suv", Vector3(-200.0, 0.0, line), -PI * 0.5)
	var follower := mgr.spawn_traffic(&"sedan", 0, NearTraffic.AVENUE, 1, -260.0)
	if stopped == null or follower == null:
		TestLib.check(false, "a stopped car and a lane car behind it")
		mgr.set_physics_process(true)
		return
	follower.ai_cruise = 15.0
	follower.ai_cool = 1.0e6                                          # no turn at the junction in between: it drives straight on
	follower.ai_speed = 15.0
	follower.speed = 15.0
	follower.vel = follower.forward() * 15.0
	var touch := {"min_gap": INF, "overlap": 0.0}
	var watch := func() -> void:
		var d := TrafficField.obb_depth(follower.global_position.x, follower.global_position.z, follower.forward().x, follower.forward().z, float(follower.spec["len"]) * 0.5, float(follower.spec["wid"]) * 0.5,
				stopped.global_position.x, stopped.global_position.z, stopped.forward().x, stopped.forward().z, float(stopped.spec["len"]) * 0.5, float(stopped.spec["wid"]) * 0.5)
		if d > 0.02:
			touch["overlap"] = float(touch["overlap"]) + DT
		var gap := stopped.global_position.x - follower.global_position.x - float(stopped.spec["len"]) * 0.5 - float(follower.spec["len"]) * 0.5
		touch["min_gap"] = minf(float(touch["min_gap"]), gap)
	_step_all(9.0, null, null, watch)
	var final_gap := stopped.global_position.x - follower.global_position.x - float(stopped.spec["len"]) * 0.5 - float(follower.spec["len"]) * 0.5
	TestLib.check(float(touch["overlap"]) == 0.0 and float(touch["min_gap"]) > 0.3, "a lane car arriving at 15 m/s behind a stopped car brakes in time (closest %.1f m, %.2f s inside)" % [float(touch["min_gap"]), float(touch["overlap"])])
	TestLib.check(absf(follower.speed) < 0.6 and final_gap > 1.0 and final_gap < 9.0 and follower.crashes == 0, "and waits behind it (%.1f m gap, %.2f m/s, %d crashes)" % [final_gap, follower.speed, follower.crashes])
	# ---- two lane cars pushed into each other (a spawn on a spawn, a teleport): the manager separates them
	_clear_cars()
	p.teleport_to(Vector3(-405.0, 0.0, line - 14.0))
	await TestLib.frames(host, 2)
	var t1 := mgr.spawn_traffic(&"sedan", 0, NearTraffic.AVENUE, 1, -400.0)
	var t2 := mgr.spawn_traffic(&"suv", 0, NearTraffic.AVENUE, 1, -380.0)
	if t1 == null or t2 == null:
		TestLib.check(false, "two lane cars")
		mgr.set_physics_process(true)
		return
	t2.global_position = t1.global_position + t1.forward() * 1.6
	t2.publish_hull()
	t1.publish_hull()
	var before := mgr.lane_overlaps
	_step_all(2.5)
	var gone := not (is_instance_valid(t1) and t1.active) or not (is_instance_valid(t2) and t2.active)
	var still := false
	if not gone:
		still = TrafficField.obb_depth(t1.global_position.x, t1.global_position.z, t1.forward().x, t1.forward().z, float(t1.spec["len"]) * 0.5, float(t1.spec["wid"]) * 0.5,
				t2.global_position.x, t2.global_position.z, t2.forward().x, t2.forward().z, float(t2.spec["len"]) * 0.5, float(t2.spec["wid"]) * 0.5) > 0.1
	TestLib.check(mgr.lane_overlaps > before and (gone or not still), "two lane cars pushed into each other are separated (or one is removed): %d resolved, %s" % [mgr.lane_overlaps - before, "one removed" if gone else "both stand clear"])
	_clear_cars()
	mgr.set_physics_process(true)


# --- the live game at 4x with the audit ----------------------------------------------------------------------------------------------------------------

func _settle(pos: Vector3) -> void:
	if city.terrain != null:
		city.terrain.settle(pos)
	if city.vegetation != null:
		city.vegetation.settle(pos)


func _audit_slice(label: String, secs: float, expect_hulls: int) -> TA.Audit:
	var audit := TA.Audit.new()
	var guard := 0
	while audit.t < secs and guard < 200000:
		guard += 1
		await host.get_tree().physics_frame
		if not Game.is_playing():
			Game.state = &"play"
		p.hp = p.max_hp
		audit.tick(1.0 / float(Engine.physics_ticks_per_second))
	audit.finish()
	TestLib.check(audit.passed(), "%s: no two hulls overlap for longer than 0.3 s in %.0f s of live traffic (%d long overlaps, longest %.2f s, deepest %.2f m, %d brief ones)" % [label, audit.t, audit.violations.size(), audit.longest, audit.deepest, audit.events])
	if not audit.passed():
		print(audit.report())
	TestLib.check(audit.max_hulls >= expect_hulls, "%s: the audit really saw traffic (%d hulls at most, expected %d+)" % [label, audit.max_hulls, expect_hulls])
	return audit


func _live_slices() -> void:
	# the market street at the spawn: the whole traffic of the city (near cars, parked cars, real cars)
	mgr.set_physics_process(true)
	mgr.stream_every = VehicleSpecs.STREAM_EVERY
	mgr.lights_on = true
	_clear_cars()
	var nt: NearTraffic = city.ambient.near_traffic
	nt.enabled = true
	if ParkedCars.instance != null:
		ParkedCars.instance.enabled = true
	if RoadTraffic.instance != null:
		RoadTraffic.instance.enabled = true
	Game.set_quality(1)
	nt.set_tier(1, 1.0)
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	var t_end := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < t_end and nt.alive_count() < 20:
		await TestLib.frames(host, 4)
	var city_audit: TA.Audit = await _audit_slice("market street", 24.0, 40)
	TestLib.check(float(city_audit.near_total) / maxf(float(city_audit.near_samples), 1.0) >= 15.0, "the street the audit watched held 15+ near cars on average (%.1f)" % (float(city_audit.near_total) / maxf(float(city_audit.near_samples), 1.0)))
	# the north highway with its road traffic and the bridges
	RoadLanes.ensure()
	var rt: RoadTraffic = city.ambient.road_traffic
	var sm := RoadLanes.sample(0, 520.0)
	var tg := Vector2(sm[2], sm[3])
	var verge := Vector2(sm[0], sm[1]) + Vector2(-tg.y, tg.x) * 9.0
	var pos := Vector3(verge.x, TerrainHeight.height_at(verge.x, verge.y) + 1.0, verge.y)
	_settle(pos)
	p.teleport_to(pos)
	await TestLib.frames(host, 6)
	t_end = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < t_end and rt.alive_count() < 5:
		await TestLib.frames(host, 4)
	TestLib.check(rt.alive_count() >= 5, "traffic drives on the north highway around the hero (%d road cars)" % rt.alive_count())
	await _audit_slice("north highway", 24.0, 8)
