extends Node3D
## Look-dev of the water on the real height function: a preview terrain built from TerrainHeight (colours by height and slope) plus WaterWorld, one camera, one PNG.
##   godot --path . res://tests/water_view.tscn -- out=/path.png cam=px,py,pz,tx,ty,tz [tier=0|1|2] [mood=day|dusk|night] [frames=10] [swim=1] [under=1]
## tools: see xvfb + Vulkan mobile like tools/shot.sh.
var _out := "/tmp/water_view.png"
var _cam_arg := "-1400,40,-300,-1900,-2,-300"
var _tier := 1
var _mood := "day"
var _frames_wait := 10
var _sun := Vector2.INF
var _frames := 0
var _cam: Camera3D
var _water: WaterWorld


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
			"cam": _cam_arg = kv[1]
			"tier": _tier = int(kv[1])
			"mood": _mood = kv[1]
			"frames": _frames_wait = int(kv[1])
			"sun": _sun = Vector2(float(kv[1].split(",")[0]), float(kv[1].split(",")[1]))
	Game.autostart = true
	Game.quality = _tier
	var f := _cam_arg.split(",")
	var cp := Vector3(float(f[0]), float(f[1]), float(f[2]))
	var tp := Vector3(float(f[3]), float(f[4]), float(f[5]))
	_environment()
	_terrain(Vector2(tp.x, tp.z))
	_water = WaterWorld.attach(self)
	_cam = Camera3D.new()
	_cam.far = 2500.0
	_cam.fov = 70.0
	add_child(_cam)
	_cam.global_position = cp
	_cam.look_at(tp)
	_cam.make_current()
	Game.set_quality(_tier)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	var sun := DirectionalLight3D.new()
	match _mood:
		"night":
			pm.sky_top_color = Color(0.02, 0.04, 0.10)
			pm.sky_horizon_color = Color(0.06, 0.10, 0.18)
			pm.ground_horizon_color = Color(0.05, 0.08, 0.14)
			pm.ground_bottom_color = Color(0.02, 0.03, 0.06)
			sun.light_color = Color(0.58, 0.72, 1.0)
			sun.light_energy = 0.9
			sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
			env.fog_light_color = Color(0.07, 0.11, 0.17)
			env.ambient_light_energy = 1.2
		"dusk":
			pm.sky_top_color = Color(0.16, 0.20, 0.42)
			pm.sky_horizon_color = Color(0.95, 0.55, 0.32)
			pm.ground_horizon_color = Color(0.5, 0.35, 0.3)
			pm.ground_bottom_color = Color(0.1, 0.1, 0.15)
			sun.light_color = Color(1.0, 0.65, 0.4)
			sun.light_energy = 1.1
			sun.rotation_degrees = Vector3(-9.0, 60.0, 0.0)
			env.fog_light_color = Color(0.7, 0.5, 0.45)
			env.ambient_light_energy = 1.4
		_:
			pm.sky_top_color = Color(0.10, 0.24, 0.52)
			pm.sky_horizon_color = Color(0.62, 0.72, 0.82)
			pm.ground_horizon_color = Color(0.55, 0.62, 0.7)
			pm.ground_bottom_color = Color(0.3, 0.34, 0.4)
			sun.light_color = Color(1.0, 0.92, 0.78)
			sun.light_energy = 1.3
			sun.rotation_degrees = Vector3(-38.0, 50.0, 0.0)
			env.fog_light_color = Color(0.55, 0.65, 0.75)
			env.ambient_light_energy = 1.6
	if _sun != Vector2.INF:
		sun.rotation_degrees = Vector3(_sun.y, _sun.x, 0.0)
	sky.sky_material = pm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_density = 0.00018
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	add_child(sun)


func _color_at(h: float, slope: float) -> Color:
	if h > 300.0 and slope < 1.2:
		return Color(0.9, 0.93, 0.97)
	if slope > 0.75:
		return Color(0.33, 0.31, 0.3) if h < 220.0 else Color(0.5, 0.49, 0.48)
	if h < TerrainHeight.SEA_LEVEL + 2.2:
		return Color(0.76, 0.69, 0.52)
	if h < 6.0:
		return Color(0.5, 0.52, 0.34)
	if h < 120.0:
		return Color(0.24, 0.38, 0.18)
	return Color(0.36, 0.34, 0.26)


func _grid(center: Vector2, half: float, step: float, hole := Rect2()) -> void:
	var n := int(half * 2.0 / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var x0 := floorf((center.x - half) / step) * step
	var z0 := floorf((center.y - half) / step) * step
	for j in n:
		for i in n:
			var x := x0 + i * step
			var z := z0 + j * step
			var h := TerrainHeight.height_at(x, z)
			var hx := TerrainHeight.height_at(x + step, z) - TerrainHeight.height_at(x - step, z)
			var hz := TerrainHeight.height_at(x, z + step) - TerrainHeight.height_at(x, z - step)
			var nrm := Vector3(-hx, 2.0 * step, -hz).normalized()
			verts.append(Vector3(x, h, z))
			norms.append(nrm)
			cols.append(_color_at(h, sqrt(hx * hx + hz * hz) / (2.0 * step)))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			if hole.size != Vector2.ZERO and hole.has_point(Vector2(x0 + (i + 0.5) * step, z0 + (j + 0.5) * step)):
				continue
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _terrain(target: Vector2) -> void:
	TerrainHeight.warm()
	_grid(Vector2.ZERO, 3000.0, 24.0, Rect2(target - Vector2(500.0, 500.0), Vector2(1000.0, 1000.0)))
	_grid(target, 520.0, 4.0)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames == _frames_wait:
		get_viewport().get_texture().get_image().save_png(_out)
		print("water_view tris ", _water.triangle_count(), " shore ", WaterWorld.shore_stats())
		get_tree().quit()
