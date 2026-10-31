class_name CameraRig
extends Node3D
## Third-person over-the-shoulder camera: shoulder offset, ADS zoom (critically damped spring), sprint FOV kick, weighty recoil with a recovery
## curve, shake from FX.shake_amount, landing dip, SpringArm3D (sphere shape) pull-in against walls, and a chase mode for driven vehicles.
## Sets Game.camera.
##
## Smoothness. The target (player or vehicle) moves in physics ticks; the rig samples its position every tick and renders the camera
## from the position interpolated with Engine.get_physics_interpolation_fraction(), so there is no judder at any display refresh rate.
## Look angles change per rendered frame. The rig is top_level and drives itself in _process.
## The SpringArm3D solves in the physics tick by itself; to avoid a tick of lag it is solved once more per rendered frame here by sending
## it the internal physics notification (its solver is a pure function of its current global transform).
##
## Look convention of add_look(yaw, pitch): screen-space deltas in radians, like takeLook() in the prototype. A positive yaw turns the view
## RIGHT, a positive pitch tilts it DOWN (the finger or mouse moved right / down). `yaw` and `pitch` themselves follow the Node3D convention:
## yaw grows counter-clockwise seen from above (turning left) and a positive pitch looks UP.

signal mode_changed(new_mode: StringName)

const PITCH_MIN := -1.0
const PITCH_MAX := 0.85
const MOUSE_SENS := 0.0022                   ## radians per pixel
const MOUSE_SPIKE_PX := 120.0
const ADS_MOUSE_SCALE := 0.72
const FREE_LOOK_TIME := 1.5

# presets (src/player.js updateCamera)
const EYE_HEIGHT := 1.55
const HIP_DIST := 3.6
const HIP_SHOULDER := 0.8
const ADS_DIST := 2.0
const ADS_SHOULDER := 0.55
const FOV_HIP := 72.0
const FOV_SPRINT := 78.0
const FOV_ADS := 50.0
const VEH_DIST := 7.5
const VEH_HEIGHT := 1.6
const VEH_FOV := 72.0
const ARM_RADIUS := 0.22
const ADS_OMEGA := 17.0                      ## spring frequency of the aim transition: settles in about a quarter second

# cinematic poses
const ORBIT_DIST := 4.4
const ORBIT_HEIGHT := 1.35
const ORBIT_FOV := 50.0
const ORBIT_PITCH := -0.05
const ORBIT_RATE := 0.07                     ## radians per second
const DEAD_DIST := 5.4
const DEAD_HEIGHT := 0.8
const DEAD_FOV := 58.0
const DEAD_PITCH := -0.42
const DEAD_RATE := 0.035

# recoil
const RECOIL_DELAY := 0.1                    ## seconds after the last kick before the view starts to settle
const RECOIL_RATE := 5.0
const RECOIL_MAX := 0.3
const RECOIL_YAW_MAX := 0.1

var camera: Camera3D
var arm: SpringArm3D
var yaw := -PI * 0.5                         ## base look yaw (Node3D convention: positive turns left)
var pitch := -0.12                           ## base look pitch (positive looks up)
var recoil_pitch := 0.0                      ## extra aim offset from the rifle kick, recovers by itself
var recoil_yaw := 0.0
var pivot_y_offset := 0.0                    ## the player sets this while smoothing a step so the camera does not pop
var mouse_sensitivity := 1.0
var free_look := 0.0                         ## seconds left of manual look (the vehicle chase camera waits)

var follow_target: Node3D:
	get:
		return _follow
	set(v):
		_set_follow_target(v)
var mode: StringName = &"foot":
	get:
		return _mode
	set(v):
		_set_mode(v)

var _follow: Node3D
var _mode: StringName = &"foot"
var _player: Player
var _pos_prev := Vector3.ZERO
var _pos_cur := Vector3.ZERO
var _follow_speed := 0.0
var _ads := Vector2.ZERO                     ## spring state (value, velocity)
var _sprint := 0.0
var _mode_mix := 0.0
var _orbit_w := 0.0
var _dead_w := 0.0
var _fov := FOV_HIP
var _fov_punch := 0.0
var _punch := 0.0                            ## visual-only backwards camera punch, metres
var _bump := 0.0                             ## landing dip, metres
var _bump_v := 0.0
var _since_kick := 99.0
var _roll := 0.0
var _bob_t := 0.0
var _shake_t := 0.0
var _ratio := 1.0                            ## fraction of the arm that is free of walls (smoothed: instant in, eased out)
var _pivot_pos := Vector3.ZERO


func _ready() -> void:
	top_level = true
	_player = get_parent() as Player
	_ensure_nodes()
	arm.collision_mask = Game.L_WORLD | Game.L_VEHICLE
	camera.make_current()
	Game.camera = camera
	if _follow == null:
		_follow = _player
	_snap_follow()
	_update_view(0.0)


func _exit_tree() -> void:
	if Game.camera == camera:
		Game.camera = null


func _ensure_nodes() -> void:
	arm = get_node_or_null("SpringArm") as SpringArm3D
	if arm == null:
		arm = SpringArm3D.new()
		arm.name = "SpringArm"
		add_child(arm)
	if arm.shape == null:
		var sph := SphereShape3D.new()
		sph.radius = ARM_RADIUS
		arm.shape = sph
	arm.margin = 0.05
	camera = arm.get_node_or_null("Camera") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera"
		camera.fov = FOV_HIP
		camera.near = 0.08
		camera.far = 2500.0
		arm.add_child(camera)


# ---------------------------------------------------------------------------------------------------------------------
# input and public API
# ---------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Game.is_playing():
		var rel := (event as InputEventMouseMotion).relative
		rel = rel.clamp(Vector2(-MOUSE_SPIKE_PX, -MOUSE_SPIKE_PX), Vector2(MOUSE_SPIKE_PX, MOUSE_SPIKE_PX))
		var k := MOUSE_SENS * mouse_sensitivity * lerpf(1.0, ADS_MOUSE_SCALE, clampf(_ads.x, 0.0, 1.0))
		add_look(rel.x * k, rel.y * k)


## Turn the view by screen-space deltas in radians: yaw > 0 turns right, pitch > 0 looks down. Used by mouse look and the touch look zone.
## Looking against the rifle kick first removes the kick, so compensating never overshoots when the view settles.
func add_look(d_yaw: float, d_pitch: float) -> void:
	var turn := -d_yaw                       # Node3D convention: positive = left
	if recoil_yaw != 0.0 and turn * recoil_yaw < 0.0:
		var absorbed := minf(absf(recoil_yaw), absf(turn)) * signf(turn)
		recoil_yaw += absorbed
		turn -= absorbed
	yaw += turn
	var up := -d_pitch
	if up < 0.0 and recoil_pitch > 0.0:
		var absorbed := minf(recoil_pitch, -up)
		recoil_pitch -= absorbed
		up += absorbed
	pitch = clampf(pitch + up, PITCH_MIN, PITCH_MAX)
	if d_yaw != 0.0 or d_pitch != 0.0:
		free_look = FREE_LOOK_TIME


## Rifle kick: up (radians, positive tilts the view up) and left. Recovers after RECOIL_DELAY.
func kick(up: float, left := 0.0) -> void:
	recoil_pitch = minf(recoil_pitch + up, RECOIL_MAX)
	recoil_yaw = clampf(recoil_yaw + left, -RECOIL_YAW_MAX, RECOIL_YAW_MAX)
	_since_kick = 0.0


## Visual-only thump: the camera is pushed back by `amount` metres and the FOV opens a hair. Does not move the aim.
func punch(amount: float) -> void:
	_punch = minf(_punch + amount, 0.1)
	_fov_punch = minf(_fov_punch + amount * 16.0, 4.0)


## FOV kick in degrees (teleports, explosions), decays by itself.
func punch_fov(degrees: float) -> void:
	_fov_punch = minf(_fov_punch + degrees, 16.0)


## Landing dip: strength 0..1.
func bump(strength: float) -> void:
	_bump_v -= clampf(strength, 0.0, 1.0) * 2.4


## Put the view in a given look direction at once (spawn, respawn).
func reset_view(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = new_pitch
	recoil_pitch = 0.0
	recoil_yaw = 0.0
	free_look = 0.0
	_punch = 0.0
	_fov_punch = 0.0
	_bump = 0.0
	_bump_v = 0.0
	_roll = 0.0
	_ads = Vector2.ZERO
	_ratio = 1.0
	snap()


## Jump the camera to where it belongs, with no smoothing (teleport, entering a vehicle).
func snap() -> void:
	_snap_follow()
	_ratio = 1.0
	_update_view(0.0)


## Turn the look angles toward a world point without touching anything else: the camera ray, from where the camera sits now, passes through it.
## Scripted cameras and the visual bot call this every frame; the smoothing of FOV and zoom keeps running.
func look_at_point(point: Vector3) -> void:
	for i in 4:
		var yp := PlayerUtil.yaw_pitch_of(point - _camera_rest_position())
		yaw = yp.x
		pitch = clampf(yp.y, PITCH_MIN, PITCH_MAX)
	recoil_pitch = 0.0
	recoil_yaw = 0.0


## look_at_point() and an immediate refresh of the camera (tests that fire right afterwards).
func aim_at(point: Vector3) -> void:
	look_at_point(point)
	_update_view(0.0)


func get_pivot_position() -> Vector3:
	return _pivot_pos


## The rendered camera's forward vector (what the crosshair points along).
func get_aim_forward() -> Vector3:
	return -camera.global_basis.z


## Yaw the body should face: the look yaw including the rifle kick.
func get_aim_yaw() -> float:
	return yaw + recoil_yaw


func get_aim_pitch() -> float:
	return pitch + recoil_pitch


func is_obstructed() -> bool:
	return _ratio < 0.97


# ---------------------------------------------------------------------------------------------------------------------
# follow target / mode
# ---------------------------------------------------------------------------------------------------------------------

func _set_follow_target(v: Node3D) -> void:
	_follow = v
	if arm != null:
		arm.clear_excluded_objects()
		if _mode == &"vehicle" and v is CollisionObject3D:
			arm.add_excluded_object((v as CollisionObject3D).get_rid())
		_snap_follow()


func _set_mode(m: StringName) -> void:
	if m == _mode:
		return
	_mode = m
	free_look = 0.0
	if arm != null:
		arm.clear_excluded_objects()
		if m == &"vehicle" and _follow is CollisionObject3D:
			arm.add_excluded_object((_follow as CollisionObject3D).get_rid())
	mode_changed.emit(m)


func _snap_follow() -> void:
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		_pos_cur = _follow.global_position
	_pos_prev = _pos_cur
	_follow_speed = 0.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_follow) or not _follow.is_inside_tree():
		return
	var p := _follow.global_position
	if p.distance_squared_to(_pos_cur) > 40000.0:        # more than 200 m in a tick: a teleport, do not smear the camera across the city
		_pos_prev = p
	else:
		_pos_prev = _pos_cur
	_follow_speed = _pos_prev.distance_to(p) / maxf(delta, 0.0001)
	_pos_cur = p


# ---------------------------------------------------------------------------------------------------------------------
# per-frame view
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_view(minf(delta, 0.1))


func _vehicle_heading() -> float:
	if not is_instance_valid(_follow):
		return yaw
	return PlayerUtil.yaw_of(-_follow.global_transform.basis.z)


func _vehicle_speed() -> float:
	if is_instance_valid(_follow):
		var s: Variant = _follow.get(&"speed")
		if s is float:
			return s
	return _follow_speed


## The camera position the current look angles give without any collision, used by aim_at().
func _camera_rest_position() -> Vector3:
	var ads_s := clampf(_ads.x, 0.0, 1.0)
	var dist := lerpf(HIP_DIST, ADS_DIST, ads_s)
	var shoulder := lerpf(HIP_SHOULDER, ADS_SHOULDER, ads_s)
	var base := _pos_cur
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		base = _follow.global_position
	var b := Basis.from_euler(Vector3(pitch + recoil_pitch, yaw + recoil_yaw, 0.0), EULER_ORDER_YXZ)
	return base + Vector3(0.0, EYE_HEIGHT, 0.0) + b * Vector3(shoulder, 0.0, dist)


func _update_view(dt: float) -> void:
	var state := Game.state
	var playing := state == &"play"
	var drv := _mode == &"vehicle"

	# --- what the player is doing (a pause freezes the view as it is, it does not zoom out)
	var live := playing or state == &"paused"
	var aiming := live and not drv and _player != null and _player.aiming
	var sprinting := live and not drv and _player != null and _player.sprinting
	_ads = PlayerUtil.spring(_ads, 1.0 if aiming else 0.0, ADS_OMEGA, dt)
	var ads_s := clampf(_ads.x, 0.0, 1.0)
	_sprint = PlayerUtil.damp(_sprint, 1.0 if sprinting else 0.0, 7.0, dt)
	_mode_mix = PlayerUtil.damp(_mode_mix, 1.0 if drv else 0.0, 4.0, dt)
	var orbit_on := state == &"menu" or state == &"win"
	var dead_on := state == &"dead"
	_orbit_w = PlayerUtil.damp(_orbit_w, 1.0 if orbit_on else 0.0, 1.8 if orbit_on else 4.5, dt)    # drift in slowly, snap back to gameplay quickly
	_dead_w = PlayerUtil.damp(_dead_w, 1.0 if dead_on else 0.0, 2.0 if dead_on else 4.5, dt)
	free_look = maxf(0.0, free_look - dt)

	# --- vehicle chase: the view eases toward the heading unless the player is looking around
	var veh_speed := 0.0
	if drv:
		veh_speed = _vehicle_speed()
		if playing and free_look <= 0.0:
			yaw = PlayerUtil.damp_angle(yaw, _vehicle_heading(), 3.0 if absf(veh_speed) > 2.0 else 0.8, dt)
			pitch = PlayerUtil.damp(pitch, -0.2, 3.0, dt)

	# --- cinematic drift (title screen, victory, death)
	if _orbit_w > 0.001 or _dead_w > 0.001:
		yaw += (ORBIT_RATE * _orbit_w + DEAD_RATE * _dead_w) * dt
		var pt := ORBIT_PITCH * _orbit_w + DEAD_PITCH * _dead_w
		pitch = lerpf(pitch, pt, 1.0 - exp(-2.5 * dt * maxf(_orbit_w, _dead_w)))

	# --- rifle kick recovery
	_since_kick += dt
	if _since_kick > RECOIL_DELAY:
		recoil_pitch = PlayerUtil.damp(recoil_pitch, 0.0, RECOIL_RATE, dt)
		recoil_yaw = PlayerUtil.damp(recoil_yaw, 0.0, RECOIL_RATE * 1.3, dt)
		if recoil_pitch < 0.00005:
			recoil_pitch = 0.0
		if absf(recoil_yaw) < 0.00005:
			recoil_yaw = 0.0

	# --- distance, shoulder, height and FOV for the current situation
	var foot_dist := lerpf(HIP_DIST, ADS_DIST, ads_s)
	var foot_shoulder := lerpf(HIP_SHOULDER, ADS_SHOULDER, ads_s)
	var foot_fov := lerpf(lerpf(FOV_HIP, FOV_SPRINT, _sprint), FOV_ADS, ads_s)
	var veh_dist := VEH_DIST + clampf(absf(veh_speed) * 0.04, 0.0, 1.2)
	var veh_fov := VEH_FOV + minf(18.0, absf(veh_speed) * 0.5)
	var dist := lerpf(foot_dist, veh_dist, _mode_mix)
	var shoulder := lerpf(foot_shoulder, 0.0, _mode_mix)
	var height := lerpf(EYE_HEIGHT, VEH_HEIGHT, _mode_mix)
	var fov_target := lerpf(foot_fov, veh_fov, _mode_mix)
	if _orbit_w > 0.001:
		dist = lerpf(dist, ORBIT_DIST, _orbit_w)
		shoulder = lerpf(shoulder, 0.0, _orbit_w)
		height = lerpf(height, ORBIT_HEIGHT, _orbit_w)
		fov_target = lerpf(fov_target, ORBIT_FOV, _orbit_w)
	if _dead_w > 0.001:
		dist = lerpf(dist, DEAD_DIST, _dead_w)
		shoulder = lerpf(shoulder, 0.3, _dead_w)
		height = lerpf(height, DEAD_HEIGHT, _dead_w)
		fov_target = lerpf(fov_target, DEAD_FOV, _dead_w)
	if dt <= 0.0:
		_fov = fov_target
	else:
		_fov = PlayerUtil.damp(_fov, fov_target, 10.0, dt)
	_fov_punch = PlayerUtil.damp(_fov_punch, 0.0, 9.0, dt)
	_punch = PlayerUtil.damp(_punch, 0.0, 16.0, dt)
	camera.fov = _fov + _fov_punch

	# --- landing dip (a damped spring)
	_bump_v += (-_bump * 220.0 - _bump_v * 18.0) * dt
	_bump += _bump_v * dt

	# --- pivot: the interpolated target plus the eye height
	var base := _pos_cur
	if dt > 0.0:
		base = _pos_prev.lerp(_pos_cur, Engine.get_physics_interpolation_fraction())
	base.y += pivot_y_offset
	_pivot_pos = base + Vector3(0.0, height, 0.0)
	var yaw_t := yaw + recoil_yaw
	var pitch_t := clampf(pitch + recoil_pitch, -1.3, 1.25)
	var aim_basis := Basis.from_euler(Vector3(pitch_t, yaw_t, 0.0), EULER_ORDER_YXZ)
	global_transform = Transform3D(aim_basis, _pivot_pos)

	# --- spring arm: points from the head to the camera including the shoulder offset, so a wall beside the player pulls the camera in too
	var a := atan2(shoulder, dist)
	arm.rotation = Vector3(0.0, a, 0.0)
	arm.spring_length = sqrt(shoulder * shoulder + dist * dist)
	arm.notification(Node.NOTIFICATION_INTERNAL_PHYSICS_PROCESS)
	var free_ratio := clampf(arm.get_hit_length() / maxf(arm.spring_length, 0.001), 0.0, 1.0)
	if free_ratio < _ratio or dt <= 0.0:
		_ratio = free_ratio                  # walls pull the camera in at once
	else:
		_ratio = PlayerUtil.damp(_ratio, free_ratio, 5.0, dt)    # and let it out gently
	var cam_pos := _pivot_pos + (aim_basis * Vector3(sin(a), 0.0, cos(a))) * (arm.spring_length * _ratio)

	# --- roll, bob, shake
	var strafe := 0.0
	var speed_h := 0.0
	if _player != null and playing and not drv:
		strafe = _player.input_strafe
		speed_h = Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob_t += dt * (3.0 + speed_h * 1.1)
	var roll_target := -strafe * 0.014 * (1.0 - ads_s) + sin(_bob_t * 0.5) * 0.0035 * _sprint
	_roll = PlayerUtil.damp(_roll, roll_target, 8.0, dt)
	var shake := FX.shake_amount
	var s_off := Vector3.ZERO
	var s_rot := Vector3.ZERO
	if shake > 0.001:
		_shake_t += dt
		var amp := shake * 0.17
		s_off = Vector3(PlayerUtil.wobble(_shake_t, 31.0, 47.0, 0.3), PlayerUtil.wobble(_shake_t, 37.0, 53.0, 1.7), PlayerUtil.wobble(_shake_t, 29.0, 43.0, 3.1)) * amp
		s_rot = Vector3(PlayerUtil.wobble(_shake_t, 33.0, 51.0, 2.2), PlayerUtil.wobble(_shake_t, 39.0, 49.0, 4.1), PlayerUtil.wobble(_shake_t, 27.0, 41.0, 5.3)) * (shake * 0.018)
	var bob_y := sin(_bob_t) * 0.012 * minf(1.0, speed_h / 6.0) * (1.0 - ads_s * 0.7)
	var cam_basis := Basis.from_euler(Vector3(pitch_t + s_rot.x, yaw_t + s_rot.y, _roll + s_rot.z), EULER_ORDER_YXZ)
	cam_pos += cam_basis * Vector3(s_off.x, s_off.y + bob_y + _bump, s_off.z + _punch)
	cam_pos.y = maxf(cam_pos.y, base.y + 0.25)          # never below the feet, even with a pitched-up low camera
	camera.global_transform = Transform3D(cam_basis, cam_pos)
