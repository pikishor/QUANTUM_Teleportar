class_name VendorScreen
extends CanvasLayer
## The vendor's trade window (weapon dealer, clinic, tech den, bar). While it is open the game state is `paused` (nothing simulates, the pause screen is not drawn:
## InteriorGameplay.vendor_open). Like the TEST menu, nothing here is a Control button (emulate_mouse_from_touch is off in this project): the node draws one canvas and hit-tests
## its own rectangles from screen touches and the mouse. Rows come from VendorLogic.rows(type); a tap on BUY calls VendorLogic.buy(). USE, ESC, B or the CLOSE button leave.
## Keys 1-7 buy the n-th row (desktop). Public for tests: open(type), close(), tap(pos), press_row(i), rows, status.

signal opened(type: StringName)
signal closed
signal purchased(id: StringName, result: Dictionary)

const Dlg := preload("res://scripts/npc/npc_dialogue.gd")
const BASE_H := 720.0
const ROW_H := 54.0
const ROW_W := 760.0
const TOP := 138.0
const BG := Color(0.01, 0.03, 0.05, 0.9)
const PANEL := Color(0.03, 0.09, 0.12, 0.92)

var is_open := false
var type: StringName = &"bar"
var rows: Array[Dictionary] = []
var status := ""
var rumour_text := ""
var greeting := ""                           ## the vendor's line for this visit (NpcDialogue.vendor_line)
var _rng := RandomNumberGenerator.new()
var rects: Array[Rect2] = []                 ## BUY button rect per row (screen px), valid after layout()
var close_rect := Rect2()
var _canvas: Control
var _resume := false
var _down := -1
var _down_pos := Vector2.ZERO


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_all)
	if Game.progress != null:
		(Game.progress as Progress).changed.connect(_refresh)


func _vp() -> Vector2:
	return _canvas.get_viewport_rect().size if _canvas != null and _canvas.is_inside_tree() else Vector2(1280, 720)


func _s() -> float:
	return _vp().y / BASE_H


func open(t: StringName) -> bool:
	if is_open or not InteriorData.has_vendor(t) or Game.state != &"play":
		return false
	type = t
	status = ""
	rumour_text = ""
	_rng.randomize()
	greeting = Dlg.vendor_line(t, Dlg.context(_player_pos()), _rng)
	is_open = true
	visible = true
	InteriorGameplay.vendor_open = true
	_resume = true
	Game.state = &"paused"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	Sfx.play(&"ui_confirm")
	opened.emit(t)
	return true


func _player_pos() -> Vector3:
	return (Game.player as Node3D).global_position if is_instance_valid(Game.player) else Vector3.ZERO


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	InteriorGameplay.vendor_open = false
	_down = -1
	if _resume and Game.state == &"paused":
		Game.state = &"play"
	_resume = false
	Sfx.play(&"ui_back")
	closed.emit()


func _refresh() -> void:
	if not is_open:
		return
	rows = VendorLogic.rows(type)
	layout()
	_canvas.queue_redraw()


func layout() -> void:
	var vp := _vp()
	var s := _s()
	rects.clear()
	var x0 := vp.x * 0.5 - ROW_W * 0.5 * s
	for i in rows.size():
		var y := (TOP + float(i) * ROW_H) * s
		rects.append(Rect2(x0 + (ROW_W - 190.0) * s, y + 5.0 * s, 180.0 * s, (ROW_H - 16.0) * s))
	close_rect = Rect2(vp.x * 0.5 - 120.0 * s, (TOP + float(rows.size()) * ROW_H + 44.0) * s, 240.0 * s, 50.0 * s)


## Buy the n-th row. Returns the VendorLogic result.
func press_row(i: int) -> Dictionary:
	if not is_open or i < 0 or i >= rows.size():
		return {"ok": false, "msg": ""}
	var res := VendorLogic.buy(type, rows[i]["id"])
	status = str(res["msg"])
	if res.has("rumour"):
		rumour_text = str(res["rumour"])
	if bool(res["ok"]) and InteriorGameplay.instance != null:
		InteriorGameplay.instance.save_state()
	purchased.emit(rows[i]["id"], res)
	_refresh()
	return res


func tap(pos: Vector2) -> bool:
	layout()
	if close_rect.has_point(pos):
		close()
		return true
	for i in rects.size():
		if rects[i].grow(6.0 * _s()).has_point(pos):
			press_row(i)
			return true
	return false


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE or k == KEY_F or k == KEY_B:
			close()
			get_viewport().set_input_as_handled()
			return
		if k >= KEY_1 and k <= KEY_9:
			press_row(int(k - KEY_1))
			get_viewport().set_input_as_handled()
			return
	var kind := 0
	var pos := Vector2.ZERO
	var id := 0
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		kind = 1 if t.pressed else 3
		pos = t.position
		id = t.index + 1
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		kind = 1 if mb.pressed else 3
		pos = mb.position
		id = 100
	if kind == 0:
		return
	if kind == 1 and _down == -1:
		_down = id
		_down_pos = pos
	elif kind == 3 and id == _down:
		_down = -1
		if pos.distance_to(_down_pos) < 24.0 * _s():
			tap(pos)
	get_viewport().set_input_as_handled()


func _draw_all() -> void:
	if not is_open:
		return
	var vp := _vp()
	var s := _s()
	var font := UiUtil.font()
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var col := InteriorData.color(type)
	var x0 := vp.x * 0.5 - ROW_W * 0.5 * s
	c.draw_string(font, Vector2(0.0, 74.0 * s), Tr.t(InteriorData.title(type)), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(50.0 * s), Color(1, 1, 1, 0.97))
	var prog := Game.progress as Progress
	if prog != null:
		var line := "%s  %d      %s  %s" % [Tr.t("CREDITS"), prog.credits, Tr.t("REPUTATION"), Tr.t(Progress.rep_name(prog.reputation))]
		c.draw_string(font, Vector2(0.0, 112.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97))
	c.draw_rect(Rect2(x0, 124.0 * s, ROW_W * s, 2.0 * s), Color(col, 0.8))
	layout()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := (TOP + float(i) * ROW_H) * s
		c.draw_rect(Rect2(x0, y, ROW_W * s, (ROW_H - 5.0) * s), PANEL)
		c.draw_string(font, Vector2(x0 + 14.0 * s, y + 22.0 * s), "%d  %s" % [i + 1, Tr.t(str(r["name"]))], HORIZONTAL_ALIGNMENT_LEFT, (ROW_W - 220.0) * s, int(24.0 * s), Color(1, 1, 1, 0.97))
		c.draw_string(font, Vector2(x0 + 14.0 * s, y + 42.0 * s), Tr.t(str(r["sub"])), HORIZONTAL_ALIGNMENT_LEFT, (ROW_W - 220.0) * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.9))
		var br := rects[i]
		var st := str(r["state"])
		var fill := Color(0.1, 0.45, 0.38, 0.95) if st == "buy" else Color(0.18, 0.2, 0.22, 0.9)
		c.draw_rect(br, fill)
		c.draw_rect(br, Color(col, 0.9) if st == "buy" else Color(1, 1, 1, 0.25), false, 2.0 * s)
		c.draw_string(font, Vector2(br.position.x, br.position.y + br.size.y * 0.5 + 8.0 * s), Tr.t(str(r["label"])), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, int(22.0 * s), Color(1, 1, 1, 0.97 if st == "buy" else 0.55))
	if rumour_text == "" and greeting != "":
		var gy := (TOP + float(rows.size()) * ROW_H + 6.0) * s
		c.draw_string(font, Vector2(x0, gy + 20.0 * s), Tr.t(greeting), HORIZONTAL_ALIGNMENT_LEFT, ROW_W * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.9))
	if rumour_text != "":
		var ry := (TOP + float(rows.size()) * ROW_H + 6.0) * s
		c.draw_string(font, Vector2(x0, ry + 20.0 * s), Tr.t(rumour_text), HORIZONTAL_ALIGNMENT_LEFT, ROW_W * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95))
	if status != "":
		c.draw_string(font, Vector2(0.0, close_rect.position.y - 8.0 * s), Tr.t(status), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.GREEN, 0.95))
	c.draw_rect(close_rect, Color(0.3, 0.1, 0.1, 0.9))
	c.draw_rect(close_rect, Color(UiUtil.RED, 0.8), false, 2.0 * s)
	c.draw_string(font, Vector2(close_rect.position.x, close_rect.position.y + close_rect.size.y * 0.5 + 8.0 * s), Tr.t("CLOSE"), HORIZONTAL_ALIGNMENT_CENTER, close_rect.size.x, int(24.0 * s), Color.WHITE)
