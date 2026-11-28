extends "res://tests/tankmis_w129_bot.gd"
## w129-tankmis: THE ODD MILITARY VEHICLES MOVE THEIR OWN WAY (TankMoves; until wave 128 all of them drove like a tracked tank). Real scene, REAL fingers only (the left thumb drives,
## ENTER by a finger; helpers of tests/tankmis_w129_bot.gd), Game.force_touch, phone-only layers on:
##   HOVER TANK   a hard turn at speed makes it DRIFT (its velocity slides off the nose), and it glides OVER the sea instead of driving along the sea bed
##   STRIDER      its speed rises and falls with each stride, and its legs step when it turns on the spot
##   MUDSKIPPER   it drives into the sea and FLOATS at the surface (not on the bed), its jets push it on, and it climbs back out onto the beach
## Every check marked [old fails] fails with W129TM_OLD=1.
## Run: tools/test.sh tests/test_tankmoves_w129.gd
const TIMEOUT_SECONDS := 140
const BEACH := Vector3(-1260.0, 0.0, 1540.0)        ## dry sand; the sea gets 2.5 m deep 28 m to the south (+z) and stays deep
const SOUTH := PI                                     ## heading that faces +z
const STREET := Vector3(-560.0, 0.0, -84.0)           ## the long east-west street z = -80, 420 m of straight road to the west of here
const WEST := PI * 0.5


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	host.get_tree().root.size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 8
	await _hover()
	await _walker()
	await _swim()
	fg.up_all()
	TestMode.god = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _ride(kind: StringName, at: Vector3, hdg: float) -> Vehicle:
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(10)
	at.y = Vehicle._terrain_y(at.x, at.z)
	await _place_hero(at + Vector3(12.0, 0.0, 0.0), at)          # the ground streams in round the hero first
	await _wait(1.0)
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, hdg)
	vm._count_fixed()
	if v == null:
		return null
	v.set_meta(&"hold", true)
	await _f(4)
	return v if await _board(v) else null


func _drop(v: Vehicle) -> void:
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(10)
	if is_instance_valid(v):
		v.remove_meta(&"hold")
		if v.active and not v.driver_is_player:
			vm._release(v)
	vm._count_fixed()


func _slip(v: Vehicle) -> float:
	var hv := Vector2(v.vel.x, v.vel.z)
	if hv.length() < 3.0:
		return 0.0
	var f := v.forward()
	return absf(hv.angle_to(Vector2(f.x, f.z)))


func _hover() -> void:
	var v := await _ride(&"t_hover", Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, Airport.RUNWAY_S - 60.0)), Airport.heading_world(0.0))      # the runway: 800 m x 44 m of open tarmac
	TestLib.check(v != null, "HOVER: the hero boards the hover tank by finger")
	if v == null:
		return
	fg.stick(Vector2(0.0, -1.0))
	await _wait(3.5)
	var v0 := v.speed
	var slip := 0.0
	fg.stick(Vector2(1.0, -1.0))
	var t0 := _t
	while _t - t0 < 1.0:
		await _step()
		slip = maxf(slip, _slip(v))
	fg.stick(Vector2.ZERO)
	print("HOVER: %.1f m/s, slip in a hard turn %.3f rad" % [v0, slip])
	TestLib.check(v0 > 10.0 and slip > 0.12, "[old fails] HOVER: a hard turn at %.0f m/s makes it drift (the path slides %.2f rad off the nose)" % [v0, slip])
	await _drop(v)
	# over the sea
	var w := await _ride(&"t_hover", BEACH, SOUTH)
	if w == null:
		TestLib.check(false, "HOVER: the hero boards the hover tank on the beach")
		return
	fg.stick(Vector2(0.0, -1.0))
	var under := 99.0
	var deep := 0.0
	t0 = _t
	while _t - t0 < 7.0:
		await _step()
		var q := w.global_position
		var dp := TerrainHeight.depth_at(q.x, q.z)
		if dp > 2.5:
			deep = maxf(deep, dp)
			under = minf(under, (q.y - w.base_y) - WaterWorld.surface_y(q.x, q.z))
	fg.stick(Vector2.ZERO)
	print("HOVER over the sea: deepest %.1f m, lowest hull height over the surface %.2f m, at %s" % [deep, under, w.global_position])
	TestLib.check(deep > 2.5 and under > -0.3, "[old fails] HOVER: it glides over the sea (%.1f m deep), never under the surface (lowest %.2f m)" % [deep, under])
	await _drop(w)


func _walker() -> void:
	var v := await _ride(&"t_walker", STREET, WEST)
	TestLib.check(v != null, "STRIDER: the hero boards the walker by finger")
	if v == null:
		return
	fg.stick(Vector2(0.0, -1.0))
	await _wait(3.0)
	var lo := 99.0
	var hi := 0.0
	var t0 := _t
	while _t - t0 < 3.0:
		await _step()
		lo = minf(lo, v.speed)
		hi = maxf(hi, v.speed)
	fg.stick(Vector2.ZERO)
	await _wait(2.0)
	print("STRIDER: speed %.2f .. %.2f m/s" % [lo, hi])
	TestLib.check(hi > 3.0 and (hi - lo) / hi > 0.25, "[old fails] STRIDER: its speed rises and falls with each stride (%.1f .. %.1f m/s)" % [lo, hi])
	await _until(func() -> bool: return absf(v.speed) < 0.1, 6.0)          # standing: only the pivot can move the legs now
	await _wait(0.3)
	var pose0 := TankModels.pose_of(v.visual.model)
	var h0 := v.heading
	fg.stick(Vector2(1.0, 0.0))
	var moved := 0.0
	var t1 := _t
	while _t - t1 < 1.5:                                                     # the largest change of any leg from its standing pose during the pivot
		await _wait(0.1)
		var pose1 := TankModels.pose_of(v.visual.model)
		for i in mini(pose0.size(), pose1.size()):
			if pose0[i] is Transform3D and pose1[i] is Transform3D:
				moved = maxf(moved, ((pose0[i] as Transform3D).origin - (pose1[i] as Transform3D).origin).length() + ((pose0[i] as Transform3D).basis.z - (pose1[i] as Transform3D).basis.z).length())
	fg.stick(Vector2.ZERO)
	var turned := absf(wrapf(v.heading - h0, -PI, PI))
	print("STRIDER: turned %.2f rad on the spot, legs moved %.3f" % [turned, moved])
	TestLib.check(turned > 0.4 and moved > 0.25, "[old fails] STRIDER: its legs step when it turns on the spot (turned %.2f rad, legs %.3f)" % [turned, moved])
	await _drop(v)


func _swim() -> void:
	var v := await _ride(&"t_amphib", BEACH, SOUTH)
	TestLib.check(v != null, "MUDSKIPPER: the hero boards the amphibious carrier on the beach by finger")
	if v == null:
		return
	fg.stick(Vector2(0.0, -1.0))
	var t0 := _t
	var float_err := 99.0
	var swim_speed := 0.0
	var deep := 0.0
	while _t - t0 < 14.0:
		await _step()
		var q := v.global_position
		var dp := TerrainHeight.depth_at(q.x, q.z)
		if dp > 3.0:
			deep = maxf(deep, dp)
			float_err = minf(float_err, absf((q.y - v.base_y) - (WaterWorld.surface_y(q.x, q.z) - TankMoves.SWIM_DRAFT)))
			swim_speed = maxf(swim_speed, absf(v.speed))
	var out_at := v.global_position
	print("MUDSKIPPER: deepest %.1f m, closest to the float line %.2f m, top swim speed %.1f m/s, at %s (y %.2f, surface %.2f)" % [deep, float_err, swim_speed, out_at, out_at.y - v.base_y, WaterWorld.surface_y(out_at.x, out_at.z)])
	TestLib.check(deep > 3.0 and float_err < 0.4, "[old fails] MUDSKIPPER: in %.1f m of water it floats at the surface (%.2f m off its float line)" % [deep, float_err])
	TestLib.check(swim_speed > 2.5 and swim_speed < TankMoves.SWIM_MAX + 0.5, "[old fails] MUDSKIPPER: its jets push it through the water at %.1f m/s (slower than on land)" % swim_speed)
	# back to the beach: turn round with the thumb, then full ahead until the tracks bite
	fg.stick(Vector2(1.0, -0.3))
	await _until(func() -> bool: return absf(wrapf(v.heading - SOUTH - PI, -PI, PI)) < 0.25, 14.0)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return TerrainHeight.depth_at(v.global_position.x, v.global_position.z) <= 0.01 and _flat(v.global_position, BEACH) < 25.0, 24.0)
	await _wait(1.5)
	fg.stick(Vector2.ZERO)
	var q2 := v.global_position
	var ground := Vehicle._terrain_y(q2.x, q2.z)
	print("MUDSKIPPER back: at %s, depth %.2f, hull %.2f over the ground" % [q2, TerrainHeight.depth_at(q2.x, q2.z), q2.y - v.base_y - ground])
	TestLib.check(TerrainHeight.depth_at(q2.x, q2.z) <= 0.01 and absf(q2.y - v.base_y - ground) < 0.4 and not v.has_meta(&"tm_swim"), "MUDSKIPPER: it climbs back out onto the beach on its tracks (depth %.2f, %.2f m over the sand)" % [TerrainHeight.depth_at(q2.x, q2.z), q2.y - v.base_y - ground])
	await _drop(v)
