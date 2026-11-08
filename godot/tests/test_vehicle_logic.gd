extends RefCounted
## Vehicle logic tests (headless): handling classes driven by spec fields (bike lean and narrow body, hover bob / no wheels / drift), graceful model fallback,
## damage states (smoke below 40 % hp, fire below 15 % that burns the car down, explosion), enter / exit polish, the car radio (3 synthesised stations, key action,
## audible only while driving), the far-traffic kinds by spec name and Vael patrol vehicles that chase from heat 3.
## Runs on the player test environment (floor, a real Player) and then on the real city for the patrol spawn. Run: tools/test.sh tests/test_vehicle_logic.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Traffic := preload("res://scripts/ambient/ambient_traffic.gd")

const K := 4
const DT := 1.0 / 60.0

var e := Env.new()
var p: Player
var mgr: VehicleManager
var root: Node3D
var _state_log: Array[int] = []


func run(host: Node) -> void:
	seed(11)
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 400.0)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	root.add_child(mgr)
	await e.frames(3)
	_specs_and_fallback()
	_handling_bike()
	_handling_hover()
	_damage_states()
	await _burn_down()
	await _enter_exit_polish()
	await _radio()
	_far_traffic()
	await _patrol_chase()
	await _patrol_on_city(host)
	Game.heat = 0.0
	mgr.queue_free()
	await e.frames(3)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	await e.teardown()


func _extras() -> void:
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)


## step_drive plus the visual sync, the way the manager's sim() does it.
func _drive(car: Vehicle, secs: float, thr: float, steer: float, hb := false) -> void:
	for i in int(ceil(secs * 60.0)):
		car.step_drive(DT, thr, steer, hb)
		car._sync(DT)


func _specs_and_fallback() -> void:
	for k: StringName in [&"bike", &"hover", &"vael_patrol"]:
		TestLib.check(VehicleSpecs.SPECS.has(k) and VehicleSpecs.model_names(k).size() >= 2, "spec %s exists with fallback model names" % k)
	TestLib.check(VehicleSpecs.cls_of(&"bike") == &"bike" and VehicleSpecs.cls_of(&"hover") == &"hover" and VehicleSpecs.cls_of(&"vael_patrol") == &"hover" and VehicleSpecs.cls_of(&"sedan") == &"car", "handling classes come from the spec")
	TestLib.check(bool(VehicleSpecs.SPECS[&"vael_patrol"]["patrol"]) and float(VehicleSpecs.SPECS[&"vael_patrol"]["hp"]) > 150.0, "the Vael patrol vehicle is a tough patrol spec")
	var counts := {}
	for i in 4000:
		var k := VehicleSpecs.pick_kind(randf())
		counts[k] = int(counts.get(k, 0)) + 1
	TestLib.check(int(counts.get(&"bike", 0)) > 200 and int(counts.get(&"hover", 0)) > 200 and not counts.has(&"vael_patrol"), "streaming picks bikes and hovers, never patrols (%s)" % str(counts))
	# a missing model never fails: the primitive fallback has the node names the visual needs
	for k: StringName in [&"bike", &"hover", &"vael_patrol", &"sedan"]:
		var c := mgr.spawn_parked(k, Vector3(60.0 + float(k.length()) * 7.0, 0.0, -60.0), 0.0)
		var v := c.visual
		TestLib.check(c != null and v.body != null and v.model != null and (v.uses_model == (VehicleSpecs.available_model(k) != "")), "%s builds (%s)" % [k, v.model_name if v.uses_model else "primitive fallback"])
		match VehicleSpecs.cls_of(k):
			&"bike":
				TestLib.check(v.wheels.size() == 2 or v.uses_model, "bike fallback has two wheels (%d)" % v.wheels.size())
			&"hover":
				TestLib.check(v.wheels.is_empty() or v.uses_model, "hover fallback has no wheels")
		if v.uses_model:
			TestLib.check(v.model.scale == Vector3.ONE, "%s model is never scaled" % k)
		mgr._release(c)
	var bike := mgr.spawn_parked(&"bike", Vector3(80.0, 0.0, -60.0), 0.0)
	var car := mgr.spawn_parked(&"sedan", Vector3(90.0, 0.0, -60.0), 0.0)
	var bw := _box_of(bike)
	var cw := _box_of(car)
	TestLib.check(bw.x < 1.0 and bw.x < cw.x * 0.5 and bw.z < cw.z, "the bike is narrow (%.2f m vs %.2f m)" % [bw.x, cw.x])
	var hov := mgr.spawn_parked(&"hover", Vector3(100.0, 0.0, -60.0), 0.0)
	TestLib.check(absf(hov.visual.model.position.y) < 0.01, "a hover craft's model is not lifted twice (the hover_h is baked into the glb)")
	_extras()


func _box_of(c: Vehicle) -> Vector3:
	for ch in c.get_children():
		if ch is CollisionShape3D:
			return ((ch as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO


func _handling_bike() -> void:
	_extras()
	var bike := mgr.spawn_parked(&"bike", Vector3(100.0, 0.0, -100.0), -PI * 0.5)
	_drive(bike, 3.0, 1.0, 0.0)
	var bike_max: float = VehicleSpecs.SPECS[&"bike"]["max"]
	TestLib.check(bike.speed > bike_max * 0.7 and bike.speed <= bike_max + 0.01, "the bike is fast (%.1f m/s, max %.0f)" % [bike.speed, bike_max])
	TestLib.check(absf(bike.lean) < 0.05 and absf(bike.visual.model.rotation.z) < 0.05, "no lean on a straight line")
	var h0 := bike.heading
	_drive(bike, 1.0, 1.0, 1.0)
	TestLib.check(bike.heading < h0 - 0.3, "steering right turns right (%.2f -> %.2f)" % [h0, bike.heading])
	var lmax := float(VehicleSpecs.SPECS[&"bike"]["lean_max"])
	TestLib.check(bike.lean > 0.15 and bike.lean <= lmax + 0.001, "the bike leans right into a right turn (%.2f rad, max %.2f)" % [bike.lean, lmax])
	TestLib.check(bike.visual.model.rotation.z < -0.1, "and the body rolls with it (z %.2f)" % bike.visual.model.rotation.z)
	_drive(bike, 1.0, 1.0, -1.0)
	TestLib.check(bike.lean < -0.15, "leaning left in a left turn (%.2f)" % bike.lean)
	# a bike turns tighter than a sedan at the same speed
	var sedan := mgr.spawn_parked(&"sedan", Vector3(100.0, 0.0, -140.0), -PI * 0.5)
	var b2 := mgr.spawn_parked(&"bike", Vector3(100.0, 0.0, -180.0), -PI * 0.5)
	for c in [sedan, b2]:
		(c as Vehicle).vel = (c as Vehicle).forward() * 30.0
		(c as Vehicle).speed = 30.0
	var hs := sedan.heading
	var hb := b2.heading
	_drive(sedan, 0.5, 0.0, 1.0)
	_drive(b2, 0.5, 0.0, 1.0)
	TestLib.check(absf(b2.heading - hb) > absf(sedan.heading - hs), "a leaning bike turns in tighter than a sedan (%.2f vs %.2f rad)" % [absf(b2.heading - hb), absf(sedan.heading - hs)])
	_extras()


func _handling_hover() -> void:
	_extras()
	var hv := mgr.spawn_parked(&"hover", Vector3(100.0, 0.0, -100.0), -PI * 0.5)
	var sd := mgr.spawn_parked(&"sedan", Vector3(100.0, 0.0, -140.0), -PI * 0.5)
	var ys: Array[float] = []
	for i in 240:
		hv.step_drive(DT, 1.0, 0.0, false)
		hv._sync(DT)
		ys.append(hv.visual.model.position.y)
	var lo := 99.0
	var hi := -99.0
	for y in ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
	TestLib.check(hi - lo > 0.04 and hi - lo < 0.3, "a hover craft bobs (%.3f m span)" % (hi - lo))
	TestLib.check(lo > -0.15 and hi < 0.15, "and only bobs around its baked ride height (min %.2f)" % lo)
	var hv_max: float = VehicleSpecs.SPECS[&"hover"]["max"]
	TestLib.check(hv.speed > hv_max * 0.7 and hv.speed <= hv_max + 0.01, "hover top speed (%.1f of %.0f)" % [hv.speed, hv_max])
	for c in [hv, sd]:
		(c as Vehicle).vel = (c as Vehicle).forward() * 22.0
		(c as Vehicle).speed = 22.0
	var worst_h := 0.0
	var worst_s := 0.0
	for i in 40:
		hv.step_drive(DT, 0.6, 1.0, false)
		hv._sync(DT)
		sd.step_drive(DT, 0.6, 1.0, false)
		sd._sync(DT)
		worst_h = maxf(worst_h, absf(hv.slip))
		worst_s = maxf(worst_s, absf(sd.slip))
	TestLib.check(worst_h > 3.0 and worst_h > worst_s * 1.4 + 0.5, "the hover craft drifts in a turn (slide %.1f m/s vs %.1f for the sedan)" % [worst_h, worst_s])
	var coast0 := hv.speed
	_drive(hv, 1.0, 0.0, 0.0)
	var hv_keep := hv.speed / coast0
	var sd2 := mgr.spawn_parked(&"sedan", Vector3(100.0, 0.0, -200.0), -PI * 0.5)
	sd2.vel = sd2.forward() * coast0
	sd2.speed = coast0
	_drive(sd2, 1.0, 0.0, 0.0)
	TestLib.check(hv_keep > sd2.speed / coast0, "a hover craft coasts further than a wheeled car (%.2f vs %.2f of its speed)" % [hv_keep, sd2.speed / coast0])
	_extras()


func _on_state(_v: Vehicle, s: int) -> void:
	_state_log.append(s)


func _damage_states() -> void:
	_extras()
	TestLib.check(Vehicle.state_for(100.0, 100.0) == 0 and Vehicle.state_for(41.0, 100.0) == 0 and Vehicle.state_for(39.0, 100.0) == 1 and Vehicle.state_for(16.0, 100.0) == 1 and Vehicle.state_for(14.0, 100.0) == 2, "damage state thresholds: smoke < 40 %, fire < 15 %")
	var car := mgr.spawn_parked(&"sedan", Vector3(120.0, 0.0, 100.0), 0.0)
	_state_log.clear()
	car.damage_state_changed.connect(_on_state)
	TestLib.check(car.damage_state() == 0, "a new car is sound")
	car.damage(car.max_hp * 0.42)                          # 58 %
	TestLib.check(car.damage_state() == 0 and _state_log.is_empty(), "58 % hp: no smoke yet")
	car.damage(car.max_hp * 0.25)                          # 33 %
	TestLib.check(car.damage_state() == 1 and _state_log == [1], "33 % hp: smoking, signal emitted once")
	var pi0 := FX._pi
	car._dist = 10.0
	car._fx_t = 0.0
	car._damage_fx(DT)
	TestLib.check(FX._pi != pi0, "smoke is spawned from the pooled FX bursts")
	car.damage(car.max_hp * 0.205)                         # 12.5 %
	TestLib.check(car.damage_state() == 2 and _state_log == [1, 2], "12 % hp: on fire")
	var pi1 := FX._pi
	car._fx_t = 0.0
	car._damage_fx(DT)
	TestLib.check(FX._pi != pi1, "fire is spawned too")
	car._dist = 500.0
	var pi2 := FX._pi
	car._fx_t = 0.0
	car._damage_fx(DT)
	TestLib.check(FX._pi == pi2, "no FX far from the player")
	# a fresh activation clears the state
	mgr._release(car)
	var again := mgr.spawn_parked(&"sedan", Vector3(120.0, 0.0, 100.0), 0.0)
	TestLib.check(again.damage_state() == 0 and again.hp == again.max_hp, "a pooled car comes back repaired and sound")
	_extras()


func _burn_down() -> void:
	_extras()
	await e.prep(Vector3(60.0, 0.0, 90.0), 0.0)
	mgr.respawn_time = 1.0
	var car := mgr.spawn_parked(&"sedan", Vector3(60.0, 0.0, 40.0), 0.0)
	car.hp = car.max_hp * 0.14
	car._update_damage_state()
	var hp0 := car.hp
	await e.secs(1.0)
	TestLib.check(not car.dead and car.hp < hp0 - 1.0, "a burning car loses hp (%.1f -> %.1f)" % [hp0, car.hp])
	Game.heat = 0.0
	car.hp = 1.0
	await e.secs(0.8)
	TestLib.check(car.dead and not mgr.list.has(car) and Game.heat >= 0.19, "a burning car finally explodes (heat %.2f)" % Game.heat)
	mgr.respawn_time = VehicleSpecs.RESPAWN_TIME
	_extras()


func _enter_exit_polish() -> void:
	_extras()
	for k: StringName in [&"bike", &"hover"]:
		var car := mgr.spawn_parked(k, Vector3(100.0, 0.0, 100.0), -PI * 0.5)
		await e.prep(car.global_position + Vector3(0.0, 0.0, -2.0), 0.0)
		TestLib.check(mgr.toggle_enter_exit() and p.vehicle == car and car.driver_is_player and mgr.driven == car, "%s can be entered" % k)
		car.vel = car.forward() * 8.0
		car.speed = 8.0
		mgr.toggle_enter_exit()
		await e.frames(2)
		var gap := p.global_position.distance_to(car.global_position)
		TestLib.check(p.vehicle == null and gap < 3.3 and gap > 1.0, "%s: exit puts the player beside it (%.1f m)" % [k, gap])
		TestLib.check(p.hp == p.max_hp, "a slow exit does not hurt")
		TestLib.check(car.speed < 8.0 * VehicleSpecs.EXIT_BRAKE + 0.5, "the vehicle sheds speed after the exit (%.1f)" % car.speed)
		mgr._release(car)
	# bailing out of a fast car hurts
	var fast := mgr.spawn_parked(&"sport", Vector3(100.0, 0.0, 130.0), -PI * 0.5)
	await e.prep(fast.global_position + Vector3(0.0, 0.0, -2.0), 0.0)
	mgr.enter(fast)
	fast.vel = fast.forward() * 30.0
	fast.speed = 30.0
	mgr.exit_vehicle()
	await e.frames(2)
	TestLib.check(p.hp < p.max_hp - 20.0 and p.hp > 0.0, "jumping out at 30 m/s hurts (hp %.0f / %.0f)" % [p.hp, p.max_hp])
	# a patrol vehicle that the player takes is an ordinary car afterwards
	var pat := mgr.spawn_parked(&"vael_patrol", Vector3(100.0, 0.0, 160.0), 0.0)
	pat.chasing = true
	await e.prep(pat.global_position + Vector3(0.0, 0.0, -2.0), 0.0)
	Game.heat = 0.0
	pat.chasing = true
	mgr.enter(pat)
	TestLib.check(not pat.chasing and not pat.patrol and pat.driver_is_player, "a commandeered patrol vehicle stops chasing")
	TestLib.check(Game.heat >= VehicleSpecs.CARJACK_HEAT - 0.001, "and taking it is a crime")
	mgr.exit_vehicle()
	Game.heat = 0.0
	_extras()


func _process_frames(n: int) -> void:
	for i in n:
		await mgr.get_tree().process_frame


func _radio() -> void:
	_extras()
	var r := mgr.radio
	TestLib.check(r != null and r.get_parent() == mgr and InputMap.has_action(CarRadio.ACTION), "the manager owns a radio and the radio_next action exists")
	TestLib.check(CarRadio.STATIONS.size() == 4 and CarRadio.station_name(0) != CarRadio.station_name(1) and CarRadio.station_name(1) != CarRadio.station_name(2), "four named stations")
	var t0 := Time.get_ticks_msec()
	r.render_all_now()
	print("radio render: %d ms for 4 stations" % (Time.get_ticks_msec() - t0))
	var sums: Array[int] = []
	for i in 4:
		var s := r._streams[i] as AudioStreamWAV
		TestLib.check(s != null and s.loop_mode == AudioStreamWAV.LOOP_FORWARD and s.mix_rate == CarRadio.RATE and s.data.size() > CarRadio.RATE * 2 * 2, "station %d is a looped stream of %.1f s" % [i, float(s.data.size()) / 2.0 / CarRadio.RATE])
		var peak := 0
		var energy := 0.0
		for k in range(0, s.data.size(), 2):
			var v := absi(s.data.decode_s16(k))
			peak = maxi(peak, v)
			energy += float(v) * float(v)
		TestLib.check(peak > 8000 and peak <= 32767, "station %d is audible and not clipped hard (peak %d)" % [i, peak])
		TestLib.check(sqrt(energy / (float(s.data.size()) * 0.5)) > 1500.0, "station %d has body (rms %.0f)" % [i, sqrt(energy / (float(s.data.size()) * 0.5))])
		sums.append(hash(s.data))
	TestLib.check(sums[0] != sums[1] and sums[1] != sums[2] and sums[0] != sums[2], "the stations are different")
	# seamless loop: the end of a station flows into its start (no jump much larger than the typical step)
	for i in 3:
		var d := (r._streams[i] as AudioStreamWAV).data
		var n := d.size() / 2
		var jump := absi(d.decode_s16(0) - d.decode_s16((n - 1) * 2))
		var step := 0
		for k in range(1, 2000):
			step = maxi(step, absi(d.decode_s16(k * 2) - d.decode_s16((k - 1) * 2)))
		TestLib.check(jump <= step * 2 + 2000, "station %d loops without a click (jump %d, typical max step %d)" % [i, jump, step])
	# switching: off -> 0 -> 1 -> 2 -> off; only audible while driving
	Sfx.muted = false
	var car := mgr.spawn_parked(&"sedan", Vector3(100.0, 0.0, 100.0), 0.0)
	await e.prep(car.global_position + Vector3(2.0, 0.0, 0.0), 0.0)
	TestLib.check(not r.on and not r.is_audible(), "the radio starts off")
	r.cycle()
	await e.frames(3)
	TestLib.check(r.on and r.station == 0 and not r.is_audible(), "on foot the radio is on but silent")
	mgr.enter(car)
	await e.frames(3)
	TestLib.check(r.is_audible() and r._player.playing, "driving: station 0 plays")
	Input.action_press(CarRadio.ACTION)
	await e.frames(2)
	Input.action_release(CarRadio.ACTION)
	await e.frames(2)
	TestLib.check(r.on and r.station == 1 and r._player.stream == r._streams[1], "the key switches to station 1")
	r.cycle()
	TestLib.check(r.station == 2 and r._player.stream == r._streams[2], "then station 2")
	Game.state = &"paused"
	await e.frames(3)
	await _process_frames(3)                   # the radio reacts in _process; physics frames can run several per rendered frame
	TestLib.check(not r.is_audible() and r._player.stream_paused, "pausing the game pauses the radio")
	Game.state = &"play"
	await e.frames(3)
	await _process_frames(3)
	TestLib.check(r.is_audible(), "resuming brings it back")
	r.cycle()
	TestLib.check(r.station == 3 and r._player.stream == r._streams[3], "then station 4")
	r.cycle()
	TestLib.check(not r.on and not r._player.playing, "the next press turns it off")
	r.set_station(1)
	await e.frames(2)
	mgr.exit_vehicle()
	await e.frames(3)
	TestLib.check(r.on and not r.is_audible() and not r._player.playing, "leaving the car silences the radio (it stays tuned)")
	r.turn_off()
	Sfx.muted = true
	Fixture.release_inputs()
	_extras()


func _far_traffic() -> void:
	var t: RefCounted = Traffic.new()
	t.build()
	t.set_count(Traffic.COUNTS[2])
	TestLib.check(Traffic.COUNTS[0] >= 110 and Traffic.COUNTS[1] >= 220 and Traffic.COUNTS[2] >= 380 and Traffic.BUILT <= Traffic.CAP and Traffic.CAP <= 760, "far traffic is denser per tier (%s) and capped (%d)" % [str(Traffic.COUNTS), Traffic.CAP])
	var seen := {}
	var speed_sum := {}
	for i in Traffic.BUILT:
		var k: StringName = t.kind_of(i)
		seen[k] = int(seen.get(k, 0)) + 1
		speed_sum[k] = float(speed_sum.get(k, 0.0)) + absf(t.speed[i])
	var all_known := true
	for k: StringName in seen:
		all_known = all_known and VehicleSpecs.SPECS.has(k)
	TestLib.check(all_known and seen.has(&"bike") and seen.has(&"hover") and seen.has(&"sedan") and seen.has(&"vael_patrol"), "far cars are named after specs (%s)" % str(seen))
	var emergency_ok := true
	for i in Traffic.BUILT:
		emergency_ok = emergency_ok and ((t.kind_of(i) == &"vael_patrol") == t.is_emergency(i))
	TestLib.check(emergency_ok, "the emergency lights belong to the Vael patrol kind")
	if VehicleSpecs.available_model(&"bike") != "":
		TestLib.check(float(speed_sum[&"bike"]) / float(seen[&"bike"]) > float(speed_sum[&"sedan"]) / float(seen[&"sedan"]), "bikes drive faster than sedans in the far traffic")
	else:
		var fb := VehicleSpecs.far_look(&"bike")
		TestLib.check(is_equal_approx(float(fb["speed"]), 1.0), "bike model missing: the far bike falls back to the car look")
	TestLib.check(is_equal_approx(float(VehicleSpecs.far_look(&"nonsense")["speed"]), 1.0), "an unknown kind falls back to the car look")
	TestLib.check(t.mm.instance_count == Traffic.BUILT and t.mm.visible_instance_count == Traffic.COUNTS[2], "one MultiMesh, tiered count")


func _patrol_chase() -> void:
	_extras()
	Game.heat = 0.0
	await e.prep(Vector3(100.0, 0.0, 100.0), 0.0)
	Game.heat = 3.0
	var pat := mgr.spawn_parked(&"vael_patrol", Vector3(100.0, 0.0, 150.0), 0.0)
	pat.chasing = true
	var d0 := pat.global_position.distance_to(p.global_position)
	await e.secs(2.0)
	var d1 := pat.global_position.distance_to(p.global_position)
	TestLib.check(d1 < d0 - 15.0 or pat.ram_hits > 0, "a chasing patrol closes in on the player (%.0f m -> %.0f m)" % [d0, d1])
	await e.secs(3.0)
	TestLib.check(pat.ram_hits >= 1 and p.hp < p.max_hp, "and rams him (%d rams, hp %.0f / %.0f)" % [pat.ram_hits, p.hp, p.max_hp])
	TestLib.check(pat.global_position.is_finite() and absf(pat.global_position.y) < 0.01, "the patrol stays on the ground")
	# chase from heat 3 (existing patrols), stand down below heat 2
	pat.chasing = false
	pat.global_position = p.global_position + Vector3(20.0, 0.0, 0.0)
	Game.heat = 3.5
	mgr._tick_patrols(0.1)
	TestLib.check(pat.chasing, "heat 3.5: a standing patrol vehicle takes up the chase")
	Game.heat = 1.0
	mgr._tick_patrols(0.1)
	TestLib.check(not pat.chasing, "heat 1: it stands down")
	Game.heat = 2.5
	mgr._tick_patrols(0.1)
	TestLib.check(not pat.chasing, "heat 2.5 (between 2 and 3): hysteresis, no new chase")
	# driven car as the target: the patrol hurts the car (Player.damage routes to it at 60 %)
	Game.heat = 3.0
	_extras()
	var car := mgr.spawn_parked(&"sedan", Vector3(100.0, 0.0, 100.0), 0.0)
	await e.prep(car.global_position + Vector3(2.0, 0.0, 0.0), 0.0)
	mgr.enter(car)
	var hp0 := car.hp
	var pat2 := mgr.spawn_parked(&"vael_patrol", Vector3(100.0, 0.0, 160.0), 0.0)
	pat2.chasing = true
	await e.secs(5.0)
	TestLib.check(car.hp < hp0, "a patrol ramming the car the player drives damages the car (%.0f -> %.0f)" % [hp0, car.hp])
	mgr.exit_vehicle()
	Game.heat = 0.0
	_extras()


func _patrol_on_city(host: Node) -> void:
	_extras()
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate()
	host.add_child(world)
	await e.frames(10)
	TestLib.check(Game.world != null and Game.world.has_method(&"road_point_near"), "the real city is up")
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	Game.heat = 0.0
	await e.secs(2.0)
	TestLib.check(mgr.patrol_count() == 0, "no patrol vehicles at heat 0")
	Game.set_quality(1)
	TestLib.check(mgr.patrol_cap() == 1, "MED sends one patrol vehicle at a time")
	Game.heat = 4.0
	Game.quiet = 0.0
	await e.secs(8.0)
	Game.heat = 4.0
	TestLib.check(mgr.patrol_count(true) >= 1 and mgr.patrol_count(true) <= mgr.patrol_cap(), "heat 4: a Vael patrol vehicle is sent (%d chasing, cap %d)" % [mgr.patrol_count(true), mgr.patrol_cap()])
	TestLib.check(mgr.list.size() <= mgr.cap(), "the patrol uses the car cap (%d / %d)" % [mgr.list.size(), mgr.cap()])
	TestLib.check(mgr.starter != null, "the starter car keeps its slot")
	Game.set_quality(2)
	await e.secs(14.0)
	Game.heat = 4.0
	TestLib.check(mgr.patrol_count(true) <= 2, "HIGH: at most two (%d)" % mgr.patrol_count(true))
	var before := mgr.total_nodes()
	await e.secs(10.0)
	TestLib.check(mgr.total_nodes() <= before + 3 and mgr.total_nodes() <= VehicleSpecs.CAPS[2] + VehicleSpecs.MAX_WRECKS + 1, "vehicle nodes stay bounded (%d)" % mgr.total_nodes())
	Game.heat = 0.0
	if Game.state == &"dead":                  # a chasing patrol can kill the idle player during the long waits; the manager only ticks while playing
		Game.state = &"play"
	await e.secs(1.0)
	TestLib.check(mgr.patrol_count(true) == 0, "heat 0: every patrol vehicle stands down")
	Game.set_quality(1)
	world.queue_free()
	await e.frames(3)
