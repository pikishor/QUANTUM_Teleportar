class_name TankCrews
extends Node
## ENEMY TANK CREWS (wave 127, w127-arms; plan line 127): military AI that drives and fights in tanks. One node under the VehicleManager (`TankCrews.current`, attached by it).
##   ARMY BASE   one crew patrols the ARMY AIRBASE east of EASTFIELD's runway while the hero is within BASE_IN; it engages him when he is wanted (1 star and up) or when he hurts it
##   WANTED      at 4 stars one tank comes for the hero, at 5 two (every WANTED_EVERY s, also while he hides from the foot patrols: only a building keeps the army away); they go home
##               when the heat falls below 3 and he is away
##   MISSIONS    the tank missions (TankSteps) place crews with spawn(.., &"mission"): they always fight; a convoy crew picks the nearest convoy truck or the hero
## Each crew is a real tank of the roster (a pooled Vehicle of VehicleManager, meta enemy_tank, outside the live car cap) driven through Vehicle.scripted: the brain writes the stick
## (script_thr / script_steer), the turret slews to `aim_at` and the main gun fires through VehicleWeapons.tick, so its shells hit on the zones of TankArmour like the hero's. It keeps its FRONT
## to the target at a standing distance, backs off when too close, frees itself when stuck, does not see through smoke (TankArms.smoke_between) nor through walls (a ray), misses at first
## (an aim error that shrinks while it keeps the target) and waits RELOAD s between rounds (EASY). Distance-throttled: it thinks every 0.1 s near the hero, 0.3 s farther, 0.8 s far,
## stands still beyond FREEZE_R and is handed back to the pool beyond RELEASE_R (not a mission's). At most cap() crews (by the graphics tier).
## W127A_OLD=1 (or TankCrews.on = false): no enemy tank anywhere.

const BASE_IN := 300.0                  ## the base crew exists while the hero is this close to the base
const ENGAGE_R := 240.0
const STAND_MIN := 32.0
const STAND_MAX := 70.0
const FREEZE_R := 360.0
const RELEASE_R := 480.0
const RELOAD := 5.0                     ## s between two rounds of one crew
const ALIGN := 0.07                     ## rad: the gun fires when it points this close to the aim point
const AIM_ERR0 := 5.0                   ## m of aim error when it first sees the target ...
const AIM_ERR1 := 1.0                   ## ... down to this after AIM_LEARN s on it
const AIM_LEARN := 10.0
const HERO_SHARE := 0.28                ## the share of a crew round's damage the hero on foot takes in its blast (the hull of his vehicle takes the round itself)
const CAPS := [2, 3, 4]                 ## crews alive by graphics tier (LOW, MED, HIGH); a mission may add MISSION_EXTRA
const MISSION_EXTRA := 1
const KINDS := [&"tank", &"ltank", &"apc"]
const WANTED_EVERY := 4.0

static var on := OS.get_environment("W127A_OLD") != "1"
static var current: TankCrews = null
static var kills := 0                   ## enemy tanks destroyed, lifetime (tests)
static var shots := 0                   ## rounds the crews fired
static var spawned := 0
static var wanted_sent := 0

var crews: Array[Dictionary] = []
static var freed_guard_on := OS.get_environment("W128O_OLD") != "1"     ## w128-open: W128O_OLD=1 = the old tick (casts a freed crew vehicle: SCRIPT ERROR)
var _base := Vector3.INF
var _base_t := 0.0
var _wanted_t := WANTED_EVERY


static func attach(vm: Node) -> void:
	if vm == null or vm.get_node_or_null(^"TankCrews") != null:
		return
	var n := TankCrews.new()
	n.name = "TankCrews"
	vm.add_child(n)


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


static func cap() -> int:
	return int(CAPS[clampi(Game.quality, 0, 2)])


## The damage a crew round's blast deals to the hero on foot (0 for every other shooter: the hero's own rounds never hurt him).
static func hero_dmg(car: Node, dmg: float) -> float:
	return dmg * HERO_SHARE if car != null and car.has_meta(&"enemy_tank") else 0.0


func _vm() -> VehicleManager:
	return Game.vehicles as VehicleManager


## The ARMY AIRBASE: the middle of its ground pads (Helipads, role army), INF when there is none.
func base_pos() -> Vector3:
	if _base.is_finite():
		return _base
	var sum := Vector3.ZERO
	var n := 0
	for p in Helipads.all():
		if p.get("role", &"") == &"army":
			sum += p["pos"] as Vector3
			n += 1
	if n > 0:
		_base = sum / float(n)
		_base.y = 0.0
	return _base


func count(mode: StringName = &"") -> int:
	var n := 0
	for c in crews:
		if mode == &"" or c["mode"] == mode:
			n += 1
	return n


func vehicles(mode: StringName = &"") -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for c in crews:
		if (mode == &"" or c["mode"] == mode) and is_instance_valid(c["v"]):
			out.append(c["v"])
	return out


## A crew in a tank of `kind` at `at` facing `heading`. `mode`: &"base", &"wanted", &"mission". `opts`: hp (hull points), targets (Array of Vehicles it may go for besides the hero),
## home (where a base crew patrols). Null when the cap is full or nothing can be spawned.
func spawn(kind: StringName, at: Vector3, heading: float, mode: StringName, opts := {}) -> Vehicle:
	if not on:
		return null
	var limit := cap() + (MISSION_EXTRA if mode == &"mission" else 0)
	if crews.size() >= limit:
		return null
	var vm := _vm()
	if vm == null:
		return null
	vm._fixed_n += 1
	var v: Vehicle = vm.spawn_parked(kind, at, heading)
	if v == null:
		vm._count_fixed()
		return null
	v.set_meta(&"hold", true)
	v.set_meta(&"enemy_tank", true)
	vm._count_fixed()
	v.scripted = true
	v.script_thr = 0.0
	v.script_steer = 0.0
	if opts.has("hp"):
		v.max_hp = float(opts["hp"])
		v.hp = v.max_hp
	var c := {"v": v, "mode": mode, "think": 0.0, "fire_t": RELOAD * 0.5, "seen_t": 0.0, "stuck_t": 0.0, "back_t": 0.0, "home": opts.get("home", at), "pi": 0,
			"targets": opts.get("targets", []), "target": null, "engaged": false, "los": false, "err": Vector3.ZERO, "hp0": v.hp}
	crews.append(c)
	spawned += 1
	if not v.exploded.is_connected(_on_dead):
		v.exploded.connect(_on_dead)
	return v


func _on_dead(v: Vehicle) -> void:
	for i in crews.size():
		if crews[i]["v"] == v:
			crews.remove_at(i)
			kills += 1
			if v.has_meta(&"hold"):
				v.remove_meta(&"hold")
			if v.has_meta(&"enemy_tank"):
				v.remove_meta(&"enemy_tank")
			v.scripted = false
			if is_instance_valid(Game.player) and (Game.player as Node3D).global_position.distance_to(v.global_position) < 300.0:
				Game.say("ENEMY TANK DESTROYED", 1.6)
			break
	if v.exploded.is_connected(_on_dead):
		v.exploded.disconnect(_on_dead)


## Hands crew vehicle `v` back to the pool (a mission ends, the hero is far away).
func release(v: Vehicle) -> void:
	for i in crews.size():
		if crews[i]["v"] == v:
			crews.remove_at(i)
			break
	if not is_instance_valid(v):
		return
	if v.exploded.is_connected(_on_dead):
		v.exploded.disconnect(_on_dead)
	for m: StringName in [&"hold", &"enemy_tank", &"aim_at", &"provoked"]:
		if v.has_meta(m):
			v.remove_meta(m)
	v.scripted = false
	var vm := _vm()
	if vm != null and v.active and not v.driver_is_player:
		vm._release(v)
		vm._count_fixed()


func release_mode(mode: StringName) -> void:
	for v in vehicles(mode):
		release(v)


## Wanted v2 asks for its tanks (4 stars: one, 5: two). True when one was sent now.
static func dispatch_wanted(level: int, ppos: Vector3) -> bool:
	var tc := current
	if not on or tc == null or level < 4:
		return false
	var want := 1 if level == 4 else 2
	if tc.count(&"wanted") >= want:
		return false
	var vm := tc._vm()
	if vm == null:
		return false
	var k: StringName = KINDS[wanted_sent % 2]
	var at := Vector3.INF
	var h := 0.0
	var spot: Array = vm._find_spot(ppos, false, 110.0, 170.0, &"tank", false)
	if not spot.is_empty():
		at = spot[0]
		h = float(spot[4])
	else:                                                                  # out in the open (no road near): a level, open spot 140 m off, nose to the hero
		var space := tc.get_viewport().world_3d.direct_space_state if tc.get_viewport() != null else null
		for i in 8:
			var a := TAU * float((wanted_sent + i) % 8) / 8.0
			var c := ppos + Vector3(cos(a), 0.0, sin(a)) * 140.0
			var g := TerrainHeight.height_at(c.x, c.z) if (absf(c.x) > TerrainHeight.CITY_HALF or absf(c.z) > TerrainHeight.CITY_HALF) else 0.0
			if space != null:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, g + 60.0, c.z), Vector3(c.x, g - 5.0, c.z), Game.L_WORLD))
				if not hit.is_empty() and (hit["position"] as Vector3).y > g + 1.0:
					continue                                                   # a roof, a rock, a tree: not here
			at = Vector3(c.x, g, c.z)
			h = atan2(-(ppos.x - c.x), -(ppos.z - c.z))
			break
	if not at.is_finite():
		return false
	var v := tc.spawn(k, at, h, &"wanted")
	if v == null:
		return false
	wanted_sent += 1
	return true


# --- the brains -----------------------------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not on or not Game.is_playing():
		return
	var pl := Game.player as Node3D
	if not is_instance_valid(pl):
		return
	var hv: Variant = pl.get(&"vehicle")
	var hero: Node3D = hv as Node3D if hv is Node3D and is_instance_valid(hv) else pl
	var hp := hero.global_position
	_base_t -= dt
	if _base_t <= 0.0:
		_base_t = 1.0
		_tick_base(hp)
	_wanted_t -= dt
	if _wanted_t <= 0.0:
		_wanted_t = WANTED_EVERY
		if not InteriorGameplay.active:
			dispatch_wanted(Wanted.level_of(Game.heat), hp)
	var i := crews.size() - 1
	while i >= 0:
		var c := crews[i]
		var raw: Variant = c["v"]
		if freed_guard_on and not is_instance_valid(raw):                    # w128-open: a freed vehicle must not be cast (`as` on a freed object is a SCRIPT ERROR that aborted this tick every frame)
			crews.remove_at(i)
			i -= 1
			continue
		var v := raw as Vehicle
		if v == null or not v.active or v.dead:
			crews.remove_at(i)
			i -= 1
			continue
		var d := Vector2(v.global_position.x - hp.x, v.global_position.z - hp.z).length()
		if d > RELEASE_R and c["mode"] != &"mission":
			release(v)
			i -= 1
			continue
		if c["mode"] == &"wanted" and Wanted.level_of(Game.heat) < 3 and d > 150.0:
			release(v)
			i -= 1
			continue
		if d > FREEZE_R:
			v.script_thr = 0.0
			v.script_steer = 0.0
			i -= 1
			continue
		c["think"] = float(c["think"]) - dt
		if float(c["think"]) <= 0.0:
			c["think"] = 0.1 if d < 120.0 else (0.3 if d < 260.0 else 0.8)
			_think(c, v, hero, dt)
		_fight(c, v, dt)
		i -= 1


## The base crew: there while the hero is near the ARMY AIRBASE, gone when he leaves (the release rule above).
func _tick_base(hp: Vector3) -> void:
	var b := base_pos()
	if not b.is_finite() or count(&"base") > 0:
		return
	if Vector2(b.x - hp.x, b.z - hp.z).length() > BASE_IN:
		return
	var g := TerrainHeight.height_at(b.x, b.z) if (absf(b.x) > TerrainHeight.CITY_HALF or absf(b.z) > TerrainHeight.CITY_HALF) else 0.0
	spawn(&"tank", Vector3(b.x + 30.0, g, b.z), 0.0, &"base", {"home": Vector3(b.x, g, b.z)})


func _is_hostile(c: Dictionary, v: Vehicle) -> bool:
	if c["mode"] != &"base":
		return true
	if v.hp < float(c["hp0"]) - 1.0 or v.has_meta(&"provoked"):
		v.set_meta(&"provoked", true)
		return true
	return Wanted.level_of(Game.heat) >= 1


## Who it goes for: the hero (in his vehicle or on foot), or for a convoy crew the nearest live convoy truck when that is closer.
func _pick(c: Dictionary, v: Vehicle, hero: Node3D) -> Node3D:
	var best: Node3D = hero
	var bd := v.global_position.distance_to(hero.global_position)
	for t: Variant in c["targets"] as Array:
		if t is Vehicle and is_instance_valid(t) and (t as Vehicle).active and not (t as Vehicle).dead:
			var dd := v.global_position.distance_to((t as Vehicle).global_position)
			if dd < bd:
				bd = dd
				best = t as Node3D
	return best


func _think(c: Dictionary, v: Vehicle, hero: Node3D, dt: float) -> void:
	var tgt := _pick(c, v, hero)
	var to := tgt.global_position - v.global_position
	var d := Vector2(to.x, to.z).length()
	var engaged := d < ENGAGE_R and _is_hostile(c, v)
	c["engaged"] = engaged
	c["target"] = tgt if engaged else null
	var goal: Vector3 = tgt.global_position
	var thr := 0.0
	if not engaged:                                                         # patrol: a slow square round home
		var home: Vector3 = c["home"]
		var corners := [Vector3(30, 0, 0), Vector3(0, 0, 30), Vector3(-30, 0, 0), Vector3(0, 0, -30)]
		goal = home + (corners[int(c["pi"]) % 4] as Vector3)
		if Vector2(goal.x - v.global_position.x, goal.z - v.global_position.z).length() < 8.0:
			c["pi"] = int(c["pi"]) + 1
		thr = 0.45
	elif d > STAND_MAX:
		thr = 0.85
	elif d < STAND_MIN:
		thr = -0.6
	var g := goal - v.global_position
	var want_h := atan2(-g.x, -g.z)
	var diff := wrapf(want_h - v.heading, -PI, PI)
	var steer := clampf(-diff * 2.0, -1.0, 1.0)
	if thr < 0.0:
		steer = 0.0                                                         # backing off: keep the nose (the thick front) on the target
	elif absf(diff) > 1.2 and thr > 0.0:
		thr *= 0.3                                                          # turn on the spot first
	if float(c["back_t"]) > 0.0:                                             # stuck: back out with the wheel turned
		c["back_t"] = float(c["back_t"]) - float(c["think"])
		thr = -0.8
		steer = 1.0
	elif thr > 0.3 and absf(v.speed) < 0.6:
		c["stuck_t"] = float(c["stuck_t"]) + float(c["think"])
		if float(c["stuck_t"]) > 1.8:
			c["stuck_t"] = 0.0
			c["back_t"] = 1.5
	else:
		c["stuck_t"] = 0.0
	v.script_thr = thr
	v.script_steer = steer
	if engaged:
		var mz := VehicleCraft.muzzle_origin(v)
		var aim := tgt.global_position + Vector3(0.0, 1.0, 0.0)
		var q := PhysicsRayQueryParameters3D.create(mz, aim, Game.L_WORLD)
		q.exclude = [v.get_rid()]
		var blocked := not v.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		c["los"] = not blocked and not TankArms.smoke_between(mz, aim) and not TankArms.in_smoke(tgt.global_position)
		if bool(c["los"]):
			c["seen_t"] = float(c["seen_t"]) + float(c["think"])
		var k := clampf(float(c["seen_t"]) / AIM_LEARN, 0.0, 1.0)
		var e := lerpf(AIM_ERR0, AIM_ERR1, k)
		if (c["err"] as Vector3).length() < 0.01 or randf() < 0.15:
			c["err"] = Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 0.4), randf_range(-1.0, 1.0)).normalized() * e
		v.set_meta(&"aim_at", aim + (c["err"] as Vector3))
	else:
		c["los"] = false
		c["seen_t"] = 0.0
		if v.has_meta(&"aim_at"):
			v.remove_meta(&"aim_at")


## Every tick: the gun's cooldown, and a round when the target is in sight, in range and under the gun.
func _fight(c: Dictionary, v: Vehicle, dt: float) -> void:
	c["fire_t"] = float(c["fire_t"]) - dt
	if v.weapons == null or not v.weapons.mounted():
		return
	var want := false
	var tgt: Variant = c["target"]
	if bool(c["engaged"]) and bool(c["los"]) and float(c["fire_t"]) <= 0.0 and tgt is Node3D and is_instance_valid(tgt) and v.has_meta(&"aim_at"):
		var ap: Vector3 = v.get_meta(&"aim_at")
		var to := ap - v.muzzle_pos()
		if to.length() < float(v.weapons.def.get("range", 200.0)) and to.normalized().angle_to(v.aim_dir()) < ALIGN:
			want = true
	if v.weapons.tick(dt, want):
		c["fire_t"] = RELOAD
		shots += 1
