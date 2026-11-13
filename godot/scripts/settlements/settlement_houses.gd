class_name SettlementHouses
extends RefCounted
## The houses of the towns (wave 112): ONE parametric house builder (walls, plinth, windows by bays, a door with trim and a step, gable / hip / flat / shed roofs, chimney, porch, garage, balcony, awning,
## shutters, terraces of several units each in its own colour) and the palettes and recipes per town style. A house is a SettlementMesh part in its own frame (origin on the ground at the middle of the
## footprint, front -Z), cached by its spec by SettlementKit; `far_house` is the cut-down copy (a box and a roof) used beyond the near range. Spec keys (all but w, d optional):
##   w d floors fh | wall wall_code trim | roof roof_code roof_type (gable hip flat shed) slope ov ovg ridge (&"z" gables face the street, &"x") parapet | units unit_cols (a terrace)
##   door_x door_col | porch porch_w | chimney chim_side chim_code | shutter (Color, a > 0) | win_w win_h bay | garage (-1 / 1 side) | balcony | awning (Color, a > 0) | shopfront | plinth | glow | seed

const P := preload("res://scripts/settlements/settlement_parts.gd")


static func house(s: Dictionary) -> Dictionary:
	var m := SettlementMesh.new()
	var w: float = s["w"]
	var d: float = s["d"]
	var floors: int = s.get("floors", 1)
	var fh: float = s.get("fh", 2.8)
	var wall: Color = s.get("wall", Color(0.85, 0.8, 0.7))
	var wcode: int = s.get("wall_code", SettlementMesh.PAINT)
	var trim: Color = s.get("trim", Color(0.93, 0.91, 0.86))
	var roof: Color = s.get("roof", Color(0.4, 0.2, 0.15))
	var rcode: int = s.get("roof_code", SettlementMesh.TILE)
	var rtype: StringName = s.get("roof_type", &"gable")
	var slope: float = s.get("slope", 0.5)
	var ov: float = s.get("ov", 0.55)
	var ovg: float = s.get("ovg", 0.3)
	var ridge: StringName = s.get("ridge", &"z")
	var units: int = s.get("units", 1)
	var unit_cols: Array = s.get("unit_cols", [])
	var sv: int = s.get("seed", 1)
	var h := float(floors) * fh
	var plinth: float = s.get("plinth", 0.5)
	var door_col: Color = s.get("door_col", Color(0.35, 0.2, 0.12))
	var glow: float = s.get("glow", 0.7)
	var win_w: float = s.get("win_w", 1.05)
	var win_h: float = s.get("win_h", 1.3)
	var bay: float = s.get("bay", 3.0)
	var shutter: Color = s.get("shutter", Color(0, 0, 0, 0))
	var door_x: float = s.get("door_x", 0.0)
	var uw := w / float(units)
	# walls (one box per unit so a terrace can have a colour per unit)
	for u in units:
		var ucol: Color = unit_cols[u] if u < unit_cols.size() else wall
		var skip := 32 | 4
		if u > 0:
			skip |= 2
		if u < units - 1:
			skip |= 1
		m.box(Vector3(-w * 0.5 + (float(u) + 0.5) * uw, h * 0.5, 0.0), Vector3(uw, h, d), ucol, wcode, skip, 1.0, 0.6)
	m.box(Vector3(0.0, plinth * 0.5, 0.0), Vector3(w + 0.1, plinth, d + 0.1), Color(0.5, 0.47, 0.43), SettlementMesh.STONE, 32 | 4, 0.95, 0.7)
	# the front door(s) and the windows
	var front_door_xs := door_list(s)
	var dw := 1.05
	for dx in front_door_xs:
		P.door(m, Vector3(dx, plinth * 0.4, -d * 0.5), Vector3(0, 0, -1), dw, 2.15 - plinth * 0.4, door_col, trim)
	for f in floors:
		var y0 := float(f) * fh + 0.9
		# front wall: bottom-left seen from outside is x = +w/2, right = -X
		var gap_a := -1.0
		var gap_b := -1.0
		if f == 0 and units == 1:
			var tc := w * 0.5 - door_x
			gap_a = tc - dw * 0.5 - 0.65
			gap_b = tc + dw * 0.5 + 0.65
		if units == 1:
			P.window_row(m, Vector3(w * 0.5, 0.0, -d * 0.5), Vector3(-1, 0, 0), w, y0, Vector3(0, 0, -1), bay, win_w, win_h, trim, glow, shutter, sv + f * 11, gap_a, gap_b)
		else:
			for u in units:
				var uc := -w * 0.5 + (float(u) + 0.5) * uw
				var dxu: float = front_door_xs[u]
				var wx := uc - (dxu - uc) * 1.0                      # the window of a unit sits on the other side of its door
				if f == 0:
					P.window(m, Vector3(wx, y0 + win_h * 0.5, -d * 0.5), Vector3(0, 0, -1), win_w, win_h, trim, glow if P.hash01(sv, u + f) > 0.3 else 0.0, shutter, sv + u)
				else:
					P.window(m, Vector3(uc - uw * 0.22, y0 + win_h * 0.5, -d * 0.5), Vector3(0, 0, -1), win_w, win_h, trim, glow, shutter, sv + u)
					P.window(m, Vector3(uc + uw * 0.22, y0 + win_h * 0.5, -d * 0.5), Vector3(0, 0, -1), win_w, win_h, trim, glow * 0.8, shutter, sv + u + 3)
		P.window_row(m, Vector3(-w * 0.5, 0.0, d * 0.5), Vector3(1, 0, 0), w, y0, Vector3(0, 0, 1), bay * 1.2, win_w, win_h, trim, glow * 0.6, shutter, sv + 50 + f)
		P.window_row(m, Vector3(-w * 0.5, 0.0, -d * 0.5), Vector3(0, 0, 1), d, y0, Vector3(-1, 0, 0), bay, win_w, win_h, trim, glow, shutter, sv + 90 + f)
		P.window_row(m, Vector3(w * 0.5, 0.0, d * 0.5), Vector3(0, 0, -1), d, y0, Vector3(1, 0, 0), bay, win_w, win_h, trim, glow, shutter, sv + 130 + f)
	if s.get("shopfront", false):                                          # one big window beside the door
		var sx := door_x - 2.3 if door_x > -w * 0.25 else door_x + 2.3
		m.quad(Vector3(sx + 1.2, 0.35, -d * 0.5 - 0.04), Vector3(sx - 1.2, 0.35, -d * 0.5 - 0.04), Vector3(sx - 1.2, 2.3, -d * 0.5 - 0.04), Vector3(sx + 1.2, 2.3, -d * 0.5 - 0.04), trim, SettlementMesh.GLASS, 1.0, 1.0, Vector2.ZERO, 0.95, Vector3(0, 0, -1), true)
	# roof
	var roof_top := h
	var rise := 0.0
	match rtype:
		&"gable":
			var t := SettlementMesh.new()
			if ridge == &"z":
				P.gable_roof(t, w, d, h, slope, ov, ovg, roof, rcode, wall, wcode)
				rise = slope * w * 0.5
			else:
				P.gable_roof(t, d, w, h, slope, ov, ovg, roof, rcode, wall, wcode)
				rise = slope * d * 0.5
			if ridge == &"z":
				m.append(t, Transform3D.IDENTITY)
			else:
				m.append(t, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
			roof_top = h + rise
		&"hip":
			P.hip_roof(m, w, d, h, slope, ov, roof, rcode)
			rise = slope * minf(w, d) * 0.5
			roof_top = h + rise
		&"flat":
			P.flat_roof(m, w, d, h, float(s.get("parapet", 0.5)), wall, wcode, Color(0.45, 0.45, 0.46))
			roof_top = h + 0.7
		&"shed":
			P.shed_roof(m, w, d, h + w * slope * 0.5, h, ov, roof, rcode, wall, wcode)
			roof_top = h + w * slope * 0.5
	# chimney
	if s.get("chimney", false):
		var cs: float = float(s.get("chim_side", 1))
		var cx := cs * w * 0.28 if rtype == &"gable" and ridge == &"x" else 0.0
		var cz := d * 0.15 if rtype == &"gable" and ridge == &"z" else 0.0
		if rtype == &"gable" and ridge == &"x":
			cz = 0.0
			cx = cs * w * 0.3
		elif rtype == &"gable":
			cx = cs * w * 0.12
			cz = d * 0.2
		else:
			cx = cs * w * 0.25
			cz = 0.0
		var ytop := roof_top + 0.45
		P.chimney(m, cx, cz, h - 0.4, ytop, s.get("chim_col", Color(0.5, 0.28, 0.22)), int(s.get("chim_code", SettlementMesh.BRICK)))
	# porch
	if s.get("porch", false):
		var pw: float = float(s.get("porch_w", 3.4))
		P.porch(m, door_x, -d * 0.5, pw, 1.8, 2.5, Color(0.55, 0.45, 0.35), Color(roof.r * 0.9, roof.g * 0.9, roof.b * 0.9), SettlementMesh.SHINGLE if rcode != SettlementMesh.TILE else SettlementMesh.TILE)
	# garage on one side
	var gs: int = int(s.get("garage", 0))
	if gs != 0:
		var gw := 3.4
		var gd := d * 0.82
		var gx := float(gs) * (w * 0.5 + gw * 0.5)
		var gh := 2.7
		m.box(Vector3(gx, gh * 0.5, -d * 0.5 + gd * 0.5), Vector3(gw, gh, gd), wall, wcode, 32 | 4 | (2 if gs > 0 else 1), 1.0, 0.6)
		var t2 := SettlementMesh.new()
		P.shed_roof(t2, gw, gd, gh + 0.25, gh, 0.12, roof, SettlementMesh.SHEET if rcode == SettlementMesh.SHEET else rcode, wall, wcode)
		m.append(t2, Transform3D(Basis.IDENTITY, Vector3(gx, 0.0, -d * 0.5 + gd * 0.5)))
		m.quad(Vector3(gx + 1.2, 0.0, -d * 0.5 - 0.03), Vector3(gx - 1.2, 0.0, -d * 0.5 - 0.03), Vector3(gx - 1.2, 2.15, -d * 0.5 - 0.03), Vector3(gx + 1.2, 2.15, -d * 0.5 - 0.03), Color(0.86, 0.85, 0.82), SettlementMesh.SHEET, 1.0, 0.85, Vector2.ZERO, 0.0, Vector3(0, 0, -1))
	if s.get("balcony", false):
		P.balcony(m, door_x, -d * 0.5, minf(w * 0.55, 3.6), 1.1, fh + 0.05, Color(0.5, 0.38, 0.26), Color(0.88, 0.84, 0.76))
	var aw: Color = s.get("awning", Color(0, 0, 0, 0))
	if aw.a > 0.0:
		P.awning(m, 0.0, -d * 0.5, w * 0.92, 1.3, 2.7, Color(aw.r, aw.g, aw.b))
	var far := far_house(s)
	var width := w + (3.4 if gs != 0 else 0.0)
	return {"mesh": m, "far": far, "size": Vector3(w, roof_top + 0.3, d), "door": Vector3(door_x, 0.0, -d * 0.5), "doors": front_door_xs, "roof_top": roof_top, "garage_side": gs, "width": width}


## The x of every front door of a spec (one per unit of a terrace).
static func door_list(s: Dictionary) -> Array[float]:
	var units: int = s.get("units", 1)
	var w: float = s["w"]
	var uw := w / float(units)
	var out: Array[float] = []
	if units > 1:
		for u in units:
			out.append(-w * 0.5 + (float(u) + 0.5) * uw + (uw * 0.28 if u % 2 == 0 else -uw * 0.28))
	else:
		out.append(float(s.get("door_x", 0.0)))
	return out


## The cut-down house: walls and roof, nothing else (12 to 20 triangles).
static func far_house(s: Dictionary) -> SettlementMesh:
	var m := SettlementMesh.new()
	var w: float = s["w"]
	var d: float = s["d"]
	var floors: int = s.get("floors", 1)
	var h := float(floors) * float(s.get("fh", 2.8))
	var wall: Color = s.get("wall", Color(0.85, 0.8, 0.7))
	var roof: Color = s.get("roof", Color(0.4, 0.2, 0.15))
	var rtype: StringName = s.get("roof_type", &"gable")
	m.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, SettlementMesh.PAINT, 32 | 4, 1.0, 0.7)
	var slope: float = s.get("slope", 0.5)
	var rcode: int = SettlementMesh.PAINT
	match rtype:
		&"gable":
			var t := SettlementMesh.new()
			var ridge: StringName = s.get("ridge", &"z")
			if ridge == &"z":
				P.gable_roof(t, w, d, h, slope, 0.3, 0.2, roof, rcode, wall, SettlementMesh.PAINT, false)
				m.append(t, Transform3D.IDENTITY)
			else:
				P.gable_roof(t, d, w, h, slope, 0.3, 0.2, roof, rcode, wall, SettlementMesh.PAINT, false)
				m.append(t, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
		&"hip":
			P.hip_roof(m, w, d, h, slope, 0.3, roof, rcode)
		&"flat":
			m.box(Vector3(0.0, h + 0.06, 0.0), Vector3(w + 0.1, 0.12, d + 0.1), Color(0.45, 0.45, 0.46), SettlementMesh.CONCRETE, 32, 1.0, 1.0)
		&"shed":
			P.shed_roof(m, w, d, h + w * slope * 0.5, h, 0.2, roof, rcode, wall, SettlementMesh.PAINT)
	return m
