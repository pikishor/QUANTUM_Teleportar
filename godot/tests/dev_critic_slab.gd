extends RefCounted
## Dev probe (wave 115 LOOK critic, not a test): what is the big flat dark-teal slab at hero height at the bomb bot's lane (210.6, 0, 2.57)? Lists every mesh whose box contains a point near the hero.
const TIMEOUT_SECONDS := 200.0
var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	Game.state = &"play"
	var at := Vector3(210.6, 0.0, 2.57)
	p.teleport_to(at)
	await frames(90)
	print("SLAB hero at ", p.global_position, " floor ", p.is_on_floor())
	var space := p.get_world_3d().direct_space_state
	for dz in [-6.0, -2.0, 2.0, 6.0]:
		for dx in [-12.0, -6.0, 0.0, 6.0]:
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(dx, 6.0, dz), at + Vector3(dx, -4.0, dz), 0xFFFFFFFF)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				print("SLAB ray (%.0f, %.0f) no hit" % [dx, dz])
			else:
				var col := hit["collider"] as Node
				print("SLAB ray (%.0f, %.0f) y %.2f layer %d %s %s" % [dx, dz, (hit["position"] as Vector3).y, (col as CollisionObject3D).collision_layer if col is CollisionObject3D else -1, col.get_class(), col.get_path()])
	print("SLAB water surface at the lane: ", WaterLayout.surface_at(at.x, at.z), " ahead: ", WaterLayout.surface_at(at.x - 8.0, at.z), " body ", WaterLayout.body_at(at.x - 8.0, at.z), " ground ", TerrainHeight.height_at(at.x - 8.0, at.z), " inland dist ", WaterLayout.inland_distance(at.x, at.z))
	var flat := 0
	for n2 in host.get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := n2 as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var bx := mi.global_transform * mi.get_aabb()
		if bx.size.y < 3.5 and maxf(bx.size.x, bx.size.z) > 12.0 and bx.position.y < 2.5 and bx.end.y > -0.6 and bx.grow(2.0).intersects(AABB(at + Vector3(-12.0, -1.0, -8.0), Vector3(14.0, 4.0, 16.0))):
			flat += 1
			print("SLAB flat mesh ", mi.get_path(), " box ", bx.position, " size ", bx.size, " surfaces ", mi.mesh.get_surface_count(), " mat ", mi.get_active_material(0))
	print("SLAB flat meshes ", flat)
	var probe := at + Vector3(-4.0, 0.7, 0.0)
	var found := 0
	for n in host.get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var box := vi.global_transform * vi.get_aabb()
		if box.has_point(probe) or box.grow(0.3).has_point(probe):
			found += 1
			print("SLAB visual ", vi.get_class(), " ", vi.get_path(), " box ", box.position, " size ", box.size, " layers ", vi.layers)
			if found > 20:
				break
	print("SLAB visuals found ", found)
	main.queue_free()
	await frames(3)
