class_name SettlementParts
extends RefCounted
## The parts a town is built from (wave 112): roofs, windows, doors, porches, fences, lamps, trees and the small things of a street, all as SettlementMesh geometry in a part's own frame
## (origin on the ground, front is -Z). Builders of whole buildings (SettlementHouses, SettlementSpecials) combine them; SettlementKit caches the results and places them.
## Orientation: faces are listed so that (p1 - p0) x (p3 - p0) points outwards; `quad_h` / `tri_h` / `poly_h` take a HINT direction instead and flip themselves.

const PAINT := SettlementMesh.PAINT
const SIDING := SettlementMesh.SIDING
const BRICK := SettlementMesh.BRICK
const STONE := SettlementMesh.STONE
const LOG := SettlementMesh.LOG
const TILE := SettlementMesh.TILE
const SHINGLE := SettlementMesh.SHINGLE
const SHEET := SettlementMesh.SHEET
const GLASS := SettlementMesh.GLASS
const WOOD := SettlementMesh.WOOD
const CONCRETE := SettlementMesh.CONCRETE
const LAWN := SettlementMesh.LAWN
const DIRT := SettlementMesh.DIRT
const METAL := SettlementMesh.METAL
const ADOBE := SettlementMesh.ADOBE
const GLOW := SettlementMesh.GLOW
const ASPHALT := SettlementMesh.ASPHALT
const PICKET := SettlementMesh.PICKET
const LEAF := SettlementMesh.LEAF
const WATER := SettlementMesh.WATER
const AWNING := SettlementMesh.AWNING


static func hash01(seed_v: int, k: int) -> float:
	var h := (seed_v * 73856093) ^ (k * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0x1000000)


# --- oriented faces ---------------------------------------------------------------------------------------------------------------------------

static func quad_h(m: SettlementMesh, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, hint: Vector3, base: Color, code: int, ao := 1.0, ao_b := 1.0, uvo := Vector2.ZERO, prm := 0.0) -> void:
	var nn := (p1 - p0).cross(p3 - p0)
	if nn.dot(hint) < 0.0:
		m.quad(p1, p0, p3, p2, base, code, ao, ao_b, uvo, prm)
	else:
		m.quad(p0, p1, p2, p3, base, code, ao, ao_b, uvo, prm)


static func tri_h(m: SettlementMesh, p0: Vector3, p1: Vector3, p2: Vector3, hint: Vector3, base: Color, code: int, ao := 1.0, ao_b := 1.0, uvo := Vector2.ZERO) -> void:
	var nn := (p1 - p0).cross(p2 - p0)
	if nn.dot(hint) < 0.0:
		m.tri(p1, p0, p2, base, code, ao, ao_b, uvo)
	else:
		m.tri(p0, p1, p2, base, code, ao, ao_b, uvo)


## A convex polygon (a barn gable) as a fan from its first point; `hint` is the outward direction. UV = metres along `u_axis` and up.
static func poly_h(m: SettlementMesh, pts: Array, hint: Vector3, base: Color, code: int, ao := 1.0, ao_b := 1.0) -> void:
	var p0: Vector3 = pts[0]
	var p1: Vector3 = pts[1]
	var p2: Vector3 = pts[2]
	var nn: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
	var flip: bool = nn.dot(hint) < 0.0
	nn = -nn if flip else nn
	var cc := SettlementMesh.col(base, code)
	var i0 := m.v.size()
	var u_axis: Vector3 = (p1 - p0).normalized()
	if absf(u_axis.y) > 0.9:
		u_axis = (p2 - p1).normalized()
	u_axis.y = 0.0
	u_axis = u_axis.normalized()
	var y0 := 1.0e9
	for p: Vector3 in pts:
		y0 = minf(y0, p.y)
	for p: Vector3 in pts:
		m.v.append(p)
		m.n.append(nn)
		m.c.append(cc)
		m.uv.append(Vector2((p - p0).dot(u_axis), p.y - y0))
		m.uv2.append(Vector2(ao * (ao_b if p.y - y0 < 0.3 else 1.0), 0.0))
	for k in range(1, pts.size() - 1):
		if flip:
			m.idx.append(i0)
			m.idx.append(i0 + k)
			m.idx.append(i0 + k + 1)
		else:
			m.idx.append(i0)
			m.idx.append(i0 + k + 1)
			m.idx.append(i0 + k)


# --- walls: windows and doors -----------------------------------------------------------------------------------------------------------------

## A window pane (one quad with the frame, mullion and sill drawn by the shader) centred at `c` on a wall whose outward normal is `nrm`; shutters at both sides when `shutter.a > 0`.
static func window(m: SettlementMesh, c: Vector3, nrm: Vector3, w: float, h: float, frame: Color, glow: float, shutter := Color(0, 0, 0, 0), seed_v := 0) -> void:
	var r := Vector3.UP.cross(nrm).normalized()
	var u := Vector3.UP
	var o := nrm * 0.03
	m.quad(c - r * w * 0.5 - u * h * 0.5 + o, c + r * w * 0.5 - u * h * 0.5 + o, c + r * w * 0.5 + u * h * 0.5 + o, c - r * w * 0.5 + u * h * 0.5 + o, frame, GLASS, 1.0, 1.0, Vector2.ZERO, glow, nrm, true)
	if shutter.a > 0.0:
		var sw := w * 0.46
		for sgn in [-1.0, 1.0]:
			var sc: Vector3 = c + r * (w * 0.5 + sw * 0.5 + 0.02) * float(sgn) + nrm * 0.05
			m.quad(sc - r * sw * 0.5 - u * h * 0.5, sc + r * sw * 0.5 - u * h * 0.5, sc + r * sw * 0.5 + u * h * 0.5, sc - r * sw * 0.5 + u * h * 0.5, Color(shutter.r, shutter.g, shutter.b), WOOD, 1.0, 1.0, Vector2(float(seed_v % 7), 0.0))


## A door at the foot of a wall (`base` on the wall surface, bottom centre), trim frame around it, a step slab in front.
static func door(m: SettlementMesh, base: Vector3, nrm: Vector3, w: float, h: float, door_col: Color, trim_col: Color, step := true) -> void:
	var r := Vector3.UP.cross(nrm).normalized()
	var u := Vector3.UP
	var tw := w + 0.28
	var th := h + 0.16
	m.quad(base - r * tw * 0.5 + nrm * 0.02, base + r * tw * 0.5 + nrm * 0.02, base + r * tw * 0.5 + u * th + nrm * 0.02, base - r * tw * 0.5 + u * th + nrm * 0.02, trim_col, PAINT, 1.0, 1.0)
	m.quad(base - r * w * 0.5 + nrm * 0.05, base + r * w * 0.5 + nrm * 0.05, base + r * w * 0.5 + u * h + nrm * 0.05, base - r * w * 0.5 + u * h + nrm * 0.05, door_col, WOOD, 1.0, 0.8)
	if step:
		var sc := base + nrm * 0.42
		var s0 := m.v.size()
		m.box(Vector3(0.0, 0.07, 0.0), Vector3(w + 0.7, 0.14, 0.84), Color(0.55, 0.53, 0.5), CONCRETE, 32, 0.9, 0.8)
		var yaw := atan2(nrm.x, nrm.z)
		m.transform_from(s0, Transform3D(Basis(Vector3.UP, yaw), sc))


## Windows in a row on one storey of a wall. `origin` is the bottom-left of the wall piece seen from outside, `right` its direction, `len` its length; `skip_from`/`skip_to` leave a gap (a door).
static func window_row(m: SettlementMesh, origin: Vector3, right: Vector3, len: float, y0: float, nrm: Vector3, bay: float, w: float, h: float, frame: Color, glow: float, shutter: Color, seed_v: int, skip_from := -1.0, skip_to := -1.0) -> int:
	var n := maxi(1, int(round((len - 0.8) / bay)))
	var made := 0
	for i in n:
		var t := (float(i) + 0.5) / float(n) * len
		if t > skip_from and t < skip_to:
			continue
		window(m, origin + right * t + Vector3(0.0, y0 + h * 0.5, 0.0), nrm, w, h, frame, glow if hash01(seed_v, i * 7 + int(y0 * 10.0)) > 0.25 else 0.0, shutter, seed_v + i)
		made += 1
	return made


# --- roofs --------------------------------------------------------------------------------------------------------------------------------------

## A gable roof, ridge along Z: walls W wide (x), L long (z), eaves at height y_e, `slope` = rise / (W / 2), plane continued `ov` beyond the walls and the gables `ovg` out. The two gable triangles close the ends.
static func gable_roof(m: SettlementMesh, W: float, L: float, y_e: float, slope: float, ov: float, ovg: float, roof: Color, rcode: int, gable: Color, gcode: int, soffit := true) -> void:
	var rise := slope * W * 0.5
	var yr := y_e + rise
	var ye := y_e - slope * ov
	var hx := W * 0.5 + ov
	var hz := L * 0.5 + ovg
	quad_h(m, Vector3(-hx, ye, -hz), Vector3(-hx, ye, hz), Vector3(0.0, yr, hz), Vector3(0.0, yr, -hz), Vector3(-1, 1, 0), roof, rcode, 1.0, 1.0, Vector2.ZERO)
	quad_h(m, Vector3(hx, ye, -hz), Vector3(hx, ye, hz), Vector3(0.0, yr, hz), Vector3(0.0, yr, -hz), Vector3(1, 1, 0), roof, rcode, 1.0, 1.0, Vector2(3.0, 0.0))
	tri_h(m, Vector3(-W * 0.5, y_e, -L * 0.5), Vector3(W * 0.5, y_e, -L * 0.5), Vector3(0.0, yr, -L * 0.5), Vector3(0, 0, -1), gable, gcode, 1.0, 0.9)
	tri_h(m, Vector3(-W * 0.5, y_e, L * 0.5), Vector3(W * 0.5, y_e, L * 0.5), Vector3(0.0, yr, L * 0.5), Vector3(0, 0, 1), gable, gcode, 1.0, 0.9)
	if soffit and ov > 0.05:
		for sgn in [-1.0, 1.0]:
			var sx: float = float(sgn)
			quad_h(m, Vector3(sx * W * 0.5, y_e, -hz), Vector3(sx * W * 0.5, y_e, hz), Vector3(sx * hx, ye, hz), Vector3(sx * hx, ye, -hz), Vector3(0, -1, 0), Color(0.34, 0.3, 0.27), PAINT, 0.62, 1.0)


## A hip roof (four planes) over W x L at eave height y_e; the ridge runs along the longer side.
static func hip_roof(m: SettlementMesh, W: float, L: float, y_e: float, slope: float, ov: float, roof: Color, rcode: int) -> void:
	var half := minf(W, L) * 0.5
	var rise := slope * half
	var yr := y_e + rise
	var ye := y_e - slope * ov
	var hx := W * 0.5 + ov
	var hz := L * 0.5 + ov
	var along_z := L >= W
	var rl := absf(L - W) * 0.5                       # half length of the ridge
	var ra := Vector3(0.0, yr, -rl) if along_z else Vector3(-rl, yr, 0.0)
	var rb := Vector3(0.0, yr, rl) if along_z else Vector3(rl, yr, 0.0)
	var fl := Vector3(-hx, ye, -hz)
	var fr := Vector3(hx, ye, -hz)
	var bl := Vector3(-hx, ye, hz)
	var br := Vector3(hx, ye, hz)
	if along_z:
		quad_h(m, fl, bl, rb, ra, Vector3(-1, 1, 0), roof, rcode)
		quad_h(m, fr, br, rb, ra, Vector3(1, 1, 0), roof, rcode, 1.0, 1.0, Vector2(3.0, 0.0))
		tri_h(m, fl, fr, ra, Vector3(0, 1, -1), roof, rcode)
		tri_h(m, bl, br, rb, Vector3(0, 1, 1), roof, rcode)
	else:
		quad_h(m, fl, fr, rb, ra, Vector3(0, 1, -1), roof, rcode)
		quad_h(m, bl, br, rb, ra, Vector3(0, 1, 1), roof, rcode, 1.0, 1.0, Vector2(3.0, 0.0))
		tri_h(m, fl, bl, ra, Vector3(-1, 1, 0), roof, rcode)
		tri_h(m, fr, br, rb, Vector3(1, 1, 0), roof, rcode)


## A flat roof with a parapet.
static func flat_roof(m: SettlementMesh, W: float, L: float, y_e: float, parapet: float, wall: Color, wcode: int, cap: Color) -> void:
	m.box(Vector3(0.0, y_e + 0.06, 0.0), Vector3(W + 0.1, 0.12, L + 0.1), cap, CONCRETE, 32, 0.95, 1.0)
	if parapet > 0.05:
		var t := 0.18
		m.box(Vector3(0.0, y_e + 0.12 + parapet * 0.5, -(L * 0.5 - t * 0.5 + 0.05)), Vector3(W + 0.1, parapet, t), wall, wcode, 32, 1.0, 1.0)
		m.box(Vector3(0.0, y_e + 0.12 + parapet * 0.5, (L * 0.5 - t * 0.5 + 0.05)), Vector3(W + 0.1, parapet, t), wall, wcode, 32, 1.0, 1.0)
		m.box(Vector3(-(W * 0.5 - t * 0.5 + 0.05), y_e + 0.12 + parapet * 0.5, 0.0), Vector3(t, parapet, L - 2.0 * t + 0.1), wall, wcode, 32, 1.0, 1.0)
		m.box(Vector3((W * 0.5 - t * 0.5 + 0.05), y_e + 0.12 + parapet * 0.5, 0.0), Vector3(t, parapet, L - 2.0 * t + 0.1), wall, wcode, 32, 1.0, 1.0)


## A single sloping roof (lean-to): high side at -Z (`high` height), low side at +Z.
static func shed_roof(m: SettlementMesh, W: float, L: float, y_high: float, y_low: float, ov: float, roof: Color, rcode: int, side_col: Color, side_code: int) -> void:
	var hx := W * 0.5 + ov
	var hz := L * 0.5 + ov
	quad_h(m, Vector3(-hx, y_low, hz), Vector3(hx, y_low, hz), Vector3(hx, y_high, -hz), Vector3(-hx, y_high, -hz), Vector3(0, 1, 1), roof, rcode)
	tri_h(m, Vector3(-W * 0.5, y_low, L * 0.5), Vector3(-W * 0.5, y_low, -L * 0.5), Vector3(-W * 0.5, y_high, -L * 0.5), Vector3(-1, 0, 0), side_col, side_code)
	tri_h(m, Vector3(W * 0.5, y_low, L * 0.5), Vector3(W * 0.5, y_low, -L * 0.5), Vector3(W * 0.5, y_high, -L * 0.5), Vector3(1, 0, 0), side_col, side_code)


## A gambrel (barn) roof, ridge along Z: steep lower planes to the knee, shallow upper planes to the ridge.
static func gambrel_roof(m: SettlementMesh, W: float, L: float, y_e: float, knee_h: float, ridge_h: float, ov: float, roof: Color, rcode: int, gable: Color, gcode: int) -> void:
	var kx := W * 0.5 * 0.62
	var yk := y_e + knee_h
	var yr := yk + ridge_h
	var hz := L * 0.5 + 0.35
	var ex := W * 0.5 + ov
	var ye := y_e - ov * (knee_h / (W * 0.5 - kx))
	for sgn in [-1.0, 1.0]:
		var sx: float = float(sgn)
		quad_h(m, Vector3(sx * ex, ye, -hz), Vector3(sx * ex, ye, hz), Vector3(sx * kx, yk, hz), Vector3(sx * kx, yk, -hz), Vector3(sx, 1, 0), roof, rcode)
		quad_h(m, Vector3(sx * kx, yk, -hz), Vector3(sx * kx, yk, hz), Vector3(0.0, yr, hz), Vector3(0.0, yr, -hz), Vector3(sx * 0.6, 1, 0), roof, rcode, 1.0, 1.0, Vector2(3.0, 0.0))
	for zz in [-1.0, 1.0]:
		var sz: float = float(zz)
		poly_h(m, [Vector3(-W * 0.5, y_e, sz * L * 0.5), Vector3(W * 0.5, y_e, sz * L * 0.5), Vector3(kx, yk, sz * L * 0.5), Vector3(0.0, yr, sz * L * 0.5), Vector3(-kx, yk, sz * L * 0.5)], Vector3(0, 0, sz), gable, gcode, 1.0, 0.85)


## A chimney: a box from `y0` to `y1` at (x, z) with a cap.
static func chimney(m: SettlementMesh, x: float, z: float, y0: float, y1: float, base: Color, code: int, size := 0.62) -> void:
	m.box(Vector3(x, (y0 + y1) * 0.5, z), Vector3(size, y1 - y0, size), base, code, 32, 1.0, 1.0)
	m.box(Vector3(x, y1 + 0.06, z), Vector3(size + 0.16, 0.12, size + 0.16), Color(0.5, 0.48, 0.45), CONCRETE, 32, 1.0, 1.0)


# --- porch, garage, balcony, awning -----------------------------------------------------------------------------------------------------------

## A porch on the front wall (at z = -d/2, centred at x): floor, two posts, a shed roof.
static func porch(m: SettlementMesh, x: float, wall_z: float, width: float, depth: float, height: float, wood: Color, roof: Color, rcode: int, floor_h := 0.28) -> void:
	m.box(Vector3(x, floor_h * 0.5, wall_z - depth * 0.5), Vector3(width, floor_h, depth), wood, WOOD, 32, 0.92, 0.8)
	var pz := wall_z - depth + 0.14
	for sgn in [-1.0, 1.0]:
		m.box(Vector3(x + float(sgn) * (width * 0.5 - 0.14), floor_h + height * 0.5, pz), Vector3(0.14, height, 0.14), Color(0.92, 0.9, 0.85), PAINT, 32 | 4, 1.0, 0.9)
	var s0 := m.v.size()
	shed_roof(m, width + 0.3, depth + 0.1, floor_h + height + 0.25, floor_h + height, 0.1, roof, rcode, Color(0.9, 0.88, 0.84), PAINT)
	m.transform_from(s0, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, wall_z - depth * 0.5)))


## A balcony slab with a picket railing on the wall at z = wall_z (front is -Z).
static func balcony(m: SettlementMesh, x: float, wall_z: float, width: float, depth: float, y: float, wood: Color, rail: Color) -> void:
	m.box(Vector3(x, y - 0.06, wall_z - depth * 0.5), Vector3(width, 0.12, depth), wood, WOOD, 32, 0.9, 1.0)
	var rz := wall_z - depth
	m.quad(Vector3(x + width * 0.5, y, rz), Vector3(x - width * 0.5, y, rz), Vector3(x - width * 0.5, y + 0.95, rz), Vector3(x + width * 0.5, y + 0.95, rz), rail, PICKET, 1.0, 1.0, Vector2.ZERO, 0.95)
	for sgn in [-1.0, 1.0]:
		quad_h(m, Vector3(x + float(sgn) * width * 0.5, y, rz), Vector3(x + float(sgn) * width * 0.5, y, wall_z), Vector3(x + float(sgn) * width * 0.5, y + 0.95, wall_z), Vector3(x + float(sgn) * width * 0.5, y + 0.95, rz), Vector3(float(sgn), 0, 0), rail, PICKET, 1.0, 1.0, Vector2.ZERO, 0.95)


## A shop awning over the front wall (z = wall_z): a sloped striped sheet.
static func awning(m: SettlementMesh, x: float, wall_z: float, width: float, depth: float, y: float, col: Color) -> void:
	quad_h(m, Vector3(x - width * 0.5, y, wall_z), Vector3(x + width * 0.5, y, wall_z), Vector3(x + width * 0.5, y - 0.55, wall_z - depth), Vector3(x - width * 0.5, y - 0.55, wall_z - depth), Vector3(0, 1, -1), col, AWNING, 1.0, 1.0)
	quad_h(m, Vector3(x - width * 0.5, y - 0.55, wall_z - depth), Vector3(x + width * 0.5, y - 0.55, wall_z - depth), Vector3(x + width * 0.5, y - 0.8, wall_z - depth), Vector3(x - width * 0.5, y - 0.8, wall_z - depth), Vector3(0, 0, -1), col.darkened(0.15), AWNING, 1.0, 1.0)


# --- small things of a street -------------------------------------------------------------------------------------------------------------------

## A picket fence run from a to b (ground y given by a.y / b.y): ONE board strip (the shader cuts the gaps), a top rail and a post every 3.5 m.
static func fence(m: SettlementMesh, a: Vector3, b: Vector3, h: float, paint: Color, both_sides := true) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.3:
		return
	var t := dir / length
	var nrm := Vector3(-t.z, 0.0, t.x)
	var up := Vector3(0.0, h, 0.0)
	m.quad(a, b, b + up, a + up, paint, PICKET, 1.0, 0.9, Vector2.ZERO, h, nrm)
	if both_sides:
		m.quad(b, a, a + up, b + up, paint, PICKET, 1.0, 0.9, Vector2.ZERO, h, -nrm)
	var posts := maxi(2, int(ceil(length / 3.5)) + 1)
	for i in posts:
		var p := a + dir * (float(i) / float(posts - 1))
		m.box(Vector3(p.x, p.y + h * 0.5 + 0.05, p.z), Vector3(0.12, h + 0.1, 0.12), paint, WOOD, 32, 1.0, 1.0)


## A low wall of stone or a wire fence: a box strip.
static func wall_run(m: SettlementMesh, a: Vector3, b: Vector3, h: float, thick: float, base: Color, code: int) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.3:
		return
	var s0 := m.v.size()
	m.box(Vector3(0.0, h * 0.5, 0.0), Vector3(thick, h, length), base, code, 32, 1.0, 0.8)
	var yaw := atan2(dir.x, dir.z)
	m.transform_from(s0, Transform3D(Basis(Vector3.UP, yaw), (a + b) * 0.5))


## A hedge: a clipped box of leaves.
static func hedge(m: SettlementMesh, a: Vector3, b: Vector3, h: float, thick: float, leaf: Color) -> void:
	wall_run(m, a, b, h, thick, leaf, LEAF)


## A street lamp: pole, arm over the street (towards -Z of the part), glowing head.
static func lamp(m: SettlementMesh, h := 6.4, arm := 1.4, pole := Color(0.2, 0.22, 0.24)) -> void:
	m.cylinder(Vector3.ZERO, 0.09, h, 6, pole, METAL, 0.06, true, 1.0, 0.7)
	m.box(Vector3(0.0, h - 0.04, -arm * 0.5), Vector3(0.09, 0.09, arm), pole, METAL, 32, 1.0, 1.0)
	m.box(Vector3(0.0, h - 0.12, -arm), Vector3(0.28, 0.1, 0.5), Color(1.0, 0.92, 0.7), GLOW, 4, 1.0, 1.0)
	m.box(Vector3(0.0, h - 0.02, -arm), Vector3(0.34, 0.06, 0.56), pole, METAL, 32, 1.0, 1.0)


## A mailbox on a post (front is -Z).
static func mailbox(m: SettlementMesh, col_box: Color) -> void:
	m.box(Vector3(0.0, 0.55, 0.0), Vector3(0.07, 1.1, 0.07), Color(0.35, 0.28, 0.2), WOOD, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 1.16, 0.0), Vector3(0.24, 0.2, 0.42), col_box, METAL, 32, 1.0, 1.0)


## A bench.
static func bench(m: SettlementMesh, wood: Color) -> void:
	m.box(Vector3(0.0, 0.45, 0.0), Vector3(1.6, 0.07, 0.45), wood, WOOD, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 0.82, 0.22), Vector3(1.6, 0.35, 0.05), wood, WOOD, 32, 1.0, 1.0)
	for sgn in [-1.0, 1.0]:
		m.box(Vector3(float(sgn) * 0.7, 0.22, 0.0), Vector3(0.07, 0.44, 0.4), Color(0.2, 0.2, 0.22), METAL, 32, 1.0, 1.0)


## A hay bale / crate / barrel group: small boxes.
static func bale(m: SettlementMesh, col_bale := Color(0.78, 0.66, 0.32)) -> void:
	m.cylinder(Vector3(0.0, 0.0, 0.0), 0.7, 1.1, 10, col_bale, LAWN, -1.0, true, 1.0, 0.8, 1.0)


# --- pets -------------------------------------------------------------------------------------------------------------------------------------------

## A dog (0.9 m long, 0.6 m at the head), nose to -Z. `seed_v` (0..3) picks the coat. Fur is the rough ADOBE shader class (noise, no pattern).
static func pet_dog(m: SettlementMesh, seed_v: int) -> void:
	var coats: Array[Color] = [Color(0.55, 0.36, 0.2), Color(0.14, 0.13, 0.12), Color(0.82, 0.74, 0.58), Color(0.86, 0.84, 0.8)]
	var c: Color = coats[seed_v & 3]
	var dk := c.darkened(0.35)
	m.box(Vector3(0.0, 0.46, 0.04), Vector3(0.28, 0.3, 0.62), c, ADOBE, 32, 1.0, 0.9)
	m.box(Vector3(0.0, 0.7, -0.36), Vector3(0.2, 0.24, 0.25), c, ADOBE, 32, 1.0, 1.0)
	m.box(Vector3(0.0, 0.64, -0.53), Vector3(0.11, 0.1, 0.14), dk.lightened(0.08), ADOBE, 32, 1.0, 1.0)
	for sx in [-1.0, 1.0]:
		m.box(Vector3(float(sx) * 0.09, 0.85, -0.33), Vector3(0.06, 0.1, 0.07), dk, ADOBE, 32, 1.0, 1.0)
		for sz in [-1.0, 1.0]:
			m.box(Vector3(float(sx) * 0.09, 0.15, float(sz) * 0.2 + 0.04), Vector3(0.07, 0.3, 0.08), c.darkened(0.12), ADOBE, 32, 1.0, 0.8)
	m.tube(Vector3(0.0, 0.56, 0.34), Vector3(0.0, 0.8, 0.5), 0.045, 0.025, 4, c, ADOBE, 1.0, 1.0)


## A cat (0.45 m long), nose to -Z.
static func pet_cat(m: SettlementMesh, seed_v: int) -> void:
	var coats: Array[Color] = [Color(0.85, 0.5, 0.2), Color(0.16, 0.15, 0.15), Color(0.8, 0.8, 0.78), Color(0.5, 0.46, 0.42)]
	var c: Color = coats[seed_v & 3]
	m.box(Vector3(0.0, 0.2, 0.03), Vector3(0.15, 0.16, 0.34), c, ADOBE, 32, 1.0, 0.9)
	m.box(Vector3(0.0, 0.32, -0.2), Vector3(0.13, 0.13, 0.12), c, ADOBE, 32, 1.0, 1.0)
	for sx in [-1.0, 1.0]:
		m.box(Vector3(float(sx) * 0.045, 0.42, -0.19), Vector3(0.04, 0.06, 0.03), c.darkened(0.25), ADOBE, 32, 1.0, 1.0)
		for sz in [-1.0, 1.0]:
			m.box(Vector3(float(sx) * 0.05, 0.07, float(sz) * 0.12 + 0.03), Vector3(0.045, 0.14, 0.05), c.darkened(0.1), ADOBE, 32, 1.0, 0.8)
	m.tube(Vector3(0.0, 0.22, 0.2), Vector3(0.0, 0.5, 0.3), 0.03, 0.02, 4, c, ADOBE, 1.0, 1.0)


# --- trees ------------------------------------------------------------------------------------------------------------------------------------

## A broadleaf tree: trunk, three overlapping crowns. `s` scales it (1 = 7 m).
static func tree_broad(m: SettlementMesh, seed_v: int, s := 1.0, leaf := Color(0.2, 0.42, 0.16)) -> void:
	var trunk := Color(0.3, 0.22, 0.15)
	m.cylinder(Vector3.ZERO, 0.22 * s, 2.6 * s, 6, trunk, WOOD, 0.14 * s, true, 1.0, 0.7)
	var j := hash01(seed_v, 1)
	var lc := leaf.lightened(j * 0.12).darkened((1.0 - j) * 0.06)
	m.blob(Vector3(0.0, 3.9 * s, 0.0), Vector3(2.0, 1.7, 2.0) * s, 9, 5, lc, LEAF, 1.0, 0.0, 0.6)
	m.blob(Vector3(1.0 * s, 3.4 * s, 0.5 * s), Vector3(1.4, 1.2, 1.4) * s, 8, 4, lc.darkened(0.08), LEAF, 1.0, 0.0, 0.6)
	m.blob(Vector3(-0.8 * s, 3.2 * s, -0.7 * s), Vector3(1.3, 1.1, 1.3) * s, 8, 4, lc.lightened(0.06), LEAF, 1.0, 0.0, 0.6)


## A conifer: trunk and three stacked cones.
static func tree_pine(m: SettlementMesh, seed_v: int, s := 1.0, leaf := Color(0.1, 0.27, 0.15)) -> void:
	m.cylinder(Vector3.ZERO, 0.2 * s, 1.6 * s, 6, Color(0.28, 0.2, 0.14), WOOD, 0.14 * s, true, 1.0, 0.7)
	var j := hash01(seed_v, 2)
	var lc := leaf.lightened(j * 0.1)
	m.cone(Vector3(0.0, 1.2 * s, 0.0), 1.9 * s, 3.2 * s, 9, lc, LEAF, 0.8)
	m.cone(Vector3(0.0, 2.6 * s, 0.0), 1.5 * s, 2.8 * s, 9, lc.lightened(0.04), LEAF, 0.9)
	m.cone(Vector3(0.0, 4.0 * s, 0.0), 1.0 * s, 2.4 * s, 8, lc.lightened(0.08), LEAF, 1.0)


## A palm: a leaning trunk in segments and a crown of fronds (flat quads, seen from both sides).
static func tree_palm(m: SettlementMesh, seed_v: int, s := 1.0) -> void:
	var trunk := Color(0.5, 0.4, 0.3)
	var lean := Vector2(0.55 * (hash01(seed_v, 3) - 0.5), 0.55 * (hash01(seed_v, 4) - 0.5)) * s
	var pos := Vector3.ZERO
	var segs := 5
	var hh := 6.0 * s
	for i in segs:
		var f0 := float(i) / float(segs)
		var f1 := float(i + 1) / float(segs)
		var p0 := Vector3(lean.x * f0 * f0 * 4.0, hh * f0, lean.y * f0 * f0 * 4.0)
		var p1 := Vector3(lean.x * f1 * f1 * 4.0, hh * f1, lean.y * f1 * f1 * 4.0)
		var r0 := 0.2 * s * (1.0 - 0.35 * f0)
		var r1 := 0.2 * s * (1.0 - 0.35 * f1)
		m.tube(p0, p1, r0, r1, 6, trunk, WOOD, 1.0, 0.75 if i == 0 else 1.0)
		pos = p1
	var leaf := Color(0.16, 0.46, 0.2)
	for k in 8:
		var a := TAU * float(k) / 8.0 + hash01(seed_v, 5) * 0.6
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var tip := pos + dir * 3.0 * s + Vector3(0.0, -1.2 * s, 0.0)
		var mid := pos + dir * 1.6 * s + Vector3(0.0, 0.5 * s, 0.0)
		var w := 0.55 * s
		m.quad(pos - side * 0.12 * s, pos + side * 0.12 * s, mid + side * w, mid - side * w, leaf, LEAF, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3.UP)
		m.quad(mid - side * w, mid + side * w, tip + side * 0.1 * s, tip - side * 0.1 * s, leaf.darkened(0.1), LEAF, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3.UP)
		m.quad(pos + side * 0.12 * s, pos - side * 0.12 * s, mid - side * w, mid + side * w, leaf, LEAF, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3.DOWN)
		m.quad(mid + side * w, mid - side * w, tip - side * 0.1 * s, tip + side * 0.1 * s, leaf.darkened(0.1), LEAF, 1.0, 1.0, Vector2.ZERO, 0.0, Vector3.DOWN)


## A bush.
static func bush(m: SettlementMesh, seed_v: int, s := 1.0, leaf := Color(0.18, 0.4, 0.15)) -> void:
	var lc := leaf.lightened(hash01(seed_v, 6) * 0.1)
	m.blob(Vector3(0.0, 0.55 * s, 0.0), Vector3(0.8, 0.6, 0.8) * s, 7, 4, lc, LEAF, 1.0, 0.0, 0.5)
	m.blob(Vector3(0.5 * s, 0.4 * s, 0.2 * s), Vector3(0.55, 0.45, 0.55) * s, 6, 3, lc.darkened(0.08), LEAF, 1.0, 0.0, 0.5)
