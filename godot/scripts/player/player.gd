class_name Player
extends CharacterBody3D
## The player: third-person over-the-shoulder shooter, strafe-style (the body faces the aim). Contract: ARCHITECTURE.md "player".
##
## Children (scenes/player.tscn): Collision (capsule), CameraRig (+ SpringArm + Camera), Body (PlayerBody), Weapon (PlayerWeapon),
## Decals (ImpactDecals), Sparks (ImpactSparks). Optional child `Quantum` when res://scripts/quantum/quantum.gd exists, exposed as `quantum`.
##
## Movement is ported from src/player.js (walk 6.2 m/s, sprint x1.6, aim 3.4, jump 7.6 m/s, gravity 22) with smooth exponential acceleration,
## coyote time, jump buffering, step-up over curbs and a void rescue. Physics runs in _physics_process; everything the player SEES (body, camera)
## is rendered from the interpolated physics position in _process, so nothing judders.
## Outside the play state nothing is driven (no input, no regeneration), but dead, victory and title still run gravity and friction (_settle_tick):
## a body killed in mid-air falls to the ground and one killed at a sprint slides to a stop. A pause freezes everything, the pose included.
##
## Time base of last_hit_time / last_hurt_time: PlayerUtil.now() = Time.get_ticks_msec() / 1000.
## HUD data: hp max_hp energy max_energy ammo mag reloading aiming sprinting spread (current total half angle in radians: aim / hip base +
## sustained-fire bloom + movement; the crosshair can map it directly) vehicle last_hit_time last_hit_kill last_hit_crit invuln; signals hurt, fired,
## hit_confirmed.

signal hurt(amount: float)
signal fired
signal hit_confirmed(kill: bool, crit: bool)

const WALK_SPEED := 6.2
const AIM_SPEED := 3.4
const SPRINT_MULT := 1.6
const JUMP_SPEED := 7.6
const GRAVITY := 22.0
const MAX_FALL_SPEED := 40.0
const GROUND_ACCEL := 14.0                   ## exponential approach rates (1/s), src/player.js
const AIR_ACCEL := 4.0
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const STEP_HEIGHT := 0.38
const REGEN_DELAY := 5.0
const REGEN_RATE := 14.0
const ENERGY_REGEN := 8.0
const ENERGY_REGEN_DRIVING := 3.0
const SPAWN_INVULNERABILITY := 1.5
const VEHICLE_DAMAGE_SHARE := 0.6            ## damage taken while driving goes to the vehicle at this factor
const SPAWN_YAW := -PI * 0.5                 ## face +X, down the main avenue
const SPAWN_PITCH := -0.12
const VOID_Y := -60.0
const SETTLE_FRICTION := 9.0                 ## 1/s: horizontal speed of a body that is not driven (dead, victory) dies away like a slide
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.8

## Where the optional Quantum module lives (ARCHITECTURE.md). A variable only so tests can point it at a stand-in.
static var quantum_path := "res://scripts/quantum/quantum.gd"

var max_hp := 100.0
var max_energy := 100.0
var hp := 100.0:
	set(v):
		hp = clampf(v, 0.0, max_hp)
var energy := 100.0:
	set(v):
		energy = clampf(v, 0.0, max_energy)

var ammo: int:
	get:
		return weapon.ammo if weapon != null else 0
	set(v):
		if weapon != null:
			weapon.ammo = clampi(v, 0, weapon.mag)
var mag: int:
	get:
		return weapon.mag if weapon != null else PlayerWeapon.MAG_SIZE
	set(v):
		if weapon != null:
			weapon.mag = maxi(1, v)
var reloading: bool:
	get:
		return weapon != null and weapon.reload_t > 0.0
var spread: float:
	get:
		return weapon.spread if weapon != null else PlayerWeapon.SPREAD_HIP

var aiming := false
var sprinting := false
## Seconds since the feet last touched the ground (0 on the ground). The body pose waits a moment before it shows "airborne", so rolling
## off a curb does not flicker the legs.
var air_time := 0.0
## Speed multiplier from abilities (Quantum superposition sets 1.3). Values >= 1 are a multiplier; values below 1 are read as a bonus (0.3 = +30 %).
var speed_boost := 1.0
## -1..1, the sideways input this tick (camera lean).
var input_strafe := 0.0
## The move stick / keys this tick (x right, y back, 0..1 long): the body uses its length to start the step off.
var input_move := Vector2.ZERO
var invuln := 0.0
## Seconds since the last damage; health regenerates once it passes REGEN_DELAY.
var since_hurt := 99.0
var last_hurt_time := -100.0
var last_hurt_from := Vector3.ZERO
var last_hit_time := -100.0
var last_hit_kill := false
var last_hit_crit := false
var quantum: Node
var camera_rig: CameraRig
var body: PlayerBody
var weapon: PlayerWeapon
var decals: ImpactDecals
var sparks: ImpactSparks
## Facing of the body (Node3D.rotation.y convention); eases toward the aim yaw.
var yaw := SPAWN_YAW

## The vehicle being driven, or null on foot. Set by the vehicles module; the player then hides, follows it and the camera chases it.
## A vehicle that gets freed while it is driven (destroyed, despawned) puts the player back on foot at once.
var vehicle: Node3D:
	get:
		return _vehicle if _in_vehicle and is_instance_valid(_vehicle) else null
	set(v):
		_set_vehicle(v)

var _vehicle: Node3D
## Vehicle mode is tracked by this flag and never by `_vehicle != null`: in Godot 4.6 a freed Object compares equal to null, so a comparison cannot
## tell "no vehicle" from "the vehicle was freed" (use is_instance_valid(), which is what _vehicle_alive() does).
var _in_vehicle := false
var _dead := false
var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_was_down := false
var _reload_was_down := false
var _was_on_floor := false
## is_on_floor() only updates in move_and_slide(); after a teleport or an outside move it is stale, so the first tick must not trust it.
var _ground_known := false
var _fall_speed := 0.0
var _hit_wall := false
var _phys_prev := Vector3.ZERO
var _phys_cur := Vector3.ZERO
var _step_offset := 0.0                      ## visual drop smoothing after a step-up (metres, decays to 0)
var _kc := KinematicCollision3D.new()
var _kc2 := KinematicCollision3D.new()
var _aim_frame := -1
var _aim_cache := {}


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Game.L_PLAYER
	collision_mask = Game.L_WORLD | Game.L_VEHICLE
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	max_slides = 6
	_ensure_children()
	Game.player = self
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(_on_next_sector)
	Game.quality_changed.connect(_on_quality_changed)
	body.set_quality(Game.quality)
	camera_rig.follow_target = self
	reset()
	decals.clear()
	_attach_quantum()


func _exit_tree() -> void:
	if Game.player == self:
		Game.player = null


func _ensure_children() -> void:
	if get_node_or_null("Collision") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		var cap := CapsuleShape3D.new()
		cap.radius = CAPSULE_RADIUS
		cap.height = CAPSULE_HEIGHT
		cs.shape = cap
		cs.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
		add_child(cs)
	camera_rig = get_node_or_null("CameraRig") as CameraRig
	if camera_rig == null:
		camera_rig = CameraRig.new()
		camera_rig.name = "CameraRig"
		add_child(camera_rig)
	body = get_node_or_null("Body") as PlayerBody
	if body == null:
		body = PlayerBody.new()
		body.name = "Body"
		add_child(body)
	weapon = get_node_or_null("Weapon") as PlayerWeapon
	if weapon == null:
		weapon = PlayerWeapon.new()
		weapon.name = "Weapon"
		add_child(weapon)
	decals = get_node_or_null("Decals") as ImpactDecals
	if decals == null:
		decals = ImpactDecals.new()
		decals.name = "Decals"
		add_child(decals)
	sparks = get_node_or_null("Sparks") as ImpactSparks
	if sparks == null:
		sparks = ImpactSparks.new()
		sparks.name = "Sparks"
		add_child(sparks)
	weapon.set_effects(decals, sparks)
	if get_node_or_null("AimAssist") == null:
		var aa := AimAssist.new()
		aa.name = "AimAssist"
		add_child(aa)


## Quantum is another module's script; a missing or broken file must never break the player.
func _attach_quantum() -> void:
	if quantum != null or not ResourceLoader.exists(quantum_path):
		return
	var script := load(quantum_path) as GDScript
	if script == null or not script.can_instantiate():
		return
	quantum = script.new() as Node
	if quantum != null:
		quantum.name = "Quantum"
		add_child(quantum)


# ---------------------------------------------------------------------------------------------------------------------
# lifecycle
# ---------------------------------------------------------------------------------------------------------------------

func _on_quality_changed(level: int) -> void:
	body.set_quality(level)


func _on_next_sector() -> void:
	reset()
	decals.clear()


## Fresh state at the spawn point: full hp / energy / ammo, 1.5 s of invulnerability, foot mode, camera behind the player.
func reset() -> void:
	_set_vehicle(null)
	_dead = false
	hp = max_hp
	energy = max_energy
	weapon.reset()
	invuln = SPAWN_INVULNERABILITY
	since_hurt = 99.0
	speed_boost = 1.0
	aiming = false
	sprinting = false
	input_strafe = 0.0
	velocity = Vector3.ZERO
	global_position = Game.SPAWN
	air_time = 0.0
	_ground_known = false
	_was_on_floor = false
	_coyote = 0.0
	_jump_buffer = 0.0
	_step_offset = 0.0
	_fall_speed = 0.0
	_hit_wall = false
	yaw = SPAWN_YAW
	body.set_dead(false)
	body.reset_pose()
	camera_rig.pivot_y_offset = 0.0
	camera_rig.reset_view(SPAWN_YAW, SPAWN_PITCH)
	_snap_interpolation()
	_apply_vehicle_state()


## Instantly move to a world position (blink, scripted moves): velocity is cleared and neither the body nor the camera streaks there.
func teleport_to(pos: Vector3) -> void:
	pos = PlayerUtil.safe_spot(pos, Game.world if is_instance_valid(Game.world) else null, get_world_3d().direct_space_state if is_inside_tree() else null)   # never outside the city walls, below the floor or inside a building
	global_position = pos
	velocity = Vector3.ZERO
	_ground_known = false
	_was_on_floor = false
	_coyote = 0.0
	_step_offset = 0.0
	_snap_interpolation()
	camera_rig.pivot_y_offset = 0.0
	camera_rig.snap()
	camera_rig.punch_fov(9.0)
	_refresh_world(pos)


## The windowed city (props, skyline), the pooled prop colliders and the camera's view must follow a jump at once, not over the next frames.
func _refresh_world(pos: Vector3) -> void:
	if is_instance_valid(Game.world):
		if Game.world.has_method(&"update_streaming"):
			Game.world.call(&"update_streaming", Vector2(pos.x, pos.z), true)
		if Game.world.has_method(&"update_colliders"):
			Game.world.call(&"update_colliders", pos)


## Outside the walls, under the floor or not a number: back onto the nearest street (hp kept, a second of grace). Returns true when it moved the hero.
func rescue_if_lost() -> bool:
	if not PlayerUtil.outside_city(global_position):
		return false
	var p := global_position
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		p = Game.SPAWN
	var street := PlayerUtil.nearest_street(Vector3(clampf(p.x, -CityLayout.WALK, CityLayout.WALK), 0.0, clampf(p.z, -CityLayout.WALK, CityLayout.WALK)))
	teleport_to(street + Vector3(0.0, 0.1, 0.0))
	invuln = maxf(invuln, 1.0)
	Game.say("LOST SIGNAL · RETURNED TO THE STREET", 1.6)
	return true


func _snap_interpolation() -> void:
	_phys_prev = global_position
	_phys_cur = global_position


# ---------------------------------------------------------------------------------------------------------------------
# queries other modules use
# ---------------------------------------------------------------------------------------------------------------------

## Where enemies aim: the chest of the player, or the cabin of the vehicle being driven.
func chest_position() -> Vector3:
	if _vehicle_alive():
		return _vehicle.global_position + Vector3(0.0, 1.1, 0.0)
	return global_position + Vector3(0.0, 1.2, 0.0)


## The camera ray through the crosshair: {origin: camera position, dir: unit forward, hit: first world point along it or the far point}.
## Geometry behind the character (between the camera and the player) is ignored, like the rifle does. One dictionary per rendered frame.
func get_aim() -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame == _aim_frame and not _aim_cache.is_empty():
		return _aim_cache
	_aim_frame = frame
	var cam := camera_rig.camera
	var origin := cam.global_position
	var dir := -cam.global_basis.z
	var along := maxf(0.0, (camera_rig.get_pivot_position() - origin).dot(dir))
	var start := origin + dir * along
	var far := start + dir * PlayerWeapon.RANGE
	var q := PhysicsRayQueryParameters3D.create(start, far, Game.L_WORLD)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	_aim_cache = {"origin": origin, "dir": dir, "hit": res["position"] if not res.is_empty() else far}
	return _aim_cache


## The crosshair radius in pixels for a viewport of the given height: the current spread seen through the live camera FOV.
func spread_in_pixels(viewport_height: float) -> float:
	var half_fov := deg_to_rad(camera_rig.camera.fov) * 0.5
	return tan(spread) / tan(half_fov) * viewport_height * 0.5


func heal(v: float) -> void:
	if v > 0.0:
		hp += v


func add_energy(v: float) -> void:
	energy += v


## True once hp reached zero (until the next reset).
func is_dead() -> bool:
	return _dead


## damage(amount, from_pos): hp loss with 1.5 s spawn invulnerability, a 5 s regeneration pause and a camera / audio reaction.
## While driving the hit goes to the vehicle at 60 %. Reaching zero calls Game.die() exactly once.
func damage(amount: float, from_pos := Vector3.ZERO) -> void:
	if amount <= 0.0 or invuln > 0.0 or _dead or not Game.is_playing() or TestMode.god:
		return
	if _vehicle_alive():
		var share := amount * VEHICLE_DAMAGE_SHARE
		if _vehicle.has_method(&"damage"):
			_vehicle.call(&"damage", share)
		last_hurt_time = PlayerUtil.now()                # the HUD vignette and attacker arc also show hits taken while driving
		last_hurt_from = from_pos
		hurt.emit(share)
		return
	hp -= amount * Upgrades.damage_taken()
	since_hurt = 0.0
	last_hurt_time = PlayerUtil.now()
	last_hurt_from = from_pos
	hurt.emit(amount)
	FX.shake(0.3)
	Sfx.play(&"hurt")
	body.flinch(clampf(amount / 25.0, 0.3, 1.5), from_pos)
	camera_rig.bump(clampf(amount / 40.0, 0.1, 0.6))
	if hp <= 0.0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	hp = 0.0
	aiming = false
	sprinting = false
	input_strafe = 0.0
	input_move = Vector2.ZERO
	weapon.cancel_reload()
	body.set_dead(true)
	Game.die()


# ---------------------------------------------------------------------------------------------------------------------
# vehicle mode
# ---------------------------------------------------------------------------------------------------------------------

func _vehicle_alive() -> bool:
	return _in_vehicle and is_instance_valid(_vehicle)


func _set_vehicle(v: Node3D) -> void:
	var next: Node3D = v if is_instance_valid(v) else null
	if next == null and not _in_vehicle:
		_vehicle = null
		return
	if next != null and _in_vehicle and next == _vehicle:
		return
	_vehicle = next
	_in_vehicle = next != null
	_apply_vehicle_state()


func _apply_vehicle_state() -> void:
	if camera_rig == null:
		return
	if _in_vehicle:
		weapon.cancel_reload()
		aiming = false
		sprinting = false
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		body.visible = false
		camera_rig.mode = &"vehicle"
		camera_rig.follow_target = _vehicle
		global_position = _vehicle.global_position
		_snap_interpolation()
		camera_rig.snap()
	else:
		collision_layer = Game.L_PLAYER
		collision_mask = Game.L_WORLD | Game.L_VEHICLE
		body.visible = true
		camera_rig.mode = &"foot"
		camera_rig.follow_target = self
		yaw = camera_rig.get_aim_yaw()
		velocity = Vector3.ZERO
		_snap_interpolation()
		camera_rig.snap()


# ---------------------------------------------------------------------------------------------------------------------
# physics
# ---------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Somebody moved the node from outside (vehicle exit, a module assigning global_position): do not interpolate across the jump.
	# Between ticks only outside code can move the body, so any difference to where the last tick left it is such a move.
	if global_position.distance_squared_to(_phys_cur) > 1e-6:
		_snap_interpolation()
		_ground_known = false
		_was_on_floor = false
	_phys_prev = _phys_cur
	match Game.state:
		&"play":
			_tick(delta)
		&"dead", &"win", &"menu":
			_settle_tick(delta)
		# paused: everything stays exactly as it is
	_phys_cur = global_position


func _tick(dt: float) -> void:
	invuln = maxf(0.0, invuln - dt)
	since_hurt += dt
	if hp < max_hp and since_hurt > REGEN_DELAY and not _dead:
		hp += REGEN_RATE * dt
	energy += (ENERGY_REGEN_DRIVING if _in_vehicle else ENERGY_REGEN) * Upgrades.regen_mult() * dt
	if _dead:
		return
	if _in_vehicle:
		if is_instance_valid(_vehicle):
			global_position = _vehicle.global_position
		else:
			_set_vehicle(null)                              # the vehicle was freed under us (destroyed, despawned): on foot again, where it was
		return
	_foot_tick(dt)
	if rescue_if_lost():
		return
	if global_position.y < VOID_Y:                      # fell out of the world: back to the spawn
		var keep := hp
		reset()
		hp = keep
		invuln = SPAWN_INVULNERABILITY


## The physics of a body nobody drives (dead, victory, title): gravity and friction, no input, no weapon, no regeneration. A player killed in
## mid-air falls to the ground, one killed at a sprint slides to a stop; the body animation reads the same velocity.
func _settle_tick(dt: float) -> void:
	if _in_vehicle:
		if is_instance_valid(_vehicle):
			global_position = _vehicle.global_position
		else:
			_set_vehicle(null)
		return
	aiming = false
	sprinting = false
	input_strafe = 0.0
	var on_floor := is_on_floor() and _ground_known
	velocity.x = PlayerUtil.damp(velocity.x, 0.0, SETTLE_FRICTION, dt)
	velocity.z = PlayerUtil.damp(velocity.z, 0.0, SETTLE_FRICTION, dt)
	if not on_floor:
		velocity.y = maxf(-MAX_FALL_SPEED, velocity.y - GRAVITY * dt * 0.5)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	_ground_known = true
	var landed := is_on_floor()
	air_time = 0.0 if landed else air_time + dt
	if not landed:
		velocity.y = maxf(-MAX_FALL_SPEED, velocity.y - GRAVITY * dt * 0.5)
	_was_on_floor = landed
	if global_position.y < VOID_Y:                      # fell out of the world while dead: back to the spawn, still dead
		global_position = Game.SPAWN
		velocity = Vector3.ZERO
		_ground_known = false


func _foot_tick(dt: float) -> void:
	# --- input
	var iv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back", 0.05)     # x right+, y back+
	var forward_in := -iv.y
	input_strafe = iv.x
	input_move = iv
	aiming = Input.is_action_pressed(&"aim")
	var want_sprint := Input.is_action_pressed(&"sprint") and not aiming and forward_in > 0.3
	var jump_down := Input.is_action_pressed(&"jump")
	if jump_down and not _jump_was_down:
		_jump_buffer = JUMP_BUFFER
	_jump_was_down = jump_down
	var reload_down := Input.is_action_pressed(&"reload")
	var reload_pressed := reload_down and not _reload_was_down
	_reload_was_down = reload_down

	# --- horizontal velocity: world direction from the look yaw, exponential approach
	var look_yaw := camera_rig.yaw
	var fwd := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var right := Vector3(cos(look_yaw), 0.0, -sin(look_yaw))
	var wish := fwd * forward_in + right * iv.x
	var boost := speed_boost if speed_boost >= 1.0 else 1.0 + speed_boost
	var top_speed := (AIM_SPEED if aiming else WALK_SPEED) * (SPRINT_MULT if want_sprint else 1.0) * boost
	var on_floor := is_on_floor() and _ground_known
	var k := GROUND_ACCEL if on_floor else AIR_ACCEL
	velocity.x = PlayerUtil.damp(velocity.x, wish.x * top_speed, k, dt)
	velocity.z = PlayerUtil.damp(velocity.z, wish.z * top_speed, k, dt)
	var horizontal := Vector2(velocity.x, velocity.z).length()
	sprinting = want_sprint and horizontal > 3.0

	# --- vertical: coyote time, jump buffering, half-step gravity (exact parabola at any tick rate)
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - dt)
	_jump_buffer = maxf(0.0, _jump_buffer - dt)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_coyote = 0.0
		on_floor = false
	if not on_floor:
		velocity.y = maxf(-MAX_FALL_SPEED, velocity.y - GRAVITY * dt * 0.5)
	elif velocity.y < 0.0:
		velocity.y = 0.0

	_fall_speed = 0.0 if on_floor else minf(_fall_speed, velocity.y)
	if on_floor and _hit_wall:
		_try_step_up(dt)
	move_and_slide()
	_ground_known = true
	_hit_wall = is_on_wall()
	var landed := is_on_floor()
	air_time = 0.0 if landed else air_time + dt
	if not landed:
		velocity.y = maxf(-MAX_FALL_SPEED, velocity.y - GRAVITY * dt * 0.5)
	if landed and not _was_on_floor:
		_on_land(_fall_speed)
	_was_on_floor = landed

	# --- weapon
	weapon.poll_switch()
	var assist := get_node_or_null("AimAssist") as AimAssist
	var auto := assist != null and assist.wants_auto_fire()
	weapon.tick(dt, Input.is_action_pressed(&"fire") or auto, reload_pressed, aiming, horizontal > 1.0)


func _on_land(fall_speed: float) -> void:
	var impact := clampf((-fall_speed - 6.0) / 18.0, 0.0, 1.0)
	_fall_speed = 0.0
	if impact > 0.0:
		camera_rig.bump(impact)
		FX.shake(impact * 0.22)
		sparks.dust(global_position + Vector3(0.0, 0.08, 0.0), impact)


## Walk up a curb or a stair: if the way ahead is blocked by something lower than STEP_HEIGHT, lift the body onto it.
func _try_step_up(dt: float) -> void:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * dt
	if motion.length_squared() < 1e-6:
		return
	var xf := global_transform
	if not test_move(xf, motion, _kc, 0.002):
		return
	if _kc.get_normal().y >= cos(floor_max_angle):
		return                                           # a walkable slope: move_and_slide copes. (A curb corner touches the capsule's round bottom, its normal is steep but not a wall.)
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(xf, up):
		return                                           # no headroom
	var raised := xf.translated(up)
	if test_move(raised, motion):
		return                                           # still blocked up there: a wall
	var ahead := raised.translated(motion.normalized() * (CAPSULE_RADIUS + 0.06))      # the whole capsule base over the step top
	if not test_move(ahead, Vector3.DOWN * (STEP_HEIGHT + 0.05), _kc2, 0.002):
		return                                           # no ground beyond: a drop, not a step
	if _kc2.get_normal().y < 0.7:
		return
	var rise := STEP_HEIGHT - _kc2.get_travel().length()
	if rise < 0.02:
		return
	global_position += Vector3.UP * (rise + 0.004)
	_step_offset -= rise


# ---------------------------------------------------------------------------------------------------------------------
# rendered frame
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	var playing := Game.is_playing()
	if playing and not _in_vehicle and not _dead:
		yaw = PlayerUtil.damp_angle(yaw, camera_rig.get_aim_yaw(), 14.0, dt)
	rotation.y = yaw
	_step_offset = PlayerUtil.damp(_step_offset, 0.0, 14.0, dt)
	camera_rig.pivot_y_offset = _step_offset
	var view_pos := _phys_prev.lerp(_phys_cur, Engine.get_physics_interpolation_fraction())
	view_pos.y += _step_offset
	body.update_view(self, dt, view_pos, yaw)
