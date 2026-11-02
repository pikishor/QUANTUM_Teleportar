extends RefCounted
## Interior kit tests (headless): the converted glb pieces exist and stay lean, the six kit layouts build on every tier inside the interior budgets (still at most 4 draw calls),
## kit props are really in the meshes, colliders and anchors hold, builds are deterministic, and credits are in docs/THIRD_PARTY.md. Run: tools/test.sh tests/test_interior_kit.gd

const ORIGIN := Vector3(900.0, 600.0, 900.0)
const KIT_TYPES: Array[StringName] = [&"corridor_lab", &"teleporter_hall", &"server_room", &"cargo_bay", &"med_bay", &"control_room"]
const SEEDS := [1, 2, 3, 7, 11]

var root: Node3D


func run(host: Node) -> void:
	root = Node3D.new()
	host.add_child(root)
	_pieces()
	_layouts()
	await _builds(host)
	_credits()


func _pieces() -> void:
	var total := 0
	for piece: String in InteriorKit.piece_names():
		var path := "res://assets/models/kit_%s.glb" % piece
		TestLib.check(ResourceLoader.exists(path), "kit piece %s exists" % piece)
		var d := InteriorKit.data(piece)
		TestLib.check(not d.is_empty(), "kit piece %s loads with mesh data" % piece)
		if d.is_empty():
			continue
		var tris := (d["idx"] as PackedInt32Array).size() / 3
		total += tris
		TestLib.check(tris > 20 and tris <= 1000, "kit piece %s is light (%d tris)" % [piece, tris])
		var sz: Vector3 = d["size"]
		TestLib.check(sz.y > 0.2 and sz.y < 5.0 and sz.x < 4.5 and sz.z < 3.0, "kit piece %s has a sane size %s" % [piece, sz])
		TestLib.check((d["cols"] as PackedColorArray).size() == (d["verts"] as PackedVector3Array).size(), "kit piece %s carries vertex colours" % piece)
	TestLib.check(total < 7000, "the whole kit is under 7000 triangles (%d)" % total)
	for kind: String in InteriorKit.PIECES:
		TestLib.check(InteriorProps.DEFS.has(kind), "%s has a DEFS entry" % kind)


func _layouts() -> void:
	TestLib.check(KIT_TYPES.size() >= 6, "at least six kit layouts")
	for t in KIT_TYPES:
		TestLib.check(InteriorGen.TYPES.has(t) and InteriorKinds.has_type(t), "%s is a registered interior type" % t)
		TestLib.check(InteriorKinds.AMBIENCE.has(t), "%s has ambience hooks" % t)
		var uses_kit := false
		for r: Dictionary in InteriorKinds.spec(t)["rooms"]:
			for step: Array in r["prog"]:
				if step.size() > 1 and str(step[1]).begins_with("kit_"):
					uses_kit = true
		TestLib.check(uses_kit, "%s programs kit pieces" % t)


func _builds(host: Node) -> void:
	var max_tris := [0, 0, 0]
	for t in KIT_TYPES:
		for sd in SEEDS:
			var plan := InteriorGen.plan_for(t, sd)
			TestLib.check(plan.signature() == InteriorPlan.generate(t, sd).signature(), "%s seed %d is deterministic" % [t, sd])
			var kit_props := 0
			for p: Dictionary in plan.props:
				if InteriorKit.is_kit(str(p["kind"])):
					kit_props += 1
			TestLib.check(kit_props >= 3, "%s seed %d places kit props (%d)" % [t, sd, kit_props])
			for a in [&"civilian", &"guard"]:
				TestLib.check((plan.anchors.get(a, []) as Array).size() >= 4, "%s seed %d keeps %s anchors" % [t, sd, a])
			for q in 3:
				var it := InteriorGen.build(t, sd, ORIGIN, q)
				root.add_child(it)
				var st: Dictionary = it.stats()
				max_tris[q] = maxi(max_tris[q], int(st["tris"]))
				TestLib.check(int(st["draws"]) <= 4, "%s seed %d tier %d: at most 4 draws (%d)" % [t, sd, q, st["draws"]])
				it.queue_free()
			await host.get_tree().process_frame
	TestLib.check(max_tris[0] <= 40000 and max_tris[1] <= 60000 and max_tris[2] <= 120000, "kit interiors stay in the triangle budgets: %s" % [max_tris])
	var ms := InteriorGen.mesh_set(InteriorGen.plan_for(&"teleporter_hall", 1), 2)
	TestLib.check(ms["tris"] > 1500, "the teleporter hall mesh holds the kit triangles (%d)" % ms["tris"])
	InteriorGen.clear_cache()


func _credits() -> void:
	var f := FileAccess.open("res://../docs/THIRD_PARTY.md", FileAccess.READ)
	TestLib.check(f != null, "docs/THIRD_PARTY.md is readable")
	if f:
		var txt := f.get_as_text()
		TestLib.check(txt.contains("Quaternius") and txt.contains("CC0"), "THIRD_PARTY.md credits Quaternius Ultimate Modular Sci-Fi (CC0)")
