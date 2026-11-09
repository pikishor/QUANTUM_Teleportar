extends Node3D
## Look-dev viewer of the wildlife with the real shader and the real clips, on a plain ground (no city).
##   tools/wildlife_view.sh /tmp/prefix species=deer,wolf,goat,boar pose=walk|run|idle|sleep|dissolve views=side,3q [night=1] [t=0.7] [dist=7]
## Images: <out>_<views index>.png (one image per view, all species side by side facing right in `side`). `dissolve` shows the quantum-dust death at fraction t.

var _args := {}
var _cam: Camera3D
var _crits: Array[Critter] = []
var _views: PackedStringArray
var _vi := 0
var _wait := 14


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = 1
	RenderingServer.global_shader_parameter_set(&"night", float(_args.get("night", "0")))
	RenderingServer.global_shader_parameter_set(&"wetness", 0.0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.9) if _args.get("night", "0") == "0" else Color(0.05, 0.07, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.38, 0.2)
	fm.roughness = 0.95
	fl.material_override = fm
	add_child(fl)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ids := String(_args.get("species", "deer,wolf")).split(",", false)
	var pose := String(_args.get("pose", "walk"))
	var x := 0.0
	for id in ids:
		var sp := AnimalSpecies.data(StringName(id))
		var c := Critter.new()
		if not c.setup(StringName(id), sp):
			continue
		add_child(c)
		c.revive(rng)
		c.scale_k = float(sp.get("vis", 1.25))
		var lift := 0.0
		if String(sp["cls"]) == "air":
			lift = 1.6
		elif String(sp["cls"]) == "water":
			lift = 0.9
		c.position = Vector3(0.0, lift, x)
		c.heading = 0.0
		match pose:
			"sleep":
				c.asleep = true
				c.play(&"idle", 0.15)
			"dissolve":
				c.play(&"idle", 0.2)
				c.set_dissolve(float(_args.get("t", "0.5")))
			"run":
				c.play(&"run", float(_args.get("speed", "1.0")))
			"idle":
				c.play(&"idle", 1.0)
			_:
				c.play(&"walk", float(_args.get("speed", "1.0")))
		if String(sp["cls"]) == "air":
			c.play(&"fly", 1.0)
			c.bank = 0.35
		if String(sp["cls"]) == "water":
			c.play(&"swim", 1.0)
		c.apply_pose()
		_crits.append(c)
		x += float(_args.get("gap", "3.4"))
	_views = String(_args.get("views", "side")).split(",", false)
	_cam = Camera3D.new()
	_cam.fov = float(_args.get("fov", "35"))
	_cam.far = 500.0
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30


func _process(_d: float) -> void:
	if _vi >= _views.size():
		get_tree().quit()
		return
	var zc := float(_crits.size() - 1) * float(_args.get("gap", "3.4")) * 0.5
	var dist := float(_args.get("dist", "9"))
	var v := _views[_vi]
	var h := float(_args.get("h", "1.2"))
	match v:
		"3q":
			_cam.position = Vector3(dist * 0.8, h + 1.0, zc - dist * 0.6)
		"front":
			_cam.position = Vector3(0.0, h, zc - dist)
		"top":
			_cam.position = Vector3(0.01, dist * 1.4, zc)
		_:
			_cam.position = Vector3(dist, h, zc)
	_cam.look_at(Vector3(0.0, h * 0.6, zc), Vector3.FORWARD if v == "top" else Vector3.UP)
	_wait -= 1
	if _wait <= 0:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_args.get("out", "/tmp/wl"), _vi])
		_vi += 1
		_wait = 8
