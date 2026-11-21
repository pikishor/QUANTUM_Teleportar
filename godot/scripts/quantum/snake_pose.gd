class_name SnakePose
extends RefCounted
## The hero's body in the QUANTUM SNAKE traversal. PlayerBody.update_view calls `update()` once a frame and then `apply_body()` (the whole body is turned about its centre: head toward the anchor on a swing,
## head forward and belly down in flight, upside down on a ceiling, a forward roll on a hard landing) and `rig_inputs()` (the arms: a hand up on the rope, hands on the wall, arms swept back in flight; the
## legs: the airborne pose, no captured clip). `blend` eases in and out, so the normal strafe-style body takes over smoothly when a state ends.
## Model axes (the rig contract): x right, y up (head), -z forward (the face). All offsets are in model axes, relative to the shoulder.

const ROLL_TIME := SnakeTraversal.ROLL_TIME

static var zip_upright := true            ## critic 117: false = the builders' pull pose (head down over the roof at the end of a roof zip)
static var throw_pose := true             ## critic 117: false = the builders' state (between two ropes the hero stood upright in the air, legs straight)
static var haul_upright := true           ## wave 117: the pose of the haul up a facade (false = the pull pose, which turned him head down there: a test shows it)
var blend := 0.0
var basis := Basis.IDENTITY               ## the wanted world orientation of the model when blend = 1
var pivot := 0.9                          ## metres above the feet the body turns about
var hand_w := Vector2.ZERO                ## weights of the left / right hand placement
var hand_l := Vector3.ZERO                ## shoulder-relative hand targets (model axes)
var hand_r := Vector3.ZERO
var air := 0.0                            ## weight of the airborne leg pose
var crouch := 0.0                         ## metres the pelvis sinks (a landing, a zip touchdown)
var stretch := 0.0
var clip_off := false
var mode: int = 0
var _q := Quaternion.IDENTITY
var _blend_target := 0.0
var _phase := 0.0
var _hl := Vector3.ZERO
var _hr := Vector3.ZERO
var _hw := Vector2.ZERO
var _air := 0.0
var _crouch := 0.0
var _first := true


func reset() -> void:
	blend = 0.0
	_blend_target = 0.0
	_hw = Vector2.ZERO
	_air = 0.0
	_crouch = 0.0
	_first = true
	clip_off = false


func on_mode(m: int, _st: SnakeTraversal) -> void:
	mode = m


## Orientation from a head direction and a facing direction (the face looks along `forward` as far as it is perpendicular to `up`).
static func basis_from(up: Vector3, forward: Vector3) -> Basis:
	var y := up.normalized()
	var f := forward - y * forward.dot(y)
	if f.length() < 0.001:
		f = y.cross(Vector3.RIGHT) if absf(y.dot(Vector3.RIGHT)) < 0.9 else y.cross(Vector3.FORWARD)
	f = f.normalized()
	var z := -f
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## One rendered frame.
func update(st: SnakeTraversal, dt: float) -> void:
	var p := st.p
	if p == null or dt <= 0.0:
		return
	_phase += dt
	var want_b := Basis.IDENTITY
	var bt := 0.0
	var hw := Vector2.ZERO
	var tl := Vector3(-0.2, -0.42, 0.1)
	var tr := Vector3(0.2, -0.42, 0.1)
	var tair := 0.0
	var tcrouch := 0.0
	var tpivot := 0.9
	var vel := p.velocity
	var yaw_b := Basis.from_euler(Vector3(0.0, p.yaw, 0.0))
	match st.mode:
		SnakeTraversal.Mode.SWING:
			bt = 1.0
			var sw := st.swing
			var c := p.global_position + Vector3(0.0, 1.25, 0.0)
			var to_anchor := (sw.anchor - c)
			var rope_dir := to_anchor.normalized() if to_anchor.length() > 0.5 else Vector3.UP
			var up_t := Vector3.UP.lerp(rope_dir, 0.5).normalized()
			var fwd := sw.swing_dir
			want_b = basis_from(up_t, fwd)
			var sh := p.global_position + Vector3(0.0, 1.45, 0.0)
			var local := want_b.inverse() * (sw.anchor - sh).normalized()
			local.y = minf(local.y, 0.7)                                                 # the arm solver needs a target that is not in line with its elbow pole (straight up)
			local.z = minf(local.z, -0.22)
			local = local.normalized()
			var reach := local * 0.54
			if sw.hand_side > 0:
				hw = Vector2(0.15, 1.0)
				tr = reach
				tl = Vector3(-0.36, -0.36, 0.28)
			else:
				hw = Vector2(1.0, 0.15)
				tl = reach
				tr = Vector3(0.36, -0.36, 0.28)
			tair = 1.0
		SnakeTraversal.Mode.ZIP:
			bt = 1.0
			var z := st.zip
			var dirv := (z.dest - p.global_position)
			var d3 := dirv.normalized() if dirv.length() > 0.3 else Vector3.UP
			if z.phase == &"land":
				want_b = yaw_b
				tcrouch = 0.3
				tair = 0.2
				hw = Vector2(0.4, 0.4)
				tl = Vector3(-0.4, -0.25, -0.3)
				tr = Vector3(0.4, -0.25, -0.3)
			elif z.phase == &"haul" and haul_upright:
				# wave 117: hauled up a facade by the rope of snakes: upright, facing the wall, the right hand high on the rope, the feet on the wall (the pull pose above aims at
				# z.dest, which lies BELOW him now: he rode up head down)
				var into := Vector3(-z.normal.x, 0.0, -z.normal.z)
				into = into.normalized() if into.length() > 0.05 else Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
				want_b = basis_from(Vector3.UP.lerp(z.normal, 0.18).normalized(), into)
				var step := sin(_phase * 14.0)
				hw = Vector2(0.5, 1.0)
				tr = Vector3(0.14, 0.52, -0.3)
				tl = Vector3(-0.32, 0.22 + 0.06 * step, -0.3)
				tair = 0.85
				tcrouch = 0.08
			else:
				var k_up := 0.8
				if zip_upright and z.phase == &"pull":
					# critic 117 (frames): the pull pose points the head at z.dest. A roof zip comes in OVER the edge, so near its end the roof is level with him, then
					# below him: he turned flat and then HEAD DOWN above the roof. The head never points below a third of the way up, and he rights himself as he arrives
					d3 = Vector3(d3.x, maxf(d3.y, 0.35), d3.z).normalized()
					var kz := clampf(z.t / maxf(z.dur, 0.01), 0.0, 1.0)
					k_up = 0.8 * (1.0 - smoothstep(0.6, 0.95, kz))
				var head := Vector3.UP.lerp(d3, k_up).normalized()
				want_b = basis_from(head, Vector3(d3.x, 0.0, d3.z) if Vector2(d3.x, d3.z).length() > 0.05 else Vector3(-sin(p.yaw), 0.0, -cos(p.yaw)))
				hw = Vector2(0.6, 1.0)
				tr = Vector3(0.12, 0.34, -0.38)
				tl = Vector3(-0.3, 0.16, -0.28)
				tair = 1.0
		SnakeTraversal.Mode.CLIMB:
			bt = 1.0
			var cl := st.climb
			var n := cl.n
			var face := Vector3(-n.x, 0.0, -n.z).normalized() if Vector2(n.x, n.z).length() > 0.05 else Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
			var sp := cl.move_speed
			var ph := _phase * (3.0 + sp * 0.5)
			if cl.ceiling:
				var fw := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
				want_b = basis_from(Vector3.DOWN, fw)
				tpivot = 0.92
			else:
				var lean := 0.0 if cl.phase == &"mantle" else 0.15
				want_b = basis_from(Vector3.UP.lerp(-n, lean).normalized(), face)
			var sa := sin(ph) if sp > 0.3 else 0.0
			hw = Vector2(1.0, 1.0)
			tl = Vector3(-0.36, 0.40 + 0.12 * sa, -0.3)
			tr = Vector3(0.36, 0.40 - 0.12 * sa, -0.3)
			tair = 0.85
			tcrouch = 0.1
		SnakeTraversal.Mode.FLY:
			bt = 1.0
			var f := st.flight
			var fd := f.dir
			var upref := Vector3.UP
			var rb := Basis(fd, -f.bank)
			upref = rb * Vector3.UP
			if f.roll_t > 0.0:
				var k := 1.0 - f.roll_t / SnakeFlight.ROLL_TIME
				upref = Basis(fd, f.roll_dir * k * TAU) * upref
			# head leads, belly down: model y -> heading, model z (the back) -> up
			var y := fd
			var z := (upref - y * upref.dot(y)).normalized()
			if z.length() < 0.5:
				z = Vector3.BACK
			var x := y.cross(z).normalized()
			want_b = Basis(x, y, z)
			tpivot = 0.95
			var spread := f.wing_spread
			hw = Vector2(1.0, 1.0)
			tl = Vector3(lerpf(-0.16, -0.5, spread), lerpf(-0.42, 0.08, spread), lerpf(0.3, -0.1, spread))
			tr = Vector3(lerpf(0.16, 0.5, spread), lerpf(-0.42, 0.08, spread), lerpf(0.3, -0.1, spread))
			tair = 0.25
		_:
			if st.roll_t > 0.0:
				bt = 1.0
				var k := 1.0 - st.roll_t / ROLL_TIME
				var fh := Vector3(vel.x, 0.0, vel.z)
				var fwd2 := fh.normalized() if fh.length() > 1.0 else Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
				var right := fwd2.cross(Vector3.UP).normalized()
				want_b = Basis(right, k * TAU * 0.999) * basis_from(Vector3.UP, fwd2)
				tpivot = 0.7
				tair = 1.0
				hw = Vector2(0.8, 0.8)
				tl = Vector3(-0.22, -0.28, -0.4)
				tr = Vector3(0.22, -0.28, -0.4)
				tcrouch = 0.25 * sin(k * PI)
			elif throw_pose and st.thrown() and vel.length() > 6.0:
				# critic 117 (frames): thrown by a swing he stood upright in the air like a figure on a shelf. Now he flies: the body leans along the throw (more when it is
				# fast), the legs trail in the airborne pose, the arms sweep back; it eases out as he slows or lands
				var fh2 := Vector3(vel.x, 0.0, vel.z)
				var fwd3 := fh2.normalized() if fh2.length() > 1.0 else Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))
				var lean := clampf(vel.length() / 30.0, 0.0, 1.0) * 0.5
				bt = 1.0
				want_b = basis_from(Vector3.UP.lerp(vel.normalized(), lean).normalized(), fwd3)
				tair = 1.0
				hw = Vector2(0.7, 0.7)
				tl = Vector3(-0.38, -0.3, 0.3)
				tr = Vector3(0.38, -0.3, 0.3)
			else:
				bt = 0.0
				want_b = yaw_b
	if not (want_b.x.is_finite() and want_b.y.is_finite() and want_b.z.is_finite()) or want_b.x.length() < 0.5 or want_b.y.length() < 0.5 or want_b.z.length() < 0.5:
		want_b = yaw_b                                                          # wave 115 critic: a degenerate pose basis (a zip to a moving car, a zero-length direction) printed "Basis must be normalized" every frame
	want_b = want_b.orthonormalized()
	if _first:
		_q = Quaternion(want_b)
		_first = false
	var rate := 12.0 if bt > 0.5 else 9.0
	var qt := Quaternion(want_b)
	_q = _q.slerp(qt, 1.0 - exp(-rate * dt)).normalized()
	basis = Basis(_q)
	blend = PlayerUtil.damp(blend, bt, 10.0 if bt > blend else 6.0, dt)
	if blend < 0.003 and bt == 0.0:
		blend = 0.0
	pivot = lerpf(pivot, tpivot, 1.0 - exp(-10.0 * dt))
	_hw = _hw.lerp(hw, 1.0 - exp(-12.0 * dt))
	_hl = _hl.lerp(tl, 1.0 - exp(-12.0 * dt))
	_hr = _hr.lerp(tr, 1.0 - exp(-12.0 * dt))
	_air = lerpf(_air, tair, 1.0 - exp(-10.0 * dt))
	_crouch = lerpf(_crouch, tcrouch, 1.0 - exp(-12.0 * dt))
	hand_w = _hw * blend
	hand_l = _hl
	hand_r = _hr
	air = _air * blend
	crouch = _crouch * blend
	clip_off = blend > 0.15


## The whole body: the model is turned about its centre by the snake pose (blended with the normal facing).
func apply_body(body: Node3D, view_pos: Vector3, yaw: float) -> void:
	if blend <= 0.002:
		return
	var base := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var q := Quaternion(base).slerp(Quaternion(basis), clampf(blend, 0.0, 1.0)).normalized()
	var b := Basis(q)
	body.global_transform = Transform3D(b, view_pos + Vector3.UP * pivot - b * Vector3(0.0, pivot, 0.0))


## The arms and the legs, before CharacterRig.apply.
func rig_inputs(rig: CharacterRig) -> void:
	if blend <= 0.002:
		return
	var w := Vector2(maxf(rig.hand_w.x, hand_w.x), maxf(rig.hand_w.y, hand_w.y))
	if hand_w.x > rig.hand_w.x:
		rig.hand_off_l = rig.hand_off_l.lerp(hand_l, clampf(hand_w.x, 0.0, 1.0))
	if hand_w.y > rig.hand_w.y:
		rig.hand_off_r = rig.hand_off_r.lerp(hand_r, clampf(hand_w.y, 0.0, 1.0))
	rig.hand_w = w
	rig.air = maxf(rig.air, air)
	rig.pose_hips.y -= crouch * 0.6
	if clip_off:
		rig.clip_w = 0.0
