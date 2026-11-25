extends RefCounted
## w123-clutter: street clutter never stands in front of a door. The real main scene at 844x390, phone HUD, REAL FINGERS (left thumb on the stick, right thumb turns the view),
## reward cards on (CrateReveal._quiet = 0).
##  1. every door within 200 m of the spawn (USE doors, walk-in shops, tower street doors) has a clear lane from the wall to the kerb: no solid street prop and no kerb car in it
##     (the wave 123 probe found 45 of 71 doors with a bollard, bin, antenna, planter, kiosk or kerb car in front);
##  2. for the 14 doors nearest the spawn the hero walks by the stick from the kerb straight to the door without being stopped;
##  3. a sidewalk walk along the spawn street has no stuck spot;
##  4. the street props still collide (a bench / bollard / planter in the pool stops a ball query) and stay MultiMesh + a constant collider pool (no node per prop).
## Run: tools/test.sh tests/test_clutter_w123.gd   (CLUTTER_OLD=1: the wave 122 street, checks 1 and 2 fail)
const TIMEOUT_SECONDS := 300
const Lib := preload("res://tests/w120_reach_lib.gd")
const C := preload("res://tests/w123_clutter_lib.gd")
var L: Lib


func run(h: Node) -> void:
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var s := Game.SPAWN
	var pcn := Game.world.get_node_or_null(^"PropColliders")
	var pc_nodes := 0 if pcn == null else pcn.find_children("*", "", true, false).size() + 1
	TestLib.check(Game.world.prop_colliders().bodies.size() == 56 and pc_nodes <= 113, "the street props keep the constant 56-body collider pool, no node per prop (%d nodes)" % pc_nodes)
	var doors := C.doors_near(s, 200.0)
	doors.sort_custom(func(a, b): return (a["wall"] as Vector3).distance_to(s) < (b["wall"] as Vector3).distance_to(s))
	var bad: Array = []
	for d in doors:
		await L.tp((d["wall"] as Vector3) + (d["n"] as Vector3) * 2.0 + Vector3(0, 0.5, 0), 0.0)      # stand there: the kerb cars of the cell are generated
		var bl := C.blockers(d)
		if not bl.is_empty():
			bad.append("%s: %s" % [d["what"], bl])
	TestLib.check(doors.size() >= 40, "there are doors near the spawn to check (%d)" % doors.size())
	TestLib.check(bad.is_empty(), "every door lane from the wall to the kerb is free of street props and kerb cars (%d of %d blocked: %s)" % [bad.size(), doors.size(), bad.slice(0, 6)])
	# 1b. no market stall on the bay edge in front of a door (it hides the door from the street)
	var lanes: Array = []
	for d in doors:
		lanes.append(d)
	var hidden: Array = []
	for site: Dictionary in StreetVendors.sites():
		var sp: Vector3 = site["pos"]
		if sp.distance_to(s) > 200.0:
			continue
		for d in lanes:
			var rel: Vector3 = sp - (d["wall"] as Vector3)
			rel.y = 0.0
			var n: Vector3 = d["n"]
			var o := rel.dot(n)
			if o > 0.0 and o < float(d["kerb"]) + 3.0 and absf(rel.dot(Vector3(-n.z, 0.0, n.x))) < 1.25 + 1.5:
				hidden.append("stall %s before %s" % [sp.snapped(Vector3.ONE * 0.1), d["what"]])
	TestLib.check(hidden.is_empty(), "no market stall stands in front of a door (%s)" % [hidden])
	# 2. by the stick from the kerb to the door
	var stuck: Array = []
	var walked := 0
	for d in doors:
		if walked >= 14:
			break
		var w: Vector3 = d["wall"]
		var n: Vector3 = d["n"]
		var kerb: float = d["kerb"]
		if kerb < 1.5:
			continue
		walked += 1
		var from := w + n * (kerb - 0.4)
		var to := w + n * 0.3
		await L.tp(from + Vector3(0, 0.3, 0), Lib.yaw_to(from, to))
		await L.secs(0.3)
		var r := await _straight(from, to, 6.0)
		if not r["ok"]:
			stuck.append("%s: %s" % [d["what"], r["why"]])
	TestLib.check(walked >= 10, "walked to %d doors" % walked)
	TestLib.check(stuck.is_empty(), "the stick takes the hero from the kerb STRAIGHT to every door: he reaches it and is never pushed more than 0.45 m off the door axis by a prop (%s)" % [stuck])
	# 3. a sidewalk walk along the spawn street
	var a := Vector3(-20.0, 0.3, 11.0)
	var b := Vector3(-100.0, 0.3, 11.0)
	await L.tp(a, Lib.yaw_to(a, b))
	var rw := await L.walk(b, 40.0, 2.0)
	TestLib.check(rw["reached"], "the sidewalk of the spawn street is walked end to end by the stick with no stuck spot (%.1f m short, %s)" % [rw["dist"], (rw["block"] as Array).map(func(x): return x["what"])])
	# 4. props collide, budget
	var pc = Game.world.prop_colliders()
	await L.tp(Vector3(-60.0, 0.3, 11.0), 0.0)
	await L.secs(0.5)
	var hit := 0
	var tried := 0
	var ss := L.p.get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = 0.2
	for body: StaticBody3D in pc.bodies:
		if tried >= 8 or body.global_position.y < -100.0:
			continue
		var id: int = pc._assigned[pc.bodies.find(body)]
		if id < 0:
			continue
		var fam: String = pc._spec_list[pc._spec[id]][3]
		if not (fam.contains("Bench") or fam.contains("Bollard") or fam.contains("Planter") or fam.contains("Bin") or fam == "Hydrants" or fam == "Lamps"):
			continue
		tried += 1
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = ball
		q.collision_mask = Game.L_WORLD
		q.transform = Transform3D(Basis(), (pc._xf[id] as Transform3D).origin + Vector3(0, 0.5, 0))
		if not ss.intersect_shape(q, 2).is_empty():
			hit += 1
	TestLib.check(tried >= 3 and hit == tried, "street furniture near the hero (benches, bollards, planters, bins, hydrants, lamps) is solid (%d of %d)" % [hit, tried])
	await L.finish()


## The left thumb pushes forward (the right thumb re-aims the view at the door when it drifts). Reached within 0.6 m, never more than 0.45 m off the line from -> to.
func _straight(from: Vector3, to: Vector3, limit: float) -> Dictionary:
	var axis := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	var side := Vector3(-axis.z, 0.0, axis.x)
	var worst := 0.0
	L.fg.stick(Vector2(0.0, -0.8))
	var t := 0.0
	var ok := false
	while t < limit:
		await L.secs(0.1)
		t += 0.1
		var gp := L.p.global_position
		worst = maxf(worst, absf(Vector3(gp.x - from.x, 0.0, gp.z - from.z).dot(side)))
		if Lib.flat(gp, to) < 0.6:
			ok = true
			break
		var err := wrapf(Lib.yaw_to(gp, to) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.15:
			L.fg.look(-err * 160.0, 0.0, 3)
	L.fg.stick(Vector2.ZERO)
	var gp2 := L.p.global_position
	if ok and worst <= 0.45:
		return {"ok": true}
	return {"ok": false, "why": "%s, %.1f m short, %.2f m off the axis" % ["reached" if ok else "not reached", Lib.flat(gp2, to), worst]}
