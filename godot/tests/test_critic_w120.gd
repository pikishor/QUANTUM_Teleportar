extends RefCounted
## w120-critic: the reviewer's own checks on wave 120 (reach + sky). The real main scene, the phone HUD, REAL FINGERS only (tests/w120_reach_lib.gd -> tests/w116_fingers.gd),
## phone-only layers on (CrateReveal._quiet = 0). Start points by teleport (setup only); every action is a finger.
##   sunk   a car driven by GAS into the deep EASTWATER sinks; a finger on ENTER beside the sunk car must NOT put the hero back in it   [old fails: he got back into the dead car under water]
##   boat   a boat driven by GAS straight at the east world edge turns back softly, never runs into the invisible wall                 [old fails: stopped dead at the wall]
##   plane  a plane at full throttle flying straight at the east world edge keeps its airspeed and height while the soft turn-back turns it   [old fails: the edge ate its airspeed, it stalled and fell]
## CRITIC_PARTS=sunk,boat,plane picks parts.
const TIMEOUT_SECONDS := 140
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib


func run(h: Node) -> void:
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var parts := (OS.get_environment("CRITIC_PARTS") if OS.get_environment("CRITIC_PARTS") != "" else "sunk,boat,plane").split(",")
	for part in parts:
		match part:
			"sunk": await _sunk()
			"boat": await _boat()
			"plane": await _plane()
	await L.finish()


func _enter(car: Vehicle) -> bool:
	for attempt in 3:
		await L.press(&"interact", 6)
		for i in 16:
			await L.secs(0.25)
			if L.p.get(&"vehicle") == car:
				return true
		await L.secs(0.4)
	return false


func _sunk() -> void:
	var vm := Game.vehicles as VehicleManager
	var bank := Vector3(1395.0, 0.0, 981.0)
	var to := Vector3(1450.0, 0.0, 1000.0)
	var yaw := Lib.yaw_to(bank, to)
	bank.y = Lib.ground(bank.x, bank.z)
	await L.tp(bank + Vector3(0.0, 1.0, 0.0), yaw)
	var car := vm.spawn_parked(&"sedan", bank + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 4.0, yaw)
	await L.secs(1.0)
	var inside := await _enter(car)
	TestLib.check(inside, "setup: in the sedan on the river bank by a finger on ENTER")
	if not inside:
		return
	L.fg.press(5, &"move_forward")
	for i in 40:
		await L.secs(0.25)
		if car.sunk and L.p.get(&"vehicle") == null:
			break
	L.fg.up(5)
	await L.secs(1.5)
	TestLib.check(car.sunk and L.p.get(&"vehicle") == null, "the car sank and the hero is out (sunk %s)" % car.sunk)
	var back := false
	for attempt in 3:
		await L.press(&"interact", 6)
		for i in 6:
			await L.secs(0.1)
			if L.p.get(&"vehicle") == car:
				back = true
	TestLib.check(not back, "a finger on ENTER beside the sunk car does not put him back into it (he got in: %s) [old fails]" % back)


func _boat() -> void:
	var vm := Game.vehicles as VehicleManager
	var s := Vector3(CityLayout.PLAY_HALF - 420.0, TerrainHeight.SEA_LEVEL - 0.5, 2000.0)
	var yaw := Lib.yaw_to(s, s + Vector3(100.0, 0.0, 0.0))
	await L.place(s + Vector3(0.0, 0.0, 3.0), yaw)
	var boat := vm.spawn_parked(&"boat", s, yaw)
	TestLib.check(boat != null, "setup: a boat out at sea")
	if boat == null:
		return
	await L.secs(1.0)
	var inside := await _enter(boat)
	TestLib.check(inside, "setup: in the boat by a finger on ENTER (hero %s, boat %s)" % [L.p.global_position, boat.global_position])
	if not inside:
		return
	L.fg.stick(Vector2(0.0, -1.0))                               # the stick full ahead all the way, no steering
	var far := 0.0
	var dead := 0
	for i in 160:
		await L.secs(0.1)
		var gp := boat.global_position
		far = maxf(far, gp.x)
		if i % 40 == 0:
			print("boat t=%.1f x=%.1f v=%.1f g=%d sea=%s fwd=%.2f drv=%s d=%.1f" % [i * 0.1, gp.x, boat.vel.length(), boat.craft.groundings, boat.craft.sea, Input.get_action_strength(&"move_forward"), boat.driver_is_player, TerrainHeight.depth_at(gp.x, gp.z)])
		if gp.x > CityLayout.PLAY_HALF - 60.0 and boat.vel.length() < 2.0:
			dead += 1
	L.fg.stick(Vector2.ZERO)
	TestLib.check(far < CityLayout.PLAY_HALF - 30.0 and dead == 0, "a boat at full GAS toward the world edge turns back before the wall (got to %.0f m from it, %d stopped ticks) [old fails]" % [CityLayout.PLAY_HALF - far, dead])
	TestLib.check(boat.global_position.x < far - 20.0, "the boat is heading home after the turn (x %.0f, furthest %.0f)" % [boat.global_position.x, far])


func _plane() -> void:
	var vm := Game.vehicles as VehicleManager
	L.fg.up_all()
	if L.p.vehicle != null:
		vm.exit_vehicle()
	await L.secs(0.3)
	var s := Vector3(CityLayout.PLAY_HALF - 600.0, 0.0, 2000.0)
	await L.place(Vector3(s.x, TerrainHeight.SEA_LEVEL - 0.5, s.z - 30.0), 0.0)
	var yaw := Lib.yaw_to(s, s + Vector3(100.0, 0.0, 0.0))
	DemoMenu.spawn_vehicle(&"plane")
	var v: Vehicle = null
	for c: Vehicle in vm.list:
		if is_instance_valid(c) and c.kind == &"plane" and (v == null or c.global_position.distance_to(L.p.global_position) < v.global_position.distance_to(L.p.global_position)):
			v = c
	TestLib.check(v != null, "setup: a plane")
	if v == null:
		return
	vm.enter(v)                                                   # setup only: put in the air below (every control after this is a finger, here: none, the throttle stays full)
	await L.f(10)
	v.craft.spool = 1.0
	v.craft.airborne = true
	v.craft.lever = 1.0
	v.global_position = Vector3(s.x, 300.0, s.z)
	v.heading = yaw
	v.speed = 55.0
	v.vel = v.forward() * 55.0
	var far := 0.0
	var low := 999.0
	var slow := 999.0
	for i in 200:
		await L.secs(0.1)
		far = maxf(far, maxf(absf(v.global_position.x), absf(v.global_position.z)))
		if i > 10:
			low = minf(low, v.global_position.y)
			slow = minf(slow, v.speed)
	var home := Vector3(-v.global_position.x, 0.0, -v.global_position.z).normalized()
	TestLib.check(slow > float(v.spec["stall"]) and low > 200.0 and v.craft.airborne, "a plane turned back at the world edge keeps flying: slowest %.1f m/s (stall %.0f), lowest %.0f m [old fails]" % [slow, float(v.spec["stall"]), low])
	TestLib.check(far < CityLayout.PLAY_HALF - 10.0 and v.forward().dot(home) > 0.3, "the plane turned for home before the wall (furthest %.0f of %.0f, facing home %.2f)" % [far, CityLayout.PLAY_HALF, v.forward().dot(home)])
