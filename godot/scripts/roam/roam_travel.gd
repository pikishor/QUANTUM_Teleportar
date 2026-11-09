class_name RoamTravel
extends Node
## FAST TRAVEL between the QUANTUM PADS (wave 111). Stand on a pad you have found (on foot, within 6 m) and a small panel lists every other FOUND pad as a big button (each at least 64 px tall, in
## two columns): tap one and the hero QUANTUM TELEPORTs there (a flash, the sound, the camera snaps). The panel does not pause the game (pause only goes through Game.state) and closes when the
## hero walks off the pad, taps STAY, or arrives: the arrival pad stays quiet until the hero has stepped away from it, so two pads never bounce him back and forth.
## `destinations()`, `go(id)`, `panel_open` and `prompt` are what the tests read; `poll(dt, hero)` is driven by RoamWorld.

signal travelled(from_id: StringName, to_id: StringName)

const ON_R := 6.0
const LEAVE_R := 12.0
const COOLDOWN := 1.2

var world: RoamWorld
var prompt := ""
var panel_open := false
var here: StringName = &""                 ## the pad the panel is open for
var trips := 0

var _layer: CanvasLayer
var _quiet: StringName = &""               ## a pad that stays closed until the hero has left it (just arrived, or STAY)
var _cool := 0.0
var _root: Control
var _panel: PanelContainer
var _buttons: Dictionary = {}              ## destination pad id -> Button


func _init(w: RoamWorld = null) -> void:
	world = w
	name = "RoamTravel"


func reset() -> void:
	_close()
	_quiet = &""
	trips = 0


func _on_foot() -> bool:
	return WorldSteps.hero_vehicle() == null and not InteriorGameplay.active


## The pad within ON_R of the hero (found ones only), {} when none.
func pad_under(hero: Vector3) -> Dictionary:
	for p in RoamData.pads():
		if world != null and not world.pad_known(p["id"]):
			continue
		var pp: Vector3 = p["pos"]
		if RoamWorld.flat(pp, hero) < ON_R and absf(pp.y - hero.y) < 6.0:
			return p
	return {}


## The found pads other than `from_id`, nearest first from the hero: [{id, name, pos, d}].
func destinations(from_id: StringName, hero := Vector3.INF) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ref := hero
	var here_p := RoamData.pad(from_id)
	if not ref.is_finite() and not here_p.is_empty():
		ref = here_p["pos"]
	for p in RoamData.pads():
		if p["id"] == from_id or (world != null and not world.pad_known(p["id"])):
			continue
		var e: Dictionary = p.duplicate()
		e["d"] = RoamWorld.flat(p["pos"], ref) if ref.is_finite() else 0.0
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	return out


func poll(dt: float, hero: Vector3) -> void:
	_cool = maxf(0.0, _cool - dt)
	prompt = ""
	if _quiet != &"":
		var qp := RoamData.pad(_quiet)
		if qp.is_empty() or RoamWorld.flat(qp["pos"], hero) > LEAVE_R:
			_quiet = &""
	if world != null and world.busy():
		_close()
		return
	var p := pad_under(hero)
	if panel_open:
		var hp := RoamData.pad(here)
		if hp.is_empty() or not _on_foot() or RoamWorld.flat(hp["pos"], hero) > LEAVE_R:
			_close()
		return
	if p.is_empty() or not _on_foot() or _cool > 0.0 or p["id"] == _quiet:
		return
	if destinations(p["id"]).is_empty():
		prompt = "QUANTUM PAD  %s  FIND ANOTHER PAD TO TRAVEL" % String(p["name"])
		return
	_open(p)


func _open(p: Dictionary) -> void:
	here = p["id"]
	panel_open = true
	_build_panel(p)


func _close() -> void:
	panel_open = false
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_buttons.clear()
	here = &""


## Teleports the hero to found pad `to_id` from the pad he stands on. False when there is no such pad, it is not found, or he is not on a pad.
func go(to_id: StringName) -> bool:
	var dest := RoamData.pad(to_id)
	var pl := Game.player as Player
	if dest.is_empty() or pl == null or (world != null and not world.pad_known(to_id)):
		return false
	var from := here
	var from_pos := pl.global_position
	if from == &"":
		var u := pad_under(from_pos)
		from = u["id"] if not u.is_empty() else &""
	var dp: Vector3 = dest["pos"]
	FX.burst(from_pos + Vector3(0.0, 1.0, 0.0), Color(0.3, 0.94, 1.0), 18, 8.0, 0.6, 0.0)
	Sfx.play(&"blink", -3.0, 0.9)
	pl.teleport_to(dp + Vector3(0.0, 1.0, 0.0))
	FX.burst(dp + Vector3(0.0, 1.0, 0.0), Color(0.3, 0.94, 1.0), 18, 8.0, 0.6, 0.0)
	Game.say("QUANTUM TELEPORT  %s" % String(dest["name"]), 2.5)
	_quiet = to_id
	_cool = COOLDOWN
	trips += 1
	_close()
	travelled.emit(from, to_id)
	return true


## STAY: close the panel and keep this pad quiet until the hero steps off it.
func stay() -> void:
	_quiet = here
	_close()


func _build_panel(p: Dictionary) -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280.0, 720.0)
	var s := clampf(vp.y / 720.0, 0.75, 2.2)
	var h := maxf(64.0, 64.0 * s)
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 70
		_layer.name = "RoamTravelLayer"
		add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	var panel := PanelContainer.new()
	_panel = panel
	panel.anchor_left = 1.0                                       # on the right, vertically centred: the hero, the toast and the prompt line stay in view (render loop 1)
	panel.anchor_right = 1.0
	panel.anchor_top = 0.45
	panel.anchor_bottom = 0.45
	panel.offset_right = -20.0 * s
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.08, 0.93)
	sb.border_color = Color(0.3, 0.94, 1.0, 0.9)
	sb.set_border_width_all(maxi(int(2.0 * s), 2))
	sb.set_content_margin_all(14.0 * s)
	sb.corner_radius_top_left = int(10.0 * s)
	sb.corner_radius_bottom_right = int(10.0 * s)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", int(10.0 * s))
	panel.add_child(col)
	var title := Label.new()
	title.text = "QUANTUM PAD   %s" % String(p["name"])
	title.add_theme_font_size_override(&"font_size", int(28.0 * s))
	title.add_theme_color_override(&"font_color", Color(0.3, 0.94, 1.0))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "QUANTUM TELEPORT TO A FOUND PAD   %s" % world.counter_text() if world != null else "QUANTUM TELEPORT"
	sub.add_theme_font_size_override(&"font_size", int(20.0 * s))
	sub.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.8))
	col.add_child(sub)
	var scroll := ScrollContainer.new()                          # many found pads on a small phone: the list scrolls, the buttons stay at least 64 px tall
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var dests := destinations(p["id"])
	var rows := (dests.size() + 1) / 2
	var content_h := float(rows) * (h + 10.0 * s)
	scroll.custom_minimum_size = Vector2(0.0, minf(content_h, vp.y * 0.42))
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", int(10.0 * s))
	grid.add_theme_constant_override(&"v_separation", int(10.0 * s))
	scroll.add_child(grid)
	for d in dests:
		var b := _button("%s   %s" % [String(d["name"]), _km(float(d["d"]))], Vector2(340.0 * s, h), s, Color(0.3, 0.94, 1.0))
		var id: StringName = d["id"]
		b.pressed.connect(func() -> void: go(id))
		grid.add_child(b)
		_buttons[id] = b
	var stay_b := _button("STAY", Vector2(340.0 * s, h), s, Color(1.0, 0.72, 0.25))
	stay_b.pressed.connect(stay)
	col.add_child(stay_b)


func _button(text: String, size: Vector2, s: float, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override(&"font_size", int(22.0 * s))
	for st: StringName in [&"normal", &"hover", &"pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.12, 0.17, 0.95) if st == &"normal" else Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.35, 0.98)
		sb.border_color = tint
		sb.set_border_width_all(maxi(int(2.0 * s), 2))
		sb.set_content_margin_all(8.0 * s)
		b.add_theme_stylebox_override(st, sb)
	return b


static func _km(d: float) -> String:
	return "%.1f KM" % (d / 1000.0) if d >= 950.0 else "%d M" % int(round(d / 10.0) * 10.0)


## The panel's rectangle on screen (tests: it must fit the viewport at every size).
func panel_rect() -> Rect2:
	return _panel.get_global_rect() if _panel != null and is_instance_valid(_panel) else Rect2()


func button_ids() -> Array:
	return _buttons.keys()


func button_size(id: StringName) -> Vector2:
	var b: Button = _buttons.get(id)
	return b.custom_minimum_size if b != null else Vector2.ZERO
