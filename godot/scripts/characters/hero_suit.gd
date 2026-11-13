class_name HeroSuit
extends RefCounted
## The hero's armour kit (wave 112, hero look v3): assets/models/hero_suit.glb, built by tools/blender/model_hero_suit.py. One mesh node per part; the glTF extras of a node carry
##   bone  the source skeleton bone the part is rigidly weighted to  ("chain:Sec1,Sec2,Sec3" for the cloak: weights by height)
##   kind  shader palette slot (KIND_*)       zone  glow zone (HeroGlow.ZONE_*)       sets  the suit sets the part belongs to
## `pieces(set_id, bone_index_by_name)` turns the parts of one suit set into the component dictionaries of HeroCharacter (kit space, rigid bone weights, gear mode), which it
## merges into the hero's single surface: the whole suit is ONE draw call. Everything is cached after the first load (a look change rebuilds the hero without reading the file again).
##
## Hardpoints for other waves (model space, x right, y up, -z forward): `hardpoint(name)`: &"wing_l" &"wing_r" (the wing mounts of the flight suit), &"emit_l" &"emit_r" (the wrist
## emitters, where the quantum snakes leave), &"core" (the chest core), &"pack" (the back unit), &"head".

const MODEL := "res://assets/models/hero_suit.glb"
const TEX_DIR := "res://assets/textures"
const SETS: Array[StringName] = [&"vanguard", &"stealth", &"assault", &"flight"]
const DEFAULT_SET := &"vanguard"
## Palette slots (COLOR.b x 16 of the merged mesh). 0..5 are the procedural boxes of the old gear.
const KIND_PLATE := 6.0
const KIND_ACCENT := 7.0
const KIND_DARK := 8.0
const KIND_FABRIC := 9.0
const KIND_GLOW := 10.0
const KIND_CANVAS := 11.0
const KIND_GOLD := 12.0
const KIND_CLOTH := 13.0
const HARDPOINTS := {
	&"emit_r": Vector3(0.705, 1.455, -0.065), &"emit_l": Vector3(-0.705, 1.455, -0.065),
	&"core": Vector3(0.0, 1.335, -0.152), &"pack": Vector3(0.0, 1.285, 0.195),
	&"wing_r": Vector3(0.11, 1.40, 0.2), &"wing_l": Vector3(-0.11, 1.40, 0.2), &"head": Vector3(0.0, 1.70, -0.02),
}

static var _loaded := false
static var _parts: Array[Dictionary] = []


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


static func is_set(id: StringName) -> bool:
	return SETS.has(id)


## The hardpoint transform origin of a named mounting place (model space), or Vector3.ZERO.
static func hardpoint(name: StringName) -> Vector3:
	return HARDPOINTS.get(name, Vector3.ZERO)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not available():
		return
	var ps := load(MODEL) as PackedScene
	if ps == null:
		return
	var root := ps.instantiate()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var ex: Variant = mi.get_meta("extras") if mi.has_meta("extras") else null
		if not (ex is Dictionary):
			continue
		var d := ex as Dictionary
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for i in v.size():
					idx.append(i)
			# glTF model space (x right, y up, -z forward) -> the kit space the hero mesh is built in (the Rig node turns it by a half turn): (-x, y, -z)
			var kv := PackedVector3Array()
			var kn := PackedVector3Array()
			for i in v.size():
				var p := v[i]
				kv.append(Vector3(-p.x, p.y, -p.z))
				var q := nrm[i] if i < nrm.size() else Vector3.UP
				kn.append(Vector3(-q.x, q.y, -q.z))
			var kt := PackedFloat32Array()
			for i in v.size():
				if tan.size() == v.size() * 4:
					kt.append_array(PackedFloat32Array([-tan[i * 4], tan[i * 4 + 1], -tan[i * 4 + 2], tan[i * 4 + 3]]))
				else:
					kt.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
			if uv.size() != v.size():
				uv = PackedVector2Array()
				uv.resize(v.size())
			var sets := PackedStringArray(String(d.get("sets", "")).split(",", false))
			_parts.append({"name": String(mi.name), "bone": String(d.get("bone", "spine_02")), "kind": float(d.get("kind", KIND_PLATE)), "zone": int(d.get("zone", 0)), "sets": sets,
					"v": kv, "n": kn, "t": kt, "uv": uv, "idx": idx, "chain_pos": String(d.get("chain_pos", "")), "chain_parent": String(d.get("chain_parent", "spine_02"))})
	root.free()


## The cloak chain of a suit set: {"parent": source bone name, "pos": PackedVector3Array of the Sec1..Sec3 pivots in MODEL space}, or {} when the set has no cloth part.
## HeroCharacter adds the three bones (named Sec1 Sec2 Sec3, the names CharacterRig drives with its cloak springs) under `parent`.
static func chain(set_id: StringName) -> Dictionary:
	_load()
	var key := String(set_id if SETS.has(set_id) else DEFAULT_SET)
	for p: Dictionary in _parts:
		if (p["sets"] as PackedStringArray).has(key) and String(p["chain_pos"]) != "":
			var pos := PackedVector3Array()
			for tri: String in String(p["chain_pos"]).split(";", false):
				var f := tri.split(",", false)
				if f.size() == 3:
					pos.append(Vector3(float(f[0]), float(f[1]), float(f[2])))
			if pos.size() == 3:
				return {"parent": String(p["chain_parent"]), "pos": pos}
	return {}


## Number of parts in the kit and in one suit set (tests).
static func part_count(set_id: StringName = &"") -> int:
	_load()
	if set_id == &"":
		return _parts.size()
	var n := 0
	for p: Dictionary in _parts:
		if (p["sets"] as PackedStringArray).has(String(set_id)):
			n += 1
	return n


static func triangles(set_id: StringName) -> int:
	_load()
	var n := 0
	for p: Dictionary in _parts:
		if (p["sets"] as PackedStringArray).has(String(set_id)):
			n += (p["idx"] as PackedInt32Array).size() / 3
	return n


## The component dictionaries of HeroCharacter for one suit set. `bones`: source bone name -> skeleton index. Parts whose bone is missing are skipped.
static func pieces(set_id: StringName, bones: Dictionary) -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	var key := String(set_id if SETS.has(set_id) else DEFAULT_SET)
	for p: Dictionary in _parts:
		if not (p["sets"] as PackedStringArray).has(key):
			continue
		var bname: String = p["bone"]
		var chain_names := PackedStringArray()
		var bi := -1
		if bname.begins_with("chain:"):
			chain_names = PackedStringArray(bname.substr(6).split(",", false))
			var ok := chain_names.size() == 3
			for cn in chain_names:
				ok = ok and bones.has(cn)
			if not ok:
				continue
			bi = int(bones[chain_names[0]])
		else:
			bi = int(bones.get(bname, -1))
		if bi < 0:
			continue
		var v: PackedVector3Array = (p["v"] as PackedVector3Array).duplicate()
		var n := v.size()
		var bn := PackedInt32Array()
		var wt := PackedFloat32Array()
		bn.resize(n * 4)
		wt.resize(n * 4)
		var kind := PackedFloat32Array()
		var pc := PackedFloat32Array()
		kind.resize(n)
		pc.resize(n)
		var ys := PackedFloat32Array()
		var cpos := PackedVector3Array()
		if chain_names.size() == 3:
			for tri: String in String(p["chain_pos"]).split(";", false):
				var f := tri.split(",", false)
				ys.append(float(f[1]))
		for i in n:
			if ys.size() == 3:                                  # the cloak: weights by height along the three pivots (kit space y = model space y)
				var y := v[i].y
				var b0 := int(bones[chain_names[0]])
				var b1 := int(bones[chain_names[1]])
				var b2 := int(bones[chain_names[2]])
				if y >= ys[0]:
					bn[i * 4] = b0
					wt[i * 4] = 1.0
				elif y >= ys[1]:
					var t := (ys[0] - y) / maxf(ys[0] - ys[1], 0.001)
					bn[i * 4] = b0
					bn[i * 4 + 1] = b1
					wt[i * 4] = 1.0 - t
					wt[i * 4 + 1] = t
				elif y >= ys[2]:
					var t2 := (ys[1] - y) / maxf(ys[1] - ys[2], 0.001)
					bn[i * 4] = b1
					bn[i * 4 + 1] = b2
					wt[i * 4] = 1.0 - t2
					wt[i * 4 + 1] = t2
				else:
					bn[i * 4] = b2
					wt[i * 4] = 1.0
			else:
				bn[i * 4] = bi
				wt[i * 4] = 1.0
			kind[i] = float(p["kind"]) / HeroCharacter.KIND_STEPS
			pc[i] = path_coord(v[i], int(p["zone"]))
		out.append({"v": v, "n": (p["n"] as PackedVector3Array).duplicate(), "t": (p["t"] as PackedFloat32Array).duplicate(), "uv": p["uv"], "bones": bn, "weights": wt,
				"idx": (p["idx"] as PackedInt32Array).duplicate(), "mode": HeroCharacter.MODE_GEAR, "suit": PackedFloat32Array(), "kind": kind, "lod": 0,
				"zone": int(p["zone"]), "pc": pc, "name": p["name"]})
	return out


## How far along the energy circuit from the chest core (0) over the shoulders and arms to the fingertips (1), and down the legs, a bind-pose point (KIT space) lies: the travelling
## wave of the FLOW glow runs along this coordinate.
static func path_coord(kit: Vector3, zone: int) -> float:
	var ax := absf(kit.x)
	match zone:
		HeroGlow.ZONE_ARMS, HeroGlow.ZONE_HANDS:
			return clampf(0.2 + 0.8 * (ax - 0.12) / 0.82, 0.0, 1.0)
		HeroGlow.ZONE_LEGS:
			return clampf(0.15 + 0.85 * (1.0 - kit.y / 1.0), 0.0, 1.0)
		HeroGlow.ZONE_WINGS:
			return clampf(0.1 + 0.9 * (kit.y - 1.05) / 0.75, 0.0, 1.0)
		HeroGlow.ZONE_HEAD:
			return 0.0
	return clampf(Vector2(ax, kit.y - 1.3).length() / 0.35 * 0.2, 0.0, 0.2)
