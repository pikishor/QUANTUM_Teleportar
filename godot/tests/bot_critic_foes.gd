extends RefCounted
## Look-dev bot of the wave 113 critic (lens LOOK): rows of roster enemies lined up in a street in front of the hero, seen from the REAL game camera, at several distances.
##   FL_OUT=/tmp/x FL_ROWS="merc_rifle,merc_shotgun;vael_grunt,vael_jackal" FL_DIST=15,40,80 [FL_HOUR=12] [FL_SPOT="x,z,yaw"] [FL_HURT=0.4] [FL_AGGRO=0]
##   BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_critic_foes.gd /tmp/x/seq 100000 1
## One image per row and distance: <FL_OUT>/row<r>_d<dist>.png. Figures are held on their spots (the AI is off) so a row stays a row; the camera is the hero's own (reset_view behind him).
## An id `op` (or `op:look`) is a classic operative of the EnemyManager (the hero shader), every other id a roster foe of the AlienWorld (human kit, alien, walker).
## SEQUENCE: FL_SEQ="id[,id...]" lines the ids up at FL_DIST[0] metres, FL_STATUS="burn|freeze|shock|dissolve" is applied through the damage system after 1.2 s, FL_KILL="plain|blast"
##   kills them FL_KILL_AT seconds after that, and a frame is saved at each FL_SEQ_T second (default 0.2,0.6,1.2,2.0,3.2) after the status (or the kill when there is no status): <FL_OUT>/seq_<k>.png.

var _setup_done := false
var _p: Player
var _w: AlienWorld
var _spot := Vector3.ZERO
var _yaw := 0.0
var _rows: Array = []
var _dists: Array[float] = []
var _ri := 0
var _di := 0
var _phase := 0
var _t := 0.0
var _warm := 0.0
var _out := ""
var _foes: Array = []
var _held: Array = []
var _render_on := true
var _seq: Array[StringName] = []
var _seq_times: Array[float] = []
var _seq_k := 0
var _status := ""
var _kill := ""
var _kill_at := 99.0
var _stat_done := false
var _kill_done := false
var _hurt := 0.0
var _aggro := false


func _init() -> void:
	_out = OS.get_environment("FL_OUT")
	var rows := OS.get_environment("FL_ROWS")
	if rows == "":
		rows = "merc_rifle,merc_shotgun,merc_rocket,merc_medic,merc_officer,merc_sniper;auth_rifle,auth_riot,auth_heavy,auth_breacher,auth_ghost,auth_drone,auth_engineer;vael_grunt,vael_jackal,vael_brute,vael_hunter,vael_elite,vael_stalker,vael_bloater;grid_walker,grid_heavy"
	for r in rows.split(";", false):
		var ids: Array[StringName] = []
		for n in r.split(",", false):
			ids.append(StringName(n))
		_rows.append(ids)
	var ds := OS.get_environment("FL_DIST")
	for n in (ds if ds != "" else "15,40,80").split(",", false):
		_dists.append(float(n))
	_hurt = float(OS.get_environment("FL_HURT")) if OS.get_environment("FL_HURT") != "" else 0.0
	_aggro = OS.get_environment("FL_AGGRO") == "1"
	var sq := OS.get_environment("FL_SEQ")
	if sq != "":
		for n in sq.split(",", false):
			_seq.append(StringName(n))
		var ts := OS.get_environment("FL_SEQ_T")
		for n in (ts if ts != "" else "0.2,0.6,1.2,2.0,3.2").split(",", false):
			_seq_times.append(float(n))
		_status = OS.get_environment("FL_STATUS")
		_kill = OS.get_environment("FL_KILL")
		if OS.get_environment("FL_KILL_AT") != "":
			_kill_at = float(OS.get_environment("FL_KILL_AT"))
		elif _kill != "":
			_kill_at = 0.9


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _lane(need: float) -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	var best := 0.0
	for tries in 900:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var open := 0.0
			for off in [-3.0, 0.0, 3.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * (need + 6.0), Game.L_WORLD | Game.L_VEHICLE)
				var hit := space.intersect_ray(q)
				var d := (need + 6.0) if hit.is_empty() else a.distance_to(hit["position"])
				open = d if off == -3.0 else minf(open, d)
			if open > best:
				best = open
				_spot = rp
				_yaw = yaw
		if best >= need + 6.0:
			return true
	print("BOTFL best lane ", snappedf(best, 0.1), " m (wanted ", need + 6.0, ")")
	return best > 40.0


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_w = AlienWorld.instance
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	(Game.enemies as EnemyManager).clear()
	(Game.enemies as EnemyManager).patrol_groups().clear()
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	if Encounters.current != null:
		Encounters.current.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	if city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(float(OS.get_environment("FL_HOUR")) if OS.get_environment("FL_HOUR") != "" else 12.0)
	var forced := OS.get_environment("FL_SPOT")
	if forced != "":
		var fp := forced.split(",")
		_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
		_yaw = float(fp[2])
	else:
		var need := 0.0
		for d in _dists:
			need = maxf(need, d)
		if not _lane(need):
			print("BOTFL no lane")
			return
	_w.force_active = true
	_w.ambient_enabled = false
	DirAccess.make_dir_recursive_absolute(_out)
	print("BOTFL spot ", _spot, " yaw ", _yaw, " rows ", _rows.size(), " dists ", _dists)


func _stage(ids: Array, dist: float) -> void:
	_w.clear_all()
	(Game.enemies as EnemyManager).clear()
	_foes.clear()
	_held.clear()
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.06)
	var n := ids.size()
	var sp := dist * 0.2 if n > 1 else 0.0
	if _seq.size() > 0:
		sp = 2.4
	for i in n:
		var lat := (float(i) - float(n - 1) * 0.5) * sp
		var at := _spot + _dir() * dist + _right() * lat
		at.y = _spot.y
		var sid := String(ids[i])
		if sid.begins_with("op"):
			var look := int(sid.substr(3)) if sid.length() > 3 else -1
			var mgr := Game.enemies as EnemyManager
			var f: Drone = mgr.spawn(&"operative", at, _aggro, false, &"", look)
			if f != null:
				f.set_physics_process(false)
				f.global_position = at
				f.rotation.y = _yaw + PI
				if _hurt > 0.0:
					f.hp = f.max_hp * (1.0 - _hurt)
				_foes.append(f)
				_held.append(at)
			continue
		var made: Array[AlienCreature] = _w.spawn_group(StringName(sid), at, 1, &"", 0.0, _aggro)
		for c in made:
			c.global_position = at
			if _hurt > 0.0:
				c.hp = c.max_hp * (1.0 - _hurt)
			_foes.append(c)
			_held.append(at)
	print("BOTFL staged ", n, " at ", dist, " m: ", ids)


func _hold() -> void:
	for i in _foes.size():
		var c := _foes[i] as Node3D
		if is_instance_valid(c) and not bool(c.get(&"dead")):
			c.global_position = _held[i]


func _kill_one(c: Node3D, how: String) -> void:
	match how:
		"blast":
			Game.explode(c.global_position + _dir() * 1.2, 5.0, {"blast": &"gr_frag", "source": _p})
		_:
			if c.has_method(&"damage"):
				c.call(&"damage", float(c.get(&"max_hp")) * 3.0)


func _apply_status(c: Node3D, kind: String) -> void:
	var dw := DamageWorld.current
	if dw == null:
		print("BOTFL no DamageWorld")
		return
	dw.foes.set_status(c, StringName(kind), 6.0)


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null or AlienWorld.instance == null:
		return false
	if not _setup_done:
		_setup()
		if _spot == Vector3.ZERO:
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
	if _seq.size() > 0:
		return _step_seq(delta)
	if _ri >= _rows.size():
		RenderingServer.render_loop_enabled = true
		print("BOTFL done")
		_p.get_tree().quit()
		return true
	if _phase == 0:
		RenderingServer.render_loop_enabled = false
		_render_on = false
		_stage(_rows[_ri], _dists[_di])
		_t = 0.0
		_phase = 1
		return false
	_t += delta
	_hold()
	_p.camera_rig.aim_at(_spot + _dir() * _dists[_di] + Vector3(0.0, 1.0, 0.0))
	if _t >= 1.4 and not _render_on:
		RenderingServer.render_loop_enabled = true
		_render_on = true
	if _t >= 1.8 and _render_on:
		var live := 0
		var shown := 0
		for c in _foes:
			if is_instance_valid(c):
				live += 1
				if (c as Node3D).is_visible_in_tree():
					shown += 1
		for c in _foes:
			var rf := c as RosterFoe
			if rf != null and is_instance_valid(rf) and not rf.hum.is_empty():
				var hb := rf.humanoid_body
				print("BOTFL   ", rf.id, " d ", snappedf(rf.flat_dist(), 0.1), " lod ", rf.hum.get("lod", -1), " far_k ", (hb.get_instance_shader_parameter(&"far_k") if hb != null else "-"), " tris ", (FoeHuman.tris(hb.mesh) if hb != null and hb.mesh != null else -1))
		print("BOTFL census live ", live, "/", _foes.size(), " visible ", shown)
		var img := _p.get_viewport().get_texture().get_image()
		var path := "%s/row%d_d%d.png" % [_out, _ri, int(_dists[_di])]
		img.save_png(path)
		print("BOTFL saved ", path)
		RenderingServer.render_loop_enabled = false
		_render_on = false
		_phase = 0
		_di += 1
		if _di >= _dists.size():
			_di = 0
			_ri += 1
	return false


func _step_seq(delta: float) -> bool:
	if _phase == 0:
		RenderingServer.render_loop_enabled = false
		_render_on = false
		_stage(_seq, _dists[0])
		_t = 0.0
		_phase = 1
		_stat_done = false
		_kill_done = false
		_seq_k = 0
		return false
	_t += delta
	_p.camera_rig.aim_at(_spot + _dir() * _dists[0] + Vector3(0.0, 1.0, 0.0))
	var t0 := 1.2                                                             # the status (or the kill) happens at this moment, the frames are timed from it
	if not _stat_done:
		_hold()
		if _t >= t0:
			_stat_done = true
			_t = 0.0
			for c in _foes:
				if is_instance_valid(c):
					if _status != "":
						_apply_status(c as Node3D, _status)
					elif _kill != "":
						_kill_one(c as Node3D, _kill)
						_kill_done = true
		return false
	if not _kill_done and _kill != "" and _t >= _kill_at:
		_kill_done = true
		for c in _foes:
			if is_instance_valid(c):
				_kill_one(c as Node3D, _kill)
	elif not _kill_done:
		_hold()
	if _seq_k < _seq_times.size():
		var due := maxf(_seq_times[_seq_k], delta * 2.0 + 0.01)
		if _t >= due - delta * 2.5 and not _render_on:
			RenderingServer.render_loop_enabled = true
			_render_on = true
		if _t >= due and _render_on:
			var img := _p.get_viewport().get_texture().get_image()
			img.save_png("%s/seq_%d.png" % [_out, _seq_k])
			print("BOTFL seq ", _seq_k, " t=", snappedf(_t, 0.01))
			_seq_k += 1
			RenderingServer.render_loop_enabled = false
			_render_on = false
	if _seq_k >= _seq_times.size():
		RenderingServer.render_loop_enabled = true
		print("BOTFL done")
		_p.get_tree().quit()
		return true
	return false
