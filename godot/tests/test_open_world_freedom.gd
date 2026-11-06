extends RefCounted
## OPEN WORLD FREEDOM in the real scene (main.tscn, the big 16 x 16 city): (1) every building lot has one enterable door that glows and shows an ENTER prompt, and a door in an outer
## district really opens a room; (2) every vehicle kind (cars, bikes, buses, patrol cars, hover) can be entered and hijacked, a traffic driver is thrown out, a bus is taken at its flank,
## a moving car is caught on the run, bailing out keeps speed; the HOVER-BIKE comes with CALL CAR and the QUANTUM GLIDE burst throws the hero forward in the air; (3) street race, taxi
## fare, delivery, bounty and stunt-jump ramps are on the street, start by themselves, pay and show on the minimap; (4) QUANTUM CHARGES with a detonator, chain reactions between cars,
## charges and blasts, the grenade launcher, destructible cover. Waits on counters and state, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_open_world_freedom.gd

const SAVE := "user://test_open_world_freedom.cfg"
const SAVE_JOBS := "user://test_open_world_freedom_jobs.cfg"

var host: Node
var main: Node
var p: Player
var vm: VehicleManager
var em: EnemyManager
var hud: Hud
var prog: Progress
var fr: Freedom
var tc: TouchControls


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func _clear_cars() -> void:
	if vm.driven != null:
		vm.exit_vehicle()
	for v in vm.list.duplicate():
		if v != vm.starter:
			vm._release(v)


func _stand_beside(car: Vehicle, gap := 1.2) -> void:
	var side := car.right() * (float(car.spec["wid"]) * 0.5 + gap)
	p.teleport_to(car.global_position + side)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	for f in [SAVE, SAVE + ".bak", SAVE_JOBS, "user://freedom.cfg"]:        # the jobs file of earlier runs (found ramps, best times) would pre-pay the stunts
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	em = Game.enemies as EnemyManager
	prog = Game.progress as Progress
	fr = Freedom.current
	var huds := main.find_children("*", "Hud", true, false)
	TestLib.check(p != null and vm != null and em != null and prog != null and fr != null and not huds.is_empty(), "main.tscn composes the player, vehicles, enemies, progress, HUD and the Freedom layer")
	if p == null or vm == null or em == null or prog == null or fr == null or huds.is_empty():
		return
	hud = huds[0] as Hud
	var tcs := hud.find_children("*", "TouchControls", true, false)
	tc = tcs[0] as TouchControls if not tcs.is_empty() else null
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	fr.jobs.save_path = SAVE_JOBS
	fr.jobs.stunts.clear()
	fr.jobs.best_race = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	Game.set_quality(2)
	Game.state = &"play"
	Game.heat = 0.0
	await frames(5)
	await _doors()
	await _vehicles()
	await _hijack()
	await _hover_and_glide()
	await _jobs()
	await _stunts()
	await _explosives()
	await _cover()
	_touch_and_prompts()
	for f in [SAVE, SAVE + ".bak", SAVE_JOBS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


# --- (1) doors ----------------------------------------------------------------------------------------------------------------

func _doors() -> void:
	var city := Game.world as City
	var doors := city.doors
	var lots := city.layout.lots.size()
	TestLib.check(lots > 600, "the big city has hundreds of building lots (%d)" % lots)
	TestLib.check(doors.size() == lots, "every building lot has exactly one door (%d doors, %d lots)" % [doors.size(), lots])
	var ids := {}
	var seen_lot := {}
	var bad_front := 0
	var bad_wall := 0
	var far := 0
	var lobby_towers := 0
	for d in doors:
		ids[d["id"]] = true
		var lot := city.layout.lots[int(d["id"])]
		seen_lot[int(d["id"])] = true
		var pos: Vector3 = d["pos"]
		var wall: Vector3 = d["wall"]
		if city.is_inside_building(Vector3(pos.x, 1.0, pos.z)):
			bad_front += 1
		# the door sits on its own lot's facade: within 0.7 m of the footprint edge
		var dx := minf(absf(wall.x - lot.rect.position.x), absf(wall.x - lot.rect.end.x))
		var dz := minf(absf(wall.z - lot.rect.position.y), absf(wall.z - lot.rect.end.y))
		if minf(dx, dz) > 0.7:
			bad_wall += 1
		if Vector2(pos.x, pos.z).length() > Game.CORE_HALF + 40.0:
			far += 1
		if lot.h >= 45.0 and d["type"] == &"lobby":
			lobby_towers += 1
	TestLib.check(ids.size() == lots and seen_lot.size() == lots, "every lot has its own door id")
	TestLib.check(bad_front == 0, "no door front is inside a building (%d bad)" % bad_front)
	TestLib.check(bad_wall == 0, "every door is on the facade of its own lot (%d bad)" % bad_wall)
	TestLib.check(far > lots / 2, "most doors are in the outer districts (%d of %d)" % [far, lots])
	TestLib.check(lobby_towers > 20, "towers get a lobby door (%d)" % lobby_towers)
	var igs := main.find_children("*", "InteriorGameplay", true, false)
	var ig: InteriorGameplay = igs[0] as InteriorGameplay if not igs.is_empty() else null
	TestLib.check(ig != null, "the interior layer is in the scene")
	if ig == null:
		return
	var marks := main.find_children("*", "DoorMarkers", true, false)
	await _until(func() -> bool: return not marks.is_empty() and (marks[0] as DoorMarkers).count > 0, 3.0)
	marks = main.find_children("*", "DoorMarkers", true, false)
	TestLib.check(not marks.is_empty() and (marks[0] as DoorMarkers).count == doors.size(), "one glowing marker per door (always visible, one draw call)")
	# prompts at the nearest, the farthest and some middle doors; the farthest one really opens a room
	var order: Array[int] = [0, doors.size() - 1, doors.size() / 2, doors.size() / 3]
	var farthest := 0
	var fd := -1.0
	for i in doors.size():
		var l := Vector2((doors[i]["pos"] as Vector3).x, (doors[i]["pos"] as Vector3).z).length()
		if l > fd:
			fd = l
			farthest = i
	order.append(farthest)
	var prompts := 0
	for i in order:
		var d: Dictionary = doors[i]
		p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
		var ok := await _until(func() -> bool: return InteriorGameplay.prompt.begins_with("ENTER"), 2.0)
		if ok:
			prompts += 1
	TestLib.check(prompts == order.size(), "standing at a door always shows ENTER (%d of %d)" % [prompts, order.size()])
	var fdoor: Dictionary = doors[farthest]
	p.teleport_to((fdoor["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(4)
	TestLib.check(ig.enter(fdoor, true) and InteriorGameplay.active, "the door of the farthest outer district opens a room (%s)" % str(fdoor["name"]))
	await frames(6)
	TestLib.check(ig.leave(true) and not InteriorGameplay.active, "and the way back out works")
	await frames(6)
	p.teleport_to(Game.SPAWN)
	await frames(4)


# --- (2) vehicles, hijack -------------------------------------------------------------------------------------------------------

func _vehicles() -> void:
	var kinds: Array[StringName] = [&"sedan", &"sport", &"suv", &"bike", &"hover", &"hoverbike", &"taxi", &"wagon", &"van", &"truck", &"rover", &"skiff", &"bus", &"interceptor", &"ambulance", &"qbike", &"vael_patrol"]
	var entered := 0
	var edge_ok := 0
	for k in kinds:
		_clear_cars()
		var car := vm.spawn_parked(k, Vector3(40.0, 0.0, -9.0), -PI * 0.5)
		if car == null:
			TestLib.check(false, "%s spawns" % k)
			continue
		await frames(1)
		_stand_beside(car, 1.2)
		var got := vm.reach_car(p.global_position)
		if got == car:
			edge_ok += 1
		vm.toggle_enter_exit()
		if vm.driven == car and p.vehicle == car:
			entered += 1
		else:
			printerr("could not enter ", k)
		vm.exit_vehicle()
		await frames(1)
	TestLib.check(edge_ok == kinds.size(), "every one of %d vehicle kinds is reached from beside its hull (%d)" % [kinds.size(), edge_ok])
	TestLib.check(entered == kinds.size(), "every vehicle kind can be entered with USE (%d of %d)" % [entered, kinds.size()])
	# a bus is long: its flank 4.8 m from the middle is still in reach, its middle 4.2 m rule alone would have missed
	_clear_cars()
	var bus := vm.spawn_parked(&"bus", Vector3(40.0, 0.0, -9.0), -PI * 0.5)
	await frames(1)
	p.teleport_to(bus.global_position + bus.forward() * 3.8 + bus.right() * (1.25 + 1.5))
	TestLib.check(Vector2(p.global_position.x - bus.global_position.x, p.global_position.z - bus.global_position.z).length() > 4.2 and vm.reach_car(p.global_position) == bus,
			"a bus is taken at its flank, far from its middle")
	p.teleport_to(bus.global_position + bus.right() * 12.0)
	TestLib.check(vm.reach_car(p.global_position) == null, "12 m away nothing is in reach")
	# a moving car is caught on the run: its reach grows with its speed
	bus.speed = 0.0
	p.teleport_to(bus.global_position + bus.right() * (1.25 + 3.1))
	var still := vm.reach_car(p.global_position) == null
	bus.speed = 16.0
	TestLib.check(still and vm.reach_car(p.global_position) == bus, "a car at 16 m/s can be taken from farther than a parked one")
	bus.speed = 0.0
	_clear_cars()


func _hijack() -> void:
	var hj := Hijack.current
	TestLib.check(hj != null, "the Hijack layer exists")
	if hj == null:
		return
	for k: StringName in [&"sedan", &"taxi", &"bus", &"interceptor", &"qbike"]:
		_clear_cars()
		Game.heat = 0.0
		var car := vm.spawn_traffic(k, 0, 8, 1, 60.0)
		if car == null:
			TestLib.check(false, "traffic %s spawns" % k)
			continue
		hj.reset()
		var before := hj.hijacks
		var entries := hj.entries
		var live_before := hj.ejected_live()
		_stand_beside(car, 1.0)
		TestLib.check(car.ai and Freedom.vehicle_prompt().begins_with("HIJACK"), "%s: a traffic car shows HIJACK (%s)" % [k, Freedom.vehicle_prompt()])
		vm.toggle_enter_exit()
		TestLib.check(vm.driven == car and not car.ai, "%s: the hijack puts the hero at the wheel and takes the AI off it" % k)
		TestLib.check(hj.hijacks == before + 1 and hj.entries == entries + 1 and hj.ejected_live() >= live_before + 1, "%s: the driver is thrown out and the entry animation plays" % k)
		TestLib.check(Game.heat >= VehicleSpecs.CARJACK_HEAT - 0.001, "%s: a hijack costs heat" % k)
		vm.exit_vehicle()
		await frames(2)
	# the ejected driver lands, lies, gets up and runs: watch the first one reach the street
	var landed := await _until(func() -> bool: return hj.ejected_live() == 0 or (hj._drivers.size() > 0 and hj._drivers[0]["state"] != &"fly"), 3.0)
	TestLib.check(landed, "the ejected driver comes down (tumble, lie, run)")
	# a parked car has nobody to throw out: plain entry, no hijack count
	_clear_cars()
	var parked := vm.spawn_parked(&"sedan", Vector3(40.0, 0.0, -9.0), -PI * 0.5)
	await frames(1)
	_stand_beside(parked, 1.0)
	var hb := hj.hijacks
	var eb := hj.entries
	TestLib.check(Freedom.vehicle_prompt().begins_with("ENTER"), "a parked car shows ENTER (%s)" % Freedom.vehicle_prompt())
	vm.toggle_enter_exit()
	TestLib.check(vm.driven == parked and hj.hijacks == hb and hj.entries == eb + 1, "a parked car is entered without a driver being thrown out")
	# bailing out at speed keeps momentum (the hero rolls off the car)
	parked.speed = 13.0
	parked.vel = parked.forward() * 13.0
	vm.exit_vehicle()
	var v := Vector2(p.velocity.x, p.velocity.z).length()
	TestLib.check(v > 4.0, "leaving a fast car keeps part of its speed (%.1f m/s)" % v)
	_clear_cars()


# --- hover-bike and the quantum glide -----------------------------------------------------------------------------------------------

func _hover_and_glide() -> void:
	_clear_cars()
	p.teleport_to(Vector3(20.0, 0.1, -9.0))                    # on the main avenue, facing along it
	p.yaw = -PI * 0.5
	p.camera_rig.yaw = -PI * 0.5
	await frames(4)
	vm._bike_ready = 0.0
	var garage := vm.get_garage()
	TestLib.check(not garage.has_car(), "the garage is empty in a new campaign")
	var bike := vm.summon_any()
	TestLib.check(bike != null and bike.kind == &"hoverbike" and bike.cls == &"hover" and bike.active, "CALL CAR with an empty garage brings a quantum HOVER-BIKE")
	if bike != null:
		_stand_beside(bike, 1.0)
		vm.toggle_enter_exit()
		TestLib.check(vm.driven == bike, "the hero rides the hover-bike")
		Input.action_press(&"move_forward")
		await frames(60)
		Input.action_release(&"move_forward")
		TestLib.check(bike.speed > 12.0 and bike.speed <= float(bike.spec["max"]) + 0.5, "it is fast (%.1f m/s after a second)" % bike.speed)
		vm.exit_vehicle()
	TestLib.check(vm.summon_any() == null, "CALL CAR is on cooldown right after")
	_clear_cars()
	# the touch CALL CAR button shows with an empty garage
	if tc != null:
		tc.more_open = true
		var shown := false
		for b in TouchControls.BUTTONS:
			if b["action"] == &"garage_call":
				shown = tc.button_visible(b)
		TestLib.check(shown, "the CALL CAR button shows even without a garage car (it calls the hover-bike)")
		tc.more_open = false
	# QUANTUM GLIDE: a second jump press in the air throws the hero forward
	Input.action_release(&"jump")
	p.energy = 100.0
	p.teleport_to(Game.SPAWN + Vector3(0.0, 14.0, 0.0))
	var bursts := p.verbs.bursts
	await _until(func() -> bool: return p.air_time > 0.3, 1.5)
	Input.action_press(&"jump")
	var ok := await _until(func() -> bool: return p.verbs.bursts == bursts + 1, 1.0)
	TestLib.check(ok, "a second jump press in the air starts the QUANTUM GLIDE burst")
	await frames(6)
	var sp := Vector2(p.velocity.x, p.velocity.z).length()
	TestLib.check(p.verbs.bursting and sp > 15.0, "the burst throws the hero forward (%.1f m/s)" % sp)
	Input.action_release(&"jump")
	await _until(func() -> bool: return p.is_on_floor(), 6.0)
	p.verbs.cancel()
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	await frames(4)


# --- (3) jobs ---------------------------------------------------------------------------------------------------------------------------

func _jobs() -> void:
	var jobs := fr.jobs
	var n := 0
	for kind: StringName in FreedomData.KINDS:
		n += (FreedomData.SPOTS[kind] as Array).size()
	TestLib.check(jobs.marker_count() == n and n == 24, "24 job markers stand on the map (race, taxi, delivery, bounty x 6)")
	var city := Game.world as City
	var clear := 0
	var core := 0
	var outer := 0
	for m in jobs.marker_list():
		var pos: Vector3 = m["pos"]
		if not city.is_inside_building(Vector3(pos.x, 1.0, pos.z)) and CityLayout.on_road(pos.x, pos.z, 0.0):
			clear += 1
		if absf(pos.x) <= Game.CORE_HALF and absf(pos.z) <= Game.CORE_HALF:
			core += 1
		else:
			outer += 1
	TestLib.check(clear == n, "every marker is on a junction, never inside a building (%d of %d)" % [clear, n])
	TestLib.check(core >= 8 and outer >= 8, "markers in the core (%d) and the outer districts (%d)" % [core, outer])
	var ramps_ok := true
	for i in FreedomData.RAMPS.size():
		var r := FreedomData.ramp(i)
		for q: Vector3 in [r["pos"], r["land"], (r["pos"] as Vector3) + (r["dir"] as Vector3) * FreedomData.RAMP_LEN]:
			ramps_ok = ramps_ok and CityLayout.on_road(q.x, q.z, 0.0) and not city.is_inside_building(Vector3(q.x, 1.0, q.z))
	TestLib.check(ramps_ok, "every stunt ramp and landing ring lies on a road")
	# a marker without a vehicle: the prompt says so
	var credits0 := prog.credits
	var taxi_m := FreedomData.marker_pos(FreedomData.TAXI, 0)
	_clear_cars()
	p.teleport_to(taxi_m + Vector3(0.0, 0.1, 0.0))
	var asked := await _until(func() -> bool: return Freedom.job_prompt().contains("GET IN A VEHICLE"), 2.0)
	TestLib.check(asked and hud.hint_text().contains("GET IN A VEHICLE"), "on a taxi marker on foot the prompt says GET IN A VEHICLE (HUD line: %s)" % hud.hint_text())
	# the taxi fare starts by itself: a car standing on the marker
	var car := vm.spawn_parked(&"taxi", taxi_m + Vector3(0.0, 0.0, 1.5), -PI * 0.5)
	await frames(1)
	vm.enter(car)
	var started := await _until(func() -> bool: return jobs.active == FreedomData.TAXI, 3.0)
	TestLib.check(started, "slowing down on the marker starts the taxi fare by itself")
	TestLib.check(jobs.goal != Vector3.INF and jobs.limit > 30.0, "the fare has a destination (%.0f m away) and a clock (%.0f s)" % [Vector2(jobs.goal.x - taxi_m.x, jobs.goal.z - taxi_m.z).length(), jobs.limit])
	var mm := Freedom.markers()
	var goal_marked := false
	for m in mm:
		goal_marked = goal_marked or bool(m["goal"])
	TestLib.check(goal_marked and jobs._goal_node.visible, "the destination is a beam and a minimap marker")
	car.global_position = Vector3(jobs.goal.x, 0.0, jobs.goal.z)
	car.speed = 0.0
	car.vel = Vector3.ZERO
	var paid := await _until(func() -> bool: return int(jobs.done[FreedomData.TAXI]) == 1, 3.0)
	TestLib.check(paid and prog.credits > credits0 and jobs.active == &"", "delivering the fare pays credits (%d)" % (prog.credits - credits0))
	# timeout fails a job with no reward
	var credits1 := prog.credits
	jobs._cool = 0.0
	TestLib.check(jobs.start(FreedomData.TAXI, 1), "a second fare starts")
	jobs.elapsed = jobs.limit + 1.0
	var timed := await _until(func() -> bool: return jobs.active == &"", 2.0)
	TestLib.check(timed and prog.credits == credits1, "running out of time ends the fare without pay")
	_clear_cars()
	# street race: four gates in a loop, driven
	jobs._cool = 0.0
	var rc := vm.spawn_parked(&"sport", FreedomData.marker_pos(FreedomData.RACE, 0) + Vector3(0.0, 0.0, 1.5), -PI * 0.5)
	await frames(1)
	vm.enter(rc)
	TestLib.check(jobs.start(FreedomData.RACE, 0), "the street race starts")
	var gates := FreedomData.race_gates(0)
	var credits2 := prog.credits
	for gi in gates.size():
		rc.global_position = Vector3(gates[gi].x, 0.0, gates[gi].z)
		rc.speed = 0.0
		var want := gi + 1
		await _until(func() -> bool: return jobs.gate_i >= want or jobs.active == &"", 2.0)
	var won := await _until(func() -> bool: return int(jobs.done[FreedomData.RACE]) == 1, 2.0)
	TestLib.check(won and prog.credits >= credits2 + FreedomData.RACE_BASE and jobs.best_race[0] > 0.0, "all four gates won the race: pay %d and a best time is kept" % (prog.credits - credits2))
	_clear_cars()
	# delivery on foot
	jobs._cool = 0.0
	p.teleport_to(FreedomData.marker_pos(FreedomData.DELIVERY, 0) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	TestLib.check(jobs.start(FreedomData.DELIVERY, 0), "the delivery starts on foot")
	var g := FreedomData.destination(FreedomData.DELIVERY, 0)
	TestLib.check(Vector2(g.x, g.z).length() < Game.HALF and not city.is_inside_building(Vector3(g.x, 1.0, g.z)), "the delivery goes to a street junction inside the map")
	p.teleport_to(Vector3(g.x, 0.1, g.z))
	var dlv := await _until(func() -> bool: return int(jobs.done[FreedomData.DELIVERY]) == 1, 3.0)
	TestLib.check(dlv, "carrying the package to its junction completes the delivery")
	# bounty: one tough operative
	jobs._cool = 0.0
	em.clear()
	p.teleport_to(FreedomData.marker_pos(FreedomData.BOUNTY, 0) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	TestLib.check(jobs.start(FreedomData.BOUNTY, 0) and jobs._target != null, "the bounty spawns its target")
	var tgt := jobs._target
	TestLib.check(tgt != null and tgt.max_hp > 150.0, "the target is tough (%.0f hp)" % (tgt.max_hp if tgt != null else 0.0))
	var credits3 := prog.credits
	if tgt != null:
		tgt.damage(tgt.max_hp * 3.0)
	var bounty := await _until(func() -> bool: return int(jobs.done[FreedomData.BOUNTY]) == 1, 3.0)
	TestLib.check(bounty and prog.credits >= credits3 + FreedomData.BOUNTY_PAY, "killing the target pays the bounty (%d)" % (prog.credits - credits3))
	em.clear()
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	await frames(3)


# --- stunt jumps ----------------------------------------------------------------------------------------------------------------------

func _stunts() -> void:
	var jobs := fr.jobs
	_clear_cars()
	var r := FreedomData.ramp(0)
	var dir: Vector3 = r["dir"]
	var heading := atan2(-dir.x, -dir.z)
	var start := (r["pos"] as Vector3) - dir * 5.0
	var car := vm.spawn_parked(&"sport", start, heading)
	await frames(1)
	vm.enter(car)
	car.speed = 20.0
	car.vel = car.forward() * 20.0
	var credits0 := prog.credits
	Input.action_press(&"move_forward")
	var up := await _until(func() -> bool: return jobs.in_air(), 2.0)
	TestLib.check(up, "a car taken fast up the ramp leaves it (stunt attempts %d)" % jobs.stunt_attempts)
	var lifted := car.visual.model.position.y
	await frames(20)
	TestLib.check(car.visual.model.position.y > 1.0 or lifted > 0.5, "the car flies: its model is lifted off the street (%.1f m)" % car.visual.model.position.y)
	var done := await _until(func() -> bool: return jobs.stunts.has(0), 4.0)
	Input.action_release(&"move_forward")
	TestLib.check(done and prog.credits >= credits0 + FreedomData.STUNT_PAY, "landing in the ring pays the stunt jump (%d, %d of %d found)" % [prog.credits - credits0, jobs.stunts.size(), FreedomData.RAMPS.size()])
	TestLib.check(absf(car.visual.model.position.y) < 0.2, "the car is back on the street after the jump")
	_clear_cars()
	# a slow car only drives over the ramp
	var slow := vm.spawn_parked(&"sedan", start, heading)
	await frames(1)
	vm.enter(slow)
	var attempts := jobs.stunt_attempts
	slow.speed = 6.0
	slow.vel = slow.forward() * 6.0
	Input.action_press(&"move_forward")
	await frames(90)
	Input.action_release(&"move_forward")
	TestLib.check(jobs.stunt_attempts == attempts, "a slow car only drives over the ramp, no jump")
	_clear_cars()
	# the hero on foot: a launch from the ramp end resolves into a landing (ring or miss), never hangs
	p.teleport_to((r["pos"] as Vector3) + dir * (FreedomData.RAMP_LEN - 1.0) + Vector3(0.0, 0.1, 0.0))
	await frames(3)
	jobs._launch_hero(p, 0, dir)
	TestLib.check(p.velocity.y > 5.0 and jobs.in_air(), "the hero is launched off the ramp too")
	var landed := await _until(func() -> bool: return not jobs.in_air(), 6.0)
	TestLib.check(landed, "the hero's stunt jump resolves when he lands")
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	await frames(4)


# --- (4) explosives, cover ---------------------------------------------------------------------------------------------------------------

func _explosives() -> void:
	var ch := fr.charges
	_clear_cars()
	em.clear()
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.1, 0.0))
	p.hp = p.max_hp
	await frames(6)
	# chain reaction: three cars side by side, one blows, the others follow one after the other
	var base := Vector3(60.0, 0.0, -9.0)
	var cars: Array[Vehicle] = []
	for i in 3:
		var c := vm.spawn_parked(&"sedan", base + Vector3(0.0, 0.0, 3.4 * float(i)), -PI * 0.5)
		if c != null:
			cars.append(c)
	await frames(2)
	TestLib.check(cars.size() == 3, "three cars stand in a row")
	if cars.size() == 3:
		cars[0].explode()
		TestLib.check(cars[1].fuse >= 0.0 or cars[1].dead, "the neighbour of a wreck is on fire with a lit fuse")
		var chain := await _until(func() -> bool: return cars[1].dead and cars[2].dead, 5.0)
		TestLib.check(chain, "a blown-up car sets the cars next to it off one after the other")
	_clear_cars()
	# quantum charges: place two, an enemy and a car beside them, DETONATE
	ch.reset()
	var armed_before := ch.armed()
	p.teleport_to(Vector3(20.0, 0.1, -9.0))
	p.camera_rig.yaw = -PI * 0.5
	await frames(8)
	var target := em.spawn(&"operative", Vector3(26.0, 0.1, -9.0), false)
	if target != null:
		target.set_physics_process(false)
		target.max_hp = 400.0
		target.hp = 400.0
	var victim := vm.spawn_parked(&"sedan", Vector3(28.0, 0.0, -13.0), 0.0)
	await frames(3)
	TestLib.check(not armed_before and ch.stock == Charges.MAX_LIVE, "no charge is down at first, three in the bag")
	TestLib.check(ch.place(), "a quantum charge is set where the crosshair points")
	await _until(func() -> bool: return ch.stock < Charges.MAX_LIVE, 1.0)
	var placed_at := ch.positions()[0] if not ch.positions().is_empty() else Vector3.ZERO
	await _until(func() -> bool: return ch._cool <= 0.0, 1.0)
	TestLib.check(ch.place() and ch.live_count() == 2, "a second charge goes down (%d live)" % ch.live_count())
	TestLib.check(ch.armed(), "with a charge down the detonator is armed")
	if tc != null:
		var db := {}
		for b in TouchControls.BUTTONS:
			if b["action"] == &"detonate":
				db = b
		TestLib.check(not db.is_empty() and tc.button_visible(db), "the DETONATE button appears while a charge is down")
	# move the targets onto the charges so the blast surely reaches them
	var cpos := ch.positions()
	if target != null and not cpos.is_empty():
		target.global_position = cpos[0] + Vector3(1.5, 0.0, 0.0)
	if victim != null and not cpos.is_empty():
		victim.global_position = Vector3(cpos[0].x + 2.0, 0.0, cpos[0].z)
	var hp0 := target.hp if target != null else 0.0
	var psf := p.hp
	TestLib.check(ch.detonate() == 2, "DETONATE arms both charges")
	var boom := await _until(func() -> bool: return ch.detonations >= 2, 2.0)
	TestLib.check(boom and ch.live_count() == 0 and not ch.armed(), "both charges go off, a fraction of a second apart")
	if target != null:
		TestLib.check(target.hp < hp0 or target.dead, "the blast hurts the enemy beside the charge (%.0f -> %.0f)" % [hp0, target.hp])
	if victim != null:
		TestLib.check(victim.dead or victim.hp < victim.max_hp * 0.5, "and wrecks the car beside it")
	TestLib.check(placed_at != Vector3.ZERO and p.hp <= psf, "the charge was set at a real place in the street")
	# a blast next to a charge sets it off in a chain
	em.clear()
	_clear_cars()
	p.hp = p.max_hp
	p.teleport_to(Vector3(20.0, 0.1, -9.0))
	await frames(6)
	await _until(func() -> bool: return ch._cool <= 0.0, 1.0)
	ch.reset()
	if ch.place():
		var where := ch.positions()[0]
		var chained0 := ch.chained
		Game.explode(where + Vector3(2.0, 0.5, 0.0), 5.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
		TestLib.check(ch.chained == chained0 + 1, "another explosion beside a charge sets it off")
		var gone := await _until(func() -> bool: return ch.live_count() == 0, 2.0)
		TestLib.check(gone, "the chained charge blows")
	else:
		TestLib.check(false, "a charge can be placed again")
	# mines are in the loadout (FLUX MINE) and the launcher is a real grenade launcher
	TestLib.check(Gear.THROWABLES.has(&"mine") and bool(WeaponDefs.DEFS[&"gravity"].get("impact", false)), "FLUX MINE stays a throwable, the GRAVITY LAUNCHER blows on impact")
	await _launcher()


func _launcher() -> void:
	em.clear()
	_clear_cars()
	WeaponDefs.unlock(&"gravity")
	p.teleport_to(Vector3(20.0, 0.1, -9.0))
	p.camera_rig.yaw = -PI * 0.5
	await frames(8)
	var tgt := em.spawn(&"operative", Vector3(32.0, 0.1, -9.0), false)
	var car := vm.spawn_parked(&"sedan", Vector3(32.0, 0.0, -13.0), 0.0)
	await frames(3)
	if tgt == null or car == null:
		TestLib.check(false, "launcher targets spawn")
		return
	tgt.set_physics_process(false)
	tgt.max_hp = 600.0
	tgt.hp = 600.0
	p.weapon.switch_to(&"gravity", true)
	p.weapon.reset()
	var blasts: Array[Vector3] = []
	var cb := func(pos: Vector3) -> void: blasts.append(pos)
	p.weapon.grenade_collapsed.connect(cb)
	var car_hp := car.hp
	await frames(4)
	p.camera_rig.aim_at(tgt.center())
	await frames(3)
	Input.action_press(&"fire")
	var hit := await _until(func() -> bool: return not blasts.is_empty(), 4.0)
	Input.action_release(&"fire")
	p.weapon.grenade_collapsed.disconnect(cb)
	TestLib.check(hit, "the launcher round blows on impact (no well to wait for)")
	if hit:
		var t_between := p.weapon.grenades_active()
		TestLib.check(t_between == 0, "no gravity well is left behind")
		TestLib.check(tgt.hp < 600.0 or tgt.dead or car.hp < car_hp or car.dead, "the blast hurts what stands at the impact (enemy %.0f, car %.0f)" % [tgt.hp, car.hp])
	p.weapon.switch_to(&"carbine", true)
	em.clear()
	_clear_cars()


# --- cover ----------------------------------------------------------------------------------------------------------------------------

func _cover() -> void:
	var bk := Breakables.current
	TestLib.check(bk != null, "breakables exist")
	if bk == null:
		return
	var idx := -1
	for i in Breakables.COUNT:
		if Breakables.KINDS[bk.kind_of[i]]["name"] == "barrier" and bk.broken[i] == 0:
			idx = i
			break
	TestLib.check(idx >= 0, "concrete barriers (destructible cover) are placed in the streets")
	if idx < 0:
		return
	TestLib.check(int(Breakables.KINDS[bk.kind_of[idx]]["hp"]) >= 10, "a barrier shrugs off a few bullets")
	var pos := bk.positions[idx]
	bk.hit_at(bk.bodies[idx], pos, Vector3.UP, 3)
	TestLib.check(bk.broken[idx] == 0, "three bullets do not bring it down")
	Game.explode(pos + Vector3(2.0, 0.0, 0.0), 6.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(bk.broken[idx] == 1, "a blast takes the cover down at once")
	bk.reset()


# --- touch buttons and prompts -----------------------------------------------------------------------------------------------------------

func _touch_and_prompts() -> void:
	if tc == null:
		return
	var c4 := {}
	var det := {}
	for b in TouchControls.BUTTONS:
		if b["action"] == &"charge_place":
			c4 = b
		elif b["action"] == &"detonate":
			det = b
	TestLib.check(not c4.is_empty() and not det.is_empty(), "the C4 and DETONATE buttons are defined")
	if c4.is_empty() or det.is_empty():
		return
	tc.more_open = false
	TestLib.check(not tc.button_visible(c4), "C4 hides in the default frame (it lives in MORE)")
	tc.more_open = true
	TestLib.check(tc.button_visible(c4), "C4 shows in the MORE cluster")
	tc.more_open = false
	TestLib.check(float(c4["r"]) * 2.0 >= 64.0 and float(det["r"]) * 2.0 >= 64.0, "both buttons are at least 64 px")
	TestLib.check(not tc.button_visible(det), "DETONATE hides without a charge")
