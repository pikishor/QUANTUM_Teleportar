class_name Minimap
extends Control
## Circular minimap, rotated so the view direction is up. The static layer (roads and building footprints from Game.world.building_rects) is rendered
## once into a texture and drawn as ONE textured polygon; only the markers (enemies, cars, pickups, beacon, clone, cores clamped to the rim) are drawn live,
## and the whole thing redraws at about 15 Hz.

const RANGE_M := 130.0              ## metres from the centre to the rim
const REFRESH := 1.0 / 15.0
const EXTENT := 360.0               ## the texture covers |x|, |z| <= EXTENT
const TEX_PX := 512
const SEGMENTS := 44
const DIAMOND := [Vector2(0, -1), Vector2(0.8, 0), Vector2(0, 1), Vector2(-0.8, 0)]
const ARROW := [Vector2(0, -1.3), Vector2(0.85, 0.9), Vector2(0, 0.4), Vector2(-0.85, 0.9)]

var tex: ImageTexture
var markers_drawn := 0              ## markers inside the rim in the last redraw (for tests)
var core_markers := 0               ## cores drawn (clamped to the rim when far) in the last redraw

var _key := 0
var _t := 0.0
var _pts := PackedVector2Array()
var _uvs := PackedVector2Array()
var _diamond := PackedVector2Array(DIAMOND)
var _arrow := PackedVector2Array(ARROW)
var _fwd := Vector2(0, -1)
var _right := Vector2(1, 0)
var _pos := Vector2.ZERO
var _k := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pts.resize(SEGMENTS)
	_uvs.resize(SEGMENTS)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH
		queue_redraw()


## (Re)builds the cached static layer when the world changed. Returns true when a texture exists.
func ensure_static() -> bool:
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	if w == null:
		return tex != null
	var rects: Variant = w.get("building_rects")
	if not (rects is Array):
		return tex != null
	var key := hash([w.get_instance_id(), (rects as Array).size()])
	if tex != null and key == _key:
		return true
	_key = key
	var img := Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.025, 0.07, 0.09))
	var ppm := float(TEX_PX) / (2.0 * EXTENT)
	var road := Color(0.07, 0.19, 0.24)
	var half_road := Game.ROAD * 0.5
	for i in Game.N + 1:
		var c := -Game.HALF + i * Game.PITCH
		_fill(img, Rect2(c - half_road, -EXTENT, Game.ROAD, 2.0 * EXTENT), ppm, road)
		_fill(img, Rect2(-EXTENT, c - half_road, 2.0 * EXTENT, Game.ROAD), ppm, road)
	var roof := Color(0.2, 0.5, 0.62)
	for r in rects as Array:
		if r is Rect2:
			_fill(img, (r as Rect2).grow(-0.5), ppm, roof)
	tex = ImageTexture.create_from_image(img)
	return true


func _fill(img: Image, r: Rect2, ppm: float, col: Color) -> void:
	var x0 := clampi(floori((r.position.x + EXTENT) * ppm), 0, TEX_PX)
	var y0 := clampi(floori((r.position.y + EXTENT) * ppm), 0, TEX_PX)
	var x1 := clampi(ceili((r.end.x + EXTENT) * ppm), 0, TEX_PX)
	var y1 := clampi(ceili((r.end.y + EXTENT) * ppm), 0, TEX_PX)
	if x1 > x0 and y1 > y0:
		img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), col)


## World (x, z) to minimap pixels relative to the centre, for the current view heading.
func to_map(wx: float, wz: float) -> Vector2:
	var d := Vector2(wx, wz) - _pos
	return Vector2(d.dot(_right), -d.dot(_fwd)) * _k


func _update_view(radius: float) -> void:
	var p := Game.player if is_instance_valid(Game.player) else null
	if p != null:
		_pos = Vector2(p.global_position.x, p.global_position.z)
	var f := Vector2(0, -1)
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		f = Vector2(cf.x, cf.z)
	elif p != null:
		f = Vector2(-sin(p.rotation.y), -cos(p.rotation.y))
	if f.length() > 0.001:
		_fwd = f.normalized()
	_right = Vector2(-_fwd.y, _fwd.x)
	_k = radius / RANGE_M


func _draw() -> void:
	var s := UiUtil.ui_scale(get_viewport_rect().size)
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	_update_view(radius)
	markers_drawn = 0
	core_markers = 0
	draw_circle(c, radius, Color(0.02, 0.06, 0.08, 0.82))
	if ensure_static():
		var inv := 1.0 / (2.0 * EXTENT)
		for i in SEGMENTS:
			var a := TAU * float(i) / SEGMENTS
			var l := Vector2(cos(a), sin(a)) * radius
			_pts[i] = c + l
			var w := _pos + _right * (l.x / _k) - _fwd * (l.y / _k)
			_uvs[i] = Vector2((w.x + EXTENT) * inv, (w.y + EXTENT) * inv)
		draw_colored_polygon(_pts, Color(1, 1, 1, 0.9), _uvs, tex)
	var inner := radius - 3.0 * s
	var own: Object = Game.player.get("vehicle") if is_instance_valid(Game.player) else null
	# cars (faint), enemies, pickups
	for v: Node in get_tree().get_nodes_in_group(&"vehicle"):
		var vn := v as Node3D
		if vn != null and vn.visible and vn != own:
			var m := to_map(vn.global_position.x, vn.global_position.z)
			if m.length() < inner:
				draw_rect(Rect2(c + m - Vector2(1.5, 1.5) * s, Vector2(3, 3) * s), Color(0.7, 0.75, 0.8, 0.6))
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		var en := e as Node3D
		if en != null and en.visible and en.get("dead") != true:
			var m := to_map(en.global_position.x, en.global_position.z)
			if m.length() < inner:
				draw_circle(c + m, 2.6 * s, UiUtil.RED)
				markers_drawn += 1
	var mis: Object = Game.missions if is_instance_valid(Game.missions) else null
	if mis != null:
		var picks: Variant = mis.get("pickups")
		if picks is Array:
			for pk in picks as Array:
				var pd: Dictionary = pk
				var pp: Vector3 = pd.get("pos", Vector3.ZERO)
				var m := to_map(pp.x, pp.z)
				if m.length() < inner:
					draw_set_transform(c + m, 0.0, Vector2(3.4, 3.4) * s)
					draw_colored_polygon(_diamond, UiUtil.GREEN if pd.get("kind", &"health") == &"health" else UiUtil.CYAN)
					draw_set_transform(Vector2.ZERO)
					markers_drawn += 1
	var q: Object = Game.player.get("quantum") if is_instance_valid(Game.player) else null
	if q != null:
		if q.get("has_beacon") == true:
			var bp: Variant = q.get("beacon_pos")
			if bp is Vector3:
				var m := to_map((bp as Vector3).x, (bp as Vector3).z)
				if m.length() < inner:
					draw_arc(c + m, 3.5 * s, 0.0, TAU, 12, UiUtil.CYAN, 1.5 * s)
		var cl := q.get("clone") as Node3D
		if is_instance_valid(cl):
			var m := to_map(cl.global_position.x, cl.global_position.z)
			if m.length() < inner:
				draw_circle(c + m, 3.0 * s, UiUtil.CYAN)
	# quantum cores: magenta diamonds, pinned to the rim and pointing outward when far
	if mis != null:
		var cores: Variant = mis.get("cores")
		if cores is Array:
			for cd in cores as Array:
				var cp: Vector3 = (cd as Dictionary).get("pos", Vector3.ZERO)
				var m := to_map(cp.x, cp.z)
				var far := m.length() > inner - 4.0 * s
				if far:
					m = (m.normalized() if m.length() > 0.001 else Vector2(0, -1)) * (inner - 4.0 * s)
				draw_set_transform(c + m, 0.0, Vector2(4.2, 4.2) * s)
				draw_colored_polygon(_diamond, UiUtil.MAGENTA)
				draw_set_transform(Vector2.ZERO)
				if not far:
					draw_arc(c + m, 7.0 * s, 0.0, TAU, 16, Color(UiUtil.MAGENTA, 0.6), 1.2 * s)
				core_markers += 1
	# the player: fixed arrow in the middle
	draw_set_transform(c, 0.0, Vector2(5.0, 5.0) * s)
	draw_colored_polygon(_arrow, Color(1, 1, 1, 0.95))
	draw_set_transform(Vector2.ZERO)
	# north tick and the rim
	var nl := Vector2(Vector2(0, -1).dot(_right), -Vector2(0, -1).dot(_fwd))
	draw_string(UiUtil.font(), c + nl * (radius - 9.0 * s) + Vector2(-4.0, 5.0) * s, "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(13.0 * s), Color(UiUtil.CYAN, 0.9))
	draw_arc(c, radius, 0.0, TAU, 56, Color(UiUtil.CYAN, 0.55), 1.6 * s, true)
