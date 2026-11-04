class_name HeroCharacter
extends RefCounted
## The superhero (Quaternius Universal Base Characters, CC0; assets in assets_incoming/characters/hero/, prepared by tools/hero/prep_hero_assets.py): a 65-bone UE-style skeleton,
## male or female, dark or light skin, rigged-to-head hair modules, eyebrows and a beard. `build(opts)` turns the glTF kit into ONE skinned mesh (one surface, one draw call) with the
## `hero_body.gdshader` material (skin / eye / hair PBR maps, quantum-realism suit), on a skeleton that CharacterRig and Locomotion pose (procedural locomotion with foot planting: idle,
## walk, run, sprint, aim, fire, reload, hit, death, jump, fall, cover, takedown, slam, glide are all PlayerBody / CharacterRig states).
##   skeleton  bones renamed to the CharacterRig contract (Hips Torso Head UpperArmL/R ForeArmL/R ThighL/R ShinL/R FootL/R Rifle); EVERY bone's rest frame is re-aligned to the model axes
##             (x right, y up, -z forward: the rig's contract) and the skin binds are recomputed from that, so the mesh is unchanged at rest; Head, the shoulders and the rifle hang
##             from the Torso (spine_02), the fingers get a static grip curl
##   mesh      body + eyes + eyebrows + hair + beard + a small procedural carbine merged into one surface (vertex colour = material and suit weight); the triangle total is kept within
##             BUDGET by reducing the largest hair piece first; engine LODs are generated for the merged surface
##   textures  loaded imported (VRAM compressed); on the LOW tier halved through TextureBudget
## With the files absent (`available()` false) or an unmappable rig `build()` returns {"root": null}: PlayerBody keeps the old procedural / skinned hero.

const DIR := "res://assets_incoming/characters/hero"
const SHADER := "res://assets/shaders/hero_body.gdshader"
const BUDGET := 18000
const BODIES: Array[StringName] = [&"male", &"female"]
const SKINS: Array[StringName] = [&"dark", &"light"]
const HAIRS: Array[StringName] = [&"none", &"buzzed", &"parted", &"long", &"buns"]
const HAIR_FILES := {&"parted": "Hair_SimpleParted", &"long": "Hair_Long", &"buns": "Hair_Buns"}
## skin tone: the dark and the light colour maps of the kit are close, the multiplier separates them
const SKIN_MULT := {&"dark": Color(0.8, 0.72, 0.68), &"light": Color(1.5, 1.3, 1.2)}
const MODE_SKIN := 0
const MODE_EYE := 1
const MODE_HAIR1 := 2
const MODE_HAIR2 := 3
const MODE_GEAR := 4
## UE source bone -> rig contract name
const RENAMES := {"pelvis": "Hips", "spine_02": "Torso", "Head": "Head", "upperarm_l": "UpperArmL", "lowerarm_l": "ForeArmL", "upperarm_r": "UpperArmR", "lowerarm_r": "ForeArmR",
		"thigh_l": "ThighL", "calf_l": "ShinL", "foot_l": "FootL", "thigh_r": "ThighR", "calf_r": "ShinR", "foot_r": "FootR"}
const EXPOSED := ["head", "neck", "hand", "index", "middle", "ring", "pinky", "thumb"]     ## bone name prefixes the suit does not cover
## The carbine (model space, relative to the rifle pivot at the butt; the muzzle looks down -Z) and where the hands and the empties of the old model contract sit relative to it.
const RIFLE_PIVOT := Vector3(0.085, 1.38, 0.02)
const MUZZLE_AT := Vector3(0.0, 0.01, -0.86)
const WRIST_R := Vector3(0.0, -0.085, -0.18)
const WRIST_L := Vector3(-0.012, -0.07, -0.47)
const MAG_WELL := Vector3(0.0, -0.13, -0.405)
const MAG_POUCH := Vector3(-0.13, 1.18, -0.12)
const ELBOW_OUT := 0.45                          ## elbow pole of the arm solve: down, a little outward and back
const ELBOW_BACK := 0.35
const HAND_ROLL_R := 1.5708                         ## extra twist of each hand about its forearm (radians)
const HAND_ROLL_L := 3.1416
const RIFLE_MODEL := "res://assets/models/hero_rifle.glb"   ## tools/blender/model_hero_rifle.py: 2.3k triangles, glow seams in vertex colour G

static var _half := {}                          ## path -> halved texture (LOW)


static func path_for(body: StringName) -> String:
	return "%s/Superhero_%s_FullBody.gltf" % [DIR, String(body).capitalize()]


## True when the kit's files are imported (otherwise the old hero is used).
static func available(body: StringName = &"male") -> bool:
	return ResourceLoader.exists(path_for(body)) and ResourceLoader.exists("%s/hero_%s_normal.png" % [DIR, body]) and ResourceLoader.exists(SHADER)


## Valid option values (unknown or missing keys fall back to the defaults).
static func sanitize(opts: Dictionary) -> Dictionary:
	var body := StringName(str(opts.get("body", "male")))
	var skin := StringName(str(opts.get("skin", "dark")))
	var hair := StringName(str(opts.get("hair", "parted")))
	return {"body": body if body in BODIES else &"male", "skin": skin if skin in SKINS else &"dark", "hair": hair if hair in HAIRS else &"parted", "beard": bool(opts.get("beard", false))}


static func tex(path: String) -> Texture2D:
	var t := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if t != null and TextureBudget.low_active:
		if not _half.has(path):
			_half[path] = TextureBudget.halve_texture(t)
		return _half[path]
	return t


static func make_material(opts: Dictionary) -> ShaderMaterial:
	var o := sanitize(opts)
	var m := ShaderMaterial.new()
	m.resource_name = "HeroBody"
	m.shader = load(SHADER)
	m.set_shader_parameter(&"skin_mult", SKIN_MULT[o["skin"]])
	# "map_body"/"map_skin" (NPC variants): load the maps of this body and skin instead, so NPCs share the hero's textures (no extra texture memory); the tint stays that of "skin"
	var mb := StringName(str(opts.get("map_body", o["body"])))
	var ms := StringName(str(opts.get("map_skin", o["skin"])))
	var pairs := {"skin_albedo": "hero_%s_%s.png" % [mb, ms], "skin_normal": "hero_%s_normal.png" % mb, "skin_rough": "hero_%s_rough.png" % mb,
			"eye_albedo": "hero_eye_albedo.png", "eye_normal": "hero_eye_normal.png", "hair1_albedo": "hero_hair1_albedo.png", "hair1_normal": "hero_hair1_normal.png",
			"hair2_albedo": "hero_hair2_albedo.png", "hair2_normal": "hero_hair2_normal.png"}
	for k: String in pairs:
		var t := tex("%s/%s" % [DIR, pairs[k]])
		if t != null:
			m.set_shader_parameter(StringName(k), t)
	return m


## {root: Node3D (null on failure), ok, info, body: MeshInstance3D, material: ShaderMaterial}. `root` is the model the PlayerBody adopts: Rig/Skeleton3D/Body plus the empties
## Muzzle, WristL, WristR, MagWell, MagPouch in model space.
static func build(opts: Dictionary) -> Dictionary:
	var o := sanitize(opts)
	var fail := {"root": null, "ok": false, "info": {}}
	if not available(o["body"]):
		return fail
	var ps := load(path_for(o["body"])) as PackedScene
	var scene := ps.instantiate() as Node3D if ps != null else null
	if scene == null:
		return fail
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		scene.free()
		return fail
	var sk := sks[0] as Skeleton3D
	var name_to_idx := {}
	for i in sk.get_bone_count():
		name_to_idx[sk.get_bone_name(i)] = i
	for src: String in RENAMES:
		if not name_to_idx.has(src):
			scene.free()
			return fail
	for must: String in ["spine_03", "neck_01", "root", "hand_l", "hand_r"]:
		if not name_to_idx.has(must):
			scene.free()
			return fail
	var info := {"body": o["body"], "skin": o["skin"], "hair": o["hair"], "beard": o["beard"]}

	# ---- collect the mesh pieces (before the skeleton is changed): bone numbers are stable, names are used to map the modules' skins
	var comps: Array = []
	var exposed := PackedByteArray()
	exposed.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var ln := sk.get_bone_name(i).to_lower()
		for pre: String in EXPOSED:
			if ln.begins_with(pre):
				exposed[i] = 1
	for mi in sk.get_children():
		var mesh_i := mi as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null:
			continue
		var low := String(mesh_i.name).to_lower()
		var c := _piece(mesh_i, name_to_idx)
		if low.begins_with("eyes"):
			c["mode"] = MODE_EYE
		elif low.begins_with("eyebrows"):
			c["mode"] = _hair_mode(mesh_i)
		else:
			c["mode"] = MODE_SKIN
			c["suit"] = _suit_weights(c, exposed)
		comps.append(c)
	var hair_id: StringName = o["hair"]
	var extras: Array[String] = []
	if hair_id == &"buzzed":
		extras.append("Hair_BuzzedFemale" if o["body"] == &"female" else "Hair_Buzzed")
	elif HAIR_FILES.has(hair_id):
		extras.append(String(HAIR_FILES[hair_id]))
	if bool(o["beard"]):
		extras.append("Hair_Beard")
	for ex in extras:
		var mp := "%s/hair/%s.gltf" % [DIR, ex]
		var mps := load(mp) as PackedScene if ResourceLoader.exists(mp) else null
		var msc := mps.instantiate() as Node3D if mps != null else null
		if msc == null:
			continue
		for mi2 in msc.find_children("*", "MeshInstance3D", true, false):
			var m2 := mi2 as MeshInstance3D
			if m2.mesh == null or m2.skin == null:
				continue
			var c2 := _piece(m2, name_to_idx)
			c2["mode"] = _hair_mode(m2)
			comps.append(c2)
		msc.free()

	# ---- the skeleton in the rig's frame
	var rig_root := Node3D.new()
	rig_root.name = "Rig"
	rig_root.rotation.y = PI                       # the kit faces +Z, the game's front is -Z
	var wrapper := Node3D.new()
	wrapper.name = "HeroModel"
	wrapper.add_child(rig_root)
	sk.owner = null
	sk.get_parent().remove_child(sk)
	rig_root.add_child(sk)
	for ch in sk.get_children():
		sk.remove_child(ch)
		ch.free()
	scene.free()
	var head_rest := sk.get_bone_global_rest(int(name_to_idx["Head"])).origin     # kit space (the mesh's own space): the shader's crown line
	var model_pos := PackedVector3Array()          # bone positions in model space
	for i in sk.get_bone_count():
		var p := sk.get_bone_global_rest(i).origin
		model_pos.append(Vector3(-p.x, p.y, -p.z))
	var parents := PackedInt32Array()
	for i in sk.get_bone_count():
		parents.append(sk.get_bone_parent(i))
	var torso := int(name_to_idx["spine_02"])
	for nm: String in ["Head", "upperarm_l", "upperarm_r"]:
		parents[int(name_to_idx[nm])] = torso
	for src: String in RENAMES:
		sk.set_bone_name(int(name_to_idx[src]), String(RENAMES[src]))
	var rifle := sk.get_bone_count()
	sk.add_bone("Rifle")
	parents.append(torso)
	model_pos.append(RIFLE_PIVOT)
	var n_bones := sk.get_bone_count()
	for i in n_bones:
		sk.set_bone_parent(i, parents[i])
	_apply_rest(sk, parents, model_pos)

	# ---- the shouldered carbine pose is baked into the REST pose (the rig's IK expects a rest pose that already holds the rifle): arms solved onto the grips, fingers curled,
	# the mesh skinned once on the CPU, and the bones re-framed at their posed positions (identity frames again), so rig.apply() with neutral inputs changes nothing
	var armed := bool(opts.get("armed", true))               # false: no carbine mesh (citizens)
	if armed:
		comps.append(_rifle_piece(rifle))
	var binds: Array[Transform3D] = []
	for i in n_bones:
		binds.append(sk.get_bone_global_rest(i).affine_inverse())
	_aim_arms(sk, RIFLE_PIVOT + WRIST_R, RIFLE_PIVOT + WRIST_L)
	_curl_fingers(sk)
	var mats: Array[Transform3D] = []
	var posed := PackedVector3Array()
	for i in n_bones:
		var gp := _global_pose(sk, i)
		mats.append(gp * binds[i])
		posed.append(Vector3(-gp.origin.x, gp.origin.y, -gp.origin.z))
	for c: Dictionary in comps:
		_bake(c, mats)
	sk.reset_bone_poses()
	_apply_rest(sk, parents, posed)

	# ---- the merged mesh
	var budget := clampi(int(opts.get("budget", BUDGET)), 1500, BUDGET)
	var total := _fit(comps, budget)
	var merged := _merge(comps)
	var mat := make_material(opts.merged(o, true))
	var hp := head_rest
	mat.set_shader_parameter(&"scalp_y", hp.y + 0.11)
	mat.set_shader_parameter(&"scalp_z", hp.z)
	mat.set_shader_parameter(&"scalp", 0.0 if hair_id == &"none" else 1.0)
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, merged, [], {}, mat, "Hero")
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	info["tris"] = total
	info["lods"] = im.get_surface_lod_count(0)
	info["pieces"] = comps.size()
	var skin := Skin.new()
	for i in n_bones:
		skin.add_bind(i, sk.get_bone_global_rest(i).affine_inverse())
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.skin = skin
	body.extra_cull_margin = 1.0
	sk.add_child(body)
	body.skeleton = NodePath("..")
	for r: Array in [["Muzzle", RIFLE_PIVOT + MUZZLE_AT], ["WristL", posed[int(name_to_idx["hand_l"])]], ["WristR", posed[int(name_to_idx["hand_r"])]], ["MagWell", RIFLE_PIVOT + MAG_WELL], ["MagPouch", MAG_POUCH]]:
		var e := Node3D.new()
		e.name = r[0]
		e.position = r[1]
		wrapper.add_child(e)
	var ok := total <= budget and mesh.get_surface_count() == 1
	info["surfaces"] = mesh.get_surface_count()
	info["ok"] = ok
	return {"root": wrapper, "ok": ok, "info": info, "body": body, "material": mat}


## Bone rests from model-space positions: identity frames (the rig's contract), the root carries the half turn of the Rig node. A local origin is a difference of model-space positions
## in the (model aligned) parent frame; the root's own origin is turned into kit space.
static func _apply_rest(sk: Skeleton3D, parents: PackedInt32Array, model_pos: PackedVector3Array) -> void:
	for i in sk.get_bone_count():
		var par := parents[i]
		if par < 0:
			sk.set_bone_rest(i, Transform3D(Basis(Vector3.UP, PI), Vector3(-model_pos[i].x, model_pos[i].y, -model_pos[i].z)))
		else:
			sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, model_pos[i] - model_pos[par]))
	sk.reset_bone_poses()


## Global pose of a bone in skeleton space, composed by hand (the skeleton's own cache is only refreshed inside the tree, on the next frame).
static func _global_pose(sk: Skeleton3D, bone: int) -> Transform3D:
	var x := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		x = sk.get_bone_pose(b) * x
		b = sk.get_bone_parent(b)
	return x


static func _model_pos(sk: Skeleton3D, bone: int) -> Vector3:
	var p := sk.get_bone_global_rest(bone).origin
	return Vector3(-p.x, p.y, -p.z)


static func _frame(dir: Vector3, pole: Vector3) -> Basis:
	var x := (pole - dir * pole.dot(dir)).normalized()
	return Basis(x, dir, x.cross(dir))


## Two-bone IK of both arms from the T pose onto the grips (the hand bone origin = the wrist reaches `wrist_r` / `wrist_l`, model space); poses UpperArm, ForeArm and Hand.
static func _aim_arms(sk: Skeleton3D, wrist_r: Vector3, wrist_l: Vector3) -> void:
	for right in [false, true]:
		var out := 1.0 if right else -1.0                        # +X is the character's right
		var ui := sk.find_bone("UpperArmR" if right else "UpperArmL")
		var fi := sk.find_bone("ForeArmR" if right else "ForeArmL")
		var hi := sk.find_bone("hand_r" if right else "hand_l")
		var s := _model_pos(sk, ui)
		var e0 := _model_pos(sk, fi)
		var w0 := _model_pos(sk, hi)
		var l1 := (e0 - s).length()
		var l2 := (w0 - e0).length()
		var n := (wrist_r if right else wrist_l) - s
		var dist := clampf(n.length(), absf(l1 - l2) + 0.02, (l1 + l2) * 0.995)
		var u := n.normalized()
		var aa := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
		var h := sqrt(maxf(l1 * l1 - aa * aa, 0.0))
		var pole0 := Vector3(out * ELBOW_OUT, -1.0, ELBOW_BACK).normalized()
		var p := (pole0 - u * pole0.dot(u)).normalized()
		var e := s + u * aa + p * h
		var w := s + u * dist
		var ua := (e - s) / l1
		var fa := (w - e) / maxf((w - e).length(), 0.0001)
		var ua0 := (e0 - s) / l1
		var fa0 := (w0 - e0) / l2
		var r_up := _frame(ua, p) * _frame(ua0, Vector3.DOWN).inverse()
		var r_fa := _frame(fa, p) * _frame(fa0, Vector3.DOWN).inverse()
		var ru := sk.get_bone_rest(ui)
		sk.set_bone_pose(ui, Transform3D(ru.basis * r_up, ru.origin))
		var rf := sk.get_bone_rest(fi)
		sk.set_bone_pose(fi, Transform3D(rf.basis * (r_up.inverse() * r_fa), rf.origin))
		var rh := sk.get_bone_rest(hi)
		sk.set_bone_pose(hi, Transform3D(rh.basis * Basis(Vector3(out, 0.0, 0.0), out * (HAND_ROLL_R if right else HAND_ROLL_L)), rh.origin))


## Linear blend skinning on the CPU: the piece's vertices, normals and tangents carried by the bone matrices `mats` (pose * bind); vertices on bones that did not move are left alone.
static func _bake(c: Dictionary, mats: Array[Transform3D]) -> void:
	var moved := PackedByteArray()
	moved.resize(mats.size())
	for i in mats.size():
		var m := mats[i]
		moved[i] = 0 if (m.origin.length_squared() < 1e-10 and m.basis.is_equal_approx(Basis.IDENTITY)) else 1
	var v: PackedVector3Array = c["v"]
	var nrm: PackedVector3Array = c["n"]
	var tan: PackedFloat32Array = c["t"]
	var bones: PackedInt32Array = c["bones"]
	var weights: PackedFloat32Array = c["weights"]
	for i in v.size():
		var any := false
		for k in 4:
			if weights[i * 4 + k] > 0.0 and moved[bones[i * 4 + k]] == 1:
				any = true
		if not any:
			continue
		var pv := Vector3.ZERO
		var pn := Vector3.ZERO
		var pt := Vector3.ZERO
		var t0 := Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])
		for k in 4:
			var w := weights[i * 4 + k]
			if w <= 0.0:
				continue
			var m := mats[bones[i * 4 + k]]
			pv += (m * v[i]) * w
			pn += (m.basis * nrm[i]) * w
			pt += (m.basis * t0) * w
		v[i] = pv
		nrm[i] = pn.normalized()
		var tn := pt.normalized()
		tan[i * 4] = tn.x
		tan[i * 4 + 1] = tn.y
		tan[i * 4 + 2] = tn.z
	c["v"] = v
	c["n"] = nrm
	c["t"] = tan


static func _hair_mode(mi: MeshInstance3D) -> int:
	var m := mi.mesh.surface_get_material(0) as BaseMaterial3D
	if m != null and m.albedo_texture != null and m.albedo_texture.resource_path.contains("hair2"):
		return MODE_HAIR2
	return MODE_HAIR1


## One mesh piece in the merged layout: skin bind numbers mapped to the body skeleton's bone numbers (by bone name), at most four influences per vertex.
static func _piece(mi: MeshInstance3D, name_to_idx: Dictionary) -> Dictionary:
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n := v.size()
	var bones_in: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights_in: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := maxi(bones_in.size() / maxi(n, 1), 1)
	var map := PackedInt32Array()
	var skin := mi.skin
	for b in skin.get_bind_count():
		var nm := String(skin.get_bind_name(b))
		map.append(int(name_to_idx[nm]) if name_to_idx.has(nm) else maxi(skin.get_bind_bone(b), 0))
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(n * 4)
	weights.resize(n * 4)
	for i in n:
		var sum := 0.0
		for k in mini(per, 4):
			sum += weights_in[i * per + k]
		var inv := 1.0 / sum if sum > 0.0001 else 1.0
		for k in 4:
			if k < per:
				var bi := bones_in[i * per + k]
				bones[i * 4 + k] = map[bi] if bi < map.size() else 0
				weights[i * 4 + k] = weights_in[i * per + k] * inv
	var tangents: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	if tangents.size() != n * 4:
		tangents = PackedFloat32Array()
		for i in n:
			tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if uv.size() != n:
		uv = PackedVector2Array()
		uv.resize(n)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	return {"v": v, "n": arr[Mesh.ARRAY_NORMAL], "t": tangents, "uv": uv, "bones": bones, "weights": weights, "idx": idx, "mode": MODE_SKIN, "suit": PackedFloat32Array(), "lod": 0}


## Per vertex: how much of the weight sits on bones the suit covers.
static func _suit_weights(c: Dictionary, exposed: PackedByteArray) -> PackedFloat32Array:
	var bones: PackedInt32Array = c["bones"]
	var weights: PackedFloat32Array = c["weights"]
	var n := bones.size() / 4
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		for k in 4:
			var b := bones[i * 4 + k]
			if b < exposed.size() and exposed[b] == 0:
				s += weights[i * 4 + k]
		out[i] = clampf(s, 0.0, 1.0)
	return out


static func _tris(c: Dictionary) -> int:
	return (c["idx"] as PackedInt32Array).size() / 3


## Keeps the sum of triangles within `budget`: the largest piece other than the body loses one LOD level at a time (the body last).
static func _fit(comps: Array, budget: int) -> int:
	for guard in 24:
		var total := 0
		for c: Dictionary in comps:
			total += _tris(c)
		if total <= budget:
			return total
		var pick := -1
		var most := 0
		for i in comps.size():
			var c: Dictionary = comps[i]
			if int(c["lod"]) >= 3 or int(c["mode"]) == MODE_SKIN or int(c["mode"]) == MODE_GEAR:
				continue
			if _tris(c) > most:
				most = _tris(c)
				pick = i
		if pick < 0:
			for i in comps.size():
				if int(comps[i]["mode"]) == MODE_SKIN and int(comps[i]["lod"]) < 3:
					pick = i
		if pick < 0:                                   # last resort (tight mid-LOD budgets): the carbine loses detail too
			for i in comps.size():
				if int(comps[i]["mode"]) == MODE_GEAR and int(comps[i]["lod"]) < 3:
					pick = i
		if pick < 0:
			return total
		_reduce(comps[pick])
	var t := 0
	for c: Dictionary in comps:
		t += _tris(c)
	return t


static func _reduce(c: Dictionary) -> void:
	var im := ImporterMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = c["v"]
	arr[Mesh.ARRAY_NORMAL] = c["n"]
	arr[Mesh.ARRAY_TEX_UV] = c["uv"]
	arr[Mesh.ARRAY_BONES] = c["bones"]
	arr[Mesh.ARRAY_WEIGHTS] = c["weights"]
	arr[Mesh.ARRAY_INDEX] = c["idx"]
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var cnt := im.get_surface_lod_count(0)
	var lvl := int(c["lod"])
	c["lod"] = lvl + 1
	if cnt > 0:
		var best := im.get_surface_lod_indices(0, mini(lvl, cnt - 1))
		if best.size() > 0 and best.size() < (c["idx"] as PackedInt32Array).size():
			c["idx"] = best
			return
	# no LOD left: drop every other triangle of the piece's tail (only reached for tiny pieces)
	var idx: PackedInt32Array = c["idx"]
	c["idx"] = idx.slice(0, (idx.size() / 6) * 3)


static func _merge(comps: Array) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for c: Dictionary in comps:
		var base := v.size()
		var cv: PackedVector3Array = c["v"]
		v.append_array(cv)
		nrm.append_array(c["n"])
		tan.append_array(c["t"])
		uv.append_array(c["uv"])
		bones.append_array(c["bones"])
		weights.append_array(c["weights"])
		var mode := float(int(c["mode"])) / 4.0
		var suit: PackedFloat32Array = c["suit"]
		for i in cv.size():
			col.append(Color(mode, suit[i] if i < suit.size() else 0.0, 0.0, 1.0))
		for i: int in c["idx"]:
			idx.append(base + i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Static grip curl of every finger (in the model-aligned frames of the rig: the right hand points +X, the left one -X; the fingers curl down about the Z axis).
static func _curl_fingers(sk: Skeleton3D) -> void:
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		var side := 0.0
		if nm.ends_with("_l") or nm.ends_with("_leaf_l"):
			side = 1.0
		elif nm.ends_with("_r") or nm.ends_with("_leaf_r"):
			side = -1.0
		if side == 0.0:
			continue
		var base := nm.get_slice("_", 0)
		var joint := int(nm.get_slice("_", 1)) if nm.get_slice("_", 1).is_valid_int() else 0
		var curl := 0.0
		if base in ["index", "middle", "ring", "pinky"]:
			curl = [0.0, 0.55, 0.85, 0.6, 0.0][clampi(joint, 0, 4)]
		elif base == "thumb":
			curl = [0.0, 0.15, 0.35, 0.3, 0.0][clampi(joint, 0, 4)]
		if curl > 0.0:
			var r := sk.get_bone_rest(i)
			sk.set_bone_pose(i, Transform3D(r.basis * Basis(Vector3.BACK, side * curl), r.origin))


# ---- the carbine ------------------------------------------------------------------------------------------------------------------

## A compact carbine (about 200 triangles) skinned to the Rifle bone: boxes and an 8 sided barrel, in the Rig's (kit) space, the pivot at the butt.
static func _rifle_piece(rifle_bone: int) -> Dictionary:
	var arrs := _rifle_arrays()
	if not arrs.is_empty():
		return _rifle_from_arrays(arrs, rifle_bone)
	return _rifle_boxes(rifle_bone)


## The Blender rifle's surface arrays (cached), or an empty array when the model is not imported.
static var _rifle_cache: Array = []

static func _rifle_arrays() -> Array:
	if not _rifle_cache.is_empty():
		return _rifle_cache
	if not ResourceLoader.exists(RIFLE_MODEL):
		return []
	var ps := load(RIFLE_MODEL) as PackedScene
	if ps == null:
		return []
	var root := ps.instantiate()
	var mis := root.find_children("*", "MeshInstance3D", true, false)
	if not mis.is_empty():
		var mi := mis[0] as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			_rifle_cache = mi.mesh.surface_get_arrays(0)
	root.free()
	return _rifle_cache


static func _rifle_from_arrays(arr: Array, rifle_bone: int) -> Dictionary:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var count := v.size()
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in count:
			idx.append(i)
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var tan := PackedFloat32Array()
	var glow := PackedFloat32Array()
	for i in count:
		var m := v[i] + RIFLE_PIVOT
		vv.append(Vector3(-m.x, m.y, -m.z))
		nn.append(Vector3(-n[i].x, n[i].y, -n[i].z))
		bones.append_array(PackedInt32Array([rifle_bone, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		tan.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		glow.append(cols[i].g if i < cols.size() else 0.0)
	var uv := PackedVector2Array()
	uv.resize(count)
	return {"v": vv, "n": nn, "t": tan, "uv": uv, "bones": bones, "weights": weights, "idx": idx, "mode": MODE_GEAR, "suit": glow, "lod": 0}


static func _rifle_boxes(rifle_bone: int) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var parts: Array = [
		[Vector3(0.0, -0.012, -0.012), Vector3(0.05, 0.13, 0.025)],     # butt pad
		[Vector3(0.0, -0.02, -0.1), Vector3(0.04, 0.085, 0.16)],       # stock
		[Vector3(0.0, 0.012, -0.265), Vector3(0.06, 0.08, 0.22)],      # upper receiver
		[Vector3(0.0, -0.05, -0.255), Vector3(0.052, 0.05, 0.19)],     # lower receiver
		[Vector3(0.0, -0.105, -0.225), Vector3(0.036, 0.1, 0.045)],    # grip
		[Vector3(0.0, -0.1, -0.33), Vector3(0.032, 0.11, 0.058)],      # magazine
		[Vector3(0.0, -0.17, -0.335), Vector3(0.032, 0.05, 0.062)],    # magazine base
		[Vector3(0.0, 0.056, -0.27), Vector3(0.03, 0.014, 0.22)],      # top rail
		[Vector3(0.0, -0.062, -0.4), Vector3(0.03, 0.03, 0.06)],       # trigger-guard block
	]
	for p: Array in parts:
		_box(v, n, idx, p[0], p[1])
	_tube(v, n, idx, Vector3(0.0, 0.0, -0.515), 0.03, 0.25)              # handguard
	_tube(v, n, idx, Vector3(0.0, 0.092, -0.3), 0.021, 0.13)             # optic
	_tube(v, n, idx, Vector3(0.0, 0.092, -0.235), 0.027, 0.02)           # optic rear ring
	_tube(v, n, idx, Vector3(0.0, 0.092, -0.365), 0.027, 0.02)           # optic front ring
	_tube(v, n, idx, Vector3(0.0, 0.012, -0.71), 0.012, 0.2)             # barrel
	_tube(v, n, idx, Vector3(0.0, 0.012, -0.82), 0.019, 0.09)            # muzzle device
	var count := v.size()
	var pivot := RIFLE_PIVOT
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	for i in count:
		var m := v[i] + pivot                                    # model space
		vv.append(Vector3(-m.x, m.y, -m.z))                      # kit space (the Rig node turns it by half a turn)
		nn.append(Vector3(-n[i].x, n[i].y, -n[i].z))
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in count:
		bones.append_array(PackedInt32Array([rifle_bone, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	var tan := PackedFloat32Array()
	for i in count:
		tan.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	var uv := PackedVector2Array()
	uv.resize(count)
	return {"v": vv, "n": nn, "t": tan, "uv": uv, "bones": bones, "weights": weights, "idx": idx, "mode": MODE_GEAR, "suit": PackedFloat32Array(), "lod": 0}


static func _box(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var faces := [[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)], [Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
			[Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)], [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]]
	for f: Array in faces:
		var nr: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var base := v.size()
		for q: Array in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			v.append(c + (nr + a * q[0] + b * q[1]) * h)
			n.append(nr)
		for t: int in [0, 2, 1, 0, 3, 2]:                        # Godot's front faces are clockwise
			idx.append(base + t)


static func _tube(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array, c: Vector3, r: float, length: float) -> void:
	var seg := 8
	var base := v.size()
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var d := Vector3(cos(a), sin(a), 0.0)
		v.append(c + d * r + Vector3(0.0, 0.0, length * 0.5))
		n.append(d)
		v.append(c + d * r - Vector3(0.0, 0.0, length * 0.5))
		n.append(d)
	for i in seg:
		var j := (i + 1) % seg
		var a0 := base + i * 2
		var b0 := base + j * 2
		idx.append_array(PackedInt32Array([a0, b0, a0 + 1, b0, b0 + 1, a0 + 1]))
	for end in 2:                                                    # end caps (the open ends showed the inside of the tube)
		var sgn := 1.0 if end == 0 else -1.0
		var cn := Vector3(0.0, 0.0, sgn)
		var ci := v.size()
		v.append(c + Vector3(0.0, 0.0, length * 0.5 * sgn))
		n.append(cn)
		var ring := ci + 1
		for i in seg:
			var a := TAU * float(i) / float(seg)
			v.append(c + Vector3(cos(a) * r, sin(a) * r, length * 0.5 * sgn))
			n.append(cn)
		for i in seg:
			var j := (i + 1) % seg
			if end == 0:
				idx.append_array(PackedInt32Array([ci, ring + j, ring + i]))
			else:
				idx.append_array(PackedInt32Array([ci, ring + i, ring + j]))
