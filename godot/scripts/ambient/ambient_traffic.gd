extends RefCounted
## Far traffic of the living city: ONE MultiMesh of paired head / tail light points moving along the 68 lanes of the road grid (17 roads x 2 axes x 2
## directions). Motion is computed in the vertex shader from a time uniform (assets/shaders/prop_traffic.gdshader), so a car costs no CPU at all;
## the tiers only change how many instances are drawn (`visible_instance_count`). Every 40th car is an emergency vehicle with red / blue strobes.
## The cars are lights only: close to the camera they fade out and the real vehicles of VehicleManager take over.

const SHADER := preload("res://assets/shaders/prop_traffic.gdshader")

const LANE_MIN := -(CityLayout.HALF + 20.0)      ## the cars wrap around along each lane over the whole big city (the shader holds the same two numbers)
const LANE_LEN := 2.0 * (CityLayout.HALF + 20.0)
const BUILT := 700                       ## instances in the MultiMesh (the HIGH count); the hard cap of the feature is CAP
const CAP := 760
const COUNTS: Array[int] = [140, 320, 700]      ## 4x the area of the original city: about 1.8x the cars (the cars are lights only: still ONE draw call, the cost is vertex-stage only)
const LANES := 4 * (CityLayout.N + 1)
const EMERGENCY_EVERY := 40
const EMERGENCY_AT := 7
## What the far cars are, by VehicleSpecs name and share of the cars (the rest of each 40 are plain cars; every 40th car is the emergency / Vael patrol vehicle). The look
## (head light tint, speed factor) comes from VehicleSpecs.far_look(): a kind whose model has not been built yet drives with the sedan's look, never fails.
const KIND_MIX: Array = [[&"sedan", 0.30], [&"sport", 0.14], [&"suv", 0.12], [&"bike", 0.16], [&"hover", 0.28]]
const EMERGENCY_KIND := &"vael_patrol"

var mm: MultiMesh
var material: ShaderMaterial
var mirror_material: ShaderMaterial
var count := 0
## Per-instance lane data, mirrored from the buffer so GDScript (sirens, tests) can place a car exactly where the shader draws it.
var lat := PackedFloat32Array()
var start := PackedFloat32Array()
var speed := PackedFloat32Array()
var axis := PackedByteArray()
var kind := PackedByteArray()            ## index into kind_names() per instance
var _kind_names: Array[StringName] = []


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var lane_lat: Array[float] = []
	var lane_speed: Array[float] = []
	var lane_axis: Array[int] = []
	var lane_phase: Array[float] = []
	for a in 2:
		for k in CityLayout.N + 1:
			for dir in [-1, 1]:
				var off: float = float(dir) * CityLayout.LANE if a == 0 else -float(dir) * CityLayout.LANE   # right-hand traffic, VehicleSpecs.lane_offset
				lane_lat.append(CityLayout.road_center(k) + off)
				lane_speed.append(float(dir) * rng.randf_range(9.0, 16.0))
				lane_axis.append(a)
				lane_phase.append(rng.randf())
	var order: Array[int] = []
	for i in LANES:
		order.append(i)
	for i in range(LANES - 1, 0, -1):                              # deterministic shuffle: any prefix of the instances covers the lanes evenly
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	mm = _new_multimesh(_lamp_mesh(), BUILT)
	var buf := PackedFloat32Array()
	buf.resize(BUILT * 20)
	lat.resize(BUILT)
	start.resize(BUILT)
	speed.resize(BUILT)
	axis.resize(BUILT)
	kind.resize(BUILT)
	_kind_names.clear()
	for km: Array in KIND_MIX:
		_kind_names.append(km[0])
	_kind_names.append(EMERGENCY_KIND)
	for i in BUILT:
		var lane := order[i % LANES]
		var slot := i / LANES
		var s := LANE_MIN + fposmod(float(slot) * 0.6180339 + lane_phase[lane], 1.0) * LANE_LEN
		var seed_v := rng.randf() * 0.98
		var emergency := i % EMERGENCY_EVERY == EMERGENCY_AT
		var base_tint := Color(1.0, 0.92, 0.78).lerp(Color(0.80, 0.90, 1.0), rng.randf())
		var kr := rng.randf()
		var ki := _kind_names.size() - 1 if emergency else _pick_kind(kr)
		var look := VehicleSpecs.far_look(_kind_names[ki])
		var tint: Color = base_tint if ki < 3 or emergency else base_tint.lerp(look["tint"], 0.85)      # cars keep the random city white, bikes and hovers carry their own light
		kind[i] = ki
		lat[i] = lane_lat[lane]
		start[i] = s
		speed[i] = lane_speed[lane] * (0.55 if emergency else float(look["speed"])) * (1.0 + 0.04 * (seed_v - 0.5))
		axis[i] = lane_axis[lane]
		var o := i * 20
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0
		buf[o + 12] = tint.r
		buf[o + 13] = tint.g
		buf[o + 14] = tint.b
		buf[o + 15] = 1.0 if emergency else 0.0
		buf[o + 16] = lat[i]
		buf[o + 17] = start[i]
		buf[o + 18] = speed[i]
		buf[o + 19] = float(axis[i]) + seed_v
	mm.buffer = buf
	material = ShaderMaterial.new()
	material.shader = SHADER
	mirror_material = ShaderMaterial.new()                          # transparent copies must be in the screen copy the ground reads
	mirror_material.shader = SHADER
	mirror_material.render_priority = -120


static func _new_multimesh(mesh: Mesh, n: int) -> MultiMesh:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.use_custom_data = true
	m.mesh = mesh
	m.instance_count = n
	return m


## Two camera-facing quads (left / right lamp); the vertex stage places and sizes them.
static func _lamp_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var b := verts.size()
		for c in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(Vector3(c.x - 0.5, c.y - 0.5, 0.0))
			uvs.append(c)
			uv2s.append(Vector2(side, 0.0))
			norms.append(Vector3(0, 0, 1))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-1300, -4, -1300), Vector3(2600, 40, 2600))
	return mesh


## How many cars are drawn (clamped to what the MultiMesh holds and to the feature cap).
func set_count(n: int) -> void:
	count = clampi(n, 0, mini(BUILT, CAP))
	mm.visible_instance_count = count


func set_time(t: float) -> void:
	material.set_shader_parameter(&"ambient_time", t)
	mirror_material.set_shader_parameter(&"ambient_time", t)


## Index into _kind_names for a random number 0..1 (the shares of KIND_MIX).
static func _pick_kind(r: float) -> int:
	var acc := 0.0
	for j in KIND_MIX.size():
		acc += float((KIND_MIX[j] as Array)[1])
		if r < acc:
			return j
	return KIND_MIX.size() - 1


## VehicleSpecs name of far car `i` (emergency cars are the Vael patrol vehicles).
func kind_of(i: int) -> StringName:
	return _kind_names[kind[i]]


func is_emergency(i: int) -> bool:
	return i % EMERGENCY_EVERY == EMERGENCY_AT


## World position (y = 0) of car `i` at ambient time `t`: the same formula as the shader.
func car_position(i: int, t: float) -> Vector3:
	var along := fposmod(start[i] + speed[i] * t - LANE_MIN, LANE_LEN) + LANE_MIN
	return Vector3(along, 0.0, lat[i]) if axis[i] == 0 else Vector3(lat[i], 0.0, along)
