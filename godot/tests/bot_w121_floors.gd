extends RefCounted
## WAVE 121 FLOORS look bot: the real game at phone aspect, the phone HUD. One PNG per view in W121_OUT: the street door, the lobby, the stairwell, floor 3, the roof door.
## Placement by teleport (pictures only; the walk itself is tests/test_floors_w121.gd by fingers).
##   W121_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=400 tools/bot.sh res://tests/bot_w121_floors.gd /tmp/x 100000 1
var _started := false
var _done := false
var tree: SceneTree
var p: Player
var out := ""


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	tree = Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run()
	return false


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	var tm = TowerFloors.instance.get_node_or_null("TowerMesh")
	print("W121 mat ", tm.material_override.shader.resource_path if tm else "none", " surf ", tm.mesh.get_surface_count() if tm and tm.mesh else -1, " vis ", tm.is_visible_in_tree() if tm else false)
	print("W121 shot ", name, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " open ", TowerFloors.open_lot, " floor ", TowerFloors.current().get("floor", -1))


func place(pos: Vector3, look_at: Vector3, pitch := -0.08) -> void:
	var yaw := atan2(-(look_at.x - pos.x), -(look_at.z - pos.z))
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(45)


func _run() -> void:
	out = OS.get_environment("W121_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var tf := TowerFloors.instance
	var tw := tf.nearest(Game.SPAWN)
	var door := TowerFloors.door_pos(tw, 7.0)
	await place(door, TowerFloors.door_pos(tw, -3.0))
	await frames(30)
	await shot("1_street_door")
	var lv := TowerFloors.levels_of(tw["lot"])
	var iu := TowerFloors.inner_u(tw)
	var iv := TowerFloors.inner_v(tw)
	await place(TowerFloors.at(tw, iu * 0.5 + 2.0, iv - 2.0, 0.05), TowerFloors.at(tw, 0.7, TowerFloors.SHAFT_W, 1.0))
	await shot("2_lobby")
	var ym := (lv[1] + lv[2]) * 0.5
	await place(TowerFloors.at(tw, 0.7, 1.95, lv[1] + 0.05), TowerFloors.at(tw, 6.0, 1.95, ym), -0.02)
	await shot("3_stairwell")
	await place(TowerFloors.at(tw, 2.0, TowerFloors.SHAFT_W + 1.6, lv[3] + 0.05), TowerFloors.at(tw, iu * 0.5, iv, lv[3] + 1.5), -0.05)
	await shot("4_floor3")
	await place(TowerFloors.at(tw, iu * 0.5, iv - 2.5, lv[3] + 0.05), TowerFloors.at(tw, iu * 0.5, iv + 5.0, lv[3] + 1.5), -0.05)
	await shot("5_floor3_windows")
	var top := lv[lv.size() - 1]
	await place(TowerFloors.at(tw, 3.0, TowerFloors.SHAFT_W + 6.0, top + 0.05), TowerFloors.at(tw, 0.7, TowerFloors.SHAFT_W, top + 1.2), -0.12)
	await shot("6_roof_door")
	_done = true
