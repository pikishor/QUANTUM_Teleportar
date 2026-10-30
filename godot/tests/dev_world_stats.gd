extends RefCounted
## Dev helper (not a test): prints instance and triangle counts per world MultiMesh. tools/test.sh tests/dev_world_stats.gd


func run(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 2)
	var total := 0
	var total_mirror := 0
	for n in city.multimesh_nodes:
		var mm := n.multimesh
		var tris := 0
		for s in mm.mesh.get_surface_count():
			var arr := mm.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var all := tris * mm.instance_count
		total += all
		print("%-18s inst=%5d tris/inst=%5d total=%8d" % [n.name, mm.instance_count, tris, all])
	for n in city.mirror_nodes:
		var mm := n.multimesh
		var tris := 0
		for s in mm.mesh.get_surface_count():
			var arr := mm.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
		total_mirror += tris * mm.instance_count
	print("TOTAL real=", total, " mirror=", total_mirror)
	print(city.stats())
