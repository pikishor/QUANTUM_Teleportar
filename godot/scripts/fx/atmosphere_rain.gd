extends Node3D
## Rain that follows the camera: long stretched streaks with a slight wind slant plus ground splashes near the camera.
##
## Pooled by construction: two MultiMeshes are allocated once at the HIGH budget and a quality tier or the rain intensity only
## changes `visible_instance_count`. All motion is analytic in the vertex shaders (assets/shaders/post_rain.gdshader and
## post_splash.gdshader); the CPU integrates only a handful of drift offsets per frame and sets a few uniforms, so there are no
## per-drop updates, no node creation and no allocations in the frame loop. The node itself sits on the camera, the shaders wrap
## the drops periodically around it, so the rain fills the view at any camera speed (driving, blinking) and stays fixed in the world.

const STREAK_SHADER := preload("res://assets/shaders/post_rain.gdshader")
const SPLASH_SHADER := preload("res://assets/shaders/post_splash.gdshader")

## Instances allocated once (the HIGH budget). A tier draws a prefix of the pool; the pool's order is low-discrepancy, so every
## prefix is evenly spread (no clumps or holes at any density).
const STREAK_POOL := 4800
const SPLASH_POOL := 2000
const STREAKS_BY_TIER: Array[int] = [1000, 2400, 4800]
const SPLASHES_BY_TIER: Array[int] = [380, 900, 2000]
const BOX_H := 24.0                 ## height of the rain volume above the ground
const NEAR_SIZE := 16.0             ## dense box round the camera
const FAR_SIZE := 48.0              ## sparse wide box; exactly 3x NEAR_SIZE so one drift wrap serves both
const SPLASH_RADIUS := 9.0
const SPEED_CLASS: Array[float] = [0.86, 1.0, 1.16]     ## must match post_rain.gdshader
const GROUND_PROBE_EVERY := 8       ## physics ticks between ground raycasts (about 7 per second)
const JUMP_LIMIT := 25.0            ## a camera displacement larger than this in one frame is a cut or a teleport, not motion
const MAX_CAM_SPEED := 70.0

## Wind in m/s (x, z). With a fall speed of 12 m/s the default leans the rain by about 8 degrees: a slight slant.
var wind := Vector2(1.5, 0.5)
var fall_speed := 12.0
## Where the drops land when no collider is found under the camera.
var ground_fallback := 0.0
## False hides all rain (streaks and splashes) without touching the weather values.
var rain_visible := true:
	set(v):
		rain_visible = v
		_refresh_visibility()
var tier := 1
var streaks: MultiMeshInstance3D
var splashes: MultiMeshInstance3D
var streak_material: ShaderMaterial
var splash_material: ShaderMaterial

var _drift: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _cam_vel := Vector3.ZERO
var _prev := Vector3.ZERO
var _have_prev := false
var _have_cam := false
var _ground := 0.0
var _ground_target := 0.0
var _ground_pushed := 1.0e9
var _rain := 0.0
var _clock := 0.0
var _gust := 1.0
var _tick := 0
var _shown := false
var _splash_ok := true
var _last_streaks := -1
var _last_splashes := -1
var _ray: PhysicsRayQueryParameters3D


func _ready() -> void:
	top_level = true                                   # always at the camera, whatever the parent's transform is
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = Game.L_WORLD
	_ray.hit_from_inside = false
	streak_material = ShaderMaterial.new()
	streak_material.shader = STREAK_SHADER
	splash_material = ShaderMaterial.new()
	splash_material.shader = SPLASH_SHADER
	streak_material.set_shader_parameter(&"box_h", BOX_H)
	streak_material.set_shader_parameter(&"near_size", NEAR_SIZE)
	streak_material.set_shader_parameter(&"far_size", FAR_SIZE)
	splash_material.set_shader_parameter(&"radius", SPLASH_RADIUS)
	streaks = _make_field("Streaks", _streak_mesh(), STREAK_POOL, streak_material)
	splashes = _make_field("Splashes", _splash_mesh(), SPLASH_POOL, splash_material)
	_refresh_visibility()
	_apply_counts()


func set_quality(level: int) -> void:
	tier = clampi(level, 0, 2)
	_apply_counts()


func set_light_direction(dir_to_light: Vector3) -> void:
	if streak_material:
		streak_material.set_shader_parameter(&"light_dir", dir_to_light.normalized())


## Instances currently drawn: streaks + splashes (each splash is 4 droplet quads and a ring quad).
func particle_count() -> int:
	return streak_count() + splash_count()


func streak_count() -> int:
	return streaks.multimesh.visible_instance_count if streaks and streaks.visible else 0


func splash_count() -> int:
	return splashes.multimesh.visible_instance_count if splashes and splashes.visible else 0


## What a tier would draw at full rain, whatever the current intensity (the quality budget).
static func budget(level: int) -> int:
	level = clampi(level, 0, 2)
	return STREAKS_BY_TIER[level] + SPLASHES_BY_TIER[level]


## Screen-space lean of far rain for a camera: positive when the rain moves to the camera's right as it falls.
func screen_slant(cam: Camera3D) -> float:
	var w := Vector3(wind.x, 0.0, wind.y) * _gust
	return clampf(cam.global_basis.x.dot(w) / fall_speed, -0.5, 0.5)


## Cast one ray down from the camera (a few times per second, from the physics tick) to find what the rain lands on.
func probe_ground(cam: Camera3D) -> void:
	_tick += 1
	if _tick % GROUND_PROBE_EVERY != 0 or cam == null or not cam.is_inside_tree():
		return
	var world := cam.get_world_3d()
	if world == null:
		return
	var from := cam.global_position + Vector3.UP * 0.4
	_ray.from = from
	_ray.to = from + Vector3.DOWN * 120.0
	var hit: Dictionary = world.direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		_ground_target = ground_fallback
	else:
		var p: Vector3 = hit["position"]
		_ground_target = p.y


## Per rendered frame. `rain` is the smoothed intensity 0..1; `cam` may be null (nothing is drawn then).
func update(delta: float, cam: Camera3D, rain: float) -> void:
	_rain = rain
	_have_cam = cam != null and is_instance_valid(cam) and cam.is_inside_tree()
	_refresh_visibility()
	_clock += delta
	if not _have_cam:
		_have_prev = false
		return
	var pos := cam.global_position
	global_position = pos
	if _have_prev and delta > 0.0:
		var d := pos - _prev
		if d.length_squared() < JUMP_LIMIT * JUMP_LIMIT:
			var v := d / delta
			var sp := v.length()
			if sp > MAX_CAM_SPEED:
				v *= MAX_CAM_SPEED / sp
			_cam_vel = _cam_vel.lerp(v, 1.0 - exp(-delta * 9.0))
		else:
			_cam_vel = Vector3.ZERO
	_prev = pos
	_have_prev = true
	if not _shown:
		return
	_gust = 1.0 + 0.4 * sin(_clock * 0.23) * sin(_clock * 0.57 + 1.3)
	var w3 := Vector3(wind.x, 0.0, wind.y) * _gust
	for i in 3:
		var d3: Vector3 = _drift[i]
		d3.x = fposmod(d3.x + w3.x * delta, FAR_SIZE)
		d3.y = fposmod(d3.y - fall_speed * SPEED_CLASS[i] * delta, BOX_H)
		d3.z = fposmod(d3.z + w3.z * delta, FAR_SIZE)
		_drift[i] = d3
	streak_material.set_shader_parameter(&"drift0", _drift[0])
	streak_material.set_shader_parameter(&"drift1", _drift[1])
	streak_material.set_shader_parameter(&"drift2", _drift[2])
	streak_material.set_shader_parameter(&"motion", Vector3(w3.x, fall_speed, w3.z))
	streak_material.set_shader_parameter(&"cam_vel", _cam_vel)
	_ground = lerpf(_ground, _ground_target, 1.0 - exp(-delta * 12.0))
	if absf(_ground - _ground_pushed) > 0.002:
		_ground_pushed = _ground
		streak_material.set_shader_parameter(&"ground_y", _ground)
		splash_material.set_shader_parameter(&"ground_y", _ground)
	_splash_ok = pos.y - _ground < 30.0                # no splashes to draw when the ground is far below
	splashes.visible = _splash_ok
	_apply_counts()


## The node flags are authoritative (they start out visible), so they are always brought in line, never skipped on a cached state.
func _refresh_visibility() -> void:
	if streaks == null:
		return
	_shown = rain_visible and _have_cam and _rain > 0.004
	if streaks.visible != _shown:
		streaks.visible = _shown
	var splash_want := _shown and _splash_ok
	if splashes.visible != splash_want:
		splashes.visible = splash_want


func _apply_counts() -> void:
	if streaks == null:
		return
	var n_s := int(float(STREAKS_BY_TIER[tier]) * _rain)
	var n_p := int(float(SPLASHES_BY_TIER[tier]) * _rain)
	if n_s != _last_streaks:
		_last_streaks = n_s
		streaks.multimesh.visible_instance_count = n_s
	if n_p != _last_splashes:
		_last_splashes = n_p
		splashes.multimesh.visible_instance_count = n_p


func _make_field(node_name: String, mesh: Mesh, count: int, mat: ShaderMaterial) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var buf := PackedFloat32Array()                    # identity transforms; the shaders place every drop themselves
	buf.resize(count * 12)
	for i in count:
		var o := i * 12
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0
	mm.buffer = buf
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.custom_aabb = AABB(Vector3(-90.0, -90.0, -90.0), Vector3(180.0, 180.0, 180.0))   # never frustum-culled: drops are placed in the shader
	mmi.ignore_occlusion_culling = true
	add_child(mmi)
	return mmi


## A unit quad: x -0.5..0.5 across, y 0 (leading head) .. 1 (fading tail) along the streak. UV carries the same coordinates.
func _streak_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.5, 1.0, 0.0), Vector3(-0.5, 1.0, 0.0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A splash: five quads. UV2.x 0..3 is a droplet (picks its direction and speed in the shader), 4 is the flat ground ring.
func _splash_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in 5:
		var b := k * 4
		verts.append_array([Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.5, 1.0, 0.0), Vector3(-0.5, 1.0, 0.0)])
		uvs.append_array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
		for j in 4:
			uv2.append(Vector2(float(k), 0.0))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
