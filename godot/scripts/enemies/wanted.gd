class_name Wanted
extends Node
## WANTED v2 (Game.heat is the level, 0..5 stars, unchanged) with escalating patrol responses and a hide-and-lose mechanic. Child of main (`Wanted.current`).
##   Responses by level (RESPONSES): 1 foot patrols (the EnemyManager reinforcements), 2 PATROL CARS (VehicleManager.spawn_patrol, capped by its tier cap), 3 ROADBLOCKS (a barrier across the
##   road ahead with two guards), 4 HUNTER DRONES (flying, hover over the hero), 5 ELITE SQUAD (three specialists of the camp that holds the ground, Factions.ELITES). Everything is spawned
##   through the pools and caps that exist (EnemyManager.cap / tier limits, the car cap); a roadblock is two pooled nodes of one shared box mesh and material.
##   Hide and lose: while nobody has the hero in sight the heat falls faster the better he hides (HIDE_RATE): COVER (out of every aware enemy's line of sight for LOS_BREAK s), INTERIOR
##   (inside a room), DISGUISE (changed vehicle or got out of one, DISGUISE_TIME s) and DECOY (a SUPERPOSITION clone has aware enemies within DECOY_RANGE). Dispatching stops while hidden.
##   Reaching 0 from above counts a WANTED LOST. Simulates only while Game.is_playing() (Game.state is the only pause); `tick(delta)` is callable by tests.

signal level_changed(level: int)
signal lost

const LEVELS := 5
## cars / block / drones / elite: how many of each response may be alive at a level.
const RESPONSES: Array[Dictionary] = [
	{"cars": 0, "block": 0, "drones": 0, "elite": 0},
	{"cars": 0, "block": 0, "drones": 0, "elite": 0},
	{"cars": 1, "block": 0, "drones": 0, "elite": 0},
	{"cars": 1, "block": 1, "drones": 0, "elite": 0},
	{"cars": 2, "block": 1, "drones": 2, "elite": 0},
	{"cars": 2, "block": 2, "drones": 3, "elite": 3},
]
const RESPONSE_LABEL: Array[String] = ["", "FOOT PATROLS", "PATROL CARS", "ROADBLOCKS", "HUNTER DRONES", "ELITE SQUAD"]
const DISPATCH_EVERY := 3.0
const WATCH_EVERY := 0.25
const LOS_BREAK := 3.0                 ## seconds out of sight before COVER counts
const DISGUISE_TIME := 9.0
const DECOY_RANGE := 30.0
const HIDE_RATE := {&"cover": 0.10, &"interior": 0.25, &"disguise": 0.30, &"decoy": 0.35}     ## extra heat lost per second
const MODE_LABEL := {&"cover": "HIDDEN", &"interior": "INSIDE", &"disguise": "DISGUISED", &"decoy": "DECOY"}
const BLOCK_SIZE := Vector3(9.0, 1.1, 0.9)
const BLOCK_MIN := 55.0
const BLOCK_MAX := 90.0
const RELEASE_DIST := 170.0

static var current: Wanted

var hide_mode: StringName = &""        ## "" | cover | interior | disguise | decoy
var watchers := 0                      ## aware enemies that have the hero in line of sight
var hidden_t := 0.0                    ## seconds nobody has had him in sight
var lost_count := 0
var decoys_used := 0
var dispatched := {&"car": 0, &"block": 0, &"drone": 0, &"elite": 0}
var last_level := 0

var _watch_t := 0.0
var _dispatch_t := 1.0
var _inside_t := 0.0
var _disguise_t := 0.0
var _veh_id := 0
var _was_hot := false
var _clone_id := 0
var _drones: Array[Drone] = []
var _elite: Array[Drone] = []
var _guards: Array[Drone] = []
var _blocks: Array[Node3D] = []        ## pooled barrier nodes (visible = in use)
var _block_mesh: BoxMesh
var _block_mat: StandardMaterial3D


func _ready() -> void:
	current = self
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)


func _exit_tree() -> void:
	if current == self:
		current = null


# --- pure rules ----------------------------------------------------------------------------------------------------

static func level_of(heat: float) -> int:
	return 0 if heat <= 0.0 else clampi(ceili(heat), 1, LEVELS)


static func response(level: int) -> Dictionary:
	return RESPONSES[clampi(level, 0, LEVELS)]


## The hide mode for the facts: inside a room, a decoy at work, a fresh disguise, cover after LOS_BREAK seconds. "" while seen or with no heat.
static func mode_for(heat: float, watching: int, hidden: float, inside: float, disguise: float, decoy_busy: bool) -> StringName:
	if heat <= 0.0:
		return &""
	if inside >= 1.0:
		return &"interior"
	if watching > 0:
		return &""
	if decoy_busy and hidden >= 1.0:
		return &"decoy"
	if disguise > 0.0 and hidden >= 1.0:
		return &"disguise"
	if hidden >= LOS_BREAK:
		return &"cover"
	return &""


static func rate_for(mode: StringName) -> float:
	return float(HIDE_RATE.get(mode, 0.0))


# --- API -----------------------------------------------------------------------------------------------------------

func level() -> int:
	return level_of(Game.heat)


func live(kind: StringName) -> int:
	_prune()
	match kind:
		&"car":
			var vm := Game.vehicles
			return int(vm.call(&"patrol_count", true)) if is_instance_valid(vm) and vm.has_method(&"patrol_count") else 0
		&"block":
			var n := 0
			for b in _blocks:
				if b.visible:
					n += 1
			return n
		&"drone":
			return _drones.size()
		&"elite":
			return _elite.size()
	return 0


## What the HUD says about the wanted state: SPOTTED, SEARCHING or the hide mode. Empty without heat.
func state_label() -> String:
	if Game.heat <= 0.0:
		return ""
	if hide_mode != &"":
		return String(MODE_LABEL[hide_mode])
	return "SPOTTED" if watchers > 0 else "SEARCHING"


## One HUD line: the faction of the hero's ground and its standing with the hero.
func faction_line() -> String:
	var p := Game.player
	if not is_instance_valid(p):
		return ""
	var camp := Factions.at((p as Node3D).global_position)
	return "%s  %s" % [Factions.title(camp), Factions.status_name(Game.progress, camp)]


func reset() -> void:
	hide_mode = &""
	watchers = 0
	hidden_t = 0.0
	_inside_t = 0.0
	_disguise_t = 0.0
	_veh_id = 0
	_was_hot = false
	last_level = 0
	_dispatch_t = 1.0
	_drones.clear()
	_elite.clear()
	_guards.clear()
	for b in _blocks:
		_hide_block(b)


func _physics_process(delta: float) -> void:
	if Game.is_playing():
		tick(delta)


func tick(delta: float) -> void:
	var heat := Game.heat
	var lv := level_of(heat)
	if lv != last_level:
		if lv > last_level and lv >= 2 and Game.is_playing():
			Game.say(RESPONSE_LABEL[lv], 1.8)
		last_level = lv
		level_changed.emit(lv)
	if heat > 0.0:
		_was_hot = true
	_track_vehicle(heat)
	_watch_t -= delta
	if _watch_t <= 0.0:
		_watch_t = WATCH_EVERY
		_count_watchers()
	if watchers > 0 and not InteriorGameplay.active:
		hidden_t = 0.0
	else:
		hidden_t += delta
	_inside_t = _inside_t + delta if InteriorGameplay.active else 0.0
	_disguise_t = maxf(0.0, _disguise_t - delta)
	var decoy := _decoy_busy()
	hide_mode = mode_for(heat, watchers, hidden_t, _inside_t, _disguise_t, decoy)
	if hide_mode == &"decoy" and _clone_id != _clone_instance():
		_clone_id = _clone_instance()
		decoys_used += 1
	if hide_mode != &"" and heat > 0.0:
		Game.heat = maxf(0.0, heat - rate_for(hide_mode) * delta)
	if _was_hot and Game.heat <= 0.0:
		_was_hot = false
		lost_count += 1
		hide_mode = &""
		Game.say("WANTED LOST", 2.0)
		lost.emit()
	_dispatch_t -= delta
	if _dispatch_t <= 0.0:
		_dispatch_t = DISPATCH_EVERY
		if hide_mode == &"" and not InteriorGameplay.active:
			dispatch()
		_release_far()


## One dispatch step: the first response below its level's allowance is sent (car, elite squad, hunter drones, roadblock: the most severe first, so the enemy cap never starves it). Returns the kind sent (&"" none).
func dispatch() -> StringName:
	var lv := level()
	if lv < 2:
		return &""
	var want := response(lv)
	_prune()
	var p := Game.player
	var em := Game.enemies as EnemyManager
	if not is_instance_valid(p) or em == null:
		return &""
	var ppos := (p as Node3D).global_position
	var camp := Factions.at(ppos)
	if live(&"car") < mini(int(want["cars"]), _car_cap()):
		var vm := Game.vehicles
		if is_instance_valid(vm) and vm.has_method(&"spawn_patrol") and vm.call(&"spawn_patrol") != null:
			dispatched[&"car"] += 1
			return &"car"
	if _elite.size() < int(want["elite"]):
		var types: Array = Factions.ELITES[camp]
		var t: StringName = types[_elite.size() % types.size()]
		if em.count_type(t) >= EnemyTypes.tier_limit(t, Game.quality):
			t = &"operative"
		var e := _spawn_near(em, t, ppos, camp)
		if e != null:
			_elite.append(e)
			dispatched[&"elite"] += 1
			return &"elite"
	if _drones.size() < int(want["drones"]):
		var d := _spawn_near(em, &"sentinel", ppos, camp)
		if d != null:
			_drones.append(d)
			dispatched[&"drone"] += 1
			return &"drone"
	if live(&"block") < int(want["block"]) and _send_block(ppos, camp, em):
		dispatched[&"block"] += 1
		return &"block"
	return &""


# --- internals -----------------------------------------------------------------------------------------------------

func _car_cap() -> int:
	var vm := Game.vehicles
	return int(vm.call(&"patrol_cap")) if is_instance_valid(vm) and vm.has_method(&"patrol_cap") else 0


func _count_watchers() -> void:
	var em := Game.enemies as EnemyManager
	var n := 0
	if em != null:
		for e in em.list:
			if e.active and not e.dead and e.aware and e.los:
				n += 1
	watchers = n


func _track_vehicle(heat: float) -> void:
	var p := Game.player
	var id := 0
	if is_instance_valid(p):
		var v: Variant = p.get(&"vehicle")
		if v is Node3D and is_instance_valid(v):
			id = (v as Node3D).get_instance_id()
	if id != _veh_id:
		if heat > 0.0:
			_disguise_t = DISGUISE_TIME
		_veh_id = id


func _clone_instance() -> int:
	var em := Game.enemies as EnemyManager
	var c := em.get_clone() if em != null else null
	return c.get_instance_id() if c != null else 0


## A SUPERPOSITION clone stands and an aware enemy is within DECOY_RANGE of it.
func _decoy_busy() -> bool:
	var em := Game.enemies as EnemyManager
	if em == null:
		return false
	var c := em.get_clone()
	if c == null:
		return false
	for e in em.list:
		if e.active and not e.dead and e.aware and e.global_position.distance_to(c.global_position) < DECOY_RANGE:
			return true
	return false


func _prune() -> void:
	for arr: Array in [_drones, _elite, _guards]:
		var i := arr.size() - 1
		while i >= 0:
			var d: Variant = arr[i]
			if not is_instance_valid(d) or (d as Drone).dead or not (d as Drone).active:
				arr.remove_at(i)
			i -= 1


func _spawn_near(em: EnemyManager, type: StringName, ppos: Vector3, camp: StringName) -> Drone:
	if em.alive_count() >= em.cap():
		return null
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return null
	var pt: Vector3 = w.call(&"road_point_near", ppos, 45.0, 80.0)
	if not pt.is_finite():
		return null
	var want: StringName = camp if camp != Factions.DRONES else &""
	return em.spawn(type, pt, true, true, want)


func _send_block(ppos: Vector3, camp: StringName, em: EnemyManager) -> bool:
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near") or em.alive_count() + 2 > em.cap():
		return false
	var pt: Vector3 = w.call(&"road_point_near", ppos, BLOCK_MIN, BLOCK_MAX)
	if not pt.is_finite():
		return false
	var node := _free_block()
	_place_block(node, pt, ppos)
	var away := Vector3(pt.x - ppos.x, 0.0, pt.z - ppos.z).normalized()
	var side := Vector3(-away.z, 0.0, away.x)
	var guard: StringName = Factions.GUARD[camp]
	for i in 2:
		var g := em.spawn(guard, pt + away * 3.0 + side * (-2.0 + 4.0 * float(i)), true, true, camp if camp != Factions.DRONES else &"")
		if g != null:
			_guards.append(g)
	return true


func _free_block() -> Node3D:
	for b in _blocks:
		if not b.visible:
			return b
	if _block_mesh == null:
		_block_mesh = BoxMesh.new()
		_block_mesh.size = BLOCK_SIZE
		_block_mat = StandardMaterial3D.new()
		_block_mat.albedo_color = Color(0.12, 0.13, 0.16)
		_block_mat.roughness = 0.7
		_block_mat.emission_enabled = true
		_block_mat.emission = Color(1.0, 0.2, 0.18)
		_block_mat.emission_energy_multiplier = 0.35
		_block_mesh.material = _block_mat
	var body := StaticBody3D.new()
	body.name = "Roadblock"
	body.collision_layer = 0
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(BLOCK_SIZE.x, 1.6, BLOCK_SIZE.z)
	cs.shape = bs
	cs.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _block_mesh
	mi.position = Vector3(0.0, BLOCK_SIZE.y * 0.5, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	body.visible = false
	add_child(body)
	_blocks.append(body)
	return body


func _place_block(node: Node3D, pt: Vector3, ppos: Vector3) -> void:
	node.global_position = Vector3(pt.x, 0.0, pt.z)
	var to := Vector3(ppos.x, 0.0, ppos.z)
	if to.distance_to(Vector3(pt.x, 0.0, pt.z)) > 0.5:
		node.look_at(to, Vector3.UP)
	node.visible = true
	(node as StaticBody3D).collision_layer = Game.L_WORLD


func _hide_block(node: Node3D) -> void:
	node.visible = false
	(node as StaticBody3D).collision_layer = 0


## Roadblocks fall back to the pool when the heat is below level 3 or the hero is far away.
func _release_far() -> void:
	var p := Game.player
	if not is_instance_valid(p):
		return
	var ppos := (p as Node3D).global_position
	for b in _blocks:
		if not b.visible:
			continue
		if level() < 3 or Vector2(b.global_position.x - ppos.x, b.global_position.z - ppos.z).length() > RELEASE_DIST:
			_hide_block(b)
