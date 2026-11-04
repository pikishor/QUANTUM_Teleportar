extends Node3D
## VFX showcase without the city: every effect of FX.qvfx (scripts/fx/quantum_vfx.gd) on a dark street under bloom, shot at fixed game ages. One rendered frame is
## exactly 1/30 game second under --fixed-fps, so the pictures show the same effect age on any renderer.
##   tools/vfx_showcase.sh OUT_PREFIX [WxH] [quality]        images: <out>_<effect>_<age ms>.png, then <out>_sheet.png when python3 + PIL exist
##   env VFX_ONLY=teleport,beam limits the run, VFX_AGES=0.15,0.4 sets the ages (seconds)

var _args := {}
var _ids: Array[StringName] = []
var _ages: Array[float] = [0.12, 0.3, 0.6]
var _cam: Camera3D
var _hero: Node3D
var _i := -1
var _frame := 0
var _next_age := 0
var _out := "/tmp/vfx"
var _wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	_out = str(_args.get("out", "/tmp/vfx"))
	Game.quality = int(_args.get("q", "1"))
	Game.state = &"play"
	var only := OS.get_environment("VFX_ONLY")
	for id in FX.QuantumVfx.SHOWCASE:
		if only == "" or String(id) in only.split(","):
			_ids.append(id)
	var ages := OS.get_environment("VFX_AGES")
	if ages != "":
		_ages.clear()
		for a in ages.split(","):
			_ages.append(float(a))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.02, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.3, 0.42)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.light_color = Color(0.6, 0.7, 1.0)
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.07, 0.075, 0.09)
	gm.roughness = 0.35
	gm.metallic = 0.2
	ground.material_override = gm
	add_child(ground)
	for k in 7:                                                                  # backdrop blocks so a shockwave has something to light up
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 6.0 + (k % 3) * 3.0, 3.0)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.11, 0.14)
		m.roughness = 0.8
		b.material_override = m
		b.position = Vector3(-18.0 + k * 6.0, bm.size.y * 0.5, -9.0)
		add_child(b)
	_hero = _make_hero()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_cam.global_position = Vector3(0.0, 2.8, 9.5)
	_cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	Engine.max_fps = 30
	_wait = 10


func _make_hero() -> Node3D:
	PlayerBody.use_superhero = true
	var body := PlayerBody.new()
	add_child(body)
	body.set_quality(Game.quality)
	body.global_position = Vector3(-0.3, 0.0, 3.0)
	return body


func _process(_dt: float) -> void:
	FX.qvfx._aura.global_transform = Transform3D(Basis.from_scale(Vector3(0.78, 1.05, 0.78)), _hero.global_position + Vector3(0.0, 0.95, 0.0))
	if _wait > 0:
		_wait -= 1
		if _wait == 0 and _i >= 0 and _i < _ids.size():
			FX.qvfx.play_demo(_ids[_i], Vector3(0.0, 0.0, 0.0), 0.0)      # frame 0 of the effect: the pictures are taken at exact ages after this
		return
	if _i >= 0 and _i < _ids.size():
		_frame += 1
		var age := _frame / 30.0
		if _next_age < _ages.size() and age >= _ages[_next_age] - 0.001:
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s_%s_%03d.png" % [_out, _ids[_i], roundi(_ages[_next_age] * 1000.0)])
			_next_age += 1
		if _next_age >= _ages.size():
			_i += 1
			_start_next()
		return
	if _i < 0:
		_i = 0
		_start_next()
	else:
		print("VFX SHOWCASE DONE draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		get_tree().quit()


func _start_next() -> void:
	FX.reset()
	_frame = 0
	_next_age = 0
	_wait = 6                                                       # let the previous effect's last frames clear
	if _i >= _ids.size():
		return
	var id: StringName = _ids[_i]
	if id in [&"beam", &"bolt", &"shotgun"] and OS.get_environment("VFX_AGES") == "":      # short effects: earlier pictures
		_ages = [0.04, 0.1, 0.2]
	elif OS.get_environment("VFX_AGES") == "":
		_ages = [0.12, 0.3, 0.6]
