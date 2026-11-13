extends Node3D
## Look-dev viewer of a town without the game (fast): a flat pad, a straight main street, the whole plan built by SettlementKit in one mesh, a sun and a sky.
##   tools/settlement_view.sh /tmp/prefix style=farm views=aerial,street,house q=1 hour=12
## views: aerial | aerial2 | street | street2 | house | houseback | far | detail | fly:x,y,z,tx,ty,tz (town frame).  The images are <out>_<view>.png
## args: style (farm industrial suburb harbour resort lodge outpost), q (0..2), hour (12 day, 22 night), r / len (pad size), houses (target), seed (id suffix)

var _args := {}
var _cam: Camera3D
var _views: PackedStringArray
var _vi := 0
var _wait := 8
var _plan: SettlementPlan
var _built := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	var style: String = _args.get("style", "farm")
	_views = String(_args.get("views", "aerial,street,house")).split(",", false)
	var hour := float(_args.get("hour", "12"))
	var night := 1.0 if (hour >= 20.0 or hour < 5.0) else 0.0
	RenderingServer.global_shader_parameter_set("night", night)
	RenderingServer.global_shader_parameter_set("wetness", float(_args.get("wet", "0")))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.78) if night < 0.5 else Color(0.02, 0.03, 0.08)
	sm.sky_horizon_color = Color(0.7, 0.8, 0.9) if night < 0.5 else Color(0.06, 0.07, 0.12)
	sm.ground_horizon_color = sm.sky_horizon_color
	sm.ground_bottom_color = Color(0.3, 0.32, 0.28) if night < 0.5 else Color(0.02, 0.02, 0.03)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9 if night < 0.5 else 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.8, 0.88) if night < 0.5 else Color(0.05, 0.06, 0.1)
	e.fog_density = 0.0016
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25 if night < 0.5 else 0.12
	sun.light_color = Color(1.0, 0.95, 0.85) if night < 0.5 else Color(0.6, 0.7, 1.0)
	sun.rotation_degrees = Vector3(-46.0, 38.0, 0.0) if hour < 17.0 else Vector3(-14.0, 60.0, 0.0)
	sun.shadow_enabled = Game.quality >= 1
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	# the site: a flat pad (the viewer's own ground), the real size of the style
	var site := {"id": StringName("view_" + style + String(_args.get("seed", ""))), "style": StringName(style), "r": float(_args.get("r", "100")), "len": float(_args.get("len", "160")), "houses": int(_args.get("houses", "30"))}
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 1400.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.4, 0.3) if style in ["outpost", "industrial", "suburb"] else Color(0.3, 0.4, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.02
	add_child(ground)
	var road := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(12.0, 700.0)
	road.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.16, 0.16, 0.18)
	rmat.roughness = 0.9
	road.material_override = rmat
	road.position.y = 0.02
	add_child(road)
	var street := PackedVector2Array()
	for i in 17:
		street.append(Vector2(0.0, -float(site["len"]) - 20.0 + float(i) * (2.0 * float(site["len"]) + 40.0) / 16.0))
	var t0 := Time.get_ticks_msec()
	_plan = SettlementPlan.build(site, street)
	var t1 := Time.get_ticks_msec()
	_built = SettlementKit.build(_plan)
	var t2 := Time.get_ticks_msec()
	var mi := MeshInstance3D.new()
	var m: SettlementMesh = _built["mesh"]
	mi.mesh = m.to_mesh(SettlementKit.material())
	mi.material_override = SettlementKit.material()
	add_child(mi)
	for rt: Dictionary in _built["rotors"]:
		var rn := MeshInstance3D.new()
		rn.mesh = (rt["mesh"] as SettlementMesh).to_mesh(SettlementKit.material())
		rn.material_override = SettlementKit.material()
		rn.position = rt["pos"]
		rn.rotation.y = float(rt["yaw"])
		add_child(rn)
	print("PLAN ", style, " items ", _plan.items.size(), " houses ", _plan.houses, " props ", _plan.props.size(), " ground ", _plan.ground.size(), " fences ", _plan.fences.size(), " parked ", _plan.parked.size(), " plan ms ", t1 - t0, " kit ms ", t2 - t1, " tris ", m.tris(), " verts ", m.vcount())
	_cam = Camera3D.new()
	_cam.fov = float(_args.get("fov", "70"))
	_cam.far = 3000.0
	add_child(_cam)
	_cam.make_current()
	_place(_views[0])


func _first_house() -> Dictionary:
	for it in _plan.items:
		if it["kind"] == &"house":
			return it
	return _plan.items[0] if not _plan.items.is_empty() else {"x": 0.0, "z": 0.0, "yaw": 0.0}


func _place(v: String) -> void:
	var hh := _first_house()
	match v:
		"aerial":
			_cam.position = Vector3(95.0, 70.0, -150.0)
			_cam.look_at(Vector3(0.0, 4.0, -10.0), Vector3.UP)
		"aerial2":
			_cam.position = Vector3(-120.0, 55.0, 120.0)
			_cam.look_at(Vector3(0.0, 4.0, 0.0), Vector3.UP)
		"street":
			_cam.position = Vector3(1.5, 1.8, -_plan.ln - 8.0)
			_cam.look_at(Vector3(0.0, 2.5, 0.0), Vector3.UP)
		"street2":
			_cam.position = Vector3(-6.0, 3.2, 40.0)
			_cam.look_at(Vector3(6.0, 2.0, 100.0), Vector3.UP)
		"far":
			_cam.position = Vector3(300.0, 30.0, -420.0)
			_cam.look_at(Vector3(0.0, 8.0, 0.0), Vector3.UP)
		"house":
			var p := Vector3(float(hh["x"]), 0.0, float(hh["z"]))
			var f := Basis(Vector3.UP, float(hh["yaw"])) * Vector3(0.0, 0.0, -1.0)
			_cam.position = p + f * 17.0 + Vector3(f.z * 4.0, 2.2, -f.x * 4.0)
			_cam.look_at(p + Vector3(0.0, 2.6, 0.0), Vector3.UP)
		"houseback":
			var p2 := Vector3(float(hh["x"]), 0.0, float(hh["z"]))
			var f2 := Basis(Vector3.UP, float(hh["yaw"])) * Vector3(0.0, 0.0, -1.0)
			_cam.position = p2 - f2 * 16.0 + Vector3(-f2.z * 6.0, 4.0, f2.x * 6.0)
			_cam.look_at(p2 + Vector3(0.0, 2.6, 0.0), Vector3.UP)
		"detail":
			var p3 := Vector3(float(hh["x"]), 0.0, float(hh["z"]))
			var f3 := Basis(Vector3.UP, float(hh["yaw"])) * Vector3(0.0, 0.0, -1.0)
			_cam.position = p3 + f3 * 9.0 + Vector3(f3.z * 2.0, 1.7, -f3.x * 2.0)
			_cam.look_at(p3 + Vector3(0.0, 1.8, 0.0), Vector3.UP)
		_:
			if v.begins_with("fly:"):
				var a := v.substr(4).split(",")
				_cam.position = Vector3(float(a[0]), float(a[1]), float(a[2]))
				_cam.look_at(Vector3(float(a[3]), float(a[4]), float(a[5])), Vector3.UP)


func _process(_d: float) -> void:
	if _cam == null:
		return
	_wait -= 1
	if _wait > 0:
		return
	var name_v := _views[_vi]
	var tag := name_v.replace(":", "_").replace(",", "_")
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_args.get("out", "/tmp/sv"), tag])
	_vi += 1
	if _vi >= _views.size():
		get_tree().quit()
		return
	_place(_views[_vi])
	_wait = 6
