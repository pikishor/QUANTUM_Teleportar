class_name HeroClips
extends RefCounted
## Motion-captured locomotion of the hero: the Quaternius Universal Animation Library (CC0) clips retargeted onto the hero skeleton (tools/hero/clips.sh, assets/anim/hero_clips.res) and
## played by DISTANCE, so a planted foot does not slide. One per hero; PlayerBody calls update() right after Locomotion.update() and HeroAnimPolish.update(), before CharacterRig.apply().
##   idle / ready   standing (relaxed, or the weapon-ready stance with the feet apart while aiming, firing, reloading)
##   walk           0.15..2.4 m/s, plays at v / 1.1 m/s
##   jog / sprint   4.2 m/s and up, play at v / 6.1 and v / 9.3 m/s, blended in phase (frame 0 of every cycle = left heel strike)
##   air            the jump / fall pose; a landing absorbs on bent legs
## Between 2.4 and 4.2 m/s no captured gait fits (the clips are a 1.1 m/s walk and a 6.1 m/s jog), so the procedural planted-foot IK gait (Locomotion) carries the legs there and the clip weight
## fades out. Strafing and diagonals also stay with the IK gait; the lower body turns toward the direction of travel inside the forward / backward cones.
## The clips drive the legs, the pelvis and the lower spine only: the arms, the weapon and the aim stay with CharacterRig (two-handed IK on the weapon's grips, aim pitch and yaw).
## Outputs, written to the rig: clip_w (0..1), clip_hips, clip_q (11 quaternions in `bones()` order), clip_yaw, clip_steady, clip_counter. Debug: `force` = [clip, time] pins a frame.

const PATH := "res://assets/anim/hero_clips.res"
const WALK_LO := 0.15
const WALK_HI := 0.6
const WALK_END_LO := 1.9
const WALK_END_HI := 2.4
const JOG_LO := 4.2
const JOG_HI := 5.4
const SPRINT_LO := 6.8
const SPRINT_HI := 8.2
const BOB_KEEP := 1.0                  ## fraction of the captured pelvis bounce that is kept (1: the planted feet stay on the floor; any scaling lifts the feet off it unless the legs are re-solved)

static var _data := {}
static var _tried := false
static var _mean_y := {}

var rig: CharacterRig
var phase := 0.0                       ## gait cycle 0..1, 0 = left heel strike
var weight := 0.0                      ## the clip weight written to the rig
var weights := {}                      ## last normalised clip weights (tests, viewers)
var force: Array = []                  ## [clip name, seconds]: pin a clip frame (look-dev)
var enabled := true
var landings := 0
var _idle_t := 0.0
var _w := {&"idle": 1.0, &"ready": 0.0, &"crouch_idle": 0.0, &"walk": 0.0, &"jog": 0.0, &"sprint": 0.0, &"air": 0.0}
var _fall_min := 0.0
var _land_k := 0.0
var _q: Array = []
var _hips := Vector3.ZERO
var _air := 0.0
var _land_t := -1.0
var _was_grounded := true
var _yaw := 0.0


static func data() -> Dictionary:
	if not _tried:
		_tried = true
		var r := load(PATH) as HeroClipData if ResourceLoader.exists(PATH) else null
		if r != null:
			_data = r.data
	return _data


static func available() -> bool:
	return not data().is_empty()


static func bones() -> Array:
	return data().get("bones", [])


func _init(r: CharacterRig = null) -> void:
	rig = r
	for i in 11:
		_q.append(Quaternion.IDENTITY)


## Metres of ground per gait cycle of a clip (the body travels this far while the clip plays once).
static func stride_of(clip: StringName) -> float:
	var c: Dictionary = (data().get("clips", {}) as Dictionary).get(String(clip), {})
	return float(c.get("stride", 1.0))


## Speed (m/s) at which a clip plays at its natural rate.
static func speed_of(clip: StringName) -> float:
	var c: Dictionary = (data().get("clips", {}) as Dictionary).get(String(clip), {})
	return float(c.get("speed", 1.0))


static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / maxf(b - a, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func reset() -> void:
	phase = 0.0
	_idle_t = 0.0
	for k in _w:
		_w[k] = 1.0 if k == &"idle" else 0.0
	_air = 0.0
	_land_t = -1.0
	_yaw = 0.0
	weight = 0.0
	if rig != null:
		rig.clip_w = 0.0


## The sampled pose of a clip at time `t` seconds (looped when the clip loops): fills `q` (11 quaternions) and returns the pelvis offset.
static func sample(clip: StringName, t: float, q: Array) -> Vector3:
	var c: Dictionary = (data().get("clips", {}) as Dictionary).get(String(clip), {})
	if c.is_empty():
		return Vector3.ZERO
	var n := int(c["n"])
	var fps := float(c["fps"])
	var looped := bool(c["loop"])
	var f := t * fps
	var i0: int
	var u: float
	if looped:
		f = fposmod(f, float(n))
		i0 = int(floor(f)) % n
		u = f - floor(f)
	else:
		f = clampf(f, 0.0, float(n - 1))
		i0 = mini(int(floor(f)), n - 2)
		u = f - float(i0)
	var i1 := (i0 + 1) % n if looped else i0 + 1
	var qa: PackedFloat32Array = c["q"]
	var ha: PackedFloat32Array = c["hips"]
	var nb := 11
	for b in nb:
		var o0 := (i0 * nb + b) * 4
		var o1 := (i1 * nb + b) * 4
		var a := Quaternion(qa[o0], qa[o0 + 1], qa[o0 + 2], qa[o0 + 3])
		var bq := Quaternion(qa[o1], qa[o1 + 1], qa[o1 + 2], qa[o1 + 3])
		q[b] = a.slerp(bq, u)
	var p0 := Vector3(ha[i0 * 3], ha[i0 * 3 + 1], ha[i0 * 3 + 2])
	var p1 := Vector3(ha[i1 * 3], ha[i1 * 3 + 1], ha[i1 * 3 + 2])
	var p := p0.lerp(p1, u)
	if looped:
		var my: float = _mean_y.get(clip, NAN)
		if is_nan(my):
			my = 0.0
			for k in n:
				my += ha[k * 3 + 1]
			my /= float(n)
			_mean_y[clip] = my
		p.y = lerpf(my, p.y, BOB_KEEP)
	return p


static func clip_time(clip: StringName, cycle: float) -> float:
	var c: Dictionary = (data().get("clips", {}) as Dictionary).get(String(clip), {})
	return cycle * float(c.get("dur", 1.0))


## One frame. `loco` is updated already; `dist` the ground distance the body travelled this frame; `terrain` 0..1 how flat the ground under the feet is (the IK gait follows slopes and stairs);
## `crouching` is the cover system's crouch. Returns the clip weight.
func update(dt: float, loco: Locomotion, dist: float, grounded: bool, vy: float, terrain: float, crouching: bool) -> float:
	if rig == null or not enabled or not available():
		weight = 0.0
		if rig != null:
			rig.clip_w = 0.0
		return 0.0
	if not force.is_empty():
		_force_pose()
		return weight
	var v := loco.vel
	var s := loco.speed
	# direction of travel against the body: 0 forward, +PI/2 right, PI backward
	var th := atan2(v.x, v.y) if s > 0.3 else 0.0
	var off := minf(absf(th), PI - absf(th))                     # angle off the body's long axis (0 forward or backward)
	var wd := 1.0 - smooth(0.62, 1.1, off)                       # forward and backward cones keep the clip; strafing is the IK gait's
	var back := absf(th) > PI * 0.5
	var yaw_t := 0.0
	if s > 0.3:
		yaw_t = (th - signf(th) * PI) if back else th
		yaw_t = clampf(yaw_t * 0.85, -0.6, 0.6)
	_yaw = lerpf(_yaw, yaw_t, 1.0 - exp(-12.0 * dt))
	# --- landing / air
	if not grounded:
		_air = lerpf(_air, 1.0, 1.0 - exp(-14.0 * dt))
		_land_t = -1.0
		_fall_min = minf(_fall_min, vy)
	else:
		if not _was_grounded:
			_land_t = 0.0
			_land_k = clampf((-_fall_min - 3.0) / 9.0, 0.0, 1.0)         # a hop barely bends the knees, a drop from a roof absorbs deep
			_fall_min = 0.0
			landings += 1
		_air = lerpf(_air, 0.0, 1.0 - exp(-18.0 * dt))
	_was_grounded = grounded
	if _land_t >= 0.0:
		_land_t += dt
		if _land_t > 0.55:
			_land_t = -1.0
	# --- target weights by speed
	var ready_k := clampf((rig.ready - 0.75) / 0.25, 0.0, 1.0) if rig != null else 0.0
	var moving := smooth(WALK_LO, WALK_HI, s)
	var t_idle := 1.0 - moving
	var t_crouch := 0.0
	if crouching:                                                # a crouched stand uses the captured crouch; a crouched walk is the IK gait (the library's crouch walk is 0.7 m/s)
		t_crouch = t_idle
		t_idle = 0.0
	var t_walk := moving * (1.0 - smooth(WALK_END_LO, WALK_END_HI, s))
	var t_jog := smooth(JOG_LO, JOG_HI, s) * (1.0 - smooth(SPRINT_LO, SPRINT_HI, s))
	var t_spr := smooth(SPRINT_LO, SPRINT_HI, s)
	var k := 1.0 - exp(-14.0 * dt)
	_w[&"crouch_idle"] = lerpf(_w[&"crouch_idle"], t_crouch, k)
	_w[&"idle"] = lerpf(_w[&"idle"], t_idle * (1.0 - ready_k), k)
	_w[&"ready"] = lerpf(_w[&"ready"], t_idle * ready_k, k)
	_w[&"walk"] = lerpf(_w[&"walk"], t_walk, k)
	_w[&"jog"] = lerpf(_w[&"jog"], t_jog, k)
	_w[&"sprint"] = lerpf(_w[&"sprint"], t_spr, k)
	_w[&"air"] = _air
	var total := 0.0
	for key in _w:
		total += _w[key]
	var ground_w := 1.0 - _air
	# --- gait phase by distance
	var gsum: float = _w[&"walk"] + _w[&"jog"] + _w[&"sprint"]
	if grounded and gsum > 0.001:
		var stride: float = (_w[&"walk"] * stride_of(&"walk") + _w[&"jog"] * stride_of(&"jog") + _w[&"sprint"] * stride_of(&"sprint")) / gsum
		var sgn := -1.0 if back else 1.0
		phase = fposmod(phase + sgn * dist / maxf(stride, 0.3), 1.0)
	_idle_t += dt
	# --- mix
	var acc_q: Array = []
	for i in 11:
		acc_q.append(Quaternion.IDENTITY)
	var acc_h := Vector3.ZERO
	var acc_w := 0.0
	var tmp: Array = []
	for i in 11:
		tmp.append(Quaternion.IDENTITY)
	var parts: Array = []
	for key in _w:
		var wk: float = _w[key]
		if key != &"air":
			wk *= ground_w
		if wk > 0.0005:
			parts.append([key, wk])
	for pr: Array in parts:
		var key: StringName = pr[0]
		var wk: float = pr[1]
		var t := _clip_time_for(key)
		var clipn: StringName = &"jump_loop" if key == &"air" else key
		var h := sample(clipn, t, tmp)
		acc_w += wk
		var f := wk / acc_w
		for i in 11:
			acc_q[i] = (acc_q[i] as Quaternion).slerp(tmp[i], f) if acc_w > wk else tmp[i]
		acc_h = acc_h.lerp(h, f) if acc_w > wk else h
	if _land_t >= 0.0 and grounded and _land_k > 0.02:           # landing: the legs absorb; the captured landing takes over from the gait for a moment
		var lt := _land_t
		var lw := (1.0 - smooth(0.2, 0.55, lt)) * minf(1.0, lt * 20.0) * _land_k * 0.85
		if lw > 0.001:
			var h2 := sample(&"jump_land", 0.07 + lt * 1.5, tmp)
			if acc_w > 0.0001:
				for i in 11:
					acc_q[i] = (acc_q[i] as Quaternion).slerp(tmp[i], lw)
				acc_h = acc_h.lerp(h2, lw)
				acc_w = acc_w + lw * (1.0 - minf(acc_w, 1.0))
			else:
				for i in 11:
					acc_q[i] = tmp[i]
				acc_h = h2
				acc_w = lw
	_q = acc_q
	_hips = acc_h
	weight = clampf(acc_w, 0.0, 1.0) * lerpf(wd, 1.0, _air) * terrain
	weights = _w.duplicate()
	_write(ready_k)
	return weight


func _clip_time_for(key: StringName) -> float:
	match key:
		&"walk", &"jog", &"sprint":
			return clip_time(key, phase)
		&"air":
			return 0.0
	return _idle_t


func _write(ready_k: float) -> void:
	rig.clip_w = weight
	rig.clip_q = _q
	rig.clip_hips = _hips
	rig.clip_yaw = _yaw
	rig.clip_steady = clampf(rig.ads * 0.85 + ready_k * 0.25, 0.0, 1.0)
	rig.clip_counter = lerpf(0.2, 0.75, rig.clip_steady)
	if weight > 0.5 and (_w[&"walk"] + _w[&"jog"] + _w[&"sprint"]) > 0.5:
		rig.phase = phase * TAU


func _force_pose() -> void:
	var tmp: Array = []
	for i in 11:
		tmp.append(Quaternion.IDENTITY)
	var h := sample(StringName(force[0]), float(force[1]), tmp)
	_q = tmp
	_hips = h
	weight = 1.0
	_yaw = 0.0
	_write(0.0)
