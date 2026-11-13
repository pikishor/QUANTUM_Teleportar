class_name VegKit
extends RefCounted
## The pieces and materials of the outskirts' vegetation (wave 105). Near pieces are Quaternius' Stylized Nature MegaKit (CC0) converted by tools/open_models/convert_nature.py into
## assets/models/nature_kit.glb (flat colours + ONE 1024 x 512 alpha atlas, see docs/THIRD_PARTY.md); the mid and far LODs of trees are generated here (cones and blobs on the same
## material, no extra texture). Everything uses assets/shaders/vegetation.gdshader: one ShaderMaterial per piece (tint, height for the wind lever, snow line).
##   VegKit.mesh(name)        ArrayMesh of a kit piece ("pine_a", "broad_b", "rock_c", ...) or a generated one ("pine_l1", "pine_l2", "broad_l1", "broad_l2")
##   VegKit.material(name)    the ShaderMaterial of the piece
##   VegKit.height(name)      the piece's height in metres at scale 1
##   VegKit.tris(name)        triangle count (budget checks)

const KIT_PATH := "res://assets/models/nature_kit.glb"
const ATLAS_PATH := "res://assets/textures/nature_atlas.webp"
const SHADER_PATH := "res://assets/shaders/vegetation.gdshader"
const OPAQUE_UV := Vector2(0.375, 0.75)                 ## the centre of the atlas' opaque tile

## name -> {tint_a, tint_b, sway, snow}: foliage colours in linear space (the shader multiplies the ambient-occlusion grey of the vertex colour), wind sway, snow dusting on / off
const LOOK := {
	"pine_a": {"a": Color(0.076, 0.204, 0.119), "b": Color(0.153, 0.323, 0.162), "sway": 0.010},
	"pine_b": {"a": Color(0.093, 0.221, 0.128), "b": Color(0.170, 0.340, 0.153), "sway": 0.010},
	"pine_c": {"a": Color(0.085, 0.212, 0.136), "b": Color(0.162, 0.315, 0.170), "sway": 0.010},
	"pine_l1": {"a": Color(0.076, 0.204, 0.119), "b": Color(0.153, 0.323, 0.162), "sway": 0.010},
	"pine_l2": {"a": Color(0.076, 0.196, 0.119), "b": Color(0.136, 0.289, 0.153), "sway": 0.008},
	"broad_a": {"a": Color(0.119, 0.289, 0.093), "b": Color(0.289, 0.476, 0.119), "sway": 0.014},
	"broad_b": {"a": Color(0.136, 0.289, 0.085), "b": Color(0.340, 0.459, 0.102), "sway": 0.014},
	"broad_c": {"a": Color(0.102, 0.272, 0.102), "b": Color(0.238, 0.442, 0.119), "sway": 0.014},
	"broad_l1": {"a": Color(0.119, 0.289, 0.093), "b": Color(0.289, 0.476, 0.119), "sway": 0.012},
	"broad_l2": {"a": Color(0.111, 0.255, 0.093), "b": Color(0.221, 0.391, 0.111), "sway": 0.010},
	"dead_a": {"a": Color(1, 1, 1), "b": Color(1, 1, 1), "sway": 0.0},
	"dead_b": {"a": Color(1, 1, 1), "b": Color(1, 1, 1), "sway": 0.0},
	"bush": {"a": Color(0.136, 0.272, 0.085), "b": Color(0.323, 0.459, 0.119), "sway": 0.03},
	"fern": {"a": Color(0.119, 0.323, 0.102), "b": Color(0.238, 0.476, 0.119), "sway": 0.04},
	"grass": {"a": Color(0.18, 0.27, 0.07), "b": Color(0.36, 0.40, 0.10), "sway": 0.05},
	"tuft": {"a": Color(0.30, 0.26, 0.09), "b": Color(0.46, 0.38, 0.14), "sway": 0.05},
	"rock_a": {"a": Color.WHITE, "b": Color.WHITE, "sway": 0.0},
	"rock_b": {"a": Color.WHITE, "b": Color.WHITE, "sway": 0.0},
	"rock_c": {"a": Color.WHITE, "b": Color.WHITE, "sway": 0.0},
	"pebble": {"a": Color.WHITE, "b": Color.WHITE, "sway": 0.0},
}

static var _meshes := {}
static var _mats := {}
static var _heights := {}
static var _tris := {}
static var _atlas: Texture2D
static var _loaded := false


static func _load_kit() -> void:
	if _loaded:
		return
	_loaded = true
	var ps := load(KIT_PATH) as PackedScene
	if ps != null:
		var root := ps.instantiate()
		for n in root.get_children():
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var m := (n as MeshInstance3D).mesh
				_meshes[String(n.name)] = m
		root.free()
	_atlas = load(ATLAS_PATH) as Texture2D
	_meshes["pine_l1"] = _conifer(false)
	_meshes["pine_l2"] = _conifer(true)
	_meshes["broad_l1"] = _crown(false)
	_meshes["broad_l2"] = _crown(true)
	LandKit.merge_into(_meshes)                                       # wave 112: the nine landscape tree species with their LODs and the impostor cross (scripts/landscape/land_kit.gd)
	for k in _meshes.keys():
		var m: Mesh = _meshes[k]
		_heights[k] = m.get_aabb().size.y
		_tris[k] = _count(m)


static func available() -> bool:
	_load_kit()
	return _meshes.has("pine_a") and _meshes.has("rock_a")


static func names() -> Array:
	_load_kit()
	return _meshes.keys()


static func mesh(nm: String) -> Mesh:
	_load_kit()
	return _meshes.get(nm)


static func height(nm: String) -> float:
	_load_kit()
	return float(_heights.get(nm, 4.0))


static func tris(nm: String) -> int:
	_load_kit()
	return int(_tris.get(nm, 0))


static func atlas() -> Texture2D:
	_load_kit()
	return _atlas


static func _count(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null and (idx as PackedInt32Array).size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func material(nm: String) -> ShaderMaterial:
	_load_kit()
	if LandKit.has_name(nm):
		return LandKit.material_for(nm)
	if _mats.has(nm):
		return _mats[nm]
	var sh := load(SHADER_PATH) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	if _atlas != null:
		mat.set_shader_parameter(&"atlas", _atlas)
	var look: Dictionary = LOOK.get(nm, LOOK["rock_a"])
	var a: Color = look["a"]
	var b: Color = look["b"]
	mat.set_shader_parameter(&"tint_a", Vector3(a.r, a.g, a.b))
	mat.set_shader_parameter(&"tint_b", Vector3(b.r, b.g, b.b))
	mat.set_shader_parameter(&"sway", float(look["sway"]))
	mat.set_shader_parameter(&"height", maxf(height(nm), 0.5))
	if nm.begins_with("rock") or nm == "pebble":
		mat.set_shader_parameter(&"solid_mul", Vector3(1.0, 0.98, 0.95))
	_mats[nm] = mat
	return mat


# --- generated far LODs ---------------------------------------------------------------------------------------------------------------------------

## Cone tiers on a thin trunk (jagged skirts so the silhouette is not a perfect cone). Same height (about 9 m) and radius as the kit's pines.
static func _conifer(far: bool) -> ArrayMesh:
	var b := _Builder.new()
	if not far:
		b.prism(Vector3.ZERO, 0.30, 0.10, 6.8, 6, Color(0.2, 0.145, 0.09), 0.0)
	var tiers: Array = [[1.4, 3.2, 3.3], [3.0, 3.0, 2.7], [4.6, 2.7, 2.1], [6.1, 2.8, 1.4]] if not far else [[0.9, 5.2, 3.2], [4.4, 4.6, 2.0]]
	var segs := 9 if not far else 6
	for t in tiers.size():
		var ti: Array = tiers[t]
		b.cone(float(ti[0]), float(ti[1]), float(ti[2]), segs, 0.55 + 0.45 * float(t) / float(tiers.size()), t * 0.37)
	return b.build()


## Trunk plus lumpy blobs (an ellipsoid with jittered rings); far = one blob.
static func _crown(far: bool) -> ArrayMesh:
	var b := _Builder.new()
	if not far:
		b.prism(Vector3.ZERO, 0.26, 0.14, 4.6, 6, Color(0.18, 0.13, 0.09), 0.0)
		b.blob(Vector3(0.0, 6.6, 0.0), Vector3(2.5, 2.8, 2.5), 8, 3, 1.0, 0.5)
		b.blob(Vector3(1.5, 5.3, 0.6), Vector3(1.5, 1.4, 1.5), 6, 2, 0.85, 1.9)
		b.blob(Vector3(-1.2, 5.6, -0.9), Vector3(1.4, 1.3, 1.4), 6, 2, 0.8, 3.1)
	else:
		b.blob(Vector3(0.0, 6.0, 0.0), Vector3(2.7, 3.6, 2.7), 5, 2, 1.0, 0.0)
	return b.build()


class _Builder:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func _v(p: Vector3, n: Vector3, c: Color, leaf: bool) -> int:
		pos.append(p)
		nrm.append(n.normalized())
		col.append(Color(c.r, c.g, c.b, 1.0 if leaf else 0.0))
		uv.append(VegKit.OPAQUE_UV if leaf else Vector2.ZERO)
		return pos.size() - 1

	func prism(base: Vector3, r0: float, r1: float, h: float, sides: int, c: Color, _t: float) -> void:
		var ring0: Array[int] = []
		var ring1: Array[int] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var d := Vector3(cos(a), 0.0, sin(a))
			ring0.append(_v(base + d * r0, d, c * 0.8, false))
			ring1.append(_v(base + d * r1 + Vector3(0, h, 0), d, c, false))
		for i in sides:
			var j := (i + 1) % sides
			idx.append_array([ring0[i], ring1[i], ring0[j], ring0[j], ring1[i], ring1[j]])

	## A star-skirted cone: base ring at y0 (alternating radius), apex at y0 + h.
	func cone(y0: float, h: float, r: float, segs: int, shade: float, phase: float) -> void:
		var apex := _v(Vector3(0.0, y0 + h, 0.0), Vector3.UP, Color(shade, shade, shade), true)
		var ring: Array[int] = []
		for i in segs:
			var a := TAU * (float(i) + phase) / float(segs)
			var rr := r * (1.0 if i % 2 == 0 else 0.76)
			var yy := y0 + (0.0 if i % 2 == 0 else h * 0.07)
			var d := Vector3(cos(a), 0.0, sin(a))
			var dark := shade * (0.78 if i % 2 == 0 else 0.66)
			ring.append(_v(Vector3(d.x * rr, yy, d.z * rr), Vector3(d.x, 0.6, d.z), Color(dark, dark, dark), true))
		for i in segs:
			idx.append_array([apex, ring[(i + 1) % segs], ring[i]])

	func blob(c: Vector3, rad: Vector3, segs: int, rings: int, shade: float, phase: float) -> void:
		var top := _v(c + Vector3(0, rad.y, 0), Vector3.UP, Color(shade, shade, shade), true)
		var rows: Array = []
		for r in range(1, rings + 1):
			var lat := PI * 0.5 - PI * float(r) / float(rings + 1) * 1.0
			var row: Array[int] = []
			for i in segs:
				var a := TAU * float(i) / float(segs) + phase + float(r) * 0.4
				var j := 1.0 + 0.14 * sin(float(i) * 2.3 + phase * 3.0 + float(r))
				var d := Vector3(cos(a) * cos(lat), sin(lat), sin(a) * cos(lat))
				var p := c + Vector3(d.x * rad.x, d.y * rad.y, d.z * rad.z) * j
				var ao := shade * clampf(0.5 + 0.5 * (0.5 + 0.5 * d.y), 0.0, 1.0)
				row.append(_v(p, d, Color(ao, ao, ao), true))
			rows.append(row)
		var bot := _v(c - Vector3(0, rad.y * 0.9, 0), Vector3.DOWN, Color(shade * 0.5, shade * 0.5, shade * 0.5), true)
		var first: Array = rows[0]
		for i in segs:
			idx.append_array([top, first[(i + 1) % segs], first[i]])
		for r in rows.size() - 1:
			var a: Array = rows[r]
			var b: Array = rows[r + 1]
			for i in segs:
				var j := (i + 1) % segs
				idx.append_array([a[i], a[j], b[i], a[j], b[j], b[i]])
		var last: Array = rows[rows.size() - 1]
		for i in segs:
			idx.append_array([bot, last[i], last[(i + 1) % segs]])

	func build() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
