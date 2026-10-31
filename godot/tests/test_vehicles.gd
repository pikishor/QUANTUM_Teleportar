extends RefCounted
## Vehicles module tests (headless): visuals (model, per-instance paint, emissive lights, primitive fallback), arcade physics numbers, enter / exit through the
## `interact` poll and the player.vehicle contract, wall collisions, damage / explosion / respawn, ramming, right-hand lanes, junction turns, stopping for the
## player, caps per tier and the lifecycle resets.
## Runs against the player test environment (floor, wall at x = -10, a real Player) with a 800 m floor added; streaming on the real city is tests/test_vehicles_city.gd.
## Time runs 4x (see ARCHITECTURE.md); the whole run must fit the 60 s (game time) watchdog.
## Run: tools/test.sh tests/test_vehicles.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const K := 4
const DT := 1.0 / 60.0

var e := Env.new()
var p: Player
var mgr: VehicleManager
var root: Node3D


func run(host: Node) -> void:
	seed(7)
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 400.0)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	root.add_child(mgr)
	await e.frames(3)
	await _starter_and_visuals()
	await _physics_numbers()
	await _enter_wall_exit()
	await _drive_in_the_open()
	await _lanes_and_turns()
	await _damage_and_respawn()
	await _ramming()
	await _caps_and_trim()
	await _lifecycle()
	mgr.queue_free()
	await e.frames(3)
	TestLib.check(Game.vehicles == null, "freeing the manager clears Game.vehicles")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	await e.teardown()


func _extras() -> void:
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)


func _run_drive(car: Vehicle, secs: float, thr: float, steer: float, hb := false) -> void:
	for i in int(ceil(secs * 60.0)):
		car.step_drive(DT, thr, steer, hb)


func _starter_and_visuals() -> void:
	TestLib.check(Game.vehicles == mgr, "the manager registers itself as Game.vehicles")
	var s := mgr.starter
	TestLib.check(s != null and s.kind == &"sport" and mgr.list.size() == 1, "the starter sport car exists")
	if s == null:
		return
	TestLib.check(s.hp == 100.0 and s.max_hp == 100.0 and s.is_in_group(&"vehicle") and s.collision_layer == Game.L_VEHICLE, "sport hp 100, group vehicle, collider on layer 8")
	TestLib.check(s.global_position.distance_to(VehicleSpecs.starter_pos()) < 0.1 and s.global_position.distance_to(Game.SPAWN) < 14.0, "the starter car stands near the spawn")
	TestLib.check(mgr.nearest(s.global_position + Vector3(2.0, 0.0, 1.0)) == s and mgr.nearest(Vector3(500.0, 0.0, 500.0)) == null, "nearest() finds it within reach and nothing far away")
	TestLib.check(s.visual.model.scale == Vector3.ONE and s.visual.uses_model, "the real model is used and never scaled")
	TestLib.check(s.visual.wheels.size() == 4 and s.visual.body != null, "Body and four wheels found")
	TestLib.check(mgr.cap() == 5, "the default tier is MED: cap 5")
	# paint is per instance; the imported material is untouched
	var src := s.visual.body.mesh.surface_get_material(0) as BaseMaterial3D
	var before := src.albedo_color
	var c2 := mgr.spawn_parked(&"sport", Vector3(60.0, 0.0, -30.0), 0.0)
	c2.visual.set_paint(Color(0.1, 0.9, 0.2))
	TestLib.check(src.albedo_color == before and c2.visual.get_paint() != s.visual.get_paint(), "recolouring touches only the instance's own Body material")
	TestLib.check(s.visual.light_factor(0) < 0.2 and s.visual.light_factor(1) < 0.5, "a parked car's lights are dim")
	# primitive fallback: same names
	var fv := VehicleVisual.new()
	var fm := fv._fallback(VehicleSpecs.SPECS[&"sedan"])
	TestLib.check(fm.get_node_or_null("Body") != null and fm.get_node_or_null("WheelFL") != null and fm.get_node_or_null("WheelRR") != null \
			and fm.get_node_or_null("Body/Headlights") != null and fm.get_node_or_null("Body/Taillights") != null, "the primitive fallback has Body, four wheels and light strips")
	fm.free()
	mgr._release(c2)


func _physics_numbers() -> void:
	_extras()
	var car := mgr.spawn_parked(&"sport", Vector3(40.0, 0.0, -40.0), -PI * 0.5)       # facing +X
	car.global_position = Vector3(40.0, 0.0, -40.0)
	_run_drive(car, 1.0, 1.0, 0.0)
	TestLib.check(car.speed > 15.0 and car.speed < 28.0, "sport from rest: %.1f m/s after 1 s of throttle (about 21)" % car.speed)
	_run_drive(car, 9.0, 1.0, 0.0)
	TestLib.check(car.speed > 45.0 and car.speed <= 50.01, "sport top speed approaches 50 m/s (%.1f)" % car.speed)
	var sp := car.speed
	_run_drive(car, 0.5, -1.0, 0.0)
	TestLib.check(car.speed < sp - 20.0, "braking takes 48 m/s2 (%.1f -> %.1f in 0.5 s)" % [sp, car.speed])
	_run_drive(car, 3.0, -1.0, 0.0)
	TestLib.check(car.speed < 0.0 and car.speed >= -50.0 * VehicleSpecs.REVERSE_FRACTION - 0.01, "reverse is capped at 35 %% of max (%.1f)" % car.speed)
	car.vel = Vector3.ZERO
	car.speed = 0.0
	var h0 := car.heading
	_run_drive(car, 0.5, 0.0, 1.0)
	TestLib.check(absf(car.heading - h0) < 1e-4, "no steering at standstill")
	_run_drive(car, 1.5, 1.0, 0.0)
	var h1 := car.heading
	_run_drive(car, 0.5, 1.0, 1.0)
	TestLib.check(car.heading < h1 - 0.1, "steering right turns the heading clockwise (%.2f -> %.2f)" % [h1, car.heading])
	var coast := car.speed
	_run_drive(car, 1.0, 0.0, 0.0)
	var coast_end := car.speed
	car.vel = car.forward() * coast
	car.speed = coast
	_run_drive(car, 1.0, 0.0, 0.0, true)
	TestLib.check(car.speed < coast_end - 1.0, "the handbrake slows faster than coasting (%.1f vs %.1f)" % [car.speed, coast_end])
	var sedan := mgr.spawn_parked(&"sedan", Vector3(40.0, 0.0, 30.0), -PI * 0.5)
	_run_drive(sedan, 12.0, 1.0, 0.0)
	TestLib.check(sedan.speed > 30.0 and sedan.speed <= 34.01 and sedan.max_hp == 120.0, "sedan top speed 34 m/s, hp 120 (%.1f)" % sedan.speed)
	var suv := mgr.spawn_parked(&"suv", Vector3(40.0, 0.0, 60.0), -PI * 0.5)
	TestLib.check(suv != null and suv.max_hp == 150.0 and suv.visual.uses_model, "the SUV spawns with its own model and hp")
	_extras()


func _enter_wall_exit() -> void:
	_extras()
	var s := mgr.starter
	s.global_position = VehicleSpecs.starter_pos()
	s.heading = VehicleSpecs.STARTER_HEADING
	s.vel = Vector3.ZERO
	s.speed = 0.0
	await e.prep(s.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
	Game.heat = 0.0
	Input.action_press(&"interact")
	await e.frames(3)
	Input.action_release(&"interact")
	await e.frames(3)
	TestLib.check(p.vehicle == s and mgr.driven == s and s.driver_is_player, "pressing interact near the car enters it (polled by the manager)")
	TestLib.check(not p.body.visible and p.camera_rig.mode == &"vehicle" and p.camera_rig.follow_target == s, "the player hides and the camera follows the car")
	TestLib.check(Game.heat == 0.0, "entering a parked car is no crime")
	TestLib.check(s.visual.light_factor(0) > 0.5, "driving switches the headlights on")
	# drive into the wall at x = -10.5 (10 m ahead): bounce, damage, shake
	Input.action_press(&"move_forward")
	var min_speed := 0.0
	var max_shake := 0.0
	for i in 130:
		await e.frames(1)
		min_speed = minf(min_speed, s.speed)
		max_shake = maxf(max_shake, FX.shake_amount)
	Input.action_release(&"move_forward")
	TestLib.check(s.hp < 90.0 and s.hp > 0.0 and s.hits >= 1, "hitting the wall hurts the car (hp %.0f)" % s.hp)
	TestLib.check(min_speed < -1.0, "the wall bounces the car back (min speed %.1f)" % min_speed)
	TestLib.check(max_shake > 0.3, "a hard hit shakes the camera (%.2f)" % max_shake)
	TestLib.check(s.global_position.x < -12.0, "the car stays outside the wall (x %.1f)" % s.global_position.x)
	TestLib.check(p.global_position.distance_to(s.global_position) < 0.5, "the player follows the car")
	await e.frames(30)
	Input.action_press(&"interact")
	await e.frames(3)
	Input.action_release(&"interact")
	await e.frames(3)
	TestLib.check(p.vehicle == null and mgr.driven == null and not s.driver_is_player, "interact again leaves the car (player.vehicle restored to null)")
	var gap := p.global_position.distance_to(s.global_position)
	TestLib.check(p.body.visible and p.camera_rig.mode == &"foot" and gap > 2.0 and gap < 4.0 and p.global_position.y < 0.6, "the player stands beside the car (%.1f m)" % gap)
	TestLib.check(mgr.toggle_enter_exit() == true and p.vehicle == s, "toggle_enter_exit() enters when on foot next to a car")
	mgr.toggle_enter_exit()
	TestLib.check(p.vehicle == null, "and leaves again")
	s.hp = s.max_hp


func _drive_in_the_open() -> void:
	_extras()
	var car := mgr.spawn_parked(&"sedan", Vector3(100.0, 0.0, -40.0), -PI * 0.5)
	await e.prep(car.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
	Input.action_press(&"interact")
	await e.frames(3)
	Input.action_release(&"interact")
	var x0 := car.global_position.x
	Input.action_press(&"move_forward")
	await e.secs(1.5)
	TestLib.check(car.global_position.x - x0 > 12.0 and car.speed > 12.0, "holding forward drives the car (%.0f m, %.1f m/s)" % [car.global_position.x - x0, car.speed])
	TestLib.check(p.global_position.distance_to(car.global_position) < 0.6, "the player node rides with the car")
	TestLib.check(absf(car.rotation.y - car.heading) < 1e-4, "the root rotates with the heading")
	var h0 := car.heading
	Input.action_press(&"move_right")
	await e.secs(0.8)
	Input.action_release(&"move_right")
	TestLib.check(car.heading < h0 - 0.3, "move_right steers right (%.2f -> %.2f)" % [h0, car.heading])
	var sp := car.speed
	Input.action_release(&"move_forward")
	Input.action_press(&"jump")
	await e.secs(0.7)
	Input.action_release(&"jump")
	TestLib.check(car.speed < sp - 3.0, "jump is the handbrake (%.1f -> %.1f)" % [sp, car.speed])
	Input.action_press(&"move_back")
	await e.secs(1.2)
	Input.action_release(&"move_back")
	TestLib.check(car.speed < 3.0, "move_back brakes (%.1f)" % car.speed)
	TestLib.check(p.speed_boost == 1.0 and absf(float(p.vehicle.speed) - car.speed) < 0.001, "the camera reads a float speed property")
	mgr.exit_vehicle()
	await e.frames(3)
	TestLib.check(p.vehicle == null and mgr.driven == null, "exit_vehicle() puts the player on foot")
	# setting player.vehicle from outside is picked up as well
	p.vehicle = car
	await e.frames(3)
	TestLib.check(mgr.driven == car and car.driver_is_player, "player.vehicle set from outside makes it the driven car")
	p.vehicle = null
	await e.frames(3)
	TestLib.check(mgr.driven == null and not car.driver_is_player, "player.vehicle cleared from outside releases it")
	Fixture.release_inputs()


func _lanes_and_turns() -> void:
	_extras()
	await e.prep(Vector3(40.0, 0.0, 40.0), 0.0)       # cars farther than 124 m from the player are streamed out: keep them near
	# right-hand lanes on all four road directions
	var cases := [[0, 1, -60.0, 5.0, -PI * 0.5], [0, -1, 90.0, -5.0, PI * 0.5], [1, 1, -60.0, -5.0, PI], [1, -1, 90.0, 5.0, 0.0]]
	var cars: Array[Vehicle] = []
	for c in cases:
		var v := mgr.spawn_traffic(&"sedan", c[0], 4, c[1], c[2])
		v.ai_cool = 1000.0
		v.ai_speed = 10.0
		cars.append(v)
	await e.secs(1.5)
	for i in cases.size():
		var c: Array = cases[i]
		var v := cars[i]
		var across := v.global_position.z if c[0] == 0 else v.global_position.x
		TestLib.check(absf(across - float(c[3])) < 0.3 and absf(wrapf(v.heading - float(c[4]), -PI, PI)) < 0.15, \
				"axis %d dir %+d keeps the right-hand lane (offset %.2f, heading %.2f)" % [c[0], c[1], across, v.heading])
		TestLib.check(v.ai_speed > 3.0 and v.speed > 3.0, "traffic cruises (%.1f m/s)" % v.speed)
	_extras()
	# at the map edge the car must turn onto the crossing road, into its right-hand lane
	await e.prep(Vector3(250.0, 0.0, 60.0), 0.0)
	var t := mgr.spawn_traffic(&"sedan", 0, 4, 1, 308.0)
	t.ai_speed = 11.0
	await e.secs(3.0)
	var expected := 320.0 + VehicleSpecs.lane_offset(1, t.ai_dir, Game.LANE)
	TestLib.check(t.ai_axis == 1 and absf(t.ai_line - expected) < 0.01, "the traffic car turned at the map edge (axis %d, line %.1f, expected %.1f)" % [t.ai_axis, t.ai_line, expected])
	TestLib.check(absf(t.global_position.x - expected) < 0.6 and absf(wrapf(t.heading - VehicleSpecs.heading_for(1, t.ai_dir), -PI, PI)) < 0.2, "and drives in the new lane (x %.1f, heading %.2f)" % [t.global_position.x, t.heading])
	_extras()
	# stops for the player standing in the lane, and drives on when he steps aside
	await e.prep(Vector3(-100.0, 0.0, 5.0), 0.0)
	var a := mgr.spawn_traffic(&"sedan", 0, 4, 1, -125.0)
	a.ai_cool = 1000.0
	a.ai_speed = 11.0
	await e.secs(2.8)
	var gap := p.global_position.x - a.global_position.x
	TestLib.check(a.ai_speed < 0.3 and gap > 3.0 and gap < 11.0, "a traffic car stops for the player ahead (speed %.2f, %.1f m away)" % [a.ai_speed, gap])
	await e.prep(Vector3(-100.0, 0.0, 60.0), 0.0)
	await e.secs(2.0)
	TestLib.check(a.ai_speed > 6.0, "and moves on when the way is clear (%.1f m/s)" % a.ai_speed)
	# stops behind a parked car in its lane
	_extras()
	var b := mgr.spawn_traffic(&"sedan", 0, 4, 1, -128.0)
	b.ai_cool = 1000.0
	b.ai_speed = 11.0
	var blocker := mgr.spawn_parked(&"sedan", Vector3(-110.0, 0.0, 5.0), -PI * 0.5)
	await e.secs(2.5)
	TestLib.check(b.ai_speed < 0.3 and blocker.global_position.x - b.global_position.x > 2.5, "traffic stops behind another car (%.1f m)" % (blocker.global_position.x - b.global_position.x))
	_extras()


func _damage_and_respawn() -> void:
	_extras()
	await e.prep(Vector3(60.0, 0.0, 90.0), 0.0)         # 60 m away: beyond the 25 m respawn distance, within the 124 m stream radius
	mgr.respawn_time = 1.0
	Game.heat = 0.0
	var spot := Vector3(60.0, 0.0, 30.0)
	var car := mgr.spawn_parked(&"sedan", spot, 0.0)
	var neighbour := mgr.spawn_parked(&"sedan", spot + Vector3(8.0, 0.0, 0.0), 0.0)
	var dummy := Fixture.add_dummy(root, spot + Vector3(0.0, 0.0, 4.0), 0.9, false)
	car.damage(30.0)
	TestLib.check(is_equal_approx(car.hp, 90.0) and not car.dead, "damage lowers hp (120 -> %.0f)" % car.hp)
	car.damage(-5.0)
	TestLib.check(is_equal_approx(car.hp, 90.0), "negative damage is ignored")
	car.damage(1000.0)
	TestLib.check(car.dead and not car.active and not car.is_in_group(&"vehicle") and not mgr.list.has(car), "a destroyed car leaves play and the group")
	TestLib.check(Game.heat >= 0.19, "destroying a car adds heat (%.2f)" % Game.heat)
	TestLib.check(neighbour.hp < neighbour.max_hp - 30.0, "the explosion hurts the car next to it (hp %.0f)" % neighbour.hp)
	TestLib.check(dummy.total_damage() > 40.0, "the explosion hurts enemies nearby (%.0f)" % dummy.total_damage())
	TestLib.check(mgr.pending_respawns() == 1, "a respawn is queued")
	car.damage(50.0)
	TestLib.check(mgr.pending_respawns() == 1, "damaging a wreck does nothing")
	await e.secs(1.6)
	var back := false
	for v in mgr.list:
		if v.global_position.distance_to(spot) < 1.0 and not v.ai and v.hp == v.max_hp:
			back = true
	TestLib.check(back and mgr.pending_respawns() == 0, "it comes back as a parked car (25 s in the game, 1 s here)")
	dummy.queue_free()
	_extras()
	# a driven car that explodes throws the player out first
	var drv := mgr.spawn_parked(&"sedan", Vector3(60.0, 0.0, 30.0), 0.0)
	await e.prep(drv.global_position + Vector3(3.0, 0.0, 0.0), 0.0)
	mgr.toggle_enter_exit()
	await e.frames(2)
	TestLib.check(p.vehicle == drv, "entered the car that will blow up")
	var hp0 := p.hp
	drv.damage(9999.0)
	await e.frames(2)
	TestLib.check(p.vehicle == null and mgr.driven == null and p.body.visible, "an exploding car puts the driver on foot")
	TestLib.check(p.hp < hp0 - 10.0, "and the blast hurts him (hp %.0f -> %.0f)" % [hp0, p.hp])
	# the starter car comes back at its place
	_extras()
	await e.prep(Vector3(0.0, 0.0, 200.0), 0.0)
	var s := mgr.starter
	s.damage(1000.0)
	TestLib.check(mgr.starter == null and mgr.pending_respawns() >= 1, "the destroyed starter car is gone for now")
	await e.secs(1.6)
	TestLib.check(mgr.starter != null and mgr.starter.global_position.distance_to(VehicleSpecs.starter_pos()) < 0.1 and mgr.starter.hp == mgr.starter.max_hp, "the starter car respawns parked at the spawn")
	mgr.respawn_time = VehicleSpecs.RESPAWN_TIME
	Fixture.release_inputs()


func _ramming() -> void:
	_extras()
	var car := mgr.spawn_parked(&"sport", Vector3(100.0, 0.0, 100.0), -PI * 0.5)
	await e.prep(car.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
	var d1 := Fixture.add_dummy(root, Vector3(135.0, 0.0, 100.0), 0.9, false)
	var d2 := Fixture.add_dummy(root, Vector3(135.0, 0.0, 112.0), 0.9, false)
	Game.heat = 0.0
	mgr.toggle_enter_exit()
	await e.frames(2)
	TestLib.check(p.vehicle == car, "entered the sport car")
	Input.action_press(&"move_forward")
	await e.secs(3.2)
	Input.action_release(&"move_forward")
	TestLib.check(d1.hits.size() == 1 and d1.total_damage() > 8.0 * 3.5 and d1.hits[0].y == 1.0, "ramming a drone at speed hits it once, as a crit (%.0f damage)" % d1.total_damage())
	TestLib.check(d2.hits.is_empty(), "an enemy off to the side is not hit")
	TestLib.check(Game.heat > 0.0, "running things over adds a little heat")
	mgr.exit_vehicle()
	await e.frames(30)
	car.vel = Vector3.ZERO
	car.speed = 0.0
	var d3 := Fixture.add_dummy(root, car.global_position, 0.9, false)
	await e.secs(1.0)
	TestLib.check(d3.hits.is_empty(), "a parked car does not run anybody over")
	d1.queue_free()
	d2.queue_free()
	d3.queue_free()
	Fixture.release_inputs()


func _caps_and_trim() -> void:
	_extras()
	await e.prep(Vector3(0.0, 0.0, 200.0), 0.0)
	for q in [0, 1, 2]:
		Game.set_quality(q)
		_extras()
		var made := 0
		for i in 12:
			if mgr.spawn_parked(&"sedan", Vector3(-60.0 + i * 12.0, 0.0, -200.0), 0.0) != null:
				made += 1
		var want: int = [3, 5, 8][q]
		TestLib.check(mgr.list.size() == want and mgr.cap() == want, "tier %d: %d live cars at most (starter included, %d)" % [q, want, mgr.list.size()])
	Game.set_quality(2)
	TestLib.check(mgr.list.size() == 8, "HIGH holds 8 cars")
	var drv := mgr.list[mgr.list.size() - 1]
	mgr.enter(drv)
	Game.set_quality(0)
	TestLib.check(mgr.list.size() == 3 and mgr.list.has(mgr.starter) and mgr.list.has(drv), "dropping to LOW trims at once to 3, keeping the starter car and the driven car")
	TestLib.check(get_vehicle_group_size() == 3, "trimmed cars left the group (%d)" % get_vehicle_group_size())
	mgr.exit_vehicle()
	await e.frames(2)
	Game.set_quality(1)
	_extras()


func get_vehicle_group_size() -> int:
	return e.host.get_tree().get_nodes_in_group(&"vehicle").size()


func _lifecycle() -> void:
	_extras()
	Game.set_quality(1)
	var s := mgr.starter
	s.hp = 30.0
	s.global_position = Vector3(5.0, 0.0, 5.0)
	var extra := mgr.spawn_parked(&"sedan", Vector3(50.0, 0.0, 50.0), 0.0)
	mgr.respawn_time = 30.0
	mgr.spawn_parked(&"suv", Vector3(70.0, 0.0, 50.0), 0.0).damage(9999.0)
	TestLib.check(mgr.pending_respawns() == 1, "a respawn is pending before the reset")
	await e.prep(s.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
	mgr.enter(s)
	await e.frames(2)
	TestLib.check(p.vehicle == s, "driving the damaged starter car")
	Game.do_respawn()
	await e.frames(4)
	TestLib.check(p.vehicle == null and mgr.driven == null, "respawn: on foot")
	TestLib.check(mgr.list.size() == 1 and mgr.starter != null and mgr.starter.hp == mgr.starter.max_hp, "respawn: only a repaired starter car is left")
	TestLib.check(mgr.starter.global_position.distance_to(VehicleSpecs.starter_pos()) < 0.1 and mgr.pending_respawns() == 0, "respawn: back at its place, queue empty")
	TestLib.check(not extra.active, "respawn: the other cars are pooled")
	var again := mgr.spawn_parked(&"sedan", Vector3(50.0, 0.0, 50.0), 0.0)
	Game.start_new_game()
	await e.frames(3)
	TestLib.check(mgr.list.size() == 1 and not again.active, "new game resets as well")
	Game.do_next_sector()
	await e.frames(3)
	TestLib.check(mgr.list.size() == 1 and mgr.starter != null, "next sector resets as well")
	mgr.respawn_time = VehicleSpecs.RESPAWN_TIME
	Fixture.release_inputs()
