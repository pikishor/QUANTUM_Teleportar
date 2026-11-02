extends RefCounted
## Enemy tactics (D2): squad roles from the callout, suppressing fire from cover, flank when the player camps, retreat at low hp, a call for reinforcement, thinker cap.
## Run: tools/test.sh tests/test_enemy_tactics.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")
const K := 4
const DT := 1.0 / 60.0

class CoverWorld extends Node3D:
	var bodies: Array = []

	func prop_colliders() -> Object:
		return self

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		return Vector3(center.x + (rmin + rmax) * 0.5, 0.0, center.z)

var e := Env.new()
var p: Player
var root: Node3D
var em: EnemyManager
var world: CoverWorld
var stub_missions := Stubs.StubMissions.new()


func run(host: Node) -> void:
	seed(5)
	await e.setup(host)
	p = e.p
	root = e.root
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	world = CoverWorld.new()
	root.add_child(world)
	Game.world = world
	root.add_child(stub_missions)
	Game.missions = stub_missions
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(3)

	await _roles()
	await _suppress()
	await _camp_flank()
	await _retreat_and_call()
	await _thinker_cap()

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.world = null
	Game.missions = null
	Game.heat = 0.0
	await e.teardown()


func _fresh() -> void:
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	stub_missions.drops.clear()
	for b in world.bodies:
		b.queue_free()
	world.bodies.clear()
	await e.prep(Vector3(0.0, 0.05, 0.0))
	p.max_hp = 1.0e6
	p.hp = p.max_hp


func _secs(s: float) -> void:
	await e.frames(int(ceil(s / DT)))


func _spawn(type: StringName, at: Vector3, aware := true, frozen := false) -> Operative:
	var d := em.spawn(type, at, aware)
	d.set_physics_process(not frozen)
	await e.frames(2)
	return d as Operative


func _crate(at: Vector3) -> void:
	var b := Fixture.add_box(root, at + Vector3(0.0, 0.8, 0.0), Vector3(2.0, 1.6, 2.0))
	world.bodies.append(b)


func _roles() -> void:
	await _fresh()
	var a := await _spawn(&"operative", Vector3(30.0, 0.0, 0.0), false, true)
	var n: Array[Operative] = []
	for i in 4:
		n.append(await _spawn(&"operative", Vector3(32.0 + i, 0.0, 3.0 * i), false, true))
	em.squad_callout(a, p.global_position)
	TestLib.check(a.tactic_role == &"anchor", "the one who spotted the player is the anchor")
	TestLib.check(n[0].tactic_role == &"flanker" and n[1].tactic_role == &"flanker" and n[0].flank_side() != n[1].flank_side(), "the next two flank from opposite sides")
	TestLib.check(n[2].tactic_role == &"pusher", "the third neighbour is the pusher")
	var x0 := n[2].global_position.distance_to(p.global_position)
	n[2].set_physics_process(true)
	n[2].aware = true
	await _secs(1.5)
	TestLib.check(n[2].global_position.distance_to(p.global_position) < x0 - 2.0, "the pusher closes in")
	em.clear()


func _suppress() -> void:
	await _fresh()
	_crate(Vector3(10.0, 0.0, 0.0))
	await e.frames(2)
	var a := await _spawn(&"operative", Vector3(13.0, 0.0, 5.0), true)
	a.tactic_role = &"anchor"
	a._called = true
	await _secs(8.0)
	TestLib.check(a.suppress_bursts > 0, "a hidden anchor fires suppressing bursts (%d)" % a.suppress_bursts)
	em.clear()


func _camp_flank() -> void:
	await _fresh()
	_crate(Vector3(10.0, 0.0, 0.0))
	await e.frames(2)
	var a := await _spawn(&"operative", Vector3(13.0, 0.0, 5.0), true)
	a._called = true
	var flanked := false
	for i in int(10.0 / DT / 4.0):
		await e.frames(4)
		if a._assigned_t > 0.0:
			flanked = true
			break
	TestLib.check(flanked, "the player camping in one place gets flanked")
	em.clear()


func _retreat_and_call() -> void:
	await _fresh()
	_crate(Vector3(10.0, 0.0, 0.0))
	await e.frames(2)
	var a := await _spawn(&"operative", Vector3(18.0, 0.0, 6.0), true)
	a._called = true
	var before := em.reinforcement_calls
	a.hp = a.max_hp * 0.4
	await _secs(0.5)
	TestLib.check(em.reinforcement_calls == before + 1, "a wounded soldier calls for reinforcement")
	a.hp = a.max_hp * 0.2
	await _secs(0.3)
	TestLib.check(a.is_retreating(), "below a quarter hp he retreats")
	var hid := false
	for i in int(6.0 / DT / 4.0):
		await e.frames(4)
		if a.cover_state() == 2:
			hid = true
			break
	TestLib.check(hid, "and hides behind cover")
	a.hp = a.max_hp * 0.2
	var calls := em.reinforcement_calls
	await _secs(0.5)
	TestLib.check(em.reinforcement_calls == calls, "only one call per life")
	em.clear()


func _thinker_cap() -> void:
	Game.set_quality(0)
	var ok := 0
	for i in 10:
		if em.try_think():
			ok += 1
	TestLib.check(ok == EnemyManager.THINKERS[0], "thinkers per frame are capped (%d)" % ok)
	Game.set_quality(1)
