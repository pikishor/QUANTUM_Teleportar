extends RefCounted
## Test environment of the player tests: a floor, a wall and a Player instance, plus the wait / reset helpers both test files use.
##   floor: top surface at y = 0, +-80 m
##   wall:  x in [-10.5, -9.5], z in [-6, 14], 6 m high
## Use through preload: const Env := preload("res://tests/player_env.gd")

const Fixture := preload("res://tests/player_fixture.gd")

const WALL_FACE_X := -10.5

var host: Node
var root: Node3D
var p: Player
var wall: StaticBody3D
var died_count := 0


func setup(h: Node) -> void:
	host = h
	root = Node3D.new()
	root.name = "PlayerTestRoot"
	host.add_child(root)
	Fixture.add_floor(root)
	wall = Fixture.add_box(root, Vector3(-10.0, 3.0, 4.0), Vector3(1.0, 6.0, 20.0))
	Game.state = &"play"
	var scene := load("res://scenes/player.tscn") as PackedScene
	TestLib.check(scene != null, "scenes/player.tscn loads")
	var inst := scene.instantiate()
	TestLib.check(inst is Player, "player.tscn root is a Player")
	p = inst as Player
	root.add_child(p)
	Game.player_died.connect(func() -> void: died_count += 1)
	await frames(10)


func teardown() -> void:
	Fixture.release_inputs()
	Game.state = &"menu"
	root.queue_free()
	# the headless audio driver would keep the last played stream alive at exit and print a leak warning
	for c in Sfx.get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
	await frames(2)


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func secs(s: float) -> void:
	await TestLib.frames(host, int(ceil(s * 60.0)))


## Fresh, controlled state: inputs released, no invulnerability, full stats, standing at pos looking along yaw.
## settle = physics frames to wait afterwards (0 = return at once, for tests that time the first moments).
func prep(pos: Vector3, yaw := -PI * 0.5, pitch := -0.12, settle := 6) -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	p.invuln = 0.0
	p.hp = p.max_hp
	p.energy = p.max_energy
	p.since_hurt = 99.0
	p.speed_boost = 1.0
	p.weapon.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	if settle > 0:
		await frames(settle)


func flat_speed() -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


## Aim the camera at a point on a dummy (height_frac of its radius above the centre), tap fire once and wait a moment.
func shoot_dummy(d: Node3D, height_frac: float, radius: float, wait := 0.15) -> void:
	var c := d.call(&"center") as Vector3
	p.camera_rig.aim_at(c + Vector3(0.0, radius * height_frac, 0.0))
	await frames(1)
	Input.action_press(&"fire")
	await frames(2)
	Input.action_release(&"fire")
	await secs(wait)
