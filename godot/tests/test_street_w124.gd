extends RefCounted
## w1242-street (finish of the wave 123 street detail). The real main scene at 844x390, phone HUD, REAL FINGERS (left thumb on the stick, right thumb turns the view: tests/w116_fingers.gd
## through Input.parse_input_event), reward cards on (CrateReveal._quiet = 0). Start points are set up by teleport (setup only); every move is the stick.
##  1. every new prop kind exists (news box, bike rack, meter, street tree, traffic sign, street name sign, billboard, shop sign, awning, door frame, display, shutter, town clutter),
##     and walking the spawn sidewalk by the stick the window around the hero draws them (ONE mesh);
##  2. no sidewalk prop of the layer stands in a door lane (USE doors, walk-in shops, tower street doors within 250 m), and by the stick the hero walks from the kerb straight
##     through 8 dressed doors (door frame, awning, displays) without being stopped;
##  3. the walk-in shop's sign lies flush on its own shop front's sign band (it floated 0.5 m out and slid over the neighbours' NEON / QUANTA BAR signs from a slant), never wider than the front;
##     the hero walks up to it by the stick;
##  4. with the street traffic on, a bus pulls in at the bus stop the hero stands at (within 6 m of the shelter), stands there and drives on;
##  5. the hero walks by the stick into a tower lobby: the window holes of the open tower have glass;
##  6. an accident scene's cars stay inside the road (the wave 123 critic frame had a car over the kerb in the bench area).
## Run: tools/test.sh tests/test_street_w124.gd   (W1242_STREET_OLD=1: the wave 124 street, every numbered check fails)
const TIMEOUT_SECONDS := 560
const Lib := preload("res://tests/w120_reach_lib.gd")
const C := preload("res://tests/w123_clutter_lib.gd")
var L: Lib


func run(h: Node) -> void:
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var s := Game.SPAWN
	var sd := StreetDetail.instance
	# 1. kinds
	var missing: Array = []
	if sd == null:
		missing.append("no StreetDetail layer")
	else:
		if not sd.built:
			sd.build()
		for k in StreetDetail.KIND_COUNT:
			if sd.kind_count[k] < (10 if k != StreetDetail.BILLBOARD else 6):
				missing.append("%s %d" % [StreetDetail.KIND_NAMES[k], sd.kind_count[k]])
	TestLib.check(missing.is_empty(), "every new street prop kind is placed (missing or too few: %s)" % [missing])
	var a := Vector3(-20.0, 0.3, 11.0)
	var b := Vector3(-100.0, 0.3, 11.0)
	await L.tp(a, Lib.yaw_to(a, b))
	var seen := {}
	var rw := {"reached": true}
	var tri_max := 0
	var props_max := 0
	for leg in 4:                                                    # four legs of 20 m: the kinds the window holds around the hero on the way
		var r_leg := await L.walk(a.lerp(b, float(leg + 1) / 4.0), 12.0, 2.0)
		rw["reached"] = rw["reached"] and r_leg["reached"]
		if sd != null:
			tri_max = maxi(tri_max, sd.triangles)
			props_max = maxi(props_max, sd.near_props)
			for pl: Dictionary in sd.placements:
				if Lib.flat(pl["pos"], L.p.global_position) < sd.near_radius() - 3.0:
					seen[StreetDetail.KIND_NAMES[int(pl["kind"])]] = true
	TestLib.check(rw["reached"] and sd != null and tri_max > 300 and props_max >= 10 and seen.size() >= 6,
		"walking the spawn sidewalk by the stick, the layer draws the props around the hero in one mesh (up to %d triangles, %d props, kinds %s)" % [tri_max, props_max, seen.keys()])
	# 2. door lanes
	var doors := C.doors_near(s, 250.0)
	var bad: Array = []
	if sd != null:
		for pl: Dictionary in sd.placements:
			var k := int(pl["kind"])
			var p: Vector3 = pl["pos"]
			if p.distance_to(s) > 270.0 or p.y > 1.0:
				continue
			var r: float = StreetDetail.KIND_R[k] if k in StreetDetail.GROUND else (0.85 if k == StreetDetail.DISPLAY or k == StreetDetail.SHUTTER else -1.0)
			if r < 0.0:
				continue
			var q := p + (pl["n"] as Vector3) * 0.25
			for d in doors:
				if StreetClutter.in_lane(d["wall"], d["n"], d["kerb"], q.x, q.z, r):
					bad.append("%s at %s before %s" % [StreetDetail.KIND_NAMES[k], p.snapped(Vector3.ONE * 0.1), d["what"]])
					break
	var tested := 0
	if sd != null:
		for pl: Dictionary in sd.placements:
			if (pl["pos"] as Vector3).distance_to(s) <= 270.0:
				tested += 1
	TestLib.check(doors.size() >= 40 and tested >= 100 and bad.is_empty(), "no prop of the layer stands in front of a door (%d props near %d doors, %d in a lane: %s)" % [tested, doors.size(), bad.size(), bad.slice(0, 5)])
	var dressed: Array = []
	if sd != null:
		for pl: Dictionary in sd.placements:
			if int(pl["kind"]) == StreetDetail.DOOR_FRAME and (pl["pos"] as Vector3).distance_to(s) < 200.0:
				dressed.append(pl)
	dressed.sort_custom(func(x, y): return (x["pos"] as Vector3).distance_to(s) < (y["pos"] as Vector3).distance_to(s))
	var stuck: Array = []
	var walked := 0
	for pl in dressed:
		if walked >= 8:
			break
		var w: Vector3 = pl["pos"]
		var n: Vector3 = pl["n"]
		var kerb := C.kerb_out(w, n)
		if kerb < 2.0:
			continue
		walked += 1
		var from := w + n * (kerb - 0.4)
		var to := w + n * 0.3
		await L.tp(from + Vector3(0, 0.3, 0), Lib.yaw_to(from, to))
		await L.secs(0.3)
		var r2 := await _straight(from, to, 6.0)
		if not r2["ok"]:
			stuck.append("door at %s: %s" % [w.snapped(Vector3.ONE * 0.1), r2["why"]])
	TestLib.check(walked >= 6 and stuck.is_empty(), "the stick takes the hero from the kerb straight through %d dressed doors (frame, awning, displays) (%s)" % [walked, stuck])
	# 3. the walk-in shop sign stays on its own shop front: it floated 0.5 m off the facade, so from a slant it slid over the neighbours' neon signs (NEON, QUANTA BAR)
	var shop_ok := false
	var why := "no walk-in shop"
	if ShopFronts.instance != null and ShopFronts.instance.enabled:
		var fnt: Font = ThemeDB.fallback_font
		var worst: Dictionary = {}
		var worst_r := -1.0
		for sh: Dictionary in ShopFronts.instance.shops:
			if (sh["base"] as Vector3).distance_to(s) > 5000.0:
				continue
			var r := fnt.get_string_size(str(sh["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x * 0.0055 / (float(sh["s1"]) - float(sh["s0"]))
			if r > worst_r:
				worst_r = r
				worst = sh
		if not worst.is_empty():
			var base: Vector3 = worst["base"]
			var nn: Vector3 = worst["n"]
			var from2 := base + nn * 14.0
			from2.y = 0.3
			await L.tp(from2, Lib.yaw_to(from2, base))
			var rw2 := await L.walk(base + nn * 3.0, 20.0, 1.5)
			await L.secs(0.5)
			var sign: Label3D = ShopFronts.instance._sign
			if sign == null or not is_instance_valid(sign) or ShopFronts.open_lot != (worst["lot"] as CityLayout.Lot).index:
				why = "the shop of '%s' was not built (walk reached %s)" % [worst["title"], rw2["reached"]]
			else:
				var box := sign.get_aabb()
				var wide := box.size.x
				var front := float(worst["s1"]) - float(worst["s0"])
				var top := sign.global_position.y + box.end.y
				var bot := sign.global_position.y + box.position.y
				var off := absf((sign.global_position - (worst["base"] as Vector3)).dot(nn))
				shop_ok = wide <= front - 0.4 and bot >= 3.7 and top <= 4.9 and off <= 0.1
				why = "'%s' %.2f m wide on a %.2f m front, %.2f .. %.2f m high, %.2f m off the facade" % [sign.text, wide, front, bot, top, off]
	TestLib.check(shop_ok, "the walk-in shop's sign stays on its own shop front, clear of the neighbours' neon signs (%s)" % why)
	# 6. accident cars inside the road
	var pc: ParkedCars = Game.world.ambient.parked
	var over := 0
	var made := 0
	for i in range(2, 22):
		for j in range(2, 6):
			var before := pc.alive_count()
			pc._gen_accident(i, j, 990000 + i * 100 + j)
			made += pc.alive_count() - before
	for i in ParkedCars.CAP:
		if not pc.car_alive(i) or pc._wreck[i] == 0:
			continue
		var cp := pc.car_position(i)
		var yaw := pc.car_yaw(i)
		var f := Vector3(sin(yaw), 0, cos(yaw))
		var rr := Vector3(f.z, 0, -f.x)
		for c in [cp + f * 2.35 + rr * 0.95, cp + f * 2.35 - rr * 0.95, cp - f * 2.35 + rr * 0.95, cp - f * 2.35 - rr * 0.95]:
			if not CityLayout.on_road(c.x, c.z, 0.0):
				over += 1
				break
	TestLib.check(made > 20 and over == 0, "the cars of an accident scene stay inside the road, none reaches over the kerb onto the sidewalk (%d of %d over)" % [over, made])
	pc.reset()
	# 5. tower glass: walk into the lobby
	var glass := 0
	var holes_ok := false
	var tf := TowerFloors.instance
	if tf != null and not tf.towers.is_empty():
		var tws: Array = tf.towers.duplicate()
		tws.sort_custom(func(x, y): return TowerFloors.door_pos(x, 1.3).distance_to(s) < TowerFloors.door_pos(y, 1.3).distance_to(s))
		var tw: Dictionary = tws[0]
		var outside := TowerFloors.door_pos(tw, 4.0)
		var inside := TowerFloors.door_pos(tw, -2.5)
		await L.tp(outside + Vector3(0, 0.3, 0), Lib.yaw_to(outside, inside))
		var rw3 := await L.walk(inside, 15.0, 1.0)
		await L.secs(0.5)
		var m: Node = tf._mesh
		var g: Node = m.get_node_or_null(^"TowerGlass") if m != null and is_instance_valid(m) else null
		glass = tf.glass_panes
		holes_ok = rw3["reached"] and g != null and (g as MeshInstance3D).mesh != null and glass >= 8
	TestLib.check(holes_ok, "walked into a tower lobby by the stick: its window holes have glass (%d panes)" % glass)
	# 4. the bus
	var nt := NearTraffic.instance
	nt.enabled = true
	nt.count = 24
	nt.reset()
	if RoadTraffic.instance != null:
		RoadTraffic.instance.enabled = true
	var st: Array = StreetLife.bus_stops.duplicate()
	st.sort_custom(func(x, y): return x.distance_to(s) < y.distance_to(s))
	var sp: Vector3 = st[0]
	var road_c := _road_of(sp)
	var away := (Vector3(0, 0, signf(sp.z - road_c.y)) if road_c.x == 0.0 else Vector3(signf(sp.x - road_c.y), 0, 0))
	await L.tp(sp + away * 2.5 + Vector3(0, 0.3, 0), 0.0)
	var d0 := StreetLife.bus_dwells
	var l0 := StreetLife.bus_leaves
	var close_stand := 0.0
	var left := false
	var t := 0.0
	while t < 170.0 and not left:
		await L.secs(0.5)
		t += 0.5
		var bi := nt.bus_at_stop()
		if bi >= 0:
			var bp := nt.car_position(bi)
			if Vector2(bp.x - sp.x, bp.z - sp.z).length() < 6.0:
				close_stand += 0.5
		if close_stand >= 3.0 and StreetLife.bus_leaves > l0:
			left = true
		if OS.get_environment("W1242_DEBUG") == "1" and int(t * 2.0) % 20 == 0:
			var buses: Array = []
			for i in nt.count:
				if nt._alive[i] != 0 and nt._kind[i] == NearTraffic.BUS_KIND:
					buses.append([nt.car_position(i).snapped(Vector3.ONE), snappedf(nt._spd[i], 0.1), nt._bus_t[i]])
			print("DBG t ", t, " alive ", nt.alive_count(), " buses ", buses, " stop ", sp)
	TestLib.check(close_stand >= 3.0 and left, "a bus pulled in at the stop the hero stands at, stood within 6 m of the shelter (%.1f s) and drove on (%d stops, %d leaves in %.0f s)" % [close_stand, StreetLife.bus_dwells - d0, StreetLife.bus_leaves - l0, t])
	nt.enabled = false
	nt.count = 0
	nt.reset()
	await L.finish()


## (axis, road centre) of the road a bus stop stands beside: axis 0 = the road along x.
static func _road_of(sp: Vector3) -> Vector2:
	for k in CityLayout.N + 1:
		var c := CityLayout.road_center(k)
		if absf(absf(sp.z - c) - 11.8) < 0.3:
			return Vector2(0.0, c)
		if absf(absf(sp.x - c) - 11.8) < 0.3:
			return Vector2(1.0, c)
	return Vector2(0.0, 0.0)


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
