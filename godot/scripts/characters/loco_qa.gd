class_name LocoQA
extends RefCounted
## Locomotion QA meter: samples a posed CharacterRig (and its Locomotion) once per rendered frame, AFTER rig.apply(), and reports what a player would see of the gait:
##   foot slide   metres a sole travels over the ground while it is in contact (planted by the gait AND within `CONTACT_Y` of the floor), per gait cycle (two steps)
##   cadence      footfalls per second, step length in metres (speed / cadence), measured from the same samples
##   pelvis       vertical range of the hip bone over the steady part of the run (the visible bob), torso pitch range
##   knee         largest knee flexion of a swinging leg
## Sampling reads the skeleton, not the gait's own bookkeeping, so a leg that cannot reach its foot (the sole drags or floats) shows up as slide.
## The meter is used by tests/test_hero_locomotion2.gd (synthetic and live motion at several speeds and frame rates) and by tests/loco_viewer.gd (the frame sequences).

const CONTACT_Y := 0.03

var rig: CharacterRig
var loco: Locomotion

var slide_total := 0.0                 ## metres, both feet, over all samples
var worst_info := ""
var slide_worst := 0.0                 ## worst single ground contact (metres)
var contacts := 0                      ## finished ground contacts
var footfalls := 0                     ## touchdowns during the measurement
var time := 0.0
var distance := 0.0
var hip_lo := 9.0
var hip_hi := -9.0
var torso_lo := 9.0
var torso_hi := -9.0
var knee_max := 0.0
var sole_lift_max := 0.0               ## highest sole above the floor while swinging
var pelvis_lead_max := 0.0             ## largest horizontal distance of the hip bone from the midpoint of the two soles (the body hanging over its feet)

var clips: HeroClips                   ## the captured gait (optional): while its weight is above CLIP_MIN the contacts and footfalls are read from the soles' HEIGHT (the IK gait's stance flags no longer describe the legs)
const CLIP_MIN := 0.6
var height_mode := false               ## force the height-based contacts (tests of the captured gait)
var own_footfalls := 0                 ## touchdowns counted from the soles' height (sole above CONTACT_Y one frame, below it the next)
var own_frames := 0
var ground := Callable()               ## optional: func(world_pos: Vector3) -> float, the floor height under a point (ramps, stairs); without it the `ground_y` of sample() is the floor
var pelvis_pop_max := 0.0              ## largest change of the hip height from one frame to the next (metres): a pop is a visible snap in the gait blend
var pelvis_pop_at := 0.0               ## time (s into the measurement) of the largest pelvis pop
var _hip_prev := NAN
var _prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _in: Array[bool] = [false, false]
var _cur: Array[float] = [0.0, 0.0]
var _ff0 := 0
var _ff1 := -1
var _origin_prev := Vector3.ZERO
var _have_origin := false
var _air_prev: Array[bool] = [true, true]
var _trk: Array = [[[], [], []], [[], [], []]]
var _dt := 1.0 / 60.0
var _air_time: Array[float] = [1.0, 1.0]
var _foot_i: Array[int] = [-1, -1]
var _ball_i: Array[int] = [-1, -1]
var _hips_i := -1
var _torso_i := -1
var _shin_i: Array[int] = [-1, -1]


func _init(r: CharacterRig, l: Locomotion) -> void:
	rig = r
	loco = l
	_hips_i = rig.skeleton.find_bone("Hips")
	_torso_i = rig.skeleton.find_bone("Torso")
	_shin_i = [rig.skeleton.find_bone("ShinL"), rig.skeleton.find_bone("ShinR")]
	_foot_i = [rig.skeleton.find_bone("FootL"), rig.skeleton.find_bone("FootR")]
	_ball_i = [rig.skeleton.find_bone("ball_l"), rig.skeleton.find_bone("ball_r")]


## Forget the measurement (the gait keeps running): call when the speed has settled.
func begin() -> void:
	slide_total = 0.0
	slide_worst = 0.0
	contacts = 0
	time = 0.0
	distance = 0.0
	hip_lo = 9.0
	hip_hi = -9.0
	torso_lo = 9.0
	torso_hi = -9.0
	knee_max = 0.0
	sole_lift_max = 0.0
	pelvis_lead_max = 0.0
	pelvis_pop_max = 0.0
	_hip_prev = NAN
	_in = [false, false]
	_cur = [0.0, 0.0]
	_have_origin = false
	_ff0 = loco.footfalls
	_ff1 = -1
	own_footfalls = 0
	own_frames = 0
	_air_prev = [true, true]
	_air_time = [1.0, 1.0]
	_trk = [[[], [], []], [[], [], []]]


## World position of the sole contact point of foot k (0 left, 1 right).
func sole_world(k: int) -> Vector3:
	var mv := rig.bone_move(CharacterRig.FOOT_L if k == 0 else CharacterRig.FOOT_R)
	return rig.model.global_transform * (mv * rig.sole_rest(k))


func hips_world() -> Vector3:
	return rig.model.global_transform * (rig.bone_move(CharacterRig.HIPS) * Vector3(0.0, rig._hips_rest_y, 0.0))


## One frame. `dt` the frame time, `moving` whether the gait is expected to be stepping (speed or turning), `ground_y` the floor height under the model.
func sample(dt: float, moving: bool, ground_y := 0.0) -> void:
	time += dt
	var origin := rig.model.global_position
	if _have_origin:
		distance += Vector2(origin.x - _origin_prev.x, origin.z - _origin_prev.z).length()
	_origin_prev = origin
	_have_origin = true
	var soles: Array[Vector3] = [sole_world(0), sole_world(1)]
	var by_h := height_mode or (clips != null and clips.weight > CLIP_MIN)
	if by_h:
		own_frames += 1
		_sample_points(ground_y, dt)
	for k in 2:
		var s := soles[k]
		var gy: float = ground.call(s) if ground.is_valid() else ground_y
		if by_h:
			if not (s.y - gy < CONTACT_Y):
				sole_lift_max = maxf(sole_lift_max, s.y - gy)
			continue
		var on_floor := loco.stance_progress(k) >= 0.0 and s.y - gy < CONTACT_Y
		if on_floor and moving:
			if _in[k]:
				var d := Vector2(s.x - _prev[k].x, s.z - _prev[k].z).length()
				slide_total += d
				_cur[k] += d
			else:
				_in[k] = true
				_cur[k] = 0.0
		elif _in[k]:
			_in[k] = false
			contacts += 1
			slide_worst = maxf(slide_worst, _cur[k])
		_prev[k] = s
		if loco.stance_progress(k) < 0.0:
			sole_lift_max = maxf(sole_lift_max, s.y - gy)
			var ki := _shin_i[k]
			if ki >= 0:
				knee_max = maxf(knee_max, absf(rig.skeleton.get_bone_pose(ki).basis.get_euler().x))
	if by_h:
		for k in 2:
			var ki2 := _shin_i[k]
			if ki2 >= 0:
				knee_max = maxf(knee_max, absf(rig.skeleton.get_bone_pose(ki2).basis.get_euler().x))
	var h := hips_world()
	var hg: float = ground.call(h) if ground.is_valid() else ground_y
	hip_lo = minf(hip_lo, h.y - hg)
	hip_hi = maxf(hip_hi, h.y - hg)
	if not is_nan(_hip_prev):
		var pop := absf((h.y - hg) - _hip_prev)
		if pop > pelvis_pop_max:
			pelvis_pop_max = pop
			pelvis_pop_at = time
	_hip_prev = h.y - hg
	var mid := (soles[0] + soles[1]) * 0.5
	pelvis_lead_max = maxf(pelvis_lead_max, Vector2(h.x - mid.x, h.z - mid.z).length())
	if _torso_i >= 0:
		var tp := rig.skeleton.get_bone_pose(_torso_i).basis.get_euler().x
		torso_lo = minf(torso_lo, tp)
		torso_hi = maxf(torso_hi, tp)


## World positions of the three contact points of foot k (heel, ball, toe tip) read from the posed skeleton.
func foot_points(k: int) -> Array[Vector3]:
	var sk := rig.skeleton
	var xf := sk.global_transform
	var fb := sk.get_bone_global_pose(_foot_i[k])
	var bb := sk.get_bone_global_pose(_ball_i[k])
	return [xf * (fb * Vector3(0.0, -0.071, 0.03)), xf * bb.origin, xf * (bb * Vector3(0.0, 0.0, -0.079))]


## The captured gait's slide: each of the three points of a foot is a contact while it is within CLIP_CONTACT_Y of its resting height; the travel of one point over the ground
## while it stays in contact is the slide (a roll from heel to toe changes the point, not the travel).
const CLIP_CONTACT_Y := 0.03


func _sample_points(ground_y: float, dt: float) -> void:
	_dt = dt
	for k in 2:
		var pts := foot_points(k)
		var any := false
		for j in 3:
			var s: Vector3 = pts[j]
			var gy: float = ground.call(s) if ground.is_valid() else ground_y
			if s.y - gy < CLIP_CONTACT_Y:
				any = true
				(_trk[k][j] as Array).append(s)
			elif (_trk[k][j] as Array).size() > 0:
				_flush(k, j)
		if any:
			if _air_prev[k] and _air_time[k] > 0.1:                  # a touchdown after a real swing (the heel-toe roll of one contact is not a step)
				own_footfalls += 1
			_air_prev[k] = false
			_air_time[k] = 0.0
		else:
			_air_prev[k] = true
			_air_time[k] += dt


## A finished contact of one point: the ground travel of its planted middle (the heel strike and the toe-off, the first and last fifth of the contact, are left out).
func _flush(k: int, j: int) -> void:
	var t: Array = _trk[k][j]
	var n := t.size()
	if n >= 4:
		var i0 := int(ceil(float(n) * 0.2))
		var i1 := int(floor(float(n) * 0.8))
		var d := 0.0
		for i in range(i0 + 1, i1):
			d += Vector2((t[i] as Vector3).x - (t[i - 1] as Vector3).x, (t[i] as Vector3).z - (t[i - 1] as Vector3).z).length()
		slide_total += d / 3.0                                      # the three points of one foot are one contact: their travel is averaged
		if d > slide_worst:
			slide_worst = d
			worst_info = "foot %d point %s %d samples at t %.2f" % [k, "HBT"[j], n, time]
		contacts += 1
	_trk[k][j] = []


## Freeze the footfall count (the gait keeps running after the measurement; the derived numbers must not change).
func end() -> void:
	_ff1 = loco.footfalls
	if own_frames > 0:
		for k in 2:
			for j in 3:
				_flush(k, j)


func _ff_now() -> int:
	if own_frames > 0:
		return own_footfalls
	return _ff1 if _ff1 >= 0 else loco.footfalls


func cycles() -> float:
	return float(_ff_now() - (0 if own_frames > 0 else _ff0)) * 0.5


## Metres of ground travel of the soles in contact per full gait cycle (two steps).
func slide_per_cycle() -> float:
	return slide_total / maxf(cycles(), 0.5)


func footfalls_seen() -> int:
	return _ff_now() - (0 if own_frames > 0 else _ff0)


func cadence() -> float:
	return float(_ff_now() - (0 if own_frames > 0 else _ff0)) / maxf(time, 0.001)


func step_length() -> float:
	return distance / maxf(float(_ff_now() - (0 if own_frames > 0 else _ff0)), 1.0)


func bob() -> float:
	return hip_hi - hip_lo


func summary() -> String:
	return "slide %.1f cm/cycle (worst contact %.1f cm, %d contacts), cadence %.2f steps/s, step %.2f m, bob %.1f cm, torso %.2f..%.2f rad, knee %.2f rad, sole lift %.2f m, pelvis offset %.2f m" % [
			slide_per_cycle() * 100.0, slide_worst * 100.0, contacts, cadence(), step_length(), bob() * 100.0, torso_lo, torso_hi, knee_max, sole_lift_max, pelvis_lead_max]
