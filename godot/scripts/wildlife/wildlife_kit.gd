class_name WildlifeKit
extends RefCounted
## Shared pieces of the wildlife: the one shader, the cached model scenes and the lizard (the only animal built in code: a flat-coloured prism body with a wiggle in the vertex stage).

const SHADER := preload("res://assets/shaders/animal.gdshader")

static var _scenes := {}
static var _lizard: ArrayMesh = null


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


## The converted model of a species (PackedScene, cached) or null (the lizard, a missing file).
static func scene(id: StringName) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := AnimalSpecies.model_path(id)
	var s: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		s = load(path) as PackedScene
	_scenes[id] = s
	return s


static func available() -> bool:
	return ResourceLoader.exists(AnimalSpecies.DIR + "deer.scn")


## The lizard: 0.5 m with the tail, faces -Z, feet on y = 0, one surface with vertex colours.
static func lizard_mesh() -> ArrayMesh:
	if _lizard != null:
		return _lizard
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.62, 0.55, 0.33)
	var belly := Color(0.78, 0.72, 0.52)
	var dark := Color(0.38, 0.32, 0.20)
	_box(st, Vector3(0.0, 0.045, -0.02), Vector3(0.075, 0.04, 0.16), body)
	_box(st, Vector3(0.0, 0.03, -0.02), Vector3(0.06, 0.02, 0.15), belly)
	_box(st, Vector3(0.0, 0.05, -0.135), Vector3(0.055, 0.035, 0.07), body)           # head
	_box(st, Vector3(0.0, 0.062, -0.155), Vector3(0.05, 0.01, 0.04), dark)
	for k in 4:                                                                       # tail, thinning out
		var z := 0.085 + 0.065 * float(k)
		var w := 0.06 * (1.0 - 0.22 * float(k))
		_box(st, Vector3(0.0, 0.035 - 0.004 * float(k), z), Vector3(w, 0.03 * (1.0 - 0.18 * float(k)), 0.075), body if k % 2 == 0 else dark)
	for sx in [-1.0, 1.0]:
		for sz in [-0.07, 0.05]:
			_box(st, Vector3(sx * 0.055, 0.015, sz), Vector3(0.04, 0.03, 0.02), dark)
	st.generate_normals()
	_lizard = st.commit()
	return _lizard


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 2, 1, 0, 3, 2], [4, 5, 6, 4, 6, 7], [0, 4, 7, 0, 7, 3], [1, 2, 6, 1, 6, 5], [3, 7, 6, 3, 6, 2], [0, 1, 5, 0, 5, 4]]
	st.set_color(col)
	for f in faces:
		for i in f:
			st.set_color(col)
			st.add_vertex(c + (v[i] as Vector3))
