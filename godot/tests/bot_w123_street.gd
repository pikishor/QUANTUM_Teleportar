extends RefCounted
## w123-clutter LOOK bot: the real game at phone aspect with the phone HUD. One PNG per view in W123_OUT: 4 city streets and 2 outskirts streets at eye height, and 3 doors seen
## from the kerb. Placement by teleport (pictures only; the walks are tests/test_clutter_w123.gd by fingers).
##   W123_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=500 tools/bot.sh res://tests/bot_w123_street.gd /tmp/x 100000 1
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


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])
	print("W123 shot ", nm, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)))


func place(pos: Vector3, look_at: Vector3, pitch := -0.05) -> void:
	var yaw := atan2(-(look_at.x - pos.x), -(look_at.z - pos.z))
	pos.y = TerrainHeight.height_at(pos.x, pos.z) + 0.2 if maxf(absf(pos.x), absf(pos.z)) > CityLayout.WALK else 0.2
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(60)


func _run() -> void:
	out = OS.get_environment("W123_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var city = Game.world
	if city.get(&"day_night") != null:
		city.day_night.set_hour(11.0)
	var streets := [[Vector3(-20, 0, 11), Vector3(-90, 0, 11)], [Vector3(-69, 0, 20), Vector3(-69, 0, 75)], [Vector3(11, 0, 30), Vector3(11, 0, 75)], [Vector3(91, 0, -70), Vector3(91, 0, -5)]]
	for i in streets.size():
		await place(streets[i][0], streets[i][1])
		await shot("street_%d" % i)
	var seen := 0
	var dl := preload("res://tests/w123_clutter_lib.gd").doors_near(Game.SPAWN, 120.0)
	for i in dl.size():
		var d: Dictionary = dl[i]
		if seen >= 3:
			break
		if not (str(d["what"]).contains("lot 129") or str(d["what"]).contains("lot 69") or str(d["what"]).contains("lot 98")):
			continue
		seen += 1
		var n: Vector3 = d["n"]
		var w: Vector3 = d["wall"]
		await place(w + n * 5.5, w + Vector3(0, 1.2, 0), -0.05)
		await shot("door_%d" % seen)
	var towns := SettlementData.doors()
	var done_t := {}
	for d in towns:
		if done_t.size() >= 2:
			break
		var key = d.get("settlement", d.get("site", done_t.size()))
		if done_t.has(key):
			continue
		done_t[key] = true
		var dp: Vector3 = d["pos"]
		var dn: Vector3 = d.get("normal", Vector3.BACK)
		var t := Vector3(-dn.z, 0, dn.x)
		await place(dp + dn * 6.0 - t * 12.0, dp + dn * 6.0 + t * 20.0)
		await shot("town_%d" % done_t.size())
	_done = true
