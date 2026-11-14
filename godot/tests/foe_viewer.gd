extends Node3D
## Look-dev viewer of the humanoid roster enemies (FoeHuman) on a flat slab, no city, no streaming. tools/foe_view.sh /tmp/prefix ids=merc_rifle,auth_riot views=front3q,side,back [variants=0,1,2]
##   ids      look ids (default: all 13)         variants  0..2, one row per variant               views   front3q | side | back | front | rear3q | face | row (the whole row from the front)
##   pose     idle | aim | run | fire | hit | die | windup                              lod  near | mid | far (forces the mesh)        per  figures per image (default all)
##   yaw      body yaw in degrees               spacing  metres between figures (default 1.5)         hp  health 0..1 of the pips       tele  telegraph 0..1
## Images: <out>_<chunk>_<view>.png ; prints the triangles of the three meshes of every look.

var _args := {}
var _cam: Camera3D
var _ids: Array[StringName] = []
var _chunks: Array = []
var _ci := 0
var _vi := 0
var _wait := 12
var _views: PackedStringArray
var _live: Array[Dictionary] = []
var _frame := 0
var _pose := "idle"
var _nodes: Array[Node3D] = []
var _settle := 36
var _cap := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	_pose = String(_args.get("pose", "idle"))
	_views = String(_args.get("views", "front3q,side,back")).split(",", false)
	var want := String(_args.get("ids", "all"))
	if want == "all":
		for id in FoeLooks.IDS:
			_ids.append(id)
	else:
		for s in want.split(",", false):
			_ids.append(StringName(s))
	var variants := PackedStringArray(String(_args.get("variants", "0")).split(",", false))
	var per := int(_args.get("per", "0"))
	var items: Array = []
	for v in variants:
		for id in _ids:
			items.append([id, int(v)])
	if per <= 0:
		per = items.size()
	var i := 0
	while i < items.size():
		_chunks.append(items.slice(i, mini(i + per, items.size())))
		i += per
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.35, 0.5, 0.8)
	psm.sky_horizon_color = Color(0.75, 0.8, 0.88)
	psm.ground_horizon_color = Color(0.45, 0.42, 0.38)
	psm.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY if String(_args.get("bg", "sky")) == "sky" else Environment.BG_COLOR
	e.background_color = Color(0.5, 0.58, 0.7)
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.rotation_degrees = Vector3(-38.0, float(_args.get("sun", "212")), 0.0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300.0, 300.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.33, 0.29)
	fm.roughness = 0.95
	fl.material_override = fm
	add_child(fl)
	_cam = Camera3D.new()
	_cam.fov = float(_args.get("fov", "34"))
	_cam.far = 600.0
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30
	var t0 := Time.get_ticks_msec()
	var seen := {}
	for it: Array in items:
		var key := String(it[0])
		if seen.has(key):
			continue
		seen[key] = true
		if not FoeLooks.has(StringName(key)):
			continue
		var h := FoeHuman.build(StringName(key), 0)
		if h.is_empty():
			print("FOE cannot build ", key)
			continue
		FoeHuman.ensure_lods()
		print("FOE %-14s tris near %5d mid %5d far %5d  kit parts %d tris %d  weapon %s" % [key, FoeHuman.tris(FoeHuman.mesh_of(h, "near")), FoeHuman.tris(FoeHuman.mesh_of(h, "mid")), FoeHuman.tris(FoeHuman.mesh_of(h, "far")), FoeKit.part_count(StringName(key)),
				FoeKit.triangles(StringName(key)), h["weapon"]])
		print("      kit tris by lod 0/1/2: %d / %d / %d  split near %s" % [FoeKit.triangles(StringName(key), 0), FoeKit.triangles(StringName(key), 1), FoeKit.triangles(StringName(key), 2), (h["info"] as Dictionary).get("split", {})])
		(h["root"] as Node).free()
	print("FOE build time ", Time.get_ticks_msec() - t0, " ms for ", seen.size(), " looks")
	_spawn()


func _spawn() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_live.clear()
	var chunk: Array = _chunks[_ci]
	var spacing := float(_args.get("spacing", "1.5"))
	var width := spacing * float(chunk.size() - 1)
	var x := -width * 0.5
	for it: Array in chunk:
		if not FoeLooks.has(StringName(it[0])):
			var cr := _creature(StringName(it[0]))
			if cr.is_empty():
				continue
			var holder0 := Node3D.new()
			add_child(holder0)
			holder0.add_child(cr["root"])
			holder0.position = Vector3(x, 0.0, 0.0)
			holder0.rotation.y = deg_to_rad(float(_args.get("yaw", "0")))
			_nodes.append(holder0)
			cr["holder"] = holder0
			_live.append(cr)
			x += spacing * float(cr.get("wide", 1.0))
			continue
		var h := FoeHuman.build(StringName(it[0]), int(it[1]))
		if h.is_empty():
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.add_child(h["root"])
		holder.position = Vector3(x, 0.0, 0.0)
		holder.rotation.y = deg_to_rad(float(_args.get("yaw", "0")))
		_nodes.append(holder)
		var lodn := String(_args.get("lod", "near"))
		if lodn == "mid":
			FoeHuman.set_lod(h, 20.0)
		elif lodn == "far":
			FoeHuman.set_lod(h, 60.0)
		FoeHuman.set_hp(h, float(_args.get("hp", "1")))
		FoeHuman.set_tele(h, float(_args.get("tele", "0")))
		var far_k := float(_args.get("far", "0"))
		if far_k > 0.0:
			FoeHuman.set_far(h, far_k)
		h["holder"] = holder
		h["x"] = x
		_live.append(h)
		x += spacing
	_frame = 0
	_wait = 6


## A creature of tools/blender/model_foes.py (assets/models/foes/<id>.glb) on the alien shader, paused on a frame of a clip.
func _creature(id: StringName) -> Dictionary:
	var path := "res://assets/models/foes/%s.glb" % String(id)
	if not ResourceLoader.exists(path):
		print("FOE no model ", path)
		return {}
	var ps := load(path) as PackedScene
	var root := ps.instantiate() as Node3D
	var spec := RosterSpecies.data(id)
	var glow: Color = spec.get("glow", Color(1.0, 0.55, 0.12))
	var mat := FoeLooks.creature_material(glow, 0.5)
	var tris := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = mat
		mi.extra_cull_margin = 2.0
		tris = maxi(tris, HumanoidVariants.tris(mi.mesh))
	var ap: AnimationPlayer = null
	for n in root.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
	var clip := StringName(_args.get("clip", "idle"))
	if ap != null:
		if not ap.has_animation(clip):
			print("FOE clips of ", id, ": ", ap.get_animation_list())
		else:
			ap.play(clip)
			ap.seek(float(_args.get("t", "0.25")) * ap.get_animation(clip).length, true)
			ap.pause()
	print("FOE creature %-14s tris %d clips %s" % [id, tris, ap.get_animation_list() if ap != null else "-"])
	var sc := float(_args.get("scale", "1"))
	root.scale = Vector3.ONE * sc
	return {"creature": true, "root": root, "ap": ap, "wide": float(spec.get("r", 0.6)) * 2.4 / 1.5 + 0.3}


func _process(_dt: float) -> void:
	if _live.is_empty():
		if _ci >= _chunks.size():
			get_tree().quit()
		return
	var dt := 1.0 / 30.0
	_frame += 1
	for h: Dictionary in _live:
		if h.has("creature"):
			continue
		var holder := h["holder"] as Node3D
		var disp := Vector3.ZERO
		var moving := 0.0
		var firing := false
		var yaw := holder.rotation.y
		match _pose:
			"run":
				var step := 4.2 * dt
				disp = Vector3(-sin(yaw), 0.0, -cos(yaw)) * step
				holder.position += disp
				moving = 1.0
				firing = false
			"aim", "fire", "windup":
				firing = true
		if _frame == 2:
			match _pose:
				"aim", "fire":
					FoeHuman.aim(h, true)
				"windup":
					FoeHuman.windup(h, 3.0)
				"hit":
					FoeHuman.aim(h, true)
				"die":
					FoeHuman.aim(h, true)
		if _pose == "fire" and _frame > 4 and _frame % 9 == 0:
			FoeHuman.fire(h)
		if _pose == "hit" and _frame == _settle - 4:
			FoeHuman.hit(h, Vector2(0.0, 1.0), 1.0)
		if _pose == "die" and _frame == 12:
			FoeHuman.die(h, int(_args.get("death", "1")), 1.1)
		FoeHuman.drive(h, dt, disp, yaw, moving, firing, 0.0, 0.0)
	if _wait > 0:
		_wait -= 1
		return
	if _frame < _settle:
		return
	var chunk: Array = _chunks[_ci]
	var cx := 0.0
	for h: Dictionary in _live:
		cx += (h["holder"] as Node3D).position.x
	cx /= float(maxi(_live.size(), 1))
	var ctr := Vector3(cx, 0.95, (_live[0]["holder"] as Node3D).position.z)
	var span := maxf(float(chunk.size() - 1) * float(_args.get("spacing", "1.5")) + 1.6, 2.4)
	var v := _views[_vi]
	var dist := float(_args.get("dist", "0"))
	var d := dist if dist > 0.0 else 4.6 + span * 0.55
	var pos := ctr
	var lookat := ctr
	match v:
		"front3q": pos = ctr + Vector3(-d * 0.55, d * 0.1, -d * 0.85)
		"rear3q": pos = ctr + Vector3(d * 0.55, d * 0.1, d * 0.85)
		"side": pos = ctr + Vector3(d, d * 0.08, 0.0)
		"front": pos = ctr + Vector3(0.0, d * 0.08, -d)
		"back": pos = ctr + Vector3(0.0, d * 0.1, d)
		"row": pos = ctr + Vector3(0.0, d * 0.12, -d * 1.2)
		"face":
			pos = ctr + Vector3(-0.35, 0.78, -1.5)
			lookat = ctr + Vector3(0.0, 0.75, 0.0)
	_cam.global_position = pos
	_cam.look_at(lookat, Vector3.UP)
	_cap += 1
	if _cap < 4:
		return                                              # the viewport shows the camera of the last frame: wait for the new view to render
	_cap = 0
	var tag := "c%d" % _ci
	get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [_args.get("out", "/tmp/foe"), tag, v])
	_vi += 1
	if _vi >= _views.size():
		_vi = 0
		_ci += 1
		if _ci >= _chunks.size():
			print("VIEWER DONE")
			get_tree().quit()
			return
		_spawn()
