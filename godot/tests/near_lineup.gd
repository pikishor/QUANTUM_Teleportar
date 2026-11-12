extends Node3D
## Look-dev lineup of the NEAR TRAFFIC cars (round 6, second pass): the twelve kinds as MultiMesh instances with the real shaders (HI mesh, LO mesh, or both side by side), on a wet floor.
##   tools/near_lineup.sh /tmp/prefix [mesh=hi|lo|both] [view=chase|front3q|rear3q|side|top] [dist=9] [night=0|1] [wet=0..1] [q=0|1|2] [cars=0,1,2,..] [h=2.2] [fov=92] [paint=-1] [brake=0]
## The image is <out>_<view>.png. `mesh=both` puts the LO mesh in a row behind the HI row so the hand-over at 22 m can be compared.

var _args := {}
var _cam: Camera3D
var _wait := 10
var _view := ""


func _hi_mesh() -> Mesh:
	return _load_mesh("cv2_near_hi")


func _lo_mesh() -> Mesh:
	return _load_mesh("cv2_near")


func _load_mesh(nm: String) -> Mesh:
	var root := Game.load_model(nm)
	var out: Mesh = null
	if root != null:
		for n in root.find_children("*", "MeshInstance3D", true, false):
			out = (n as MeshInstance3D).mesh
			break
		root.free()
	return out


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	var night := float(_args.get("night", "0"))
	RenderingServer.global_shader_parameter_set(&"night", night)
	RenderingServer.global_shader_parameter_set(&"wetness", float(_args.get("wet", "0.0")))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.1).lerp(Color(0.55, 0.68, 0.85), 1.0 - night)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.55)
	e.ambient_light_energy = lerpf(0.9, 0.5, night)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if Game.quality >= 1:
		e.fog_enabled = true
		e.fog_light_color = Color(0.5, 0.58, 0.7).lerp(Color(0.06, 0.08, 0.14), night)
		e.fog_density = 0.004
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = lerpf(1.1, 0.35, night)
	sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(0.6, 0.7, 1.0), night)
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	add_child(sun)
	if night > 0.5:
		for p in [Vector3(-8.0, 4.0, 3.0), Vector3(14.0, 4.0, -4.0)]:
			var neon := OmniLight3D.new()
			neon.light_color = Color(1.0, 0.25, 0.8) if p.x < 0.0 else Color(0.2, 0.9, 1.0)
			neon.light_energy = 2.5
			neon.omni_range = 18.0
			neon.position = p
			add_child(neon)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240.0, 240.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.13, 0.135, 0.15).lerp(Color(0.1, 0.105, 0.12), night)
	fm.roughness = lerpf(0.75, 0.3, float(_args.get("wet", "0.0")))
	fl.material_override = fm
	add_child(fl)
	var kinds := PackedInt32Array()
	for s in String(_args.get("cars", "0,1,2,3,4,5,6,7,8,9,10,11")).split(",", false):
		kinds.append(int(s))
	var mesh_mode := String(_args.get("mesh", "hi"))
	var blank := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 1))
	var light_map := ImageTexture.create_from_image(blank)
	var rows := 2 if mesh_mode == "both" else 1
	var per_row := int(_args.get("cols", "6"))
	var gap := float(_args.get("gap", "7.0"))
	for r in rows:
		var is_lo := mesh_mode == "lo" or (mesh_mode == "both" and r == 1)
		var mesh := _lo_mesh() if is_lo else _hi_mesh()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = kinds.size()
		for i in kinds.size():
			var c := i % per_row
			var rr := i / per_row
			var x := (float(c) - (per_row - 1) * 0.5) * gap
			var z := -float(rr) * 9.0 - float(r) * 30.0
			var yaw := float(_args.get("yaw", "0")) * PI / 180.0
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.0, z)))
			var pi := int(_args.get("paint", "-1"))
			mm.set_instance_custom_data(i, Color(float(pi if pi >= 0 else (i * 3 + 1) % 8), float(kinds[i]), float(_args.get("brake", "0")), float(_args.get("lamps", "1" if night > 0.5 else "0"))))
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/prop_nearcar.gdshader" if is_lo else "res://assets/shaders/prop_nearcar_hi.gdshader") as Shader
		mat.set_shader_parameter(&"light_map", light_map)
		if not is_lo and _args.has("raw"):
			mat.set_shader_parameter(&"debug_raw", 1.0)
		if _args.has("dbg"):
			mat.set_shader_parameter(&"debug_view", float(_args["dbg"]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-200, -5, -200), Vector3(400, 60, 400))
		add_child(mi)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH                  # the game camera: 92 degrees horizontal on every aspect ratio
	_cam.fov = float(_args.get("fov", "92"))
	_cam.near = 0.1
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30
	_view = String(_args.get("view", "chase"))
	var d := float(_args.get("dist", "9"))
	var h := float(_args.get("h", "2.2"))
	var look := Vector3(float(_args.get("lx", "0")), 0.7, -float(_args.get("lz", "0")))
	var pos := Vector3(0.0, h, d)
	match _view:
		"chase": pos = Vector3(float(_args.get("cx", "0")), h, d)
		"front3q": pos = Vector3(-d * 0.55, h + d * 0.18, -d * 0.8 - 4.0)
		"rear3q": pos = Vector3(d * 0.55, h + d * 0.18, d * 0.8 + 4.0)
		"side": pos = Vector3(-d, h, 0.0)
		"top": pos = Vector3(0.0, d * 1.2, 0.1)
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)


func _process(_dt: float) -> void:
	_wait -= 1
	if _wait == 0:
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/near"), _view])
		print("NEAR LINEUP DONE")
		get_tree().quit()
