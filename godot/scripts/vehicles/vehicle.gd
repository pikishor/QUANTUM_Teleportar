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
var cop := false                    ## a police interceptor of the pursuit ladder (VehicleManager._tick_cops): patrol-style chase, shadows the hero below COP_RAM_HEAT
var tires_flat := 0.0               ## s: tyres shot by a spike strip (top speed x TIRES_SPEED, grip x TIRES_GRIP)
var passengers := 0                 ## people riding along in a traffic car (thrown out with the driver by a hijack)
var ram_hits := 0                   ## patrol rams that landed (tests)
var tactic: StringName = &"ram"      ## patrol pursuit tactic (VehicleSpecs.TACTICS)
var weapons: VehicleWeapons         ## mounted weapon (sport / suv / hover), null on other kinds
var craft: VehicleCraft.State       ## roster craft (helicopter, plane, boat, tank): their own physics state, null on cars, bikes and hover craft
var base_y := 0.0                   ## height of the node when it rests (0, a boat floats at the flood level minus its draft)
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
const PANELS_PER_CAR := 3
var _panels_torn := 0
var _leak_t := 0.0
var _dist := 0.0                    ## distance to the player (update_lod)
var _stuck := 0.0
var _wedge_t := 0.0                ## seconds the player held the throttle without the car moving
var _crash_age := 99.0              ## seconds since the last crash (a car that just hit something and crawls at 1-4 km/h is wedged, a car pulling away from a light is not)
var _nudge_t := 0.0                ## seconds of automatic reverse left
var _nudge_steer := 0.0
var wedge_count := 0               ## how many times the car backed itself out (tests, stats)
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
## --- the car model (cars only, see _drive_car): gearbox, tyres, body motion, damage details ---
var gear := 1                       ## 1..5 (the box shifts by itself)
var rpm := 0.16                     ## 0..1 of the redline: the engine note, the HUD
var yaw_rate := 0.0                 ## rad/s, + = turning left (the heading grows)
var steer_angle := 0.0              ## front wheel angle in rad, + = left (visual and model)
var long_acc := 0.0                 ## smoothed longitudinal acceleration m/s2 (+ = speeding up)
var lat_acc := 0.0                  ## smoothed lateral acceleration m/s2 (+ = to the left)
var skid := 0.0                     ## 0..1 how hard the tyres are sliding or spinning (squeal, smoke, skid marks)
var wheelspin := 0.0                ## 0..1 the driven wheels break loose under power
var last_impact := 0.0              ## closing speed (m/s) of the last collision that counted
var impact_t := 99.0                ## seconds since then
var crashes := 0                    ## collisions that hurt the hull (tests, stats)
var _shift_t := 0.0
var _shift_cool := 0.0
var _ax := 0.0
var _pitch := 0.0
var _pitch_v := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _heave := 0.0
var _heave_v := 0.0
var _road_t := 0.0                  ## s until the next road seam / patch the suspension rides over (a small kick of the body, bigger with speed)
var _spin_fx := 0.0


## One-time construction: model, collider, MirrorProxy.
func setup(k: StringName, mgr: Node) -> void:
	kind = k
	spec = VehicleSpecs.SPECS[k]
	manager = mgr
	max_hp = spec["hp"]
	hp = max_hp
	cls = VehicleSpecs.cls_of(k)
	patrol = bool(spec.get("patrol", false))
	if VehicleCraft.is_craft(cls):
		craft = VehicleCraft.State.new()
	if cls == &"boat":
		base_y = FloodZone.LEVEL - float(spec.get("draft", 0.35))
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
	var foot := 0.0 if (cls == &"heli" or cls == &"plane") else 0.2         # an aircraft rests on its skids / wheels: its hit box starts at the node
	cs.position = Vector3(0.0, foot + h * 0.5 + float(spec.get("hover_h", 0.0)), 0.0)      # a hover craft's hull floats: so does its hit box
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
	if visual != null:
		visual.restore_wheels()
	_panels_torn = 0
	_leak_t = 0.0
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
	driver_is_player = false
	braking = false
	steer_in = 0.0
	slip = 0.0
	hits = 0
	lean = 0.0
	bob = 0.0
	patrol = bool(spec.get("patrol", false))
	cop = false
	tires_flat = 0.0
	passengers = 0
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
	global_position = Vector3(pos.x, base_y, pos.z)
	rotation = Vector3(0.0, h, 0.0)
	_heading_set = h
	if craft != null:
		craft.reset(h)
	visual.model.rotation = Vector3.ZERO
	visual.model.position = Vector3(0.0, 0.0, 0.0)
	var ci := randi() % VehicleSpecs.COLORS.size()
	visual.set_paint(VehicleSpecs.COLORS[ci])
	paint_i = ci
	_drift_t = 9.0
	drifting = false
	gear = 1
	rpm = VehicleSpecs.IDLE_RPM
	yaw_rate = 0.0
	steer_angle = 0.0
	long_acc = 0.0
	lat_acc = 0.0
	skid = 0.0
	wheelspin = 0.0
	last_impact = 0.0
	impact_t = 99.0
	crashes = 0
	_shift_t = 0.0
	_shift_cool = 0.0
	_ax = 0.0
	_pitch = 0.0
	_pitch_v = 0.0
	_roll = 0.0
	_roll_v = 0.0
	_heave = 0.0
	_heave_v = 0.0
	visual.repair()
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
	if craft != null:                                        # a craft that blows up in the air lands where it was, as a husk
		global_position.y = base_y
		craft.airborne = false
		craft.spool = 0.0
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
	if visual != null:
		visual.restore_wheels()
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
	passengers = mini(randi() % maxi(VehicleSpecs.seats_of(kind), 1), 3) if cls == &"car" else 0
	_apply_lights()


## The player takes the wheel (VehicleManager.enter): door sound, a patrol vehicle stops being one, lights on at once.
func on_enter() -> void:
	patrol = false
	cop = false
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


## The direction a mounted weapon fires in (the nose, or the crosshair for the roster craft) and where the round starts.
func aim_dir() -> Vector3:
	return VehicleCraft.aim_dir(self) if craft != null else forward()


func muzzle_pos() -> Vector3:
	return VehicleCraft.muzzle(self) if craft != null else global_position + forward() * float(spec["len"]) * 0.5 + Vector3(0.0, 0.7 + float(spec.get("hover_h", 0.0)), 0.0)


## True while a helicopter or plane is in the air: it passes over cars and people, and nothing on the ground rams or collides with it.
func is_aloft() -> bool:
	return craft != null and craft.airborne


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))


# --- damage -----------------------------------------------------------------------------------------------------------

## The damage contract (see the player section): weapon hits, explosions and fire. Crashes go through crash() (speed, angle, mass and dents).
func damage(amount: float) -> void:
	if dead or not active or amount <= 0.0:
		return
	_hurt(amount * VehicleSpecs.EXTERNAL_DAMAGE)
	if amount >= 45.0 and not dead and _dist < 60.0:             # a big blast leaves its dents on the panels facing it
		var lp := Vector3(randf_range(-0.7, 0.7), float(spec["hgt"]) * 0.5, randf_range(-1.0, 1.0) * float(spec["len"]) * 0.4)
		visual.add_dent(lp, Vector3(-signf(lp.x), 0.0, 0.0), clampf(amount / max_hp, 0.05, 0.4))
		tear_panel_now(lp, Vector3(signf(lp.x), 0.3, 0.0))              # ...and a panel is torn off it


## A wheel flies off (CarDebris: it bounces and rolls away). `i` = which wheel, -1 = a random one that is still on. Returns false when there is none or the car is far away.
func shed_wheel_now(i := -1) -> bool:
	if visual == null or visual.wheels.is_empty() or FX.car_debris == null or (_dist > 60.0 and not driver_is_player):
		return false
	var idx := i
	if idx < 0:
		var open: Array[int] = []
		for k in visual.wheels.size():
			if not visual.wheel_shed(k):
				open.append(k)
		if open.is_empty():
			return false
		idx = open[randi() % open.size()]
	var w: Node3D = visual.wheels[idx]
	var out := global_transform.basis * Vector3(signf(w.position.x) if absf(w.position.x) > 0.05 else 1.0, 0.0, 0.0)
	FX.car_debris.shed_wheel(w.global_transform, vel * 0.6 + out * randf_range(2.5, 5.0) + Vector3.UP * randf_range(3.0, 6.0), visual.wheel_radius)
	visual.shed_wheel(idx)
	FX.burst(w.global_position, Color(1.0, 0.8, 0.45), 8, 5.0, 0.35, 9.0, 0.8)
	Sfx.impact(&"metal", w.global_position, Vector3.UP)
	return true


## A body panel is torn off at the local point `local_at`, flying the way `local_dir` points (out of the car); at most PANELS_PER_CAR per car.
func tear_panel_now(local_at: Vector3, local_dir: Vector3) -> bool:
	if visual == null or FX.car_debris == null or _panels_torn >= PANELS_PER_CAR or (_dist > 60.0 and not driver_is_player):
		return false
	_panels_torn += 1
	var sz := Vector3(float(spec["wid"]) * 0.45, 0.05, float(spec["len"]) * 0.22)
	var out := (global_transform.basis * Vector3(local_dir.x, 0.0, local_dir.z).normalized())
	if out.length() < 0.1:
		out = Vector3.UP
	FX.car_debris.tear_panel(to_global(local_at), vel * 0.5 + out * randf_range(3.0, 6.5) + Vector3.UP * randf_range(4.0, 8.0), visual.get_paint(), sz, global_transform.basis)
	FX.burst(to_global(local_at), Color(1.0, 0.75, 0.4), 6, 4.5, 0.3, 9.0, 0.7)
	return true


## Takes `amount` hit points off the hull and updates what shows: wear, the windows, smoke and fire (an explosion only when the hull is gone).
func _hurt(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		explode()
		return
	var f := 1.0 - hp / maxf(max_hp, 1.0)
	if f > 0.62 and visual.wheels_lost() < 1:
		shed_wheel_now()                                            # a badly hurt car loses a wheel
	visual.set_damage_look(f)
	visual.set_deform(f)
	visual.set_condition(f)
	_update_damage_state()


## The mechanic: full hull, dents hammered out, glass replaced, smoke and fire out, the fuse of a chain reaction cut. Works on a car in play (a repair bay, the garage, a pickup).
func repair() -> void:
	if dead or wreck:
		return
	hp = max_hp
	fuse = -1.0
	_warned = 0
	visual.repair()
	if dmg_state != 0:
		dmg_state = 0
		damage_state_changed.emit(self, 0)
	visual.set_glow(VehicleSpecs.GLOWS[randi() % VehicleSpecs.GLOWS.size()])
	last_impact = 0.0


## Look-dev and tests: the car as it looks after a crash that took `frac` of its hull (a frontal dent, a side dent, wear, cracked glass, smoke or fire by the hp).
func debug_damage(frac: float) -> void:
	hp = max_hp * (1.0 - frac)
	var ln := float(spec["len"])
	var wd := float(spec["wid"])
	visual.add_dent(Vector3(0.25, 0.65, -ln * 0.5), Vector3(0.0, 0.0, 1.0), frac)
	visual.add_dent(Vector3(wd * 0.5, 0.7, -ln * 0.12), Vector3(-1.0, 0.0, 0.0), frac * 0.8)
	visual.set_damage_look(frac)
	visual.set_deform(frac)
	visual.set_condition(frac)
	_update_damage_state()


## Damage fraction (0..1 of CRASH_REF_HP) of a collision at closing speed `v` m/s along the contact normal: nothing below CRASH_SAFE, then growing steeply.
static func crash_fraction(v: float) -> float:
	if v <= VehicleSpecs.CRASH_SAFE:
		return 0.0
	return pow(clampf((v - VehicleSpecs.CRASH_SAFE) / (VehicleSpecs.CRASH_WRECK - VehicleSpecs.CRASH_SAFE), 0.0, 1.5), VehicleSpecs.CRASH_POWER)


## A collision at `at` (world) with the surface normal `n` pointing INTO this car, closing speed `v` along it, against a body of `other_mass` kg (INF = a wall).
## The hull loses CRASH_REF_HP x crash_fraction(v) (a lighter car takes more from a heavy one), the panels dent at the contact, the windows crack on a hard hit and the
## driver (the hero) is hurt only by really hard impacts. Returns the hp lost.
func crash(v: float, at: Vector3, n: Vector3, other_mass := INF) -> float:
	var repeat := impact_t < VehicleSpecs.CRASH_REPEAT_GAP and v < last_impact * 1.25
	last_impact = maxf(v, last_impact) if repeat else v
	impact_t = 0.0
	if v <= VehicleSpecs.HIT_SPEED:
		return 0.0
	if repeat:
		return 0.0                                                   # the same crash, still grinding along the wall
	_heave_v -= clampf(v * 0.12, 0.0, 2.2)                       # the suspension compresses: the body drops and rebounds
	_pitch_v += clampf(v * 0.05, 0.0, 0.9) * (1.0 if forward().dot(n) < 0.0 else -1.0)
	var lost := 0.0
	var frac := crash_fraction(v)
	if frac > 0.0:
		var share := 1.0
		if other_mass < INF:
			share = clampf(2.0 * other_mass / (other_mass + VehicleSpecs.mass_of(kind)), 0.5, 1.8)
		lost = minf(VehicleSpecs.CRASH_REF_HP, max_hp) * frac * share          # a light car (sport 250 hp) loses the same SHARE of its hull as a sedan; a truck, bus or SUV loses less
		if v <= VehicleSpecs.CRASH_BUMP_V:
			lost = minf(lost, max_hp * VehicleSpecs.CRASH_BUMP_MAX)             # a street bump is a dent, not a write-off
		if v <= VehicleSpecs.CRASH_SURVIVE_V and hp > max_hp * VehicleSpecs.CRASH_LIMP_FROM:
			lost = minf(lost, hp - max_hp * VehicleSpecs.CRASH_LIMP_HP)        # a healthy car survives one crash and limps away: the player keeps the car he took
		hits += 1
		crashes += 1
		_crash_age = 0.0
		if driver_is_player:
			var pl := Game.player
			if v > VehicleSpecs.HERO_HURT_SPEED and is_instance_valid(pl) and not dead:
				var hurt_hp := VehicleSpecs.HERO_HURT_MAX * pow(clampf((v - VehicleSpecs.HERO_HURT_SPEED) / (VehicleSpecs.CRASH_WRECK - VehicleSpecs.HERO_HURT_SPEED), 0.0, 1.5), 2.0)
				if pl.get(&"max_hp") is float:
					hurt_hp = minf(hurt_hp, (pl.get(&"max_hp") as float) * VehicleSpecs.HERO_HURT_CAP)
				if pl.has_method(&"hurt_driver"):
					pl.call(&"hurt_driver", hurt_hp, at)
				elif pl.has_method(&"damage"):
					pl.call(&"damage", hurt_hp, at)
		var local_at := to_local(at)
		local_at.y = clampf(local_at.y, 0.25, float(spec["hgt"]))
		var local_dir := global_transform.basis.inverse() * n          # the way the panel is pushed: into the car
		local_dir.y = 0.0
		if _dist < 60.0 or driver_is_player:
			visual.add_dent(local_at, local_dir, frac)
		if frac > 0.28 and not dead:
			visual.crack_glass(clampf(frac * 1.6, 0.0, 1.0), local_at)
		if frac > 0.38 and not dead:
			tear_panel_now(local_at, local_dir)
		if frac > 0.75 and not dead and visual.wheels_lost() < 2:
			shed_wheel_now()
		_hurt(lost)
	return lost


## 0 sound, 1 smoking below 40 % hp, 2 burning below 15 % hp.
static func state_for(hp_now: float, hp_max: float) -> int:
	var f := hp_now / maxf(hp_max, 1.0)
	if f < VehicleSpecs.FIRE_BELOW:
		return 2
	return 1 if f < VehicleSpecs.SMOKE_BELOW else 0


func damage_state() -> int:
	return dmg_state


## The four stages a player sees: 0 sound, 1 a thin wisp from the bonnet (below 70 % hull), 2 dark smoke (below 40 %), 3 fire (below 15 %). Dents and cracked glass come with every hit.
static func stage_for(hp_now: float, hp_max: float) -> int:
	var f := hp_now / maxf(hp_max, 1.0)
	if f < VehicleSpecs.FIRE_BELOW:
		return 3
	if f < VehicleSpecs.SMOKE_BELOW:
		return 2
	return 1 if f < VehicleSpecs.WISP_BELOW else 0


func damage_stage() -> int:
	return 3 if fuse >= 0.0 else stage_for(hp, max_hp)


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
	if dead or not active:
		return
	var wisp := dmg_state == 0 and hp < max_hp * VehicleSpecs.WISP_BELOW
	if dmg_state == 0 and not wisp:
		return
	if dmg_state == 2:
		damage(VehicleSpecs.BURN_DPS * dt)
		if dead:
			return
	if _dist > VehicleSpecs.FX_RANGE and not driver_is_player:
		return
	_leak_t -= dt
	if _leak_t <= 0.0 and FX.marks != null and _dist < 45.0:                # a hurt car leaves a trail of oil on the street
		_leak_t = 1.6 if absf(speed) > 2.0 else 4.0
		if FX.marks.live_of(BlastMarks.K_OIL) >= 10:
			return
		FX.marks.oil(Vector3(global_position.x, 0.0, global_position.z) - forward() * float(spec["len"]) * 0.2, clampf(0.7 + 0.5 * (1.0 - hp / maxf(max_hp, 1.0)), 0.7, 1.5), 40.0)
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
	elif wisp:
		_fx_t = VehicleSpecs.SMOKE_EVERY * 2.4
		FX.burst(at, Color(0.62, 0.63, 0.66, 0.4), 1, 0.9, 1.3, -1.3, 1.1)           # a thin grey wisp: the engine is hurt, not dying
	else:
		_fx_t = VehicleSpecs.SMOKE_EVERY
		FX.burst(at, Color(0.22, 0.22, 0.24, 0.75), 3, 1.7, 1.3, -2.2, 2.0)


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
	if FX.car_debris != null and (_dist < 80.0 or driver_is_player):
		FX.car_debris.wreck(self)                                   # wheels and body panels fly off
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
	elif craft != null:
		VehicleCraft.idle(self, dt)
	else:
		_coast(dt)
	_sync(dt)
	_damage_fx(dt)


## Driving: thr -1..1 (brake / reverse .. throttle), steer -1..1 (left .. right), handbrake, boost (nitro). Cars use the gearbox + tyre model, bikes and hover craft the arcade one.
func step_drive(dt: float, thr: float, steer: float, handbrake: bool, boost := false) -> void:
	tires_flat = maxf(tires_flat - dt, 0.0)
	_crash_age += dt
	if craft != null:                                    # helicopter, plane, boat, tank: VehicleCraft
		VehicleCraft.step(self, dt, thr, steer, handbrake, boost)
		return
	if driver_is_player and cls == &"car":
		# wedged: the throttle is held and the car does not move (a shopfront, a lamp post, another car). It backs out by itself for a second, wheel turned away.
		if _nudge_t > 0.0:
			_nudge_t -= dt
			thr = -1.0
			steer = _nudge_steer
			handbrake = false
		elif thr > 0.5 and absf(vel.length()) < (VehicleSpecs.WEDGE_SPEED_CRASH if _crash_age < VehicleSpecs.WEDGE_AFTER_CRASH else VehicleSpecs.WEDGE_SPEED):
			_wedge_t += dt
			if _wedge_t > VehicleSpecs.WEDGE_SECS:
				_wedge_t = 0.0
				_nudge_t = VehicleSpecs.NUDGE_SECS
				_nudge_steer = -signf(steer) if absf(steer) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
				wedge_count += 1
				Game.say("BACKING OUT", 1.2)
		else:
			_wedge_t = 0.0
	if cls == &"car":
		_drive_car(dt, thr, steer, handbrake, boost)
	else:
		_drive_arcade(dt, thr, steer, handbrake, boost)


## Tyre force curve: x = slip angle / the peak slip angle. Rises to the peak at x = 1, then the tyre starts to slide and keeps only SLIDE_GRIP of its peak force.
static func tyre_curve(x: float) -> float:
	var ax := absf(x)
	var f := tanh(1.7 * ax) * (1.0 - (1.0 - VehicleSpecs.SLIDE_GRIP) * smoothstep(1.0, 2.8, ax))
	return f if x >= 0.0 else -f


## Wheel angle limit at speed v: a full lock at a standstill, a few degrees when fast (a phone stick cannot flick a car at 120 km/h into a spin).
static func steer_limit(v: float) -> float:
	return VehicleSpecs.STEER_MAX / (1.0 + pow(v / VehicleSpecs.STEER_V0, 1.4))


## The car model. Single-track (bicycle) dynamics: front and rear axle with a slip angle curve each (grip peaks, then the tyre slides), weight transfer under braking and
## power, a friction circle (braking or spinning wheels leave less cornering grip), a 5 speed gearbox with a torque curve and shift cuts, steering that narrows with speed, a counter-steer
## assist and a handbrake that frees the rear. Below LOW_SPEED the car turns kinematically. Sub-stepped at 120 Hz so it is stable at any frame rate.
func _drive_car(dt: float, thr: float, steer: float, handbrake: bool, boost: bool) -> void:
	var T := spec
	var base_max: float = T["max"]
	var vmax := base_max * (VehicleSpecs.TIRES_SPEED if tires_flat > 0.0 else 1.0)
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
	var m := VehicleSpecs.mass_of(kind)
	var wb := VehicleSpecs.wheelbase(kind)
	var a_f := wb * VehicleSpecs.CG_FRONT                         # centre of gravity to the front axle
	var b_r := wb - a_f
	var hcg: float = float(T["hgt"]) * VehicleSpecs.CG_HEIGHT
	var iz := m * (float(T["len"]) * float(T["len"]) + float(T["wid"]) * float(T["wid"])) / 12.0 * 1.15
	var atm := Game.atmosphere as Atmosphere
	var mu := VehicleSpecs.mu_of(kind) * (1.0 - VehicleSpecs.WET_GRIP_LOSS * (atm.wetness_now if atm != null else 0.0)) * (VehicleSpecs.TIRES_GRIP if tires_flat > 0.0 else 1.0)
	var steer_k := float(T.get("steer", 1.0))
	var n_sub := maxi(1, ceili(dt / (1.0 / 120.0) - 0.001))
	var h := dt / float(n_sub)
	var vx := vel.dot(forward())
	var vyl := -vel.dot(right())
	_shift_t = maxf(_shift_t - dt, 0.0)
	_shift_cool -= dt
	# --- gearbox: by speed, with a torque cut while it changes
	var top_g := vmax * float(VehicleSpecs.GEAR_TOPS[gear - 1])
	var rpm_n := clampf(vx / maxf(top_g, 1.0), 0.0, 1.1)
	if vx > 0.5 and thr > 0.05 and gear < VehicleSpecs.GEAR_TOPS.size() and rpm_n > VehicleSpecs.UPSHIFT_AT and _shift_cool <= 0.0:
		gear += 1
		_shift_t = VehicleSpecs.SHIFT_TIME
		_shift_cool = 0.45
	elif gear > 1 and _shift_cool <= 0.0 and vx / (vmax * float(VehicleSpecs.GEAR_TOPS[gear - 2])) < 0.78:
		gear -= 1
		_shift_cool = 0.3
	elif vx < 0.6 and gear > 1:
		gear = 1
	top_g = vmax * float(VehicleSpecs.GEAR_TOPS[gear - 1])
	rpm_n = clampf(vx / maxf(top_g, 1.0), 0.0, 1.1)
	var rpm_goal := lerpf(VehicleSpecs.IDLE_RPM, 1.0, clampf(rpm_n, 0.0, 1.0))
	if thr > 0.05 and vx < 3.0:
		rpm_goal = maxf(rpm_goal, 0.3 + 0.35 * thr)              # revving on the spot: the clutch slips at a standstill
	rpm = lerpf(rpm, rpm_goal + (0.06 * thr if _shift_t <= 0.0 else -0.12), 1.0 - exp(-14.0 * dt))
	# --- throttle, brake, handbrake
	var acc_eng := 0.0
	var brake_dec := 0.0
	var reversing := vx < 0.5 and thr < -0.05
	if thr > 0.05 and _shift_t <= 0.0:
		var r := clampf(vx / maxf(top_g, 1.0), 0.0, 1.05)
		var tq := 0.78 + 0.22 * smoothstep(0.0, 0.45, r) - 0.28 * smoothstep(0.72, 1.0, r)
		acc_eng = float(T["acc"]) * acc_k * float(VehicleSpecs.GEAR_ACC[gear - 1]) * tq * thr
		if gear == VehicleSpecs.GEAR_TOPS.size():
			acc_eng *= sqrt(clampf((1.0 - r) / 0.1, 0.0, 1.0))
		elif r >= 1.0:
			acc_eng = 0.0
		if vx < -0.5:
			brake_dec = float(T["brake"]) * VehicleSpecs.BRAKE_K * thr
			acc_eng = 0.0
	elif reversing:
		acc_eng = -float(T["acc"]) * 0.5 * -thr * clampf(1.0 - absf(vx) / (base_max * VehicleSpecs.REVERSE_FRACTION), 0.0, 1.0)
	elif thr < -0.05 and vx > 0.5:
		brake_dec = float(T["brake"]) * VehicleSpecs.BRAKE_K * -thr
	var coast := thr > -0.05 and thr < 0.05 and vx > 0.5
	braking = handbrake or brake_dec > 0.5
	# --- steering: the wheel follows the stick (fast in, faster out), narrower with speed; the assist catches a slide
	var dmax := steer_limit(absf(vx)) * steer_k
	var delta_want := -steer * dmax
	var slew := (VehicleSpecs.STEER_RATE_CAR if absf(delta_want) > absf(steer_angle) or delta_want * steer_angle < 0.0 else VehicleSpecs.STEER_RETURN) * dt
	steer_angle = clampf(steer_angle + clampf(delta_want - steer_angle, -slew, slew), -VehicleSpecs.STEER_MAX, VehicleSpecs.STEER_MAX)
	if handbrake:
		_drift_t = 0.0
	else:
		_drift_t += dt
	var rear_k := 1.0
	if handbrake or _drift_t < VehicleSpecs.DRIFT_RECOVER:
		rear_k = lerpf(VehicleSpecs.HANDBRAKE_REAR, 1.0, clampf(_drift_t / VehicleSpecs.DRIFT_RECOVER, 0.0, 1.0))
	var max_alpha := 0.0
	var ax_sum := 0.0
	var ay_sum := 0.0
	var spin := 0.0
	var ap := VehicleSpecs.PEAK_SLIP
	# --- the sub-steps
	for _i in n_sub:
		var vxe := maxf(vx, 1.5)
		var w := clampf((vx - VehicleSpecs.LOW_SPEED) / 1.5, 0.0, 1.0)
		var delta := steer_angle
		var ax_t := 0.0
		var ay_t := 0.0
		var r_dyn := yaw_rate
		var vy_dyn := vyl
		if w > 0.0:
			var beta := atan2(vyl, vxe)
			if absf(beta) > 0.05 and not handbrake:
				delta = clampf(delta + VehicleSpecs.COUNTER_STEER * beta * w, -0.5, 0.5)
			var nf := m * VehicleSpecs.G * b_r / wb - m * _ax * hcg / wb
			var nr := m * VehicleSpecs.G * a_f / wb + m * _ax * hcg / wb
			nf = maxf(nf, 0.2 * m * VehicleSpecs.G)
			nr = maxf(nr, 0.2 * m * VehicleSpecs.G)
			var cap_f := mu * nf
			var cap_r := mu * nr * rear_k
			var fd := m * acc_eng
			if fd > cap_r:
				spin = maxf(spin, clampf(fd / cap_r - 1.0, 0.0, 1.0))
				fd = cap_r * 0.92
			var fb_hand := m * VehicleSpecs.G * mu * 0.5 if handbrake else 0.0
			var fb_f := m * brake_dec * 0.62
			var fb_r := m * brake_dec * 0.38 + fb_hand
			var kf := sqrt(maxf(0.25, 1.0 - 0.75 * minf(fb_f / cap_f, 1.0) ** 2))
			var kr := sqrt(maxf(0.25, 1.0 - 0.75 * minf((absf(fd) + fb_r) / maxf(cap_r, 1.0), 1.0) ** 2))
			var af := atan2(vyl + a_f * yaw_rate, vxe) - delta
			var ar := atan2(vyl - b_r * yaw_rate, vxe)
			max_alpha = maxf(max_alpha, maxf(absf(af), absf(ar)))
			var fyf := -cap_f * kf * tyre_curve(af / ap)
			var fyr := -cap_r * kr * tyre_curve(ar / ap)
			var c := cos(delta)
			ay_t = (fyf * c + fyr) / m
			var long_f := fd - fb_f - fb_r
			var drag := VehicleSpecs.AERO * vx * absf(vx) * m + (VehicleSpecs.ENGINE_BRAKE * m * clampf(vx / 4.0, 0.0, 1.0) if coast else 0.0)
			ax_t = (long_f - drag - fyf * sin(delta)) / m
			r_dyn = yaw_rate + ((a_f * fyf * c - b_r * fyr) / iz - VehicleSpecs.YAW_DAMP * yaw_rate) * h
			vy_dyn = vyl + (ay_t - yaw_rate * vx) * h
		else:
			ax_t = acc_eng - brake_dec * signf(vx if absf(vx) > 0.05 else 1.0) - (VehicleSpecs.ENGINE_BRAKE * clampf(vx / 3.0, -1.0, 1.0) if coast else 0.0)
			if absf(vx) < 0.4 and thr == 0.0:
				ax_t = -vx / maxf(h, 0.001) * 0.5
		# kinematic alternative, blended in at low speed (and used alone in reverse)
		var r_kin := vx * tan(delta) / wb
		var vy_kin := vyl * exp(-9.0 * h)
		yaw_rate = lerpf(lerpf(yaw_rate, r_kin, 1.0 - exp(-14.0 * h)), r_dyn, w)
		vyl = lerpf(vy_kin, vy_dyn, w)
		# longitudinal: brakes never push through zero
		var nvx := vx + (ax_t + yaw_rate * vyl * (1.0 if w > 0.0 else 0.0)) * h
		if brake_dec > 0.0 and vx * nvx < 0.0 and not reversing:
			nvx = 0.0
		if handbrake and w <= 0.0:
			nvx *= exp(-3.0 * h)
		if vx > vmax and not boosting and vx > base_max:
			nvx = maxf(base_max, nvx - VehicleSpecs.NITRO_COOL * h)
		vx = clampf(nvx, -base_max * VehicleSpecs.REVERSE_FRACTION, vmax * 1.02)
		yaw_rate = clampf(yaw_rate, -3.6, 3.6)
		heading += yaw_rate * h
		_ax = lerpf(_ax, ax_t, 1.0 - exp(-8.0 * h))
		ax_sum += ax_t
		ay_sum += ay_t if w > 0.0 else yaw_rate * vx
	var inv := 1.0 / float(n_sub)
	long_acc = lerpf(long_acc, ax_sum * inv, 1.0 - exp(-10.0 * dt))
	lat_acc = lerpf(lat_acc, ay_sum * inv, 1.0 - exp(-10.0 * dt))
	wheelspin = lerpf(wheelspin, spin, 1.0 - exp(-12.0 * dt))
	var lock := clampf((brake_dec / maxf(float(T["brake"]) * VehicleSpecs.BRAKE_K, 1.0) - 0.8) * 5.0, 0.0, 1.0) * clampf(vx / 8.0, 0.0, 1.0)
	if handbrake:
		lock = clampf(vx / 10.0, 0.0, 1.0)
	var slide := clampf((max_alpha / ap - 1.1) / 1.4, 0.0, 1.0) * clampf((absf(vx) - 3.0) / 7.0, 0.0, 1.0)
	skid = lerpf(skid, maxf(maxf(slide, wheelspin * 0.8), lock * 0.6 * clampf(vx / 12.0, 0.0, 1.0)), 1.0 - exp(-12.0 * dt))
	vel = forward() * vx - right() * vyl
	speed = vx
	slip = -vyl
	drifting = absf(vyl) > VehicleSpecs.SMOKE_SLIP and absf(vx) > 6.0
	steer_in = steer
	_move(dt)
	speed = vel.dot(forward())
	slip = vel.dot(right())


func _drive_arcade(dt: float, thr: float, steer: float, handbrake: bool, boost: bool) -> void:
	var T := spec
	var vmax: float = float(T["max"]) * (VehicleSpecs.TIRES_SPEED if tires_flat > 0.0 else 1.0)
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


## A car nobody drives (parked, or knocked about): friction, no steering, the spin of a knock dies away.
func _coast(dt: float) -> void:
	if vel.length_squared() < 0.01 and absf(yaw_rate) < 0.02:
		vel = Vector3.ZERO
		yaw_rate = 0.0
		speed = 0.0
		return
	vel *= exp(-VehicleSpecs.UNPOWERED_DRAG * dt)
	if absf(yaw_rate) > 0.01:
		heading += yaw_rate * dt
		yaw_rate *= exp(-2.2 * dt)
	else:
		yaw_rate = 0.0
	_move(dt)
	speed = vel.dot(forward())
	slip = vel.dot(right())
	braking = false


## Move by vel * dt against the world (layer 1): a hit is answered with an impulse (bounce, spin, scrape) and sounds, sparks and damage by its closing speed along the wall
## normal, then the car slides along the wall for the rest of the step.
func _move(dt: float) -> void:
	if _heading_set != heading:                              # the collider turns with the car before it moves
		rotation.y = heading
		_heading_set = heading
	var motion := Vector3(vel.x * dt, 0.0, vel.z * dt)
	if motion.length_squared() < 1e-10:
		return
	var col := move_and_collide(motion)
	if col != null:
		_bounce(col)
	if global_position.y != base_y:
		global_position.y = base_y


func _bounce(col: KinematicCollision3D) -> void:
	var n := col.get_normal()
	n.y = 0.0
	if n.length_squared() < 1e-6:
		return
	n = n.normalized()
	var at := col.get_position()
	if cls == &"car":
		var vn_com := -vel.dot(n)                                  # the damage follows the speed INTO the wall (the angle counts), not the spin of the outer corner
		var vimp := impulse_hit(n, at, VehicleSpecs.RESTITUTION, INF)
		if vimp > VehicleSpecs.HIT_SPEED:
			vimp = minf(vimp, maxf(vn_com, 0.0) * 1.15)
			crash(vimp, at, n, INF)
			if driver_is_player:
				FX.shake(minf(1.0, vimp / 25.0))
			FX.burst(Vector3(at.x, 0.8, at.z), Color(1.0, 0.75, 0.38), 8, 5.0, 0.3, 8.0, 0.3)
			Sfx.play_at(&"hit", global_position, -4.0)
	else:
		var vn := vel.dot(n)
		if vn < 0.0:
			vel -= VehicleSpecs.BOUNCE * vn * n
			var impact := -vn
			if impact > VehicleSpecs.HIT_SPEED:
				hits += 1
				damage(impact * VehicleSpecs.HIT_DAMAGE)
				if driver_is_player:
					FX.shake(minf(1.0, impact / 25.0))
				FX.burst(Vector3(at.x, 0.8, at.z), Color(1.0, 0.75, 0.38), 8, 5.0, 0.3, 8.0, 0.3)
				Sfx.play_at(&"hit", global_position, -4.0)
	var rem := col.get_remainder()
	rem -= n * rem.dot(n)
	rem.y = 0.0
	if rem.length_squared() > 1e-6:
		move_and_collide(rem)


## Velocity of the hull at world point `at` (the car's velocity plus its spin about the centre).
func point_velocity(at: Vector3) -> Vector3:
	var r := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	return vel + Vector3(yaw_rate * r.z, 0.0, -yaw_rate * r.x)


## 1 / m + (r x n)^2 / I: how little a unit impulse along `n` at `at` moves this car (the denominator of the impulse formula).
func inverse_mass_at(n: Vector3, at: Vector3) -> float:
	var m := VehicleSpecs.mass_of(kind)
	var iz := m * (float(spec["len"]) * float(spec["len"]) + float(spec["wid"]) * float(spec["wid"])) / 12.0 * 1.15
	var r := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	var rxn := r.z * n.x - r.x * n.z
	return 1.0 / m + rxn * rxn / iz


## Applies the impulse `j` (world, kg m/s) at `at`: changes the velocity and the spin. A car that was following its lane or parked is moved by it like any other.
func apply_impulse(j: Vector3, at: Vector3) -> void:
	var m := VehicleSpecs.mass_of(kind)
	var iz := m * (float(spec["len"]) * float(spec["len"]) + float(spec["wid"]) * float(spec["wid"])) / 12.0 * 1.15
	var r := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	vel += Vector3(j.x, 0.0, j.z) / m
	yaw_rate = clampf(yaw_rate + (r.z * j.x - r.x * j.z) / iz, -4.0, 4.0)
	speed = vel.dot(forward())


## Rigid impulse of a wall contact at world point `at` with normal `n` (pointing into this car): changes this car's velocity AND its spin (a hit off the centre line turns the car)
## and scrapes some speed off along the wall. Returns the closing speed along the normal (0 when it was separating). Car against car is VehicleManager.collide_cars.
func impulse_hit(n: Vector3, at: Vector3, e: float, _other_mass: float) -> float:
	var m := VehicleSpecs.mass_of(kind)
	var iz := m * (float(spec["len"]) * float(spec["len"]) + float(spec["wid"]) * float(spec["wid"])) / 12.0 * 1.15
	var r := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	var rxn := r.z * n.x - r.x * n.z
	var vrel := point_velocity(at).dot(n)
	if vrel >= 0.0:
		return 0.0
	var j := -(1.0 + e) * vrel / (1.0 / m + rxn * rxn / iz)
	vel += n * (j / m)
	yaw_rate = clampf(yaw_rate + j * rxn / iz, -4.0, 4.0)
	var t := Vector3(-n.z, 0.0, n.x)                          # scraping along the surface costs speed
	var vt := vel.dot(t)
	var dvt := minf(absf(vt), VehicleSpecs.WALL_FRICTION * j / m) * signf(vt)
	vel -= t * dvt
	return -vrel


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
	if NearTraffic.instance != null and NearTraffic.instance.blocks(me, fx, fz, side, VehicleSpecs.AI_LOOK):       # the near (MultiMesh) cars are traffic too
		return true
	var mgr := manager as VehicleManager
	if mgr != null and not (ai_panic > 1.0 and not siren):            # a car in flight does not brake for the traffic ahead: that is how AI cars crash into each other
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
	var shadow := cop and Game.heat < VehicleSpecs.COP_RAM_HEAT            # low heat: the interceptor tails him with the siren on, no ramming
	if shadow and dist < 14.0:
		var pcar0: Object = pl.get(&"vehicle")
		var psp := (pcar0 as Vehicle).speed if pcar0 is Vehicle else 0.0
		thr = clampf((psp - speed) * 0.3 + 0.1, -1.0, 0.6)
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
	step_drive(dt, thr, steer, false, tactic == &"ram" and dist > 25.0 and not shadow)
	_ram_cd -= dt
	if dist < 3.4 and absf(speed) > 6.0 and _ram_cd <= 0.0 and not shadow:
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
	if sp < 3.0 or tactic == &"ram" or (cop and Game.heat < VehicleSpecs.COP_RAM_HEAT):
		return pp
	var dir := pv / sp
	var side := Vector3(-dir.z, 0.0, dir.x)
	if tactic == &"boxin":
		var s := 1.0 if (global_position - pp).dot(side) >= 0.0 else -1.0
		if (global_position - pp).dot(dir) > 2.0:                  # behind him: first come up alongside
			return pp + side * s * VehicleSpecs.BOXIN_SIDE - dir * 0.0
		return pp + side * s * (VehicleSpecs.BOXIN_SIDE * 0.55)    # alongside: squeeze in
	return pp + dir * (VehicleSpecs.BLOCK_AHEAD * clampf(sp / 25.0, 0.6, 1.4))


## A spike strip got the tyres: slow, loose, a little hull damage, sparks and a bang. Police cars drive over their own strips.
func blow_tires() -> void:
	if tires_flat > 0.0 or cop or dead:
		return
	tires_flat = VehicleSpecs.TIRES_TIME
	hp = maxf(hp - VehicleSpecs.TIRES_DAMAGE, 1.0)
	FX.burst(global_position + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.8, 0.4), 12, 6.0, 0.4, 5.0, 0.3)
	Sfx.play_at(&"hit", global_position, -2.0)
	if driver_is_player:
		FX.shake(0.4)
		Game.say("TYRES SHOT")


## A ram: the player (or the car he drives, through Player.damage) loses PATROL_RAM_DAMAGE, the patrol rebounds.
func _ram(pl: Node) -> void:
	_ram_cd = VehicleSpecs.PATROL_RAM_COOLDOWN
	ram_hits += 1
	if pl.has_method(&"damage"):
		pl.call(&"damage", VehicleSpecs.PATROL_RAM_DAMAGE * (VehicleSpecs.COP_RAM_FACTOR if cop else 1.0), global_position)
	vel *= -0.35
	speed = vel.dot(forward())
	FX.burst(global_position + Vector3(0.0, 0.9, 0.0) + forward() * 2.0, Color(0.6, 1.0, 0.4), 8, 5.0, 0.3, 8.0, 0.3)
	Sfx.play_at(&"hit", global_position, -3.0)


# --- visuals ------------------------------------------------------------------------------------------------------------

func _sync(dt: float) -> void:
	if _heading_set != heading:
		rotation.y = heading
		_heading_set = heading
	impact_t += dt
	if craft != null:
		VehicleCraft.sync(self, dt)
		_last_vf = speed
		_prev_h = heading
		_apply_lights()
		_finish_fx(dt)
		return
	var moving := absf(speed) > 0.05
	var yaw_est := wrapf(heading - _prev_h, -PI, PI) / maxf(dt, 0.0001)
	if cls == &"car":
		var steer_vis := steer_angle if driver_is_player else clampf(atan(yaw_est * float(VehicleSpecs.wheelbase(kind)) / maxf(absf(speed), 2.0)), -0.5, 0.5)
		if moving or absf(_steer_vis) > 0.01:
			_steer_vis = _damp(_steer_vis, steer_vis, 14.0, dt)
			visual.spin(speed * dt, _steer_vis)
	elif moving or absf(_steer_vis) > 0.01:
		_steer_vis = _damp(_steer_vis, steer_in * 0.5, 10.0, dt)
		visual.spin(speed * dt, _steer_vis)
	if cls == &"bike":
		_sync_bike(dt)
	elif cls == &"hover":
		_sync_hover(dt)
	elif driver_is_player or _dist < 70.0:
		_sync_body(dt, yaw_est)
	_last_vf = speed
	_prev_h = heading
	_apply_lights()
	_finish_fx(dt)


## Body motion of a car: a spring-damper per axis driven by the accelerations (nose dives under braking, squats under power, leans out of a corner, rocks after a hit).
func _sync_body(dt: float, yaw_est: float) -> void:
	var acc := long_acc
	var lat := lat_acc
	if not driver_is_player:
		acc = (speed - _last_vf) / maxf(dt, 0.0001)
		long_acc = _damp(long_acc, clampf(acc, -14.0, 10.0), 8.0, dt)
		lat_acc = _damp(lat_acc, clampf(yaw_est * speed, -12.0, 12.0), 8.0, dt)
		acc = long_acc
		lat = lat_acc
	var tp := clampf(acc * VehicleSpecs.BODY_PITCH, -VehicleSpecs.BODY_PITCH_MAX, VehicleSpecs.BODY_PITCH_MAX)
	var tr := clampf(-lat * VehicleSpecs.BODY_ROLL, -VehicleSpecs.BODY_ROLL_MAX, VehicleSpecs.BODY_ROLL_MAX)
	if absf(speed) > 4.0 and cls == &"car":              # suspension bounce: the road is not a billiard table (seams, patches, manhole covers every few metres)
		_road_t -= dt
		if _road_t <= 0.0:
			_road_t = randf_range(2.0, 6.0) / maxf(absf(speed), 4.0)
			_heave_v += randf_range(-1.0, 1.0) * VehicleSpecs.ROAD_KICK * clampf(absf(speed) / 20.0, 0.2, 1.4)
			_pitch_v += randf_range(-1.0, 1.0) * VehicleSpecs.ROAD_KICK * 0.25
	var left := minf(dt, 0.05)
	while left > 0.0:
		var h := minf(left, 0.012)
		_pitch_v += (225.0 * (tp - _pitch) - 13.0 * _pitch_v) * h
		_pitch += _pitch_v * h
		_roll_v += (225.0 * (tr - _roll) - 13.0 * _roll_v) * h
		_roll += _roll_v * h
		_heave_v += (160.0 * (0.0 - _heave) - 9.0 * _heave_v) * h
		_heave += _heave_v * h
		left -= h
	_pitch = clampf(_pitch, -0.14, 0.14)
	_roll = clampf(_roll, -0.16, 0.16)
	_heave = clampf(_heave, -0.14, 0.1)
	visual.model.rotation = Vector3(_pitch, 0.0, _roll - 0.02 * visual.deform)
	visual.model.position = Vector3(0.0, _heave - 0.05 * visual.deform, 0.0)


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
