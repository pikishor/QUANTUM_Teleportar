extends RefCounted
## Look-dev bot of the wave 113 play critic: the hit feedback of a blast on the real phone HUD. The hero throws a FRAG POP (the real weapon path) at three enemies 14 m ahead; frames at +0.08 s, +0.25 s and +0.6 s.
## QT_CREDIT=0 switches the new credit off (the "before" frames: no X, no kill ring, no numbers). BOT_USER_ARGS="--touch" BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" FB_OUT=/tmp/fb
##   tools/bot.sh res://tests/bot_w113_feedback.gd /tmp/fb/seq 100000 1
const MOMENTS: Array[float] = [0.09, 0.26, 0.6]

var _p: Player
var _mgr: EnemyManager
var _spot := Vector3.ZERO
var _yaw := 0.0
var _setup_done := false
var _warm := 0.0
var _t := 0.0
var _fired := false
var _armed := false
var _shots := 0
var _out := ""
var _foes: Array[Drone] = []


func _init() -> void:
	_out = OS.get_environment("FB_OUT")


func _lane() -> bool:
	var city := Game.world as City
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


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup_done = true
		_p = Game.player as Player
		_mgr = Game.enemies as EnemyManager
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		_mgr.patrol_groups().clear()
		_mgr.clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		Game.missions.contracts.enabled = false
		_p.max_hp = 1.0e6
		_p.hp = 1.0e6
		TestMode.god = true
		var forced := OS.get_environment("BX_SPOT")
		if forced != "":
			var fp := forced.split(",")
			_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
			_yaw = float(fp[2])
		elif not _lane():
			print("BOTFB no lane")
			return true
		DirAccess.make_dir_recursive_absolute(_out)
		WeaponDefs.hero_mode = true
		print("BOTFB lane ", _spot, " yaw ", _yaw, " credit ", BlastCredit.enabled)
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 2.5:
		if _warm == 0.0:
			_p.teleport_to(_spot)
			_p.camera_rig.reset_view(_yaw, -0.06)
		_warm += delta
		return false
	if not _fired:
		_fired = true
		_mgr.clear()
		_p.teleport_to(_spot)
		_p.camera_rig.reset_view(_yaw, -0.06)
		var at := _spot + _dir() * 14.0
		for k in 3:
			var pos := at + _right() * (float(k - 1) * 2.6) + _dir() * (float(k % 2) * 2.0 - 1.0)
			pos.y = _spot.y
			var f := _mgr.spawn(&"operative", pos, false)
			if f != null:
				f.set_physics_process(false)
				f.global_position = pos
				f.max_hp = 60.0
				f.hp = 60.0
				f.rotation.y = _yaw + PI
				_foes.append(f)
		var w := _p.weapon
		WeaponDefs.unlock(&"gr_frag")
		w.switch_to(&"gr_frag", true)
		w.ammo = w.mag
		w.reserve = 9
		BlastTable.apply(&"gr_frag", at + Vector3(0.0, 0.25, 0.0), _p, {})
		_t = 0.0
		return false
	_t += delta
	_p.camera_rig.aim_at(_spot + _dir() * 14.0 + Vector3(0.0, 1.2, 0.0))
	if _shots < MOMENTS.size():
		var due := maxf(MOMENTS[_shots], delta * 1.9)
		if _armed:                                                            # the frame that was drawn after the clock was set is the one that is read now
			_armed = false
			var img := _p.get_viewport().get_texture().get_image()
			var path := "%s/fb_m%d.png" % [_out, _shots]
			img.save_png(path)
			print("BOTFB m", _shots, " t=", snappedf(_t, 0.01), " last_hit_age ", snappedf(PlayerUtil.now() - _p.last_hit_time, 0.01), " kill ", _p.last_hit_kill)
			_shots += 1
		elif _t >= due - delta:
			_armed = true
			if _p.last_hit_time > 0.0:
				_p.last_hit_time = PlayerUtil.now() - due                       # the HUD marker lives in wall-clock seconds and the software renderer takes half a second a frame: show the frame as it looks on a phone
	if _shots >= MOMENTS.size():
		WeaponDefs.hero_mode = false
		_p.get_tree().quit()
		return true
	return false
