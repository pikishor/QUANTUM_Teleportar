class_name TriPen
extends RefCounted
## w129-integrator: a pen with the CanvasItem drawing calls MapIcons uses (draw_circle, draw_arc, draw_line, draw_polyline, draw_colored_polygon, draw_rect,
## draw_string). Every shape is collected as triangles and painted by ONE canvas_item_add_triangle_array in flush(); the words follow it. On the Mobile renderer each
## circle, arc, line and polygon of a glyph was its own canvas draw (the minimap's place pins at the airfield: about 10 canvas draws for three glyphs).
##   var pen := TriPen.new();  MapIcons.draw(pen, &"airport", at, r, col);  ...;  pen.flush(self)

var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _texts: Array = []


func is_empty() -> bool:
	return _idx.is_empty() and _texts.is_empty()


func _fan(pts: PackedVector2Array, col: Color) -> void:
	var b := _pts.size()
	for q in pts:
		_pts.append(q)
		_cols.append(col)
	for i in range(1, pts.size() - 1):
		_idx.append(b)
		_idx.append(b + i)
		_idx.append(b + i + 1)


func _quad(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	if a.distance_squared_to(b) < 1.0e-8:
		return
	var d := (b - a).normalized().orthogonal() * maxf(w, 1.0) * 0.5
	_fan(PackedVector2Array([a + d, b + d, b - d, a - d]), col)


func draw_circle(c: Vector2, r: float, col: Color, _filled := true, _width := -1.0, _aa := false) -> void:
	var n := clampi(int(r * 1.2), 12, 40)
	var pts := PackedVector2Array()
	for i in n:
		pts.append(c + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	_fan(pts, col)


func draw_arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w := 1.0, _aa := false) -> void:
	var ww := maxf(w, 1.0)
	var ri := r - ww * 0.5
	var ro := r + ww * 0.5
	n = maxi(n, 1)
	for i in n:
		var t0 := lerpf(a0, a1, float(i) / float(n))
		var t1 := lerpf(a0, a1, float(i + 1) / float(n))
		var u0 := Vector2(cos(t0), sin(t0))
		var u1 := Vector2(cos(t1), sin(t1))
		_fan(PackedVector2Array([c + u0 * ri, c + u0 * ro, c + u1 * ro, c + u1 * ri]), col)


func draw_line(a: Vector2, b: Vector2, col: Color, w := 1.0, _aa := false) -> void:
	_quad(a, b, w, col)


func draw_polyline(pts: PackedVector2Array, col: Color, w := 1.0, _aa := false) -> void:
	for i in range(pts.size() - 1):
		_quad(pts[i], pts[i + 1], w, col)


func draw_colored_polygon(pts: PackedVector2Array, col: Color, _uvs := PackedVector2Array(), _tex: Texture2D = null) -> void:
	if pts.size() < 3:
		return
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri.is_empty():
		_fan(pts, col)
		return
	var b := _pts.size()
	for q in pts:
		_pts.append(q)
		_cols.append(col)
	for i in tri:
		_idx.append(b + i)


func draw_rect(r: Rect2, col: Color, filled := true, w := -1.0, _aa := false) -> void:
	if filled:
		_fan(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)
		return
	var ww := maxf(w, 1.0)
	var tl := r.position
	var br := r.end
	_quad(tl, Vector2(br.x, tl.y), ww, col)
	_quad(Vector2(br.x, tl.y), br, ww, col)
	_quad(br, Vector2(tl.x, br.y), ww, col)
	_quad(Vector2(tl.x, br.y), tl, ww, col)


func draw_string(font: Font, pos: Vector2, text: String, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, size := 16, col := Color.WHITE) -> void:
	_texts.append([font, pos, text, align, width, size, col])


## Paints everything collected on `ci` (shapes in one call, then the words) and empties the pen.
func flush(ci: CanvasItem) -> void:
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _idx, _pts, _cols)
	for t: Array in _texts:
		ci.draw_string(t[0], t[1], t[2], t[3], t[4], t[5], t[6])
	_pts.clear()
	_cols.clear()
	_idx.clear()
	_texts.clear()
