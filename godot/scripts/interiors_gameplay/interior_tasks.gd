class_name InteriorTasks
extends Node
## Everything a phone player needs to FINISH a task inside a building (owner round 4: "I go inside and cannot finish the task because the option itself is not there").
## One place that knows every job type a room can hold and what the player does for it, and says so on screen:
##   interior jobs (InteriorMissions)  safe CRACK, hostage FREE, officer FIND / kill, terminal HACK         the room's own job
##   stealth jobs (StealthRunner)      PLANT THE DEVICE, COPY THE DATA, reach the terminal, takedowns     teleporter hall, warehouse, server room, cargo bay
##   heist stage (CampaignRunner)      TAKE THE DATA at the loot point when the room has no job of its own
##   quantum gates (QuantumPuzzles)    OPEN THE GATE (USE opens the outermost closed gate; the verbs still do it the old way)
##   vendors (VendorScreen)            TALK
##   the way out                       LEAVE at the door, and the LEAVE button / key that works from anywhere in the room
## For each: a contextual USE prompt (`best`), a floating label over the object (`items`, drawn by InteriorPrompts), a task status line (`status_line`) and the objective on the compass strip.
## Pure rules plus a refresh timer: the HUD, the touch layer and the bots only read `items`, `best()`, `status_line()` and call `activate()`.

const GATE_REACH := 4.2
const LOOT_REACH := 2.6
const LEAVE_CONFIRM := 3.0                 ## seconds the second LEAVE tap may follow the first (a job in progress asks once)
const REFRESH := 0.1
const SHOW_RANGE := 15.0                   ## metres: labels over objects farther away than this are not drawn (the objective always is, as an edge arrow)

const COL_JOB := Color(0.45, 0.95, 1.0)
const COL_VENDOR := Color(1.0, 0.72, 0.25)
const COL_EXIT := Color(0.4, 1.0, 0.6)
const COL_GATE := Color(1.0, 0.25, 0.75)

var gameplay: InteriorGameplay
var items: Array[Dictionary] = []          ## [{id, pos, label, height, objective, color, kind}]: floating labels, refreshed every REFRESH s
var leave_armed := 0.0                     ## seconds left on a pending "tap LEAVE again" (0 = not asked)
var job_done := false                      ## this visit's job was finished (the status line says LEAVE)
var loot_pos := Vector3.INF                ## where the heist data is (set when the heist step needs it)
var prompts: InteriorPrompts

var _t := 0.0
var _status := ""
var _hooked_missions: Object
var _hooked_stealth: Object


func _ready() -> void:
	name = "InteriorTasks"


func setup(g: InteriorGameplay) -> void:
	gameplay = g
	var layer := CanvasLayer.new()
	layer.layer = 8                                          # under the HUD (10): the plates float in the room, the HUD's plates stay on top
	layer.name = "PromptLayer"
	add_child(layer)
	prompts = InteriorPrompts.new()
	prompts.tasks = self
	layer.add_child(prompts)


## A new visit: forget the last one's state.
func begin_visit() -> void:
	items.clear()
	leave_armed = 0.0
	job_done = false
	loot_pos = Vector3.INF
	_status = ""
	_t = REFRESH
	_hook()


func end_visit() -> void:
	items.clear()
	leave_armed = 0.0
	job_done = false
	loot_pos = Vector3.INF
	_status = ""


func _hook() -> void:
	if gameplay != null and gameplay.missions != null and gameplay.missions != _hooked_missions:
		_hooked_missions = gameplay.missions
		gameplay.missions.completed.connect(func(_k: StringName, _id: int, _r: Dictionary) -> void: job_done = true)
	var st := _stealth()
	if st != null and st != _hooked_stealth:
		_hooked_stealth = st
		st.finished.connect(func(_id: StringName, ok: bool, _why: String) -> void:
			if ok:
				job_done = true)


func _stealth() -> StealthRunner:
	var m := Game.missions as Missions
	return m.stealth if m != null else null


func _campaign() -> CampaignRunner:
	var m := Game.missions as Missions
	return m.campaign if m != null else null


# --- the tick ---------------------------------------------------------------------------------------------------------------

func tick(delta: float, pp: Vector3) -> void:
	leave_armed = maxf(leave_armed - delta, 0.0)
	_t += delta
	if _t >= REFRESH:
		_t = 0.0
		_refresh(pp)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _refresh(pp: Vector3) -> void:
	items.clear()
	if gameplay == null or not InteriorGameplay.active or gameplay.interior == null:
		return
	var m := gameplay.missions
	for it: Dictionary in m.interactables():
		_add(it, COL_JOB, &"job")
	var st := _stealth()
	if st != null:
		for it: Dictionary in st.interactables():
			_add(it, COL_JOB, &"stealth")
	var camp := _campaign()
	if camp != null and camp.heist_take_open() and not m.is_active():
		if not loot_pos.is_finite():
			loot_pos = _loot_point()
		_add({"id": &"loot", "pos": loot_pos, "label": "TAKE THE DATA", "height": 1.5, "objective": true}, COL_JOB, &"heist")
	var pz := m.puzzles
	if is_instance_valid(pz):
		var g := pz.next_gate()
		if not g.is_empty():
			_add({"id": &"gate", "pos": pz.at(float(g["depth"])), "label": "GATE  " + QuantumPuzzles.gate_hint(g["kind"]), "height": 2.4, "objective": false}, COL_GATE, &"gate")
	var v := gameplay.actors.vendor
	if v != null and v.active:
		_add({"id": &"vendor", "pos": v.global_position, "label": "TALK  " + InteriorData.title(gameplay.actors.type), "height": 2.3, "objective": false}, COL_VENDOR, &"vendor")
	_add({"id": &"exit", "pos": InteriorGameplay.exit_point(gameplay.interior), "label": "EXIT", "height": 2.3, "objective": job_done}, COL_EXIT, &"exit")
	_status = _make_status(pp)


func _add(it: Dictionary, col: Color, kind: StringName) -> void:
	var d := it.duplicate()
	d["color"] = col
	d["kind"] = kind
	items.append(d)


## The loot point of a heist in a room without a job: the terminal in the technical rooms, the safe in the office.
func _loot_point() -> Vector3:
	var room := gameplay.interior
	var kind: StringName = &"safe" if gameplay.actors.type in [&"lobby", &"warehouse", &"apartment", &"club", &"bar"] else &"terminal"
	var list := InteriorGameplay.anchor_points(room, kind, 1, int(room.get("seed")))
	var p: Vector3 = list[0]["pos"]
	return Vector3(p.x, InteriorGameplay.ORIGIN.y, p.z)


# --- USE ---------------------------------------------------------------------------------------------------------------------

## What USE does at `pp` right now: {action, prompt} or {} (nothing in reach). Order: the gate in the way, the job, the vendor, the door.
func best(pp: Vector3) -> Dictionary:
	if gameplay == null or not InteriorGameplay.active or gameplay.interior == null:
		return {}
	var m := gameplay.missions
	if is_instance_valid(m.puzzles):
		var g := m.puzzles.next_gate()
		if not g.is_empty() and _flat(pp, m.puzzles.at(float(g["depth"]))) < GATE_REACH:
			return {"action": &"gate", "prompt": "OPEN THE GATE"}
	var mp := m.prompt_for(pp)
	if mp != "":
		return {"action": &"mission", "prompt": mp}
	var st := _stealth()
	if st != null:
		var sp := st.prompt_for(pp)
		if sp != "":
			return {"action": &"stealth", "prompt": sp}
	var camp := _campaign()
	if camp != null and camp.heist_take_open() and not m.is_active():
		if not loot_pos.is_finite():
			loot_pos = _loot_point()
		if _flat(pp, loot_pos) < LOOT_REACH:
			return {"action": &"heist", "prompt": "TAKE THE DATA"}
	# the vendor and the door can be within reach of each other (a small bar): the one the hero is relatively closer to wins, the door on a tie, so the way out is never hidden behind a TALK prompt
	var v := gameplay.actors.vendor
	var near_v := INF
	if v != null and v.active:
		near_v = _flat(pp, v.global_position) / InteriorGameplay.REACH_VENDOR
	var near_e := _flat(pp, InteriorGameplay.exit_point(gameplay.interior)) / InteriorGameplay.REACH_EXIT
	if near_e < 1.0 and near_e <= near_v:
		return {"action": &"exit", "prompt": "LEAVE  %s" % str(gameplay.door.get("name", ""))}
	if near_v < 1.0:
		return {"action": &"vendor", "prompt": "TALK  %s" % InteriorData.title(gameplay.actors.type)}
	return {}


## Do what `best` named. Returns true when something happened.
func activate(act: StringName, pp: Vector3) -> bool:
	match act:
		&"gate":
			var pz := gameplay.missions.puzzles
			if is_instance_valid(pz) and pz.assist():
				Sfx.play(&"ui_tap")
				Game.say("GATE OPEN", 1.4)
				return true
		&"mission":
			return gameplay.missions.interact(pp)
		&"stealth":
			var st := _stealth()
			return st != null and st.interact(pp)
		&"heist":
			var camp := _campaign()
			if camp != null and camp.take_data():
				Sfx.play(&"ui_contract_complete")
				Game.say("DATA TAKEN  GET OUT", 2.5)
				return true
		&"vendor":
			gameplay.vendor_screen.open(gameplay.actors.type)
			return true
		&"exit":
			return gameplay.leave()
	return false


# --- the way out ---------------------------------------------------------------------------------------------------------------

## True while a job is under way that leaving would throw away (progress made, the hostage fight started, a stealth run, the heist data in hand).
func job_in_progress() -> bool:
	if gameplay == null:
		return false
	var m := gameplay.missions
	if m.is_active() and (m.progress > 0.01 or m.hacking):
		return true
	var st := _stealth()
	if st != null and st.is_running() and (st.progress > 0.01 or st.working):
		return true
	var camp := _campaign()
	return camp != null and camp.state == &"active" and camp.kind == &"heist" and camp.loot


## The LEAVE button / key: out from anywhere in the room. A job in progress asks once ("TAP LEAVE AGAIN") before it is thrown away; at the door, or with nothing to lose, it just goes.
## Returns true when the fade out started.
func request_leave(pp: Vector3) -> bool:
	if gameplay == null or not InteriorGameplay.active or gameplay.busy:
		return false
	var near_exit := _flat(pp, InteriorGameplay.exit_point(gameplay.interior)) < InteriorGameplay.REACH_EXIT
	if near_exit or not job_in_progress() or leave_armed > 0.0:
		leave_armed = 0.0
		return gameplay.leave()
	leave_armed = LEAVE_CONFIRM
	Game.say("TAP LEAVE AGAIN TO GIVE UP THE JOB", 2.4)
	return false


# --- the task status line -------------------------------------------------------------------------------------------------------

func status_line() -> String:
	return _status


func _make_status(pp: Vector3) -> String:
	if leave_armed > 0.0:
		return "TAP LEAVE AGAIN TO GIVE UP THE JOB"
	var m := gameplay.missions
	var st := _stealth()
	var camp := _campaign()
	if m.is_active():
		return ""                                             # the job's own line (InteriorGameplay.hud_line) is on the plate
	if st != null and st.is_running():
		return ""                                             # the stealth line is on the plate
	if camp != null and camp.heist_take_open():
		var d := roundi(_flat(pp, loot_pos)) if loot_pos.is_finite() else 0
		return "HEIST  TAKE THE DATA  %d M" % d if d > 3 else "HEIST  USE TO TAKE THE DATA"
	if job_done or gameplay.done.has(int(gameplay.door.get("id", -1))):
		return "JOB DONE  LEAVE ANY TIME"
	if gameplay.actors.vendor != null and gameplay.actors.vendor.active:
		return "SHOP  TALK TO THE VENDOR OR LEAVE"
	return "NOTHING TO DO HERE  LEAVE ANY TIME"


## The objective to point at: the first item marked `objective` ({} when none).
func objective() -> Dictionary:
	for it: Dictionary in items:
		if bool(it.get("objective", false)):
			return it
	return {}
