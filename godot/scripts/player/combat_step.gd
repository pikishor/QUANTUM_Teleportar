class_name CombatStep
extends RefCounted
## COMBAT STEP: a hero who holds FIRE with the stick untouched does not stand planted. He side-steps (a new direction every 0.9-1.7 s, never into a wall, a car or a drop) at a
## third of his walk speed while he shoots, and the camera yaw turns by exactly the angle the step moves the muzzle off the target, so the crosshair stays on whatever it was on
## (the step is for the hero's body and the picture, never against the player's aim). It stands down for precision (ADS, the Pulse Lance, melee), crouching / cover, the stick,
## reduce-motion and a half-second after the trigger is first pulled (a tap is a tap). Player._foot_tick adds `wish()` to the stick's own wish vector.

const SPEED := 2.1                   ## m/s of the sideways step
const EASE := 4.5                    ## share of full speed gained per second (a full reversal takes 0.45 s)
const START_DELAY := 0.35            ## seconds of held trigger before the first step
const HOLD_MIN := 0.9
const HOLD_MAX := 1.7
const PROBE := 1.4                   ## metres of free ground / air sideways the step needs
const AIM_DIST_DEFAULT := 25.0       ## the distance the camera turn is figured for when no foe is ahead
const SKIP_CLASSES: Array[StringName] = [&"sniper", &"melee"]

static var enabled := true

var dir := 1.0                       ## +1 right, -1 left
var active := false                  ## the hero is stepping this tick
var flips := 0                       ## direction changes so far (tests)
var travelled := 0.0                 ## metres stepped so far (tests)
var _fire_t := 0.0
var _hold := 1.0
var _blocked_t := 0.0
var _v := 0.0                        ## the step's current share of full speed, -1..1: it eases toward `dir`, so a reversal passes through a stop instead of snapping 4 m/s the other way (director review 5, #1: a planted foot and a snapped reversal made a wide scissor)


## The extra wish vector (world, unit-ish: 0.34 of a full push) for this tick, or ZERO. `stick` is the stick length, `firing` the trigger.
func wish(p: Player, dt: float, stick: float, firing: bool, aiming: bool, on_floor: bool) -> Vector3:
	active = false
	if not firing or stick > 0.1:
		_fire_t = 0.0
		_v = 0.0
		return Vector3.ZERO
	_fire_t += dt
	if not enabled or aiming or not on_floor or UiSettings.s_reduce_motion or _fire_t < START_DELAY or not is_instance_valid(p) or p.cover == null or p.cover.crouching:
		_v = 0.0
		return Vector3.ZERO
	var w: PlayerWeapon = p.weapon
	if w != null and SKIP_CLASSES.has(WeaponDefs.class_of(w.current)):
		return Vector3.ZERO
	var yaw := p.camera_rig.yaw
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_hold -= dt
	if _hold <= 0.0:
		_hold = randf_range(HOLD_MIN, HOLD_MAX)
		dir = -dir
		flips += 1
	if not _clear(p, right * dir):
		dir = -dir                                         # a wall, a car or an edge on this side: the other way, at once
		flips += 1
		_hold = randf_range(HOLD_MIN, HOLD_MAX)
		if not _clear(p, right * dir):
			return Vector3.ZERO                            # boxed in on both sides: stand and shoot
	active = true
	_v = move_toward(_v, dir, EASE * dt)
	var step := SPEED * _v
	travelled += absf(step) * dt
	var aim_d := _aim_distance(p, yaw)
	p.camera_rig.yaw += step * dt / aim_d              # the muzzle moves `step * dt` to the side: turn left (+yaw) by that angle over the distance to the aim point
	return right * _v * (SPEED / Player.WALK_SPEED)


## True when `d` (a unit-ish horizontal direction) has PROBE metres of free body room and ground under it.
func _clear(p: Player, d: Vector3) -> bool:
	var space := p.get_world_3d().direct_space_state
	var from := p.global_position + Vector3(0.0, 0.9, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + d.normalized() * PROBE, Game.L_WORLD)
	if not space.intersect_ray(q).is_empty():
		return false
	var foot := p.global_position + d.normalized() * PROBE
	var g := PhysicsRayQueryParameters3D.create(foot + Vector3(0.0, 0.6, 0.0), foot + Vector3(0.0, -1.2, 0.0), Game.L_WORLD)
	return not space.intersect_ray(g).is_empty()


## The distance (clamped) from the hero to what the crosshair is on: the nearest living foe within 20 degrees of the view, else a default.
func _aim_distance(p: Player, yaw: float) -> float:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return AIM_DIST_DEFAULT
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var best := AIM_DIST_DEFAULT
	var found := false
	for d: Drone in mgr.list:
		if not is_instance_valid(d) or d.dead or not d.active:
			continue
		var to := d.global_position - p.global_position
		to.y = 0.0
		var l := to.length()
		if l < 2.0 or l > 70.0 or to.dot(fwd) / l < 0.94:
			continue
		if not found or l < best:
			best = l
			found = true
	return clampf(best, 4.0, 70.0)
