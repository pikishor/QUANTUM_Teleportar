class_name FoeArms
extends RefCounted
## ONE place that puts a weapon into an enemy's hands, by weapon id (wave 113, enemy look v3). It reads the weapon registry of scripts/player (WeaponModels.mesh / spec / grip_offsets / muzzle_shift,
## WeaponDefs class), so the models of every later weapon wave swap in by themselves: an enemy never owns a gun model of its own.
##   pieces(id, rifle_bone)   the weapon as component dictionaries of HeroCharacter (skinned to the Rifle bone, split by material kind), merged into the body's single surface: no extra draw call
##   setup(rig, hanim, id)    the rig's grip offsets (both hands go to this weapon's grips), the upper-body mount class (rifle / pistol / shotgun / launcher) and the muzzle shift; returns the muzzle info
##   mount_class(id)          HumanoidAnim.MOUNTS key of a weapon id
##   attach(look_id, id)      the cache key of a body built for (look, weapon): FoeHuman rebuilds only when one of them changes
## The vertex colours of a weapon mesh (RGB paint, A = glow) are sorted into the enemy palette kinds: glow, brass, black polymer, gunmetal, steel.

const SCALE := Vector3(1.3, 1.3, 1.1)
const HEAVY_SCALE := Vector3(1.15, 1.15, 1.1)
const HEAVY: Array[StringName] = [&"rocket", &"minigun", &"lmg", &"amr", &"flame", &"qcollapse", &"gravity", &"lance", &"rail", &"xbow", &"ebeam", &"epod", &"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker"]
const MUZZLE_AT := Vector3(0.0, 0.01, -0.86)

static var _cache := {}


static func has_weapon(id: StringName) -> bool:
	return WeaponDefs.DEFS.has(id)


## The upper-body mount class (HumanoidAnim.MOUNTS) of a weapon id.
static func mount_class(id: StringName) -> StringName:
	var cls: StringName = StringName(WeaponDefs.CLASS_OF.get(id, &"rifle"))
	match cls:
		&"pistol":
			return &"pistol"
		&"shotgun":
			return &"shotgun"
		&"heavy", &"blast":
			return &"launcher"
	return &"rifle"


static func attach(look_id: StringName, id: StringName) -> String:
	return "%s/%s" % [look_id, id]


## Grips and muzzle of a weapon id for a rig: sets `grip_off_l/r`, tells the upper-body state machine which mount it is, and returns {muzzle_shift, mount, reach}.
static func setup(rig: CharacterRig, hanim: HumanoidAnim, id: StringName) -> Dictionary:
	var wid := id if has_weapon(id) else &"carbine"
	var g := WeaponModels.grip_offsets(wid)
	if rig != null:
		rig.grip_off_l = g[0]
		rig.grip_off_r = g[1]
	var mc := mount_class(wid)
	if hanim != null:
		hanim.set_weapon(mc)
	return {"muzzle_shift": WeaponModels.muzzle_shift(wid), "mount": mc, "reach": float(WeaponModels.spec(wid).get("reach", 0.86))}


const TARGET_TRIS := [700, 320, 130]       ## triangles of the weapon in the near / mid / far mesh (the open-source models have 1.3-2.4k)


## The weapon as component dictionaries (kit space, skinned to `rifle_bone`), cached per id; `lod` 0 near, 1 mid, 2 far (the weapon is simplified to TARGET_TRIS[lod]).
static func pieces(id: StringName, rifle_bone: int, lod := 0) -> Array[Dictionary]:
	var wid := id if has_weapon(id) else &"carbine"
	var raw: Array = _raw(wid)
	var out: Array[Dictionary] = []
	for r: Dictionary in raw:
		var n := (r["v"] as PackedVector3Array).size()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(n * 4)
		weights.resize(n * 4)
		for i in n:
			bones[i * 4] = rifle_bone
			weights[i * 4] = 1.0
		var kind := PackedFloat32Array()
		kind.resize(n)
		kind.fill(float(r["kind"]) / HeroCharacter.KIND_STEPS)
		out.append({"v": (r["v"] as PackedVector3Array).duplicate(), "n": (r["n"] as PackedVector3Array).duplicate(), "t": (r["t"] as PackedFloat32Array).duplicate(), "uv": r["uv"], "bones": bones,
				"weights": weights, "idx": (r["idx"] as PackedInt32Array).duplicate(), "mode": HeroCharacter.MODE_GEAR, "suit": PackedFloat32Array(), "kind": kind, "lod": 0,
				"zone": int(r["zone"]), "pc": PackedFloat32Array(), "name": "weapon_" + String(id)})
	var target: int = TARGET_TRIS[clampi(lod, 0, 2)]
	for guard in 6:
		var total := 0
		var biggest := -1
		var most := 0
		for i in out.size():
			var tc := (out[i]["idx"] as PackedInt32Array).size() / 3
			total += tc
			if tc > most and int(out[i]["lod"]) < 3:
				most = tc
				biggest = i
		if total <= target or biggest < 0:
			break
		HeroCharacter._reduce(out[biggest])
	return out


static func _kind_of(c: Color) -> int:
	if c.a > 0.2:
		return int(FoeKit.KIND_GLOW)
	var lum := (c.r + c.g + c.b) / 3.0
	if c.r > c.g * 1.2 and c.r > c.b * 1.5 and lum > 0.1:
		return int(FoeKit.KIND_BRASS)
	if lum < 0.075:
		return int(FoeKit.KIND_POLY)
	if lum < 0.2:
		return int(FoeKit.KIND_DARK)
	return int(FoeKit.KIND_STEEL)


## Triangles of the weapon sorted by kind: [{kind, zone, v, n, t, uv, idx}] in kit space (the Rifle bone frame at rest), cached.
static func _raw(id: StringName) -> Array:
	if _cache.has(id):
		return _cache[id]
	var out: Array = []
	var m := WeaponModels.mesh(id)
	if m != null and m.get_surface_count() > 0:
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in v.size():
				idx.append(i)
		var sc := SCALE * (HEAVY_SCALE if HEAVY.has(id) else Vector3.ONE)
		var shift := WeaponModels.muzzle_shift(id)
		var off := HeroCharacter.RIFLE_PIVOT + Vector3(MUZZLE_AT.x, MUZZLE_AT.y, MUZZLE_AT.z + shift)
		var groups := {}
		for t in idx.size() / 3:
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var d := idx[t * 3 + 2]
			var c0 := cols[a] if a < cols.size() else Color(0.15, 0.16, 0.19, 0.0)
			var c1 := cols[b] if b < cols.size() else c0
			var c2 := cols[d] if d < cols.size() else c0
			var ca := Color((c0.r + c1.r + c2.r) / 3.0, (c0.g + c1.g + c2.g) / 3.0, (c0.b + c1.b + c2.b) / 3.0, maxf(c0.a, maxf(c1.a, c2.a)))
			var k := _kind_of(ca)
			if not groups.has(k):
				groups[k] = {"v": [], "n": [], "idx": [], "map": {}}
			var g: Dictionary = groups[k]
			var map: Dictionary = g["map"]
			var gv: Array = g["v"]
			var gn: Array = g["n"]
			var gi: Array = g["idx"]
			for src: int in [a, b, d]:
				if not map.has(src):
					map[src] = gv.size()
					var p := v[src] * sc + off
					gv.append(Vector3(-p.x, p.y, -p.z))
					var q := nr[src] if src < nr.size() else Vector3.UP
					gn.append(Vector3(-q.x / sc.x, q.y / sc.y, -q.z / sc.z).normalized())
				gi.append(int(map[src]))
		for k: int in groups:
			var g: Dictionary = groups[k]
			var n := (g["v"] as Array).size()
			var t4 := PackedFloat32Array()
			t4.resize(n * 4)
			for i in n:
				t4[i * 4] = 1.0
				t4[i * 4 + 3] = 1.0
			var uv := PackedVector2Array()
			uv.resize(n)
			uv.fill(Vector2(1.0, 0.0))
			out.append({"kind": k, "zone": FoeKit.ZONE_TELL if k == int(FoeKit.KIND_GLOW) else 0, "v": PackedVector3Array(g["v"]), "n": PackedVector3Array(g["n"]), "t": t4,
					"uv": uv, "idx": PackedInt32Array(g["idx"])})
	_cache[id] = out
	return out
