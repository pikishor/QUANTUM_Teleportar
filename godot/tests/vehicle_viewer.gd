extends Node3D
## Look-dev viewer of the cars without the city (fast): real Vehicle nodes on a wet floor under night-ish lights, a hero beside them for scale.
##   tools/vehicle_view.sh /tmp/prefix kinds=sedan,sport views=front3q,side,rear3q,chase damage=0,0.5,0.9 q=1
## views: front3q | side | rear3q | front | rear | chase | hood | top.  damage: hull damage fractions (0 sound .. 1 wrecked), one image per value.
## The images are <out>_<kind>_<view>_<damage>.png

var _args := {}
var _cam: Camera3D
var _cars: Array[Vehicle] = []
var _kinds: PackedStringArray
var _views: PackedStringArray
var _dmg: PackedStringArray
var _ki := 0
var _vi := 0
var _di := 0
var _wait := 10
var _hero: PlayerBody
var _car: Vehicle


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	_kinds = String(_args.get("kinds", "sedan,sport,suv")).split(",", false)
	_views = String(_args.get("views", "front3q,side,rear3q")).split(",", false)
	_dmg = String(_args.get("damage", "0")).split(",", false)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.55)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	sun.light_color = Color(0.8, 0.85, 1.0)
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	add_child(sun)
	var neon := OmniLight3D.new()
	neon.light_color = Color(1.0, 0.25, 0.8)
	neon.light_energy = 2.0
	neon.omni_range = 14.0
	neon.position = Vector3(-5.0, 3.0, 3.0)
	add_child(neon)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.1, 0.11, 0.13)
	fm.roughness = 0.35
	fm.metallic = 0.3
	fl.material_override = fm
	add_child(fl)
	PlayerBody.use_superhero = true
	_hero = PlayerBody.new()
	add_child(_hero)
	_hero.set_quality(1)
	_hero.global_position = Vector3(2.6, 0.0, 1.4)
	_hero.rotation.y = 2.2
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30
	_next_car()


func _next_car() -> void:
	if is_instance_valid(_car):
		_car.deactivate()
		_car.queue_free()
	_car = Vehicle.new()
	add_child(_car)
	_car.setup(StringName(_kinds[_ki]), null)
	_car.activate(Vector3.ZERO, 0.0)
	_car.visual.set_paint(VehicleSpecs.COLORS[int(_args.get("paint", "1"))])
	_car.update_lod(0.0)
	_car.visual.set_lights(0.9, 0.7, 1.0)
	if _args.has("steer"):
		_car.visual.spin(0.0, float(_args["steer"]))               # steer=0.4: the front wheels turned LEFT by 0.4 rad (Vehicle.steer_angle is + = left)
	_apply_damage()


func _apply_damage() -> void:
	var f := float(_dmg[_di])
	_car.hp = _car.max_hp * (1.0 - f)
	if f > 0.0:
		_car.debug_damage(f)


func _process(_dt: float) -> void:
	if _hero.rig != null:
		_hero.rig.apply()
	if _wait > 0:
		_wait -= 1
		return
	var ln: float = float(_car.spec["len"])
	var hg: float = float(_car.spec["hgt"])
	var d := maxf(ln * 1.25, 5.5)
	var v := _views[_vi]
	var pos := Vector3.ZERO
	var look := Vector3(0.0, hg * 0.45, 0.0)
	_cam.fov = 40.0
	match v:
		"front3q": pos = Vector3(-d * 0.75, hg * 0.9 + 0.5, -d * 0.7)
		"rear3q": pos = Vector3(d * 0.75, hg * 0.9 + 0.5, d * 0.7)
		"side": pos = Vector3(d * 1.1, hg * 0.6, 0.0)
		"front": pos = Vector3(0.0, hg * 0.7, -d * 1.1)
		"rear": pos = Vector3(0.0, hg * 0.7 + 0.2, d * 1.1)
		"top": pos = Vector3(0.0, d * 1.3, 0.1)
		"chase":
			pos = Vector3(0.0, 2.6, 8.6)
			look = Vector3(0.0, 1.0, -4.0)
			_cam.fov = 72.0
		"hood":
			pos = Vector3(0.0, hg * 0.93, -ln * 0.05)
			look = Vector3(0.0, hg * 0.85, -20.0)
			_cam.fov = 80.0
	_hero.visible = v != "chase" and v != "hood"
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_wait -= 1
	if _wait > -4:
		return
	var tag := "%s_%s_%s" % [_kinds[_ki], v, _dmg[_di]]
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/v"), tag])
	_wait = 3
	_vi += 1
	if _vi >= _views.size():
		_vi = 0
		_di += 1
		if _di >= _dmg.size():
			_di = 0
			_ki += 1
			if _ki >= _kinds.size():
				print("VIEWER DONE")
				get_tree().quit()
				return
			_next_car()
			_wait = 6
			return
		_apply_damage()
		_wait = 6
