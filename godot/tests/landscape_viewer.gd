extends Node3D
## Look-dev stage for the landscape trees and ground cover with the real materials (tools/shot.sh OUT res://tests/landscape_viewer.tscn 24; software Vulkan).
## env LV_VIEW: "trees" (default: a column per species, rows LOD0 full / LOD0 lite / LOD1 / impostor), "close" (full LOD0 of every species, camera low and near), "forest" (a dense mixed
## stand drawn the way the game does: LOD0, LOD1 and impostors by distance), "cover" (ground cover pieces).  LV_WIND = wind strength (default 0.3), LV_HOUR = 0 day .. 1 night grade,
## LV_RAIN = wetness 0..1, LV_CAM = "x,y,z,tx,ty,tz" overrides the camera.
func _ready() -> void:
	LandClimate.ensure()
	var wind := float(OS.get_environment("LV_WIND")) if OS.get_environment("LV_WIND") != "" else 0.3
	LandClimate.override(wind, 190.0)
	RenderingServer.global_shader_parameter_set(&"wind", Vector4(cos(deg_to_rad(190.0)), sin(deg_to_rad(190.0)), wind, 0.0))
	var night := float(OS.get_environment("LV_HOUR")) if OS.get_environment("LV_HOUR") != "" else 0.0
	RenderingServer.global_shader_parameter_set(&"night", night)
	var wet := float(OS.get_environment("LV_RAIN")) if OS.get_environment("LV_RAIN") != "" else 0.1
	RenderingServer.global_shader_parameter_set(&"wetness", wet)
	RenderingServer.global_shader_parameter_set(&"rain", wet)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.70, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.76)
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.74, 0.88)
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.25
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.26, 0.32, 0.16)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var view := OS.get_environment("LV_VIEW") if OS.get_environment("LV_VIEW") != "" else "trees"
	var cam_pos := Vector3(0, 9, 52)
	var cam_tgt := Vector3(0, 6, -10)
	var species: Array = LandKit.species()
	match view:
		"trees":
			var row := int(OS.get_environment("LV_ROW")) if OS.get_environment("LV_ROW") != "" else 0
			var x0 := -float(species.size() - 1) * 6.5
			for i in species.size():
				var sp: String = species[i]
				var x := x0 + i * 13.0
				match row:
					0:
						_place("%s_0" % sp, Vector3(x, 0, 0))
					1:
						_place("%s_0l" % sp, Vector3(x, 0, 0))
					2:
						_place("%s_1" % sp, Vector3(x, 0, 0))
					_:
						_impostor(sp, Vector3(x, 0, 0))
			cam_pos = Vector3(0, 5.5, 52)
			cam_tgt = Vector3(0, 6.5, 0)
		"close":
			var x1 := -float(species.size() - 1) * 7.5
			for i in species.size():
				var sp2: String = species[i]
				_place("%s_0" % sp2, Vector3(x1 + i * 15.0, 0, 0))
			cam_pos = Vector3(0, 3.0, 26)
			cam_tgt = Vector3(0, 6.5, 0)
		"forest":
			_forest()
			cam_pos = Vector3(0, 2.2, 30)
			cam_tgt = Vector3(0, 7, -40)
		"cover":
			_cover()
			cam_pos = Vector3(0, 1.6, 7)
			cam_tgt = Vector3(0, 0.6, -2)
	if OS.get_environment("LV_CAM") != "":
		var a := OS.get_environment("LV_CAM").split(",")
		cam_pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
		cam_tgt = Vector3(float(a[3]), float(a[4]), float(a[5]))
	var cam := Camera3D.new()
	cam.fov = 62
	cam.far = 900
	add_child(cam)
	cam.position = cam_pos
	cam.look_at(cam_tgt, Vector3.UP)
	cam.make_current()


func _place(nm: String, pos: Vector3, rot_y := 0.0, scale_v := 1.0) -> void:
	var m := VegKit.mesh(nm)
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = VegKit.material(nm)
	mi.position = pos
	mi.rotation.y = rot_y
	mi.scale = Vector3.ONE * scale_v
	add_child(mi)


func _impostor(sp: String, pos: Vector3, scale_v := 1.0) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = VegKit.mesh("imp")
	mm.instance_count = 1
	var sz := LandKit.impostor_size(sp)
	var t := Transform3D(Basis.from_scale(Vector3(sz.x, sz.y, sz.x) * scale_v), pos)
	mm.set_instance_transform(0, t)
	mm.set_instance_custom_data(0, Color(0.5, 0.0, float(LandKit.impostor_cell(sp)), 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = VegKit.material("imp")
	add_child(mmi)


func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mix := ["oak", "oak", "birch", "pine", "fir", "fir", "poplar", "oak", "pine"]
	var slots := {}
	for i in 520:
		var sp: String = mix[rng.randi() % mix.size()]
		var p := Vector3(rng.randf_range(-70, 70), 0, rng.randf_range(-260, 20))
		var d := absf(p.z - 30.0)
		var sc := rng.randf_range(0.85, 1.3)
		var rot := rng.randf() * TAU
		if d < 28.0:
			_place("%s_0" % sp, p, rot, sc)
		elif d < 85.0:
			_place("%s_1" % sp, p, rot, sc)
		else:
			_impostor(sp, p, sc)


func _cover() -> void:
	var names := ["g_grass1", "g_grass2", "g_dry", "g_tall", "g_daisy", "g_poppy", "g_lav", "g_clover", "g_fern1", "g_fern2", "g_bush1", "g_bush2", "g_reed"]
	var x := -float(names.size() - 1) * 0.9
	for nm in names:
		if VegKit.mesh(nm) != null:
			_place(nm, Vector3(x, 0, 0), 0.0, 1.0)
		x += 1.8
