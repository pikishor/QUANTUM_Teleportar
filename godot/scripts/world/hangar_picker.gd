class_name HangarPicker
extends CanvasLayer
## w129-airdraws: the HANGAR PLANE PICKER. While the hero stands on foot inside a hangar or an army shelter, a PLANES chip shows; a finger on it opens a list of every
## plane that fits through that door (wingspan and length against the opening and the floor), paged six at a time. A finger on a name rolls that plane onto the hangar
## apron in front of the open door, nose out, ready to ENTER (the plane picked before at the same hangar, if nobody flies it, goes back to the hangar crew). Plain Buttons: TouchButtons makes
## them answer a finger. Made by Hangars.Doors (AirDraws.old: no picker, the wave 128 hangars).
##   HangarPicker.instance   site_id()  (the hangar the hero is in, &"" outside)   open   kinds_for(site)   picked (site id -> Vehicle)

const PER_PAGE := 6
static var instance: HangarPicker

var chip: Button
var panel: PanelContainer
var title: Label
var grid: GridContainer
var prev_b: Button
var next_b: Button
var close_b: Button
var open := false
var page := 0
var picked := {}                         ## site id -> the Vehicle rolled out last
var _site := {}
var _kinds: Array[StringName] = []


static func kinds_for(site: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var dw := float(site["dw"])
	var depth := float((site["size"] as Vector3).x if site["door"] == &"e" else (site["size"] as Vector3).z)
	for k: StringName in PlaneRoster.KINDS:
		var sp: Dictionary = VehicleSpecs.SPECS.get(k, {})
		if sp.is_empty():
			continue
		var span := float(sp.get("span", sp.get("wid", 99.0)))
		if span <= dw - 2.0 and float(sp.get("len", 99.0)) <= depth - 6.0 and float(sp.get("hgt", 0.0)) <= float(site["dh"]) - 0.5:
			out.append(k)
	return out


func _ready() -> void:
	instance = self
	layer = 12
	name = "HangarPicker"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	chip = _button("PLANES", root)
	chip.pressed.connect(_toggle)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.08, 0.9)
	sb.border_color = Color(UiUtil.CYAN, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", sb)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	col.add_child(grid)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 14)
	col.add_child(row)
	prev_b = _button("<  PREV", row)
	prev_b.pressed.connect(func() -> void: _page(-1))
	close_b = _button("CLOSE", row)
	close_b.pressed.connect(close)
	next_b = _button("NEXT  >", row)
	next_b.pressed.connect(func() -> void: _page(1))
	panel.visible = false
	chip.visible = false


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


## The hangar or shelter the hero stands in on foot (&"" elsewhere or in a vehicle).
static func site_id() -> StringName:
	var p := Game.player as Node3D
	if not is_instance_valid(p) or p.get(&"vehicle") != null or not Hangars.on:
		return &""
	var lp := Airport.to_local(p.global_position)
	for s: Dictionary in Hangars.SITES:
		if Hangars.inside(s, lp):
			return s["id"]
	return &""


func _process(_dt: float) -> void:
	var sid := site_id() if Game.state == &"play" else &""
	if sid == &"":
		if open:
			close()
		chip.visible = false
		return
	_site = Hangars.site(sid)
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var fs := int(24.0 * s)
	chip.add_theme_font_size_override(&"font_size", fs)
	chip.custom_minimum_size = Vector2(170.0, 60.0) * s
	chip.size = chip.custom_minimum_size
	chip.position = Vector2(UiUtil.insets(vp).x + 200.0 * s, 18.0 * s)          # top left, beside the minimap: clear of the mission banner, the edge chips, the look swipe and the thumbs
	chip.visible = not open
	if open:
		_layout(vp, s)


func _toggle() -> void:
	if open:
		close()
	else:
		open_list()


func open_list() -> void:
	if _site.is_empty():
		return
	open = true
	page = 0
	_kinds = kinds_for(_site)
	_fill()
	panel.visible = true
	chip.visible = false


func close() -> void:
	open = false
	panel.visible = false


func _page(d: int) -> void:
	var pages := maxi(1, ceili(float(_kinds.size()) / float(PER_PAGE)))
	page = posmod(page + d, pages)
	_fill()


func _fill() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var pages := maxi(1, ceili(float(_kinds.size()) / float(PER_PAGE)))
	title.text = "%s   PLANES THAT FIT   %d / %d" % [String(_site.get("name", "HANGAR")), page + 1, pages]
	for i in range(page * PER_PAGE, mini(_kinds.size(), (page + 1) * PER_PAGE)):
		var k: StringName = _kinds[i]
		var b := _button(VehicleSpecs.name_of(k), grid)
		b.set_meta(&"kind", k)
		b.pressed.connect(pick.bind(k))
	prev_b.visible = pages > 1
	next_b.visible = pages > 1
	var vp := get_viewport().get_visible_rect().size
	_layout(vp, UiUtil.ui_scale(vp))


func _layout(vp: Vector2, s: float) -> void:
	var fs := int(22.0 * s)
	title.add_theme_font_size_override(&"font_size", fs)
	for b: Button in [prev_b, next_b, close_b]:
		b.add_theme_font_size_override(&"font_size", fs)
		b.custom_minimum_size = Vector2(150.0, 60.0) * s
	for b in grid.get_children():
		(b as Button).add_theme_font_size_override(&"font_size", int(20.0 * s))
		(b as Button).custom_minimum_size = Vector2(250.0, 64.0) * s
	panel.reset_size()
	panel.position = (vp - panel.size) * 0.5


## Rolls `kind` out of the hangar the hero is in: onto the apron in front of the door, nose out.
func pick(kind: StringName) -> Vehicle:
	if _site.is_empty():
		return null
	var vm := Game.vehicles as VehicleManager
	if vm == null:
		return null
	var sid: StringName = _site["id"]
	var old_v: Vehicle = picked.get(sid)
	if is_instance_valid(old_v) and old_v.active and not old_v.driver_is_player and absf(old_v.speed) < 1.0:
		vm._release(old_v)
	var df := Hangars.door_frame(_site)
	var out: Vector3 = df["out"]
	var ln := float(VehicleSpecs.SPECS[kind].get("len", 10.0))
	var lp: Vector3 = (df["c"] as Vector3) + out * (3.0 + ln * 0.5)           # rolled out onto the apron in front of the open door, nose out
	var h := -PI * 0.5 if _site["door"] == &"e" else PI                    # local heading: nose east (an east door) or south
	var w := Airport.to_world(lp)
	w.y = TerrainHeight.height_at(w.x, w.z)
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, w, Airport.heading_world(h))
	if v != null:
		v.set_meta(&"hold", true)
		v.set_meta(&"called", true)
		picked[sid] = v
	vm._count_fixed()
	close()
	Game.say("%s  READY  -  WALK UP AND ENTER" % VehicleSpecs.name_of(kind), 2.4)
	return v
