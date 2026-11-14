extends RefCounted

func run(host: Node) -> void:
	var out := []
	for id in WeaponDefs.all_ids():
		var d: Dictionary = WeaponDefs.def(id)
		var row := {"id": String(id)}
		for k in d.keys():
			var v = d[k]
			match typeof(v):
				TYPE_STRING_NAME, TYPE_STRING:
					row[String(k)] = String(v)
				TYPE_COLOR:
					row[String(k)] = (v as Color).to_html(false)
				TYPE_VECTOR3:
					row[String(k)] = [v.x, v.y, v.z]
				TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
					row[String(k)] = v
				TYPE_ARRAY:
					var arr := []
					for e in v:
						if typeof(e) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME]:
							arr.append(e if typeof(e) != TYPE_STRING_NAME else String(e))
					row[String(k)] = arr
				_:
					pass
		row["class"] = String(WeaponDefs.CLASS_OF.get(id, &""))
		row["family"] = String(WeaponDefs.FAMILY_OF.get(id, &""))
		row["spec_reach"] = float(WeaponModels.spec(id).get("reach", 0.0))
		var gr: Vector3 = WeaponModels.spec(id)["gr"]
		var gl: Vector3 = WeaponModels.spec(id)["gl"]
		row["spec_gr"] = [gr.x, gr.y, gr.z]
		row["spec_gl"] = [gl.x, gl.y, gl.z]
		row["anim_class"] = String(HeroAnimTuning.WEAPON_CLASS.get(id, &""))
		row["vfx_class"] = String(preload("res://scripts/fx/quantum_vfx.gd").WEAPON_CLASS.get(id, &""))
		var m := WeaponModels.mesh(id)
		if m != null:
			var bb := m.get_aabb()
			row["aabb_pos"] = [bb.position.x, bb.position.y, bb.position.z]
			row["aabb_size"] = [bb.size.x, bb.size.y, bb.size.z]
		out.append(row)
	var f := FileAccess.open(OS.get_environment("DUMP_OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("dumped ", out.size())
