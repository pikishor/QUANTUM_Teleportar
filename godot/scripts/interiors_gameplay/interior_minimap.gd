class_name InteriorMinimap
extends RefCounted
## What the minimap draws while the player is inside an interior (hooked in at the top of Minimap._draw): the floor and walls of the generated layout (the interior's `floor_rects`
## and `wall_rects`, as rotated quads: the map turns with the camera), the exit door, vendors, civilians, hostile guards, mission markers and the player arrow, zoomed to RANGE metres.
## The counters are for tests. Nothing allocates per frame beyond the small polygon arrays of the draw call itself (a few dozen quads at 15 Hz).

const RANGE := 24.0
const FLOOR := Color(0.07, 0.2, 0.25, 0.95)
const WALL := Color(0.25, 0.62, 0.74, 0.95)
const ARROW := [Vector2(0, -1.3), Vector2(0.85, 0.9), Vector2(0, 0.4), Vector2(-0.85, 0.9)]

static var floors_drawn := 0
static var walls_drawn := 0
static var markers_drawn := 0
static var last_range := RANGE


static func _quad(mm: Control, r: Rect2, radius: float, c: Vector2, col: Color) -> bool:
	var pts := PackedVector2Array()
	var inside := false
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var m: Vector2 = mm.call(&"to_map", corner.x, corner.y)
		if m.length() < radius:
			inside = true
		pts.append(c + m.limit_length(radius - 2.0))
	if not inside and r.size.x < 60.0 and r.size.y < 60.0 and pts[0].distance_to(c) > radius * 1.6:
		return false
	if not _drawable(pts):
		return false
	mm.draw_colored_polygon(pts, col)
	return true


## True when the four projected corners still make a proper convex quad. Pulling every corner into the map circle (limit_length above) can collapse a rectangle to a
## line or fold it into a bow tie, and draw_colored_polygon then fails to triangulate ("Invalid polygon data": hundreds of errors a minute while walking along some
## walls; found by tests/bot_soak.gd). Such a sliver at the rim is not worth drawing.
static func _drawable(p: PackedVector2Array) -> bool:
	var turn := 0.0
	for i in 4:
		var cr := (p[(i + 1) % 4] - p[i]).cross(p[(i + 2) % 4] - p[(i + 1) % 4])
		if absf(cr) < 0.01 or turn * cr < 0.0:
			return false
		turn = cr
	return true


static func draw(mm: Control, c: Vector2, radius: float, s: float) -> void:
	floors_drawn = 0
	walls_drawn = 0
	markers_drawn = 0
	var ig := InteriorGameplay.instance
	var room: Node3D = ig.interior if ig != null else null
	var k := radius / RANGE
	mm.set(&"_k", k)
	last_range = RANGE
	if room != null:
		for r: Rect2 in room.get("floor_rects"):
			if _quad(mm, r, radius, c, FLOOR):
				floors_drawn += 1
		for r: Rect2 in room.get("wall_rects"):
			if _quad(mm, r, radius, c, WALL):
				walls_drawn += 1
	var inner := radius - 4.0 * s
	var tex_disc := UiUtil.sprite(&"disc")
	var tex_dia := UiUtil.sprite(&"diamond")
	var tex_ring := UiUtil.sprite(&"ring")
	if ig != null:
		var list: Array[Dictionary] = ig.minimap_markers()
		for mk: Dictionary in list:
			var wp: Vector3 = mk["pos"]
			var m: Vector2 = mm.call(&"to_map", wp.x, wp.z)
			var col: Color = mk["color"]
			var kind: StringName = mk["kind"]
			if kind == &"area" or kind == &"zone":
				var rr := maxf(float(mk["radius"]) * k, 7.0 * s)
				if m.length() < inner:
					mm.draw_texture_rect(tex_ring, Rect2(c + m - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(col, 0.7))
					markers_drawn += 1
				continue
			if m.length() > inner:
				m = m.normalized() * inner
			var hs := float(mk.get("size", 4.2)) * s
			var tex := tex_disc if kind == &"disc" else tex_dia
			mm.draw_texture_rect(tex, Rect2(c + m - Vector2(hs, hs), Vector2(hs, hs) * 2.0), false, col)
			markers_drawn += 1
	mm.draw_set_transform(c, 0.0, Vector2(5.0, 5.0) * s)
	mm.draw_colored_polygon(PackedVector2Array(ARROW), Color(1, 1, 1, 0.95))
	mm.draw_set_transform(Vector2.ZERO)
	mm.draw_arc(c, radius, 0.0, TAU, 56, Color(UiUtil.CYAN, 0.55), 1.6 * s, false)
