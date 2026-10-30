extends Node3D
## Look-dev stage for the generated models: lit wet asphalt, night sky, haze, neon practicals and rim lights.
## Pick the camera with the environment variable QT_VIEW (shot.sh passes the environment through):
##   QT_VIEW=overview                      every model in rows (default)
##   QT_VIEW=<model>,<dist>,<yaw>,<pitch>  one model at the origin; yaw 0 = seen from the front (-Z side), 180 = from behind
##                                         e.g. QT_VIEW=player,3.5,180,8   QT_VIEW=drone_sentinel,20,35,6   QT_VIEW=car_sport,10,30,8
## QT_MOOD=studio switches to neutral bright lighting for judging shapes (default: night with neon).
## Example: QT_VIEW=car_sport,10,30,8 tools/shot.sh /tmp/car.png res://tests/assets_showcase.tscn 25

const ROWS := [
	{"z": 0.0, "step": 2.6, "models": ["player", "operative"]},
	{"z": -7.0, "step": 4.5, "models": ["drone_sentinel", "drone_striker", "drone_heavy"]},
	{"z": -17.0, "step": 6.5, "models": ["car_sedan", "car_sport", "car_suv"]},
	{"z": 5.0, "step": 1.6, "models": ["pickup_health", "pickup_energy", "core_gem"]},
]

var focus_model: Node3D
var studio := false


func _ready() -> void:
	studio = OS.get_environment("QT_MOOD") == "studio"
	_build_environment()
	_build_ground()
	_build_lights()
	var view := OS.get_environment("QT_VIEW")
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	if view == "" or view == "overview":
		_place_rows()
		cam.position = Vector3(0, 7.5, 24)
		cam.look_at(Vector3(0, 1.0, -6), Vector3.UP)
	elif view.begins_with("row"):
		_place_rows()
		var idx := int(view.substr(3))
		var row: Dictionary = ROWS[idx]
		cam.position = Vector3(0, 3.0, row["z"] + 9.0)
		cam.look_at(Vector3(0, 1.0, row["z"]), Vector3.UP)
	else:
		var p := view.split(",")
		var model_name := p[0]
		var dist := float(p[1]) if p.size() > 1 else 4.0
		var yaw := deg_to_rad(float(p[2])) if p.size() > 2 else 0.0
		var pitch := deg_to_rad(float(p[3])) if p.size() > 3 else 8.0
		var lift := float(p[4]) if p.size() > 4 else -1.0
		focus_model = _load(model_name)
		add_child(focus_model)
		var aabb := _aabb(focus_model)
		var target := aabb.get_center()
		if lift >= 0.0:
			target.y = lift
		# front of the model is -Z, so yaw 0 puts the camera on the -Z side looking back at it
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		cam.position = target + dir * dist
		cam.look_at(target, Vector3.UP)


func _load(model_name: String) -> Node3D:
	var m := Game.load_model(model_name)
	if m == null:
		m = MeshInstance3D.new()
		(m as MeshInstance3D).mesh = BoxMesh.new()
		push_warning("showcase: model %s missing, using a box" % model_name)
	m.name = model_name
	return m


func _place_rows() -> void:
	for row: Dictionary in ROWS:
		var names: Array = row["models"]
		var x0: float = -float(names.size() - 1) * float(row["step"]) * 0.5
		for i in names.size():
			var m := _load(names[i])
			m.position = Vector3(x0 + i * float(row["step"]), 0.0, row["z"])
			add_child(m)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	return box


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.03, 0.07)
	sky_mat.sky_horizon_color = Color(0.16, 0.1, 0.22)
	sky_mat.ground_horizon_color = Color(0.10, 0.07, 0.15)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.sky_energy_multiplier = 0.9
	if studio:
		sky_mat.sky_top_color = Color(0.45, 0.5, 0.58)
		sky_mat.sky_horizon_color = Color(0.7, 0.72, 0.75)
		sky_mat.ground_horizon_color = Color(0.5, 0.5, 0.5)
		sky_mat.ground_bottom_color = Color(0.3, 0.3, 0.3)
		sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = not studio
	env.fog_light_color = Color(0.07, 0.1, 0.14)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_ground() -> void:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	m.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.82, 0.9)
	mat.uv1_scale = Vector3(80, 80, 1)       # 2 m tiles
	var a := "res://assets/textures/asphalt_albedo.png"
	var o := "res://assets/textures/asphalt_orm.png"
	var n := "res://assets/textures/asphalt_normal.png"
	if ResourceLoader.exists(a):
		mat.albedo_texture = load(a)
	if ResourceLoader.exists(o):
		mat.roughness_texture = load(o)
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.roughness = 0.75
	else:
		mat.roughness = 0.35
	if ResourceLoader.exists(n):
		mat.normal_enabled = true
		mat.normal_texture = load(n)
		mat.normal_scale = 1.0
	mat.metallic_specular = 0.7
	m.material_override = mat
	add_child(m)


func _build_lights() -> void:
	if studio:
		var key := DirectionalLight3D.new()
		key.light_energy = 1.3
		key.rotation_degrees = Vector3(-40, -35, 0)
		key.shadow_enabled = true
		add_child(key)
		var fill := DirectionalLight3D.new()
		fill.light_energy = 0.55
		fill.light_color = Color(0.8, 0.9, 1.0)
		fill.rotation_degrees = Vector3(-25, 140, 0)
		add_child(fill)
		return
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.light_energy = 0.75
	moon.rotation_degrees = Vector3(-38, 150, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)
	# warm sodium key from the front-left, cool teal fill from the right, magenta + cyan neon practicals, hot rim from behind
	_omni(Vector3(-7, 4.0, 6), Color(1.0, 0.72, 0.42), 3.2, 22.0)
	_omni(Vector3(8, 3.0, 4), Color(0.2, 0.7, 0.8), 2.0, 20.0)
	_omni(Vector3(-8, 2.5, -9), Color(1.0, 0.1, 0.55), 5.0, 18.0)
	_omni(Vector3(8, 2.5, -10), Color(0.1, 0.85, 1.0), 5.0, 18.0)
	_omni(Vector3(0, 5.0, -22), Color(1.0, 0.2, 0.7), 6.0, 24.0)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.35, 0.85, 1.0)
	rim.light_energy = 0.55
	rim.rotation_degrees = Vector3(-20, -25, 0)     # shines toward -Z and +X: a backlight for characters seen from the camera at +Z
	add_child(rim)


func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.6
	add_child(l)
