class_name CharacterImport
extends RefCounted
## Import pipeline of third-party rigged characters (docs: assets_incoming/README.md). Looks in res://assets_incoming/characters/<role>/ for a rigged .glb / .gltf (or an
## already imported .fbx scene), retargets it to the CharacterRig contract and gives it the quantum-realism skin; with nothing there it returns the procedural model.
##   roles        hero, enemy_<kind>, citizen_<kind>
##   retarget     bones are renamed to CharacterRig.BONE_NAMES by name mapping (Mixamo, Quaternius / Unreal style, Rigify DEF-); a missing Rifle bone is added under the right hand;
##                animation clips are renamed to ANIM_NAMES (idle walk run aim fire hit death jump) by keyword and their bone tracks follow the renamed bones
##   skin         one ShaderMaterial (assets/shaders/character_quantum.gdshader): source albedo, alien palette tint, iridescent trim; the same on every surface
##   budget       triangles per role (TRI_BUDGET): a mesh over it is rebuilt from the largest auto-LOD that fits, then LODs are generated
## Offline hard-limit decimation and bone-roll alignment: tools/blender/import_character.py. Run-time entry: instantiate(role).

const ROOT := "res://assets_incoming/characters"
const ANIM_NAMES: Array[StringName] = [&"idle", &"walk", &"run", &"aim", &"fire", &"hit", &"death", &"jump"]
const ANIM_KEYWORDS := {&"idle": ["idle", "stand", "breath"], &"walk": ["walk"], &"run": ["run", "sprint", "jog"], &"aim": ["aim", "rifle_idle", "rifleidle"],
		&"fire": ["fire", "shoot", "shot"], &"hit": ["hit", "hurt", "react", "damage"], &"death": ["death", "die", "dying"], &"jump": ["jump", "leap"]}
const TRI_BUDGET := {"hero": 18000, "enemy": 12000, "citizen": 4000}
const TARGET_HEIGHT := {"hero": 1.8, "enemy": 1.85, "citizen": 1.75}
const PALETTE := {"hero": Color(0.45, 0.8, 1.0), "enemy": Color(1.0, 0.45, 0.7), "citizen": Color(0.7, 0.75, 0.85)}
## Per-role palette tint of the imported creature kit (quantum realism: muted body, the tint carries the species colour); a role not listed uses PALETTE of its class.
const ROLE_TINT := {"enemy_alien": Color(0.45, 0.95, 0.75), "enemy_demon": Color(1.0, 0.5, 0.38), "enemy_bluedemon": Color(0.5, 0.65, 1.0)}
const FALLBACK := {"hero": "player", "enemy": "operative", "citizen": "citizen"}
const MAX_SURFACES := 4
## contract bone -> candidate base names (normalised: lower case, no prefix / side / separators), best first
const ALIASES := {
	&"Hips": ["hips", "pelvis", "hip"],
	&"Torso": ["spine2", "chest", "upperchest", "spine003", "spine03", "spine1", "spine02", "spine", "torso", "abdomen"],
	&"Head": ["head", "spine006"],
	&"UpperArm": ["upperarm", "uparm", "arm"],
	&"ForeArm": ["forearm", "lowerarm", "lowarm"],
	&"Thigh": ["upleg", "upperleg", "thigh"],
	&"Shin": ["lowerleg", "shin", "calf", "leg"],
	&"Foot": ["foot", "ankle"],
	&"Hand": ["hand", "wrist"],
}
const WEAPON_NAMES: Array[String] = ["rifle", "weapon", "gun"]


## Role class: "hero", "enemy" or "citizen" ("" when unknown).
static func role_class(role: String) -> String:
	for k in TRI_BUDGET:
		if role == k or role.begins_with(k + "_"):
			return k
	return ""


## First rigged source file of a role folder ("" when none).
static func find_source(role: String) -> String:
	var dir := "%s/%s" % [ROOT, role]
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for f in DirAccess.get_files_at(dir):
		var e := f.get_extension().to_lower()
		if e == "glb" or e == "gltf" or e == "fbx":
			return "%s/%s" % [dir, f]
	return ""


## Normalised bone name -> [base, side] ("L", "R" or "").
static func normalize(bone: String) -> Array:
	var s := bone.to_lower()
	var rx := RegEx.create_from_string("^(mixamorig\\d*|def|org|mch|armature)[:_\\-.]")
	var m := rx.search(s)
	if m:
		s = s.substr(m.get_end())
	var side := ""
	for tok in ["left", "right"]:
		if s.contains(tok):
			side = "L" if tok == "left" else "R"
			s = s.replace(tok, "")
	var sx := RegEx.create_from_string("[._\\-]([lr])$")
	var sm := sx.search(s)
	if sm:
		side = sm.get_string(1).to_upper()
		s = s.substr(0, sm.get_start())
	var cl := RegEx.create_from_string("[^a-z0-9]")
	return [cl.sub(s, "", true), side]


## Mapping contract bone name (String) -> source bone index; empty when the mandatory bones (Hips, Torso, Head, arms, legs) cannot all be found.
static func map_bones(sk: Skeleton3D) -> Dictionary:
	var norm: Array = []
	for i in sk.get_bone_count():
		norm.append(normalize(sk.get_bone_name(i)))
	var out := {}
	for key in ALIASES:
		var sides: Array = [""] if key in [&"Hips", &"Torso", &"Head"] else ["L", "R"]
		for side in sides:
			var found := -1
			for cand in ALIASES[key]:
				for i in norm.size():
					if norm[i][0] == cand and norm[i][1] == side:
						found = i
						break
				if found >= 0:
					break
			if found < 0:
				continue
			var nm: String = String(key) + side if key != &"Hand" else "Hand" + side
			out[nm] = found
	for must in ["Hips", "Torso", "Head", "UpperArmL", "ForeArmL", "UpperArmR", "ForeArmR", "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]:
		if not out.has(must):
			return {}
	return out


## Rename the mapped bones to the contract names (Hips Torso Head UpperArmL ...) and add Rifle; returns {old name: new name}. Empty when the rig cannot be mapped.
static func retarget(sk: Skeleton3D) -> Dictionary:
	var map := map_bones(sk)
	if map.is_empty():
		return {}
	var renames := {}
	var taken := {}
	for nm in map:
		taken[sk.get_bone_name(map[nm])] = true
	for nm in map:
		if nm.begins_with("Hand"):
			continue
		var idx: int = map[nm]
		var old := sk.get_bone_name(idx)
		var clash := sk.find_bone(nm)
		if clash >= 0 and clash != idx:
			sk.set_bone_name(clash, "%s_src" % nm)
		if old != nm:
			sk.set_bone_name(idx, nm)
			renames[old] = nm
	var rifle := -1
	for i in sk.get_bone_count():
		var low := sk.get_bone_name(i).to_lower()
		for w in WEAPON_NAMES:
			if low.contains(w) and rifle < 0:
				rifle = i
	if rifle >= 0 and sk.get_bone_name(rifle) != "Rifle":
		renames[sk.get_bone_name(rifle)] = "Rifle"
		sk.set_bone_name(rifle, "Rifle")
	elif rifle < 0:
		var hand: int = map.get("HandR", map["ForeArmR"] as int)
		var rb := sk.get_bone_count()
		sk.add_bone("Rifle")
		sk.set_bone_parent(rb, hand)
		sk.set_bone_rest(rb, Transform3D.IDENTITY)
		sk.reset_bone_pose(rb)
	return renames


## Canonical clip name of a source animation name ("" when it matches none).
static func canonical_anim(clip: String) -> StringName:
	var low := clip.to_lower()
	for k in ANIM_NAMES:
		for kw in ANIM_KEYWORDS[k]:
			if low.contains(kw):
				return k
	return &""


## Rename the clips of every AnimationPlayer to ANIM_NAMES (first match wins) and point their bone tracks at the renamed bones. Returns the canonical names present.
static func retarget_animations(root: Node, renames: Dictionary) -> Array[StringName]:
	var present: Array[StringName] = []
	for n in root.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var lib_src := ap.get_animation_library(&"") if ap.has_animation_library(&"") else null
		if lib_src == null:
			continue
		var lib := AnimationLibrary.new()
		for clip in lib_src.get_animation_list():
			var c := canonical_anim(String(clip))
			if c == &"" or lib.has_animation(c):
				continue
			var a := lib_src.get_animation(clip).duplicate() as Animation
			for t in a.get_track_count():
				var p := String(a.track_get_path(t))
				var colon := p.find(":")
				if colon >= 0 and renames.has(p.substr(colon + 1)):
					a.track_set_path(t, NodePath(p.substr(0, colon + 1) + String(renames[p.substr(colon + 1)])))
			lib.add_animation(c, a)
			present.append(c)
		ap.remove_animation_library(&"")
		ap.add_animation_library(&"", lib)
	return present


static func tri_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


## Mesh within `budget` triangles with auto-LODs: when over budget the surfaces are rebuilt on the largest generated LOD that fits. `info` gets tris, lods, over (bool).
static func limit_mesh(mesh: ArrayMesh, budget: int, info: Dictionary) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {}, mesh.surface_get_material(s), mesh.surface_get_name(s))
	var total := tri_count(mesh)
	info["tris_source"] = total
	if total > budget:
		im.generate_lods(25.0, 60.0, [])
		var lod_i := 0
		var best := PackedInt32Array()
		var found := false
		for l in range(im.get_surface_lod_count(0) - 1, -1, -1):        # scan from the finest LOD to the coarsest
			var sum := 0
			for s in im.get_surface_count():
				sum += im.get_surface_lod_indices(s, l).size() / 3 if l < im.get_surface_lod_count(s) else (im.get_surface_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if sum <= budget:
				lod_i = l
				found = true
				break
		if not found:
			lod_i = maxi(im.get_surface_lod_count(0) - 1, 0)
		var rebuilt := ImporterMesh.new()
		for s in im.get_surface_count():
			var arr := im.get_surface_arrays(s)
			if im.get_surface_lod_count(s) > lod_i:
				arr[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(s, lod_i)
			rebuilt.add_surface(im.get_surface_primitive_type(s), arr, [], {}, im.get_surface_material(s), im.get_surface_name(s))
		im = rebuilt
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	info["tris"] = tri_count(out)
	info["over"] = int(info["tris"]) > budget
	info["lods"] = im.get_surface_lod_count(0) if im.get_surface_count() > 0 else 0
	return out


## The quantum-realism skin for a role class; takes the albedo texture and colour of the source material when it has one.
static func make_material(cls: String, source: Material, seed_value: float, role := "") -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/character_quantum.gdshader")
	m.set_shader_parameter(&"palette_tint", ROLE_TINT.get(role, PALETTE.get(cls, Color.WHITE)))
	m.set_shader_parameter(&"film_seed", seed_value)
	var sm := source as BaseMaterial3D
	if sm != null:
		m.set_shader_parameter(&"albedo_color", sm.albedo_color)
		if sm.albedo_texture != null:
			m.set_shader_parameter(&"albedo_tex", sm.albedo_texture)
		m.set_shader_parameter(&"roughness_v", sm.roughness)
	return m


## Process an imported scene (retarget, skin, triangle limit, height). Returns {root, ok, info}; root is null when the rig cannot be mapped.
static func process(scene: Node3D, role: String) -> Dictionary:
	var cls := role_class(role)
	var info := {"role": role, "class": cls}
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty() or cls == "":
		return {"root": null, "ok": false, "info": info}
	var sk := sks[0] as Skeleton3D
	var renames := retarget(sk)
	if renames.is_empty() and not CharacterRig.has_rig(scene):
		return {"root": null, "ok": false, "info": info}
	info["renamed"] = renames.size()
	info["anims"] = retarget_animations(scene, renames)
	var seed_value := fposmod(float(hash(role)) * 0.000137, 1.0)
	var tris := 0
	var surfaces := 0
	var body: MeshInstance3D
	for c in sk.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var minfo := {}
		var lim := limit_mesh(mi.mesh as ArrayMesh, int(TRI_BUDGET[cls]), minfo)
		var src_mat: Material = mi.get_active_material(0)
		mi.mesh = lim
		for s in lim.get_surface_count():
			lim.surface_set_material(s, make_material(cls, src_mat, seed_value, role))
		tris += int(minfo["tris"])
		surfaces += lim.get_surface_count()
		info["over"] = bool(info.get("over", false)) or bool(minfo["over"])
		info["lods"] = minfo["lods"]
		if body == null:
			body = mi
	if body == null:
		return {"root": null, "ok": false, "info": info}
	body.name = "Body"
	info["tris"] = tris
	info["surfaces"] = surfaces
	var wrapper := Node3D.new()
	wrapper.name = "ImportedCharacter"
	wrapper.add_child(scene)
	scene.rotation.y = PI                       # glTF characters face +Z, the game's front is -Z
	var aabb := body.mesh.get_aabb()
	var h := aabb.size.y * CharacterRig.chain_to(body, scene).basis.get_scale().y
	if h > 0.01:
		var k := float(TARGET_HEIGHT[cls]) / h
		scene.scale = Vector3.ONE * k
		info["scale"] = k
	info["ok"] = surfaces <= MAX_SURFACES
	return {"root": wrapper, "ok": info["ok"], "info": info}


## Load and process a file path; null on any failure.
static func load_file(path: String, role: String) -> Dictionary:
	var scene: Node3D
	if path.get_extension().to_lower() == "fbx":
		var ps := load(path) as PackedScene if ResourceLoader.exists(path) else null
		scene = ps.instantiate() as Node3D if ps else null
	else:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(path, st) == OK:
			scene = doc.generate_scene(st) as Node3D
	if scene == null:
		return {"root": null, "ok": false, "info": {"role": role}}
	return process(scene, role)


## The model for a role: the imported one when its folder holds a usable rigged file, else the procedural model (Game.load_model), else null.
static func instantiate(role: String) -> Node3D:
	var src := find_source(role)
	if src != "":
		var r := load_file(src, role)
		if r["root"] != null:
			return r["root"]
		push_warning("CharacterImport: %s unusable, using the procedural model" % src)
	var cls := role_class(role)
	if cls == "":
		return null
	return Game.load_model(FALLBACK[cls])
