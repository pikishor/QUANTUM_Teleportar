extends RefCounted
## WAVE 123 STREET LIFE (w123-life; owner round 7: "not many details on the street", "small silly errors. Are you even checking"). The real main scene, the phone HUD, REAL FINGERS
## (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event in window coordinates), reward cards on (CrateReveal._quiet = 0), Game.force_touch, 844 x 390.
## Start points are set by teleport (setup only); every move is the left thumb on the stick, every action a finger on a drawn button.
##   street   the hero walks the market street by the stick for 30 s: at least 5 kinds of activity within 30 m (chat, shop window, bus stop wait, vendor, bench, phone, street event,
##            animals, a bus at its stop); people sit on the benches and wait at the bus stops
##   bus      a bus on the street brakes at the bus stop, stands with the hero watching, and drives on
##   door     a finger on JUMP while running at a tower door frame (beside the opening, straight and slanted) never starts a wall run up the frame and he is back on his feet
##   shop     inside a walk-in shop, facing the shelves, the SNAKE button never reads CLIMB (it is not on screen at all)
##   parapet  on a roof, a finger on SWING while running at the parapet takes him over it (the parapet does not stop a snake move)
## W123_LIFE_OLD=1 switches the w123-life changes off (StreetLife.fix): every check marked [old fails] fails.
## Run: tools/test.sh tests/test_life_w123.gd

const TIMEOUT_SECONDS := 280
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib


func run(h: Node) -> void:
	StreetLife.fix = OS.get_environment("W123_LIFE_OLD") != "1"
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	await _street()
	await _bus()
	await _door()
	await _shop()
	await _parapet()
	await L.finish()
	StreetLife.fix = true


const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")


func _amb() -> Node:
	var w := Game.world as City
	return w.ambient if w != null else null


# --- street ----------------------------------------------------------------------------------------------------------------

func _street() -> void:
	var amb = _amb()
	var nt := NearTraffic.instance
	nt.enabled = true
	nt.set_tier(nt.quality, 1.0)
	var stop := _stop_x()                                      # the street of the bus stop nearest the spawn: the far sidewalk, from 30 m before the shelter
	var c := CityLayout.road_center(roundi((stop.z + CityLayout.HALF) / CityLayout.PITCH))
	var lat := c - signf(stop.z - c) * 11.3
	var start := Vector3(stop.x + 30.0, 0.2, lat)
	var goal := Vector3(stop.x - 150.0, 0.0, lat)
	await L.tp(start, Lib.yaw_to(start, goal))
	await L.secs(1.0)
	var cr = amb.crowd
	var seen := {}
	var benches := 0
	var bus_wait := 0
	var t := 0.0
	L.fg.stick(Vector2(0.0, -0.45))                            # a stroll
	while t < 30.0:
		await L.secs(0.5)
		t += 0.5
		var gp := L.p.global_position
		var err := wrapf(Lib.yaw_to(gp, goal) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.2:
			L.fg.look(-err * 160.0, 0.0, 3)
		for i in cr.count:
			if not cr.is_alive(i):
				continue
			var d: Vector3 = cr.person_position(i) - gp
			if d.x * d.x + d.z * d.z > 30.0 * 30.0:
				continue
			if cr.has_method(&"is_sitting") and cr.is_sitting(i):
				seen["bench"] = true
				benches = maxi(benches, 1)
				continue
			if cr.is_vendor(i):
				seen["vendor"] = true
				continue
			match cr.state_of(i):
				&"idle":
					seen["chat"] = true
				&"linger":
					if cr.last_stop_kind(i) == Crowd.STOP_BUS:
						seen["bus stop"] = true
						bus_wait += 1
					elif cr.last_stop_kind(i) == Crowd.STOP_SHOP:
						seen["shop window"] = true
		if amb.beats.active_near(gp, 30.0) > 0:
			seen["street event"] = true
		if LifeCensus.take(gp, 30.0)["fauna"] > 0:
			seen["animals"] = true
		var b := nt.bus_at_stop()
		if b >= 0 and (nt.car_position(b) - gp).length() < 40.0:
			seen["bus at its stop"] = true
		if amb.life.sitting_near(gp, 30.0) > 0:
			seen["bench"] = true
		if amb.life.waiting_near(gp, 30.0) > 0:
			seen["bus stop"] = true
			bus_wait += 1
	L.fg.stick(Vector2.ZERO)
	print("  street (%s -> %s, bus stop %s) kinds: %s (bench sitters now %d, served %d)" % [start, goal, stop, seen.keys(), amb.life.sitting_count(), amb.life.sat])
	TestLib.check(seen.size() >= 6, "[old fails] on the market street at least 6 kinds of street life within 30 m in 30 s of walking: %s" % [seen.keys()])
	TestLib.check(seen.has("bench"), "[old fails] people sit on the street benches (%d seated now)" % amb.life.sitting_count())
	TestLib.check(seen.has("bus stop"), "people wait at a bus stop (%d samples)" % bus_wait)
	# a seated person sits ON a bench seat (not beside it, not in the road)
	var ok_seat := false
	for i in cr.count:
		if cr.has_method(&"is_sitting") and cr.is_sitting(i):
			var pp: Vector3 = cr.person_position(i)
			for bs: Vector3 in StreetLife.benches:
				if Vector2(bs.x - pp.x, bs.z - pp.z).length() < 0.2:
					ok_seat = true
	TestLib.check(ok_seat, "[old fails] a seated person is on a bench seat")


# --- bus -------------------------------------------------------------------------------------------------------------------

func _stop_x() -> Vector3:
	var best := Vector3.INF
	for sp: Vector3 in StreetLife.bus_stops:
		var c := CityLayout.road_center(roundi((sp.z + CityLayout.HALF) / CityLayout.PITCH))
		if absf(absf(sp.z - c) - 11.8) > 0.2 or absf(sp.x) > CityLayout.HALF - 120.0:
			continue                                            # a stop on a road along x, away from the city edge
		if best == Vector3.INF or sp.distance_to(Game.SPAWN) < best.distance_to(Game.SPAWN):
			best = sp
	return best


func _bus() -> void:
	var nt := NearTraffic.instance
	var best := _stop_x()
	TestLib.check(best != Vector3.INF, "a bus stop on a street along x (%d stops)" % StreetLife.bus_stops.size())
	if best == Vector3.INF:
		return
	var c := CityLayout.road_center(roundi((best.z + CityLayout.HALF) / CityLayout.PITCH))
	var dir := 1
	var line := c + VehicleSpecs.lane_offset(0, dir, CityLayout.LANE)
	if absf(line - best.z) > StreetLife.BUS_SIDE:
		dir = -1
		line = c + VehicleSpecs.lane_offset(0, dir, CityLayout.LANE)
	# the hero watches from the sidewalk across from the shelter
	var watch := Vector3(best.x + 6.0, 0.2, best.z + signf(best.z - c) * 1.5)
	await L.tp(watch, Lib.yaw_to(watch, best - Vector3(dir * 30.0, 0.0, 0.0)))
	await L.secs(0.5)
	nt.reset()
	nt.place(0, 0, dir, line, best.x - dir * 45.0, NearTraffic.BUS_KIND, 11.0, 1)
	await L.secs(1.0)
	var amb = _amb()
	var waiting0: int = amb.life.waiting_near(best, 8.0)
	var b0: int = amb.life.boarded
	var d0 := StreetLife.bus_dwells
	var l0 := StreetLife.bus_leaves
	var stood_at := INF
	var stood_t := 0.0
	var t := 0.0
	while t < 26.0:
		await L.secs(0.25)
		t += 0.25
		if not nt.car_alive(0) or nt.car_kind(0) != &"bus":
			break
		if nt.car_speed(0) < 0.3:
			var du := absf(nt.car_position(0).x - best.x)
			if du < 4.0:
				stood_t += 0.25
				stood_at = minf(stood_at, du)
		if StreetLife.bus_leaves > l0 and nt.car_speed(0) > 3.0:
			break
	print("  bus: stood %.1f s %.1f m from the stop, dwells %d leaves %d, speed now %.1f" % [stood_t, stood_at, StreetLife.bus_dwells - d0, StreetLife.bus_leaves - l0, nt.car_speed(0)])
	TestLib.check(stood_t >= 3.0, "[old fails] a bus brakes at the bus stop and stands there (%.1f s within %.1f m)" % [stood_t, stood_at])
	TestLib.check(waiting0 > 0 and amb.life.boarded > b0, "[old fails] people wait at that stop (%d) and get on the bus (%d boarded)" % [waiting0, amb.life.boarded - b0])
	TestLib.check(StreetLife.bus_leaves > l0 and nt.car_alive(0) and nt.car_speed(0) > 3.0, "[old fails] ... and then drives on (speed %.1f)" % nt.car_speed(0))


# --- door frame jump -------------------------------------------------------------------------------------------------------

func _door() -> void:
	var nt := NearTraffic.instance
	nt.enabled = false
	nt.count = 0
	nt.reset()
	var tw: Dictionary = TowerFloors.instance.nearest(Game.SPAWN)
	TestLib.check(not tw.is_empty(), "a walk-in tower near the spawn")
	if tw.is_empty():
		return
	var n: Vector3 = tw["n"]
	var tg: Vector3 = tw["t"]
	var door := TowerFloors.door_pos(tw, 0.0)
	var bad: Array[String] = []
	var tries := 0
	for side in [1.0, -1.0]:
		for ang in [0.0, 0.5, -0.5]:
			for k in [-1.2, 1.2]:
				tries += 1
				var r := await _jump_at(door, n * side, tg, k, 3.0 if side > 0.0 else 2.6, ang)
				if r != "":
					bad.append("%s side %d ang %.1f k %.1f" % [r, int(side), ang, k])
	TestLib.check(bad.is_empty(), "[old fails] a finger on JUMP while running at the door frame (%d runs, outside and inside, straight and slanted) starts no wall run up the frame, never hangs in the air, never ends in or through the wall: %s" % [tries, bad])


## One run at the door frame; "" when fine, else what went wrong.
func _jump_at(door: Vector3, out: Vector3, tg: Vector3, k: float, dist: float, ang: float) -> String:
	var start := door + out * dist + tg * (k - tan(ang) * dist) + Vector3.UP * 0.2
	await L.tp(start, Lib.yaw_to(start, door + tg * k))
	await L.secs(0.4)
	var wr0: int = L.p.verbs.wall_runs
	L.fg.stick(Vector2(0.0, -1.0))
	var jumped := false
	var hang := 0.0
	var air := 0.0
	var t := 0.0
	var side0 := signf((L.p.global_position - door).dot(out))
	var cross_lat := 0.0                                       # lateral offset where he passed the wall plane (the opening is |lat| < 1)
	while t < 2.6:
		await L.secs(0.05)
		t += 0.05
		var gp := L.p.global_position
		if cross_lat == 0.0 and signf((gp - door).dot(out) + 0.5 * side0) != side0:       # half a metre past the wall face: he went through
			cross_lat = (gp - door).dot(tg) + 0.001
		if not jumped and (gp - door).dot(out) < 1.0:
			jumped = true
			await L.press(&"jump")
		if jumped and not L.p.is_on_floor():
			air += 0.05
		if jumped and gp.y - door.y > 0.8 and L.p.velocity.length() < 0.6 and not L.p.is_on_floor():
			hang += 0.05                                       # in the air and not moving: stuck on the frame
	L.fg.stick(Vector2.ZERO)
	await L.secs(0.4)
	var runs: int = L.p.verbs.wall_runs - wr0
	var through := absf(cross_lat) > TowerFloors.DOOR_W * 0.5 + 0.15 and absf(cross_lat) < 6.0      # (far along the facade he ran round the building's corner)
	if runs > 0 and ang == 0.0:
		return "wall run up the frame (air %.2f s, hang %.2f s)" % [air, hang]
	if hang > 0.25:
		return "hangs %.2f s in the air (wall runs %d)" % [hang, runs]
	if through:
		return "passed through the wall %.2f m beside the door's middle" % cross_lat
	if not L.p.is_on_floor():
		return "not on his feet"
	return ""


# --- shop: no CLIMB ---------------------------------------------------------------------------------------------------------

func _shop() -> void:
	var sf := ShopFronts.instance
	var s: Dictionary = sf.nearest_of(&"food", Game.SPAWN) if sf != null else {}
	TestLib.check(not s.is_empty(), "a walk-in food shop near the spawn")
	if s.is_empty():
		return
	var n: Vector3 = s["normal"]
	var w: Vector3 = s["wall"]
	var outside := w + n * 2.8
	await L.tp(outside, Lib.yaw_to(outside, w))
	await L.secs(0.6)
	await _go(w + n * 1.0, 6.0)
	await _go(w - n * 2.0, 4.0)
	var cur := sf.current()
	var inside := not cur.is_empty() and ShopFronts.inside(L.p.global_position)
	TestLib.check(inside, "by the stick through the door into the shop (%s)" % L.p.global_position.snapped(Vector3.ONE * 0.1))
	if not inside:
		return
	# the side wall: walk up to it and face it
	var wall_pt := ShopFronts.at(cur, float(cur["s0"]) + 0.2, float(cur["d"]) * 0.45, 0.0)
	var labels: Array[String] = []
	await _go(ShopFronts.at(cur, float(cur["s0"]) + 1.2, float(cur["d"]) * 0.45, 0.0), 5.0, 0.4)
	for k in 6:
		var gp := L.p.global_position
		var err := wrapf(Lib.yaw_to(gp, wall_pt) - L.p.camera_rig.yaw, -PI, PI)
		L.fg.look(-err * 160.0, 0.0, 3)
		L.fg.stick(Vector2(0.0, -0.6))
		await L.secs(0.25)
		L.fg.stick(Vector2.ZERO)
		await L.secs(0.25)
		labels.append(L.fg.button_label(&"snake"))
	print("  shop: snake button %s, wall_ready %s" % [labels, L.p.snake.wall_ready])
	TestLib.check(not labels.has("CLIMB") and ShopFronts.inside(L.p.global_position), "[old fails] facing the shop's wall inside the shop, no CLIMB on the screen (%s)" % [labels])
	TestLib.check(L.fg.button(&"snake") == Vector2.INF, "[old fails] ... the SNAKE button is not on screen in the shop, as under a tower's ceilings")


func _go(q: Vector3, limit: float, arrive := 0.6) -> bool:
	var t := 0.0
	var still := 0.0
	var last := L.p.global_position
	var pushing := false
	while t < limit:
		var gp := L.p.global_position
		if Lib.flat(gp, q) < arrive:
			break
		var err := wrapf(Lib.yaw_to(gp, q) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.4:
			if pushing:
				L.fg.stick(Vector2.ZERO)
				pushing = false
			L.fg.look(-err * 160.0, 0.0, 4)
			await L.f(3)
			t += 0.1
			continue
		if not pushing:
			L.fg.stick(Vector2(0.0, -0.7))
			pushing = true
		await L.secs(0.1)
		t += 0.1
		if absf(err) > 0.15:
			L.fg.look(-err * 160.0, 0.0, 3)
		var mv := Lib.flat(L.p.global_position, last)
		last = L.p.global_position
		still = still + 0.1 if mv < 0.02 else 0.0
		if still > 1.5:
			break
	L.fg.stick(Vector2.ZERO)
	await L.f(3)
	return Lib.flat(L.p.global_position, q) < arrive


# --- snake swing over a parapet ------------------------------------------------------------------------------------------

func _parapet() -> void:
	var city = Game.world
	var best: CityLayout.Lot = null
	var bd := INF
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if b.cls != &"block" or lot.h < 8.0 or lot.h > 40.0 or minf(lot.w, lot.d) < 12.0:
			continue
		var dd := Vector2(lot.cx, lot.cz).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z))
		if dd < bd:
			bd = dd
			best = lot
	TestLib.check(best != null and RoofParapets.enabled, "a flat roof with a parapet near the spawn")
	if best == null:
		return
	var y := best.h
	var start := Vector3(best.cx, y + 0.3, best.cz)
	var edge := Vector3(best.cx + best.w * 0.5, y, best.cz)
	await L.tp(start, Lib.yaw_to(start, edge + Vector3(8, 0, 0)))
	await L.secs(1.0)
	var on_roof := absf(L.p.global_position.y - y) < 0.6
	L.fg.stick(Vector2(0.0, -1.0))
	var t := 0.0
	while t < 6.0 and L.p.global_position.x < edge.x - 3.0:
		await L.secs(0.1)
		t += 0.1
	var pressed := L.fg.press(8, &"snake")                    # SWING while running at the parapet
	await L.f(4)
	L.fg.up(8)
	t = 0.0
	var over := false
	while t < 4.0:
		await L.secs(0.1)
		t += 0.1
		var gp := L.p.global_position
		if gp.x > edge.x + 0.5:
			over = true
			break
	L.fg.stick(Vector2.ZERO)
	var gp2 := L.p.global_position
	print("  parapet: roof %.0f m, pressed SWING %s, mode %s, x %.1f (edge %.1f) y %.1f" % [y, pressed, L.p.snake.mode, gp2.x, edge.x, gp2.y])
	TestLib.check(on_roof and pressed and over, "a finger on SWING while running at the roof parapet (%.0f m up) takes him over it (x %.1f, edge %.1f)" % [y, gp2.x, edge.x])
	await L.secs(3.0)
