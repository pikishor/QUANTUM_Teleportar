extends RefCounted
## w121-lifts look bot: the facade lift and the tower lift at phone aspect with the phone HUD, real fingers for every action (tests/w116_fingers.gd). One PNG per moment in W121_OUT.
##   W121_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch QUALITY=0 BOT_TIMEOUT=580 tools/bot.sh res://tests/bot_lifts_w121.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var tree: SceneTree
var fg: Fingers
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
	var tl := TowerLift.instance
	print("W121 shot ", name, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " lift ", tl.mode, " stop ", tl.at_stop, " floor ", tl.hud_floor())


func tap(pos: Vector2) -> void:
	fg.down(7, pos)
	await frames(3)
	fg.up(7)
	await frames(3)


func use() -> void:
	if fg.press(6, &"interact"):
		await frames(4)
		fg.up(6)
	await frames(30)


func place(pos: Vector3, yaw: float, pitch := -0.12) -> void:
	fg.up_all()
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.yaw = yaw
	p.camera_rig.reset_view(yaw, pitch)
	p.camera_rig.snap()
	await frames(40)


func panel_tap(nm: String) -> void:
	for b in TowerLift.instance.panel_buttons():
		if b.name == nm:
			await tap(b.get_global_rect().get_center())


func _run() -> void:
	out = OS.get_environment("W121_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	fg = Fingers.new(tree.root)
	var tc := tree.root.find_children("*", "TouchControls", true, false)
	fg.tc = tc[0] as TouchControls if not tc.is_empty() else null
	TestMode.god = true
	await frames(60)
	var tl := TowerLift.instance
	# --- the facade lift of the tall lot nearest the spawn
	var lay := TowerLift._layout()
	var best := -1
	var bd := 1.0e9
	for i in TowerLift.tall_lots():
		var lot: CityLayout.Lot = lay.lots[i]
		if TowerFloors.instance != null and TowerFloors.instance.towers.any(func(t): return (t["lot"] as CityLayout.Lot).index == i):
			continue
		var d := Vector2(lot.cx - Game.SPAWN.x, lot.cz - Game.SPAWN.z).length()
		if d < bd:
			bd = d
			best = i
	var sp := TowerLift.spot(lay.lots[best])
	var n: Vector3 = sp["normal"]
	var c: Vector3 = sp["pos"]
	var away := c + n * 9.0 + (Basis(Vector3.UP, float(sp["yaw"])) * Vector3.RIGHT) * 3.0
	await place(away, atan2(-(c - away).x, -(c - away).z), -0.05)
	await frames(30)
	await place(tl.call_point(0) + n * 0.3, atan2(n.x, n.z))
	await shot("01_out_call")
	await use()
	await frames(20)
	await place(c + Vector3(0, 0.05, 0), atan2(n.x, n.z) + PI)
	await use()
	await frames(6)
	await shot("02_out_panel")
	await panel_tap("Floor_ROOF")
	await frames(25)
	await shot("03_out_riding")
	await frames(90)
	await place(tl.call_point(1) - n * 1.5 + Vector3(0, 0.2, 0), atan2(n.x, n.z))
	await shot("04_out_roof")
	# --- the tower lift
	var tf := TowerFloors.instance
	if tf != null:
		var tw := tf.nearest(Game.SPAWN)
		var door := TowerFloors.door_pos(tw, 3.0)
		await place(door + Vector3(0, 0.5, 0), atan2(-(TowerFloors.door_pos(tw, -3.0) - door).x, -(TowerFloors.door_pos(tw, -3.0) - door).z))
		await place(TowerFloors.door_pos(tw, -2.0) + Vector3(0, 0.3, 0), p.yaw)
		await frames(60)
		if tl.mode == &"in":
			var f: Vector3 = tl.base.basis * Vector3.BACK
			await place(tl.call_point(0) + f * 1.2 + Vector3(0, 0.2, 0), atan2(f.x, f.z), -0.15)
			await use()
			await frames(30)
			await shot("05_in_open")
			await place(tl.base.origin + Vector3(0, 0.2, 0), atan2(-f.x, -f.z))
			await use()
			await frames(6)
			await shot("06_in_panel")
			await panel_tap("Floor_%d" % (tl.stops.size() - 2))
			await frames(80)
			await place(tl.call_point(tl.stops.size() - 2) + f * 1.6 + Vector3(0, 0.2, 0), atan2(f.x, f.z), -0.15)
			await shot("07_in_top_floor")
			fg.down(7, fg.tc._minimap_rect().get_center())
			await frames(3)
			fg.up(7)
			await frames(40)
			await shot("08_map_floor")
	_done = true
