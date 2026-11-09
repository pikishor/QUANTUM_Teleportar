extends Node3D
## Look-dev viewer of the alien creatures on a flat sand slab (no city, no terrain streaming): each creature stands still (the AlienWorld is NOT stepped) so the models and the
## procedural bodies can be inspected. tools/alien_view.sh /tmp/prefix ids=skitter,grunt,brute views=front3q,side,top [q=1] [hour=day]
## views: front3q | side | rear3q | front | top | far.   Images: <out>_<id>_<view>.png ; `lineup=1` puts all ids in a row and shoots one image per view (<out>_lineup_<view>.png)

var _args := {}
var _cam: Camera3D
var _ids: PackedStringArray
var _views: PackedStringArray
var _ii := 0
var _vi := 0
var _wait := 8
var _world: AlienWorld
var _live: Array[AlienCreature] = []
var _lineup := false
var _site_mode := false
var _site_node: MeshInstance3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			_args[kv[0]] = kv[1]
	Game.quality = int(_args.get("q", "1"))
	_ids = String(_args.get("ids", "skitter,hive_grunt,crag_brute")).split(",", false)
	_views = String(_args.get("views", "front3q,side")).split(",", false)
	_lineup = _args.has("lineup")
	if _args.has("sites"):                                   # sites=ridge_camp,forest_nest : the site meshes at the origin (heights relative to their pad), views as for creatures
		_ids = String(_args["sites"]).split(",", false)
		_site_mode = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85) if String(_args.get("hour", "day")) == "day" else Color(0.05, 0.07, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.66, 0.76)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300.0, 300.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.42, 0.3)
	fm.roughness = 0.95
	fl.material_override = fm
	add_child(fl)
	_world = AlienWorld.new()
	add_child(_world)
	_world.ambient_enabled = false
	_world.force_active = false
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 600.0
	add_child(_cam)
	_cam.make_current()
	Engine.max_fps = 30
	AlienSites.ensure()
	if _lineup:
		var x := 0.0
		for id in _ids:
			var c := _world.make(StringName(id))
			if c == null:
				continue
			add_child(c)
			var w := maxf(c.radius * 2.6, 2.2)
			x += w * 0.5
			c.position = Vector3(x, 0.0, 0.0)
			x += w * 0.5
			_place(c)
			_live.append(c)
		for c in _live:
			c.position.x -= x * 0.5
	else:
		_next()


func _place(c: AlienCreature) -> void:
	c.rise = 1.0
	c.set_exposed(true)
	if c is RosterFoe:
		(c as RosterFoe).cloak_k = 0.0                       # look-dev: the veil stalker is shown uncloaked
	c.heading = float(_args.get("yaw", "0")) * PI / 180.0
	c.alt = 4.0
	if c.cls == AlienSpecies.AIR:
		c.position.y = c.alt
	c._apply()
	if c.ap != null:
		var clip := StringName(_args.get("clip", "idle"))
		if c.ap.has_animation(clip):
			c.ap.play(clip)
			c.ap.seek(float(_args.get("t", "0.3")), true)
		elif c.ap.has_animation(&"fly"):
			c.ap.play(&"fly")
			c.ap.seek(0.2, true)


func _next() -> void:
	for c in _live:
		c.queue_free()
	_live.clear()
	if _site_mode:
		if _site_node != null:
			_site_node.queue_free()
		var st := AlienSites.by_id(StringName(_ids[_ii]))
		var kit := AlienSiteKit.build(st)
		_site_node = MeshInstance3D.new()
		_site_node.mesh = kit["mesh"]
		_site_node.material_override = AlienKit.site_material()
		add_child(_site_node)
		var guard := _world.make(&"hive_grunt")
		add_child(guard)
		guard.position = Vector3(0.0, 0.0, 0.0)
		_live.append(guard)
		guard.queue_free()
		_live.clear()
		print("site ", _ids[_ii], " tris ", kit["tris"])
		return
	var c := _world.make(StringName(_ids[_ii]))
	if c == null:
		print("cannot make ", _ids[_ii])
		_ii += 1
		return
	add_child(c)
	c.position = Vector3.ZERO
	_place(c)
	_live.append(c)


func _process(_dt: float) -> void:
	if _wait > 0:
		_wait -= 1
		return
	if _live.is_empty() and not _site_mode:
		get_tree().quit()
		return
	if _site_mode:
		var tgt := Vector3(0.0, 8.0, 0.0)
		var dd := float(_args.get("d", "60"))
		var vv := _views[_vi]
		var cp := tgt + (Vector3(-dd * 0.6, dd * 0.35, -dd * 0.8) if vv == "front3q" else (Vector3(dd * 0.9, dd * 0.3, dd * 0.4) if vv == "side" else Vector3(0.0, dd, 0.1)))
		_cam.global_position = cp
		_cam.look_at(tgt, Vector3.UP)
		_wait -= 1
		if _wait > -4:
			return
		get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [_args.get("out", "/tmp/a"), _ids[_ii], vv])
		_wait = 3
		_vi += 1
		if _vi >= _views.size():
			_vi = 0
			_ii += 1
			if _ii >= _ids.size():
				print("VIEWER DONE")
				get_tree().quit()
				return
			_next()
			_wait = 6
		return
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for c in _live:
		for s: Array in c.shapes:
			var p := c.position + c._to_world(s[0] as Vector3)
			var r := float(s[1]) * c.vis
			lo = lo.min(p - Vector3(r, r, r))
			hi = hi.max(p + Vector3(r, r, r))
	var ctr := (lo + hi) * 0.5
	var ext := (hi - lo)
	var size := maxf(maxf(ext.x, ext.y * 1.2), ext.z) + 1.0
	var d := size * (1.4 if not _lineup else 1.15)
	var v := _views[_vi]
	var pos := ctr
	match v:
		"front3q": pos = ctr + Vector3(-d * 0.6, d * 0.18, -d * 0.8)
		"rear3q": pos = ctr + Vector3(d * 0.6, d * 0.18, d * 0.8)
		"side": pos = ctr + Vector3(d, d * 0.12, 0.0)
		"front": pos = ctr + Vector3(0.0, d * 0.12, -d)
		"top": pos = ctr + Vector3(0.0, d, 0.1)
		"far": pos = ctr + Vector3(-d * 1.6, d * 0.3, -d * 1.6)
	_cam.global_position = pos
	_cam.look_at(ctr, Vector3.UP)
	_wait -= 1
	if _wait > -4:
		return
	var tag := "lineup" if _lineup else String(_ids[_ii])
	get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [_args.get("out", "/tmp/a"), tag, v])
	_wait = 3
	_vi += 1
	if _vi >= _views.size():
		_vi = 0
		_ii += 1
		if _lineup or _ii >= _ids.size():
			print("VIEWER DONE")
			get_tree().quit()
			return
		_next()
		_wait = 6
