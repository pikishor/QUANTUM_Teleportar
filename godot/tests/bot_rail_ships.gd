extends RefCounted
## Look-dev bot for the railways and ships (tools/bot.sh res://tests/bot_rail_ships.gd OUT EVERY COUNT, QUALITY=0|1|2, BOT_RES=2400x1080).
## env: RS_VIEWS = semicolon list, one per shot slot; a view is
##   "c:px,py,pz,tx,ty,tz"                      free camera at p looking at t (metres)
##   "r:route:u:dist:h:ang"                     a camera beside route `route` at metres u: dist away, h above the bed, ang degrees round the track (0 = behind it, 90 = right side, 180 = ahead)
##   "t:route:kind:car:dist:h:ang"              the same, round the middle of car `car` of that train (clock as set)
##   "ride:route:kind:car:lx,ly,lz:yaw"         the hero on the train: local car position, camera yaw (radians) (real game camera)
##   "hero:x,y,z:yaw"                           the hero at x,y,z with the real camera (y < -50: on the terrain)
##   "ship:id:dist:h:ang"                       a camera round a ship of ShipWorld (when it exists)
##   a view may end with "@clock" (seconds on the timetable)
## RS_FRAMES = frames per view (default 10); RS_HOUR = hour of day; RS_NORAIN=1.
var _views: Array[String] = []
var _i := 0
var _f := 0
var _applied := -1


func _init() -> void:
	for s in OS.get_environment("RS_VIEWS").split(";", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	var wait := int(OS.get_environment("RS_FRAMES")) if OS.get_environment("RS_FRAMES") != "" else 10
	if _f == 2:
		Game.state = &"play"
		if OS.get_environment("RS_HOUR") != "" and is_instance_valid(Game.world):
			(Game.world as City).day_night.set_hour(float(OS.get_environment("RS_HOUR")))
		if OS.get_environment("RS_NORAIN") != "0" and is_instance_valid(Game.atmosphere):
			(Game.atmosphere as Atmosphere).set_weather(0.0, 0.15)
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
	if _f >= 3 and _i < _views.size():
		if _applied != _i:
			_applied = _i
			_apply(p, _views[_i])
		else:
			_hold(p, _views[_i])
	_f += 1
	if _f >= 3 + wait:
		_f = 3
		_i += 1
	return _i >= _views.size()


func _hold(p: Player, v: String) -> void:
	if v.begins_with("c:") or v.begins_with("ride:") or v.begins_with("t:") or v.begins_with("r:") or v.begins_with("ship:"):
		_apply_cam(p, v, false)


func _apply(p: Player, v: String) -> void:
	var rw := RailWorld.instance
	if v.contains("@") and rw != null:
		var parts := v.split("@")
		v = parts[0]
		rw.set_clock(float(parts[1]))
	_apply_cam(p, v, true)


func _ground(x: float, z: float) -> float:
	return TerrainHeight.height_at(x, z)


func _apply_cam(p: Player, v: String, first: bool) -> void:
	if v.contains("@"):
		v = v.split("@")[0]
	var rw := RailWorld.instance
	var a := v.split(":")
	match a[0]:
		"c":
			var q := a[1].split(",")
			var pos := Vector3(float(q[0]), float(q[1]), float(q[2]))
			var tgt := Vector3(float(q[3]), float(q[4]), float(q[5]))
			_place_hero(p, pos, first)
			p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos).looking_at(tgt, Vector3.UP), 70.0)
		"r":
			var r := RailNet.route(StringName(a[1]))
			var pa := RailNet.point_at(r, float(a[2]))
			var t: Vector3 = Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
			var off := (-t).rotated(Vector3.UP, -deg_to_rad(float(a[5]))) * float(a[3])
			var tgt: Vector3 = (pa[0] as Vector3) + Vector3(0.0, 2.0, 0.0)
			var pos := tgt + off + Vector3(0.0, float(a[4]), 0.0)
			_place_hero(p, pos, first)
			p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos).looking_at(tgt, Vector3.UP), 70.0)
		"t":
			var tr := rw.train(StringName(a[1]), StringName(a[2])) if rw != null else null
			if tr == null:
				return
			var xf := tr.car_xf(int(a[3]))
			var t := -xf.basis.z
			t.y = 0.0
			t = t.normalized()
			var off2 := (-t).rotated(Vector3.UP, -deg_to_rad(float(a[6]))) * float(a[4])
			var tgt2 := xf.origin + Vector3(0.0, 2.0, 0.0)
			var pos2 := tgt2 + off2 + Vector3(0.0, float(a[5]), 0.0)
			_place_hero(p, pos2, first)
			p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos2).looking_at(tgt2, Vector3.UP), 70.0)
		"ride":
			var tr2 := rw.train(StringName(a[1]), StringName(a[2])) if rw != null else null
			if tr2 == null:
				return
			var lq := a[4].split(",")
			var xf2 := tr2.car_xf(int(a[3]))
			if first:
				p.global_position = xf2 * Vector3(float(lq[0]), float(lq[1]), float(lq[2]))
				p.velocity = Vector3.ZERO
				p.camera_rig.cine_clear()
			p.camera_rig.yaw = float(a[5])
		"hero":
			var q2 := a[1].split(",")
			var y := float(q2[1])
			if y < -50.0:
				y = _ground(float(q2[0]), float(q2[2])) + 1.0
			if first:
				p.global_position = Vector3(float(q2[0]), y, float(q2[2]))
				p.velocity = Vector3.ZERO
				p.camera_rig.cine_clear()
				if rw != null:
					rw.ensure_near(p.global_position, 500.0)
			p.camera_rig.yaw = float(a[2])
		"ship":
			var sw := ShipWorld.instance
			if sw == null or not sw.has_method(&"ship_node"):
				return
			var sh: Node3D = sw.call(&"ship_node", StringName(a[1]))
			if sh == null:
				return
			var t3 := -sh.global_transform.basis.z
			t3.y = 0.0
			t3 = t3.normalized()
			var off3 := (-t3).rotated(Vector3.UP, -deg_to_rad(float(a[4]))) * float(a[2])
			var tgt3 := sh.global_position + Vector3(0.0, 8.0, 0.0)
			var pos3 := tgt3 + off3 + Vector3(0.0, float(a[3]), 0.0)
			_place_hero(p, pos3, first)
			p.camera_rig.cine_set(Transform3D(Basis.IDENTITY, pos3).looking_at(tgt3, Vector3.UP), 70.0)


func _place_hero(p: Player, pos: Vector3, first: bool) -> void:
	if not first:
		return
	var y := maxf(_ground(pos.x, pos.z) + 1.0, TerrainHeight.SEA_LEVEL + 3.0) if (absf(pos.x) > 1100.0 or absf(pos.z) > 1100.0) else 0.0
	p.global_position = Vector3(pos.x, y, pos.z)
	p.velocity = Vector3.ZERO
	var rw := RailWorld.instance
	if rw != null:
		rw.ensure_near(pos, 450.0)
	var sw := ShipWorld.instance
	if sw != null and sw.has_method(&"ensure_near"):
		sw.call(&"ensure_near", pos)
