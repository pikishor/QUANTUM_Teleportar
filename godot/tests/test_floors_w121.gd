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


func _leak() -> void:
	var lot: CityLayout.Lot = tw["lot"]
	var far := TowerFloors.door_pos(tw, 60.0)
	await L.tp(far, 0.0)
	await L.secs(0.6)
	var n0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
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
	var n1 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var o1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var cs := (Game.world.collision_body as Node).get_node_or_null("Building%d_0" % lot.index) as CollisionShape3D
	TestLib.check(entered == 10 and TowerFloors.builds - b0 >= 10, "10 more entries by the stick (%d entered, %d builds) [old fails]" % [entered, TowerFloors.builds - b0])
	TestLib.check(n1 - n0 <= 3 and o1 - o0 < 400 and TowerFloors.open_lot == -1 and cs != null and not cs.disabled, "no leak after 10 entries: nodes %+d, objects %+d, the building's own collider back on" % [n1 - n0, o1 - o0])
