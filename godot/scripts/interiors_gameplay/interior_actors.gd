class_name InteriorActors
extends Node3D
## The people of one interior, capped at InteriorData.ACTOR_CAP (3..5): a vendor, civilians (InteriorCivilian, a pool of 5), Vael guards (the existing `operative` from the
## EnemyManager, idle-patrolling between the guard anchors, stealthy: they notice the player only inside STEALTH_DIST or after a shot / heat) and the hunters that followed the
## player through the door (aware, spawned one by one next to the door). Everything is pooled: civilians are built once, guards come from the enemy pool and go back to it.
## Simulates only while Game.is_playing() (the manager ticks it). No allocation per frame.

const POOL := 5
const STEALTH_DIST := 5.0
const PATROL_EVERY := 9.0
const SHOT_RADIUS := 26.0
const FOLLOW_DELAY := 1.4

var vendor: InteriorCivilian
var civilians: Array[InteriorCivilian] = []
var guards: Array[Drone] = []
var followers: Array[Drone] = []
var interior: Node3D
var type: StringName = &"bar"
var officer: Drone                           ## the club's hidden officer (also in `guards`)
var hostage: InteriorCivilian                ## the apartment's captive (also in `civilians`)

var _pool: Array[InteriorCivilian] = []
var _guard_anchors: Array[Vector3] = []
var _patrol_t := 0.0
var _follow_types: Array[StringName] = []
var _follow_t := 0.0
var _hooked_player: Object


func _ready() -> void:
	name = "InteriorActors"


func _acquire() -> InteriorCivilian:
	for c in _pool:
		if not c.active:
			return c
	var c := InteriorCivilian.new()
	add_child(c)
	_pool.append(c)
	return c


func total() -> int:
	var n := 0
	if vendor != null and vendor.active:
		n += 1
	for c in civilians:
		if c.active:
			n += 1
	for g in guards:
		if is_instance_valid(g) and g.active and not g.dead:
			n += 1
	for f in followers:
		if is_instance_valid(f) and f.active and not f.dead:
			n += 1
	return n


func guards_alive() -> int:
	var n := 0
	for g in guards:
		if is_instance_valid(g) and g.active and not g.dead:
			n += 1
	return n


## Fill an interior. `plan` comes from InteriorData.plan(); `follow_types` are the hunters waiting outside (spawned one by one later).
func populate(room: Node3D, t: StringName, plan: Dictionary, follow_types: Array[StringName], mission: StringName, seed_value: int) -> void:
	clear()
	interior = room
	type = t
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 3
	var spots: Array[Vector3] = []
	for a in InteriorGameplay.anchor_points(room, &"civilian", 6, seed_value):
		spots.append(a["pos"])
	# vendor
	if int(plan["vendor"]) > 0:
		var va: Array = InteriorGameplay.anchor_points(room, &"vendor", 1, seed_value)
		var v := _acquire()
		v.setup(rng.randi())
		v.activate(&"vendor", va[0]["pos"], float(va[0]["yaw"]), InteriorData.color(t))
		v.light_with(room)
		vendor = v
	# civilians (the hostage is the one civilian of an apartment with that mission)
	var n_civ := int(plan["civilians"])
	var ca: Array = InteriorGameplay.anchor_points(room, &"civilian", maxi(n_civ, 1), seed_value)
	for i in n_civ:
		var c := _acquire()
		c.setup(rng.randi())
		c.light_with(room)
		var a: Dictionary = ca[i % ca.size()]
		if mission == &"hostage" and i == 0:
			var ha: Array = InteriorGameplay.anchor_points(room, &"hostage", 1, seed_value)
			c.activate(&"hostage", ha[0]["pos"], float(ha[0]["yaw"]), Color(0.4, 0.95, 1.0))
			hostage = c
		else:
			c.activate(&"civilian", a["pos"], float(a["yaw"]))
			c.spots = spots.duplicate()
		civilians.append(c)
	# guards
	_guard_anchors.clear()
	var n_g := int(plan["guards"])
	var ga: Array = InteriorGameplay.anchor_points(room, &"guard", maxi(n_g, 2), seed_value)
	var door_at: Vector3 = room.get("door_pos")
	ga.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector3).distance_to(door_at) > (b["pos"] as Vector3).distance_to(door_at))       # guards stand far from the door
	for a: Dictionary in ga:
		_guard_anchors.append(a["pos"])
	var em := Game.enemies as EnemyManager
	if em != null:
		for i in n_g:
			var pos: Vector3 = _guard_anchors[i % _guard_anchors.size()]
			var g := em.spawn(&"operative", pos, false)
			if g == null:
				continue
			g.aware_dist = STEALTH_DIST
			guards.append(g)
			if mission == &"assassinate" and i == 0:
				officer = g
				var op: Array = InteriorGameplay.anchor_points(room, &"officer", 1, seed_value)
				op.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector3).distance_to(door_at) > (b["pos"] as Vector3).distance_to(door_at))
				g.global_position = op[0]["pos"]
				g.home = Vector3(op[0]["pos"].x, 0.0, op[0]["pos"].z)
				var hp := 240.0 * Progress.enemy_hp_mult()
				g.max_hp = hp
				g.hp = hp
				if g.model != null:
					g.model.scale = Vector3.ONE * 1.18
	_follow_types = follow_types.duplicate()
	_follow_t = FOLLOW_DELAY
	_patrol_t = PATROL_EVERY
	_hook_player()


func _hook_player() -> void:
	var p := Game.player
	if is_instance_valid(p) and p != _hooked_player and p.has_signal(&"fired"):
		(p as Object).connect(&"fired", _on_player_fired)
		_hooked_player = p


## Release everything back to the pools (interior closed, respawn, new game).
func clear() -> void:
	var em := Game.enemies as EnemyManager
	for g in guards:
		if em != null and is_instance_valid(g) and g.active:
			em.release(g)
	for f in followers:
		if em != null and is_instance_valid(f) and f.active:
			em.release(f)
	guards.clear()
	followers.clear()
	for c in _pool:
		c.deactivate()
	civilians.clear()
	vendor = null
	officer = null
	hostage = null
	_follow_types.clear()
	_guard_anchors.clear()


func tick(delta: float) -> void:
	if not Game.is_playing():
		return
	for c in _pool:
		if c.active:
			c.tick(delta)
	# hunters from the street come through the door one at a time
	if not _follow_types.is_empty():
		_follow_t -= delta
		if _follow_t <= 0.0:
			_follow_t = FOLLOW_DELAY
			var em := Game.enemies as EnemyManager
			var t: StringName = _follow_types.pop_front()
			if em != null and interior != null and total() < InteriorData.ACTOR_CAP + 2:
				var at: Vector3 = interior.get("door_pos") + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.4, 0.4))
				var f := em.spawn(t, at, true)
				if f != null:
					followers.append(f)
	# idle guards walk their beat: re-home to the next guard anchor
	_patrol_t -= delta
	if _patrol_t <= 0.0 and _guard_anchors.size() > 1:
		_patrol_t = PATROL_EVERY
		for g in guards:
			if is_instance_valid(g) and g.active and not g.dead and not g.aware and g != officer:
				g.home = _guard_anchors[randi() % _guard_anchors.size()]
	for g in guards:
		if is_instance_valid(g) and g.active and g.aware:
			g.aware_dist = Drone.AWARE_DIST
	_keep_inside()


## Enemies obey the interior's wall rects when they step, but a knockback or a spawn glitch must never leave one outside: pull strays back to the door.
func _keep_inside() -> void:
	if interior == null:
		return
	var bounds: Rect2 = interior.get("bounds")
	for list: Array in [guards, followers]:
		for g: Drone in list:
			if is_instance_valid(g) and g.active and not g.dead and not bounds.grow(1.0).has_point(Vector2(g.global_position.x, g.global_position.z)):
				var dp: Vector3 = interior.get("door_pos")
				g.global_position = Vector3(dp.x, g.global_position.y, dp.z)


func _on_player_fired() -> void:
	if interior == null or not InteriorGameplay.active:
		return
	var p := Game.player.global_position
	for c in civilians:
		if c.active and c.global_position.distance_to(p) < SHOT_RADIUS:
			c.flee_from(p)
	for g in guards:
		if is_instance_valid(g) and g.active and not g.dead and not g.aware and g.global_position.distance_to(p) < SHOT_RADIUS and g != officer:
			g.alert()


## Alert every guard (a safe alarm, a hack wave).
func alert_all() -> void:
	for g in guards:
		if is_instance_valid(g) and g.active and not g.dead:
			g.alert()
