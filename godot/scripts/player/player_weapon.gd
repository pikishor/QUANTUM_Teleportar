class_name PlayerWeapon
extends Node
## The assault rifle: 30-round magazine, 1.3 s reload, 0.11 s fire interval, hitscan.
## The shot is a ray from the CAMERA through the crosshair (mask: world + enemy + vehicle); the tracer is drawn from the muzzle to the hit
## point. Targets are found two ways and the nearest wins: the physics ray (colliders on the enemy / vehicle layers) and a ray-sphere test
## against every node of group "enemy" that exposes center() and radius (the prototype's hit model, so collider-less targets still work).
## A crit is a hit in the upper part of the target: hit.y > center().y + radius * 0.35.
## Two short extra rays keep the rifle honest: pivot -> muzzle (the weapon is poking into a wall) and muzzle -> aim point (cover in front of the barrel).
## Everything is pooled (FX tracers, the flash sprites and lights in PlayerBody, the sparks and puffs of ImpactSparks, the ImpactDecals MultiMesh): firing creates no nodes.
## Hit data for the HUD lives on the Player: last_hit_time (PlayerUtil.now() seconds), last_hit_kill, last_hit_crit, plus the hit_confirmed(kill, crit) signal.

const MAG_SIZE := 30
const RELOAD_TIME := 1.3
const FIRE_INTERVAL := 0.11
const DAMAGE := 14.0
const DAMAGE_CRIT := 30.0
const DAMAGE_VEHICLE := 9.0
const RANGE := 220.0
const CRIT_HEIGHT := 0.35                    ## of the target radius above its centre

const SPREAD_HIP := 0.014                    ## radians (half angle), src/player.js
const SPREAD_ADS := 0.004
const SPREAD_MOVE := 0.010
const BLOOM_PER_SHOT := 0.0032
const BLOOM_MAX := 0.03
const BLOOM_HOLD := 0.18                     ## seconds after a shot before the bloom starts to recover
const BLOOM_RECOVER := 0.08                  ## per second

const RECOIL_START := 0.0095                 ## camera kick per shot (radians): first shots kick hardest, settling toward RECOIL_END
const RECOIL_END := 0.0055
const RECOIL_YAW := 0.0035
const RECOIL_ADS_SCALE := 0.65
const BURST_RESET := 0.35

const TRACER_COLOR := Color(1.0, 0.86, 0.5)
const MASK_SHOT := 1 | 4 | 8                 # world + enemy + vehicle (Game.L_*)

var mag := MAG_SIZE
var ammo := MAG_SIZE
var reload_t := 0.0                          ## seconds of reload left, 0 when not reloading
var fire_t := 0.0                            ## seconds until the next shot may leave the barrel
var bloom := 0.0                             ## spread added by sustained fire
var spread := SPREAD_HIP                     ## current total half angle in radians (what the crosshair shows and what the shot uses)
var shots_fired := 0                         ## lifetime counter, for tests and stats

var _player: Player
var _since_shot := 99.0
var _burst := 0
var _move_spread := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ray_b := PhysicsRayQueryParameters3D.new()
var _exclude_base: Array[RID] = []
var _exclude: Array[RID] = []
var _decals: ImpactDecals
var _sparks: ImpactSparks


func _ready() -> void:
	_player = get_parent() as Player
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.collision_mask = MASK_SHOT
	_ray_b.collide_with_areas = false
	_ray_b.collide_with_bodies = true
	_ray_b.collision_mask = Game.L_WORLD | Game.L_VEHICLE
	if _player != null:
		_exclude_base = [_player.get_rid()]
		_ray_b.exclude = _exclude_base


func set_effects(decals: ImpactDecals, sparks: ImpactSparks) -> void:
	_decals = decals
	_sparks = sparks


func reset() -> void:
	mag = Upgrades.mag_size()
	ammo = mag
	reload_t = 0.0
	fire_t = 0.0
	bloom = 0.0
	_since_shot = 99.0
	_burst = 0
	_move_spread = 0.0
	spread = SPREAD_HIP


func is_reloading() -> bool:
	return reload_t > 0.0


func cancel_reload() -> void:
	reload_t = 0.0


func start_reload() -> bool:
	if reload_t > 0.0 or ammo >= mag:
		return false
	reload_t = RELOAD_TIME * Upgrades.reload_mult()
	Sfx.play(&"reload")
	return true


## Advance the weapon by dt. firing / reload_pressed come from the input actions, aiming and moving from the player.
func tick(dt: float, firing: bool, reload_pressed: bool, aiming: bool, moving: bool) -> void:
	fire_t -= dt
	_since_shot += dt
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			reload_t = 0.0
			ammo = mag
	if reload_pressed:
		start_reload()
	if firing and reload_t <= 0.0:
		if ammo <= 0:
			start_reload()
		elif fire_t <= 0.0:
			_shoot(dt, aiming)
	if _since_shot > BLOOM_HOLD:
		bloom = maxf(0.0, bloom - BLOOM_RECOVER * dt)
	if _since_shot > BURST_RESET:
		_burst = 0
	_move_spread = PlayerUtil.damp(_move_spread, SPREAD_MOVE if moving else 0.0, 12.0, dt)
	spread = (SPREAD_ADS if aiming else SPREAD_HIP) + bloom + _move_spread


## Dispersion applied to a unit direction: uniform inside a cone of half angle `angle` around `dir`, using the camera basis.
static func jitter_dir(basis: Basis, angle: float, rng_a: float, rng_r: float) -> Vector3:
	var fwd := -basis.z
	var a := rng_a * TAU
	var r := angle * sqrt(rng_r)
	return (fwd + basis.x * (cos(a) * r) + basis.y * (sin(a) * r)).normalized()


func _shoot(dt: float, aiming: bool) -> void:
	var p := _player
	var rig := p.camera_rig
	ammo -= 1
	shots_fired += 1
	fire_t = maxf(fire_t, -dt) + FIRE_INTERVAL      # keep the cadence exact whatever the tick rate, without banking shots
	_since_shot = 0.0
	_burst += 1
	Sfx.play(&"shot", -2.0, randf_range(0.95, 1.05))

	# --- the aim ray: camera through the crosshair, starting at the player's depth so geometry behind the character is ignored
	var cam := rig.camera
	var cam_pos := cam.global_position
	var dir := jitter_dir(cam.global_basis, spread, randf(), randf())
	var along := maxf(0.0, (rig.get_pivot_position() - cam_pos).dot(dir))
	var origin := cam_pos + dir * along
	var best := RANGE
	var target: Node = null
	var normal := Vector3.ZERO
	var space := p.get_world_3d().direct_space_state
	_exclude.assign(_exclude_base)
	_ray.from = origin
	_ray.to = origin + dir * RANGE
	for _attempt in 3:
		_ray.exclude = _exclude
		var res := space.intersect_ray(_ray)
		if res.is_empty():
			break
		var hit_pos: Vector3 = res["position"]
		var hit_target := _damageable_of(res["collider"] as Node)
		if hit_target != null and _is_dead(hit_target):
			_exclude.append(res["rid"])          # a corpse does not stop bullets
			continue
		best = origin.distance_to(hit_pos)
		normal = res["normal"]
		target = hit_target
		break
	# collider-less (or generously sized) enemies: the prototype's ray-sphere test
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or _is_dead(e):
			continue
		var c: Vector3 = e.call(&"center")
		var r := _radius_of(e)
		if r <= 0.0:
			continue
		var t := PlayerUtil.ray_sphere(origin, dir, c, r)
		if t < best:
			best = t
			target = e
			normal = (origin + dir * t - c).normalized()
	var hit := origin + dir * best
	var hit_something := best < RANGE - 0.001

	# --- the barrel: poking into a wall, or cover right in front of the muzzle
	var mz := p.body.muzzle.global_position
	var anchor := rig.get_pivot_position()
	var blocked := _blocked_between(space, anchor, mz)
	if blocked.is_empty():
		blocked = _blocked_between(space, mz, hit)
	if not blocked.is_empty():
		hit = blocked["position"]
		normal = blocked["normal"]
		target = _damageable_of(blocked["collider"] as Node)
		hit_something = true

	# --- effects at the muzzle
	FX.tracer(mz, hit, TRACER_COLOR)
	p.body.fire_flash(1.0)

	# --- recoil: the aim itself climbs (bullets follow the camera), with a pattern that settles
	var k := clampf(float(_burst - 1) / 10.0, 0.0, 1.0)
	var kick := lerpf(RECOIL_START, RECOIL_END, k) * randf_range(0.85, 1.15)
	var kick_yaw := randf_range(-1.0, 1.0) * RECOIL_YAW
	if aiming:
		kick *= RECOIL_ADS_SCALE
		kick_yaw *= RECOIL_ADS_SCALE
	rig.kick(kick, kick_yaw)
	rig.punch(0.03)
	bloom = minf(BLOOM_MAX, bloom + BLOOM_PER_SHOT)

	# --- impact
	if target != null and not _is_dead(target):
		_hit_target(target, hit, normal)
	elif hit_something:
		_hit_world(hit, normal)
	p.fired.emit()


## Is the segment a -> b blocked by the world or a vehicle? Returns the ray result (empty = clear).
func _blocked_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var d := b - a
	var dist := d.length()
	if dist < 0.08:
		return {}
	_ray_b.from = a
	_ray_b.to = a + d * (1.0 - 0.025 / dist)
	return space.intersect_ray(_ray_b)


func _hit_target(target: Node, hit: Vector3, normal: Vector3) -> void:
	var p := _player
	var is_vehicle := target.is_in_group(&"vehicle") and not target.is_in_group(&"enemy")
	var crit := false
	var human := false
	if not is_vehicle:
		var c := Vector3.ZERO
		if target.has_method(&"center"):
			c = target.call(&"center")
		else:
			c = (target as Node3D).global_position
		var r := _radius_of(target)
		crit = r > 0.0 and hit.y > c.y + r * CRIT_HEIGHT
		human = target.get(&"type") == &"operative"
		target.call(&"damage", (DAMAGE_CRIT if crit else DAMAGE) * Upgrades.damage_mult(), crit)
	else:
		target.call(&"damage", DAMAGE_VEHICLE)
	var kill := (not is_vehicle) and _is_dead(target)
	p.last_hit_time = PlayerUtil.now()
	p.last_hit_kill = kill
	p.last_hit_crit = crit
	p.hit_confirmed.emit(kill, crit)
	var n := normal if normal != Vector3.ZERO else Vector3.UP
	if _sparks != null:
		if is_vehicle:
			_sparks.impact_machine(hit, n)
		elif human:
			if Game.graphic_violence:
				_sparks.impact_blood(hit, n)
			_sparks.impact_person(hit, n)
		else:
			_sparks.impact_machine(hit, n)


func _hit_world(hit: Vector3, normal: Vector3) -> void:
	var n := normal if normal != Vector3.ZERO else Vector3.UP
	if _sparks != null:
		_sparks.impact_world(hit, n)
	if _decals != null:
		_decals.add(hit, n, randf_range(0.14, 0.2))


## The node that takes damage for a physics collider: the collider itself or the nearest ancestor in group enemy / vehicle.
static func _damageable_of(collider: Node) -> Node:
	var n := collider
	while n != null:
		if (n.is_in_group(&"enemy") or n.is_in_group(&"vehicle")) and n.has_method(&"damage"):
			return n
		n = n.get_parent()
	return null


static func _radius_of(target: Object) -> float:
	var r: Variant = target.get(&"radius")
	if r is float or r is int:
		return float(r)
	return 0.0


static func _is_dead(target: Object) -> bool:
	if not is_instance_valid(target):
		return true
	var n := target as Node
	if n != null and n.is_queued_for_deletion():
		return true
	var d: Variant = target.get(&"dead")
	if d is bool and d:
		return true
	var h: Variant = target.get(&"hp")
	if (h is float or h is int) and float(h) <= 0.0:
		return true
	return false
