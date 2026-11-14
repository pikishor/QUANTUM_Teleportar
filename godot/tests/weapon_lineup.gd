extends Node3D
## Look-dev lineup of the weapons (wave 114): every weapon of a batch in a grid, studio light and reflections, one orthographic camera, names under the weapons.
##   xvfb-run -a -s "-screen 0 2400x1350x24" godot --rendering-driver vulkan --rendering-method mobile --resolution 2400x1350 --path . res://tests/weapon_lineup.tscn -- out=/tmp/l batch=0 per=40 cols=8 view=side lod=0
## args: ids=a,b,c (else the batch: all_ids() sliced by batch / per) cols=N view=side|q34|top|front lod=0|1 out=prefix true=1 (true relative size, else every weapon fitted into its cell) q=quality
## The picture is <out>.png

var _args := {}
var _wait := 0
var _ids: Array[StringName] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.14)
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.45, 0.55, 0.8)
	psm.sky_horizon_color = Color(0.85, 0.88, 0.95)
	psm.ground_horizon_color = Color(0.45, 0.47, 0.55)
	psm.ground_bottom_color = Color(0.16, 0.18, 0.26)
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.4
	key.light_color = Color(1.0, 0.96, 0.9)
	key.rotation_degrees = Vector3(-35.0, 55.0, 0.0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.0
	rim.light_color = Color(0.5, 0.75, 1.0)
	rim.rotation_degrees = Vector3(-20.0, 160.0, 0.0)
	add_child(rim)
	var all: Array[StringName] = WeaponDefs.all_ids()
	if _args.has("ids"):
		for s in String(_args["ids"]).split(",", false):
			_ids.append(StringName(s))
	else:
		var per := int(_args.get("per", "40"))
		var b := int(_args.get("batch", "0"))
		for i in range(b * per, mini(all.size(), (b + 1) * per)):
			_ids.append(all[i])
	var cols := int(_args.get("cols", "8"))
	var lod := int(_args.get("lod", "0"))
	var view := String(_args.get("view", "side"))
	var true_scale := String(_args.get("true", "0")) == "1"
	var cell := Vector2(1.5, 0.62)
	var rows := int(ceil(float(_ids.size()) / float(cols)))
	var yaw := 0.0
	var pitch := 0.0
	match view:
		"q34":
			yaw = deg_to_rad(-38.0)
			pitch = deg_to_rad(-12.0)
		"top":
			pitch = deg_to_rad(-90.0)
		"front":
			yaw = deg_to_rad(-90.0)
	for i in _ids.size():
		var id := _ids[i]
		var r := i / cols
		var c := i % cols
		var center := Vector3(0.0, (float(rows) * 0.5 - float(r) - 0.5) * cell.y, (float(cols) * 0.5 - float(c) - 0.5) * -cell.x)
		var w := WeaponModels.build(id, lod)
		if _args.has("dbg"):
			var mat := WeaponModels.pbr_material_copy()
			mat.set_shader_parameter(&"dbg", int(_args["dbg"]))
			(w.get_node("Body") as MeshInstance3D).material_override = mat
		add_child(w)
		var bb := _aabb(w)
		var sc := 1.0
		if not true_scale:
			sc = clampf(minf(cell.x * 0.86 / maxf(bb.size.z, 0.01), cell.y * 0.7 / maxf(bb.size.y, 0.01)), 0.3, 6.0)
		else:
			sc = 1.0
		var pivot := Node3D.new()
		add_child(pivot)
		remove_child(w)
		pivot.add_child(w)
		w.position = -bb.get_center() * sc
		w.scale = Vector3.ONE * sc
		pivot.position = center
		pivot.rotation = Vector3(pitch, yaw, 0.0)
		var lab := Label3D.new()
		lab.text = "%s  %s" % [String(id), String(WeaponDefs.def(id).get("name", ""))]
		lab.pixel_size = 0.0016
		lab.font_size = 36
		lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lab.rotation_degrees = Vector3(0, 90, 0)
		lab.position = center + Vector3(0.01, -cell.y * 0.43, 0.0)
		lab.modulate = Color(1.0, 0.86, 0.5)
		lab.no_depth_test = true
		add_child(lab)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var W := float(cols) * cell.x
	var H := float(rows) * cell.y
	var aspect := float(get_viewport().size.x) / float(get_viewport().size.y)
	cam.size = maxf(H * 1.02, W / aspect * 1.02)
	cam.position = Vector3(8.0, 0.0, 0.0)
	cam.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	cam.near = 0.5
	cam.far = 40.0
	add_child(cam)
	cam.make_current()
	Engine.max_fps = 30
	_wait = 12


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a := m.global_transform * m.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _process(_dt: float) -> void:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path := String(_args.get("out", "/tmp/weapon_lineup")) + ".png"
			img.save_png(path)
			print("LINEUP saved ", path, " ", img.get_size(), " weapons ", _ids.size())
			get_tree().quit()
