class_name MapScreen
extends CanvasLayer
## Full-screen city map (owner round 3: "map improved but needs to be much better"). Reached by tapping the minimap, the pause menu MAP button, or key M. Pauses through Game.state only
## (&"paused"); closing resumes the previous state.
## - The WHOLE city is drawn at once, north up: roads (the main avenues brighter), every building footprint (colour by height), parks, the district tints and their names, so the first
##   look is a map of the city, not a black square. Cells you have not walked near (DISCOVER_R, a wide reveal that follows you fast on foot and in a car) sit under a dark fog: you still
##   see the street grid and the district outline, but no building detail, no markers and the zone name reads UNCHARTED.
## - ZOOM: pinch with two fingers (mouse wheel / trackpad on desktop), drag to pan, button `Zoom` cycles 1x / 2x / 4x, `Locate` centres on you. `zoom_f` is the continuous zoom (1 .. ZOOM_MAX),
##   `zoom` its nearest whole level, `view_center` the world (x, z) in the middle of the square frame.
## - YOU: an arrow with a view cone that points where you look (north up map).
## - GPS: the objective route (MapRoute.goal: your own waypoint, else the scripted step, else the side contract) drawn ALONG THE ROADS with its distance; the minimap draws the same line.
## - MARKERS with icons by shape and colour (MapIcons): MISSION, SIDE, JOBS (street races, fares, deliveries, stunts), SHOPS, GARAGE (garages and repair bays), WEAPONS (crates), HOME,
##   ITEMS. At the overview nearby markers of one kind merge into one badge with a count. Tap a marker: a route to it and its name; tap the waypoint again: removed. The left column is the
##   LEGEND and the filter in one: a chip per kind with its icon, name and count (`F_<kind>`).
## - DANGER: districts whose ruling camp is hostile to you, ambush events and the wanted search area are red (legend entry DANGER).
## Buttons by name: Close, Clear, Zoom, Locate, F_mission, F_side, F_job, F_shop, F_garage, F_weapon, F_home, F_items. The map area is the Control "Map" (tap = _tap(pos)).
## API: open() close_screen() is_open() discover(pos, radius) is_discovered(x, z) discovered_count() set_waypoint(v3) clear_waypoint() has_waypoint() world_to_map(x, z) map_to_world(p)
## marker_counts() -> {kind: n} of markers currently shown (fog + filters applied), danger_zones(), route_points(), set_zoom(z) cycle_zoom() zoom_by(f, focus) pan(by_world).

signal closed

const Districts := preload("res://scripts/world/city_districts.gd")
const CityEventsScript := preload("res://scripts/world/city_events.gd")

const CELLS := 32
const CELL := 40.0                                  ## metres per cell (CELLS * CELL = 1280 = 2 * CityLayout.HALF)
const HALF := CELLS * CELL * 0.5
const ZOOMS: Array[int] = [1, 2, 4]
const ZOOM_MAX := 8.0
const DRAG_PX := 14.0
const LOD_ZOOM := 2.0                              ## below this zoom the crowded kinds show only their nearest few
const LOD_KINDS: Array[StringName] = [&"interior", &"shop", &"garage", &"items", &"weapon", &"job"]
const LOD_NEAR := 3
const LOD_NEAR_JOB := 8
const START_HALF := 300.0                           ## metres: the original city (|x|, |z| <= this) is charted from the first second, so the map is not a black square with a dot (it was 6 %)
const DISCOVER_R := 150.0                           ## metres: how far around you the map charts itself (it was 70: 6 % after a walk)
const KINDS: Array[StringName] = [&"mission", &"side", &"interior", &"job", &"shop", &"garage", &"weapon", &"home", &"items"]
const KIND_LABEL := {&"mission": "MISSION", &"side": "SIDE", &"interior": "INTERIORS", &"job": "JOBS", &"shop": "SHOPS", &"garage": "GARAGE", &"weapon": "WEAPONS", &"home": "HOME", &"items": "ITEMS"}
const KIND_COLOR := {&"mission": Color(1.0, 0.75, 0.15), &"side": Color(0.2, 0.9, 1.0), &"interior": Color(0.62, 0.76, 1.0), &"job": Color(1.0, 0.45, 0.85), &"shop": Color(0.3, 1.0, 0.55), &"garage": Color(1.0, 0.5, 0.2),
	&"weapon": Color(1.0, 0.82, 0.3), &"home": Color(0.85, 0.9, 1.0), &"items": Color(0.75, 0.45, 1.0)}
const DANGER_COLOR := Color(1.0, 0.25, 0.25)
const SAVE_PATH := "user://map.cfg"
static var path_override := ""             ## DEMO MODE points the map at its own file (scripts/demo/demo_mode.gd); "" = SAVE_PATH
const GARAGE_TYPES: Array[StringName] = [&"warehouse", &"cargo_bay"]
const TAP_CLEAR_PX := 28.0
const MARKER_PICK_PX := 26.0
const CLUSTER_PX := 30.0
const COL_W := 212.0                                 ## base px: the legend column (left) and the button column (right)
const BTN_H := 64.0
const GAP := 6.0

var waypoint := Vector3.INF
var filters := {&"mission": true, &"side": true, &"interior": true, &"job": true, &"shop": true, &"garage": true, &"weapon": true, &"home": true, &"items": true}

var zoom_f := 1.0                                    ## continuous zoom: the square frame shows 2 * HALF / zoom_f metres across
var zoom: int:                                       ## the nearest whole level (1, 2, 4, ...), for the button text and tests
	get:
		return maxi(roundi(zoom_f), 1)
var view_center := Vector2.ZERO                      ## world (x, z) at the middle of the square frame
var selected := {}                                   ## the marker last tapped: {kind, pos, label}
var scan_log: Array[Dictionary] = []                 ## tests: {text, rect} of every label the map drew
var scan_on := false
var _placed: Array[Rect2] = []                      ## label boxes already drawn this frame (a new label that would overlap one is skipped)
var drawn := {}                                      ## tests: what the last draw produced {roads, lots, markers, labels, route, you, danger}

var _press := Vector2.INF
var _dragging := false
var _touches := {}                                   ## finger index -> position (pinch)
var _pinch_d0 := 0.0
var _pinch_z0 := 1.0
var _gesture := false                                ## a pinch happened since the last finger went down: its lift is not a tap
var _seen := PackedByteArray()
var _open := false
var _resume := &"play"
var _root: Control
var _map: Control
var _sub_text := ""                                ## the line beside the title: charted share and route length
var _zoom_btn: Button
var _btns := {}
var _side_btns: Array[Button] = []
var _rect := Rect2()                                 ## the square frame that holds the whole city at zoom 1 (control px)
var _counts := {}
var _t := 0.0
var _anim := 0.0
var _dirty := false
var _lots: Array = []
var _lots_owner := 0
var _route := PackedVector3Array()
var _route_goal := Vector3.INF
var _charted := 0
var _x0 := 12.0
var _route_m := 0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_seen.resize(CELLS * CELLS)
	_load()
	reveal_start()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.015, 0.03, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_map = Control.new()
	_map.name = "Map"
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.clip_contents = true
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	_root.add_child(_map)
	_map.resized.connect(_layout)
	for k in KINDS:
		var b := _chip(k)
		_btns[k] = b
	_zoom_btn = _button("ZOOM 1X", &"Zoom")
	_zoom_btn.pressed.connect(cycle_zoom)
	var loc := _button("YOU", &"Locate")
	loc.pressed.connect(locate)
	var clr := _button("CLEAR", &"Clear")
	clr.pressed.connect(clear_waypoint)
	var cls := _button("CLOSE", &"Close")
	cls.pressed.connect(close_screen)
	_side_btns = [cls, _zoom_btn, loc, clr]
	_layout()


func _s() -> float:
	return UiUtil.ui_scale(get_viewport().get_visible_rect().size)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _style(fill: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 54.0
	sb.content_margin_right = 8.0
	return sb


func _button(text: String, nm: StringName) -> Button:
	var b := Button.new()
	b.name = String(nm)
	b.text = text
	b.custom_minimum_size = Vector2(64, BTN_H)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	var base := Color(0.03, 0.07, 0.1, 0.92)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := _style(base if st != "pressed" else Color(0.1, 0.2, 0.26, 0.95), Color(UiUtil.CYAN, 0.7), 2)
		sb.content_margin_left = 8.0
		b.add_theme_stylebox_override(st, sb)
	_root.add_child(b)
	return b


## A legend chip: icon, name and count; a toggle (pressed = shown).
func _chip(k: StringName) -> Button:
	var b := _button(String(KIND_LABEL[k]), StringName("F_%s" % k))
	b.toggle_mode = true
	b.button_pressed = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var col: Color = KIND_COLOR[k]
	for st in ["normal", "hover"]:
		b.add_theme_stylebox_override(st, _style(Color(0.02, 0.04, 0.06, 0.9), Color(col, 0.35), 2))
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, _style(Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.95), col, 2))
	b.pressed.connect(_on_filter.bind(k))
	b.draw.connect(func() -> void: MapIcons.draw(b, k, Vector2(28.0, b.size.y * 0.5), 15.0, col if b.button_pressed else Color(col, 0.4)))
	return b


## Places the title, the legend column (left) and the button column (right) inside the safe area.
func _layout() -> void:
	if _map == null or _zoom_btn == null or _side_btns.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var x0 := ins.x + 12.0 * s
	_x0 = x0
	var y := 62.0 * s
	for k in KINDS:
		var b: Button = _btns[k]
		b.position = Vector2(x0, y)
		b.size = Vector2(COL_W * s, BTN_H * s)
		b.add_theme_font_size_override("font_size", int(22.0 * s))
		y += (BTN_H + 2.0) * s
	var rx := vp.x - ins.y - 12.0 * s - 164.0 * s
	var ry := 8.0 * s
	for b: Button in _side_btns:
		b.position = Vector2(rx, ry)
		b.size = Vector2(164.0 * s, BTN_H * s)
		b.add_theme_font_size_override("font_size", int(22.0 * s))
		ry += (BTN_H + GAP + 2.0) * s
	_update_rect()


# ---------------------------------------------------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_anim += delta
	if _open:
		if _t >= 0.2:
			_t = 0.0
			_refresh_chips()
			_map.queue_redraw()
		return
	if _t < 0.5:
		return
	_t = 0.0
	if Game.state == &"play" and is_instance_valid(Game.player):
		discover(Game.player.global_position)
	if _dirty:
		_save()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_M:
		if _open:
			close_screen()
		else:
			open()
		get_viewport().set_input_as_handled()


static func cell_of(x: float, z: float) -> int:
	var cx := clampi(int(floor((x + HALF) / CELL)), 0, CELLS - 1)
	var cz := clampi(int(floor((z + HALF) / CELL)), 0, CELLS - 1)
	return cz * CELLS + cx


static func cell_center(i: int) -> Vector2:
	return Vector2(-HALF + (i % CELLS + 0.5) * CELL, -HALF + (i / CELLS + 0.5) * CELL)


## Marks every cell whose centre is within `radius` + half a cell of pos.
func discover(pos: Vector3, radius := DISCOVER_R) -> void:
	if _seen.size() != CELLS * CELLS:
		_seen.resize(CELLS * CELLS)
	var c0 := cell_of(pos.x - radius - CELL, pos.z - radius - CELL)
	var c1 := cell_of(pos.x + radius + CELL, pos.z + radius + CELL)
	for cz in range(c0 / CELLS, c1 / CELLS + 1):
		for cx in range(c0 % CELLS, c1 % CELLS + 1):
			var i := cz * CELLS + cx
			if _seen[i] == 0 and cell_center(i).distance_to(Vector2(pos.x, pos.z)) <= radius + CELL * 0.5:
				_seen[i] = 1
				_dirty = true


func is_discovered(x: float, z: float) -> bool:
	return _seen.size() == CELLS * CELLS and _seen[cell_of(x, z)] == 1


func discovered_count() -> int:
	var n := 0
	for v in _seen:
		n += int(v)
	return n


func district_discovered(d: int) -> bool:
	for i in CELLS * CELLS:
		if _seen[i] == 1:
			var c := cell_center(i)
			if Districts.at(c.x, c.y) == d:
				return true
	return false


## A cell of this zone (0..3 core districts, 4..7 outer zones) has been walked near.
func zone_discovered(zone: int) -> bool:
	for i in CELLS * CELLS:
		if _seen[i] == 1:
			var c := cell_center(i)
			if Districts.zone_at(c.x, c.y) == zone:
				return true
	return false


## Where a zone's name is written: the landmark spot of a core district, the middle of the ring side of an outer zone.
func _zone_label_pos(zone: int) -> Vector2:
	if zone < Districts.COUNT:
		var t: Vector2 = Districts.LANDMARK_TARGETS[zone]
		return t + Vector2(0.0, -CityLayout.CORE_HALF * 0.3)
	var mid := (CityLayout.HALF + CityLayout.CORE_HALF) * 0.5
	match zone:
		Districts.DOCKYARDS:
			return Vector2(0.0, -mid)
		Districts.GROW_FIELDS:
			return Vector2(0.0, mid)
		Districts.AMBER_TERRACES:
			return Vector2(mid, 0.0)
	return Vector2(-mid, 0.0)


func set_waypoint(w: Vector3) -> void:
	waypoint = Vector3(clampf(w.x, -HALF, HALF), 0.0, clampf(w.z, -HALF, HALF))
	selected = {}
	_dirty = true
	_rebuild_route()
	if _map != null:
		_map.queue_redraw()


func clear_waypoint() -> void:
	waypoint = Vector3.INF
	selected = {}
	_dirty = true
	_rebuild_route()
	if _map != null:
		_map.queue_redraw()


func has_waypoint() -> bool:
	return waypoint.is_finite()


func _on_filter(k: StringName) -> void:
	filters[k] = (_btns[k] as Button).button_pressed
	_map.queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------
# open / close
# ---------------------------------------------------------------------------------------------------------------------

func is_open() -> bool:
	return _open


func open() -> void:
	if _open or not (Game.state == &"play" or Game.state == &"paused"):
		return
	_resume = &"paused" if Game.state == &"paused" else &"play"
	Game.state = &"paused"
	if is_instance_valid(Game.player):
		discover(Game.player.global_position)
	_open = true
	visible = true
	_layout()
	set_zoom(1)
	_load_lots()
	_rebuild_route()
	_refresh_chips()
	_map.queue_redraw()


func close_screen() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_touches.clear()
	_save()
	if Game.state == &"paused":
		Game.state = _resume
	closed.emit()


func _load_lots() -> void:
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	var lay: Variant = w.get("layout") if w != null else null
	var id := w.get_instance_id() if w != null else 0
	if lay is CityLayout and (_lots.is_empty() or _lots_owner != id):
		_lots = (lay as CityLayout).lots
		_lots_owner = id


# ---------------------------------------------------------------------------------------------------------------------
# map space
# ---------------------------------------------------------------------------------------------------------------------

func _update_rect() -> void:
	if _map == null:
		return
	var sz := _map.size
	var side := maxf(minf(sz.x, sz.y), 1.0)
	_rect = Rect2((sz.x - side) * 0.5, (sz.y - side) * 0.5, side, side)


## Metres across the square frame at the current zoom.
func span() -> float:
	return 2.0 * HALF / zoom_f


## World (x, z) of the square frame's upper left corner.
func _view_origin() -> Vector2:
	return view_center - Vector2(span(), span()) * 0.5


func world_to_map(x: float, z: float) -> Vector2:
	return _rect.position + ((Vector2(x, z) - _view_origin()) / span()) * _rect.size


func map_to_world(p: Vector2) -> Vector3:
	var u := (p - _rect.position) / _rect.size
	var w := _view_origin() + u * span()
	return Vector3(clampf(w.x, -HALF, HALF), 0.0, clampf(w.y, -HALF, HALF))


## Next zoom level: whole map, then 2x and 4x around you (the hero, or the map centre when no hero exists).
func cycle_zoom() -> void:
	set_zoom(ZOOMS[(ZOOMS.find(zoom) + 1) % ZOOMS.size()] if ZOOMS.has(zoom) else 1)


func set_zoom(z: int) -> void:
	zoom_f = float(z) if ZOOMS.has(z) else 1.0
	if zoom_f <= 1.0:
		view_center = Vector2.ZERO
	else:
		locate()
		return
	_after_zoom()


## Centre the view on the hero.
func locate() -> void:
	if is_instance_valid(Game.player):
		var pp: Vector3 = Game.player.global_position
		view_center = Vector2(pp.x, pp.z)
	_after_zoom()


func _after_zoom() -> void:
	_clamp_view()
	if _zoom_btn != null:
		_zoom_btn.text = "ZOOM %dX" % zoom
	if _map != null:
		_map.queue_redraw()


## Multiply the zoom by `f`, keeping the world point under the screen position `focus` where it is (a pinch zooms into the fingers).
func zoom_by(f: float, focus := Vector2.INF) -> void:
	var before := Vector2.ZERO
	var use_focus := focus.is_finite() and _rect.size.x > 1.0
	if use_focus:
		before = _view_origin() + ((focus - _rect.position) / _rect.size) * span()
	zoom_f = clampf(zoom_f * f, 1.0, ZOOM_MAX)
	if use_focus:
		var after_o := before - ((focus - _rect.position) / _rect.size) * span()
		view_center = after_o + Vector2(span(), span()) * 0.5
	_after_zoom()


func pan(by_world: Vector2) -> void:
	view_center += by_world
	_clamp_view()
	if _map != null:
		_map.queue_redraw()


func _clamp_view() -> void:
	var lim := HALF - span() * 0.5
	view_center = Vector2(clampf(view_center.x, -lim, lim), clampf(view_center.y, -lim, lim))


func _on_map_input(event: InputEvent) -> void:
	# pinch: two fingers
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			_touches[te.index] = te.position
			if _touches.size() == 2:
				_start_pinch()
		else:
			var was_two := _touches.size() >= 2
			_touches.erase(te.index)
			if was_two:
				_gesture = true
				_press = Vector2.INF
				_dragging = false
				if _touches.size() == 1:
					_press = (_touches.values()[0] as Vector2)
			elif _touches.is_empty() and _gesture:
				_gesture = false
				return
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		_touches[de.index] = de.position
		if _touches.size() >= 2:
			_update_pinch(de.relative)
			return
	elif event is InputEventMagnifyGesture:
		var me := event as InputEventMagnifyGesture
		zoom_by(me.factor, me.position)
		return
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.25, mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(0.8, mb.position)
			return
	if _touches.size() >= 2:
		return
	var p := Vector2.INF
	var down := false
	var up := false
	var drag := Vector2.ZERO
	if event is InputEventScreenTouch:
		p = (event as InputEventScreenTouch).position
		down = (event as InputEventScreenTouch).pressed
		up = not down
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		p = (event as InputEventMouseButton).position
		down = (event as InputEventMouseButton).pressed
		up = not down
	elif event is InputEventScreenDrag:
		p = (event as InputEventScreenDrag).position
		drag = (event as InputEventScreenDrag).relative
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		p = (event as InputEventMouseMotion).position
		drag = (event as InputEventMouseMotion).relative
	if not p.is_finite():
		return
	if down:
		_press = p
		_dragging = false
	elif drag != Vector2.ZERO and _press.is_finite():
		if not _dragging and p.distance_to(_press) > DRAG_PX * _s():
			_dragging = true
		if _dragging:
			pan(-drag / _rect.size.x * span())
	elif up and _press.is_finite():
		if not _dragging:
			_tap_at(p)
		_press = Vector2.INF
		_dragging = false


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch_d0 = maxf((pts[0] as Vector2).distance_to(pts[1] as Vector2), 1.0)
	_pinch_z0 = zoom_f
	_gesture = true
	_press = Vector2.INF
	_dragging = false


## A pinch step: the zoom follows the distance between the first two fingers, the view follows their midpoint.
func _update_pinch(_rel: Vector2) -> void:
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var d := maxf(a.distance_to(b), 1.0)
	var target := clampf(_pinch_z0 * d / _pinch_d0, 1.0, ZOOM_MAX)
	zoom_by(target / zoom_f, (a + b) * 0.5)


## A finger lift without a drag: a marker under it is selected (a route to it), otherwise the waypoint goes there.
func _tap_at(p: Vector2) -> void:
	var mk := marker_at(p)
	if not mk.is_empty():
		var pos: Vector3 = mk["pos"]
		if has_waypoint() and Vector2(waypoint.x - pos.x, waypoint.z - pos.z).length() < 1.0:
			clear_waypoint()
		else:
			set_waypoint(pos)
			selected = mk
		Sfx.play(&"ui_tap")
		return
	_tap(p)


## A tap at control position p: on the waypoint removes it, on the map places it.
func _tap(p: Vector2) -> void:
	if _map.size.x <= 0.0 or p.x < 0.0 or p.y < 0.0 or p.x > _map.size.x or p.y > _map.size.y:
		return
	var w := _view_origin() + ((p - _rect.position) / _rect.size) * span()
	if absf(w.x) > HALF or absf(w.y) > HALF:
		return                                            # the dark margin outside the city
	if has_waypoint() and world_to_map(waypoint.x, waypoint.z).distance_to(p) <= _tap_clear_px():
		clear_waypoint()
	else:
		set_waypoint(map_to_world(p))
	Sfx.play(&"ui_tap")


func _tap_clear_px() -> float:
	return TAP_CLEAR_PX * _s()


# ---------------------------------------------------------------------------------------------------------------------
# markers
# ---------------------------------------------------------------------------------------------------------------------

## All markers of the world: [{kind, pos: Vector3, fog: bool (hidden under fog), label}], before filters.
func collect_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: Node = Game.missions
	if is_instance_valid(m):
		var camp: Object = m.get("campaign")
		if camp != null:
			var wp: Dictionary = camp.call(&"waypoint")
			if wp.has("pos"):
				out.append({"kind": &"mission", "pos": wp["pos"], "fog": false, "label": "MISSION"})
			else:
				var g: Variant = camp.get("guide")
				if g is MissionGuide:
					var gw: Dictionary = (g as MissionGuide).waypoint()
					if gw.has("pos"):
						out.append({"kind": &"mission", "pos": gw["pos"], "fog": false, "label": "NEXT STEP"})
		var con: Object = m.get("contracts")
		if con != null and StringName(con.get("state")) in [&"offered", &"active"]:
			var cp: Vector3 = con.get("pos")
			if cp.is_finite():
				out.append({"kind": &"side", "pos": cp, "fog": false, "label": "SIDE JOB"})
	if is_instance_valid(Game.world):
		for d: Dictionary in Game.world.get("doors"):
			var t: StringName = d["type"]
			var kind := &""
			if GARAGE_TYPES.has(t):
				kind = &"garage"
			elif InteriorData.has_vendor(t):
				kind = &"shop"
			elif InteriorData.MISSION_TYPES.has(t):
				kind = &"interior"
			if kind != &"":
				var p: Vector3 = d["pos"]
				out.append({"kind": kind, "pos": p, "fog": true, "label": InteriorData.title(t)})
	var prog := Game.progress as Progress
	for sh: Dictionary in Safehouses.markers(prog):
		out.append({"kind": &"home", "pos": sh["pos"], "fog": false, "label": "SAFEHOUSE"})      # owned safehouses: fast-save points
	if prog != null and prog.collectibles != null:
		var spots := Collectibles.spots()
		for i in spots.size():
			if not prog.collectibles.is_collected(i):
				out.append({"kind": &"items", "pos": spots[i], "fog": true, "label": "SHARD"})
	var fr: Freedom = Freedom.current
	if fr != null:
		var jm: Variant = fr.jobs.get("_marker_pos") if fr.jobs != null else null
		if jm is Array:
			for mk: Dictionary in jm as Array:
				out.append({"kind": &"job", "pos": mk["pos"], "fog": true, "label": String(mk.get("kind", &"job")).to_upper().replace("_", " ")})
		if fr.crates != null:
			for i in int(fr.crates.call(&"count")):
				out.append({"kind": &"weapon", "pos": WeaponLadder.crate_pos(i), "fog": true, "label": "WEAPON CRATE"})
		if fr.repairs != null:
			for i in int(fr.repairs.call(&"count")):
				out.append({"kind": &"garage", "pos": fr.repairs.call(&"pos", i), "fog": true, "label": "REPAIR BAY"})
	return out


## The overview shows what a player needs, not 600 icons (director review): the objective, side jobs and homes always, and of the crowded kinds (INTERIORS,
## SHOPS, GARAGE, ITEMS, WEAPONS, JOBS) only the LOD_NEAR (jobs: LOD_NEAR_JOB) nearest to the hero. Zoomed in (zoom_f >= LOD_ZOOM) every marker of an enabled kind is drawn.
func lod_markers(list: Array[Dictionary]) -> Array[Dictionary]:
	if zoom_f >= LOD_ZOOM:
		return list
	var from := Vector2.ZERO
	if is_instance_valid(Game.player):
		from = Vector2(Game.player.global_position.x, Game.player.global_position.z)
	var out: Array[Dictionary] = []
	var crowded := {}
	for mk in list:
		if LOD_KINDS.has(mk["kind"]):
			var p: Vector3 = mk["pos"]
			if not crowded.has(mk["kind"]):
				crowded[mk["kind"]] = []
			(crowded[mk["kind"]] as Array).append([Vector2(p.x, p.z).distance_squared_to(from), mk])
		else:
			out.append(mk)
	for k: StringName in crowded:
		var arr: Array = crowded[k]
		arr.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for i in mini(arr.size(), LOD_NEAR_JOB if k == &"job" else LOD_NEAR):
			out.append(arr[i][1])
	return out


## Markers shown right now: filter on, and (for fogged kinds) the cell discovered.
func visible_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mk in collect_markers():
		var p: Vector3 = mk["pos"]
		if not bool(filters.get(mk["kind"], true)):
			continue
		if bool(mk["fog"]) and not is_discovered(p.x, p.z):
			continue
		out.append(mk)
	return out


func marker_counts() -> Dictionary:
	var c := {}
	for k in KINDS:
		c[k] = 0
	for mk in visible_markers():
		c[mk["kind"]] = int(c[mk["kind"]]) + 1
	return c


## The marker nearest to the screen position p within MARKER_PICK_PX, {} when none.
func marker_at(p: Vector2) -> Dictionary:
	var best := {}
	var bd := MARKER_PICK_PX * _s()
	for mk in lod_markers(visible_markers()):
		var pw: Vector3 = mk["pos"]
		var d := world_to_map(pw.x, pw.z).distance_to(p)
		if d <= bd:
			bd = d
			best = mk
	return best


func _refresh_chips() -> void:
	_counts = marker_counts()
	for k in KINDS:
		var b: Button = _btns[k]
		var n := int(_counts.get(k, 0))
		var t := Tr.t(String(KIND_LABEL[k])) if LOD_KINDS.has(k) else "%s  %d" % [Tr.t(String(KIND_LABEL[k])), n]
		if b.text != t:
			b.text = t
	if _map != null:
		_charted = roundi(100.0 * float(discovered_count()) / float(CELLS * CELLS))
		var t2 := "%d%% CHARTED" % _charted + (("    ROUTE %d M" % _route_m) if _route.size() >= 2 else "")
		_sub_text = t2


# ---------------------------------------------------------------------------------------------------------------------
# danger and the route
# ---------------------------------------------------------------------------------------------------------------------

## Danger zones: [{kind: &"district"|&"ambush"|&"search", pos: Vector2 (x, z), radius: metres, label}]. A district whose ruling camp is HOSTILE to you; ambush / rift events; while
## wanted, the police search area round you.
func danger_zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prog: Object = Game.progress if is_instance_valid(Game.progress) else null
	if prog != null:
		for d in Districts.COUNT:
			if Factions.status(prog, Factions.primary(d)) == Factions.Status.HOSTILE:
				var half := CityLayout.CORE_HALF
				var rx0 := -half if (d == Districts.MARKET or d == Districts.SLUMS) else 0.0       # the district is one quadrant of the core (see city_districts.gd)
				var rz0 := -half if (d == Districts.MARKET or d == Districts.FOUNDRY) else 0.0
				out.append({"kind": &"district", "pos": Vector2(rx0 + half * 0.5, rz0 + half * 0.5), "radius": half * 0.5, "rect": Rect2(rx0, rz0, half, half), "label": "HOSTILE  %s" % Factions.title(Factions.primary(d)), "district": d})
	var cev: Object = CityEventsScript.current
	if is_instance_valid(cev):
		for mk: Dictionary in cev.markers():
			if mk["kind"] == &"ambush" or mk["kind"] == &"rift":
				var ep: Vector3 = mk["pos"]
				out.append({"kind": &"ambush", "pos": Vector2(ep.x, ep.z), "radius": maxf(float(mk["radius"]), 24.0), "label": "AMBUSH" if mk["kind"] == &"ambush" else "RIFT"})
	if is_instance_valid(Game.player) and Game.heat > 0.05:
		var pp: Vector3 = Game.player.global_position
		out.append({"kind": &"search", "pos": Vector2(pp.x, pp.z), "radius": 140.0 + 160.0 * clampf(Game.heat, 0.0, 1.0), "label": "WANTED"})
	return out


## The goal the route leads to, Vector3.INF when none.
func route_goal() -> Vector3:
	return MapRoute.goal(waypoint)


func _rebuild_route() -> void:
	_route_goal = route_goal()
	_route = PackedVector3Array()
	if _route_goal.is_finite() and is_instance_valid(Game.player):
		_route = MapRoute.route(Game.player.global_position, _route_goal)
		_route_m = roundi(MapRoute.length(_route))


## The GPS polyline (empty when there is no goal).
func route_points() -> PackedVector3Array:
	return _route


# ---------------------------------------------------------------------------------------------------------------------
# drawing (paused screen: redrawn at 5 Hz while open, lots and roads are culled to the view)
# ---------------------------------------------------------------------------------------------------------------------

func _label_out(font: Font, pos: Vector2, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, avoid := false) -> bool:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else pos.x
	var box := Rect2(x - 3.0, pos.y - size * 0.8, w + 6.0, size * 1.05)
	if avoid:
		for r in _placed:
			if r.intersects(box):
				return false
	_placed.append(box)
	_map.draw_string_outline(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(size / 5, 3), Color(0.0, 0.02, 0.04, 0.95))
	_map.draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if scan_on:
		scan_log.append({"text": text, "rect": Rect2(x, pos.y - size * 0.78, w, size)})
	return true


func _draw_map() -> void:
	if _rect.size.x < 8.0:
		return
	var font := ThemeDB.fallback_font
	var s := _s()
	var sz := _map.size
	var view := Rect2(Vector2.ZERO, sz)
	var ppm := _rect.size.x / span()                       # screen px per metre
	var origin := _view_origin()
	_placed.clear()
	if scan_on:
		scan_log.clear()
	drawn = {"roads": 0, "lots": 0, "markers": 0, "labels": 0, "route": false, "you": false, "danger": 0}
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.015, 0.03, 1.0))
	var city := Rect2(world_to_map(-HALF, -HALF), Vector2(2.0 * HALF, 2.0 * HALF) * ppm)
	_map.draw_rect(city.grow(4.0 * s), Color(UiUtil.CYAN, 0.18), false, 2.0 * s)
	_map.draw_rect(city, Color(0.02, 0.04, 0.06, 1.0))
	# district tint per block (the zone accent), under everything
	var pitch := CityLayout.PITCH
	for bi in CityLayout.N:
		for bj in CityLayout.N:
			var bx := CityLayout.road_center(bi) + pitch * 0.5
			var bz := CityLayout.road_center(bj) + pitch * 0.5
			var br := Rect2(world_to_map(bx - CityLayout.BLOCK * 0.5, bz - CityLayout.BLOCK * 0.5), Vector2(CityLayout.BLOCK, CityLayout.BLOCK) * ppm)
			if not br.intersects(view):
				continue
			var acc: Color = Districts.palette(Districts.look_at(bx, bz))["accent"]
			var k := 0.15 if Districts.zone_at(bx, bz) < Districts.COUNT else 0.09
			_map.draw_rect(br, Color(acc.r * k, acc.g * k, acc.b * k, 1.0))
	# roads: the whole grid, avenues every fourth line brighter
	var rw := CityLayout.ROAD * ppm
	for i in CityLayout.N + 1:
		var c := CityLayout.road_center(i)
		var main := i % 4 == 0
		var col := Color(0.34, 0.43, 0.52, 1.0) if main else Color(0.22, 0.29, 0.36, 1.0)
		var w := maxf(rw * (1.25 if main else 1.0), 2.0)
		var a := world_to_map(c, -HALF - CityLayout.ROAD * 0.5)
		var b := world_to_map(c, HALF + CityLayout.ROAD * 0.5)
		if a.x + w > 0.0 and a.x - w < sz.x:
			_map.draw_rect(Rect2(a.x - w * 0.5, a.y, w, b.y - a.y), col)
			drawn["roads"] = int(drawn["roads"]) + 1
		var a2 := world_to_map(-HALF - CityLayout.ROAD * 0.5, c)
		var b2 := world_to_map(HALF + CityLayout.ROAD * 0.5, c)
		if a2.y + w > 0.0 and a2.y - w < sz.y:
			_map.draw_rect(Rect2(a2.x, a2.y - w * 0.5, b2.x - a2.x, w), col)
			drawn["roads"] = int(drawn["roads"]) + 1
	# parks and open lots
	var w3: Object = Game.world if is_instance_valid(Game.world) else null
	var lay: Variant = w3.get("layout") if w3 != null else null
	if lay is CityLayout:
		for pz: Vector2 in (lay as CityLayout).plazas:
			var pr := Rect2(world_to_map(pz.x - 13.0, pz.y - 13.0), Vector2(26.0, 26.0) * ppm)
			if pr.intersects(view):
				_map.draw_rect(pr, Color(0.08, 0.24, 0.17, 1.0))
	# building footprints
	for lot: Variant in _lots:
		var lr: Rect2 = (lot as CityLayout.Lot).rect
		var sr := Rect2(world_to_map(lr.position.x, lr.position.y), lr.size * ppm)
		if not sr.intersects(view):
			continue
		var hk := clampf(((lot as CityLayout.Lot).h - 16.0) / 72.0, 0.0, 1.0)
		_map.draw_rect(sr, Color(0.09 + 0.12 * hk, 0.14 + 0.2 * hk, 0.19 + 0.24 * hk, 1.0))
		drawn["lots"] = int(drawn["lots"]) + 1
	# danger tint under the fog
	var dz := danger_zones()
	for z: Dictionary in dz:
		var zc := world_to_map((z["pos"] as Vector2).x, (z["pos"] as Vector2).y)
		var zr := float(z["radius"]) * ppm
		if z.has("rect"):                                              # a hostile district: its whole quadrant, red
			var rr0: Rect2 = z["rect"]
			var zrect := Rect2(world_to_map(rr0.position.x, rr0.position.y), rr0.size * ppm)
			_map.draw_rect(zrect, Color(DANGER_COLOR, 0.14))
			_map.draw_rect(zrect, Color(DANGER_COLOR, 0.85), false, 3.0 * s)
		else:
			_map.draw_circle(zc, zr, Color(DANGER_COLOR, 0.12))
			_map.draw_arc(zc, zr, 0.0, TAU, 48, Color(DANGER_COLOR, 0.85), 2.5 * s, true)
		drawn["danger"] = int(drawn["danger"]) + 1
	# fog: one dark rectangle per run of unvisited cells in a row (the roads and the district tint show through, the buildings are dimmed away)
	var cs := CELL * ppm
	var seen_n := 0
	for cz in CELLS:
		var run0 := -1
		for cx in CELLS + 1:
			var fogged := cx < CELLS and _seen[cz * CELLS + cx] == 0
			if cx < CELLS and not fogged:
				seen_n += 1
			if fogged and run0 < 0:
				run0 = cx
			elif not fogged and run0 >= 0:
				var fr := Rect2(world_to_map(-HALF + run0 * CELL, -HALF + cz * CELL), Vector2((cx - run0) * cs, cs))
				if fr.intersects(view):
					_map.draw_rect(fr, Color(0.0, 0.015, 0.03, 0.66))
				run0 = -1
	_charted = roundi(100.0 * seen_n / float(CELLS * CELLS))
	# district names: their boxes are reserved first (nothing else is written over a name); they are drawn after the markers
	var big := int((26.0 if zoom_f < 2.5 else 30.0) * s)
	var small := int(20.0 * s)
	var names: Array = []
	for d in 8:
		var tc := _zone_label_pos(d)
		var p := world_to_map(tc.x, tc.y)
		if not view.grow(-20.0 * s).has_point(p):
			continue
		var seen := zone_discovered(d)
		var dname := Districts.zone_title(d) if seen else "UNCHARTED"
		var nsz := big if d < Districts.COUNT else small
		var nw := font.get_string_size(dname, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x
		_placed.append(Rect2(p.x - nw * 0.5 - 3.0, p.y - nsz * 0.8, nw + 6.0, nsz * 1.05))
		names.append([p, dname, nsz, Color(1, 1, 1, 0.95) if seen else Color(0.7, 0.8, 0.9, 0.6)])
	# GPS route along the roads: dark casing, bright line, direction chevrons, distance at the goal
	var you := Vector2.INF
	var heading := Vector2(0, -1)
	if is_instance_valid(Game.player):
		var pp: Vector3 = Game.player.global_position
		you = world_to_map(pp.x, pp.z)
		if is_instance_valid(Game.camera):
			var cf := -Game.camera.global_transform.basis.z
			if Vector2(cf.x, cf.z).length() > 0.01:
				heading = Vector2(cf.x, cf.z).normalized()
		else:
			heading = Vector2(-sin(Game.player.rotation.y), -cos(Game.player.rotation.y))
	if _route.size() >= 2:
		var pl := PackedVector2Array()
		for rp: Vector3 in _route:
			pl.append(world_to_map(rp.x, rp.z))
		var rcol := Color(UiUtil.CYAN, 1.0) if has_waypoint() else Color(1.0, 0.78, 0.2, 1.0)
		_map.draw_polyline(pl, Color(0.0, 0.02, 0.04, 0.95), 9.0 * s, true)
		_map.draw_polyline(pl, rcol, 5.0 * s, true)
		_chevrons(pl, rcol, s)
		drawn["route"] = true
		var gp := pl[pl.size() - 1]
		var pulse := 0.5 + 0.5 * sin(_anim * 5.0)
		_map.draw_arc(gp, (13.0 + 4.0 * pulse) * s, 0.0, TAU, 28, Color(rcol, 0.9 - 0.4 * pulse), 3.0 * s, true)
		_route_m = roundi(MapRoute.length(_route))
	elif has_waypoint():
		var wpm := world_to_map(waypoint.x, waypoint.z)
		_map.draw_arc(wpm, 13.0 * s, 0.0, TAU, 24, Color(1, 1, 1, 0.95), 3.0 * s)
	# markers (clustered at the overview)
	_counts.clear()
	var cl := {}                                                       # "kind|cx|cy" -> [sum px, n, a marker]
	var r_badge := (10.0 if zoom_f < 2.0 else 13.0) * s
	for mk in lod_markers(visible_markers()):
		var k: StringName = mk["kind"]
		var pw: Vector3 = mk["pos"]
		var mp := world_to_map(pw.x, pw.z)
		if not view.grow(10.0).has_point(mp):
			continue
		_counts[k] = int(_counts.get(k, 0)) + 1
		var cpx := CLUSTER_PX * s * (1.7 if zoom_f < 1.6 else 1.2)
		var key := "%s|%d|%d" % [k, int(mp.x / cpx), int(mp.y / cpx)] if (zoom_f < 3.0 and k != &"mission" and k != &"home") else "%s|%s" % [k, pw]
		if not cl.has(key):
			cl[key] = [Vector2.ZERO, 0, mk]
		cl[key][0] += mp
		cl[key][1] += 1
	for key: String in cl:
		var e: Array = cl[key]
		var n: int = e[1]
		var mk2: Dictionary = e[2]
		var c2: Vector2 = (e[0] as Vector2) / float(n)
		var kind: StringName = mk2["kind"]
		var rr := r_badge * (1.35 if kind == &"mission" else 1.0)
		MapIcons.draw(_map, kind, c2, rr, KIND_COLOR[kind])
		drawn["markers"] = int(drawn["markers"]) + 1
		if n > 1:
			_label_out(font, c2 + Vector2(rr * 0.9, -rr * 0.7), str(n), int(16.0 * s), Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_LEFT, true)
		elif kind == &"mission" or (zoom_f >= 3.0 and kind != &"interior") or zoom_f >= 5.5:
			_label_out(font, c2 + Vector2(0.0, rr + 16.0 * s), String(mk2.get("label", "")), int(16.0 * s), Color(KIND_COLOR[kind]).lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, true)
	# district names on top of the markers
	for nm: Array in names:
		_label_out(font, nm[0], nm[1], nm[2], nm[3])
		drawn["labels"] = int(drawn["labels"]) + 1
	for z: Dictionary in dz:
		if z["kind"] == &"district":
			var tp := world_to_map((z["pos"] as Vector2).x, (z["pos"] as Vector2).y) + Vector2(0.0, 56.0 * s)
			if view.grow(-20.0 * s).has_point(tp):
				MapIcons.draw(_map, &"danger", tp + Vector2(-70.0 * s, -7.0 * s), 11.0 * s, DANGER_COLOR)
				_label_out(font, tp + Vector2(-50.0 * s, 0.0), "HOSTILE", int(18.0 * s), DANGER_COLOR, HORIZONTAL_ALIGNMENT_LEFT, true)
	# the selected marker's name
	if not selected.is_empty():
		var sp: Vector3 = selected["pos"]
		var sm := world_to_map(sp.x, sp.z)
		_map.draw_arc(sm, r_badge * 1.7, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 3.0 * s, true)
		_label_out(font, sm + Vector2(0.0, -r_badge * 1.7 - 8.0 * s), String(selected.get("label", "")), int(20.0 * s), Color(1, 1, 1, 1.0))
	# YOU: view cone and arrow, pointing where you look
	if you.is_finite():
		var right := Vector2(-heading.y, heading.x)
		var cone := PackedVector2Array([you, you + (heading * 1.0 + right * 0.55) * 46.0 * s, you + (heading * 1.0 - right * 0.55) * 46.0 * s])
		_map.draw_colored_polygon(cone, Color(1, 1, 1, 0.2))
		var tip := you + heading * 16.0 * s
		var tail := you - heading * 10.0 * s
		var arrow := PackedVector2Array([tip, tail + right * 11.0 * s, you - heading * 3.0 * s, tail - right * 11.0 * s])
		_map.draw_colored_polygon(arrow, Color(0.0, 0.02, 0.04, 1.0))
		_map.draw_colored_polygon(PackedVector2Array([you + heading * 13.0 * s, tail + right * 8.0 * s, you - heading * 3.0 * s, tail - right * 8.0 * s]), Color(1, 1, 1, 1))
		_map.draw_arc(you, 20.0 * s + 3.0 * s * sin(_anim * 4.0), 0.0, TAU, 28, Color(1, 1, 1, 0.55), 2.0 * s, true)
		drawn["you"] = true
		if not view.grow(-30.0 * s).has_point(you):
			_edge_arrow(you, s)
	# north, scale bar and the gesture hint
	var ins := UiUtil.insets(get_viewport().get_visible_rect().size)
	var rx := sz.x - ins.y - 12.0 * s - 164.0 * s
	var nc := Vector2(rx - 34.0 * s, 40.0 * s)
	_map.draw_circle(nc, 22.0 * s, Color(0.01, 0.03, 0.05, 0.9))
	_map.draw_arc(nc, 22.0 * s, 0.0, TAU, 24, Color(UiUtil.CYAN, 0.8), 2.0 * s, true)
	_map.draw_colored_polygon(PackedVector2Array([nc + Vector2(0, -17.0 * s), nc + Vector2(6.0 * s, -4.0 * s), nc + Vector2(-6.0 * s, -4.0 * s)]), UiUtil.CYAN)
	_label_out(font, nc + Vector2(0.0, 18.0 * s), "N", int(18.0 * s), Color(1, 1, 1, 0.95))
	var bar_m := 200.0 if zoom_f < 2.0 else (100.0 if zoom_f < 5.0 else 50.0)
	var bar_px := bar_m * ppm
	var bx0 := rx + 82.0 * s - bar_px * 0.5
	var by0 := sz.y - 22.0 * s
	_map.draw_line(Vector2(bx0, by0), Vector2(bx0 + bar_px, by0), Color(1, 1, 1, 0.85), 3.0 * s)
	_map.draw_line(Vector2(bx0, by0 - 6.0 * s), Vector2(bx0, by0 + 6.0 * s), Color(1, 1, 1, 0.85), 3.0 * s)
	_map.draw_line(Vector2(bx0 + bar_px, by0 - 6.0 * s), Vector2(bx0 + bar_px, by0 + 6.0 * s), Color(1, 1, 1, 0.85), 3.0 * s)
	_label_out(font, Vector2(rx + 82.0 * s, by0 - 12.0 * s), "%d M" % int(bar_m), int(16.0 * s), Color(1, 1, 1, 0.9))
	var hint := "TAP A MARKER OR THE MAP: ROUTE.  PINCH: ZOOM" if not has_waypoint() else "TAP THE WAYPOINT TO REMOVE IT.  PINCH: ZOOM"
	_title_row(font, s)
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16.0 * s)).x
	_map.draw_rect(Rect2(sz.x * 0.5 - hw * 0.5 - 12.0 * s, sz.y - 34.0 * s, hw + 24.0 * s, 26.0 * s), Color(0.0, 0.02, 0.04, 0.78))
	_label_out(font, Vector2(sz.x * 0.5, sz.y - 15.0 * s), hint, int(16.0 * s), Color(1, 1, 1, 0.8))


## "MAP" and the charted / route line, top left above the legend.
func _title_row(font: Font, s: float) -> void:
	_label_out(font, Vector2(_x0, 42.0 * s), "MAP", int(32.0 * s), UiUtil.CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	_label_out(font, Vector2(_x0 + 92.0 * s, 40.0 * s), _sub_text, int(18.0 * s), Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)


## Small arrowheads along a polyline every ~80 px, pointing along its direction.
func _chevrons(pl: PackedVector2Array, col: Color, s: float) -> void:
	var step := 80.0 * s
	var acc := step * 0.5
	for i in range(1, pl.size()):
		var a := pl[i - 1]
		var b := pl[i]
		var l := a.distance_to(b)
		if l < 1.0:
			continue
		var dir := (b - a) / l
		var side := Vector2(-dir.y, dir.x)
		var t := acc
		while t < l:
			var p := a + dir * t
			_map.draw_colored_polygon(PackedVector2Array([p + dir * 7.0 * s, p - dir * 5.0 * s + side * 6.0 * s, p - dir * 5.0 * s - side * 6.0 * s]), Color(0.0, 0.02, 0.04, 0.95))
			_map.draw_colored_polygon(PackedVector2Array([p + dir * 5.0 * s, p - dir * 3.0 * s + side * 4.0 * s, p - dir * 3.0 * s - side * 4.0 * s]), col.lerp(Color.WHITE, 0.5))
			t += step
		acc = t - l


## The hero is off screen (zoomed in and panned away): an arrow at the nearest edge points to them.
func _edge_arrow(you: Vector2, s: float) -> void:
	var sz := _map.size
	var c := sz * 0.5
	var d := (you - c).normalized()
	var p := Vector2(clampf(you.x, 40.0 * s, sz.x - 40.0 * s), clampf(you.y, 40.0 * s, sz.y - 40.0 * s))
	var side := Vector2(-d.y, d.x)
	_map.draw_colored_polygon(PackedVector2Array([p + d * 16.0 * s, p - d * 8.0 * s + side * 12.0 * s, p - d * 8.0 * s - side * 12.0 * s]), Color(1, 1, 1, 0.95))


# ---------------------------------------------------------------------------------------------------------------------
# save
# ---------------------------------------------------------------------------------------------------------------------

static func file_path() -> String:
	return path_override if path_override != "" else SAVE_PATH


## The city core around the spawn is charted at the start (cells whose centre is within START_HALF on both axes).
func reveal_start() -> void:
	if _seen.size() != CELLS * CELLS:
		_seen.resize(CELLS * CELLS)
	for i in CELLS * CELLS:
		var c := cell_center(i)
		if _seen[i] == 0 and absf(c.x) <= START_HALF and absf(c.y) <= START_HALF:
			_seen[i] = 1                                    # not _dirty: it is recomputed at every load, so it never makes a save of its own


## DEMO MODE: every cell charted (kept in the demo file only).
func reveal_all() -> void:
	_seen = PackedByteArray()
	_seen.resize(CELLS * CELLS)
	_seen.fill(1)
	_dirty = true
	_save()


## Reads the discovery file again (the demo ended: back to the real map).
func reload() -> void:
	_seen = PackedByteArray()
	_seen.resize(CELLS * CELLS)
	waypoint = Vector3.INF
	_dirty = false
	_load()
	reveal_start()


func _save() -> void:
	_dirty = false
	var cf := ConfigFile.new()
	cf.set_value("map", "seen", _seen)
	cf.set_value("map", "waypoint", waypoint if waypoint.is_finite() else Vector3(1e9, 0, 1e9))
	cf.save(file_path())


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(file_path()) != OK:
		return
	var v: Variant = cf.get_value("map", "seen", null)
	if v is PackedByteArray and (v as PackedByteArray).size() == CELLS * CELLS:
		_seen = v
	elif v is PackedByteArray and (v as PackedByteArray).size() == 256:
		# a save from the 8 x 8 city (16 x 16 cells of 40 m): it is the core of the big map, cells 8 .. 23 on each axis
		var old: PackedByteArray = v
		_seen = PackedByteArray()
		_seen.resize(CELLS * CELLS)
		var off := (CELLS - 16) / 2
		for k in 256:
			if old[k] == 1:
				_seen[(k / 16 + off) * CELLS + (k % 16 + off)] = 1
	var w: Variant = cf.get_value("map", "waypoint", null)
	if w is Vector3 and absf((w as Vector3).x) < 1e6:
		waypoint = w
