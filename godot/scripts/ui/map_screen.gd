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

const CELLS := 52
const CELL := 40.0                                  ## metres per cell (CELLS * CELL = 2080 = 2 * CityLayout.HALF)
const HALF := CELLS * CELL * 0.5
const ZOOMS: Array[int] = [1, 2, 4]
const OPEN_ZOOM_F := 3.0                          ## the 2080 m map opens at 3x (a 693 m frame, about what 2x gave on the 1280 m map: the district labels stay apart)
const OPEN_ZOOM := 2                              ## the zoom the map opens at (1 = the whole city)
const ZOOM_MAX := 8.0
const WORLD_ZOOM := 0.36                           ## WORLD view (the zoom button's fourth level): the whole 6 km terrain world fits the screen height
const DRAG_PX := 14.0
const LOD_ZOOM := 2.0                              ## below this zoom the crowded kinds show only their nearest few
const LOD_KINDS: Array[StringName] = [&"interior", &"shop", &"garage", &"items", &"weapon", &"job"]
const LOD_NEAR := 3
const LOD_NEAR_JOB := 4
const ALWAYS_KINDS: Array[StringName] = [&"mission", &"side", &"home"]   ## never dropped by the icon cap
const KIND_ORDER: Array[StringName] = [&"job", &"garage", &"weapon", &"shop", &"interior", &"items"]   ## round-robin order of the capped kinds (most useful first)
const CAP_OVERVIEW := 14                          ## icons on screen at zoom < 2 (round 3 director review: 600 icons were unreadable)
const CAP_MID := 20                               ## zoom 2 .. 4
const CAP_NEAR := 24                              ## zoom >= 4: even a street shows at most this many icons
const HINT_SECONDS := 6.0
const MAX_CHEVRONS := 260
const INPUT_QUIET := 0.25                         ## seconds after opening that pointer input is ignored: the tap that opened the map (a minimap tap, the MAP card) must not place a waypoint under the finger
const LABEL_MAX := 6                              ## marker names printed at once (objective and selection come on top)
const START_HALF := 160.0                           ## metres: only the spawn block (|x|, |z| <= this) is charted from the first second: the map STARTS mostly uncharted (menu cut round: it was 300 m = 22 %)
const DISCOVER_R := 240.0                           ## metres: how far around you the map charts itself on foot (it was 150: a walk to the next block did not show)
const DISCOVER_SPEED_K := 5.0                       ## metres of extra reveal radius per m/s of speed: a drive charts a wide road (the cap keeps a plane or a nitro from charting the city in a minute)
const DISCOVER_R_MAX := 420.0
const BADGE_R := 25.0                               ## base px: marker badge radius at the overview (was 17: tiny icons, director review 4 #9)
const BADGE_R_NEAR := 28.0
const KINDS: Array[StringName] = [&"mission", &"side", &"interior", &"job", &"shop", &"garage", &"weapon", &"home", &"items", &"site"]
const KIND_LABEL := {&"mission": "MISSION", &"side": "SIDE", &"interior": "INTERIORS", &"job": "JOBS", &"shop": "SHOPS", &"garage": "GARAGE", &"weapon": "WEAPONS", &"home": "HOME", &"items": "ITEMS", &"site": "SITES"}
const KIND_COLOR := {&"mission": Color(1.0, 0.75, 0.15), &"side": Color(0.2, 0.9, 1.0), &"interior": Color(0.62, 0.76, 1.0), &"job": Color(1.0, 0.45, 0.85), &"shop": Color(0.3, 1.0, 0.55), &"garage": Color(1.0, 0.5, 0.2),
	&"weapon": Color(1.0, 0.82, 0.3), &"home": Color(0.85, 0.9, 1.0), &"items": Color(0.75, 0.45, 1.0), &"site": Color(0.45, 0.85, 1.0)}
const DANGER_COLOR := Color(1.0, 0.25, 0.25)
const FOG_ALPHA := 0.30                              ## the veil over the uncharted cells (it was 0.66 black: a dirty dark field at the start)
const SAVE_PATH := "user://map.cfg"
static var up := false                    ## true while a map is open: Hud, TouchControls, the story cards, photo mode ... ignore pointer input then (the map owns it; a tap used to fall through to the pause menu underneath)
static var path_override := ""             ## DEMO MODE points the map at its own file (scripts/demo/demo_mode.gd); "" = SAVE_PATH
const GARAGE_TYPES: Array[StringName] = [&"warehouse", &"cargo_bay"]
const TAP_CLEAR_PX := 28.0
const MARKER_PICK_PX := 44.0
const CLUSTER_PX := 50.0
const COL_W := 212.0                                 ## base px: the legend column (left) and the button column (right)
const BTN_H := 64.0
const GAP := 6.0

var waypoint := Vector3.INF
var filters := {&"mission": true, &"side": true, &"interior": true, &"job": true, &"shop": true, &"garage": true, &"weapon": true, &"home": true, &"items": true}

var world_mode := false                              ## WORLD view: the map shows the whole terrain world (TerrainMap picture), panning reaches all of it
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
var _right_rect := Rect2()                           ## the opaque panel behind the button column (control px)
var _legend_rect := Rect2()                          ## the opaque panel behind the legend chips (control px)
var _chip_vis := 0
var _open_age := 0.0                                  ## seconds since the map opened: the gesture hint is only there for the first few
var _route_m := 0
var _tint_mesh: ArrayMesh                            ## static layers as ONE mesh each (district tint per block, building footprints): one draw call, no per-lot script work in the draw
var _lots_mesh: ArrayMesh
var _lots_mesh_n := 0
var _lots_mesh_owner := 0
var _fog_mesh: ArrayMesh
var _fog_hash := 0
var _redraw_wanted := true
var _redraw_t := 0.0
var _goal_btn: Button
var activity := 0                                    ## counts every pan, zoom, tap, waypoint, open and close: the screen watchdog reads it as progress


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_seen.resize(CELLS * CELLS)
	_load()
	reveal_start()
	if not Game.new_game.is_connected(_on_new_game):
		Game.new_game.connect(_on_new_game)
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
	_zoom_btn.pressed.connect(_on_zoom_button)
	var loc := _button("YOU", &"Locate")
	loc.pressed.connect(locate)
	_goal_btn = _button("GOAL", &"Goal")
	_goal_btn.pressed.connect(fit_route)
	var clr := _button("CLEAR", &"Clear")
	clr.pressed.connect(clear_waypoint)
	var cls := _button("CLOSE", &"Close")
	cls.pressed.connect(close_screen)
	var mis := _button("MISSIONS", &"Missions")                  # the Mission Board is one tap away from the map (docs/DESIGN.md core loop)
	mis.pressed.connect(open_board)
	_side_btns = [cls, mis, _zoom_btn, loc, _goal_btn, clr]
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
	b.draw.connect(func() -> void:
		var ir := b.size.y * 0.30                                           # the icon sits left of the text (content margin 54 px): its edge is 2 r + 8 = 46 px at 64 px tall
		MapIcons.draw(b, k, Vector2(ir + 8.0, b.size.y * 0.5), ir, col if b.button_pressed else Color(col, 0.4)))
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
	var y_top := y
	for k in KINDS:
		var b: Button = _btns[k]
		b.visible = _chip_shown(k)
		if not b.visible:
			continue
		b.position = Vector2(x0, y)
		b.size = Vector2(COL_W * s, BTN_H * s)
		b.add_theme_font_size_override("font_size", int(22.0 * s))
		y += (BTN_H + 2.0) * s
	_legend_rect = Rect2(x0 - 6.0 * s, y_top - 6.0 * s, COL_W * s + 12.0 * s, y - y_top + 10.0 * s)
	var rx := vp.x - ins.y - 12.0 * s - 164.0 * s
	var ry := 8.0 * s
	_right_rect = Rect2(rx - 6.0 * s, 0.0, 164.0 * s + 12.0 * s + ins.y + 6.0 * s, (BTN_H + GAP + 2.0) * s * float(_side_btns.size()) + 14.0 * s)
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
		_open_age += delta
		if Game.state != &"paused":                       # the game moved on under the map (death, a cutscene, a resume by another path): never leave a map over a running game
			close_screen()
			return
		if _t >= 0.2:
			_t = 0.0
			_refresh_chips()
			_map.queue_redraw()
		return
	if _t < 0.5:
		return
	_t = 0.0
	if Game.state == &"play" and is_instance_valid(Game.player):
		discover(Game.player.global_position, reveal_radius())
	if _dirty:
		_save()


## Esc, the pad's B and the phone's back button close the map first (they used to reach the pause menu under it and resume the game).
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"))) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B):
		close_screen()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _open:
		close_screen()


func _exit_tree() -> void:
	if _open:
		up = false


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


## How far around the hero the map charts itself right now: DISCOVER_R on foot, wider the faster the hero (or the car) moves.
func reveal_radius() -> float:
	var v := 0.0
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p != null:
		var veh: Object = p.get(&"vehicle")
		var src: Object = veh if veh != null else p
		var vel: Variant = src.get(&"velocity") if src.get(&"velocity") != null else src.get(&"vel")
		if vel is Vector3:
			v = Vector2((vel as Vector3).x, (vel as Vector3).z).length()
	return minf(DISCOVER_R + v * DISCOVER_SPEED_K, DISCOVER_R_MAX)


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
	if not w.is_finite():
		return
	activity += 1
	waypoint = Vector3(clampf(w.x, -HALF, HALF), 0.0, clampf(w.z, -HALF, HALF))
	selected = {}
	_dirty = true
	_rebuild_route()
	if _map != null:
		_map.queue_redraw()


func clear_waypoint() -> void:
	activity += 1
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
	up = true                                             # before the state change: the HUD hides its pause screen for the map instead of drawing it underneath
	Game.state = &"paused"
	if is_instance_valid(Game.player):
		discover(Game.player.global_position, reveal_radius())
	_open = true
	up = true
	activity += 1
	_open_age = 0.0
	world_mode = false
	_touches.clear()
	_press = Vector2.INF
	_dragging = false
	_gesture = false
	visible = true
	get_tree().call_group(&"hud", &"map_toggled", true)
	_layout()
	set_zoom(OPEN_ZOOM)
	zoom_f = maxf(zoom_f, OPEN_ZOOM_F)
	_after_zoom()                                         # opens close on the hero: a 1280 m city drawn on one phone height is a postage stamp (director review 3, #9)
	_load_lots()
	_rebuild_route()
	if _route.size() >= 2:
		fit_route()                                       # hero and objective both in the frame
	_refresh_chips()
	_map.queue_redraw()


## MISSIONS: the map closes and the Mission Board opens (from the game it pauses and returns there).
func open_board() -> void:
	if not _open:
		return
	close_screen()
	if is_inside_tree():
		get_tree().call_group(&"hud", &"open_board")


func close_screen() -> void:
	if not _open:
		return
	_open = false
	up = false
	activity += 1
	visible = false
	_touches.clear()
	_press = Vector2.INF
	_dragging = false
	_gesture = false
	_save()
	if Game.state == &"paused":
		Game.state = _resume
	if is_inside_tree():
		get_tree().call_group(&"hud", &"map_toggled", false)
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
	_rect = Rect2(Vector2.ZERO, Vector2(maxf(_map.size.x, 1.0), maxf(_map.size.y, 1.0)))     # the map fills the whole screen (it was the square of the screen height, with dark bars on a phone)


## Metres from the top to the bottom edge of the screen at the current zoom (zoom 1 = the whole city fits the height; the width shows more as the phone is wider).
func span() -> float:
	return 2.0 * HALF / zoom_f


## Screen px per metre.
func ppm() -> float:
	return _rect.size.y / span()


## Metres across the whole screen (width, height).
func extent() -> Vector2:
	return _rect.size / ppm()


## World (x, z) of the screen's upper left corner.
func _view_origin() -> Vector2:
	return view_center - extent() * 0.5


func world_to_map(x: float, z: float) -> Vector2:
	return _rect.position + (Vector2(x, z) - _view_origin()) * ppm()


func map_to_world(p: Vector2) -> Vector3:
	var w := _view_origin() + (p - _rect.position) / ppm()
	var lim := _view_half()
	return Vector3(clampf(w.x, -lim, lim), 0.0, clampf(w.y, -lim, lim))


## Half side of the area the view may show: the city, or the whole terrain world in WORLD view.
func _view_half() -> float:
	return TerrainHeight.WORLD_HALF if world_mode else HALF


## Next zoom level: whole map, then 2x and 4x around you (the hero, or the map centre when no hero exists).
func cycle_zoom() -> void:
	set_zoom(ZOOMS[(ZOOMS.find(zoom) + 1) % ZOOMS.size()] if ZOOMS.has(zoom) else 1)


## The zoom button: 1x, 2x, 4x, then (once the world picture exists) WORLD, then back to 1x. `cycle_zoom` keeps its three levels.
func _on_zoom_button() -> void:
	if world_mode:
		set_world_mode(false)
	elif zoom == 4 and TerrainMap.ready:
		set_world_mode(true)
	else:
		cycle_zoom()


func set_world_mode(on: bool) -> void:
	world_mode = on and TerrainMap.ready
	if world_mode:
		zoom_f = WORLD_ZOOM
		view_center = Vector2.ZERO
		_after_zoom()
	else:
		set_zoom(1)


func set_zoom(z: int) -> void:
	world_mode = false
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
	activity += 1
	_clamp_view()
	if _zoom_btn != null:
		_zoom_btn.text = "WORLD" if world_mode else "ZOOM %dX" % zoom
	if _map != null:
		_map.queue_redraw()


## Multiply the zoom by `f`, keeping the world point under the screen position `focus` where it is (a pinch zooms into the fingers).
func zoom_by(f: float, focus := Vector2.INF) -> void:
	if not is_finite(f) or f <= 0.0:
		return
	var before := Vector2.ZERO
	var use_focus := focus.is_finite() and _rect.size.x > 1.0
	if use_focus:
		before = _view_origin() + (focus - _rect.position) / ppm()
	zoom_f = clampf(zoom_f * f, WORLD_ZOOM if world_mode else 1.0, ZOOM_MAX)
	if use_focus:
		var after_o := before - (focus - _rect.position) / ppm()
		view_center = after_o + extent() * 0.5
	_after_zoom()


func pan(by_world: Vector2) -> void:
	if not by_world.is_finite():
		return
	view_center += by_world
	activity += 1
	_clamp_view()
	if _map != null:
		_map.queue_redraw()


## The view never leaves the city: where the screen is wider than the city (zoom 1 on a phone) that axis stays centred.
func _clamp_view() -> void:
	if not view_center.is_finite():
		view_center = Vector2.ZERO
	var half := extent() * 0.5
	var lim := _view_half()
	var lx := maxf(lim - half.x, 0.0)
	var lz := maxf(lim - half.y, 0.0)
	view_center = Vector2(clampf(view_center.x, -lx, lx), clampf(view_center.y, -lz, lz))


## True when the view is pinned by the city edge (a test helper: zooming about a point near the edge cannot keep it fixed there).
func _clamp_limited() -> bool:
	var half := extent() * 0.5
	return absf(view_center.x) >= HALF - half.x - 0.5 or absf(view_center.y) >= HALF - half.y - 0.5


## Frames the hero and the objective (the route's goal) together; zoom 1..4. Without a route it centres on the hero.
func fit_route() -> void:
	activity += 1
	var goal := route_goal()
	if not is_instance_valid(Game.player) or not goal.is_finite():
		locate()
		return
	var pp: Vector3 = Game.player.global_position
	var a := Vector2(pp.x, pp.z)
	var b := Vector2(goal.x, goal.z)
	var d := (a - b).abs() + Vector2(220.0, 220.0)                    # metres of margin: the streets around the route stay in the frame
	var size := maxf(_rect.size.y, 1.0)
	var ppm_need := minf(_rect.size.x * 0.62 / d.x, _rect.size.y * 0.7 / d.y)
	zoom_f = clampf(2.0 * HALF * ppm_need / size, 1.0, 2.6)
	view_center = (a + b) * 0.5
	_after_zoom()


func _on_map_input(event: InputEvent) -> void:
	if _open_age < INPUT_QUIET:
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventScreenDrag:
		activity += 1
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
			pan(-drag / ppm())
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
	var w := _view_origin() + (p - _rect.position) / ppm()
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
		var bd: Variant = m.get("board")
		if bd is MissionBoard and not (bd as MissionBoard).is_running():
			for o: Dictionary in (bd as MissionBoard).offers:           # the three offers of the Mission Board: pins on the map ("MISSIONS" lists them)
				var op: Vector3 = o.get("pos", Vector3.INF)
				if op.is_finite():
					out.append({"kind": &"side", "pos": op, "fog": false, "label": str(o["title"])})
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
				var cw := StringName(WeaponLadder.CRATES[i]["weapon"])
				out.append({"kind": &"weapon", "pos": WeaponLadder.crate_pos(i), "fog": true, "label": ("%s  %s" % [WeaponLadder.CRATES[i]["name"], WeaponDefs.title(cw)]) if cw != &"" else "AMMO CRATE"})
		if fr.repairs != null:
			for i in int(fr.repairs.call(&"count")):
				out.append({"kind": &"garage", "pos": fr.repairs.call(&"pos", i), "fog": true, "label": "REPAIR BAY"})
	for pt: Dictionary in VehicleSpawns.POINTS:                  # where the helicopter, plane, tank and boats wait (round 5 roster): the car glyph, the vehicle's name
		out.append({"kind": &"garage", "pos": pt["pos"], "fog": true, "label": VehicleSpecs.name_of(pt["kind"])})
	out.append({"kind": &"garage", "pos": Harbour.center(), "fog": true, "label": "HARBOUR: BOATS AND JET SKIS"})       # the port on the south coast (one marker for its six berths)
	out.append_array(WorldRoam.map_markers())                       # the free-roam courses and the treasure hunt (flight school, off-road trial, jet-ski laps)
	out.append_array(Airport.map_markers())                         # EASTFIELD AIRPORT and the helipads
	out.append_array(OutskirtsSites.map_markers())                  # the mountain and outskirt sites: observatory, radio tower, mine, crash site, cabins, villages, farms (the cave once found)
	return out


## Icon cap per zoom (director review: ~600 icons at 77 % charted). Counted per frame: CAP_OVERVIEW below zoom 2, CAP_MID below 4, CAP_NEAR above.
func badge_cap() -> int:
	return CAP_OVERVIEW if zoom_f < LOD_ZOOM else (CAP_MID if zoom_f < 4.0 else CAP_NEAR)


## What the map draws: the objective, side jobs and homes always; of the crowded kinds the nearest ones, taken round-robin (a job, a garage, a crate, a shop, a door, a shard) until the cap
## of this zoom is full, so every kind that is near shows up and none floods the map. Below zoom 2 each crowded kind adds at most LOD_NEAR (jobs LOD_NEAR_JOB) around the HERO; zoomed in the
## reference is the centre of the view and only markers inside the view count.
func lod_markers(list: Array[Dictionary]) -> Array[Dictionary]:
	var overview := zoom_f < LOD_ZOOM
	var from := view_center
	if overview and is_instance_valid(Game.player):
		from = Vector2(Game.player.global_position.x, Game.player.global_position.z)
	var view := Rect2(Vector2.ZERO, _map.size).grow(10.0) if _map != null and _map.size.x > 8.0 else Rect2()
	var out: Array[Dictionary] = []
	var crowded := {}
	for mk in list:
		var p: Vector3 = mk["pos"]
		if not overview and view.size.x > 0.0 and not view.has_point(world_to_map(p.x, p.z)):
			continue
		if ALWAYS_KINDS.has(mk["kind"]):
			out.append(mk)
			continue
		if not crowded.has(mk["kind"]):
			crowded[mk["kind"]] = []
		(crowded[mk["kind"]] as Array).append([Vector2(p.x, p.z).distance_squared_to(from), mk])
	var room := maxi(badge_cap() - out.size(), 0)
	for k: StringName in crowded:
		(crowded[k] as Array).sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var rank := 0
	while room > 0:
		var took := false
		for k: StringName in KIND_ORDER:
			if not crowded.has(k) or room <= 0:
				continue
			var arr: Array = crowded[k]
			var lim := arr.size()
			if overview:
				lim = mini(lim, LOD_NEAR_JOB if k == &"job" else LOD_NEAR)
			if rank < lim:
				out.append(arr[rank][1])
				room -= 1
				took = true
		if not took:
			break
		rank += 1
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


## The always-kinds (MISSION, SIDE, HOME) are legend rows only while there is one: "MISSION 0" is noise.
func _chip_shown(k: StringName) -> bool:
	return not ALWAYS_KINDS.has(k) or int(_counts.get(k, 0)) > 0


func _refresh_chips() -> void:
	_counts = marker_counts()
	var vis := 0
	for k in KINDS:
		if _chip_shown(k):
			vis |= 1 << KINDS.find(k)
	if vis != _chip_vis:
		_chip_vis = vis
		_layout()
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
	if _route_goal.is_finite() and is_instance_valid(Game.player) and Game.player.global_position.is_finite():
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
	x = clampf(x, 6.0, maxf(_map.size.x - w - 6.0, 6.0))                # a name never runs off the screen edge
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


## Rectangles (metres) with a colour each as ONE mesh (4 vertices and 6 indices per rectangle, vertex colours). Drawn with a Transform2D from metres to pixels.
static func rect_mesh(rects: Array[Rect2], cols: PackedColorArray) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if rects.is_empty():
		return mesh
	var vs := PackedVector2Array()
	var cs := PackedColorArray()
	var ix := PackedInt32Array()
	vs.resize(rects.size() * 4)
	cs.resize(rects.size() * 4)
	ix.resize(rects.size() * 6)
	for i in rects.size():
		var r := rects[i]
		var b := i * 4
		vs[b] = r.position
		vs[b + 1] = Vector2(r.end.x, r.position.y)
		vs[b + 2] = r.end
		vs[b + 3] = Vector2(r.position.x, r.end.y)
		for k in 4:
			cs[b + k] = cols[i]
		var q := i * 6
		ix[q] = b
		ix[q + 1] = b + 1
		ix[q + 2] = b + 2
		ix[q + 3] = b
		ix[q + 4] = b + 2
		ix[q + 5] = b + 3
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_INDEX] = ix
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## The district tint of every block (the zone accent), built once.
func _tint_layer() -> ArrayMesh:
	if _tint_mesh == null:
		var rects: Array[Rect2] = []
		var cols := PackedColorArray()
		var pitch := CityLayout.PITCH
		for bi in CityLayout.N:
			for bj in CityLayout.N:
				var bx := CityLayout.road_center(bi) + pitch * 0.5
				var bz := CityLayout.road_center(bj) + pitch * 0.5
				var acc: Color = Districts.palette(Districts.look_at(bx, bz))["accent"]
				var k := 0.22 if Districts.zone_at(bx, bz) < Districts.COUNT else 0.12
				rects.append(Rect2(bx - CityLayout.BLOCK * 0.5, bz - CityLayout.BLOCK * 0.5, CityLayout.BLOCK, CityLayout.BLOCK))
				cols.append(Color(0.06 + acc.r * k, 0.08 + acc.g * k, 0.11 + acc.b * k, 1.0))
		_tint_mesh = rect_mesh(rects, cols)
	return _tint_mesh


## Every building footprint, coloured by height; rebuilt when the city changes.
func _lots_layer() -> ArrayMesh:
	var n := _lots.size()
	if n == 0:
		return null
	if _lots_mesh == null or _lots_mesh_n != n or _lots_mesh_owner != _lots_owner:
		var rects: Array[Rect2] = []
		var cols := PackedColorArray()
		for lot: Variant in _lots:
			var l := lot as CityLayout.Lot
			var hk := clampf((l.h - 16.0) / 72.0, 0.0, 1.0)
			rects.append(l.rect)
			cols.append(Color(0.15 + 0.14 * hk, 0.22 + 0.22 * hk, 0.30 + 0.26 * hk, 1.0))
		_lots_mesh = rect_mesh(rects, cols)
		_lots_mesh_n = n
		_lots_mesh_owner = _lots_owner
	return _lots_mesh


## The city's ground as a texture: the district colours blended smoothly over the whole 2080 m (96 x 96 px, built once, 27 KB): the map is a coloured chart at 0 % charted, never a black field.
static var _ground: ImageTexture
const GROUND_N := 96


static func ground_texture() -> ImageTexture:
	if _ground == null:
		var img := Image.create(GROUND_N, GROUND_N, false, Image.FORMAT_RGB8)
		for j in GROUND_N:
			for i in GROUND_N:
				var x := -HALF + (float(i) + 0.5) / float(GROUND_N) * 2.0 * HALF
				var z := -HALF + (float(j) + 0.5) / float(GROUND_N) * 2.0 * HALF
				var acc := Color(0, 0, 0)
				for o: Vector2 in [Vector2.ZERO, Vector2(70, 0), Vector2(-70, 0), Vector2(0, 70), Vector2(0, -70)]:      # a soft blend: the accent of the block under the pixel and the four around it
					acc += Districts.palette(Districts.look_at(x + o.x, z + o.y))["accent"] as Color
				acc /= 5.0
				var core := Districts.zone_at(x, z) < Districts.COUNT
				var k := 0.42 if core else 0.26
				img.set_pixel(i, j, Color(0.07 + acc.r * k, 0.10 + acc.g * k, 0.15 + acc.b * k))
		_ground = ImageTexture.create_from_image(img)
	return _ground


## Fog and the chart's edge in one pass: a light veil over every cell not walked near (one rectangle per run), and a thin bright line wherever a charted cell meets an uncharted one.
## One mesh each, rebuilt only when the charted cells change.
func _fog_layer() -> ArrayMesh:
	var h: int = hash(_seen)
	if _fog_mesh == null or h != _fog_hash:
		var rects: Array[Rect2] = []
		var cols := PackedColorArray()
		for cz in CELLS:
			var run0 := -1
			for cx in CELLS + 1:
				var fogged := cx < CELLS and _seen[cz * CELLS + cx] == 0
				if fogged and run0 < 0:
					run0 = cx
				elif not fogged and run0 >= 0:
					rects.append(Rect2(-HALF + run0 * CELL, -HALF + cz * CELL, float(cx - run0) * CELL, CELL))
					cols.append(Color(0.01, 0.03, 0.07, FOG_ALPHA))
					run0 = -1
		var edge := Color(UiUtil.CYAN, 0.7)
		var ew := 3.0
		for cz in CELLS:
			for cx in CELLS:
				if _seen[cz * CELLS + cx] == 0:
					continue
				var x0 := -HALF + cx * CELL
				var z0 := -HALF + cz * CELL
				if cx + 1 < CELLS and _seen[cz * CELLS + cx + 1] == 0:
					rects.append(Rect2(x0 + CELL - ew * 0.5, z0, ew, CELL))
					cols.append(edge)
				if cx > 0 and _seen[cz * CELLS + cx - 1] == 0:
					rects.append(Rect2(x0 - ew * 0.5, z0, ew, CELL))
					cols.append(edge)
				if cz + 1 < CELLS and _seen[(cz + 1) * CELLS + cx] == 0:
					rects.append(Rect2(x0, z0 + CELL - ew * 0.5, CELL, ew))
					cols.append(edge)
				if cz > 0 and _seen[(cz - 1) * CELLS + cx] == 0:
					rects.append(Rect2(x0, z0 - ew * 0.5, CELL, ew))
					cols.append(edge)
		_fog_mesh = rect_mesh(rects, cols)
		_fog_hash = h
	return _fog_mesh


## WORLD view: the names of the regions, on top of the picture (the map draws the city and the markers over it).
func _draw_world_labels(font: Font, s: float) -> void:
	var fs := int(24.0 * s)
	for e in TerrainMap.LABELS:
		var p := world_to_map((e[1] as Vector2).x, (e[1] as Vector2).y)
		if not _map.get_rect().grow(-20.0).has_point(p):
			continue
		var w := font.get_string_size(e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := p - Vector2(w * 0.5, 0.0)
		_map.draw_string_outline(font, pos, e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(fs / 5, 3), Color(0.0, 0.02, 0.04, 0.95))
		_map.draw_string(font, pos, e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.95, 1.0, 0.92))


func _draw_map() -> void:
	if _rect.size.x < 8.0:
		return
	var font := ThemeDB.fallback_font
	var s := _s()
	var sz := _map.size
	var view := Rect2(Vector2.ZERO, sz)
	var pm := ppm()                                        # screen px per metre
	var origin := _view_origin()
	_placed.clear()
	if scan_on:
		scan_log.clear()
	drawn = {"badges": [], "roads": 0, "lots": 0, "markers": 0, "labels": 0, "route": false, "you": false, "danger": 0}
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.04, 0.065, 1.0))
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var city := Rect2(world_to_map(-HALF, -HALF), Vector2(2.0 * HALF, 2.0 * HALF) * pm)
	if world_mode:
		_draw_world_labels(font, s)
	# outskirts: the road grid carries on, faint, past the city edge, so a wide phone screen is a map and not black bars
	var o_col := Color(0.07, 0.1, 0.13, 1.0)
	var o_w := maxf(CityLayout.ROAD * pm, 2.0)
	var terr := TerrainMap.ready and TerrainMap.texture != null
	if terr:                                                           # the land outside the city: coast, mountains, rivers, highways (TerrainMap, drawn once on a worker thread)
		var tw := TerrainHeight.WORLD_HALF
		_map.draw_texture_rect(TerrainMap.texture, Rect2(world_to_map(-tw, -tw), Vector2(2.0 * tw, 2.0 * tw) * pm), false, Color(1.0, 1.0, 1.0, 0.92))
	for oi in (range(-12, CityLayout.N + 13) if not terr else range(0)):
		var oc := -CityLayout.HALF + float(oi) * CityLayout.PITCH
		var op := world_to_map(oc, 0.0)
		if (oi < 0 or oi > CityLayout.N) and op.x + o_w > 0.0 and op.x - o_w < sz.x:
			_map.draw_rect(Rect2(op.x - o_w * 0.5, 0.0, o_w, sz.y), o_col)
		var oq := world_to_map(0.0, oc)
		if oi >= 0 and oi <= CityLayout.N and oq.y + o_w > 0.0 and oq.y - o_w < sz.y:
			if city.position.x > 0.0:
				_map.draw_rect(Rect2(0.0, oq.y - o_w * 0.5, city.position.x, o_w), o_col)
			if city.end.x < sz.x:
				_map.draw_rect(Rect2(city.end.x, oq.y - o_w * 0.5, sz.x - city.end.x, o_w), o_col)
	_map.draw_rect(city.grow(4.0 * s), Color(UiUtil.CYAN, 0.18), false, 2.0 * s)
	_map.draw_texture_rect(ground_texture(), city, false)                                      # the ground: district colours, smooth, never black
	var xf := Transform2D(Vector2(pm, 0.0), Vector2(0.0, pm), world_to_map(0.0, 0.0))        # metres (x, z) -> screen px
	_map.draw_mesh(_tint_layer(), null, xf)                                                    # district tint per block, under everything (one draw call)
	# roads: the whole grid, avenues every fourth line brighter
	var rw := CityLayout.ROAD * pm
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
			var pr := Rect2(world_to_map(pz.x - 13.0, pz.y - 13.0), Vector2(26.0, 26.0) * pm)
			if pr.intersects(view):
				_map.draw_rect(pr, Color(0.08, 0.24, 0.17, 1.0))
	# building footprints: one mesh (colour by height), one draw call
	var lm := _lots_layer()
	if lm != null:
		_map.draw_mesh(lm, null, xf)
		drawn["lots"] = _lots_mesh_n
	# danger tint under the fog
	var dz := danger_zones()
	for z: Dictionary in dz:
		var zc := world_to_map((z["pos"] as Vector2).x, (z["pos"] as Vector2).y)
		var zr := float(z["radius"]) * pm
		if z.has("rect"):                                              # a hostile district: its whole quadrant, red
			var rr0: Rect2 = z["rect"]
			var zrect := Rect2(world_to_map(rr0.position.x, rr0.position.y), rr0.size * pm)
			_map.draw_rect(zrect, Color(DANGER_COLOR, 0.14))
			_map.draw_rect(zrect, Color(DANGER_COLOR, 0.85), false, 3.0 * s)
		else:
			_map.draw_circle(zc, zr, Color(DANGER_COLOR, 0.12))
			_map.draw_arc(zc, zr, 0.0, TAU, 48, Color(DANGER_COLOR, 0.85), 2.5 * s, true)
		drawn["danger"] = int(drawn["danger"]) + 1
	# fog: the cells you have not walked near (the roads and the district tint show through, the buildings are dimmed away); one mesh, rebuilt only when the charted cells change
	_map.draw_mesh(_fog_layer(), null, xf)
	var seen_n := discovered_count()
	_charted = roundi(100.0 * seen_n / float(CELLS * CELLS))
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
			if rp.is_finite():
				pl.append(world_to_map(rp.x, rp.z))
		pl = clean_polyline(pl)
		if pl.size() >= 2:
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
	var r_badge := (BADGE_R if zoom_f < 2.0 else BADGE_R_NEAR) * s
	for mk in lod_markers(visible_markers()):
		var k: StringName = mk["kind"]
		var pw: Vector3 = mk["pos"]
		var mp := world_to_map(pw.x, pw.z)
		if not view.grow(10.0).has_point(mp):
			continue
		_counts[k] = int(_counts.get(k, 0)) + 1
		var cpx := CLUSTER_PX * s * (1.7 if zoom_f < 1.6 else 1.2)
		var key := "%s|%d|%d" % [k, int(mp.x / cpx), int(mp.y / cpx)] if (zoom_f < 5.0 and k != &"mission" and k != &"home") else "%s|%s" % [k, pw]
		if not cl.has(key):
			cl[key] = [Vector2.ZERO, 0, mk]
		cl[key][0] += mp
		cl[key][1] += 1
	var labels_left := LABEL_MAX
	var objective := Vector2.INF
	for om in visible_markers():
		if om["kind"] == &"mission":
			var op: Vector3 = om["pos"]
			objective = world_to_map(op.x, op.z)
			break
	var keys: Array = cl.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return not ALWAYS_KINDS.has((cl[b][2] as Dictionary)["kind"]) and ALWAYS_KINDS.has((cl[a][2] as Dictionary)["kind"]))   # objective first: its label wins
	# director review 5, defect 10: 40 icons stacked at 3-4x and one lump at 1x. After the per-kind clusters, a second pass in priority order (objective, side job, home, then job, garage,
	# weapon, shop, door, item) drops every badge that would sit on a higher one and adds its count to that one's number: a pile becomes one icon with "7" beside it.
	var order: Array = keys.duplicate()
	order.sort_custom(func(a: String, b: String) -> bool:
		var ka: StringName = (cl[a][2] as Dictionary)["kind"]
		var kb: StringName = (cl[b][2] as Dictionary)["kind"]
		var pa := -1 if ALWAYS_KINDS.has(ka) else KIND_ORDER.find(ka)
		var pb := -1 if ALWAYS_KINDS.has(kb) else KIND_ORDER.find(kb)
		if pa != pb:
			return pa < pb
		return int(cl[a][1]) > int(cl[b][1]))
	var merged := {}
	var host_c := {}
	var host_r := {}
	for k0: String in order:
		var e1: Array = cl[k0]
		var kind1: StringName = (e1[2] as Dictionary)["kind"]
		var rr1 := r_badge * (1.5 if kind1 == &"mission" else 1.0)
		var c1: Vector2 = (e1[0] as Vector2) / float(e1[1])
		var host := ""
		for hk: String in merged:
			if ALWAYS_KINDS.has(kind1):
				break                                                # the objective, a side job and a home are never merged away
			if c1.distance_to(host_c[hk]) < (rr1 + float(host_r[hk])) * 1.55:
				host = hk
				break
		if host == "":
			merged[k0] = [c1 * float(e1[1]), int(e1[1]), e1[2]]
			host_c[k0] = c1
			host_r[k0] = rr1
		else:
			merged[host][1] = int(merged[host][1]) + int(e1[1])
			merged[host][0] = (host_c[host] as Vector2) * float(merged[host][1])
	cl = merged
	keys = merged.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return not ALWAYS_KINDS.has((cl[b][2] as Dictionary)["kind"]) and ALWAYS_KINDS.has((cl[a][2] as Dictionary)["kind"]))
	for key0: String in keys:                                           # every badge reserves its box first: no name is written over an icon
		var e0: Array = cl[key0]
		var rr0 := r_badge * (1.5 if (e0[2] as Dictionary)["kind"] == &"mission" else 1.0)
		var c0: Vector2 = (e0[0] as Vector2) / float(e0[1])
		var bbox := Rect2(c0 - Vector2(rr0, rr0), Vector2(rr0, rr0) * 2.0)
		if int(e0[1]) > 1:
			bbox = bbox.merge(Rect2(c0 + Vector2(rr0 * 0.6, -rr0 * 1.6), Vector2(26.0 * s, 20.0 * s)))     # the count written beside the badge
		_placed.append(bbox)
	# district names: their boxes are reserved first (nothing else is written over a name); they are drawn after the markers
	var big := int((26.0 if zoom_f < 2.5 else 24.0) * s)
	var small := int(22.0 * s)
	var name_a := 0.82 if zoom_f < 2.5 else 0.6                       # zoomed in the names step back: the markers and the route are the subject
	var names: Array = []
	var name_boxes: Array[Rect2] = []
	for d in 8:
		var tc := _zone_label_pos(d)
		var p := world_to_map(tc.x, tc.y)
		if not view.grow(-20.0 * s).has_point(p):
			continue
		var seen := zone_discovered(d)
		var dname := Districts.zone_title(d) if seen else "UNCHARTED"
		var nsz := big if d < Districts.COUNT else small
		var nw := font.get_string_size(dname, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x
		var nbox := Rect2(p.x - nw * 0.5 - 3.0, p.y - nsz * 0.8, nw + 6.0, nsz * 1.05)
		var clash := false
		for other: Rect2 in name_boxes + _placed:                                    # the overview of the 2080 m map puts the four core names almost on top of each other: the later one steps aside
			if nbox.intersection(other).get_area() > 0.15 * minf(nbox.get_area(), other.get_area()):
				clash = true
		if clash:
			continue
		name_boxes.append(nbox)
		_placed.append(nbox)
		names.append([p, dname, nsz, Color(1, 1, 1, name_a) if seen else Color(0.7, 0.8, 0.9, name_a * 0.65)])
	for key: String in keys:
		var e: Array = cl[key]
		var n: int = e[1]
		var mk2: Dictionary = e[2]
		var c2: Vector2 = (e[0] as Vector2) / float(n)
		var kind: StringName = mk2["kind"]
		var rr := r_badge * (1.5 if kind == &"mission" else 1.0)
		if kind == &"mission":
			var ph := 0.5 + 0.5 * sin(_anim * 4.0)
			_map.draw_arc(c2, rr * (1.5 + 0.35 * ph), 0.0, TAU, 32, Color(KIND_COLOR[kind], 0.9 - 0.5 * ph), 4.0 * s, true)
		MapIcons.draw(_map, kind, c2, rr, KIND_COLOR[kind])
		drawn["markers"] = int(drawn["markers"]) + 1
		(drawn["badges"] as Array).append([c2, rr, kind, n])
		if n > 1:
			_label_out(font, c2 + Vector2(rr * 0.9, -rr * 0.7), str(n), int(18.0 * s), Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_LEFT, true)
		elif ALWAYS_KINDS.has(kind) or (zoom_f >= 3.0 and labels_left > 0 and kind != &"interior"):
			if not ALWAYS_KINDS.has(kind):
				labels_left -= 1
			_label_out(font, c2 + Vector2(0.0, rr + 18.0 * s), String(mk2.get("label", "")), int(20.0 * s), Color(KIND_COLOR[kind]).lerp(Color.WHITE, 0.4), HORIZONTAL_ALIGNMENT_CENTER, true)
	if objective.is_finite() and not view.grow(-30.0 * s).has_point(objective):
		_edge_marker(objective, s, KIND_COLOR[&"mission"])                    # the objective is off screen: an arrow at the edge points to it
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
	# legend panel: opaque, so the chips never sit on top of busy streets (the chips are children of the screen above this layer)
	_map.draw_rect(_right_rect, Color(0.0, 0.015, 0.03, 0.96))
	_map.draw_rect(Rect2(_right_rect.position, Vector2(2.0 * s, _right_rect.size.y)), Color(UiUtil.CYAN, 0.35))
	_map.draw_rect(_legend_rect, Color(0.0, 0.015, 0.03, 0.96))
	_map.draw_rect(_legend_rect, Color(UiUtil.CYAN, 0.35), false, 2.0 * s)
	# north, scale bar and the gesture hint
	var ins := UiUtil.insets(get_viewport().get_visible_rect().size)
	var rx := sz.x - ins.y - 12.0 * s - 164.0 * s
	var nc := Vector2(rx - 34.0 * s, 40.0 * s)
	_map.draw_circle(nc, 22.0 * s, Color(0.01, 0.03, 0.05, 0.9))
	_map.draw_arc(nc, 22.0 * s, 0.0, TAU, 24, Color(UiUtil.CYAN, 0.8), 2.0 * s, true)
	_map.draw_colored_polygon(PackedVector2Array([nc + Vector2(0, -17.0 * s), nc + Vector2(6.0 * s, -4.0 * s), nc + Vector2(-6.0 * s, -4.0 * s)]), UiUtil.CYAN)
	_label_out(font, nc + Vector2(0.0, 18.0 * s), "N", int(18.0 * s), Color(1, 1, 1, 0.95))
	var bar_m := 200.0 if zoom_f < 2.0 else (100.0 if zoom_f < 5.0 else 50.0)
	var bar_px := bar_m * pm
	var bx0 := rx + 82.0 * s - bar_px * 0.5
	var by0 := sz.y - 22.0 * s
	_map.draw_line(Vector2(bx0, by0), Vector2(bx0 + bar_px, by0), Color(1, 1, 1, 0.85), 3.0 * s)
	_map.draw_line(Vector2(bx0, by0 - 6.0 * s), Vector2(bx0, by0 + 6.0 * s), Color(1, 1, 1, 0.85), 3.0 * s)
	_map.draw_line(Vector2(bx0 + bar_px, by0 - 6.0 * s), Vector2(bx0 + bar_px, by0 + 6.0 * s), Color(1, 1, 1, 0.85), 3.0 * s)
	_label_out(font, Vector2(rx + 82.0 * s, by0 - 12.0 * s), "%d M" % int(bar_m), int(16.0 * s), Color(1, 1, 1, 0.9))
	var hint := "TAP A MARKER OR THE MAP: ROUTE.  PINCH: ZOOM" if not has_waypoint() else "TAP THE WAYPOINT TO REMOVE IT.  PINCH: ZOOM"
	_title_row(font, s)
	if _open_age < HINT_SECONDS or selected.has("pos"):                  # the hint leaves after a few seconds: it sat on top of the names and the route
		var hs := int(20.0 * s)
		var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
		_map.draw_rect(Rect2(sz.x * 0.5 - hw * 0.5 - 12.0 * s, sz.y - 40.0 * s, hw + 24.0 * s, 32.0 * s), Color(0.0, 0.02, 0.04, 0.9))
		_label_out(font, Vector2(sz.x * 0.5, sz.y - 16.0 * s), hint, hs, Color(1, 1, 1, 0.85))


## "MAP" and the charted / route line, top left above the legend.
func _title_row(font: Font, s: float) -> void:
	_label_out(font, Vector2(_x0, 42.0 * s), "MAP", int(32.0 * s), UiUtil.CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	_label_out(font, Vector2(_x0 + 100.0 * s, 40.0 * s), _sub_text, int(22.0 * s), Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_LEFT)


## A polyline without points that are not finite (an infinite or NaN point would make the chevron walk run forever).
static func clean_polyline(pl: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pl:
		if is_finite(p.x) and is_finite(p.y):
			out.append(p)
	return out


## Small arrowheads along a polyline every ~80 px, pointing along its direction.
func _chevrons(pl: PackedVector2Array, col: Color, s: float) -> void:
	var step := maxf(80.0 * s, 16.0)
	var acc := step * 0.5
	var left := MAX_CHEVRONS                                            # a bound on the walk: no polyline, however long, can make this loop run for long
	var view := Rect2(Vector2.ZERO, _map.size).grow(step)
	for i in range(1, pl.size()):
		var a := pl[i - 1]
		var b := pl[i]
		var l := a.distance_to(b)
		if l < 1.0 or not is_finite(l):
			continue
		if not view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
			acc = fposmod(acc - l, step)                                # off screen: keep the rhythm, draw nothing
			continue
		var dir := (b - a) / l
		var side := Vector2(-dir.y, dir.x)
		var t := acc
		while t < l and left > 0:
			left -= 1
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


## An off-screen objective: a coloured arrow on the nearest edge of the view pointing at it.
func _edge_marker(target: Vector2, s: float, col: Color) -> void:
	var sz := _map.size
	var c := sz * 0.5
	var d := (target - c).normalized()
	var p := Vector2(clampf(target.x, 60.0 * s, sz.x - 60.0 * s), clampf(target.y, 60.0 * s, sz.y - 60.0 * s))
	var side := Vector2(-d.y, d.x)
	_map.draw_colored_polygon(PackedVector2Array([p + d * 22.0 * s, p - d * 10.0 * s + side * 16.0 * s, p - d * 10.0 * s - side * 16.0 * s]), Color(0.0, 0.02, 0.04, 1.0))
	_map.draw_colored_polygon(PackedVector2Array([p + d * 17.0 * s, p - d * 7.0 * s + side * 11.0 * s, p - d * 7.0 * s - side * 11.0 * s]), col)


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


## A NEW game starts on a blank map (the persisted discovery file of the last run said "85 % CHARTED" at the first open, director review 4, #9); CONTINUE, a picked chapter and the demo keep theirs.
func _on_new_game() -> void:
	_forget_if_new.call_deferred()


func _forget_if_new() -> void:
	var prog: Object = Game.progress
	if DemoMode.active or path_override != "" or prog == null or not bool(prog.get(&"fresh_game")):
		return
	forget()


## Back to the city core only (the start state): the cells, the waypoint and the file.
func forget() -> void:
	_seen = PackedByteArray()
	_seen.resize(CELLS * CELLS)
	waypoint = Vector3.INF
	reveal_start()
	_fog_hash = 0
	_redraw_wanted = true
	_save()


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
	elif v is PackedByteArray and (v as PackedByteArray).size() == 1024:
		# a save from the 16 x 16 block city (32 x 32 cells): it sits in the middle of the 26 x 26 block map
		var old32: PackedByteArray = v
		_seen = PackedByteArray()
		_seen.resize(CELLS * CELLS)
		var off32 := (CELLS - 32) / 2
		for k in 1024:
			if old32[k] == 1:
				_seen[(k / 32 + off32) * CELLS + (k % 32 + off32)] = 1
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
