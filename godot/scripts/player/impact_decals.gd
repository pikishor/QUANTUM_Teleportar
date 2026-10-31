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
const TEX_SIZE := 64

static var _texture: ImageTexture
static var _material: StandardMaterial3D

var _mm: MultiMesh
var _node: MultiMeshInstance3D
var _born := PackedFloat32Array()    ## spawn time (PlayerUtil.now) per instance, negative = unused
var _next := 0
var _filled := 0
var _live := 0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _get_material()
	_mm.mesh = quad
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	_born.resize(CAPACITY)
	_born.fill(-1.0)
	_node = MultiMeshInstance3D.new()
	_node.name = "Holes"
	_node.multimesh = _mm
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.custom_aabb = AABB(Vector3(-1200.0, -50.0, -1200.0), Vector3(2400.0, 400.0, 2400.0))
	add_child(_node)
	set_process(false)


## Add a hole at a surface point with the surface normal. size is the diameter in metres.
func add(pos: Vector3, normal: Vector3, size := 0.17) -> void:
	if _mm == null:
		return
	var n := normal.normalized()
	if n == Vector3.ZERO:
		n = Vector3.UP
	var ref := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	var tangent := n.cross(ref).normalized()
	var bitangent := n.cross(tangent)
	var basis := Basis(tangent, bitangent, n).rotated(n, randf() * TAU) * Basis.from_scale(Vector3(size, size, size))
	var i := _next
	_next = (_next + 1) % CAPACITY
	if _born[i] < 0.0:
		_live += 1
	_filled = mini(_filled + 1, CAPACITY)
	_mm.visible_instance_count = _filled
	_mm.set_instance_transform(i, Transform3D(basis, pos + n * LIFT))
	_mm.set_instance_color(i, Color.WHITE)
	_born[i] = PlayerUtil.now()
	set_process(true)


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
			_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, clampf((LIFE - age) / FADE, 0.0, 1.0)))
	if _live <= 0:
		set_process(false)


static func _get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = _get_texture()
		# a whisper of self-illumination keeps the pale rim readable on surfaces the scene hardly lights (night streets), without glowing in bright places
		_material.emission_enabled = true
		_material.emission = Color.WHITE
		_material.emission_texture = _get_texture()
		_material.emission_energy_multiplier = 0.14
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.95
		_material.metallic_specular = 0.15
		_material.cull_mode = BaseMaterial3D.CULL_BACK
	return _material


## A scorched, chipped bullet hole painted once: a dark pit, a ring of pale dust and a few hairline cracks. Alpha-blended.
static func _get_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := TEX_SIZE * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var u := (x + 0.5 - half) / half
			var v := (y + 0.5 - half) / half
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var wob := sin(ang * 5.0 + 0.7) * 0.07 + sin(ang * 11.0 + 2.1) * 0.05 + sin(ang * 23.0) * 0.025
			var hole_r := 0.30 + wob * 0.6
			var halo_r := 0.62 + wob
			var pit := 1.0 - smoothstep(hole_r - 0.06, hole_r + 0.04, r)
			var halo := (1.0 - smoothstep(halo_r - 0.3, halo_r, r)) * 0.8
			var crack_dir := pow(absf(sin(ang * 3.5 + 0.4)), 60.0)
			var crack := crack_dir * (1.0 - smoothstep(0.25, 0.98, r)) * 0.7
			var dust := smoothstep(hole_r - 0.02, halo_r - 0.1, r)
			# a black pit ringed by freshly exposed, pale material: it has to read against dark night surfaces, where a plain dark hole would vanish
			var col := Color(0.01, 0.01, 0.012).lerp(Color(0.82, 0.81, 0.78), dust)
			var alpha := clampf(maxf(maxf(pit, halo), crack), 0.0, 1.0)
			alpha *= 1.0 - smoothstep(0.86, 1.0, r)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, alpha))
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture
