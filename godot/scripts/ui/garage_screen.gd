class_name GarageScreen
extends CanvasLayer
## E6 garage screen (touch friendly): SAVE CAR (the car being driven), paint swatches, four upgrade rows (SPEED, ARMOUR, GRIP, WEAPON) and CLOSE.
## Opening pauses through Game.state only (&"paused"); closing resumes &"play". Real Buttons (min 72 px tall), so touch and mouse both work.
## API: open() · close_screen() · is_open() · refresh() · buttons by name: Save, Close, Paint0..7, Up_speed, Up_armour, Up_grip, Up_weapon

signal closed

var _root: Control
var _box: VBoxContainer
var _title: Label
var _credits: Label
var _info: Label
var _open := false
var _resume := &"play"
var _paint_btns: Array[Button] = []
var _up_btns := {}


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -420.0
	box.offset_right = 420.0
	box.offset_top = -300.0
	box.offset_bottom = 300.0
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_box = box
	_title = _label(box, "GARAGE", 34, UiUtil.CYAN)
	_credits = _label(box, "", 26, UiUtil.AMBER)
	_info = _label(box, "", 24, Color.WHITE)
	var save := _button(box, "SAVE THIS CAR", &"Save")
	save.pressed.connect(_on_save)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for i in VehicleSpecs.COLORS.size():
		var b := Button.new()
		b.name = "Paint%d" % i
		b.custom_minimum_size = Vector2(96, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = VehicleSpecs.COLORS[i]
		sb.set_border_width_all(3)
		sb.border_color = Color(0, 0, 0, 0.6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(_on_paint.bind(i))
		row.add_child(b)
		_paint_btns.append(b)
	for st in Garage.STATS:
		var ub := _button(box, "", StringName("Up_%s" % st))
		ub.pressed.connect(_on_upgrade.bind(st))
		_up_btns[st] = ub
	var close := _button(box, "CLOSE", &"Close")
	close.pressed.connect(close_screen)


func _label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, nm: StringName) -> Button:
	var b := Button.new()
	b.name = String(nm)
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.add_theme_font_size_override("font_size", 26)
	parent.add_child(b)
	return b


## The 840 x 600 panel shrinks to fit a small screen (844 x 390 phone): scale about its centre, never above 1. Returns the scale used.
func fit(vp: Vector2) -> float:
	var k := clampf(minf((vp.x - 24.0) / 840.0, (vp.y - 16.0) / 600.0), 0.3, 1.0)
	_box.pivot_offset = Vector2(420.0, 300.0)
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
	_credits.text = "CREDITS  %d" % (int(w.get(&"credits")) if w != null else 0)
	var driven: Variant = Game.vehicles.get(&"driven") if is_instance_valid(Game.vehicles) else null
	var save_btn := _root.find_child("Save", true, false) as Button
	save_btn.disabled = not (driven is Vehicle and Garage.can_keep(driven as Vehicle))
	if g == null or not g.has_car():
		_info.text = "EMPTY.  DRIVE A CAR AND SAVE IT."
	else:
		_info.text = "KEPT  %s" % String(g.kind).to_upper()
	for i in _paint_btns.size():
		_paint_btns[i].disabled = g == null or not g.has_car()
		_paint_btns[i].modulate = Color(1, 1, 1, 1.0 if g != null and g.paint == i else 0.7)
	for st in Garage.STATS:
		var b := _up_btns[st] as Button
		var lv := g.level(st) if g != null else 0
		var pips := "#".repeat(lv) + "-".repeat(Garage.MAX_LEVEL - lv)
		var pr := g.price(st) if g != null else 0
		b.text = "%s  [%s]  %s" % [Garage.LABELS[st], pips, ("%d" % pr) if pr > 0 else "MAX"]
		b.disabled = g == null or not g.can_upgrade(st, w)


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
