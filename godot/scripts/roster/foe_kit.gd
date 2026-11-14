class_name FoeKit
extends RefCounted
## The enemy armour kit (wave 113, enemy look v3): assets/models/enemy_kit.glb, built by tools/blender/model_enemy_kit.py. One mesh node per part; the glTF extras of a node carry
##   bone   the source skeleton bone the part is rigidly weighted to  ("Rifle": the weapon bone, "chain:Sec1,Sec2,Sec3": cloth that trails the motion, weights by height)
##   kind   shader palette slot (KIND_*)    zone  glow zone (ZONE_*)    looks  the look ids the part belongs to ("*" = every look)    lod  2 = keep up to 80 m, 1 = up to 45 m, 0 = detail (near only)
## `pieces(look, bones, lod)` turns the parts of one look into the component dictionaries of HeroCharacter (kit space, rigid bone weights, gear mode), which it merges into the enemy's single
## skinned surface: the whole armour is ONE draw call. Vertex data of every part: UV.x = baked ambient occlusion, UV.y = convex edge wear (tools/blender/enemykit/lib.py), UV2.x = pip index
## (health pips). Everything is cached after the first load.

const MODEL := "res://assets/models/enemy_kit.glb"
const KIND_PLATE_A := 1.0
const KIND_PLATE_B := 2.0
const KIND_TRIM := 3.0
const KIND_DARK := 4.0
const KIND_RUBBER := 5.0
const KIND_FABRIC_A := 6.0
const KIND_FABRIC_B := 7.0
const KIND_GLASS := 8.0
const KIND_GLOW := 9.0
const KIND_BRASS := 10.0
const KIND_CLOTH := 11.0
const KIND_MARK := 12.0
const KIND_HAZARD := 13.0
const KIND_STEEL := 14.0
const KIND_POLY := 15.0
const ZONE_NONE := 0
const ZONE_VISOR := 1
const ZONE_WEAK := 2
const ZONE_PIPS := 3
const ZONE_TELL := 4
const ZONE_TRIM := 5
const ZONE_JET := 6
## Parts that keep the silhouette at 45 to 80 m (lod 2) and at 14 to 45 m (lod 1); everything else is detail for the near mesh. Matched on the part name prefix.
const LOD2 := ["helm_shell", "helm_visor", "hood", "hat_crown", "hat_brim", "cap_top", "beanie", "pack", "rocket_tube", "rack", "shield_frame", "cloak_hump", "vest_plate", "auth_chest",
	"turret_head", "pauldron", "boot_foot", "officer_jacket", "coat_tails", "sniper_cape", "helm_flare", "helm_mask", "helm_jaw", "radio_whip", "charges_ram", "cloak_tails"]
const LOD1 := ["helm_", "hood_", "cap_", "belt", "collar", "vest_", "knee_pad", "vambrace", "shield_", "pack_", "rocket_", "turret_", "rack_", "cloak_", "charges", "epaulette", "sash",
	"bandolier", "auth_back", "auth_ridge", "auth_stripe", "ammo_box", "wrist_", "baton", "thigh_plate", "boot_shaft", "glove", "goggle"]

static var _loaded := false
static var _parts: Array[Dictionary] = []
static var _looks := {}


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


static func _lod_of(part_name: String) -> int:
	for p: String in LOD2:
		if part_name.begins_with(p):
			return 2
	for p: String in LOD1:
		if part_name.begins_with(p):
			return 1
	return 0


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
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for i in v.size():
					idx.append(i)
			# glTF model space (x right, y up, -z forward) -> the kit space the hero mesh is built in (the Rig node turns it by a half turn): (-x, y, -z)
			var kv := PackedVector3Array()
			var kn := PackedVector3Array()
			var kt := PackedFloat32Array()
			kt.resize(v.size() * 4)
			for i in v.size():
				var p := v[i]
				kv.append(Vector3(-p.x, p.y, -p.z))
				var q := nrm[i] if i < nrm.size() else Vector3.UP
				kn.append(Vector3(-q.x, q.y, -q.z))
				kt[i * 4] = 1.0
				kt[i * 4 + 3] = 1.0
			if uv.size() != v.size():
				uv = PackedVector2Array()
				uv.resize(v.size())
				uv.fill(Vector2(1.0, 0.0))
			var looks := PackedStringArray(String(d.get("looks", "*")).split(",", false))
			var part := {"name": String(mi.name).get_slice("__", 1) if String(mi.name).contains("__") else String(mi.name), "bone": String(d.get("bone", "spine_02")),
					"kind": float(d.get("kind", KIND_PLATE_A)), "zone": int(d.get("zone", 0)), "looks": looks, "v": kv, "n": kn, "t": kt, "uv": uv, "idx": idx,
					"chain_pos": String(d.get("chain_pos", "")), "chain_parent": String(d.get("chain_parent", "spine_02"))}
			part["lod"] = _lod_of(String(part["name"]))
			_parts.append(part)
			for l: String in looks:
				if l != "*":
					_looks[StringName(l)] = true
	root.free()


static func looks() -> Array[StringName]:
	_load()
	var out: Array[StringName] = []
	for k: StringName in _looks:
		out.append(k)
	out.sort()
	return out


static func has_look(look: StringName) -> bool:
	_load()
	return _looks.has(look)


static func _in_look(p: Dictionary, look: StringName) -> bool:
	var ls: PackedStringArray = p["looks"]
	return ls.has("*") or ls.has(String(look))


## Number of parts and triangles of one look (tests).
static func part_count(look: StringName) -> int:
	_load()
	var n := 0
	for p: Dictionary in _parts:
		if _in_look(p, look):
			n += 1
	return n


static func triangles(look: StringName, lod := 0) -> int:
	_load()
	var n := 0
	for p: Dictionary in _parts:
		if _in_look(p, look) and int(p["lod"]) >= lod:
			n += (p["idx"] as PackedInt32Array).size() / 3
	return n


## The cloth chain of a look: {"parent": source bone name, "pos": PackedVector3Array of the Sec1..Sec3 pivots in MODEL space}, or {} when the look has no cloth on the chain.
static func chain(look: StringName) -> Dictionary:
	_load()
	for p: Dictionary in _parts:
		if _in_look(p, look) and String(p["chain_pos"]) != "":
			var pos := PackedVector3Array()
			for tri: String in String(p["chain_pos"]).split(";", false):
				var f := tri.split(",", false)
				if f.size() == 3:
					pos.append(Vector3(float(f[0]), float(f[1]), float(f[2])))
			if pos.size() == 3:
				return {"parent": String(p["chain_parent"]), "pos": pos}
	return {}


## The component dictionaries of HeroCharacter for one look. `bones`: source bone name -> skeleton index (plus "Rifle"). `lod`: 0 every part, 1 the parts kept at mid distance, 2 the silhouette only.
static func pieces(look: StringName, bones: Dictionary, lod := 0) -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for p: Dictionary in _parts:
		if not _in_look(p, look) or int(p["lod"]) < lod:
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
		if chain_names.size() == 3:
			for tri: String in String(p["chain_pos"]).split(";", false):
				var f := tri.split(",", false)
				ys.append(float(f[1]))
		var is_pip := int(p["zone"]) == ZONE_PIPS
		var pitch := 0.026 if String(p["name"]) == "pips_front" else 0.03
		for i in n:
			if ys.size() == 3:                                  # cloth: weights by height along the three pivots (kit space y = model space y)
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
			if is_pip:
				pc[i] = clampf((roundf(v[i].x / pitch + 2.0) + 0.5) / 5.0, 0.0, 1.0)
		out.append({"v": v, "n": (p["n"] as PackedVector3Array).duplicate(), "t": (p["t"] as PackedFloat32Array).duplicate(), "uv": p["uv"], "bones": bn, "weights": wt,
				"idx": (p["idx"] as PackedInt32Array).duplicate(), "mode": HeroCharacter.MODE_GEAR, "suit": PackedFloat32Array(), "kind": kind, "lod": 0,
				"zone": int(p["zone"]), "pc": pc, "name": p["name"]})
	return out
