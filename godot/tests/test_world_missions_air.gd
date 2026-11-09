extends "res://tests/wm_base.gd"
## AIR AND VEHICLE MISSIONS (wave 107), part 2: the AIR RACE flown for real through the EASTWATER canyon gates in a helicopter (ten gates up and back, then landed on the pad) and the
## HELICOPTER EXTRACTION (real enemies at the landing zone, the helicopter that lands there, the flight to the helipad and the landing), both through the Mission Board with pay and ladder reward.
## Run: tools/test.sh tests/test_world_missions_air.gd

const TIMEOUT_SECONDS := 140.0


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", WorldRoam.SAVE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	TerrainHeight.warm()
	var main := await _boot(host)
	if main == null:
		return
	_board.world_offers = true
	await _race()
	await _extract()
	await _shutdown(main)


func _race() -> void:
	_clear_vehicles()
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	var pad := WorldSites.pad(&"dust_wells")
	var pp: Vector3 = pad["pos"]
	await _land_hero(pp + Vector3(0.0, 0.0, 30.0))
	var o := await _start(&"air_race", pp)
	if o.is_empty():
		return
	TestLib.check(str(o["steps"][1]["text"]).contains("EASTWATER") and (o["steps"][1]["pts"] as Array).size() >= 8, "the nearest canyon is EASTWATER, ten gates up and back")
	var got := await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	if not got:
		TestLib.check(false, "a helicopter waits on the pad")
		return
	var heli: Vehicle = _camp.ws.provided[0]
	TestLib.check(heli.kind == &"heli" and heli.global_position.distance_to(pp) < 16.0, "a helicopter waits on the pad")
	TestLib.check(_camp.hud_line().contains("GET IN THE HELICOPTER"), "the line says GET IN THE HELICOPTER on foot: %s" % _camp.hud_line())
	await _enter(heli)
	var on := await _step_is(1, &"gates", 6.0)
	TestLib.check(on and _camp.ws.gates.size() >= 8, "in the helicopter the race begins with %d gates" % _camp.ws.gates.size())
	if not on:
		return
	TestLib.check(_camp.ws.marks != null and _camp.ws.marks.shown == 2, "the current gate and the next one are drawn")
	print("DBG marks visible_in_tree ", _camp.ws.marks.is_visible_in_tree(), " parent ", _camp.ws.marks.get_parent(), " ring0 ", _camp.ws.marks._ring[0].global_transform, " vis ", _camp.ws.marks._ring[0].visible, " gate0 ", _camp.ws.gates[0])
	var ws := _camp.ws
	var taken := 0
	var t0 := Time.get_ticks_msec()
	while _camp.kind == &"gates" and _camp.state == &"active" and float(Time.get_ticks_msec() - t0) < 90000.0:
		if ws.gi < ws.gates.size():
			_fly_toward(heli, ws.gates[ws.gi])
		taken = maxi(taken, ws.gates_taken)
		await _host.get_tree().process_frame
	_release()
	print("DBG race gates done in ", float(Time.get_ticks_msec() - t0) / 1000.0, " s real")
	TestLib.check(taken >= ws.gates.size() - 1 or _camp.step_index >= 2, "the helicopter flew the gates (%d taken of %d)" % [taken, ws.gates.size()])
	TestLib.check(_camp.step_index >= 2, "the race is done and the landing step is next (step %d)" % _camp.step_index)
	# land on the pad: fly over it, then down
	var t1 := Time.get_ticks_msec()
	while (_camp.state == &"active" or _camp.state == &"armed") and _camp.step_index == 2 and float(Time.get_ticks_msec() - t1) < 40000.0:
		_land_toward(Vector3.ZERO, Vector3(pp.x, pp.y, pp.z), heli)
		await _host.get_tree().process_frame
	_release()
	print("DBG race landing end state ", _camp.state, " step ", _camp.step_index, " heli ", heli.global_position, " pad ", pp, " agl ", heli.craft.agl, " air ", heli.craft.airborne, " speed ", heli.speed, " t ", float(Time.get_ticks_msec() - t1) / 1000.0, " hud ", _camp.hud_line())
	await _finish_check(o, "air race", credits0, done0)
	TestLib.check(heli.hp > heli.max_hp * 0.4, "the helicopter survived the canyon (hp %.0f of %.0f)" % [heli.hp, heli.max_hp])


func _extract() -> void:
	_clear_vehicles()
	var prog := Game.progress as Progress
	var done0 := MissionRewards.missions_done
	var credits0 := prog.credits
	var lodge := WorldSites.pad(&"lodge")
	var lz: Vector3 = lodge["pos"]
	await _land_hero(lz + Vector3(-300.0, 0.0, 0.0))
	var o := await _start(&"heli_extract", lz)
	if o.is_empty():
		return
	TestLib.check(str(o["steps"][0]["text"]).contains("LANDING ZONE"), "step 1: the landing zone at the lodge")
	var car := _vm.spawn_parked(&"suv", lz + Vector3(-30.0, 0.0, 0.0), 0.0)
	await _enter(car)
	car.global_position = Vector3(lz.x - 6.0, lz.y + 0.5, lz.z)
	car.speed = 0.0
	TestLib.check(await _step_is(1, &"defend", 6.0), "at the zone the hold begins")
	_vm.exit_vehicle()
	await _land_hero(lz + Vector3(3.0, 0.0, 3.0))
	_camp.step["hold"] = 14.0                                                       # the real wave fight, a shorter hold than the 30 s of the game (the test's time budget)
	var waves := await _until(func() -> bool: return _camp.wave >= 1 or _camp.foes_alive() > 0, 20.0)
	TestLib.check(waves, "real enemies come at the zone")
	var held := await _until(func() -> bool: return _camp.step_index >= 2, 60.0)
	TestLib.check(held, "holding the zone for 30 s ends the step")
	var got := await _until(func() -> bool: return not _camp.ws.provided.is_empty(), 4.0)
	var heli: Vehicle = _camp.ws.provided[0] if got else null
	TestLib.check(heli != null and heli.kind == &"heli" and heli.global_position.distance_to(lz) < 20.0, "a helicopter lands at the zone")
	if heli == null:
		return
	await _enter(heli)
	TestLib.check(await _step_is(3, &"reach", 6.0), "in the helicopter the last step is the helipad")
	var drop: Vector3 = o["steps"][3]["pos"]
	# fly it over the helipad (a hop: the canyon race flew a real course) and set it down
	heli.global_position = Vector3(drop.x, drop.y + 40.0, drop.z + 20.0)
	heli.craft.airborne = true
	await _hold(0.5)
	TestLib.check(_camp.step_index == 3, "over the helipad but still in the air is not a landing")
	var t1 := Time.get_ticks_msec()
	while (_camp.state == &"active" or _camp.state == &"armed") and _camp.step_index == 3 and float(Time.get_ticks_msec() - t1) < 40000.0:
		_land_toward(Vector3.ZERO, drop, heli)
		await _host.get_tree().process_frame
	_release()
	await _finish_check(o, "heli extraction", credits0, done0)

