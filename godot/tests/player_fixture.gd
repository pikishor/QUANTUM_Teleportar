extends RefCounted
## Shared fixtures of the player tests and the player bot: arena geometry on the world layer, dummy enemies and vehicles, input cleanup.
## Use through preload: const Fixture := preload("res://tests/player_fixture.gd")

const Dummy := preload("res://tests/player_dummy_enemy.gd")
const DummyVehicle := preload("res://tests/player_dummy_vehicle.gd")

const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"fire", &"aim",
		&"reload", &"blink", &"entangle", &"superpose", &"collapse", &"interact", &"pause"]


## A flat floor whose top surface is at y, `half` metres each way.
static func add_floor(parent: Node, half := 80.0, y := 0.0, material: Material = null) -> StaticBody3D:
	var b := add_box(parent, Vector3(0.0, y - 0.5, 0.0), Vector3(half * 2.0, 1.0, half * 2.0), material)
	b.name = "Floor"
	return b


## A static box on the world layer (collider and, with a material or visual=true, a mesh).
static func add_box(parent: Node, center: Vector3, size: Vector3, material: Material = null, visual := false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	if material != null or visual:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		if material != null:
			mi.material_override = material
		b.add_child(mi)
	parent.add_child(b)
	b.global_position = center
	return b


static func add_dummy(parent: Node, pos: Vector3, radius := 0.9, with_collider := true, visual := false) -> Node3D:
	var d := Dummy.new()
	d.setup(radius, with_collider, visual)
	parent.add_child(d)
	d.global_position = pos
	return d


static func add_vehicle(parent: Node, pos: Vector3, size := Vector3(1.9, 1.3, 4.5), with_collider := false, visual := false) -> Node3D:
	var v := DummyVehicle.new()
	v.setup(size, with_collider, visual)
	parent.add_child(v)
	v.global_position = pos
	return v


static func release_inputs() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)
