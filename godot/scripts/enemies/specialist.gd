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
const BLINK_WIND := 0.25                     ## stalker: seconds phased out (no damage) before it reappears
const SHELL_TIME := 1.5                      ## walker: seconds from the lock to the impact
const PULSE_WIND := 0.9                      ## warden: windup of the phase pulse
const SUMMON_WIND := 0.8                     ## hivemother: windup of the call
const POUNCE_WIND := 0.5                     ## pouncer: crouch before the leap
const POUNCE_TIME := 0.45                    ## pouncer: seconds of the leap along the locked line

var role: StringName = &""
var shield_hp := 0.0
var shield_max := 0.0
var shield_node: MeshInstance3D
var tell: MeshInstance3D                   ## the role's emissive tell mesh (EnemyTells), null for shield / sniper-less roles

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
var _blink_cd := 0.0
var _blink_wind := 0.0
var _blinks := 0
var _shell_cd := 0.0
var _shell_t := 0.0
var _shell_at := Vector3.ZERO
var _shells := 0
var _pulse_cd := 0.0
var _pulse_wind := 0.0
var _pulses := 0
var _summon_cd := 0.0
var _summon_wind := 0.0
var _summons := 0
var _pounce_cd := 0.0
var _pounce_wind := 0.0
var _pounce_t := 0.0
var _pounce_dir := Vector2.ZERO
var _pounce_hit := false
var _pounces := 0
var healed := 0.0                            ## mender: total health given to allies (tests)


func setup(t: StringName) -> void:
	super.setup(t)
	role = cfg.get("role", &"")
	if model != null:
		EnemyLook.apply_rim(model, EnemyLook.code_color(cfg), Game.quality)
	if role == &"shield" or role == &"carrier":
		_build_shield()
	elif model != null:
		tell = EnemyTells.make(role)                  # the emissive tell of the role (flanker streaks, sniper eye, brute heat cracks): ONE shared mesh, one draw
		if tell != null:
			model.add_child(tell)


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
	_blink_cd = randf_range(1.5, 3.0)
	_blink_wind = 0.0
	_shell_cd = randf_range(1.5, 3.0)
	_shell_t = 0.0
	_pulse_cd = randf_range(3.0, 5.0)
	_pulse_wind = 0.0
	_summon_cd = randf_range(3.0, 5.0)
	_summon_wind = 0.0
	_pounce_cd = randf_range(1.0, 2.5)
	_pounce_wind = 0.0
	_pounce_t = 0.0
	_pounce_hit = false
	healed = 0.0
	if shield_node != null:
		shield_node.visible = shield_hp > 0.0


func _build_shield() -> void:
	shield_node = MeshInstance3D.new()
	shield_node.name = "Shield"
	var bm := QuadMesh.new()                              # one double-sided quad with a hex-cell texture and a bright frame (glows at 25 m, was a flat 28 % box)
	bm.size = Vector2(1.5, 1.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = EnemyTells.shield_texture()
	mat.albedo_color = Color(1.25, 1.25, 1.25, 0.6)
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
	if role == &"carrier":
		return true                                         # the carrier's ward wraps all round
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
	if was and (role == &"shield" or role == &"carrier"):
		_burst(center() + Vector3(0.0, 0.0, 0.0), Color(0.4, 0.9, 1.0), 14, 6.0, 0.4, 3.0, 1.6)
		_stagger = 0.4
		Sfx.play_at(&"boom", center(), -8.0, 1.8)
	if was and role == &"carrier":
		_release(int(cfg.get("release", 2)))


## Phased out (a stalker mid-blink): hits pass through.
func damage(amount: float, crit := false, mirrored := false) -> void:
	if _blink_wind > 0.0 and role == &"stalker":
		return
	super.damage(amount, crit, mirrored)


## Release `n` swarmers next to this enemy (aware, reinforcements; the manager cap and the swarmer tier limit apply). Returns how many came out.
func _release(n: int) -> int:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return 0
	var out := 0
	for i in n:
		if mgr.count_type(&"swarmer") >= EnemyTypes.tier_limit(&"swarmer", Game.quality):
			break
		var a := TAU * float(i) / maxf(float(n), 1.0) + randf() * 0.5
		var pos := global_position + Vector3(cos(a) * 1.6, 0.0, sin(a) * 1.6)
		if mgr.spawn(&"swarmer", pos, true, true) != null:
			out += 1
	return out


## Phase out and reappear 6-9 m (elites 10-14 m) from the target, anywhere on the ring. Returns true.
func blink() -> bool:
	var far := EnemyTypes.is_elite(type)
	var a := randf() * TAU
	var r := randf_range(10.0, 14.0) if far else randf_range(6.0, 9.0)
	var c := _tgt if _tgt_ok else global_position
	var nx := c.x + cos(a) * r
	var nz := c.z + sin(a) * r
	_burst(center(), EnemyLook.code_color(cfg), 6, 5.0, 0.3, 0.0)
	global_position = Vector3(nx, _ground_y(nx, nz), nz)
	_have_last = false
	_burst(center(), EnemyLook.code_color(cfg), 6, 5.0, 0.3, 0.0)
	_blinks += 1
	_blink_cd = randf_range(3.5, 5.0)
	return true


func blink_count() -> int:
	return _blinks


func shell_count() -> int:
	return _shells


func pulse_count() -> int:
	return _pulses


func summon_count() -> int:
	return _summons


func _turn_rate() -> float:
	if role == &"shield" and shield_hp > 0.0:
		return 2.2
	if role == &"brute" and (_charging or _slam_wind > 0.0):
		return 0.5
	return 8.0


func _animate(delta: float) -> void:
	super._animate(delta)
	if tell != null:
		tell.visible = not dead
		EnemyLook.boost_tell(tell, threat_charge())
	if shield_node != null and shield_node.visible:
		_shield_flash = maxf(0.0, _shield_flash - delta)
		var m := (shield_node.mesh as QuadMesh).material as StandardMaterial3D
		m.albedo_color.a = 0.6 + 0.4 * clampf(_shield_flash / 0.12, 0.0, 1.0) + 0.05 * sin(_clock * 6.0)
		m.albedo_color.r = EnemyLook.plate_glow(threat_charge()) + 2.4 * clampf(_shield_flash / 0.12, 0.0, 1.0)
		m.albedo_color.g = m.albedo_color.r
		m.albedo_color.b = m.albedo_color.r


# --- movement and attacks per role -------------------------------------------------------------------------------------

func _move_aware(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	match role:
		&"stalker":
			_move_stalker(delta, ux, uz, d, speed, rng)
		&"walker":
			_move_walker(delta, ux, uz, d, speed)
		&"pouncer":
			_move_pouncer(delta, ux, uz, d, speed)
		&"mender":
			_move_mender(delta, ux, uz, d, speed, rng)
		&"warden":
			_move_warden(delta, ux, uz, d, speed, rng)
		&"hivemother":
			_move_hivemother(delta, ux, uz, d, speed, rng)
		&"shield", &"carrier":
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
			elif d > rng * 0.9 * Weather.snipe_mult() or (not los and _no_los > 2.0):
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


func _move_stalker(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	_blink_cd = maxf(0.0, _blink_cd - delta)
	if _blink_wind > 0.0:
		_speed = 0.0
		_blink_wind -= delta
		if _blink_wind <= 0.0:
			blink()
		return
	if _blink_cd <= 0.0 and d < 34.0:
		_blink_wind = BLINK_WIND
		return
	super._move_aware(delta, ux, uz, d, speed, rng)


## Artillery: keeps 25 m+ away, stands still while a shell is in the air (the lock is the target's ground point, a sidestep dodges it).
func _move_walker(delta: float, ux: float, uz: float, d: float, speed: float) -> void:
	if _shell_t > 0.0:
		_speed = 0.0
		return
	if d < 22.0:
		_mx = -ux
		_mz = -uz
		_speed = speed
	elif d > 45.0 or not los:
		_mx = ux
		_mz = uz
		_speed = speed
	else:
		_speed = 0.0


## Leap: a 0.5 s crouch (the lock is the direction at its end, a sidestep dodges it), then a fast straight lunge that hurts the player once on contact.
func _move_pouncer(delta: float, ux: float, uz: float, d: float, speed: float) -> void:
	_pounce_cd = maxf(0.0, _pounce_cd - delta)
	if _pounce_wind > 0.0:
		_speed = 0.0
		_pounce_wind -= delta
		if _pounce_wind <= 0.0:
			_pounce_t = POUNCE_TIME
			_pounce_hit = false
			_pounce_dir = Vector2(ux, uz)
		return
	if _pounce_t > 0.0:
		_pounce_t -= delta
		_mx = _pounce_dir.x
		_mz = _pounce_dir.y
		_speed = speed * 4.2
		if d < 1.8 and not _pounce_hit:
			_pounce_hit = true
			_pounces += 1
			var p := Game.player
			if is_instance_valid(p):
				p.call(&"damage", float(cfg["dmg"]), global_position)
			FX.shake(0.25)
		if _pounce_t <= 0.0 or _pounce_hit:
			_pounce_t = 0.0
			_pounce_cd = randf_range(2.0, 3.5)
		return
	if _pounce_cd <= 0.0 and d > 4.0 and d < 16.0 and los:
		_pounce_wind = POUNCE_WIND
		return
	_mx = ux
	_mz = uz
	_speed = speed * (0.6 if d < 5.0 else 1.0)


## Support: stays 12-20 m from the target and mends allies within heal_radius (cfg heal_rate hp/s each, not itself). Kill it first.
func _move_mender(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	var mgr := Game.enemies as EnemyManager
	if mgr != null:
		var rate := float(cfg.get("heal_rate", 14.0)) * delta
		var r := float(cfg.get("heal_radius", 9.0))
		for e in mgr.list:
			if e == self or not e.active or e.dead or e.hp >= e.max_hp:
				continue
			if e.global_position.distance_to(global_position) <= r:
				var add := minf(rate, e.max_hp - e.hp)
				e.hp += add
				healed += add
	if d < 12.0:
		_mx = -ux
		_mz = -uz
		_speed = speed
	elif d > rng:
		_mx = ux
		_mz = uz
		_speed = speed
	else:
		super._move_aware(delta, ux, uz, d, speed * 0.5, rng)


func pounce_count() -> int:
	return _pounces


func _move_warden(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	_pulse_cd = maxf(0.0, _pulse_cd - delta)
	if _pulse_wind > 0.0:
		_speed = 0.0
		_pulse_wind -= delta
		if _pulse_wind <= 0.0:
			_pulse()
		return
	if _pulse_cd <= 0.0 and d < 24.0:
		_pulse_wind = PULSE_WIND
		return
	super._move_aware(delta, ux, uz, d, speed, rng)


## The phase pulse: a ring around the warden (Game.explode, player damage only), then it blinks away.
func _pulse() -> void:
	_pulses += 1
	_pulse_cd = randf_range(6.0, 8.0)
	var at := Vector3(global_position.x, global_position.y + 0.15, global_position.z)
	Game.explode(at, float(cfg.get("pulse_radius", 6.5)), {"enemy_dmg": 0.0, "car_dmg": 12.0, "player_dmg": float(cfg.get("pulse_dmg", 20.0)), "color": Color(0.8, 0.8, 1.0)})
	FX.shake(0.4)
	blink()


func _move_hivemother(delta: float, ux: float, uz: float, d: float, speed: float, rng: float) -> void:
	_summon_cd = maxf(0.0, _summon_cd - delta)
	if _summon_wind > 0.0:
		_speed = 0.0
		_summon_wind -= delta
		if _summon_wind <= 0.0:
			_summons += 1
			_summon_cd = randf_range(8.0, 10.0)
			_release(int(cfg.get("summon", 2)))
			Sfx.play_at(&"boom", center(), -8.0, 0.8)
		return
	if _summon_cd <= 0.0 and d < 40.0:
		_summon_wind = SUMMON_WIND
		return
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
		&"walker":
			_fire_walker(delta, d, rng)
			return
		&"brute", &"pouncer":
			return                                              # no ranged attack
		&"sniper":
			if _aim_t > 0.0 and _aim_t <= SNIPER_LOCK and not _locked:
				_locked = true
				_lock_point = _tgt                              # the laser stops following: the shot goes where he was
			elif _aim_t <= 0.0 and _burst_left == 0:
				_locked = false
	super._fire_cycle(delta, d, rng)


## Mortar: lock the target's ground point, land a shell SHELL_TIME later (Game.explode, shell_radius).
func _fire_walker(delta: float, d: float, rng: float) -> void:
	if _shell_t > 0.0:
		_shell_t -= delta
		if _shell_t <= 0.0:
			_shells += 1
			_shell_cd = randf_range(float((cfg["fire"] as Vector2).x), float((cfg["fire"] as Vector2).y))
			Game.explode(_shell_at, float(cfg.get("shell_radius", 4.5)), {"enemy_dmg": 0.0, "car_dmg": 20.0, "player_dmg": float(cfg["dmg"]), "color": Color(0.6, 0.65, 1.0)})
		return
	_shell_cd -= delta
	if _shell_cd <= 0.0 and _tgt_ok and d > 12.0 and d < rng:
		_shell_at = Vector3(_tgt.x, _ground_y(_tgt.x, _tgt.z) + 0.15, _tgt.z)
		_shell_t = SHELL_TIME
		Sfx.play_at(&"enemy_shot", center(), -2.0, 0.6)


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
		&"shield", &"carrier":
			return Color(0.4, 0.85, 1.0)
		&"stalker":
			return Color(0.4, 1.0, 0.7)
		&"warden":
			return Color(0.9, 0.9, 1.0)
		&"hivemother":
			return Color(1.0, 0.5, 0.65)
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
	if role == &"pouncer" and _pounce_wind > 0.0:
		return clampf(1.0 - _pounce_wind / POUNCE_WIND, 0.0, 1.0)
	if role == &"stalker" and _blink_wind > 0.0:
		return clampf(1.0 - _blink_wind / BLINK_WIND, 0.0, 1.0)
	if role == &"walker" and _shell_t > 0.0:
		return clampf(1.0 - _shell_t / SHELL_TIME, 0.0, 1.0)
	if role == &"warden" and _pulse_wind > 0.0:
		return clampf(1.0 - _pulse_wind / PULSE_WIND, 0.0, 1.0)
	if role == &"hivemother" and _summon_wind > 0.0:
		return clampf(1.0 - _summon_wind / SUMMON_WIND, 0.0, 1.0)
	return super.threat_charge()


func shows_aim_line() -> bool:
	if role == &"brute" or role == &"walker" or role == &"pouncer":
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
