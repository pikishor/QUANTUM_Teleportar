class_name MapScreen
extends CanvasLayer
## H3 full-screen map. Reached by tapping the minimap (touch), or key M. Pauses through Game.state only (&"paused"), closing resumes the previous state.
## - Eight zones (Districts.ZONE_TITLES: the four core districts and the four outer ones of the big city) as tinted areas of the 32 x 32 grid (CELL m). Cells you have not walked near (DISCOVER_R) sit under fog: no zone name, no markers.
## - ZOOM (button `Zoom`): 1x the whole 1280 m map, 2x and 4x centred on you; drag to pan when zoomed. `zoom`, `view_center`, `set_zoom(z)`.
## - Tap the map to place ONE custom waypoint (a ring plus a route line from you); tapping it again, or CLEAR, removes it. Saved in user://map.cfg with the discovered cells.
## - Markers (legend + filters): MISSION (campaign goal, always shown), SIDE (contract marker + mission doors), ITEMS (uncollected shards), GARAGE (warehouse doors), SHOP (vendor doors).
## - There is no fast travel. Buttons by name: Close, Clear, F_mission, F_side, F_items, F_garage, F_shop. The map area is the Control "Map" (tap = _tap(pos)).
## API: open() close_screen() is_open() discover(pos) is_discovered(x, z) discovered_count() set_waypoint(v3) clear_waypoint() has_waypoint() world_to_map(x, z) map_to_world(p)
## marker_counts() -> {kind: n} of markers currently shown (fog + filters applied).

signal closed

const Districts := preload("res://scripts/world/city_districts.gd")

const CELLS := 32
const CELL := 40.0                                  ## metres per cell (CELLS * CELL = 1280 = 2 * CityLayout.HALF)
const HALF := CELLS * CELL * 0.5
const ZOOMS: Array[int] = [1, 2, 4]
const DRAG_PX := 14.0
const DISCOVER_R := 70.0
const KINDS: Array[StringName] = [&"mission", &"side", &"items", &"garage", &"shop", &"home"]
const KIND_LABEL := {&"mission": "MISSION", &"side": "SIDE", &"items": "ITEMS", &"garage": "GARAGE", &"shop": "SHOP", &"home": "HOME"}
const KIND_COLOR := {&"mission": Color(1.0, 0.75, 0.15), &"side": Color(0.2, 0.9, 1.0), &"items": Color(0.75, 0.45, 1.0), &"garage": Color(1.0, 0.45, 0.2), &"shop": Color(0.3, 1.0, 0.55), &"home": Color(1.0, 1.0, 1.0)}
const SAVE_PATH := "user://map.cfg"
static var path_override := ""             ## DEMO MODE points the map at its own file (scripts/demo/demo_mode.gd); "" = SAVE_PATH
const GARAGE_TYPES: Array[StringName] = [&"warehouse", &"cargo_bay"]
const TAP_CLEAR_PX := 28.0

var waypoint := Vector3.INF
var filters := {&"mission": true, &"side": true, &"items": true, &"garage": true, &"shop": true, &"home": true}

var zoom := 1                                        ## index into ZOOMS' values: 1, 2 or 4 (the map shows 2 * HALF / zoom metres across)
var view_center := Vector2.ZERO                      ## world (x, z) at the middle of the square when zoomed in
var _press := Vector2.INF
var _dragging := false
var _seen := PackedByteArray()
var _open := false
var _resume := &"play"
var _root: Control
var _map: Control
var _title: Label
var _zoom_btn: Button
var _btns := {}
var _rect := Rect2()                                 ## the square map inside _map (control px)
var _counts := {}
var _t := 0.0
var _dirty := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_seen.resize(CELLS * CELLS)
	_load()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.04, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12.0
	box.offset_right = -12.0
	box.offset_top = 8.0
	box.offset_bottom = -8.0
	box.add_theme_constant_override("separation", 6)
	_root.add_child(box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	box.add_child(bar)
	_title = _label(bar, "MAP", 28, UiUtil.CYAN)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for k in KINDS:
		var b := _button(bar, String(KIND_LABEL[k]), StringName("F_%s" % k))
		b.toggle_mode = true
		b.button_pressed = true
		b.pressed.connect(_on_filter.bind(k))
		_btns[k] = b
	_zoom_btn = _button(bar, "ZOOM 1X", &"Zoom")
	_zoom_btn.pressed.connect(cycle_zoom)
	_button(bar, "CLEAR", &"Clear").pressed.connect(clear_waypoint)
	_button(bar, "CLOSE", &"Close").pressed.connect(close_screen)
	_map = Control.new()
	_map.name = "Map"
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	box.add_child(_map)
	_map.resized.connect(_update_rect)


func _label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, nm: StringName) -> Button:
	var b := Button.new()
	b.name = String(nm)
	b.text = text
	b.custom_minimum_size = Vector2(64, 64)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


# ---------------------------------------------------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	if _open:
		_map.queue_redraw()
	elif Game.state == &"play" and is_instance_valid(Game.player):
		discover(Game.player.global_position)
	if _dirty and not _open:
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


## Marks every cell whose centre is within DISCOVER_R + half a cell of pos.
func discover(pos: Vector3) -> void:
	if _seen.size() != CELLS * CELLS:
		_seen.resize(CELLS * CELLS)
	for i in CELLS * CELLS:
		if _seen[i] == 0 and cell_center(i).distance_to(Vector2(pos.x, pos.z)) <= DISCOVER_R + CELL * 0.5:
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
	_dirty = true
	if _map != null:
		_map.queue_redraw()


func clear_waypoint() -> void:
	waypoint = Vector3.INF
	_dirty = true
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
	set_zoom(1)
	_update_rect()
	_map.queue_redraw()


func close_screen() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_save()
	if Game.state == &"paused":
		Game.state = _resume
	closed.emit()


# ---------------------------------------------------------------------------------------------------------------------
# map space
# ---------------------------------------------------------------------------------------------------------------------

func _update_rect() -> void:
	var sz := _map.size
	var side := maxf(minf(sz.x, sz.y), 1.0)
	_rect = Rect2((sz.x - side) * 0.5, (sz.y - side) * 0.5, side, side)


## Metres across the square at the current zoom.
func span() -> float:
	return 2.0 * HALF / float(zoom)


## World (x, z) of the square's upper left corner.
func _view_origin() -> Vector2:
	return view_center - Vector2(span(), span()) * 0.5


func world_to_map(x: float, z: float) -> Vector2:
	return _rect.position + ((Vector2(x, z) - _view_origin()) / span()) * _rect.size


func map_to_world(p: Vector2) -> Vector3:
	var u := (p - _rect.position) / _rect.size
	var w := _view_origin() + Vector2(clampf(u.x, 0.0, 1.0), clampf(u.y, 0.0, 1.0)) * span()
	return Vector3(clampf(w.x, -HALF, HALF), 0.0, clampf(w.y, -HALF, HALF))


## Next zoom level: whole map, then 2x and 4x around you (the hero, or the map centre when no hero exists).
func cycle_zoom() -> void:
	set_zoom(ZOOMS[(ZOOMS.find(zoom) + 1) % ZOOMS.size()])


func set_zoom(z: int) -> void:
	zoom = z if ZOOMS.has(z) else 1
	if zoom == 1:
		view_center = Vector2.ZERO
	elif is_instance_valid(Game.player):
		var pp: Vector3 = Game.player.global_position
		view_center = Vector2(pp.x, pp.z)
	_clamp_view()
	if _zoom_btn != null:
		_zoom_btn.text = "ZOOM %dX" % zoom
	if _map != null:
		_map.queue_redraw()


func pan(by_world: Vector2) -> void:
	view_center += by_world
	_clamp_view()
	if _map != null:
		_map.queue_redraw()


func _clamp_view() -> void:
	var lim := HALF - span() * 0.5
	view_center = Vector2(clampf(view_center.x, -lim, lim), clampf(view_center.y, -lim, lim))


func _on_map_input(event: InputEvent) -> void:
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
		if zoom == 1:
			_tap(p)                      # the whole map cannot be panned: a tap places the waypoint at once
			_press = Vector2.INF
	elif drag != Vector2.ZERO and _press.is_finite():
		if not _dragging and p.distance_to(_press) > DRAG_PX * UiUtil.ui_scale(get_viewport().get_visible_rect().size):
			_dragging = true
		if _dragging:
			pan(-drag / _rect.size.x * span())
	elif up and _press.is_finite():
		if not _dragging:
			_tap(p)
		_press = Vector2.INF
		_dragging = false


## A tap at control position p: on the waypoint removes it, on the map places it.
func _tap(p: Vector2) -> void:
	if not _rect.has_point(p):
		return
	if has_waypoint() and world_to_map(waypoint.x, waypoint.z).distance_to(p) <= _tap_clear_px():
		clear_waypoint()
	else:
		set_waypoint(map_to_world(p))
	Sfx.play(&"ui_tap")


func _tap_clear_px() -> float:
	return TAP_CLEAR_PX * UiUtil.ui_scale(get_viewport().get_visible_rect().size)


# ---------------------------------------------------------------------------------------------------------------------
# markers
# ---------------------------------------------------------------------------------------------------------------------

## All markers of the world: [{kind, pos: Vector3, fog: bool (hidden under fog)}], before filters.
func collect_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: Node = Game.missions
	if is_instance_valid(m):
		var camp: Object = m.get("campaign")
		if camp != null:
			var wp: Dictionary = camp.call(&"waypoint")
			if wp.has("pos"):
				out.append({"kind": &"mission", "pos": wp["pos"], "fog": false})
		var con: Object = m.get("contracts")
		if con != null and StringName(con.get("state")) in [&"offered", &"active"]:
			var cp: Vector3 = con.get("pos")
			if cp.is_finite():
				out.append({"kind": &"side", "pos": cp, "fog": false})
	if is_instance_valid(Game.world):
		for d: Dictionary in Game.world.get("doors"):
			var t: StringName = d["type"]
			var kind := &""
			if GARAGE_TYPES.has(t):
				kind = &"garage"
			elif InteriorData.has_vendor(t):
				kind = &"shop"
			elif InteriorData.MISSION_TYPES.has(t):
				kind = &"side"
			if kind != &"":
				var p: Vector3 = d["pos"]
				out.append({"kind": kind, "pos": p, "fog": true})
	var prog := Game.progress as Progress
	for sh: Dictionary in Safehouses.markers(prog):
		out.append({"kind": &"home", "pos": sh["pos"], "fog": false})      # owned safehouses: fast-save points
	if prog != null and prog.collectibles != null:
		var spots := Collectibles.spots()
		for i in spots.size():
			if not prog.collectibles.is_collected(i):
				out.append({"kind": &"items", "pos": spots[i], "fog": true})
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


# ---------------------------------------------------------------------------------------------------------------------
# drawing (paused screen, so a few extra draws do not matter)
# ---------------------------------------------------------------------------------------------------------------------

func _draw_map() -> void:
	if _rect.size.x < 8.0:
		return
	var font := ThemeDB.fallback_font
	var s := UiUtil.ui_scale(get_viewport().get_visible_rect().size)
	var cs := _rect.size.x / (span() / CELL)               # one cell on screen
	var seen_n := 0
	_map.draw_rect(_rect, Color(0.01, 0.02, 0.04, 1.0))
	# zones: every cell tinted with the accent of its zone (core district or outer zone), then fog on top of the cells not yet visited
	for i in CELLS * CELLS:
		var c0 := cell_center(i)
		var r := Rect2(world_to_map(c0.x - CELL * 0.5, c0.y - CELL * 0.5), Vector2(cs, cs))
		var seen_c := _seen[i] == 1
		if seen_c:
			seen_n += 1
		if not r.intersects(_rect):
			continue
		var acc: Color = Districts.palette(Districts.look_at(c0.x, c0.y))["accent"]
		var k := 0.18 if Districts.zone_at(c0.x, c0.y) < Districts.COUNT else 0.11       # the outer zones are dimmer than the core
		_map.draw_rect(r.intersection(_rect), Color(acc.r * k, acc.g * k, acc.b * k, 1.0))
		if seen_c:
			if zoom > 1:
				_map.draw_rect(r.intersection(_rect), Color(1, 1, 1, 0.045), false, 1.0)
		else:
			_map.draw_rect(r.intersection(_rect), Color(0.01, 0.02, 0.04, 0.82))
	# the original core (the first sector) is outlined so the player sees where the big city starts
	var core_a := world_to_map(-CityLayout.CORE_HALF, -CityLayout.CORE_HALF)
	var core_b := world_to_map(CityLayout.CORE_HALF, CityLayout.CORE_HALF)
	_map.draw_rect(Rect2(core_a, core_b - core_a), Color(1, 1, 1, 0.16), false, 1.5)
	_map.draw_rect(_rect, Color(1, 1, 1, 0.35), false, 2.0)
	var zone_names: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	for d in zone_names:
		var tc := _zone_label_pos(d)
		var p := world_to_map(tc.x, tc.y)
		if not _rect.grow(-30.0).has_point(p):
			continue
		var seen := zone_discovered(d)
		var dname := Districts.zone_title(d) if seen else "UNCHARTED"
		var fs := int((22.0 if d < Districts.COUNT else 18.0) * s)
		var w := font.get_string_size(dname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_map.draw_string(font, p + Vector2(-w * 0.5, 0.0), dname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85 if seen else 0.35))
	# waypoint route
	var you := Vector2.INF
	if is_instance_valid(Game.player):
		var pp: Vector3 = Game.player.global_position
		you = world_to_map(pp.x, pp.z)
		if not _rect.grow(12.0).has_point(you):
			you = Vector2.INF
	if has_waypoint():
		var wpm := world_to_map(waypoint.x, waypoint.z)
		if you.is_finite():
			_map.draw_dashed_line(you, wpm, Color(1, 1, 1, 0.85), 3.0, 10.0)
		if _rect.grow(12.0).has_point(wpm):
			_map.draw_arc(wpm, 12.0 * s, 0.0, TAU, 20, Color(1, 1, 1, 0.95), 3.0)
			_map.draw_circle(wpm, 4.0 * s, Color(1, 1, 1, 0.95))
	# markers
	_counts.clear()
	for mk in visible_markers():
		var k: StringName = mk["kind"]
		var pw: Vector3 = mk["pos"]
		var mp := world_to_map(pw.x, pw.z)
		if not _rect.grow(8.0).has_point(mp):
			continue
		var col: Color = KIND_COLOR[k]
		var rr := (8.0 if k == &"mission" else 5.5) * s
		if k == &"mission" or k == &"side":
			_map.draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -rr), mp + Vector2(rr, 0), mp + Vector2(0, rr), mp + Vector2(-rr, 0)]), col)
		elif k == &"items":
			_map.draw_circle(mp, rr * 0.8, col)
		elif k == &"home":
			_map.draw_arc(mp, rr * 1.2, 0.0, TAU, 16, col, 2.5 * s)
			_map.draw_circle(mp, rr * 0.5, col)
		else:
			_map.draw_rect(Rect2(mp - Vector2(rr, rr) * 0.8, Vector2(rr, rr) * 1.6), col)
		_counts[k] = int(_counts.get(k, 0)) + 1
	if you.is_finite():
		_map.draw_colored_polygon(PackedVector2Array([you + Vector2(0, -10) * s, you + Vector2(8, 8) * s, you + Vector2(0, 3) * s, you + Vector2(-8, 8) * s]), Color(1, 1, 1))
	_title.text = "MAP   %d%% CHARTED" % int(round(100.0 * seen_n / (CELLS * CELLS)))
	# legend, left of the square (or inside the corner when the screen is narrow)
	var lx := 14.0 * s
	var ly := 20.0 * s
	var fs2 := int(18.0 * s)
	for k in KINDS:
		var col2: Color = KIND_COLOR[k]
		var on := bool(filters.get(k, true))
		_map.draw_rect(Rect2(lx, ly - 12.0 * s, 14.0 * s, 14.0 * s), Color(col2, 1.0 if on else 0.3))
		_map.draw_string(font, Vector2(lx + 22.0 * s, ly), String(KIND_LABEL[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, 0.9 if on else 0.4))
		ly += 26.0 * s
	_map.draw_string(font, Vector2(lx, ly + 6.0 * s), "TAP = WAYPOINT", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, 0.7))


# ---------------------------------------------------------------------------------------------------------------------
# save
# ---------------------------------------------------------------------------------------------------------------------

static func file_path() -> String:
	return path_override if path_override != "" else SAVE_PATH


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
