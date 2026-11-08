class_name Tutorial
extends Node
## First-launch training (child of Story: Game.story.tutorial): five short steps, move, look, shoot, blink, enter a car, each with a prompt that adapts to touch or keyboard
## (StoryData.TUTORIAL: `kb` / `touch` texts, a radio line when the step is done). The HUD draws the prompt on a plate low in the middle of the screen (clear of the touch
## buttons) with a SKIP plate; Tab or a tap on the plate skips it. It starts after the prologue cards of a NEW run when the save says the tutorial was never finished
## (never under Game.autostart unless `force` is set), and finishing or skipping stores `tutorial_done` through Game.progress. Steps are detected by polling the player (no
## hooks into other modules): the position, the camera heading, the weapon's shots_fired (or the fire action held), the quantum bits and the vehicle.

signal step_changed(index: int)
signal finished(skipped: bool)

const MOVE_NEED := 5.0               ## metres walked
const LOOK_NEED := 0.9               ## radians of camera turn
const SHOT_NEED := 3
const FIRE_HOLD_NEED := 0.4          ## seconds of the fire action held (when there is no weapon to count shots)
const JUMP_LIMIT := 4.0              ## a step this long between two ticks is a teleport, not walking

var active := false
var skipped := false
var step := 0
var force := false                   ## start even under Game.autostart (tests)
var touch_override := -1             ## -1 auto, 0 keyboard, 1 touch (tests)
var skip_rect := Rect2()             ## screen rect of the SKIP plate, set by the HUD each frame it draws one
var flash := 0.0                     ## seconds left of the "TRAINING COMPLETE" flash after the last step

var _moved := 0.0
var _last_pos := Vector3.ZERO
var _yaw := 0.0
var _last_yaw := 0.0
var _shots0 := 0
var _fire_t := 0.0
var _beacon := false
var _has_base := false


func _ready() -> void:
	Game.new_game.connect(stop)


# --- public API --------------------------------------------------------------------------------------------------------

func use_touch() -> bool:
	if touch_override >= 0:
		return touch_override == 1
	return Game.force_touch or DisplayServer.is_touchscreen_available()


func steps() -> Array[Dictionary]:
	return StoryData.TUTORIAL


func step_count() -> int:
	return StoryData.TUTORIAL.size()


func step_id() -> String:
	return str(StoryData.TUTORIAL[step]["id"]) if active and step < step_count() else ""


## The prompt of the current step for the current input method ("" when inactive). The blink step changes after the beacon is out; the car step shows the distance.
func prompt() -> String:
	if not active or step >= step_count():
		return ""
	var d: Dictionary = StoryData.TUTORIAL[step]
	var key := "touch" if use_touch() else "kb"
	if str(d["id"]) == "blink" and _beacon:
		key += "2"
	var text := str(d[key])
	if str(d["id"]) == "car":
		var m := _car_distance()
		if m >= 0.0:
			text += "   %d M" % roundi(m)
	return text


func counter_text() -> String:
	return "TRAINING  %d / %d" % [mini(step + 1, step_count()), step_count()] if active else ""


func skip_hint() -> String:
	return StoryData.TUTORIAL_SKIP_TOUCH if use_touch() else StoryData.TUTORIAL_SKIP_KB


## Start (or restart) the training at step 0.
func begin() -> void:
	active = true
	skipped = false
	step = 0
	flash = 0.0
	_reset_trackers()
	step_changed.emit(0)


## Starts it after the prologue of a new run when this is a first launch: no `tutorial_done` in the save, not a tool / test run.
func maybe_start() -> bool:
	if Game.autostart and not force:
		return false
	var prog := Game.progress as Progress
	if prog != null and prog.tutorial_done:
		return false
	begin()
	return true


func skip() -> void:
	if active:
		_finish(true)


## Ends it without storing anything (a new run starts: the HUD must not keep a stale prompt).
func stop() -> void:
	active = false
	flash = 0.0


# --- simulation ----------------------------------------------------------------------------------------------------------

func _reset_trackers() -> void:
	_moved = 0.0
	_fire_t = 0.0
	_beacon = false
	_has_base = false
	var p := Game.player
	if is_instance_valid(p):
		_last_pos = p.global_position
		_last_yaw = _camera_yaw()
		var w: Variant = p.get("weapon")
		_shots0 = int((w as Object).get("shots_fired")) if w != null else 0
		_has_base = true


func _camera_yaw() -> float:
	if is_instance_valid(Game.camera):
		var f := -Game.camera.global_transform.basis.z
		return atan2(-f.x, -f.z)
	var p := Game.player
	return p.rotation.y if is_instance_valid(p) else 0.0


func _car_distance() -> float:
	var v := Game.vehicles
	var p := Game.player
	if not is_instance_valid(v) or not is_instance_valid(p) or not v.has_method(&"nearest"):
		return -1.0
	var best := -1.0
	var starter: Variant = v.get("starter")
	if starter is Node3D and is_instance_valid(starter):
		best = (starter as Node3D).global_position.distance_to(p.global_position)
	return best


func _process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)


func _physics_process(delta: float) -> void:
	if not active or not Game.is_playing():
		return
	tick(delta)


## Polls the player for the current step (the physics process calls it while playing; tests call it directly).
func tick(delta: float) -> void:
	var p := Game.player
	if not active or not is_instance_valid(p):
		return
	if not _has_base:
		_reset_trackers()
		return
	var done := false
	match step_id():
		"move":
			var d := Vector2(p.global_position.x - _last_pos.x, p.global_position.z - _last_pos.z).length()
			if d < JUMP_LIMIT:
				_moved += d
			_last_pos = p.global_position
			done = _moved >= MOVE_NEED
		"look":
			var y := _camera_yaw()
			_yaw += absf(wrapf(y - _last_yaw, -PI, PI))
			_last_yaw = y
			done = _yaw >= LOOK_NEED
		"shoot":
			var w: Variant = p.get("weapon")
			if w != null:
				done = int((w as Object).get("shots_fired")) - _shots0 >= SHOT_NEED
			if Input.is_action_pressed(&"fire"):
				_fire_t += delta
				done = done or (w == null and _fire_t >= FIRE_HOLD_NEED)
		"blink":
			var q: Variant = p.get("quantum")
			if q != null:
				var qo := q as Object
				_beacon = _beacon or qo.get("has_beacon") == true
				var bl: Variant = qo.get("bits_left")
				done = (bl is float or bl is int) and float(bl) > 0.0
		"car":
			done = p.get("vehicle") != null
	if done:
		_next()


func _next() -> void:
	var d: Dictionary = StoryData.TUTORIAL[step]
	if is_instance_valid(Game.story) and Game.story.has_method(&"say"):
		var l: Dictionary = d["done"]
		Game.story.call(&"say", str(l["s"]), str(l["t"]), "tutorial." + str(d["id"]), 0.0, 1)
	step += 1
	_yaw = 0.0
	if step >= step_count():
		_finish(false)
		return
	_reset_trackers()
	step_changed.emit(step)
	Sfx.play(&"pickup")


func _finish(was_skipped: bool) -> void:
	active = false
	skipped = was_skipped
	flash = 2.5 if not was_skipped else 0.0
	var prog := Game.progress as Progress
	if prog != null:
		prog.mark_tutorial_done()
	if not was_skipped:
		Game.say(StoryData.TUTORIAL_DONE, 2.5)
	finished.emit(was_skipped)


func _input(event: InputEvent) -> void:
	if not active or not Game.is_playing() or MapScreen.up:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_TAB:
			skip()
			get_viewport().set_input_as_handled()
	elif skip_rect.size.x > 0.0:
		var pos := Vector2(-1.0, -1.0)
		var hit := false
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			pos = (event as InputEventScreenTouch).position
			hit = true
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pos = (event as InputEventMouseButton).position
			hit = true
		if hit and skip_rect.grow(6.0).has_point(pos):
			skip()
			get_viewport().set_input_as_handled()
