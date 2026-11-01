class_name InteriorMesher
extends RefCounted
## Turns an InteriorPlan into three merged meshes (so an interior is three draw calls, however many props it holds):
##   surface  walls, floors, ceilings, trim, strips, signs and every prop (shaders/interior_surface.gdshader)
##   window   the panes of shop windows and the street door: a fake view of the neon street (shaders/interior_window.gdshader)
##   glow     additive halos round neon and the club's light-show beams (shaders/interior_glow.gdshader)
## The graphics tier only decides how many DETAIL props are drawn (decor and clutter; LOW keeps about a third, MED three quarters, HIGH all) and how finely the floor's baked
## ambient occlusion is sampled; the plan, the colliders and every big prop are the same on every tier.

const MB := preload("res://scripts/world/mesh_builder.gd")

const KEEP := [0.35, 0.75, 1.01]                  ## per tier: the fraction (by each prop's fixed rank) of detail props that is drawn
const FLOOR_CELL := [1.5, 0.75, 0.5]
const EXTERIOR := Color(0.045, 0.045, 0.055)
const FRAME := Color(0.08, 0.08, 0.1)


## {surface: ArrayMesh, window: ArrayMesh or null, glow: ArrayMesh or null, tris: int, props_drawn: int, props_total: int}
static func build(plan: InteriorPlan, quality: int) -> Dictionary:
	quality = clampi(quality, 0, 2)
	var sb := MB.new()
	var wb := MB.new()
	var gb := MB.new()
	for r: Dictionary in plan.rooms:
		_floor(sb, plan, r, quality)
		_ceiling(sb, r)
	for dd: Dictionary in plan.doors:
		_door_floor(sb, plan, dd)
	for s: Dictionary in plan.segs:
		_segment(sb, wb, plan, s)
	for p: Vector2 in plan.posts:
		var h := 3.4
		for r: Dictionary in plan.rooms:
			if (r["rect"] as Rect2).grow(InteriorPlan.T + 0.05).has_point(p):
				h = maxf(h, float(r["h"]))
		sb.uv = Vector2(0.0, h)
		sb.box(Vector3(p.x, h * 0.5, p.y), Vector3(InteriorPlan.T, h, InteriorPlan.T), Color(EXTERIOR.r * 2.0, EXTERIOR.g * 2.0, EXTERIOR.b * 2.0, 0.0), false, Vector2.ZERO, MB.F_TOP)
	for st: Dictionary in plan.strips:
		sb.uv = Vector2(float(st["cls"]), randf_phase(st))
		var col: Color = st["col"]
		sb.strut(st["a"], st["b"], float(st["th"]), Color(col.r, col.g, col.b, float(st["em"])))
		var mid: Vector3 = ((st["a"] as Vector3) + (st["b"] as Vector3)) * 0.5
		var len := ((st["a"] as Vector3) - (st["b"] as Vector3)).length()
		var down := float(st["cls"]) == 8.0
		if len > 1.0:
			var along_x := absf(((st["a"] as Vector3) - (st["b"] as Vector3)).x) > absf(((st["a"] as Vector3) - (st["b"] as Vector3)).z)
			var wv := Vector3(len, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, len)
			var dv := Vector3(0.0, 0.0, 0.45) if along_x else Vector3(0.45, 0.0, 0.0)
			var up := Vector3(0.0, -0.01 if down else 0.0, 0.0)
			if down:
				gb.quad(mid - wv * 0.5 - dv * 1.0 + up, mid + wv * 0.5 - dv * 1.0 + up, mid + wv * 0.5 + dv * 1.0 + up, mid - wv * 0.5 + dv * 1.0 + up, Vector3.DOWN,
					Color(col.r, col.g, col.b, 0.16), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(2, 0), Vector2(3, 0), Vector2(3, 1), Vector2(2, 1)]))
	for b: Dictionary in plan.beams:
		var bc: Color = b["col"]
		var base: Vector3 = b["pos"]
		var segs := 8 if quality > 0 else 6
		gb.funnel(base, 0.05, float(b["radius"]), segs, 0.06, Color(bc.r, bc.g, bc.b, 0.45 if quality > 0 else 0.35))
	var keep: float = KEEP[quality]
	var drawn := 0
	for p: Dictionary in plan.props:
		if bool(p["detail"]) and float(p["rank"]) > keep:
			continue
		InteriorProps.build(sb, gb, p)
		drawn += 1
	var out := {"surface": sb.build(null, false, true), "window": null, "glow": null, "tris": sb.idx.size() / 3, "props_drawn": drawn, "props_total": plan.props.size()}
	if not wb.is_empty():
		out["window"] = wb.build(null, false, true)
		out["tris"] = int(out["tris"]) + wb.idx.size() / 3
	if not gb.is_empty():
		out["glow"] = gb.build(null, false, true)
		out["tris"] = int(out["tris"]) + gb.idx.size() / 3
	return out


static func randf_phase(st: Dictionary) -> float:
	var a: Vector3 = st["a"]
	return fposmod(a.x * 7.31 + a.z * 3.17, 20.0)


# ---------------------------------------------------------------------------------------------------------------------
# floors and ceilings
# ---------------------------------------------------------------------------------------------------------------------

static func _rect_dist(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dz * dz)


static func _floor(sb: RefCounted, plan: InteriorPlan, room: Dictionary, quality: int) -> void:
	var r: Rect2 = room["rect"]
	var cell: float = FLOOR_CELL[quality]
	var nx := maxi(1, int(ceil(r.size.x / cell)))
	var nz := maxi(1, int(ceil(r.size.y / cell)))
	var cw := r.size.x / float(nx)
	var cd := r.size.y / float(nz)
	var base: Color = room["floor"]
	var dance: Rect2 = room["dance"]
	var occ: Array = plan._occ
	for iz in nz:
		for ix in nx:
			var x0 := r.position.x + float(ix) * cw
			var z0 := r.position.y + float(iz) * cd
			var c := Vector2(x0 + cw * 0.5, z0 + cd * 0.5)
			var is_dance := dance.size != Vector2.ZERO and dance.has_point(c)
			var ao := 1.0
			var de := minf(minf(c.x - r.position.x, r.end.x - c.x), minf(c.y - r.position.y, r.end.y - c.y))
			var tw := clampf(1.0 - de / 1.1, 0.0, 1.0)
			ao *= 1.0 - 0.55 * tw * tw
			for o: Rect2 in occ:
				var d := _rect_dist(c, o)
				if d < 0.7:
					var k := 1.0 - d / 0.7
					ao *= 1.0 - 0.5 * k * k
			var col := Color(base.r * ao, base.g * ao, base.b * ao, 1.0 if is_dance else 0.0)
			sb.uv = Vector2(6.0 if is_dance else 1.0, 0.0)
			sb.quad(Vector3(x0, 0.0, z0), Vector3(x0 + cw, 0.0, z0), Vector3(x0 + cw, 0.0, z0 + cd), Vector3(x0, 0.0, z0 + cd), Vector3.UP, col)


static func _ceiling(sb: RefCounted, room: Dictionary) -> void:
	var r: Rect2 = room["rect"]
	var h: float = room["h"]
	var c: Color = room["ceil"]
	sb.uv = Vector2(2.0, 0.0)
	sb.quad(Vector3(r.position.x, h, r.position.y), Vector3(r.end.x, h, r.position.y), Vector3(r.end.x, h, r.end.y), Vector3(r.position.x, h, r.end.y), Vector3.DOWN, Color(c.r, c.g, c.b, 0.0))


static func _door_floor(sb: RefCounted, plan: InteriorPlan, dd: Dictionary) -> void:
	var hw := float(dd["w"]) * 0.5
	var T := InteriorPlan.T
	var col: Color = (plan.rooms[int(dd["a"])]["floor"] as Color) * 0.85
	sb.uv = Vector2(1.0, 0.0)
	col.a = 0.0
	if int(dd["axis"]) == 0:
		var z0 := float(dd["line"]) - T * 0.5
		sb.quad(Vector3(float(dd["c"]) - hw, 0.0, z0), Vector3(float(dd["c"]) + hw, 0.0, z0), Vector3(float(dd["c"]) + hw, 0.0, z0 + T), Vector3(float(dd["c"]) - hw, 0.0, z0 + T), Vector3.UP, col)
	else:
		var x0 := float(dd["line"]) - T * 0.5
		sb.quad(Vector3(x0, 0.0, float(dd["c"]) - hw), Vector3(x0 + T, 0.0, float(dd["c"]) - hw), Vector3(x0 + T, 0.0, float(dd["c"]) + hw), Vector3(x0, 0.0, float(dd["c"]) + hw), Vector3.UP, col)


# ---------------------------------------------------------------------------------------------------------------------
# walls
# ---------------------------------------------------------------------------------------------------------------------

static func _room_wall(plan: InteriorPlan, room: int) -> Color:
	if room < 0:
		return EXTERIOR
	return plan.rooms[room]["wall"]


static func _segment(sb: RefCounted, wb: RefCounted, plan: InteriorPlan, s: Dictionary) -> void:
	var axis := int(s["axis"])
	var line := float(s["line"])
	var h := float(s["h"])
	var col_pos := _room_wall(plan, int(s["pos_room"]))
	var col_neg := _room_wall(plan, int(s["neg_room"]))
	var trim: Color = plan.pal["trim"]
	for pc: Array in plan.seg_pieces(s, true):
		_wall_piece(sb, axis, line, float(pc[0]), float(pc[1]), float(pc[2]), float(pc[3]), col_pos, col_neg, trim, h)
	# door frames: jambs, head and an accent strip on the head
	var accent: Color = (plan.pal["neon"] as Array)[0]
	for d: Array in s["doors"]:
		var c := float(d[0])
		var w := float(d[1])
		var T := InteriorPlan.T
		var thick := T + 0.06
		var fc := Color(trim.r * 0.7, trim.g * 0.7, trim.b * 0.7, 0.0)
		sb.uv = Vector2(3.0, 0.0)
		if axis == 0:
			sb.box(Vector3(c - w * 0.5 - 0.035, InteriorPlan.DOOR_H * 0.5, line), Vector3(0.07, InteriorPlan.DOOR_H, thick), fc, false)
			sb.box(Vector3(c + w * 0.5 + 0.035, InteriorPlan.DOOR_H * 0.5, line), Vector3(0.07, InteriorPlan.DOOR_H, thick), fc, false)
			sb.box(Vector3(c, InteriorPlan.DOOR_H + 0.035, line), Vector3(w + 0.14, 0.07, thick), fc, false)
		else:
			sb.box(Vector3(line, InteriorPlan.DOOR_H * 0.5, c - w * 0.5 - 0.035), Vector3(thick, InteriorPlan.DOOR_H, 0.07), fc, false)
			sb.box(Vector3(line, InteriorPlan.DOOR_H * 0.5, c + w * 0.5 + 0.035), Vector3(thick, InteriorPlan.DOOR_H, 0.07), fc, false)
			sb.box(Vector3(line, InteriorPlan.DOOR_H + 0.035, c), Vector3(thick, 0.07, w + 0.14), fc, false)
		sb.uv = Vector2(8.0, 0.0)
		var street := int(s["other"]) < 0 and int(s["side"]) == InteriorPlan.SIDE_FRONT and int(s["owner"]) == 0
		var sc := Color(0.2, 1.0, 0.45, 1.8) if street else Color(accent.r, accent.g, accent.b, 1.3)
		var both := int(s["other"]) >= 0
		if axis == 0:
			var iz := -1.0 if int(s["side"]) == InteriorPlan.SIDE_FRONT else 1.0
			sb.box(Vector3(c, InteriorPlan.DOOR_H + 0.02, line + iz * (T * 0.5 + 0.035)), Vector3(w * 0.6, 0.05, 0.02), sc, false)
			if both:
				sb.box(Vector3(c, InteriorPlan.DOOR_H + 0.02, line - iz * (T * 0.5 + 0.035)), Vector3(w * 0.6, 0.05, 0.02), sc, false)
		else:
			var ix := 1.0 if int(s["side"]) == InteriorPlan.SIDE_LEFT else -1.0
			sb.box(Vector3(line + ix * (T * 0.5 + 0.035), InteriorPlan.DOOR_H + 0.02, c), Vector3(0.02, 0.05, w * 0.6), sc, false)
			if both:
				sb.box(Vector3(line - ix * (T * 0.5 + 0.035), InteriorPlan.DOOR_H + 0.02, c), Vector3(0.02, 0.05, w * 0.6), sc, false)
		if street:
			# the street door itself: a glass leaf showing the street, a push bar and the exit marker
			var inward := -1.0
			var pz := line - T * 0.5 + 0.02
			wb.uv = Vector2(InteriorPlan.DOOR_H, 3.7)
			wb.quad(Vector3(c - w * 0.5, 0.04, line), Vector3(c + w * 0.5, 0.04, line), Vector3(c + w * 0.5, InteriorPlan.DOOR_H - 0.04, line), Vector3(c - w * 0.5, InteriorPlan.DOOR_H - 0.04, line), Vector3(0, 0, inward), Color.WHITE)
			sb.uv = Vector2(3.0, 0.0)
			sb.box(Vector3(c, 1.0, pz - 0.05), Vector3(w - 0.3, 0.05, 0.05), Color(0.5, 0.5, 0.55, 0.0), false)
			sb.box(Vector3(c, InteriorPlan.DOOR_H * 0.5, line), Vector3(0.06, InteriorPlan.DOOR_H - 0.1, 0.06), Color(0.1, 0.1, 0.12, 0.0), false)
	# window frames, mullions and panes
	for wv: Array in s["windows"]:
		var c := float(wv[0])
		var w := float(wv[1])
		var y0 := float(wv[2])
		var y1 := float(wv[3])
		var T := InteriorPlan.T
		var fc := Color(trim.r * 0.6, trim.g * 0.6, trim.b * 0.6, 0.0)
		var inward_dir := Vector3.ZERO
		match int(s["side"]):
			InteriorPlan.SIDE_FRONT: inward_dir = Vector3(0, 0, -1)
			InteriorPlan.SIDE_BACK: inward_dir = Vector3(0, 0, 1)
			InteriorPlan.SIDE_LEFT: inward_dir = Vector3(1, 0, 0)
			_: inward_dir = Vector3(-1, 0, 0)
		var phase := fposmod(c * 1.7 + line * 0.9, 9.0)
		sb.uv = Vector2(3.0, 0.0)
		if axis == 0:
			wb.uv = Vector2(y1 - y0, phase)
			wb.quad(Vector3(c - w * 0.5, y0, line), Vector3(c + w * 0.5, y0, line), Vector3(c + w * 0.5, y1, line), Vector3(c - w * 0.5, y1, line), inward_dir, Color.WHITE)
			var zf := line + inward_dir.z * (T * 0.5 - 0.02)
			sb.box(Vector3(c - w * 0.5 + 0.03, (y0 + y1) * 0.5, zf), Vector3(0.06, y1 - y0, 0.06), fc, false)
			sb.box(Vector3(c + w * 0.5 - 0.03, (y0 + y1) * 0.5, zf), Vector3(0.06, y1 - y0, 0.06), fc, false)
			sb.box(Vector3(c, y0 + 0.03, zf), Vector3(w, 0.06, 0.07), fc, false)
			sb.box(Vector3(c, y1 - 0.03, zf), Vector3(w, 0.06, 0.07), fc, false)
			if w > 1.9:
				sb.box(Vector3(c, (y0 + y1) * 0.5, zf), Vector3(0.05, y1 - y0, 0.05), fc, false)
		else:
			wb.uv = Vector2(y1 - y0, phase)
			wb.quad(Vector3(line, y0, c - w * 0.5), Vector3(line, y0, c + w * 0.5), Vector3(line, y1, c + w * 0.5), Vector3(line, y1, c - w * 0.5), inward_dir, Color.WHITE)
			var xf := line + inward_dir.x * (T * 0.5 - 0.02)
			sb.box(Vector3(xf, (y0 + y1) * 0.5, c - w * 0.5 + 0.03), Vector3(0.06, y1 - y0, 0.06), fc, false)
			sb.box(Vector3(xf, (y0 + y1) * 0.5, c + w * 0.5 - 0.03), Vector3(0.06, y1 - y0, 0.06), fc, false)
			sb.box(Vector3(xf, y0 + 0.03, c), Vector3(0.07, 0.06, w), fc, false)
			sb.box(Vector3(xf, y1 - 0.03, c), Vector3(0.07, 0.06, w), fc, false)
			if w > 1.9:
				sb.box(Vector3(xf, (y0 + y1) * 0.5, c), Vector3(0.05, y1 - y0, 0.05), fc, false)


## One solid piece of a wall: both faces in their room's colour, the edges in the trim colour (the top only when it can be seen, i.e. under a window).
static func _wall_piece(sb: RefCounted, axis: int, line: float, a0: float, a1: float, y0: float, y1: float, col_pos: Color, col_neg: Color, trim: Color, h: float) -> void:
	var T := InteriorPlan.T
	var hp := T * 0.5
	var cp := Color(col_pos.r, col_pos.g, col_pos.b, 0.0)
	var cn := Color(col_neg.r, col_neg.g, col_neg.b, 0.0)
	var ct := Color(trim.r * 0.6, trim.g * 0.6, trim.b * 0.6, 0.0)
	# relief: a baseboard and a dado rail on both faces, a crown moulding under the ceiling (real geometry, so the room has edges the light can catch)
	var tl := Color(trim.r * 0.8, trim.g * 0.8, trim.b * 0.8, 0.0)
	var mid_a := (a0 + a1) * 0.5
	var len := a1 - a0
	sb.uv = Vector2(3.0, 0.0)
	if y0 < 0.01 and len > 0.1:
		_trim_box(sb, axis, line, mid_a, len, 0.07, 0.14, T + 0.07, tl)
	if y0 < 0.01 and y1 > 1.2 and len > 0.1:
		_trim_box(sb, axis, line, mid_a, len, 1.06, 0.05, T + 0.05, tl)
	if y1 > h - 0.01 and len > 0.1:
		_trim_box(sb, axis, line, mid_a, len, h - 0.09, 0.18, T + 0.08, tl)
	sb.uv = Vector2(0.0, h)
	if axis == 0:
		sb.quad(Vector3(a0, y0, line + hp), Vector3(a1, y0, line + hp), Vector3(a1, y1, line + hp), Vector3(a0, y1, line + hp), Vector3.BACK, cp)
		sb.quad(Vector3(a0, y0, line - hp), Vector3(a1, y0, line - hp), Vector3(a1, y1, line - hp), Vector3(a0, y1, line - hp), Vector3.FORWARD, cn)
		sb.quad(Vector3(a0, y0, line - hp), Vector3(a0, y0, line + hp), Vector3(a0, y1, line + hp), Vector3(a0, y1, line - hp), Vector3.LEFT, ct)
		sb.quad(Vector3(a1, y0, line - hp), Vector3(a1, y0, line + hp), Vector3(a1, y1, line + hp), Vector3(a1, y1, line - hp), Vector3.RIGHT, ct)
		if y1 < h - 0.01:
			sb.quad(Vector3(a0, y1, line - hp), Vector3(a1, y1, line - hp), Vector3(a1, y1, line + hp), Vector3(a0, y1, line + hp), Vector3.UP, ct)
		if y0 > 0.01:
			sb.quad(Vector3(a0, y0, line - hp), Vector3(a1, y0, line - hp), Vector3(a1, y0, line + hp), Vector3(a0, y0, line + hp), Vector3.DOWN, ct)
	else:
		sb.quad(Vector3(line + hp, y0, a0), Vector3(line + hp, y0, a1), Vector3(line + hp, y1, a1), Vector3(line + hp, y1, a0), Vector3.RIGHT, cp)
		sb.quad(Vector3(line - hp, y0, a0), Vector3(line - hp, y0, a1), Vector3(line - hp, y1, a1), Vector3(line - hp, y1, a0), Vector3.LEFT, cn)
		sb.quad(Vector3(line - hp, y0, a0), Vector3(line + hp, y0, a0), Vector3(line + hp, y1, a0), Vector3(line - hp, y1, a0), Vector3.FORWARD, ct)
		sb.quad(Vector3(line - hp, y0, a1), Vector3(line + hp, y0, a1), Vector3(line + hp, y1, a1), Vector3(line - hp, y1, a1), Vector3.BACK, ct)
		if y1 < h - 0.01:
			sb.quad(Vector3(line - hp, y1, a0), Vector3(line + hp, y1, a0), Vector3(line + hp, y1, a1), Vector3(line - hp, y1, a1), Vector3.UP, ct)
		if y0 > 0.01:
			sb.quad(Vector3(line - hp, y0, a0), Vector3(line + hp, y0, a0), Vector3(line + hp, y0, a1), Vector3(line - hp, y0, a1), Vector3.DOWN, ct)


static func _trim_box(sb: RefCounted, axis: int, line: float, mid: float, len: float, y: float, hh: float, thick: float, col: Color) -> void:
	if axis == 0:
		sb.box(Vector3(mid, y, line), Vector3(len, hh, thick), col, false, Vector2.ZERO, MB.F_PX | MB.F_NX)
	else:
		sb.box(Vector3(line, y, mid), Vector3(thick, hh, len), col, false, Vector2.ZERO, MB.F_ENDS)
