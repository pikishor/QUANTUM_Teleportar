extends RefCounted
## WAVE 120 REACH look bot: the real game at phone aspect, the phone HUD, real fingers (tests/w116_fingers.gd). One PNG per moment in W120_OUT: swimming across the EASTWATER,
## scrambling up a steep valley side, the open sea at the world edge (the swell turns the swimmer back), a car sinking in the river.
##   W120_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS=--touch ENGINE_ARGS="--fixed-fps 30" QUALITY=0 BOT_TIMEOUT=580 tools/bot.sh res://tests/bot_w120_reach.gd /tmp/x 100000 1
const Fingers := preload("res://tests/w116_fingers.gd")
var _started := false
var _done := false
var tree: SceneTree
var root: Window
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
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("W120 shot ", name, " pos ", p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " swim ", p.swim.active, " scramble ", p.scrambling)


func tp(pos: Vector3, yaw: float, direct := false) -> void:
	fg.up_all()
	await frames(2)
	p.snake.cancel()
	p.swim.reset()
	if direct:
		p.global_position = pos
	else:
		p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, -0.08)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await frames(60)


static func yaw_to(a: Vector3, b: Vector3) -> float:
	return atan2(-(b.x - a.x), -(b.z - a.z))


func _run() -> void:
	root = tree.root
	out = OS.get_environment("W120_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	Game.state = &"play"
	p = Game.player as Player
	fg = Fingers.new(p)
	TestMode.god = true
	var parts := OS.get_environment("W120_PARTS") if OS.get_environment("W120_PARTS") != "" else "swim,climb,edge"
	if parts.contains("swim"):
		await _swim()
	if parts.contains("climb"):
		await _climb()
	if parts.contains("edge"):
		await _edge()
	_done = true


func _swim() -> void:
	var a := Vector3(1421.5, TerrainHeight.height_at(1421.5, 990.5) + 1.0, 990.5)
	var b := Vector3(1476.7, 0.0, 1010.1)
	await tp(a, yaw_to(a, b))
	fg.stick(Vector2(0.0, -0.8))
	for i in 12:
		await frames(30)
		if p.swim.active:
			break
	await frames(40)
	await shot("swim_river")
	fg.stick(Vector2.ZERO)


func _climb() -> void:
	var a := Vector3(2028.8, TerrainHeight.height_at(2028.8, 78.8) + 1.0, 78.8)
	var b := Vector3(2070.1, 0.0, 119.8)
	await tp(a, yaw_to(a, b))
	fg.stick(Vector2(0.0, -1.0))
	for i in 20:
		await frames(15)
		if p.scrambling:
			break
	await frames(30)
	await shot("climb_steep")
	await frames(120)
	await shot("climb_steep_higher")
	fg.stick(Vector2.ZERO)


func _edge() -> void:
	var a := Vector3(CityLayout.PLAY_HALF - 160.0, TerrainHeight.SEA_LEVEL - 0.5, 600.0)
	var b := Vector3(CityLayout.PLAY_HALF + 300.0, 0.0, 600.0)
	await tp(a, yaw_to(a, b), true)
	fg.stick(Vector2(0.0, -1.0))
	await frames(300)
	await shot("edge_sea_out")
	fg.stick(Vector2.ZERO)
	fg.look(-500.0, 0.0, 8)
	await frames(40)
	await shot("edge_sea_back_to_land")
