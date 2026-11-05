class_name DemoPanel
extends CanvasLayer
## The DEMO menu and the DEMO badge (demo mode, scripts/demo/demo_mode.gd). While DemoMode.active it draws a 64 px DEMO button on the left edge during play (it opens the menu) and
## the menu itself: tabs for chapters, side missions, activities, set pieces, bosses, events, contracts, interiors, spawns and tools (difficulty, god mode, infinite ammo, teleports,
## QUIT DEMO). Tap an entry to go there / spawn it; the menu closes and the game runs. Like the TEST MENU nothing here is a Control button (`emulate_mouse_from_touch` is off): the node
## hit-tests its own rectangles from screen touches and the mouse, and drags scroll the page. The game stands still behind the menu through Game.state only. Added LAST in main.gd.

signal opened
signal closed

const TABS: Array[String] = ["CHAPTERS", "SIDE", "ACTIVITY", "SET PIECE", "BOSS", "EVENT", "CONTRACT", "INTERIOR", "SEQUEL", "CHASE", "SPAWN", "TOOLS"]
const BG := Color(0.01, 0.03, 0.05, 1.0)
const PANEL := Color(0.05, 0.13, 0.17, 1.0)
const ON := Color(0.1, 0.55, 0.45, 1.0)
const EDGE := Color(0.45, 0.95, 1.0, 0.8)
const AMBER := Color(1.0, 0.72, 0.25)
const TAB_ROW := 70.0                       ## base px: pitch of a tab row (a 64 px tab and a gap)
const TAB_MIN_W := 150.0                    ## base px: a tab is never narrower than this; more tabs than fit one row wrap onto more rows
const BTN_H := 64.0                         ## base px (never below UiUtil.TOUCH_MIN)

var is_open := false
var page := 0
var scroll := 0.0
var status := ""
var items: Array[Dictionary] = []          ## {rect (content space), label, fn: Callable, on: Callable or null, head: bool, launch: bool}
var _canvas: Control
var _resume: StringName = &""
var _down := -1
var _down_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _moved := false
var _entry_down := false
var _content_h := 0.0
var _layout_key := ""
var _catalog: Array[Dictionary] = []


func _ready() -> void:
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"demo_panel")
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_all)
	Game.state_changed.connect(func(_s: StringName) -> void: _canvas.queue_redraw())
	Game.message.connect(func(t: String, _sec: float) -> void: if is_open: status = t)


func _process(_delta: float) -> void:
	if not DemoMode.active:
		if is_open:
			close()
		return
	if is_open or _entry_visible():
		_canvas.queue_redraw()


# --- open / close ---------------------------------------------------------------------------------------------------------------------

func open() -> bool:
	if not DemoMode.active or is_open or not (Game.state == &"play" or Game.state == &"paused"):
		return false
	is_open = true
	_resume = &""
	if Game.state == &"play":
		_resume = &"play"
		Game.state = &"paused"
	scroll = 0.0
	_layout_key = ""
	if _catalog.is_empty():
		_catalog = DemoMode.catalog()
	opened.emit()
	_canvas.queue_redraw()
	return true


func close() -> void:
	if not is_open:
		return
	is_open = false
	_down = -1
	if _resume == &"play" and Game.state == &"paused":
		Game.state = &"play"
	_resume = &""
	closed.emit()
	_canvas.queue_redraw()


func set_page(i: int) -> void:
	page = clampi(i, 0, TABS.size() - 1)
	scroll = 0.0
	_layout_key = ""
	_canvas.queue_redraw()


# --- layout ---------------------------------------------------------------------------------------------------------------------------

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _s() -> float:
	return UiUtil.ui_scale(_vp())


func _top() -> float:
	return (156.0 + float(tab_rows() - 1) * TAB_ROW) * _s()


func _left() -> float:
	return maxf(UiUtil.insets(_vp()).x, 18.0 * _s())


func _head(text: String) -> Dictionary:
	return {"head": true, "label": text}


## A launch entry: the menu closes (the game runs again), then the action starts.
func _go(label: String, kind: StringName, id: Variant) -> Dictionary:
	return {"label": label, "launch": true, "fn": func() -> void: _launch(kind, id), "on": null}


func _btn(label: String, fn: Callable, on: Variant = null) -> Dictionary:
	return {"label": label, "fn": fn, "on": on}


func _act(label: String, fn: Callable) -> Dictionary:
	return _btn(label, func() -> void: status = str(fn.call()))


func _launch(kind: StringName, id: Variant) -> void:
	close()
	status = DemoMode.launch(kind, id)
	if status == "":
		status = "COULD NOT START"


func _page_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if page < _catalog.size():
		var g: Dictionary = _catalog[page]
		out.append(_head(String(g["title"])))
		for it: Dictionary in g["items"]:
			out.append(_go(String(it["label"]), g["kind"], it["id"]))
		return out
	match TABS[page]:
		"SPAWN":
			out.append(_head("SPAWN AT THE CROSSHAIR: ENEMIES"))
			for t: StringName in TestMode.ENEMIES:
				out.append(_act(String(t).to_upper(), TestMode.spawn_enemy.bind(t)))
			out.append(_head("VEHICLES"))
			for k: StringName in TestMode.VEHICLES:
				out.append(_act(String(k).to_upper(), TestMode.spawn_vehicle.bind(k)))
			out.append(_head("GARAGE CAR (MAXED)"))
			for k: StringName in TestMode.VEHICLES:
				out.append(_act("GARAGE " + String(k).to_upper(), _garage_car.bind(k)))
		"TOOLS":
			out.append(_head("DIFFICULTY"))
			for m in Difficulty.NAMES.size():
				out.append(_btn(Difficulty.NAMES[m], func() -> void: status = DemoMode.set_difficulty(m), func() -> bool: return Difficulty.current == m))
			out.append(_head("TOGGLES"))
			out.append(_btn("GOD MODE", func() -> void: TestMode.toggle(&"god"), func() -> bool: return TestMode.god))
			out.append(_btn("INFINITE AMMO", func() -> void: TestMode.toggle(&"ammo"), func() -> bool: return TestMode.infinite_ammo))
			out.append(_head("NOW"))
			out.append(_act("HEAL AND FILL AMMO", _heal))
			out.append(_act("REVEAL THE MAP", DemoMode.reveal_map))
			out.append(_act("KILL ALL ENEMIES", TestMode.kill_all_enemies))
			out.append(_head("TELEPORT"))
			for pair: Array in [["NEAREST CORE", "core"], ["A ROOFTOP", "roof"], ["SPAWN", "spawn"], ["CORNER NW", "nw"], ["CORNER NE", "ne"], ["CORNER SW", "sw"], ["CORNER SE", "se"]]:
				out.append(_act(pair[0], TestMode.teleport.bind(pair[1])))
			out.append(_head("LEAVE"))
			out.append({"label": "QUIT DEMO", "fn": _quit, "on": null, "quit": true})
	return out


func _garage_car(kind: StringName) -> String:
	var prog := Game.progress as Progress
	if prog == null or not VehicleSpecs.SPECS.has(kind):
		return ""
	prog.garage.kind = kind
	for st: StringName in Garage.STATS:
		prog.garage.levels[st] = Garage.MAX_LEVEL
	prog.changed.emit()
	return "GARAGE CAR  %s" % String(kind).to_upper()


func _heal() -> String:
	var p := Game.player as Player
	if p == null:
		return ""
	p.hp = p.max_hp
	p.energy = p.max_energy
	TestMode.fill_ammo()
	return "HEALED"


func _quit() -> void:
	close()
	DemoMode.quit()


func _columns(vp: Vector2) -> int:
	return 4 if vp.x / vp.y > 1.9 else 3


## Builds the item rectangles of the current page (content space: y = 0 at the top of the scroll area).
func layout() -> void:
	var vp := _vp()
	var key := "%d|%d|%d|%d" % [page, int(vp.x), int(vp.y), _catalog.size()]
	if key == _layout_key:
		return
	_layout_key = key
	items = _page_items()
	var s := _s()
	var gap := 12.0 * s
	var left := _left()
	var width := vp.x - left * 2.0
	var cols := _columns(vp)
	var bw := (width - gap * float(cols - 1)) / float(cols)
	var bh := BTN_H * s
	var y := 0.0
	var col := 0
	for it in items:
		if it.get("head", false):
			if col != 0:
				y += bh + gap
				col = 0
			it["rect"] = Rect2(left, y, width, 34.0 * s)
			y += 40.0 * s
			continue
		it["rect"] = Rect2(left + float(col) * (bw + gap), y, bw, bh)
		col += 1
		if col >= cols:
			col = 0
			y += bh + gap
	if col != 0:
		y += bh + gap
	_content_h = y
	scroll = clampf(scroll, 0.0, _max_scroll())


func _max_scroll() -> float:
	return maxf(0.0, _content_h - (_vp().y - _top() - 10.0 * _s()))


func _close_rect() -> Rect2:
	var s := _s()
	var w := 120.0 * s
	return Rect2(_vp().x - _left() - w, 84.0 * s, w, BTN_H * s)


## Number of rows the tabs wrap onto at this viewport (each tab keeps at least TAB_MIN_W base px; the rows are balanced).
func tab_rows() -> int:
	var s := _s()
	var avail := _vp().x - _left() * 2.0 - 120.0 * s - 12.0 * s
	var per_row := maxi(1, int(avail / (TAB_MIN_W * s)))
	return ceili(float(TABS.size()) / float(per_row))


func _tab_rects() -> Array[Rect2]:
	var s := _s()
	var left := _left()
	var avail := _vp().x - left * 2.0 - _close_rect().size.x - 12.0 * s
	var rows := tab_rows()
	var per_row := ceili(float(TABS.size()) / float(rows))
	var tw := avail / float(per_row)
	var out: Array[Rect2] = []
	for i in TABS.size():
		out.append(Rect2(left + tw * float(i % per_row), (84.0 + TAB_ROW * float(i / per_row)) * s, tw - 4.0 * s, BTN_H * s))
	return out


## The DEMO button / badge (left edge, during play and pause while the demo runs): opens the menu.
func entry_rect() -> Rect2:
	var s := _s()
	return Rect2(maxf(UiUtil.insets(_vp()).x, 8.0 * s) + 8.0 * s, 300.0 * s, 120.0 * s, BTN_H * s)


func _entry_visible() -> bool:
	return DemoMode.active and not is_open and (Game.state == &"play" or Game.state == &"paused")


## Every hit rectangle in screen space (tests check the 64 px rule against these).
func hit_rects() -> Array[Rect2]:
	layout()
	var out: Array[Rect2] = [entry_rect(), _close_rect()]
	out.append_array(_tab_rects())
	for it in items:
		if not it.get("head", false):
			var r: Rect2 = it["rect"]
			out.append(Rect2(r.position.x, r.position.y + _top(), r.size.x, r.size.y))
	return out


# --- input ----------------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not DemoMode.active:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and is_open and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	var kind := 0                                   # 1 press, 2 move, 3 release
	var pos := Vector2.ZERO
	var id := 0
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		kind = 1 if t.pressed else 3
		pos = t.position
		id = t.index + 1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		kind = 2
		pos = d.position
		id = d.index + 1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if is_open and mb.pressed:
				scroll = clampf(scroll + (-90.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 90.0) * _s(), 0.0, _max_scroll())
				_canvas.queue_redraw()
				get_viewport().set_input_as_handled()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		kind = 1 if mb.pressed else 3
		pos = mb.position
		id = 100
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		kind = 2
		pos = (event as InputEventMouseMotion).position
		id = 100
	if kind != 0 and handle_pointer(kind, pos, id):
		get_viewport().set_input_as_handled()


## One pointer event (1 press, 2 move, 3 release); true when the panel used it. Public so tests can drive it.
func handle_pointer(kind: int, pos: Vector2, id: int) -> bool:
	if is_open:
		match kind:
			1:
				if _down == -1:
					_down = id
					_down_pos = pos
					_last_pos = pos
					_moved = false
			2:
				if id == _down:
					if pos.distance_to(_down_pos) > 14.0 * _s():
						_moved = true
					if _moved:
						scroll = clampf(scroll - (pos.y - _last_pos.y), 0.0, _max_scroll())
						_canvas.queue_redraw()
					_last_pos = pos
			3:
				if id == _down:
					_down = -1
					if not _moved:
						tap(pos)
		return true
	match kind:
		1:
			if _entry_visible() and entry_rect().has_point(pos):
				_entry_down = true
				_down = id
				return true
		2:
			return id == _down and _entry_down
		3:
			if id == _down and _entry_down:
				_entry_down = false
				_down = -1
				if entry_rect().has_point(pos):
					open()
				return true
	return false


## A tap at a screen position (the menu is open).
func tap(pos: Vector2) -> bool:
	layout()
	if _close_rect().has_point(pos):
		close()
		return true
	var tabs := _tab_rects()
	for i in tabs.size():
		if tabs[i].has_point(pos):
			set_page(i)
			return true
	if pos.y < _top():
		return false
	var cy := pos.y - _top() + scroll
	for it in items:
		if it.get("head", false):
			continue
		if (it["rect"] as Rect2).has_point(Vector2(pos.x, cy)):
			(it["fn"] as Callable).call()
			Sfx.play(&"ui_tap")
			_layout_key = "" if not bool(it.get("launch", false)) and not bool(it.get("quit", false)) else _layout_key
			_canvas.queue_redraw()
			return true
	return false


## Press an entry by its label (tests and the bot).
func press_label(label: String) -> bool:
	layout()
	for it in items:
		if not it.get("head", false) and String(it["label"]) == label:
			(it["fn"] as Callable).call()
			return true
	return false


func labels() -> PackedStringArray:
	layout()
	var out := PackedStringArray()
	for it in items:
		if not it.get("head", false):
			out.append(String(it["label"]))
	return out


# --- drawing --------------------------------------------------------------------------------------------------------------------------

func _text(font: Font, pos: Vector2, text: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_canvas.draw_string(font, pos, text, align, width, size, col)


func _draw_all() -> void:
	if not DemoMode.active:
		return
	var vp := _vp()
	var s := _s()
	var font := UiUtil.font()
	if is_open:
		_draw_menu(vp, s, font)
		return
	if _entry_visible():
		var r := entry_rect()
		_canvas.draw_rect(r, Color(0.35, 0.22, 0.03, 0.85))
		_canvas.draw_rect(r, AMBER, false, 2.0)
		_text(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 9.0 * s), "DEMO", int(26.0 * s), Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_menu(vp: Vector2, s: float, font: Font) -> void:
	layout()
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var top := _top()
	for it in items:
		var r: Rect2 = it["rect"]
		var rr := Rect2(r.position.x, r.position.y - scroll + top, r.size.x, r.size.y)
		if rr.end.y < top - 4.0 or rr.position.y > vp.y:
			continue
		if it.get("head", false):
			_text(font, Vector2(rr.position.x, rr.position.y + 24.0 * s), String(it["label"]), int(18.0 * s), AMBER, rr.size.x)
			continue
		var on := it["on"] is Callable and bool((it["on"] as Callable).call())
		var quit := bool(it.get("quit", false))
		_canvas.draw_rect(rr, Color(0.45, 0.1, 0.1, 1.0) if quit else (ON if on else PANEL))
		_canvas.draw_rect(rr, EDGE if on else Color(EDGE, 0.35), false, 2.0)
		_text(font, Vector2(rr.position.x, rr.position.y + rr.size.y * 0.5 + 8.0 * s), String(it["label"]), int(22.0 * s), Color.WHITE, rr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_canvas.draw_rect(Rect2(0, 0, vp.x, top - 4.0 * s), BG)
	var l := _left()
	var badge := Rect2(l, 14.0 * s, 110.0 * s, 52.0 * s)
	_canvas.draw_rect(badge, Color(0.35, 0.22, 0.03, 0.95))
	_canvas.draw_rect(badge, AMBER, false, 2.0)
	_text(font, Vector2(badge.position.x, badge.position.y + badge.size.y * 0.5 + 9.0 * s), "DEMO", int(28.0 * s), Color.WHITE, badge.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text(font, Vector2(l + 130.0 * s, 48.0 * s), status, int(20.0 * s), Color(0.7, 1.0, 0.9), vp.x - l * 2.0 - 140.0 * s)
	var tabs := _tab_rects()
	for i in tabs.size():
		_canvas.draw_rect(tabs[i], ON if i == page else PANEL)
		_canvas.draw_rect(tabs[i], EDGE, false, 2.0)
		_text(font, Vector2(tabs[i].position.x, tabs[i].position.y + tabs[i].size.y * 0.5 + 8.0 * s), TABS[i], int(22.0 * s), Color.WHITE, tabs[i].size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var cr := _close_rect()
	_canvas.draw_rect(cr, Color(0.45, 0.1, 0.1, 1.0))
	_canvas.draw_rect(cr, EDGE, false, 2.0)
	_text(font, Vector2(cr.position.x, cr.position.y + cr.size.y * 0.5 + 8.0 * s), "CLOSE", int(22.0 * s), Color.WHITE, cr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _max_scroll() > 0.0:
		var frac := scroll / _max_scroll()
		_canvas.draw_rect(Rect2(vp.x - 8.0 * s, top + frac * (vp.y - top - 90.0 * s), 5.0 * s, 80.0 * s), Color(EDGE, 0.6))
