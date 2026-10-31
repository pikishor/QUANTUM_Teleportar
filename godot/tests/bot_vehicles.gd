extends RefCounted
## Visual bot of the vehicles module on the real city (real main scene): the starter car parked with enemies around, driving it, a drift, a close look at the
## paint and lights, traffic, an explosion. Prints draw calls, primitives and live cars at the end of each phase.
##   tools/bot.sh res://tests/bot_vehicles.gd <out_prefix> 40 7        (every 40 frames, 7 pictures: phases 0-6)
##   RENDERER=compat tools/bot.sh ...                                    (OpenGL Compatibility renderer)
##   BOT_PHASES=0,3 tools/bot.sh ... 40 2                                (only these phases, in this order; the count must match)
##   BOT_NOCARS=1                                                        (no cars at all: the baseline of the city, player and enemies)
##   BOT_NOENEMIES=1                                                     (phase 0 without the staged enemies)
##   BOT_ONLY_STARTER=1                                                  (no streamed cars: starter car + staged enemies only, for the draw-call budget)
## Phases: 0 starter parked + 4 enemies in view  1 driving  2 drifting  3 close look  4 traffic around the junction  5 explosion  6 night view of the lights
##   7 worst case for the budget: the starter car and 4 more cars (a full MED cap) all in view within 30 m, no enemies
## The game runs in slow motion (Engine.time_scale) so a software-rendered frame covers about 20 ms of game time.

const Fixture := preload("res://tests/player_fixture.gd")

const TIME_SCALE := 0.3
const NAMES: Array[String] = ["parked_enemies", "driving", "drift", "closeup", "traffic", "explosion", "lights", "car_lot"]

var _every := 40
var _count := 7
var _phase := -1
var _setup_done := false
var _p: Player
var _vm: VehicleManager
var _em: EnemyManager
var _order: Array[int] = []


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
	_vm = Game.vehicles as VehicleManager
	_em = Game.enemies as EnemyManager
	Engine.time_scale = TIME_SCALE
	_p.max_hp = 1.0e6
	_em.patrol_groups().clear()
	_em.clear()
	if OS.get_environment("BOT_NOCARS") != "":                   # budget baseline: no cars at all (the phases that need the starter car will not work)
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
		for v in _vm.list.duplicate():
			_vm._release(v)
		_vm.starter = null
	if OS.get_environment("BOT_ONLY_STARTER") != "":
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
		for v in _vm.list.duplicate():
			if v != _vm.starter:
				_vm._release(v)


func _reset_player(pos: Vector3, yaw: float) -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	if _vm.driven != null:
		_vm.exit_vehicle()
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.teleport_to(pos)
	_p.camera_rig.reset_view(yaw, -0.12)
	_p.yaw = yaw
	Game.heat = 0.0


func _enter(phase: int) -> void:
	Fixture.release_inputs()
	var s := _vm.starter
	if s == null:
		s = _vm.spawn_parked(&"sport", VehicleSpecs.starter_pos(), VehicleSpecs.STARTER_HEADING) if OS.get_environment("BOT_NOCARS") == "" else null
	if s == null and phase != 0:
		return
	match phase:
		0:
			_reset_player(Game.SPAWN, -PI * 0.5)
			_em.clear()
			if OS.get_environment("BOT_NOENEMIES") != "":
				return
			for o in [Vector3(14.0, 0.0, -2.5), Vector3(18.0, 0.0, 3.5), Vector3(24.0, 0.0, -1.0), Vector3(30.0, 0.0, 4.0)]:
				_em.spawn(&"sentinel" if o.x < 20.0 else &"operative", Game.SPAWN + o, false)
		1:
			_em.clear()
			_reset_player(s.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
			_vm.enter(s)
		2:
			pass
		3:
			_vm.exit_vehicle()
			_reset_player(s.global_position + Vector3(-5.0, 0.0, -1.5), -PI * 0.5 + 0.35)
		4:
			_reset_player(Vector3(0.0, 0.0, 12.0), -PI * 0.5)
			_vm.stream_every = 0.05
		5:
			_reset_player(s.global_position + Vector3(-9.0, 0.0, 2.0), -PI * 0.5)
		6:
			_reset_player(s.global_position + Vector3(4.0, 0.0, 6.0), PI * 0.75)
		7:
			_em.clear()
			for v in _vm.list.duplicate():
				if v != s:
					_vm._release(v)
			_vm.stream_every = 1.0e9
			_vm._stream_t = 1.0e9
			_reset_player(Game.SPAWN, -PI * 0.5)
			var lot := [[&"sedan", 13.0, -8.3, PI * 0.5], [&"suv", 22.0, -8.3, PI * 0.5], [&"sedan", 30.0, 8.3, -PI * 0.5], [&"sport", 17.0, 8.3, -PI * 0.5]]
			for c in lot:
				_vm.spawn_parked(c[0], Vector3(Game.SPAWN.x + c[1], 0.0, c[2]), c[3])


func _run(phase: int, k: int) -> void:
	match phase:
		1:
			Input.action_press(&"move_forward")
			if k > 25:
				Input.action_press(&"move_right")
		2:
			Input.action_press(&"move_forward")
			Input.action_release(&"move_right")
			if k > 8:
				Input.action_press(&"move_left")
			if k > 20:
				Input.action_press(&"jump")
		5:
			if k == 12 and _vm.starter != null:
				_vm.starter.damage(9999.0)


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
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
		var info := RenderingServer
		print("BOT phase %d: live cars %d (traffic %d, parked %d), speed %.1f, car hp %.0f, enemies %d, draw calls %d, primitives %d, quality %d" % [
				phase, _vm.list.size(), _vm.traffic_count(), _vm.parked_count(), _vm.starter.speed if _vm.starter != null else 0.0,
				_vm.starter.hp if _vm.starter != null else 0.0, _em.alive_count(),
				info.get_rendering_info(info.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), info.get_rendering_info(info.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), Game.quality])
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
