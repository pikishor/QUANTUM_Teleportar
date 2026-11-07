extends RefCounted
## Director review 3, gameplay half (docs/SLICE_REVIEW.md "Fix pass, round 3 gameplay half"), in the REAL game scene:
##   1  the car: three bumps at 39 / 48 / 51 km/h no longer wreck a car (the first costs almost nothing, no bump takes more than CRASH_BUMP_MAX of the hull), a hard hit still hurts;
##      a car wedged against a wall with the throttle held backs itself out; the crack decal sits inside the glass (below the roof line), a bump in a car never flashes the screen red
##   2  the fight: the first wave comes about 18 s in and the squad stands 11-21 m away (the real director, in the real scene)
##   3  the camera never sits inside a lamp post or a kiosk (the arm ignores props: a sphere query at the camera pushes it aside)
##   8  the hack site is a lit pad (a wide band and a bright disc), any other marker is a thin ring again
##   9  a fresh player's map is charted only around the start (not 100 %)
## Waits on game time, positions and counters, never on frame counts; user:// state is reset first. Frames of the same things: tests/bot_round2_fight.gd (FIGHT_OUT=...),
## tools/vehicle_view.sh (cracks), tests/bot_director_review.gd; the sheet is docs/shots/slice/round3_a_before_after.jpg.
## Run: tools/test.sh tests/test_director_round3_a.gd

const K := 4
const DT := 1.0 / 60.0
const AVE_Z := 5.0

var host: Node
var city: City
var p: Player
var mgr: VehicleManager
var walls: Array[StaticBody3D] = []


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_numbers()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	TestLib.check(city != null and p != null and mgr != null, "the real scene has a city, a player and a vehicle manager")
	if city == null or p == null or mgr == null:
		return
	p.set_physics_process(true)
	p.max_hp = 100.0
	p.hp = 100.0
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	for k: StringName in [&"sedan", &"sport"]:
		mgr.spawn_parked(k, Vector3(-700.0 + float(mgr.list.size()) * 10.0, 0.0, 400.0), 0.0)
		await TestLib.frames(host, 2)
		for v in mgr.list.duplicate():
			if v != mgr.starter:
				mgr._release(v)
	await TestLib.frames(host, 4)
	await _bumps_and_wedge()
	_crack_inside_glass()
	await _hack_pad()
	_map_fresh()
	await _camera_props()
	await _first_wave()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	for w in walls:
		w.queue_free()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


# --- the numbers ----------------------------------------------------------------------------------------------------------------------------------------

func _numbers() -> void:
	var f39 := Vehicle.crash_fraction(39.0 / 3.6)
	var f51 := Vehicle.crash_fraction(51.0 / 3.6)
	TestLib.check(f39 < 0.05 and f51 < 0.15, "a 39 km/h bump is %.1f %% and a 51 km/h bump %.1f %% of the reference hull" % [f39 * 100.0, f51 * 100.0])
	TestLib.check(Vehicle.crash_fraction(90.0 / 3.6) > 0.55, "90 km/h still hurts a lot (%.0f %%)" % (Vehicle.crash_fraction(90.0 / 3.6) * 100.0))
	TestLib.check(VehicleSpecs.CRASH_BUMP_MAX <= 0.13 and VehicleSpecs.WEDGE_SECS <= 2.0, "a street bump takes at most %.0f %% of the hull, a wedged car backs out after %.1f s" % [VehicleSpecs.CRASH_BUMP_MAX * 100.0, VehicleSpecs.WEDGE_SECS])
	TestLib.check(Encounters.FIRST_DELAY <= 20.0 and Encounters.FIRST_DELAY >= 15.0 and Encounters.SPAWN_MAX <= 22.0 and Encounters.SPAWN_MIN <= 12.0, "the first squad comes about %.0f s in, %.0f-%.0f m away" % [Encounters.FIRST_DELAY, Encounters.SPAWN_MIN, Encounters.SPAWN_MAX])


# --- helpers --------------------------------------------------------------------------------------------------------------------------------------------

func _clear() -> void:
	if mgr.driven != null:
		mgr.exit_vehicle()
	for v in mgr.list.duplicate():
		mgr._release(v)
	mgr.starter = null
	if NearTraffic.instance != null:
		NearTraffic.instance.count = 0
		NearTraffic.instance.reset()


func _car(kind: StringName, x: float, z := AVE_Z, heading := -PI * 0.5, collide := false) -> Vehicle:
	while mgr.list.size() >= mgr.cap():
		mgr._release(mgr.list[0])
	var v := mgr.spawn_parked(kind, Vector3(x, 0.0, z), heading)
	v.global_position = Vector3(x, 0.0, z)
	v.heading = heading
	v.rotation = Vector3(0.0, heading, 0.0)
	v._heading_set = heading
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.yaw_rate = 0.0
	v._dist = 0.0
	v.collision_mask = Game.L_WORLD if collide else 0
	return v


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	host.add_child(b)
	b.global_position = center
	walls.append(b)
	return b


## One head-on hit of `speed` m/s into the wall at x = -300; returns the hull share lost (0..1 of max_hp).
func _hit(v: Vehicle, speed: float) -> float:
	v.global_position = Vector3(-304.6, 0.0, AVE_Z)
	v.heading = -PI * 0.5
	v.rotation = Vector3(0.0, v.heading, 0.0)
	v._heading_set = v.heading
	v.vel = v.forward() * speed
	v.speed = speed
	var hp0 := v.hp
	var c0 := v.crashes
	var t := 0.0
	while v.crashes == c0 and t < 2.0:
		v.step_drive(DT, 0.0, 0.0, false)
		v._sync(DT)
		t += DT
	for i in 30:
		v.step_drive(DT, 0.0, 0.0, false)
		v._sync(DT)
	return (hp0 - v.hp) / v.max_hp


# --- 1: the car -----------------------------------------------------------------------------------------------------------------------------------------

func _bumps_and_wedge() -> void:
	_clear()
	mgr.set_physics_process(false)
	_wall(Vector3(-299.5, 3.0, AVE_Z), Vector3(1.0, 6.0, 160.0))
	await TestLib.frames(host, 4)
	var car := _car(&"sport", -304.6, AVE_Z, -PI * 0.5, true)
	var hp0 := car.hp
	var shares: Array[float] = []
	for kmh: float in [39.0, 48.0, 51.0]:
		shares.append(_hit(car, kmh / 3.6))
	var total := (hp0 - car.hp) / car.max_hp
	var worst := 0.0
	for sh in shares:
		worst = maxf(worst, sh)
	TestLib.check(worst <= VehicleSpecs.CRASH_BUMP_MAX + 0.01 and total < 0.35 and not car.dead and car.hp > car.max_hp * 0.6, "three bumps at 39 / 48 / 51 km/h cost %.0f %% / %.0f %% / %.0f %% of a sport car's hull (%.0f %% in all), the car is fine" % [shares[0] * 100.0, shares[1] * 100.0, shares[2] * 100.0, total * 100.0])
	_clear()
	# wedged: nose into the wall, the throttle held. It must back out by itself.
	var wedge := _car(&"sedan", -306.0, AVE_Z, -PI * 0.5, true)
	mgr.enter(wedge)
	wedge.active = true
	var n0 := wedge.wedge_count
	var t := 0.0
	var best_back := 0.0
	while t < 9.0 and wedge.wedge_count == n0:
		wedge.step_drive(DT, 1.0, 0.0, false)
		wedge._sync(DT)
		t += DT
	TestLib.check(wedge.wedge_count > n0 and t <= 9.0, "held against a wall the car decides it is wedged (%.1f s after the start, the run-up included)" % t)
	var wedge_x := wedge.global_position.x
	var t2 := 0.0
	while t2 < 1.4:
		wedge.step_drive(DT, 1.0, 0.0, false)
		wedge._sync(DT)
		best_back = maxf(best_back, wedge_x - wedge.global_position.x)
		t2 += DT
	TestLib.check(best_back > 0.8, "and backs out on its own (%.1f m away from the wall with the throttle still held)" % best_back)
	mgr.exit_vehicle()
	_clear()
	mgr.set_physics_process(true)


func _crack_inside_glass() -> void:
	_clear()
	var ok := true
	var worst := ""
	for k: StringName in [&"sedan", &"sport", &"taxi", &"suv", &"wagon"]:
		var v := _car(k, -560.0 + float(randi() % 20), 300.0, 0.0)
		v.visual.crack_glass(1.0, Vector3(0.9, 0.7, 0.0))
		var mi := v.visual._crack_mi as MeshInstance3D
		var top := 0.0
		if mi != null and mi.mesh != null:
			top = mi.mesh.get_aabb().end.y
		var hg := float(VehicleSpecs.SPECS[k]["hgt"])
		if mi == null or top <= 0.0 or top > hg * 0.9:
			ok = false
			worst = "%s %.2f of %.2f" % [k, top, hg]
		v.visual.repair()
	TestLib.check(ok, "the crack decal stays below the roof line on every body (%s)" % worst)
	_clear()


# --- 8: the hack pad ------------------------------------------------------------------------------------------------------------------------------------

func _hack_pad() -> void:
	var m := Game.missions as Missions
	var vis := ContractVisuals.new()
	host.add_child(vis)
	vis.show_marker(0, Vector3(0, 0, 0), 9.0, ContractTypes.CYAN, 0.0, true)
	var mat := vis.markers[0].mat as ShaderMaterial
	var thin_fill := float(mat.get_shader_parameter(&"fill_a"))
	vis.set_pad_style(0, true)
	var pad_fill := float(mat.get_shader_parameter(&"fill_a"))
	var pad_inner := float(mat.get_shader_parameter(&"inner"))
	TestLib.check(pad_fill > thin_fill * 4.0 and pad_inner < 0.85, "the hack pad is a wide band with a bright disc (fill %.2f, band from %.2f; a plain ring has %.3f)" % [pad_fill, pad_inner, thin_fill])
	vis.show_marker(0, Vector3(5, 0, 5), 4.0, ContractTypes.AMBER, -1.0, true)
	TestLib.check(is_equal_approx(float(mat.get_shader_parameter(&"fill_a")), thin_fill), "the next marker is a thin ring again")
	vis.queue_free()
	if m != null and m.campaign != null:
		var k := m.campaign
		k.enabled = true
		var started := k.start_custom({"id": "r3a", "clears_sector": false, "steps": [{"kind": "hack", "pos": [-200.0, 0.0], "hold": 20.0, "obj": "Hack the node"}]})
		var real := -1.0
		var guard := 0
		while guard < 120 and (k.visuals == null or not k.visuals.marker_visible(0)):
			await TestLib.frames(host, 2)
			guard += 1
		if k.visuals != null:
			real = float((k.visuals.markers[0].mat as ShaderMaterial).get_shader_parameter(&"fill_a"))
		TestLib.check(started and real > 0.2, "the campaign's own hack step draws the pad (started %s, fill %.2f)" % [str(started), real])
		k.enabled = false


# --- 9: the map -----------------------------------------------------------------------------------------------------------------------------------------

func _map_fresh() -> void:
	MapScreen.path_override = "user://test_round3_a_map_%d.cfg" % OS.get_process_id()
	var ms := MapScreen.new()
	host.add_child(ms)
	var share := 100.0 * float(ms.discovered_count()) / float(MapScreen.CELLS * MapScreen.CELLS)
	TestLib.check(share >= 10.0 and share <= 40.0, "a fresh map is charted around the start only (%.0f %%, never 100 %%)" % share)
	ms.queue_free()
	MapScreen.path_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_round3_a_map_%d.cfg" % OS.get_process_id()))


# --- 3: the camera and the props -----------------------------------------------------------------------------------------------------------------------

func _camera_props() -> void:
	var rig := p.camera_rig
	Game.state = &"play"
	await TestLib.frames(host, 3)
	rig._exclude_props()
	var pole := StaticBody3D.new()
	pole.collision_layer = Game.L_WORLD
	pole.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.2
	cyl.height = 8.0
	cs.shape = cyl
	pole.add_child(cs)
	host.add_child(pole)
	walls.append(pole)
	await TestLib.frames(host, 2)
	var cam_at := rig.camera.global_position
	pole.global_position = Vector3(cam_at.x + 0.1, cam_at.y, cam_at.z)
	await TestLib.frames(host, 2)
	rig._prop_rids[pole.get_rid()] = true
	var push := rig._prop_avoid(cam_at, rig._pivot_pos, 1.0)
	TestLib.check(push.length() > 0.3, "a pole at the camera pushes it aside (%.2f m)" % push.length())
	pole.global_position = Vector3(cam_at.x + 30.0, cam_at.y, cam_at.z)
	await TestLib.frames(host, 2)
	var away := rig._prop_avoid(cam_at, rig._pivot_pos, 5.0)
	TestLib.check(away.length() < 0.05, "and lets go once the pole is far away (%.2f m)" % away.length())


# --- 2: the first wave ----------------------------------------------------------------------------------------------------------------------------------

func _first_wave() -> void:
	_clear()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	var mgrE := Game.enemies as EnemyManager
	mgrE.patrol_groups().clear()
	mgrE.clear()
	if Game.story != null:
		(Game.story as Story).skip_cards()
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	Game.state = &"play"
	var enc := Encounters.current
	enc.enabled = true
	enc.reset()
	p.global_position = Game.SPAWN
	Game.heat = 0.0
	var lo := 1.0e9
	var started := false
	var guard := 0
	while not started and guard < 400:
		enc.tick(0.25)
		guard += 1
		started = enc.waves_started >= 1
	TestLib.check(started and enc.first_wave_t >= Encounters.FIRST_DELAY - 2.0 and enc.first_wave_t <= Encounters.FIRST_DELAY + 6.0, "the first squad is on the street %.1f s into the play" % enc.first_wave_t)
	var near_ok := started
	var n := 0
	for d in enc.squad:
		if is_instance_valid(d):
			var dist := Vector2(d.global_position.x - p.global_position.x, d.global_position.z - p.global_position.z).length()
			lo = minf(lo, dist)
			near_ok = near_ok and dist <= Encounters.SPAWN_MAX + 6.0
			n += 1
	TestLib.check(n >= 3 and near_ok and lo >= 5.0, "the squad (%d) stands within %.0f m of the hero, the nearest at %.0f m" % [n, Encounters.SPAWN_MAX + 6.0, lo])
	enc.enabled = false
	mgrE.clear()
