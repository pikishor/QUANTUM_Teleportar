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
	var props = city._props
	print("VENTS ", props.vents.slice(0, 5))
	for n in city.multimesh_nodes:
		if n.name in ["Holograms", "Billboards"]:
			var mm := n.multimesh
			print(n.name, " first instance origin x,z,y: ", mm.buffer[3], " ", mm.buffer[11], " ", mm.buffer[7])
	var tall := []
	for b in city.building_data:
		if b.lot.h >= 88.0:
			tall.append([b.lot.cx, b.lot.cz, b.cls])
	print("LANDMARKS ", tall)
	for n in city.multimesh_nodes:
		if n.name == "FireEscapes":
			var b := n.multimesh.buffer
			var st := 12 + 4
			for k in mini(4, n.multimesh.instance_count):
				print("FIRE ", b[k * st + 3], " ", b[k * st + 7], " ", b[k * st + 11], " yaw basis zx ", b[k * st + 8])
	var screens := []
	for b in city.building_data:
		if (b.flags & 8) != 0:
			screens.append([b.lot.cx, b.lot.cz, b.lot.h, b.lot.w])
	print("SCREENS ", screens.slice(0, 6))
