extends RefCounted
## Materials v2 (shader-only surface realism): the include is texture-free and defines every term, the ground / facade / prop shaders use it, the strength follows the
## graphics tier, the TEST menu switch works, and the live city carries the shaders. Run: tools/test.sh tests/test_materials_v2.gd (new class_name: tools/import.sh first)

const INC := "res://assets/shaders/material_v2.gdshaderinc"


func run(host: Node) -> void:
	_test_sources()
	_test_tiers(host)
	_test_flicker()
	await _test_live_city(host)
	_test_menus()
	MaterialsV2.set_enabled(true)
	MaterialsV2.set_tier(Game.quality)


func _test_sources() -> void:
	var inc := FileAccess.get_file_as_string(INC)
	TestLib.check(inc.length() > 500, "include exists")
	for fn in ["mv2_macro", "mv2_tint", "mv2_tri", "mv2_edge", "mv2_road_decals", "mv2_glass", "mv2_pane_wobble", "mv2_flicker", "mv2_amount"]:
		TestLib.check(inc.contains(fn), "include defines %s" % fn)
	TestLib.check(not inc.contains("texture(") and not inc.contains("sampler2D"), "include reads no texture (texture memory stays flat)")
	TestLib.check(inc.contains("#ifndef MV2_INCLUDED"), "include is guarded against double inclusion")
	TestLib.check(inc.contains("global uniform float %s" % MaterialsV2.PARAM), "shader global matches MaterialsV2.PARAM")
	var users := {
		"ground_core.gdshaderinc": ["mv2_macro", "mv2_road_decals"],
		"building_core.gdshaderinc": ["mv2_macro", "mv2_tri", "mv2_glass", "mv2_pane_wobble", "mv2_flicker"],
		"prop_core.gdshaderinc": ["mv2_macro", "mv2_tri", "mv2_edge", "mv2_flicker"],
	}
	for f: String in users:
		var src := FileAccess.get_file_as_string("res://assets/shaders/%s" % f)
		TestLib.check(src.contains("material_v2.gdshaderinc"), "%s includes the layer" % f)
		for fn: String in users[f]:
			TestLib.check(src.contains(fn), "%s uses %s" % [f, fn])
	for sh: String in MaterialsV2.SHADERS:
		TestLib.check(load("res://assets/shaders/%s.gdshader" % sh) is Shader, "%s loads" % sh)


func _test_tiers(host: Node) -> void:
	TestLib.check(MaterialsV2.registered, "global registered by Game._ready")
	var tiers := PerfTiers.new()
	host.add_child(tiers)
	var last := -1.0
	for t in 3:
		Game.quality_changed.emit(t)
		TestLib.check(is_equal_approx(MaterialsV2.amount, MaterialsV2.amount_for(t)), "tier %d sets the strength" % t)
		TestLib.check(MaterialsV2.amount > last, "strength rises with the tier")
		last = MaterialsV2.amount
	TestLib.check(MaterialsV2.amount_for(0) >= 0.3 and MaterialsV2.amount_for(2) <= 1.0, "LOW keeps part of the look, HIGH is full")
	MaterialsV2.set_enabled(false)
	TestLib.check(MaterialsV2.effective() == 0.0, "switch off gives the v1 look")
	Game.quality_changed.emit(1)
	TestLib.check(MaterialsV2.effective() == 0.0, "a tier change does not re-enable it")
	MaterialsV2.set_enabled(true)
	TestLib.check(is_equal_approx(MaterialsV2.effective(), MaterialsV2.amount_for(1)), "switch on restores the tier strength")
	host.remove_child(tiers)
	tiers.queue_free()


func _test_flicker() -> void:
	var lo := 10.0
	var hi := 0.0
	for k in 600:
		var f := MaterialsV2.flicker(0.37 + float(k % 7) * 0.11, float(k) * 0.173)
		lo = minf(lo, f)
		hi = maxf(hi, f)
	TestLib.check(lo >= 0.6 and hi <= 1.001, "sign flicker stays in a readable band (%.2f..%.2f)" % [lo, hi])
	TestLib.check(hi - lo > 0.02, "sign flicker actually varies")
	TestLib.check(is_equal_approx(MaterialsV2.flicker(0.4, 3.0, 0.0), 1.0), "amount 0 is steady")


func _test_live_city(host: Node) -> void:
	var scene := load("res://scenes/world.tscn") as PackedScene
	var city := scene.instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	var found := {}
	var stack: Array[Node] = [city]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mats: Array = []
		if n is GeometryInstance3D:
			var gi := n as GeometryInstance3D
			if gi.material_override != null:
				mats.append(gi.material_override)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				mats.append(mi.get_active_material(s))
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh.mesh
			for s in mm.get_surface_count():
				mats.append(mm.surface_get_material(s))
		for m in mats:
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				found[(m as ShaderMaterial).shader.resource_path.get_file().get_basename()] = true
	TestLib.check(found.has("ground") or found.has("ground_lite"), "the live city draws its ground with a v2 shader (%s)" % str(found.keys()))
	TestLib.check(found.has("building"), "the live city draws its facades with a v2 shader")
	var n_v2 := 0
	for k: String in found:
		if MaterialsV2.SHADERS.has(k):
			n_v2 += 1
	TestLib.check(n_v2 >= 3, "at least three v2 shader families are live (%d)" % n_v2)
	host.remove_child(city)
	city.queue_free()


func _test_menus() -> void:
	var msg := TestMode.set_materials_v2(false)
	TestLib.check(not MaterialsV2.enabled and msg.contains("V1"), "TEST action switches to the v1 look")
	msg = TestMode.set_materials_v2(true)
	TestLib.check(MaterialsV2.enabled and msg.contains("V2"), "TEST action switches to v2")
	var src := FileAccess.get_file_as_string("res://scripts/ui/test_menu.gd")
	TestLib.check(src.contains("set_materials_v2"), "TEST menu lists the switch")
	src = FileAccess.get_file_as_string("res://scripts/ui/demo_menu.gd")
	TestLib.check(src.contains("set_materials_v2"), "DEMO menu lists the switch")
