extends RefCounted
## WAVE 122 ROOMS look bot: the real game at phone aspect, the phone HUD. One PNG per view in W122_OUT: per kind (office, apartment, hotel, house) the lobby / street floor and
## floor 1 rooms; the office stairwell. Placement by teleport (pictures only; the walk is tests/test_rooms_w122.gd by fingers).
##   W122_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=500 tools/bot.sh res://tests/bot_w122_rooms.gd /tmp/x 100000 1
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
	print("W122 shot ", name, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " open ", TowerFloors.open_lot, " people ", TowerFloors.instance.people()["actors"].size())


func place(pos: Vector3, look_at: Vector3, pitch := -0.08) -> void:
	var yaw := atan2(-(look_at.x - pos.x), -(look_at.z - pos.z))
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(40)


func _run() -> void:
	out = OS.get_environment("W122_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var tf := TowerFloors.instance
	var only := OS.get_environment("W122_KINDS")
	for kind: StringName in [&"office", &"apartment", &"hotel", &"house"]:
		if only != "" and not only.contains(String(kind)):
			continue
		var tw := tf.nearest(Game.SPAWN, 0.0 if kind == &"house" else TowerFloors.MIN_H, kind)
		if tw.is_empty():
			continue
		var lv := TowerFloors.levels_of(tw["lot"])
		var iu := TowerFloors.inner_u(tw)
		var iv := TowerFloors.inner_v(tw)
		await place(TowerFloors.door_pos(tw, 7.0), TowerFloors.door_pos(tw, -3.0))
		await shot("%s_0_door" % kind)
		await place(TowerFloors.at(tw, iu * 0.5 + 2.0, iv - 2.0, 0.05), TowerFloors.at(tw, iu * 0.3, TowerFloors.SHAFT_W, 1.0))
		await shot("%s_1_street_floor" % kind)
		await place(TowerFloors.at(tw, iu * 0.5, TowerFloors.SHAFT_W + 1.4, lv[1] + 0.05), TowerFloors.at(tw, iu * 0.5, iv, lv[1] + 1.0), -0.12)
		await shot("%s_2_floor1" % kind)
		var rw := iu / clampi(int(iu / 6.5), 2, 5)
		await place(TowerFloors.at(tw, rw * 0.5, iv - 6.0 + 0.6, lv[1] + 0.05), TowerFloors.at(tw, rw * 0.5 + 1.0, iv, lv[1] + 0.6), -0.2)
		await shot("%s_3_room" % kind)
		if kind == &"office":
			var ym := (lv[1] + lv[2]) * 0.5
			await place(TowerFloors.at(tw, 0.7, 1.95, lv[1] + 0.05), TowerFloors.at(tw, 6.0, 1.95, ym), -0.02)
			await shot("%s_4_stairwell" % kind)
	_done = true
