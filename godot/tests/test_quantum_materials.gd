extends RefCounted
const Districts := preload("res://scripts/world/city_districts.gd")
## Quantum-realism layer: shaders compile with the signature include, ground/facade materials stay fallback-capable. Run: tools/test.sh tests/test_quantum_materials.gd


func run(_host: Node) -> void:
	var inc := FileAccess.get_file_as_string("res://assets/shaders/quantum_surface.gdshaderinc")
	for fn in ["qs_film", "qs_flicker", "qs_seam", "qs_amount"]:
		TestLib.check(inc.contains(fn), "include defines %s" % fn)
	TestLib.check(not inc.contains("texture("), "layer taps no texture (LOW stays cheap)")
	for f in ["ground_core", "building_core"]:
		var src := FileAccess.get_file_as_string("res://assets/shaders/%s.gdshaderinc" % f)
		TestLib.check(src.contains("quantum_surface.gdshaderinc") and src.contains("qs_seam"), "%s uses the layer" % f)
	for sh in ["ground", "ground_lite", "building", "scanned_surface"]:
		TestLib.check(load("res://assets/shaders/%s.gdshader" % sh) is Shader, "%s compiles" % sh)
	var m := ShaderMaterial.new()
	for tier in [0, 1, 2]:
		var n := MaterialLib.apply_to(m, ["road", "walk", "brick", "wall"], tier)
		TestLib.check(n == 0 or MaterialLib.has_scanned("asphalt", tier), "tier %d: scanned slots only when imported" % tier)
	TestLib.check(MaterialLib.apply_to(null, ["road"], 2) == 0, "null material is a no-op")
	for d in Districts.COUNT:
		TestLib.check(MaterialLib.seam_color(d).get_luminance() > 0.2, "district %d seam colour glows" % d)
	var fb := StandardMaterial3D.new()
	TestLib.check(MaterialLib.get_material("brick", 2, fb) == fb or MaterialLib.has_scanned("brick", 2), "facade falls back")
