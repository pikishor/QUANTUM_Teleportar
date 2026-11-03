class_name FirstUse
extends Node
## Icon-based first-use prompts (child of Story: Game.story.first_use). Ten short imperative labels, one per mechanic (move, aim, QUANTUM TELEPORT, ENTANGLE, SUPERPOSITION,
## COLLAPSE, cover, vehicle, map, side missions), each shown once in the order of HINTS after its `ready` condition holds, then marked seen in Game.progress (cine_seen, id
## "hint_<id>"). A hint ends when its action is detected or after SHOW_TIME. Never while the tutorial is active. OPTIONS > HINTS (replay()) clears the seen marks.
## The HUD draws current() as a small plate with an icon glyph. Labels go through Tr.

signal shown(id: StringName)

const SHOW_TIME := 6.0
const GAP := 4.0                     ## seconds of quiet between two hints
const HINTS: Array[Dictionary] = [
	{"id": &"move", "kb": "MOVE WITH W A S D", "touch": "DRAG TO MOVE", "icon": &"disc", "col": Color(0.4, 0.9, 1.0)},
	{"id": &"aim", "kb": "HOLD RIGHT MOUSE TO AIM", "touch": "HOLD TO AIM", "icon": &"ring", "col": Color(1.0, 0.8, 0.3)},
	{"id": &"teleport", "kb": "HOLD Q TO QUANTUM TELEPORT", "touch": "HOLD TO QUANTUM TELEPORT", "icon": &"diamond", "col": Color(0.5, 0.8, 1.0)},
	{"id": &"entangle", "kb": "PRESS E TO ENTANGLE", "touch": "TAP TO ENTANGLE", "icon": &"star", "col": Color(1.0, 0.5, 0.9)},
	{"id": &"superposition", "kb": "PRESS R FOR SUPERPOSITION", "touch": "TAP FOR SUPERPOSITION", "icon": &"diamond", "col": Color(0.7, 1.0, 0.7)},
	{"id": &"collapse", "kb": "PRESS C TO COLLAPSE", "touch": "TAP TO COLLAPSE", "icon": &"star", "col": Color(1.0, 0.6, 0.3)},
	{"id": &"cover", "kb": "CROUCH BEHIND COVER", "touch": "TAP TO TAKE COVER", "icon": &"ring", "col": Color(0.8, 0.8, 0.9)},
	{"id": &"vehicle", "kb": "PRESS F TO ENTER", "touch": "TAP USE TO ENTER", "icon": &"disc", "col": Color(1.0, 0.8, 0.3)},
	{"id": &"map", "kb": "PRESS M FOR MAP", "touch": "OPEN THE MAP", "icon": &"diamond", "col": Color(0.4, 0.9, 1.0)},
	{"id": &"side", "kb": "TAKE SIDE MISSIONS", "touch": "TAKE SIDE MISSIONS", "icon": &"star", "col": Color(1.0, 0.8, 0.3)},
]

var force := false                   ## run under Game.autostart (tests)
var touch_override := -1             ## -1 auto, 0 keyboard, 1 touch (tests)
var enabled := true
var cur := -1                        ## index into HINTS of the hint on screen, -1 none
var age := 0.0                       ## seconds the current hint has been up
var _quiet := 2.0
var _play := 0.0


func _ready() -> void:
	Game.new_game.connect(_reset)


static func seen_id(id: StringName) -> StringName:
	return StringName("hint_" + str(id))


func is_seen(id: StringName) -> bool:
	var prog := Game.progress as Progress
	return prog != null and prog.cine_seen.has(seen_id(id))


func use_touch() -> bool:
	if touch_override >= 0:
		return touch_override == 1
	return Game.force_touch or DisplayServer.is_touchscreen_available()


func current() -> Dictionary:
	return HINTS[cur] if cur >= 0 else {}


## The label of the hint on screen for the current input method ("" none).
func label() -> String:
	if cur < 0:
		return ""
	return Tr.t(str(HINTS[cur]["touch" if use_touch() else "kb"]))


## Clears every seen mark so all prompts show again (OPTIONS).
func replay() -> void:
	var prog := Game.progress as Progress
	if prog != null:
		for h in HINTS:
			prog.cine_seen.erase(seen_id(h["id"]))
		prog.call(&"_autosave")
	cur = -1
	_quiet = 2.0


func _reset() -> void:
	cur = -1
	_quiet = 2.0
	_play = 0.0


func _physics_process(delta: float) -> void:
	if Game.is_playing():
		tick(delta)


func _active_tutorial() -> bool:
	var st := Game.story
	var t: Variant = st.get(&"tutorial") if is_instance_valid(st) else null
	return t != null and (t as Object).get(&"active") == true


## Polls the player (physics process while playing; tests call it directly).
func tick(delta: float) -> void:
	var p := Game.player
	var prog := Game.progress as Progress
	if not enabled or prog == null or not is_instance_valid(p) or (Game.autostart and not force) or _active_tutorial():
		return
	_play += delta
	if cur >= 0:
		age += delta
		if _done(HINTS[cur]["id"], p) or age >= SHOW_TIME:
			prog.mark_cine(seen_id(HINTS[cur]["id"]))
			cur = -1
			_quiet = GAP
		return
	_quiet -= delta
	if _quiet > 0.0:
		return
	for i in HINTS.size():
		var id: StringName = HINTS[i]["id"]
		if not is_seen(id):
			if _is_ready(id, p):
				cur = i
				age = 0.0
				shown.emit(id)
			return                     # strict order: the first unseen hint waits for its own condition


func _q(p: Node) -> Object:
	var q: Variant = p.get("quantum")
	return q as Object if q != null else null


func _is_ready(id: StringName, p: Node) -> bool:
	match id:
		&"move", &"aim":
			return true
		&"teleport", &"entangle", &"superposition":
			return _q(p) != null
		&"collapse":
			return _q(p) != null and _play > 40.0
		&"cover":
			return not get_tree().get_nodes_in_group(&"enemy").is_empty()
		&"vehicle":
			return p.get("vehicle") == null and _starter_dist(p) < 25
		&"map":
			return _play > 60.0
		&"side":
			return _play > 90.0
	return false


func _starter_dist(p: Node) -> int:
	var v := Game.vehicles
	if not is_instance_valid(v):
		return 999
	var s: Variant = v.get("starter")
	if s is Node3D and is_instance_valid(s):
		return int((s as Node3D).global_position.distance_to((p as Node3D).global_position))
	return 999


func _done(id: StringName, p: Node) -> bool:
	var q := _q(p)
	match id:
		&"move":
			return (p as Node3D).global_position.distance_to(_pos0(p)) > 3.0
		&"aim":
			return p.get("aiming") == true
		&"teleport":
			return q != null and (q.get("aiming") == true or q.get("last_fix") != "")
		&"entangle":
			return q != null and not (q.get("links") as Array).is_empty()
		&"superposition":
			return q != null and q.get("clone") != null
		&"collapse":
			return q != null and float(q.get("collapse_fx")) > 0.0
		&"cover":
			var c: Variant = p.get("cover")
			return c != null and ((c as Object).get("in_cover") == true or (c as Object).get("crouching") == true)
		&"vehicle":
			return p.get("vehicle") != null
	return false


var _p0 := Vector3.ZERO
var _p0_set := false


func _pos0(p: Node) -> Vector3:
	if not _p0_set or age < 0.02:
		_p0 = (p as Node3D).global_position
		_p0_set = true
	return _p0
