extends RefCounted
## Open-source models (round 4): 14 CC0 vehicles (Kenney Car Kit 3.1, converted by tools/open_models/convert_vehicles.py to assets/models/ov_*.glb) wired into VehicleSpecs / VehicleVisual,
## and 12 CC0 guns (Quaternius Ultimate Gun Pack, OpenGameArt RPG-7; tools/open_models/convert_weapons.py -> ow_*.glb) wired into WeaponModels, both with the old procedural models as fallback.
## Checks: the node / surface contract of a vehicle (Body, Body_LOD1, wheels as separate nodes at the axles, Body / Details / lamp surfaces, no textures), triangle caps (cars <= 4000
## at LOD0, <= 1200 at LOD1, weapons <= 3000), the size against the spec, VehicleVisual builds every kind from its open model (paint, wheels, LOD1), the weapon meshes (muzzle at the origin, barrel -Z,
## realistic length) and the fallbacks, and that licences and credits are kept with the packs.
## Run: tools/test.sh tests/test_open_models.gd   (after tools/import.sh)

const KINDS := {
	&"sedan": "ov_sedan", &"sport": "ov_sport", &"compact": "ov_hatch", &"suv": "ov_suv", &"luxury": "ov_luxury", &"taxi": "ov_taxi", &"interceptor": "ov_police",
	&"ambulance": "ov_ambulance", &"van": "ov_van", &"delivery": "ov_delivery", &"truck": "ov_truck", &"firetruck": "ov_firetruck", &"garbage": "ov_garbage", &"racer": "ov_race",
}
const CAR_TRIS := 4000
const LOD1_TRIS := 1200
const WEAPON_TRIS := 3000
const WEAPON_LEN := {&"pistol": 0.215, &"burst": 0.30, &"revolver": 0.27, &"akimbo": 0.215, &"flux": 0.50, &"carbine": 0.92, &"marksman": 1.0, &"arc": 0.80,
	&"scatter": 0.98, &"breacher": 0.78, &"rail": 1.12, &"rocket": 0.98}


func run(host: Node) -> void:
	OS.set_environment("QT_OPEN_MODELS", "1")
	OS.set_environment("QT_RV_MODELS", "0")              # this test is about the Kenney set; the Rgsdev models that now lead are covered by test_cars_world_scale
	var q: int = Game.quality
	Game.quality = 0                                     # LOW: the open model comes first for every kind (above LOW six kinds keep their older, smoother art, see _registry)
	_registry()
	for kind: StringName in KINDS:
		_model(host, kind, KINDS[kind])
	await _visuals(host)
	Game.quality = q
	_weapons()
	_fallbacks()
	_credits()
	OS.set_environment("QT_RV_MODELS", "1")


func _registry() -> void:
	TestLib.check(KINDS.size() >= 8 and KINDS.size() <= 14, "%d open vehicle kinds (8-14 asked)" % KINDS.size())
	for kind: StringName in KINDS:
		TestLib.check(VehicleSpecs.SPECS.has(kind) and VehicleSpecs.SPECS[kind].has("ov"), "%s has an open model key" % kind)
		var names := VehicleSpecs.model_names(kind)
		TestLib.check(not names.is_empty() and names[0] == KINDS[kind], "%s tries %s first (%s)" % [kind, KINDS[kind], ",".join(names)])
		TestLib.check(names.size() >= 2, "%s keeps an older model or the primitive as fallback" % kind)
	TestLib.check(VehicleSpecs.STREAM_KINDS.size() == VehicleSpecs.STREAM_WEIGHTS.size(), "one stream weight per kind")
	var sum := 0.0
	for w in VehicleSpecs.STREAM_WEIGHTS:
		sum += w
	TestLib.check(absf(sum - 1.0) < 0.001, "stream weights add up to 1 (%.3f)" % sum)
	for kind: StringName in [&"luxury", &"racer", &"delivery", &"garbage", &"firetruck"]:
		TestLib.check(kind in VehicleSpecs.STREAM_KINDS, "new kind %s is in the traffic mix" % kind)
		TestLib.check(VehicleSpecs.mass_of(kind) > 500.0 and VehicleSpecs.seats_of(kind) >= 1, "%s has mass and seats" % kind)
	Game.quality = 1
	for kind: StringName in KINDS:
		var first := VehicleSpecs.model_names(kind)[0]
		if VehicleSpecs.SPECS[kind].has("ov_low"):
			TestLib.check(first == String(VehicleSpecs.SPECS[kind]["model"]) and VehicleSpecs.model_names(kind).has(KINDS[kind]), "%s keeps its older art first above LOW, the open model stays as fallback" % kind)
		else:
			TestLib.check(first == KINDS[kind], "%s (no older art) uses its open model at every tier" % kind)
	Game.quality = 0
	OS.set_environment("QT_OPEN_MODELS", "0")
	TestLib.check(VehicleSpecs.model_names(&"sedan")[0] == "car_sedan", "QT_OPEN_MODELS=0 puts the older sedan back first")
	OS.set_environment("QT_OPEN_MODELS", "1")


func _tris(mi: MeshInstance3D, skip_lamps := false) -> int:
	var n := 0
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if skip_lamps and mat != null and String(mat.resource_name) in ["Headlights", "Taillights", "Underglow"]:
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _surface_names(mi: MeshInstance3D) -> Array[String]:
	var out: Array[String] = []
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		out.append(String(m.resource_name) if m != null else "")
	return out


func _model(host: Node, kind: StringName, model_name: String) -> void:
	TestLib.check(ResourceLoader.exists("res://assets/models/%s.glb" % model_name), "%s.glb exists" % model_name)
	TestLib.check(VehicleSpecs.available_model(kind) == model_name, "%s is the model VehicleSpecs picks for %s" % [model_name, kind])
	var m := Game.load_model(model_name)
	TestLib.check(m != null, "%s loads" % model_name)
	if m == null:
		return
	host.add_child(m)
	var body := m.get_node_or_null("Body") as MeshInstance3D
	var lod1 := m.get_node_or_null("Body_LOD1") as MeshInstance3D
	TestLib.check(body != null and lod1 != null, "%s has Body and Body_LOD1" % model_name)
	if body == null or lod1 == null:
		m.queue_free()
		return
	var total := _tris(body)
	var wheels: Array[MeshInstance3D] = []
	var spec: Dictionary = VehicleSpecs.SPECS[kind]
	var radius: float = float(spec["wheel"])
	for wn in [["WheelFL", -1, -1], ["WheelFR", 1, -1], ["WheelRL", -1, 1], ["WheelRR", 1, 1]]:
		var w := m.get_node_or_null(String(wn[0])) as MeshInstance3D
		TestLib.check(w != null, "%s has the separate wheel node %s" % [model_name, wn[0]])
		if w == null:
			continue
		wheels.append(w)
		total += _tris(w)
		TestLib.check(signf(w.position.x) == float(wn[1]) and signf(w.position.z) == float(wn[2]), "%s %s is on the right corner (x %.2f, z %.2f; front is -Z)" % [model_name, wn[0], w.position.x, w.position.z])
		var wb := w.get_aabb()
		TestLib.check(wb.get_center().length() < 0.06, "%s %s is pivoted at the axle" % [model_name, wn[0]])
		TestLib.check(absf(wb.size.y * 0.5 - radius) < 0.06 and absf(w.position.y - radius) < 0.06, "%s %s radius %.2f matches the spec %.2f and rests on the ground" % [model_name, wn[0], wb.size.y * 0.5, radius])
	TestLib.check(total <= CAR_TRIS, "%s LOD0 (body + wheels) %d triangles <= %d" % [model_name, total, CAR_TRIS])
	TestLib.check(_tris(lod1) <= LOD1_TRIS and _tris(lod1) < _tris(body), "%s LOD1 %d triangles (<= %d, below LOD0's %d)" % [model_name, _tris(lod1), LOD1_TRIS, _tris(body)])
	var names := _surface_names(body)
	for n in ["Body", "Details", "Headlights", "Taillights"]:
		TestLib.check(names.has(n), "%s has the %s surface" % [model_name, n])
	var n1 := _surface_names(lod1)
	var same := true
	for n: String in n1:
		same = same and names.has(n)
	TestLib.check(same, "%s LOD1 uses the materials of LOD0" % model_name)
	var tex := false
	for mi in [body, lod1] + wheels:
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var bm := (mi as MeshInstance3D).mesh.surface_get_material(s) as BaseMaterial3D
			tex = tex or (bm != null and (bm.albedo_texture != null or bm.normal_texture != null))
	TestLib.check(not tex, "%s carries no texture (vertex colours only: no texture memory)" % model_name)
	var arr := body.mesh.surface_get_arrays(1)
	var cols: Variant = arr[Mesh.ARRAY_COLOR]
	TestLib.check(cols != null and (cols as PackedColorArray).size() > 10, "%s Details surface has baked vertex colours" % model_name)
	var bm := body.mesh.surface_get_material(0) as BaseMaterial3D
	TestLib.check(bm != null and bm.cull_mode == BaseMaterial3D.CULL_BACK, "%s is single-sided (no double fill cost)" % model_name)
	var box := AABB()
	var first := true
	for mi in [body] + wheels:
		var b := (mi as MeshInstance3D).get_aabb()
		b.position += (mi as MeshInstance3D).position
		box = b if first else box.merge(b)
		first = false
	TestLib.check(absf(box.size.z - float(spec["len"])) <= 0.35 and absf(box.size.x - float(spec["wid"])) <= 0.35 and absf(box.size.y - float(spec["hgt"])) <= 0.35,
		"%s is %.2f x %.2f x %.2f m (spec %.2f x %.2f x %.2f)" % [model_name, box.size.z, box.size.x, box.size.y, float(spec["len"]), float(spec["wid"]), float(spec["hgt"])])
	TestLib.check(box.position.y > -0.05 and box.position.y < 0.1 and absf(box.get_center().x) < 0.08, "%s stands on the ground (min y %.3f) and is symmetric (x centre %.3f)" % [model_name, box.position.y, box.get_center().x])
	m.get_parent().remove_child(m)
	m.free()


func _visuals(host: Node) -> void:
	for kind: StringName in KINDS:
		var v := VehicleVisual.new()
		var root := v.build(kind, Color(0.2, 0.9, 1.0))
		host.add_child(root)
		TestLib.check(v.uses_model and v.model_name == KINDS[kind], "VehicleVisual builds %s from %s (got '%s')" % [kind, KINDS[kind], v.model_name])
		TestLib.check(v.wheels.size() == 4 and v.body != null and v.body_lod1 != null, "%s: four wheels, body and LOD1" % kind)
		v.set_paint(Color(0.9, 0.1, 0.1))
		var mat := v.body.get_surface_override_material(0) as BaseMaterial3D
		TestLib.check(mat != null and mat.albedo_color.r > mat.albedo_color.b, "%s: the paint recolours the Body surface" % kind)
		v.set_lights(1.0, 1.0, 0.0)
		host.remove_child(root)
		root.free()
	await host.get_tree().process_frame


func _weapons() -> void:
	WeaponModels._cache.clear()
	for id: StringName in WEAPON_LEN:
		TestLib.check(ResourceLoader.exists("res://assets/models/ow_%s.glb" % String(id)), "ow_%s.glb exists" % id)
		var m := WeaponModels.mesh(id)
		TestLib.check(m != null, "%s has a mesh" % id)
		if m == null:
			continue
		var arr := m.surface_get_arrays(0)
		var tris := (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var wide := id == &"akimbo"
		var box := m.get_aabb()
		TestLib.check(tris > 300 and tris <= WEAPON_TRIS * (2 if wide else 1), "%s open model has %d triangles (300..%d)" % [id, tris, WEAPON_TRIS * (2 if wide else 1)])
		TestLib.check(box.position.z > -0.03 and box.position.z < 0.03, "%s muzzle sits at the origin (front z %.3f, barrel points -Z)" % [id, box.position.z])
		TestLib.check(absf(box.end.z - float(WEAPON_LEN[id])) < 0.06, "%s is %.2f m long (target %.2f)" % [id, box.end.z, float(WEAPON_LEN[id])])
		TestLib.check(box.position.y > -0.5 and box.end.y < 0.25 and box.position.y < -0.04, "%s: bore axis at y 0, grip below (y %.2f .. %.2f)" % [id, box.position.y, box.end.y])
		TestLib.check(absf(box.get_center().x) < (0.1 if wide else 0.03), "%s is centred on the aim line (x %.3f)" % [id, box.get_center().x])
		var cols: Variant = arr[Mesh.ARRAY_COLOR]
		var lum := 0.0
		if cols != null:
			for c in (cols as PackedColorArray):
				lum += c.r + c.g + c.b
			lum /= maxf(1.0, float((cols as PackedColorArray).size()) * 3.0)
		TestLib.check(cols != null and lum > 0.008 and lum < 0.5, "%s has gunmetal vertex colours (mean %.3f)" % [id, lum])
	for id: StringName in [&"blade", &"whip", &"gravity", &"minigun", &"grenade", &"lance"]:
		TestLib.check(WeaponModels.mesh(id) != null, "%s keeps its procedural mesh" % id)


func _fallbacks() -> void:
	OS.set_environment("QT_OPEN_MODELS", "0")
	WeaponModels._cache.clear()
	var open_tris := 0
	var m := WeaponModels.mesh(&"carbine")
	TestLib.check(m != null and m.get_aabb().size.z > 0.5, "QT_OPEN_MODELS=0 gives the procedural carbine back")
	var pistol := WeaponModels.mesh(&"pistol")
	open_tris = (pistol.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	TestLib.check(open_tris < 300, "the procedural pistol is the small box model (%d triangles)" % open_tris)
	OS.set_environment("QT_OPEN_MODELS", "1")
	WeaponModels._cache.clear()
	TestLib.check((WeaponModels.mesh(&"pistol").surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 > 300, "the open pistol is back with the switch on")


func _credits() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	for d in ["art_sources/kenney_car_kit", "art_sources/open_weapons"]:
		var base := root.path_join(d)
		if not DirAccess.dir_exists_absolute(base):
			continue                                          # an export without the repository
		TestLib.check(FileAccess.file_exists(base.path_join("SOURCE.md")), "%s keeps its SOURCE.md (URL)" % d)
		TestLib.check(FileAccess.file_exists(base.path_join("License.txt")) or FileAccess.file_exists(base.path_join("LICENSE.txt")), "%s keeps the licence text" % d)
	var tp := root.path_join("docs/THIRD_PARTY.md")
	if FileAccess.file_exists(tp):
		var text := FileAccess.get_file_as_string(tp)
		TestLib.check(text.contains("Kenney Car Kit") and text.contains("Ultimate Gun Pack"), "docs/THIRD_PARTY.md credits the Kenney Car Kit and the Quaternius Ultimate Gun Pack")
