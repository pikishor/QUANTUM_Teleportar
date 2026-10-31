extends RefCounted
## Stand-ins for the other modules in the enemies tests and the enemies bot: a world with only the road queries, a missions node that records drops,
## and a quantum node with a clone. Use through preload: const Stubs := preload("res://tests/enemies_stubs.gd")


## Game.world stand-in: roads along x = k * 80 (+- lane), no buildings.
class StubWorld extends Node3D:
	func random_road_point() -> Vector3:
		return Vector3(float(randi_range(-3, 3)) * 80.0 + 5.0, 0.0, randf_range(-280.0, 280.0))

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		return Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)


## Game.missions stand-in: remembers every drop.
class StubMissions extends Node:
	var drops: Array = []

	func drop(kind: StringName, pos: Vector3) -> void:
		drops.append([kind, pos])


## player.quantum stand-in: a clone node and a collapse counter.
class StubQuantum extends Node:
	var clone: Node3D
	var collapsed := 0

	func collapse() -> void:
		collapsed += 1
		if is_instance_valid(clone):
			clone.queue_free()
		clone = null
