extends RefCounted
## Lists every visible transparent / unshaded mesh near the camera in a spot (names, shader, blend, size). GLITCH_SPOTS=int_tech,street_12  tools/bot.sh res://tests/bot_glitch_audit.gd /tmp/x 100000 1
var _p: Player
var _wait := 30
var _i := 0
var _spots: Array[String] = []

func _init() -> void:
	for n in OS.get_environment("GLITCH_SPOTS").split(",", false):
		_spots.append(n)

func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		_begin()
	if _wait > 0:
		_wait -= 1
		return false
	_report(_spots[_i])
	_i += 1
	if _i >= _spots.size():
		OS.kill(OS.get_process_id())
		return true
	_begin()
	return false

func _begin() -> void:
	_wait = 20
	Game.state = &"play"
	var s := _spots[_i]
	var ig := InteriorGameplay.instance
	var dn: DayNight = (Game.world as City).day_night
	dn.frozen = true
	if s.begins_with("street_"):
		if ig.active: ig.leave(true)
		dn.set_hour(float(s.trim_prefix("street_")))
		_p.teleport_to(Game.SPAWN)
	else:
		ig.leave(true)
		_p.teleport_to(Game.SPAWN)
		ig.enter(ig.doors_of(StringName(s.trim_prefix("int_")), Game.SPAWN)[0], true)

func _report(spot: String) -> void:
	var cam := _p.get_viewport().get_camera_3d()
	var cp := cam.global_position
	print("AUDIT ==== ", spot, " cam ", cp)
	var lim := float(OS.get_environment("GLITCH_DIST")) if OS.get_environment("GLITCH_DIST") != "" else 25.0
	for n in _p.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var aabb := g.global_transform * g.get_aabb()
		var d := aabb.get_center().distance_to(cp)
		if aabb.grow(1.0).has_point(cp):
			d = 0.0
		if d > lim + aabb.size.length() * 0.5:
			continue
		var mats: Array = []
		var m: Material = g.material_override
		if m != null: mats.append(m)
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var me := (g as MeshInstance3D).mesh
			for i in me.get_surface_count():
				var sm: Material = (g as MeshInstance3D).get_active_material(i)
				mats.append(sm)
		for mt in mats:
			var info := _mat_info(mt)
			if info != "":
				print("AUDIT %s | %s | d=%.1f size=%s | %s" % [str(g.get_path()).right(70), g.get_class(), d, aabb.size.snapped(Vector3(0.01,0.01,0.01)), info])

func _mat_info(mt: Material) -> String:
	if mt == null:
		return "NO MATERIAL"
	if mt is ShaderMaterial:
		var sh := (mt as ShaderMaterial).shader
		var code := sh.code if sh != null else ""
		var blend := ""
		for l in code.split("\n"):
			if l.begins_with("render_mode"):
				blend = l
		if blend.contains("blend_") or blend.contains("unshaded") or code.contains("ALPHA"):
			return "SHADER %s %s" % [sh.resource_path.get_file(), blend]
		return ""
	if mt is BaseMaterial3D:
		var b := mt as BaseMaterial3D
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return "STD tr=%d unshaded=%s alpha=%.2f blend=%d" % [b.transparency, b.shading_mode == 0, b.albedo_color.a, b.blend_mode]
	return ""
