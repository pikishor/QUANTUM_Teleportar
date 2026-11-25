extends RefCounted
## WAVE 122 SHOPS look bot: the real game at phone aspect with the phone HUD. One PNG per view in W122_OUT: street windows at night and by day, the shop fronts of the six kinds,
## inside a shop, a tower window from inside, a roof edge. Placement by teleport (pictures only; the walks are tests/test_shops_w122.gd by fingers).
##   W122_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=500 tools/bot.sh res://tests/bot_w122_shops.gd /tmp/x 100000 1
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
	print("W122 shot ", nm, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)))


func place(pos: Vector3, look_at: Vector3, pitch := -0.08) -> void:
	var yaw := atan2(-(look_at.x - pos.x), -(look_at.z - pos.z))
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(45)


func _hour(h: float) -> void:
	var city = Game.world
	if city != null and city.get(&"day_night") != null:
		city.day_night.set_hour(h)


func _run() -> void:
	out = OS.get_environment("W122_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	if OS.get_environment("W122_LP") == "1":
		Game.set_low_plus(true)
		await frames(10)
	var doors: Array = Game.world.get("doors")
	var d0: Dictionary = {}
	var best := 1e9
	for d: Dictionary in doors:
		var dd: float = (d["pos"] as Vector3).distance_to(Game.SPAWN)
		if dd < best:
			best = dd
			d0 = d
	var n0: Vector3 = d0["normal"]
	var w0: Vector3 = d0["wall"]
	for h in [22.0, 12.0]:
		_hour(h)
		await place(w0 + n0 * 9.0, w0 + Vector3(0, 7, 0), 0.12)
		await shot("1_windows_%d" % int(h))
		await place(w0 + n0 * 16.0, w0 + Vector3(0, 14, 0), 0.45)
		await shot("1b_windows_up_%d" % int(h))
	if OS.get_environment("W122_ONLY_WIN") == "1":
		_done = true
		return
	_hour(21.0)
	var only := OS.get_environment("W122_SHOPS")
	if Engine.has_singleton(&"ShopFronts") or ClassDB.class_exists(&"ShopFronts") or true:
		var sf: Variant = Game.world.get_tree().root.find_child("ShopFronts", true, false)
		if sf != null:
			for kind: StringName in sf.KINDS:
				var s: Dictionary = sf.nearest_of(kind, Game.SPAWN)
				if s.is_empty():
					continue
				var dn: Vector3 = s["normal"]
				var dw: Vector3 = s["wall"]
				await place(dw + dn * 7.0 + (s["along"] as Vector3) * 2.0, dw + Vector3(0, 1.5, 0), -0.02)
				await shot("2_front_%s" % kind)
				if only == "" or str(kind) in only.split(","):
					await place(dw - dn * 1.2, dw - dn * 6.0 + Vector3(0, 1.0, 0), -0.05)
					await shot("3_inside_%s" % kind)
					await place(dw - dn * 3.0 + (s["along"] as Vector3) * 0.4, dw + dn * 6.0 + Vector3(0, 1.4, 0), -0.02)
					await shot("4_lookout_%s" % kind)
	_done = true
