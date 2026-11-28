extends RefCounted
## w129-tankmis LOOK BOT: the booths, booms and fences of TankPlaces at the ARMY BASE and the three CHECKPOINTS, one frame each from the hero's spot beside the road.
##   PL_OUT=<dir> QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_w129_places.gd /tmp/x 100000 1
var _started := false
var _done := false


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _pf(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame


func _run(tree: SceneTree) -> void:
	var out := OS.get_environment("PL_OUT") if OS.get_environment("PL_OUT") != "" else "/tmp/pl"
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	await _pf(tree, 30)
	var p := Game.player as Player
	for i in 300:
		if TerrainRoads.built:
			break
		await _pf(tree, 2)
	for s: Dictionary in TankPlaces.places():
		var c: Vector3 = s["pos"]
		var n: Vector2 = s["nrm"]
		var d: Vector2 = s["dir"]
		var stand := c + Vector3(n.x, 0.0, n.y) * (float(s["w"]) * 0.5 + 16.0) + Vector3(d.x, 0.0, d.y) * 22.0
		stand.y = Vehicle._terrain_y(stand.x, stand.z) + 0.5
		p.teleport_to(stand)
		var to := c - stand
		p.yaw = atan2(-to.x, -to.z)
		p.camera_rig.reset_view(p.yaw, -0.18)
		await _pf(tree, 240)
		await RenderingServer.frame_post_draw
		tree.root.get_texture().get_image().save_png("%s/place_%s.png" % [out, s["id"]])
		print("PLACE SHOT %s" % s["id"])
	_done = true
