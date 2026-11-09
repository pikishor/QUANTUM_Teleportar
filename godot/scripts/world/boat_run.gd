class_name BoatRun
extends Node
## BOAT MISSION HOOKS (wave 105): the harbour's first boat activity and the events a boat mission can hang on. Child of the HarbourWorld.
##
## BOAT RUN: drive any boat or jet ski through the START buoy (the first point of Harbour.COURSE, a cyan beam over the water in the basin); the clock starts, a gold beam marks the next buoy, the last
## one is the finish. The run pays CREDITS by time (PAY_BASE + a bonus for each 10 s under PAR_TIME), says the time and keeps the BEST of the session. Leaving the boat or leaving the harbour ends it
## quietly. EASY by design (docs/DESIGN.md): wide buoys (GATE_RADIUS), a generous par.
## Hooks for the mission system and the tests (signals, nothing else needed):
##   started()                    the run begins        checkpoint(i)             buoy `i` taken       finished(seconds, ok, reward)   cancelled(why)
##   docked(dock_id, boat)        a boat the hero drives stops within a dock's radius (Harbour.DOCKS: the piers, the ferry landing, the west quay): hook for deliveries and pickups
##   Harbour.COURSE, Harbour.DOCKS, hooks()   the places, as data
## Logic is driven by step(dt) from _physics_process while Game.is_playing(); tests call step() directly with `player_boat` set.

signal started
signal checkpoint(index: int)
signal finished(seconds: float, ok: bool, reward: int)
signal cancelled(why: String)
signal docked(dock_id: StringName, boat: Vehicle)

const GATE_RADIUS := 16.0
const PAR_TIME := 75.0
const PAY_BASE := 120
const PAY_BONUS := 40                 ## per 10 s under PAR_TIME
const MAX_TIME := 240.0
const LEAVE_RADIUS := 420.0
const DOCK_SPEED := 3.5
const DOCK_HOLD := 1.0                ## seconds a boat must stay slow inside the dock radius

var running := false
var index := 0                         ## the next buoy
var elapsed := 0.0
var best := 0.0                        ## best time this session (0 = none)
var runs := 0
var player_boat: Vehicle = null        ## the boat the hero drives (tests set it; the live game reads Game.vehicles.driven)
var last_reward := 0
var _beam: MeshInstance3D
var _start_beam: MeshInstance3D
var _cool := 0.0
var _dock_t := 0.0
var _last_dock: StringName = &""


func _ready() -> void:
	set_physics_process(true)
	_start_beam = MissionVisuals.make_beam(Color(0.2, 0.9, 1.0), 2.2, 14.0, 0.9, 0.15)
	_start_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_start_beam.visible = false
	add_child(_start_beam)
	_beam = MissionVisuals.make_beam(Color(1.0, 0.8, 0.3), 2.0, 12.0, 0.9, 0.2)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not Game.is_playing():
		return
	step(delta)


## The hero's boat (or null when he is on foot or in a car).
func current_boat() -> Vehicle:
	if is_instance_valid(player_boat):
		return player_boat if player_boat.cls == &"boat" else null
	var vm := Game.vehicles
	if vm != null:
		var d: Variant = vm.get(&"driven")
		if d is Vehicle and (d as Vehicle).cls == &"boat":
			return d as Vehicle
	return null


func step(dt: float) -> void:
	_cool = maxf(0.0, _cool - dt)
	var boat := current_boat()
	var near := boat != null and Vector2(boat.global_position.x - Harbour.center().x, boat.global_position.z - Harbour.center().z).length() < 700.0
	if _start_beam != null:
		_start_beam.visible = near and not running
		if near and not running:
			_start_beam.global_position = Harbour.COURSE[0] + Vector3(0.0, 4.0, 0.0)
	_dock_check(boat, dt)
	if not running:
		if near and _cool <= 0.0 and Vector2(boat.global_position.x - Harbour.COURSE[0].x, boat.global_position.z - Harbour.COURSE[0].z).length() < GATE_RADIUS:
			begin()
		return
	if boat == null:
		cancel("LEFT THE BOAT")
		return
	if Vector2(boat.global_position.x - Harbour.center().x, boat.global_position.z - Harbour.center().z).length() > LEAVE_RADIUS + 400.0:
		cancel("LEFT THE HARBOUR")
		return
	elapsed += dt
	var gate: Vector3 = Harbour.COURSE[index]
	_beam.visible = true
	_beam.global_position = gate + Vector3(0.0, 4.0, 0.0)
	if Vector2(boat.global_position.x - gate.x, boat.global_position.z - gate.z).length() < GATE_RADIUS:
		checkpoint.emit(index)
		index += 1
		if index >= Harbour.COURSE.size():
			_finish(true)
			return
	if elapsed > MAX_TIME:
		_finish(false)


func begin() -> void:
	running = true
	index = 1
	elapsed = 0.0
	started.emit()
	Game.say("BOAT RUN  FOLLOW THE GOLD BEAMS", 3.0)


func cancel(why: String) -> void:
	if not running:
		return
	running = false
	_beam.visible = false
	_cool = 4.0
	cancelled.emit(why)
	Game.say("BOAT RUN ENDED  " + why, 2.5)


static func reward_for(seconds: float) -> int:
	return PAY_BASE + maxi(0, int((PAR_TIME - seconds) / 10.0)) * PAY_BONUS


func _finish(ok: bool) -> void:
	running = false
	_beam.visible = false
	_cool = 6.0
	runs += 1
	var reward := reward_for(elapsed) if ok else 0
	if ok and (best <= 0.0 or elapsed < best):
		best = elapsed
	last_reward = reward
	var prog := Game.progress as Progress
	if ok and prog != null:
		prog.add_credits(reward)
	Game.say(("BOAT RUN  %.1f S  +%d" % [elapsed, reward]) if ok else "BOAT RUN  TIME UP", 3.5)
	finished.emit(elapsed, ok, reward)


## A boat of the hero that stays slow inside a dock's radius for DOCK_HOLD seconds fires `docked` once per visit.
func _dock_check(boat: Vehicle, dt: float) -> void:
	if boat == null:
		_dock_t = 0.0
		_last_dock = &""
		return
	var nd := Harbour.nearest_dock(boat.global_position)
	var d: Dictionary = nd[0]
	if d.is_empty() or float(nd[1]) > float(d["r"]) + 6.0 or absf(boat.speed) > DOCK_SPEED:
		_dock_t = 0.0
		if d.is_empty() or float(nd[1]) > float(d["r"]) + 14.0:
			_last_dock = &""
		return
	_dock_t += dt
	if _dock_t >= DOCK_HOLD and _last_dock != d["id"]:
		_last_dock = d["id"]
		docked.emit(d["id"], boat)
		Game.say("DOCKED  " + String(d["name"]), 2.0)


## The places a boat mission can use, as data: {id, kind, name, pos, r}. kind: dock (pick up / drop), buoy (a course gate), start.
static func hooks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in Harbour.DOCKS:
		out.append({"id": d["id"], "kind": &"dock", "name": d["name"], "pos": d["pos"], "r": d["r"]})
	for i in Harbour.COURSE.size():
		out.append({"id": StringName("buoy_%d" % i), "kind": &"start" if i == 0 else &"buoy", "name": "BUOY %d" % i, "pos": Harbour.COURSE[i], "r": GATE_RADIUS})
	return out
