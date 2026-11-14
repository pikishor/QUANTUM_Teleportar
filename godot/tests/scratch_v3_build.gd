extends RefCounted
func run(_host: Node) -> void:
	var lens := {}
	var bad := []
	var tris := 0
	for id: StringName in WeaponDefsV3.ids():
		var m := WeaponModels.mesh(id)
		if m == null or m.get_surface_count() != 1:
			bad.append(String(id) + " no mesh")
			continue
		var bb := m.get_aabb()
		if not (bb.size.z > 0.15 and bb.size.z < 1.5 and bb.end.z > 0.1 and bb.position.z > -0.4):
			bad.append("%s len %.2f start %.2f" % [id, bb.size.z, bb.position.z])
		lens["%d_%d_%d" % [roundi(bb.size.x * 40.0), roundi(bb.size.y * 40.0), roundi(bb.size.z * 40.0)]] = true
		tris += m.get_faces().size() / 3
	print("BAD ", bad)
	print("SILHOUETTES ", lens.size(), " of ", WeaponDefsV3.ids().size(), " tris total ", tris)
	TestLib.check(bad.is_empty(), "every mesh sane")
