class_name RailJobs
extends Node
## Train missions (wave 106; docs/DESIGN.md: easy missions with GTA and COD flavour). Four jobs on markers at the stations; they start when the hero stands in the ring, pay through
## `Progress.add_credits`, and never trap the player: every job has a time limit and an `abort()`; failing only drops the job and the marker comes back. One job at a time.
##   HEIST        NORTH STATION     board the ORE train, climb onto the roof of its box car, hold the hatch for 4 s, jump off with the loot            (+350)
##   ESCORT       NORTH STATION     ride the EXPRESS to MOUNT STATION; guards storm the train at FOOTHILLS and must be dealt with before it arrives  (+450)
##   DERAIL       the coast line    blow the track at the marker (a grenade, a charge, a rocket) while the CONTAINER train runs at it                 (+600)
##   ROOF CHASE   GREENWAY          board the REGIONAL train; four guards stand on its roof once it pulls out: climb up and clear it                    (+500)
## `jobs` is the table; `state` the running job's step; signals `started`, `step`, `finished(ok, reward)`; `markers()` feeds the minimap. Tests drive a job with `start(id)` and `poll(dt)`.

signal started(id: StringName)
signal step_changed(id: StringName, step: StringName)
signal finished(id: StringName, ok: bool, reward: int)

const RING := 9.0
const STAY := 1.2
const LIMIT := 300.0
const PAY := {&"heist": 350, &"escort": 450, &"derail": 600, &"roof": 500}
const TITLES := {&"heist": "TRAIN HEIST", &"escort": "TRAIN ESCORT", &"derail": "DERAIL", &"roof": "ROOF CHASE"}

var active: StringName = &""
var step: StringName = &""
var elapsed := 0.0
var done := {}                                  ## id -> times completed
var enemies: Array = []
var objective := ""
var _t_in := 0.0
var _hold := 0.0
var _mark := Vector3.ZERO
var _train: Train
var _cool := 0.0
var _spawned := false
var _loot := false
var _blown := false
var _conn := false


## The ring positions on the line (a platform spot of the station, or a point of the track).
func spot(id: StringName) -> Vector3:
	var rw := RailWorld.instance
	var r: Dictionary
	match id:
		&"heist", &"escort":
			r = RailNet.route(&"mountain")
			return _platform_spot(r, 0)
		&"roof":
			r = RailNet.route(&"coast")
			return _platform_spot(r, 0)
		&"derail":
			r = RailNet.route(&"coast")
			var pa := RailNet.point_at(r, float(r["len"]) * 0.55)
			var t := Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
			return (pa[0] as Vector3) + RailNet.right_of(t) * 7.5 + Vector3(0.0, 0.2, 0.0)
	return Vector3.INF


func _platform_spot(r: Dictionary, idx: int) -> Vector3:
	var st: Dictionary = r["stations"][idx]
	var pa := RailNet.point_at(r, float(st["s"]) - 20.0)
	var t := Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
	return (pa[0] as Vector3) + RailNet.right_of(t) * (RailNet.HALF_SEP * float(pa[2]) + 1.62 + 2.2) + Vector3(0.0, RailNet.PLATFORM_Y + 0.3, 0.0)


func target_pos(id: StringName) -> Vector3:
	if id == &"derail":
		return _mark if _mark != Vector3.ZERO else spot(&"derail")
	return spot(id)


func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in [&"heist", &"escort", &"derail", &"roof"]:
		if active == &"" or active == id:
			out.append({"pos": spot(id), "color": Color(1.0, 0.72, 0.2), "radius": 9.0, "goal": active == id, "label": String(TITLES[id]), "kind": &"job"})
	return out


func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	poll(delta)


## One tick of the job logic (the world calls it every physics frame; tests call it with their own dt).
func poll(delta: float) -> void:
	if not Game.is_playing() or not is_instance_valid(Game.player):
		return
	_cool = maxf(0.0, _cool - delta)
	var hero := (Game.player as Node3D).global_position
	if active == &"":
		if _cool > 0.0:
			return
		for id: StringName in [&"heist", &"escort", &"derail", &"roof"]:
			var sp := spot(id)
			if sp.is_finite() and Vector2(sp.x - hero.x, sp.z - hero.z).length() < RING and absf(sp.y - hero.y) < 4.0:
				_t_in += delta
				if _t_in >= STAY:
					start(id)
					return
		_t_in = 0.0
		return
	elapsed += delta
	if elapsed > LIMIT:
		_end(false, "TOO SLOW")
		return
	match active:
		&"heist":
			_poll_heist(delta, hero)
		&"escort":
			_poll_escort(delta, hero)
		&"derail":
			_poll_derail(delta, hero)
		&"roof":
			_poll_roof(delta, hero)


func start(id: StringName) -> void:
	if active != &"":
		return
	active = id
	elapsed = 0.0
	_t_in = 0.0
	_hold = 0.0
	_spawned = false
	_loot = false
	_blown = false
	enemies.clear()
	_train = null
	var rw := RailWorld.instance
	match id:
		&"heist":
			_train = rw.train(&"mountain", &"ore")
			_set_step(&"board", "BOARD THE ORE TRAIN")
		&"escort":
			_train = rw.train(&"mountain", &"express")
			_set_step(&"board", "BOARD THE EXPRESS")
		&"derail":
			_train = rw.train(&"coast", &"container")
			_mark = spot(&"derail")
			if not _conn:
				_conn = true
				Game.exploded.connect(_on_blast)
			_set_step(&"blast", "BLOW THE TRACK AT THE MARKER WHEN THE TRAIN COMES")
		&"roof":
			_train = rw.train(&"coast", &"regional")
			_set_step(&"board", "BOARD THE REGIONAL TRAIN")
	Game.say("%s   %s" % [String(TITLES[id]), objective], 3.5)
	started.emit(id)


func abort() -> void:
	if active != &"":
		_end(false, "ABANDONED")


func _set_step(s: StringName, text: String) -> void:
	step = s
	objective = text
	step_changed.emit(active, s)


func _end(ok: bool, why := "") -> void:
	var id := active
	var reward := int(PAY[id]) if ok else 0
	if ok:
		done[id] = int(done.get(id, 0)) + 1
		var pr := Game.progress
		if pr != null and pr.has_method(&"add_credits"):
			pr.call(&"add_credits", reward)
		Game.say("%s COMPLETE   +%d" % [String(TITLES[id]), reward], 3.0)
	else:
		Game.say("%s FAILED   %s" % [String(TITLES[id]), why], 3.0)
	for e in enemies:
		if is_instance_valid(e) and not e.dead and Game.enemies != null:
			pass
	enemies.clear()
	active = &""
	step = &""
	objective = ""
	_cool = 6.0
	_mark = Vector3.ZERO
	finished.emit(id, ok, reward)


func _riding_train(hero: Vector3) -> Train:
	var rw := RailWorld.instance
	var cu := rw.car_under(hero)
	return cu["train"] if not cu.is_empty() else null


func _on_roof(hero: Vector3, tr: Train, car_type: StringName = &"") -> bool:
	var cu := RailWorld.instance.car_under(hero)
	if cu.is_empty() or cu["train"] != tr:
		return false
	var i: int = cu["i"]
	if car_type != &"" and tr.cars[i]["type"] != car_type:
		return false
	return float((cu["local"] as Vector3).y) > float((tr.cars[i]["spec"] as Dictionary)["roof_y"]) - 0.6


# --- heist ------------------------------------------------------------------------------------------------------------------------------

func _poll_heist(delta: float, hero: Vector3) -> void:
	if _train.derailed:
		_end(false, "TRAIN LOST")
		return
	match step:
		&"board":
			if _riding_train(hero) == _train:
				_set_step(&"roof", "CLIMB ONTO A BOX CAR ROOF  (USE AT A LADDER)")
		&"roof":
			if _on_roof(hero, _train, &"boxcar"):
				_hold += delta
				objective = "HOLD THE HATCH  %d" % int(ceil(maxf(4.0 - _hold, 0.0)))
				if _hold >= 4.0:
					_loot = true
					_set_step(&"escape", "GOT THE LOOT   JUMP OFF THE TRAIN")
					Game.say("LOOT SECURED", 2.0)
			else:
				_hold = 0.0
		&"escape":
			if RailWorld.instance.car_under(hero).is_empty():
				_end(true)


# --- escort -----------------------------------------------------------------------------------------------------------------------------

func _poll_escort(delta: float, hero: Vector3) -> void:
	match step:
		&"board":
			if _riding_train(hero) == _train and int(_train.state["stop"]) >= 0:
				_set_step(&"ride", "RIDE TO MOUNT STATION")
		&"ride":
			if _riding_train(hero) != _train and not _spawned and _train.speed() > 3.0:
				_end(false, "LEFT THE TRAIN")
				return
			if _train.speed() > 8.0 and not _spawned and int(_train.state["next"]) == 2 and float(_train.u()) > 0.0:
				_spawned = true
				_spawn_guards(_train, 1, 3)
				_set_step(&"guards", "GUARDS ON BOARD   CLEAR THEM")
		&"guards":
			if _alive() == 0:
				_set_step(&"arrive", "RIDE ON TO MOUNT STATION")
		&"arrive":
			if int(_train.state["stop"]) == 2 and _riding_train(hero) == _train:
				_end(true)
			elif _riding_train(hero) != _train and _train.speed() > 3.0:
				_end(false, "LEFT THE TRAIN")


# --- derail -----------------------------------------------------------------------------------------------------------------------------

func _poll_derail(delta: float, hero: Vector3) -> void:
	if _train.derailed:
		_end(true)
		return
	var d := _train.centre().distance_to(_mark)
	var eta := "" if _train.speed() < 1.0 else "   %d M OUT" % int(d)
	objective = "BLOW THE TRACK AT THE MARKER%s" % eta


func _on_blast(pos: Vector3, radius: float) -> void:
	if active != &"derail" or _train == null:
		return
	if Vector2(pos.x - _mark.x, pos.z - _mark.z).length() <= radius + 12.0 and _train.centre().distance_to(_mark) < 420.0 and _train.speed() > 3.0:
		_blown = true
		_train.derail()


# --- roof chase -------------------------------------------------------------------------------------------------------------------------

func _poll_roof(delta: float, hero: Vector3) -> void:
	match step:
		&"board":
			if _riding_train(hero) == _train:
				_set_step(&"depart", "THE TRAIN PULLS OUT SOON")
		&"depart":
			if _train.speed() > 6.0 and not _spawned:
				_spawned = true
				_spawn_guards(_train, 1, 4, true)
				_set_step(&"clear", "FOUR GUARDS ON THE ROOF   CLEAR THEM")
			elif _riding_train(hero) != _train and _train.speed() > 3.0:
				_end(false, "LEFT THE TRAIN")
		&"clear":
			if _alive() == 0:
				_end(true)


# --- guards -----------------------------------------------------------------------------------------------------------------------------

func _alive() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.active and not e.dead:
			n += 1
	return n


## Guards on a train: inside a car (not a roof) or on the roof.
func _spawn_guards(tr: Train, car: int, count: int, roof := false) -> void:
	var em := Game.enemies as EnemyManager
	if em == null:
		return
	for k in count:
		var ci := clampi(car + (k % 2), 0, tr.cars.size() - 1)
		var spec: Dictionary = tr.cars[ci]["spec"]
		var xf := (tr.cars[ci]["root"] as Node3D).global_transform
		var lz := -4.0 + float(k) * 2.6
		var lp := Vector3(0.0, float(spec["roof_y"]) + 0.4 if roof else TrainKit.FLOOR + 0.3, lz)
		var e := em.spawn(&"operative", xf * lp, true)
		if e != null:
			enemies.append(e)


func jobs_table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in [&"heist", &"escort", &"derail", &"roof"]:
		out.append({"id": id, "title": String(TITLES[id]), "pay": int(PAY[id]), "spot": spot(id)})
	return out
