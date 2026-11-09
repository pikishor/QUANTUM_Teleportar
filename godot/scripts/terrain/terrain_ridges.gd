class_name TerrainRidges
extends MeshInstance3D
## Far mountain impostors: one ring mesh (180 segments, 2 triangles each) of ridge silhouettes at RADIUS metres around the camera, so the horizon over the sea reads as distant ranges
## instead of a flat line. It follows the camera in X and Z (no parallax at that distance), is unshaded and takes the haze colour of the environment's fog every frame. One draw call.

const RADIUS := 8200.0
const SEGMENTS := 180
const BASE := -80.0

var _mat: ShaderMaterial
var _env: Environment


func _ready() -> void:
	name = "FarRidges"
	var noise := FastNoiseLite.new()
	noise.seed = 20240
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.6
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in SEGMENTS + 1:
		var a := TAU * float(i) / float(SEGMENTS)
		var cx := cos(a)
		var cz := sin(a)
		var n := noise.get_noise_2d(cx * 3.0, cz * 3.0) * 0.5 + 0.5                       # seamless: sampled on a circle
		var crest := 140.0 + 520.0 * pow(n, 1.6)
		verts.append(Vector3(cx * RADIUS, BASE, cz * RADIUS))
		verts.append(Vector3(cx * RADIUS, crest, cz * RADIUS))
		uvs.append(Vector2(float(i) / float(SEGMENTS), 0.0))
		uvs.append(Vector2(float(i) / float(SEGMENTS), 1.0))
		if i < SEGMENTS:
			var b := i * 2
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b + 1, b + 3, b + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-RADIUS, BASE, -RADIUS), Vector3(2.0 * RADIUS, 1000.0, 2.0 * RADIUS))
	self.mesh = mesh
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/terrain_ridge.gdshader") as Shader
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 16384.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	if _env == null:
		var vp := get_viewport()
		_env = vp.world_3d.environment if vp != null and vp.world_3d != null else null
	if _env != null and _mat != null:
		_mat.set_shader_parameter(&"haze", _env.fog_light_color)
