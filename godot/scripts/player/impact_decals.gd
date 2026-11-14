class_name ImpactDecals
extends Node3D
## Pooled bullet-hole decals. One MultiMesh holds a ring buffer of CAPACITY quads (a single draw call for every hole in the world),
## so firing never creates nodes. Holes stay LIFE seconds and fade out over the last FADE seconds; the oldest one is recycled when
## the ring is full. Quads (not Decal nodes) because they behave the same in the Mobile and the Compatibility renderer.
## The node is top_level, so the instances live in world space whatever its parent does.

const CAPACITY := 40
const LIFE := 18.0
const FADE := 5.0
const LIFT := 0.012                  ## metres the quad floats above the surface (avoids z-fighting)
const SHADER := preload("res://assets/shaders/fx_decals.gdshader")
## Per-surface pools inside the one ring: a surface never holds more than its quota (the oldest hole of that surface is recycled first), so glass cracks
## cannot push out every metal dent. tint = instance colour, k = size factor, look = the material of fx_decals.gdshader (0 concrete: a pit, chips and hairline cracks, 1 metal: a round hole with
## a bright burr and a soot smear, 2 glass: a star of cracks and rings, 3 wood: a ragged hole and pale splinters, 4 asphalt: a small pit, grit, a wet halo). Wave 113: wood and asphalt are new,
## every material has its own look (it was one tinted pit for all).
const SURFACES := {
	&"concrete": {"quota": 40, "tint": Color(1.0, 1.0, 1.0), "k": 1.0, "look": 0},
	&"metal": {"quota": 16, "tint": Color(1.0, 1.0, 1.0), "k": 0.8, "look": 1},
	&"glass": {"quota": 12, "tint": Color(1.0, 1.0, 1.0), "k": 1.7, "look": 2},
	&"wood": {"quota": 14, "tint": Color(1.0, 1.0, 1.0), "k": 1.2, "look": 3},
	&"asphalt": {"quota": 18, "tint": Color(1.0, 1.0, 1.0), "k": 0.9, "look": 4},
}

static var _material: ShaderMaterial

var _mm: MultiMesh
var _node: MultiMeshInstance3D
var _born := PackedFloat32Array()    ## spawn time (PlayerUtil.now) per instance, negative = unused
var _next := 0
var _surf: Array[StringName] = []     ## surface of each slot
var _filled := 0
var _live := 0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _get_material()
	_mm.mesh = quad
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	_born.resize(CAPACITY)
	_born.fill(-1.0)
	_surf.resize(CAPACITY)
	_surf.fill(&"concrete")
	_node = MultiMeshInstance3D.new()
	_node.name = "Holes"
	_node.multimesh = _mm
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.custom_aabb = AABB(Vector3(-1500.0, -50.0, -1500.0), Vector3(3000.0, 400.0, 3000.0))
	_node.visible = false                # nothing to draw until the first hole: no draw call while the ring is empty
	add_child(_node)
	set_process(false)


## Add a hole at a surface point with the surface normal. size is the diameter in metres.
func add(pos: Vector3, normal: Vector3, size := 0.17, surface := &"concrete") -> void:
	if _mm == null:
		return
	var n := normal.normalized()
	if n == Vector3.ZERO:
		n = Vector3.UP
	var ref := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	var tangent := n.cross(ref).normalized()
	var bitangent := n.cross(tangent)
	var basis := Basis(tangent, bitangent, n).rotated(n, randf() * TAU) * Basis.from_scale(Vector3(size, size, size))
	var sd: Dictionary = SURFACES.get(surface, SURFACES[&"concrete"])
	size *= float(sd["k"])
	var i := _next
	if _count_of(surface) >= int(sd["quota"]):         # this surface's pool is full: recycle its oldest hole
		var oldest := INF
		for j in CAPACITY:
			if _born[j] >= 0.0 and _surf[j] == surface and _born[j] < oldest:
				oldest = _born[j]
				i = j
	else:
		_next = (_next + 1) % CAPACITY
	_surf[i] = surface
	if _born[i] < 0.0:
		_live += 1
	_filled = mini(_filled + 1, CAPACITY)
	_mm.visible_instance_count = _filled
	_mm.set_instance_transform(i, Transform3D(basis, pos + n * LIFT))
	_mm.set_instance_color(i, sd["tint"])
	_mm.set_instance_custom_data(i, Color(float(sd["look"]), randf(), 0.0, 0.0))
	_born[i] = PlayerUtil.now()
	_node.visible = true
	set_process(true)


func _count_of(surface: StringName) -> int:
	var n := 0
	for j in CAPACITY:
		if _born[j] >= 0.0 and _surf[j] == surface:
			n += 1
	return n


## Live holes on one surface.
func count_on(surface: StringName) -> int:
	return _count_of(surface)


func active_count() -> int:
	return _live


func clear() -> void:
	if _mm == null:
		return
	for i in CAPACITY:
		if _born[i] >= 0.0:
			_mm.set_instance_transform(i, _hidden)
			_born[i] = -1.0
	_live = 0
	_filled = 0
	_next = 0
	_mm.visible_instance_count = 0
	_node.visible = false
	set_process(false)


func _process(_delta: float) -> void:
	var now := PlayerUtil.now()
	for i in _filled:
		var b := _born[i]
		if b < 0.0:
			continue
		var age := now - b
		if age >= LIFE:
			_mm.set_instance_transform(i, _hidden)
			_born[i] = -1.0
			_live -= 1
		elif age > LIFE - FADE:
			var tc: Color = SURFACES[_surf[i]]["tint"]
			tc.a = clampf((LIFE - age) / FADE, 0.0, 1.0)
			_mm.set_instance_color(i, tc)
	if _live <= 0:
		_node.visible = false
		set_process(false)


static func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material
