extends RefCounted
func run(h: Node) -> void:
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	h.add_child(main)
	for i in 20:
		await h.get_tree().process_frame
	Game.state = &"play"
	var vm := Game.vehicles as VehicleManager
	var p := Game.player as Player
	var at := p.global_position + Vector3(10, 0, 0)
	vm._fixed_n += 1
	var v := vm.spawn_parked(&"t_apc8", at, 0.0)
	v.set_meta(&"hold", true)
	for i in 30:
		await h.get_tree().physics_frame
	var m := v.visual.model
	print("model scale ", m.scale, " basis ", m.transform.basis)
	for n in m.get_children():
		print(n.name, " ", n.get_class(), " ", (n as Node3D).transform)
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			print("  count ", mm.instance_count, " aabb ", mm.get_aabb(), " mesh aabb ", mm.mesh.get_aabb())
			for i in mini(mm.instance_count, 8):
				print("   ", i, " ", mm.get_instance_transform(i))
			print("  pose ", TankModels.pose_of(m, String(n.name)).slice(0, 3))
	main.queue_free()
