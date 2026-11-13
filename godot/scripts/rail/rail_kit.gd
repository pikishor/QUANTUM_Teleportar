class_name RailKit
extends RefCounted
## Meshes of the railway (data: RailNet). A route is cut into CHUNKS of about 320 m; every chunk is ONE merged mesh and one draw call (track bed with sleepers, rails or the maglev guideway, catenary
## masts, viaduct girders and piers, tunnel tubes and portals, platforms, canopies, station halls, stairs, level crossing planks and signs, signal poles). All of it uses rail_kit.gdshader
## (vertex colour = paint, COLOR.a = material code; see the shader). Vertices are relative to the chunk origin (a point on the ground at the chunk centre) so distance culling by node position
## and by bounding box agree. RailWorld puts the chunks in the scene (and builds their colliders lazily): `build_chunk(route, i0, i1)` returns {mesh, origin, boxes, tris}.

const MB := preload("res://scripts/world/mesh_builder.gd")
const SHADER := preload("res://assets/shaders/rail_kit.gdshader")
const CHUNK_LEN := 320.0
const CONCRETE := Color(0.62, 0.61, 0.58, 2.0 / 8.0)
const CONCRETE_DARK := Color(0.42, 0.42, 0.41, 2.0 / 8.0)
const CONCRETE_LIGHT := Color(0.74, 0.73, 0.7, 2.0 / 8.0)
const STEEL := Color(0.52, 0.54, 0.58, 3.0 / 8.0)
const STEEL_DARK := Color(0.2, 0.22, 0.25, 3.0 / 8.0)
const STEEL_GREEN := Color(0.16, 0.3, 0.26, 3.0 / 8.0)
const RAIL := Color(0.46, 0.46, 0.5, 3.0 / 8.0)
const LAMP := Color(1.0, 0.86, 0.55, 4.0 / 8.0)
const LAMP_BLUE := Color(0.4, 0.75, 1.0, 4.0 / 8.0)
const BALLAST := Color(0.5, 0.48, 0.45, 1.0)
const ASPHALT := Color(0.13, 0.13, 0.14, 5.0 / 8.0)
const GLASS := Color(0.55, 0.78, 1.0, 7.0 / 8.0)
const WOOD := Color(0.44, 0.32, 0.2, 0.0)
const SIGN_RED := Color(0.78, 0.12, 0.1, 0.0)
const SIGN_WHITE := Color(0.92, 0.92, 0.9, 0.0)
const MAST_H := 6.4
const DECK_HW := 5.2                           ## box girder half width

static var _mat: ShaderMaterial
static var _frames := {}                       ## route id -> Array of {p, t, rt, k}


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


static func _c(col: Color, code: float) -> Color:
	return Color(col.r, col.g, col.b, code / 8.0)


# --- frames ---------------------------------------------------------------------------------------------------------------------------

static func frames(r: Dictionary) -> Array:
	var id: StringName = r["id"]
	if _frames.has(id):
		return _frames[id]
	var pos: PackedVector2Array = r["pos"]
	var y: PackedFloat32Array = r["y"]
	var k: PackedFloat32Array = r["k"]
	var out: Array = []
	for i in pos.size():
		var a := pos[maxi(i - 1, 0)]
		var b := pos[mini(i + 1, pos.size() - 1)]
		var t := Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
		out.append({"p": Vector3(pos[i].x, y[i], pos[i].y), "t": t, "rt": RailNet.right_of(t), "k": k[i]})
	_frames[id] = out
	return out


## A point of sample i at lateral `lat` (right of the direction of growing s) and `dy` over the bed, in world space.
static func fp(F: Array, i: int, lat: float, dy: float) -> Vector3:
	var f: Dictionary = F[i]
	return (f["p"] as Vector3) + (f["rt"] as Vector3) * lat + Vector3.UP * dy


## Chunk boundaries as sample index ranges (one sample shared between neighbours).
static func chunk_ranges(r: Dictionary) -> Array[Vector2i]:
	var s: PackedFloat32Array = r["s"]
	var n := s.size()
	var out: Array[Vector2i] = []
	var i0 := 0
	var next := CHUNK_LEN
	for i in range(1, n):
		if s[i] >= next or i == n - 1:
			out.append(Vector2i(i0, i))
			i0 = i
			next = s[i] + CHUNK_LEN
	return out


# --- one chunk ------------------------------------------------------------------------------------------------------------------------

static func build_chunk(r: Dictionary, i0: int, i1: int) -> Dictionary:
	var F := frames(r)
	var mode: PackedByteArray = r["mode"]
	var s: PackedFloat32Array = r["s"]
	var maglev: bool = r["style"] == &"maglev"
	var org := Vector3.ZERO
	for i in range(i0, i1 + 1):
		org += (F[i]["p"] as Vector3)
	org /= float(i1 - i0 + 1)
	org.y = 0.0
	var mb := MB.new()
	var boxes: Array = []
	for i in range(i0, i1):
		if mode[i] == RailNet.MODE_VIADUCT:
			_deck(mb, F, i, org, maglev)
		_bed(mb, F, i, org, maglev, int(mode[i]) == RailNet.MODE_TUNNEL)
		if not maglev:
			_catenary(mb, F, s, i, org)
	_viaduct_piers(mb, r, F, i0, i1, org, boxes)
	_tunnel_parts(mb, r, F, i0, i1, org)
	for st: Dictionary in r["stations"]:
		var zone := float(st["len"]) * 0.5 + 24.0
		if s[i0] <= float(st["s"]) + zone and s[i1] >= float(st["s"]) - zone:
			_station(mb, r, st, F, i0, i1, org, boxes)
	for c: Dictionary in r["crossings"]:
		if int(c["i"]) >= i0 and int(c["i"]) < i1 and bool(c["level"]):
			_crossing_static(mb, c, org)
	for sg: Dictionary in r["signals"]:
		var li := RailNet.locate(r, float(sg["u"]))
		if int(li.x) >= i0 and int(li.x) < i1:
			_signal_pole(mb, r, sg, org)
	var mesh := mb.build(material(), true)
	return {"mesh": mesh, "origin": org, "boxes": boxes, "tris": mb.idx.size() / 3}


static func _o(v: Vector3, org: Vector3) -> Vector3:
	return v - org


# --- track bed, rails ----------------------------------------------------------------------------------------------------------------

static func _bed(mb: MB, F: Array, i: int, org: Vector3, maglev: bool, in_tunnel: bool) -> void:
	var a: Dictionary = F[i]
	var b: Dictionary = F[i + 1]
	var ds := (a["p"] as Vector3).distance_to(b["p"] as Vector3)
	var hw_top := 4.25
	var hw_foot := RailNet.BED_HW
	var run0 := _run(F, i)
	var col := BALLAST if not maglev else _c(Color(0.58, 0.57, 0.55), 2.0)
	var lane_a := RailNet.HALF_SEP * float(a["k"])
	var lane_b := RailNet.HALF_SEP * float(b["k"])
	var pa0 := _o(fp(F, i, -hw_top, 0.0), org)
	var pa1 := _o(fp(F, i, hw_top, 0.0), org)
	var pb0 := _o(fp(F, i + 1, -hw_top, 0.0), org)
	var pb1 := _o(fp(F, i + 1, hw_top, 0.0), org)
	var n := Vector3.UP
	var la_u := -1.0 if maglev else lane_a                 # UV2.y < 0: no sleepers (the maglev bed is plain concrete)
	var lb_u := -1.0 if maglev else lane_b
	var v0 := mb.vertex(pa0, n, col, Vector2(0.0, run0), Vector2(-hw_top, la_u))
	var v1 := mb.vertex(pa1, n, col, Vector2(1.0, run0), Vector2(hw_top, la_u))
	var v2 := mb.vertex(pb1, n, col, Vector2(1.0, run0 + ds), Vector2(hw_top, lb_u))
	var v3 := mb.vertex(pb0, n, col, Vector2(0.0, run0 + ds), Vector2(-hw_top, lb_u))
	mb.tri(v0, v1, v2)
	mb.tri(v0, v2, v3)
	# the shoulders (no sleepers)
	for sx in [-1.0, 1.0]:
		var sgn := float(sx)
		var q0 := _o(fp(F, i, sgn * hw_top, 0.0), org)
		var q1 := _o(fp(F, i, sgn * hw_foot, -0.5), org)
		var q2 := _o(fp(F, i + 1, sgn * hw_foot, -0.5), org)
		var q3 := _o(fp(F, i + 1, sgn * hw_top, 0.0), org)
		mb.quad(q0, q1, q2, q3, ((a["rt"] as Vector3) * sgn + Vector3.UP * 0.7).normalized(), col, Vector2.ZERO, Vector2(0.0, -1.0))
	if maglev:
		for sx in [-1.0, 1.0]:                              # the guideways: a concrete beam with two guide strips
			var l0 := float(sx) * lane_a
			var l1 := float(sx) * lane_b
			mb.quad(_o(fp(F, i, l0 - 1.35, 0.12), org), _o(fp(F, i, l0 + 1.35, 0.12), org), _o(fp(F, i + 1, l1 + 1.35, 0.12), org), _o(fp(F, i + 1, l1 - 1.35, 0.12), org), Vector3.UP, CONCRETE_LIGHT)
			for sd in [-1.0, 1.0]:
				var e0 := l0 + float(sd) * 1.35
				var e1 := l1 + float(sd) * 1.35
				mb.quad(_o(fp(F, i, e0, 0.12), org), _o(fp(F, i, e0, 0.0), org), _o(fp(F, i + 1, e1, 0.0), org), _o(fp(F, i + 1, e1, 0.12), org), (a["rt"] as Vector3) * float(sd), CONCRETE_DARK)
			for sd in [-1.0, 1.0]:
				var g0 := l0 + float(sd) * 0.8
				var g1 := l1 + float(sd) * 0.8
				mb.quad(_o(fp(F, i, g0 - 0.07, 0.13), org), _o(fp(F, i, g0 + 0.07, 0.13), org), _o(fp(F, i + 1, g1 + 0.07, 0.13), org), _o(fp(F, i + 1, g1 - 0.07, 0.13), org), Vector3.UP, LAMP_BLUE)
		return
	for sx in [-1.0, 1.0]:                                   # four rails
		for sd in [-1.0, 1.0]:
			var e0 := float(sx) * lane_a + float(sd) * (RailNet.GAUGE * 0.5)
			var e1 := float(sx) * lane_b + float(sd) * (RailNet.GAUGE * 0.5)
			_rail_seg(mb, F, i, e0, e1, org)


static func _run(F: Array, i: int) -> float:
	# metres along the route up to sample i (cached per frame array in the frame dictionary)
	var f: Dictionary = F[i]
	if f.has("run"):
		return float(f["run"])
	var acc := 0.0
	for j in range(1, i + 1):
		acc += (F[j]["p"] as Vector3).distance_to(F[j - 1]["p"] as Vector3)
	f["run"] = acc
	return acc


static func _rail_seg(mb: MB, F: Array, i: int, e0: float, e1: float, org: Vector3) -> void:
	var hw := 0.05
	var h := RailNet.RAIL_TOP
	var a0 := _o(fp(F, i, e0 - hw, h), org)
	var a1 := _o(fp(F, i, e0 + hw, h), org)
	var b0 := _o(fp(F, i + 1, e1 - hw, h), org)
	var b1 := _o(fp(F, i + 1, e1 + hw, h), org)
	mb.quad(a0, a1, b1, b0, Vector3.UP, RAIL)
	mb.quad(_o(fp(F, i, e0 - hw, 0.0), org), a0, b0, _o(fp(F, i + 1, e1 - hw, 0.0), org), -(F[i]["rt"] as Vector3), RAIL)
	mb.quad(_o(fp(F, i, e0 + hw, 0.0), org), a1, b1, _o(fp(F, i + 1, e1 + hw, 0.0), org), (F[i]["rt"] as Vector3), RAIL)


## Catenary: a mast every ~40 m on the right side, a cantilever over both tracks, two contact wires.
static func _catenary(mb: MB, F: Array, s: PackedFloat32Array, i: int, org: Vector3) -> void:
	var a: Dictionary = F[i]
	var b: Dictionary = F[i + 1]
	var la := RailNet.HALF_SEP * float(a["k"])
	var lb := RailNet.HALF_SEP * float(b["k"])
	for sx in [-1.0, 1.0]:
		mb.quad(_o(fp(F, i, float(sx) * la - 0.025, MAST_H - 0.8), org), _o(fp(F, i, float(sx) * la + 0.025, MAST_H - 0.8), org), _o(fp(F, i + 1, float(sx) * lb + 0.025, MAST_H - 0.8), org),
			_o(fp(F, i + 1, float(sx) * lb - 0.025, MAST_H - 0.8), org), Vector3.UP, STEEL_DARK)
	if int(s[i] / 40.0) != int(s[i + 1] / 40.0):
		var lat := la + 2.9
		var base := _o(fp(F, i, lat, -0.4), org)
		mb.box(base + Vector3(0.0, MAST_H * 0.5, 0.0), Vector3(0.32, MAST_H + 0.4, 0.32), STEEL_DARK, false)
		mb.strut(_o(fp(F, i, lat, MAST_H), org), _o(fp(F, i, -la - 0.3, MAST_H - 0.3), org), 0.16, STEEL_DARK)
		mb.strut(_o(fp(F, i, lat, MAST_H - 0.2), org), _o(fp(F, i, lat - 1.8, MAST_H + 0.7), org), 0.1, STEEL)
		mb.box(_o(fp(F, i, lat, 0.0), org) + Vector3(0.0, 0.1, 0.0), Vector3(0.9, 0.5, 0.9), CONCRETE_DARK, false)


# --- viaduct ---------------------------------------------------------------------------------------------------------------------------

## A box girder under the bed: trapezoid section with parapets (or the maglev's noise screens).
static func _deck(mb: MB, F: Array, i: int, org: Vector3, maglev: bool) -> void:
	var prof := PackedVector2Array([Vector2(-DECK_HW, -0.5), Vector2(DECK_HW, -0.5), Vector2(DECK_HW, -0.9), Vector2(DECK_HW - 1.1, -2.7), Vector2(-DECK_HW + 1.1, -2.7), Vector2(-DECK_HW, -0.9)])
	_strip(mb, F, i, prof, _c(Color(0.7, 0.69, 0.66), 2.0), org, false)
	for sx in [-1.0, 1.0]:
		var lat := float(sx) * (DECK_HW - 0.12)
		var ph := 1.15 if not maglev else 1.9
		var pp := PackedVector2Array([Vector2(lat - 0.12, -0.5), Vector2(lat + 0.12, -0.5), Vector2(lat + 0.12, ph), Vector2(lat - 0.12, ph)])
		_strip(mb, F, i, pp, _c(Color(0.58, 0.58, 0.56), 2.0) if not maglev else _c(Color(0.5, 0.58, 0.64), 3.0), org, false)


## A closed profile (lateral, dy) swept between sample i and i + 1: outward normals.
static func _strip(mb: MB, F: Array, i: int, prof: PackedVector2Array, col: Color, org: Vector3, inward: bool) -> void:
	var n := prof.size()
	var area := 0.0
	for k in n:
		var a := prof[k]
		var b := prof[(k + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := (1.0 if area > 0.0 else -1.0) * (-1.0 if inward else 1.0)
	var f0: Dictionary = F[i]
	var f1: Dictionary = F[i + 1]
	for k in n:
		var a := prof[k]
		var b := prof[(k + 1) % n]
		var e := b - a
		if e.length_squared() < 1.0e-8:
			continue
		var nn := Vector2(e.y, -e.x).normalized() * sgn
		var n3: Vector3 = (f0["rt"] as Vector3) * nn.x + Vector3.UP * nn.y
		var p00 := _o(fp(F, i, a.x, a.y), org)
		var p01 := _o(fp(F, i, b.x, b.y), org)
		var p10 := _o(fp(F, i + 1, a.x, a.y), org)
		var p11 := _o(fp(F, i + 1, b.x, b.y), org)
		mb.quad(p00, p01, p11, p10, n3, col)


## Piers of every viaduct run in the chunk: a T pier on the street's middle in the city (never at a junction), bents elsewhere. Adds collision boxes {pos, size, yaw}.
static func _viaduct_piers(mb: MB, r: Dictionary, F: Array, i0: int, i1: int, org: Vector3, boxes: Array) -> void:
	var mode: PackedByteArray = r["mode"]
	var s: PackedFloat32Array = r["s"]
	var last_s := -1.0e9
	for i in range(i0, i1):
		if mode[i] != RailNet.MODE_VIADUCT:
			continue
		var f: Dictionary = F[i]
		var p: Vector3 = f["p"]
		var city := bool(r["elev"]) and TerrainHeight.city_distance(p.x, p.z) <= 0.0
		var want := false
		if city:
			var m := fposmod(p.x - 40.0, 80.0)
			m = minf(m, 80.0 - m)
			want = m < 4.5 and s[i] - last_s > 60.0
		else:
			want = s[i] - last_s >= 26.0
		if not want:
			continue
		if not city and s[i] - last_s < 150.0:                                 # wave 112 critic: a bent whose columns would stand in a carriageway (a viaduct crossing over a road) slides on to the next sample:
			var rt0: Vector3 = f["rt"]                                          # piers in the PASS ROAD and the RING ROAD lanes stopped cars dead (road audit: Collision_mountain at 242, -1341 and 229..305, -1313..-1347)
			var on_road := false
			for sx0 in [-1.0, 0.0, 1.0]:
				var cp0: Vector3 = p + rt0 * float(sx0) * 2.9
				var nr0 := TerrainRoads.nearest(cp0.x, cp0.z)
				if int(nr0[1]) >= 0 and float(nr0[0]) < float((TerrainRoads.roads()[int(nr0[1])] as Dictionary)["w"]) * 0.5 + 1.8:
					on_road = true
			if on_road:
				continue
		last_s = s[i]
		var g := TerrainHeight.height_at(p.x, p.z) if not city else 0.0
		var top := p.y - 2.7
		if top - g < 1.2:
			continue
		var yaw := atan2((f["t"] as Vector3).x, (f["t"] as Vector3).z)
		if city:
			var base := Vector3(p.x, g, p.z) - org
			mb.box_yaw(base + Vector3(0.0, (top - g) * 0.5, 0.0), Vector3(2.4, top - g, 2.4), yaw, CONCRETE, false)
			mb.box_yaw(base + Vector3(0.0, top - 0.55, 0.0) , Vector3(9.4, 1.1, 2.9), yaw, CONCRETE, true)
			boxes.append({"pos": Vector3(p.x, g + (top - g) * 0.5, p.z), "size": Vector3(2.4, top - g, 2.4), "yaw": yaw})
		else:
			var rt: Vector3 = f["rt"]
			for sx in [-1.0, 1.0]:
				var cx := p + rt * float(sx) * 2.9
				var gg := TerrainHeight.height_at(cx.x, cx.z) - 1.0
				if top - gg > 0.5:
					mb.box_yaw(Vector3(cx.x, gg, cx.z) - org + Vector3(0.0, (top - gg) * 0.5, 0.0), Vector3(1.5, top - gg, 1.5), yaw, CONCRETE, false)
					boxes.append({"pos": Vector3(cx.x, gg + (top - gg) * 0.5, cx.z), "size": Vector3(1.5, top - gg, 1.5), "yaw": yaw})
			mb.box_yaw(p - org + Vector3(0.0, -2.2, 0.0), Vector3(DECK_HW * 2.0 - 0.6, 0.9, 1.6), yaw, CONCRETE_DARK, true)


# --- tunnels ---------------------------------------------------------------------------------------------------------------------------

## Arch section of the tube: (lateral, dy) points from the left floor corner over the crown to the right floor corner. hw = half width, wall = height of the straight wall, rise = crown over it.
static func arch(hw: float, wall: float, rise: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(-hw, -0.5))
	out.append(Vector2(-hw, wall))
	for k in range(1, 8):
		var a := PI - PI * float(k) / 8.0
		out.append(Vector2(cos(a) * hw, wall + sin(a) * rise))
	out.append(Vector2(hw, wall))
	out.append(Vector2(hw, -0.5))
	return out


static func tube_params(r: Dictionary, i: int) -> Vector3:
	var hw := 3.7
	var wall := 3.2
	var rise := 3.7
	for st: Dictionary in r["stations"]:
		if bool(st["underground"]):
			var d := absf((r["s"] as PackedFloat32Array)[i] - float(st["s"])) - float(st["len"]) * 0.5 - 6.0
			var w := clampf(1.0 - d / 18.0, 0.0, 1.0)
			hw = lerpf(hw, 9.4, w)
			wall = lerpf(wall, 3.6, w)
			rise = lerpf(rise, 5.4, w)
	return Vector3(hw, wall, rise)


static func _tunnel_parts(mb: MB, r: Dictionary, F: Array, i0: int, i1: int, org: Vector3) -> void:
	var mode: PackedByteArray = r["mode"]
	var s: PackedFloat32Array = r["s"]
	for i in range(i0, i1):
		if mode[i] != RailNet.MODE_TUNNEL:
			continue
		var tp := tube_params(r, i)
		var prof := arch(tp.x, tp.y, tp.z)
		_strip(mb, F, i, prof, _c(Color(0.5, 0.5, 0.48), 2.0), org, true)
		if int(s[i] / 18.0) != int(s[i + 1] / 18.0):                         # lamps along both walls and a lit strip
			for sx in [-1.0, 1.0]:
				mb.box(_o(fp(F, i, float(sx) * (tp.x - 0.12), tp.y + 0.5), org), Vector3(0.22, 0.2, 2.2), LAMP, false)
		if (i == 0 or mode[i - 1] != RailNet.MODE_TUNNEL) or (i + 1 >= mode.size() - 1 or mode[i + 1] != RailNet.MODE_TUNNEL):
			_portal(mb, F, i, i == 0 or mode[i - 1] != RailNet.MODE_TUNNEL, tp, r, org)


## The headwall of a tunnel mouth: a wall with an arch opening, wing walls, a lamp bar. `entering` = the tube starts at sample i (the wall faces backwards along the route).
static func _portal(mb: MB, F: Array, i: int, entering: bool, tp: Vector3, r: Dictionary, org: Vector3) -> void:
	var f: Dictionary = F[i]
	var p: Vector3 = f["p"]
	var t: Vector3 = f["t"]
	var face := -t if entering else t                              # the wall faces away from the hill
	var rt: Vector3 = f["rt"]
	var ground := TerrainHeight.height_at(p.x, p.z)
	var wall_h := maxf(ground - p.y + 3.0, tp.y + tp.z + 2.4)
	wall_h = minf(wall_h, 26.0)
	var yaw := atan2(face.x, face.z)
	var base := p + (-face) * 0.0 - org
	var hw := tp.x + 3.6
	var top_open := tp.y + tp.z
	var col := _c(Color(0.58, 0.57, 0.54), 2.0)
	# two jambs, a lintel above the crown, wing walls flaring out
	mb.box_yaw(base + rt * (hw * 0.5 + tp.x * 0.5) + Vector3(0.0, wall_h * 0.5 - 0.5, 0.0), Vector3(hw - tp.x, wall_h, 2.4), yaw, col, false)
	mb.box_yaw(base - rt * (hw * 0.5 + tp.x * 0.5) + Vector3(0.0, wall_h * 0.5 - 0.5, 0.0), Vector3(hw - tp.x, wall_h, 2.4), yaw, col, false)
	mb.box_yaw(base + Vector3(0.0, (wall_h + top_open) * 0.5 - 0.5, 0.0), Vector3(tp.x * 2.0 + 0.1, wall_h - top_open, 2.4), yaw, col, false)
	mb.box_yaw(base + face * 0.2 + Vector3(0.0, top_open - 0.2, 0.0), Vector3(tp.x * 2.0 + 1.0, 0.45, 2.6), yaw, CONCRETE_DARK, true)
	for sx in [-1.0, 1.0]:
		mb.box_yaw(base + rt * float(sx) * (hw + 0.4) - face * 2.2 + Vector3(0.0, wall_h * 0.4, 0.0), Vector3(1.0, wall_h * 0.8 + 0.5, 6.0), yaw + float(sx) * 0.35, CONCRETE_DARK, false)
	mb.box_yaw(base + face * 0.16 + Vector3(0.0, top_open - 1.0, 0.0), Vector3(tp.x * 1.4, 0.18, 0.1), yaw, LAMP, false)


# --- stations ---------------------------------------------------------------------------------------------------------------------------

static func _station(mb: MB, r: Dictionary, st: Dictionary, F: Array, i0: int, i1: int, org: Vector3, boxes: Array) -> void:
	var s: PackedFloat32Array = r["s"]
	var half := float(st["len"]) * 0.5
	var elevated := bool(r["elev"]) and TerrainHeight.city_distance((F[int(st["ic"])]["p"] as Vector3).x, (F[int(st["ic"])]["p"] as Vector3).z) <= 0.0
	var under: bool = bool(st["underground"])
	var plat_w := 4.2
	var step_every := 1
	for i in range(i0, i1):
		if s[i + 1] < float(st["s"]) - half or s[i] > float(st["s"]) + half:
			continue
		var f0: Dictionary = F[i]
		var f1: Dictionary = F[i + 1]
		var p0: Vector3 = f0["p"]
		var p1: Vector3 = f1["p"]
		var t: Vector3 = f0["t"]
		var yaw := atan2(t.x, t.z)
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1) + 0.25
		var k := (float(f0["k"]) + float(f1["k"])) * 0.5
		var inner := RailNet.HALF_SEP * k + 1.62
		for sx in [-1.0, 1.0]:
			var lat := float(sx) * (inner + plat_w * 0.5)
			var c := mid + (f0["rt"] as Vector3) * lat - org
			var depth := 1.7 if (elevated or under) else 1.15
			mb.box_yaw(c + Vector3(0.0, RailNet.PLATFORM_Y - depth * 0.5, 0.0), Vector3(plat_w, depth, seg), yaw, _c(Color(0.7, 0.69, 0.66), 2.0), true)
			# the yellow safety strip at the edge and a tactile band
			mb.box_yaw(mid + (f0["rt"] as Vector3) * float(sx) * (inner + 0.28) - org + Vector3(0.0, RailNet.PLATFORM_Y + 0.01, 0.0), Vector3(0.5, 0.03, seg), yaw, Color(0.95, 0.78, 0.1, 0.0), false)
		boxes.append({"pos": mid + Vector3(0.0, RailNet.PLATFORM_Y - 0.6, 0.0) + (f0["rt"] as Vector3) * (inner + plat_w * 0.5), "size": Vector3(plat_w, 1.2, seg), "yaw": yaw})
		boxes.append({"pos": mid + Vector3(0.0, RailNet.PLATFORM_Y - 0.6, 0.0) - (f0["rt"] as Vector3) * (inner + plat_w * 0.5), "size": Vector3(plat_w, 1.2, seg), "yaw": yaw})
		# canopy: posts every 12 m, a roof over each platform (not underground)
		if not under:
			var roof_y := RailNet.PLATFORM_Y + 4.5
			for sx in [-1.0, 1.0]:
				var lat2 := float(sx) * (inner + plat_w * 0.5)
				mb.box_yaw(mid + (f0["rt"] as Vector3) * lat2 - org + Vector3(0.0, roof_y, 0.0), Vector3(plat_w + 0.8, 0.22, seg), yaw, _c(Color(0.78, 0.8, 0.82), 6.0), true)
				mb.box_yaw(mid + (f0["rt"] as Vector3) * lat2 - org + Vector3(0.0, roof_y + 0.18, 0.0), Vector3(plat_w + 0.5, 0.12, seg), yaw, STEEL, false)
				if int((s[i] - (float(st["s"]) - half)) / 12.0) != int((s[i + 1] - (float(st["s"]) - half)) / 12.0):
					mb.box_yaw(mid + (f0["rt"] as Vector3) * float(sx) * (inner + plat_w - 0.4) - org + Vector3(0.0, roof_y * 0.5 + 0.4, 0.0), Vector3(0.3, roof_y, 0.3), yaw, STEEL_DARK, false)
					mb.box_yaw(mid + (f0["rt"] as Vector3) * float(sx) * (inner + plat_w * 0.5) - org + Vector3(0.0, roof_y - 0.35, 0.0), Vector3(plat_w, 0.1, 0.1), yaw, LAMP, false)
		else:
			for sx in [-1.0, 1.0]:                                    # benches and lamps along the cavern platforms
				if int((s[i] - (float(st["s"]) - half)) / 10.0) != int((s[i + 1] - (float(st["s"]) - half)) / 10.0):
					mb.box_yaw(mid + (f0["rt"] as Vector3) * float(sx) * (inner + plat_w * 0.7) - org + Vector3(0.0, RailNet.PLATFORM_Y + 0.25, 0.0), Vector3(0.5, 0.5, 2.0), yaw, WOOD, false)
	# the station hall (beside the platform, outside the track) on the ground stations; ramps up to an elevated platform
	var ic: int = int(st["ic"])
	if ic >= i0 and ic < i1 and not under:
		var f: Dictionary = F[ic]
		var t2: Vector3 = f["t"]
		var yaw2 := atan2(t2.x, t2.z)
		var side := 1.0
		var base := (f["p"] as Vector3) + (f["rt"] as Vector3) * side * (RailNet.HALF_SEP * float(f["k"]) + 1.62 + plat_w + 6.0) - org
		if elevated:
			_ramps(mb, r, st, F, org, boxes, i0, i1)
		else:
			mb.box_yaw(base + Vector3(0.0, 2.8, 0.0), Vector3(9.0, 5.6, 22.0), yaw2, _c(Color(0.82, 0.8, 0.74), 2.0), false)
			mb.box_yaw(base + Vector3(0.0, 5.75, 0.0), Vector3(10.8, 0.4, 24.0), yaw2, CONCRETE_DARK, true)
			for k in 5:
				mb.box_yaw(base - (f["rt"] as Vector3) * 4.52 + t2 * (-8.0 + float(k) * 4.0) + Vector3(0.0, 3.0, 0.0), Vector3(0.12, 1.7, 2.4), yaw2, GLASS, false)
			mb.box_yaw(base - (f["rt"] as Vector3) * 4.52 + Vector3(0.0, 1.2, 0.0), Vector3(0.14, 2.4, 2.0), yaw2, _c(Color(0.28, 0.3, 0.34), 0.0), false)
			boxes.append({"pos": base + org + Vector3(0.0, 2.8, 0.0), "size": Vector3(9.0, 5.6, 22.0), "yaw": yaw2})
			# a name board on posts in front of the hall
			mb.box_yaw(base - (f["rt"] as Vector3) * 5.4 + Vector3(0.0, 4.4, 0.0), Vector3(0.2, 1.6, 7.0), yaw2, _c(Color(0.1, 0.25, 0.5), 0.0), false)


## Two ramps down from the ends of an elevated platform to the street: stairs on a slope, a rail on each side. Colliders are tilted boxes.
static func _ramps(mb: MB, r: Dictionary, st: Dictionary, F: Array, org: Vector3, boxes: Array, i0: int, i1: int) -> void:
	var half := float(st["len"]) * 0.5
	for end in [-1.0, 1.0]:
		var u0: float = float(st["s"]) + float(end) * (half - 0.5)
		var pa := RailNet.point_at(r, u0)
		var t: Vector3 = Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
		var rt := RailNet.right_of(t)
		var top_y: float = (pa[0] as Vector3).y + RailNet.PLATFORM_Y
		var side := float(end) * -1.0                                       # opposite sides at the two ends
		var lat := side * 7.9
		var length := top_y / 0.3
		var steps := int(length / 0.55)
		var dir := t * float(end)
		var start := (pa[0] as Vector3) + rt * lat
		start.y = 0.0
		var from := start
		var yaw_t := atan2(t.x, t.z)
		for k in steps:
			var f := float(k) / float(steps)
			var c := from + dir * (length * f + 0.3) + Vector3(0.0, top_y * (1.0 - f) - 0.15, 0.0)
			mb.box_yaw(c - org, Vector3(2.7, 0.3, 0.55), yaw_t, CONCRETE_LIGHT, false)
		# side rails
		for sd in [-1.0, 1.0]:
			var a := from + rt * float(sd) * 1.45
			var b := a + dir * length
			mb.strut(a + Vector3(0.0, top_y + 0.9, 0.0) - org, b + Vector3(0.0, 0.9, 0.0) - org, 0.1, STEEL)
			mb.strut(a + Vector3(0.0, top_y - 0.1, 0.0) - org, b + Vector3(0.0, -0.1, 0.0) - org, 0.14, CONCRETE_DARK)
		# collider: a ramp box tilted along the slope
		var mid := from + dir * length * 0.5 + Vector3(0.0, top_y * 0.5 - 0.2, 0.0)
		var slope := atan2(top_y, length)
		var yaw := atan2(dir.x, dir.z)
		boxes.append({"pos": mid, "size": Vector3(2.9, 0.4, sqrt(length * length + top_y * top_y)), "yaw": yaw, "pitch": slope})
		# landing at the platform end: the platform slab continues to the ramp
		mb.box_yaw(start + dir * -1.0 + Vector3(0.0, top_y - 0.2, 0.0) - org, Vector3(2.9, 0.4, 2.0), yaw_t, CONCRETE_LIGHT, false)
		boxes.append({"pos": start + dir * -1.0 + Vector3(0.0, top_y - 0.2, 0.0), "size": Vector3(2.9, 0.4, 2.0), "yaw": yaw_t})


# --- level crossings and signals -------------------------------------------------------------------------------------------------------

static func _crossing_static(mb: MB, c: Dictionary, org: Vector3) -> void:
	var p: Vector3 = c["pos"]
	var rd: Vector2 = c["road_dir"]
	var rtv: Vector2 = c["dir"]
	var yaw := atan2(-rd.y, rd.x)
	var rw: float = float(c["road_w"])
	# the road surface over the rails: a slab with a rubber look
	mb.box_yaw(Vector3(p.x, p.y + 0.0, p.z) - org + Vector3(0.0, 0.07, 0.0), Vector3(rw + 3.0, 0.16, 2.0 * (RailNet.HALF_SEP + 1.9)), yaw, ASPHALT, false)
	# crossbucks on both approaches, on the right-hand side of each road direction
	for sd in [-1.0, 1.0]:
		var travel := Vector3(rd.x, 0.0, rd.y) * float(sd)
		var right := RailNet.right_of(travel)
		var q := Vector3(p.x, p.y, p.z) - travel * (RailNet.HALF_SEP + 5.6) + right * (rw * 0.5 + 1.1) - org
		mb.box(q + Vector3(0.0, 1.6, 0.0), Vector3(0.12, 3.2, 0.12), STEEL, false)
		mb.strut(q + Vector3(-0.8, 3.3, 0.0), q + Vector3(0.8, 4.1, 0.0), 0.14, SIGN_WHITE)
		mb.strut(q + Vector3(-0.8, 4.1, 0.0), q + Vector3(0.8, 3.3, 0.0), 0.14, SIGN_WHITE)
		mb.strut(q + Vector3(0.0, 3.3, 0.18), q + Vector3(0.0, 4.1, 0.18), 0.06, SIGN_RED)


## The static pole of a signal: the head (black box) with the two lamps is a node (RailWorld).
static func _signal_pole(mb: MB, r: Dictionary, sg: Dictionary, org: Vector3) -> void:
	var u := float(sg["u"])
	var pa := RailNet.point_at(r, u)
	var t: Vector3 = Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
	var rt := RailNet.right_of(t)
	var d := float(sg["dir"])
	var base: Vector3 = (pa[0] as Vector3) + rt * d * (RailNet.HALF_SEP * float(pa[2]) + 3.3)
	var q := base - org
	mb.box(q + Vector3(0.0, 2.6, 0.0), Vector3(0.18, 5.4, 0.18), STEEL_DARK, false)
	mb.box(q + Vector3(0.0, 4.9, 0.0) + t * d * 0.0, Vector3(0.5, 1.2, 0.3), _c(Color(0.05, 0.05, 0.06), 0.0), true)


## Position and heading (yaw) where the head of a signal sits (the lamps are drawn there).
static func signal_head(r: Dictionary, sg: Dictionary) -> Array:
	var pa := RailNet.point_at(r, float(sg["u"]))
	var t := Vector3((pa[1] as Vector3).x, 0.0, (pa[1] as Vector3).z).normalized()
	var d := float(sg["dir"])
	var base: Vector3 = (pa[0] as Vector3) + RailNet.right_of(t) * d * (RailNet.HALF_SEP * float(pa[2]) + 3.3)
	return [base + Vector3(0.0, 5.0, 0.0) - t * d * 0.2, atan2(-t.x * d, -t.z * d)]


## The inner surface of a tunnel run (floor, walls, crown) for its trimesh collider, relative to its own origin (returned too).
static func tunnel_collider_mesh(r: Dictionary, run: Dictionary) -> Dictionary:
	var F := frames(r)
	var org: Vector3 = F[int(run["i0"])]["p"]
	var mb := MB.new()
	for i in range(int(run["i0"]), int(run["i1"])):
		var tp := tube_params(r, i)
		_strip(mb, F, i, arch(tp.x, tp.y, tp.z), Color.WHITE, org, true)
		var fl0 := _o(fp(F, i, -tp.x, -0.5), org)
		var fl1 := _o(fp(F, i, tp.x, -0.5), org)
		var fl2 := _o(fp(F, i + 1, tp.x, -0.5), org)
		var fl3 := _o(fp(F, i + 1, -tp.x, -0.5), org)
		mb.quad(fl0, fl1, fl2, fl3, Vector3.UP, Color.WHITE)
	return {"mesh": mb.build(null, false, false), "origin": org}
