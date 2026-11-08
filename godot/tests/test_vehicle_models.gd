extends RefCounted
## Vehicle art set (Wave 14): the seven new models (taxi, wagon, van, truck, street bike, hover car, Vael patrol hover-vehicle) made by tools/blender (carlib / model_*.py).
## Checks the contract every vehicle model has to keep: loads through Game.load_model, nodes (Body, Body_LOD1, wheels as separate nodes pivoted at the axle where the kind
## has wheels), triangle limits (LOD0 and LOD1, per surface budget), the same material set on both LODs, baked textures (a small atlas) with a glowing alien trim, emissive
## lamp surfaces, real lights without shadows, the model's size against its spec, the registry in VehicleSpecs (speed, hp, mass, seats, stream weights) and that VehicleVisual
## builds it, shares the paint and lamp materials between the LODs and switches LODs by distance.
## Run: tools/test.sh tests/test_vehicle_models.gd   (after tools/import.sh)

const LAMPS := ["Headlights", "Taillights", "Underglow"]
const BUDGET_LOD0 := 12500          ## Body (with the lamp glow fans) plus wheels: what is drawn up close. The old cars are 9.6k, the truck is the largest here
const BUDGET_LOD0_SOLID := 7500     ## the body without the lamp fans
const LOD1_MAX_SHARE := 0.45        ## solid triangles of Body_LOD1 over those of Body
const LOD1_MIN := 250
const MAX_SURFACES_NEAR := 9        ## Body (5) + four wheels: the cars' draw call budget
const MAX_ATLAS := 1024             ## px: these models are small; four more 2K atlases each would cost texture memory the city has no room for
const FILL_MASK := 1 << 18

## model -> kind, wheel layout ("car" = four corner wheels, "bike" = WheelF / WheelR on the centre line, "none" = hover craft), size tolerance in m
const MODELS := {
	"car_taxi": {"kind": &"taxi", "wheels": "car", "tol": 0.6},
	"car_wagon": {"kind": &"wagon", "wheels": "car", "tol": 0.3},
	"car_van": {"kind": &"van", "wheels": "car", "tol": 0.45},
	"car_truck": {"kind": &"truck", "wheels": "car", "tol": 0.45},
	"bike_street": {"kind": &"bike", "wheels": "bike", "tol": 0.3},
	"car_hover": {"kind": &"hover", "wheels": "none", "tol": 0.3},
	"car_vael_patrol": {"kind": &"vael_patrol", "wheels": "none", "tol": 0.3},
}


func run(host: Node) -> void:
	OS.set_environment("QT_OPEN_MODELS", "0")             # this test is about the Wave 14 art set; tests/test_open_models.gd covers the open-source models
	_registry()
	for model_name: String in MODELS:
		_model(host, model_name, MODELS[model_name])
	await _visuals(host)
	OS.set_environment("QT_OPEN_MODELS", "1")


# ------------------------------------------------------------------ registry in VehicleSpecs
func _registry() -> void:
	var fresh: Array[StringName] = [&"taxi", &"wagon", &"van", &"truck", &"bike", &"hover", &"vael_patrol"]
	for k in fresh:
		TestLib.check(VehicleSpecs.SPECS.has(k), "%s is registered in VehicleSpecs.SPECS" % k)
		if not VehicleSpecs.SPECS.has(k):
			continue
		var sp: Dictionary = VehicleSpecs.SPECS[k]
		TestLib.check(float(sp["max"]) > 10.0 and float(sp["acc"]) > 3.0 and float(sp["brake"]) > 10.0 and float(sp["hp"]) > 20.0, "%s has speed / acceleration / brake / hp" % k)
		TestLib.check(VehicleSpecs.mass_of(k) >= 100.0 and VehicleSpecs.seats_of(k) >= 1, "%s has mass %.0f kg and %d seats" % [k, VehicleSpecs.mass_of(k), VehicleSpecs.seats_of(k)])
	for k: StringName in VehicleSpecs.SPECS:
		TestLib.check(VehicleSpecs.mass_of(k) > 0.0 and VehicleSpecs.seats_of(k) > 0, "%s: mass_of / seats_of answer for every kind" % k)
	TestLib.check(VehicleSpecs.mass_of(&"truck") > VehicleSpecs.mass_of(&"van") and VehicleSpecs.mass_of(&"van") > VehicleSpecs.mass_of(&"sedan") and VehicleSpecs.mass_of(&"sedan") > VehicleSpecs.mass_of(&"bike"),
		"masses are ordered truck > van > sedan > bike")
	TestLib.check(float(VehicleSpecs.SPECS[&"truck"]["max"]) < float(VehicleSpecs.SPECS[&"sedan"]["max"]) and float(VehicleSpecs.SPECS[&"sport"]["max"]) > float(VehicleSpecs.SPECS[&"van"]["max"]),
		"a truck is slower than a sedan, a sport car faster than a van")
	TestLib.check(VehicleSpecs.STREAM_KINDS.size() == VehicleSpecs.STREAM_WEIGHTS.size(), "one stream weight per streamed kind")
	var sum := 0.0
	for w in VehicleSpecs.STREAM_WEIGHTS:
		sum += w
	TestLib.check(absf(sum - 1.0) < 0.001, "the stream weights add up to 1 (%.3f)" % sum)
	for k: StringName in VehicleSpecs.STREAM_KINDS:
		TestLib.check(VehicleSpecs.SPECS.has(k), "streamed kind %s has a spec" % k)
	for k: StringName in [&"taxi", &"wagon", &"van", &"truck"]:
		TestLib.check(k in VehicleSpecs.STREAM_KINDS, "%s is part of the traffic mix" % k)
	TestLib.check(not (&"vael_patrol" in VehicleSpecs.STREAM_KINDS), "Vael patrols are never streamed as traffic")
	seed(11)
	var counts := {}
	for i in 5000:
		var k := VehicleSpecs.pick_kind(randf())
		counts[k] = int(counts.get(k, 0)) + 1
	for k: StringName in [&"taxi", &"wagon", &"van", &"truck"]:
		TestLib.check(int(counts.get(k, 0)) > 100, "traffic picks %s (%d of 5000)" % [k, int(counts.get(k, 0))])
	# palettes: a taxi is yellow whatever the random pick, a husk keeps its charred colour
	for c in VehicleSpecs.COLORS:
		var t := VehicleSpecs.paint_for(&"taxi", c)
		TestLib.check(t.r > 0.7 and t.g > 0.5 and t.b < 0.3, "a taxi in the street palette's %s is yellow" % c)
	TestLib.check(VehicleSpecs.paint_for(&"taxi", VehicleSpecs.WRECK_COLOR) == VehicleSpecs.WRECK_COLOR, "a taxi husk keeps the wreck colour")
	TestLib.check(VehicleSpecs.paint_for(&"sedan", VehicleSpecs.COLORS[0]) == VehicleSpecs.COLORS[0], "a sedan wears the random street colour")


# ------------------------------------------------------------------ one model
func _model(host: Node, model_name: String, d: Dictionary) -> void:
	var kind: StringName = d["kind"]
	var tol: float = d["tol"]
	TestLib.check(ResourceLoader.exists("res://assets/models/%s.glb" % model_name), "%s.glb exists" % model_name)
	TestLib.check(VehicleSpecs.available_model(kind) == model_name, "%s is the model VehicleSpecs picks for %s" % [model_name, kind])
	var m := Game.load_model(model_name)
	TestLib.check(m != null, "%s loads through Game.load_model" % model_name)
	if m == null:
		return
	host.add_child(m)
	# nodes
	var body := m.get_node_or_null("Body") as MeshInstance3D
	var lod1 := m.get_node_or_null("Body_LOD1") as MeshInstance3D
	TestLib.check(body != null and body.mesh != null, "%s has the Body mesh (LOD0)" % model_name)
	TestLib.check(lod1 != null and lod1.mesh != null, "%s has the Body_LOD1 mesh" % model_name)
	if body == null or lod1 == null:
		m.queue_free()
		return
	var wheels := _wheels(m, model_name, d["wheels"], kind)
	# triangles
	var t0 := _tris(body)
	var t0_solid := _tris(body, true)
	var t1_solid := _tris(lod1, true)
	var near_tris := t0
	for w in wheels:
		near_tris += _tris(w as MeshInstance3D)
	TestLib.check(near_tris >= 2500 and near_tris <= BUDGET_LOD0, "%s LOD0 (body + wheels) %d triangles within 2500..%d" % [model_name, near_tris, BUDGET_LOD0])
	TestLib.check(t0_solid <= BUDGET_LOD0_SOLID, "%s solid body %d triangles (<= %d)" % [model_name, t0_solid, BUDGET_LOD0_SOLID])
	TestLib.check(t1_solid >= LOD1_MIN and float(t1_solid) <= float(t0_solid) * LOD1_MAX_SHARE, "%s LOD1 has %d solid triangles, %.0f %% of LOD0's %d (<= %.0f %%)" % [model_name, t1_solid, 100.0 * float(t1_solid) / maxf(float(t0_solid), 1.0), t0_solid, LOD1_MAX_SHARE * 100.0])
	TestLib.check(_tris(lod1) < t0, "%s LOD1 in total (%d) is lighter than LOD0 (%d)" % [model_name, _tris(lod1), t0])
	# draw calls: the raw surface count; the game merges the three lamp surfaces into one
	var surf := body.mesh.get_surface_count()
	for w in wheels:
		surf += (w as MeshInstance3D).mesh.get_surface_count()
	TestLib.check(surf <= MAX_SURFACES_NEAR, "%s draws in %d surfaces (<= %d)" % [model_name, surf, MAX_SURFACES_NEAR])
	TestLib.check(lod1.mesh.get_surface_count() <= body.mesh.get_surface_count(), "%s LOD1 has no more surfaces than LOD0 (%d / %d)" % [model_name, lod1.mesh.get_surface_count(), body.mesh.get_surface_count()])
	# the same materials on both LODs
	var n0 := _surface_names(body)
	var n1 := _surface_names(lod1)
	var same := true
	for n: String in n1:
		same = same and n0.has(n)
	TestLib.check(same and n1.has("Body") and n1.has("Details"), "%s LOD1 uses materials of LOD0 only (%s | %s)" % [model_name, ",".join(n1), ",".join(n0)])
	for n in LAMPS:
		TestLib.check(n0.has(n) and n1.has(n), "%s has the %s lamp surface on both LODs" % [model_name, n])
	# materials and baked textures
	var mb := _material(body, "Body")
	var md := _material(body, "Details")
	TestLib.check(mb != null and mb.albedo_texture != null and mb.normal_texture != null, "%s has a textured 'Body' paint material (the game recolours a duplicate)" % model_name)
	TestLib.check(md != null and md.albedo_texture != null and md.normal_texture != null, "%s has a baked 'Details' atlas" % model_name)
	if mb != null and mb.albedo_texture != null and md != null and md.albedo_texture != null:
		var side := maxi(mb.albedo_texture.get_width(), md.albedo_texture.get_width())
		TestLib.check(side <= MAX_ATLAS and md.albedo_texture.get_width() >= 512, "%s atlases are %d px (512..%d)" % [model_name, side, MAX_ATLAS])
		TestLib.check(mb.albedo_texture.resource_path.contains("/%s_" % model_name) and md.albedo_texture.resource_path.contains("/%s_" % model_name), "%s has its own baked atlas files" % model_name)
	TestLib.check(md != null and md.emission_enabled and md.emission_texture != null, "%s has glowing alien trim baked into the atlas (emission map)" % model_name)
	for n in LAMPS:
		var lm := _material(body, n)
		TestLib.check(lm != null and lm.emission_enabled and lm.emission_energy_multiplier >= 1.0 and lm.emission_energy_multiplier <= 3.2, "%s %s is emissive (not hotter than the tonemap allows)" % [model_name, n])
	TestLib.check(_mean_z(body, "Headlights") < -0.7 and _mean_z(body, "Taillights") > 0.7, "%s headlights face -Z and taillights +Z" % model_name)
	# size against the spec (the lamp glow fans reach past the body on purpose)
	var spec: Dictionary = VehicleSpecs.SPECS[kind]
	var box := _solid_aabb(m, ["Body"], wheels)
	TestLib.check(absf(box.size.z - float(spec["len"])) <= tol, "%s is %.2f m long (spec %.2f)" % [model_name, box.size.z, float(spec["len"])])
	TestLib.check(absf(box.size.x - float(spec["wid"])) <= tol, "%s is %.2f m wide (spec %.2f)" % [model_name, box.size.x, float(spec["wid"])])
	TestLib.check(absf(box.size.y - float(spec["hgt"])) <= tol, "%s is %.2f m tall (spec %.2f)" % [model_name, box.size.y, float(spec["hgt"])])
	if str(d["wheels"]) == "none":
		var hh: float = float(spec["hover_h"])
		TestLib.check(box.position.y >= hh - 0.25 and box.position.y <= hh + 0.02, "%s floats: lowest solid point %.2f m (hover_h %.2f)" % [model_name, box.position.y, hh])
	else:
		TestLib.check(box.position.y > -0.02 and box.position.y < 0.08, "%s touches the ground (min y %.3f)" % [model_name, box.position.y])
	TestLib.check(absf(box.get_center().x) < 0.06, "%s is symmetric about the centre line (x centre %.3f)" % [model_name, box.get_center().x])
	# lights
	var lights := m.find_children("*", "Light3D", true, false)
	var fill := false
	var shadows := false
	var spot := false
	for l in lights:
		fill = fill or (l as Light3D).light_cull_mask == FILL_MASK
		shadows = shadows or (l as Light3D).shadow_enabled
		spot = spot or l is SpotLight3D
	TestLib.check(lights.size() >= 3 and fill and spot and m.get_node_or_null("UnderglowLight") != null, "%s ships headlight spot, underglow and a model-only fill light (%d lights)" % [model_name, lights.size()])
	TestLib.check(not shadows, "%s lights cast no shadows" % model_name)
	m.get_parent().remove_child(m)
	m.free()


## The wheel nodes of the model, checked against the layout. Returns them (empty for a hover craft).
func _wheels(m: Node3D, model_name: String, layout: String, kind: StringName) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var radius: float = float(VehicleSpecs.SPECS[kind]["wheel"])
	var names: Array = []
	match layout:
		"car":
			names = [["WheelFL", -1, -1], ["WheelFR", 1, -1], ["WheelRL", -1, 1], ["WheelRR", 1, 1]]
		"bike":
			names = [["WheelF", 0, -1], ["WheelR", 0, 1]]
	if layout == "none":
		for wn in ["WheelFL", "WheelF", "WheelRL", "WheelR"]:
			TestLib.check(m.get_node_or_null(wn) == null, "%s has no %s (it hovers)" % [model_name, wn])
	for pair in names:
		var w := m.get_node_or_null(String(pair[0])) as MeshInstance3D
		TestLib.check(w != null, "%s has the separate wheel node %s" % [model_name, pair[0]])
		if w == null:
			continue
		out.append(w)
		TestLib.check((int(pair[1]) == 0 and absf(w.position.x) < 0.02) or (int(pair[1]) != 0 and signf(w.position.x) == float(pair[1])), "%s %s is on the right side (x %.2f)" % [model_name, pair[0], w.position.x])
		TestLib.check(signf(w.position.z) == float(pair[2]), "%s %s is on the right axle (front is -Z, z %.2f)" % [model_name, pair[0], w.position.z])
		var wb := w.get_aabb()
		TestLib.check(wb.get_center().length() < 0.06, "%s %s is pivoted at the axle" % [model_name, pair[0]])
		TestLib.check(absf(wb.size.y * 0.5 - radius) < 0.06, "%s %s radius %.2f m matches the spec (%.2f)" % [model_name, pair[0], wb.size.y * 0.5, radius])
		TestLib.check(absf(w.position.y - wb.size.y * 0.5) < 0.04, "%s %s rests on the ground" % [model_name, pair[0]])
		TestLib.check(w.visibility_range_end > 10.0 and w.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s %s fades out with distance and casts no shadow" % [model_name, pair[0]])
	return out


# ------------------------------------------------------------------ VehicleVisual: LOD switch, shared materials, paint
func _visuals(host: Node) -> void:
	for model_name: String in MODELS:
		var d: Dictionary = MODELS[model_name]
		var kind: StringName = d["kind"]
		var v := VehicleVisual.new()
		var root := v.build(kind, Color(0.2, 0.9, 1.0))
		host.add_child(root)
		TestLib.check(v.uses_model and v.model_name == model_name, "%s: VehicleVisual builds the real model (%s)" % [kind, v.model_name])
		TestLib.check(v.body != null and v.body_lod1 != null, "%s: the visual found Body and Body_LOD1" % kind)
		if v.body == null or v.body_lod1 == null:
			root.queue_free()
			continue
		TestLib.check(is_equal_approx(v.body.visibility_range_end, VehicleVisual.LOD1_DIST) and is_equal_approx(v.body_lod1.visibility_range_begin, VehicleVisual.LOD1_DIST),
			"%s: Body up to %.0f m, Body_LOD1 beyond" % [kind, VehicleVisual.LOD1_DIST])
		TestLib.check(v.body.visibility_range_begin == 0.0 and v.body_lod1.visibility_range_end == 0.0, "%s: the LOD ranges do not leave a gap" % kind)
		# the same material instances on both LODs: the paint and the lamps follow
		var shared := 0
		var total := 0
		var lamp_ok := false
		for s in v.body_lod1.mesh.get_surface_count():
			var o1 := v.body_lod1.get_surface_override_material(s)
			total += 1
			if o1 == null:
				continue
			for t in v.body.mesh.get_surface_count():
				if v.body.get_surface_override_material(t) == o1:
					shared += 1
					if o1 is ShaderMaterial:
						lamp_ok = true
					break
		TestLib.check(shared == total and total >= 3, "%s: LOD1 shares all %d surface materials with LOD0 (%d)" % [kind, total, shared])
		TestLib.check(lamp_ok, "%s: the merged lamp material is shared by both LODs" % kind)
		v.set_paint(Color(0.5, 0.1, 0.1))
		var painted := v.get_paint()
		var lod_body: BaseMaterial3D = null
		for s in v.body_lod1.mesh.get_surface_count():
			var mt := v.body_lod1.get_surface_override_material(s) as BaseMaterial3D
			if mt != null and String((v.body_lod1.mesh.surface_get_material(s) as Material).resource_name) == "Body":
				lod_body = mt
		TestLib.check(lod_body != null and lod_body.albedo_color.is_equal_approx(painted) and painted.r > painted.b, "%s: a repaint reaches Body_LOD1" % kind)
		# wheels follow the layout and steer the front ones
		var nw := 4 if str(d["wheels"]) == "car" else (2 if str(d["wheels"]) == "bike" else 0)
		TestLib.check(v.wheels.size() == nw, "%s: %d wheel nodes (%d)" % [kind, nw, v.wheels.size()])
		if nw > 0:
			v.spin(1.0, 0.3)
			TestLib.check(is_equal_approx(v.wheels[0].rotation.y, 0.3) and not is_equal_approx(v.wheels[0].rotation.x, 0.0) and is_equal_approx(v.wheels[v.wheels.size() - 1].rotation.y, 0.0),
				"%s: the front wheel steers and rolls, the rear one only rolls" % kind)
		host.remove_child(root)
		root.free()


# ------------------------------------------------------------------ helpers
func _tris(mi: MeshInstance3D, solid_only := false) -> int:
	var total := 0
	if mi == null or mi.mesh == null:
		return 0
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if solid_only and mat != null and String(mat.resource_name) in LAMPS:
			continue
		var arr := mi.mesh.surface_get_arrays(s)
		var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
		total += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _surface_names(mi: MeshInstance3D) -> Array[String]:
	var out: Array[String] = []
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		out.append(String(mat.resource_name) if mat != null else "")
	return out


func _material(mi: MeshInstance3D, mat_name: String) -> StandardMaterial3D:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if m != null and m.resource_name == mat_name:
			return m
	return null


func _mean_z(mi: MeshInstance3D, mat_name: String) -> float:
	var sum := 0.0
	var n := 0
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m != null and m.resource_name == mat_name:
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				sum += (mi.global_transform * v).z
				n += 1
	return sum / maxf(float(n), 1.0)


## World bounds of the solid vertices of the named mesh nodes plus the wheel nodes (lamp surfaces are left out: their glow fans reach past the body).
func _solid_aabb(root: Node3D, names: Array, wheels: Array[Node3D]) -> AABB:
	var nodes: Array[MeshInstance3D] = []
	for n: String in names:
		nodes.append(root.get_node(n) as MeshInstance3D)
	for w in wheels:
		nodes.append(w as MeshInstance3D)
	var box := AABB()
	var first := true
	for mi in nodes:
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and String(mat.resource_name) in LAMPS:
				continue
			for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var p := mi.global_transform * v
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
	return box
