extends RefCounted
## Look-dev bot of the blast arsenal (wave 113): the real game, the real camera behind the hero, blasts of the table at three distances (BX_DIST, default 6,14,28 m ahead of the hero), three frames each
## (BX_MOMENTS seconds after the trigger: the flash, the fireball and the smoke), saved as <BX_OUT>/<id>_d<dist>_m<k>.png. Three enemies (they cannot die) and a parked car stand near the blast so the
## shove, the lift and the cover can be seen. The renderer only runs for the frames that are saved (RenderingServer.render_loop_enabled), so a sweep of 45 blasts takes minutes, not an hour.
##   BX_OUT=/tmp/x BX_IDS=gr_frag,la_rocket BX_DIST=6,14,28 BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_blast_arsenal.gd /tmp/x/seq 100000 1
## BX_CAR=0 leaves the car out, BX_FOES=0 the enemies, BX_ALT=1 uses BlastOps.cast / strikes through their real delivery where the id has one.

const DEFAULT_IDS := "gr_frag,la_rocket,la_plasma,gr_spark,gr_blinder,gr_fog,gr_well,gr_ember,la_thermo,st_orbital,gr_still,ord_depth_charge,gr_arc,wb_gas_tank,st_air_l"
## id -> the seconds after the trigger that are saved (default [0.12, 0.45, 1.3])
const MOMENTS := {
	&"gr_well": [0.8, 2.12, 2.4], &"gr_fog": [0.3, 1.6, 4.0], &"gr_ember": [0.2, 0.9, 3.2], &"gr_still": [0.3, 1.5, 3.0], &"gr_blinder": [0.08, 0.4, 1.2], &"gr_spark": [0.1, 0.4, 1.0],
	&"st_orbital": [0.15, 0.5, 1.5], &"wb_gas_tank": [0.15, 0.6, 2.0], &"st_air_l": [0.15, 0.55, 1.6], &"la_thermo": [0.1, 0.4, 1.4], &"ult_meteor": [1.2, 2.15, 3.2],
	&"ult_blackhole": [1.8, 5.2, 5.9], &"ult_mega": [0.12, 0.5, 1.4], &"ult_freeze": [0.3, 1.5, 3.0],
}

var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _spot := Vector3.ZERO
var _yaw := 0.0
var _ids: Array[StringName] = []
var _dists: Array[float] = []
var _i := 0
var _d := 0
var _t := 0.0
var _phase := 0                       ## 0 = place and trigger, 1 = run the clock and save
var _shots := 0
var _out := ""
var _foes: Array[Drone] = []
var _car: Vehicle
var _render_on := true
var _fired := false
var _warm := 0.0                      ## seconds of play before the first stage: the first teleport fades in from black and would darken the first frames


func _init() -> void:
	_out = OS.get_environment("BX_OUT")
	var s := OS.get_environment("BX_IDS")
	for n in (s if s != "" else DEFAULT_IDS).split(",", false):
		_ids.append(StringName(n))
	var ds := OS.get_environment("BX_DIST")
	for n in (ds if ds != "" else "6,14,28").split(",", false):
		_dists.append(float(n))


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
	if not _lane():
		print("BOTBX no open lane found")
		return
	DirAccess.make_dir_recursive_absolute(_out)
	WeaponDefs.hero_mode = true
	print("BOTBX lane at ", _spot, " yaw ", _yaw, " ids ", _ids, " dists ", _dists)


func _stage(dist: float) -> void:
	BlastOps.shared(_p.get_tree()).reset()
	BlastFx.shared().reset()
	if FX.marks != null:
		FX.marks.clear()                                                  # each blast shows its own scorch, not the one of the stage before
	_mgr.clear()
	_foes.clear()
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.06)
	var at := _spot + _dir() * dist
	if OS.get_environment("BX_FOES") != "0":
		for k in 3:
			var pos := at + _right() * (float(k - 1) * 2.7) + _dir() * (float(k % 2) * 2.6 - 1.0)
			pos.y = _spot.y
			var f := _mgr.spawn(&"operative", pos, false)
			if f != null:
				f.set_physics_process(false)
				f.global_position = pos
				f.max_hp = 1.0e6
				f.hp = 1.0e6
				f.rotation.y = _yaw + PI
				_foes.append(f)
	if OS.get_environment("BX_CAR") != "0":
		var vm := Game.vehicles as VehicleManager
		if vm != null:
			vm._reset_all()                                                   # the car of the last stage is a wreck or a husk: every stage gets a fresh one
			_car = vm.spawn_parked(&"sedan", at + _right() * 7.5 + _dir() * 1.5, _yaw + PI * 0.5)
			if _car != null:
				_car.hp = _car.max_hp
				_car.visual.repair()
				_car.visual.set_damage_look(0.0)                                  # the pool keeps the burnt look of the car's last life: put the clean paint back
				_car.visual.set_deform(0.0)
				_car.visual.set_condition(0.0)
	_t = 0.0
	_shots = 0
	_fired = false


func _fire(id: StringName, dist: float) -> void:
	var at := _spot + _dir() * dist + Vector3(0.0, 0.25, 0.0)
	var src := _p
	var e := BlastTable.entry(id)
	var ops := BlastOps.shared(_p.get_tree())
	if StringName(e["cat"]) == &"ultimate":
		ops.cast(id, src, true)
	elif id == &"st_orbital" or id == &"st_air_l" or id == &"st_artillery":
		BlastFx.shared().beacon_tick(at, float(e["radius"]), BlastElements.color(StringName(e["element"]), "ring"), 0.3)
		BlastTable.apply(id, at, src, {})
	elif id == &"wb_gas_tank" or id == &"wb_fuel_truck" or id == &"wb_barrel":
		WorldBlasters.spawn(id, at - Vector3(0.0, 0.25, 0.0), _yaw)
		WorldBlasters.current.hit_at(at, 99.0)
	else:
		BlastTable.apply(id, at, src, {})


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
		print("BOTBX done")
		_p.get_tree().quit()                                              # tools/bot.sh always passes --shot-seq, which keeps the game running: end it here
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
	var dist := _dists[_d]
	if _phase == 0:
		RenderingServer.render_loop_enabled = false
		_render_on = false
		_stage(dist)
		_phase = 1
		return false
	var moments: Array = MOMENTS.get(id, [0.12, 0.45, 1.3])
	if not _fired:
		_fired = true
		_fire(id, dist)
	_t += delta
	var at := _spot + _dir() * dist
	_p.camera_rig.aim_at(at + Vector3(0.0, 1.2, 0.0))
	for f in _foes:
		if is_instance_valid(f):
			f.hp = f.max_hp
			f.set(&"_hit_k", 0.0)                                             # their physics process is off here, so the white-hot hit flash would never fade
			if f.humanoid_body != null:
				f.humanoid_body.set_instance_shader_parameter(&"hit_k", 0.0)
	if _shots < moments.size():
		var due := float(moments[_shots])
		var next_frame := due - delta * 2.5
		if _t >= next_frame and not _render_on:
			RenderingServer.render_loop_enabled = true
			_render_on = true
		if _t >= due and _render_on:
			var img := _p.get_viewport().get_texture().get_image()
			var path := "%s/%s_d%d_m%d.png" % [_out, id, int(dist), _shots]
			img.save_png(path)
			print("BOTBX ", id, " d", int(dist), " m", _shots, " t=", snappedf(_t, 0.01), " puffs ", BlastFx.shared().cloud_live(), " slots ", FX.explosions.active_count())
			_shots += 1
			RenderingServer.render_loop_enabled = false
			_render_on = false
	if _shots >= moments.size():
		_phase = 0
		_d += 1
		if _d >= _dists.size():
			_d = 0
			_i += 1
	return false
