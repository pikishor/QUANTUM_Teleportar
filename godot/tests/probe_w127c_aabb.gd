extends RefCounted
func run(h: Node) -> void:
	for k in [&"tank", &"ltank", &"t_heavy", &"t_apc8", &"t_walker", &"t_hover", &"t_jeep", &"t_mine"]:
		var sp: Dictionary = VehicleSpecs.SPECS[k]
		var m := VehicleCraftModels.build(String(sp.get("procedural", "")), sp) if sp.has("procedural") else null
		if m == null:
			print("%s: not procedural (%s)" % [k, sp.get("model")])
			continue
		var surf := 0
		var s := ""
		for n in m.find_children("*", "GeometryInstance3D", true, false):
			var c := 0
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				c = (n as MeshInstance3D).mesh.get_surface_count()
			elif n is MultiMeshInstance3D:
				c = (n as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
			surf += c
			s += " %s:%d%s" % [n.name, c, "(shadow off)" if (n as GeometryInstance3D).cast_shadow == 0 else ""]
		print("%s: %d draw surfaces:%s" % [k, surf, s])
		m.free()
