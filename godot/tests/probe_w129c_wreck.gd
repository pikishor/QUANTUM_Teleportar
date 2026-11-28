extends RefCounted
## w129-critic probe: a car blown up beside the hero; how long its husk stays.
var host: Node

func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame

func run(h: Node) -> void:
	host = h
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	var p := Game.player as Player
	var vm := Game.vehicles as VehicleManager
	for where: Vector3 in [Vector3(30.0, 0.0, 10.0), Airport.to_world(Vector3(1250.0, 0.0, -640.0)) + Vector3(-50.0, 0.0, 60.0)]:
		where.y = TerrainHeight.height_at(where.x, where.z)
		p.teleport_to(where + Vector3(-12.0, 0.5, 0.0))
		await _f(30)
		vm._release_farthest(where)
		var w := vm.spawn_parked(&"sedan", where, 0.0)
		await _f(5)
		w.explode()
		for i in 12:
			await _f(5)
			print("t%d wrecks %d w.wreck %s active %s inlist %s player %s dist %.1f" % [i * 5, vm.wreck_count(), w.wreck, w.active, w in vm.list, p.global_position, p.global_position.distance_to(w.global_position)])
	main.queue_free()
	await _f(2)
