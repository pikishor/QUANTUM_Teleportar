extends RefCounted
## Glitch scan bot: real-game-camera frames at the phone aspect (touch HUD on) of the places where the owner saw translucent slabs, white sheets and the black hero patch.
##   GLITCH_OUT=<dir> GLITCH_SPOTS=a,b GLITCH_HOUR=12 BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_glitch_scan.gd /tmp/x 100000 1
## Spots: street_<hour> (spawn crosswalk, hero from behind), int_<type> (hero from behind in a door's interior), hero_back / hero_side (closeups), hud_off variants add `_clean`.
## Prints GLITCH <spot> <flat-translucent fraction> <rect> per shot. The same numeric check is VisualQaLib.translucent_slabs.
const SETTLE := 14
var _i := 0
var _wait := 0
var _spots: Array[String] = []
var _out := ""
var _p: Player
var _hud: Hud
var _cine: Transform3D
var _use_cine := false
var _hide_hud := false
var _tp_done := false
var _burst_at := 0.0
var _layers := false                         ## GLITCH_LAYERS=1: after each shot hide every translucent family in turn and print how big a sheet it adds
var _lay_base: Image
var _lay_fams: Array[String] = []
var _lay_nodes: Dictionary = {}
var _lay_k := -1
var _nohud_pending := false
var _hud_layers: Array = []
var _lay_hidden: Array = []


func _init() -> void:
	_out = OS.get_environment("GLITCH_OUT")
	_layers = OS.get_environment("GLITCH_LAYERS") != ""
	var s := OS.get_environment("GLITCH_SPOTS")
	if s != "":
		for n in s.split(",", false):
			_spots.append(n)
	else:
		_spots.assign(["street_12", "street_21", "hero_back", "hero_side"])
		for t in InteriorData.TYPES:
			_spots.append("int_%s" % t)


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		_hud = _p.get_tree().get_first_node_in_group(&"hud") as Hud
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		for n in _p.get_tree().root.find_children("*", "Stability", true, false):
			n.set_process(false)
		_p.max_hp = 1.0e6
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	if _wait > 0:
		_wait -= 1
		_hold()
		return false
	var spot_now := _spots[_i].get_slice("#", 0)
	if spot_now.begins_with("tp_") and not _tp_done:
		_tp_done = true
		_p.quantum.cd_blink = 0.0
		_p.quantum.blink()                      # teleport to the beacon thrown in _begin
		_wait = int(spot_now.trim_prefix("tp_"))
		return false
	if _layers and _lay_k >= 0:
		if _layer_step():
			return false
	var img := _p.get_viewport().get_texture().get_image()
	if _layers and _lay_k < 0:
		_layer_begin(img)
		return false
	var sl := VisualQaLib.translucent_slabs(img)
	if sl["kind"] == "flat":
		_dump_near(sl)
	var name := _spots[_i]
	img.save_png("%s/%s.png" % [_out, name])
	print("GLITCH %s slab=%.4f rect=%s kind=%s" % [name, sl["frac"], sl["rect"], sl["kind"]])
	_i += 1
	if _i >= _spots.size():
		print("GLITCH_DONE")
		if OS.get_environment("BOT_FASTEXIT") != "":
			OS.kill(OS.get_process_id())
		return true
	_begin()
	return false


## GLITCH_HIDE=a,b hides every node whose path, or whose shader file name, contains one of the words (bisecting a glitch: render again and see what vanished).
func _apply_hide() -> void:
	var words := OS.get_environment("GLITCH_HIDE").split(",", false)
	if words.is_empty():
		return
	for n in _p.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var key := str(g.get_path())
		var m: Material = g.material_override
		if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (g as MeshInstance3D).get_active_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			key += " " + (m as ShaderMaterial).shader.resource_path.get_file()
		for w in words:
			if key.contains(w):
				g.visible = false


func _dump_near(flat: Dictionary) -> void:
		var cp := _p.get_viewport().get_camera_3d().global_position
		print("NEAR %s flat=%.3f cam=%s" % [_spots[_i], flat["frac"], cp])
		for n in _p.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree() or _family(g) == "":
				continue
			var ab := g.global_transform * g.get_aabb()
			if ab.get_center().distance_to(cp) < 8.0 + ab.size.length() * 0.5:
				var cnt := ""
				if g is CPUParticles3D:
					cnt = "emitting=%s amount=%d" % [(g as CPUParticles3D).emitting, (g as CPUParticles3D).amount]
				print("NEAR   %s %s d=%.1f size=%s %s" % [str(g.get_path()).right(70), _family(g), ab.get_center().distance_to(cp), ab.size.snapped(Vector3(0.1, 0.1, 0.1)), cnt])


func _family(g: GeometryInstance3D) -> String:
	var mats: Array = []
	if g.material_override != null:
		mats.append(g.material_override)
	elif g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
		for i in (g as MeshInstance3D).mesh.get_surface_count():
			mats.append((g as MeshInstance3D).get_active_material(i))
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null and (g as MultiMeshInstance3D).multimesh.mesh != null:
		var mm := (g as MultiMeshInstance3D).multimesh.mesh
		for i in mm.get_surface_count():
			mats.append(mm.surface_get_material(i))
	elif g is CPUParticles3D and (g as CPUParticles3D).mesh != null:
		mats.append((g as CPUParticles3D).mesh.surface_get_material(0))
	for mt in mats:
		if mt is ShaderMaterial and (mt as ShaderMaterial).shader != null:
			var code := (mt as ShaderMaterial).shader.code
			if code.contains("blend_") or code.contains("ALPHA"):
				return "shader:" + (mt as ShaderMaterial).shader.resource_path.get_file()
		elif mt is BaseMaterial3D:
			var b := mt as BaseMaterial3D
			if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				var nm := String(g.name)
				while nm.length() > 0 and (nm[nm.length() - 1].is_valid_int() or nm[nm.length() - 1] == "@"):
					nm = nm.left(nm.length() - 1)
				return "std:%s/%s" % [g.get_class(), nm]
	return ""


func _layer_begin(img: Image) -> void:
	_lay_base = img
	var flat := VisualQaLib.translucent_slabs(img)
	if flat["kind"] == "flat":
		img.save_png("%s/%s_FLAT.png" % [_out, _spots[_i]])
		_hud_layers.clear()
		for cl in _p.get_tree().root.find_children("*", "CanvasLayer", true, false):
			if (cl as CanvasLayer).visible:
				_hud_layers.append(cl)
				(cl as CanvasLayer).visible = false
		_nohud_pending = true
	if flat["kind"] == "flat" or OS.get_environment("GLITCH_NEAR") != "":
		_dump_near(flat)
	_lay_nodes.clear()
	_lay_fams.clear()
	for n in _p.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var f := _family(g)
		if f == "":
			continue
		if not _lay_nodes.has(f):
			_lay_nodes[f] = []
			_lay_fams.append(f)
		(_lay_nodes[f] as Array).append(g)
	_lay_k = 0
	_lay_hidden = []
	_wait = 0
	Engine.time_scale = 0.0001
	if _nohud_pending:
		_wait = 2
	else:
		_layer_hide()


func _layer_hide() -> void:
	_lay_hidden = (_lay_nodes[_lay_fams[_lay_k]] as Array).duplicate()
	for g in _lay_hidden:
		if is_instance_valid(g):
			(g as GeometryInstance3D).visible = false
	_wait = 2


## Returns true while the family loop runs (the shot of the spot is saved when it ends).
func _layer_step() -> bool:
	var img := _p.get_viewport().get_texture().get_image()
	if _nohud_pending:
		_nohud_pending = false
		img.save_png("%s/%s_NOHUD.png" % [_out, _spots[_i]])
		for cl in _hud_layers:
			if is_instance_valid(cl):
				(cl as CanvasLayer).visible = true
		print("NOHUD %s flat=%.3f" % [_spots[_i], VisualQaLib.translucent_slabs(img)["frac"]])
		_layer_hide()
		return true
	var sl := VisualQaLib.translucent_slabs(_lay_base, img)       # base frame (layers shown) against the frame without this family
	if float(sl["frac"]) > float(OS.get_environment("GLITCH_MIN") if OS.get_environment("GLITCH_MIN") != "" else "0.004"):
		print("LAYER %s %s frac=%.4f fill=%.2f rect=%s %s nodes=%d first=%s" % [_spots[_i], _lay_fams[_lay_k], sl["frac"], sl["fill"], sl["rect"], sl["kind"], _lay_hidden.size(), str((_lay_hidden[0] as Node).get_path()).right(60) if not _lay_hidden.is_empty() else ""])
	for g in _lay_hidden:
		if is_instance_valid(g):
			(g as GeometryInstance3D).visible = true
	_lay_k += 1
	if _lay_k >= _lay_fams.size():
		_lay_k = -1
		Engine.time_scale = 1.0
		_lay_base.save_png("%s/%s.png" % [_out, _spots[_i]])
		_i += 1
		if _i >= _spots.size():
			print("GLITCH_DONE")
			if OS.get_environment("BOT_FASTEXIT") != "":
				OS.kill(OS.get_process_id())
			return false
		_begin()
		return true
	_layer_hide()
	return true


func _hold() -> void:
	_apply_hide()
	if _burst_at > 0.0 and _wait == 3:
		var cam := _p.get_viewport().get_camera_3d()
		var at := cam.global_position - cam.global_basis.z * _burst_at
		FX.burst(at, Color(0.4, 0.95, 1.0), 14, 2.0, 0.9, 0.0, 9.0)       # a soft fireball puff cloud
		FX.burst(at + Vector3(0.0, -0.2, 0.0), Color(1.0, 0.6, 0.3), 24, 3.0, 0.8, 0.0, 1.0)
		(_p.body as PlayerBody).call(&"_fire_burst", at, 36)
	_p.hp = _p.max_hp
	_p.set(&"last_hurt_time", -100.0)
	if _use_cine:
		_p.camera_rig.cine_set(_cine, 70.0)


func _begin() -> void:
	_wait = SETTLE
	_use_cine = false
	Game.state = &"play"
	if is_instance_valid(Game.enemies):
		TestMode.kill_all_enemies()
	TestMode.set_weather("CLEAR")
	TestMode.set_heat(0.0)
	if _hud != null and _hud.touch != null:
		_hud.touch.controls_on = true
		_hud.touch.set_process(true)
	var spot := _spots[_i].get_slice("#", 0)
	_tp_done = false
	_burst_at = 0.0
	var ig := InteriorGameplay.instance
	if ig != null and ig.active and not spot.begins_with("int_"):
		ig.leave(true)
	var dn: DayNight = (Game.world as City).day_night
	dn.frozen = true
	if spot.begins_with("street_"):
		dn.set_hour(float(spot.trim_prefix("street_")))
		_p.teleport_to(Game.SPAWN)
		_p.camera_rig.reset_view(-PI * 0.5, -0.12)
	elif spot.begins_with("int_"):
		if ig != null:
			ig.leave(true)
			_p.teleport_to(Game.SPAWN)
			var doors := ig.doors_of(StringName(spot.trim_prefix("int_")), Game.SPAWN)
			if not doors.is_empty():
				ig.enter(doors[0], true)
	elif spot.begins_with("tp_") or spot == "beacon":
		dn.set_hour(12.0)
		_p.teleport_to(Game.SPAWN)
		_p.camera_rig.reset_view(-PI * 0.5, -0.12)
		_p.energy = _p.max_energy
		_p.quantum.reset()
		_p.quantum.cd_blink = 0.0
		_p.quantum.blink()                      # throws the beacon at the aimed floor point
	elif spot.begins_with("burst"):
		# the hero's hit burst (and every other pooled sprite) right in front of the lens: the old unsized, untextured motes were metre-wide squares
		dn.set_hour(12.0)
		_p.teleport_to(Game.SPAWN)
		_p.camera_rig.reset_view(-PI * 0.5, -0.12)
		_use_cine = false
		_burst_at = 1.3
	elif spot.begins_with("hero_"):
		dn.set_hour(12.0)
		_p.teleport_to(Game.SPAWN)
		var o := _p.global_position
		var off := Vector3(0.0, 1.4, 2.4) if spot == "hero_back" else Vector3(2.4, 1.3, 0.3)
		var yaw := _p.body.global_basis.get_euler().y if _p.body != null else 0.0
		var rot := Basis(Vector3.UP, yaw)
		_cine = Transform3D(Basis.IDENTITY, o + rot * off).looking_at(o + Vector3(0, 1.0, 0), Vector3.UP)
		_use_cine = true
