extends RefCounted
## Street look bot for wave 15: phase 0 busy sidewalk with the new citizens, phase 1 a row of the wave 14 vehicles (taxi, hover, patrol, van, bike).
##   tools/bot.sh res://tests/bot_wave15.gd <out_prefix> 60 2

const Fixture := preload("res://tests/player_fixture.gd")

var _every := 60
var _count := 2
var _phase := -1
var _p: Player
var _vm: VehicleManager


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))


func _enter(phase: int) -> void:
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_p.max_hp = 1.0e6
	Game.enemies.clear()
	Fixture.release_inputs()
	Game.state = &"play"
	var yaw := -PI * 0.5
	if phase == 0:
		_p.teleport_to(Game.SPAWN + Vector3(0.0, 0.0, 6.0))
	elif phase >= 2:
		var crowd: RefCounted = (Game.world as City).ambient.crowd
		var best := Vector3.ZERO
		var found := false
		var seen := 0
		if crowd != null:
			for i in crowd.count:
				if crowd._alive[i] != 0 and crowd.person_position(i).distance_to(Game.SPAWN) < 45.0:
					seen += 1
					if seen == (phase - 1) * 5:
						best = crowd.person_position(i)
						found = true
						break
		if found:
			var from := best + Vector3(-4.0, 0.0, 0.0)
			_p.teleport_to(from)
			yaw = atan2(-(best - from).x, -(best - from).z)
		print("BOT citizen view found=%s at %s" % [found, best])
	else:
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
		for v in _vm.list.duplicate():
			_vm._release(v)
		_p.teleport_to(Game.SPAWN + Vector3(12.0, 0.0, 0.0))
		var row := [[&"taxi", 9.0, -8.3, PI * 0.5], [&"hover", 16.0, -8.3, PI * 0.5], [&"vael_patrol", 24.0, -8.3, PI * 0.5],
				[&"van", 11.0, 8.3, -PI * 0.5], [&"bike", 18.0, 8.3, -PI * 0.5], [&"wagon", 26.0, 8.3, -PI * 0.5]]
		for c in row:
			_vm.spawn_parked(c[0], Vector3(Game.SPAWN.x + c[1], 0.0, c[2]), c[3])
	_p.camera_rig.reset_view(yaw, -0.1)
	_p.yaw = yaw


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
		return false
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	if slot != _phase:
		_phase = slot
		_enter(slot)
		print("BOT phase %d (frame %d)" % [slot, f])
	return f >= _every * _count
