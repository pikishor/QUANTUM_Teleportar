extends "res://tests/wm_base.gd"
## AIR AND VEHICLE MISSIONS (wave 107), part 1: data, the board and the ground / water / airport missions. Data first, then the REAL game scene:
##  * WorldSites / WorldMissions / PathFollow: six mission types (airport heist, helicopter extraction, mountain pursuit, river chase, air race, plane delivery) build at every origin, validate as
##    campaign chapters, put every goal on land (or water for the boat) and every air gate clear of the ground; the board puts a world mission on offer by location;
##  * live: a MOUNTAIN PURSUIT is driven for real (a 4x4 waits at the foot of the road, a scripted pickup runs the road, the hero boxes it in), a RIVER CHASE in a real boat down the real river,
##    an AIRPORT HEIST (real hangar guard, plane on the strip) and a PLANE DELIVERY walked through their steps, each through the Mission Board with its pay and its reward for the weapon ladder;
##    a failed vehicle step begins again with a fresh target and a stuck one recovers; held vehicles are not streamed away.
## Part 2 (test_world_missions_air.gd): air race and helicopter extraction. Part 3 (test_world_roam.gd): the free-roam courses and the treasure hunt.
## Run: tools/test.sh tests/test_world_missions.gd   (waits on positions, counters and game time, never on frame counts; WM_ONLY=pursuit,river,... runs parts while developing)

const TIMEOUT_SECONDS := 140.0

var _only: PackedStringArray = PackedStringArray()


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", WorldRoam.SAVE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var env := OS.get_environment("WM_ONLY")
	if env != "":
		_only = env.split(",")
	_data()
	var main := await _boot(host)
	if main == null:
		return
	_roam.reset()
	_board.world_offers = true
	if _want("offers"):
		await _offers()
	if _want("pursuit"):
		await _pursuit()
	if _want("stuck"):
		await _stuck()
	if _want("heist"):
		await _heist()
	if _want("delivery"):
		await _delivery()
	if _want("river"):
		await _river()
	await _shutdown(main)


func _want(part: String) -> bool:
	return _only.is_empty() or _only.has(part)


func _data() -> void:
	TerrainHeight.warm()
	WaterLayout.ensure()
	OutskirtsSites.ensure()
	TestLib.check(WorldMissions.TYPES.size() == 6 and WorldMissions.DEFS.size() == 6, "six world mission types")
	TestLib.check(MissionBoard.TYPES.size() == 16 and MissionBoard.DEFS.size() == 16, "the sixteen city types are untouched")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var origins := [Vector3.ZERO, Vector3(1500.0, 0.0, 300.0), Vector3(-400.0, 0.0, -1900.0), Vector3(-1300.0, 0.0, 900.0)]
	var all_valid := true
	var texts_ok := true
	var kinds := {}
	var dry_ok := true
	for t in WorldMissions.TYPES:
		for org: Vector3 in origins:
			var rec := WorldMissions.build(t, 1, org, rng)
			if rec.is_empty():
				all_valid = false
				printerr("%s at %s: no recipe" % [t, str(org)])
				continue
			var why := CampaignSteps.validate_chapter({"steps": rec["steps"]})
			if not why.is_empty():
				all_valid = false
				printerr("%s: %s" % [t, str(why)])
			TestLib.check(float(rec["route_m"]) > 300.0, "%s has a real route (%d m)" % [t, int(float(rec["route_m"]))])
			if (rec["steps"] as Array).size() < 3:
				all_valid = false
			for st: Dictionary in rec["steps"]:
				kinds[StringName(st["kind"])] = true
				if str(st["text"]).length() > 40:
					texts_ok = false
					printerr("text too long: %s" % st["text"])
				var pos: Vector3 = st["pos"]
				if not pos.is_finite():
					all_valid = false
				var need := StringName(str(st.get("veh", "")))
				if need == &"boat":
					dry_ok = dry_ok and TerrainHeight.depth_at(pos.x, pos.z) > 1.0
				elif need == &"" and String(st["kind"]) == "reach":
					dry_ok = dry_ok and TerrainHeight.depth_at(pos.x, pos.z) <= 0.0
	TestLib.check(all_valid, "every recipe builds at every origin, validates as a chapter and has at least three steps")
	TestLib.check(texts_ok, "every objective line is short")
	for k: StringName in [&"reach", &"gates", &"pursuit", &"kill_target", &"defend"]:
		TestLib.check(kinds.has(k), "the recipes use the step kind %s" % k)
	TestLib.check(dry_ok, "walk-to goals are on dry land, the boat's goals on deep water")
	# locations
	var ap := WorldSites.airport()
	TestLib.check((ap["strip"] as Vector3).is_finite() and (ap["gate"] as Vector3).is_finite() and (ap["hangar"] as Vector3).is_finite(), "the airport has a gate, a strip and a hangar (real: %s)" % str(ap["real"]))
	TestLib.check(WorldSites.heli_pads().size() >= 3 and WorldSites.landing_fields().size() >= 3, "helicopter pads and plane fields exist in the mountains and outskirts")
	for rn in WorldSites.CHASE_ROADS:
		var rt := WorldSites.road_route(rn)
		TestLib.check(rt.size() > 5 and WorldSites.length_of(rt) > 200.0, "road route %s: %d points, %d m" % [rn, rt.size(), int(WorldSites.length_of(rt))])
	# the canyons: every gate clear of the ground by 8 m, every leg clear all along
	for c in WorldSites.CANYONS:
		var gs := WorldSites.canyon_gates(c)
		TestLib.check(gs.size() >= 8, "%s has %d gates" % [c["name"], gs.size()])
		TestLib.check(_legs_clear(gs, 8.0), "%s: the line between every two gates is clear of the terrain" % c["name"])
	# path following maths
	var pf := PathFollow.new(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -100), Vector3(100, 0, -200)]))
	TestLib.check(is_equal_approx(pf.total, 100.0 + sqrt(2.0) * 100.0) and pf.is_valid(), "path length")
	pf.advance(Vector3(0, 0, -40))
	var s1 := pf.s
	pf.advance(Vector3(0, 0, -10))
	TestLib.check(pf.s >= s1 and absf(s1 - 40.0) < 1.0, "the position along the line only grows (%.1f)" % pf.s)
	TestLib.check(pf.point_at(100.0).distance_to(Vector3(0, 0, -100)) < 0.01 and pf.point_at(-5.0) == Vector3(0, 0, 0), "point_at clamps and interpolates")
	TestLib.check(WorldSteps.seg_dist(Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(50, 3, 0)) < 3.01, "a segment passes a gate between two frames")
	TestLib.check(WorldMissions.pay_for(500.0, 2000.0, 0) > WorldMissions.pay_for(500.0, 500.0, 0) and WorldMissions.pay_for(500.0, 1000.0, 2) > WorldMissions.pay_for(500.0, 1000.0, 0), "pay grows with the route and the tier")


func _offers() -> void:
	_board.world_offers = false
	var plain := 0
	for i in 8:
		var offs := _board.generate(Vector3(-385.0, 0.0, -1970.0))
		for o in offs:
			if WorldMissions.DEFS.has(StringName(o["type"])):
				plain += 1
	TestLib.check(plain == 0, "with the flag off the board never offers a world mission")
	_board.world_offers = true
	var near_lodge := 0
	var types := {}
	for i in 6:
		var offs := _board.generate(Vector3(-385.0, 0.0, -1970.0))
		var has := false
		for o in offs:
			var t := StringName(o["type"])
			if WorldMissions.DEFS.has(t):
				has = true
				types[t] = true
				TestLib.check(bool(o["world"]) and float(o["reward"]) >= 400.0 and (o["pos"] as Vector3).is_finite() and (o["chapter"]["steps"] as Array).size() >= 3, "offer %s: pay %d, a chapter of %d steps" % [t, int(o["reward"]), (o["chapter"]["steps"] as Array).size()])
		if has:
			near_lodge += 1
	TestLib.check(near_lodge == 6, "standing at the lodge the board offers a world mission every time (%d of 6, %s)" % [near_lodge, str(types.keys())])
	var offs2 := _board.generate(Vector3.ZERO)
	TestLib.check(offs2.size() == 3, "three offers anywhere")
	var distinct := {}
	for o in offs2:
		distinct[o["type"]] = true
	TestLib.check(distinct.size() == 3, "and three different types")


func _pursuit() -> void:
	_clear_vehicles()
	TrafficField.bare_street()                # the pursuit tests the mission, not the road traffic and the driveway cars of DUST WELLS the 4x4 would meet at the foot of the track
	var route := WorldSites.road_route("QUARRY TRACK")
	var dust := Vector3(1520.0, 0.0, 330.0)
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	await _land_hero(dust)
	var o := await _start(&"mountain_pursuit", dust)
	if o.is_empty():
		return
	var st0: Dictionary = o["steps"][0]
	TestLib.check(str(st0["text"]).contains("QUARRY TRACK") and StringName(str(st0["veh"])) == &"ground", "the first step sends the hero to the road in a ground vehicle (%s)" % str(st0["text"]))
	var got := await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	TestLib.check(got and _camp.ws.provided[0].kind == &"suv" and _camp.ws.provided[0].has_meta(&"hold"), "a 4x4 waits at the foot of the road and is held against streaming")
	TestLib.check(_camp.hud_line().contains("GET IN A CAR"), "on foot the line says what to do: %s" % _camp.hud_line())
	var suv: Vehicle = _camp.ws.provided[0]
	TestLib.check(suv.global_position.distance_to(route[0]) < 14.0, "it stands at the start of the road (%.1f m)" % suv.global_position.distance_to(route[0]))
	await _enter(suv)
	var on := await _step_is(1, &"pursuit", 6.0)
	TestLib.check(on, "in the 4x4 the pursuit begins")
	if not on:
		return
	var ws := _camp.ws
	var tgt: Vehicle = ws.target
	TestLib.check(tgt.scripted and tgt.kind == &"pickup" and tgt.global_position.distance_to(suv.global_position) > 40.0 and tgt.global_position.distance_to(suv.global_position) < 110.0, "the smuggler's pickup is a script-driven vehicle %.0f m ahead" % tgt.global_position.distance_to(suv.global_position))
	var pf := PathFollow.new(route)
	var s_first := ws.path.s
	var s_max := s_first
	var near_min := 999.0
	var t0 := Time.get_ticks_msec()
	while _camp.kind == &"pursuit" and _camp.state == &"active" and float(Time.get_ticks_msec() - t0) < 60000.0:
		if ws.path != null:
			s_max = maxf(s_max, ws.path.s)
		if is_instance_valid(tgt):
			near_min = minf(near_min, tgt.global_position.distance_to(suv.global_position))
		_steer_along(suv, pf, 21.0)
		await _host.get_tree().process_frame
	_release()
	TestLib.check(s_max > s_first + 120.0, "the target ran along the road (%.0f m of it)" % (s_max - s_first))
	TestLib.check(_camp.step_index >= 2, "the hero caught it and the step is done (step %d, closest %.1f m)" % [_camp.step_index, near_min])
	# the last step: secure the cargo at the top of the road (a hop, the climb is the same road)
	if await _step_is(2, &"reach", 6.0):
		suv.global_position = Vector3(route[route.size() - 1].x, route[route.size() - 1].y + 1.0, route[route.size() - 1].z)
		suv.speed = 0.0
	await _finish_check(o, "mountain pursuit", credits0, done0)
	await TestLib.frames(_host, 3)
	TestLib.check(_camp.ws.provided.is_empty() and not suv.has_meta(&"hold"), "the held vehicles are released when the mission ends")


func _river() -> void:
	_clear_vehicles()
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	var ri := int(WorldMissions.RIVER_CHASE["river"])
	var i0 := int(WorldMissions.RIVER_CHASE["from"])
	var route := WorldSites.river_route(ri, i0, int(WorldMissions.RIVER_CHASE["to"]))
	WaterLayout.ensure()
	var rp: PackedVector2Array = (WaterLayout.paths[ri] as Dictionary)["pos"]
	var ctr := Vector3(rp[i0].x, 0.0, rp[i0].y)
	await _land_hero(ctr + Vector3(60.0, 0.0, 60.0))
	var o := await _start(&"river_chase", _p.global_position)
	if o.is_empty():
		return
	var put: Vector3 = o["steps"][0]["pos"]
	TestLib.check(TerrainHeight.depth_at(put.x, put.z) > 1.5, "the boat is left on deep water at the bank (%.1f m deep)" % TerrainHeight.depth_at(put.x, put.z))
	var got := await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	if not got:
		TestLib.check(false, "a boat waits on the river")
		return
	var boat: Vehicle = _camp.ws.provided[0]
	TestLib.check(boat.kind == &"boat" and boat.cls == &"boat" and boat.craft != null and boat.craft.sea, "a speedboat floats on the real river (%s, sea %s)" % [boat.kind, str(boat.craft.sea)])
	TestLib.check(_camp.hud_line().contains("GET IN A BOAT"), "on foot the line says GET IN A BOAT: %s" % _camp.hud_line())
	await _enter(boat)
	var on := await _step_is(1, &"pursuit", 6.0)
	TestLib.check(on, "in the boat the chase begins")
	if not on:
		return
	var ws := _camp.ws
	var tgt: Vehicle = ws.target
	TestLib.check(tgt.cls == &"boat" and tgt.scripted, "the smuggler's boat is script-driven on the water")
	var pf := PathFollow.new(route)
	var s_first := ws.path.s
	var s_max := s_first
	var t0 := Time.get_ticks_msec()
	while _camp.kind == &"pursuit" and _camp.state == &"active" and float(Time.get_ticks_msec() - t0) < 70000.0:
		if ws.path != null:
			s_max = maxf(s_max, ws.path.s)
		_steer_along(boat, pf, 23.0)
		await _host.get_tree().process_frame
	TestLib.check(s_max > s_first + 150.0, "the smuggler's boat ran down the river (%.0f m)" % (s_max - s_first))
	TestLib.check(_camp.step_index >= 2, "the boat was caught (step %d)" % _camp.step_index)
	# follow to the mouth for real
	var t1 := Time.get_ticks_msec()
	while (_camp.state == &"active" or _camp.state == &"armed") and _camp.step_index == 2 and float(Time.get_ticks_msec() - t1) < 6000.0:
		_steer_along(boat, pf, 24.0)
		await _host.get_tree().process_frame
	_release()
	if _camp.step_index == 2:                                                       # the rest of the river is the same water: the last hundred metres by a hop (the test's time budget)
		var q := pf.point_at(pf.total - 20.0)
		boat.global_position = Vector3(q.x, boat.global_position.y, q.z)
		boat.speed = 0.0
		await _hold(0.5)
	TestLib.check(boat.craft.groundings <= 3, "the boat did not run aground more than three times (%d)" % boat.craft.groundings)
	await _finish_check(o, "river chase", credits0, done0)


func _heist() -> void:
	_clear_vehicles()
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	var ap := WorldSites.airport()
	var gate: Vector3 = ap["gate"]
	await _land_hero(gate + Vector3(-60.0, 0.0, 0.0))
	var o := await _start(&"airport_heist", _p.global_position)
	if o.is_empty():
		return
	TestLib.check(str(o["steps"][0]["text"]).contains("AIRPORT"), "step 1: get to the airport (%s)" % str(o["steps"][0]["text"]))
	var car := _vm.spawn_parked(&"sport", gate + Vector3(-30.0, 0.0, 0.0), 0.0)
	await _enter(car)
	car.global_position = Vector3(gate.x, car.global_position.y, gate.z)
	car.speed = 0.0
	TestLib.check(await _step_is(1, &"kill_target", 6.0), "at the gate the hangar fight begins")
	await _hold(0.5)
	var foes := 0
	for f: Variant in _camp.foes:
		if is_instance_valid(f):
			foes += 1
	TestLib.check(_camp.target != null and is_instance_valid(_camp.target), "a real guard stands at the hangar (%d more)" % foes)
	if _camp.target != null and is_instance_valid(_camp.target):
		_camp.target.damage(1.0e6)
	TestLib.check(await _step_is(2, &"reach", 8.0), "with the guard down the plane is next")
	var got := await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	var plane: Vehicle = _camp.ws.provided[0] if got else null
	TestLib.check(plane != null and plane.kind == &"plane" and plane.global_position.distance_to(ap["strip"]) < 40.0, "a plane waits on the strip")
	if plane == null:
		return
	TestLib.check(_camp.hud_line().contains("GET IN THE PLANE"), "in the car the line says GET IN THE PLANE: %s" % _camp.hud_line())
	await _enter(plane)
	TestLib.check(await _step_is(3, &"reach", 6.0), "in the plane: fly out and land is the last step")
	var field: Vector3 = o["steps"][3]["pos"]
	# in the air above the field: not done; on the ground, slow: done
	plane.global_position = Vector3(field.x, field.y + 50.0, field.z)
	plane.craft.airborne = true
	plane.craft.agl = 50.0
	plane.speed = 30.0
	await _hold(0.4)
	TestLib.check(_camp.step_index == 3 and _camp.hud_line().contains("LAND IT"), "above the field the step waits for a landing: %s" % _camp.hud_line())
	plane.global_position = Vector3(field.x, field.y + 0.3, field.z)
	plane.craft.airborne = false
	plane.craft.agl = 0.0
	plane.speed = 0.0
	await _finish_check(o, "airport heist", credits0, done0)


func _delivery() -> void:
	_clear_vehicles()
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	var ap := WorldSites.airport()
	var strip: Vector3 = ap["strip"]
	await _land_hero(strip + Vector3(0.0, 0.0, 30.0))
	var o := await _start(&"plane_delivery", strip)
	if o.is_empty():
		return
	var got := await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	var plane: Vehicle = _camp.ws.provided[0] if got else null
	TestLib.check(plane != null and plane.kind == &"plane", "a cargo plane waits on the strip")
	if plane == null:
		return
	await _enter(plane)
	TestLib.check(await _step_is(1, &"reach", 6.0), "in the plane: the delivery flight")
	var field: Vector3 = o["steps"][1]["pos"]
	TestLib.check(_camp.hud_line().contains("M"), "the line shows the distance: %s" % _camp.hud_line())
	plane.global_position = Vector3(field.x, field.y + 25.0, field.z)
	plane.craft.airborne = true                                                   # low over the field, still flying: no landing yet
	plane.craft.agl = 25.0
	plane.speed = 30.0
	await TestLib.frames(_host, 3)
	TestLib.check(_camp.step_index == 1, "flying low over the field is not a delivery")
	plane.global_position = Vector3(field.x, field.y + 0.3, field.z)
	plane.craft.airborne = false
	plane.craft.agl = 0.0
	plane.speed = 45.0
	plane.vel = plane.forward() * 45.0
	await TestLib.frames(_host, 2)
	TestLib.check(_camp.step_index == 1, "touching down at speed is not a delivery either (%.0f m/s)" % plane.speed)
	plane.speed = 0.0
	plane.vel = Vector3.ZERO
	TestLib.check(await _step_is(2, &"reach", 5.0), "stopped on the field the plane is delivered, the buyer is next")
	plane.craft.agl = 0.0
	_vm.exit_vehicle()
	var buyer: Vector3 = o["steps"][2]["pos"]
	await _land_hero(buyer)
	await _finish_check(o, "plane delivery", credits0, done0)


## A stuck or failed vehicle step never traps the hero: a failed pursuit begins again with a fresh target (the old one goes back to the pool), and the game's own recovery completes a step.
func _stuck() -> void:
	_clear_vehicles()
	var route := WorldSites.road_route("QUARRY TRACK")
	var dust := Vector3(1520.0, 0.0, 330.0)
	await _land_hero(dust)
	var o := await _start(&"mountain_pursuit", dust)
	if o.is_empty():
		return
	await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	var suv: Vehicle = _camp.ws.provided[0]
	await _enter(suv)
	if not await _step_is(1, &"pursuit", 6.0):
		TestLib.check(false, "the pursuit began")
		return
	var first: Vehicle = _camp.ws.target
	_camp._fail("TEST")
	TestLib.check(await _until(func() -> bool: return _camp.state == &"retry" or _camp.state == &"armed", 4.0), "a failed pursuit step goes to the retry")
	TestLib.check(await _step_is(1, &"pursuit", 8.0), "and begins again by itself")
	var second: Vehicle = _camp.ws.target
	var scripted_n := 0
	for v in _vm.list:
		if v.scripted:
			scripted_n += 1
	TestLib.check(second != null and scripted_n == 1 and second.hp >= second.max_hp - 0.1 and _camp.ws.path.s < 120.0, "with a fresh target at the start of the run, and only one scripted vehicle on the road (%d)" % scripted_n)
	TestLib.check(_camp.fails >= 1, "the failure is counted (%d)" % _camp.fails)
	# nothing moves for a long time: the recovery finishes the step
	TestLib.check(_camp.recover_step() and await _until(func() -> bool: return _camp.step_index >= 2, 4.0), "the game's own recovery completes a stuck pursuit step")
	suv.global_position = Vector3(route[route.size() - 1].x, route[route.size() - 1].y + 1.0, route[route.size() - 1].z)
	suv.speed = 0.0
	await _until(func() -> bool: return _board.state == &"idle", 8.0)
	# a held vehicle is not streamed away
	_clear_vehicles()
	var heli := _vm.spawn_parked(&"heli", dust + Vector3(40.0, 0.0, 0.0), 0.0)
	heli.set_meta(&"hold", true)
	_vm._stream()
	TestLib.check(heli.active, "a held vehicle survives the streaming pass")
	heli.remove_meta(&"hold")
	_board.abandon("TEST")
