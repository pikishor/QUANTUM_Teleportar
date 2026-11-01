class_name CameraRig
extends Node3D
## Third-person over-the-shoulder camera: shoulder offset, ADS zoom (critically damped spring), sprint FOV kick, weighty recoil with a recovery
## curve, shake from FX.shake_amount, landing dip, SpringArm3D (sphere shape) pull-in against walls, and a chase mode for driven vehicles.
## Sets Game.camera.
##
## Smoothness. On foot the target (the player) moves in physics ticks and draws itself from the interpolated tick position, so the rig samples that
## position every tick and renders the camera from the same interpolation (Engine.get_physics_interpolation_fraction()): no judder at any refresh rate.
## In vehicle mode the rig instead reads the vehicle node's global_position every rendered frame, with no interpolation of its own. A vehicle that is
## moved once per physics tick then stays exactly where it is on screen (camera and car step together), whatever the tree order is; interpolating the
## camera between two ticks while the car is drawn at its newest tick makes the car saw back and forth by one tick step (0.5 m at 30 m/s).
## The rig runs late (process_priority, process_physics_priority) so a vehicle that moves in _process or _physics_process is read after it has moved,
## and in vehicle mode the camera is also shifted by the vehicle's displacement inside the physics tick that moved it: anything that reads the camera
## between that tick and the next rendered frame (a raycast, get_aim()) sees camera and vehicle in lockstep too.
## Look angles change per rendered frame. The rig is top_level and drives itself in _process.
## The SpringArm3D solves in the physics tick by itself; to avoid a tick of lag it is solved once more per rendered frame here by sending
## it the internal physics notification (its solver is a pure function of its current global transform).
## The arm never gets shorter than MIN_ARM: with a wall right behind the player the camera stops short of the head instead of sinking into the helmet.
## Squeezed that close, the camera also slides sideways (to the shoulder that has room, found with two short rays) and a little up, so the
## character leaves the crosshair's line instead of filling the middle of the screen. Vehicle mode has no such slide.
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
const FOV_HIP := 92.0          # horizontal degrees (keep_aspect = KEEP_WIDTH): the same view on 16:9 tablets and 20:9 phones
const FOV_SPRINT := 100.0
const FOV_ADS := 62.0
const VEH_DIST := 7.5
const VEH_HEIGHT := 1.6
const VEH_FOV := 92.0
const ARM_RADIUS := 0.22
const FADE_START := 1.2                      ## the hero fades out smoothly when the camera is closer than this (metres from the head) ...
const FADE_END := 0.9                        ## ... and is fully hidden at this distance
const MIN_ARM := 0.85                        ## shortest camera arm in metres, however close the wall is (the prototype's floor was 0.5 m)
const RIG_PRIORITY := 100                    ## process priority: after the nodes it follows (lower numbers run first)
const INTERIOR_ARM_SCALE := 0.68             ## inside a generated interior (scripts/interiors/) the on-foot arm is this fraction of its length ...
const INTERIOR_MIN_ARM := 0.3                ## ... and may shrink to this: the hero capsule (0.35 m) keeps the camera in front of the wall behind him, the hero fades out when the camera is that close
const SQUEEZE_START := 2.0                   ## an arm shorter than this (metres) starts to slide the camera toward a free shoulder ...
const SQUEEZE_SIDE := 0.5                    ## ... by this much sideways at full squeeze (arm at the MIN_ARM floor) ...
const SQUEEZE_UP := 0.1                      ## ... and this much up
const SIDE_PROBE := 0.95                     ## a wall closer than this beside the head means that side is not free
const ADS_OMEGA := 17.0                      ## spring frequency of the aim transition: settles in about a quarter second

# cinematic poses
const ORBIT_DIST := 4.4
const ORBIT_HEIGHT := 1.35
const ORBIT_FOV := 78.0
const ORBIT_PITCH := -0.05
const ORBIT_RATE := 0.07                     ## radians per second
const DEAD_DIST := 5.4                       ## the death camera: behind and above the fallen body, looking past it at what killed it
const DEAD_HEIGHT := 1.1
const DEAD_FOV := 86.0
const DEAD_PITCH := -0.16                    ## shallow: the horizon and the attacker stay in the picture
const DEAD_RATE := 0.03                      ## free orbit (no known killer), radians per second
const DEAD_ARC := 0.5                        ## the kill camera sweeps from -ARC to +ARC around the line to the killer ...
const DEAD_ARC_TIME := 3.2                   ## ... over this many seconds of game time (slow motion makes it a slow, short orbit)
const DEAD_KILLER_AGE := 4.0                 ## a hit older than this (seconds) is not "the killer"

# shake caps: the camera never moves more than this, however many hits and blasts pile up
const CINE_TTL := 0.25                       ## a scripted camera pose lapses by itself this many real seconds after the last cine_set(): nothing can leave the view stuck

const SHAKE_MAX_OFF := 0.2                   ## metres
const SHAKE_MAX_ROT := 0.03                  ## radians (about 1.7 degrees)

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
var hero_fade := 0.0                         ## 0..1: how far the hero is faded out because the camera is closer than FADE_START
var _props_excluded := false

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
var _dead_age := 0.0                         ## seconds of game time in the dead state
var ads_fov := FOV_ADS        ## degrees at full ADS for the weapon in hand (the Pulse Lance zooms like a sniper scope)
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
var _last_base := Vector3.ZERO               ## the followed position the last view update was built on (vehicle mode: for the in-tick shift)
var _swing := 0.0                            ## sideways slide of the camera while squeezed against a wall (metres, + is to the right), eased
var _side := 1.0                             ## the shoulder the slide goes to: +1 right, -1 left, 0 none (kept while it stays free)
var _probe := PhysicsRayQueryParameters3D.new()
var _cine_ttl := 0.0                         ## > 0 while a cinematic drives the camera (scripts/cinematics/cinematics.gd calls cine_set() every frame)
var _cine_xf := Transform3D.IDENTITY
var _cine_fov := 70.0


func _ready() -> void:
	top_level = true
	process_priority = RIG_PRIORITY
	process_physics_priority = RIG_PRIORITY
	_player = get_parent() as Player
	_ensure_nodes()
	arm.collision_mask = Game.L_WORLD              # buildings and solid walls only: cars, pedestrians and the pooled prop colliders never shorten the arm (see _exclude_props)
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
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	# The rig solves the arm once per rendered frame (see _process); the arm's own per-physics-tick solve would move the camera to the raw arm end
	# and the weapon would aim from there whenever a frame holds two physics ticks (30 fps phones), so it is switched off.
	arm.set_physics_process_internal(false)


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
	_dead_w = 0.0                            # a respawn or a new sector never starts inside the death or title camera
	_dead_age = 0.0
	_orbit_w = 0.0
	snap()


## Hand the camera back to the player on foot (the followed vehicle is gone, hidden or no longer the player's): foot mode, following the player, snapped.
func recover_to_player() -> void:
	if _player != null and _player.vehicle != null:
		_player.vehicle = null               # runs the player's own foot-state restore: body shown, collider back, camera foot mode
	if arm != null:
		arm.clear_excluded_objects()
		_props_excluded = false
	_mode = &"foot"
	_mode_mix = 0.0
	_follow = _player
	free_look = 0.0
	_snap_follow()
	_ratio = 1.0
	mode_changed.emit(&"foot")


## Cinematic camera: from now on the rendered camera sits at `xf` with horizontal FOV `fov` (everything else keeps running underneath: look angles, spring, shake).
## Must be called every frame; the pose lapses CINE_TTL real seconds after the last call, so a cinematic that ends, errors or is freed hands the view back by itself.
func cine_set(xf: Transform3D, fov: float) -> void:
	_cine_xf = xf
	_cine_fov = fov
	_cine_ttl = CINE_TTL


## Hand the camera back to gameplay now (the gameplay view is already current underneath, so nothing is smoothed or snapped).
func cine_clear() -> void:
	_cine_ttl = 0.0


func is_cinematic() -> bool:
	return _cine_ttl > 0.0


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


## 0 on the hip, 1 fully aimed down sights (the smoothed zoom), for a HUD that wants to follow the aim transition.
func get_ads_amount() -> float:
	return clampf(_ads.x, 0.0, 1.0)


# ---------------------------------------------------------------------------------------------------------------------
# follow target / mode
# ---------------------------------------------------------------------------------------------------------------------

func _set_follow_target(v: Node3D) -> void:
	_follow = v
	if arm != null:
		arm.clear_excluded_objects()
		_props_excluded = false
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
		_props_excluded = false
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
	if _mode == &"vehicle":
		var shift := p + Vector3(0.0, pivot_y_offset, 0.0) - _last_base
		if shift != Vector3.ZERO:
			global_position += shift                   # the arm and the camera are children of the rig: they travel with it
			_pivot_pos += shift
			_last_base += shift


# ---------------------------------------------------------------------------------------------------------------------
# per-frame view
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_view(minf(delta, 0.1))


## Yaw that looks from the fallen player toward the last attacker, or NAN when the hit is too old or unknown (a fall, an unknown source).
func _killer_yaw() -> float:
	if _player == null or PlayerUtil.now() - _player.last_hurt_time > DEAD_KILLER_AGE:
		return NAN
	var from := _player.last_hurt_from
	if not from.is_finite() or from == Vector3.ZERO:
		return NAN
	var d := from - _player.global_position
	d.y = 0.0
	if d.length() < 1.0:
		return NAN
	return PlayerUtil.yaw_of(d)


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


## The shoulder the camera should slide to while squeezed: +1 right (preferred), -1 left when the right side is walled in, 0 when both are.
## Two short rays from the head; a side that was free stays free until the wall is clearly closer (no flicker at the boundary).
func _free_side(right: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	_probe.collision_mask = Game.L_WORLD
	var right_ok := not _blocked(space, right, SIDE_PROBE - (0.2 if _side > 0.0 else 0.0))
	if right_ok:
		_side = 1.0
	elif not _blocked(space, -right, SIDE_PROBE - (0.2 if _side < 0.0 else 0.0)):
		_side = -1.0
	else:
		_side = 0.0
	return _side


func _blocked(space: PhysicsDirectSpaceState3D, dir: Vector3, length: float) -> bool:
	_probe.from = _pivot_pos
	_probe.to = _pivot_pos + dir * length
	return not space.intersect_ray(_probe).is_empty()


## The pooled prop colliders (lamp poles, dumpsters, kiosks, roof clutter) are world bodies for walking, shooting and blinking but never shorten the camera arm.
func _exclude_props() -> void:
	if arm == null or not is_instance_valid(Game.world) or not Game.world.has_method(&"prop_colliders"):
		return
	var pool = Game.world.call(&"prop_colliders")
	if pool == null:
		return
	_props_excluded = true
	for b: StaticBody3D in pool.bodies:
		arm.add_excluded_object(b.get_rid())


## Smooth hero fade for a camera that is close to the head (a wall at the back, a corner): 0 at FADE_START metres, 1 at FADE_END.
func _update_fade(cam_dist: float, driving: bool) -> void:
	var f := 0.0 if driving else clampf((FADE_START - cam_dist) / (FADE_START - FADE_END), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	if absf(f - hero_fade) < 0.002 and f != 1.0 and f != 0.0:
		return
	hero_fade = f
	if _player != null and _player.body != null and _player.body.has_method(&"set_fade"):
		_player.body.call(&"set_fade", f)


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


## The camera must never keep chasing something that is gone: a vehicle that was freed, deactivated, hidden or exploded, or that the player no longer sits in.
func _check_follow() -> void:
	if _player == null:
		return
	if _mode == &"vehicle":
		var bad := not is_instance_valid(_follow) or not _follow.is_inside_tree() or _player.vehicle == null
		if not bad:
			bad = not _follow.visible or _follow.get(&"active") == false or _follow.get(&"dead") == true
		if bad:
			recover_to_player()
	elif not is_instance_valid(_follow) or _follow != _player:
		_follow = _player
		_snap_follow()


func _update_view(dt: float) -> void:
	_check_follow()
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
	_dead_age = _dead_age + dt if dead_on else 0.0
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
		var killer := _killer_yaw() if dead_on else NAN
		if is_nan(killer):
			yaw += (ORBIT_RATE * _orbit_w + DEAD_RATE * _dead_w) * dt
		else:                                # sweep slowly around the line to whatever killed the player, so it stays in the picture
			var arc := lerpf(-DEAD_ARC, DEAD_ARC, clampf(_dead_age / DEAD_ARC_TIME, 0.0, 1.0))
			yaw = PlayerUtil.damp_angle(yaw, killer + arc, 3.0, dt)
			yaw += ORBIT_RATE * _orbit_w * dt
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
	var foot_dist := lerpf(HIP_DIST, ADS_DIST, ads_s) * (INTERIOR_ARM_SCALE if InteriorSpace.active else 1.0)      # a shorter arm in the tight rooms of a generated interior
	var foot_shoulder := lerpf(HIP_SHOULDER, ADS_SHOULDER, ads_s)
	var foot_fov := lerpf(lerpf(FOV_HIP, FOV_SPRINT, _sprint), ads_fov, ads_s)
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
	# Sub-stepped: one explicit step of this stiff spring blows up at 10 fps (dt 0.1) and flings the camera thousands of metres away ("the world is gone" on a
	# phone that drops frames in a firefight); at most 8 ms per step is stable for any frame time. Clamped as a last line of defence.
	var left := dt
	while left > 0.0:
		var h := minf(left, 0.008)
		_bump_v += (-_bump * 220.0 - _bump_v * 18.0) * h
		_bump += _bump_v * h
		left -= h
	_bump = clampf(_bump, -0.6, 0.6)
	_bump_v = clampf(_bump_v, -9.0, 9.0)

	# --- pivot: the target plus the eye height. A vehicle is followed at its real position of this very frame (lockstep, see the header),
	# the player at the interpolated physics position.
	var base := _pos_cur
	if drv and is_instance_valid(_follow) and _follow.is_inside_tree():
		base = _follow.global_position
	elif dt > 0.0:
		base = _pos_prev.lerp(_pos_cur, Engine.get_physics_interpolation_fraction())
	base.y += pivot_y_offset
	_last_base = base
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
	var arm_len := maxf(arm.spring_length, 0.001)
	var arm_free := arm.get_hit_length()
	var free_ratio := clampf(arm_free / arm_len, minf(1.0, (INTERIOR_MIN_ARM if InteriorSpace.active else MIN_ARM) / arm_len), 1.0)     # never closer than MIN_ARM, even inside a wall
	if free_ratio < _ratio or dt <= 0.0:
		_ratio = free_ratio                  # walls pull the camera in at once
	else:
		_ratio = PlayerUtil.damp(_ratio, free_ratio, 5.0, dt)    # and let it out gently
	var cam_pos := _pivot_pos + (aim_basis * Vector3(sin(a), 0.0, cos(a))) * (arm.spring_length * _ratio)

	_update_fade(arm.spring_length * _ratio, drv)
	if not _props_excluded:
		_exclude_props()

	# --- squeezed against a wall: slide toward the free shoulder and a little up (see the header)
	var squeeze := 0.0 if drv else clampf((SQUEEZE_START - arm_free) / (SQUEEZE_START - MIN_ARM), 0.0, 1.0)
	var swing_target := 0.0
	if squeeze > 0.0 and dt > 0.0:
		swing_target = squeeze * SQUEEZE_SIDE * _free_side(aim_basis.x)
	_swing = swing_target if dt <= 0.0 else PlayerUtil.damp(_swing, swing_target, 9.0, dt)
	if absf(_swing) > 0.001:
		cam_pos += aim_basis.x * _swing + aim_basis.y * (absf(_swing) / SQUEEZE_SIDE * SQUEEZE_UP)

	# --- roll, bob, shake
	var strafe := 0.0
	var speed_h := 0.0
	if _player != null and playing and not drv:
		strafe = _player.input_strafe
		speed_h = Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob_t += dt * (3.0 + speed_h * 1.1)
	var roll_target := -strafe * 0.014 * (1.0 - ads_s) + sin(_bob_t * 0.5) * 0.0035 * _sprint
	_roll = PlayerUtil.damp(_roll, roll_target, 8.0, dt)
	var shake := clampf(FX.shake_amount, 0.0, 1.0)
	var s_off := Vector3.ZERO
	var s_rot := Vector3.ZERO
	if shake > 0.001:
		_shake_t += dt
		var amp := minf(shake * 0.17, SHAKE_MAX_OFF)
		s_off = Vector3(PlayerUtil.wobble(_shake_t, 31.0, 47.0, 0.3), PlayerUtil.wobble(_shake_t, 37.0, 53.0, 1.7), PlayerUtil.wobble(_shake_t, 29.0, 43.0, 3.1)) * amp
		s_rot = Vector3(PlayerUtil.wobble(_shake_t, 33.0, 51.0, 2.2), PlayerUtil.wobble(_shake_t, 39.0, 49.0, 4.1), PlayerUtil.wobble(_shake_t, 27.0, 41.0, 5.3)) * minf(shake * 0.018, SHAKE_MAX_ROT)
	var bob_y := sin(_bob_t) * 0.012 * minf(1.0, speed_h / 6.0) * (1.0 - ads_s * 0.7)
	var cam_basis := Basis.from_euler(Vector3(pitch_t + s_rot.x, yaw_t + s_rot.y, _roll + s_rot.z), EULER_ORDER_YXZ)
	cam_pos += cam_basis * Vector3(s_off.x, s_off.y + bob_y + _bump, s_off.z + _punch)
	cam_pos.y = maxf(cam_pos.y, base.y + 0.25)          # never below the feet, even with a pitched-up low camera
	if not cam_pos.is_finite():                         # a broken position must never freeze the picture: fall back to the pivot
		cam_pos = _pivot_pos + Vector3(0.0, 1.0, 3.0)
		if not cam_pos.is_finite():
			cam_pos = Vector3(0.0, 3.0, 5.0)
	camera.global_transform = Transform3D(cam_basis, cam_pos)
	if _cine_ttl > 0.0:
		_cine_ttl = maxf(_cine_ttl - dt / maxf(Engine.time_scale, 0.05), 0.0) if dt > 0.0 else _cine_ttl
		if _cine_xf.origin.is_finite() and _cine_xf.basis.is_finite():
			camera.global_transform = _cine_xf
			camera.fov = clampf(_cine_fov, 20.0, 120.0)
