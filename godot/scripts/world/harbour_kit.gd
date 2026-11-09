class_name HarbourKit
extends RefCounted
## Meshes of the harbour (layout: Harbour.layout()). Four merged meshes, four draw calls whatever the amount of stuff: GROUND (the concrete apron, own shader), KIT (quay walls, piers, containers, sheds,
## cranes, tanks, the office, the ferry terminal, the lighthouse: harbour_kit.gdshader), DETAIL (lamps, bollards, crates: culled beyond 450 m), ROAD (the harbour road ribbon). The ferry is its own
## small mesh (HarbourWorld moves it). Vertex colour is the paint, COLOR.a the material code (see bridge_kit.gd).

const MB := preload("res://scripts/world/mesh_builder.gd")
const GROUND_SHADER := preload("res://assets/shaders/harbour_ground.gdshader")
const Q := Harbour.QUAY_Y
const CONTAINER := 1.0 / 8.0
const CONCRETE := Color(0.6, 0.6, 0.58, 2.0 / 8.0)
const CONCRETE_DARK := Color(0.42, 0.42, 0.41, 2.0 / 8.0)
const STEEL := Color(0.55, 0.57, 0.6, 3.0 / 8.0)
const STEEL_DARK := Color(0.2, 0.22, 0.25, 3.0 / 8.0)
const LAMP := Color(1.0, 0.86, 0.55, 4.0 / 8.0)
const PAINT := 0.0
const CLAD := 6.0 / 8.0

static var _ground_mat: ShaderMaterial


static func ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = GROUND_SHADER
		var b := Harbour.BASIN
		_ground_mat.set_shader_parameter(&"basin", Vector4(b.position.x, b.position.y, b.end.x, b.end.y))
	return _ground_mat


static func _c(col: Color, code: float) -> Color:
	return Color(col.r, col.g, col.b, code)


# --- the ground -------------------------------------------------------------------------------------------------------------------------

## Flat concrete over the three land parts of the apron (north strip, west and east headland): at the quay height plus 3 cm, UV is unused (the shader works in world space).
static func ground() -> ArrayMesh:
	var mb := MB.new()
	var A := Harbour.APRON
	var B := Harbour.BASIN
	var y := Q + 0.03
	for r in [Rect2(A.position.x, A.position.y, A.size.x, B.position.y - A.position.y), Rect2(A.position.x, B.position.y, B.position.x - A.position.x, A.end.y - B.position.y),
			Rect2(B.end.x, B.position.y, A.end.x - B.end.x, A.end.y - B.position.y)]:
		var rr := r as Rect2
		mb.quad(Vector3(rr.position.x, y, rr.position.y), Vector3(rr.end.x, y, rr.position.y), Vector3(rr.end.x, y, rr.end.y), Vector3(rr.position.x, y, rr.end.y), Vector3.UP, Color.WHITE)
	return mb.build(ground_material())


# --- quay walls and piers ---------------------------------------------------------------------------------------------------------------

static func _quay_walls(mb: MB) -> void:
	var A := Harbour.APRON
	var B := Harbour.BASIN
	var bottom := -4.5
	var h := Q - bottom
	var c := CONCRETE_DARK
	# basin walls: west (x = B.x, face towards +x), east, north (face towards +z); the apron's south faces on the open sea
	mb.box(Vector3(B.position.x - 0.5, (Q + bottom) * 0.5, (B.position.y + A.end.y) * 0.5), Vector3(1.0, h, A.end.y - B.position.y), c, false)
	mb.box(Vector3(B.end.x + 0.5, (Q + bottom) * 0.5, (B.position.y + A.end.y) * 0.5), Vector3(1.0, h, A.end.y - B.position.y), c, false)
	mb.box(Vector3((B.position.x + B.end.x) * 0.5, (Q + bottom) * 0.5, B.position.y - 0.5), Vector3(B.size.x + 2.0, h, 1.0), c, false)
	mb.box(Vector3((A.position.x + B.position.x) * 0.5, (Q + bottom) * 0.5, A.end.y + 0.5), Vector3(B.position.x - A.position.x, h, 1.0), c, false)
	mb.box(Vector3((B.end.x + A.end.x) * 0.5, (Q + bottom) * 0.5, A.end.y + 0.5), Vector3(A.end.x - B.end.x, h, 1.0), c, false)
	# coping: a slab along every edge, a little proud of the face, with a fender strip below the waterline
	var cop := CONCRETE
	mb.box(Vector3(B.position.x - 0.3, Q - 0.15, (B.position.y + A.end.y) * 0.5), Vector3(1.4, 0.4, A.end.y - B.position.y + 1.4), cop, false)
	mb.box(Vector3(B.end.x + 0.3, Q - 0.15, (B.position.y + A.end.y) * 0.5), Vector3(1.4, 0.4, A.end.y - B.position.y + 1.4), cop, false)
	mb.box(Vector3((B.position.x + B.end.x) * 0.5, Q - 0.15, B.position.y - 0.3), Vector3(B.size.x + 2.8, 0.4, 1.4), cop, false)
	mb.box(Vector3((A.position.x + B.position.x) * 0.5, Q - 0.15, A.end.y + 0.3), Vector3(B.position.x - A.position.x, 0.4, 1.4), cop, false)
	mb.box(Vector3((B.end.x + A.end.x) * 0.5, Q - 0.15, A.end.y + 0.3), Vector3(A.end.x - B.end.x, 0.4, 1.4), cop, false)
	var fender := _c(Color(0.08, 0.08, 0.09), PAINT)
	for z in range(int(B.position.y) + 6, int(A.end.y), 14):
		mb.box(Vector3(B.position.x + 0.05, -1.2, float(z)), Vector3(0.3, 1.8, 0.9), fender, false)
		mb.box(Vector3(B.end.x - 0.05, -1.2, float(z)), Vector3(0.3, 1.8, 0.9), fender, false)
	for x in range(int(B.position.x) + 8, int(B.end.x), 16):
		mb.box(Vector3(float(x), -1.2, B.position.y + 0.05), Vector3(0.9, 1.8, 0.3), fender, false)


static func _piers(mb: MB) -> void:
	for px in Harbour.PIER_X:
		var z0 := Harbour.PIER_Z0
		var z1 := Harbour.PIER_Z1
		var zm := (z0 + z1) * 0.5
		mb.box(Vector3(px, Q - 0.45, zm), Vector3(Harbour.PIER_W, 0.9, z1 - z0), CONCRETE, true)
		mb.box(Vector3(px, Q - 0.2, z1 + 0.5), Vector3(Harbour.PIER_W + 0.6, 0.5, 1.2), CONCRETE_DARK, true)           # the pier head
		for z in range(int(z0) + 4, int(z1), 8):
			for sx in [-1.0, 1.0]:
				mb.box(Vector3(px + float(sx) * (Harbour.PIER_W * 0.5 - 0.6), -2.8, float(z)), Vector3(0.7, 7.5, 0.7), CONCRETE_DARK, false)      # piles
		for z in range(int(z0) + 8, int(z1), 16):
			mb.box(Vector3(px, -0.9, float(z)), Vector3(Harbour.PIER_W - 0.2, 0.5, 0.6), CONCRETE_DARK, false)                          # cross beams


# --- containers, sheds, cranes, tanks ---------------------------------------------------------------------------------------------------

static func _containers(mb: MB, L: Dictionary) -> void:
	for c: Dictionary in L["containers"]:
		var col: Color = c["col"]
		mb.box(c["pos"], c["size"], Color(col.r, col.g, col.b, CONTAINER), false)
		var p: Vector3 = c["pos"]
		var s: Vector3 = c["size"]
		mb.box(p + Vector3(s.x * 0.5 + 0.02, 0.0, 0.0), Vector3(0.06, s.y * 0.92, s.z * 0.95), Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, CONTAINER), false)      # the doors: darker ends


static func _sheds(mb: MB, L: Dictionary) -> void:
	for s: Dictionary in L["sheds"]:
		var p: Vector3 = s["pos"]
		var sz: Vector3 = s["size"]
		var col: Color = s["col"]
		mb.box(p + Vector3(0.0, sz.y * 0.5, 0.0), sz, _c(col, CLAD), false)
		# gabled roof: two slopes and two gable ends, the ridge along x
		var rc := _c(Color(0.34, 0.36, 0.4), CLAD)
		var x0 := p.x - sz.x * 0.5 - 0.6
		var x1 := p.x + sz.x * 0.5 + 0.6
		var yb := p.y + sz.y
		var zs := p.z + sz.z * 0.5 + 0.5
		var zn := p.z - sz.z * 0.5 - 0.5
		mb.quad(Vector3(x0, yb, zs), Vector3(x1, yb, zs), Vector3(x1, yb + 3.4, p.z), Vector3(x0, yb + 3.4, p.z), Vector3(0.0, 0.9, 0.45).normalized(), rc)
		mb.quad(Vector3(x0, yb, zn), Vector3(x1, yb, zn), Vector3(x1, yb + 3.4, p.z), Vector3(x0, yb + 3.4, p.z), Vector3(0.0, 0.9, -0.45).normalized(), rc)
		mb.quad(Vector3(x0, yb, zs), Vector3(x0, yb, zn), Vector3(x0, yb + 3.4, p.z), Vector3(x0, yb + 3.4, p.z), Vector3.LEFT, _c(col, CLAD))
		mb.quad(Vector3(x1, yb, zs), Vector3(x1, yb, zn), Vector3(x1, yb + 3.4, p.z), Vector3(x1, yb + 3.4, p.z), Vector3.RIGHT, _c(col, CLAD))
		# big roller doors and a window strip on the south face
		var face_z := p.z + sz.z * 0.5 + 0.04
		var dn := maxi(2, int(sz.x / 24.0))
		for d in dn:
			var dx := p.x - sz.x * 0.5 + (float(d) + 0.5) * sz.x / float(dn)
			mb.box(Vector3(dx, p.y + 3.2, face_z), Vector3(7.0, 6.4, 0.1), _c(Color(0.28, 0.3, 0.34), PAINT), false)
			mb.box(Vector3(dx, p.y + sz.y - 2.0, face_z), Vector3(sz.x / float(dn) - 3.0, 1.0, 0.1), _c(Color(0.7, 0.85, 1.0), 4.0 / 8.0), false)


static func _office(mb: MB, L: Dictionary) -> void:
	var o: Dictionary = L["office"]
	var p: Vector3 = o["pos"]
	var s: Vector3 = o["size"]
	mb.box(p + Vector3(0.0, s.y * 0.5, 0.0), s, _c(Color(0.78, 0.8, 0.82), 2.0 / 8.0), false)
	mb.box(p + Vector3(0.0, s.y + 0.4, 0.0), Vector3(s.x + 1.0, 0.8, s.z + 1.0), CONCRETE_DARK, true)
	var fz := p.z + s.z * 0.5 + 0.05
	for fl in 3:
		var yy := p.y + 3.0 + float(fl) * 4.2
		mb.box(Vector3(p.x, yy, fz), Vector3(s.x - 3.0, 2.2, 0.1), _c(Color(0.18, 0.34, 0.5), PAINT), false)
		for k in 6:
			mb.box(Vector3(p.x - s.x * 0.5 + 3.0 + float(k) * (s.x - 6.0) / 5.0, yy, fz + 0.03), Vector3(2.4, 1.6, 0.08), _c(Color(1.0, 0.9, 0.62), 4.0 / 8.0), false)
	mb.box(p + Vector3(0.0, s.y + 3.0, 0.0), Vector3(2.0, 4.0, 2.0), STEEL, false)                       # a radio mast on the roof
	mb.strut(p + Vector3(0.0, s.y + 5.0, 0.0), p + Vector3(0.0, s.y + 14.0, 0.0), 0.25, STEEL, true)


static func _terminal(mb: MB, L: Dictionary) -> void:
	var t: Dictionary = L["terminal"]
	var p: Vector3 = t["pos"]
	var s: Vector3 = t["size"]
	mb.box(p + Vector3(0.0, s.y * 0.5, 0.0), s, _c(Color(0.86, 0.87, 0.88), 2.0 / 8.0), false)
	mb.box(p + Vector3(-s.x * 0.5 - 3.0, s.y + 0.4, 0.0), Vector3(s.x + 8.0, 0.7, s.z + 4.0), _c(Color(0.14, 0.36, 0.58), 3.0 / 8.0), true)     # the canopy over the berth
	for k in 5:
		var z := p.z - s.z * 0.5 + 3.0 + float(k) * (s.z - 6.0) / 4.0
		mb.box(Vector3(p.x - s.x * 0.5 - 0.1, p.y + 3.0, z), Vector3(0.1, 3.2, 5.0), _c(Color(0.7, 0.88, 1.0), 4.0 / 8.0), false)
		mb.box(Vector3(p.x - s.x * 0.5 - 6.8, p.y + 4.5, z), Vector3(0.5, 9.0, 0.5), STEEL, false)         # canopy posts
	mb.box(p + Vector3(-s.x * 0.5 - 7.5, 3.2, 0.0), Vector3(1.0, 6.4, s.z - 4.0), _c(Color(0.5, 0.52, 0.55), 3.0 / 8.0), false)


static func _cranes(mb: MB, L: Dictionary) -> void:
	var colors: Array[Color] = [Color(0.88, 0.42, 0.1), Color(0.88, 0.42, 0.1), Color(0.14, 0.4, 0.66)]
	var ci := 0
	for cr: Dictionary in L["cranes"]:
		var cp: Vector3 = cr["pos"]
		var d: float = cr["dir"]
		var col := _c(colors[ci % colors.size()], 3.0 / 8.0)
		ci += 1
		var top := Q + 30.0
		var xs := cp.x
		var xl := cp.x - d * 15.0
		for sz in [-8.0, 8.0]:
			for x in [xs, xl]:
				mb.box(Vector3(x, Q + 15.0, cp.z + float(sz)), Vector3(1.6, 30.0, 1.6), col, false)
			mb.strut(Vector3(xs, Q + 1.0, cp.z + float(sz)), Vector3(xl, Q + 27.0, cp.z + float(sz)), 0.45, STEEL)             # X braces between the leg pairs
			mb.strut(Vector3(xl, Q + 1.0, cp.z + float(sz)), Vector3(xs, Q + 27.0, cp.z + float(sz)), 0.45, STEEL)
			mb.box(Vector3((xs + xl) * 0.5, Q + 27.0, cp.z + float(sz)), Vector3(absf(xs - xl) + 1.6, 1.4, 1.6), col, false)
		for x in [xs, xl]:
			mb.box(Vector3(x, Q + 27.0, cp.z), Vector3(1.6, 1.4, 16.0), col, false)                                             # portal beams
			mb.box(Vector3(x, Q + 8.0, cp.z), Vector3(1.4, 1.2, 16.0), STEEL, false)
		# the boom (two girders) over the water, the back reach over the land
		var tip := xs + d * 38.0
		var back := xl - d * 8.0
		for sz in [-8.0, 8.0]:
			mb.box(Vector3((tip + back) * 0.5, top, cp.z + float(sz)), Vector3(absf(tip - back), 2.6, 1.4), col, false)
			mb.strut(Vector3(xs, top + 1.3, cp.z + float(sz)), Vector3(tip, top + 1.3, cp.z + float(sz)), 0.25, STEEL)
			for k in 8:
				var bx := lerpf(xs, tip, float(k) / 8.0)
				mb.strut(Vector3(bx, top - 1.2, cp.z + float(sz)), Vector3(bx + d * 2.4, top + 1.3, cp.z + float(sz)), 0.18, STEEL)
		for k in 5:
			mb.box(Vector3(lerpf(back, tip, float(k) / 4.0), top, cp.z), Vector3(1.0, 1.0, 16.0), STEEL_DARK, false)
		mb.box(Vector3(xl - d * 3.0, top + 2.6, cp.z), Vector3(6.0, 4.0, 8.0), _c(Color(0.82, 0.82, 0.8), 3.0 / 8.0), false)       # machinery house
		mb.box(Vector3(xs + d * 1.5, top - 2.8, cp.z + 9.4), Vector3(2.4, 2.2, 2.2), _c(Color(0.9, 0.9, 0.92), 3.0 / 8.0), false)  # the driver's cab
		mb.box(Vector3(xs + d * 1.5, top - 2.8, cp.z + 10.5), Vector3(1.9, 1.4, 0.1), LAMP, false)
		# the trolley, cables and a hanging container over the water
		var tx := xs + d * 22.0
		mb.box(Vector3(tx, top - 1.8, cp.z), Vector3(3.0, 1.4, 6.0), STEEL_DARK, false)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				mb.strut(Vector3(tx + float(sx) * 1.2, top - 2.2, cp.z + float(sz) * 2.4), Vector3(tx + float(sx) * 1.4, Q + 11.0, cp.z + float(sz) * 4.0), 0.07, STEEL)
		mb.box(Vector3(tx, Q + 10.6, cp.z), Vector3(12.4, 0.7, 2.7), STEEL_DARK, false)
		mb.box(Vector3(tx, Q + 9.1, cp.z), Vector3(12.2, 2.6, 2.5), Color(0.72, 0.18, 0.14, CONTAINER) if ci % 2 == 0 else Color(0.16, 0.34, 0.62, CONTAINER), false)
		mb.box(Vector3(cp.x - d * 0.0, Q + 0.4, cp.z + 8.0), Vector3(18.0, 0.8, 1.2), STEEL_DARK, false)                         # rail on the ground, both legs


static func _tanks(mb: MB, L: Dictionary) -> void:
	var cols: Array[Color] = [Color(0.88, 0.88, 0.86), Color(0.86, 0.9, 0.92), Color(0.9, 0.86, 0.8)]
	var i := 0
	for t: Dictionary in L["tanks"]:
		var p: Vector3 = t["pos"]
		var r: float = t["r"]
		var h: float = t["h"]
		var col := _c(cols[i % cols.size()], 3.0 / 8.0)
		i += 1
		mb.cylinder(p, r, h, 20, col, -1.0, true, false)
		mb.cylinder(p + Vector3(0.0, h, 0.0), r * 0.98, r * 0.35, 20, col, r * 0.2, true, false)                                   # a domed top
		mb.cylinder(p + Vector3(0.0, h * 0.55, 0.0), r * 1.02, 0.5, 20, STEEL_DARK, -1.0, false, false)                              # a girth ring
		mb.strut(p + Vector3(r * 0.98, 0.2, 0.0), p + Vector3(r * 0.98, h + 0.2, 0.0), 0.4, STEEL_DARK, true)                    # a ladder
		mb.box(p + Vector3(0.0, 0.2, 0.0), Vector3(r * 2.6, 0.4, r * 2.6), CONCRETE_DARK, true)                                   # the bund floor
	# pipes between tanks, on low racks
	for k in 5:
		var a: Dictionary = L["tanks"][k]
		var b: Dictionary = L["tanks"][k + 1]
		var pa: Vector3 = a["pos"]
		var pb: Vector3 = b["pos"]
		mb.strut(Vector3(pa.x, Q + 3.0, pa.z + float(a["r"])), Vector3(pb.x, Q + 3.0, pb.z + float(b["r"])), 0.5, _c(Color(0.7, 0.2, 0.15), 3.0 / 8.0))


static func _lighthouse(mb: MB, L: Dictionary) -> void:
	var p: Vector3 = L["lighthouse"]
	var white := _c(Color(0.92, 0.92, 0.9), 2.0 / 8.0)
	var red := _c(Color(0.78, 0.14, 0.1), 2.0 / 8.0)
	mb.cylinder(p, 4.6, 6.0, 16, white, 3.8, true, false)
	mb.cylinder(p + Vector3(0, 6.0, 0), 3.8, 7.0, 16, red, 3.3, true, false)
	mb.cylinder(p + Vector3(0, 13.0, 0), 3.3, 7.0, 16, white, 2.9, true, false)
	mb.cylinder(p + Vector3(0, 20.0, 0), 2.9, 6.0, 16, red, 2.6, true, false)
	mb.cylinder(p + Vector3(0, 26.0, 0), 4.0, 0.6, 16, STEEL_DARK, -1.0, true, false)                                              # the gallery
	mb.cylinder(p + Vector3(0, 26.6, 0), 1.9, 3.0, 12, LAMP, -1.0, true, false)                                                      # the lantern
	mb.cylinder(p + Vector3(0, 29.6, 0), 2.4, 1.8, 12, STEEL_DARK, 0.2, true, false)                                                 # the cap
	for k in 12:
		var a := TAU * float(k) / 12.0
		mb.box(p + Vector3(cos(a) * 3.9, 27.3, sin(a) * 3.9), Vector3(0.1, 1.0, 0.1), STEEL, false)
	mb.box(p + Vector3(0.0, 1.4, 4.7), Vector3(1.4, 2.8, 0.3), STEEL_DARK, false)                                                   # the door


# --- small things ----------------------------------------------------------------------------------------------------------------------

static func _detail(mb: MB, L: Dictionary) -> void:
	for p: Vector3 in L["lamps"]:
		mb.box(p + Vector3(0.0, 4.5, 0.0), Vector3(0.18, 9.0, 0.18), STEEL_DARK, false)
		mb.box(p + Vector3(0.0, 9.1, 0.0), Vector3(0.9, 0.25, 0.6), LAMP, false)
	for p: Vector3 in L["bollards"]:
		mb.cylinder(p, 0.32, 0.55, 8, STEEL_DARK, 0.24, true, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 36:                                                                                                                        # crates, barrels and pallets at the sheds and the yard
		var x := rng.randf_range(-320.0, 380.0)
		var z := rng.randf_range(1404.0, 1412.0) if k % 2 == 0 else rng.randf_range(1392.0, 1400.0)
		var wood := Color(0.5 + rng.randf() * 0.1, 0.38, 0.22, 0.0)
		mb.box(Vector3(x, Q + 0.6, z), Vector3(1.2, 1.2, 1.2), wood, false)
		mb.cylinder(Vector3(x + 1.8, Q, z + 0.4), 0.4, 0.9, 8, Color(0.2, 0.36, 0.62, 3.0 / 8.0), -1.0, true, false)


## The harbour road: from the north apron edge down x = ROAD_X, around a curve, to the start of the bridge: a ribbon on the apron with the highway shader (BridgeKit.road_material).
static func road_points() -> PackedVector3Array:
	var S := Bridges.SUSPENSION
	var x0: float = Harbour.ROAD_X
	var z1: float = S["z"]
	var pts := PackedVector3Array()
	var y := Q
	for z in range(1340, 1576, 12):
		pts.append(Vector3(x0, y, float(z)))
	var r := 28.0                                                      # a quarter circle from heading south to heading east
	for k in range(0, 9):
		var a := PI * 0.5 * float(k) / 8.0
		pts.append(Vector3(x0 + r - r * cos(a), y, 1576.0 + r * sin(a)))
	var x := x0 + r
	while x < float(S["x0"]):
		pts.append(Vector3(x, y, z1))
		x += 12.0
	pts.append(Vector3(float(S["x0"]), y, z1))
	return pts


static func road_mesh() -> ArrayMesh:
	var b := {"pts": road_points(), "road_w": 12.0}
	return BridgeKit.road_ribbon(b)


static func kit() -> ArrayMesh:
	var mb := MB.new()
	var L := Harbour.layout()
	_quay_walls(mb)
	_piers(mb)
	_containers(mb, L)
	_sheds(mb, L)
	_office(mb, L)
	_terminal(mb, L)
	_cranes(mb, L)
	_tanks(mb, L)
	_lighthouse(mb, L)
	return mb.build(BridgeKit.kit_material())


static func detail() -> ArrayMesh:
	var mb := MB.new()
	_detail(mb, Harbour.layout())
	return mb.build(BridgeKit.kit_material())


# --- the ferry --------------------------------------------------------------------------------------------------------------------------

## A small passenger ferry, 38 m long, nose towards -Z, waterline at y = 0 (its hull goes 1.5 m below): white superstructure, a blue hull, two decks of windows, a funnel and a radar mast.
static func ferry() -> ArrayMesh:
	var mb := MB.new()
	var hull := _c(Color(0.14, 0.3, 0.5), PAINT)
	var white := _c(Color(0.92, 0.93, 0.94), PAINT)
	var L := 38.0
	var W := 9.0
	# hull: a prism of (x, y) extruded along z, then the bow tapered by two wedges
	var hp := PackedVector2Array([Vector2(-W * 0.5, 2.2), Vector2(-W * 0.5 + 0.4, -1.5), Vector2(W * 0.5 - 0.4, -1.5), Vector2(W * 0.5, 2.2)])
	mb.prism(hp, -L * 0.5 + 6.0, L * 0.5, hull)
	var zb := -L * 0.5 + 6.0
	var zt := -L * 0.5
	mb.quad(Vector3(-W * 0.5, 2.2, zb), Vector3(-W * 0.5 + 0.4, -1.5, zb), Vector3(0.0, -1.2, zt), Vector3(0.0, 2.8, zt), Vector3(-0.85, 0.0, -0.5).normalized(), hull)
	mb.quad(Vector3(W * 0.5, 2.2, zb), Vector3(W * 0.5 - 0.4, -1.5, zb), Vector3(0.0, -1.2, zt), Vector3(0.0, 2.8, zt), Vector3(0.85, 0.0, -0.5).normalized(), hull)
	mb.quad(Vector3(-W * 0.5, 2.2, zb), Vector3(W * 0.5, 2.2, zb), Vector3(0.0, 2.8, zt), Vector3(0.0, 2.8, zt), Vector3.UP, white)
	mb.quad(Vector3(-W * 0.5 + 0.4, -1.5, zb), Vector3(W * 0.5 - 0.4, -1.5, zb), Vector3(0.0, -1.2, zt), Vector3(0.0, -1.2, zt), Vector3.DOWN, hull)
	mb.box(Vector3(0.0, 2.4, 0.0), Vector3(W + 0.3, 0.5, L - 5.0), white, true)                                                    # the main deck
	mb.box(Vector3(0.0, 4.4, 2.0), Vector3(W - 1.4, 3.6, L - 14.0), white, true)                                                   # superstructure
	mb.box(Vector3(0.0, 7.6, 3.0), Vector3(W - 3.0, 3.0, L - 22.0), white, true)                                                   # upper deck
	mb.box(Vector3(0.0, 8.5, -L * 0.5 + 12.0), Vector3(W - 3.6, 3.2, 5.0), white, true)                                            # the bridge
	for side in [-1.0, 1.0]:
		mb.box(Vector3(float(side) * (W * 0.5 - 0.65), 4.4, 2.0), Vector3(0.1, 1.3, L - 16.0), _c(Color(0.18, 0.3, 0.45), PAINT), false)
		mb.box(Vector3(float(side) * (W * 0.5 - 0.64), 4.4, 2.0), Vector3(0.1, 1.0, L - 18.0), _c(Color(1.0, 0.92, 0.7), 4.0 / 8.0), false)
		mb.box(Vector3(float(side) * (W * 0.5 - 1.55), 7.6, 3.0), Vector3(0.1, 1.2, L - 24.0), _c(Color(0.18, 0.3, 0.45), PAINT), false)
	mb.box(Vector3(0.0, 8.5, -L * 0.5 + 9.45), Vector3(W - 4.0, 1.4, 0.1), _c(Color(0.18, 0.3, 0.45), PAINT), false)
	mb.cylinder(Vector3(0.0, 9.1, 8.0), 1.5, 4.2, 12, _c(Color(0.82, 0.18, 0.12), PAINT), 1.3, true, false)                          # the funnel
	mb.box(Vector3(0.0, 10.4, -L * 0.5 + 12.0), Vector3(0.15, 3.0, 0.15), STEEL, false)
	mb.box(Vector3(0.0, 12.0, -L * 0.5 + 12.0), Vector3(2.4, 0.2, 0.4), STEEL, false)
	for k in 4:
		mb.box(Vector3(0.0, 2.9, -L * 0.5 + 4.0 + float(k) * 3.0), Vector3(W - 1.0, 0.7, 0.1), _c(Color(0.8, 0.8, 0.78), PAINT), false)         # rails at the bow
	return mb.build(BridgeKit.kit_material())
