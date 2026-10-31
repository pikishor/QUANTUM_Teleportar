extends RefCounted
## Visual bot of the contracts, tutorial and shop in the real city (scenes/main.tscn):
##   tools/bot.sh res://tests/bot_contracts.gd <out_prefix> 40 6        (every 40 frames, 6 pictures: phases 0-5)
## Phases: 0 tutorial prompt  1 hack offer  2 hack under attack (progress ring)  3 officer + boss bar  4 courier route line  5 pause screen with the upgrade shop

const NAMES: Array[String] = ["tutorial", "offer", "hack", "officer", "courier", "shop"]

var _every := 40
var _count := 6
var _p: Player
var _m: Missions
var _c: Contracts
var _phase := -1
var _base := Vector3.ZERO


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(10, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.missions == null or Game.story == null or Game.enemies == null:
		return false
	if _p == null:
		_p = Game.player as Player
		_m = Game.missions as Missions
		_c = _m.contracts
		_c.set_physics_process(false)
		_base = Game.SPAWN
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(slot)
		print("BOT phase %d %s (frame %d)" % [slot, NAMES[slot % NAMES.size()], f])
	_run(slot, k)
	if k == _every - 1 and OS.get_environment("BOT_STATS") != "":
		print("BOT stats phase %d %s: draw calls %d, primitives %d, nodes %d" % [slot, NAMES[slot % NAMES.size()],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	return f >= _every * _count


func _ahead(d: float) -> Vector3:
	var fwd := Vector3(1.0, 0.0, 0.0)
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		fwd = Vector3(cf.x, 0.0, cf.z).normalized()
	return Vector3(_p.global_position.x, 0.0, _p.global_position.z) + fwd * d


func _enter(phase: int) -> void:
	Game.state = &"play"
	_p.vehicle = null
	_p.invuln = 999.0
	_p.teleport_to(_base)
	Game.enemies.clear()
	_c._on_new_sector()
	var t := (Game.story as Story).tutorial
	match phase % NAMES.size():
		0:
			t.force = true
			t.touch_override = 1 if Game.force_touch else 0
			t.begin()
		1:
			t.skip()
			_c.offer(&"hack", _ahead(22.0))
		2:
			_c.offer(&"hack", _ahead(14.0))
			_p.teleport_to(_c.pos + Vector3(1.0, 0.0, 1.0))
			_c.tick(0.1)
			for i in 12:
				_c.tick(1.0)
		3:
			_c.offer(&"officer", _ahead(40.0))
			_p.teleport_to(_c.pos + Vector3(1.0, 0.0, 1.0))
			_c.tick(0.1)
			if _c.target != null:
				_p.teleport_to(_c.target.global_position + Vector3(-9.0, 0.0, 0.0))
				(_c.target as Drone).damage(60.0)
		4:
			_c.offer(&"courier", _ahead(10.0))
			_p.teleport_to(_c.pos + Vector3(1.0, 0.0, 1.0))
			_c.tick(0.1)
		5:
			(Game.progress as Progress).add_credits(700)
			Game.state = &"paused"
			var huds := _p.get_tree().root.find_children("*", "Hud", true, false)
			if not huds.is_empty():
				(huds[0] as Hud).press_button(&"shop")


func _run(phase: int, _k: int) -> void:
	_p.invuln = 999.0
	var rig := _p.camera_rig
	match phase % NAMES.size():
		1:
			rig.look_at_point(_c.pos + Vector3(0.0, 2.0, 0.0))
		2:
			rig.look_at_point(_c.pos + Vector3(8.0, 0.0, 0.0))          # the ring's arc on the street ahead
		3:
			if is_instance_valid(_c.target):
				rig.look_at_point(_c.target.global_position + Vector3(0.0, 1.2, 0.0))
		4:
			var r := _c.route_points()
			if r.size() >= 2:
				rig.look_at_point(r[0] + (r[1] - r[0]).normalized() * 20.0 + Vector3(0.0, 0.5, 0.0))
