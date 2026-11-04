extends RefCounted
## Character import pipeline (headless): bone-name mapping of Mixamo / Quaternius / Rigify naming, retarget to the CharacterRig contract, clip renaming, material, triangle limit
## with auto-LOD, and the procedural fallback. A tiny synthetic rigged glb (Mixamo names) is generated here.
## Run: tools/test.sh tests/test_character_import.gd   (tools/import.sh first: new class_name scripts)

const MIXAMO := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
const PARENT := [-1, 0, 1, 2, 3, 4, 3, 6, 7, 3, 9, 10, 0, 12, 13, 0, 15, 16]
const REST_Y := [0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.25, 1.1, 0.95, 1.25, 1.1, 0.95, 0.85, 0.5, 0.1, 0.85, 0.5, 0.1]


static func _sk(names: Array, prefix: String) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for i in names.size():
		sk.add_bone(prefix + names[i])
		if PARENT[i] >= 0:
			sk.set_bone_parent(i, PARENT[i])
		var py: float = REST_Y[i] - (REST_Y[PARENT[i]] if PARENT[i] >= 0 else 0.0)
		var px := 0.0
		if names[i].contains("Left"):
			px = 0.1
		elif names[i].contains("Right"):
			px = -0.1
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(px if PARENT[i] == 0 or i in [6, 9] else 0.0, py, 0.0)))
		sk.reset_bone_pose(i)
	return sk


## A skinned grid of `n` x `n` quads around the skeleton (about 2 n n triangles), every vertex bound to bone 0.
static func _mesh(n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for y in n + 1:
		for x in n + 1:
			v.append(Vector3(x * 0.6 / n - 0.3, y * 1.6 / n, 0.0))
			uv.append(Vector2(float(x) / n, float(y) / n))
	for y in n:
		for x in n:
			var a := y * (n + 1) + x
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in v.size():
		bones.append_array([0, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _scene(prefix: String, n: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Armature"
	var sk := _sk(MIXAMO, prefix)
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _mesh(n)
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	for nm in ["Idle", "Walking", "Running", "Death"]:
		var a := Animation.new()
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:" + prefix + "Hips"))
		a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
		a.rotation_track_insert_key(t, 1.0, Quaternion(Vector3.UP, 0.3))
		a.length = 1.0
		lib.add_animation(nm, a)
	ap.add_animation_library(&"", lib)
	return root


func run(host: Node) -> void:
	# --- name mapping of the three rig families
	var rows := [["mixamorig:LeftUpLeg", "ThighL"], ["mixamorig1:RightForeArm", "ForeArmR"], ["DEF-upper_arm.L", "UpperArmL"], ["DEF-shin.R", "ShinR"],
			["UpperArm.L", "UpperArmL"], ["LowerLeg.R", "ShinR"], ["thigh_l", "ThighL"], ["calf_r", "ShinR"]]
	for r in rows:
		var nb := CharacterImport.normalize(r[0])
		var key := ""
		for k in CharacterImport.ALIASES:
			if nb[0] in CharacterImport.ALIASES[k] and String(k) + nb[1] == r[1]:
				key = r[1]
		TestLib.check(key == r[1], "%s maps to %s (%s)" % [r[0], r[1], nb])
	TestLib.check(CharacterImport.canonical_anim("Rifle Walking Forward") == &"walk" and CharacterImport.canonical_anim("Dying_01") == &"death"
			and CharacterImport.canonical_anim("xyz") == &"", "clip names map to idle / walk / ... by keyword")
	TestLib.check(CharacterImport.role_class("enemy_trooper") == "enemy" and CharacterImport.role_class("hero") == "hero" and CharacterImport.role_class("tree") == "", "roles")

	# --- synthetic glb through the whole pipeline
	var dir := "user://test_character_import"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/syn.glb"
	var src := _scene("mixamorig_", 12)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	TestLib.check(doc.append_from_scene(src, st) == OK and doc.write_to_filesystem(st, path) == OK, "synthetic rigged glb written")
	src.free()
	var res := CharacterImport.load_file(path, "enemy_test")
	TestLib.check(res["root"] != null, "synthetic glb imports and retargets: %s" % [res["info"]])
	if res["root"] == null:
		return
	var root := res["root"] as Node3D
	host.add_child(root)
	TestLib.check(CharacterRig.has_rig(root), "retargeted skeleton has every CharacterRig bone")
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	TestLib.check(sk.find_bone("Rifle") >= 0 and sk.get_bone_parent(sk.find_bone("Rifle")) >= 0, "Rifle bone added under the right hand")
	var ap := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	TestLib.check(ap.has_animation(&"idle") and ap.has_animation(&"walk") and ap.has_animation(&"run") and ap.has_animation(&"death") and not ap.has_animation(&"Idle"), "clips renamed to the contract names")
	var ia := ap.get_animation(&"idle")
	var tp := String(ia.track_get_path(0)) if ia.get_track_count() > 0 else ""
	TestLib.check(tp.ends_with(":Hips"), "track path follows the renamed bone (%s)" % tp)
	var body := sk.get_child(0) as MeshInstance3D
	var mat := body.mesh.surface_get_material(0) as ShaderMaterial
	TestLib.check(mat != null and mat.shader.resource_path.ends_with("character_quantum.gdshader"), "quantum-realism material on the body")
	TestLib.check(int(res["info"]["surfaces"]) <= CharacterImport.MAX_SURFACES and float(res["info"].get("scale", 0.0)) > 0.0, "surface budget kept, scaled to height")
	root.queue_free()

	# --- triangle limit with auto-LOD (a 90 x 90 grid is 16200 triangles, the citizen budget is 4000)
	var info := {}
	var lim := CharacterImport.limit_mesh(_mesh(90), CharacterImport.TRI_BUDGET["citizen"], info)
	TestLib.check(int(info["tris_source"]) == 16200 and int(info["tris"]) <= 4000 or bool(info["over"]), "over-budget mesh reduced: %s" % [info])
	var small := {}
	CharacterImport.limit_mesh(_mesh(10), 4000, small)
	TestLib.check(int(small["tris"]) == 200 and not bool(small["over"]), "mesh under budget is kept")

	# --- fallback and unusable sources
	TestLib.check(CharacterImport.find_source("hero_none") == "", "nothing dropped: no source")
	var fb := CharacterImport.instantiate("hero_none")
	TestLib.check(fb != null and CharacterRig.has_rig(fb), "empty folder falls back to the procedural hero")
	if fb:
		fb.free()
	TestLib.check(CharacterImport.instantiate("nonsense") == null, "unknown role yields null")
	var bad := Node3D.new()
	TestLib.check(CharacterImport.process(bad, "hero")["root"] == null, "scene without skeleton rejected")
	bad.free()
