extends RefCounted
## Visual bot of the player module. Drives the real Player through its input actions in a small night arena (tests/player_arena.gd) and lets
## Dev save a screenshot every N frames (tools/bot.sh does that). Look at the pictures: camera framing, model readability, tracers, flashes.
##   tools/bot.sh res://tests/bot_player.gd <out_prefix> 30 20        (every 30 frames, 20 pictures: phases 0-19; writes <out_prefix>_000.png ...)
##   RENDERER=compat tools/bot.sh ...                                     (OpenGL Compatibility renderer)
##   BOT_MODE=city tools/bot.sh ...                                       (keep the other modules and walk the real city instead of the arena)
##   BOT_PHASES=2,6,7 tools/bot.sh ... 40 3                              (run only these phases, in this order; the count must match)
## Software rendering runs at 5-10 fps, which would hide a 0.05 s muzzle flash between two rendered frames, so the bot runs the game in slow motion
## (Engine.time_scale): every rendered frame then covers about 20 ms of game time, like a 50 fps device. Phases are counted in rendered frames and
## end exactly on a screenshot frame, so each picture shows the end of its phase:
##   0 idle  1 walk  2 strafe  3 sprint  4 jump (apex)  5 aim down sights  6 hip fire  7 ADS fire  8 automatic fire  9 reload  10 crit
##   11 hurt  12 vehicle chase  13 camera pull-in at a wall  14 death  15 respawn  16 front  17 side  18 rifle close-up  19 wall holes
##   20 the idle view with the body hidden (BOT_STATS=1 prints draw calls and primitives at the end of each phase: phase 0 minus phase 20 is the player's cost)

const Arena := preload("res://tests/player_arena.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const TIME_SCALE := 0.2
const NAMES: Array[String] = ["idle", "walk", "strafe", "sprint", "jump", "ads", "fire_hip", "fire_ads", "fire_auto", "reload", "crit",
		"hurt", "vehicle", "pullin", "death", "respawn", "front", "side", "closeup", "wall_hole", "hidden_body"]

var _every := 40
var _count := 20
var _mode := "arena"
var _setup_done := false
var _p: Player
var _rig: CameraRig
var _dummies: Array[Node3D] = []
var _car: Node3D
var _phase := -1
var _order: Array[int] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))              # a phase needs at least 30 frames (the jump and the burst are timed back from its end)
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	var m := OS.get_environment("BOT_MODE")
	if m != "":
		_mode = m
	for part in OS.get_environment("BOT_PHASES").split(",", false):
		_order.append(int(part))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_rig = _p.camera_rig
	Engine.time_scale = TIME_SCALE
	var main := _p.get_parent()
	if _mode == "arena":
		for c in main.get_children():
			if c != _p:
				c.queue_free()                       # strip the other modules: this bot looks at the player alone
		Game.world = null
		var info := Arena.build(main as Node3D)
		for d in info["dummies"]:
			_dummies.append(d as Node3D)
		_car = info["car"] as Node3D
	else:
		_car = Fixture.add_vehicle(main, Game.SPAWN + Vector3(4.0, 0.0, 6.0), Vector3(1.9, 1.3, 4.5), false, true)
		for pos: Vector3 in [Vector3(14.0, 0.0, 0.0), Vector3(20.0, 0.0, 6.0)]:
			var d := Fixture.add_dummy(main, Game.SPAWN + pos, 0.95, true, true)
			d.respawn_after = 2.0
			_dummies.append(d)


func _spawn() -> Vector3:
	return Arena.ARENA_SPAWN if _mode == "arena" else Game.SPAWN


func _reset_player(pos: Vector3, yaw: float, pitch := -0.1) -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.vehicle = null
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.since_hurt = 99.0
	_p.weapon.reset()
	_p.teleport_to(pos)
	_rig.reset_view(yaw, pitch)
	_p.yaw = yaw


func step(_t: float, delta: float) -> bool:
	if Game.player == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var phase := _order[slot % _order.size()] if not _order.is_empty() else slot
	var k := ((f - 1) % _every) + 1                  # 1 .. _every, the screenshot is taken at k == _every
	if slot != _phase:
		_phase = slot
		_enter(phase)
		print("BOT phase %d %s (frame %d)" % [phase, NAMES[phase % NAMES.size()], f])
	_run(phase, k, delta)
	if k == _every - 1 and OS.get_environment("BOT_STATS") != "":
		print("BOT stats phase %d %s: draw calls %d, primitives %d, objects %d" % [phase, NAMES[phase % NAMES.size()],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	return f >= _every * _count


func _target() -> Node3D:
	return _dummies[0]


func _center(d: Node3D) -> Vector3:
	return d.call(&"center")


## Called once at the first frame of a phase.
func _enter(phase: int) -> void:
	var yaw := -PI * 0.5
	match phase:
		0:
			_reset_player(_spawn(), yaw)
		1:
			_reset_player(_spawn(), yaw)
			Input.action_press(&"move_forward")
		2:
			_reset_player(_spawn() + Vector3(0.0, 0.0, -2.0), yaw)
			Input.action_press(&"move_right")
		3:
			_reset_player(_spawn() + Vector3(-4.0, 0.0, 0.0), yaw, -0.06)
			Input.action_press(&"move_forward")
			Input.action_press(&"sprint")
		4:
			_reset_player(_spawn(), yaw)
		5:
			_reset_player(_spawn(), yaw)
			Input.action_press(&"aim")
		6:
			_reset_player(_spawn(), yaw)
		7:
			_reset_player(_spawn(), yaw)
			Input.action_press(&"aim")
		8:
			_reset_player(_spawn(), yaw)
		9:
			_reset_player(_spawn(), yaw)
			Input.action_press(&"fire")
		10:
			_reset_player(_spawn(), yaw)
		11:
			_reset_player(_spawn(), yaw)
		12:
			_reset_player(_spawn(), yaw)
			if _car != null:
				_car.global_position = _spawn() + Vector3(2.0, 0.0, -12.0)
				_car.heading = -PI * 0.5
				_car.rotation.y = _car.heading
				_car.speed = 9.0
				_p.vehicle = _car
		13:
			if _car != null:
				_car.speed = 0.0
			_p.vehicle = null
			if _mode == "arena":
				_reset_player(Vector3(-15.6, 0.0, -4.0), yaw, -0.05)
			else:
				_reset_player(Game.SPAWN + Vector3(0.0, 0.0, 0.0), yaw)
		14:
			_reset_player(_spawn(), yaw)
			_p.damage(999.0)
		15:
			Game.do_respawn()
			_p.teleport_to(_spawn())                 # Game.SPAWN lies inside the arena's wall: respawn at the arena's own spawn
			_rig.reset_view(yaw, -0.1)
		16, 17, 18:
			_reset_player(_spawn(), yaw)
			if phase == 18:
				Input.action_press(&"aim")
			else:
				Game.state = &"menu"
		19:
			_reset_player(_spawn() + Vector3(34.0, 0.0, 0.0), yaw, -0.02)
			Input.action_press(&"aim")
			if _mode == "arena":
				# a cluster of old holes on the wall, so the picture shows the decals themselves and not only the fresh sparks
				_p.decals.clear()
				for i in 9:
					_p.decals.add(Vector3(32.99, 1.55 + (i % 3) * 0.32, -0.7 + (i / 3) * 0.55 + (i % 2) * 0.12), Vector3(-1.0, 0.0, 0.0), 0.17 + (i % 4) * 0.02)
		20:
			# the same view with and without the body and its lights, toggled every 10 frames (BOT_STATS=1 prints the difference)
			_reset_player(_spawn(), yaw)
		_:
			_reset_player(_spawn(), yaw)
			Input.action_press(&"move_forward")


func _run(phase: int, k: int, delta: float) -> void:
	var e := _every
	match phase:
		2:
			_rig.look_at_point(_center(_target()))
		3:
			pass
		4:
			if k == e - 17:
				Input.action_press(&"jump")
			elif k == e - 14:
				Input.action_release(&"jump")
		5:
			_rig.look_at_point(_center(_target()))
		6, 7:
			_rig.look_at_point(_center(_target()))
			if k == e - 2:
				Input.action_press(&"fire")
			elif k == e - 1:
				Input.action_release(&"fire")
		8:
			_rig.look_at_point(_center(_dummies[1]) if _dummies.size() > 1 else _center(_target()))
			if k == e - 24:
				Input.action_press(&"fire")
		9:
			if k == 3:
				Input.action_release(&"fire")
				Input.action_press(&"reload")
			elif k == 6:
				Input.action_release(&"reload")
		10:
			var c: Vector3 = _center(_target())
			_rig.look_at_point(c + Vector3(0.0, 0.7, 0.0))
			if k == e - 2:
				Input.action_press(&"fire")
			elif k == e - 1:
				Input.action_release(&"fire")
		11:
			if k == e - 2:
				_p.damage(25.0, _p.global_position + Vector3(6.0, 1.0, 3.0))
		12:
			if _car != null:
				_car.drive(delta)
		14, 15:
			pass
		20:
			var show := (k / 10) % 2 == 0
			_p.body.visible = show
			_p.body.character_light = show
			if OS.get_environment("BOT_STATS") != "" and k % 10 == 9:
				print("BOT ab body=%s: draw calls %d, primitives %d" % [str(show), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
						RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		16:
			_rig.yaw = _p.yaw + PI
			_rig.pitch = -0.04
		17:
			_rig.yaw = _p.yaw + PI * 0.5
			_rig.pitch = -0.04
		18:
			_rig.look_at_point(_center(_target()) + Vector3(0.0, 0.3, 0.0))
		19:
			var hit := Vector3(33.0, 1.9, 0.0) if _mode == "arena" else Game.SPAWN + Vector3(60.0, 2.0, 0.0)
			_rig.look_at_point(hit)
			if k > 8 and k % 8 == 0 and k < e - 14:
				Input.action_press(&"fire")
			elif k % 8 == 1:
				Input.action_release(&"fire")
		_:
			pass
