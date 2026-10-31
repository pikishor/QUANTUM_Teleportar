extends RefCounted
## Visual bot of the enemies module: stages a group (2 operatives, a sentinel, a heavy, a striker) on the real city's main avenue in front of the player,
## then lets the player fire at it. Look at the pictures: readability of operatives and drones at 8-28 m (DynamicFill), tracers, bolts, hit effects, deaths.
##   tools/bot.sh res://tests/bot_enemies.gd <out_prefix> 40 8        (every 40 frames, 8 pictures: phases 0-7; writes <out_prefix>_000.png ...)
##   RENDERER=compat tools/bot.sh ...                                   (OpenGL Compatibility renderer)
##   BOT_PHASES=1,4 tools/bot.sh ... 40 2                               (only these phases, in this order; the count must match)
##   BOT_STATS=1                                                         (print draw calls and primitives at the end of each phase)
## Phases: 0 idle group  1 alerted  2 firing at the first operative  3 second operative  4 enemy fire (player holds still)  5 operative close-up
##   6 striker charge  7 heavy under fire. The game runs in slow motion (Engine.time_scale) so a software-rendered frame covers about 20 ms of game time.

const Fixture := preload("res://tests/player_fixture.gd")

const TIME_SCALE := 0.3
const NAMES: Array[String] = ["idle", "alerted", "fire_op", "fire_op2", "enemy_fire", "closeup", "striker", "heavy"]

var _every := 40
var _count := 8
var _phase := -1
var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _order: Array[int] = []
var _group: Array[Drone] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	for part in OS.get_environment("BOT_PHASES").split(",", false):
		_order.append(int(part))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_mgr = Game.enemies as EnemyManager
	Engine.time_scale = TIME_SCALE
	_p.max_hp = 1.0e6
	_mgr.patrol_groups().clear()          # only the staged group


func _stage(offsets: Array, types: Array, aware: bool) -> void:
	_mgr.clear()
	_group.clear()
	for i in offsets.size():
		var d := _mgr.spawn(types[i], Game.SPAWN + (offsets[i] as Vector3), aware)
		if d != null:
			d.hp = d.max_hp * 1.0
			_group.append(d)


func _reset_player() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.weapon.reset()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	Game.heat = 0.0


func _enter(phase: int) -> void:
	Fixture.release_inputs()
	match phase:
		0:
			_reset_player()
			_stage([Vector3(9.0, 0.0, -2.5), Vector3(14.0, 0.0, 3.5), Vector3(18.0, 0.0, -1.0), Vector3(26.0, 0.0, 4.0), Vector3(22.0, 0.0, -5.0)],
					[&"operative", &"operative", &"sentinel", &"heavy", &"operative"], false)
		1:
			for d in _group:
				d.alert()
		2, 3:
			pass
		4:
			_reset_player()
			_stage([Vector3(10.0, 0.0, -2.0), Vector3(16.0, 0.0, 3.0), Vector3(14.0, 0.0, -4.0), Vector3(24.0, 0.0, 1.0)],
					[&"operative", &"sentinel", &"operative", &"heavy"], true)
		5:
			_reset_player()
			_stage([Vector3(6.0, 0.0, -3.6), Vector3(9.0, 0.0, 3.6)], [&"operative", &"sentinel"], false)
		6:
			_reset_player()
			_stage([Vector3(22.0, 0.0, 0.0), Vector3(30.0, 0.0, 4.0), Vector3(18.0, 0.0, 6.0)], [&"striker", &"striker", &"operative"], true)
		7:
			_reset_player()
			_stage([Vector3(15.0, 0.0, 0.0), Vector3(24.0, 0.0, 6.0)], [&"heavy", &"sentinel"], true)


func _aim(d: Drone, fire: bool) -> void:
	if not is_instance_valid(d) or d.dead or not d.active:
		Input.action_release(&"fire")
		return
	_p.camera_rig.aim_at(d.center())
	if fire:
		Input.action_press(&"fire")


func _run(phase: int, _k: int) -> void:
	match phase:
		2:
			_p.invuln = 5.0
			_aim(_group[0], true)
		3:
			_p.invuln = 5.0
			_aim(_group[1], true)
		4:
			_p.invuln = 0.0
			_p.camera_rig.aim_at(_group[0].center())
		7:
			_aim(_group[0], true)


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var phase := _order[slot % _order.size()] if not _order.is_empty() else slot
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(phase)
		print("BOT phase %d %s (frame %d)" % [phase, NAMES[phase % NAMES.size()], f])
	_run(phase, k)
	if k == _every - 1:
		var alive := 0
		for d in _mgr.list:
			alive += 1 if not d.dead else 0
		print("BOT phase %d: %d enemies alive, %d bolts, player hp %.0f%s" % [phase, alive, _mgr.active_bolts(), _p.hp,
				(", draw calls %d, primitives %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]) if OS.get_environment("BOT_STATS") != "" else ""])
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
