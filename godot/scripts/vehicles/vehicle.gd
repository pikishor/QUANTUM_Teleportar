class_name Vehicle
extends CharacterBody3D
## One car (group `vehicle`, layer `vehicle`). Kinematic arcade physics, no VehicleBody3D, no RigidBody: the manager calls sim(dt) once per physics tick.
##
## Three drivers share one body: the player (throttle / brake on move_forward / move_back, steer on move_left / move_right, handbrake on jump; port of
## drive() in src/vehicles.js), the traffic AI (right-hand lane at Game.LANE, a turn decided at junctions, stops for the player and other cars) and nobody
## (parked or knocked about: it slides to a stop). Forward is -Z; heading is Node3D.rotation.y, so the root rotates with the car.
## API: damage(amount) · speed (signed m/s along the heading) · hp / max_hp · driver_is_player · heading · kind · is_starter.
## A car is pooled by the manager: activate() / deactivate() reuse the same nodes, materials and (cheap) MirrorProxy.

signal exploded(vehicle: Vehicle)

var kind: StringName = &"sedan"
var spec: Dictionary = VehicleSpecs.SPECS[&"sedan"]
var hp := 120.0
var max_hp := 120.0
var speed := 0.0                    ## signed forward speed in m/s
var heading := 0.0                  ## radians, = rotation.y
var driver_is_player := false
var active := false                 ## in play (a pooled car is inactive, hidden, out of the group and its collider is off)
var dead := false                   ## exploded: stays as a husk (wreck) until the respawn, then goes back to the pool
var wreck := false                  ## the visible, dark, unlit husk of an exploded car (no group, no simulation, never enterable)
var is_starter := false
var ai := false                     ## traffic: follows its lane
var ai_axis := 0                    ## 0 = along X, 1 = along Z
var ai_dir := 1
var ai_line := 0.0                  ## lane centre coordinate across the road
var ai_speed := 0.0
var ai_cruise := 11.0
var ai_cool := 0.0                  ## metres to travel before the next junction may turn
var vel := Vector3.ZERO             ## world velocity (y = 0)
var braking := false                ## brake / handbrake lights
var steer_in := 0.0                 ## last steering input -1..1 (wheel visual)
var slip := 0.0                     ## lateral speed, m/s (body roll)
var visual: VehicleVisual
var manager: Node
var hits := 0                       ## wall and car impacts that hurt (tests, stats)

var _mirror: MirrorProxy
var _mirror_on := false
var _none: Array[MeshInstance3D] = []
var _steer_vis := 0.0
var _lean_p := 0.0
var _lean_r := 0.0
var _last_vf := 0.0
var _heading_set := NAN


## One-time construction: model, collider, MirrorProxy.
func setup(k: StringName, mgr: Node) -> void:
	kind = k
	spec = VehicleSpecs.SPECS[k]
	manager = mgr
	max_hp = spec["hp"]
	hp = max_hp
	name = "Car_%s" % k
	collision_layer = 0
	collision_mask = Game.L_WORLD
	var glow := VehicleSpecs.GLOWS[randi() % VehicleSpecs.GLOWS.size()]
	visual = VehicleVisual.new()
	add_child(visual.build(k, glow))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var h: float = float(spec["hgt"]) - 0.2
	box.size = Vector3(float(spec["wid"]) - 0.1, h, float(spec["len"]) - 0.3)
	cs.shape = box
	cs.position = Vector3(0.0, 0.2 + h * 0.5, 0.0)
	add_child(cs)
	_mirror = MirrorProxy.new()
	add_child(_mirror)
	set_physics_process(false)
	visible = false


## Put the car into play at `pos` (ground position), parked and repaired. Call set_traffic() afterwards for a moving one.
func activate(pos: Vector3, h: float) -> void:
	hp = max_hp
	dead = false
	wreck = false
	speed = 0.0
	vel = Vector3.ZERO
	ai = false
	ai_speed = 0.0
	driver_is_player = false
	braking = false
	steer_in = 0.0
	slip = 0.0
	hits = 0
	_steer_vis = 0.0
	_lean_p = 0.0
	_lean_r = 0.0
	_last_vf = 0.0
	heading = h
	global_position = Vector3(pos.x, 0.0, pos.z)
	rotation = Vector3(0.0, h, 0.0)
	_heading_set = h
	visual.model.rotation = Vector3.ZERO
	var ci := randi() % VehicleSpecs.COLORS.size()
	visual.set_paint(VehicleSpecs.COLORS[ci])
	visual.set_glow(VehicleSpecs.GLOWS[randi() % VehicleSpecs.GLOWS.size()])
	_apply_lights()
	collision_layer = Game.L_VEHICLE
	if not is_in_group(&"vehicle"):
		add_to_group(&"vehicle")
	visible = true
	active = true


## The exploded car stays where it is as a charred husk: dark paint, lights out, a little sag, out of the group (nothing targets or damages it) and out of the
## simulation. The manager releases it when the replacement car is due. Burning-less on purpose: no particles, no lights, no cost.
func become_wreck() -> void:
	wreck = true
	active = false
	driver_is_player = false
	ai = false
	speed = 0.0
	vel = Vector3.ZERO
	braking = false
	steer_in = 0.0
	if is_in_group(&"vehicle"):
		remove_from_group(&"vehicle")
	visual.set_paint(VehicleSpecs.WRECK_COLOR)
	visual.set_lights(0.0, 0.0, 0.0)
	visual.model.rotation = Vector3(0.02, 0.0, 0.07)
	if _mirror_on:                                           # a husk casts no reflection
		_mirror_on = false
		_mirror.track(_none)
	visible = true


func deactivate() -> void:
	wreck = false
	active = false
	driver_is_player = false
	ai = false
	collision_layer = 0
	visible = false
	if is_in_group(&"vehicle"):
		remove_from_group(&"vehicle")
	if _mirror_on:
		_mirror_on = false
		_mirror.track(_none)


## Make this car a traffic car in the lane `line` of a road along `axis` travelling in `dir`.
func set_traffic(axis: int, dir: int, line: float, cruise: float) -> void:
	ai = true
	ai_axis = axis
	ai_dir = dir
	ai_line = line
	ai_cruise = cruise
	ai_speed = 0.0
	ai_cool = 0.0
	_apply_lights()


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))


# --- damage -----------------------------------------------------------------------------------------------------------

## The damage contract (see the player section): weapon hits, explosions, wall and car impacts.
func damage(amount: float) -> void:
	if dead or not active or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		explode()


## Blow up: the driver is thrown out first, then Game.explode (radius 9: enemies 80, cars 70, player 35), heat +0.2; the manager respawns it as parked.
func explode() -> void:
	if dead:
		return
	dead = true
	var pos := global_position
	var mgr := manager as VehicleManager
	if driver_is_player:
		if mgr != null:
			mgr.exit_vehicle()
		var pl := Game.player
		if is_instance_valid(pl) and pl.get(&"vehicle") == self:       # never leave the player (and the chase camera) tied to a wreck
			pl.set(&"vehicle", null)
		driver_is_player = false
	Game.explode(pos + Vector3(0.0, 1.0, 0.0), 9.0, {"enemy_dmg": 80.0, "car_dmg": 70.0, "player_dmg": 35.0, "color": Color(1.0, 0.54, 0.19)})
	Game.add_heat(VehicleSpecs.CARJACK_HEAT)
	exploded.emit(self)
	if mgr != null:
		mgr.on_destroyed(self)


# --- simulation --------------------------------------------------------------------------------------------------------

## One physics tick (called by the manager while Game.is_playing()).
func sim(dt: float) -> void:
	if driver_is_player:
		step_drive(dt, Input.get_axis(&"move_back", &"move_forward"), Input.get_axis(&"move_left", &"move_right"), Input.is_action_pressed(&"jump"))
	elif ai:
		_ai_step(dt)
	else:
		_coast(dt)
	_sync(dt)


## Arcade driving (src/vehicles.js drive()): thr -1..1 (brake / reverse .. throttle), steer -1..1 (left .. right), handbrake.
func step_drive(dt: float, thr: float, steer: float, handbrake: bool) -> void:
	var T := spec
	var vmax: float = T["max"]
	var fwd := forward()
	var rgt := right()
	var vf := vel.dot(fwd)
	var vl := vel.dot(rgt)
	if thr > 0.05:
		vf += float(T["acc"]) * thr * (1.0 - maxf(0.0, vf) / vmax) * dt
	elif thr < -0.05:
		vf += (-float(T["brake"]) if vf > 0.5 else -float(T["acc"]) * 0.45) * -thr * dt
	else:
		vf *= exp(-VehicleSpecs.COAST_DRAG * dt)
	if handbrake:
		vf *= exp(-VehicleSpecs.HANDBRAKE_DRAG * dt)
	vf = clampf(vf, -vmax * VehicleSpecs.REVERSE_FRACTION, vmax)
	var auth := clampf(absf(vf) / 5.0, 0.0, 1.0) / (1.0 + absf(vf) / 38.0)
	heading -= steer * VehicleSpecs.STEER_RATE * auth * (1.0 if vf >= 0.0 else -1.0) * dt
	vl *= exp(-(VehicleSpecs.HANDBRAKE_GRIP if handbrake else float(T["grip"])) * dt)
	fwd = forward()
	rgt = right()
	vel = fwd * vf + rgt * vl
	speed = vf
	slip = vl
	braking = handbrake or (thr < -0.05 and vf > 0.5)
	steer_in = steer
	_move(dt)
	speed = vel.dot(fwd)


## A car nobody drives (parked, or knocked about): friction, no steering.
func _coast(dt: float) -> void:
	if vel.length_squared() < 0.01:
		vel = Vector3.ZERO
		speed = 0.0
		return
	vel *= exp(-VehicleSpecs.UNPOWERED_DRAG * dt)
	_move(dt)
	speed = vel.dot(forward())
	braking = false


## Move by vel * dt against the world (layer 1): bounce, damage and shake on a hard hit, then slide along the wall for the rest of the step.
func _move(dt: float) -> void:
	var motion := Vector3(vel.x * dt, 0.0, vel.z * dt)
	if motion.length_squared() < 1e-10:
		return
	var col := move_and_collide(motion)
	if col != null:
		_bounce(col)
	if global_position.y != 0.0:
		global_position.y = 0.0


func _bounce(col: KinematicCollision3D) -> void:
	var n := col.get_normal()
	n.y = 0.0
	if n.length_squared() < 1e-6:
		return
	n = n.normalized()
	var vn := vel.dot(n)
	if vn < 0.0:
		vel -= VehicleSpecs.BOUNCE * vn * n
		var impact := -vn
		if impact > VehicleSpecs.HIT_SPEED:
			hits += 1
			damage(impact * VehicleSpecs.HIT_DAMAGE)
			if driver_is_player:
				FX.shake(minf(1.0, impact / 25.0))
			var at := col.get_position()
			FX.burst(Vector3(at.x, 0.8, at.z), Color(1.0, 0.75, 0.38), 8, 5.0, 0.3, 8.0, 0.3)
			Sfx.play_at(&"hit", global_position, -4.0)
	var rem := col.get_remainder()
	rem -= n * rem.dot(n)
	rem.y = 0.0
	if rem.length_squared() > 1e-6:
		move_and_collide(rem)


# --- traffic AI ---------------------------------------------------------------------------------------------------------

func _ai_step(dt: float) -> void:
	var fx := float(ai_dir) if ai_axis == 0 else 0.0
	var fz := float(ai_dir) if ai_axis == 1 else 0.0
	var blocked := _blocked(fx, fz)
	ai_speed = _damp(ai_speed, 0.0 if blocked else ai_cruise, 5.0 if blocked else 1.5, dt)
	var p := global_position
	var ox := p.x
	var oz := p.z
	var prev_u := ox if ai_axis == 0 else oz
	var step := float(ai_dir) * ai_speed * dt
	if ai_axis == 0:
		p.x += step
		p.z = _damp(p.z, ai_line, 2.5, dt)
	else:
		p.z += step
		p.x = _damp(p.x, ai_line, 2.5, dt)
	ai_cool -= absf(step)
	var u := p.x if ai_axis == 0 else p.z
	var idx := VehicleSpecs.road_index(u)
	var c := VehicleSpecs.road_center(idx)
	if ai_cool <= 0.0 and (prev_u - c) * (u - c) <= 0.0 and prev_u != u:
		_turn(c, idx, p)
	global_position = p
	var dx := p.x - ox
	var dz := p.z - oz
	if dx * dx + dz * dz > 1e-6:
		heading = _damp_angle(heading, atan2(-dx, -dz), 7.0, dt)
	vel = Vector3(dx / dt, 0.0, dz / dt)
	speed = ai_speed
	braking = blocked or ai_speed < 1.0
	steer_in = 0.0


## Something (the player on foot, another car) within AI_LOOK metres ahead and AI_SIDE to the side.
func _blocked(fx: float, fz: float) -> bool:
	var me := global_position
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"vehicle") == null and absf(pl.global_position.y - me.y) < 3.0:
		if _ahead(pl.global_position - me, fx, fz):
			return true
	var mgr := manager as VehicleManager
	if mgr != null:
		for o in mgr.list:
			if o != self and o.active and not o.dead and _ahead(o.global_position - me, fx, fz):
				return true
	return false


func _ahead(r: Vector3, fx: float, fz: float) -> bool:
	var ahead := r.x * fx + r.z * fz
	var side := absf(r.x * fz - r.z * fx)
	return ahead > 0.0 and ahead < VehicleSpecs.AI_LOOK and side < VehicleSpecs.AI_SIDE


## At a junction: usually straight on, otherwise turn onto the crossing road into its right-hand lane of the new direction (always at the map edge).
func _turn(c: float, idx: int, p: Vector3) -> void:
	var edge := (idx == 0 and ai_dir < 0) or (idx == Game.N and ai_dir > 0)
	if not edge and randf() < VehicleSpecs.AI_STRAIGHT_CHANCE:
		return
	var across := p.z if ai_axis == 0 else p.x
	var d2 := 1 if randf() < 0.5 else -1
	if across > Game.HALF - 14.0:
		d2 = -1
	elif across < -Game.HALF + 14.0:
		d2 = 1
	ai_axis = 1 - ai_axis
	ai_dir = d2
	ai_line = c + VehicleSpecs.lane_offset(ai_axis, d2, Game.LANE)
	ai_speed *= 0.7
	ai_cool = VehicleSpecs.AI_TURN_COOLDOWN


# --- visuals ------------------------------------------------------------------------------------------------------------

func _sync(dt: float) -> void:
	if _heading_set != heading:
		rotation.y = heading
		_heading_set = heading
	var moving := absf(speed) > 0.05
	if moving or absf(_steer_vis) > 0.01:
		_steer_vis = _damp(_steer_vis, steer_in * 0.5, 10.0, dt)
		visual.spin(speed * dt, _steer_vis)
	if driver_is_player:
		var acc := (speed - _last_vf) / maxf(dt, 0.0001)
		_lean_p = _damp(_lean_p, clampf(acc * 0.0016, -0.035, 0.035), 6.0, dt)
		_lean_r = _damp(_lean_r, clampf(-slip * 0.01, -0.06, 0.06), 6.0, dt)
		visual.model.rotation = Vector3(_lean_p, 0.0, _lean_r)
	_last_vf = speed
	_apply_lights()


## Lights follow the state: parked cars glow faintly, moving ones show full headlights, brake lights flare.
func _apply_lights() -> void:
	if driver_is_player or ai:
		visual.set_lights(0.9, 1.0 if braking else 0.5, 1.0)
	else:
		visual.set_lights(0.1, 0.35, 0.3)


## Level of detail from the distance to the player (the manager calls it a few times a second).
func update_lod(dist: float) -> void:
	visual.set_wheels_visible(dist < VehicleSpecs.WHEELS_NEAR)
	visual.set_shadow(Game.quality >= 1 and dist < 35.0)
	var want := Game.quality >= 1 and dist < VehicleSpecs.MIRROR_NEAR + (8.0 if _mirror_on else 0.0)
	if want != _mirror_on:
		_mirror_on = want
		_mirror.track(visual.mirror_meshes if want else _none)
	var show := dist < 140.0 or driver_is_player
	if show != visible:
		visible = show


func has_mirror() -> bool:
	return _mirror_on


static func _damp(a: float, b: float, k: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-k * dt))


static func _damp_angle(a: float, b: float, k: float, dt: float) -> float:
	return a + wrapf(b - a, -PI, PI) * (1.0 - exp(-k * dt))
