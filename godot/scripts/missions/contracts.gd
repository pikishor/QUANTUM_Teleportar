class_name Contracts
extends Node
## Procedural side missions ("contracts") on top of the sector's core hunt (child of Missions: Game.missions.contracts).
##
## Flow: idle (a pause) -> offered (a marker with a beam stands on a street 60-170 m away; walk or drive into it) -> active -> done / failed -> a pause -> the next one.
## Six kinds (ContractTypes): `officer` kill a marked, tougher Vael officer and his guards; `hack` hold a node's ring for N seconds under drone attack (progress arc on the
## ring); `chase` wreck a fleeing car (a traffic car from the vehicle module made fast); `courier` timed delivery along a route line; `survive` hold a rift anchor through
## waves; `drones` destroy N drones with quantum LINK kills (a kill counts when the drone was linked to another at the moment it died). The story chapter weights which
## kind comes up (ContractTypes.WEIGHTS) and the sector scales enemy health, counts, pay and time limits (Progress.difficulty).
## Rewards: credits (reputation and heat adjusted), coherence, integrity, sometimes a free shop upgrade, +8 reputation. Failures (time out, target lost, anchor lost, too
## many direct kills) cost reputation and can be retried at the same marker (MAX_RETRIES), then the contract is abandoned; dying puts the contract on hold without penalty.
## Everything simulates only while Game.is_playing(); it resets on new_game / next_sector; the visuals (ContractVisuals) are built at the first offer and pooled.
## ORACLE / KESTREL / VAEL BROADCAST lines come from StoryData.CONTRACT_RADIO.

signal offered(kind: StringName)
signal started(kind: StringName)
signal completed(kind: StringName, reward: Dictionary)
signal failed(kind: StringName, reason: String)

const OFFER_DELAY := 20.0              ## seconds after a sector starts before the first offer
const PAUSE_DONE := 16.0
const PAUSE_FAIL := 7.0
const PAUSE_ABANDON := 24.0
const MAX_RETRIES := 2
const ACCEPT_RADIUS := 4.5
const OFFER_MIN := 60.0
const OFFER_MAX := 170.0
const OFFER_FAR := 280.0               ## an offer this far away is moved next to the player
const HACK_RADIUS := 9.0
const HACK_NEED := 24.0                ## seconds inside the ring (sector 1)
const HACK_DECAY := 0.6                ## progress lost per second outside, as a share of the fill rate
const HACK_PULSE := 11.0               ## seconds between drone attacks on the node
const ANCHOR_RADIUS := 40.0
const ANCHOR_LEASH := 62.0
const ANCHOR_LEASH_TIME := 10.0
const WAVE_GAP := 5.0
const SPAWN_STEP := 0.6
const OFFICER_HP := 240.0
const OFFICER_SCALE := 1.18
const OFFICER_HINT_FAR := 70.0         ## beyond this the minimap shows an area, not a point
const OFFICER_HINT_R := 34.0
const CHASE_HP := 140.0
const CHASE_ESCAPE := 120.0
const CHASE_ESCAPE_TIME := 6.0
const COURIER_RADIUS := 6.0
const LINK_WINDOW := 1.5               ## a drone counts as linked for this long after its last linked tick
const DRONE_SPARE := 3                 ## direct kills a link trial forgives (each one is replaced)

var enabled := true
var state: StringName = &"idle"        ## idle | offered | active | cooldown
var kind: StringName = &""
var pos := Vector3.ZERO                ## marker A: the contract's start / zone centre / target
var dest := Vector3.ZERO               ## courier: the drop-off
var time_left := 0.0
var time_total := 0.0
var progress := -1.0                   ## 0..1 for contracts that have one, -1 otherwise
var retries_used := 0
var done_count := 0
var failed_count := 0
var last_reward: Dictionary = {}
var last_fail := ""
var is_retry := false
var target: Node3D                     ## officer (Drone) or chase car (Vehicle)
var foes: Array = []                   ## enemies this contract spawned (Drone)
var wave := 0
var waves := 0
var pending := 0                       ## enemies of the wave still to spawn
var need := 0                          ## link kills / hack seconds needed
var got := 0                           ## link kills so far
var spare := 0
var inside := false
var route: PackedVector3Array = PackedVector3Array()
var rng := RandomNumberGenerator.new()
var visuals: ContractVisuals

var _wait := OFFER_DELAY
var _last_kind: StringName = &""
var _spawn_t := 0.0
var _gap_t := 0.0
var _attack_t := 0.0
var _outside_t := 0.0
var _escape_t := 0.0
var _hint_off := Vector3.ZERO
var _mid_said := false
var _link_seen := {}                   ## Drone instance id -> time of its last linked tick
var _clock := 0.0
var _nag_t := 0.0
var _markers: Array[Dictionary] = []
var _marker_n := 0
var _target_dead := false


func _ready() -> void:
	rng.randomize()
	add_to_group(&"contracts")
	for i in 4:
		_markers.append({pos = Vector3.ZERO, color = Color.WHITE, kind = &"", radius = 0.0})
	Game.new_game.connect(_on_new_sector)
	Game.next_sector.connect(_on_new_sector)
	Game.player_died.connect(_on_died)


func _exit_tree() -> void:
	_cleanup(true)


# --- public API --------------------------------------------------------------------------------------------------------

func chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


func is_active() -> bool:
	return state == &"active"


func has_marker() -> bool:
	return state == &"offered" or state == &"active"


## Forces an offer now (tests, bots, a future "request contract" button). `at` Vector3.INF = pick a street near the player. Returns false when a contract is running.
func offer(k := &"", at := Vector3.INF) -> bool:
	if state == &"active":
		return false
	_cleanup(true)
	kind = k if k != &"" else _pick_kind()
	pos = at if at.is_finite() else _find_spot()
	state = &"offered"
	is_retry = false
	retries_used = 0
	_show_offer()
	offered.emit(kind)
	_radio("offer")
	_chapter_line()
	return true


## Starts the offered contract (walking into the marker does the same).
func accept() -> bool:
	if state != &"offered":
		return false
	if not _begin():
		return false
	return true


## Gives up the running contract (counts as a failure with the "ABANDONED" reason).
func abandon() -> void:
	if state == &"active":
		_fail("ABANDONED")


## Advance by `delta` seconds (the physics process calls it while playing; tests call it directly).
func tick(delta: float) -> void:
	_clock += delta
	match state:
		&"idle":
			_wait -= delta
			if _wait <= 0.0 and enabled and _can_offer():
				offer()
		&"cooldown":
			_wait -= delta
			if _wait <= 0.0:
				if is_retry:
					_re_offer_same()
				else:
					state = &"idle"
					_wait = 0.0
		&"offered":
			_tick_offered()
		&"active":
			_tick_active(delta)


## "HACK NODE  62%   1:20" and the like: one HUD line for the current state ("" when idle).
func hud_line() -> String:
	if not is_instance_valid(Game.player) and state != &"idle":
		return ""
	var title := ContractTypes.title(kind) if kind != &"" else ""
	match state:
		&"offered":
			return "%s%s  %d M" % ["RETRY  " if is_retry else "CONTRACT  ", title, roundi(distance_to_goal())]
		&"active":
			match kind:
				&"officer": return "%s  %s  %d M" % [title, _clock_text(time_left), roundi(distance_to_goal())]
				&"hack": return "%s  %d%%  %s%s" % [title, roundi(maxf(progress, 0.0) * 100.0), _clock_text(time_left), "" if inside else "  RETURN TO THE RING"]
				&"chase": return "%s  %s  %d M" % [title, _clock_text(time_left), roundi(distance_to_goal())]
				&"courier": return "%s  %s  %d M" % [title, _clock_text(time_left), roundi(distance_to_goal())]
				&"survive": return "%s  WAVE %d / %d  FOES %d" % [title, mini(wave + 1, waves), waves, foes_alive() + pending]
				&"drones": return "%s  %d / %d  %s" % [title, got, need, _clock_text(time_left)]
		&"cooldown":
			return "" if not is_retry else "CONTRACT FAILED  RETRY SOON"
	return ""


func distance_to_goal() -> float:
	var p := _ref_pos()
	if not p.is_finite():
		return 0.0
	var goal := pos
	if state == &"active":
		match kind:
			&"officer", &"chase":
				if is_instance_valid(target):
					goal = target.global_position
			&"courier":
				goal = dest
	return Vector2(goal.x - p.x, goal.z - p.z).length()


## 0..1 for the HUD's thin bar, -1 when the contract has none.
func progress_fraction() -> float:
	return progress if state == &"active" else -1.0


## {name, frac} of the marked officer for the HUD's boss bar, {} otherwise.
func boss() -> Dictionary:
	if state == &"active" and kind == &"officer" and is_instance_valid(target):
		var d := target as Drone
		if d != null and not d.dead:
			return {"name": "VAEL OFFICER", "frac": clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)}
	return {}


func foes_alive() -> int:
	var n := 0
	for f: Variant in foes:
		var d := f as Drone
		if d != null and is_instance_valid(d) and d.active and not d.dead and not d.remove:
			n += 1
	return n


## Minimap markers, reused entries: [{pos, color, kind (&"offer" &"target" &"zone" &"dest" &"area"), radius}] (radius in metres: zone and area rings). Call
## marker_count() for how many are valid (the array is reused, so never keep it).
func markers() -> Array[Dictionary]:
	_marker_n = 0
	match state:
		&"offered":
			_add_marker(pos, ContractTypes.CYAN, &"offer", 0.0)
		&"active":
			match kind:
				&"officer":
					if is_instance_valid(target):
						var tp := target.global_position
						var p := _ref_pos()
						if p.is_finite() and Vector2(tp.x - p.x, tp.z - p.z).length() > OFFICER_HINT_FAR:
							_add_marker(tp + _hint_off, ContractTypes.RED, &"area", OFFICER_HINT_R)
						else:
							_add_marker(tp, ContractTypes.RED, &"target", 0.0)
				&"chase":
					if is_instance_valid(target):
						_add_marker(target.global_position, ContractTypes.AMBER, &"target", 0.0)
				&"hack":
					_add_marker(pos, ContractTypes.CYAN, &"zone", HACK_RADIUS)
				&"survive":
					_add_marker(pos, ContractTypes.CYAN, &"zone", ANCHOR_RADIUS)
				&"courier":
					_add_marker(dest, ContractTypes.AMBER, &"dest", 0.0)
				&"drones":
					for f: Variant in foes:
						var d := f as Drone
						if d != null and is_instance_valid(d) and d.active and not d.dead:
							_add_marker(d.global_position, ContractTypes.CYAN, &"target", 0.0)
	return _markers


func marker_count() -> int:
	return _marker_n


func _add_marker(p: Vector3, c: Color, k: StringName, r: float) -> void:
	if _marker_n >= _markers.size():
		return
	var m := _markers[_marker_n]
	m.pos = p
	m.color = c
	m.kind = k
	m.radius = r
	_marker_n += 1


## The route polyline of a courier run (empty otherwise): the minimap draws it as one line.
func route_points() -> PackedVector3Array:
	return route if (state == &"active" and kind == &"courier") else PackedVector3Array()


# --- lifecycle ---------------------------------------------------------------------------------------------------------

func _on_new_sector() -> void:
	_cleanup(true)
	state = &"idle"
	kind = &""
	_wait = OFFER_DELAY
	retries_used = 0
	is_retry = false
	progress = -1.0
	_last_kind = &""


func _on_died() -> void:
	if state == &"active":
		_hold_after_death()


## Dying puts a running contract on hold: what it spawned is removed and the same contract is offered again at its marker, with no penalty.
func _hold_after_death() -> void:
	var k := kind
	var p := pos
	_cleanup(true)
	kind = k
	pos = p
	state = &"offered"
	is_retry = true
	_show_offer()
	_radio_generic("decohered")


func _can_offer() -> bool:
	if not Game.is_playing() or not is_instance_valid(Game.player):
		return false
	if Game.heat >= 3.0:
		return false
	if is_instance_valid(Game.story):
		var tut: Variant = Game.story.get("tutorial")
		if tut != null and (tut as Object).get("active") == true:
			return false
	return true


func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	tick(delta)


func _process(delta: float) -> void:
	if visuals != null and has_marker():
		visuals.animate(delta)


# --- choosing and showing ----------------------------------------------------------------------------------------------

func _pick_kind() -> StringName:
	var banned: Array = []
	if not _car_in_reach():
		banned.append(&"chase")
	return ContractTypes.pick(chapter(), rng, _last_kind, banned)


func _car_in_reach() -> bool:
	var v := Game.vehicles
	if not is_instance_valid(v) or not v.has_method(&"nearest"):
		return false
	var p := Game.player
	if not is_instance_valid(p):
		return false
	if p.get(&"vehicle") != null:
		return true
	return v.call(&"nearest", p.global_position, 55.0) != null


func _ref_pos() -> Vector3:
	var p := Game.player
	if not is_instance_valid(p):
		return Vector3.INF
	var veh := p.get(&"vehicle") as Node3D
	if veh != null and is_instance_valid(veh):
		return veh.global_position
	return p.global_position


func _ensure_visuals() -> void:
	if visuals == null:
		visuals = ContractVisuals.new()
		add_child(visuals)


## A street position within [rmin, rmax] of `center` (the real city, or the junction list of a test world); `center` itself offset 40 m when nothing is found.
func road_point(center: Vector3, rmin: float, rmax: float) -> Vector3:
	var w := Game.world
	if is_instance_valid(w):
		if w.has_method(&"road_point_near"):
			var p: Vector3 = w.call(&"road_point_near", center, rmin, rmax)
			if p.is_finite():
				return Vector3(p.x, 0.0, p.z)
		if "intersections" in w:
			var list: Array[Vector3] = []
			for q: Vector3 in w.intersections:
				var d := Vector2(q.x - center.x, q.z - center.z).length()
				if d >= rmin and d <= rmax:
					list.append(q)
			if not list.is_empty():
				var q2 := list[rng.randi() % list.size()]
				return Vector3(q2.x, 0.0, q2.z)
	var a := rng.randf() * TAU
	return Vector3(center.x + cos(a) * (rmin + rmax) * 0.5, 0.0, center.z + sin(a) * (rmin + rmax) * 0.5)


func _find_spot() -> Vector3:
	var p := _ref_pos()
	if not p.is_finite():
		p = Game.SPAWN
	return road_point(p, OFFER_MIN, OFFER_MAX)


func _show_offer() -> void:
	_ensure_visuals()
	visuals.hide_all()
	visuals.show_marker(0, pos, ACCEPT_RADIUS, ContractTypes.CYAN)
	Game.say("CONTRACT AVAILABLE  %s" % ContractTypes.title(kind), 2.5)


func _re_offer_same() -> void:
	state = &"offered"
	_show_offer()
	_radio_generic("retry")


func _tick_offered() -> void:
	var p := _ref_pos()
	if not p.is_finite():
		return
	var d := Vector2(pos.x - p.x, pos.z - p.z).length()
	if d < ACCEPT_RADIUS and absf(p.y - pos.y) < 6.0:
		_begin()
	elif d > OFFER_FAR and not is_retry:
		pos = _find_spot()
		_show_offer()


# --- starting each kind ------------------------------------------------------------------------------------------------

func _begin() -> bool:
	var ch := chapter()
	var diff := Progress.difficulty(ch)
	foes.clear()
	target = null
	progress = 0.0
	got = 0
	wave = 0
	waves = 0
	pending = 0
	inside = true
	_mid_said = false
	_outside_t = 0.0
	_escape_t = 0.0
	_target_dead = false
	_link_seen.clear()
	_ensure_visuals()
	time_total = ContractTypes.time_limit(kind, ch)
	var ok := true
	match kind:
		&"officer": ok = _begin_officer(ch, diff)
		&"hack": ok = _begin_hack(ch)
		&"chase": ok = _begin_chase(ch)
		&"courier": ok = _begin_courier(ch)
		&"survive": ok = _begin_survive(ch)
		&"drones": ok = _begin_drones(ch)
	if not ok:
		Game.say("AREA CROWDED, STAND BY", 1.6)
		return false
	time_left = time_total
	state = &"active"
	started.emit(kind)
	_radio("start")
	Game.say(ContractTypes.title(kind), 2.0)
	Sfx.play(&"core")
	return true


func _spawn(type: StringName, at: Vector3, aware := true) -> Drone:
	var em := Game.enemies as EnemyManager
	if em == null:
		return null
	var d := em.spawn(type, at, aware)
	if d != null:
		foes.append(d)
	return d


func _begin_officer(ch: int, diff: Dictionary) -> bool:
	var p := _ref_pos()
	var at := road_point(p, 75.0, 135.0)
	var o := _spawn(&"operative", at, false)
	if o == null:
		return false
	var hp := OFFICER_HP * float(diff["hp"])
	o.max_hp = hp
	o.hp = hp
	if o.model != null:
		o.model.scale = Vector3.ONE * OFFICER_SCALE
	target = o
	for i in ContractTypes.count(&"officer", ch):
		var a := TAU * (float(i) + rng.randf()) / float(maxi(ContractTypes.count(&"officer", ch), 1))
		var g := _spawn(&"operative" if i % 2 == 0 or ch < 2 else &"sentinel", at + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(5.0, 9.0), false)
	var ang := rng.randf() * TAU
	_hint_off = Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(10.0, 18.0)
	Game.add_heat(0.5)
	pos = at
	visuals.hide_all()
	visuals.show_marker(0, at, 2.0, ContractTypes.RED, -1.0, true)
	progress = 0.0
	return true


func _begin_hack(ch: int) -> bool:
	need = int(HACK_NEED + 2.0 * ch)
	progress = 0.0
	_attack_t = 5.0
	visuals.hide_all()
	visuals.show_marker(0, pos, HACK_RADIUS, ContractTypes.CYAN, 0.0)
	Game.add_heat(0.4)
	return true


func _begin_survive(ch: int) -> bool:
	waves = 3 + (1 if ch >= 3 else 0)
	wave = 0
	pending = ContractTypes.count(&"survive", ch, 0)
	_spawn_t = 1.0
	_gap_t = 0.0
	progress = 0.0
	visuals.hide_all()
	visuals.show_marker(0, pos, ANCHOR_RADIUS, ContractTypes.CYAN, 0.0)
	Game.add_heat(1.0)
	return true


func _begin_drones(ch: int) -> bool:
	need = ContractTypes.count(&"drones", ch)
	spare = DRONE_SPARE
	got = 0
	var n := 0
	for i in need:
		var at := road_point(pos, 12.0, 46.0)
		if _spawn(&"sentinel", at, false) != null:
			n += 1
	if n == 0:
		return false
	progress = 0.0
	visuals.hide_all()
	visuals.show_marker(0, pos, ANCHOR_RADIUS * 0.6, ContractTypes.CYAN, -1.0, false)
	return true


func _begin_chase(_ch: int) -> bool:
	var vm := Game.vehicles
	if not is_instance_valid(vm) or not vm.has_method(&"spawn_traffic"):
		return false
	var p := _ref_pos()
	var at := road_point(p, 55.0, 100.0)
	var axis := rng.randi() % 2
	var dir := 1 if rng.randf() < 0.5 else -1
	var road_i: int = VehicleSpecs.road_index(at.z if axis == 0 else at.x)
	var along := at.x if axis == 0 else at.z
	var car: Vehicle = vm.call(&"spawn_traffic", &"sedan", axis, road_i, dir, along)
	if car == null:
		_free_a_car(vm)
		car = vm.call(&"spawn_traffic", &"sedan", axis, road_i, dir, along)
	if car == null:
		return false
	car.max_hp = CHASE_HP
	car.hp = CHASE_HP
	car.ai_cruise = minf(15.0 + 1.2 * chapter(), 24.0)
	car.set_meta(&"hold", true)
	if not car.exploded.is_connected(_on_target_exploded):
		car.exploded.connect(_on_target_exploded)
	target = car
	pos = car.global_position
	visuals.hide_all()
	visuals.show_marker(0, pos, 3.0, ContractTypes.AMBER, -1.0, true)
	Game.add_heat(0.1)
	progress = 0.0
	return true


## The vehicle module is at its tier cap: the farthest ordinary car goes back to the pool to make room for the target.
func _free_a_car(vm: Node) -> void:
	var list: Array = vm.get("list")
	var p := _ref_pos()
	var far: Vehicle = null
	var far_d := -1.0
	for v: Vehicle in list:
		if v == vm.get("starter") or v.driver_is_player or v.has_meta(&"hold"):
			continue
		var d := v.global_position.distance_to(p)
		if d > far_d:
			far_d = d
			far = v
	if far != null:
		vm.call(&"_release", far)


func _begin_courier(ch: int) -> bool:
	var origin := pos
	var w := Game.world
	var best := Vector3.INF
	if is_instance_valid(w) and "intersections" in w:
		var cand: Array[Vector3] = []
		for q: Vector3 in w.intersections:
			var d := Vector2(q.x - origin.x, q.z - origin.z).length()
			if d >= 220.0 and d <= 360.0:
				cand.append(q)
		if not cand.is_empty():
			best = cand[rng.randi() % cand.size()]
	if not best.is_finite():
		best = road_point(origin, 200.0, 340.0)
	dest = Vector3(best.x, 0.0, best.z)
	route = build_route(origin, dest)
	time_total = ContractTypes.time_limit(&"courier", ch, ContractTypes.route_length(origin, dest))
	visuals.hide_all()
	visuals.show_marker(1, dest, COURIER_RADIUS, ContractTypes.AMBER, -1.0, true)
	visuals.set_route(route)
	progress = 0.0
	_hint_off = Vector3(maxf(Vector2(dest.x - origin.x, dest.z - origin.z).length(), 1.0), 0.0, 0.0)     ## x: the straight distance at the start (progress base)
	return true


## The street-aligned path from a to b: along the road the start stands on, then along the one the destination stands on (one corner).
static func build_route(a: Vector3, b: Vector3) -> PackedVector3Array:
	var ia := VehicleSpecs.road_index(a.x)
	var on_z_road := absf(a.x - VehicleSpecs.road_center(ia)) < Game.ROAD * 0.5
	var corner := Vector3(a.x, 0.0, b.z) if on_z_road else Vector3(b.x, 0.0, a.z)
	return PackedVector3Array([Vector3(a.x, 0.0, a.z), corner, Vector3(b.x, 0.0, b.z)])


# --- ticking an active contract ----------------------------------------------------------------------------------------

func _tick_active(delta: float) -> void:
	time_left -= delta
	var p := _ref_pos()
	match kind:
		&"officer": _tick_officer(delta)
		&"hack": _tick_hack(delta, p)
		&"chase": _tick_chase(delta, p)
		&"courier": _tick_courier(p)
		&"survive": _tick_survive(delta, p)
		&"drones": _tick_drones(delta)
	if state != &"active":
		return
	if time_left <= 0.0:
		_fail("TIME OUT")
		return
	if not _mid_said and _is_mid():
		_mid_said = true
		_radio("mid")


func _is_mid() -> bool:
	match kind:
		&"officer": return progress >= 0.5
		&"hack": return progress >= 0.5
		&"chase": return time_left < time_total * 0.5
		&"courier": return time_left < time_total * 0.5
		&"survive": return wave >= 1
		&"drones": return got * 2 >= need
	return false


func _tick_officer(_delta: float) -> void:
	var d := target as Drone
	if d == null or not is_instance_valid(d):
		_fail("TARGET LOST")
		return
	if d.dead or d.hp <= 0.0:
		_complete(clampf(time_left / maxf(time_total, 1.0), 0.0, 1.0))
		return
	if not d.active or d.remove:
		_fail("TARGET LOST")
		return
	d.set(&"_bar_t", 6.0)                          # the officer keeps his health bar in the world, not only after a hit
	progress = 1.0 - clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
	visuals.move_marker(0, d.global_position)


func _tick_hack(delta: float, p: Vector3) -> void:
	var d := Vector2(pos.x - p.x, pos.z - p.z).length() if p.is_finite() else INF
	inside = d < HACK_RADIUS and absf(p.y - pos.y) < 6.0
	var rate := delta / maxf(float(need), 1.0)
	progress = clampf(progress + (rate if inside else -rate * HACK_DECAY), 0.0, 1.0)
	visuals.set_progress(0, progress)
	_nag_t -= delta
	if not inside and _nag_t <= 0.0:
		_nag_t = 4.0
		Game.say("RETURN TO THE RING", 1.5)
	_attack_t -= delta
	if _attack_t <= 0.0:
		_attack_t = HACK_PULSE
		_hack_attack()
	if progress >= 1.0:
		_complete(clampf(time_left / maxf(time_total, 1.0), 0.0, 1.0))


func _hack_attack() -> void:
	var ch := chapter()
	var n := ContractTypes.count(&"hack", ch)
	for i in n:
		var type := &"sentinel"
		if i % 3 == 2:
			type = &"striker"
		elif ch >= 2 and i % 2 == 1:
			type = &"operative"
		_spawn(type, road_point(pos, 34.0, 56.0), true)       # EnemyManager.spawn already applies the sector's health factor
	_prune_foes()


func _tick_chase(delta: float, p: Vector3) -> void:
	var car := target as Vehicle
	if car == null or not is_instance_valid(car):
		_fail("TARGET LOST")
		return
	if _target_dead or car.dead:
		_complete(clampf(time_left / maxf(time_total, 1.0), 0.0, 1.0))
		return
	if not car.active:
		_fail("TARGET LOST")
		return
	var d := Vector2(car.global_position.x - p.x, car.global_position.z - p.z).length() if p.is_finite() else 0.0
	if d > CHASE_ESCAPE:
		_escape_t += delta
		if _escape_t > CHASE_ESCAPE_TIME:
			_fail("TARGET ESCAPED")
			return
	else:
		_escape_t = 0.0
	progress = 1.0 - clampf(car.hp / maxf(car.max_hp, 1.0), 0.0, 1.0)
	pos = car.global_position
	visuals.move_marker(0, car.global_position)


func _on_target_exploded(_v: Vehicle) -> void:
	_target_dead = true


func _tick_courier(p: Vector3) -> void:
	if not p.is_finite():
		return
	var d := Vector2(dest.x - p.x, dest.z - p.z).length()
	var base := maxf(_hint_off.x, 1.0)
	progress = clampf(1.0 - d / base, 0.0, 1.0)
	if d < COURIER_RADIUS and absf(p.y - dest.y) < 6.0:
		_complete(clampf(time_left / maxf(time_total, 1.0), 0.0, 1.0))


func _tick_survive(delta: float, p: Vector3) -> void:
	var d := Vector2(pos.x - p.x, pos.z - p.z).length() if p.is_finite() else 0.0
	inside = d < ANCHOR_LEASH
	if inside:
		_outside_t = 0.0
	else:
		_outside_t += delta
		_nag_t -= delta
		if _nag_t <= 0.0:
			_nag_t = 3.0
			Game.say("RETURN TO THE ANCHOR", 1.5)
		if _outside_t > ANCHOR_LEASH_TIME:
			_fail("ANCHOR LOST")
			return
	if pending > 0:
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = SPAWN_STEP
			if _spawn_wave_enemy():
				pending -= 1
	elif foes_alive() == 0:
		if _gap_t <= 0.0 and wave < waves:
			_gap_t = WAVE_GAP
			Game.say("WAVE %d CLEARED" % (wave + 1), 1.8)
		_gap_t -= delta
		if _gap_t <= 0.0:
			wave += 1
			if wave >= waves:
				progress = 1.0
				_complete(clampf(time_left / maxf(time_total, 1.0), 0.0, 1.0))
				return
			pending = ContractTypes.count(&"survive", chapter(), wave)
			_spawn_t = 1.0
			if wave == waves - 1 and not _mid_said:
				Game.say("FINAL WAVE", 1.8)
	progress = clampf((float(wave) + (1.0 - float(pending + foes_alive()) / float(maxi(ContractTypes.count(&"survive", chapter(), wave), 1)))) / float(maxi(waves, 1)), 0.0, 0.99)
	visuals.set_progress(0, clampf(float(wave) / float(maxi(waves, 1)), 0.0, 1.0))
	_prune_foes()


func _spawn_wave_enemy() -> bool:
	var ch := chapter()
	var type := &"sentinel"
	var roll := rng.randi() % 4
	if wave == 0:
		type = &"operative" if roll == 0 else &"sentinel"
	elif wave < waves - 1:
		type = &"operative" if roll < 2 else (&"striker" if roll == 2 else &"sentinel")
	else:
		type = &"heavy" if (ch >= 2 and pending == 1) else (&"operative" if roll < 2 else &"striker")
	return _spawn(type, road_point(pos, 36.0, 58.0), true) != null


func _tick_drones(_delta: float) -> void:
	var now := _clock
	var i := foes.size() - 1
	while i >= 0:
		var d := foes[i] as Drone
		if d == null or not is_instance_valid(d) or not d.active:
			foes.remove_at(i)
		elif d.dead:
			var link_kill := _link_seen.has(d.get_instance_id()) and now - float(_link_seen[d.get_instance_id()]) <= LINK_WINDOW
			_link_seen.erase(d.get_instance_id())
			foes.remove_at(i)
			if link_kill:
				got += 1
				Game.say("LINK KILL  %d / %d" % [got, need], 1.8)
				Sfx.play(&"link")
			else:
				spare -= 1
				Game.say("DIRECT KILL  DOES NOT COUNT", 2.0)
		elif is_instance_valid(d.linked) and not d.linked.dead:
			_link_seen[d.get_instance_id()] = now
		i -= 1
	progress = clampf(float(got) / float(maxi(need, 1)), 0.0, 1.0)
	if got >= need:
		_complete(clampf(time_left / maxf(time_total, 1.0), 0.0, 1.0))
		return
	var missing := maxi(need - got, 2) - foes.size()       # always two drones alive, so the last kill still has a partner to link
	if missing > 0:
		if spare < 0:
			_fail("TOO MANY DIRECT KILLS")
			return
		for k in missing:
			if _spawn(&"sentinel", road_point(pos, 14.0, 46.0), false) == null:
				break


func _prune_foes() -> void:
	var i := foes.size() - 1
	while i >= 0:
		var d := foes[i] as Drone
		if d == null or not is_instance_valid(d) or not d.active:
			foes.remove_at(i)
		i -= 1


# --- ending ------------------------------------------------------------------------------------------------------------

func _complete(speed: float) -> void:
	var prog := Game.progress as Progress
	var rep := prog.reputation if prog != null else 0
	var ch := chapter()
	var r := ContractTypes.reward(kind, ch, Progress.rep_bonus(rep), speed)
	var credits := int(r["credits"])
	var heat_f := ContractTypes.heat_factor(Game.heat)
	credits = int(roundf(float(credits) * heat_f / 5.0)) * 5
	r["credits"] = credits
	r["heat_factor"] = heat_f
	if prog != null:
		prog.add_credits(credits)
		prog.add_reputation(int(r["rep"]))
		prog.contracts_done += 1
		prog.bonus_score(100)
	else:
		Game.add_score(100)
	var pl := Game.player
	if is_instance_valid(pl):
		if pl.has_method(&"add_energy"):
			pl.call(&"add_energy", float(r["energy"]))
		if pl.has_method(&"heal"):
			pl.call(&"heal", float(r["heal"]))
	var upgrade := &""
	if bool(r["upgrade"]) and prog != null:
		upgrade = prog.grant_upgrade(&"", rng)
	r["upgrade_id"] = upgrade
	last_reward = r
	done_count += 1
	var k := kind
	var msg := "CONTRACT COMPLETE  +%d CREDITS" % credits
	if upgrade != &"":
		msg += "  +%s" % Upgrades.title(upgrade)
	Game.say(msg, 3.2)
	Sfx.play(&"core")
	FX.burst(pos + Vector3(0.0, 1.0, 0.0), ContractTypes.color(k), 40, 8.0, 0.9, 1.0, 1.0)
	_cleanup(false)
	state = &"cooldown"
	is_retry = false
	retries_used = 0
	_wait = PAUSE_DONE
	_last_kind = k
	kind = k
	completed.emit(k, r)
	_radio("done", String(k))
	if upgrade != &"":
		_radio_generic("upgrade")
	if prog != null and Progress.rep_tier(prog.reputation) > Progress.rep_tier(rep):
		_radio_generic("rep_up")


func _fail(reason: String) -> void:
	var k := kind
	var prog := Game.progress as Progress
	failed_count += 1
	last_fail = reason
	retries_used += 1
	if prog != null:
		prog.contracts_failed += 1
		prog.add_reputation(-4)
	_cleanup(true)
	kind = k
	_last_kind = k
	Game.say("CONTRACT FAILED  %s" % reason, 3.0)
	Sfx.play(&"hurt")
	failed.emit(k, reason)
	_radio("fail", String(k))
	if retries_used <= MAX_RETRIES and reason != "ABANDONED":
		state = &"cooldown"
		is_retry = true
		_wait = PAUSE_FAIL
	else:
		if prog != null:
			prog.add_reputation(-3)
		_radio_generic("abandon")
		state = &"cooldown"
		is_retry = false
		retries_used = 0
		_wait = PAUSE_ABANDON


## Hide the visuals, release the car's hold, and (when `release_foes`) send what the contract spawned back to the pool.
func _cleanup(release_foes: bool) -> void:
	if visuals != null:
		visuals.hide_all()
	var car := target as Vehicle
	if car != null and is_instance_valid(car):
		car.remove_meta(&"hold")
		if car.exploded.is_connected(_on_target_exploded):
			car.exploded.disconnect(_on_target_exploded)
	if release_foes:
		var em := Game.enemies as EnemyManager
		if em != null:
			for f: Variant in foes:
				var d := f as Drone
				if d != null and is_instance_valid(d) and d.active:
					em.release(d)
	foes.clear()
	target = null
	_link_seen.clear()
	progress = -1.0


# --- radio ---------------------------------------------------------------------------------------------------------------

func _say_line(l: Dictionary, id: String, prio := 1) -> void:
	if is_instance_valid(Game.story) and Game.story.has_method(&"say"):
		Game.story.call(&"say", str(l["s"]), str(l["t"]), id, 0.0, prio)


func _radio(key: String, kind_name := "") -> void:
	var k := kind_name if kind_name != "" else String(kind)
	var lines: Array = (StoryData.CONTRACT_RADIO.get(k, {}) as Dictionary).get(key, [])
	if lines.is_empty():
		return
	_say_line(lines[rng.randi() % lines.size()] as Dictionary, "contract.%s.%s" % [k, key])


func _radio_generic(key: String) -> void:
	var lines: Array = StoryData.CONTRACT_GENERIC.get(key, [])
	if lines.is_empty():
		return
	_say_line(lines[rng.randi() % lines.size()] as Dictionary, "contract.%s" % key)


var _chapter_said := -1

func _chapter_line() -> void:
	var ch := chapter()
	if ch == _chapter_said:
		return
	_chapter_said = ch
	_say_line(StoryData.CONTRACT_CHAPTER[clampi(ch, 0, StoryData.CONTRACT_CHAPTER.size() - 1)], "contract.chapter%d" % ch, 0)


static func _clock_text(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
