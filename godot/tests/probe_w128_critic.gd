extends RefCounted
## w128-critic probe: a parked aircraft built in a pooled Vehicle that held another kind before (prints its body meshes).
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")

func _dump(v: Vehicle) -> String:
	var s := []
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).begins_with("Body") or String(m.name) == "Detail":
			var mats := []
			for i in (m.mesh.get_surface_count() if m.mesh else 0):
				var mm := m.get_active_material(i)
				mats.append("%s/%s/%s" % [mm.resource_name if mm else "null", (mm as BaseMaterial3D).transparency if mm is BaseMaterial3D else -1, (mm as BaseMaterial3D).albedo_color if mm is BaseMaterial3D else (mm.get_class() if mm else "")])
			s.append(str(mats))
			s.append("aabb %s lay %d cast %d " % [m.get_aabb(), m.layers, m.cast_shadow])
			s.append("%s vis=%s tree=%s mesh=%s surf=%d range=%.0f-%.0f" % [m.name, m.visible, m.is_visible_in_tree(), m.mesh != null, m.mesh.get_surface_count() if m.mesh else 0, m.visibility_range_begin, m.visibility_range_end])
	return " | ".join(s)

func run(h: Node) -> void:
	var A := Audit.new()
	await A.boot(h, "w128cp")
	var vm := Game.vehicles as VehicleManager
	var at := Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	(Game.player as Player).teleport_to(at + Vector3(-60, 0.5, 0))
	await A.pframes(30)
	for k in [&"p_awacs", &"p_tanker", &"p_awacs"]:
		vm._release_farthest(at)
		var v := vm.spawn_parked(k, at, 0.0)
		await A.pframes(10)
		print("PROBE ", k, " ", v.get_instance_id(), " ", _dump(v))
		vm._release(v)
		await A.pframes(2)
	TestLib.check(true, "probe")
	await A.shutdown()
