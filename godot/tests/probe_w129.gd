extends RefCounted
## w129-machanim probe: the tail wheel and the nose of the old GLB jet and cargo plane (vertex clusters near the ground).
const TIMEOUT_SECONDS := 60

func run(_h: Node) -> void:
	for e in [["xv_jet", 3.0, 1.3], ["xv_cargo", 10.0, 5.5]]:
		var r := (load("res://assets/models/%s.glb" % e[0]) as PackedScene).instantiate()
		var mi := r.get_node("Body") as MeshInstance3D
		var lo := Vector3(99, 99, 99)
		var hi := -lo
		var n := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			print(e[0], " surf ", s, " verts ", vv.size(), " idx ", idx.size(), " mat ", mi.mesh.surface_get_material(s).resource_name if mi.mesh.surface_get_material(s) else "", " alb ", (mi.mesh.surface_get_material(s) as BaseMaterial3D).albedo_color if mi.mesh.surface_get_material(s) is BaseMaterial3D else "")
			for v in vv:
				if v.z > float(e[1]) and v.y < float(e[2]) and absf(v.x) < 2.0:
					lo = lo.min(v); hi = hi.max(v); n += 1
		print(e[0], " tail cluster n ", n, " ", lo, " .. ", hi)
		# nose: lowest point of the first 12 % of the length
		var a := mi.get_aabb()
		var best := Vector3(0, 99, 0)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				if v.z < a.position.z + a.size.z * 0.16 and absf(v.x) < 0.5 and v.y < best.y:
					best = v
		print(e[0], " nose belly ", best)
		r.free()
	TestLib.check(true, "probe")
