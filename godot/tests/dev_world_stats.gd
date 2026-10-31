extends RefCounted
## Dev helper (not a test): prints instances and triangles per world MultiMesh family, with the camera windows applied at a few
## camera positions and quality tiers. tools/test.sh tests/dev_world_stats.gd


func run(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 2)
	var Stream := preload("res://scripts/world/city_stream.gd")
	var poses := {"spawn": Vector2(-30.0, 4.0), "centre": Vector2(0.0, 0.0), "corner": Vector2(300.0, 300.0), "far": Vector2(2000.0, 0.0)}
	for level in [1, 0, 2]:
		city.set_quality(level)
		for key in poses:
			city.update_streaming(poses[key], true)
			print("=== quality %d, camera %s %s" % [level, key, poses[key]])
			var total := 0
			var total_mirror := 0
			var mirrored := {}
			for m in city.mirror_nodes:
				if m.is_visible_in_tree():
					mirrored[m.multimesh] = true
			for n in city.multimesh_nodes:
				if not n.is_visible_in_tree():
					continue
				var mm := n.multimesh
				var tris := Stream.mesh_triangles(mm.mesh)
				var drawn := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
				total += tris * drawn
				if mirrored.has(mm):
					total_mirror += tris * drawn
				if level == 1 and key == "spawn":
					print("%-20s drawn=%5d of %5d  tris/inst=%4d  drawn tris=%7d  mirrored=%s" % [n.name, drawn, mm.instance_count, tris, tris * drawn, str(mirrored.has(mm))])
			print("TOTAL drawn real=%d mirror=%d (all tiers on) | stats=%s" % [total, total_mirror, str(city.stats())])
	var cm: ArrayMesh = city._misc.cable_mesh
	if cm != null:
		print("cables: %d triangles, one draw call" % (Stream.mesh_triangles(cm)))
