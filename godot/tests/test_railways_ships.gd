extends RefCounted
## RAILWAYS AND SHIPS (wave 106). Data first, then the REAL game scene:
##  * RailNet: three double-track lines (maglev over the city, mountain line with a tunnel and viaducts, coast line), grades under 6 %, flat stations, level crossings that take the road's height,
##    rail trestles in the bridge list, timetables whose two trains never share a track, the kit meshes and the rolling stock;
##  * ShipKit / fleet: five ship types, the destroyer has two turrets, a helm and a helipad, the berths and sea lanes have the depth, the sounds exist;
##  * live: RailWorld and ShipWorld under the city; a maglev dwelling at CENTRAL carries the hero when it pulls out (moving platform), a seat holds him, a ladder takes him to the roof;
##    the level crossing barrier comes down for a train and goes up again; the DERAIL job ends a container train and pays; the HEIST job runs board / roof / escape;
##    the destroyer: the hero takes the helm and sails it, mans a gun and a shell explodes; the helipad is solid.
## Run: tools/test.sh tests/test_railways_ships.gd   (waits on positions, counters and game time, never on frame counts)

const TIMEOUT_SECONDS := 140.0
const K := 3

var _host: Node
var _p: Player
var _rw: RailWorld
var _sw: ShipWorld
var _city: City


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_data()
	await _scene(host)


# --- data -------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TerrainHeight.warm()
	var st := RailNet.stats()
	TestLib.check(int(st["routes"]) == 3 and float(st["length"]) > 6000.0, "three lines, %d m of track" % int(st["length"]))
	TestLib.check(int(st["stations"]) >= 10 and int(st["tunnels"]) >= 1 and int(st["viaducts"]) >= 3 and int(st["crossings"]) >= 2, "stations %d, tunnels %d, viaducts %d, crossings %d" % [st["stations"], st["tunnels"], st["viaducts"], st["crossings"]])
	TestLib.check(float(st["max_grade"]) <= 0.06, "no grade over 6 %% (%.1f %%)" % (float(st["max_grade"]) * 100.0))
	var level_ok := true
	var flat_ok := true
	var kinds := {}
	for r in RailNet.routes():
		var y: PackedFloat32Array = r["y"]
		var s: PackedFloat32Array = r["s"]
		for c: Dictionary in r["crossings"]:
			if bool(c["level"]) and absf(y[int(c["i"])] - float(c["road_y"])) > 0.3:
				level_ok = false
		for stn: Dictionary in r["stations"]:
			for i in y.size():
				if absf(s[i] - float(stn["s"])) <= float(stn["len"]) * 0.5 and absf(y[i] - float(stn["y"])) > 0.05:
					flat_ok = false
		for v: Dictionary in r["viaducts"]:
			kinds[&"viaduct"] = true
		for t: Dictionary in r["tunnels"]:
			kinds[&"tunnel"] = true
	TestLib.check(level_ok, "a level crossing lies at the height of its road")
	TestLib.check(flat_ok, "every platform is dead level")
	var mag := RailNet.route(&"maglev")
	var city_deck := true
	var mpos: PackedVector2Array = mag["pos"]
	for i in mpos.size():
		if TerrainHeight.city_distance(mpos[i].x, mpos[i].y) <= 0.0 and absf(float((mag["y"] as PackedFloat32Array)[i]) - RailNet.ELEV) > 0.01:
			city_deck = false
	TestLib.check(city_deck and float(mag["len"]) > 2500.0, "the maglev runs at %.0f m over the whole city on a viaduct (%d stations)" % [RailNet.ELEV, (mag["stations"] as Array).size()])
	# the carve: on the ground part of a line the land is cut to the bed
	var coast := RailNet.route(&"coast")
	var cp: PackedVector2Array = coast["pos"]
	var ci := cp.size() * 3 / 10
	TestLib.check(absf(TerrainHeight.height_at(cp[ci].x, cp[ci].y) - float((coast["y"] as PackedFloat32Array)[ci])) < 0.6, "the terrain carries the coast line on its bench (%.2f vs %.2f)" % [TerrainHeight.height_at(cp[ci].x, cp[ci].y), float((coast["y"] as PackedFloat32Array)[ci])])
	Bridges.ensure()
	TestLib.check(Bridges.of_kind(&"rail").size() >= 1, "the railway's trestle over water is in the bridge list")
	# the mountain line: one tunnel with an underground station, portals
	var mt := RailNet.route(&"mountain")
	TestLib.check(not (mt["tunnels"] as Array).is_empty(), "the mountain line goes through the hill (tunnel %d m)" % int(((mt["tunnels"] as Array)[0] as Dictionary)["len"]))
	# timetables
	var clash := false
	var moved := true
	for r in RailNet.routes():
		var sch := RailSchedule.new(r)
		var tds: Array = r["trains"]
		var t := 0.0
		while t < sch.period * 1.0:
			var a := sch.at(t, float((tds[0] as Dictionary)["phase"]))
			var b := sch.at(t, float((tds[1] as Dictionary)["phase"]))
			var la := TrainKit.consist_length((tds[0] as Dictionary)["kind"])
			var lb := TrainKit.consist_length((tds[1] as Dictionary)["kind"])
			if int(a["dir"]) == int(b["dir"]) and absf(float(a["u"]) - float(b["u"])) < (la + lb) * 0.5 + 20.0:
				clash = true
			if float(a["u"]) < -1.0 or float(a["u"]) > float(r["len"]) + 1.0:
				moved = false
			t += 2.0
		var e0 := sch.at(0.0, 0.0)
		moved = moved and sch.period > 100.0 and float(e0["v"]) == 0.0
	TestLib.check(not clash and moved, "on every line the two trains never share a track and stay on the line")
	# rolling stock
	var cars_ok := true
	for kind in TrainKit.CONSISTS:
		for ty: StringName in TrainKit.CONSISTS[kind]:
			var cd := TrainKit.car(ty, kind)
			if int(cd["tris"]) < 100 or int(cd["tris"]) > 9000 or (cd["spec"]["shapes"] as Array).is_empty():
				cars_ok = false
	TestLib.check(cars_ok and TrainKit.CONSISTS.size() == 5, "five kinds of train (passenger, maglev, ore, regional, container) with every car type modelled and solid")
	var pax := TrainKit.car(&"coach", &"express")
	TestLib.check(not (pax["spec"]["seats"] as Array).is_empty() and (pax["spec"]["doors"] as Array).size() == 2, "a coach has seats and two door gaps")
	# ships
	for ty in [&"destroyer", &"cargo", &"tanker", &"cruise", &"submarine"]:
		var sp := ShipKit.spec(ty)
		TestLib.check(int(sp["tris"]) > 300 and int(sp["tris"]) < 12000 and not (sp["shapes"] as Array).is_empty(), "%s: %d triangles, %d solids" % [ty, sp["tris"], (sp["shapes"] as Array).size()])
	var ds := ShipKit.spec(&"destroyer")
	TestLib.check((ds["turrets"] as Array).size() == 2 and (ds["pad"] as Vector3).is_finite() and (ds["helm"] as Vector3).y > 8.0 and bool(ds["boardable"]), "the destroyer has two gun turrets, a bridge to steer from and a helipad")
	var deep := true
	for f: Dictionary in ShipWorld.FLEET:
		var p: Vector3 = f["pos"]
		var d := float(ShipKit.spec(f["type"])["draft"])
		deep = deep and TerrainHeight.depth_at(p.x, p.z) >= d + 0.5
	for l: Dictionary in ShipWorld.LANES:
		var pts: Array = l["path"]
		var d2 := float(ShipKit.spec(l["type"])["draft"])
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			for k in 16:
				var q := a.lerp(b, float(k) / 16.0)
				deep = deep and TerrainHeight.depth_at(q.x, q.y) >= d2 + 3.0
	TestLib.check(deep, "every berth and every sea lane has the water for its ship")
	for nm in [&"train_horn", &"maglev_chime", &"train_clatter", &"maglev_hum", &"crossing_bell", &"ship_horn", &"ship_engine", &"train_brake"]:
		TestLib.check(not Sfx.variants_of(nm).is_empty(), "sound %s exists" % nm)
	var bm := ShipKit.buoy_mesh([Vector3.ZERO], [Color.RED])
	TestLib.check(bm.get_surface_count() == 1, "buoys build")


# --- the real scene ---------------------------------------------------------------------------------------------------------------------

func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if cond.call():
			return true
		await _host.get_tree().process_frame
	return cond.call()


func _hold(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await _host.get_tree().process_frame


func _release() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"fire", &"jump", &"interact"]:
		Input.action_release(a)


func _scene(host: Node) -> void:
	CarRadio.auto_headless = true
	Game.quality = 1
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	_city = Game.world as City
	_rw = RailWorld.instance
	_sw = ShipWorld.instance
	TestLib.check(_p != null and _city != null and _rw != null and _sw != null and _rw.get_parent() == _city and _sw.get_parent() == _city, "the city has a RailWorld and a ShipWorld")
	if _p == null or _rw == null or _sw == null:
		main.queue_free()
		CarRadio.auto_headless = false
		return
	_p.set_physics_process(true)
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	(Game.enemies as EnemyManager).clear()
	var vm := Game.vehicles as VehicleManager
	vm.stream_every = 1.0e9
	vm._stream_t = 1.0e9
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	await _chunks_and_trains()
	await _riding()
	await _crossing()
	await _jobs()
	await _ships()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_release()
	_p.control_hold = false
	CarRadio.auto_headless = false
	main.queue_free()
	await TestLib.frames(host, 2)


func _stop_time(r: Dictionary, kind: StringName, stop: int, min_left: float) -> float:
	var sch: RailSchedule = _rw.schedules[r["id"]]
	var ph := 0.0
	for td: Dictionary in r["trains"]:
		if td["kind"] == kind:
			ph = float(td["phase"])
			break
	var t := 0.0
	while t < sch.period:
		var s := sch.at(t, ph)
		if int(s["stop"]) == stop and float(s["dwell_left"]) > min_left:
			return t
		t += 0.5
	return -1.0


func _station_platform(r: Dictionary, idx: int) -> Vector3:
	var st: Dictionary = (r["stations"] as Array)[idx]
	var pa := RailNet.point_at(r, float(st["s"]))
	var t := Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
	return (pa[0] as Vector3) + RailNet.right_of(t) * (RailNet.HALF_SEP * float(pa[2]) + 1.62 + 2.0) + Vector3(0.0, RailNet.PLATFORM_Y + 0.4, 0.0)


func _chunks_and_trains() -> void:
	var mag := RailNet.route(&"maglev")
	var plat := _station_platform(mag, 2)
	_p.teleport_to(plat)
	var n := _rw.ensure_near(plat, 600.0)
	var st := _rw.stats()
	TestLib.check(int(st["built"]) >= 3 and int(st["tris"]) > 5000 and int(st["tris"]) < 90000, "chunks around CENTRAL are built: %d chunks, %d triangles" % [st["built"], st["tris"]])
	TestLib.check(int(st["with_colliders"]) >= 1 and int(st["colliders"]) > 10, "and solid (%d colliders: piers, platforms, stairs)" % st["colliders"])
	var meshes := 0
	for ch in _rw.chunks:
		if ch["built"] and is_instance_valid(ch["node"]) and (ch["node"] as MeshInstance3D).visibility_range_end > 0.0:
			meshes += 1
	TestLib.check(meshes == int(st["built"]), "every chunk is ONE mesh with a draw distance (%d)" % meshes)
	TestLib.check(int(st["trains"]) == 6 and int(st["gates"]) >= 1 and int(st["signals"]) > 4, "six trains, %d level crossings, %d signals" % [st["gates"], st["signals"]])
	# the hero stands on the platform: the platform collider holds him
	await _hold(1.2)
	TestLib.check(_p.global_position.y > plat.y - 0.6 and _p.global_position.y < plat.y + 1.5, "the hero stands on the elevated platform (y %.1f, platform %.1f)" % [_p.global_position.y, plat.y])


func _riding() -> void:
	var mag := RailNet.route(&"maglev")
	var t0 := _stop_time(mag, &"maglev", 2, 12.0)
	TestLib.check(t0 >= 0.0, "the timetable has the maglev standing at CENTRAL")
	_rw.set_clock(t0)
	var tr := _rw.train(&"maglev", &"maglev")
	await _until(func() -> bool: return tr.active, 4.0)
	TestLib.check(tr.active and tr.speed() == 0.0, "the maglev dwells at CENTRAL, solid and in view")
	# the hero steps into car 1 through a door gap: local (1.0, floor, 0)
	var xf := tr.car_xf(1)
	_p.global_position = xf * Vector3(0.0, TrainKit.FLOOR + 0.3, 5.0)
	_p.velocity = Vector3.ZERO
	await _hold(0.8)
	var cu := _rw.car_under(_p.global_position)
	TestLib.check(not cu.is_empty() and cu["train"] == tr, "the hero stands inside the car (floor y %.2f)" % (_p.global_position.y - tr.car_xf(1).origin.y))
	# a seat
	var spec: Dictionary = tr.cars[1]["spec"]
	var seat: Vector3 = (spec["seats"] as Array)[2]
	_p.global_position = tr.car_xf(1) * (seat + Vector3(0.0, 0.2, 0.0))
	_p.velocity = Vector3.ZERO
	await _hold(0.4)
	TestLib.check(_rw.use_prompt() == "SIT" and RideUse.prompt() == "SIT", "at a seat the USE says SIT")
	_rw.use_do()
	TestLib.check(_rw.seated and _p.control_hold, "seated: the stick no longer walks the hero")
	_rw.stand_up()
	TestLib.check(not _p.control_hold, "and he stands up again")
	# the ride: leave in a few seconds; the hero is carried
	var start_pos := _p.global_position
	_p.global_position = tr.car_xf(1) * Vector3(0.0, TrainKit.FLOOR + 0.3, 5.0)
	var s0 := tr.centre()
	_rw.set_clock(_rw.clock + (float(tr.state["dwell_left"]) - 2.0))
	var went := await _until(func() -> bool: return tr.speed() > 6.0, 14.0)
	await _hold(2.5)
	var cu2 := _rw.car_under(_p.global_position)
	var carried := _p.global_position.distance_to(start_pos)
	TestLib.check(went and not cu2.is_empty() and carried > 12.0, "the train pulls out and carries the hero with it (%.0f m, %.1f m/s, still in the car: %s)" % [carried, tr.speed(), str(not cu2.is_empty())])
	# the roof from a ladder at the end of a car: stop the train again at the next station for a quiet check
	var t1 := _stop_time(mag, &"maglev", 3, 12.0)
	_rw.set_clock(t1)
	await _until(func() -> bool: return tr.active and tr.speed() == 0.0, 4.0)
	var ladder: Vector3 = (tr.cars[1]["spec"]["ladders"] as Array)[1]
	var xf2 := tr.car_xf(1)
	var half := float(tr.cars[1]["len"]) * 0.5
	_p.global_position = xf2 * Vector3(-2.3 * float(tr.lane_dir()), TrainKit.FLOOR + 0.3, half + 0.2)       # the platform side of the car, by the ladder at its end
	_p.velocity = Vector3.ZERO
	await _hold(0.6)
	var pr := _rw.use_prompt()
	TestLib.check(pr == "CLIMB TO ROOF", "at the end of a car the USE says CLIMB TO ROOF (got '%s')" % pr)
	_rw.use_do()
	await _hold(0.5)
	var cu3 := _rw.car_under(_p.global_position)
	var up_y := float((cu3["local"] as Vector3).y) if not cu3.is_empty() else -9.0
	TestLib.check(not cu3.is_empty() and up_y > float((tr.cars[int(cu3["i"])]["spec"] as Dictionary)["roof_y"]) - 0.4, "the hero is on a roof (local y %.2f)" % up_y)


func _crossing() -> void:
	var coast := RailNet.route(&"coast")
	var g := _rw.gate_of(&"coast", 0)
	TestLib.check(not g.is_empty(), "the coast line has a level crossing with barriers")
	if g.is_empty():
		return
	var c: Dictionary = g["c"]
	var cpos: Vector3 = c["pos"]
	_p.teleport_to(cpos + Vector3(0.0, 1.5, 30.0))
	_rw.ensure_near(cpos, 500.0)
	# the freight train a short way before the crossing, heading at it
	var tr := _rw.train(&"coast", &"container")
	var sch: RailSchedule = _rw.schedules[&"coast"]
	var ph := 0.5
	var found := -1.0
	var t := 0.0
	while t < sch.period:
		var s := sch.at(t, ph)
		var gap := absf(float(s["u"]) - float(c["u"])) - tr.length * 0.5
		var heading: bool = float(s["dir"]) * (float(c["u"]) - float(s["u"])) > 0.0
		if heading and float(s["v"]) > 5.0 and gap > 90.0 and gap < 125.0:
			found = t
			break
		t += 0.5
	TestLib.check(found >= 0.0, "the timetable brings the container train at the crossing")
	if found < 0.0:
		return
	_rw.set_clock(found - 6.0)
	await _hold(0.5)
	TestLib.check(float(g["gate"]) > 0.95, "no train near: the barriers stand open")
	await _until(func() -> bool: return float(g["gate"]) < 0.05, 14.0)
	var arm_solid := false
	for sb in g["bodies"]:
		if (sb as StaticBody3D).collision_layer != 0:
			arm_solid = true
	TestLib.check(float(g["gate"]) < 0.05 and arm_solid, "the barriers come down and are solid when the train approaches (gate %.2f)" % float(g["gate"]))
	# after it has gone by they open again
	var sc := sch.at(found, ph)
	var after := found + 80.0
	_rw.set_clock(after)
	await _until(func() -> bool: return float(g["gate"]) > 0.95, 25.0)
	TestLib.check(float(g["gate"]) > 0.95, "and open again once it has passed (gate %.2f)" % float(g["gate"]))


func _credits() -> int:
	var pr := Game.progress
	return int(pr.get("credits")) if pr != null and pr.get("credits") != null else 0


func _jobs() -> void:
	var jobs := _rw.jobs
	var rows := jobs.jobs_table()
	TestLib.check(rows.size() == 4 and jobs.markers().size() == 4, "four train missions on the minimap: heist, escort, derail, roof chase")
	# DERAIL: the marker on the coast line; the container train approaches; a blast at the marker derails it
	var c0 := _credits()
	jobs.start(&"derail")
	var mark := jobs.target_pos(&"derail")
	_p.teleport_to(mark + Vector3(0.0, 1.0, 10.0))
	var tr := _rw.train(&"coast", &"container")
	var sch: RailSchedule = _rw.schedules[&"coast"]
	var r := RailNet.route(&"coast")
	var mu := float(r["len"]) * 0.55
	var found := -1.0
	var t := 0.0
	while t < sch.period:
		var s := sch.at(t, 0.5)
		var gap := absf(float(s["u"]) - mu)
		if float(s["v"]) > 8.0 and gap > 60.0 and gap < 110.0 and float(s["dir"]) * (mu - float(s["u"])) > 0.0:
			found = t
			break
		t += 0.5
	TestLib.check(found >= 0.0 and jobs.active == &"derail", "DERAIL starts: blow the track at the marker")
	_rw.set_clock(found)
	await _until(func() -> bool: return tr.active and tr.speed() > 6.0, 4.0)
	Game.explode(mark, 7.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	await _hold(0.6)
	TestLib.check(tr.derailed and jobs.active == &"" and _credits() >= c0 + int(RailJobs.PAY[&"derail"]), "the blast derails the train and the job pays (%d -> %d credits)" % [c0, _credits()])
	tr.derailed = false
	# HEIST: board the ore train, hold a box car roof for 4 s, jump off
	var t_ore := _stop_time(RailNet.route(&"mountain"), &"ore", 0, 30.0)
	var ore := _rw.train(&"mountain", &"ore")
	_p.teleport_to(_station_platform(RailNet.route(&"mountain"), 0))
	_rw.ensure_near(_p.global_position, 500.0)
	_rw.set_clock(t_ore)
	await _until(func() -> bool: return ore.active, 4.0)
	var c1 := _credits()
	jobs.start(&"heist")
	var bi := -1
	for i in ore.cars.size():
		if ore.cars[i]["type"] == &"boxcar":
			bi = i
	TestLib.check(bi >= 0 and jobs.step == &"board", "HEIST starts: board the ore train")
	_p.global_position = ore.car_xf(bi) * Vector3(0.0, TrainKit.FLOOR + 0.5, 0.0) + Vector3(0.0, 0.0, 0.0)
	await _until(func() -> bool: return jobs.step == &"roof", 3.0)
	TestLib.check(jobs.step == &"roof", "on the train: CLIMB ONTO A BOX CAR ROOF")
	_p.global_position = ore.car_xf(bi) * Vector3(0.0, float(ore.cars[bi]["spec"]["roof_y"]) + 0.5, 0.0)
	var got := await _until(func() -> bool: return jobs.step == &"escape", 9.0)
	TestLib.check(got, "holding the roof for 4 s secures the loot")
	_p.teleport_to(_station_platform(RailNet.route(&"mountain"), 0) + Vector3(0.0, 0.0, 0.0) + Vector3(30.0, 0.0, 0.0))
	await _until(func() -> bool: return jobs.active == &"", 5.0)
	TestLib.check(jobs.active == &"" and _credits() >= c1 + int(RailJobs.PAY[&"heist"]), "jumping off ends the heist and pays (%d -> %d)" % [c1, _credits()])
	_rw.jobs._cool = 0.0
	jobs.abort()


func _ships() -> void:
	var s := _sw.ship_node(&"destroyer")
	TestLib.check(s != null and s.type == &"destroyer", "the fleet has a destroyer at the harbour")
	_p.teleport_to(s.helm_world() + Vector3(0.0, 1.0, 0.0))
	_sw.ensure_near(_p.global_position, 600.0)
	await _hold(1.0)
	TestLib.check(s.built and s.turret_nodes.size() == 2, "the destroyer is built with its two gun turrets")
	_p.global_position = s.helm_world() + Vector3(0.0, 0.6, 0.0)
	_p.velocity = Vector3.ZERO
	await _hold(0.8)
	var on_deck := _p.global_position.y > s.global_position.y + 4.0
	TestLib.check(on_deck and _sw.use_prompt() == "TAKE HELM" and RideUse.prompt() == "TAKE HELM", "on the bridge the USE says TAKE HELM (hero %.1f m over the waterline)" % (_p.global_position.y - s.global_position.y))
	_sw.use_do()
	TestLib.check(_sw.helm_ship == s and s.mode == &"helm" and _p.control_hold, "at the helm: the hero steers the ship")
	var p0 := s.sim_pos
	Input.action_press(&"move_forward")
	var moved := await _until(func() -> bool: return Vector2(s.sim_pos.x - p0.x, s.sim_pos.z - p0.z).length() > 40.0 and s.speed > 4.0, 30.0)
	var h0 := s.heading
	Input.action_press(&"move_left")
	await _hold(1.5)
	Input.action_release(&"move_left")
	Input.action_release(&"move_forward")
	var lp := s.global_transform.affine_inverse() * _p.global_position
	var deep_now := TerrainHeight.depth_at(s.sim_pos.x, s.sim_pos.z)
	TestLib.check(moved and wrapf(s.heading - h0, -PI, PI) > 0.03 and deep_now >= float(s.spec["draft"]), "the destroyer sails (%.0f m, %.1f m/s), turns to port and stays afloat (%.1f m of water)" % [Vector2(s.sim_pos.x - p0.x, s.sim_pos.z - p0.z).length(), s.speed, deep_now])
	TestLib.check(absf(lp.x) < 10.0 and absf(lp.z) < 75.0 and lp.y > 3.0, "the hero was carried on the bridge (local %.1f, %.1f, %.1f)" % [lp.x, lp.y, lp.z])
	_sw.use_do()
	TestLib.check(_sw.helm_ship == null and not _p.control_hold, "leaving the helm gives the hero back his feet")
	# run aground: a ship driven at the shore stops in the water
	s.heading = 0.0                                          # bow north, at the quay wall
	s.speed = 8.0
	s.teleport(Vector3(-200.0, 0.0, 1688.0))
	var g0 := s.groundings
	for i in 240:
		s.step_helm(0.05, 1.0, 0.0)
	TestLib.check(s.groundings > g0 and TerrainHeight.depth_at(s.sim_pos.x, s.sim_pos.z) >= float(s.spec["draft"]) + 0.3, "driven at the quay the ship runs aground in the water, not onto the land (%d groundings)" % (s.groundings - g0))
	# the helipad is solid and the guns
	s.heading = float(ShipWorld.FLEET[0]["h"])
	s.speed = 0.0
	s.teleport(s.home)
	await _hold(0.3)
	var pad := s.pad_world()
	var q := PhysicsRayQueryParameters3D.create(pad + Vector3(0.0, 6.0, 0.0), pad + Vector3(0.0, -4.0, 0.0), Game.L_WORLD)
	var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
	TestLib.check(not hit.is_empty() and absf((hit["position"] as Vector3).y - pad.y) < 0.6, "the helipad is solid at its height (%.1f vs %.1f)" % [(hit["position"] as Vector3).y if not hit.is_empty() else -99.0, pad.y])
	_p.global_position = s.gun_world(0) + Vector3(0.0, 1.5, 3.0)
	_p.velocity = Vector3.ZERO
	await _hold(0.6)
	TestLib.check(_sw.use_prompt() == "MAN GUN", "at the forward turret the USE says MAN GUN")
	_sw.use_do()
	TestLib.check(_sw.gun_ship == s and s.manned == 0, "manning the gun")
	var blasts := {"n": 0}
	var cb := func(_pos: Vector3, _r: float) -> void: blasts["n"] += 1
	Game.exploded.connect(cb)
	Input.action_press(&"fire")
	var fired := await _until(func() -> bool: return _sw.shots >= 1, 4.0)
	Input.action_release(&"fire")
	var burst := await _until(func() -> bool: return int(blasts["n"]) >= 1, 8.0)
	Game.exploded.disconnect(cb)
	TestLib.check(fired and burst, "FIRE sends a shell and it explodes (%d shots, %d blasts)" % [_sw.shots, blasts["n"]])
	_sw.use_do()
	# the sea lanes: the cruise liner is built when the hero is near and sails
	var cr := _sw.ship_node(&"cruise")
	cr.build()
	var a := cr.lane_at(cr.lane_u + cr.lane_speed * 10.0)
	var b := cr.lane_at(cr.lane_u + cr.lane_speed * 40.0)
	var moved_lane := (a[0] as Vector2).distance_to(b[0] as Vector2)
	TestLib.check(cr.built and moved_lane > 100.0 and cr.lane_length() > 1500.0 and float(_sw.stats()["tris"]) > 3000.0, "the cruise liner sails a %.0f m loop by the clock (%.0f m in 30 s)" % [cr.lane_length(), moved_lane])
