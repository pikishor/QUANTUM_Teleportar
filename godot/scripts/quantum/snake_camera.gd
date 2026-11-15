class_name SnakeCamera
extends RefCounted
## The camera of the QUANTUM SNAKE traversal. CameraRig._update_view reads these smoothed outputs every rendered frame (one hook) and adds them to its own distance, height, field of view and roll;
## the yaw and pitch targets steer the view only while the player is not looking around himself (CameraRig.free_look). Nothing here moves the camera: no clipping logic of its own, the rig's
## spring arm and facade rules still keep the lens out of buildings.
##   swing  a longer arm and a wider lens with speed (a speed-lined FOV kick on attach and release), the lens banks into the turn, the view leans after the direction of travel when the finger is off the screen
##   zip    a wide lens and a short arm while the pull runs, a landing dip
##   climb  the camera turns to face the wall and looks up it, a little closer
##   fly    a wide lens and a long arm that grow with speed, the camera banks with the hero (55 %), a dive pulls the lens up behind him
## Reduce motion (UiSettings.s_reduce_motion) halves the field of view effects and removes the bank. `speed_lines` 0..1 drives the screen-edge streaks (snake_fx.gd).

var active := false
var dist_add := 0.0
var height_add := 0.0
var fov_add := 0.0
var shoulder_k := 1.0
var roll := 0.0
var yaw_to := NAN
var yaw_rate := 0.0
var pitch_to := NAN
var pitch_rate := 0.0
var speed_lines := 0.0
var speed := 0.0
var _w := 0.0                          ## overall blend 0..1 (eases in and out)
var _mode := 0
var _t_dist := 0.0
var _t_height := 0.0
var _t_fov := 0.0
var _t_shoulder := 1.0
var _t_roll := 0.0


func reset() -> void:
	active = false
	dist_add = 0.0
	height_add = 0.0
	fov_add = 0.0
	shoulder_k = 1.0
	roll = 0.0
	yaw_to = NAN
	pitch_to = NAN
	speed_lines = 0.0
	_w = 0.0


func on_mode(mode: int) -> void:
	_mode = mode


## One rendered frame. `looking` true while the player looks around himself (the auto turn waits).
func update(st: SnakeTraversal, dt: float, looking: bool) -> void:
	var p := st.p
	if p == null:
		return
	var calm := 0.5 if UiSettings.s_reduce_motion else 1.0
	var sp := p.velocity.length()
	speed = PlayerUtil.damp(speed, sp, 8.0, dt)
	var want := 0.0 if st.mode == SnakeTraversal.Mode.NONE else 1.0
	if st.mode == SnakeTraversal.Mode.NONE and st.air_momentum > 0.0:
		want = clampf(st.air_momentum / 1.0, 0.0, 1.0) * 0.8                     # the view lingers while the released speed carries on
	_w = PlayerUtil.damp(_w, want, 5.0 if want > _w else 2.4, dt)
	active = _w > 0.003
	if not active:
		dist_add = 0.0
		height_add = 0.0
		fov_add = 0.0
		roll = 0.0
		yaw_to = NAN
		pitch_to = NAN
		speed_lines = PlayerUtil.damp(speed_lines, 0.0, 6.0, dt)
		return
	var td := 0.0
	var th := 0.0
	var tf := 0.0
	var ts := 1.0
	var tr := 0.0
	var lines := 0.0
	yaw_to = NAN
	pitch_to = NAN
	var vh := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var vhl := vh.length()
	var right := Vector3(cos(p.camera_rig.yaw), 0.0, -sin(p.camera_rig.yaw))
	match st.mode:
		SnakeTraversal.Mode.SWING:
			td = clampf(sp * 0.05, 0.0, 2.6) + 0.9
			th = 0.9 + clampf(sp * 0.01, 0.0, 0.4)
			tf = clampf(sp * 0.42, 0.0, 17.0) * calm
			ts = 0.7
			if sp > 6.0:
				tr = -clampf(p.velocity.dot(right) / maxf(sp, 1.0), -1.0, 1.0) * 0.1 * calm
			lines = clampf((sp - 22.0) / 30.0, 0.0, 1.0) * calm
			if not looking and vhl > 10.0:
				yaw_to = PlayerUtil.yaw_of(vh / vhl)
				yaw_rate = 1.1
				pitch_to = clampf(-0.2 + p.velocity.y / maxf(sp, 1.0) * 0.18, -0.36, 0.06)
				pitch_rate = 1.4
		SnakeTraversal.Mode.ZIP:
			td = 0.9
			th = 0.3
			tf = clampf(sp * 0.28, 4.0, 20.0) * calm
			ts = 0.6
			lines = clampf((sp - 18.0) / 40.0, 0.0, 1.0) * calm
		SnakeTraversal.Mode.CLIMB:
			td = 1.3
			th = 1.0
			tf = 4.0 * calm
			ts = 0.4
			if not looking:
				yaw_to = st.climb.face_yaw()
				yaw_rate = 2.4
				pitch_to = 0.42 if st.climb.ceiling else (0.02 if st.climb.move_dir.y > 0.2 else -0.04)
				pitch_rate = 1.8
		SnakeTraversal.Mode.FLY:
			var cruise := maxf(SnakePower.fly_cruise(), 1.0)
			td = 0.7 + clampf(sp * 0.035, 0.0, 2.4)
			th = 0.6 + clampf(sp * 0.01, 0.0, 0.5)
			tf = (5.0 + clampf(sp * 0.26, 0.0, 20.0)) * calm
			ts = 0.35
			tr = st.flight.bank * 0.55 * calm
			lines = clampf((sp - cruise * 0.7) / (cruise * 1.2), 0.0, 1.0) * calm
			if st.flight.phase == &"takeoff":
				td += 1.2
				tf += 6.0
		_:
			td = 0.4
			tf = clampf(sp * 0.25, 0.0, 12.0) * calm
			ts = 0.85
			lines = clampf((sp - 24.0) / 30.0, 0.0, 0.6) * calm
	var k := _w
	_t_dist = PlayerUtil.damp(_t_dist, td, 4.0, dt)
	_t_height = PlayerUtil.damp(_t_height, th, 4.0, dt)
	_t_fov = PlayerUtil.damp(_t_fov, tf, 5.0, dt)
	_t_shoulder = PlayerUtil.damp(_t_shoulder, ts, 4.0, dt)
	_t_roll = PlayerUtil.damp(_t_roll, tr, 5.0, dt)
	dist_add = _t_dist * k
	height_add = _t_height * k
	fov_add = _t_fov * k
	shoulder_k = lerpf(1.0, _t_shoulder, k)
	roll = _t_roll * k
	speed_lines = PlayerUtil.damp(speed_lines, lines * k, 6.0, dt)
