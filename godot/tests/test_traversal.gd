extends RefCounted
## Rooftop traversal tests (headless): vault a low obstacle, mantle a 2 m ledge, ledge grab after a gap jump, too-high ledge refused, ladder to a roof,
## QUANTUM TELEPORT onto a real city rooftop, ladder zones in the city. Waits on counters and position, never on a fixed frame count.
## Run: tools/test.sh tests/test_traversal.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player


func run(host: Node) -> void:
	await e.setup(host)
	p = e.p
	await _vault()
	await _mantle()
	await _too_high()
	await _gap()
	await _ladder()
	await e.teardown()
	await _city(host)


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await e.frames(1)
		n -= 1
	return cond.call()


func _hold_forward_jump() -> void:
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")


func _vault() -> void:
	var box := Fixture.add_box(e.root, Vector3(20.0, 0.5, 0.0), Vector3(1.0, 1.0, 6.0))
	await e.prep(Vector3(18.7, 0.0, 0.0), -PI * 0.5, 0.0)
	var c0 := p.traversal.count
	_hold_forward_jump()
	var ok := await _until(func() -> bool: return p.traversal.count > c0, 1.5)
	TestLib.check(ok and p.traversal.last_kind == Traversal.Kind.VAULT, "forward + jump at a 1 m obstacle vaults it")
	var over := await _until(func() -> bool: return p.global_position.x > 21.0 and not p.traversal.active(), 3.0)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	TestLib.check(over, "the vault ends on the far side (x %.2f)" % p.global_position.x)
	await e.secs(0.5)
	TestLib.check(p.global_position.y < 0.2 and p.is_on_floor(), "and the player stands on the street again (y %.2f)" % p.global_position.y)
	box.queue_free()


func _mantle() -> void:
	var ledge := Fixture.add_box(e.root, Vector3(20.0, 1.0, 0.0), Vector3(4.0, 2.0, 6.0))
	await e.prep(Vector3(16.5, 0.0, 0.0), -PI * 0.5, 0.0)
	var c0 := p.traversal.count
	_hold_forward_jump()
	var ok := await _until(func() -> bool: return p.traversal.count > c0, 1.5)
	TestLib.check(ok and p.traversal.last_kind == Traversal.Kind.MANTLE, "a 2 m ledge is mantled")
	var up := await _until(func() -> bool: return p.global_position.y > 1.9 and not p.traversal.active(), 3.0)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	await e.secs(0.4)
	TestLib.check(up and p.global_position.y > 1.9 and p.global_position.x > 17.9, "the player stands on top (%s)" % str(p.global_position))
	ledge.queue_free()


func _too_high() -> void:
	var mode := Difficulty.current
	Difficulty.set_mode(2)                    # HARD has no wall-run (HeroVerbs): the wall-run would climb this wall on purpose
	var wall := Fixture.add_box(e.root, Vector3(20.0, 2.5, 0.0), Vector3(4.0, 5.0, 6.0))
	await e.prep(Vector3(16.5, 0.0, 0.0), -PI * 0.5, 0.0)
	var c0 := p.traversal.count
	_hold_forward_jump()
	await e.secs(1.0)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	Difficulty.set_mode(mode)
	TestLib.check(p.traversal.count == c0 and p.global_position.y < 1.5, "a 5 m wall is not climbed (jump reach + 2.5 m ledge grab is below it) (y %.2f)" % p.global_position.y)
	wall.queue_free()


func _gap() -> void:
	var a := Fixture.add_box(e.root, Vector3(0.0, 4.0, 60.0), Vector3(10.0, 8.0, 10.0))      # roof at y = 8, z 55..65
	var b := Fixture.add_box(e.root, Vector3(0.0, 4.0, 72.0), Vector3(10.0, 8.0, 10.0))      # z 67..77: a 2 m gap
	await e.prep(Vector3(0.0, 8.0, 59.0), PI, 0.0)
	p.yaw = PI
	var c0 := p.traversal.count
	Input.action_press(&"move_forward")
	# the camera yaw PI looks along +z
	Input.action_press(&"sprint")
	await e.secs(0.5)
	Input.action_press(&"jump")
	await e.frames(2)
	Input.action_release(&"jump")
	var ok := await _until(func() -> bool: return p.global_position.z > 67.5 and p.global_position.y > 7.5 and p.is_on_floor(), 3.0)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	TestLib.check(ok, "a rooftop gap is jumped (or grabbed) and the far roof reached (%s)" % str(p.global_position))
	a.queue_free()
	b.queue_free()


func _ladder() -> void:
	var tower := Fixture.add_box(e.root, Vector3(0.0, 6.0, -40.0), Vector3(10.0, 12.0, 10.0))     # wall face z = -35, roof 12
	Traversal.clear_zones()
	Traversal.add_zone(Vector3(0.0, 0.0, -35.0), Vector3(0.0, 0.0, 1.0), 12.0)
	await e.prep(Vector3(0.0, 0.0, -34.2), 0.0, 0.0)               # yaw 0 looks along -z
	var c0 := p.traversal.count
	Input.action_press(&"move_forward")
	var on := await _until(func() -> bool: return p.traversal.count > c0, 2.0)
	TestLib.check(on and p.traversal.kind == Traversal.Kind.CLIMB, "walking into a ladder starts a climb")
	var top := await _until(func() -> bool: return p.global_position.y > 11.9 and not p.traversal.active(), 8.0)
	Input.action_release(&"move_forward")
	await e.secs(0.4)
	TestLib.check(top and p.global_position.z < -35.2 and absf(p.global_position.y - 12.0) < 0.3, "the ladder ends on the roof (%s)" % str(p.global_position))
	Traversal.clear_zones()
	tower.queue_free()


func _city(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	TestLib.check(Traversal.zones.size() >= 5, "the city has rooftop ladders (%d)" % Traversal.zones.size())
	var lot: CityLayout.Lot = null
	for l in city.layout.lots:
		if l.h >= 12.0 and l.h <= 40.0:
			lot = l
			break
	TestLib.check(lot != null, "a mid-rise lot exists")
	if lot != null:
		var pt := PlayerUtil.safe_spot(Vector3(lot.cx, lot.h, lot.cz), city, null)
		TestLib.check(absf(pt.x - lot.cx) < 1.0 and absf(pt.z - lot.cz) < 1.0 and pt.y > lot.h * 0.5, "QUANTUM TELEPORT target on a roof is kept up there (%s, roof %.1f)" % [str(pt), lot.h])
	city.queue_free()
	await TestLib.frames(host, 2)
