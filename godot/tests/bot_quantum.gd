extends RefCounted
## Visual bot of the quantum module in the real city: beacon, teleport (with the Alice / Bob readout), entangle, ghost clone and collapse blast.
##   tools/bot.sh res://tests/bot_quantum.gd <out_prefix> 40 5        (every 40 frames, 5 pictures: phases 0-4; writes <out_prefix>_000.png ...)
##   RENDERER=compat tools/bot.sh ...                                   (OpenGL Compatibility renderer)
##   BOT_PHASES=0,3 tools/bot.sh ... 40 2                               (only these phases, in this order; the count must match)
##   BOT_QUALITY=0|1|2                                                   (graphics tier, default 1)
##   BOT_STATS=1                                                         (print draw calls and primitives at the end of each phase)
## Phases: 0 beacon out  1 just teleported (readout)  2 entangled pair under fire  3 ghost clone  4 collapse blast. Slow motion keeps one software frame near 20 ms.

const Fixture := preload("res://tests/player_fixture.gd")

const TIME_SCALE := 0.3
const NAMES: Array[String] = ["beacon", "teleport", "entangle", "clone", "collapse"]

var _every := 40
var _count := 5
var _phase := -1
var _setup_done := false
var _p: Player
var _q: Quantum
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
	_q = _p.quantum as Quantum
	_mgr = Game.enemies as EnemyManager
	Engine.time_scale = TIME_SCALE
	_p.max_hp = 1.0e6
	_mgr.patrol_groups().clear()
	var tier := OS.get_environment("BOT_QUALITY")
	if tier != "":
		Game.set_quality(int(tier))


func _reset_player() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	_q.reset()
	_mgr.clear()
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.weapon.reset()
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	Game.heat = 0.0


func _stage(offsets: Array, types: Array) -> void:
	_group.clear()
	for i in offsets.size():
		var d := _mgr.spawn(types[i], Game.SPAWN + (offsets[i] as Vector3), false)
		if d != null:
			_group.append(d)


func _enter(phase: int) -> void:
	_reset_player()
	match phase:
		0:
			_p.camera_rig.reset_view(-PI * 0.5, -0.22)
		1:
			_p.camera_rig.reset_view(-PI * 0.5, -0.22)
		2:
			_stage([Vector3(11.0, 0.0, -2.5), Vector3(17.0, 0.0, 3.5), Vector3(24.0, 0.0, -1.0)], [&"sentinel", &"sentinel", &"heavy"])
		3, 4:
			_stage([Vector3(2.5, 0.0, 6.0)] if phase == 4 else [], [&"sentinel"])


func _run(phase: int, k: int) -> void:
	match phase:
		0:
			if k == 2:
				_q.blink()
		1:
			if k == 2:
				_q.blink()
			elif k == 6:
				_q.blink()
		2:
			if k == 3 and _group.size() >= 2:
				_p.camera_rig.aim_at(_group[0].center())
			elif k == 5:
				_q.link_drones()
			elif k == 20 and not _group.is_empty():
				_group[0].damage(14.0)
		3:
			if k == 2:
				_q.superpose()
			elif k == 4:
				_p.teleport_to(Game.SPAWN + Vector3(5.5, 0.0, 3.0))
			elif k == 6:
				_p.camera_rig.aim_at(_q.clone.global_position + Vector3(0.0, 1.0, 0.0)) if _q.clone != null else null
		4:
			if k == 2:
				_q.superpose()
			elif k == 3:
				_p.teleport_to(Game.SPAWN + Vector3(-4.0, 0.0, 8.0))
				_p.camera_rig.aim_at(Game.SPAWN + Vector3(2.5, 1.0, 4.0))
			elif k == 24:
				_q.collapse()


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or (Game.player as Player).quantum == null:
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
		print("BOT phase %d: beacon %s clone %s links %d energy %.0f%s" % [phase, _q.has_beacon, _q.clone != null, _q.links.size(), _p.energy,
				(", draw calls %d, primitives %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]) if OS.get_environment("BOT_STATS") != "" else ""])
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
