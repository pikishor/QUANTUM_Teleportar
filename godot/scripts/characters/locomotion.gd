class_name Locomotion
extends RefCounted
## The stateful half of the character animation (the hero's PlayerBody and the trooper's Operative own one each; CharacterRig is the stateless pose solver).
## It turns the REAL motion of the body (the displacement of its origin since the last frame, its yaw, its air state) into the inputs of the rig:
##   foot planting   the gait phase advances with the DISTANCE travelled (never with time), so the stride lengthens with the speed. A planted foot is a point fixed in
##                   the world: every frame it is moved by minus the body's displacement and rotated by minus its yaw change, so it cannot slide (walk, strafe, back-pedal,
##                   turning in place and any mix). A foot in the air flies from where it left the ground to a landing point predicted from the velocity (Raibert),
##                   on a lifted arc, with the heel / toe roll of the digitigrade foot (heel strike, flat, heel lift and toe-off). At rest the phase keeps running by time
##                   until both feet stand, and a stance that is not at its home spot (aiming, turning) is re-stepped.
##   pelvis          sway over the support foot, drop on the swing side (roll), yaw with the stride, bob (the rig lowers the pelvis to the reach of the legs); the shoulders
##                   counter-rotate and the head stays level and looks where the aim goes.
##   weight          lean from the acceleration (start, stop), a short backward anticipation when the move starts, landing squash with a recovery, takeoff stretch,
##                   airborne poses for rising, apex and falling, aim-down-sights blading, idle breathing / weight shift / glance.
##   cloak, tail     a chain of critically damped springs driven by the body acceleration and the turn rate.
## Everything is a critically damped spring or a closed form: no allocation per frame (the arrays below are sized once).

const FEET := 2
const LATERAL_CLAMP := 1.1
const SHIN_FORWARD := 0.12            ## where the soles of the idle stance sit (metres, forward of the model origin) comes from the rig's rest pose instead
const SIGMA_WALK := 0.62
const STEP_MAX := 0.66               ## longest ground contact travel of a foot (metres)
const TOE_OFF := -0.5
const HEEL_STRIKE := 0.24
const RESTEP_DIST := 0.09
const REACH_LEASH := 0.42            ## a planted foot farther than this from its hip (metres) is stepped

var rig: CharacterRig
var scale_amp := 1.0                 ## 1 hero, a little less for the shorter trooper
var turn_scale := 0.0                ## > 0: replaces scale_amp in the stepping rate of a turn on the spot (the superhero: long legs, short turn steps)

# --- public outputs besides the rig fields
var speed := 0.0                     ## smoothed ground speed (m/s)
var vel := Vector2.ZERO              ## smoothed body-space velocity (x right, y forward)
var acc := Vector2.ZERO              ## smoothed body-space acceleration (m/s^2)
var run_amount := 0.0                ## 0 walk .. 1 sprint
var yaw_rate := 0.0
var footfalls := 0                   ## number of touchdowns so far (tests, footsteps)
var planted_l := true                ## stance flags of the last update
var planted_r := true
var sole_world_l := Vector3.ZERO     ## the sole contact point of each foot as the rig was told (model space)
var sole_world_r := Vector3.ZERO

# --- state
var _home: PackedVector2Array         ## idle sole spots in the body frame (x right, y forward)
var _fp: PackedVector2Array           ## planted, or current, sole spot of each foot (body frame)
var _lo: PackedVector2Array           ## where the foot left the ground (body frame, kept world fixed during the swing)
var _swing := PackedByteArray()
var _phase := 0.06                    ## gait phase, cycles
var _sigma := SIGMA_WALK
var _fyaw: PackedFloat32Array         ## foot yaw (counter-rotated while planted)
var _first := true
var _yaw_prev := 0.0
var _vx := Vector2.ZERO               ## spring states (value, velocity)
var _vy_s := Vector2.ZERO
var _lean := Vector2.ZERO
var _sway := Vector2.ZERO
var _lag := Vector2.ZERO              ## torso lags the turn
var _look := Vector2.ZERO
var _look_p := Vector2.ZERO
var _squash := Vector2.ZERO
var _roll := Vector2.ZERO
var _air := 0.0
var _sprint := 0.0
var _ads := 0.0
var _was_grounded := true
var _fall_min := 0.0
var _antic := 0.0
var _was_moving := false
var _want_prev := 0.0
var _clock := 0.0
var _sec := PackedVector2Array()      ## 3 chain segments x (pitch, side) springs: index k*2 (pitch), k*2+1 (side)
var _yr := 0.0
var _turn_gate := 0.0
var _w := PackedFloat32Array()        ## stance weight of each foot 0..1
var _kk := PackedFloat32Array()       ## stance progress 0..1 (or swing progress +1..2: not used)
var _idle_hold := true
var _forced := PackedFloat32Array([0.0, 0.0])    ## > 0: a planted foot that got out of reach is being stepped to its landing point (progress 0..1, by time)


func _init(r: CharacterRig = null) -> void:
	rig = r
	_home = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	_fp = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	_lo = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	_swing = PackedByteArray([0, 0])
	_fyaw = PackedFloat32Array([0.0, 0.0])
	_w = PackedFloat32Array([1.0, 1.0])
	_kk = PackedFloat32Array([0.5, 0.5])
	_sec = PackedVector2Array()
	_sec.resize(6)
	if r != null:
		_read_home()


func _read_home() -> void:
	for k in FEET:
		var a := rig.sole_rest(k)                      # model space: x right, z back
		_home[k] = Vector2(a.x, -a.z)
		_fp[k] = _home[k]
		_lo[k] = _home[k]


## Forget everything and stand with both feet at home (spawn, respawn, teleport).
func reset() -> void:
	_first = true
	_vx = Vector2.ZERO
	_vy_s = Vector2.ZERO
	_lean = Vector2.ZERO
	_sway = Vector2.ZERO
	_lag = Vector2.ZERO
	_look = Vector2.ZERO
	_look_p = Vector2.ZERO
	_squash = Vector2.ZERO
	_roll = Vector2.ZERO
	_air = 0.0
	_sprint = 0.0
	_antic = 0.0
	_was_moving = false
	_phase = 0.06
	_sigma = SIGMA_WALK
	for i in 6:
		_sec[i] = Vector2.ZERO
	if rig != null:
		_read_home()
	for k in FEET:
		_swing[k] = 0
		_fyaw[k] = 0.0
		_w[k] = 1.0
		_forced[k] = 0.0
	speed = 0.0
	vel = Vector2.ZERO
	acc = Vector2.ZERO


## One rendered frame. `disp` is the world displacement of the body origin since the previous call, `yaw` its facing (Node3D.rotation.y), `grounded` false in the air
## (already debounced by the owner), `vy` the vertical speed, `want` 0..1 how hard the move input is pushed, `sprint_on` / `aim_on` the stance wishes,
## `look_off` the yaw of the aim relative to the body (radians, + left), `pitch` the aim pitch the owner smooths.
func update(dt: float, disp: Vector3, yaw: float, grounded: bool, vy: float, want: float, sprint_on: bool, aim_on: bool, look_off := 0.0) -> void:
	if rig == null or dt <= 0.0:
		return
	_clock += dt
	var d2 := Vector2(disp.x, disp.z)
	if _first or d2.length() > 3.0:                      # teleport, blink, first frame: stand where we are
		_first = false
		_yaw_prev = yaw
		_read_home()
		d2 = Vector2.ZERO
	var dyaw := angle_difference(_yaw_prev, yaw)
	var fwd := Vector2(-sin(_yaw_prev), -cos(_yaw_prev))   # world (x, z) of the body axes at the START of the frame
	var rgt := Vector2(cos(_yaw_prev), -sin(_yaw_prev))
	var step := Vector2(d2.dot(rgt), d2.dot(fwd))           # displacement in the old body frame (x right, y forward)
	_yaw_prev = yaw
	var dist := d2.length()

	# --- smoothed velocity, acceleration, speed
	var v_raw := step / dt
	_vx = PlayerUtil.spring(_vx, v_raw.x, 20.0, dt)
	_vy_s = PlayerUtil.spring(_vy_s, v_raw.y, 20.0, dt)
	vel = Vector2(_vx.x, _vy_s.x)
	acc = Vector2(_vx.y, _vy_s.y)
	speed = vel.length()
	run_amount = clampf((speed - 2.2) / 6.0, 0.0, 1.0)
	yaw_rate = PlayerUtil.damp(yaw_rate, dyaw / dt, 16.0, dt)
	_sprint = PlayerUtil.damp(_sprint, 1.0 if sprint_on else 0.0, 9.0, dt)
	_ads = PlayerUtil.damp(_ads, 1.0 if aim_on else 0.0, 11.0, dt)

	# --- air state: takeoff stretch, landing squash
	_air = PlayerUtil.damp(_air, 0.0 if grounded else 1.0, 12.0, dt)
	if not grounded:
		_fall_min = minf(_fall_min, vy)
	if _was_grounded and not grounded and vy > 1.0:
		_squash.y = -3.2                                  # push off: the pelvis rises on the toes
	if grounded and not _was_grounded:
		var impact := clampf((-_fall_min - 2.5) / 12.0, 0.0, 1.0)
		_squash.y = 2.4 + 8.0 * impact
		_fall_min = 0.0
		for k in FEET:                                    # land with both feet down, a little apart, in the direction of travel
			_swing[k] = 0
			_fp[k] = _home[k] + Vector2(0.0, 0.05 * (1.0 if k == 0 else -1.0)) + (vel.normalized() * 0.08 if speed > 1.0 else Vector2.ZERO)
			_w[k] = 1.0
		footfalls += 2
	_was_grounded = grounded
	_squash = PlayerUtil.spring(_squash, 0.0, 15.0, dt) if _squash.x != 0.0 or _squash.y != 0.0 else _squash

	# --- gait parameters from the speed and the direction of travel
	var raw_sp := step.length() / dt
	var sp := maxf(speed, 0.001)
	var lat := absf(vel.x) / sp
	var back := clampf(-vel.y / sp, 0.0, 1.0)
	var dscale := lerpf(1.0, 0.8, lat) * lerpf(1.0, 0.72, back)
	var gspd := maxf(speed, raw_sp * 0.8)                # the first frames of a start: the smoothed speed still lags the real motion
	var cyc := (0.8 + 0.5 * gspd) * dscale * scale_amp   # metres per full cycle (two steps)
	cyc = maxf(cyc, 0.8)
	var contact := minf(SIGMA_WALK * cyc, STEP_MAX * scale_amp)
	var moving := gspd > 0.45 and grounded
	var turning := absf(yaw_rate) > 0.7 and speed < 1.6 and grounded
	var sigma_t := contact / cyc if moving else SIGMA_WALK
	_sigma = PlayerUtil.damp(_sigma, sigma_t, 7.0, dt) if moving else sigma_t
	var sig := minf(_sigma, contact / cyc) if moving else _sigma         # the leash of a planted foot never exceeds one contact length, whatever the speed does meanwhile
	var lead_n := vel / maxf(speed, 0.5)                 # shrinks to nothing below 0.5 m/s
	var pred := lead_n * (contact * 0.5)

	# --- phase: by distance while moving, by arc length while turning on the spot, by time while settling
	var advance := 0.0
	if grounded:
		if moving:
			advance = dist / cyc
		elif turning:
			advance = absf(dyaw) * 0.3 / (1.1 * (turn_scale if turn_scale > 0.0 else scale_amp))
		else:
			var misplaced := false
			for k in FEET:
				if (_fp[k] - _home_now(k)).length() > RESTEP_DIST:
					misplaced = true
			var both_down := _stance(0, _phase) and _stance(1, _phase)
			if misplaced or not both_down or _sigma < SIGMA_WALK - 0.03:
				advance = dt * 3.4
		_phase += advance
		_phase -= floorf(_phase)

	# --- feet
	var c := cos(dyaw)
	var s := sin(dyaw)
	var home_lead := Vector2(pred.x, pred.y)
	for k in FEET:
		var pk := _phase + (0.0 if k == 0 else 0.5)
		pk -= floorf(pk)
		var in_stance := pk < sig
		var was_swing := _swing[k] == 1
		# the world fixed points follow the body motion
		var p := _fp[k] - step
		_fp[k] = Vector2(p.x * c + p.y * s, p.y * c - p.x * s)
		var lp := _lo[k] - step
		_lo[k] = Vector2(lp.x * c + lp.y * s, lp.y * c - lp.x * s)
		_fyaw[k] -= dyaw * (1.0 if not was_swing else 0.0)
		if not grounded:
			_w[k] = PlayerUtil.damp(_w[k], 0.0, 18.0, dt)
			continue
		if _forced[k] > 0.0:                               # out of reach: a quick corrective step to the landing point, whatever the phase says
			var fu := minf(_forced[k] + dt / 0.2, 1.0)
			_forced[k] = fu if fu < 1.0 else 0.0
			var ft := _home_now(k) + _rot(home_lead, yaw_rate * 0.18)
			_fp[k] = _lo[k].lerp(ft, fu * fu * (3.0 - 2.0 * fu))
			_swing[k] = 1 if fu < 1.0 else 0
			_kk[k] = fu if fu < 1.0 else 0.15
			_w[k] = PlayerUtil.damp(_w[k], 0.0, 30.0, dt) if fu < 1.0 else 0.3
			continue
		if in_stance and not was_swing and (_fp[k] - Vector2(_home[k].x, 0.0)).length() > REACH_LEASH * scale_amp and (moving or turning):
			_forced[k] = 0.001
			_lo[k] = _fp[k]
			_swing[k] = 1
			continue
		if in_stance:
			if was_swing:                                  # touchdown
				_swing[k] = 0
				footfalls += 1
			var kk := pk / maxf(sig, 0.05)
			_kk[k] = kk
			_w[k] = _smooth01(kk / 0.12) * (1.0 - _smooth01((kk - 0.88) / 0.12)) if moving or turning else 1.0
			_fyaw[k] = clampf(_fyaw[k], -0.9, 0.9)
		else:
			if not was_swing:                              # lift off
				_swing[k] = 1
				_lo[k] = _fp[k]
			var u := (pk - sig) / maxf(1.0 - sig, 0.05)
			_kk[k] = u
			var tgt := _home_now(k) + _rot(home_lead, yaw_rate * 0.18)
			var e := u * u * (3.0 - 2.0 * u)
			_fp[k] = _lo[k].lerp(tgt, e)
			_w[k] = PlayerUtil.damp(_w[k], 0.0, 30.0, dt)
			_fyaw[k] = lerpf(_fyaw[k], (0.07 if k == 1 else -0.07), clampf(dt * 8.0, 0.0, 1.0))
	planted_l = _swing[0] == 0
	planted_r = _swing[1] == 0

	# --- the air and ground poses of the soles, written into the rig
	var run_h := lerpf(0.07, 0.3, run_amount)
	var rise := clampf(vy / 7.6, 0.0, 1.0)
	var fall := clampf(-vy / 9.0, 0.0, 1.0)
	var apex := clampf(1.0 - rise - fall, 0.0, 1.0)
	for k in FEET:
		var is_l := k == 0
		var sole := Vector3(_fp[k].x, 0.0, -_fp[k].y)
		var pitch := 0.0
		if _swing[k] == 1:
			var u := _kk[k]
			sole.y = run_h * sin(PI * pow(clampf(u, 0.0, 1.0), 0.75))
			pitch = lerpf(TOE_OFF, HEEL_STRIKE, _smooth01(u)) + 0.3 * sin(PI * u) * run_amount
		else:
			var kk := _kk[k]
			if moving or turning:
				if kk < 0.2:
					pitch = HEEL_STRIKE * (1.0 - kk / 0.2)
				elif kk > 0.62:
					pitch = TOE_OFF * _smooth01((kk - 0.62) / 0.38)
		# airborne: rising feet trail, the apex tucks the knees, falling reaches down for the ground
		var ay := rise * (0.28 if is_l else 0.2) + apex * 0.4 + fall * (0.12 if is_l else 0.05)
		var az := rise * (0.0 if is_l else -0.18) + apex * (0.18 if is_l else 0.1) + fall * (0.16 if is_l else 0.08)
		var apitch := rise * -0.5 + apex * -0.2 + fall * 0.15
		var air_pos := Vector3(_home[k].x, ay, -(_home[k].y + az) - vel.y * 0.04)
		sole = sole.lerp(air_pos, _air)
		pitch = lerpf(pitch, apitch, _air)
		if k == 0:
			sole_world_l = sole
			rig.sole_l = sole
			rig.pitch_l = pitch
			rig.yaw_l = _fyaw[0]
			rig.support_l = _w[0] * (1.0 - _air)
		else:
			sole_world_r = sole
			rig.sole_r = sole
			rig.pitch_r = pitch
			rig.yaw_r = _fyaw[1]
			rig.support_r = _w[1] * (1.0 - _air)

	# --- pelvis: sway, drop, yaw, weight transfer; idle breathing and weight shift
	var gate := clampf(speed / 1.5, 0.0, 1.0) if grounded else 0.0
	var wd := _w[0] - _w[1]                               # + left foot carries the weight
	var idle := 1.0 - gate
	var shift := sin(_clock * 0.9) * 0.012 * idle
	_sway = PlayerUtil.spring(_sway, -wd * 0.03 * gate + shift, 14.0, dt)
	_roll = PlayerUtil.spring(_roll, -wd * 0.045 * gate - shift * 1.2, 14.0, dt)
	var py := wd * 0.075 * gate * (1.0 + 0.8 * run_amount)
	rig.sway = _sway.x
	rig.pelvis_roll = _roll.x
	rig.pelvis_yaw = py
	# anticipation: a short backward weight shift when a move starts
	if want > 0.3 and _want_prev <= 0.3 and speed < 0.6 and grounded:
		_antic = 0.13
	_want_prev = want
	_antic = maxf(0.0, _antic - dt)
	var antic_w := sin(PI * (1.0 - _antic / 0.13)) if _antic > 0.0 else 0.0
	# lean: speed, acceleration (leans into the start, back into the stop), sprint, the anticipation dip
	var lean_t := -0.022 * clampf(vel.y, -4.0, 10.0) - 0.0032 * clampf(acc.y, -60.0, 60.0) - 0.08 * _sprint + 0.055 * antic_w
	_lean = PlayerUtil.spring(_lean, lean_t, 10.0, dt)
	var brake := clampf(-acc.dot(vel / sp) / 50.0, 0.0, 1.0) * gate if speed > 0.5 else 0.0
	var dip_t := 0.02 * antic_w + 0.035 * brake + 0.015 * run_amount + 0.02 * _ads
	rig.squash = _squash.x + dip_t
	rig.air = _air
	rig.support = maxf(rig.support_l, rig.support_r)
	# turn lag of the torso, the head leads the turn and the aim
	_lag = PlayerUtil.spring(_lag, clampf(-yaw_rate * 0.06, -0.4, 0.4), 9.0, dt)
	var glance := 0.28 * sin(_clock * 0.43) * maxf(0.0, sin(_clock * 0.17 + 1.0)) * idle
	_look = PlayerUtil.spring(_look, clampf(yaw_rate * 0.07 + look_off * 0.8, -0.8, 0.8) + glance, 11.0, dt)
	_look_p = PlayerUtil.spring(_look_p, -0.06 * _ads, 9.0, dt)
	var ads_twist := -0.13 * _ads
	rig.extra_torso = Vector3(rig.extra_torso.x, _lag.x - 0.5 * py + ads_twist, rig.extra_torso.z)
	rig.ads = _ads
	rig.lean = _lean.x
	rig.roll = clampf(-vel.x * 0.014, -0.1, 0.1) + _roll.x * 0.6
	rig.head_look = Vector2(_look.x, _look_p.x)
	rig.run = run_amount
	rig.sprint = _sprint
	rig.amp = clampf(speed / 3.0, 0.0, 1.0) * (1.0 - _air)
	rig.phase = _phase * TAU
	rig.fw = clampf(vel.y / sp, -1.0, 1.0) if speed > 0.2 else 1.0
	rig.lw = clampf(vel.x / sp, -1.0, 1.0) if speed > 0.2 else 0.0
	rig.breathe = sin(_clock * 2.1) * 0.018 * idle + sin(_clock * 5.2) * 0.004 * gate
	rig.clock = _clock
	rig.ik = true

	# --- the chain (cloak or tail): critically damped springs, lower segments softer
	for k in 3:
		var om := 15.0 - 3.0 * float(k)
		var pt := -(0.1 + 0.07 * float(k)) * clampf(vel.y / 6.0, -0.4, 1.4) - 0.0045 * acc.y * (1.0 + 0.6 * float(k)) - 0.3 * _air * (1.0 + 0.4 * float(k))
		pt = clampf(pt, -1.0, 0.6)
		var st := 0.0045 * -acc.x * (1.0 + 0.5 * float(k)) + 0.06 * yaw_rate * float(k + 1) * 0.5 - 0.06 * vel.x / 6.0
		st = clampf(st, -0.8, 0.8)
		_sec[k * 2] = PlayerUtil.spring(_sec[k * 2], pt, om, dt)
		_sec[k * 2 + 1] = PlayerUtil.spring(_sec[k * 2 + 1], st, om, dt)
		rig.sec_pitch[k] = _sec[k * 2].x
		rig.sec_side[k] = _sec[k * 2 + 1].x
	rig.use_springs = true


## Stance progress of a foot 0..1 (heel strike .. toe-off), or -1 while it is in the air or swinging (tests, the foot-slide bot).
func stance_progress(k: int) -> float:
	return _kk[k] if (_swing[k] == 0 and _air < 0.3) else -1.0


## Home spot of a foot now (the idle stance, widened and blading while aiming).
func _home_now(k: int) -> Vector2:
	var h := _home[k]
	var sgn := -1.0 if k == 0 else 1.0
	return h + Vector2(sgn * 0.0 + (-0.03 if k == 0 else 0.03) * _ads, (0.12 if k == 0 else -0.1) * _ads)


func _stance(k: int, ph: float) -> bool:
	var pk := ph + (0.0 if k == 0 else 0.5)
	pk -= floorf(pk)
	return pk < _sigma


static func _smooth01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _rot(v: Vector2, a: float) -> Vector2:
	var cs := cos(a)
	var sn := sin(a)
	return Vector2(v.x * cs + v.y * sn, v.y * cs - v.x * sn)
