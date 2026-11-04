extends RefCounted
## Hero verbs (wave 54b) in the real player scene: wall-run + wall kick, glide, ground slam shockwave, WARP GRAB of an enemy / car / prop and the throw, HARD limits,
## the GRAB touch button and the input action. Waits on counters and state, never on fixed frame counts.
## Run: tools/test.sh tests/test_hero_verbs.gd

const Env := preload("res://tests/player_env.gd")
const DummyEnemy := preload("res://tests/player_dummy_enemy.gd")
const DummyVehicle := preload("res://tests/player_dummy_vehicle.gd")

var e := Env.new()
var p: Player
var _mode := 0


func run(host: Node) -> void:
	_mode = Difficulty.current
	await e.setup(host)
	p = e.p
	Difficulty.set_mode(0)
	await _wall()
	await _glide()
	await _slam()
	await _grab_enemy()
	await _grab_car()
	await _grab_prop()
	_hard()
	_wiring()
	Difficulty.set_mode(_mode)
	await e.teardown()


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await e.frames(1)
		n -= 1
	return cond.call()


func _enemy(pos: Vector3) -> Node3D:
	var d := DummyEnemy.new()
	d.setup(0.9, true, false)
	e.root.add_child(d)
	d.global_position = pos
	return d


func _wall() -> void:
	TestLib.check(HeroPower.can_wall_run(), "STORY allows wall-run")
	await e.prep(Vector3(-8.9, 3.0, 4.0), PI * 0.5, 0.0, 0)
	var r0 := p.verbs.wall_runs
	Input.action_press(&"move_forward")
	var ok := await _until(func() -> bool: return p.verbs.wall_runs > r0, 1.5)
	TestLib.check(ok, "holding toward a wall in the air starts a wall-run")
	var y0 := p.global_position.y
	await _until(func() -> bool: return p.global_position.y > y0 + 0.4 or not p.verbs.wall_running, 1.0)
	TestLib.check(p.global_position.y > y0 + 0.4, "the wall-run climbs instead of falling (dy %.2f)" % (p.global_position.y - y0))
	var k0 := p.verbs.wall_jumps
	Input.action_press(&"jump")
	var kicked := await _until(func() -> bool: return p.verbs.wall_jumps > k0, 1.0)
	Input.action_release(&"jump")
	TestLib.check(kicked and p.velocity.x > 0.0, "jump kicks off the wall, away from it")
	Input.action_release(&"move_forward")
	await _until(func() -> bool: return p.is_on_floor(), 4.0)


func _glide() -> void:
	await e.prep(Vector3(0.0, 40.0, 0.0), -PI * 0.5, 0.0, 0)
	Input.action_press(&"jump")
	var ok := await _until(func() -> bool: return p.gliding and p.velocity.y < 0.0, 2.0)
	TestLib.check(ok, "holding jump while falling glides")
	await e.secs(0.5)
	TestLib.check(p.gliding and p.velocity.y > -HeroPower.f("glide") - 1.0, "the glide caps the fall speed (vy %.1f)" % p.velocity.y)
	Input.action_release(&"jump")
	await _until(func() -> bool: return p.is_on_floor(), 8.0)


func _slam() -> void:
	var near := _enemy(Vector3(2.5, 0.0, 0.0))
	var far := _enemy(Vector3(30.0, 0.0, 0.0))
	await e.prep(Vector3(0.0, 8.0, 0.0), -PI * 0.5, 0.0, 0)
	await _until(func() -> bool: return p.air_time > 0.3, 1.0)
	var s0 := p.verbs.slams
	Input.action_press(&"crouch")
	var ok := await _until(func() -> bool: return p.verbs.slams > s0, 1.0)
	TestLib.check(ok, "tap crouch in the air starts a slam")
	var landed := await _until(func() -> bool: return not p.verbs.slamming and p.verbs.slams > s0 and p.is_on_floor(), 3.0)
	Input.action_release(&"crouch")
	TestLib.check(landed, "the slam ends on the ground")
	TestLib.check(near.hits.size() > 0 and near.hp < near.max_hp, "the shockwave damages a nearby enemy")
	TestLib.check(far.hits.is_empty(), "and spares one outside the radius")
	near.queue_free()
	far.queue_free()
	await e.frames(2)


func _grab_enemy() -> void:
	var d := _enemy(Vector3(5.0, 0.0, 0.0))
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 6)
	var g0 := p.verbs.grabs
	Input.action_press(&"grab")
	var ok := await _until(func() -> bool: return p.verbs.grabs > g0, 1.0)
	TestLib.check(ok and p.verbs.held_kind == &"enemy", "holding GRAB lifts the enemy in front")
	await _until(func() -> bool: return d.global_position.y > 1.2, 1.5)
	TestLib.check(d.global_position.y > 1.2 and d.global_position.distance_to(p.global_position) < 4.0, "it is held above and ahead (y %.2f)" % d.global_position.y)
	var t0 := p.verbs.throws
	var i0 := p.verbs.impacts
	Input.action_release(&"grab")
	var thrown := await _until(func() -> bool: return p.verbs.throws > t0 and p.verbs.impacts > i0, 4.0)
	TestLib.check(thrown, "releasing throws it and it lands with an impact")
	TestLib.check(d.hp < d.max_hp or d.dead, "the thrown enemy is hurt")
	TestLib.check(not p.verbs.holding and d.global_position.y < 1.0, "and is back on the ground (y %.2f)" % d.global_position.y)
	d.queue_free()
	await e.frames(2)


func _grab_car() -> void:
	var v := DummyVehicle.new()
	v.setup(Vector3(2.0, 1.4, 4.0), true, false)
	e.root.add_child(v)
	v.global_position = Vector3(7.0, 0.0, 0.0)
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 6)
	var g0 := p.verbs.grabs
	Input.action_press(&"grab")
	var ok := await _until(func() -> bool: return p.verbs.grabs > g0, 1.0)
	TestLib.check(ok and p.verbs.held_kind == &"vehicle", "WARP GRAB lifts a car")
	await _until(func() -> bool: return v.global_position.y > 1.0, 1.5)
	TestLib.check(v.global_position.y > 1.0, "the car is lifted (y %.2f)" % v.global_position.y)
	var i0 := p.verbs.impacts
	Input.action_release(&"grab")
	var thrown := await _until(func() -> bool: return p.verbs.impacts > i0, 4.0)
	TestLib.check(thrown, "the car is thrown and lands")
	TestLib.check(v.collision_layer == Game.L_VEHICLE, "and is solid again")
	v.queue_free()
	await e.frames(2)


func _grab_prop() -> void:
	var bk := Breakables.new()
	e.root.add_child(bk)
	await e.frames(2)
	var idx := -1
	for i in bk.positions.size():
		var sz: Vector3 = Breakables.KINDS[bk.kind_of[i]]["size"]
		if sz.y < 2.0 and sz.x < 2.0:
			idx = i
			break
	TestLib.check(idx >= 0, "a liftable prop exists")
	if idx < 0:
		return
	bk.positions[idx] = Vector3(4.0, 0.5, 0.0)
	await e.prep(Vector3(0.0, 0.0, 0.0), -PI * 0.5, 0.0, 6)
	var g0 := p.verbs.grabs
	var b0 := bk.broken_count
	Input.action_press(&"grab")
	var ok := await _until(func() -> bool: return p.verbs.grabs > g0, 1.0)
	TestLib.check(ok and p.verbs.held_kind == &"prop", "WARP GRAB lifts a prop")
	TestLib.check(bk.broken_count == b0 + 1 and bk.broken[idx] == 1, "the prop leaves its place")
	var i0 := p.verbs.impacts
	await e.secs(0.3)
	Input.action_release(&"grab")
	var thrown := await _until(func() -> bool: return p.verbs.impacts > i0, 4.0)
	TestLib.check(thrown, "the prop is thrown and hits")
	Input.action_release(&"grab")
	bk.queue_free()
	await e.frames(2)


func _hard() -> void:
	Difficulty.set_mode(2)
	TestLib.check(not HeroPower.can_wall_run(), "HARD has no wall-run")
	TestLib.check(not HeroVerbs.cars_ok(), "HARD cannot grab cars")
	TestLib.check(HeroVerbs.cfg("slam") < 90.0 and HeroVerbs.cfg("grab_range") < 14.0, "HARD verbs are weaker")
	Difficulty.set_mode(0)


func _wiring() -> void:
	TestLib.check(InputMap.has_action(&"grab"), "the grab action exists")
	var found := false
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"grab":
			found = true
			TestLib.check(float(b["r"]) * 2.0 >= 64.0, "the GRAB touch button is at least 64 px")
	TestLib.check(found, "the touch layer has a GRAB button")
	TestLib.check(p.verbs != null, "the Player owns the verbs")
