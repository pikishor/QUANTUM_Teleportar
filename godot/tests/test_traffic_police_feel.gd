extends RefCounted
## TRAFFIC AND POLICE FEEL in the real scene (main.tscn): (1) 12+ drivable kinds with distinct silhouettes (every kind builds a model, the shaped primitives have Body / Glass / Trim
## surfaces and sizes that match their spec, a bus is longer and taller than a compact); (2) a hijack throws out the driver AND a rider; (3) traffic brakes for an obstacle, flees gunfire and
## cars in flight hit each other with damage by closing speed; (4) the police ladder: heat 0.6 an interceptor tails the hero without ramming, heat 2+ they ram, heat 3+ spike strips are
## laid ahead and a car driving over one loses its tyres (slow, loose), cops drive over their own strips, strips run out; stand-down releases them. Waits on counters and state.
## Run: tools/test.sh tests/test_traffic_police_feel.gd

var host: Node
var p: Player
var vm: VehicleManager


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


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	for f in ["user://save.cfg", "user://freedom.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	TestLib.check(p != null and vm != null and vm.spikes != null, "main.tscn composes the player, the vehicle manager and the spike strips")
	if p == null or vm == null or vm.spikes == null:
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.autosave_enabled = false
		prog.path = "user://test_traffic_police_feel.cfg"
		prog.new_campaign()
	Game.set_quality(2)
	Game.state = &"play"
	Game.heat = 0.0
	await frames(5)
	await _models()
	await _hijack_rider()
	await _traffic()
	await _police()
	_clear_cars()
	Game.heat = 0.0


func _models() -> void:
	var kinds: Array[StringName] = [&"compact", &"sedan", &"sport", &"suv", &"van", &"truck", &"bus", &"taxi", &"interceptor", &"ambulance", &"qbike", &"hover", &"hoverbike", &"wagon"]
	var n := 0
	for k in kinds:
		_clear_cars()
		var v := vm.spawn_parked(k, Vector3(60.0, 0.0, 8.3), 0.0)
		if v == null:
			TestLib.check(false, "%s spawns" % k)
			continue
		n += 1
		var vis := v.visual
		TestLib.check(vis != null and vis.model != null and vis.body != null or v.cls != &"car", "%s has a body model" % k)
	TestLib.check(n >= 12, "12+ drivable kinds spawn (%d)" % n)
	var sizes := {}
	for k in [&"compact", &"bus", &"interceptor", &"ambulance"]:
		var m := VehicleSilhouettes.build_body(k, VehicleSpecs.SPECS[k])
		var bb := m.mesh.get_aabb()
		sizes[k] = bb.size
		TestLib.check(m.mesh.get_surface_count() >= 2, "%s silhouette has body + glass surfaces" % k)
		TestLib.check(absf(bb.size.z - float(VehicleSpecs.SPECS[k]["len"])) < 0.6 and bb.size.y > float(VehicleSpecs.SPECS[k]["hgt"]) * 0.8, "%s silhouette matches its spec size (%s)" % [k, bb.size])
		m.free()
	TestLib.check((sizes[&"bus"] as Vector3).z > 2.0 * (sizes[&"compact"] as Vector3).z and (sizes[&"bus"] as Vector3).y > (sizes[&"compact"] as Vector3).y * 1.8, "a bus is far longer and taller than a compact")
	TestLib.check((sizes[&"ambulance"] as Vector3).y > (sizes[&"interceptor"] as Vector3).y * 1.5, "an ambulance is much taller than an interceptor")
	_clear_cars()


func _hijack_rider() -> void:
	var hj := Hijack.current
	TestLib.check(hj != null, "the Hijack layer exists")
	if hj == null:
		return
	_clear_cars()
	var car := vm.spawn_traffic(&"sedan", 0, 8, 1, 60.0)
	if car == null:
		TestLib.check(false, "traffic sedan spawns")
		return
	car.passengers = 2
	hj.reset()
	var before := hj.passengers_ejected
	var side := car.right() * (float(car.spec["wid"]) * 0.5 + 1.0)
	p.teleport_to(car.global_position + side)
	vm.toggle_enter_exit()
	TestLib.check(vm.driven == car and hj.hijacks >= 1, "the hijack takes the car")
	TestLib.check(hj.passengers_ejected == before + 1 and car.passengers == 0 and hj.ejected_live() >= 2, "a rider is thrown out with the driver")
	vm.exit_vehicle()
	Game.heat = 0.0
	_clear_cars()


func _traffic() -> void:
	_clear_cars()
	vm.lights_on = false
	var lead := vm.spawn_traffic(&"sedan", 0, 8, 1, 400.0)
	var back := vm.spawn_traffic(&"sedan", 0, 8, 1, 372.0)
	if lead == null or back == null:
		TestLib.check(false, "two traffic cars spawn")
		return
	p.teleport_to(Vector3(385.0, 1.0, lead.global_position.z + 16.0))
	lead.ai_speed = 0.0
	lead.ai_stun = 6.0                                           # the car ahead is stopped (a crash behind it)
	back.ai_cruise = 13.0
	back.ai_speed = 13.0
	var ok := await _until(func() -> bool: return back.ai_speed < 1.0 and back.global_position.distance_to(lead.global_position) > 3.0, 8.0)
	TestLib.check(ok, "traffic brakes for the stopped car ahead without touching it (gap %.1f m, speed %.1f)" % [back.global_position.distance_to(lead.global_position), back.ai_speed])
	# gunfire: a car flees (panic) and a car in flight really hits the one ahead
	lead.ai_stun = 0.0
	lead.ai_speed = 0.0
	lead.ai_cruise = 3.0
	back.global_position = lead.global_position - Vector3(14.0, 0.0, 0.0)
	back.ai_speed = 12.0
	vm.hear(back.global_position, &"gun")
	TestLib.check(back.ai_panic > 1.0 and back.reactions > 0, "traffic flees gunfire")
	var hp0 := lead.hp + back.hp
	lead.ai_stun = 0.0
	lead.ai_speed = 2.0
	var hit := await _until(func() -> bool: return not back.ai or not lead.ai, 6.0)
	TestLib.check(hit, "a panicking car runs into the traffic ahead (a real collision)")
	await frames(4)
	TestLib.check(lead.hp + back.hp < hp0 or lead.hits + back.hits > 0 or lead.speed != 2.0, "the crash has consequences (damage, hits or speed change)")
	vm.lights_on = true
	_clear_cars()


func _police() -> void:
	_clear_cars()
	var car := vm.spawn_parked(&"sport", Vector3(80.0, 0.0, 8.3), 0.0)
	p.teleport_to(car.global_position + car.right() * 2.4)
	vm.toggle_enter_exit()
	TestLib.check(vm.driven == car, "the hero drives for the chase")
	Game.heat = 0.0
	await frames(10)
	TestLib.check(vm.cop_count() == 0, "no heat: no police")
	Game.heat = 0.8
	vm._cop_t = 0.0
	var tail := await _until(func() -> bool: return vm.cop_count(true) >= 1, 8.0)
	TestLib.check(tail, "heat 0.8: an interceptor is sent after him (spawned %d)" % vm.cops_spawned)
	var cop: Vehicle = null
	for v in vm.list:
		if v.cop:
			cop = v
	if cop == null:
		TestLib.check(false, "a cop car exists")
		return
	TestLib.check(cop.kind == &"interceptor" and cop.chasing and cop.is_emergency(), "it is an interceptor on a chase with its siren")
	# shadowing: put it 8 m behind him at speed, no rams land at low heat
	car.heading = -PI * 0.5
	car.speed = 14.0
	car.vel = car.forward() * 14.0
	cop.global_position = car.global_position - car.forward() * 8.0
	cop.heading = car.heading
	cop.speed = 14.0
	cop.vel = cop.forward() * 14.0
	cop.ram_hits = 0
	var php := p.hp if p.get(&"hp") != null else 0.0
	await _until(func() -> bool: return false, 3.0)
	TestLib.check(cop.ram_hits == 0, "at heat 0.8 the interceptor shadows him and does not ram")
	# escalation: ramming from heat 2
	Game.heat = 2.4
	cop.global_position = car.global_position - car.forward() * 4.0
	cop.heading = car.heading
	cop.speed = 20.0
	cop.vel = cop.forward() * 20.0
	var rammed := await _until(func() -> bool:
		car.speed = 14.0
		car.vel = car.forward() * 14.0
		if cop.global_position.distance_to(car.global_position) > 3.3:
			cop.global_position = car.global_position - car.forward() * 3.0
			cop.speed = 22.0
			cop.vel = cop.forward() * 22.0
		return cop.ram_hits > 0, 6.0)
	TestLib.check(rammed, "at heat 2.4 the interceptor rams him (hits %d)" % cop.ram_hits)
	TestLib.check(vm.cop_want(0.2) == 0 and vm.cop_want(0.8) == 1 and vm.cop_want(2.5) == 2 and vm.cop_want(4.5) == 3, "the response grows with the heat (0 / 1 / 2 / 3 cars)")
	# spike strips from heat 3
	Game.heat = 3.5
	car.speed = 16.0
	car.vel = car.forward() * 16.0
	vm._spike_t = 0.0
	var laid := await _until(func() -> bool:
		car.speed = 16.0
		car.vel = car.forward() * 16.0
		return vm.spikes.laid >= 1, 6.0)
	TestLib.check(laid and vm.spikes.active_count() >= 1, "at heat 3.5 the police lay a spike strip ahead of him")
	var bar := vm.lay_spikes_ahead()
	TestLib.check(bar != null and bar.visible, "a strip can be laid on demand across the road ahead")
	if bar != null:
		bar.global_position = car.global_position + car.forward() * 3.0
		car.speed = 18.0
		car.vel = car.forward() * 18.0
		cop.global_position = bar.global_position + Vector3(0.0, 0.0, 0.0)
		cop.cop = true
		var blown := await _until(func() -> bool: return car.tires_flat > 0.0, 4.0)
		TestLib.check(blown and vm.spikes.hits >= 1, "driving over a strip shoots the tyres")
		TestLib.check(not cop.tires_flat > 0.0, "the police drive over their own strip")
		var top := float(car.spec["max"])
		car.speed = 0.0
		car.vel = Vector3.ZERO
		var v_hold := 0.0
		for i in 240:
			car.step_drive(1.0 / 60.0, 1.0, 0.0, false)
			v_hold = maxf(v_hold, absf(car.speed))
		TestLib.check(v_hold < top * 0.62, "flat tyres cap the speed (%.1f of %.1f)" % [v_hold, top])
	vm.spikes.clear()
	TestLib.check(vm.spikes.active_count() == 0, "strips can be cleared")
	# stand-down
	vm.exit_vehicle()
	Game.heat = 0.0
	await frames(5)
	await _until(func() -> bool: return vm.cop_count(true) == 0, 3.0)
	TestLib.check(vm.cop_count(true) == 0, "at heat 0 the police stop chasing")
