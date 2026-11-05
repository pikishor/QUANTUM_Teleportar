extends Node3D
## Look-dev viewer of the superhero without the city (fast): a PlayerBody on a floor under a sky light, shot from several sides.
##   xvfb-run -a godot --rendering-driver vulkan --rendering-method mobile --resolution 1280x720 --path . res://tests/hero_viewer.tscn -- out=/tmp/v views=front,side,back,head,three body=male skin=dark hair=parted beard=0 pose=idle q=1
## pose: idle | aim | sprint | dead | hit      The images are <out>_<view>.png

var _args := {}
var _body: PlayerBody
var _cam: Camera3D
var _views: PackedStringArray
var _i := 0
var _wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	_views = String(_args.get("views", "front,side,back,head,three")).split(",", false)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.38, 0.45)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.13, 0.15)
	fm.roughness = 0.6
	floor_mi.material_override = fm
	add_child(floor_mi)
	PlayerBody.use_superhero = str(_args.get("old", "0")) != "1"
	_body = PlayerBody.new()
	add_child(_body)
	var look := HeroLook.new()
	look.body = StringName(str(_args.get("body", "male")))
	look.skin_tone = StringName(str(_args.get("skin", "dark")))
	look.hair = StringName(str(_args.get("hair", "parted")))
	look.beard = str(_args.get("beard", "0")) == "1"
	_body.apply_look(look)
	print("VIEWER hero ", look.body, look.skin_tone, look.hair, " ", _body._hero_opts, " inside ", _body.is_inside_tree(), " args ", _args)
	_body.set_quality(int(_args.get("q", "1")))
	_cam = Camera3D.new()
	_cam.fov = 38.0
	add_child(_cam)
	_cam.make_current()
	_wait = 8
	Engine.max_fps = 30


func _pose() -> void:
	var rig := _body.rig
	if rig == null:
		return
	var p := String(_args.get("pose", "idle"))
	rig.ready = 1.0
	rig.ik = false
	match p:
		"sprint":
			rig.amp = 1.0
			rig.run = 1.0
			rig.sprint = 1.0
			rig.phase = 1.2
		"dead":
			rig.dead = 1.0
			rig.death_kind = int(_args.get("kind", "0"))
			rig.apply()
			_body.rotation = Vector3(0.2, 0.35, PI * 0.5)
			_body.global_position = Vector3(0.0, 0.0, 0.0)
			_body._rest_on_floor(0.0)
			return
		"aim":
			rig.aim_pitch = 0.2
		"walk":
			rig.amp = 0.6
			rig.phase = 0.8
	rig.apply()
	_body.global_position = Vector3.ZERO


func _process(_dt: float) -> void:
	_pose()
	if _wait > 0:
		_wait -= 1
		return
	if _i > 0 or true:
		var v := _views[_i]
		var c := Vector3(0.0, 1.0, 0.0)
		var pos := Vector3.ZERO
		match v:
			"front": pos = Vector3(0.0, 1.2, -3.4); _cam.fov = 38.0
			"side": pos = Vector3(3.4, 1.2, 0.0)
			"back": pos = Vector3(0.0, 1.2, 3.4)
			"three": pos = Vector3(2.4, 1.5, -2.6)
			"head": pos = Vector3(0.45, 1.65, -1.0); c = Vector3(0.0, 1.62, 0.0)
			"head3": pos = Vector3(-0.8, 1.85, -0.9); c = Vector3(0.0, 1.62, 0.0)
			"headb": pos = Vector3(0.4, 1.75, 1.0); c = Vector3(0.0, 1.62, 0.0)
			"headf": pos = Vector3(0.0, 1.68, -1.0); c = Vector3(0.0, 1.62, 0.0)
			"rifle": pos = Vector3(1.5, 1.5, -1.4); c = Vector3(0.0, 1.3, -0.4)
		_cam.global_position = pos
		_cam.look_at(c, Vector3.UP)
		_body.update_character_lights()       # the key / rim follow the camera, as in the game
		if _wait == 0:
			_wait = -1
			return
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/v"), v])
		_i += 1
		_wait = 4
		if _i >= _views.size():
			print("VIEWER DONE draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			get_tree().quit()
