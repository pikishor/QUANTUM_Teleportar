extends RefCounted
## w120-critic look bot (boat turning back at the east world edge, by the stick only; was: WAVE 120 REACH look bot): the real game at phone aspect, the phone HUD, real fingers (tests/w116_fingers.gd). One PNG per moment in W120_OUT: swimming across the EASTWATER,
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
	CrateReveal._quiet = 0
	p = Game.player as Player
	fg = Fingers.new(p)
	TestMode.god = true
	var s := Vector3(CityLayout.PLAY_HALF - 300.0, TerrainHeight.SEA_LEVEL - 0.5, 2000.0)
	var yaw := yaw_to(s, s + Vector3(100.0, 0.0, 0.0))
	await tp(s + Vector3(0.0, 0.0, 3.0), yaw, true)
	var vm := Game.vehicles as VehicleManager
	var boat := vm.spawn_parked(&"boat", s, yaw)
	await frames(30)
	fg.press(6, &"interact")
	await frames(6)
	fg.up(6)
	await frames(30)
	fg.stick(Vector2(0.0, -1.0))
	for i in 6:
		await frames(60)
		await shot("boat_edge_%d" % i)
		print("boat x ", boat.global_position.x, " v ", boat.vel.length(), " in ", p.vehicle == boat)
	fg.stick(Vector2.ZERO)
	_done = true
