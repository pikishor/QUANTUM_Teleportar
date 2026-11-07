extends RefCounted
## Director round 2 A render rig (hero, weapon, HUD, story) (docs/SLICE_REVIEW.md "After"): quick frames of the hero and the weapon from the real game camera, the HUD and the menus, then exits.
##   DA_OUT=<dir> DA_VIEWS=back,three,aim,walk[,menu_more,menu_pause,map] DA_WEAPON=carbine BOT_RES=1600x720 QUALITY=0 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_dfb.gd /tmp/x 100000 1
const SETTLE := 40
var _views: PackedStringArray = PackedStringArray(["back", "three", "aim"])
var _i := 0
var _wait := 0
var _p: Player
var _out := ""
var _w: StringName = &"carbine"
var _saving := false


func _init() -> void:
	_out = OS.get_environment("DA_OUT")
	var v := OS.get_environment("DA_VIEWS")
	if v != "":
		_views = v.split(",", false)
	var w := OS.get_environment("DA_WEAPON")
	if w != "":
		_w = StringName(w)


func step(_t: float, _dt: float) -> bool:
	if _saving or _i >= _views.size():
		return false
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		_p.max_hp = 1.0e6
		for id: StringName in WeaponDefs.IDS:
			WeaponDefs.unlock(id)
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
	_p.hp = _p.max_hp
	var v := _views[_i]
	if v == "three":
		var o := _p.global_position
		var cam := Transform3D(Basis.IDENTITY, o + Vector3(1.4, 1.5, -1.9).rotated(Vector3.UP, _p.rotation.y)).looking_at(o + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		_p.camera_rig.cine_set(cam, 50.0)
	if v == "face":
		var o3 := _p.global_position
		var cam3 := Transform3D(Basis.IDENTITY, o3 + Vector3(0.45, 1.72, -1.25).rotated(Vector3.UP, _p.rotation.y)).looking_at(o3 + Vector3(0.0, 1.62, 0.0), Vector3.UP)
		_p.camera_rig.cine_set(cam3, 45.0)
	if v == "frontfull":
		var o4 := _p.global_position
		var cam4 := Transform3D(Basis.IDENTITY, o4 + Vector3(0.9, 1.3, -3.4).rotated(Vector3.UP, _p.rotation.y)).looking_at(o4 + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		_p.camera_rig.cine_set(cam4, 50.0)
	if v == "backclose":
		var o5 := _p.global_position
		var cam5 := Transform3D(Basis.IDENTITY, o5 + Vector3(0.5, 1.5, 1.7).rotated(Vector3.UP, _p.rotation.y)).looking_at(o5 + Vector3(0.0, 1.1, 0.0), Vector3.UP)
		_p.camera_rig.cine_set(cam5, 50.0)
	if v == "side":
		var o2 := _p.global_position
		var cam2 := Transform3D(Basis.IDENTITY, o2 + Vector3(2.6, 1.4, 0.0).rotated(Vector3.UP, _p.rotation.y)).looking_at(o2 + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		_p.camera_rig.cine_set(cam2, 45.0)
	if v == "walk" or v == "camp_walk":
		Input.action_press(&"move_forward")
	if _wait > 0:
		_wait -= 1
		return false
	_saving = true
	var we := _p.get_tree().root.find_child("Environment", true, false) as WorldEnvironment
	if we != null:
		if OS.get_environment("DA_NOGLOW") != "":
			we.environment.glow_enabled = false
		if OS.get_environment("DA_NOFOG") != "":
			we.environment.fog_enabled = false
	var hide_name := OS.get_environment("DA_HIDE")
	for one in hide_name.split(",", false):
		for hn in _p.get_tree().root.find_children(one, "Node3D", true, false):
			(hn as Node3D).visible = false
	if OS.get_environment("DA_PROBE") != "":
		_probe()
	_shot(v)
	return false


func _shot(v: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, v])
	print("DA %s draws %d prims %d" % [v, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_saving = false
	Input.action_release(&"move_forward")
	Input.action_release(&"aim")
	_i += 1
	if _i >= _views.size():
		print("DA_DONE")
		_p.get_tree().quit()
		return
	_begin()


func _begin() -> void:
	_wait = SETTLE
	Game.state = &"play"
	var v := _views[_i]
	_p.camera_rig.cine_clear() if _p.camera_rig.has_method(&"cine_clear") else null
	if v == "aim":
		Input.action_press(&"aim")
	if v == "camp" or v == "camp_walk":
		var m := Game.missions as Missions
		if m != null and m.campaign != null and m.campaign.state == &"idle":
			m.campaign.enabled = true
			m.campaign.start_chapter(0, 0, true)
	if v == "enemy":
		var fwd := -_p.global_transform.basis.z
		var side := _p.global_transform.basis.x
		var n := 0
		for t: StringName in [&"striker", &"heavy", &"operative"]:
			Game.enemies.spawn(t, _p.global_position + fwd * 9.0 + side * (float(n) - 1.0) * 3.0, false)
			n += 1
	if v == "camp_walk":
		Input.action_press(&"move_forward")
	var hud := _p.get_tree().get_first_node_in_group(&"hud") as Hud
	if hud != null:
		if v == "menu_more" and hud.has_method(&"press_button"):
			Game.state = &"paused"


## DA_PROBE=1: prints the lights and the see-through / unshaded meshes close to the camera (what washes the frame).
func _probe() -> void:
	var cam := _p.get_viewport().get_camera_3d()
	var cp := cam.global_position
	print("DA probe cam ", cp, " fog ", _fog())
	for top in ["World", "World/Geometry", "Main"]:
		var tn := _p.get_tree().root.get_node_or_null("Main" if top == "Main" else "Main/" + top) as Node
		if tn != null:
			var names := []
			for ch in tn.get_children():
				names.append(ch.name)
			print("DA children of ", top, ": ", names)
	for n in _p.get_tree().root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.visible and l.is_visible_in_tree() and l.global_position.distance_to(cp) < 150.0:
			print("DA light ", l.get_path(), " ", l.light_color, " e ", l.light_energy, " d ", snappedf(l.global_position.distance_to(cp), 0.1), " ", l.get_class(), " range ", (l.get(&"omni_range") if l is OmniLight3D else (l.get(&"spot_range") if l is SpotLight3D else 0)))
	for n2 in _p.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n2 as GeometryInstance3D
		var gab := g.global_transform * g.get_aabb()
		if not g.is_visible_in_tree() or gab.grow(1.0).has_point(cp) == false and gab.get_center().distance_to(cp) - gab.size.length() * 0.5 > 12.0:
			continue
		var m: Material = g.material_override
		if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (g as MeshInstance3D).get_active_material(0)
		var tr := false
		if m is BaseMaterial3D:
			tr = (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or (m as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		elif m is ShaderMaterial:
			tr = String((m as ShaderMaterial).shader.code).contains("blend_add") or String((m as ShaderMaterial).shader.code).contains("unshaded")
		if tr:
			print("DA mesh ", g.get_path(), " ", g.get_class(), " d ", snappedf(g.global_position.distance_to(cp), 0.1), " aabb ", g.get_aabb().size)


func _fog() -> String:
	var we := _p.get_tree().root.find_child("Environment", true, false) as WorldEnvironment
	return str(we.environment.fog_density) if we != null else "?"
