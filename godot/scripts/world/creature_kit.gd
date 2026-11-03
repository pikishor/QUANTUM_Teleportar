class_name CreatureKit
extends RefCounted
## Creature kit, flora part: Quaternius space-kit trees, plants and rocks (CC0, docs/THIRD_PARTY.md) converted by tools/creature_kit.py into assets/models/kit_flora.glb
## (nine nodes Tree0-2 / Plant0-2 / Rock0-2, vertex colours from the atlas, desaturated). Like the interior kit a piece is NOT a node: its triangles are read once, flattened to the street
## kit's vertex format and concatenated into the camera-centred StreetKit window (city_kit_window.gd), so park and plaza dressing costs triangles and no draw call.
## Placement: a ring of trees, plants and rocks round every plaza (lot centres CityLayout.plazas), from a per-plaza generator so the street kit's own random stream is untouched.
## Also here: the enemy bodies of the creature kit (ENEMY_BODIES, imported through CharacterImport from assets_incoming/characters) and the extra vehicle kinds / pickup model names.

const PATH := "res://assets/models/kit_flora.glb"
const GAIN := 2.2                         ## the street kit's PAINT_GAIN equivalent: night props must stay readable, the prop shader's grime darkens them again
const FAMILIES := ["Tree", "Plant", "Rock"]
const VARIANTS := 3
## Per plaza: [family, count, ring radius min, ring radius max] (the lot is 18-26 m, the plaza keeps its middle free)
const RING := [["Tree", 2, 7.0, 9.0], ["Plant", 3, 5.5, 9.0], ["Rock", 2, 6.0, 9.5]]
const ENEMY_BODIES := {&"stalker": "enemy_alien", &"brute": "enemy_bluedemon", &"walker": "enemy_demon", &"pouncer": "enemy_alien", &"mender": "enemy_demon", &"phasewright": "enemy_alien"}
const EXTRA_VEHICLES: Array[StringName] = [&"rover", &"skiff"]
const PICKUP_MODELS := ["pickup_weapon"]

static var _cache: Dictionary = {}        ## "Tree0" -> flat geometry {v, n, uv, uv2, c, count} ({} when the glb is missing)


static func piece(family: String, variant: int) -> Dictionary:
	var key := "%s%d" % [family, variant % VARIANTS]
	if _cache.has(key):
		return _cache[key]
	_load_all()
	return _cache.get(key, {})


static func _load_all() -> void:
	for f in FAMILIES:
		for v in VARIANTS:
			_cache["%s%d" % [f, v]] = {}
	if not ResourceLoader.exists(PATH):
		return
	var ps := load(PATH) as PackedScene
	if ps == null:
		return
	var root := ps.instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0 or not _cache.has(String(mi.name)):
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cs = arr[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var n := idx.size()
		var gv := PackedVector3Array()
		var gn := PackedVector3Array()
		var guv := PackedVector2Array()
		var guv2 := PackedVector2Array()
		var gc := PackedColorArray()
		gv.resize(n)
		gn.resize(n)
		guv.resize(n)
		guv2.resize(n)
		gc.resize(n)
		for i in n:
			var j := idx[i]
			gv[i] = vs[j]
			gn[i] = ns[j]
			guv2[i] = Vector2(0.0, 0.8)
			var col: Color = cs[j] if cs != null else Color(0.4, 0.45, 0.4)
			gc[i] = Color(col.r * GAIN, col.g * GAIN, col.b * GAIN, 0.0)
		var g := {"v": gv, "n": gn, "uv": guv, "uv2": guv2, "c": gc, "count": n}
		_cache[String(mi.name)] = g
	root.free()


## Flat geometry of a street-kit flora kind (CityKit.FLORA_TREE / FLORA_PLANT / FLORA_ROCK) and variant; {} when the glb is not imported.
static func geo(kind: int, variant: int) -> Dictionary:
	var fam: String = FAMILIES[clampi(kind - 19, 0, FAMILIES.size() - 1)]
	return piece(fam, variant)


## Ring of flora round a plaza centre: Array of {kind (0 tree, 1 plant, 2 rock), variant, pos Vector2, yaw, seed}. Deterministic per plaza.
static func ring(plaza: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(plaza.x) * 131.0 + absf(plaza.y) * 7919.0) + 40213
	for fi in RING.size():
		var spec: Array = RING[fi]
		for k in int(spec[1]):
			var a := (float(k) + rng.randf() * 0.7) / float(spec[1]) * TAU + float(fi) * 0.9
			var r := rng.randf_range(float(spec[2]), float(spec[3]))
			var p := plaza + Vector2(cos(a), sin(a)) * r
			p = Vector2(clampf(p.x, plaza.x - 8.5, plaza.x + 8.5), clampf(p.y, plaza.y - 8.5, plaza.y + 8.5))
			out.append({"kind": fi, "variant": rng.randi() % VARIANTS, "pos": p, "yaw": rng.randf() * TAU, "seed": rng.randf()})
	return out
