extends RefCounted
## Traffic AI and the wave-53 vehicle set on the real city scene (headless): junction lights (red stops, green goes), yielding to a siren car, reactions to a horn, gunfire
## and a crash, crash deformation, the four new kinds (bus, interceptor, ambulance, quantum bike) in the traffic mix and the TEST MENU list, and radio station 4.
## Waits are on state with timeouts, never on frame counts. Run: tools/test.sh tests/test_traffic_ai.gd

const Env := preload("res://tests/player_env.gd")
const K := 4
const ROAD := 4 + CityLayout.CORE0         ## axis-0 road index used (z = 0)
const JCT := 3 + CityLayout.CORE0          ## junction column on it (x = -80)

var e := Env.new()
var p: Player
var mgr: VehicleManager


func run(host: Node) -> void:
	seed(7)
	_pure()
	await e.setup(host)
	p = e.p
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	e.root.add_child(mgr)
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate()
	host.add_child(world)
	await e.frames(10)
	TestLib.check(Game.world != null and Game.vehicles == mgr, "the real city and the vehicle manager are up")
	await e.prep(Vector3(VehicleSpecs.road_center(JCT), 0.0, VehicleSpecs.road_center(ROAD) - 30.0), 0.0)
	await _lights()
	await _yield()
	await _reactions()
	await _kinds(host)
	_radio()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	world.queue_free()
	mgr.queue_free()
	await e.teardown()


# ------------------------------------------------------------------ data
func _pure() -> void:
	var both := 0
	var green := [0, 0]
	for i in 720:
		var t := float(i) * 0.05
		var a := VehicleSpecs.signal_state(0, t)
		var b := VehicleSpecs.signal_state(1, t)
		if a == 0 and b == 0:
			both += 1
		green[0] += 1 if a == 0 else 0
		green[1] += 1 if b == 0 else 0
	TestLib.check(both == 0, "the two axes are never green together")
	TestLib.check(green[0] > 100 and green[1] > 100 and absi(green[0] - green[1]) <= 2, "both axes get the same green share (%s)" % [green])
	for k: StringName in [&"bus", &"interceptor", &"ambulance", &"qbike"]:
		TestLib.check(VehicleSpecs.SPECS.has(k) and k in VehicleSpecs.STREAM_KINDS and k in TestMode.VEHICLES, "%s has a spec, is in the traffic mix and in the TEST MENU list" % k)
	TestLib.check(VehicleSpecs.is_siren(&"interceptor") and VehicleSpecs.is_siren(&"ambulance") and not VehicleSpecs.is_siren(&"bus"), "interceptor and ambulance carry sirens")
	TestLib.check(VehicleSpecs.cls_of(&"qbike") == &"bike" and VehicleSpecs.mass_of(&"bus") > VehicleSpecs.mass_of(&"truck"), "the quantum bike leans like a bike, the bus is the heaviest")
	TestLib.check(VehicleSpecs.STREAM_KINDS.size() == VehicleSpecs.STREAM_WEIGHTS.size(), "one weight per streamed kind")
	var counts := {}
	for i in 6000:
		var k := VehicleSpecs.pick_kind(randf())
		counts[k] = int(counts.get(k, 0)) + 1
	for k: StringName in [&"bus", &"interceptor", &"ambulance", &"qbike"]:
		TestLib.check(int(counts.get(k, 0)) > 40, "traffic picks %s (%d of 6000)" % [k, int(counts.get(k, 0))])


func _radio() -> void:
	TestLib.check(CarRadio.STATIONS.size() == 4 and CarRadio.station_name(3) == "LOFI ORBIT", "the radio has a fourth station")
	var pcm := CarRadio.render(3)
	var loud := 0
	for i in range(0, pcm.size() - 1, 2):
		if absi(pcm.decode_s16(i)) > 800:
			loud += 1
	TestLib.check(pcm.size() > 100000 and loud > 500, "station 4 renders audible audio (%d bytes)" % pcm.size())
	var r := mgr.radio
	if r == null:
		return
	r.turn_off()
	var seq: Array[int] = []
	for i in 4:
		r.cycle()
		seq.append(r.station if r.on else -1)
	TestLib.check(seq == [0, 1, 2, 3], "cycling visits the four stations (%s)" % [seq])
	TestLib.check(not r.cycle() and not r.on, "one more press turns the radio off")


# ------------------------------------------------------------------ helpers
func _clear() -> void:
	for v in mgr.list.duplicate():
		if v != mgr.starter and not v.driver_is_player:
			mgr._release(v)
	mgr.stream_every = 9999.0
	mgr._stream_t = 9999.0


## Wait on a state with a timeout (game seconds at the test's time scale).
func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await e.secs(0.1)
		t += 0.1 * K
	return cond.call()


func _road_car(kind: StringName, along: float, cruise := 12.0) -> Vehicle:
	var v := mgr.spawn_traffic(kind, 0, ROAD, 1, along)
	TestLib.check(v != null, "a %s joins the traffic" % kind)
	if v != null:
		v.ai_cruise = cruise
		v.ai_cool = 1.0e6                      # no turns: the test follows the road
	return v


# ------------------------------------------------------------------ lights
func _lights() -> void:
	_clear()
	var c := VehicleSpecs.road_center(JCT)
	mgr.signal_frozen = true
	mgr.signal_clock = 13.0                       # axis 0 is red
	TestLib.check(VehicleSpecs.signal_state(0, mgr.signal_clock) == 2, "the test clock shows red for the road")
	var v := _road_car(&"sedan", c - 18.0)
	if v == null:
		return
	await _until(func() -> bool: return v.ai_speed < 0.3 and v.at_light, 10.0)
	var d := c - v.global_position.x
	TestLib.check(v.at_light and v.ai_speed < 0.5, "the car stops at a red light (speed %.2f)" % v.ai_speed)
	TestLib.check(d > VehicleSpecs.LIGHT_COMMIT, "it waits before the junction (%.1f m short)" % d)
	await e.secs(1.0)
	TestLib.check(c - v.global_position.x > VehicleSpecs.LIGHT_COMMIT, "it keeps waiting while the light stays red")
	TestLib.check(v.braking, "the brake lights are on")
	mgr.signal_clock = 2.0                         # green
	var went := await _until(func() -> bool: return v.global_position.x > c + 4.0, 12.0)
	TestLib.check(went and not v.at_light, "the car drives through when the light turns green")
	# a siren car does not stop for the light
	_clear()
	mgr.signal_clock = 13.0
	var s := _road_car(&"interceptor", c - 18.0)
	if s != null:
		var passed := await _until(func() -> bool: return s.global_position.x > c + 4.0, 12.0)
		TestLib.check(passed and s.is_emergency(), "an interceptor with its siren on runs the red light")


# ------------------------------------------------------------------ yielding
func _yield() -> void:
	_clear()
	mgr.signal_clock = 2.0                         # green all along (frozen)
	var c := VehicleSpecs.road_center(JCT)
	var a := _road_car(&"sedan", c - 70.0, 10.0)
	var b := _road_car(&"ambulance", c - 92.0, 12.0)
	if a == null or b == null:
		return
	var lane := a.ai_line
	var yielded := await _until(func() -> bool: return a.yielding, 8.0)
	TestLib.check(yielded and b.is_emergency(), "traffic yields to an ambulance behind it")
	var shifted := await _until(func() -> bool: return absf(a.global_position.z - lane) > 1.0 and a.ai_speed < VehicleSpecs.YIELD_SPEED + 1.5, 6.0)
	TestLib.check(shifted, "the yielding car pulls to the kerb (%.2f m) and slows (%.1f m/s)" % [absf(a.global_position.z - lane), a.ai_speed])
	var overtaken := await _until(func() -> bool: return b.global_position.x > a.global_position.x + 8.0, 14.0)
	TestLib.check(overtaken, "the ambulance gets past")
	var back := await _until(func() -> bool: return not a.yielding and absf(a.global_position.z - lane) < 0.5, 10.0)
	TestLib.check(back, "the car returns to its lane afterwards")


# ------------------------------------------------------------------ reactions
func _reactions() -> void:
	_clear()
	mgr.signal_clock = 2.0
	var c := VehicleSpecs.road_center(JCT)
	var v := _road_car(&"sedan", c - 70.0, 10.0)
	if v == null:
		return
	await _until(func() -> bool: return v.ai_speed > 8.0, 8.0)
	var here := v.global_position
	TestLib.check(mgr.hear(here + Vector3(10.0, 0.0, 0.0), &"horn") == 0 and v.ai_panic == 0.0, "a horn ahead of the car does nothing")
	TestLib.check(mgr.hear(here + Vector3(0.0, 0.0, 200.0), &"gun") == 0, "gunfire far away is ignored")
	TestLib.check(mgr.hear(here + Vector3(-8.0, 0.0, 0.0), &"horn") == 1 and v.ai_panic > 0.0, "a horn behind the car makes it hurry on")
	v.ai_panic = 0.0
	TestLib.check(mgr.hear(here + Vector3(5.0, 0.0, 20.0), &"gun") == 1 and v.ai_panic >= VehicleSpecs.PANIC_TIME - 0.01, "gunfire nearby sends the car fleeing")
	var fast := await _until(func() -> bool: return v.ai_speed > v.ai_cruise * 1.15, 6.0)
	TestLib.check(fast, "the fleeing car speeds up (%.1f of cruise %.1f)" % [v.ai_speed, v.ai_cruise])
	v.ai_panic = 0.0
	TestLib.check(mgr.hear(v.global_position + Vector3(0.0, 0.0, 6.0), &"crash") == 1 and v.ai_stun > 0.0, "a crash nearby stuns the car")
	var stopped := await _until(func() -> bool: return v.ai_speed < 1.0, 5.0)
	TestLib.check(stopped, "traffic stops near a crash")
	var resumed := await _until(func() -> bool: return v.ai_stun <= 0.0 and v.ai_speed > 4.0, 10.0)
	TestLib.check(resumed, "and drives on again")
	# the real sources: the player's gun and horn reach the traffic through Stealth.noise and Sfx.horn
	var pp := p.global_position
	v.global_position = Vector3(pp.x + 14.0, 0.0, pp.z)
	v.ai_panic = 0.0
	Stealth.noise([], pp, &"gun")
	TestLib.check(v.ai_panic > 0.0, "a gunshot through Stealth.noise sends traffic fleeing")
	v.ai_panic = 0.0
	Sfx._horn_cd = 0.0
	v.global_position = Vector3(pp.x + 6.0, 0.0, pp.z)
	v.ai_axis = 0
	v.ai_dir = 1
	Sfx.horn()
	TestLib.check(v.ai_panic > 0.0, "the horn (Sfx.horn) makes a car ahead of the player hurry on")
	# crash deformation
	v.ai_panic = 0.0
	var m := v.visual.model
	var base := m.scale
	v.damage(v.max_hp * 0.5)
	TestLib.check(m.scale.y < base.y - 0.02 and m.scale.x > base.x, "damage crumples the body (scale %s)" % m.scale)
	v.activate(v.global_position, 0.0)
	TestLib.check(m.scale.is_equal_approx(base), "a repaired car is whole again")


# ------------------------------------------------------------------ the new kinds
func _kinds(host: Node) -> void:
	_clear()
	for k: StringName in [&"bus", &"interceptor", &"ambulance", &"qbike"]:
		if mgr.list.size() >= mgr.cap():
			mgr._release(mgr.list[mgr.list.size() - 1] if mgr.list[mgr.list.size() - 1] != mgr.starter else mgr.list[0])
		var at := p.global_position + Vector3(0.0, 0.0, 40.0)
		var v := mgr.spawn_parked(k, at, 0.0)
		TestLib.check(v != null and v.kind == k and v.visual != null and v.visual.model != null, "%s spawns and builds" % k)
		if v == null:
			continue
		v.step_drive(0.1, 1.0, 0.0, false)
		for i in 20:
			v.step_drive(0.05, 1.0, 0.3, false)
		TestLib.check(v.speed > 0.5, "%s drives (%.1f m/s)" % [k, v.speed])
		mgr._release(v)
	var traffic := mgr.spawn_traffic(&"interceptor", 0, ROAD, 1, VehicleSpecs.road_center(JCT) - 40.0)
	TestLib.check(traffic != null and traffic.ai and traffic.is_emergency(), "an interceptor in traffic counts as an emergency car")
	var parked := mgr.spawn_parked(&"ambulance", p.global_position + Vector3(20.0, 0.0, 0.0), 0.0)
	TestLib.check(parked != null and not parked.is_emergency(), "a parked ambulance is not")
