class_name GarageScreen
extends CanvasLayer
## The garage screen (E6, rebuilt on the UI kit in wave 109): one cut-corner panel, the kept car's PICTURE and name on the left with SAVE THIS CAR and the eight paint swatches under it, the
## four upgrade tracks (SPEED, ARMOUR, GRIP, WEAPON) on the right as rows with segmented level bars and the price, and CLOSE. Touch friendly: real Buttons (min 72 px tall), so touch and mouse both
## work; their faces are drawn by `_Face` children (kit panel, text, pips) so the look matches every other screen.
## Opening pauses through Game.state only (&"paused"); closing resumes &"play".
## API: open() · close_screen() · is_open() · refresh() · fit(vp) · buttons by name: Save, Close, Paint0..7, Up_speed, Up_armour, Up_grip, Up_weapon

signal closed

const W := 840.0
const H := 600.0
const UP_EFFECT := {&"speed": "TOP SPEED AND PICK-UP", &"armour": "MORE HIT POINTS", &"grip": "STICKS TO THE ROAD", &"weapon": "DAMAGE AND AMMO"}

var _root: Control
var _box: Control
var _open := false
var _resume := &"play"
var _paint_btns: Array[Button] = []
var _up_btns := {}
var _face: Control                      ## the panel, the car picture and the texts (one custom-drawn control behind the buttons)
var _credits_text := ""
var _info_text := ""


## The face of a button: drawn on top of the Button (mouse ignored) with the kit's panel, so a Button is one kit button.
class _Face extends Control:
	var kind := "button"                 ## "button", "up" (an upgrade row) or "paint"
	var label := ""
	var sub := ""
	var tint: Color = UiUtil.CYAN
	var level := 0
	var max_level := 3
	var price := 0
	var enabled := true
	var color: Color = Color.WHITE
	var on := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var f := UiUtil.font()
		var r := Rect2(Vector2.ZERO, size)
		var a := 1.0 if enabled else 0.45
		if kind == "paint":
			draw_rect(r, Color(color, a))
			draw_rect(r, Color(1, 1, 1, 0.9 if on else 0.25), false, 4.0 if on else 1.5)
			if on:
				UiKit.glyph(self, &"check", r.get_center(), 14.0, Color(0, 0, 0, 0.75), 1.0)
			return
		UiKit.panel(self, r, 1.0, tint, on, 9.0)
		draw_set_transform(Vector2.ZERO)
		if kind == "up":
			draw_string(f, Vector2(18.0, 34.0), label, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, 26, Color(1, 1, 1, 0.97 * a))
			draw_string(f, Vector2(18.0, 58.0), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.62, 15, Color(1, 1, 1, 0.55 * a))
			var seg := (size.x * 0.5 - float(max_level - 1) * 6.0) / float(max_level)
			for i in max_level:
				var sr := Rect2(18.0 + float(i) * (seg + 6.0), size.y - 22.0, seg, 10.0)
				draw_rect(sr, Color(tint, 0.95 * a) if i < level else Color(1, 1, 1, 0.14))
			var txt := "MAX" if price <= 0 else str(price)
			var col := UiUtil.AMBER if price <= 0 else (UiUtil.GREEN if enabled else Color(1, 1, 1, 0.5))
			var chip := Rect2(size.x - 150.0, 16.0, 134.0, size.y - 32.0)
			draw_rect(chip, Color(col, 0.18))
			draw_rect(chip, Color(col, 0.8 if enabled or price <= 0 else 0.3), false, 2.0)
			draw_string(f, Vector2(chip.position.x, chip.position.y + chip.size.y * 0.5 + 10.0), txt, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 28, Color(col.lerp(Color.WHITE, 0.3), 1.0))
		else:
			draw_string(f, Vector2(0.0, size.y * 0.5 + 10.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Color(1, 1, 1, 0.97 * a))


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.04, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_box = Control.new()                                          # the 840 x 600 design area, centred; `fit` scales it about its middle
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 0.5
	_box.anchor_bottom = 0.5
	_box.offset_left = -W * 0.5
	_box.offset_right = W * 0.5
	_box.offset_top = -H * 0.5
	_box.offset_bottom = H * 0.5
	_root.add_child(_box)
	_face = Control.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.draw.connect(_draw_face)
	_box.add_child(_face)
	var save := _button("Save", Vector2(24.0, 330.0), Vector2(372.0, 72.0), "SAVE THIS CAR", &"plus", UiUtil.CYAN)
	save.pressed.connect(_on_save)
	for i in VehicleSpecs.COLORS.size():                          # twelve swatches (round 6): four a row, three rows
		var b := Button.new()
		b.name = "Paint%d" % i
		b.position = Vector2(24.0 + float(i % 4) * 94.0, 406.0 + float(i / 4) * 66.0)
		b.size = Vector2(88.0, 64.0)
		b.custom_minimum_size = Vector2(88.0, 64.0)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		_box.add_child(b)
		var fc := _Face.new()
		fc.kind = "paint"
		fc.color = VehicleSpecs.COLORS[i]
		b.add_child(fc)
		b.pressed.connect(_on_paint.bind(i))
		_paint_btns.append(b)
	var y := 96.0
	for st in Garage.STATS:
		var ub := _button("Up_%s" % st, Vector2(424.0, y), Vector2(392.0, 84.0), String(Garage.LABELS[st]), &"", UiUtil.CYAN, "up")
		ub.pressed.connect(_on_upgrade.bind(st))
		_up_btns[st] = ub
		y += 94.0
	var close := _button("Close", Vector2(424.0, 482.0), Vector2(392.0, 72.0), "CLOSE", &"back", UiUtil.AMBER)
	close.pressed.connect(close_screen)


func _button(nm: String, pos: Vector2, sz: Vector2, text: String, _icon: StringName, tint: Color, kind := "button") -> Button:
	var b := Button.new()
	b.name = nm
	b.position = pos
	b.size = sz
	b.custom_minimum_size = Vector2(0, 72)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	_box.add_child(b)
	var fc := _Face.new()
	fc.kind = kind
	fc.label = text
	fc.tint = tint
	b.add_child(fc)
	return b


func _draw_face() -> void:
	var f := UiUtil.font()
	var panel := Rect2(0.0, 0.0, W, H)
	UiKit.panel(_face, panel, 1.0, UiUtil.CYAN, false, 18.0, true)
	_face.draw_string(f, Vector2(24.0, 52.0), "GARAGE", HORIZONTAL_ALIGNMENT_LEFT, 300.0, 40, Color(1, 1, 1, 0.98))
	_face.draw_line(Vector2(24.0, 64.0), Vector2(120.0, 64.0), UiUtil.MAGENTA, 3.0)
	_face.draw_circle(Vector2(W - 170.0, 40.0), 12.0, Color(UiUtil.AMBER, 0.95))
	_face.draw_string(f, Vector2(W - 150.0, 50.0), _credits_text, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 28, Color(UiUtil.AMBER, 1.0))
	# the kept car: its picture on a plate, its name under it
	var pic := Rect2(24.0, 88.0, 372.0, 190.0)
	_face.draw_rect(pic, Color(0.0, 0.0, 0.0, 0.3))
	_face.draw_rect(pic, Color(UiUtil.CYAN, 0.35), false, 1.5)
	var g := _garage()
	if g != null and g.has_car():
		var tex := ItemIcons.vehicle(g.kind)
		if tex != null:
			ItemIcons.draw_tex(_face, tex, pic.grow(-6.0))
	else:
		_face.draw_string(f, Vector2(pic.position.x, pic.position.y + pic.size.y * 0.5), "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, pic.size.x, 34, Color(1, 1, 1, 0.4))
	_face.draw_string(f, Vector2(24.0, 308.0), _info_text, HORIZONTAL_ALIGNMENT_LEFT, 372.0, 22, Color(UiUtil.CYAN, 0.97))
	_face.draw_string(f, Vector2(424.0, 82.0), "UPGRADES", HORIZONTAL_ALIGNMENT_LEFT, 300.0, 22, Color(UiUtil.AMBER, 0.97))
	_face.draw_string(f, Vector2(24.0, 568.0), "PAINT", HORIZONTAL_ALIGNMENT_LEFT, 200.0, 15, Color(1, 1, 1, 0.0))


## The 840 x 600 panel shrinks to fit a small screen (844 x 390 phone): scale about its centre, never above 1. Returns the scale used.
func fit(vp: Vector2) -> float:
	var k := clampf(minf((vp.x - 24.0) / W, (vp.y - 16.0) / H), 0.3, 1.0)
	_box.pivot_offset = Vector2(W * 0.5, H * 0.5)
	_box.scale = Vector2(k, k)
	return k


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or not (Game.state == &"play" or Game.state == &"paused"):
		return
	_resume = &"paused" if Game.state == &"paused" else &"play"
	Game.state = &"paused"
	_open = true
	visible = true
	fit(get_viewport().get_visible_rect().size)
	refresh()


## Close and resume.
func close_screen() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if Game.state == &"paused":
		Game.state = _resume
	closed.emit()


func _garage() -> Garage:
	if is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"get_garage"):
		return Game.vehicles.call(&"get_garage") as Garage
	return null


func _wallet() -> Object:
	return Game.progress


func refresh() -> void:
	var g := _garage()
	var w := _wallet()
	_credits_text = "%d" % (int(w.get(&"credits")) if w != null else 0)
	var driven: Variant = Game.vehicles.get(&"driven") if is_instance_valid(Game.vehicles) else null
	var save_btn := _box.find_child("Save", true, false) as Button
	save_btn.disabled = not (driven is Vehicle and Garage.can_keep(driven as Vehicle))
	(save_btn.get_child(0) as _Face).enabled = not save_btn.disabled
	if g == null or not g.has_car():
		_info_text = "EMPTY.  DRIVE A CAR AND SAVE IT."
	else:
		_info_text = "KEPT  %s" % String(g.kind).to_upper()
	for i in _paint_btns.size():
		_paint_btns[i].disabled = g == null or not g.has_car()
		var fc := _paint_btns[i].get_child(0) as _Face
		fc.enabled = not _paint_btns[i].disabled
		fc.on = g != null and g.has_car() and g.paint == i
		fc.queue_redraw()
	for st in Garage.STATS:
		var b := _up_btns[st] as Button
		var lv := g.level(st) if g != null else 0
		var pr := g.price(st) if g != null else 0
		b.disabled = g == null or not g.can_upgrade(st, w)
		var fc2 := b.get_child(0) as _Face
		fc2.level = lv
		fc2.max_level = Garage.MAX_LEVEL
		fc2.price = pr
		fc2.enabled = not b.disabled
		fc2.sub = String(UP_EFFECT.get(st, ""))
		fc2.queue_redraw()
	save_btn.get_child(0).queue_redraw()
	_face.queue_redraw()


func _on_save() -> void:
	if is_instance_valid(Game.vehicles) and Game.vehicles.call(&"save_driven"):
		Sfx.play(&"ui_tap")
	refresh()


func _on_paint(i: int) -> void:
	var g := _garage()
	if g != null and g.set_paint(i):
		var car := Game.vehicles.call(&"garage_car") as Vehicle if is_instance_valid(Game.vehicles) else null
		if car != null:
			car.paint_i = i
			car.visual.set_paint(VehicleSpecs.COLORS[i])
		Sfx.play(&"ui_tap")
	refresh()


func _on_upgrade(st: StringName) -> void:
	var g := _garage()
	if g != null and g.upgrade(st, _wallet()):
		var car := Game.vehicles.call(&"garage_car") as Vehicle if is_instance_valid(Game.vehicles) else null
		if car != null:
			car.apply_garage(g)
		Sfx.play(&"ui_tap")
	refresh()
