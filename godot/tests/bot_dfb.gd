extends RefCounted
## Director fixes B render rig (docs/SLICE_REVIEW.md "After"): quick frames of the hero and the weapon from the real game camera, the HUD and the menus, then exits.
##   DF_OUT=<dir> DF_VIEWS=back,three,aim,walk[,menu_more,menu_pause,map] DF_WEAPON=carbine BOT_RES=1600x720 QUALITY=0 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_dfb.gd /tmp/x 100000 1
const SETTLE := 40
var _views: PackedStringArray = PackedStringArray(["back", "three", "aim"])
var _i := 0
var _wait := 0
var _p: Player
var _out := ""
var _w: StringName = &"carbine"
var _saving := false


func _init() -> void:
	_out = OS.get_environment("DF_OUT")
	var v := OS.get_environment("DF_VIEWS")
	if v != "":
		_views = v.split(",", false)
	var w := OS.get_environment("DF_WEAPON")
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
	_shot(v)
	return false


func _shot(v: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _p.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, v])
	print("DF %s draws %d prims %d" % [v, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_saving = false
	Input.action_release(&"move_forward")
	Input.action_release(&"aim")
	_i += 1
	if _i >= _views.size():
		print("DF_DONE")
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
