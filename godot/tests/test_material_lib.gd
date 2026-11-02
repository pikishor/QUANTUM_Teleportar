extends RefCounted
## MaterialLib falls back to the procedural material when no scanned assets exist. Run: tools/test.sh tests/test_material_lib.gd


func run(_host: Node) -> void:
	var fb := StandardMaterial3D.new()
	for k in MaterialLib.KINDS:
		if not MaterialLib.has_scanned(k, 2):
			TestLib.check(MaterialLib.scanned(k, 2) == null, "%s: no scanned set -> null" % k)
			TestLib.check(MaterialLib.get_material(k, 0, fb) == fb, "%s: falls back to procedural" % k)
	TestLib.check(not MaterialLib.has_scanned("lava", 2), "unknown kind has no set")
	TestLib.check(MaterialLib.path("brick", "orm", 0).ends_with("_half.png"), "LOW uses half files")
	TestLib.check(load(MaterialLib.SHADER) is Shader, "scanned shader compiles")
