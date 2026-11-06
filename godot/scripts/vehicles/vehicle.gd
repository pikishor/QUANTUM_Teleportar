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
signal damage_state_changed(vehicle: Vehicle, state: int)     ## 0 sound, 1 smoking (hp < 40 %), 2 burning (hp < 15 %, the car burns down and explodes)

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
var garage_car := false             ## the player's garage car (tuned spec, see apply_garage); reset when it goes back to the pool
var paint_i := -1                   ## index into VehicleSpecs.COLORS of the current paint (-1 unknown)
var ai := false                     ## traffic: follows its lane
var ai_axis := 0                    ## 0 = along X, 1 = along Z
var ai_dir := 1
var ai_line := 0.0                  ## lane centre coordinate across the road
var ai_speed := 0.0
var ai_cruise := 11.0
var ai_cool := 0.0                  ## metres to travel before the next junction may turn
var ai_panic := 0.0                 ## s: fleeing after gunfire (faster, ignores lights) or hurrying on after a horn
var ai_stun := 0.0                  ## s: stopped by a crash nearby
var yielding := false               ## pulled over for a siren behind it
var at_light := false               ## braking for a red or amber light (tests)
var reactions := 0                  ## horn / gunfire / crash reactions so far (tests)
var _yield_t := 0.0                 ## re-check timer of the siren search
var vel := Vector3.ZERO             ## world velocity (y = 0)
var braking := false                ## brake / handbrake lights
var steer_in := 0.0                 ## last steering input -1..1 (wheel visual)
var slip := 0.0                     ## lateral speed, m/s (body roll)
var visual: VehicleVisual
var manager: Node
var hits := 0                       ## wall and car impacts that hurt (tests, stats)
var cls: StringName = &"car"        ## handling class from the spec: car / bike / hover
var lean := 0.0                     ## bike: body roll in rad (+ = leaning right), also the roll of an AI bike in a turn
var bob := 0.0                      ## hover: current height offset of the model above the ride height (m)
var dmg_state := 0                  ## see damage_state_changed
var patrol := false                 ## a Vael patrol vehicle (spec flag)
var chasing := false                ## patrol: drives at the player and rams him
var ram_hits := 0                   ## patrol rams that landed (tests)
var tactic: StringName = &"ram"      ## patrol pursuit tactic (VehicleSpecs.TACTICS)
var weapons: VehicleWeapons         ## mounted weapon (sport / suv / hover), null on other kinds
var fuse := -1.0                    ## chain reaction (open world freedom): seconds until a burning car next to a wreck blows up (< 0 = none)
var nitro := 1.0                    ## boost tank 0..1
var boosting := false
var _nitro_wait := 0.0

var _mirror: MirrorProxy
var _mirror_on := false
var _none: Array[MeshInstance3D] = []
var _steer_vis := 0.0
var _lean_p := 0.0
var _lean_r := 0.0
var _last_vf := 0.0
var _heading_set := NAN
var _prev_h := 0.0
var _bob_t := 0.0
var _fx_t := 0.0
var _fx_n := 0
var _dist := 0.0                    ## distance to the player (update_lod)
var _stuck := 0.0
var _rev := 0.0
var _ram_cd := 0.0
var _siren_t := 0.0
var _siren_i := 0
var _warned := 0
var _fin_t := 0.0                   ## time of the finish shimmer
var _fin_acc := 0.0
var _smoke_t := 0.0
var _drift_t := 0.0                 ## seconds since the handbrake was released: traction comes back gradually
var drifting := false               ## sliding hard enough to smoke (tests)


## One-time construction: model, collider, MirrorProxy.
func setup(k: StringName, mgr: Node) -> void:
	kind = k
	spec = VehicleSpecs.SPECS[k]
	manager = mgr
	max_hp = spec["hp"]
	hp = max_hp
	cls = VehicleSpecs.cls_of(k)
	patrol = bool(spec.get("patrol", false))
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
	cs.position = Vector3(0.0, 0.2 + h * 0.5 + float(spec.get("hover_h", 0.0)), 0.0)      # a hover craft's hull floats: so does its hit box
	add_child(cs)
	if VehicleWeapons.has_weapon(k):
		weapons = VehicleWeapons.new()
		weapons.setup(self)
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
	ai_panic = 0.0
	ai_stun = 0.0
	yielding = false
	at_light = false
	visual.set_deform(0.0)
	driver_is_player = false
	braking = false
	steer_in = 0.0
	slip = 0.0
	hits = 0
	lean = 0.0
	bob = 0.0
	patrol = bool(spec.get("patrol", false))
	dmg_state = 0
	chasing = false
	ram_hits = 0
	nitro = 1.0
	fuse = -1.0
	boosting = false
	_nitro_wait = 0.0
	if weapons != null:
		weapons.reload_full()
	_prev_h = h
	_fx_t = 0.0
	_stuck = 0.0
	_rev = 0.0
	_ram_cd = 0.0
	_warned = 0
	_steer_vis = 0.0
	_lean_p = 0.0
	_lean_r = 0.0
	_last_vf = 0.0
	heading = h
	global_position = Vector3(pos.x, 0.0, pos.z)
	rotation = Vector3(0.0, h, 0.0)
	_heading_set = h
	visual.model.rotation = Vector3.ZERO
	visual.model.position = Vector3(0.0, 0.0, 0.0)
	var ci := randi() % VehicleSpecs.COLORS.size()
	visual.set_paint(VehicleSpecs.COLORS[ci])
	paint_i = ci
	_drift_t = 9.0
	drifting = false
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
	chasing = false
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


## Makes this car the player's garage car: tuned spec, hit points, mounted weapon and paint from `g` (call after activate()).
func apply_garage(g: Garage) -> void:
	garage_car = true
	spec = g.tuned_spec()
	max_hp = float(spec["hp"])
	hp = max_hp
	var wd := g.weapon_def()
	if not wd.is_empty():
		if weapons == null:
			weapons = VehicleWeapons.new()
			weapons.setup(self)
		weapons.def = wd
		weapons.reload_full()
	paint_i = g.paint
	visual.set_paint(VehicleSpecs.COLORS[g.paint])


func _reset_garage() -> void:
	if not garage_car:
		return
	garage_car = false
	spec = VehicleSpecs.SPECS[kind]
	max_hp = float(spec["hp"])
	hp = max_hp
	if weapons != null:
		if VehicleWeapons.has_weapon(kind):
			weapons.setup(self)
		else:
			weapons = null


func deactivate() -> void:
	_reset_garage()
	wreck = false
	active = false
	driver_is_player = false
	ai = false
	chasing = false
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


## The player takes the wheel (VehicleManager.enter): door sound, a patrol vehicle stops being one, lights on at once.
func on_enter() -> void:
	patrol = false
	chasing = false
	lean = 0.0
	Sfx.play(&"car_door", -6.0)
	_apply_lights()


## The player leaves the wheel (VehicleManager.exit_vehicle): the car keeps a share of its speed and rolls to a stop (no input), a bike drops its lean.
func on_exit() -> void:
	vel *= VehicleSpecs.EXIT_BRAKE
	speed *= VehicleSpecs.EXIT_BRAKE
	Sfx.play(&"car_door", -6.0)
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
	else:
		visual.set_damage_look(1.0 - hp / maxf(max_hp, 1.0))
		visual.set_deform(1.0 - hp / maxf(max_hp, 1.0))
		_update_damage_state()


## 0 sound, 1 smoking below 40 % hp, 2 burning below 15 % hp.
static func state_for(hp_now: float, hp_max: float) -> int:
	var f := hp_now / maxf(hp_max, 1.0)
	if f < VehicleSpecs.FIRE_BELOW:
		return 2
	return 1 if f < VehicleSpecs.SMOKE_BELOW else 0


func damage_state() -> int:
	return dmg_state


func _update_damage_state() -> void:
	var ns := state_for(hp, max_hp)
	if fuse >= 0.0:
		ns = 2                                              # a lit fuse keeps the fire going
	if ns == dmg_state:
		return
	dmg_state = ns
	if ns == 2:
		visual.set_glow(Color(1.0, 0.42, 0.08))                 # the underglow turns into the colour of the fire
	if driver_is_player and ns > _warned:
		_warned = ns
		Game.say("ENGINE ON FIRE · GET OUT" if ns == 2 else "ENGINE DAMAGED", 1.8)
	damage_state_changed.emit(self, ns)


## Smoke and fire: pooled FX bursts only while the player is near (or driving it); fire also burns hp until the car blows up.
func _damage_fx(dt: float) -> void:
	if dmg_state == 0 or dead or not active:
		return
	if dmg_state == 2:
		damage(VehicleSpecs.BURN_DPS * dt)
		if dead:
			return
	if _dist > VehicleSpecs.FX_RANGE and not driver_is_player:
		return
	_fx_t -= dt
	if _fx_t > 0.0:
		return
	_fx_n += 1
	var at := global_position + forward() * float(spec["len"]) * 0.3 + Vector3(0.0, float(spec["hgt"]) * 0.75 + float(spec.get("hover_h", 0.0)), 0.0)
	if dmg_state == 2:
		_fx_t = VehicleSpecs.FIRE_EVERY
		FX.burst(at, Color(1.0, 0.5, 0.14, 0.9), 4, 2.4, 0.5, -5.0, 1.3)
		if _fx_n % 2 == 0:
			FX.burst(at + Vector3(0.0, 0.5, 0.0), Color(0.08, 0.08, 0.09, 0.8), 2, 1.6, 1.2, -2.5, 1.9)
	else:
		_fx_t = VehicleSpecs.SMOKE_EVERY
		FX.burst(at, Color(0.35, 0.35, 0.37, 0.7), 2, 1.5, 1.1, -2.0, 1.7)


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
	dmg_state = 3
	damage_state_changed.emit(self, 3)
	Game.explode(pos + Vector3(0.0, 1.0, 0.0), 9.0, {"enemy_dmg": 80.0, "car_dmg": 70.0, "player_dmg": 35.0, "color": Color(1.0, 0.54, 0.19)})
	Game.add_heat(VehicleSpecs.CARJACK_HEAT)
	_chain_ignite(pos)
	exploded.emit(self)
	if mgr != null:
		mgr.on_destroyed(self)


## Chain reaction: every other live car within CHAIN_RADIUS of a blast catches fire and blows up CHAIN_DELAY (staggered by distance) seconds later.
func _chain_ignite(pos: Vector3) -> void:
	var mgr := manager as VehicleManager
	if mgr == null:
		return
	for o in mgr.list:
		if o == self or o.dead or not o.active or o.wreck:
			continue
		var d := o.global_position.distance_to(pos)
		if d <= VehicleSpecs.CHAIN_RADIUS:
			o.ignite(VehicleSpecs.CHAIN_DELAY * (0.4 + 0.6 * d / VehicleSpecs.CHAIN_RADIUS))


## Sets the car alight: it burns and explodes after `delay` seconds (the earliest fuse wins).
func ignite(delay: float) -> void:
	if dead or not active:
		return
	if fuse < 0.0 or delay < fuse:
		fuse = delay
	if dmg_state < 2:
		dmg_state = 2
		damage_state_changed.emit(self, 2)


## Horizontal distance from `pos` to the hull (an oriented box of the spec's length and width): 0 inside it. A long bus is reached at its flank, not its middle.
func edge_distance(pos: Vector3) -> float:
	var d := pos - global_position
	var lx := absf(d.dot(right()))
	var lz := absf(d.dot(forward()))
	var dx := maxf(lx - float(spec["wid"]) * 0.5, 0.0)
	var dz := maxf(lz - float(spec["len"]) * 0.5, 0.0)
	return sqrt(dx * dx + dz * dz)


# --- simulation --------------------------------------------------------------------------------------------------------

## One physics tick (called by the manager while Game.is_playing()).
func sim(dt: float) -> void:
	if fuse >= 0.0:
		fuse -= dt
		if fuse < 0.0:
			explode()
			return
	if driver_is_player:
		step_drive(dt, Input.get_axis(&"move_back", &"move_forward"), Input.get_axis(&"move_left", &"move_right"), Input.is_action_pressed(&"jump"), Input.is_action_pressed(&"sprint"))
		if weapons != null:
			weapons.tick(dt, Input.is_action_pressed(&"fire"))
	elif chasing:
		_chase_step(dt)
	elif ai:
		_ai_step(dt)
	else:
		_coast(dt)
	_sync(dt)
	_damage_fx(dt)


## Arcade driving (src/vehicles.js drive()): thr -1..1 (brake / reverse .. throttle), steer -1..1 (left .. right), handbrake.
func step_drive(dt: float, thr: float, steer: float, handbrake: bool, boost := false) -> void:
	var T := spec
	var vmax: float = T["max"]
	var acc_k := 1.0
	boosting = boost and thr > 0.05 and nitro > (0.0 if boosting else VehicleSpecs.NITRO_MIN)
	if boosting:
		nitro = maxf(0.0, nitro - VehicleSpecs.NITRO_DRAIN * dt)
		_nitro_wait = VehicleSpecs.NITRO_DELAY
		vmax *= VehicleSpecs.NITRO_SPEED
		acc_k = VehicleSpecs.NITRO_ACC
		if nitro <= 0.0:
			boosting = false
	else:
		_nitro_wait -= dt
		if _nitro_wait <= 0.0:
			nitro = minf(1.0, nitro + VehicleSpecs.NITRO_REGEN * dt)
	var fwd := forward()
	var rgt := right()
	var fwd0 := fwd
	var rgt0 := rgt
	var vf := vel.dot(fwd)
	var vl := vel.dot(rgt)
	if thr > 0.05:
		vf += float(T["acc"]) * acc_k * thr * (1.0 - maxf(0.0, vf) / vmax) * dt
	elif thr < -0.05:
		vf += (-float(T["brake"]) if vf > 0.5 else -float(T["acc"]) * 0.45) * -thr * dt
	else:
		vf *= exp(-float(T.get("coast", VehicleSpecs.COAST_DRAG)) * dt)
	if handbrake:
		vf *= exp(-VehicleSpecs.HANDBRAKE_DRAG * dt)
	var base_max: float = T["max"]
	if not boosting and vf > base_max:
		vf = maxf(base_max, vf - VehicleSpecs.NITRO_COOL * dt)
	vf = clampf(vf, -base_max * VehicleSpecs.REVERSE_FRACTION, vmax)
	var auth := clampf(absf(vf) / 5.0, 0.0, 1.0) / (1.0 + absf(vf) / 38.0)
	if cls == &"bike":
		auth *= 1.0 + 0.3 * absf(lean) / maxf(float(T["lean_max"]), 0.1)      # a leaning bike turns in tighter
		vf *= 1.0 - 0.06 * absf(lean) * dt                                      # and scrubs a little speed
	heading -= steer * VehicleSpecs.STEER_RATE * float(T.get("steer", 1.0)) * auth * (1.0 if vf >= 0.0 else -1.0) * dt
	var grip: float = float(T["grip"])
	if handbrake:
		grip = VehicleSpecs.HANDBRAKE_GRIP * (0.45 if cls == &"hover" else 1.0)
		_drift_t = 0.0
	else:
		# a slide ends gradually: traction returns over DRIFT_RECOVER s instead of snapping back (a controllable, linkable drift)
		_drift_t += dt
		grip = lerpf(VehicleSpecs.HANDBRAKE_GRIP * 1.6, grip, clampf(_drift_t / VehicleSpecs.DRIFT_RECOVER, 0.0, 1.0))
		# counter-steer assist: steering against the slide turns the nose back faster
		if absf(vl) > 3.0 and steer * vl > 0.0 and cls == &"car":
			heading -= steer * VehicleSpecs.DRIFT_ASSIST * clampf(absf(vl) / 12.0, 0.0, 1.0) * dt
	vl *= exp(-grip * dt)
	drifting = absf(vl) > VehicleSpecs.SMOKE_SLIP and absf(vf) > 6.0 and cls != &"hover"
	fwd = forward()
	rgt = right()
	vel = fwd * vf + rgt * vl
	if cls == &"hover":                                  # a hover craft keeps part of its old momentum while the nose swings round: it drifts
		var share := clampf(float(T.get("drift", 0.0)) * (0.8 if handbrake else 0.3), 0.0, 0.9)
		vel = vel.lerp(fwd0 * vf + rgt0 * vl, share)
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
	slip = vel.dot(right())
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
	var siren := is_emergency()
	var blocked := _blocked(fx, fz, siren)
	ai_panic = maxf(ai_panic - dt, 0.0)
	ai_stun = maxf(ai_stun - dt, 0.0)
	var u0 := global_position.x if ai_axis == 0 else global_position.z
	at_light = not blocked and _light_blocks(u0)
	if siren:
		yielding = false
	else:
		_yield_t -= dt
		yielding = _siren_behind()
	var want := ai_cruise
	if siren:
		want *= VehicleSpecs.SIREN_SPEED
		_chase_siren(dt)
	elif ai_panic > 0.0:
		want *= VehicleSpecs.PANIC_SPEED
	if yielding:
		want = minf(want, VehicleSpecs.YIELD_SPEED)
	var halt := blocked or at_light or ai_stun > 0.0
	ai_speed = _damp(ai_speed, 0.0 if halt else want, 5.0 if halt else 1.5, dt)
	blocked = blocked or at_light or ai_stun > 0.0
	var p := global_position
	var ox := p.x
	var oz := p.z
	var prev_u := ox if ai_axis == 0 else oz
	var step := float(ai_dir) * ai_speed * dt
	var line := ai_line + (VehicleSpecs.lane_offset(ai_axis, ai_dir, VehicleSpecs.YIELD_SHIFT) if yielding else 0.0)
	if ai_axis == 0:
		p.x += step
		p.z = _damp(p.z, line, 2.5, dt)
	else:
		p.z += step
		p.x = _damp(p.x, line, 2.5, dt)
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
func _blocked(fx: float, fz: float, siren := false) -> bool:
	var me := global_position
	var side := VehicleSpecs.AI_SIDE * (0.6 if siren else 1.0)       # a siren car squeezes past a yielding car
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"vehicle") == null and absf(pl.global_position.y - me.y) < 3.0:
		if _ahead(pl.global_position - me, fx, fz, side):
			return true
	var mgr := manager as VehicleManager
	if mgr != null:
		for o in mgr.list:
			if o != self and o.active and not o.dead and _ahead(o.global_position - me, fx, fz, side):
				return true
	return false


func _ahead(r: Vector3, fx: float, fz: float, half := VehicleSpecs.AI_SIDE) -> bool:
	var ahead := r.x * fx + r.z * fz
	var side := absf(r.x * fz - r.z * fx)
	return ahead > 0.0 and ahead < VehicleSpecs.AI_LOOK and side < half


## A siren car: an interceptor or ambulance in traffic, or a chasing Vael patrol. It ignores lights and the others yield to it.
func is_emergency() -> bool:
	return active and not dead and not driver_is_player and ((ai and VehicleSpecs.is_siren(kind)) or (patrol and chasing))


## The junction ahead shows red (or amber too far to stop at) and this car has not yet reached its stop distance. Panicking cars and sirens ignore lights.
func _light_blocks(u: float) -> bool:
	if ai_panic > 0.0 or is_emergency():
		return false
	var mgr := manager as VehicleManager
	if mgr == null or not mgr.lights_on:
		return false
	var idx_f := (u + Game.HALF) / Game.PITCH
	var ci := ceili(idx_f) if ai_dir > 0 else floori(idx_f)
	if ci < 0 or ci > Game.N:
		return false
	var d := (VehicleSpecs.road_center(ci) - u) * float(ai_dir)
	if d <= VehicleSpecs.LIGHT_COMMIT or d > VehicleSpecs.LIGHT_LOOK:
		return false
	var st := VehicleSpecs.signal_state(ai_axis, mgr.signal_clock)
	return st == 2 or (st == 1 and d > VehicleSpecs.AMBER_STOP)


## True while a siren car is behind or beside this one on the same road, within YIELD_RANGE (checked a few times a second, the answer is held).
func _siren_behind() -> bool:
	if _yield_t > 0.0:
		return yielding
	_yield_t = 0.2
	var mgr := manager as VehicleManager
	if mgr == null:
		return false
	var me := global_position
	var fx := float(ai_dir) if ai_axis == 0 else 0.0
	var fz := float(ai_dir) if ai_axis == 1 else 0.0
	for o in mgr.list:
		if o == self or not o.is_emergency():
			continue
		var r := o.global_position - me
		var along := r.x * fx + r.z * fz
		var across := absf(r.x * fz - r.z * fx)
		if along < 6.0 and along > -VehicleSpecs.YIELD_RANGE and across < 8.0:
			return true
	return false


## Horn, gunfire or a crash at `pos` (VehicleManager.hear): traffic reacts. Gunfire sends cars fleeing, a horn makes the car ahead of it hurry on, a crash stops cars nearby for a moment.
func hear(pos: Vector3, what: StringName) -> void:
	if not ai or not active or dead or driver_is_player or is_emergency():
		return
	var r := pos - global_position
	r.y = 0.0
	var d := r.length()
	match what:
		&"gun":
			if d < VehicleSpecs.GUN_HEAR:
				ai_panic = VehicleSpecs.PANIC_TIME
				reactions += 1
		&"horn":
			var f := Vector3(float(ai_dir) if ai_axis == 0 else 0.0, 0.0, float(ai_dir) if ai_axis == 1 else 0.0)
			if d < VehicleSpecs.HORN_HEAR and r.dot(f) < 0.0:               # the horn sounds behind this car
				ai_panic = maxf(ai_panic, VehicleSpecs.HORN_NUDGE)
				reactions += 1
		&"crash":
			if d < VehicleSpecs.CRASH_HEAR:
				ai_stun = VehicleSpecs.STUN_TIME
				reactions += 1


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


# --- Vael patrol chase ---------------------------------------------------------------------------------------------------

## Drive at the player (his vehicle when he drives): steer towards him, back out when stuck on a wall, ram him when close. Siren colours flash on the lamps.
func _chase_step(dt: float) -> void:
	var pl := Game.player
	if not is_instance_valid(pl):
		_coast(dt)
		return
	var real := pl.global_position - global_position
	real.y = 0.0
	var dist := real.length()
	var goal := chase_goal()
	var to := goal - global_position
	to.y = 0.0
	var err := wrapf(atan2(-to.x, -to.z) - heading, -PI, PI)
	var holding := tactic == &"block" and to.length() < VehicleSpecs.BLOCK_STOP
	if holding:                                              # roadblock: stop and turn broadside to the target
		var face := wrapf(atan2(-real.x, -real.z) + PI * 0.5 - heading, -PI, PI)
		step_drive(dt, -1.0 if speed > 1.0 else 0.0, clampf(-face * 2.0, -1.0, 1.0), false)
		_chase_siren(dt)
		if dist < 3.4 and absf(speed) > 6.0 and _ram_cd <= 0.0:
			_ram(pl)
		return
	var thr := 1.0
	var steer := clampf(-err * 2.4, -1.0, 1.0)
	if _rev > 0.0:
		_rev -= dt
		thr = -1.0
		steer = -steer
	else:
		if absf(err) > 1.9 and dist < 30.0:
			thr = 0.45                                       # he is behind: swing round
		if absf(speed) < 2.0 and dist > 6.0:
			_stuck += dt
			if _stuck > 1.1:
				_stuck = 0.0
				_rev = 0.9
		else:
			_stuck = 0.0
	step_drive(dt, thr, steer, false, tactic == &"ram" and dist > 25.0)
	_ram_cd -= dt
	if dist < 3.4 and absf(speed) > 6.0 and _ram_cd <= 0.0:
		_ram(pl)
	_chase_siren(dt)


func _chase_siren(dt: float) -> void:
	_siren_t -= dt
	if _siren_t <= 0.0:
		_siren_t = 0.25
		_siren_i = 1 - _siren_i
		visual.set_glow(VehicleSpecs.PATROL_SIREN[_siren_i])


## Where the pursuit tactic wants the patrol to be: ram = his position, boxin = a point beside him (the side we are already on), block = ahead of his motion.
func chase_goal() -> Vector3:
	var pl := Game.player
	var pp := pl.global_position
	var pv := Vector3.ZERO
	var pcar: Object = pl.get(&"vehicle")
	if pcar is Vehicle:
		pv = (pcar as Vehicle).vel
	pv.y = 0.0
	var sp := pv.length()
	if sp < 3.0 or tactic == &"ram":
		return pp
	var dir := pv / sp
	var side := Vector3(-dir.z, 0.0, dir.x)
	if tactic == &"boxin":
		var s := 1.0 if (global_position - pp).dot(side) >= 0.0 else -1.0
		if (global_position - pp).dot(dir) > 2.0:                  # behind him: first come up alongside
			return pp + side * s * VehicleSpecs.BOXIN_SIDE - dir * 0.0
		return pp + side * s * (VehicleSpecs.BOXIN_SIDE * 0.55)    # alongside: squeeze in
	return pp + dir * (VehicleSpecs.BLOCK_AHEAD * clampf(sp / 25.0, 0.6, 1.4))


## A ram: the player (or the car he drives, through Player.damage) loses PATROL_RAM_DAMAGE, the patrol rebounds.
func _ram(pl: Node) -> void:
	_ram_cd = VehicleSpecs.PATROL_RAM_COOLDOWN
	ram_hits += 1
	if pl.has_method(&"damage"):
		pl.call(&"damage", VehicleSpecs.PATROL_RAM_DAMAGE, global_position)
	vel *= -0.35
	speed = vel.dot(forward())
	FX.burst(global_position + Vector3(0.0, 0.9, 0.0) + forward() * 2.0, Color(0.6, 1.0, 0.4), 8, 5.0, 0.3, 8.0, 0.3)
	Sfx.play_at(&"hit", global_position, -3.0)


# --- visuals ------------------------------------------------------------------------------------------------------------

func _sync(dt: float) -> void:
	if _heading_set != heading:
		rotation.y = heading
		_heading_set = heading
	var moving := absf(speed) > 0.05
	if moving or absf(_steer_vis) > 0.01:
		_steer_vis = _damp(_steer_vis, steer_in * 0.5, 10.0, dt)
		visual.spin(speed * dt, _steer_vis)
	if cls == &"bike":
		_sync_bike(dt)
	elif cls == &"hover":
		_sync_hover(dt)
	elif driver_is_player:
		var acc := (speed - _last_vf) / maxf(dt, 0.0001)
		_lean_p = _damp(_lean_p, clampf(acc * 0.0016, -0.035, 0.035), 6.0, dt)
		_lean_r = _damp(_lean_r, clampf(-slip * 0.01, -0.06, 0.06), 6.0, dt)
		visual.model.rotation = Vector3(_lean_p, 0.0, _lean_r)
	_last_vf = speed
	_prev_h = heading
	_apply_lights()
	_finish_fx(dt)


## Bike: the body rolls into the turn, lean = atan(v * yaw rate / g), for the player's bike and for traffic alike.
func _sync_bike(dt: float) -> void:
	var yaw_rate := wrapf(heading - _prev_h, -PI, PI) / maxf(dt, 0.0001)
	var want := clampf(atan(-yaw_rate * speed / 9.8), -float(spec["lean_max"]), float(spec["lean_max"]))
	lean = _damp(lean, want, 8.0, dt)
	var acc := (speed - _last_vf) / maxf(dt, 0.0001)
	_lean_p = _damp(_lean_p, clampf(-acc * 0.002, -0.07, 0.07), 6.0, dt)       # nose lifts when accelerating
	visual.model.rotation = Vector3(_lean_p, 0.0, -lean)


## Hover craft: rides at hover_h (the model has its underside at hover_h baked in, so only the bob moves it) and bobs on two slow sine waves (stronger when moving), pitching with throttle and rolling into a slide.
func _sync_hover(dt: float) -> void:
	_bob_t += dt
	var amp := float(spec["bob"]) * (0.6 + 0.4 * clampf(absf(speed) / 20.0, 0.0, 1.0))
	bob = sin(_bob_t * 2.3 + float(get_instance_id() % 7)) * amp + sin(_bob_t * 5.1) * amp * 0.25
	var acc := (speed - _last_vf) / maxf(dt, 0.0001)
	_lean_p = _damp(_lean_p, clampf(acc * 0.0014, -0.05, 0.05) + sin(_bob_t * 1.7) * 0.012, 6.0, dt)
	_lean_r = _damp(_lean_r, clampf(-slip * 0.012, -0.14, 0.14) + sin(_bob_t * 1.3) * 0.01, 6.0, dt)
	visual.model.position = Vector3(0.0, bob, 0.0)
	visual.model.rotation = Vector3(_lean_p, 0.0, _lean_r)


## Finish and tyre smoke, only for cars near the player: thin-film / flicker shimmer, wet gloss, drift smoke from the rear tyres.
func _finish_fx(dt: float) -> void:
	_fin_t += dt
	if _dist < 60.0 or driver_is_player:
		_fin_acc += dt
		if _fin_acc > 0.1:
			_fin_acc = 0.0
			visual.shimmer(_fin_t, speed)
			var atm := Game.atmosphere as Atmosphere                   # not RenderingServer.global_shader_parameter_get: editor only, an error per call on a device
			visual.set_wet(atm.wetness_now if atm != null else 0.0)
		if drifting and (driver_is_player or _dist < VehicleSpecs.FX_RANGE * 0.6):
			_smoke_t -= dt
			if _smoke_t <= 0.0:
				_smoke_t = VehicleSpecs.TYRE_SMOKE_EVERY
				var back := -forward() * float(spec["len"]) * 0.32
				var side := right() * float(spec["wid"]) * 0.4
				var c := Color(0.8, 0.82, 0.86, 0.55)
				FX.burst(global_position + back + side + Vector3(0.0, 0.2, 0.0), c, 2, 1.2, 0.8, -1.0, 2.2)
				FX.burst(global_position + back - side + Vector3(0.0, 0.2, 0.0), c, 2, 1.2, 0.8, -1.0, 2.2)


## Lights follow the state: parked cars glow faintly, moving ones show full headlights, brake lights flare.
func _apply_lights() -> void:
	if driver_is_player or ai or chasing:
		visual.set_lights(0.9, 1.0 if braking else 0.5, 1.4 if cls == &"hover" else 1.0)
	else:
		visual.set_lights(0.1, 0.35, 0.3)


## Level of detail from the distance to the player (the manager calls it a few times a second).
func update_lod(dist: float) -> void:
	_dist = dist
	visual.set_wheels_visible(dist < VehicleSpecs.WHEELS_NEAR)
	visual.set_shadow(Game.quality >= 1 and dist < PerfTiers.shadow_range() + (4.0 if visual.shadow_on else 0.0))
	visual.set_model_lights(dist < PerfTiers.light_range(Game.quality) + (4.0 if visual.lights_on else 0.0))
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
