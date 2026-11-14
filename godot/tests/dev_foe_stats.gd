extends RefCounted
## scratch (wave 113): statistics of the REFERENCED vertices of the near / mid / far meshes of a look
func run(host: Node) -> void:
	for look in [&"merc_medic", &"auth_drone"]:
		var h := FoeHuman.build(look, 1)
		FoeHuman.ensure_lods()
		for which in ["near", "mid", "far"]:
			var m := FoeHuman.mesh_of(h, which) as ArrayMesh
			var arr := m.surface_get_arrays(0)
			var v := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var n := arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
			var c := arr[Mesh.ARRAY_COLOR] as PackedColorArray
			var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			var seen := {}
			for i in idx:
				seen[i] = true
			var hist := {}
			var zero_n := 0
			for i in seen:
				var kk := int(round(c[i].b * 16.0))
				var md := int(round(c[i].r * 4.0))
				var key := "m%d_k%d" % [md, kk]
				hist[key] = int(hist.get(key, 0)) + 1
				if n[i].length() < 0.5:
					zero_n += 1
			print("STATS ", look, " ", which, " verts ", v.size(), " idx ", idx.size(), " referenced ", seen.size(), " zero_normals ", zero_n, " ", hist)
			var uvs := arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array
			var uv2 := arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
			var ao_sum := 0.0
			for i in seen:
				ao_sum += uvs[i].x
			print("      uv.x mean over referenced ", snappedf(ao_sum / maxf(float(seen.size()), 1.0), 0.001), " uv2 size ", uv2.size() if uv2 != null else -1)
