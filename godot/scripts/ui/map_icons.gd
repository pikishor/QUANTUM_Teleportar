class_name MapIcons
extends RefCounted
## The marker badges of the map and its legend: one dark disc with a coloured ring and a vector glyph per kind, so a marker reads by SHAPE as well as colour (colour-blind safe):
## mission = diamond, side = exclamation mark, interior = door, job = flag, shop = dollar, garage = car, weapon = crosshair, home = house, items = gem, danger = warning triangle,
## site = peak with a snow cap (the outskirts' sites), you = arrow (drawn by the map itself). `draw(item, kind, centre, radius, colour)` draws on any CanvasItem inside its _draw.

const KINDS: Array[StringName] = [&"mission", &"side", &"interior", &"job", &"shop", &"garage", &"weapon", &"home", &"items", &"danger", &"site"]
## Glyph-only shapes of the big world (a marker's `glyph` field picks one of these over its kind's shape): the airport (a plane), the harbour (an anchor), the city (three towers), the helipad (an H).
const GLYPHS: Array[StringName] = [&"airport", &"harbour", &"city", &"helipad", &"pad"]


static func draw(ci: CanvasItem, kind: StringName, c: Vector2, r: float, col: Color, backing := true) -> void:
	if backing:
		ci.draw_circle(c, r, Color(0.01, 0.03, 0.05, 0.92))
		ci.draw_arc(c, r, 0.0, TAU, 24, col, maxf(r * 0.16, 1.5), true)
	var g := r * 0.58                                   # glyph half size
	match kind:
		&"mission":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g * 1.25), c + Vector2(g * 1.05, 0), c + Vector2(0, g * 1.25), c + Vector2(-g * 1.05, 0)]), col)
		&"side":
			ci.draw_rect(Rect2(c + Vector2(-g * 0.22, -g * 1.05), Vector2(g * 0.44, g * 1.4)), col)
			ci.draw_rect(Rect2(c + Vector2(-g * 0.25, g * 0.55), Vector2(g * 0.5, g * 0.5)), col)
		&"interior":
			ci.draw_rect(Rect2(c + Vector2(-g * 0.75, -g * 1.1), Vector2(g * 1.5, g * 2.2)), col, false, maxf(g * 0.22, 1.5))
			ci.draw_circle(c + Vector2(g * 0.35, g * 0.1), maxf(g * 0.2, 1.2), col)
		&"job":
			ci.draw_line(c + Vector2(-g * 0.7, g), c + Vector2(-g * 0.7, -g), col, maxf(g * 0.2, 1.5))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-g * 0.7, -g), c + Vector2(g * 0.95, -g * 0.4), c + Vector2(-g * 0.7, g * 0.2)]), col)
		&"shop":
			var f := ThemeDB.fallback_font
			var fs := int(maxf(r * 1.5, 10.0))
			var w := f.get_string_size("$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		&"garage":
			ci.draw_rect(Rect2(c + Vector2(-g * 1.15, -g * 0.1), Vector2(g * 2.3, g * 0.75)), col)
			ci.draw_rect(Rect2(c + Vector2(-g * 0.6, -g * 0.75), Vector2(g * 1.2, g * 0.7)), col)
			ci.draw_circle(c + Vector2(-g * 0.65, g * 0.7), g * 0.3, Color(0.01, 0.03, 0.05))
			ci.draw_circle(c + Vector2(g * 0.65, g * 0.7), g * 0.3, Color(0.01, 0.03, 0.05))
		&"weapon":
			ci.draw_arc(c, g * 0.8, 0.0, TAU, 14, col, maxf(g * 0.2, 1.5))
			ci.draw_line(c + Vector2(-g * 1.2, 0), c + Vector2(-g * 0.3, 0), col, maxf(g * 0.2, 1.5))
			ci.draw_line(c + Vector2(g * 0.3, 0), c + Vector2(g * 1.2, 0), col, maxf(g * 0.2, 1.5))
			ci.draw_line(c + Vector2(0, -g * 1.2), c + Vector2(0, -g * 0.3), col, maxf(g * 0.2, 1.5))
			ci.draw_line(c + Vector2(0, g * 0.3), c + Vector2(0, g * 1.2), col, maxf(g * 0.2, 1.5))
		&"home":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g * 1.2), c + Vector2(g * 1.2, -g * 0.1), c + Vector2(g * 0.85, -g * 0.1), c + Vector2(g * 0.85, g * 0.95), c + Vector2(-g * 0.85, g * 0.95), c + Vector2(-g * 0.85, -g * 0.1), c + Vector2(-g * 1.2, -g * 0.1)]), col)
		&"items":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g), c + Vector2(g * 0.9, -g * 0.2), c + Vector2(0, g), c + Vector2(-g * 0.9, -g * 0.2)]), col)
		&"site":                                          # a peak with a snow cap: the sites of the outskirts
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-g * 1.25, g * 0.85), c + Vector2(-g * 0.25, -g * 0.95), c + Vector2(g * 0.35, -g * 0.1), c + Vector2(g * 0.75, -g * 0.55), c + Vector2(g * 1.25, g * 0.85)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-g * 0.25, -g * 0.95), c + Vector2(-g * 0.62, -g * 0.3), c + Vector2(-g * 0.25, -g * 0.45), c + Vector2(g * 0.05, -g * 0.3)]), Color(0.01, 0.03, 0.05))
		&"airport":                                       # a plane seen from above: fuselage, swept wings, tail
			ci.draw_line(c + Vector2(0, -g * 1.25), c + Vector2(0, g * 1.15), col, maxf(g * 0.34, 1.5))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g * 0.15), c + Vector2(g * 1.3, g * 0.55), c + Vector2(g * 1.3, g * 0.8), c + Vector2(0, g * 0.35), c + Vector2(-g * 1.3, g * 0.8), c + Vector2(-g * 1.3, g * 0.55)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, g * 0.85), c + Vector2(g * 0.6, g * 1.2), c + Vector2(-g * 0.6, g * 1.2)]), col)
		&"harbour":                                       # an anchor: ring, shank, stock, the two flukes
			ci.draw_arc(c + Vector2(0, -g * 0.85), g * 0.28, 0.0, TAU, 12, col, maxf(g * 0.2, 1.5))
			ci.draw_line(c + Vector2(0, -g * 0.55), c + Vector2(0, g * 0.95), col, maxf(g * 0.24, 1.5))
			ci.draw_line(c + Vector2(-g * 0.5, -g * 0.2), c + Vector2(g * 0.5, -g * 0.2), col, maxf(g * 0.22, 1.5))
			ci.draw_arc(c + Vector2(0, g * 0.15), g * 0.95, 0.15, PI - 0.15, 14, col, maxf(g * 0.24, 1.5))
		&"city":                                          # three towers of different heights
			ci.draw_rect(Rect2(c + Vector2(-g * 1.1, -g * 0.1), Vector2(g * 0.6, g * 1.1)), col)
			ci.draw_rect(Rect2(c + Vector2(-g * 0.3, -g * 1.15), Vector2(g * 0.65, g * 2.15)), col)
			ci.draw_rect(Rect2(c + Vector2(g * 0.5, -g * 0.5), Vector2(g * 0.6, g * 1.5)), col)
		&"helipad":                                       # an H in a ring
			ci.draw_arc(c, g * 1.05, 0.0, TAU, 20, col, maxf(g * 0.2, 1.5))
			ci.draw_line(c + Vector2(-g * 0.4, -g * 0.55), c + Vector2(-g * 0.4, g * 0.55), col, maxf(g * 0.22, 1.5))
			ci.draw_line(c + Vector2(g * 0.4, -g * 0.55), c + Vector2(g * 0.4, g * 0.55), col, maxf(g * 0.22, 1.5))
			ci.draw_line(c + Vector2(-g * 0.4, 0), c + Vector2(g * 0.4, 0), col, maxf(g * 0.22, 1.5))
		&"pad":                                           # a quantum pad: a ring with a chevron pointing up
			ci.draw_arc(c, g * 1.05, 0.0, TAU, 20, col, maxf(g * 0.2, 1.5))
			ci.draw_polyline(PackedVector2Array([c + Vector2(-g * 0.55, g * 0.25), c + Vector2(0, -g * 0.4), c + Vector2(g * 0.55, g * 0.25)]), col, maxf(g * 0.24, 1.5))
			ci.draw_line(c + Vector2(-g * 0.4, g * 0.7), c + Vector2(g * 0.4, g * 0.7), col, maxf(g * 0.2, 1.5))
		&"danger":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g * 1.15), c + Vector2(g * 1.15, g * 0.9), c + Vector2(-g * 1.15, g * 0.9)]), col)
			ci.draw_rect(Rect2(c + Vector2(-g * 0.12, -g * 0.4), Vector2(g * 0.24, g * 0.7)), Color(0.01, 0.03, 0.05))
			ci.draw_rect(Rect2(c + Vector2(-g * 0.14, g * 0.45), Vector2(g * 0.28, g * 0.26)), Color(0.01, 0.03, 0.05))
		_:
			ci.draw_circle(c, g * 0.7, col)
