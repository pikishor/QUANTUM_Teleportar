extends RefCounted
## Visual bot of the missions module: the real city and player (scenes/main.tscn) with the camera parked at a few views of a core and a pickup.
##   tools/bot.sh res://tests/bot_missions.gd <out_prefix> 30 7        (every 30 frames, 7 pictures: phases 0-6; RENDERER=compat works)
## Phases: 0 core at 25 m  1 beam from 150 m  2 core at 7 m  3 health pickup at 9 m  4 energy pickup at 22 m  5 core collected (burst)  6 beam looking up from 40 m
## BOT_STATS=1 prints draw calls and primitives at the end of each phase.

const NAMES: Array[String] = ["core_25m", "beam_150m", "core_7m", "health_9m", "energy_22m", "collect", "beam_up"]

var _every := 30
var _count := 7
var _p: Player
var _m: Missions
var _phase := -1
var _core: Vector3
var _dir := Vector3(0.0, 0.0, 1.0)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(10, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.missions == null or (Game.missions as Missions).cores.is_empty():
		return false
	if _p == null:
		_p = Game.player as Player
		_m = Game.missions as Missions
		_core = _m.cores[0].pos
		_dir = Vector3(0.0, 0.0, -signf(_core.z) if _core.z != 0.0 else 1.0)      # toward the middle of the city
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(slot)
		print("BOT phase %d %s (frame %d)" % [slot, NAMES[slot % NAMES.size()], f])
	_run(slot, k)
	if k == _every - 1 and OS.get_environment("BOT_STATS") != "":
		print("BOT stats phase %d %s: draw calls %d, primitives %d, cores %d, pickups %d" % [slot, NAMES[slot % NAMES.size()],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), _m.cores.size(), _m.pickups.size()])
	return f >= _every * _count


func _place(offset: float) -> void:
	_p.vehicle = null
	_p.invuln = 999.0
	_p.teleport_to(_core + _dir * offset)
	var rig := _p.camera_rig
	rig.reset_view(atan2(-_dir.x, -_dir.z) + PI, -0.05)      # face the core, i.e. back along the direction we came from
	_p.yaw = rig.yaw


func _enter(phase: int) -> void:
	Game.state = &"play"
	_m.clear_pickups()
	match phase % NAMES.size():
		0:
			_place(25.0)
		1:
			_place(150.0)
		2:
			_place(7.0)
		3:
			_place(24.0)
			_m.drop(&"health", _core + _dir * 15.0)
		4:
			_place(36.0)
			_m.drop(&"energy", _core + _dir * 14.0)
		5:
			_place(14.0)
		6:
			_place(40.0)


func _run(phase: int, k: int) -> void:
	var rig := _p.camera_rig
	_p.invuln = 999.0
	var gem := _core + Vector3(0.0, 2.0, 0.0)
	match phase % NAMES.size():
		0, 2, 5:
			rig.look_at_point(gem)
			if phase % NAMES.size() == 5 and k == _every - 3 and not _m.cores.is_empty():
				_p.teleport_to(_core + Vector3(0.0, 0.0, 1.0))      # step onto the core: the burst is on screen at the end of the phase
		1:
			rig.look_at_point(_core + Vector3(0.0, 55.0, 0.0))
		3:
			rig.look_at_point(_core + _dir * 15.0 + Vector3(0.0, 0.9, 0.0))
		4:
			rig.look_at_point(_core + _dir * 14.0 + Vector3(0.0, 0.9, 0.0))
		6:
			rig.look_at_point(_core + Vector3(0.0, 120.0, 0.0))
