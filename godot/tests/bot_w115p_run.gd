extends RefCounted
## Look-and-measure bot of the wave 115 PLAY critic: a SWING RUN from the street with the touch HUD, as a thumb does it (jump, hold SNAKE, tap again on the ground), frames at 5 per game second from the
## real camera, plus one measurement line per frame (mode, speed, draws, triangles, the script time of the frame).
##   W_OUT=/dir W_SECS=45 W_FPS=5 W_START=spawn|x,z,yaw W_TRAFFIC=1 W_DIFF=1 BOT_RES=844x390 BOT_USER_ARGS="--touch" QUALITY=0 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_w115p_run.gd /tmp/x/seq 100000 1
## The frames are written to W_OUT/r_<n>.png; the lines start with BOTP.

var _setup_done := false
var _p: Player
var _sn: SnakeTraversal
var _out := ""
var _secs := 45.0
var _fps := 5.0
var _t0 := 0.0
var _next_shot := 0.0
var _n := 0
var _rng := RandomNumberGenerator.new()
var _jumped := false
var _steer_t := 0.0
var _steer := 0.0
var _last_clock := 0.0
var _draw_max := 0
var _draw_sum := 0
var _cpu_max := 0.0
var _cpu_sum := 0.0
var _frames := 0
var _lines: Array[String] = []
var _done := false


func _init() -> void:
	_out = OS.get_environment("W_OUT")
	if OS.get_environment("W_SECS") != "":
		_secs = float(OS.get_environment("W_SECS"))
	if OS.get_environment("W_FPS") != "":
		_fps = float(OS.get_environment("W_FPS"))
	_rng.seed = 17


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_sn = _p.snake
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	(Game.enemies as EnemyManager).clear()
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	if Encounters.current != null:
		Encounters.current.enabled = false
	if OS.get_environment("W_TRAFFIC") == "0":
		TrafficField.bare_street()
	TestMode.god = true
	var diff := int(OS.get_environment("W_DIFF")) if OS.get_environment("W_DIFF") != "" else 1
	Difficulty.set_mode(diff)
	SnakeTraversal.assist = true
	var start := OS.get_environment("W_START")
	var sp := Game.SPAWN
	var yaw := 0.0
	if start != "" and start != "spawn":
		var f := start.split(",")
		sp = Vector3(float(f[0]), 0.0, float(f[1]))
		yaw = float(f[2])
	_p.teleport_to(sp)
	_p.camera_rig.reset_view(yaw, 0.15)
	_p.yaw = yaw
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = _sn.time
	_last_clock = _sn.time
	print("BOTP start at ", sp, " yaw ", yaw, " diff ", diff, " secs ", _secs)


func step(t: float, delta: float) -> bool:
	if _done:
		return true
	if not _setup_done:
		if t > 3.0 and Game.player != null and Game.world != null:
			_setup()
		return false
	var now := _sn.time - _t0
	var dt := _sn.time - _last_clock
	_last_clock = _sn.time
	if now >= _secs:
		Input.action_release(&"snake")
		Input.action_release(&"jump")
		Input.action_release(&"move_forward")
		print("BOTP done frames ", _frames, " shots ", _n, " draws avg %.0f max %d, script ms avg %.2f max %.2f" % [float(_draw_sum) / maxf(float(_frames), 1.0), _draw_max, _cpu_sum / maxf(float(_frames), 1.0), _cpu_max])
		_p.get_tree().quit()
		_done = true
		return true
	# the thumb
	if _p.is_on_floor() and _sn.mode == SnakeTraversal.Mode.NONE:
		Input.action_release(&"snake")
		Input.action_press(&"jump")
		Input.action_press(&"move_forward")
		_jumped = true
	else:
		Input.action_release(&"jump")
		if _p.air_time > 0.25 or _sn.mode != SnakeTraversal.Mode.NONE:
			Input.action_press(&"snake")
	_steer_t -= maxf(dt, 0.0)
	if _steer_t <= 0.0:
		_steer = _rng.randf_range(-0.5, 0.5)
		_steer_t = _rng.randf_range(1.0, 3.0)
	_p.camera_rig.add_look(_steer * maxf(dt, 0.0), 0.0)
	# measurements
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var cpu := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	_frames += 1
	_draw_sum += draws
	_draw_max = maxi(_draw_max, draws)
	_cpu_sum += cpu
	_cpu_max = maxf(_cpu_max, cpu)
	if now >= _next_shot:
		_next_shot += 1.0 / _fps
		var img := _p.get_viewport().get_texture().get_image()
		img.save_png("%s/r_%03d.png" % [_out, _n])
		print("BOTP r_%03d t %.1f mode %s speed %.1f y %.1f energy %.0f draws %d tris %dk script %.2f ms" % [_n, now, _sn.mode_name(), _p.velocity.length(), _p.global_position.y, _sn.energy, draws, prims / 1000, cpu])
		_n += 1
	return false
