extends Node3D
## Look-dev stage of the hero (wave 112, hero look v3): ONE PlayerBody on a floor under game-like lighting, shot from many camera presets at phone aspect. Not part of the test suite.
##   tools/hero/stage.sh OUT_PREFIX views=game,back,front,side,three,head suit=assault scheme=0 pose=run glow=flow:1.5:00e5ff light=dusk q=1 body=male hair=parted
## views: game back front side three threeb head bust legs shoulder far15 far40 far80 turn (front, three, side, threeb, back in one image row is made by tools/contact_sheet.py)
## pose: idle aim sprint walk dead hit glide fly (rig fields are written directly, like tests/hero_viewer.gd)
## light: dusk (default) day night studio.  glow=mode:intensity:hexcolor (the HeroLook.set_glow API).  lod=<n> forces a mesh LOD bias.  lens=<fov degrees> overrides the view's fov.

var _args := {}
var _body: PlayerBody
var _cam: Camera3D
var _views: PackedStringArray
var _i := 0
var _wait := 0
var _t := 0.0
var _sun: DirectionalLight3D
var _env: Environment


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	_views = String(_args.get("views", "game,back,front,side,three,head")).split(",", false)
	var light := String(_args.get("light", "dusk"))
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	match light:
		"day":
			psm.sky_top_color = Color(0.32, 0.5, 0.8)
			psm.sky_horizon_color = Color(0.7, 0.78, 0.88)
			psm.ground_bottom_color = Color(0.2, 0.2, 0.22)
			psm.ground_horizon_color = Color(0.55, 0.58, 0.62)
		"night":
			psm.sky_top_color = Color(0.02, 0.03, 0.07)
			psm.sky_horizon_color = Color(0.07, 0.09, 0.16)
			psm.ground_bottom_color = Color(0.02, 0.02, 0.03)
			psm.ground_horizon_color = Color(0.06, 0.07, 0.1)
		"studio":
			psm.sky_top_color = Color(0.16, 0.17, 0.2)
			psm.sky_horizon_color = Color(0.22, 0.23, 0.26)
			psm.ground_bottom_color = Color(0.1, 0.1, 0.11)
			psm.ground_horizon_color = Color(0.18, 0.19, 0.21)
		_:
			psm.sky_top_color = Color(0.1, 0.13, 0.25)
			psm.sky_horizon_color = Color(0.42, 0.34, 0.4)
			psm.ground_bottom_color = Color(0.06, 0.06, 0.08)
			psm.ground_horizon_color = Color(0.3, 0.28, 0.32)
	sky.sky_material = psm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME                  # the radiance map is complete in one frame (the default builds it over many frames: early captures were dark)
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.9 if light != "night" else 0.5
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_energy = {"day": 1.5, "night": 0.12, "studio": 0.5}.get(light, 0.9)
	_sun.light_color = {"day": Color(1.0, 0.96, 0.9), "night": Color(0.5, 0.6, 1.0), "studio": Color(1.0, 0.98, 0.95)}.get(light, Color(1.0, 0.72, 0.5))
	_sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	_sun.shadow_enabled = true
	add_child(_sun)
	if light == "dusk" or light == "night":                    # neon spill like the city: a cyan and a magenta lamp either side
		for spec: Array in [[Vector3(-3.0, 2.5, -2.0), Color(0.2, 0.9, 1.0)], [Vector3(3.5, 2.0, 2.5), Color(1.0, 0.3, 0.8)]]:
			var l := OmniLight3D.new()
			l.position = spec[0]
			l.light_color = spec[1]
			l.light_energy = 2.2
			l.omni_range = 9.0
			add_child(l)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300.0, 300.0)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.1, 0.105, 0.115) if light != "day" else Color(0.32, 0.33, 0.35)
	fm.roughness = 0.55
	floor_mi.material_override = fm
	add_child(floor_mi)
	PlayerBody.use_superhero = true
	_body = PlayerBody.new()
	add_child(_body)
	var look := HeroLook.new()
	look.body = StringName(str(_args.get("body", "male")))
	look.skin_tone = StringName(str(_args.get("skin", "dark")))
	look.hair = StringName(str(_args.get("hair", "parted")))
	look.beard = str(_args.get("beard", "0")) == "1"
	if _args.has("suit"):
		look.set("suit", StringName(str(_args["suit"])))
	if _args.has("scheme"):
		look.scheme = int(_args["scheme"])
	if _args.has("accent"):
		look.accent_hue = int(_args["accent"])
	_body.apply_look(look)
	_body.set_quality(int(_args.get("q", "1")))
	if _args.has("weapon"):
		_body.set_weapon_look(StringName(str(_args["weapon"])))
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 92.0
	_cam.far = 400.0
	add_child(_cam)
	_cam.make_current()
	if _args.has("dbg") and _body.hero_mat != null:
		_body.hero_mat.set_shader_parameter(&"dbg_view", float(_args["dbg"]))
	if _args.has("lod"):
		for n in _body.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).lod_bias = float(_args["lod"])
	print("STAGE hero opts ", _body._hero_opts, " tris ", _body.hero_info.get("tris", "?"), " info ", _body.hero_info)
	_wait = 36
	Engine.max_fps = 30


func _pose(dt: float) -> void:
	var rig := _body.rig
	if rig == null:
		return
	var p := String(_args.get("pose", "idle"))
	rig.ready = 1.0
	rig.ik = false
	rig.clock += dt
	match p:
		"sprint":
			rig.amp = 1.0
			rig.run = 1.0
			rig.sprint = 1.0
			rig.phase = 1.2 + _t * 7.0
		"run":
			rig.amp = 1.0
			rig.run = 1.0
			rig.phase = 1.2 + _t * 7.0
		"dead":
			rig.dead = 1.0
			rig.death_kind = int(_args.get("kind", "0"))
			rig.apply()
			_body.rotation = Vector3(0.2, 0.35, PI * 0.5)
			_body.global_position = Vector3.ZERO
			_body._rest_on_floor(0.0)
			return
		"aim":
			rig.aim_pitch = 0.1
		"walk":
			rig.amp = 0.6
			rig.phase = 0.8 + _t * 4.0
		"glide":
			rig.air = 1.0
	rig.apply()
	_body.sync_muzzle()
	_body.global_position = Vector3.ZERO
	_body.rotation = Vector3.ZERO


func _glow_args() -> void:
	if not _args.has("glow"):
		return
	var parts := String(_args["glow"]).split(":")
	var mode := StringName(parts[0])
	var inten := float(parts[1]) if parts.size() > 1 else 1.0
	var col := Color.html(parts[2]) if parts.size() > 2 else Color(0.2, 0.9, 1.0)
	HeroLook.set_glow(col, inten, mode)


func _process(dt: float) -> void:
	_t += dt
	_pose(dt)
	if _body.has_method(&"update_glow"):
		_glow_args()
		_body.call(&"update_glow", dt)
	if _wait > 0:
		_wait -= 1
		return
	var v := _views[_i]
	var c := Vector3(0.0, 1.0, 0.0)
	var pos := Vector3.ZERO
	var fov := 92.0
	var vh := 1.0
	var keep_w := false
	match v:
		"game": pos = Vector3(1.05, 1.62, 3.2); c = Vector3(0.45, 1.25, -5.0); fov = 92.0; keep_w = true
		"back": pos = Vector3(0.0, 1.2, 4.6); c = Vector3(0.0, 0.92, 0.0); fov = 30.0
		"backhi": pos = Vector3(0.0, 1.5, 3.2); c = Vector3(0.0, 1.25, 0.0); fov = 40.0
		"front": pos = Vector3(0.0, 1.2, -4.6); c = Vector3(0.0, 0.92, 0.0); fov = 30.0
		"side": pos = Vector3(4.6, 1.2, 0.0); c = Vector3(0.0, 0.92, 0.0); fov = 30.0
		"three": pos = Vector3(3.2, 1.5, -3.2); c = Vector3(0.0, 0.92, 0.0); fov = 30.0
		"threeb": pos = Vector3(3.2, 1.5, 3.2); c = Vector3(0.0, 0.92, 0.0); fov = 30.0
		"head": pos = Vector3(0.45, 1.68, -1.35); c = Vector3(0.0, 1.62, 0.0); fov = 24.0
		"headb": pos = Vector3(0.5, 1.72, 1.4); c = Vector3(0.0, 1.62, 0.0); fov = 24.0
		"bust": pos = Vector3(0.75, 1.6, -2.1); c = Vector3(0.0, 1.45, 0.0); fov = 26.0
		"bustb": pos = Vector3(0.75, 1.62, 2.1); c = Vector3(0.0, 1.45, 0.0); fov = 26.0
		"shoulder": pos = Vector3(1.4, 1.75, 1.5); c = Vector3(0.1, 1.42, 0.0); fov = 24.0
		"legs": pos = Vector3(2.2, 0.7, -2.4); c = Vector3(0.0, 0.5, 0.0); fov = 30.0
		"legsb": pos = Vector3(-2.2, 0.7, 2.4); c = Vector3(0.0, 0.5, 0.0); fov = 30.0
		"hands": pos = Vector3(1.2, 1.5, -1.8); c = Vector3(0.2, 1.3, -0.3); fov = 28.0
		"torso": pos = Vector3(0.6, 1.4, -2.2); c = Vector3(0.0, 1.2, 0.0); fov = 30.0
		"far15": pos = Vector3(0.0, 1.7, 15.0); c = Vector3(0.0, 1.2, 0.0); fov = 92.0; keep_w = true
		"far40": pos = Vector3(0.0, 1.9, 40.0); c = Vector3(0.0, 1.2, 0.0); fov = 92.0; keep_w = true
		"far80": pos = Vector3(0.0, 2.2, 80.0); c = Vector3(0.0, 1.2, 0.0); fov = 92.0; keep_w = true
		"far15x": pos = Vector3(0.0, 1.7, 15.0); c = Vector3(0.0, 1.0, 0.0); fov = 7.5          # the 15 m view magnified: what the silhouette looks like at 2400 px
		"far40x": pos = Vector3(0.0, 1.9, 40.0); c = Vector3(0.0, 1.0, 0.0); fov = 2.9
		"far80x": pos = Vector3(0.0, 2.2, 80.0); c = Vector3(0.0, 1.0, 0.0); fov = 1.5
	_cam.keep_aspect = Camera3D.KEEP_WIDTH if keep_w else Camera3D.KEEP_HEIGHT
	if _args.has("lens"):
		fov = float(_args["lens"])
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(c, Vector3.UP)
	_body.update_character_lights()
	if _wait == 0:
		_wait = -1
		return
	var tag := v
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/stage"), tag])
	_i += 1
	_wait = 4
	if _i >= _views.size():
		var rs := RenderingServer
		print("STAGE DONE draws=", rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			" tex_mb=", snappedf(float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0, 0.1))
		get_tree().quit()
