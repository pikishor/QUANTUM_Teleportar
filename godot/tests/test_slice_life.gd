extends RefCounted
## Slice life (owner round 3: "the streets are empty, nothing happens"): around the spawn in the market street there are always 20+ civilians (walking, talking, shopping, fleeing),
## 6+ cars driving at real speeds (NearTraffic: one MultiMesh, lanes, lights, stops for people), stall vendors, fauna and street beats (an argument, a street show, a runner, a horn).
## Pure data and rules first (stall sites, car mesh, lane geometry, lights, gaps, turns), then the REAL composed game (scenes/main.tscn) stepped through AmbientCity._process by hand:
## a census at 5 positions around the spawn, a vendor that is scared / shot, the beats, the hero taking a near car (the real Vehicle appears), a crash that makes near cars real.
## Looked at with tests/bot_slice_life.gd (SLICE_HUD=0 BOT_RES=2400x1080 tools/bot.sh ...), sheets in docs/shots/slice/life_*.png.
## Run: tools/test.sh tests/test_slice_life.gd

const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")
const Props := preload("res://scripts/world/city_props.gd")
const TIMEOUT_SECONDS := 130.0
const DT := 0.05
## hero positions: offsets from the spawn (-30, 4), all within 40 m of it: the avenue (two), the cross road at x = 0 (two), next to the junction
const SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(-24.0, 0.0, -4.0), Vector3(30.0, 0.0, -26.0), Vector3(30.0, 0.0, 24.0), Vector3(14.0, 0.0, -2.0)]

var host: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	_sites()
	_meshes()
	_unit_cars()
	_unit_rules()
	await _real_scene()


# --- stall sites ----------------------------------------------------------------------------------------------------------

func _sites() -> void:
	var sit := StreetVendors.sites()
	TestLib.check(sit.size() >= 100, "the city has stall sites (%d)" % sit.size())
	var near := 0
	var bad := 0
	for s: Dictionary in sit:
		var pos: Vector3 = s["pos"]
		var c: float = pos.z if int(s["axis"]) == 0 else pos.x
		var off := absf(c - CityLayout.road_center(roundi((c + CityLayout.HALF) / CityLayout.PITCH)))
		if absf(off - StreetVendors.STALL_OFF) > 0.05 or absf(pos.x) > CityLayout.HALF or absf(pos.z) > CityLayout.HALF:
			bad += 1
		if Vector2(pos.x - Game.SPAWN.x, pos.z - Game.SPAWN.z).length() < 40.0:
			near += 1
	TestLib.check(bad == 0, "every stall stands on the kerb side of its road (%d wrong)" % bad)
	TestLib.check(near >= 2, "the market street next to the spawn has stalls (%d within 40 m)" % near)
	TestLib.check(StreetVendors.sites() == sit, "the site table is computed once")


# --- meshes ---------------------------------------------------------------------------------------------------------------

func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _meshes() -> void:
	var car := NearTraffic.car_mesh()
	var t := _tris(car)
	TestLib.check(car.get_surface_count() == 1, "a near car is ONE surface (one draw call for all of them)")
	TestLib.check(t >= 120 and t <= 400, "a near car is a few hundred triangles (%d)" % t)
	var stall := Props.stall_mesh()
	TestLib.check(stall.get_surface_count() == 1 and _tris(stall) <= 700, "a stall is one surface, under 700 triangles (%d)" % _tris(stall))
	TestLib.check(NearTraffic.COUNTS[0] <= NearTraffic.COUNTS[1] and NearTraffic.COUNTS[1] <= NearTraffic.COUNTS[2] and NearTraffic.COUNTS[2] <= NearTraffic.BUILT, "near cars per tier fit the MultiMesh")
	TestLib.check(Crowd.COUNTS[0] >= 36, "LOW keeps at least 36 people in the ring so the market street holds 20+ (%d)" % Crowd.COUNTS[0])


# --- the rules of the near cars --------------------------------------------------------------------------------------------

func _lane_ok(nt: NearTraffic, i: int) -> bool:
	var ax := nt.car_axis(i)
	var p := nt.car_position(i)
	var across := p.z if ax == 0 else p.x
	var k := roundi((across + CityLayout.HALF) / CityLayout.PITCH)
	return absf(across - nt.car_shift_world(i) - (CityLayout.road_center(k) + VehicleSpecs.lane_offset(ax, nt.car_dir(i), CityLayout.LANE))) < 0.05


func _unit_cars() -> void:
	var nt := NearTraffic.new()
	nt.build(null)
	nt.desync = false
	var c0 := CityLayout.road_center(8)                      # the avenue z = 0
	var jx := CityLayout.road_center(9)                      # the junction at x = 80
	# a red light: the car stops short of the junction, a green lets it through
	nt.count = 1
	nt.signal_clock_override = 10.0                          # axis 0 is red from 9 s
	nt.place(0, 0, 1, c0 + CityLayout.LANE, jx - 44.0, 0, 12.0, 1)
	var centre := Vector3(jx - 40.0, 0.0, 0.0)
	var worst_u := -1.0e9
	for k in 300:
		nt.step(DT, centre)
		worst_u = maxf(worst_u, nt.car_position(0).x)
	TestLib.check(nt.car_alive(0) and nt.car_speed(0) < 0.5, "a car stops for a red (speed %.2f)" % nt.car_speed(0))
	TestLib.check(worst_u < jx - NearTraffic.STOP_LINE + 3.0, "... short of the junction: stopped at %.1f m before its centre" % (jx - worst_u))
	TestLib.check(nt.stops_light >= 1, "the red was seen (%d)" % nt.stops_light)
	nt.signal_clock_override = 0.0                           # green for axis 0
	for k in 160:
		nt.step(DT, centre)
	var through := not nt.car_alive(0) or nt.car_position(0).x > jx - 4.0 or nt.car_turning(0) or nt.car_axis(0) == 1
	TestLib.check(through and (not nt.car_alive(0) or nt.car_axis(0) == 1 or nt.car_turning(0) or nt.car_speed(0) > 5.0), "on green it drives on (x %.1f, speed %.1f)" % [nt.car_position(0).x, nt.car_speed(0)])
	# following: the car behind a stopped one keeps a gap
	nt.count = 2
	nt.signal_clock_override = 0.0
	nt.place(0, 0, 1, c0 + CityLayout.LANE, -200.0, 0, 12.0, 1)
	nt.place(1, 0, 1, c0 + CityLayout.LANE, -170.0, 0, 11.0, 2, 0.0)
	nt._stun[1] = 999.0
	var centre2 := Vector3(-185.0, 0.0, 0.0)
	for k in 400:
		nt.step(DT, centre2)
	var gap := nt.car_position(1).x - nt.car_position(0).x
	TestLib.check(gap > 4.5 and nt.car_speed(0) < 0.6, "a car queues behind a stopped one without touching it (gap %.1f m, speed %.2f)" % [gap, nt.car_speed(0)])
	# people and obstacles
	var f := Vector2(1.0, 0.0)
	var p0 := Vector2(0.0, 5.0)
	TestLib.check(nt.gap_allow(p0, f, Vector2(5.0, 5.4), 2.25, 0.5, NearTraffic.SIDE_FOOT) == 0.0, "a person 5 m ahead in the lane stops the car")
	var mid := nt.gap_allow(p0, f, Vector2(12.0, 5.2), 2.25, 0.5, NearTraffic.SIDE_FOOT)
	TestLib.check(mid > 0.0 and mid < 12.0, "a person 12 m ahead only slows it (%.1f m/s)" % mid)
	TestLib.check(nt.gap_allow(p0, f, Vector2(5.0, 9.0), 2.25, 0.5, NearTraffic.SIDE_FOOT) == 99.0, "a person on the pavement does not")
	TestLib.check(nt.gap_allow(p0, f, Vector2(-5.0, 5.0), 2.25, 0.5, NearTraffic.SIDE_FOOT) == 99.0, "nor does one behind it")
	# a person standing in the lane: the car drifts round him instead of waiting for ever
	nt.count = 1
	nt.signal_clock_override = 0.0
	nt.place(0, 0, 1, c0 + CityLayout.LANE, -300.0, 0, 12.0, 1)
	var stand := Vector3(-270.0, 0.0, c0 + CityLayout.LANE + 0.3)
	var closest_lat := 1.0e9
	var slowest := 99.0
	var max_x := -1.0e9
	for k in 300:
		nt.step(DT, stand)
		var cp := nt.car_position(0)
		max_x = maxf(max_x, cp.x)
		if absf(cp.x - stand.x) < 2.4:
			closest_lat = minf(closest_lat, absf(cp.z - stand.z))
		slowest = minf(slowest, nt.car_speed(0))
	TestLib.check(max_x > stand.x + 8.0, "a car drives past a person standing in its lane (reached x %.1f, he stands at %.1f)" % [max_x, stand.x])
	TestLib.check(closest_lat >= 1.2 and closest_lat < 1.0e8, "... leaving room (%.2f m)" % closest_lat)
	# a street's worth: speeds, lanes, turns
	nt.reset()
	nt.desync = true
	nt.signal_clock_override = -1.0
	nt.set_tier(1)
	var mid_pos := Vector3(-30.0, 0.0, 4.0)
	var turned := 0
	var was_turning := PackedByteArray()
	was_turning.resize(NearTraffic.BUILT)
	var fastest := 0.0
	var slowest_cruise := 99.0
	var fastest_cruise := 0.0
	for k in 700:
		nt.step(DT, mid_pos)
		for i in nt.count:
			if nt.car_alive(i):
				fastest = maxf(fastest, nt.car_speed(i))
				var t := nt.car_turning(i)
				if t and was_turning[i] == 0:
					turned += 1
				was_turning[i] = 1 if t else 0
	var bad := 0
	var alive := 0
	for i in nt.count:
		if nt.car_alive(i):
			alive += 1
			slowest_cruise = minf(slowest_cruise, nt._cruise[i])
			fastest_cruise = maxf(fastest_cruise, nt._cruise[i])
			if not nt.car_turning(i) and not _lane_ok(nt, i):
				bad += 1
	TestLib.check(alive >= int(nt.count * 0.6), "the ring is filled (%d of %d)" % [alive, nt.count])
	TestLib.check(bad == 0, "every car that is not on a curve drives its right-hand lane (%d off)" % bad)
	TestLib.check(turned >= 3, "cars turn at junctions on a curve (%d turns in 35 s)" % turned)
	TestLib.check(slowest_cruise >= VehicleSpecs.AI_CRUISE_MIN * 0.85 and fastest_cruise <= VehicleSpecs.AI_CRUISE_MAX * 1.3 + 0.01, "cruise speeds are real speeds (%.1f to %.1f m/s)" % [slowest_cruise, fastest_cruise])
	TestLib.check(fastest > 8.0 and fastest < 20.0, "cars reach city speed and no more (%.1f m/s)" % fastest)
	# gunfire: cars within earshot flee, far ones do not
	var near_i := -1
	var far_i := -1
	for i in nt.count:
		if nt.car_alive(i):
			var d := nt.car_position(i).distance_to(mid_pos)
			if d < 30.0 and near_i < 0:
				near_i = i
			elif d > 62.0 and far_i < 0:
				far_i = i
	if near_i >= 0:
		nt.hear(nt.car_position(near_i) + Vector3(3.0, 0.0, 3.0), &"gun")
		TestLib.check(nt.car_panic(near_i) > 0.0, "a shot next to a car makes it flee")
	if far_i >= 0:
		var before := nt.car_panic(far_i)
		nt.hear(mid_pos, &"gun")
		TestLib.check(nt.car_panic(far_i) == before, "a car 60 m away does not hear it")
	# CPU: the whole ring, a frame
	var t0 := Time.get_ticks_usec()
	for k in 200:
		nt.step(DT, mid_pos)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 200.0
	TestLib.check(ms < 5.0, "the near traffic costs %.2f ms a frame (limit 5)" % ms)
	NearTraffic.instance = null


## The avenue's lights, the drift round several obstacles at once, the vendor behind his counter.
func _unit_rules() -> void:
	var green_av := 0
	var both := 0
	var cross_green := 0
	var n := 360
	for k in n:
		var clk := float(k) * 0.05
		var a0 := NearTraffic.signal_for(0, NearTraffic.AVENUE, 3, clk, true)
		var a1 := NearTraffic.signal_for(1, 5, NearTraffic.AVENUE, clk, true)
		green_av += 1 if a0 == 0 else 0
		cross_green += 1 if a1 == 0 else 0
		both += 1 if (a0 != 2 and a1 != 2) else 0
	TestLib.check(both == 0, "the avenue and its cross road are never open together (%d samples)" % both)
	TestLib.check(float(green_av) / float(n) >= 0.6 and cross_green > 0, "the market avenue is the main road: green %.0f %% of the cycle, the cross road still gets its turn (%d samples)" % [100.0 * float(green_av) / float(n), cross_green])
	TestLib.check(NearTraffic.signal_for(0, 3, 4, 2.0, true) == VehicleSpecs.signal_state(0, 2.0 + NearTraffic.junction_offset(0, 3, 4)), "other roads keep the city's two-phase lights")
	# a hero in the lane and the camera behind him: one drift round both (the old per-obstacle drift took the camera's side into the hero and the avenue queued behind him)
	var nt := NearTraffic.new()
	nt.build(null)
	nt._n_obs = 2
	nt._obs[0] = -1.0                                         # the hero, 1 m left of the lane's centre
	nt._obs[1] = -0.2                                         # the camera
	nt._obs_cam[0] = 0
	nt._obs_cam[1] = 1
	var sh := nt._pick_shift()
	TestLib.check(absf(sh) > 0.5 and absf(-1.0 - sh) >= NearTraffic.SWERVE_CLEAR - 0.05 and absf(-0.2 - sh) >= NearTraffic.SWERVE_CLEAR - 0.05, "one drift clears the hero and the camera together (%.2f m)" % sh)
	nt._n_obs = 1
	nt._obs[0] = 6.0
	nt._obs_cam[0] = 0
	TestLib.check(nt._pick_shift() == 0.0, "an obstacle beyond the lane's reach asks for no drift")
	# the vendor stands between the counter and the lit back panel of his stall
	var back_of_counter := StreetVendors.STALL_OFF + 0.5
	var back_panel := StreetVendors.STALL_OFF + 1.7
	TestLib.check(StreetVendors.VENDOR_OFF > back_of_counter and StreetVendors.VENDOR_OFF < back_panel, "the vendor stands behind the counter, in front of the back panel (%.2f m, between %.2f and %.2f)" % [StreetVendors.VENDOR_OFF, back_of_counter, back_panel])


# --- the real game -----------------------------------------------------------------------------------------------------------

func _tick(amb: Node3D, n: int) -> void:
	var vm := Game.vehicles as VehicleManager
	for k in n:
		if vm != null:
			vm.signal_clock += DT                              # the junction lights run on the test's clock, not the real one
		amb._process(DT)


func _census(p: Player, c: Vector3) -> Dictionary:
	return LifeCensus.take(Vector3(c.x, 0.0, c.z), 40.0)


func _real_scene() -> void:
	Game.civilian_casualties = true
	MapScreen.path_override = "user://test_slice_life_map_%d.cfg" % OS.get_process_id()      # a map file of its own: what an earlier run charted is not what a new player sees
	DirAccess.remove_absolute(MapScreen.path_override)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	var city := Game.world as City
	if p == null or city == null or city.ambient == null:
		TestLib.check(false, "the real game has a player and a city with an ambient layer")
		return
	Game.state = &"play"
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	p.max_hp = 1.0e6
	var amb: Node3D = city.ambient
	var nt: NearTraffic = amb.near_traffic
	var crowd: RefCounted = amb.crowd
	var vm := Game.vehicles as VehicleManager
	vm.lights_on = true
	# wired: the live process steps the near cars and the vendors by itself
	var t_end := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < t_end and (nt.alive_count() < 8 or amb.vendors.active_count() < 1):
		await TestLib.frames(host, 4)
	TestLib.check(nt.alive_count() >= 8, "the live game drives near cars (%d)" % nt.alive_count())
	TestLib.check(amb.vendors.active_count() >= 1, "the live game puts vendors behind the stalls (%d)" % amb.vendors.active_count())
	var nodes := 0
	for n in city.multimesh_nodes:
		if n.name == &"NearTraffic":
			nodes += 1
			TestLib.check((n as MultiMeshInstance3D).multimesh.instance_count == NearTraffic.BUILT and (n as MultiMeshInstance3D).multimesh.visible_instance_count <= nt.alive_count(), "the NearTraffic MultiMesh draws only the cars the camera can see (%d of %d)" % [(n as MultiMeshInstance3D).multimesh.visible_instance_count, nt.alive_count()])
	TestLib.check(nodes == 1, "the world has ONE NearTraffic MultiMesh node")
	var ms := p.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	if ms != null:
		var share := 100.0 * float(ms.discovered_count()) / float(MapScreen.CELLS * MapScreen.CELLS)
		TestLib.check(share >= 20.0 and ms.is_discovered(Game.SPAWN.x, Game.SPAWN.z) and ms.is_discovered(250.0, -250.0), "the map charts the city core at the start (%.0f %%)" % share)
		TestLib.check(not ms.is_discovered(600.0, 600.0), "the outer ring stays fogged until you go there")
	else:
		TestLib.check(false, "the map screen exists in the live game")
	amb.set_process(false)                                    # from here the test steps the ambient layer by hand (the same _process the engine calls)
	amb.simulate = true
	TestLib.check(Game.is_playing(), "the game is playing")
	var tree_nodes := p.get_tree().get_node_count()

	for q in [2, 1, 0]:                                        # MED, then the LOW of the phone (the rest of the test runs on LOW)
		Game.set_quality(q)
		_tick(amb, 40)
		await _census_run(amb, p, q)

	# fleeing: gunfire sends the street running
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	_tick(amb, 60)
	var calm: Dictionary = _census(p, p.global_position)
	crowd.scare_from(p.global_position, 30.0)
	var fl: Dictionary = _census(p, p.global_position)
	TestLib.check(int(fl["civ_flee"]) >= 6 and int(calm["civ_flee"]) < int(fl["civ_flee"]), "gunfire sends the street running (%d -> %d fleeing)" % [int(calm["civ_flee"]), int(fl["civ_flee"])])
	_tick(amb, 200)

	# vendors: scared they run, shot they die, the stall gets a new one
	var v_slot := -1
	for i in crowd.count:
		if crowd.is_pinned(i) and crowd.is_alive(i):
			v_slot = i
			break
	TestLib.check(v_slot >= 0, "a vendor stands at a stall")
	if v_slot >= 0:
		var served0: int = amb.vendors.served
		crowd.scare_person(v_slot, crowd.person_position(v_slot) + Vector3(2.0, 0.0, 0.0))
		TestLib.check(not crowd.is_pinned(v_slot) and crowd.is_fleeing(v_slot), "a scared vendor runs from his stall")
		_tick(amb, 60)
		TestLib.check(amb.vendors.served > served0 or crowd.vendors_near(p.global_position, 60.0) >= 2, "the empty stall gets a new vendor (%d served)" % amb.vendors.served)
		var victim := -1
		for i in crowd.count:
			if crowd.is_pinned(i) and crowd.is_alive(i):
				victim = i
				break
		if victim >= 0:
			var vk: int = crowd.killed_total
			crowd.kill_person(victim, p.global_position)
			TestLib.check(crowd.killed_total == vk + 1 and not crowd.is_pinned(victim), "a shot vendor dies and lets go of his slot")

	# beats
	var bc := Game.SPAWN + Vector3(0.0, 0.1, 0.0)
	p.teleport_to(bc)
	_tick(amb, 100)
	var b0: int = amb.beats.started
	TestLib.check(amb.beats.start(bc, &"gather"), "a street show can start")
	var watching := 0
	for i in crowd.count:
		if crowd.is_alive(i) and not crowd.is_pinned(i) and crowd.state_of(i) == &"linger":
			watching += 1
	TestLib.check(watching >= 2, "people stop to watch it (%d)" % watching)
	TestLib.check(amb.beats.start(bc, &"chase"), "a runner can bolt")
	TestLib.check(crowd.fled_total() > 0, "... and he runs")
	TestLib.check(amb.beats.start(bc, &"argue") or amb.beats.by_kind.get(&"gather", 0) >= 2, "an argument can start (or falls back to a show)")
	var h0: int = nt.honks
	TestLib.check(amb.beats.start(bc, &"honk") or nt.moving_near(bc, 40.0) == 0, "a horn can sound")
	TestLib.check(amb.beats.started >= b0 + 3, "four beats started (%d)" % (amb.beats.started - b0))
	TestLib.check(nt.honks >= h0, "honks are counted")
	var pre: int = amb.beats.active.size()
	_tick(amb, 400)                                          # 20 s: they end
	TestLib.check(amb.beats.active.size() <= 3, "beats end and the list stays short (%d, was %d)" % [amb.beats.active.size(), pre])

	# the hero takes a near car: it becomes a real Vehicle at the same place, speed and lane, and he can drive it
	var ni := -1
	for i in nt.count:
		if nt.car_alive(i) and nt.car_speed(i) > 4.0 and not nt.car_turning(i) and nt.car_position(i).distance_to(bc) < 50.0:
			ni = i
			break
	TestLib.check(ni >= 0, "a near car is driving by")
	if ni >= 0:
		var cp := nt.car_position(ni)
		var kind := nt.car_kind(ni)
		var spd := nt.car_speed(ni)
		var f := Vector3(-sin(nt.car_yaw(ni)), 0.0, -cos(nt.car_yaw(ni)))
		var side := Vector3(-f.z, 0.0, f.x)
		var pr0 := nt.promoted
		for j in nt.count:                                    # nobody else near this one: the nearest car in reach is the one we mean
			if j != ni and nt.car_position(j).distance_to(cp) < 14.0:
				nt._alive[j] = 0
		p.teleport_to(cp + side * 2.3 + Vector3(0.0, 0.1, 0.0))
		var got := vm.reach_car(p.global_position)
		var real: Vehicle = null
		for v in vm.list:
			if v.ai and v.global_position.distance_to(cp) < 0.6 and v.kind == kind:
				real = v
		TestLib.check(real != null and nt.promoted == pr0 + 1 and got != null, "a near car within reach becomes a real car")
		if real != null:
			TestLib.check(not nt.car_alive(ni), "... and the MultiMesh one is gone")
			TestLib.check(real.kind == kind and real.ai and absf(real.ai_speed - spd) < 0.5, "... same kind, driving, same speed (%s %.1f)" % [str(real.kind), real.ai_speed])
			TestLib.check(real.global_position.distance_to(cp) < 0.3, "... at the same place")
			real.ai_speed = 0.0
			real.speed = 0.0
			vm.toggle_enter_exit()
			TestLib.check(vm.driven == real, "he gets in: any car in the street can be taken")
			# a near car ahead of the driven car becomes real before the crash
			var df := Vector3(-sin(real.heading), 0.0, -cos(real.heading))
			var spare := -1
			for i in nt.count:
				if not nt.car_alive(i):
					spare = i
					break
			if spare >= 0:
				var ahead := real.global_position + df * 6.0
				var ax := 0 if absf(df.x) > absf(df.z) else 1
				nt.place(spare, ax, 1, ahead.z if ax == 0 else ahead.x, ahead.x if ax == 0 else ahead.z, 0, 10.0, 3, 0.0)
				nt._stun[spare] = 999.0
				var pr1 := nt.promoted
				vm._near_t = 0.0
				vm._physics_process_body(0.02)
				TestLib.check(nt.promoted == pr1 + 1 and not nt.car_alive(spare), "a near car in the path of the driven car becomes real (so the crash is a real one)")
			vm.exit_vehicle()

	# a car goes round the hero standing in its lane (and does not hurt him)
	nt.reset()
	for i in nt.count:
		nt._alive[i] = 0
		nt._age[i] = 1.0                                       # no refill while the test places its own
	var lane_z := CityLayout.road_center(8) + CityLayout.LANE
	var hero_x := 40.0                                         # mid-block between the junctions at x = 0 and 80
	for v in vm.list.duplicate():                              # the real cars of the earlier steps (a promoted one, the crash) must not stand in this lane
		if is_instance_valid(v) and v != vm.driven and absf(v.global_position.x - hero_x) < 60.0 and absf(v.global_position.z - lane_z) < 12.0:
			v.global_position = Vector3(v.global_position.x, v.global_position.y, v.global_position.z + 400.0)
	p.teleport_to(Vector3(hero_x, 0.1, lane_z))
	await TestLib.frames(host, 2)
	nt.place(0, 0, 1, lane_z, hero_x - 30.0, 0, 12.0, 4)
	var hp0 := p.hp
	var near_lat := 1.0e9
	var reach_x := -1.0e9
	for k in 240:
		nt.step(DT, p.global_position)
		var cp := nt.car_position(0)
		reach_x = maxf(reach_x, cp.x)
		if absf(cp.x - p.global_position.x) < 2.4:
			near_lat = minf(near_lat, absf(cp.z - p.global_position.z))
	TestLib.check(near_lat >= 1.2 and p.hp >= hp0 and reach_x > hero_x + 4.0, "a car drives round the hero standing in its lane (%.2f m clear, hp %.0f, reached x %.1f of hero %.1f, alive %s, speed %.1f)" % [near_lat, p.hp, reach_x, hero_x, str(nt.car_alive(0)), nt.car_speed(0)])

	# gunfire through the real manager reaches the near cars
	nt.reset()
	nt.place(1, 0, 1, lane_z, hero_x - 20.0, 0, 12.0, 4)
	vm.hear(p.global_position, &"gun")
	TestLib.check(nt.car_panic(1) > 0.0, "VehicleManager.hear reaches the near cars (panic %.1f s)" % nt.car_panic(1))

	# nothing grows
	TestLib.check(absi(p.get_tree().get_node_count() - tree_nodes) < 220, "no node per near car or per person (only the promoted real cars and the effects add some) (%d -> %d)" % [tree_nodes, p.get_tree().get_node_count()])
	main.queue_free()
	await TestLib.frames(host, 2)
	DirAccess.remove_absolute(MapScreen.path_override)
	MapScreen.path_override = ""


## The census at 5 positions around the spawn, on tier `q`.
func _census_run(amb: Node3D, p: Player, q: int) -> void:
	var nt: NearTraffic = amb.near_traffic
	var crowd: RefCounted = amb.crowd
	var min_civ := 999
	var vendors_at_spawn := 0
	var fauna_hits := 0
	var event_hits := 0
	var states := {}
	for si in SPOTS.size():
		p.teleport_to(Game.SPAWN + SPOTS[si] + Vector3(0.0, 0.1, 0.0))
		_tick(amb, 220)                                       # 11 s of game time: the ring re-centres and refills
		var civ_ok := true
		var moving: Array[int] = []
		var ev := 0
		var fa := 0
		for s in 16:
			_tick(amb, 24)                                    # 19 s of samples: more than one light cycle
			var cs := _census(p, p.global_position)
			min_civ = mini(min_civ, int(cs["civ"]))
			civ_ok = civ_ok and int(cs["civ"]) >= 20
			moving.append(int(cs["cars_moving"]))
			ev += 1 if int(cs["events"]) >= 1 else 0
			fa += 1 if int(cs["fauna"]) >= 1 else 0
			if si == 0:
				vendors_at_spawn = maxi(vendors_at_spawn, int(cs["vendors"]))
			for k: String in ["civ_walk", "civ_talk", "civ_shop"]:
				states[k] = int(states.get(k, 0)) + int(cs[k])
		moving.sort()
		event_hits += 1 if ev >= 5 else 0
		fauna_hits += 1 if fa >= 9 else 0
		TestLib.check(civ_ok, "tier %d, spot %d: 20+ civilians within 40 m in every sample (lowest %d)" % [q, si, min_civ])
		TestLib.check(moving[moving.size() / 2] >= 5 and moving[moving.size() - 1] >= 7, "tier %d, spot %d: 6+ cars moving within 40 m (median %d, best %d: %s)" % [q, si, moving[moving.size() / 2], moving[moving.size() - 1], str(moving)])
	TestLib.check(vendors_at_spawn >= 2, "tier %d: the spawn has vendors at their stalls (%d)" % [q, vendors_at_spawn])
	TestLib.check(fauna_hits >= 4, "tier %d: fauna lives within 40 m at %d of 5 positions" % [q, fauna_hits])
	TestLib.check(event_hits >= 4, "tier %d: something is going on within 40 m at %d of 5 positions" % [q, event_hits])
	TestLib.check(int(states.get("civ_walk", 0)) > 0 and int(states.get("civ_talk", 0)) > 0 and int(states.get("civ_shop", 0)) > 0, "tier %d: people walk, talk and shop: %s" % [q, str(states)])
	TestLib.check(amb.beats.started >= 1, "tier %d: beats ran (%d, %s)" % [q, amb.beats.started, str(amb.beats.by_kind)])
