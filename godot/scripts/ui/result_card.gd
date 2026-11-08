class_name ResultCard
extends CanvasLayer
## The mission result card (DESIGN.md core loop step 4: "complete the mission, get credits, a new weapon or an upgrade, see the next mission at once").
## Opens by itself when MissionRewards has paid a finished mission (`Progress.mission_result`) and the game is playing: the game stands still through Game.state only (play -> paused -> play).
## One screen, big numbers: CREDITS earned (counts up), the one thing UNLOCKED (a weapon with its own picture, a weapon crate, a mod, an upgrade level), a tiny level / XP bar, the first-ten
## missions strip ("something new every mission"), "NEXT WEAPON IN 2 MISSIONS" and what to do next (the mission guide's objective line). Two buttons, both 64 px or more: the big NEXT, and one
## contextual button (EQUIP the new mod or weapon, or UPGRADES when the wallet can buy one). Like the TEST and DEMO menus nothing here is a Control button: the node hit-tests its own
## rectangles from touches and the mouse, and is added late in main.gd (before the TEST menu) so it sees input first.
## `enabled` is false under tools / tests / bots (Game.autostart): a modal card would stall them; tests that exercise the card set it.

signal opened(result: Dictionary)
signal closed
signal next_pressed

const BG := Color(0.01, 0.025, 0.045, 1.0)
const PLATE := Color(0.045, 0.07, 0.12, 1.0)
const SHOW_DELAY := 1.4                 ## seconds of play between the completion and the card (the OBJECTIVE COMPLETE toast and its sound are heard first)
const COUNT_TIME := 0.9                 ## the credits count up over this many seconds
const QUEUE_MAX := 3
const KIND_NAME := {&"weapon": "NEW WEAPON", &"crate": "WEAPON CRATE", &"mod": "NEW WEAPON MOD", &"upgrade": "UPGRADE", &"cash": "BONUS"}
const KIND_GLYPH := {&"weapon": &"weapon", &"crate": &"heists", &"mod": &"options", &"upgrade": &"plus", &"cash": &"achievements"}
const KIND_COLOR := {&"weapon": Color(1.0, 0.45, 0.9), &"crate": Color(1.0, 0.72, 0.25), &"mod": Color(0.45, 0.95, 1.0), &"upgrade": Color(0.4, 1.0, 0.6), &"cash": Color(1.0, 0.72, 0.25)}

static var enabled := true
## Called after NEXT closes the card (the Mission Board sets this to offer the next mission); also the `next_pressed` signal.
static var next_hook := Callable()

var is_open := false
var current: Dictionary = {}
var queue: Array[Dictionary] = []
var shown := 0                           ## cards opened (tests)
var second_used := false                 ## the contextual button was pressed on this card
var _canvas: Control
var _resume: StringName = &""
var _delay := 0.0
var _t := 0.0
var _down := -1
var _connected := false


func _ready() -> void:
	layer = 39
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"result_card")
	if Game.autostart:
		enabled = false
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_all)
	Game.state_changed.connect(func(_s: StringName) -> void: _canvas.queue_redraw())


func _process(delta: float) -> void:
	if not _connected:
		var prog := Game.progress as Progress
		if prog != null:
			_connected = true
			prog.mission_result.connect(_on_result)
	if is_open:
		_t += delta
		_canvas.queue_redraw()
		if Game.state != &"paused":                          # something else took the game (a death, the menu): the card is moot
			_close(false)
		return
	if queue.is_empty():
		return
	if Game.state == &"play":
		_delay -= delta
		if _delay <= 0.0:
			open(queue.pop_front())
	elif Game.state == &"menu":
		queue.clear()


func _on_result(result: Dictionary) -> void:
	if not enabled:
		return
	queue.append(result)
	while queue.size() > QUEUE_MAX:
		queue.pop_front()
	if queue.size() == 1 and not is_open:
		_delay = SHOW_DELAY


# --- open / close ---------------------------------------------------------------------------------------------------------------------

func open(result: Dictionary) -> bool:
	if is_open or result.is_empty():
		return false
	is_open = true
	current = result
	second_used = false
	_t = 0.0
	_down = -1
	_resume = &""
	if Game.state == &"play":
		_resume = &"play"
		Game.state = &"paused"
	shown += 1
	Sfx.play(&"ui_contract_complete")
	opened.emit(result)
	_canvas.queue_redraw()
	return true


## NEXT: the card closes, the game runs again and the board (or the guide) takes over.
func press_next() -> void:
	if not is_open:
		return
	Sfx.play(&"ui_confirm")
	_close(true)
	next_pressed.emit()
	if next_hook.is_valid():
		next_hook.call()
	else:
		var m := Game.missions
		if is_instance_valid(m) and m.get(&"board") != null and (m.get(&"board") as Object).has_method(&"offer_next"):
			(m.get(&"board") as Object).call(&"offer_next")


func _close(resume: bool) -> void:
	if not is_open:
		return
	is_open = false
	_down = -1
	if resume and _resume == &"play" and Game.state == &"paused":
		Game.state = &"play"
	_resume = &""
	closed.emit()
	if not queue.is_empty():
		_delay = 0.4
	_canvas.queue_redraw()


# --- content --------------------------------------------------------------------------------------------------------------------------

func reward() -> Dictionary:
	return current.get("reward", {}) as Dictionary


## The contextual button: {id, label} or {} when there is nothing useful to offer.
func second_action() -> Dictionary:
	var r := reward()
	match StringName(r.get("kind", &"")):
		&"mod":
			return {"id": &"equip_mod", "label": "EQUIPPED" if second_used else "EQUIP NOW"}
		&"weapon", &"crate":
			return {"id": &"equip_weapon", "label": "IN HAND" if second_used else "EQUIP NOW"}
	var up := current.get("upgrade", {}) as Dictionary
	var prog := Game.progress as Progress
	if prog != null and not up.is_empty():
		var u: StringName = up["id"]
		if prog.can_buy(u):
			return {"id": &"upgrades", "label": "UPGRADES"}
	return {}


func press_second() -> bool:
	if not is_open or second_used:
		return false
	var a := second_action()
	if a.is_empty():
		return false
	var r := reward()
	match StringName(a["id"]):
		&"equip_mod":
			second_used = MissionRewards.equip_now(StringName(r["id"]))
		&"equip_weapon":
			var pl := Game.player
			if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
				second_used = (pl.get(&"weapon") as PlayerWeapon).switch_to(StringName(r["id"]), true)
			else:
				WeaponDefs.last_used = StringName(r["id"])
				second_used = true
		&"upgrades":
			var hud := get_tree().get_first_node_in_group(&"hud") as Hud
			if hud != null and Game.state == &"paused":
				_close(false)
				Sfx.play(&"ui_confirm")
				return hud.press_button(&"hero_open")
	if second_used:
		Sfx.play(&"ui_purchase")
	_canvas.queue_redraw()
	return second_used


## What to do next: the guide's objective, else the map.
static func next_line() -> String:
	var m := Game.missions as Missions
	if m != null and m.campaign != null and m.campaign.guide != null:
		var l := m.campaign.guide.line()
		if l != "":
			return l
	return "FREE ROAM  PICK YOUR NEXT MISSION ON THE MAP"


# --- layout ---------------------------------------------------------------------------------------------------------------------------

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _s() -> float:
	return UiUtil.ui_scale(_vp())


func _left() -> float:
	return maxf(UiUtil.insets(_vp()).x, 24.0 * _s()) + 16.0 * _s()


func next_rect() -> Rect2:
	var s := _s()
	var vp := _vp()
	var avail := vp.x - _left() * 2.0
	var w := minf(380.0 * s, avail * 0.5)                    # a squarish window (a tablet, a test) shares the width between the two buttons
	return Rect2(vp.x - _left() - w, vp.y - 100.0 * s, w, 76.0 * s)


func second_rect() -> Rect2:
	var s := _s()
	var n := next_rect()
	var w := minf(320.0 * s, (vp_w() - _left() * 2.0) * 0.44)
	return Rect2(n.position.x - w - 16.0 * s, n.position.y + 6.0 * s, w, 64.0 * s)


func vp_w() -> float:
	return _vp().x


## Every hit rectangle (screen space); tests check the 64 px rule against these.
func hit_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [next_rect()]
	if not second_action().is_empty():
		out.append(second_rect())
	return out


func _col1() -> Rect2:
	var s := _s()
	var vp := _vp()
	var l := _left()
	return Rect2(l, 130.0 * s, (vp.x - l * 2.0) * 0.40, 290.0 * s)


func _col2() -> Rect2:
	var s := _s()
	var vp := _vp()
	var l := _left()
	var c1 := _col1()
	return Rect2(c1.end.x + 28.0 * s, c1.position.y, vp.x - l - c1.end.x - 28.0 * s, 290.0 * s)


## The strip of the first ten missions: one square per mission.
func strip_rects() -> Array[Rect2]:
	var s := _s()
	var vp := _vp()
	var l := _left()
	var rows: Array = current.get("ladder", []) as Array
	var out: Array[Rect2] = []
	var n := rows.size()
	if n == 0:
		return out
	var w := minf(56.0 * s, (vp.x - l * 2.0 - 12.0 * s * float(n - 1)) / float(n))
	var gap := 12.0 * s
	var total := w * float(n) + gap * float(n - 1)
	var x0 := (vp.x - total) * 0.5
	for i in n:
		out.append(Rect2(x0 + (w + gap) * float(i), 462.0 * s, w, w))
	return out


# --- input ----------------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.physical_keycode == KEY_ESCAPE or k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_SPACE):
			press_next()
		get_viewport().set_input_as_handled()
		return
	var kind := 0                                   # 1 press, 3 release
	var pos := Vector2.ZERO
	var id := 0
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		kind = 1 if t.pressed else 3
		pos = t.position
		id = t.index + 1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			kind = 1 if mb.pressed else 3
			pos = mb.position
			id = 100
	if kind != 0:
		handle_pointer(kind, pos, id)
	get_viewport().set_input_as_handled()           # while the card is open it owns every touch


## One pointer event (1 press, 3 release). A button fires on release inside the rectangle it was pressed in. Public so tests can drive it.
func handle_pointer(kind: int, pos: Vector2, id: int) -> bool:
	if not is_open:
		return false
	if kind == 1:
		if _down == -1:
			_down = id
		return true
	if kind == 3 and id == _down:
		_down = -1
		tap(pos)
	return true


func tap(pos: Vector2) -> bool:
	if next_rect().grow(8.0 * _s()).has_point(pos):
		press_next()
		return true
	if not second_action().is_empty() and second_rect().grow(6.0 * _s()).has_point(pos):
		press_second()
		return true
	return false


# --- drawing --------------------------------------------------------------------------------------------------------------------------

func _text(font: Font, pos: Vector2, text: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_canvas.draw_string(font, pos, text, align, width, size, col)


func _draw_all() -> void:
	if not is_open or current.is_empty():
		return
	var vp := _vp()
	var s := _s()
	var font := UiUtil.font()
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var l := _left()
	# header
	c.draw_rect(Rect2(0.0, 0.0, vp.x, 6.0 * s), UiUtil.CYAN)
	var head := "MISSION COMPLETE"
	_text(font, Vector2(l, 64.0 * s), head, int(UiUtil.fit_size(font, head, vp.x - l * 2.0, int(46.0 * s))), UiUtil.CYAN, vp.x - l * 2.0)
	var sub := "%s    MISSION %d" % [String(current.get("title", "")), int(current.get("n", 0))]
	_text(font, Vector2(l, 102.0 * s), sub, int(UiUtil.fit_size(font, sub, vp.x - l * 2.0, int(26.0 * s))), Color(1, 1, 1, 0.78), vp.x - l * 2.0)
	_draw_credits(c, font, s)
	_draw_reward(c, font, s)
	_draw_strip(c, font, s, vp)
	# the two lines: next weapon, next thing to do
	var dy := 0.0 if not strip_rects().is_empty() else -80.0 * s          # no strip after the tenth mission: the lines move up
	var wl := String(current.get("weapon_line", ""))
	if wl != "":
		_text(font, Vector2(l, 548.0 * s + dy), wl, int(UiUtil.fit_size(font, wl, vp.x * 0.62, int(26.0 * s))), Color(UiUtil.CYAN, 0.95), vp.x * 0.62)
	var nl := next_line()
	_text(font, Vector2(l, 588.0 * s + dy), nl, int(UiUtil.fit_size(font, nl, vp.x * 0.62, int(26.0 * s))), Color(UiUtil.AMBER, 0.95), vp.x * 0.62)
	var up := current.get("upgrade", {}) as Dictionary
	if not up.is_empty():
		var ut := "UPGRADE  %s %d  %d CR%s" % [Upgrades.title(up["id"]), int(up["level"]), int(up["price"]), "  READY" if bool(up["affordable"]) else "  (YOU HAVE %d)" % int(up["credits"])]
		_text(font, Vector2(l, 628.0 * s + dy), ut, int(UiUtil.fit_size(font, ut, vp.x * 0.62, int(24.0 * s))), Color(UiUtil.GREEN if bool(up["affordable"]) else Color(1, 1, 1, 0.6)), vp.x * 0.62)
	# buttons
	var sa := second_action()
	if not sa.is_empty():
		var sr := second_rect()
		var done := second_used
		c.draw_rect(sr, Color(0.05, 0.16, 0.1, 1.0) if done else Color(0.06, 0.1, 0.17, 1.0))
		c.draw_rect(sr, Color(UiUtil.GREEN if done else UiUtil.CYAN, 0.95), false, 3.0 * s)
		var st := String(sa["label"])
		_text(font, Vector2(sr.position.x, sr.position.y + sr.size.y * 0.5 + 9.0 * s), st, int(UiUtil.fit_size(font, st, sr.size.x - 16.0 * s, int(26.0 * s))), Color.WHITE, sr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var nr := next_rect()
	c.draw_rect(nr, Color(0.07, 0.4, 0.45, 1.0))
	c.draw_rect(nr, UiUtil.CYAN, false, 4.0 * s)
	_text(font, Vector2(nr.position.x, nr.position.y + nr.size.y * 0.5 + 13.0 * s), "NEXT", int(40.0 * s), Color.WHITE, nr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	MenuKit.glyph(c, &"play", Vector2(nr.end.x - 40.0 * s, nr.position.y + nr.size.y * 0.5), 14.0 * s, Color.WHITE, s)


func _draw_credits(c: Control, font: Font, s: float) -> void:
	var r := _col1()
	var credits := int(current.get("credits", 0))
	var shown_n := int(round(float(credits) * clampf(_t / COUNT_TIME, 0.0, 1.0)))
	c.draw_rect(r, PLATE)
	c.draw_rect(Rect2(r.position.x, r.position.y, 6.0 * s, r.size.y), UiUtil.AMBER)
	var num := "+%d" % shown_n
	_text(font, Vector2(r.position.x + 24.0 * s, r.position.y + 112.0 * s), num, int(UiUtil.fit_size(font, num, r.size.x - 40.0 * s, int(110.0 * s))), UiUtil.AMBER, r.size.x - 40.0 * s)
	_text(font, Vector2(r.position.x + 26.0 * s, r.position.y + 152.0 * s), "CREDITS", int(30.0 * s), Color(1, 1, 1, 0.9), r.size.x)
	var bonus := int(current.get("bonus", 0))
	if bonus > 0:
		_text(font, Vector2(r.position.x + 26.0 * s, r.position.y + 188.0 * s), "INCLUDES  %d MISSION BONUS" % bonus, int(UiUtil.fit_size(font, "INCLUDES  %d MISSION BONUS" % bonus, r.size.x - 40.0 * s, int(22.0 * s))), Color(UiUtil.AMBER, 0.8), r.size.x - 40.0 * s)
	# level and XP: tiny
	var lv := int(current.get("level", 1))
	var have := int(current.get("xp_have", 0))
	var need := int(current.get("xp_need", 0))
	var ly := r.position.y + 232.0 * s
	var lt := "LEVEL %d%s    +%d XP" % [lv, "  UP" if bool(current.get("level_up", false)) else "", int(current.get("xp", 0))]
	_text(font, Vector2(r.position.x + 26.0 * s, ly), lt, int(UiUtil.fit_size(font, lt, r.size.x - 40.0 * s, int(20.0 * s))), Color(1, 1, 1, 0.8), r.size.x - 40.0 * s)
	var bar := Rect2(r.position.x + 26.0 * s, ly + 12.0 * s, r.size.x - 52.0 * s, 8.0 * s)
	c.draw_rect(bar, Color(1, 1, 1, 0.14))
	var frac := clampf(float(have) / float(need), 0.0, 1.0) if need > 0 else 1.0
	c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), UiUtil.GREEN)


func _draw_reward(c: Control, font: Font, s: float) -> void:
	var r := _col2()
	var rw := reward()
	var kind := StringName(rw.get("kind", &"cash"))
	var tint: Color = KIND_COLOR.get(kind, UiUtil.CYAN)
	c.draw_rect(r, PLATE)
	c.draw_rect(r, Color(tint, 0.9), false, 3.0 * s)
	c.draw_rect(Rect2(r.position.x, r.position.y, 8.0 * s, r.size.y), tint)
	var cap := String(KIND_NAME.get(kind, "UNLOCKED"))
	_text(font, Vector2(r.position.x + 28.0 * s, r.position.y + 42.0 * s), cap, int(UiUtil.fit_size(font, cap, r.size.x - 60.0 * s, int(32.0 * s))), tint, r.size.x - 60.0 * s)
	var pic := Rect2(r.position.x + 24.0 * s, r.position.y + 62.0 * s, r.size.x * 0.46, r.size.y - 82.0 * s)
	c.draw_rect(pic, Color(0.07, 0.1, 0.17, 1.0))
	c.draw_rect(pic, Color(tint, 0.35), false, 1.5 * s)
	var id := StringName(rw.get("id", &""))
	if kind == &"weapon" or kind == &"crate":
		ItemIcons.draw_weapon(c, id, pic.grow(-8.0 * s), Color(1, 1, 1, 1.0))
	else:
		var gl: StringName = KIND_GLYPH.get(kind, &"check")
		var cp := pic.get_center()
		var rad := minf(pic.size.x, pic.size.y) * 0.3
		c.draw_circle(cp, rad * 1.25, Color(tint, 0.22))
		MenuKit.glyph(c, gl, cp, rad, tint.lerp(Color.WHITE, 0.4), s)
	if bool(rw.get("new", false)) or kind == &"weapon" or kind == &"crate":
		var tag := Rect2(pic.position.x + 6.0 * s, pic.position.y + 6.0 * s, 62.0 * s, 26.0 * s)
		c.draw_rect(tag, tint)
		_text(font, Vector2(tag.position.x, tag.position.y + 20.0 * s), "NEW", int(20.0 * s), Color(0.02, 0.04, 0.07), tag.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var tx := pic.end.x + 20.0 * s
	var tw := r.end.x - tx - 14.0 * s
	var nm := String(rw.get("title", ""))
	var ny := r.position.y + 120.0 * s
	_text(font, Vector2(tx, ny), nm, int(UiUtil.fit_size(font, nm, tw, int(40.0 * s))), Color.WHITE, tw)
	var subt := String(rw.get("sub", ""))
	if subt != "":
		_text(font, Vector2(tx, ny + 40.0 * s), subt, int(UiUtil.fit_size(font, subt, tw, int(22.0 * s))), Color(tint.lerp(Color.WHITE, 0.45), 0.95), tw)
	if rw.has("extra"):
		var ex := "+ MOD  %s" % String(Attachments.PARTS[StringName(rw["extra"])]["name"])
		_text(font, Vector2(tx, ny + 76.0 * s), ex, int(UiUtil.fit_size(font, ex, tw, int(22.0 * s))), Color(UiUtil.CYAN, 0.95), tw)


func _draw_strip(c: Control, font: Font, s: float, vp: Vector2) -> void:
	var rects := strip_rects()
	if rects.is_empty():
		return
	var rows: Array = current.get("ladder", []) as Array
	var done_n := 0
	for rw: Variant in rows:
		if bool((rw as Dictionary)["done"]):
			done_n += 1
	var head := "FIRST 10 MISSIONS  SOMETHING NEW EVERY TIME  %d / %d" % [done_n, rows.size()]
	_text(font, Vector2(rects[0].position.x, rects[0].position.y - 12.0 * s), head, int(UiUtil.fit_size(font, head, vp.x * 0.7, int(22.0 * s))), Color(1, 1, 1, 0.78), vp.x * 0.7)
	for i in rects.size():
		var rr := rects[i]
		var row := rows[i] as Dictionary
		var kind := StringName(row["kind"])
		var tint: Color = KIND_COLOR.get(kind, UiUtil.CYAN)
		var done := bool(row["done"])
		var now := bool(row["now"])
		c.draw_rect(rr, Color(tint, 0.30) if done else Color(1, 1, 1, 0.06))
		c.draw_rect(rr, Color(tint, 1.0 if now else (0.7 if done else 0.3)), false, (4.0 if now else 2.0) * s)
		MenuKit.glyph(c, KIND_GLYPH.get(kind, &"check"), rr.get_center(), rr.size.x * 0.28, Color(tint.lerp(Color.WHITE, 0.4), 1.0 if done else 0.45), s)
		if done and not now:
			MenuKit.glyph(c, &"check", rr.position + Vector2(rr.size.x - 12.0 * s, 12.0 * s), 7.0 * s, UiUtil.GREEN, s)
