extends RefCounted
## WAVE 121 FLOORS (owner round 7: "building detail and interiors with stairs"). The real main scene, the phone HUD, REAL FINGERS only (the left thumb on the stick, view swipes,
## JUMP: tests/w116_fingers.gd through tests/w120_reach_lib.gd), the phone-only layers on (CrateReveal._quiet = 0). Start points are set up by teleport; every move is a finger.
##   in      from the sidewalk by the stick through the street door of a tall building into its lobby (no USE button, no black frame, no room far away)   [old fails: facade wall]
##   up      up the stairwell to floor 3 (real steps, never under a floor, never stuck) and out onto the floor, rooms there                               [old fails]
##   roof    on up to the roof, out of the stair house door, standing on the roof at the building's height                                             [old fails]
##   down    back down the same stairs to the street floor and out of the street door onto the sidewalk                                                [old fails]
##   leak    10 more entries (walk in, leave): node count and the tower's colliders back to where they were                                           [old fails: no entry]
## FLOORS_OLD=1 = the wave 120 buildings (TowerFloors.enabled false). Run: tools/test.sh tests/test_floors_w121.gd
const TIMEOUT_SECONDS := 150
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib
var tw: Dictionary = {}
var worst_under := 0.0


func run(h: Node) -> void:
	TowerFloors.enabled = OS.get_environment("FLOORS_OLD") != "1"
	h.get_tree().root.size = Vector2i(844, 390)                     # integrator w121: the owner's phone (on the square test window GRAB stood on the stick: a test-window artefact)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	TestLib.check(tf != null, "the walk-in tower module is in the main scene")
	if tf == null:
		await L.finish()
		return
	var kinds := {}
	tf.nearest(Game.SPAWN)
	for t in tf.towers:
		kinds[t["kind"]] = true
	TestLib.check(TowerFloors.enabled and kinds.size() >= 3, "tall buildings of 3 kinds can be walked into (%s, %d towers)" % [kinds.keys(), tf.towers.size()])
	tw = tf.nearest(Game.SPAWN)
	var lot: CityLayout.Lot = tw["lot"]
	print("tower lot %d %s %.0f x %.0f x %.0f m at (%.0f, %.0f)" % [lot.index, tw["kind"], lot.w, lot.d, lot.h, lot.cx, lot.cz])
	await _in()
	await _up()
	await _down()
	await _leak()
	TowerFloors.enabled = true
	await L.finish()


func _route(level: int) -> Array[Vector3]:
	var tf := TowerFloors.instance
	if tf._cur.is_empty():
		tf.open(tw)                 # old code never opens: the same geometry is used only to know where to walk
		var r := tf.route(level)
		tf.close()
		return r
	return tf.route(level)


func _follow(pts: Array[Vector3], what: String) -> bool:
	for i in pts.size():
		var q := pts[i]
		var r := await _step(q, 9.0)
		var gp := L.p.global_position
		worst_under = maxf(worst_under, q.y - 1.2 - gp.y if i > 1 else 0.0)
		if not r["reached"]:
			print("  %s: point %d %s not reached (hero %s, %.1f m short, block %s)" % [what, i, q, gp, r["dist"], r["block"]])
			return false
	return true


## One stair point by fingers: the right thumb turns the view toward it first (stick released), then the left thumb pushes; never more than 25 degrees off.
func _step(q: Vector3, limit: float) -> Dictionary:
	var t := 0.0
	var pushing := false
	var still := 0.0
	var last := L.p.global_position
	while t < limit:
		var gp := L.p.global_position
		if Lib.flat(gp, q) < 0.45:
			L.fg.stick(Vector2.ZERO)
			return {"reached": true, "dist": 0.0, "block": []}
		var err := wrapf(Lib.yaw_to(gp, q) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.42 or (not pushing and absf(err) > 0.15):
			if pushing:
				L.fg.stick(Vector2.ZERO)
				pushing = false
			L.fg.look(-err * 160.0, 0.0, 4)
			await L.f(3)
			t += 0.1
			continue
		if not pushing:
			L.fg.stick(Vector2(0.0, -0.6))
			pushing = true
		await L.secs(0.1)
		t += 0.1
		if absf(err) > 0.2:
			L.fg.look(-err * 160.0, 0.0, 3)
		var mv := Lib.flat(L.p.global_position, last)
		last = L.p.global_position
		still = still + 0.1 if mv < 0.03 else 0.0
		if still > 1.5:
			break
	L.fg.stick(Vector2.ZERO)
	var col := L.p.get_last_slide_collision()
	return {"reached": false, "dist": Lib.flat(L.p.global_position, q), "block": [str((col.get_collider_shape() as Node).name) if col != null and col.get_collider_shape() is Node else "-"]}


func _in() -> void:
	var door := TowerFloors.door_pos(tw, 4.0)
	var pts := _route(0)
	await L.tp(door, Lib.yaw_to(door, pts[0]))
	var frames0 := Engine.get_frames_drawn()
	var r := await L.walk(pts[0], 10.0, 0.6, 0.8)
	var gp := L.p.global_position
	TestLib.check(r["reached"] and TowerFloors.inside(gp) and absf(gp.y) < 0.5, "by the stick from the sidewalk through the street door into the lobby (hero %s, block %s) [old fails: the facade]" % [gp, r["block"]])
	TestLib.check(TowerFloors.inside(gp) and not InteriorGameplay.active and not InteriorGameplay.instance.is_fading() and Engine.get_frames_drawn() >= frames0, "no USE door, no fade, no room far away: he stands in the building itself [old fails]")
	var lot: CityLayout.Lot = tw["lot"]
	TestLib.check(TowerFloors.open_lot == lot.index and Vector2(gp.x, gp.z).distance_to(Vector2(lot.cx, lot.cz)) < maxf(lot.w, lot.d), "the inside is where the outside is, the same size (open lot %d)" % TowerFloors.open_lot)


func _up() -> void:
	var tf := TowerFloors.instance
	var ok := await _follow(_route(3).slice(1), "up")
	var gp := L.p.global_position
	var lv := tf._levels if not tf._levels.is_empty() else TowerFloors.levels_of(tw["lot"])
	TestLib.check(ok and absf(gp.y - lv[3]) < 0.6 and tf.floor_of(gp.y) == 3, "up the stairs by the stick to floor 3 (hero y %.2f, floor 3 at %.2f, floor %d) [old fails]" % [gp.y, lv[3], tf.floor_of(gp.y)])
	TestLib.check(ok and worst_under < 0.3, "never under a floor on the way up (worst %.2f m)" % worst_under)
	# floor 3: walk into the open floor, its rooms are built
	var mid := TowerFloors.at(tw, TowerFloors.inner_u(tw) * 0.5, TowerFloors.SHAFT_W + 2.5, lv[3])
	var r := await L.walk(mid, 6.0, 0.8, 0.8)
	TestLib.check(r["reached"] and absf(L.p.global_position.y - lv[3]) < 0.5 and tf._room_body != null and tf._room_body.get_child_count() > 4, "out on floor 3 among its rooms (%d room colliders)" % (tf._room_body.get_child_count() if tf._room_body != null else 0))
	# on to the roof
	var top := lv.size() - 1
	var back := _route(3)
	ok = await _follow([back[back.size() - 1]] as Array[Vector3] + _route(top).slice(2 + 5 * 3), "roof")
	var out := TowerFloors.at(tw, TowerFloors.LAND * 0.5 + 3.0, TowerFloors.SHAFT_W + 4.0, lv[top])
	r = await L.walk(out, 6.0, 0.6, 0.8)
	gp = L.p.global_position
	var lot: CityLayout.Lot = tw["lot"]
	TestLib.check(ok and r["reached"] and absf(gp.y - lot.h) < 0.5 and not TowerFloors.inside(gp), "up to the roof and out of the stair house door: on the roof at the building's height %.1f m (hero y %.2f) [old fails]" % [lot.h, gp.y])
	await L.secs(1.0)
	TestLib.check(absf(L.p.global_position.y - lot.h) < 0.5, "he still stands on the roof a second later (y %.2f)" % L.p.global_position.y)


func _down() -> void:
	var tf := TowerFloors.instance
	var lv := tf._levels if not tf._levels.is_empty() else TowerFloors.levels_of(tw["lot"])
	var top := lv.size() - 1
	var up := _route(top)
	var pts: Array[Vector3] = [up[up.size() - 1]]
	var stairs := up.slice(2, up.size() - 1)
	stairs.reverse()
	for q in stairs:
		pts.append(q)
	pts.append(up[1])
	pts.append(up[0])
	var ok := await _follow(pts, "down")
	var door := TowerFloors.door_pos(tw, 3.0)
	var r := await L.walk(door, 8.0, 0.8, 0.8)
	var gp := L.p.global_position
	TestLib.check(ok and r["reached"] and absf(gp.y) < 0.4 and not TowerFloors.inside(gp), "down every flight to the street floor and out of the street door onto the sidewalk (hero %s) [old fails]" % gp)
	TestLib.check(ok and worst_under < 0.3, "never under a floor on the whole climb (worst %.2f m)" % worst_under)


## The node count of the game WITHOUT the street population (w125-ci): the live vehicles (VehicleManager) and the enemies (EnemyManager's drones, pooled) stream in and out
## around the hero all the time. Per-node diffs of local runs (DejaVu font, 3 copies in parallel): +57 / -61 nodes under VehicleManager with nothing else changed, and in a failing
## run "+9 under EnemyManager": a street patrol group woke near the tower during the window (list 0 -> 3) and its SENTINEL was created for the first time (the pool had none).
## The plain OBJECT_NODE_COUNT drifted by -15 to +12 with no tower involved and failed this check on the runner (CI 45672210947 FLAKY +12, 45769386420 +7, 45832989677 +6 and
## +8). The tower's rooms, doors, colliders, lift and people are all still counted; the tower's own armed men are checked separately (all released when it closes).
func _nodes() -> int:
	var n := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vm := Game.vehicles as Node
	if is_instance_valid(vm):
		n -= _count(vm)
	var em := Game.enemies as Node
	if is_instance_valid(em):
		for d in em.get_children():
			if d is Drone:
				n -= _count(d)
	return n


## Nodes of the tree (not the live vehicles) by their path's first four parts, plus the orphans: printed when the check fails.
func _groups() -> Dictionary:
	var out := {"(orphans)": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))}
	_group(Game.player.get_tree().root, out)
	return out


func _group(n: Node, out: Dictionary) -> void:
	if n == Game.vehicles or n is Drone:
		return
	var k := "/".join(Array(str(n.get_path()).split("/")).slice(0, 5))
	out[k] = int(out.get(k, 0)) + 1
	for ch in n.get_children(true):
		_group(ch, out)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children(true):
		c += _count(ch)
	return c


func _leak() -> void:
	var lot: CityLayout.Lot = tw["lot"]
	var far := TowerFloors.door_pos(tw, 60.0)
	await L.tp(far, 0.0)
	await L.secs(0.6)
	var n0 := _nodes()
	var g0 := _groups()
	var o0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var b0 := TowerFloors.builds
	var entered := 0
	for i in 10:
		var door := TowerFloors.door_pos(tw, 3.0)
		var pts := _route(0)
		await L.tp(door, Lib.yaw_to(door, pts[0]))
		var r := await L.walk(pts[0], 8.0, 0.8, 0.8)
		if r["reached"] and TowerFloors.inside(L.p.global_position):
			entered += 1
		await L.tp(far, 0.0)
		await L.secs(0.6)
	var n1 := _nodes()
	var o1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	if n1 - n0 > 3:                                                  # w125-ci: name where the nodes are (the runner's log is the only place this shows)
		var g1 := _groups()
		for k in g1:
			if int(g1[k]) != int(g0.get(k, 0)):
				print("leak: %s %+d" % [k, int(g1[k]) - int(g0.get(k, 0))])
		for k in g0:
			if not g1.has(k):
				print("leak: %s %+d" % [k, -int(g0[k])])
	var cs := (Game.world.collision_body as Node).get_node_or_null("Building%d_0" % lot.index) as CollisionShape3D
	TestLib.check(entered == 10 and TowerFloors.builds - b0 >= 10, "10 more entries by the stick (%d entered, %d builds) [old fails]" % [entered, TowerFloors.builds - b0])
	var ppl := TowerFloors.instance.people()
	TestLib.check((ppl["foes"] as Array).is_empty() and (ppl["actors"] as Array).is_empty(), "the tower's people and armed men are gone after the last exit (%d, %d)" % [(ppl["actors"] as Array).size(), (ppl["foes"] as Array).size()])
	TestLib.check(n1 - n0 <= 3 and o1 - o0 < 400 and TowerFloors.open_lot == -1 and cs != null and not cs.disabled, "no leak after 10 entries: nodes %+d, objects %+d, the building's own collider back on" % [n1 - n0, o1 - o0])
