class_name Specialist
extends Operative
## The four specialist Vael troops (cfg "role"), all on the operative's rig and model with a tint (cfg color) and a scale (cfg scale): no new model, EnemyMarks for every telegraph.
##   shield   a frontal energy shield (cfg shield_hp, a translucent plate: ONE extra draw while it is up). shield_blocks(from) is true for shots from the front arc (60 degrees
##            either side of where he faces): PlayerWeapon sends those to shield_hit() (no damage) for the carbine and the scatter; the Pulse Lance and the grenade call break_shield().
##            He turns slowly (2.2 rad/s), so a strafing player gets behind him. Unshielded he is faster and panics. Explosions damage him directly (Game.explode).
##   flanker  fast (8.2 m/s), circles the target at about 11 m and darts in and out, fires two-round bursts after a 0.22 s windup.
##   sniper   holds 35 m+ (backs away when pressed), uses cover, and shoots a hard round (30 damage) after a 0.8 s laser-sight telegraph (EnemyMarks aim line + muzzle charge);
##            the aim point locks 0.25 s before the shot, so moving in the last quarter second dodges it.
##   brute    380 hp, charges in a straight line after a 0.4 s roar and slams the ground (a shock ring through Game.explode, radius 4 m) when within 3.4 m after a 0.55 s windup.

const SHIELD_ARC := 0.5                     ## cos of the half angle of the shield (60 degrees)
const SNIPER_LOCK := 0.25
const SLAM_WIND := 0.55
const ROAR_TIME := 0.4
const SLAM_RADIUS := 4.0

var role: StringName = &""
var shield_hp := 0.0
var shield_max := 0.0
var shield_node: MeshInstance3D

var _shield_flash := 0.0
var _locked := false
var _lock_point := Vector3.ZERO
var _slam_wind := 0.0
var _slam_cd := 0.0
var _roar_t := 0.0
var _charging := false
var _charge_t := 0.0
var _charge_cd := 0.0
var _charge_dir := Vector2.ZERO
var _orbit_t := 0.0
var _dash := 0.0
var _slams := 0


func setup(t: StringName) -> void:
	super.setup(t)
	role = cfg.get("role", &"")
	if role == &"shield":
		_build_shield()


func _on_activate() -> void:
	super._on_activate()
	shield_max = float(cfg.get("shield_hp", 0.0))
	shield_hp = shield_max
	_shield_flash = 0.0
	_locked = false
	_slam_wind = 0.0
	_slam_cd = 1.0
	_roar_t = 0.0
	_charging = false
	_charge_cd = randf_range(1.0, 2.5)
	_orbit_t = 0.0
	_dash = 0.0
	if shield_node != null:
		shield_node.visible = shield_hp > 0.0


func _build_shield() -> void:
	shield_node = MeshInstance3D.new()
	shield_node.name = "Shield"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 1.75, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.3, 0.85, 1.0, 0.28)
	bm.material = mat
	shield_node.mesh = bm
	shield_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield_node.position = Vector3(0.0, 1.05 * _base_scale, -0.95 * _base_scale)
	add_child(shield_node)


# --- the shield ------------------------------------------------------------------------------------------------------

## Does a shot from `from` hit the shield? (a shield up, the shooter inside the frontal arc)
func shield_blocks(from: Vector3) -> bool:
	if shield_hp <= 0.0 or dead:
		return false
	var to := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	if to.length() < 0.1:
		return true
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return fwd.dot(to.normalized()) > SHIELD_ARC


## The shield takes the hit: sparks, a flash, and it breaks at zero.
func shield_hit(amount: float, at: Vector3) -> void:
	if shield_hp <= 0.0:
		return
	shield_hp -= amount
	_shield_flash = 0.12
	aware = true
	_bar_t = BAR_SECONDS
	_burst(at, Color(0.4, 0.9, 1.0), 4, 4.0, 0.2, 2.0)
	Sfx.play_at(&"hit", at, -4.0, 1.6)
	if shield_hp <= 0.0:
		break_shield()


func break_shield() -> void:
	if shield_hp <= 0.0 and (shield_node == null or not shield_node.visible):
		return
	var was := shield_hp > 0.0
	shield_hp = 0.0
	if shield_node != null:
		shield_node.visible = false
	if was and role == &"shield":
		_burst(center() + Vector3(0.0, 0.0, 0.0), Color(0.4, 0.9, 1.0), 14, 6.0, 0.4, 3.0, 1.6)
		_stagger = 0.4
		Sfx.play_at(&"boom", center(), -8.0, 1.8)


func _turn_rate() -> float:
	if role == &"shield" and shield_hp > 0.0:
		return 2.2
	if role == &"brute" and (_charging or _slam_wind > 0.0):
		return 0.5
	return 8.0


func _animate(delta: float) -> void:
	super._animate(delta)
	if shield_node != null and shield_node.visible:
		_shield_flash = maxf(0.0, _shield_flash - delta)
		var m := (shield_node.mesh as BoxMesh).material as StandardMaterial3D
		m.albedo_color.a = 0.28 + 0.5 * clampf(_shield_flash / 0.12, 0.0, 1.0) + 0.05 * sin(_clock * 6.0)


# --- movement and attacks per role -------------------------------------------------------------------------------------

func _move_aware(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	match role:
		&"shield":
			var k := 1.0 if shield_hp > 0.0 else 1.35
			if d > rng * 0.55:
				_mx = ux
				_mz = uz
				_speed = speed * k
			elif d < rng * 0.25:
				_mx = -ux
				_mz = -uz
				_speed = speed * 0.5
			else:
				super._move_aware(delta, ux, uz, d, speed * k, rng)
		&"flanker":
			_move_flanker(delta, ux, uz, d, speed)
		&"sniper":
			if d < 24.0:
				_mx = -ux                                          # too close: back off and keep the lane
				_mz = -uz
				_speed = speed * 1.1
			elif d > rng * 0.9 or (not los and _no_los > 2.0):
				_mx = ux
				_mz = uz
				_speed = speed
			else:
				super._move_aware(delta, ux, uz, d, speed, rng)
				if _cover_state == 0:
					_speed *= 0.2
		&"brute":
			_move_brute(delta, ux, uz, d, speed)
		_:
			super._move_aware(delta, ux, uz, d, speed, rng)


func _move_flanker(delta: float, ux: float, uz: float, d: float, speed: float) -> void:
	_orbit_t -= delta
	if _orbit_t <= 0.0:
		_orbit_t = randf_range(1.2, 2.4)
		_flank = -_flank if randf() < 0.45 else _flank
		_dash = 0.6 if randf() < 0.35 else 0.0
	var want := 11.0
	var radial := clampf((d - want) / 6.0, -1.0, 1.0)         # + closes in, - opens up
	if _dash > 0.0:
		_dash -= delta
		radial = 1.0
	var tx := -uz * _flank
	var tz := ux * _flank
	var m := Vector2(tx + ux * radial, tz + uz * radial).normalized()
	_mx = m.x
	_mz = m.y
	_speed = speed * (0.85 if _burst_left == 0 else 0.5)


func _move_brute(delta: float, ux: float, uz: float, d: float, speed: float) -> void:
	_slam_cd = maxf(0.0, _slam_cd - delta)
	_charge_cd = maxf(0.0, _charge_cd - delta)
	if _slam_wind > 0.0:
		_speed = 0.0
		_slam_wind -= delta
		if _slam_wind <= 0.0:
			_slam()
		return
	if _roar_t > 0.0:
		_speed = 0.0
		_roar_t -= delta
		if _roar_t <= 0.0:
			_charging = true
			_charge_t = clampf(d / 10.0 + 0.5, 0.8, 2.4)
			_charge_dir = Vector2(ux, uz)                      # locked at the start of the charge: a sidestep dodges it
		return
	if _charging:
		_charge_t -= delta
		_mx = _charge_dir.x
		_mz = _charge_dir.y
		_speed = speed * 1.9
		if d < 3.0 or _charge_t <= 0.0:
			_charging = false
			_charge_cd = randf_range(2.5, 4.0)
			if d < 3.6:
				_slam_wind = SLAM_WIND
		return
	if d < 3.4 and _slam_cd <= 0.0:
		_slam_wind = SLAM_WIND
		return
	if d > 8.0 and d < 28.0 and los and _charge_cd <= 0.0:
		_roar_t = ROAR_TIME
		Sfx.play_at(&"boom", center(), -10.0, 0.5)
		return
	_mx = ux
	_mz = uz
	_speed = speed * (0.6 if d < 5.0 else 1.0)


## The ground slam: a shock ring (Game.explode through the pooled blast) that hurts the player within SLAM_RADIUS and shakes the camera.
func _slam() -> void:
	_slams += 1
	_slam_cd = 2.4
	var at := Vector3(global_position.x, global_position.y + 0.15, global_position.z)
	Game.explode(at, _slam_radius(), {"enemy_dmg": 0.0, "car_dmg": 15.0, "player_dmg": _slam_damage(), "color": Color(1.0, 0.55, 0.15)})
	FX.shake(0.5)


func _slam_radius() -> float:
	return SLAM_RADIUS


func _slam_damage() -> float:
	return float(cfg["dmg"])


func slam_count() -> int:
	return _slams


func _fire_cycle(delta: float, d: float, rng: float) -> void:
	match role:
		&"brute":
			return                                              # no ranged attack
		&"sniper":
			if _aim_t > 0.0 and _aim_t <= SNIPER_LOCK and not _locked:
				_locked = true
				_lock_point = _tgt                              # the laser stops following: the shot goes where he was
			elif _aim_t <= 0.0 and _burst_left == 0:
				_locked = false
	super._fire_cycle(delta, d, rng)


func _shoot(d: float) -> void:
	if role == &"sniper" and _locked:
		_aim_override = _lock_point
		super._shoot(d)
		_aim_override = Vector3.INF
		_locked = false
		return
	super._shoot(d)


func _tracer_color() -> Color:
	match role:
		&"sniper":
			return Color(1.0, 0.25, 0.85)
		&"flanker":
			return Color(1.0, 0.7, 0.25)
		&"shield":
			return Color(0.4, 0.85, 1.0)
	return super._tracer_color()


func threat_charge() -> float:
	if dead:
		return 0.0
	if role == &"brute":
		if _slam_wind > 0.0:
			return clampf(1.0 - _slam_wind / SLAM_WIND, 0.0, 1.0)
		if _roar_t > 0.0:
			return clampf(1.0 - _roar_t / ROAR_TIME, 0.0, 1.0)
		return 1.0 if _charging else 0.0
	return super.threat_charge()


func shows_aim_line() -> bool:
	if role == &"brute":
		return false
	return super.shows_aim_line()


## True while the brute is charging or winding up (tests, HUD hints).
func is_charging() -> bool:
	return _charging


func is_winding() -> bool:
	return _slam_wind > 0.0 or _roar_t > 0.0


## The tint of the shield / role for tests.
func shield_up() -> bool:
	return shield_hp > 0.0
