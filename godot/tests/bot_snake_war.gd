extends RefCounted
## Look-dev bot of the snake combat (wave 115): the real game, the real camera behind the hero, one power at a time cast at three operatives (and a parked car), four frames each (SW_MOMENTS seconds
## after the cast), saved as <SW_OUT>/<id>_m<k>.png. The renderer only runs for the frames that are saved (RenderingServer.render_loop_enabled), so a sweep takes minutes.
##   SW_OUT=/tmp/x SW_IDS=sv_pull,sb_coil SW_DIST=10 BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_snake_war.gd /tmp/x/seq 100000 1
## SW_FOES=0 leaves the enemies out, SW_CAR=0 the car, SW_SPOT="x,z,yaw" fixes the street, SW_HUD=1 keeps the phone HUD (BOT_USER_ARGS="--touch"), SW_ARM=0 casts without arming.

const DEFAULT_IDS := "sv_pull,sv_grab,sv_net,sv_lash,sv_shield,sb_coil,sb_swarm,sb_chain,sb_gravity,sb_storm,sb_mega"
const MOMENTS := {
	&"sv_pull": [0.12, 0.3, 0.7, 1.4], &"sv_grab": [0.3, 0.9, 1.5, 2.1], &"sv_disarm": [0.1, 0.3, 0.6, 1.2], &"sv_yank": [0.15, 0.4, 0.8, 1.4], &"sv_net": [0.25, 0.6, 1.4, 2.6],
	&"sv_lash": [0.1, 0.45, 0.9, 1.4], &"sv_shield": [0.3, 1.0, 2.4, 4.0], &"sv_decoy": [0.3, 0.9, 2.0, 4.0], &"sv_trap": [0.3, 0.9, 1.6, 2.4], &"sv_guard": [0.4, 1.4, 2.6, 4.0],
	&"sb_coil": [0.5, 1.0, 1.5, 2.6], &"sb_swarm": [0.8, 1.3, 1.9, 2.8], &"sb_flare": [0.5, 0.9, 1.5, 2.6], &"sb_freeze": [0.5, 1.0, 1.8, 3.2], &"sb_seeker": [0.3, 0.7, 1.1, 1.7],
	&"sb_chain": [0.5, 0.8, 1.1, 1.6], &"sb_cluster": [0.5, 0.8, 1.1, 1.8], &"sb_constrict": [0.8, 1.6, 2.2, 3.2], &"sb_burrow": [0.4, 0.9, 1.4, 2.0], &"sb_gravity": [0.6, 1.2, 1.8, 2.6],
	&"sb_storm": [0.5, 1.0, 1.7, 2.6], &"sb_mega": [0.5, 1.0, 1.4, 2.2],
}

var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _war: SnakeWar
var _spot := Vector3.ZERO
var _yaw := 0.0
var _ids: Array[StringName] = []
var _i := 0
var _t := 0.0
var _phase := 0
var _shots := 0
var _out := ""
var _foes: Array[Drone] = []
var _car: Vehicle
var _render_on := true
var _fired := false
var _warm := 0.0
var _dist := 10.0
var _lash_n := 0
var _released := false


func _init() -> void:
	_out = OS.get_environment("SW_OUT")
	var s := OS.get_environment("SW_IDS")
	for n in (s if s != "" else DEFAULT_IDS).split(",", false):
		_ids.append(StringName(n))
	var d := OS.get_environment("SW_DIST")
	_dist = float(d) if d != "" else 10.0


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	for tries in 600:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-5.0, 0.0, 5.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 64.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_yaw = yaw
				return true
	return false


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_mgr = Game.enemies as EnemyManager
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	_mgr.patrol_groups().clear()
	_mgr.clear()
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	var forced := OS.get_environment("SW_SPOT")
	if forced != "":
		var fp := forced.split(",")
		_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
		_yaw = float(fp[2])
	elif not _lane():
		print("BOTSW no open lane found")
		return
	DirAccess.make_dir_recursive_absolute(_out)
	WeaponDefs.hero_mode = true
	_war = SnakeWar.of(_p)
	print("BOTSW lane at ", _spot, " yaw ", _yaw, " ids ", _ids)


func _stage() -> void:
	var sw := SnakeSwarm.current
	if sw != null:
		sw.clear()
	var ops := BlastOps.shared(_p.get_tree())
	ops.reset()
	BlastFx.shared().reset()
	if FX.marks != null:
		FX.marks.clear()
	if FX.car_debris != null:
		FX.car_debris.clear()
	_war.reset()
	_mgr.clear()
	_foes.clear()
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.06)
	var dist := _dist
	var id := _ids[_i]
	if id == &"sv_lash":
		dist = 4.5
	var at := _spot + _dir() * dist
	if OS.get_environment("SW_FOES") != "0":
		for k in 3:
			var pos := at + _right() * (float(k - 1) * 2.4) + _dir() * (float(k % 2) * 2.0 - 0.8)
			pos.y = _spot.y
			var f := _mgr.spawn(&"operative", pos, false)
			if f != null:
				f.set_physics_process(false)
				f.global_position = pos
				f.max_hp = 1.0e6
				f.hp = 1.0e6
				f.rotation.y = _yaw + PI
				_foes.append(f)
	if OS.get_environment("SW_CAR") != "0":
		var vm := Game.vehicles as VehicleManager
		if vm != null:
			vm._reset_all()
			_car = vm.spawn_parked(&"sedan", at + _right() * 8.0 + _dir() * 1.5, _yaw + PI * 0.5)
			if _car != null:
				_car.hp = _car.max_hp
				_car.visual.repair()
				_car.visual.set_damage_look(0.0)
				_car.visual.set_deform(0.0)
				_car.visual.set_condition(0.0)
	if (id == &"sv_yank" or id == &"sb_burrow") and _car != null:
		_p.camera_rig.aim_at(_car.global_position + Vector3(0.0, 0.7, 0.0))
	_t = 0.0
	_shots = 0
	_fired = false
	_lash_n = 0
	_released = false


func _fire(id: StringName) -> void:
	if OS.get_environment("SW_ARM") != "0":
		_war.arm(id)
	if id == &"sv_grab":
		Input.action_press(&"fire")                                  # the thumb stays on FIRE while the snakes hold the body
	_war.cast(id, true)


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
		if _spot == Vector3.ZERO:
			return true
	if _i >= _ids.size():
		RenderingServer.render_loop_enabled = true
		WeaponDefs.hero_mode = false
		print("BOTSW done")
		_p.get_tree().quit()
		return true
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 2.5:
		if _warm == 0.0:
			_p.teleport_to(_spot)
			_p.camera_rig.reset_view(_yaw, -0.06)
		_warm += delta
		RenderingServer.render_loop_enabled = false
		return false
	var id := _ids[_i]
	if _phase == 0:
		RenderingServer.render_loop_enabled = false
		_render_on = false
		_stage()
		_phase = 1
		return false
	var moments: Array = MOMENTS.get(id, [0.15, 0.5, 1.0, 2.0])
	if not _fired:
		_fired = true
		_fire(id)
	_t += delta
	if id == &"sv_grab" and not _released and _t > 1.2:
		_released = true
		Input.action_release(&"fire")
	if id == &"sv_yank" or id == &"sb_burrow":
		if _car != null and is_instance_valid(_car) and _t < 0.1:
			_p.camera_rig.aim_at(_car.global_position + Vector3(0.0, 0.7, 0.0))
	if id == &"sv_lash" and _lash_n < 3 and _t > 0.34 * float(_lash_n + 1):
		_lash_n += 1
		_war.verbs._lash_cd = 0.0
		_war.verbs._lash(false, true)
	_p.camera_rig.aim_at(_spot + _dir() * (_dist * 0.8) + Vector3(0.0, 1.3, 0.0))
	for f in _foes:
		if is_instance_valid(f):
			f.hp = f.max_hp
			f.set(&"_hit_k", 0.0)
			if f.humanoid_body != null:
				f.humanoid_body.set_instance_shader_parameter(&"hit_k", 0.0)
	if _shots < moments.size():
		var due := maxf(float(moments[_shots]), delta * 2.0 + 0.01)
		var next_frame := due - delta * 2.5
		if _t >= next_frame and not _render_on:
			RenderingServer.render_loop_enabled = true
			_render_on = true
		if _t >= due and _render_on:
			var img := _p.get_viewport().get_texture().get_image()
			img.save_png("%s/%s_m%d.png" % [_out, id, _shots])
			var sw := SnakeSwarm.current
			print("BOTSW ", id, " m", _shots, " t=", snappedf(_t, 0.01), " bodies ", sw.count() if sw != null else -1, " tendrils ", SnakeTendrilPool.current.count() if SnakeTendrilPool.current != null else -1,
				" holds ", _war.holds.count(), " casts ", _war.casts, " hero ", _p.global_position, " foes ", _foes.map(func(f: Drone) -> Vector3: return f.global_position if is_instance_valid(f) else Vector3.ZERO))
			_shots += 1
			RenderingServer.render_loop_enabled = false
			_render_on = false
	if _shots >= moments.size():
		_phase = 0
		_i += 1
	return false
