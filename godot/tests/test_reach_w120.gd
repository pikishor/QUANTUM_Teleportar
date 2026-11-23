extends RefCounted
## WAVE 120 REACH (owner round 7: "the whole map must be reachable: mountains, river, buildings; no invisible walls"). The real main scene, the phone HUD, REAL FINGERS only
## (stick, JUMP, ENTER, GAS, view swipes: tests/w116_fingers.gd through tests/w120_reach_lib.gd), the phone-only layers on (CrateReveal._quiet = 0). Start points are set up by
## teleport; every move is a finger.
##   walk    by the stick to: a city street, a village (PINE HOLLOW), the river bed (HIGHLINE RIVER), a far shore, and up a mountain face steeper than the walkable 50 degrees
##           (EASTWATER valley side, 38 m up; the wave 119 hero stood at its foot)                                                         [old fails: the steep face]
##   swim    across the EASTWATER (swims, reaches the far bank)
##   car     a car driven by GAS into deep water sinks and the hero is out, swimming                                                          [old fails: the car stopped at the shore]
##   edge    swimming out to sea toward the world edge: a swell turns him back before the old invisible wall, he stays in the sea              [old fails]
##   drops   200 random drops over the land: never more than 0.6 m under the ground during the fall, standing on it after                [old fails: sank 3 m before the rescue]
## REACH_OLD=1 = the wave 119 behaviour (PlayerSwim.reach_on false). REACH_PARTS=walk,swim,... picks parts. REACH_DROPS=n changes the drop count (default 200).
## Run: tools/test.sh tests/test_reach_w120.gd
const TIMEOUT_SECONDS := 140
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib


func run(h: Node) -> void:
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var parts := (OS.get_environment("REACH_PARTS") if OS.get_environment("REACH_PARTS") != "" else "walk,swim,car,edge,drops").split(",")
	for part in parts:
		var t0 := Time.get_ticks_msec()
		match part:
			"walk": await _walk()
			"swim": await _swim()
			"car": await _car()
			"edge": await _edge()
			"drops": await _drops()
		print("part %s: %.1f s" % [part, (Time.get_ticks_msec() - t0) / 1000.0])
	await L.finish()


func _go(name: String, from: Vector2, to: Vector2, limit := 20.0) -> Dictionary:
	var f3 := Vector3(from.x, Lib.ground(from.x, from.y) + 1.0, from.y)
	var t3 := Vector3(to.x, 0.0, to.y)
	await L.tp(f3, Lib.yaw_to(f3, t3))
	await L.secs(0.5)
	var r := await L.walk(t3, limit)
	TestLib.check(r["reached"] and not r["fell"], "by the stick to %s (%.1f m short, climbed %.1f m, block %s)" % [name, r["dist"], r["climbed"], r["block"]])
	return r


func _walk() -> void:
	var sp := Game.SPAWN + Vector3(0.0, 1.2, 0.0)
	var to := Vector2(sp.x, sp.z - 20.0)
	for k in 8:                                                   # setup: a direction along the street (a ray at chest height clear for 22 m)
		var d := Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0))
		var q := PhysicsRayQueryParameters3D.create(sp, sp + d * 22.0, Game.L_WORLD)
		if L.p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			to = Vector2(sp.x + d.x * 20.0, sp.z + d.z * 20.0)
			break
	await _go("a city street", Vector2(sp.x, sp.z), to)
	OutskirtsSites.ensure()
	var ph: Vector3 = OutskirtsSites.by_id(&"pine_hollow")["pos"]
	await _go("the village PINE HOLLOW", Vector2(ph.x, ph.z) + Vector2(30, 0), Vector2(ph.x, ph.z))
	await _go("the HIGHLINE RIVER bed", Vector2(-884.6, -1474.3), Vector2(-900.0, -1500.0))
	await _go("the far west shore (into the sea)", Vector2(-3250.0, 0.0), Vector2(-3292.0, 0.0))
	var r := await _go("the top of a steep valley side (steeper than 50 degrees)", Vector2(2028.8, 78.8), Vector2(2070.1, 119.8))
	TestLib.check(float(r["climbed"]) > 25.0, "the steep face was climbed, not walked around (%.1f m up) [old fails]" % r["climbed"])


func _swim() -> void:
	var r := await _go("the far bank across the EASTWATER", Vector2(1421.5, 990.5), Vector2(1476.7, 1010.1), 30.0)
	TestLib.check(r["swam"], "he swam on the way across the river")


func _car() -> void:
	var vm := Game.vehicles as VehicleManager
	var bank := Vector3(1395.0, 0.0, 981.0)
	var to := Vector3(1450.0, 0.0, 1000.0)
	var yaw := Lib.yaw_to(bank, to)
	bank.y = Lib.ground(bank.x, bank.z)
	await L.tp(bank + Vector3(0.0, 1.0, 0.0), yaw)
	var car := vm.spawn_parked(&"sedan", bank + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 4.0, yaw)
	TestLib.check(car != null, "a sedan stands on the river bank")
	if car == null:
		return
	await L.secs(1.0)
	var inside := false
	for attempt in 3:
		await L.press(&"interact", 6)
		for i in 24:
			await L.secs(0.25)
			if L.p.get(&"vehicle") == car:
				inside = true
				break
		if inside:
			break
		await L.secs(0.5)
	TestLib.check(inside, "a finger on ENTER beside a car on the river bank: in the car [old fails: ENTER did nothing anywhere over 2 m of height] (in %s, button %s %s, car %s, hero %s)" % [L.p.vehicle, L.fg.button(&"interact"), L.fg.button_label(&"interact"), car.global_position, L.p.global_position])
	if not inside:
		return
	L.fg.press(5, &"move_forward")                                  # GAS held
	var sank := false
	for i in 40:
		await L.secs(0.25)
		if car.sunk:
			sank = true
		if sank and L.p.get(&"vehicle") == null and L.p.swim.active:
			break
	L.fg.up(5)
	await L.secs(1.0)
	TestLib.check(sank, "the car drove into the deep river and sank (car at %s) [old fails]" % car.global_position)
	TestLib.check(L.p.get(&"vehicle") == null and (L.p.swim.active or L.p.swim.wading), "the hero is out of the sunk car, in the water (swimming %s)" % L.p.swim.active)


func _edge() -> void:
	var s := Vector3(CityLayout.PLAY_HALF - 160.0, TerrainHeight.SEA_LEVEL - 0.5, 600.0)
	var e := Vector3(CityLayout.PLAY_HALF + 200.0, 0.0, 600.0)
	await L.place(s, Lib.yaw_to(s, e))
	var t0 := L.p.swim.turned_back
	var far := 0.0
	L.fg.stick(Vector2(0.0, -1.0))
	for i in 120:
		await L.secs(0.25)
		far = maxf(far, L.p.global_position.x)
		var err := wrapf(Lib.yaw_to(L.p.global_position, e) - L.p.camera_rig.yaw, -PI, PI)
		if absf(err) > 0.21:
			L.fg.look(-err * 160.0, 0.0, 4)
	L.fg.stick(Vector2.ZERO)
	TestLib.check(L.p.swim.turned_back > t0 and far < CityLayout.PLAY_HALF - 100.0, "swimming at the world edge: the swell turned him back %.0f m before the old wall (%d notes) [old fails]" % [CityLayout.PLAY_HALF - far, L.p.swim.turned_back - t0])
	TestLib.check(L.p.global_position.x > CityLayout.PLAY_HALF - 400.0 and L.p.swim.active, "he is still out in the sea, swimming (x %.0f): no teleport back to a street" % L.p.global_position.x)


func _drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1200
	var n := int(OS.get_environment("REACH_DROPS")) if OS.get_environment("REACH_DROPS") != "" else 200
	var bad: Array[String] = []
	var done := 0
	var tries := 0
	while done < n and tries < n * 4:
		tries += 1
		var x := rng.randf_range(-4200.0, 4200.0)
		var z := rng.randf_range(-4200.0, 4200.0)
		var g := Lib.ground(x, z)
		if g < TerrainHeight.SEA_LEVEL + 0.5 or maxf(absf(x), absf(z)) < CityLayout.WALK + 20.0 or WaterWorld.surface_y(x, z) != TerrainHeight.NO_WATER:
			continue
		done += 1
		L.p.snake.cancel()
		L.p.swim.reset()
		L.p.global_position = Vector3(x, g + 3.0, z)                # setup: in the air over a spot the hero has never been near (its collider may not exist yet)
		L.p.velocity = Vector3(0.0, -25.0, 0.0)
		var worst := -99.0
		for k in 24:
			await L.host.get_tree().physics_frame
			var gp := L.p.global_position
			worst = maxf(worst, Lib.ground(gp.x, gp.z) - gp.y)
		var gp2 := L.p.global_position
		if worst > 0.6 or L.under_ground(gp2):
			bad.append("(%.0f, %.0f) %.1f m under" % [x, z, worst])
	TestLib.check(done >= n and bad.is_empty(), "%d random drops over the land: never more than 0.6 m under the ground (%d bad: %s) [old fails]" % [done, bad.size(), bad.slice(0, 6)])
