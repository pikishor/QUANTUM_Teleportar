class_name TestMenu
extends CanvasLayer
## The TEST MENU (hack mode): big touch buttons for every cheat and test action (the logic is in scripts/common/test_mode.gd). Opened from the title screen and the pause
## screen (a TEST button in the top right corner), by a long press on the FPS box (touch_controls.gd) or F10. Built from the same rules as the HUD: nothing is a Control
## button (`emulate_mouse_from_touch` is off in this project), the node hit-tests its own rectangles from screen touches and the mouse, and drags scroll the page.
## While test mode is available it also draws the 1-4 weapon quick buttons on the right edge during play and the optional stats overlay.
## Add it LAST in main.gd so it sees input before the HUD and the touch controls (`_input` runs in reverse tree order).

signal opened
signal closed

const TABS: Array[String] = ["CHEATS", "LOOT", "WORLD", "SPAWN", "GO", "MISSION", "STATS"]
const BASE_H := 720.0
const BG := Color(0.01, 0.03, 0.05, 0.96)
const PANEL := Color(0.05, 0.13, 0.17, 1.0)
const ON := Color(0.1, 0.55, 0.45, 1.0)
const EDGE := Color(0.45, 0.95, 1.0, 0.8)
const QUICK_IDS: Array[StringName] = [&"carbine", &"scatter", &"lance", &"grenade"]

var is_open := false
var page := 0
var scroll := 0.0
var status := ""
var items: Array[Dictionary] = []          ## {rect: Rect2 (content space), label, fn: Callable, toggle: StringName, head: bool}
var _canvas: Control
var _resume: StringName = &""
var _down := -1                              ## the finger / button that is down, -1 none
var _down_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _moved := false
var _content_h := 0.0
var _layout_key := ""
var _entry_down := &""                       ## "entry" (the TEST button) or "quick<n>" while a press that started on one is held
var _stats_t := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"test_menu")
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_all)
	Game.state_changed.connect(func(_s: StringName) -> void: _canvas.queue_redraw())
	Game.message.connect(func(t: String, _sec: float) -> void: status = t)


func _process(delta: float) -> void:
	if not TestMode.available():
		return
	_stats_t -= delta
	if is_open or TestMode.show_stats or _quick_visible() or _entry_visible():
		if _stats_t <= 0.0 or is_open:
			_stats_t = 0.2
			_canvas.queue_redraw()


# --- open / close ---------------------------------------------------------------------------------------------------------------------

func open() -> bool:
	if not TestMode.available() or is_open:
		return false
	is_open = true
	_resume = &""
	if Game.state == &"play":                       # the game stands still behind the menu
		_resume = &"play"
		Game.state = &"paused"
	scroll = 0.0
	_layout_key = ""
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
	return maxf(_vp().y / BASE_H, 0.1)


func _top() -> float:
	return 132.0 * _s()


func _inset() -> float:
	return UiUtil.insets(_vp()).x


func _head(text: String) -> Dictionary:
	return {"head": true, "label": text}


func _btn(label: String, fn: Callable, toggle := &"") -> Dictionary:
	return {"label": label, "fn": fn, "toggle": toggle}


func _act(label: String, fn: Callable) -> Dictionary:
	return _btn(label, func() -> void: status = str(fn.call()))


func _page_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match page:
		0:
			out.append(_head("TOGGLES"))
			out.append(_btn("GOD MODE", func() -> void: TestMode.toggle(&"god"), &"god"))
			out.append(_btn("INFINITE AMMO", func() -> void: TestMode.toggle(&"ammo"), &"ammo"))
			out.append(_btn("ONE-HIT KILLS", func() -> void: TestMode.toggle(&"onehit"), &"onehit"))
			out.append(_btn("NO HEAT", func() -> void: TestMode.toggle(&"noheat"), &"noheat"))
			out.append(_btn("FREEZE ENEMIES", func() -> void: TestMode.toggle(&"freeze"), &"freeze"))
			out.append(_btn("WEAPON BUTTONS 1-4", func() -> void: TestMode.toggle(&"quick"), &"quick"))
			out.append(_head("NOW"))
			out.append(_act("HEAL AND ENERGY", _heal))
			out.append(_act("FILL AMMO", TestMode.fill_ammo))
			out.append(_act("KILL ALL ENEMIES", TestMode.kill_all_enemies))
		1:
			out.append(_head("GIVE AND SELECT A WEAPON"))
			for id: StringName in WeaponDefs.IDS:
				out.append(_act(WeaponDefs.title(id), TestMode.give_weapon.bind(id)))
			out.append(_act("ALL WEAPONS", TestMode.give_all_weapons))
			out.append(_head("CREDITS AND UPGRADES"))
			for n: int in [1000, 5000, 25000]:
				out.append(_act("+%d CREDITS" % n, TestMode.add_credits.bind(n)))
			out.append(_act("MAX ALL UPGRADES", TestMode.max_upgrades))
		2:
			out.append(_head("WEATHER (TIME OF DAY: THE CITY IS NIGHT ONLY)"))
			for w: String in TestMode.WEATHER:
				out.append(_act(w, TestMode.set_weather.bind(w)))
			out.append(_head("HEAT LEVEL"))
			for h in 6:
				out.append(_act("HEAT %d" % h, TestMode.set_heat.bind(float(h))))
			out.append(_head("GRAPHICS TIER"))
			for q in 3:
				out.append(_btn(["LOW", "MED", "HIGH"][q], func() -> void: Game.set_quality(q)))
		3:
			out.append(_head("SPAWN AT THE CROSSHAIR: ENEMIES"))
			for t: StringName in TestMode.ENEMIES:
				out.append(_act(String(t).to_upper() + (" (BOSS)" if t == &"overseer" else ""), TestMode.spawn_enemy.bind(t)))
			out.append(_head("VEHICLES"))
			for k: StringName in TestMode.VEHICLES:
				out.append(_act(String(k).to_upper(), TestMode.spawn_vehicle.bind(k)))
		4:
			out.append(_head("TELEPORT"))
			for pair: Array in [["NEAREST CORE", "core"], ["CONTRACT MARKER", "contract"], ["A ROOFTOP", "roof"], ["SPAWN", "spawn"], ["CORNER NW", "nw"], ["CORNER NE", "ne"], ["CORNER SW", "sw"], ["CORNER SE", "se"]]:
				out.append(_act(pair[0], TestMode.teleport.bind(pair[1])))
		5:
			out.append(_head("JUMP TO SECTOR"))
			for c in 6:
				out.append(_act("SECTOR %d" % (c + 1), TestMode.jump_to_chapter.bind(c)))
			out.append(_head("START A CONTRACT"))
			for k: StringName in TestMode.CONTRACTS:
				out.append(_act(ContractTypes.title(k), TestMode.start_contract.bind(k)))
			out.append(_head("CURRENT CONTRACT"))
			out.append(_act("SKIP (PAID)", TestMode.skip_contract))
		6:
			out.append(_head("STATS"))
			out.append(_btn("STATS OVERLAY", func() -> void: TestMode.toggle(&"stats"), &"stats"))
			out.append(_btn("ERROR PANEL", _toggle_errors))
			out.append(_btn("KEEP TEST MODE (SAVED)", _toggle_forced, &"forced"))
	return out


func _heal() -> String:
	var p := Game.player as Player
	if p == null:
		return ""
	p.hp = p.max_hp
	p.energy = p.max_energy
	Game.say("HEALED", 1.2)
	return "HEALED"


func _toggle_errors() -> void:
	for n in get_tree().root.find_children("*", "TouchControls", true, false):
		var tc := n as TouchControls
		tc.errors_on = not tc.errors_on
		tc.perf_on = true
		tc.queue_redraw()
	status = "ERROR PANEL TOGGLED (SHOWN ON THE FPS BOX SIDE OF THE HUD)"


func _toggle_forced() -> void:
	TestMode.forced = not TestMode.forced
	var us := UiSettings.new()
	us.test_mode = TestMode.forced
	us.save()
	status = "TEST MODE IN RELEASE BUILDS: %s" % ("ON" if TestMode.forced else "OFF")


func _columns(vp: Vector2) -> int:
	return 4 if vp.x / vp.y > 1.9 else 3


## Builds the item rectangles of the current page (content space: y = 0 at the top of the scroll area).
func layout() -> void:
	var vp := _vp()
	var key := "%d|%d|%d" % [page, int(vp.x), int(vp.y)]
	if key == _layout_key:
		return
	_layout_key = key
	items = _page_items()
	var s := _s()
	var gap := 12.0 * s
	var left := maxf(_inset(), 18.0 * s)
	var width := vp.x - left * 2.0
	var cols := _columns(vp)
	var bw := (width - gap * float(cols - 1)) / float(cols)
	var bh := 66.0 * s
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
	if page == 6:
		_content_h += 220.0 * s
	scroll = clampf(scroll, 0.0, _max_scroll())


func _max_scroll() -> float:
	return maxf(0.0, _content_h - (_vp().y - _top() - 10.0 * _s()))


func _tab_rects() -> Array[Rect2]:
	var vp := _vp()
	var s := _s()
	var left := maxf(_inset(), 18.0 * s)
	var closew := 120.0 * s
	var avail := vp.x - left * 2.0 - closew - 12.0 * s
	var tw := avail / float(TABS.size())
	var out: Array[Rect2] = []
	for i in TABS.size():
		out.append(Rect2(left + tw * float(i), 70.0 * s, tw - 6.0 * s, 52.0 * s))
	return out


func _close_rect() -> Rect2:
	var vp := _vp()
	var s := _s()
	return Rect2(vp.x - maxf(_inset(), 18.0 * s) - 120.0 * s, 70.0 * s, 120.0 * s, 52.0 * s)


func _play_rect() -> Rect2:
	var vp := _vp()
	var s := _s()
	return Rect2(vp.x - maxf(_inset(), 18.0 * s) - 280.0 * s, 12.0 * s, 280.0 * s, 48.0 * s)


## The TEST button on the title and pause screens.
func entry_rect() -> Rect2:
	var vp := _vp()
	var s := _s()
	return Rect2(vp.x - maxf(_inset(), 14.0 * s) - 130.0 * s, 14.0 * s, 130.0 * s, 56.0 * s)


func quick_rect(i: int) -> Rect2:
	var vp := _vp()
	var s := _s()
	var r := 28.0 * s
	var cx := vp.x - maxf(_inset(), 8.0 * s) - 52.0 * s
	return Rect2(cx - r, (136.0 + 66.0 * float(i)) * s - r, r * 2.0, r * 2.0)


func _entry_visible() -> bool:
	return TestMode.available() and not is_open and (Game.state == &"menu" or Game.state == &"paused")


func _quick_visible() -> bool:
	return TestMode.quick_buttons_on() and not is_open and Game.state == &"play"


# --- input ---------------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not TestMode.available():
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_F10:
			if is_open:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
			return
		if is_open and ke.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
			return
	var kind := 0                                   # 1 press, 2 move, 3 release, 4 wheel
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
	if kind == 0:
		return
	if handle_pointer(kind, pos, id):
		get_viewport().set_input_as_handled()


## One pointer event (kind 1 press, 2 move, 3 release); returns true when the menu used it. Public so tests can drive it.
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
	# closed: the TEST button (title / pause) and the weapon quick buttons (play)
	match kind:
		1:
			if _entry_visible() and entry_rect().has_point(pos):
				_entry_down = &"entry"
				_down = id
				return true
			if _quick_visible():
				for i in QUICK_IDS.size():
					if quick_rect(i).grow(8.0 * _s()).has_point(pos):
						_entry_down = StringName("quick%d" % i)
						_down = id
						return true
		2:
			return id == _down and _entry_down != &""
		3:
			if id == _down and _entry_down != &"":
				var which := _entry_down
				_entry_down = &""
				_down = -1
				if which == &"entry":
					if entry_rect().has_point(pos):
						open()
				else:
					var i := int(String(which).substr(5))
					if quick_rect(i).grow(8.0 * _s()).has_point(pos):
						TestMode.select_weapon(QUICK_IDS[i])
				return true
	return false


## A tap at a screen position (the menu is open).
func tap(pos: Vector2) -> bool:
	layout()
	if _close_rect().has_point(pos):
		close()
		return true
	if Game.state == &"menu" and _play_rect().has_point(pos):
		close()
		Game.start_new_game()
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
		var r: Rect2 = it["rect"]
		if r.has_point(Vector2(pos.x, cy)):
			(it["fn"] as Callable).call()
			Sfx.play(&"ui_tap")
			_canvas.queue_redraw()
			return true
	return false


## Press a button by its label (tests and the bot): "GOD MODE", "ALL WEAPONS" ...
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


# --- drawing -------------------------------------------------------------------------------------------------------------------------

func _text(font: Font, pos: Vector2, text: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_canvas.draw_string(font, pos, text, align, width, size, col)


func _draw_all() -> void:
	if not TestMode.available():
		return
	var vp := _vp()
	var s := _s()
	var font := UiUtil.font()
	if is_open:
		_draw_menu(vp, s, font)
		return
	if TestMode.show_stats:
		var lines := TestMode.stats_text().split("\n")
		var box := Rect2(vp.x * 0.5 - 250.0 * s, 4.0 * s, 500.0 * s, (10.0 + 20.0 * float(lines.size())) * s)
		_canvas.draw_rect(box, Color(0, 0, 0, 0.55))
		for i in lines.size():
			_text(font, Vector2(box.position.x + 8.0 * s, box.position.y + (22.0 + 20.0 * float(i)) * s), lines[i], int(15.0 * s), Color(0.6, 1.0, 0.8), box.size.x - 16.0 * s)
	if _entry_visible():
		var r := entry_rect()
		_canvas.draw_rect(r, Color(0.35, 0.12, 0.05, 0.9))
		_canvas.draw_rect(r, AMBER, false, 2.0)
		_text(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 8.0 * s), "TEST", int(24.0 * s), Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _quick_visible():
		var p := Game.player as Player
		var cur: StringName = p.weapon.current if p != null and p.weapon != null else &""
		for i in QUICK_IDS.size():
			var r := quick_rect(i)
			var c := r.get_center()
			var held := WeaponDefs.is_unlocked(QUICK_IDS[i])
			_canvas.draw_circle(c, r.size.x * 0.5, Color(0.02, 0.1, 0.13, 0.78) if held else Color(0.02, 0.06, 0.08, 0.6))
			_canvas.draw_arc(c, r.size.x * 0.5, 0.0, TAU, 28, ON if QUICK_IDS[i] == cur else EDGE, 3.0 * s if QUICK_IDS[i] == cur else 1.5 * s)
			_text(font, Vector2(r.position.x, c.y + 9.0 * s), str(i + 1), int(26.0 * s), Color.WHITE if held else Color(1, 1, 1, 0.55), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


const AMBER := Color(1.0, 0.72, 0.25)


func _draw_menu(vp: Vector2, s: float, font: Font) -> void:
	layout()
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var top := _top()
	# content (clipped by the header drawn over it)
	for it in items:
		var r: Rect2 = it["rect"]
		var rr := Rect2(r.position.x, r.position.y - scroll + top, r.size.x, r.size.y)
		if rr.end.y < top - 4.0 or rr.position.y > vp.y:
			continue
		if it.get("head", false):
			_text(font, Vector2(rr.position.x, rr.position.y + 24.0 * s), String(it["label"]), int(18.0 * s), AMBER, rr.size.x)
			continue
		var on := _toggle_on(it)
		_canvas.draw_rect(rr, ON if on else PANEL)
		_canvas.draw_rect(rr, EDGE if on else Color(EDGE, 0.35), false, 2.0)
		var label := String(it["label"])
		if it["toggle"] != &"" and it["toggle"] != &"forced":
			label += "   " + ("ON" if on else "OFF")
		elif it["toggle"] == &"forced":
			label += "   " + ("ON" if on else "OFF")
		_text(font, Vector2(rr.position.x, rr.position.y + rr.size.y * 0.5 + 8.0 * s), label, int(22.0 * s), Color.WHITE, rr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if page == 6:
		var y := top + (_content_h - 220.0 * s) - scroll + 10.0 * s
		var lines := TestMode.stats_text().split("\n")
		for i in lines.size():
			_text(font, Vector2(maxf(_inset(), 18.0 * s), y + (22.0 + 26.0 * float(i)) * s), lines[i], int(20.0 * s), Color(0.6, 1.0, 0.8), vp.x - 40.0 * s)
	# header
	_canvas.draw_rect(Rect2(0, 0, vp.x, top - 4.0 * s), BG)
	_text(font, Vector2(maxf(_inset(), 18.0 * s), 44.0 * s), "TEST MENU", int(30.0 * s), AMBER)
	_text(font, Vector2(maxf(_inset(), 18.0 * s) + 220.0 * s, 42.0 * s), status, int(18.0 * s), Color(0.7, 1.0, 0.9), vp.x - 560.0 * s)
	var tabs := _tab_rects()
	for i in tabs.size():
		_canvas.draw_rect(tabs[i], ON if i == page else PANEL)
		_canvas.draw_rect(tabs[i], EDGE, false, 2.0)
		_text(font, Vector2(tabs[i].position.x, tabs[i].position.y + tabs[i].size.y * 0.5 + 7.0 * s), TABS[i], int(20.0 * s), Color.WHITE, tabs[i].size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var cr := _close_rect()
	_canvas.draw_rect(cr, Color(0.45, 0.1, 0.1, 1.0))
	_canvas.draw_rect(cr, EDGE, false, 2.0)
	_text(font, Vector2(cr.position.x, cr.position.y + cr.size.y * 0.5 + 8.0 * s), "CLOSE", int(22.0 * s), Color.WHITE, cr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if Game.state == &"menu":
		var pr := _play_rect()
		_canvas.draw_rect(pr, ON)
		_canvas.draw_rect(pr, EDGE, false, 2.0)
		_text(font, Vector2(pr.position.x, pr.position.y + pr.size.y * 0.5 + 8.0 * s), "START GAME", int(22.0 * s), Color.WHITE, pr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _max_scroll() > 0.0:
		var frac := scroll / _max_scroll()
		_canvas.draw_rect(Rect2(vp.x - 8.0 * s, top + frac * (vp.y - top - 90.0 * s), 5.0 * s, 80.0 * s), Color(EDGE, 0.6))


func _toggle_on(it: Dictionary) -> bool:
	var t: StringName = it["toggle"]
	if t == &"":
		return false
	if t == &"forced":
		return TestMode.forced
	return TestMode.is_on(t)
