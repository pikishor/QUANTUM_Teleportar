class_name PlayerWeapon
extends Node
## The player's four alien weapons (numbers in WeaponDefs): Rift Carbine (default hitscan rifle, 30 rounds, 1.3 s reload, 0.11 s interval), Shard Scatter (8 pellets, per-pellet head
## test and range falloff), Pulse Lance (hold to charge, release for a piercing shot, sniper zoom on ADS) and Singularity Grenade (thrown arc, gravity well, collapse blast through
## Game.explode). `current` is the weapon in hand; `mag`, `ammo`, `reserve`, `reload_t`, `fire_t`, `spread` always describe it (the Player's ammo / mag / reloading / spread read them).
## Every weapon keeps its own ammo and reserve (reserve < 0 = unlimited, the carbine). Switching (weapon_1..4, weapon_next / weapon_prev on the wheel, `swap` on touch) takes SWAP_TIME seconds
## during which the rig plays its quick rifle-lower animation (the reload pose) and nothing fires. Shop upgrades act on every weapon through its own base values (WeaponDefs.mag_size,
## Upgrades.damage_mult, Upgrades.reload_mult).
## The shot is a ray from the CAMERA through the crosshair (mask: world + enemy + vehicle); the tracer is drawn from the muzzle to the hit point. Targets are found two ways and the nearest
## wins: the physics ray (colliders on the enemy / vehicle layers) and a ray-sphere test against every node of group "enemy" that exposes center() and radius.
## A crit is a hit in the upper part of the target: hit.y > center().y + radius * 0.35. A shield trooper's frontal shield (shield_blocks / shield_hit) absorbs the carbine and the
## scatter; the lance and the grenade break it (break_shield). Hit data for the HUD lives on the Player: last_hit_time, last_hit_kill, last_hit_crit, plus hit_confirmed(kill, crit).
## Everything is pooled (FX tracers, the flash sprites, ImpactSparks, ImpactDecals, two grenade nodes): firing creates no nodes after the first throw.

signal weapon_changed(id: StringName)
signal grenade_collapsed(pos: Vector3)

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
const SWAP_TIME := 0.32
const GRENADE_GRAVITY := 22.0
const WELL_TICK := 0.2
const AMMO_PACK := {&"scatter": 12, &"lance": 5, &"grenade": 2}

var current: StringName = &"carbine"
var def: Dictionary = WeaponDefs.DEFS[&"carbine"]
var mag := MAG_SIZE
var ammo := MAG_SIZE
var reserve := -1                            ## spare rounds of the current weapon (-1 = unlimited)
var reload_t := 0.0                          ## seconds of reload left, 0 when not reloading
var reload_total := RELOAD_TIME
var fire_t := 0.0                            ## seconds until the next shot may leave the barrel
var bloom := 0.0                             ## spread added by sustained fire
var spread := SPREAD_HIP                     ## current total half angle in radians (what the crosshair shows and what the shot uses)
var shots_fired := 0                         ## lifetime counter, for tests and stats
var charge := 0.0                            ## Pulse Lance: 0..1 while the trigger is held
var swap_t := 0.0                            ## seconds of the switch animation left

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
var _store := {}                             ## weapon id -> Vector2i(ammo, reserve) of the weapons not in hand
var _mags := {}                              ## weapon id -> magazine size last applied
var _grenades: Array[Dictionary] = []
var _grenade_mat: StandardMaterial3D
var _charge_fx := 0.0


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


func _mag_for(id: StringName) -> int:
	return WeaponDefs.mag_size(id, Upgrades.level(&"mag"))


## Full magazines and starting reserves for every weapon, the carbine (or the last owned weapon) in hand, nothing charging or flying.
func reset() -> void:
	_store.clear()
	for id: StringName in WeaponDefs.IDS:
		_mags[id] = _mag_for(id)
		_store[id] = Vector2i(_mag_for(id), int(WeaponDefs.def(id)["reserve"]))
	if not WeaponDefs.is_unlocked(current):
		current = &"carbine"
	_load(current)
	reload_t = 0.0
	fire_t = 0.0
	bloom = 0.0
	charge = 0.0
	swap_t = 0.0
	_since_shot = 99.0
	_burst = 0
	_move_spread = 0.0
	spread = float(def["spread_hip"])
	_clear_grenades()


func _load(id: StringName) -> void:
	current = id
	def = WeaponDefs.def(id)
	var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), int(def["reserve"])))
	mag = _mag_for(id)
	_mags[id] = mag
	ammo = clampi(st.x, 0, mag)
	reserve = st.y
	reload_total = float(def["reload"]) * Upgrades.reload_mult()
	spread = float(def["spread_hip"])
	if _player != null:
		if _player.camera_rig != null:
			_player.camera_rig.ads_fov = float(def["zoom"])
		if _player.body != null and _player.body.has_method(&"set_weapon_look"):
			_player.body.call(&"set_weapon_look", id)


func _save_current() -> void:
	_store[current] = Vector2i(ammo, reserve)


## Shop upgrades go live: every weapon's magazine follows its own base. `top_up` gives the new rounds at once (a purchase), otherwise the ammo is only clamped.
func apply_upgrades(top_up := false) -> void:
	_save_current()
	for id: StringName in WeaponDefs.IDS:
		var nw := _mag_for(id)
		var old := int(_mags.get(id, nw))
		var st: Vector2i = _store.get(id, Vector2i(nw, int(WeaponDefs.def(id)["reserve"])))
		var a := st.x + maxi(nw - old, 0) if top_up else mini(st.x, nw)
		_store[id] = Vector2i(clampi(a, 0, nw), st.y)
		_mags[id] = nw
	_load(current)


# --- switching and pickups --------------------------------------------------------------------------------------------

func switch_to(id: StringName, instant := false) -> bool:
	if id == current or not WeaponDefs.DEFS.has(id):
		return false
	if not WeaponDefs.is_unlocked(id):
		Game.say("%s  LOCKED" % WeaponDefs.title(id), 1.2)
		return false
	_save_current()
	_load(id)
	WeaponDefs.last_used = id
	reload_t = 0.0
	charge = 0.0
	_burst = 0
	bloom = 0.0
	swap_t = 0.0 if instant else SWAP_TIME
	Sfx.play(&"reload", -9.0, 1.5)
	weapon_changed.emit(id)
	return true


## The next (dir 1) or previous (dir -1) owned weapon. Returns true when the weapon changed.
func cycle(dir: int) -> bool:
	var owned: Array[StringName] = []
	for id: StringName in WeaponDefs.IDS:
		if WeaponDefs.is_unlocked(id):
			owned.append(id)
	if owned.size() < 2:
		return false
	var i := owned.find(current)
	return switch_to(owned[posmod(i + dir, owned.size())])


## Keyboard 1-4, wheel and the touch SWAP button (Player calls it every physics frame on foot).
func poll_switch() -> void:
	for i in WeaponDefs.IDS.size():
		if Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))):
			switch_to(WeaponDefs.IDS[i])
	if Input.is_action_just_pressed(&"weapon_next") or Input.is_action_just_pressed(&"swap"):
		cycle(1)
	if Input.is_action_just_pressed(&"weapon_prev"):
		cycle(-1)


## A weapon pickup: unlocks the weapon (the first time) or adds an ammo pack. Returns the message for the HUD.
func grant(id: StringName) -> String:
	if not WeaponDefs.DEFS.has(id) or id == &"carbine":
		return ""
	_save_current()
	if WeaponDefs.unlock(id):
		if not _store.has(id):
			_store[id] = Vector2i(_mag_for(id), int(WeaponDefs.def(id)["reserve"]))
		return "NEW WEAPON  %s" % WeaponDefs.title(id)
	var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), 0))
	var cap := int(WeaponDefs.def(id)["reserve"]) * 2
	st.y = mini(st.y + int(AMMO_PACK.get(id, 6)), cap)
	_store[id] = st
	if id == current:
		reserve = st.y
	return "+%d %s" % [int(AMMO_PACK.get(id, 6)), WeaponDefs.title(id)]


## Spare rounds of any weapon (the current one live), for the HUD and tests.
func reserve_of(id: StringName) -> int:
	if id == current:
		return reserve
	var st: Vector2i = _store.get(id, Vector2i(0, int(WeaponDefs.def(id)["reserve"])))
	return st.y


func ammo_of(id: StringName) -> int:
	if id == current:
		return ammo
	var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), 0))
	return st.x


# --- state ----------------------------------------------------------------------------------------------------------

func is_reloading() -> bool:
	return reload_t > 0.0


func cancel_reload() -> void:
	reload_t = 0.0


func start_reload() -> bool:
	if reload_t > 0.0 or ammo >= mag or swap_t > 0.0 or reserve == 0:
		return false
	reload_total = float(def["reload"]) * Upgrades.reload_mult()
	reload_t = reload_total
	charge = 0.0
	Sfx.play(&"reload")
	return true


func _finish_reload() -> void:
	var need := mag - ammo
	var take := need if reserve < 0 else mini(need, reserve)
	ammo += take
	if reserve >= 0:
		reserve -= take


## Advance the weapon by dt. firing / reload_pressed come from the input actions, aiming and moving from the player.
func tick(dt: float, firing: bool, reload_pressed: bool, aiming: bool, moving: bool) -> void:
	if TestMode.infinite_ammo:                                      # test mode: never dry, never reloading
		ammo = mag
		if reserve >= 0:
			reserve = maxi(reserve, int(def["reserve"]))
	fire_t -= dt
	_since_shot += dt
	swap_t = maxf(0.0, swap_t - dt)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			reload_t = 0.0
			_finish_reload()
	if reload_pressed:
		start_reload()
	var can_fire := reload_t <= 0.0 and swap_t <= 0.0
	match String(def["kind"]):
		"charge":
			_tick_charge(dt, firing and can_fire, aiming)
		_:
			if firing and can_fire:
				if ammo <= 0:
					Sfx.dry_fire()
					start_reload()
				elif fire_t <= 0.0:
					if String(def["kind"]) == "throw":
						_throw()
					else:
						_shoot(dt, aiming)
	if _since_shot > BLOOM_HOLD:
		bloom = maxf(0.0, bloom - BLOOM_RECOVER * dt)
	if _since_shot > BURST_RESET:
		_burst = 0
	_move_spread = PlayerUtil.damp(_move_spread, float(def["spread_move"]) if moving else 0.0, 12.0, dt)
	spread = (float(def["spread_ads"]) if aiming else float(def["spread_hip"])) + bloom + _move_spread


## Dispersion applied to a unit direction: uniform inside a cone of half angle `angle` around `dir`, using the camera basis.
static func jitter_dir(basis: Basis, angle: float, rng_a: float, rng_r: float) -> Vector3:
	var fwd := -basis.z
	var a := rng_a * TAU
	var r := angle * sqrt(rng_r)
	return (fwd + basis.x * (cos(a) * r) + basis.y * (sin(a) * r)).normalized()


## [origin, dir] of an aim ray: the camera through the crosshair with `sp` half angle of dispersion, starting at the player's depth.
func _aim_ray(sp: float) -> Array:
	var rig := _player.camera_rig
	var cam := rig.camera
	var cam_pos := cam.global_position
	var dir := jitter_dir(cam.global_basis, sp, randf(), randf())
	var along := maxf(0.0, (rig.get_pivot_position() - cam_pos).dot(dir))
	return [cam_pos + dir * along, dir]


func _recoil(aiming: bool) -> void:
	var rig := _player.camera_rig
	var k := clampf(float(_burst - 1) / 10.0, 0.0, 1.0)
	var kick := lerpf(float(def["kick"]), float(def["kick_end"]), k) * randf_range(0.85, 1.15)
	var kick_yaw := randf_range(-1.0, 1.0) * float(def["kick_yaw"])
	if aiming:
		kick *= RECOIL_ADS_SCALE
		kick_yaw *= RECOIL_ADS_SCALE
	rig.kick(kick, kick_yaw)
	rig.punch(0.03 if String(def["kind"]) == "hit" and int(def["pellets"]) == 1 else 0.07)
	bloom = minf(float(def["bloom_max"]), bloom + float(def["bloom"]))


# --- carbine and scatter (hitscan) ------------------------------------------------------------------------------------

func _shoot(dt: float, aiming: bool) -> void:
	var p := _player
	ammo -= 1
	shots_fired += 1
	fire_t = maxf(fire_t, -dt) + float(def["interval"])      # keep the cadence exact whatever the tick rate, without banking shots
	_since_shot = 0.0
	_burst += 1
	var pellets := int(def["pellets"])
	if pellets > 1:
		Sfx.play(&"shot", 2.0, randf_range(0.5, 0.6))
		Sfx.play(&"explosion_small", -8.0, 1.5)
	else:
		Sfx.play(&"shot", -2.0, randf_range(0.95, 1.05))
	for i in pellets:
		_trace_pellet()
	p.body.fire_flash(1.0 if pellets == 1 else 1.7)
	_recoil(aiming)
	p.fired.emit()


func _trace_pellet() -> void:
	var p := _player
	var ar := _aim_ray(spread)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var range_m := float(def["range"])
	var best := range_m
	var target: Node = null
	var normal := Vector3.ZERO
	var space := p.get_world_3d().direct_space_state
	_exclude.assign(_exclude_base)
	_ray.from = origin
	_ray.to = origin + dir * range_m
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
	var hit_something := best < range_m - 0.001

	# --- the barrel: poking into a wall, or cover right in front of the muzzle
	var mz := p.body.muzzle.global_position
	var anchor := p.camera_rig.get_pivot_position()
	var blocked := _blocked_between(space, anchor, mz)
	if blocked.is_empty():
		blocked = _blocked_between(space, mz, hit)
	if not blocked.is_empty():
		hit = blocked["position"]
		normal = blocked["normal"]
		target = _damageable_of(blocked["collider"] as Node)
		hit_something = true

	FX.tracer(mz, hit, def["tracer"])

	var from_d := float(def["falloff_from"])
	var k := 1.0
	if mz.distance_to(hit) > from_d:
		k = lerpf(1.0, 0.25, clampf((mz.distance_to(hit) - from_d) / maxf(range_m - from_d, 1.0), 0.0, 1.0))
	if target != null and not _is_dead(target):
		_hit_target(target, hit, normal, k)
	elif hit_something:
		_hit_world(hit, normal)


## Is the segment a -> b blocked by the world or a vehicle? Returns the ray result (empty = clear).
func _blocked_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var d := b - a
	var dist := d.length()
	if dist < 0.08:
		return {}
	_ray_b.from = a
	_ray_b.to = a + d * (1.0 - 0.025 / dist)
	return space.intersect_ray(_ray_b)


func _hit_target(target: Node, hit: Vector3, normal: Vector3, k := 1.0) -> void:
	var p := _player
	var is_vehicle := target.is_in_group(&"vehicle") and not target.is_in_group(&"enemy")
	var crit := false
	var human := false
	var n := normal if normal != Vector3.ZERO else Vector3.UP
	if not is_vehicle:
		var c := Vector3.ZERO
		if target.has_method(&"center"):
			c = target.call(&"center")
		else:
			c = (target as Node3D).global_position
		var r := _radius_of(target)
		crit = r > 0.0 and hit.y > c.y + r * CRIT_HEIGHT
		human = target is Operative or target.get(&"type") == &"operative"
		var amount := TestMode.damage((float(def["crit"]) if crit else float(def["damage"])) * k * Upgrades.damage_mult())
		if target.has_method(&"shield_blocks"):
			if bool(def["pierce_shield"]):
				target.call(&"break_shield")
			elif bool(target.call(&"shield_blocks", p.global_position)):
				target.call(&"shield_hit", amount, hit)                     # the frontal shield eats it: no damage, a cyan spark
				p.last_hit_time = PlayerUtil.now()
				p.last_hit_kill = false
				p.last_hit_crit = false
				p.hit_confirmed.emit(false, false)
				if _sparks != null:
					_sparks.impact_machine(hit, n)
				return
		target.call(&"damage", amount, crit)
	else:
		target.call(&"damage", DAMAGE_VEHICLE * float(def["damage"]) / DAMAGE * k)
	var kill := (not is_vehicle) and _is_dead(target)
	p.last_hit_time = PlayerUtil.now()
	p.last_hit_kill = kill
	p.last_hit_crit = crit
	p.hit_confirmed.emit(kill, crit)
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


# --- Pulse Lance --------------------------------------------------------------------------------------------------------

func _tick_charge(dt: float, firing: bool, aiming: bool) -> void:
	var need := float(def["charge_time"])
	if firing and ammo > 0 and fire_t <= 0.0:
		if charge <= 0.0:
			Sfx.play(&"link", -8.0, 0.8)
		charge = minf(1.0, charge + dt / need)
		_charge_fx -= dt
		if _charge_fx <= 0.0:                               # the charge is visible: a growing flare at the muzzle, a spark ring at full charge
			_charge_fx = 0.07
			var mz := _player.body.muzzle.global_position
			FX.muzzle_flash(mz, -_player.camera_rig.camera.global_basis.z, def["tracer"], 0.5 + charge * 2.2)
			if charge >= 1.0:
				FX.burst(mz, def["tracer"], 3, 2.0, 0.2, 0.0, 0.8)
	elif charge > 0.0:
		var c := charge
		charge = 0.0
		if c >= float(def["min_charge"]) and ammo > 0 and fire_t <= 0.0 and reload_t <= 0.0 and swap_t <= 0.0:
			_fire_lance(c, aiming)
	elif firing and ammo <= 0 and fire_t <= 0.0:
		Sfx.dry_fire()
		start_reload()


func _fire_lance(c: float, aiming: bool) -> void:
	var p := _player
	ammo -= 1
	shots_fired += 1
	fire_t = float(def["interval"])
	_since_shot = 0.0
	_burst = 1
	Sfx.play(&"boom", -8.0, 1.7)
	Sfx.play(&"shot", 0.0, 0.7)
	var ar := _aim_ray(spread)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var range_m := float(def["range"])
	var space := p.get_world_3d().direct_space_state
	_ray_b.from = origin
	_ray_b.to = origin + dir * range_m
	var wall := space.intersect_ray(_ray_b)
	var wall_t := range_m
	var wall_normal := Vector3.UP
	var wall_collider: Node = null
	if not wall.is_empty():
		wall_t = origin.distance_to(wall["position"])
		wall_normal = wall["normal"]
		wall_collider = wall["collider"] as Node
	var victims: Array = []                                 # [t, enemy] sorted by distance
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or _is_dead(e):
			continue
		var r := _radius_of(e)
		if r <= 0.0:
			continue
		var t := PlayerUtil.ray_sphere(origin, dir, e.call(&"center"), r)
		if t < wall_t:
			var at := victims.size()
			while at > 0 and float(victims[at - 1][0]) > t:
				at -= 1
			victims.insert(at, [t, e])
	var scale := lerpf(0.35, 1.0, clampf((c - float(def["min_charge"])) / (1.0 - float(def["min_charge"])), 0.0, 1.0))
	var mz := p.body.muzzle.global_position
	var end := origin + dir * wall_t
	FX.tracer(mz, end, def["tracer"])
	FX.tracer(mz, end, Color(1.0, 1.0, 1.0))
	p.body.fire_flash(2.0)
	for v: Array in victims:
		var e: Node = v[1]
		if is_instance_valid(e) and not _is_dead(e):
			_hit_target(e, origin + dir * float(v[0]), -dir, scale)
	if wall_collider != null:
		var veh := _damageable_of(wall_collider)
		if veh != null and veh.is_in_group(&"vehicle") and not veh.is_in_group(&"enemy"):
			_hit_target(veh, end, wall_normal, scale * 3.0)
		else:
			_hit_world(end, wall_normal)
	_recoil(aiming)
	p.fired.emit()


# --- Singularity Grenade ----------------------------------------------------------------------------------------------

func _throw() -> void:
	var p := _player
	ammo -= 1
	shots_fired += 1
	fire_t = float(def["interval"])
	_since_shot = 0.0
	_burst = 1
	Sfx.play(&"blink", -6.0, 1.6)
	var ar := _aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var space := p.get_world_3d().direct_space_state
	_ray_b.from = origin
	_ray_b.to = origin + dir * float(def["range"])
	var res := space.intersect_ray(_ray_b)
	var aim_pt: Vector3 = res["position"] if not res.is_empty() else origin + dir * 40.0
	var from := p.body.muzzle.global_position
	var delta := aim_pt - from
	var flat := Vector2(delta.x, delta.z).length()
	var t := clampf(flat / float(def["speed"]), 0.3, 2.0)
	var g := _free_grenade()
	g["state"] = 0
	g["pos"] = from
	g["vel"] = Vector3(delta.x / t, delta.y / t + 0.5 * GRENADE_GRAVITY * t, delta.z / t)
	g["t"] = 0.0
	var node: MeshInstance3D = g["node"]
	node.global_position = from
	node.scale = Vector3.ONE * 0.26
	node.visible = true
	p.body.fire_flash(0.7)
	_recoil(false)
	p.fired.emit()


func _free_grenade() -> Dictionary:
	for g in _grenades:
		if int(g["state"]) < 0:
			return g
	if _grenades.size() >= 2:                               # both busy: the oldest collapses early and gives its slot
		var oldest := _grenades[0]
		for g in _grenades:
			if float(g["t"]) > float(oldest["t"]):
				oldest = g
		_collapse(oldest)
		return oldest
	if _grenade_mat == null:
		_grenade_mat = StandardMaterial3D.new()
		_grenade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_grenade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_grenade_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_grenade_mat.albedo_color = Color(0.75, 0.35, 1.0, 0.6)
		_grenade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	sm.material = _grenade_mat
	node.mesh = sm
	node.top_level = true
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.add_child(node)
	var g := {"node": node, "state": -1, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "t": 0.0, "well": 0.0, "tick": 0.0}
	_grenades.append(g)
	return g


func _clear_grenades() -> void:
	for g in _grenades:
		g["state"] = -1
		(g["node"] as Node3D).visible = false


## Live grenades (flying or in the well phase), for tests and the bot.
func grenades_active() -> int:
	var n := 0
	for g in _grenades:
		if int(g["state"]) >= 0:
			n += 1
	return n


func well_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for g in _grenades:
		if int(g["state"]) == 1:
			out.append(g["pos"])
	return out


func _physics_process(delta: float) -> void:
	if _grenades.is_empty() or not Game.is_playing():
		return
	for g in _grenades:
		match int(g["state"]):
			0:
				_fly(g, delta)
			1:
				_well(g, delta)


func _fly(g: Dictionary, dt: float) -> void:
	var vel: Vector3 = g["vel"]
	vel.y -= GRENADE_GRAVITY * dt
	g["vel"] = vel
	var pos: Vector3 = g["pos"]
	var nxt := pos + vel * dt
	g["t"] = float(g["t"]) + dt
	_ray_b.from = pos
	_ray_b.to = nxt
	var res := _player.get_world_3d().direct_space_state.intersect_ray(_ray_b)
	var land := false
	if not res.is_empty():
		nxt = (res["position"] as Vector3) + (res["normal"] as Vector3) * 0.25
		land = true
	else:
		for e: Node in get_tree().get_nodes_in_group(&"enemy"):
			if e is Node3D and e.has_method(&"center") and not _is_dead(e) and (e.call(&"center") as Vector3).distance_to(nxt) < _radius_of(e) + 0.3:
				land = true
				break
	g["pos"] = nxt
	(g["node"] as Node3D).global_position = nxt
	if land or float(g["t"]) >= float(def_of_grenade()["fuse"]):
		_start_well(g)


static func def_of_grenade() -> Dictionary:
	return WeaponDefs.DEFS[&"grenade"]


func _start_well(g: Dictionary) -> void:
	var d := def_of_grenade()
	g["state"] = 1
	g["well"] = float(d["well_time"])
	g["tick"] = 0.0
	FX.burst(g["pos"], WeaponDefs.COLLAPSE_COLOR, 16, 7.0, 0.5, 0.0, 1.2)
	Sfx.play_at(&"superpos", g["pos"], -4.0, 0.7)


func _well(g: Dictionary, dt: float) -> void:
	var d := def_of_grenade()
	var pos: Vector3 = g["pos"]
	var left := float(g["well"]) - dt
	g["well"] = left
	var life := 1.0 - left / float(d["well_time"])
	var node: MeshInstance3D = g["node"]
	node.scale = Vector3.ONE * (0.6 + 2.6 * life + 0.25 * sin(life * 40.0))
	var radius := float(d["well_radius"])
	var pull := float(d["well_pull"])
	var tick := float(g["tick"]) + dt
	var hurt := false
	if tick >= WELL_TICK:
		tick -= WELL_TICK
		hurt = true
		FX.burst(pos + Vector3(randf_range(-radius, radius), 0.4, randf_range(-radius, radius)) * 0.3, WeaponDefs.COLLAPSE_COLOR, 5, -3.0, 0.4, 0.0, 0.9)
	g["tick"] = tick
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or _is_dead(e):
			continue
		var en := e as Node3D
		var off := Vector3(pos.x - en.global_position.x, 0.0, pos.z - en.global_position.z)
		var dist := off.length()
		if dist > radius:
			continue
		if e.has_method(&"break_shield"):
			e.call(&"break_shield")
		if dist > 1.4:
			en.global_position += off / dist * (pull * (0.45 + 0.55 * (1.0 - dist / radius)) * dt)
		if hurt:
			e.call(&"damage", float(d["well_dps"]) * WELL_TICK * Upgrades.damage_mult(), false)
	if left <= 0.0:
		_collapse(g)


func _collapse(g: Dictionary) -> void:
	var d := def_of_grenade()
	var pos: Vector3 = g["pos"]
	g["state"] = -1
	(g["node"] as Node3D).visible = false
	Game.explode(pos + Vector3(0.0, 0.5, 0.0), float(d["blast_radius"]), {"enemy_dmg": float(d["damage"]) * Upgrades.damage_mult(), "car_dmg": 40.0, "player_dmg": 0.0, "color": WeaponDefs.COLLAPSE_COLOR})
	grenade_collapsed.emit(pos)


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
