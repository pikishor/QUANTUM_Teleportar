extends Node3D
## Look-dev lineup of the Cars v2 set (round 6): many real Vehicle nodes in a grid on a wet floor under night lights, one image per view.
##   tools/carv2_lineup.sh /tmp/prefix kinds=sedan,sport,... view=front3q|rear3q|side|front|rear|top|low paint=auto|0..11 lod=auto|0|1|2 cols=6 gap=7.5 q=1 dist=34 night=1 damage=0
## The image is <out>_<view>.png. `lod` forces one LOD for every car (the camera distance would pick LOD1 for a far lineup), `paint=auto` walks through the 12 paints.

var _args := {}
var _cam: Camera3D
var _cars: Array[Vehicle] = []
var _wait := 14
var _view := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	var night := float(_args.get("night", "1"))
	RenderingServer.global_shader_parameter_set(&"night", night)
	RenderingServer.global_shader_parameter_set(&"wetness", float(_args.get("wet", "0.8")))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.1).lerp(Color(0.5, 0.65, 0.85), 1.0 - night)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.55)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = lerpf(1.2, 0.9, night)
	sun.light_color = Color(0.8, 0.85, 1.0)
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	add_child(sun)
	for p in [Vector3(-6.0, 4.0, 6.0), Vector3(12.0, 4.0, -8.0), Vector3(26.0, 4.0, 10.0)]:
		var neon := OmniLight3D.new()
		neon.light_color = Color(1.0, 0.25, 0.8) if p.x < 10.0 else Color(0.2, 0.9, 1.0)
		neon.light_energy = 2.0
		neon.omni_range = 16.0
		neon.position = p
		add_child(neon)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160.0, 160.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.1, 0.11, 0.13)
	fm.roughness = 0.35
	fm.metallic = 0.3
	fl.material_override = fm
	add_child(fl)
	VehicleVisual.ensure_key_light(self)
	_cam = Camera3D.new()
	_cam.fov = float(_args.get("fov", "38"))
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30
	var kinds := String(_args.get("kinds", "compact,sedan,racer,sport,muscle,suv,pickup,van,truck,bus,taxi,interceptor")).split(",", false)
	var cols := int(_args.get("cols", "6"))
	var gap := float(_args.get("gap", "7.5"))
	var rgap := float(_args.get("rgap", "13.0"))
	var rows := int(ceil(float(kinds.size()) / float(cols)))
	var lod := String(_args.get("lod", "auto"))
	for i in kinds.size():
		var car := Vehicle.new()
		add_child(car)
		car.setup(StringName(kinds[i]), null)
		var c := i % cols
		var r := i / cols
		var x := (float(c) - (cols - 1) * 0.5) * gap
		var z := (float(r) - (rows - 1) * 0.5) * rgap
		car.activate(Vector3(x, 0.0, z), float(_args.get("heading", "0")) * PI / 180.0)
		var pi := int(_args.get("paint", "-1")) if String(_args.get("paint", "auto")) != "auto" else i
		car.visual.set_paint(VehicleSpecs.COLORS[pi % VehicleSpecs.COLORS.size()])
		car.paint_i = pi % VehicleSpecs.COLORS.size()
		car.update_lod(0.0)
		car.visual.set_lights(float(_args.get("head", "0.9")), float(_args.get("tail", "0.7")), 1.0)
		var dmg := float(_args.get("damage", "0"))
		if dmg > 0.0:
			car.hp = car.max_hp * (1.0 - dmg)
			car.debug_damage(dmg)
		if lod != "auto":
			_force_lod(car, int(lod))
		_cars.append(car)
	_view = String(_args.get("view", "front3q"))
	_place_camera(rows, cols, gap, rgap)


func _force_lod(car: Vehicle, lod: int) -> void:
	var v := car.visual
	if v.v2 == null:
		return
	for mi: MeshInstance3D in [v.v2.body, v.v2.lod1, v.v2.lod2]:
		if mi != null:
			mi.visibility_range_begin = 0.0
			mi.visibility_range_end = 0.0
	v.v2.body.visible = lod == 0
	if v.v2.lod1 != null:
		v.v2.lod1.visible = lod == 1
	if v.v2.lod2 != null:
		v.v2.lod2.visible = lod == 2
	# the wheels are vertices of the Details surface of Body and Body_LOD1 (and baked into Body_LOD2): nothing else to switch


func _place_camera(rows: int, cols: int, gap: float, rgap: float) -> void:
	var d := float(_args.get("dist", "34"))
	var w := (cols - 1) * gap
	var pos := Vector3(0.0, 9.0, 0.0)
	var look := Vector3(0.0, 0.8, 0.0)
	match _view:
		"front3q": pos = Vector3(-d * 0.55, d * 0.30, -d * 0.75)
		"rear3q": pos = Vector3(d * 0.55, d * 0.30, d * 0.75)
		"front": pos = Vector3(0.0, d * 0.28, -d)
		"rear": pos = Vector3(0.0, d * 0.28, d)
		"side": pos = Vector3(-d, d * 0.22, 0.0)
		"top": pos = Vector3(0.0, d * 1.2, 0.1)
		"low": pos = Vector3(-d * 0.6, 1.6, -d * 0.8)
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)


func _process(_dt: float) -> void:
	_wait -= 1
	if _wait > 0:
		return
	if _wait == 0:
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/lineup"), _view])
		print("LINEUP DONE")
		get_tree().quit()
