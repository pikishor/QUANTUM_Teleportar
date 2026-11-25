extends RefCounted
## w123-critic: the wave 123 street as a player sees it. Real main scene at 844x390, phone HUD (Game.force_touch), reward cards on (CrateReveal._quiet = 0), REAL FINGERS
## (tests/w116_fingers.gd: InputEventScreenTouch / Drag through Input.parse_input_event). Start points by teleport (setup only); every move is the left thumb on the stick.
##  1. walkers: while the hero walks two sidewalks by the stick, the pedestrians near him never stand inside a solid street prop (kerb transformers, kiosks, benches,
##     planters, lamps): at most 0.5% of the samples (wave 123 as built: about 4%)
##  2. nobody sits on a bench seat or waits on a bus-stop spot that is inside a solid prop (wave 123: 35 seats in kiosks / kit clusters, 6 spots on lamps / poles)
##  3. the side-step table is built in under 400 ms (one hitch when the city loads)
## Run: tools/test.sh tests/test_critic_w123.gd   (W123C_OLD=1: wave 123 as built, checks 1 and 2 fail)
const TIMEOUT_SECONDS := 290
const Lib := preload("res://tests/w120_reach_lib.gd")
const Dodge := preload("res://scripts/ambient/crowd_dodge.gd")
var L: Lib


func run(h: Node) -> void:
	StreetLife.critic = OS.get_environment("W123C_OLD") != "1"
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var amb = (Game.world as City).ambient
	var cr = amb.crowd
	var t0 := Time.get_ticks_msec()
	Dodge.build(Game.world)
	var ms := Time.get_ticks_msec() - t0
	TestLib.check(ms < 400, "the side-step table is built in %d ms (< 400)" % ms)
	# 1. walkers
	var legs := [[Vector3(-20, 0.3, 11), Vector3(-100, 0.3, 11)], [Vector3(-11, 0.3, 30), Vector3(-11, 0.3, 100)]]
	var samples := 0
	var inside := 0
	var ex: Array = []
	for leg in legs:
		await L.tp(leg[0], Lib.yaw_to(leg[0], leg[1]))
		L.fg.stick(Vector2(0, -0.6))
		for t in 36:
			await L.secs(0.5)
			for i in cr.count:
				if not cr.is_alive(i) or cr.is_pinned(i):
					continue
				var p: Vector3 = cr.person_position(i)
				if Lib.flat(p, L.p.global_position) > 60.0:
					continue
				samples += 1
				var s := StreetLife.solid_at(p.x, p.z, 0.05)
				if s != "":
					inside += 1
					if ex.size() < 5:
						ex.append("%s at %s" % [s, p.snapped(Vector3.ONE * 0.1)])
		L.fg.stick(Vector2.ZERO)
	TestLib.check(samples > 1500 and inside * 200 <= samples, "pedestrians step around the kerb props: %d of %d samples inside a prop (<= 0.5%%) %s" % [inside, samples, ex])
	# 2. sitters and waiters: walk by the stick past the seats and stops that stand in a prop, then look at everybody seated or waiting
	var bad: Array = []
	for b in StreetLife.benches:
		if StreetLife.solid_at(b.x, b.z, 0.3, "StreetDress") != "":
			bad.append(Vector3(b.x, 0.0, b.z))
	for sp in StreetLife.bus_stops:
		for j in 3:
			var w := StreetLife.wait_spot(sp, j)
			if StreetLife.solid_at(w[0], w[1], 0.3) != "":
				bad.append(Vector3(w[0], 0.0, w[1]))
	TestLib.check(bad.size() >= 5, "there are seats / spots inside props to try (%d)" % bad.size())
	var found: Array = []
	var tried := 0
	for spot: Vector3 in bad:
		if tried >= 14:
			break
		tried += 1
		var from := spot + Vector3(6.0, 0.3, 0.0)
		await L.tp(from, Lib.yaw_to(from, spot))
		L.fg.stick(Vector2(0, -0.4))
		await L.secs(1.5)
		L.fg.stick(Vector2.ZERO)
		await L.secs(1.5)
		for i in cr.count:
			if cr.is_alive(i) and (cr.is_sitting(i) or cr.is_waiting(i)):
				var q: Vector3 = cr.person_position(i)
				var s2 := StreetLife.solid_at(q.x, q.z, 0.2, "StreetDress" if cr.is_sitting(i) else "")
				if s2 != "" and not found.has(q.snapped(Vector3.ONE * 0.1)):
					found.append(q.snapped(Vector3.ONE * 0.1))
					print("  in prop: ", "sits" if cr.is_sitting(i) else "waits", " in ", s2, " at ", q.snapped(Vector3.ONE * 0.1))
	TestLib.check(found.is_empty(), "nobody sits or waits inside a kiosk, kit cluster, lamp or pole (%d found at %d tried spots)" % [found.size(), tried])
	# 3. the sidewalk bench people sit on is solid: the left thumb pushes the hero at it from the street side and he does not come out behind it
	var bs: Array = StreetLife.benches.duplicate()
	bs.sort_custom(func(a, b): return Vector2(a.x, a.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)) < Vector2(b.x, b.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)))
	var through: Array = []
	var pushed := 0
	for b: Vector3 in bs:
		if pushed >= 4:
			break
		var seat := Vector3(b.x, 0.0, b.z)
		if StreetLife.solid_at(b.x, b.z, 0.3, "StreetDress") != "":
			continue
		pushed += 1
		var dz: float = b.y
		var from := seat + Vector3(0.0, 0.3, dz * 2.6)
		var to := seat - Vector3(0.0, 0.0, dz * 1.2)
		await L.tp(from, Lib.yaw_to(from, to))
		await L.secs(0.3)
		L.fg.stick(Vector2(0.0, -1.0))
		await L.secs(2.5)
		L.fg.stick(Vector2.ZERO)
		var past := (L.p.global_position.z - seat.z) * dz
		if past < -0.15:
			through.append("bench at %s: hero came out %.2f m behind the seat" % [seat.snapped(Vector3.ONE * 0.1), -past])
	TestLib.check(pushed >= 3 and through.is_empty(), "the hero cannot walk through a sidewalk bench (%d pushed: %s)" % [pushed, through])
	# 5. a finger on FIRE near people on the benches: they run off along the sidewalk line, not along the bench row through the bench sets and shop fronts
	var runs: Array = []
	var off_line: Array = []
	for b: Vector3 in bs.slice(0, 12):
		if runs.size() >= 3:
			break
		var seat2 := Vector3(b.x, 0.0, b.z)
		var stand := seat2 + Vector3(4.0, 0.3, b.y * 3.0)
		await L.tp(stand, Lib.yaw_to(stand, seat2))
		await L.secs(2.0)
		var who := -1
		for i in cr.count:
			if cr.is_alive(i) and cr.is_sitting(i) and Lib.flat(cr.person_position(i), seat2) < 1.0:
				who = i
		if who < 0:
			continue
		runs.append(who)
		L.fg.press(6, &"fire")
		await L.secs(0.4)
		L.fg.up(6)
		await L.secs(2.5)
		var q2: Vector3 = cr.person_position(who)
		var latc: float = q2.z if int(cr._axis[who]) == 0 else q2.x          # across its own sidewalk (it may have turned a corner)
		var road := roundi((latc + CityLayout.HALF) / CityLayout.PITCH)
		var dist := absf(latc - (-CityLayout.HALF + road * CityLayout.PITCH))
		if cr.is_sitting(who) or dist > 12.7:
			off_line.append("seat %s: %s %.1f m from the road centre" % [seat2.snapped(Vector3.ONE * 0.1), "still seated" if cr.is_sitting(who) else "running", dist])
	TestLib.check(runs.size() >= 2 and off_line.is_empty(), "people scared off a bench run along the sidewalk (within 12.7 m of the road centre) (%d tried: %s)" % [runs.size(), off_line])
	# 4. no bench set stands in a door's lane now that it is solid (it would block the door)
	var lanes := StreetClutter.grid_for(Game.world.doors)
	var in_lane := 0
	for b in StreetLife.benches:
		if StreetClutter.blocks_lane(lanes, b.x, b.z - b.y * 0.1, 0.9):
			in_lane += 1
	TestLib.check(in_lane == 0, "no sidewalk bench stands in front of a door (%d)" % in_lane)
	await L.finish()
	StreetLife.critic = true
