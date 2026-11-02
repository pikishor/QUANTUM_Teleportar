extends RefCounted
## Vehicle weapons (E2) and chases (E4): mounted weapons on sport / suv / hover (ammo, overheating, hits), nitro, Vael pursuit tactics.
## Run: tools/test.sh tests/test_vehicle_weapons.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const DT := 1.0 / 60.0

var e := Env.new()
var mgr: VehicleManager


func run(host: Node) -> void:
	seed(3)
	await e.setup(host)
	Fixture.add_floor(e.root, 400.0)
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	e.root.add_child(mgr)
	Game.quality = 2
	await e.frames(3)
	for v in mgr.list.duplicate():
		if v != mgr.starter:
			mgr._release(v)
	_weapons()
	_overheat_and_ammo()
	await _hits()
	_nitro()
	_tactics()
	mgr.queue_free()
	await e.frames(3)
	await e.teardown()


func _car(kind: StringName, pos := Vector3(0, 0, 40)) -> Vehicle:
	for v in mgr.list.duplicate():                                  # stay under the tier cap: keep only the starter and this section's cars
		if v != mgr.starter and mgr.list.size() >= mgr.cap() - 1:
			mgr._release(v)
	var c := mgr.spawn_parked(kind, pos, 0.0)
	assert(c != null)
	return c


func _weapons() -> void:
	for k in [&"sport", &"suv", &"hover"]:
		var v := _car(k)
		TestLib.check(v.weapons != null and v.weapons.mounted() and v.weapons.ammo > 0, "%s has a mounted weapon" % k)
	TestLib.check(_car(&"sedan").weapons == null, "a sedan has none")


func _overheat_and_ammo() -> void:
	var v := _car(&"sport", Vector3(40, 0, 40))
	var fired := 0
	for i in 600:
		if v.weapons.tick(DT, true):
			fired += 1
		if v.weapons.locked:
			break
	TestLib.check(v.weapons.locked and v.weapons.heat >= 1.0, "holding fire overheats the gun")
	TestLib.check(not v.weapons.tick(DT, true), "a locked gun does not fire")
	for i in 600:
		v.weapons.tick(DT, false)
	TestLib.check(not v.weapons.locked and v.weapons.heat < 0.4, "it cools and unlocks")
	v.weapons.ammo = 1
	v.weapons.heat = 0.0
	v.weapons._cd = 0.0
	TestLib.check(v.weapons.tick(DT, true), "last round fires")
	v.weapons._cd = 0.0
	TestLib.check(not v.weapons.tick(DT, true) and v.weapons.ammo == 0, "no ammo, no shot")
	v.weapons.reload_full()
	TestLib.check(v.weapons.ammo == int(VehicleSpecs.WEAPONS[&"sport"]["ammo"]), "reload_full refills")


func _hits() -> void:
	var tgt := _car(&"sedan", Vector3(0, 0, -60))
	var shooter := _car(&"sport", Vector3(0, 0, -20))
	shooter.heading = 0.0
	shooter.rotation.y = 0.0
	await e.frames(2)
	var hp0 := tgt.hp
	for i in 30:
		shooter.weapons._cd = 0.0
		shooter.weapons.tick(DT, true)
	await e.frames(1)
	TestLib.check(shooter.weapons.hits > 0 and tgt.hp < hp0, "rounds hit and damage a car ahead (hits %d)" % shooter.weapons.hits)


func _nitro() -> void:
	var a := _car(&"sport", Vector3(-60, 0, 40))
	var b := _car(&"sport", Vector3(-80, 0, 40))
	for i in 300:
		a.step_drive(DT, 1.0, 0.0, false, true)
		b.step_drive(DT, 1.0, 0.0, false, false)
	TestLib.check(a.speed > b.speed and b.speed <= 50.5, "nitro is faster (%.1f vs %.1f)" % [a.speed, b.speed])
	TestLib.check(a.nitro < 0.9, "it drains the tank")
	var low := a.nitro
	for i in 30:
		a.step_drive(DT, 1.0, 0.0, false, false)
	for i in 240:
		a.step_drive(DT, 1.0, 0.0, false, false)
	TestLib.check(a.nitro > low, "the tank refills")
	a.nitro = 0.0
	a.step_drive(DT, 1.0, 0.0, false, true)
	TestLib.check(not a.boosting, "an empty tank cannot boost")


func _tactics() -> void:
	var pl := e.p
	pl.global_position = Vector3(0, 0, 0)
	var car := _car(&"sport", Vector3(100, 0, 100))
	pl.vehicle = car
	car.vel = Vector3(0, 0, -20)
	var pat := _car(&"vael_patrol", Vector3(-20, 0, 30))
	pat.tactic = &"ram"
	var g := pat.chase_goal()
	TestLib.check(g.distance_to(pl.global_position) < 0.1, "ram aims at the target")
	pat.tactic = &"boxin"
	g = pat.chase_goal()
	TestLib.check(absf(g.x - pl.global_position.x) > 2.0 and absf(g.x - pl.global_position.x) < 6.0, "box-in aims beside him")
	pat.tactic = &"block"
	g = pat.chase_goal()
	TestLib.check(g.z < pl.global_position.z - 15.0, "roadblock aims ahead of his motion")
	pl.vehicle = null
	var m := VehicleSpecs.TACTICS
	TestLib.check(m.size() == 3, "three tactics")
