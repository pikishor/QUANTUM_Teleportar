class_name OutskirtsKit
extends RefCounted
## Meshes of the outskirts' sites (data: OutskirtsSites). `build(site)` returns one merged ArrayMesh per site (ONE draw call: assets/shaders/outskirts_kit.gdshader, vertex colour = paint,
## COLOR.a = material code / 8) plus what the live node needs: collision boxes, lamp positions (lit windows share the mesh; these are for real lights), animated parts, the interaction point.
## Everything is built in the site's local frame (origin = the middle of the pad on the pad height, +Y up, the site's front is -Z, OutskirtsSites.to_world turns it into world space).
##   {mesh, boxes: [{pos: Vector3, size: Vector3, yaw: float}], rotors: [{mesh, pos, axis, speed}], lamps: [{pos, color, energy, range}], use: Vector3, tris}
## Material codes (alpha * 8): 0 paint, 1 timber, 2 rock and stone, 3 metal, 4 lit glass or lamp, 5 roof shingles, 6 corrugated sheet, 7 alien hull, 8 soil / hay / grass.

const MB := preload("res://scripts/world/mesh_builder.gd")
const SHADER := preload("res://assets/shaders/outskirts_kit.gdshader")

const PAINT := 0.0
const WOOD := 1.0 / 8.0
const ROCK := 2.0 / 8.0
const METAL := 3.0 / 8.0
const GLOW := 4.0 / 8.0
const SHINGLE := 5.0 / 8.0
const SHEET := 6.0 / 8.0
const ALIEN := 7.0 / 8.0
const SOIL := 8.0 / 8.0

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


static func _c(r: float, g: float, b: float, code: float) -> Color:
	return Color(r, g, b, code)


static func _rng(site: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(site["id"])) & 0x7fffffff
	return r


## The meshes and parts of a site (by kind). Returns {} for an unknown kind.
static func build(site: Dictionary) -> Dictionary:
	var mb := MB.new()
	var out := {"boxes": [], "rotors": [], "lamps": [], "use": Vector3(0.0, 0.0, -6.0)}
	var rng := _rng(site)
	match StringName(site["kind"]):
		&"cabins":
			_cabins(mb, out, rng, site)
		&"farm":
			_farm(mb, out, rng, site)
		&"village":
			_village(mb, out, rng, site)
		&"tower":
			_tower(mb, out)
		&"observatory":
			_observatory(mb, out)
		&"mine":
			_mine(mb, out, rng)
		&"crash":
			_crash(mb, out, rng, site)
		&"cave":
			_cave_mouth(mb, out, rng)
		_:
			return {}
	out["mesh"] = mb.build(material())
	var n := 0
	for s in (out["mesh"] as ArrayMesh).get_surface_count():
		n += ((out["mesh"] as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	out["tris"] = n
	return out


## A rock lump: a jittered ellipsoid with flat-shaded facets (a smooth sphere reads as a marshmallow). Lower third flattened so it sits on the ground.
static func _lump(mb: MB, c: Vector3, radii: Vector3, col: Color, rng: RandomNumberGenerator, segs := 9, rings := 4) -> void:
	var grid: Array = []
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		var row: Array[Vector3] = []
		for k in segs:
			var th := TAU * float(k) / float(segs) + 0.35 * float(r)
			var j := 1.0 + rng.randf_range(-0.22, 0.2)
			if r == 0 or r == rings:
				j = 1.0
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var p := c + Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z) * j
			p.y = maxf(p.y, c.y - radii.y * 0.45)
			row.append(p)
		grid.append(row)
	for r in rings:
		var a: Array = grid[r]
		var b: Array = grid[r + 1]
		for k in segs:
			var k2 := (k + 1) % segs
			var shade := 0.82 + 0.3 * rng.randf()
			var cc := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
			_facet(mb, a[k], b[k], b[k2], cc, c)
			if r > 0:
				_facet(mb, a[k], b[k2], a[k2], cc, c)


static func _facet(mb: MB, p0: Vector3, p1: Vector3, p2: Vector3, col: Color, centre: Vector3) -> void:
	var n := (p1 - p0).cross(p2 - p0)
	if n.length() < 1.0e-6:
		return
	n = n.normalized()
	if n.dot(((p0 + p1 + p2) / 3.0) - centre) < 0.0:
		n = -n
	mb.quad(p0, p1, p2, p2, n, col)


static func _box_col(out: Dictionary, pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	(out["boxes"] as Array).append({"pos": pos, "size": size, "yaw": yaw})


## A yawed box with its base on `base`.
static func _bx(mb: MB, base: Vector3, size: Vector3, yaw: float, col: Color) -> void:
	mb.box_yaw(base + Vector3(0.0, size.y * 0.5, 0.0), size, yaw, col, false)


# --- small parts ------------------------------------------------------------------------------------------------------------------------------

## A log cabin: walls, a gable roof with overhang, porch with two posts, a chimney, door and windows. Built around the origin then placed at `p` with `yaw`.
static func _cabin(mb: MB, out: Dictionary, p: Vector3, w: float, d: float, yaw: float, wood: Color, roof: Color, lit := true, plank := false) -> void:
	var start := mb.verts.size()
	var h := 2.7
	mb.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wood, false)
	mb.box(Vector3(0.0, 0.18, 0.0), Vector3(w + 0.5, 0.36, d + 0.5), _c(0.26, 0.25, 0.24, ROCK), false)                       # stone footing
	var rise := w * 0.34
	mb.prism(PackedVector2Array([Vector2(-w * 0.5 - 0.6, h), Vector2(w * 0.5 + 0.6, h), Vector2(0.0, h + rise)]), -d * 0.5 - 0.7, d * 0.5 + 0.7, roof)
	mb.box(Vector3(0.0, h + 0.05, 0.0), Vector3(w + 1.2, 0.12, d + 1.4), _c(0.1, 0.07, 0.05, WOOD), false)                    # eaves board
	mb.box(Vector3(w * 0.28, h + rise * 0.8, d * 0.18), Vector3(0.7, rise * 1.6, 0.7), _c(0.3, 0.28, 0.27, ROCK), false)         # chimney
	# door and windows (front is -Z)
	mb.box(Vector3(0.0, 1.05, -d * 0.5 - 0.03), Vector3(1.0, 2.1, 0.1), _c(0.07, 0.045, 0.03, WOOD), false)
	var win := _c(1.0, 0.78, 0.42, GLOW) if lit else _c(0.05, 0.07, 0.09, GLOW)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * w * 0.3, 1.55, -d * 0.5 - 0.03), Vector3(0.9, 0.8, 0.1), win, false)
		mb.box(Vector3(float(sx) * (w * 0.5 + 0.03), 1.55, 0.0), Vector3(0.1, 0.8, 0.9), win, false)
	# porch
	mb.box(Vector3(0.0, 0.22, -d * 0.5 - 1.0), Vector3(w * 0.7, 0.2, 2.0), _c(0.2, 0.12, 0.07, WOOD), false)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * w * 0.32, 1.3, -d * 0.5 - 1.8), Vector3(0.22, 2.4, 0.22), _c(0.2, 0.12, 0.07, WOOD), false)
	mb.box(Vector3(0.0, 2.5, -d * 0.5 - 1.1), Vector3(w * 0.8, 0.14, 2.3), roof, false)
	mb.xform_from(start, Transform3D(Basis(Vector3.UP, yaw), p))
	_box_col(out, p + Basis(Vector3.UP, yaw) * Vector3(0.0, h * 0.5 + rise * 0.3, 0.0), Vector3(w, h + rise * 0.6, d), yaw)
	if lit:
		(out["lamps"] as Array).append({"pos": p + Basis(Vector3.UP, yaw) * Vector3(0.0, 1.6, -d * 0.5 - 1.5), "color": Color(1.0, 0.75, 0.4), "energy": 0.9, "range": 10.0})


static func _fence(mb: MB, a: Vector3, b: Vector3, h := 1.1) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 3.0))
	var col := _c(0.22, 0.14, 0.08, WOOD)
	for i in n + 1:
		var p := a + d * (float(i) / float(n))
		mb.box(p + Vector3(0.0, h * 0.5, 0.0), Vector3(0.14, h, 0.14), col, false)
	mb.strut(a + Vector3(0.0, h * 0.8, 0.0), b + Vector3(0.0, h * 0.8, 0.0), 0.07, col)
	mb.strut(a + Vector3(0.0, h * 0.4, 0.0), b + Vector3(0.0, h * 0.4, 0.0), 0.07, col)


static func _tree_stump_pile(mb: MB, p: Vector3, rng: RandomNumberGenerator) -> void:
	for i in 5:
		var q := p + Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		mb.cylinder(q, 0.22, 0.6, 7, _c(0.25, 0.15, 0.08, WOOD), -1.0, true, false)


static func _haystack(mb: MB, p: Vector3, r: float) -> void:
	mb.cylinder(p, r, r * 1.3, 10, _c(0.62, 0.5, 0.2, SOIL), r * 0.55, true, false)
	mb.sphere(p + Vector3(0.0, r * 1.3, 0.0), Vector3(r * 0.55, r * 0.35, r * 0.55), 8, 3, _c(0.62, 0.5, 0.2, SOIL))


static func _bale(mb: MB, p: Vector3, yaw: float) -> void:
	var s := mb.verts.size()
	mb.cylinder(Vector3(0.0, 0.0, -0.6), 0.65, 1.2, 10, _c(0.66, 0.54, 0.22, SOIL), -1.0, true, true)
	mb.xform_from(s, Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0.0, 0.65, 0.0)))


static func _lamp_post(mb: MB, out: Dictionary, p: Vector3, h := 4.2) -> void:
	mb.cylinder(p, 0.09, h, 6, _c(0.2, 0.2, 0.22, METAL))
	mb.box(p + Vector3(0.0, h + 0.1, 0.0), Vector3(0.4, 0.2, 0.4), _c(1.0, 0.82, 0.5, GLOW), false)
	(out["lamps"] as Array).append({"pos": p + Vector3(0.0, h, 0.0), "color": Color(1.0, 0.8, 0.5), "energy": 0.8, "range": 12.0})


# --- cabins ----------------------------------------------------------------------------------------------------------------------------------

static func _cabins(mb: MB, out: Dictionary, rng: RandomNumberGenerator, site: Dictionary) -> void:
	var woods := [_c(0.20, 0.115, 0.06, WOOD), _c(0.24, 0.14, 0.07, WOOD), _c(0.17, 0.10, 0.06, WOOD)]
	var roofs := [_c(0.16, 0.09, 0.07, SHINGLE), _c(0.12, 0.13, 0.12, SHINGLE), _c(0.2, 0.1, 0.07, SHINGLE)]
	var spots := [Vector3(0.0, 0.0, 2.0), Vector3(-17.0, 0.0, -6.0), Vector3(16.0, 0.0, -9.0), Vector3(2.0, 0.0, 19.0)]
	var sizes := [Vector2(7.5, 6.0), Vector2(6.0, 5.2), Vector2(6.4, 5.4), Vector2(5.2, 4.6)]
	for i in 4:
		_cabin(mb, out, spots[i], sizes[i].x, sizes[i].y, rng.randf_range(-0.3, 0.3) + (0.0 if i == 0 else PI * 0.02 * float(i)), woods[i % 3], roofs[(i + 1) % 3], i < 3)
	# campfire ring, benches, woodpile, a fence around the clearing, a lamp post, a well-worn path
	var ring := Vector3(-3.0, 0.0, -11.0)
	for k in 8:
		var a := TAU * float(k) / 8.0
		mb.box(ring + Vector3(cos(a), 0.15, sin(a)) * 1.3, Vector3(0.5, 0.3, 0.5), _c(0.3, 0.29, 0.28, ROCK), false)
	mb.cylinder(ring, 0.5, 0.35, 8, _c(0.12, 0.06, 0.03, WOOD), 0.15, true, false)
	(out["lamps"] as Array).append({"pos": ring + Vector3(0.0, 0.9, 0.0), "color": Color(1.0, 0.5, 0.2), "energy": 1.3, "range": 14.0})
	for sx in [-1.0, 1.0]:
		mb.box(ring + Vector3(float(sx) * 2.4, 0.3, 0.0), Vector3(0.5, 0.6, 2.2), _c(0.2, 0.12, 0.07, WOOD), false)
	for i in 6:
		mb.box(Vector3(-24.0, 0.3 + float(i / 3) * 0.55, -3.0 + float(i % 3) * 0.9), Vector3(1.5, 0.5, 0.7), _c(0.22, 0.13, 0.07, WOOD), false)
	_box_col(out, Vector3(-24.0, 0.6, -2.0), Vector3(1.6, 1.2, 3.0))
	_tree_stump_pile(mb, Vector3(22.0, 0.0, 6.0), rng)
	var r := 33.0
	var n := 14
	for k in n:
		if k >= 2 and k <= 3:
			continue                                                       # a gap in the fence at the front: the way in
		var a0 := TAU * float(k) / float(n) + PI * 0.5
		var a1 := TAU * float(k + 1) / float(n) + PI * 0.5
		_fence(mb, Vector3(cos(a0) * r, 0.0, sin(a0) * r), Vector3(cos(a1) * r, 0.0, sin(a1) * r))
	_lamp_post(mb, out, Vector3(-5.0, 0.0, -17.0))
	out["use"] = Vector3(0.0, 0.0, -9.0)


# --- farms -----------------------------------------------------------------------------------------------------------------------------------

static func _barn(mb: MB, out: Dictionary, p: Vector3, yaw: float, w: float, d: float, red: Color) -> void:
	var s := mb.verts.size()
	var h := 5.0
	mb.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), red, false)
	# gambrel roof: two stacked prisms
	var roof := _c(0.28, 0.29, 0.31, SHEET)
	mb.prism(PackedVector2Array([Vector2(-w * 0.5 - 0.4, h), Vector2(w * 0.5 + 0.4, h), Vector2(w * 0.32, h + 2.3), Vector2(-w * 0.32, h + 2.3)]), -d * 0.5 - 0.5, d * 0.5 + 0.5, roof)
	mb.prism(PackedVector2Array([Vector2(-w * 0.32, h + 2.3), Vector2(w * 0.32, h + 2.3), Vector2(0.0, h + 3.7)]), -d * 0.5 - 0.5, d * 0.5 + 0.5, roof)
	# big doors with white X, hayloft door
	var white := _c(0.82, 0.82, 0.8, PAINT)
	mb.box(Vector3(0.0, 2.0, -d * 0.5 - 0.04), Vector3(3.6, 4.0, 0.1), _c(0.34, 0.07, 0.05, PAINT), false)
	mb.strut(Vector3(-1.8, 0.1, -d * 0.5 - 0.1), Vector3(1.8, 3.9, -d * 0.5 - 0.1), 0.12, white)
	mb.strut(Vector3(1.8, 0.1, -d * 0.5 - 0.1), Vector3(-1.8, 3.9, -d * 0.5 - 0.1), 0.12, white)
	mb.box(Vector3(0.0, h + 1.1, -d * 0.5 - 0.5), Vector3(1.4, 1.5, 0.1), _c(0.06, 0.04, 0.03, PAINT), false)
	mb.xform_from(s, Transform3D(Basis(Vector3.UP, yaw), p))
	_box_col(out, p + Vector3(0.0, h * 0.5 + 1.2, 0.0), Vector3(w, h + 2.4, d), yaw)


static func _silo(mb: MB, out: Dictionary, p: Vector3) -> void:
	mb.cylinder(p, 2.3, 12.0, 14, _c(0.62, 0.64, 0.66, SHEET), -1.0, false, false)
	mb.sphere(p + Vector3(0.0, 12.0, 0.0), Vector3(2.3, 1.6, 2.3), 14, 4, _c(0.5, 0.52, 0.55, SHEET))
	for k in 4:
		mb.box(p + Vector3(0.0, 2.8 + float(k) * 2.8, 0.0), Vector3(4.7, 0.12, 4.7) * 0.5, _c(0.4, 0.42, 0.45, METAL), false)
	_box_col(out, p + Vector3(0.0, 6.0, 0.0), Vector3(4.5, 12.0, 4.5))


static func _windmill(mb: MB, out: Dictionary, p: Vector3) -> void:
	var col := _c(0.65, 0.66, 0.68, METAL)
	var top := 13.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.strut(p + Vector3(float(sx) * 1.6, 0.0, float(sz) * 1.6), p + Vector3(float(sx) * 0.35, top, float(sz) * 0.35), 0.16, col)
	for k in 4:
		var y := 2.5 + float(k) * 2.6
		var w := lerpf(1.6, 0.35, y / top)
		mb.strut(p + Vector3(-w, y, -w), p + Vector3(w, y, -w), 0.08, col)
		mb.strut(p + Vector3(-w, y, w), p + Vector3(w, y, w), 0.08, col)
		mb.strut(p + Vector3(-w, y, -w), p + Vector3(-w, y, w), 0.08, col)
		mb.strut(p + Vector3(w, y, -w), p + Vector3(w, y, w), 0.08, col)
	mb.box(p + Vector3(0.0, top + 0.3, 0.0), Vector3(0.9, 0.7, 1.4), _c(0.4, 0.42, 0.45, METAL), false)
	mb.box(p + Vector3(0.0, top + 0.5, 2.2), Vector3(0.08, 0.9, 2.6), _c(0.8, 0.8, 0.78, PAINT), false)            # tail vane
	# the wheel is its own mesh (it turns)
	var rb := MB.new()
	for k in 12:
		var a := TAU * float(k) / 12.0
		rb.strut(Vector3.ZERO, Vector3(cos(a) * 2.6, sin(a) * 2.6, 0.0), 0.1, _c(0.85, 0.85, 0.82, METAL))
		rb.box(Vector3(cos(a) * 1.9, sin(a) * 1.9, 0.0), Vector3(0.9, 0.5, 0.06), _c(0.8, 0.8, 0.78, METAL), false)
	(out["rotors"] as Array).append({"mesh": rb.build(material()), "pos": p + Vector3(0.0, top + 0.3, -0.9), "axis": Vector3(0.0, 0.0, 1.0), "speed": 1.2})
	_box_col(out, p + Vector3(0.0, 6.5, 0.0), Vector3(3.2, 13.0, 3.2))


static func _farmhouse(mb: MB, out: Dictionary, p: Vector3, yaw: float, w: float, d: float, wall: Color, roof: Color) -> void:
	var s := mb.verts.size()
	var h := 2.9
	mb.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, false)
	mb.prism(PackedVector2Array([Vector2(-w * 0.5 - 0.5, h), Vector2(w * 0.5 + 0.5, h), Vector2(0.0, h + w * 0.3)]), -d * 0.5 - 0.5, d * 0.5 + 0.5, roof)
	mb.box(Vector3(-w * 0.25, h + w * 0.2, 0.0), Vector3(0.7, w * 0.4, 0.7), _c(0.3, 0.2, 0.17, ROCK), false)
	mb.box(Vector3(0.0, 1.05, -d * 0.5 - 0.03), Vector3(1.0, 2.1, 0.1), _c(0.22, 0.1, 0.06, WOOD), false)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * w * 0.3, 1.6, -d * 0.5 - 0.03), Vector3(1.0, 1.0, 0.1), _c(1.0, 0.8, 0.45, GLOW), false)
		mb.box(Vector3(float(sx) * w * 0.3, 1.6, d * 0.5 + 0.03), Vector3(1.0, 1.0, 0.1), _c(1.0, 0.8, 0.45, GLOW), false)
	mb.box(Vector3(0.0, 0.2, -d * 0.5 - 0.9), Vector3(w * 0.6, 0.15, 1.8), _c(0.55, 0.55, 0.53, ROCK), false)
	mb.xform_from(s, Transform3D(Basis(Vector3.UP, yaw), p))
	_box_col(out, p + Vector3(0.0, h * 0.5 + 0.8, 0.0), Vector3(w, h + 1.6, d), yaw)


static func _farm(mb: MB, out: Dictionary, rng: RandomNumberGenerator, _site: Dictionary) -> void:
	_barn(mb, out, Vector3(-22.0, 0.0, 12.0), 0.15, 9.0, 14.0, _c(0.34, 0.07, 0.05, PAINT))
	_silo(mb, out, Vector3(-30.0, 0.0, 26.0))
	_silo(mb, out, Vector3(-24.5, 0.0, 28.0))
	_farmhouse(mb, out, Vector3(14.0, 0.0, -4.0), -0.25, 9.0, 6.5, _c(0.62, 0.6, 0.55, PAINT), _c(0.22, 0.08, 0.06, SHINGLE))
	(out["lamps"] as Array).append({"pos": Vector3(14.0, 1.7, -9.5), "color": Color(1.0, 0.75, 0.4), "energy": 0.9, "range": 11.0})
	_windmill(mb, out, Vector3(30.0, 0.0, 10.0))
	# an open shed and a trailer of tools
	mb.box(Vector3(26.0, 1.6, -22.0), Vector3(8.0, 0.14, 5.0), _c(0.3, 0.31, 0.33, SHEET), false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box(Vector3(26.0 + float(sx) * 3.7, 0.8, -22.0 + float(sz) * 2.3), Vector3(0.2, 1.6, 0.2), _c(0.2, 0.12, 0.07, WOOD), false)
	_box_col(out, Vector3(26.0, 1.0, -22.0), Vector3(8.0, 2.0, 5.0))
	# crop rows in two fields (low boxes: no collision), hay, a fenced yard
	for f in 2:
		var origin := Vector3(-8.0 + float(f) * 40.0, 0.0, -42.0) if f == 0 else Vector3(26.0, 0.0, 34.0)
		var col := _c(0.20, 0.34, 0.09, SOIL) if f == 0 else _c(0.58, 0.46, 0.14, SOIL)
		for i in 14:
			var rowx := origin.x + float(i) * 1.7
			mb.box(Vector3(rowx, 0.17, origin.z), Vector3(0.8, 0.34, 26.0), col, false)
	for i in 5:
		_bale(mb, Vector3(2.0 + float(i) * 1.6, 0.0, 18.0 + rng.randf_range(-0.3, 0.3)), rng.randf_range(0.0, 3.0))
	_haystack(mb, Vector3(-2.0, 0.0, 30.0), 2.2)
	_fence(mb, Vector3(-14.0, 0.0, -10.0), Vector3(8.0, 0.0, -10.0))
	_fence(mb, Vector3(-14.0, 0.0, -10.0), Vector3(-14.0, 0.0, 2.0))
	_fence(mb, Vector3(8.0, 0.0, -10.0), Vector3(8.0, 0.0, 4.0))
	# a water trough and a tractor-sized stack of crates stand in for machinery
	mb.box(Vector3(8.0, 0.4, 22.0), Vector3(3.0, 0.8, 0.9), _c(0.4, 0.43, 0.46, METAL), false)
	_box_col(out, Vector3(8.0, 0.4, 22.0), Vector3(3.0, 0.8, 0.9))
	_lamp_post(mb, out, Vector3(4.0, 0.0, -14.0))
	out["use"] = Vector3(4.0, 0.0, -8.0)


# --- villages --------------------------------------------------------------------------------------------------------------------------------

static func _village(mb: MB, out: Dictionary, rng: RandomNumberGenerator, site: Dictionary) -> void:
	var desert: bool = site["id"] == &"dust_wells"
	# the street: a packed-earth strip down the middle (flat, a few cm above the pad, no collision)
	mb.box(Vector3(0.0, 0.03, 0.0), Vector3(9.0, 0.06, 150.0), _c(0.30, 0.24, 0.17, SOIL) if desert else _c(0.22, 0.17, 0.11, SOIL), false)
	var wall_cols := [_c(0.42, 0.29, 0.19, PAINT), _c(0.46, 0.32, 0.21, PAINT), _c(0.5, 0.37, 0.25, PAINT), _c(0.38, 0.27, 0.18, PAINT)] if desert else [_c(0.22, 0.125, 0.07, WOOD), _c(0.26, 0.15, 0.08, WOOD), _c(0.19, 0.11, 0.065, WOOD), _c(0.30, 0.19, 0.1, WOOD)]
	var roof_cols := [_c(0.2, 0.14, 0.1, PAINT), _c(0.34, 0.22, 0.13, PAINT)] if desert else [_c(0.17, 0.09, 0.07, SHINGLE), _c(0.12, 0.13, 0.14, SHINGLE), _c(0.2, 0.1, 0.07, SHINGLE)]
	var zs := [-50.0, -30.0, -9.0, 12.0, 33.0, 52.0]
	for i in zs.size():
		for side in [-1.0, 1.0]:
			var w := rng.randf_range(6.0, 9.0)
			var d := rng.randf_range(6.0, 8.5)
			var p := Vector3(float(side) * (11.0 + w * 0.5 + rng.randf_range(0.0, 2.5)), 0.0, zs[i] + rng.randf_range(-3.0, 3.0))
			var yaw := (PI * 0.5 if side < 0.0 else -PI * 0.5) + rng.randf_range(-0.12, 0.12)     # fronts face the street
			if desert:
				_adobe(mb, out, p, w, d, yaw, wall_cols[rng.randi() % wall_cols.size()], roof_cols[rng.randi() % roof_cols.size()], i == 2 and side > 0.0)
			else:
				_cabin(mb, out, p, w, d, yaw, wall_cols[rng.randi() % wall_cols.size()], roof_cols[rng.randi() % roof_cols.size()], rng.randf() < 0.8)
	# the well, a market stall or two, a tower (water tank in the desert, a bell tower in the forest), lamps along the street
	var well := Vector3(0.0, 0.0, -2.0)
	mb.cylinder(well, 1.1, 0.9, 10, _c(0.3, 0.29, 0.28, ROCK), -1.0, false, false)
	for sx in [-1.0, 1.0]:
		mb.box(well + Vector3(float(sx) * 1.0, 1.4, 0.0), Vector3(0.14, 1.6, 0.14), _c(0.2, 0.12, 0.07, WOOD), false)
	mb.prism(PackedVector2Array([Vector2(-1.4, 2.2), Vector2(1.4, 2.2), Vector2(0.0, 3.0)]), -0.9, 0.9, _c(0.18, 0.1, 0.07, SHINGLE))
	_box_col(out, well + Vector3(0.0, 0.45, 0.0), Vector3(2.2, 0.9, 2.2))
	if desert:
		var tank := Vector3(0.0, 0.0, 28.0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				mb.strut(tank + Vector3(float(sx) * 1.5, 0.0, float(sz) * 1.5), tank + Vector3(float(sx) * 1.2, 7.0, float(sz) * 1.2), 0.2, _c(0.3, 0.3, 0.32, METAL))
		mb.cylinder(tank + Vector3(0.0, 7.0, 0.0), 2.2, 3.2, 12, _c(0.55, 0.57, 0.58, SHEET), 2.2, true, true)
		_box_col(out, tank + Vector3(0.0, 4.0, 0.0), Vector3(3.2, 8.0, 3.2))
		for k in 3:                                                         # palm-like pillars
			mb.cylinder(Vector3(-16.0 + float(k) * 16.0, 0.0, 66.0), 0.25, 5.0, 6, _c(0.28, 0.2, 0.12, WOOD), 0.15, true, false)
	else:
		var tw := Vector3(8.0, 0.0, 16.0)
		mb.box(tw + Vector3(0.0, 3.0, 0.0), Vector3(3.4, 6.0, 3.4), _c(0.24, 0.14, 0.08, WOOD), false)
		mb.prism(PackedVector2Array([Vector2(-2.2, 6.0), Vector2(2.2, 6.0), Vector2(0.0, 9.5)]), -2.2, 2.2, _c(0.12, 0.13, 0.14, SHINGLE))
		mb.box(tw + Vector3(0.0, 5.3, -1.72), Vector3(1.0, 1.2, 0.1), _c(1.0, 0.8, 0.45, GLOW), false)
		_box_col(out, tw + Vector3(0.0, 4.0, 0.0), Vector3(3.4, 8.0, 3.4))
	for i in 3:
		var sp := Vector3(-6.0 if i % 2 == 0 else 6.0, 0.0, -36.0 + float(i) * 34.0)
		_lamp_post(mb, out, sp)
	# market stalls with striped awnings
	for i in 2:
		var sp2 := Vector3(-5.5 + float(i) * 11.0, 0.0, 6.0 + float(i) * 12.0)
		mb.box(sp2 + Vector3(0.0, 0.5, 0.0), Vector3(3.0, 1.0, 1.4), _c(0.3, 0.19, 0.1, WOOD), false)
		for sx in [-1.0, 1.0]:
			mb.box(sp2 + Vector3(float(sx) * 1.4, 1.2, -0.6), Vector3(0.1, 2.4, 0.1), _c(0.2, 0.12, 0.07, WOOD), false)
		mb.box(sp2 + Vector3(0.0, 2.45, -0.4), Vector3(3.4, 0.08, 2.0), _c(0.7, 0.2, 0.12, PAINT) if i == 0 else _c(0.2, 0.4, 0.55, PAINT), false)
		_box_col(out, sp2 + Vector3(0.0, 0.5, 0.0), Vector3(3.0, 1.0, 1.4))
	for k in 4:
		if desert:
			_tree_stump_pile(mb, Vector3(-30.0 + float(k) * 20.0, 0.0, 74.0), rng)
		else:
			_haystack(mb, Vector3(-30.0 + float(k) * 20.0, 0.0, 74.0 + rng.randf_range(-2.0, 2.0)), 1.8)
	out["use"] = Vector3(0.0, 0.0, -4.0)


static func _adobe(mb: MB, out: Dictionary, p: Vector3, w: float, d: float, yaw: float, wall: Color, roof: Color, tall: bool) -> void:
	var s := mb.verts.size()
	var h := 3.3 if not tall else 6.0
	mb.box(Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), wall, false)
	mb.box(Vector3(0.0, h + 0.15, 0.0), Vector3(w + 0.4, 0.3, d + 0.4), roof, false)                       # flat roof with a parapet
	mb.box(Vector3(w * 0.35, h + 0.45, d * 0.2), Vector3(0.5, 0.6, 0.5), roof, false)
	for k in 4:                                                           # roof beams sticking out of the wall
		mb.box(Vector3(-w * 0.5 - 0.3, h - 0.3, -d * 0.35 + float(k) * d * 0.23), Vector3(0.7, 0.16, 0.16), _c(0.2, 0.12, 0.07, WOOD), false)
	mb.box(Vector3(0.0, 1.1, -d * 0.5 - 0.03), Vector3(1.1, 2.2, 0.1), _c(0.14, 0.08, 0.05, WOOD), false)
	mb.box(Vector3(w * 0.3, 1.9, -d * 0.5 - 0.03), Vector3(0.9, 0.9, 0.1), _c(0.08, 0.1, 0.12, GLOW), false)
	mb.box(Vector3(-w * 0.3, 1.9, -d * 0.5 - 0.03), Vector3(0.9, 0.9, 0.1), _c(1.0, 0.78, 0.42, GLOW), false)
	mb.box(Vector3(0.0, h * 0.5, -d * 0.5 - 1.0), Vector3(w * 0.8, 0.14, 2.0) * Vector3(1, 0, 1) + Vector3(0.0, 0.14, 0.0), roof, false)
	mb.xform_from(s, Transform3D(Basis(Vector3.UP, yaw), p))
	_box_col(out, p + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), yaw)


# --- radio tower -----------------------------------------------------------------------------------------------------------------------------

static func _tower(mb: MB, out: Dictionary) -> void:
	var top := 62.0
	var segs := 9
	var red := _c(0.65, 0.07, 0.05, METAL)
	var white := _c(0.8, 0.8, 0.8, METAL)
	var half0 := 3.6
	var half1 := 0.85
	var prev := PackedVector3Array()
	for i in segs + 1:
		var t := float(i) / float(segs)
		var y := top * t
		var hw := lerpf(half0, half1, t)
		var cur := PackedVector3Array([Vector3(-hw, y, -hw), Vector3(hw, y, -hw), Vector3(hw, y, hw), Vector3(-hw, y, hw)])
		var col := red if i % 2 == 1 else white
		if i > 0:
			for k in 4:
				mb.strut(prev[k], cur[k], 0.24 - 0.12 * t, col)                    # legs
				var k2 := (k + 1) % 4
				mb.strut(prev[k], cur[k2], 0.1, col)                                # braces, an X on every face
				mb.strut(prev[k2], cur[k], 0.1, col)
		for k in 4:
			mb.strut(cur[k], cur[(k + 1) % 4], 0.14, col)                          # rings
		prev = cur
	# platform with rail, dishes and the aviation light
	var py := top * 0.78
	var hw2 := lerpf(half0, half1, 0.78)
	mb.box(Vector3(0.0, py, 0.0), Vector3(hw2 * 2.0 + 1.2, 0.2, hw2 * 2.0 + 1.2), _c(0.3, 0.3, 0.33, METAL), false)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var dish := Vector3(cos(a), 0.0, sin(a)) * (hw2 + 0.9)
		mb.sphere(Vector3(dish.x, py + 0.9, dish.z), Vector3(0.9, 0.9, 0.35) if k % 2 == 0 else Vector3(0.35, 0.9, 0.9), 10, 4, _c(0.85, 0.85, 0.83, PAINT))
	mb.cylinder(Vector3(0.0, top, 0.0), 0.12, 9.0, 6, _c(0.65, 0.07, 0.05, METAL))                                          # mast
	mb.sphere(Vector3(0.0, top + 9.3, 0.0), Vector3(0.35, 0.35, 0.35), 8, 4, _c(1.0, 0.12, 0.08, GLOW))
	(out["lamps"] as Array).append({"pos": Vector3(0.0, top + 9.3, 0.0), "color": Color(1.0, 0.15, 0.1), "energy": 1.6, "range": 40.0, "blink": 1.4})
	# equipment hut, generator, solar panels, fence
	mb.box(Vector3(9.0, 1.6, -3.0), Vector3(5.2, 3.2, 3.6), _c(0.5, 0.52, 0.5, SHEET), false)
	mb.box(Vector3(9.0, 3.4, -3.0), Vector3(5.6, 0.25, 4.0), _c(0.3, 0.3, 0.32, SHEET), false)
	mb.box(Vector3(9.0, 1.0, -4.82), Vector3(1.0, 2.0, 0.1), _c(0.12, 0.13, 0.15, METAL), false)
	mb.box(Vector3(11.7, 0.9, -4.8), Vector3(0.8, 0.7, 0.1), _c(0.2, 0.8, 1.0, GLOW), false)
	_box_col(out, Vector3(9.0, 1.7, -3.0), Vector3(5.2, 3.4, 3.6))
	mb.box(Vector3(-9.0, 0.7, -3.0), Vector3(2.2, 1.4, 1.2), _c(0.78, 0.55, 0.1, PAINT), false)
	_box_col(out, Vector3(-9.0, 0.7, -3.0), Vector3(2.2, 1.4, 1.2))
	for k in 3:
		var s := mb.verts.size()
		mb.box(Vector3(0.0, 0.0, 0.0), Vector3(2.4, 0.08, 1.4), _c(0.05, 0.09, 0.2, METAL), false)
		mb.xform_from(s, Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-10.0 + float(k) * 2.6, 1.2, 9.0)))
		mb.box(Vector3(-10.0 + float(k) * 2.6, 0.5, 9.0), Vector3(0.1, 1.0, 0.1), _c(0.4, 0.4, 0.42, METAL), false)
	var fr := 19.0
	for k in 16:
		if k == 11 or k == 12:
			continue
		var a0 := TAU * float(k) / 16.0
		var a1 := TAU * float(k + 1) / 16.0
		var p0 := Vector3(cos(a0) * fr, 0.0, sin(a0) * fr)
		var p1 := Vector3(cos(a1) * fr, 0.0, sin(a1) * fr)
		mb.strut(p0 + Vector3(0.0, 2.2, 0.0), p1 + Vector3(0.0, 2.2, 0.0), 0.06, _c(0.45, 0.46, 0.48, METAL))
		mb.strut(p0 + Vector3(0.0, 1.0, 0.0), p1 + Vector3(0.0, 1.0, 0.0), 0.05, _c(0.45, 0.46, 0.48, METAL))
		mb.cylinder(p0, 0.07, 2.3, 5, _c(0.4, 0.4, 0.42, METAL))
	# base: concrete plinth, feet and the console the hero uses to restore the signal
	mb.box(Vector3(0.0, 0.25, 0.0), Vector3(half0 * 2.0 + 2.0, 0.5, half0 * 2.0 + 2.0), _c(0.5, 0.5, 0.48, ROCK), false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box_col(out, Vector3(float(sx) * half0, 4.0, float(sz) * half0), Vector3(0.6, 8.0, 0.6))
	mb.box(Vector3(0.0, 0.5, -9.0), Vector3(1.4, 1.0, 0.8), _c(0.15, 0.17, 0.2, METAL), false)
	mb.box(Vector3(0.0, 1.06, -9.0), Vector3(1.2, 0.08, 0.6), _c(0.2, 0.9, 1.0, GLOW), false)
	_box_col(out, Vector3(0.0, 0.5, -9.0), Vector3(1.4, 1.0, 0.8))
	out["use"] = Vector3(0.0, 0.0, -10.5)


# --- observatory -----------------------------------------------------------------------------------------------------------------------------

static func _observatory(mb: MB, out: Dictionary) -> void:
	var white := _c(0.72, 0.74, 0.76, PAINT)
	var grey := _c(0.32, 0.34, 0.37, METAL)
	# the main drum with the dome
	mb.cylinder(Vector3(0.0, 0.0, 4.0), 8.0, 9.0, 20, white, -1.0, false, false)
	mb.cylinder(Vector3(0.0, 9.0, 4.0), 8.6, 0.7, 20, grey, -1.0, true, false)                  # ring beam
	mb.sphere(Vector3(0.0, 9.7, 4.0), Vector3(8.0, 7.2, 8.0), 20, 7, _c(0.78, 0.8, 0.82, METAL))
	_box_col(out, Vector3(0.0, 6.0, 4.0), Vector3(14.0, 12.0, 14.0), 0.0)
	# the slit (dark) and the telescope barrel poking out of it
	mb.box(Vector3(0.0, 13.4, -2.6), Vector3(2.4, 7.2, 2.2), _c(0.02, 0.03, 0.05, PAINT), false)
	var s := mb.verts.size()
	mb.cylinder(Vector3.ZERO, 0.75, 6.0, 10, _c(0.85, 0.86, 0.88, METAL), 0.6, true, true)
	mb.xform_from(s, Transform3D(Basis(Vector3.RIGHT, -1.0), Vector3(0.0, 11.5, -1.8)))
	# annex with a flat roof, antennas, solar panels, a platform with rail and steps
	mb.box(Vector3(14.0, 2.0, 8.0), Vector3(9.0, 4.0, 7.0), white, false)
	mb.box(Vector3(14.0, 4.15, 8.0), Vector3(9.6, 0.3, 7.6), grey, false)
	mb.box(Vector3(14.0, 2.0, 4.45), Vector3(5.0, 1.2, 0.1), _c(1.0, 0.85, 0.5, GLOW), false)
	_box_col(out, Vector3(14.0, 2.1, 8.0), Vector3(9.0, 4.2, 7.0))
	mb.cylinder(Vector3(17.0, 4.3, 10.0), 0.1, 7.0, 6, grey)
	mb.sphere(Vector3(11.5, 5.2, 9.0), Vector3(1.4, 1.0, 1.4), 12, 4, white)
	for k in 4:
		var s2 := mb.verts.size()
		mb.box(Vector3.ZERO, Vector3(3.0, 0.1, 1.8), _c(0.05, 0.1, 0.22, METAL), false)
		mb.xform_from(s2, Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(-6.0 + float(k) * 3.4, 1.0, 17.0)))
		mb.box(Vector3(-6.0 + float(k) * 3.4, 0.45, 17.0), Vector3(0.12, 0.9, 0.12), grey, false)
	# the way in: a concrete apron with a low wall and a flagpole
	mb.box(Vector3(0.0, 0.1, -16.0), Vector3(14.0, 0.2, 14.0), _c(0.5, 0.5, 0.48, ROCK), false)
	for sx in [-1.0, 1.0]:
		mb.strut(Vector3(float(sx) * 7.0, 0.6, -23.0), Vector3(float(sx) * 7.0, 0.6, -9.0), 0.08, grey)
		for k in 5:
			mb.cylinder(Vector3(float(sx) * 7.0, 0.0, -23.0 + float(k) * 3.5), 0.05, 1.1, 5, grey)
	mb.cylinder(Vector3(-5.0, 0.0, -20.0), 0.07, 8.0, 6, grey)
	mb.box(Vector3(-4.2, 7.3, -20.0), Vector3(1.6, 1.0, 0.04), _c(0.1, 0.5, 0.8, PAINT), false)
	mb.box(Vector3(0.0, 1.0, -8.2), Vector3(2.0, 2.0, 0.2), _c(0.1, 0.11, 0.13, METAL), false)             # door
	mb.box(Vector3(0.0, 1.0, -8.35), Vector3(1.6, 1.6, 0.05), _c(0.2, 0.9, 1.0, GLOW), false)
	# the sky-scan console beside the door
	mb.box(Vector3(4.0, 0.55, -10.0), Vector3(1.4, 1.1, 0.9), _c(0.15, 0.17, 0.2, METAL), false)
	mb.box(Vector3(4.0, 1.14, -10.0), Vector3(1.2, 0.08, 0.7), _c(0.2, 0.9, 1.0, GLOW), false)
	_box_col(out, Vector3(4.0, 0.55, -10.0), Vector3(1.4, 1.1, 0.9))
	(out["lamps"] as Array).append({"pos": Vector3(0.0, 4.5, -12.0), "color": Color(0.7, 0.9, 1.0), "energy": 1.1, "range": 18.0})
	_lamp_post(mb, out, Vector3(-9.0, 0.0, -14.0))
	out["use"] = Vector3(4.0, 0.0, -12.0)


# --- mine ------------------------------------------------------------------------------------------------------------------------------------

static func _mine(mb: MB, out: Dictionary, rng: RandomNumberGenerator) -> void:
	# the hill the shaft goes into (+Z is into the hill): a heap of rock lumps with the portal cut into the front
	var rock := [_c(0.34, 0.31, 0.28, ROCK), _c(0.28, 0.27, 0.27, ROCK), _c(0.38, 0.34, 0.3, ROCK)]
	for i in 11:
		var r := rng.randf_range(4.0, 6.5)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (2.6 + r * 0.9 + rng.randf_range(0.0, 4.5))                  # beside the portal, never in front of it
		var z := 7.5 + rng.randf_range(0.0, 8.0)
		_lump(mb, Vector3(x, r * 0.35, z), Vector3(r, r * 0.9, r), rock[i % 3], rng)
	_lump(mb, Vector3(0.0, 8.2, 13.0), Vector3(7.0, 4.2, 6.0), rock[0], rng, 10, 4)                                  # the lintel mass over the portal (above the 4.2 m frame)
	_box_col(out, Vector3(-8.5, 4.0, 11.0), Vector3(8.0, 8.0, 12.0))
	_box_col(out, Vector3(8.5, 4.0, 11.0), Vector3(8.0, 8.0, 12.0))
	_box_col(out, Vector3(0.0, 6.5, 11.0), Vector3(9.0, 4.0, 12.0))
	_box_col(out, Vector3(0.0, 2.0, 19.0), Vector3(9.0, 4.0, 1.0))                                              # the end of the shaft
	# timber frame of the portal: two posts, a cap, three sets inside and the dark mouth
	var wood := _c(0.2, 0.12, 0.065, WOOD)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * 2.3, 1.9, 8.0), Vector3(0.5, 3.8, 0.6), wood, false)
		_box_col(out, Vector3(float(sx) * 3.4, 1.9, 12.0), Vector3(2.0, 3.8, 9.0))
	mb.box(Vector3(0.0, 3.95, 8.0), Vector3(5.6, 0.5, 0.7), wood, false)
	for k in 3:
		var z := 11.0 + float(k) * 3.0
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(float(sx) * 2.2, 1.8, z), Vector3(0.4, 3.6, 0.4), wood, false)
		mb.box(Vector3(0.0, 3.7, z), Vector3(4.8, 0.4, 0.5), wood, false)
	mb.box(Vector3(0.0, 1.7, 18.0), Vector3(4.4, 3.4, 0.2), _c(0.01, 0.01, 0.015, PAINT), false)                # rockfall in the dark
	mb.box(Vector3(0.0, 0.04, 13.0), Vector3(4.4, 0.08, 12.0), _c(0.12, 0.1, 0.09, SOIL), false)                  # shaft floor
	# rails out of the mouth, sleepers, an ore cart
	var iron := _c(0.28, 0.27, 0.27, METAL)
	for sx in [-1.0, 1.0]:
		mb.strut(Vector3(float(sx) * 0.75, 0.14, 18.0), Vector3(float(sx) * 0.75, 0.14, -14.0), 0.1, iron)
	for k in 17:
		mb.box(Vector3(0.0, 0.07, 17.0 - float(k) * 2.0), Vector3(2.4, 0.12, 0.3), wood, false)
	var cart := Vector3(0.0, 0.0, -5.0)
	mb.box(cart + Vector3(0.0, 0.85, 0.0), Vector3(1.7, 0.9, 2.2), _c(0.34, 0.17, 0.09, METAL), false)
	mb.box(cart + Vector3(0.0, 1.35, 0.0), Vector3(1.4, 0.25, 1.9), _c(0.1, 0.1, 0.11, ROCK), false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.cylinder(cart + Vector3(float(sx) * 0.75, 0.3, float(sz) * 0.7), 0.3, 0.1, 8, iron)
	_box_col(out, cart + Vector3(0.0, 0.85, 0.0), Vector3(1.7, 1.2, 2.2))
	# headframe: a wooden A-frame with a wheel over the old shaft, an office shed with a sheet roof, barrels, sign
	var hf := Vector3(-15.0, 0.0, -2.0)
	for sz in [-1.0, 1.0]:
		mb.strut(hf + Vector3(-1.5, 0.0, float(sz) * 1.6), hf + Vector3(0.0, 11.0, float(sz) * 0.4), 0.3, wood)
		mb.strut(hf + Vector3(1.5, 0.0, float(sz) * 1.6), hf + Vector3(0.0, 11.0, float(sz) * 0.4), 0.3, wood)
	mb.strut(hf + Vector3(-0.8, 5.0, 0.8), hf + Vector3(0.8, 5.0, -0.8), 0.18, wood)
	mb.cylinder(hf + Vector3(0.0, 10.4, -0.8), 1.3, 0.3, 14, iron, -1.0, true, true)
	_box_col(out, hf + Vector3(0.0, 4.0, 0.0), Vector3(3.6, 8.0, 3.6))
	var shed := Vector3(14.0, 0.0, -4.0)
	mb.box(shed + Vector3(0.0, 1.6, 0.0), Vector3(6.0, 3.2, 4.5), _c(0.3, 0.2, 0.12, WOOD), false)
	mb.prism(PackedVector2Array([Vector2(-3.4, 3.2), Vector2(3.4, 3.2), Vector2(0.0, 4.5)]), -2.6, 2.6, _c(0.34, 0.35, 0.37, SHEET))
	mb.box(shed + Vector3(0.0, 1.0, -2.28), Vector3(1.0, 2.0, 0.1), _c(0.06, 0.04, 0.03, WOOD), false)
	mb.box(shed + Vector3(1.9, 1.7, -2.28), Vector3(0.9, 0.8, 0.1), _c(1.0, 0.78, 0.42, GLOW), false)
	_box_col(out, shed + Vector3(0.0, 2.2, 0.0), Vector3(6.0, 4.4, 4.5))
	for k in 4:
		mb.cylinder(Vector3(9.0 + float(k % 2) * 0.9, 0.0, 4.0 + float(k / 2) * 0.9), 0.4, 1.0, 8, _c(0.4, 0.18, 0.08, METAL))
	_box_col(out, Vector3(9.4, 0.6, 4.4), Vector3(1.8, 1.2, 1.8))
	mb.box(Vector3(5.5, 1.5, -9.0), Vector3(0.14, 3.0, 0.14), wood, false)
	mb.box(Vector3(5.5, 2.7, -9.0), Vector3(2.0, 0.9, 0.1), _c(0.8, 0.65, 0.1, PAINT), false)                       # DANGER sign board
	mb.box(Vector3(5.5, 2.7, -9.06), Vector3(1.6, 0.14, 0.02), _c(0.05, 0.05, 0.05, PAINT), false)
	for k in 10:                                                                                                       # ore heap
		_lump(mb, Vector3(-6.0 + rng.randf_range(-2.0, 2.0), 0.5, -7.0 + rng.randf_range(-1.5, 1.5)), Vector3(1.0, 0.7, 1.0) * rng.randf_range(0.5, 1.2), _c(0.2, 0.19, 0.2, ROCK), rng, 6, 3)
	(out["lamps"] as Array).append({"pos": Vector3(0.0, 3.4, 8.8), "color": Color(1.0, 0.68, 0.3), "energy": 1.2, "range": 12.0})
	out["use"] = Vector3(0.0, 0.0, 16.0)


# --- crash site ------------------------------------------------------------------------------------------------------------------------------

static func _crash(mb: MB, out: Dictionary, rng: RandomNumberGenerator, _site: Dictionary) -> void:
	# the saucer lies tilted in the crater: a flattened hull, a broken dome, ribs, debris and glowing core crystals. Built around the crater floor (about 7 m below the pad).
	var floor_y := -5.6
	var hull := _c(0.16, 0.18, 0.2, ALIEN)
	var plate := _c(0.24, 0.26, 0.3, ALIEN)
	var s := mb.verts.size()
	mb.sphere(Vector3.ZERO, Vector3(19.0, 3.2, 19.0), 22, 6, hull)
	mb.cylinder(Vector3(0.0, -0.5, 0.0), 19.4, 1.0, 22, plate, 19.2, true, false)                               # rim band
	mb.sphere(Vector3(0.0, 2.0, 0.0), Vector3(7.8, 4.6, 7.8), 16, 5, _c(0.1, 0.35, 0.4, GLOW))               # dome (cracked glass glow)
	for k in 8:                                                                                                  # hull ribs
		var a := TAU * float(k) / 8.0
		mb.strut(Vector3(cos(a) * 7.0, 2.4, sin(a) * 7.0), Vector3(cos(a) * 18.0, 0.5, sin(a) * 18.0), 0.4, plate)
	mb.xform_from(s, Transform3D(Basis(Vector3.RIGHT, 0.26) * Basis(Vector3.FORWARD, 0.12), Vector3(3.0, floor_y + 3.6, 4.0)))
	_box_col(out, Vector3(3.0, floor_y + 4.2, 4.0), Vector3(26.0, 5.0, 26.0))
	# torn-off pieces and trailing debris
	for i in 14:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(8.0, 38.0)
		var p := Vector3(cos(a) * r, floor_y + 0.1 + clampf((r - 14.0) * 0.28, 0.0, 6.0), sin(a) * r)
		var sz := Vector3(rng.randf_range(0.8, 3.4), rng.randf_range(0.3, 0.9), rng.randf_range(0.8, 3.0))
		mb.box_yaw(p + Vector3(0.0, sz.y * 0.5, 0.0), sz, rng.randf_range(0.0, TAU), plate if i % 2 == 0 else hull, false)
	# the crystals: tall shards of core energy leaning out of the hull, with glow
	for i in 9:
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)
		var base := Vector3(3.0 + cos(a) * 10.0, floor_y + 2.0, 4.0 + sin(a) * 10.0)
		var h := rng.randf_range(2.5, 6.5)
		var s2 := mb.verts.size()
		mb.cylinder(Vector3.ZERO, 0.55, h, 5, _c(0.25, 0.95, 1.0, GLOW) if i % 3 != 0 else _c(0.95, 0.3, 0.9, GLOW), 0.04, true, false)
		mb.xform_from(s2, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)), base))
	(out["lamps"] as Array).append({"pos": Vector3(3.0, floor_y + 5.0, 4.0), "color": Color(0.3, 0.95, 1.0), "energy": 2.0, "range": 34.0})
	(out["lamps"] as Array).append({"pos": Vector3(-6.0, floor_y + 3.0, 10.0), "color": Color(0.95, 0.35, 0.9), "energy": 1.2, "range": 18.0})
	# scorched ground: a dark ring and streaks on the crater (flat quads a few cm above the bowl: the carve is a function, so they ride at +0.04 over `ground_y` sampled by the node)
	out["use"] = Vector3(-8.0, floor_y + 1.0, 0.0)
	out["crater_floor"] = floor_y


# --- cave mouth ------------------------------------------------------------------------------------------------------------------------------

static func _cave_mouth(mb: MB, out: Dictionary, rng: RandomNumberGenerator) -> void:
	# +Z is into the rock face. A mound of lumps with an arch in the middle (7 m wide, 5 m high), dark mouth, glowing crystals, a lantern.
	var rock := [_c(0.30, 0.29, 0.29, ROCK), _c(0.25, 0.25, 0.26, ROCK), _c(0.34, 0.32, 0.3, ROCK)]
	for i in 12:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * rng.randf_range(4.2, 11.0)
		var z := 6.0 + rng.randf_range(0.0, 8.0)
		var r := rng.randf_range(3.5, 6.5)
		_lump(mb, Vector3(x, r * 0.5, z), Vector3(r, r * 0.95, r), rock[i % 3], rng)
	_lump(mb, Vector3(0.0, 6.4, 8.5), Vector3(6.0, 3.0, 5.0), rock[1], rng, 10, 4)                              # the arch's lintel
	for sx in [-1.0, 1.0]:
		_lump(mb, Vector3(float(sx) * 3.9, 2.4, 6.6), Vector3(1.8, 2.8, 1.8), rock[0], rng, 7, 3)               # jambs
	mb.box(Vector3(0.0, 2.2, 10.0), Vector3(6.0, 4.4, 0.3), _c(0.0, 0.0, 0.01, PAINT), false)                      # the dark
	mb.box(Vector3(0.0, 0.05, 7.0), Vector3(6.4, 0.1, 6.0), _c(0.15, 0.13, 0.12, SOIL), false)
	_box_col(out, Vector3(-8.0, 3.5, 10.0), Vector3(9.0, 7.0, 9.0))
	_box_col(out, Vector3(8.0, 3.5, 10.0), Vector3(9.0, 7.0, 9.0))
	_box_col(out, Vector3(0.0, 6.5, 9.0), Vector3(8.0, 3.0, 8.0))
	_box_col(out, Vector3(0.0, 2.0, 10.6), Vector3(7.0, 4.0, 0.6))
	for i in 6:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var base := Vector3(sx * rng.randf_range(2.4, 5.0), 0.0, 3.0 + rng.randf_range(0.0, 3.0))
		var h := rng.randf_range(0.8, 2.0)
		mb.cylinder(base, 0.28, h, 5, _c(0.3, 0.9, 1.0, GLOW), 0.03, true, false)
	(out["lamps"] as Array).append({"pos": Vector3(0.0, 2.0, 5.5), "color": Color(0.4, 0.9, 1.0), "energy": 1.3, "range": 12.0})
	out["use"] = Vector3(0.0, 0.0, 6.0)
