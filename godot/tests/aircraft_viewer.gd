extends Node3D
## Look-dev viewer of the aircraft in daylight on an apron slab (no city): real Vehicle nodes, a hero beside them for scale, spinning rotors frozen by their blur discs.
##   tools/aircraft_view.sh /tmp/prefix kinds=gunship,jet views=front3q,side,rear3q,top,chase [paint=1] [q=1] [burn=1]
## views: front3q | side | rear3q | front | rear | top | chase | cockpit. Images: <out>_<kind>_<view>.png

var _args := {}
var _cam: Camera3D
var _kinds: PackedStringArray
var _views: PackedStringArray
var _ki := 0
var _vi := 0
var _wait := 10
var _hero: PlayerBody
var _car: Vehicle


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	_kinds = String(_args.get("kinds", "gunship,jet")).split(",", false)
	_views = String(_args.get("views", "front3q,side,rear3q")).split(",", false)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.7, 0.9)
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
	pm.size = Vector2(400.0, 400.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.46, 0.46)
	fm.roughness = 0.9
	fl.material_override = fm
	add_child(fl)
	PlayerBody.use_superhero = true
	_hero = PlayerBody.new()
	add_child(_hero)
	_hero.set_quality(1)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30
	_next()


func _next() -> void:
	if is_instance_valid(_car):
		_car.deactivate()
		_car.queue_free()
	_car = Vehicle.new()
	add_child(_car)
	_car.setup(StringName(_kinds[_ki]), null)
	_car.activate(Vector3.ZERO, 0.0)
	_car.visual.set_paint(VehicleSpecs.COLORS[int(_args.get("paint", "5"))])
	_car.update_lod(0.0)
	_car.visual.set_lights(0.0, 0.0, 0.0)
	var wid := float(_car.spec["wid"])
	_hero.global_position = Vector3(wid * 0.5 + 1.8, 0.0, float(_car.spec["len"]) * 0.18)
	_hero.rotation.y = 2.2
	if _args.has("burn") and _car.craft != null:
		_car.craft.lever = 1.0
		_car.craft.spool = 1.0


func _process(_dt: float) -> void:
	if _hero.rig != null:
		_hero.rig.apply()
	if _wait > 0:
		_wait -= 1
		return
	var ln: float = float(_car.spec["len"])
	var hg: float = float(_car.spec["hgt"])
	var d := maxf(ln * 1.5, 9.0)
	var v := _views[_vi]
	var pos := Vector3.ZERO
	var look := Vector3(0.0, hg * 0.45, 0.0)
	_cam.fov = 40.0
	match v:
		"front3q": pos = Vector3(-d * 0.75, hg * 0.9 + 1.0, -d * 0.8)
		"rear3q": pos = Vector3(d * 0.75, hg * 0.9 + 1.0, d * 0.8)
		"side": pos = Vector3(d * 1.1, hg * 0.6, 0.0)
		"front": pos = Vector3(0.0, hg * 0.7, -d * 1.1)
		"rear": pos = Vector3(0.0, hg * 0.7 + 0.2, d * 1.1)
		"top": pos = Vector3(0.0, d * 1.3, 0.1)
		"chase":
			var cd := float(_car.spec.get("cam_d", 20.0))
			var ch := float(_car.spec.get("cam_h", 5.0))
			pos = Vector3(0.0, ch, cd)
			look = Vector3(0.0, hg * 0.5, -cd * 0.4)
			_cam.fov = 66.0
		"cockpit":
			pos = Vector3(0.0, hg * 0.7, -ln * 0.2)
			look = Vector3(0.0, hg * 0.6, -50.0)
			_cam.fov = 80.0
	_hero.visible = v != "chase" and v != "cockpit"
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_wait -= 1
	if _wait > -4:
		return
	var tag := "%s_%s" % [_kinds[_ki], v]
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/a"), tag])
	_wait = 3
	_vi += 1
	if _vi >= _views.size():
		_vi = 0
		_ki += 1
		if _ki >= _kinds.size():
			print("VIEWER DONE")
			get_tree().quit()
			return
		_next()
		_wait = 6
