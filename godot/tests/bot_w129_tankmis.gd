extends "res://tests/tankmis_w129_bot.gd"
## w129-tankmis LOOK BOT: the three tank missions played by the finger bot of tests/tankmis_w129_bot.gd in the real main scene, a frame every SHOT_EVERY game seconds while a mission
## runs (the yard, the crews coming down the street, the convoy driving round the corner, the artillery marker), at phone aspect.
##   TM_OUT=<dir> TM_TAG=q0 QUALITY=0 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=1500 tools/bot.sh res://tests/bot_w129_tankmis.gd /tmp/x 100000 1
const SHOT_EVERY := 9.0
var _started := false
var _done := false
var out := ""
var tag := ""
var _n := 0


func step(_t0: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_go(tree)
	return false


func _go(tree: SceneTree) -> void:
	host = tree.root
	out = OS.get_environment("TM_OUT") if OS.get_environment("TM_OUT") != "" else "/tmp/tm"
	tag = OS.get_environment("TM_TAG") if OS.get_environment("TM_TAG") != "" else "q"
	DirAccess.make_dir_recursive_absolute(out)
	await _f(30)
	Game.state = &"play"
	Game.force_touch = true
	CrateReveal._quiet = 0
	MissionGuide.auto_recover = false
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.5
	hud = tree.root.find_children("*", "Hud", true, false)[0] as Hud
	board = MissionBoardScreen.board()
	board.take_over = false
	var which := OS.get_environment("TM_MISSIONS")
	for m in (which.split(",") if which != "" else PackedStringArray(["tank_battle", "tank_convoy", "tank_artillery"])):
		mission = StringName(m)
		notes = {}
		ride = null
		_shooter(StringName(m))
		await play(StringName(m))
		if board.is_running():
			board.abandon("BOT")
	mission = &""
	Engine.time_scale = 1.0
	_done = true


func _shooter(m: StringName) -> void:
	await host.get_tree().create_timer(4.0).timeout
	while mission == m and not _done:
		if not board.is_running():
			await host.get_tree().create_timer(1.0).timeout
			continue
		await RenderingServer.frame_post_draw
		_n += 1
		host.get_texture().get_image().save_png("%s/%s_%02d_%s.png" % [out, m, _n, tag])
		print("TM SHOT %s %d: %s" % [m, _n, _camp().hud_line()])
		await host.get_tree().create_timer(SHOT_EVERY).timeout
