extends "res://tests/wm_base.gd"
## FREE ROAM IN THE BIG WORLD (wave 107): FLIGHT SCHOOL, OFF-ROAD TRIAL and JET-SKI LAPS start by themselves in their start ring, count the gates in order, pay by time, keep the best time (saved), feed
## the weapon ladder on the first finish only and pay half on a repeat; a course ends when the hero leaves the vehicle for good and no course starts while a board mission runs; the TREASURE HUNT
## hands the scanner over, reveals caches with the real scanner pulse (beam, minimap pin, a ping for the far ones), pays for each dug-out cache, counts every third as a mission and saves.
## Run: tools/test.sh tests/test_world_roam.gd

const TIMEOUT_SECONDS := 140.0


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", WorldRoam.SAVE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	TerrainHeight.warm()
	WaterLayout.ensure()
	OutskirtsSites.ensure()
	_data()
	var main := await _boot(host)
	if main == null:
		return
	_roam.reset()
	var only := OS.get_environment("WM_ONLY")
	if only == "" or only.contains("roam"):
		await _roam_courses()
	if only == "" or only.contains("treasure"):
		await _treasure()
	await _shutdown(main)


func _data() -> void:
	# roam courses (data)
	var wr := WorldRoam.new()
	for id in WorldRoam.COURSE_IDS:
		var c := wr.course(id)
		TestLib.check(not c.is_empty() and (c["gates"] as Array).size() >= 5 and (c["start"] as Vector3).is_finite(), "%s: a course of %d gates" % [id, (c["gates"] as Array).size() if not c.is_empty() else 0])
	var fs := wr.course(&"flight_school")
	var fg: Array[Vector3] = fs["gates"]
	TestLib.check(_legs_clear(fg, 6.0), "flight school: no gate or leg is inside the terrain")
	var jet := wr.course(&"jetski")
	var wet := true
	for g: Vector3 in jet["gates"]:
		wet = wet and TerrainHeight.depth_at(g.x, g.z) > 1.0
	TestLib.check(wet, "jet-ski laps: every buoy has deep water under it")
	TestLib.check(wr.caches().size() == 6, "six caches hide around the outskirts")
	var cache_ok := true
	for cc in wr.caches():
		var cp: Vector3 = cc["pos"]
		cache_ok = cache_ok and TerrainHeight.depth_at(cp.x, cp.z) <= 0.0
	TestLib.check(cache_ok, "every cache is on dry land")
	TestLib.check(WorldRoam.pay_for(&"jetski", 40.0) > WorldRoam.pay_for(&"jetski", 200.0), "a faster lap pays more")
	TestLib.check(WorldRoam._compass(Vector2(0.0, -10.0)) == "NORTH" and WorldRoam._compass(Vector2(10.0, 0.0)) == "EAST", "the scanner ping names a direction")
	wr.free()


func _roam_run(id: StringName, kind: StringName, label: String) -> void:
	var c := _roam.course(id)
	var st: Vector3 = c["start"]
	var v := _vm.spawn_parked(kind, st + Vector3(0.0, 0.0, 0.0), 0.0)
	TestLib.check(v != null, "%s: a %s is at the start" % [label, kind])
	if v == null:
		return
	await _enter(v)
	if v.craft != null and (kind == &"heli" or kind == &"plane"):
		v.craft.airborne = true
		v.global_position = st + Vector3(0.0, 12.0, 0.0)
	v.speed = 6.0
	if not (kind == &"heli" or kind == &"plane"):
		Input.action_press(&"move_forward")                                    # a car or a boat has to be under way: the stick forward, as a player has it
	var started := await _until(func() -> bool: return _roam.active == id, 4.0)
	Input.action_release(&"move_forward")
	TestLib.check(started, "%s starts by itself when the hero drives into the start ring" % label)
	if not started:
		return
	var gates: Array[Vector3] = c["gates"]
	var seen := 0
	var g_taken := []
	var cb := func(gid: StringName, i: int) -> void: g_taken.append(i)
	_roam.gate_passed.connect(cb)
	for g: Vector3 in gates:
		v.global_position = g
		v.speed = 8.0
		await TestLib.frames(_host, 3)
		seen += 1
	_roam.gate_passed.disconnect(cb)
	TestLib.check(g_taken.size() == gates.size() and g_taken[0] == 0, "%s: %d gates counted in order" % [label, g_taken.size()])


func _roam_courses() -> void:
	_clear_vehicles()
	if _board.is_running():
		_board.abandon("TEST")
	var prog := Game.progress as Progress
	var fin := []
	_roam.finished.connect(func(id: StringName, ok: bool, reward: int) -> void: fin.append([id, ok, reward]))
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	var fs_start: Vector3 = _roam.course(&"flight_school")["start"]
	await _land_hero(fs_start + Vector3(-60.0, 0.0, 30.0))
	# FLIGHT SCHOOL
	await _roam_run(&"flight_school", &"heli", "flight school")
	await _until(func() -> bool: return not fin.is_empty(), 3.0)
	TestLib.check(fin.size() == 1 and fin[0][0] == &"flight_school" and fin[0][1] and int(fin[0][2]) >= 300, "flight school pays %s" % str(fin))
	TestLib.check(prog.credits >= credits0 + int(fin[0][2]), "the credits arrive (%d -> %d)" % [credits0, prog.credits])
	TestLib.check(MissionRewards.missions_done == done0 + 1, "the first finish counts as a mission for the weapon ladder (%d -> %d)" % [done0, MissionRewards.missions_done])
	TestLib.check(float(_roam.best.get(&"flight_school", 0.0)) > 0.0 and FileAccess.file_exists(WorldRoam.SAVE_PATH), "the best time is kept and saved")
	TestLib.check(_roam.active == &"" and (_roam.marks == null or _roam.marks.shown == 0), "the gate rings are gone after the finish")
	# a repeat pays half and does not move the ladder again
	_clear_vehicles()
	await _until(func() -> bool: return _roam._cool <= 0.0, 4.0)
	var first_pay := int(fin[0][2])
	await _roam_run(&"flight_school", &"heli", "flight school (again)")
	await _until(func() -> bool: return fin.size() >= 2, 3.0)
	TestLib.check(fin.size() == 2 and int(fin[1][2]) <= first_pay / 2 + 5 and MissionRewards.missions_done == done0 + 1, "a repeat pays half and the ladder stays (%s, %d)" % [str(fin[1]), MissionRewards.missions_done])
	# OFF-ROAD TRIAL
	_clear_vehicles()
	await _until(func() -> bool: return _roam._cool <= 0.0, 4.0)
	var off := _roam.course(&"offroad")
	await _land_hero(off["start"])
	var pts := WorldRoam.vehicle_points()
	TestLib.check(pts.size() == 2 and VehicleSpawns.point(&"roam_offroad_rover").size() > 0, "a rover and a quad wait at the foot of the track (spawn points)")
	await _roam_run(&"offroad", &"rover", "off-road trial")
	await _until(func() -> bool: return fin.size() >= 3, 3.0)
	TestLib.check(fin.size() == 3 and fin[2][0] == &"offroad" and fin[2][1] and MissionRewards.missions_done == done0 + 2, "the off-road trial pays and moves the ladder once more (%s, %d)" % [str(fin[2]), MissionRewards.missions_done])
	# JET-SKI LAPS
	_clear_vehicles()
	await _until(func() -> bool: return _roam._cool <= 0.0, 4.0)
	await _land_hero(Vector3(0.0, 0.0, 1300.0))
	await _roam_run(&"jetski", &"jetski", "jet-ski laps")
	await _until(func() -> bool: return fin.size() >= 4, 3.0)
	TestLib.check(fin.size() == 4 and fin[3][0] == &"jetski" and fin[3][1] and int(fin[3][2]) >= 300, "the jet-ski laps pay (%s)" % str(fin[3]))
	# leaving the vehicle for good ends a course quietly, and a board mission blocks one
	_clear_vehicles()
	await _until(func() -> bool: return _roam._cool <= 0.0, 4.0)
	var heli := _vm.spawn_parked(&"heli", fs_start, 0.0)
	await _enter(heli)
	heli.craft.airborne = true
	heli.global_position = fs_start + Vector3(0.0, 14.0, 0.0)
	heli.speed = 6.0
	var again := await _until(func() -> bool: return _roam.active == &"flight_school", 4.0)
	TestLib.check(again, "a fourth course begins")
	_vm.exit_vehicle()
	await _land_hero(fs_start + Vector3(-80.0, 0.0, 120.0))
	TestLib.check(await _until(func() -> bool: return _roam.active == &"" and fin.size() >= 5 and not fin[4][1], 6.0), "getting out for good ends the course (%s)" % str(fin.back()))
	_clear_vehicles()
	var o := _board.build(&"patrol", _p.global_position, true)
	TestLib.check(_board.accept_offer(o), "a board mission starts")
	await _until(func() -> bool: return _board.is_running(), 3.0)
	var heli2 := _vm.spawn_parked(&"heli", fs_start, 0.0)
	await _enter(heli2)
	heli2.craft.airborne = true
	heli2.global_position = fs_start + Vector3(0.0, 14.0, 0.0)
	heli2.speed = 6.0
	await _until(func() -> bool: return _roam._cool <= 0.0, 4.0)
	await _hold(1.0)
	TestLib.check(_roam.active == &"", "while a board mission runs no course starts")
	_board.abandon("TEST")
	_clear_vehicles()


func _treasure() -> void:
	_clear_vehicles()
	if _board.is_running():
		_board.abandon("TEST")
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	Gear.owned.erase(&"scanner")
	Gear.gadget = &""
	_roam.found.clear()
	_roam.revealed.clear()
	_roam.treasure_paid = 0
	var cs := _roam.caches()
	var c0: Vector3 = cs[0]["pos"]
	var found_sigs := []
	_roam.cache_found.connect(func(i: int, total: int) -> void: found_sigs.append([i, total]))
	# 150 m from the crash site: the hunt gives the scanner for free
	await _land_hero(c0 + Vector3(150.0, 0.0, 0.0))
	TestLib.check(await _until(func() -> bool: return Gear.is_owned(&"scanner") and Gear.gadget == &"scanner", 3.0), "near the hunt the scanner pulse is handed over and equipped")
	# a pulse from 60 m reveals the caches of the crash site and shows their beams
	await _land_hero(c0 + Vector3(60.0, 0.0, 0.0))
	_p.energy = 100.0
	var used := _p.gadgets.use()
	TestLib.check(used, "the real scanner pulse fires")
	await _hold(0.5)
	TestLib.check(_roam.scans >= 1 and _roam.revealed.has(0), "the pulse revealed the nearest cache (%s)" % str(_roam.revealed.keys()))
	TestLib.check(_roam._beams.size() > 0 and _roam._beams[0].visible, "its beam stands in the world")
	var mk := _roam.markers()
	var has_pin := false
	for m: Dictionary in mk:
		if String(m["label"]) == "CACHE":
			has_pin = true
	TestLib.check(has_pin, "and it is a pin on the minimap")
	# a faint pulse from farther away names a direction
	_roam.revealed.clear()
	var pings0 := _roam.pings
	_roam.scan(c0 + Vector3(180.0, 0.0, 0.0))
	TestLib.check(_roam.pings == pings0 + 1, "a pulse from 180 m only pings the direction")
	# dig them out: walking up to each pays; every third counts as a mission
	for i in cs.size():
		var p: Vector3 = cs[i]["pos"]
		await _land_hero(p + Vector3(0.0, 0.0, 0.8))
		var ok := await _until(func() -> bool: return _roam.found.has(i), 3.0)
		TestLib.check(ok, "cache %d (%s) is dug out" % [i, cs[i]["name"]])
	TestLib.check(_roam.found_count() == 6 and found_sigs.size() == 6 and int(found_sigs[5][1]) == 6, "six caches found, six signals")
	TestLib.check(prog.credits >= credits0 + 6 * WorldRoam.CACHE_PAY + WorldRoam.ALL_BONUS, "the caches paid (%d -> %d)" % [credits0, prog.credits])
	TestLib.check(_roam.treasure_paid == 2 and MissionRewards.missions_done == done0 + 2, "every third cache counts as a mission for the weapon ladder (%d -> %d)" % [done0, MissionRewards.missions_done])
	var wr2 := WorldRoam.new()
	wr2._load()
	TestLib.check(wr2.found.size() == 6, "the found caches are saved (%d)" % wr2.found.size())
	wr2.free()
	_roam.reset()
	TestLib.check(_roam.found.is_empty() and not FileAccess.file_exists(WorldRoam.SAVE_PATH), "a new game forgets them")

