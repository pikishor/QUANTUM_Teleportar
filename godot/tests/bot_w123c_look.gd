extends RefCounted
## w123-critic LOOK bot (frames only, placement by teleport): bench sitters, bus-stop waiters, a kerb street, day and night.
##   W123C_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=500 tools/bot.sh res://tests/bot_w123c_look.gd /tmp/x 100000 1
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
	print("W123C shot ", nm, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)))


func place(pos: Vector3, look: Vector3, n := 90) -> void:
	var yaw := atan2(-(look.x - pos.x), -(look.z - pos.z))
	pos.y = 0.2
	p.teleport_to(pos)
	p.velocity = Vector3.ZERO
	p.camera_rig.reset_view(yaw, -0.12)
	p.yaw = yaw
	await frames(n)


func _run() -> void:
	out = OS.get_environment("W123C_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var city = Game.world
	var amb = city.ambient
	for hour in [11.0]:
		if city.get(&"day_night") != null:
			city.day_night.set_hour(hour)
		var tag := "d" if hour < 12.0 else "n"
		# benches near the spawn: stand 4 m off the seat, look at it
		var bs: Array = StreetLife.benches.duplicate()
		bs.sort_custom(func(a, b): return Vector2(a.x, a.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)) < Vector2(b.x, b.z).distance_to(Vector2(Game.SPAWN.x, Game.SPAWN.z)))
		for k in 2:
			var b: Vector3 = bs[k * 2]
			var seat := Vector3(b.x, 0.0, b.z)
			await place(seat + Vector3(3.0, 0.0, 3.5 * b.y), seat, 240)
			await shot("%s_bench_%d" % [tag, k])
		# the bus stop nearest the spawn
		var st: Array = StreetLife.bus_stops.duplicate()
		st.sort_custom(func(a, b): return a.distance_to(Game.SPAWN) < b.distance_to(Game.SPAWN))
		for k in 2:
			var sp: Vector3 = st[k]
			var w := StreetLife.wait_spot(sp, 1)
			var ws := Vector3(w[0], 0.0, w[1])
			var away := (ws - sp)
			away.y = 0.0
			await place(ws + away.normalized() * 5.0 + (Vector3(1, 0, 0) if int(w[3]) == 0 else Vector3(0, 0, 1)) * 4.0, ws, 240)
			await shot("%s_stop_%d" % [tag, k])
		await place(Vector3(-20, 0, 11), Vector3(-90, 0, 11))
		await shot("%s_street" % tag)
		print("W123C sitting=", amb.life.sitting_count(), " waited=", amb.life.waited)
	_done = true
