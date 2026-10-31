extends RefCounted
## Full-game bot (integrator): real main scene, real Player/Hud/Story/Quantum/Vehicles. One picture per phase, stats line per phase.
##   tools/bot.sh res://tests/bot_full.gd <out_prefix> 30 14       (add --touch via BOT_TOUCH=1 env to force the touch layout)
## 0 start (car + 4 enemies in view)  1 firing  2 kill  3 blink beacon  4 teleport  5 link  6 superpose  7 collapse blast  8 car explosion
## 9 enter car  10 drive  11 exit  12 die  13 respawn

const Fixture := preload("res://tests/player_fixture.gd")
const NAMES: Array[String] = ["start", "fire", "kill", "beacon", "teleport", "link", "superpose", "collapse", "car_blast", "enter", "drive", "exit", "die", "respawn"]
var _every := 30
var _count := 14
var _phase := -1
var _setup_done := false
var _p: Player
var _vm: VehicleManager
var _em: EnemyManager
var _hud: Hud
var _drones: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(20, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	if OS.get_environment("BOT_TOUCH") != "":
		Game.force_touch = true


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_em = Game.enemies as EnemyManager
	for c in Game.vehicles.get_parent().get_children():
		if c is Hud:
			_hud = c
	Engine.time_scale = 0.3
	_em.patrol_groups().clear()
	_em.clear()
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy


func _face(pos: Vector3, yaw: float) -> void:
	_p.teleport_to(pos)
	_p.camera_rig.reset_view(yaw, -0.1)
	_p.yaw = yaw


func _spawn_four() -> void:
	_em.clear()
	_drones.clear()
	var types: Array = [&"sentinel", &"operative", &"operative", &"sentinel"]
	for i in 4:
		_drones.append(_em.spawn(types[i], Game.SPAWN + Vector3(14.0 + 3.0 * i, 0.0, -6.0 + 4.0 * i), true))


func _enter(ph: int) -> void:
	_p.energy = _p.max_energy
	match ph:
		0:
			_face(Game.SPAWN, -PI * 0.5)
			_spawn_four()
			_p.invuln = 99.0
			_hud.press_button(&"respawn") if Game.state != &"play" else null
		3, 4, 5, 6:
			_p.invuln = 99.0
		8:
			_em.clear()
			_face(Game.SPAWN, -PI * 0.5)
			var c := _vm.spawn_parked(&"sedan", Game.SPAWN + Vector3(9.0, 0.0, -4.0), PI * 0.5)
			if c != null: c.set_meta(&"bot", true)
		9:
			_em.clear()
			_face(Game.SPAWN, -PI * 0.5)
			_p.teleport_to(_vm.starter.global_position + Vector3(2.0, 0.0, 0.0))
		11:
			pass
		12:
			_p.invuln = 0.0
			_spawn_four()
		13:
			_hud.screen_age = 5.0
			_hud.press_button(&"respawn")


func _run(ph: int, k: int) -> void:
	var q: Node = _p.quantum
	match ph:
		1:
			if k == 5 and _drones.size() > 0:
				Input.action_press(&"fire")
			if k == _every - 2:
				Input.action_release(&"fire")
		2:
			for d in _drones:
				if is_instance_valid(d) and k == 6:
					d.damage(9999.0)
		3:
			if k == 4: q.blink()
		4:
			if k == 4: q.blink()
		5:
			if k == 4:
				_spawn_four()
			if k == 8: q.entangle()
		6:
			if k == 4: q.superpose()
		7:
			if k == 4 and q.clone != null:
				q.clone.global_position = Game.SPAWN + Vector3(14.0, 0.0, -2.0)
			if k == _every - 5 and q.clone != null: q.collapse()
		8:
			if k == _every - 6:
				for v in _vm.list:
					if v.has_meta(&"bot") and is_instance_valid(v): v.damage(9999.0)
		9:
			if k == 4: _vm.enter(_vm.starter)
		10:
			Input.action_press(&"move_forward")
		11:
			Input.action_release(&"move_forward")
			if k == 4: _vm.exit_vehicle()
		12:
			if k == _every - 8:
				_p.damage(999.0, _drones[0].global_position if is_instance_valid(_drones[0]) else Vector3.ZERO)


func _dump_casters() -> void:
	var agg := {}
	var stack: Array = [Game.world.get_tree().root]
	var cam := _p.camera_rig.camera.global_position
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree() and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var g := n as GeometryInstance3D
			if g.global_position.distance_to(cam) > 120.0:
				continue
			var surf := 1
			if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
				surf = (g as MeshInstance3D).mesh.get_surface_count()
			var key := "%s/%s" % [str(n.get_parent().name).rstrip("0123456789"), str(n.name).rstrip("0123456789")]
			agg[key] = int(agg.get(key, 0)) + surf
	print("BOT casters ", agg)


func _stats(ph: int) -> void:
	if ph == 0 and OS.get_environment("BOT_DUMP") != "":
		_dump_casters()
	var vp := _p.get_viewport().get_viewport_rid()
	var info := RenderingServer
	print("BOT stats %2d %-10s visible draws=%d prims=%d | total draws=%d prims=%d | state=%s hp=%d enemies=%d vehicle=%s cam_dist=%.1f" % [ph, NAMES[ph],
		info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		info.viewport_get_render_info(vp, info.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		info.get_rendering_info(info.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), info.get_rendering_info(info.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		Game.state, int(_p.hp), _em.list.size(), str(_p.vehicle != null), _p.camera_rig.camera.global_position.distance_to(_p.global_position)])


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(slot)
	_run(slot, k)
	if k == _every - 1:
		_stats(slot)
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
