extends RefCounted
## Real fingers for the wave 116 flight tests and probes: InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, window coordinates
## (root.get_final_transform() * canvas position), the way a phone delivers them. Nothing here calls a game function to act: the game only ever sees the events.
## `button(action)` only READS where the touch HUD has drawn a button (TouchControls.BUTTONS and its layout), and says INF when that button is not on screen.

var root: Window
var tc: TouchControls
var held := {}                       ## finger index -> canvas position


func _init(host: Node) -> void:
	root = host.get_tree().root
	var tcs := root.find_children("*", "TouchControls", true, false)
	tc = tcs[0] as TouchControls if not tcs.is_empty() else null


func down(finger: int, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.position = root.get_final_transform() * pos
	e.pressed = true
	held[finger] = pos
	Input.parse_input_event(e)


func up(finger: int) -> void:
	if not held.has(finger):
		return
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.position = root.get_final_transform() * (held[finger] as Vector2)
	e.pressed = false
	held.erase(finger)
	Input.parse_input_event(e)


func move(finger: int, to: Vector2) -> void:
	if not held.has(finger):
		return
	var from: Vector2 = held[finger]
	var e := InputEventScreenDrag.new()
	e.index = finger
	e.position = root.get_final_transform() * to
	e.relative = root.get_final_transform().basis_xform(to - from)
	held[finger] = to
	Input.parse_input_event(e)


func up_all() -> void:
	for f in held.keys():
		up(f)


func vp() -> Vector2:
	return root.get_visible_rect().size


## Centre of the touch button of `action` as drawn now (canvas px), Vector2.INF when it is not on screen.
func button(action: StringName) -> Vector2:
	if tc == null or not tc.controls_on:
		return Vector2.INF
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b):
			return tc._button_center(b)
	return Vector2.INF


func button_label(action: StringName) -> String:
	if tc == null:
		return ""
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b):
			return tc._label_of(b)
	return ""


## Put `finger` on the button of `action`. False (and nothing sent) when the button is not on screen.
func press(finger: int, action: StringName) -> bool:
	var at := button(action)
	if at == Vector2.INF:
		return false
	down(finger, at)
	return true


## The left thumb: `v` in -1..1 (y -1 = forward). Vector2.ZERO lifts the thumb. Finger 0.
func stick(v: Vector2) -> void:
	if v == Vector2.ZERO:
		up(0)
		return
	var o := Vector2(vp().x * 0.14, vp().y * 0.72)
	if not held.has(0):
		down(0, o)
	move(0, o + v * TouchControls.STICK_RADIUS * tc._scale())


## The right thumb swipes the view by (dx, dy) canvas px in `steps` drag events. Finger 3.
func look(dx: float, dy: float, steps := 6) -> void:
	var o := Vector2(vp().x * 0.5, vp().y * 0.3)
	down(3, o)
	for i in steps:
		move(3, o + Vector2(dx, dy) * (float(i + 1) / float(steps)))
	up(3)
