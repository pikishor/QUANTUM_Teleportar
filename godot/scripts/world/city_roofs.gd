extends RefCounted
## Rooftop clutter and facade add-ons: AC units, water tanks, antenna masts with aviation beacons, stair houses, LED billboards on
## the roofs; awnings, fire escapes and neon blade signs on the facades. Placed from the building data of the city (each building's
## class, footprint and facade grid) with the props builder's RNG; every family is one MultiMesh through props.add_family().

const MB := preload("res://scripts/world/mesh_builder.gd")
const BM := preload("res://scripts/world/building_meshes.gd")

const EM_BEACON := 0.30
const EM_SCREEN := 0.60
const EM_BLADE := 0.70
const EM_GLOW := 1.0
const NEON_COLORS: Array[Color] = [Color(0.2, 0.85, 1.0), Color(1.0, 0.16, 0.62), Color(0.58, 0.36, 1.0), Color(0.2, 1.0, 0.66)]


# --- meshes ----------------------------------------------------------------------------------------------------------------

static func _mb(metal: float, rough: float) -> MB:
	var b := MB.new()
	b.uv2 = Vector2(metal, rough)
	return b


static func _uvq() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])


static func awning_mesh() -> ArrayMesh:
	var b := _mb(0.0, 0.85)
	var fab := Color(0.16, 0.035, 0.03, 0.0)
	var hw := 1.9
	b.quad(Vector3(-hw, 3.9, 0.0), Vector3(hw, 3.9, 0.0), Vector3(hw, 3.35, 1.4), Vector3(-hw, 3.35, 1.4), Vector3(0, 0.93, 0.37), fab)
	b.quad(Vector3(-hw, 3.35, 1.4), Vector3(hw, 3.35, 1.4), Vector3(hw, 3.05, 1.4), Vector3(-hw, 3.05, 1.4), Vector3.BACK, fab * 0.8)
	b.quad(Vector3(-hw, 3.9, 0.0), Vector3(hw, 3.35, 1.4), Vector3(hw, 3.05, 1.4), Vector3(-hw, 3.05, 1.4), Vector3(0, -0.93, -0.37), Color(0.02, 0.02, 0.02, 0.0))
	return b.build(null, true, true)


## Two floors of fire escape (platforms at 0, -3.5, -7.0 relative to the top platform; two opposing stair flights).
static func fire_escape_mesh() -> ArrayMesh:
	var b := _mb(0.85, 0.55)
	var iron := Color(0.04, 0.042, 0.045, 0.0)
	for level in 2:
		var y := -3.5 * level
		b.box(Vector3(0, y, 0.55), Vector3(2.6, 0.07, 1.1), iron, false)
		b.box(Vector3(0, y + 0.95, 1.08), Vector3(2.6, 0.04, 0.04), iron, false)
		for x in [-1.3, 0.0, 1.3]:
			b.box(Vector3(x, y + 0.5, 1.08), Vector3(0.04, 1.0, 0.04), iron, false)
		for sx in [-1.3, 1.3]:
			b.box(Vector3(sx, y + 0.95, 0.55), Vector3(0.04, 0.04, 1.1), iron, false)
	var flights := [[Vector3(0.95, 0.0, 0.0), Vector3(-0.95, -3.5, 0.0)], [Vector3(-0.95, -3.5, 0.0), Vector3(0.95, -7.0, 0.0)]]
	for f in flights:
		for z in [0.18, 0.92]:
			b.strut(f[0] + Vector3(0, 0, z), f[1] + Vector3(0, 0, z), 0.07, iron)
		for t in 5:
			var k := (float(t) + 0.5) / 5.0
			var p: Vector3 = f[0].lerp(f[1], k)
			b.box(p + Vector3(0, 0, 0.55), Vector3(0.24, 0.03, 0.8), iron, false)
	return b.build(null, true, true)


## Vertical neon blade sign sticking out of a wall (+Z outward), double sided.
static func blade_mesh() -> ArrayMesh:
	var b := _mb(0.2, 0.5)
	b.box(Vector3(0, 1.6, 0.75), Vector3(0.07, 3.25, 1.15), Color(0.03, 0.03, 0.035, 0.0), false)
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(0.045, 0.0, 1.25), Vector3(0.045, 0.0, 0.25), Vector3(0.045, 3.2, 0.25), Vector3(0.045, 3.2, 1.25), Vector3.RIGHT,
			Color(1, 1, 1, EM_BLADE), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	b.quad(Vector3(-0.045, 0.0, 0.25), Vector3(-0.045, 0.0, 1.25), Vector3(-0.045, 3.2, 1.25), Vector3(-0.045, 3.2, 0.25), Vector3.LEFT,
			Color(1, 1, 1, EM_BLADE), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	return b.build(null, true, true)


static func ac_mesh() -> ArrayMesh:
	var b := _mb(0.5, 0.6)
	b.box(Vector3(0, 0.5, 0), Vector3(2.0, 0.95, 1.1), Color(0.16, 0.165, 0.17, 0.0), false)
	b.box(Vector3(0, 1.0, 0), Vector3(2.06, 0.06, 1.16), Color(0.10, 0.10, 0.105, 0.0), false)
	var dark := Color(0.03, 0.03, 0.035, 0.0)
	for x in [-0.5, 0.5]:
		b.quad(Vector3(x - 0.38, 1.035, -0.38), Vector3(x + 0.38, 1.035, -0.38), Vector3(x + 0.38, 1.035, 0.38), Vector3(x - 0.38, 1.035, 0.38), Vector3.UP, dark)
	b.quad(Vector3(1.012, 0.1, -0.5), Vector3(1.012, 0.1, 0.5), Vector3(1.012, 0.85, 0.5), Vector3(1.012, 0.85, -0.5), Vector3.RIGHT, dark)
	return b.build(null, true, true)


static func tank_mesh() -> ArrayMesh:
	var b := _mb(0.2, 0.75)
	var wood := Color(0.11, 0.075, 0.05, 0.0)
	b.cylinder(Vector3(0, 1.8, 0), 1.5, 2.7, 8, wood, -1.0, false, true)
	b.cylinder(Vector3(0, 4.5, 0), 1.6, 0.9, 8, Color(0.06, 0.055, 0.05, 0.0), 0.12, false)
	for h in [2.5, 3.8]:
		b.cylinder(Vector3(0, h, 0), 1.53, 0.07, 8, Color(0.05, 0.05, 0.055, 0.0), -1.0, false)
	var iron := Color(0.05, 0.05, 0.055, 0.0)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var p := Vector3(cos(a), 0, sin(a)) * 1.25
		b.strut(p, p + Vector3(0, 1.85, 0), 0.12, iron, false)
	return b.build(null, true, true)


static func mast_mesh() -> ArrayMesh:
	var b := _mb(0.7, 0.5)
	var iron := Color(0.07, 0.07, 0.075, 0.0)
	b.cylinder(Vector3(0, 0, 0), 0.16, 13.4, 6, iron, 0.045, false)                    # one tapered mast
	for h in [5.0, 8.0, 11.0]:
		b.strut(Vector3(-1.1 + (h - 5.0) * 0.12, h, 0), Vector3(1.1 - (h - 5.0) * 0.12, h, 0), 0.05, iron, false)
	var start := b.verts.size()
	b.cylinder(Vector3(0, 0, 0), 0.7, 0.12, 6, Color(0.18, 0.18, 0.19, 0.0), 0.1)
	b.xform_from(start, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-65.0)), Vector3(0.9, 7.2, 0.3)))
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 13.5, 0), Vector3(0.16, 0.2, 0.16), Color(1, 1, 1, EM_BEACON), false)
	b.box(Vector3(1.0, 5.15, 0), Vector3(0.1, 0.1, 0.1), Color(1, 1, 1, EM_BEACON), false)
	return b.build(null, true, true)


static func stair_house_mesh() -> ArrayMesh:
	var b := _mb(0.0, 0.85)
	b.box(Vector3(0, 1.45, 0), Vector3(3.4, 2.9, 3.0), Color(0.19, 0.19, 0.2, 0.0))
	b.box(Vector3(0, 2.95, 0), Vector3(3.6, 0.14, 3.2), Color(0.09, 0.09, 0.095, 0.0))
	b.box(Vector3(0, 1.0, 1.52), Vector3(1.0, 2.0, 0.06), Color(0.05, 0.055, 0.06, 0.0))
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 2.25, 1.55), Vector3(0.5, 0.14, 0.05), Color(1.0, 0.62, 0.25, EM_GLOW))
	return b.build(null, true, true)


## Roof billboard: a legged frame carrying an LED panel (+Z), neon rim, two floodlights.
static func billboard_mesh() -> ArrayMesh:
	var b := _mb(0.7, 0.5)
	var iron := Color(0.06, 0.06, 0.065, 0.0)
	for x in [-3.8, 0.0, 3.8]:
		b.strut(Vector3(x, 0.0, -0.8), Vector3(x, 3.2, -0.15), 0.18, iron, false)
		b.strut(Vector3(x, 0.0, 0.7), Vector3(x, 3.2, -0.15), 0.12, iron, false)
	b.box(Vector3(0, 5.8, -0.2), Vector3(10.6, 5.0, 0.3), Color(0.03, 0.03, 0.035, 0.0), false, b.uv2, MB.F_PZ)     # the LED panel covers the front
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-5.0, 3.4, -0.02), Vector3(5.0, 3.4, -0.02), Vector3(5.0, 8.2, -0.02), Vector3(-5.0, 8.2, -0.02), Vector3.BACK,
			Color(1, 1, 1, EM_SCREEN), Vector2.ZERO, Vector2.ZERO, _uvq())
	var rim := Color(0.2, 0.9, 1.0, EM_GLOW)
	b.box(Vector3(0, 8.28, 0.0), Vector3(10.4, 0.12, 0.14), rim, false, b.uv2, MB.F_NZ)
	b.box(Vector3(0, 3.32, 0.0), Vector3(10.4, 0.12, 0.14), rim, false, b.uv2, MB.F_NZ)
	b.box(Vector3(-5.08, 5.8, 0.0), Vector3(0.12, 5.0, 0.14), rim, false, b.uv2, MB.F_NZ)
	b.box(Vector3(5.08, 5.8, 0.0), Vector3(0.12, 5.0, 0.14), rim, false, b.uv2, MB.F_NZ)
	b.uv2 = Vector2(0.5, 0.5)
	for x in [-3.0, 3.0]:
		b.strut(Vector3(x, 8.4, -0.1), Vector3(x, 8.9, 0.9), 0.06, iron, false)
		b.box(Vector3(x, 8.95, 1.0), Vector3(0.5, 0.2, 0.3), Color(0.05, 0.05, 0.055, 0.0))
	return b.build(null, true, true)


## Low parapet / cover wall segment (3 m): concrete with a coping, a place to take cover.
static func cover_wall_mesh() -> ArrayMesh:
	var b := _mb(0.0, 0.85)
	b.box(Vector3(0, 0.55, 0), Vector3(3.0, 1.1, 0.3), Color(0.15, 0.15, 0.16, 0.0))
	b.box(Vector3(0, 1.13, 0), Vector3(3.1, 0.1, 0.42), Color(0.22, 0.22, 0.23, 0.0))
	b.box(Vector3(0, 0.3, 0.16), Vector3(2.9, 0.04, 0.02), Color(0.06, 0.06, 0.065, 0.0), false)
	return b.build(null, true, true)


## A pipe run on stands with an elbow rising into a vent stack.
static func pipes_mesh() -> ArrayMesh:
	var b := _mb(0.6, 0.55)
	var pipe := Color(0.14, 0.14, 0.15, 0.0)
	var lag := Color(0.30, 0.29, 0.27, 0.0)
	b.strut(Vector3(-2.0, 0.62, -0.2), Vector3(1.6, 0.62, -0.2), 0.16, pipe, true)
	b.strut(Vector3(-2.0, 0.62, 0.22), Vector3(1.6, 0.62, 0.22), 0.12, lag, true)
	b.cylinder(Vector3(1.6, 0.62, -0.2), 0.09, 1.3, 6, pipe, 0.08, true)
	b.sphere(Vector3(1.6, 2.0, -0.2), Vector3(0.2, 0.1, 0.2), 6, 2, Color(0.08, 0.08, 0.09, 0.0))
	for x in [-1.6, 0.0, 1.2]:
		b.box(Vector3(x, 0.3, 0.0), Vector3(0.12, 0.6, 0.7), Color(0.07, 0.07, 0.075, 0.0), false)
	return b.build(null, true, true)


## Skylight: a kerb with a pitched glass roof that leaks a faint cold light from the rooms below.
static func skylight_mesh() -> ArrayMesh:
	var b := _mb(0.0, 0.7)
	b.box(Vector3(0, 0.2, 0), Vector3(2.4, 0.4, 1.7), Color(0.12, 0.12, 0.13, 0.0))
	b.uv2 = Vector2(0.3, 0.1)
	var profile := PackedVector2Array([Vector2(-1.05, 0.4), Vector2(1.05, 0.4), Vector2(0.3, 0.95), Vector2(-0.3, 0.95)])
	b.prism(profile, -0.75, 0.75, Color(0.025, 0.09, 0.10, EM_GLOW))
	b.uv2 = Vector2(0.0, 0.7)
	for x in [-0.55, 0.0, 0.55]:
		b.box(Vector3(x, 0.7, 0.0), Vector3(0.05, 0.6, 1.55), Color(0.03, 0.03, 0.035, 0.0), false)
	return b.build(null, true, true)


## Rooftop HVAC unit: louvred housing, a fan grille on top and a duct stub.
static func hvac_mesh() -> ArrayMesh:
	var b := _mb(0.5, 0.6)
	b.box(Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 2.4), Color(0.18, 0.185, 0.19, 0.0))
	b.box(Vector3(0, 1.22, 0), Vector3(2.5, 0.06, 2.5), Color(0.10, 0.10, 0.105, 0.0))
	b.cylinder(Vector3(0.3, 1.25, 0.2), 0.8, 0.12, 10, Color(0.03, 0.03, 0.035, 0.0), 0.8)
	var dark := Color(0.03, 0.03, 0.035, 0.0)
	for k in 5:
		b.quad(Vector3(1.21, 0.15 + k * 0.2, -1.0), Vector3(1.21, 0.15 + k * 0.2, 1.0), Vector3(1.21, 0.27 + k * 0.2, 1.0), Vector3(1.21, 0.27 + k * 0.2, -1.0), Vector3.RIGHT, dark)
	b.strut(Vector3(-1.2, 0.6, 0.0), Vector3(-2.2, 0.6, 0.0), 0.5, Color(0.12, 0.12, 0.125, 0.0), true)
	return b.build(null, true, true)


# --- placement -------------------------------------------------------------------------------------------------------------

## Facade bay centre (metres along the wall from its left edge viewed from outside) -> world offset from the lot centre.
## face: 0 +X, 1 -X, 2 +Z, 3 -Z (the shader's face ids). Returns [local position on the wall plane (x, z), outward yaw].
static func wall_point(lot: CityLayout.Lot, face: int, u: float) -> Array:
	match face:
		0:
			return [Vector2(lot.w * 0.5, lot.d * 0.5 - u), PI * 0.5]
		1:
			return [Vector2(-lot.w * 0.5, -lot.d * 0.5 + u), -PI * 0.5]
		2:
			return [Vector2(-lot.w * 0.5 + u, lot.d * 0.5), 0.0]
		_:
			return [Vector2(lot.w * 0.5 - u, -lot.d * 0.5), PI]


static func wall_width(lot: CityLayout.Lot, face: int) -> float:
	return lot.d if face < 2 else lot.w


func build(props, layout: CityLayout, buildings: Array) -> void:
	var rng: RandomNumberGenerator = props.rng
	var awn: Array = []
	var fire: Array = []
	var blades: Array = []
	var ac: Array = []
	var tanks: Array = []
	var masts: Array = []
	var houses: Array = []
	var boards: Array = []
	var covers: Array = []
	var pipes: Array = []
	var skylights: Array = []
	var hvacs: Array = []
	var reserved_centre := Vector2.INF
	var reserved_r := 6.2
	for b in buildings:
		reserved_centre = Vector2.INF
		reserved_r = 6.2
		var lot: CityLayout.Lot = b.lot
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var sx := 1 if lot.cx > bx else -1
		var sz := 1 if lot.cz > bz else -1
		# the two walls that face streets: +/-X (outward sx) and +/-Z (outward sz)
		var street_faces: Array[int] = [0 if sx > 0 else 1, 2 if sz > 0 else 3]

		# ---- awnings over shop bays and blade signs on the corners ----------------------------------------------------
		for face in street_faces:
			var fw := wall_width(lot, face)
			var nb := maxi(2, int(floor(fw / 4.8 + 0.5)))
			var bw := fw / float(nb)
			for k in nb:
				if rng.randf() < 0.36:
					var wp: Array = wall_point(lot, face, (float(k) + 0.5) * bw)
					var p2: Vector2 = wp[0]
					var yaw: float = wp[1]
					var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(bw * 0.9 / 3.8, 1.0, 1.0)), Vector3(lot.cx + p2.x, 0.0, lot.cz + p2.y))
					awn.append([xf, Color(rng.randf(), rng.randf(), 0.0, 1.0)])
			if rng.randf() < 0.7:
				var u := rng.randf_range(0.8, 2.5) if rng.randf() < 0.5 else fw - rng.randf_range(0.8, 2.5)
				var wp2: Array = wall_point(lot, face, u)
				var q: Vector2 = wp2[0]
				var y := rng.randf_range(4.6, maxf(8.0, minf(lot.h * 0.5, 24.0)))        # tall towers carry signs higher up
				var xf2 := Transform3D(Basis(Vector3.UP, float(wp2[1])), Vector3(lot.cx + q.x, y, lot.cz + q.y))
				var sv := rng.randf()
				blades.append([xf2, Color(sv, 0.0, 0.0, 1.0)])
				var nc: Color = NEON_COLORS[int(floor(sv * 4.0)) % 4]
				props.glow_add(xf2.origin + xf2.basis * Vector3(0.0, 1.6, 0.75), Color(nc.r, nc.g, nc.b, 0.9), 1, 4.2, 0.0, sv)

		# ---- fire escapes on low brick / punched buildings -------------------------------------------------------------
		if b.cls == &"block" and lot.h <= 30.0 and rng.randf() < 0.42:
			var face := street_faces[rng.randi() % 2]
			var fw2 := wall_width(lot, face)
			var gh := 4.6
			var body := maxf(lot.h - gh - 1.2, 3.5)
			var nfl := maxi(1, int(floor(body / 3.5 + 0.5)))
			var fh := body / float(nfl)
			var u2 := rng.randf_range(2.2, fw2 - 2.2)
			var wp3: Array = wall_point(lot, face, u2)
			var q3: Vector2 = wp3[0]
			var fl := 1
			while fl < nfl:
				var y3 := gh + float(fl) * fh + 0.2
				var xf3 := Transform3D(Basis(Vector3.UP, float(wp3[1])) * Basis.from_scale(Vector3(1.0, fh / 3.5, 1.0)), Vector3(lot.cx + q3.x, y3, lot.cz + q3.y))
				fire.append([xf3, Color(rng.randf(), 0.0, 0.0, 1.0)])
				fl += 2

		# ---- roof clutter ------------------------------------------------------------------------------------------------
		var tp: Array = BM.top_part(b.cls)
		var rx0: float = lot.cx + tp[0] * lot.w + 1.4
		var rx1: float = lot.cx + tp[1] * lot.w - 1.4
		var rz0: float = lot.cz + tp[2] * lot.d + 1.4
		var rz1: float = lot.cz + tp[3] * lot.d - 1.4
		var roof_y := lot.h
		if rx1 - rx0 < 3.0 or rz1 - rz0 < 3.0:
			continue
		var cells := {}
		if (b.flags & 16) != 0 and rx1 - rx0 > 9.0 and rz1 - rz0 > 9.0:
			# helipad zone: reserve the cells around the roof centre
			var cxr := (rx0 + rx1) * 0.5
			var czr := (rz0 + rz1) * 0.5
			cells = {}
			reserved_centre = Vector2(cxr, czr)
			reserved_r = 6.2
		else:
			reserved_centre = Vector2((rx0 + rx1) * 0.5, (rz0 + rz1) * 0.5)      # every crown keeps a clear landing spot at its centre (the pooled prop colliders must not occupy it)
			reserved_r = 3.4
		var n_ac := clampi(int(round((rx1 - rx0) * (rz1 - rz0) / 100.0)), 1, 5)
		for k in n_ac:
			var p := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 3.2, reserved_centre, reserved_r)
			if p != Vector2.INF:
				var yaw2 := float(rng.randi() % 4) * PI * 0.5
				ac.append([Transform3D(Basis(Vector3.UP, yaw2), Vector3(p.x, roof_y, p.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		if rng.randf() < 0.85:                                  # stair houses / penthouses: the small setback masses of the skyline
			var p2 := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 4.6, reserved_centre, reserved_r)
			if p2 != Vector2.INF:
				houses.append([Transform3D(Basis(Vector3.UP, float(rng.randi() % 4) * PI * 0.5), Vector3(p2.x, roof_y, p2.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		if lot.h <= 70.0 and rng.randf() < 0.55:
			var p3 := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 4.2, reserved_centre, reserved_r)
			if p3 != Vector2.INF:
				var tsv := rng.randf()
				# variety without a second mesh: the tank's own seed picks a squat or a standard tank and a footprint (the pooled collider stays valid), no random stream moves
				var tk := Vector3(0.9 + 0.35 * fposmod(tsv * 5.3, 1.0), 0.7 + 0.3 * fposmod(tsv * 11.7, 1.0), 0.9 + 0.35 * fposmod(tsv * 5.3, 1.0))
				tanks.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(tk), Vector3(p3.x, roof_y, p3.y)), Color(tsv, 0.0, 0.0, 1.0)])
		# more roof families on every roof class: HVAC units, pipe runs, skylights and low cover walls
		if rng.randf() < 0.75:
			var ph := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 3.4, reserved_centre, reserved_r)
			if ph != Vector2.INF:
				hvacs.append([Transform3D(Basis(Vector3.UP, float(rng.randi() % 4) * PI * 0.5), Vector3(ph.x, roof_y, ph.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		if rng.randf() < 0.7:
			var pp := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 4.6, reserved_centre, reserved_r)
			if pp != Vector2.INF:
				pipes.append([Transform3D(Basis(Vector3.UP, float(rng.randi() % 4) * PI * 0.5), Vector3(pp.x, roof_y, pp.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		if rng.randf() < 0.5:
			var ps := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 3.0, reserved_centre, reserved_r)
			if ps != Vector2.INF:
				skylights.append([Transform3D(Basis(Vector3.UP, float(rng.randi() % 2) * PI * 0.5), Vector3(ps.x, roof_y, ps.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		var n_cover := clampi(int(round((rx1 - rx0) * (rz1 - rz0) / 220.0)), 1, 3)
		for k in n_cover:
			if rng.randf() < 0.75:
				var pc := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 3.4, reserved_centre, reserved_r)
				if pc != Vector2.INF:
					covers.append([Transform3D(Basis(Vector3.UP, float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.12, 0.12)), Vector3(pc.x, roof_y, pc.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		var want_mast := 0.92 if lot.h >= 62.0 else (0.5 if lot.h >= 28.0 else 0.26)
		if rng.randf() < want_mast:
			var p4 := _free_cell(rng, cells, rx0, rx1, rz0, rz1, 2.2, reserved_centre, reserved_r)
			if p4 != Vector2.INF:
				var mxf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p4.x, roof_y, p4.y))
				var sv2 := rng.randf()
				masts.append([mxf, Color(sv2, 0.0, 0.0, 1.0)])
				props.glow_add(mxf.origin + Vector3(0, 13.5, 0), Color(1.0, 0.1, 0.06, 2.0), 3, 5.0, 0.0, sv2)
		# a tall vertical roof sign: the blade-sign mesh scaled up, standing on the street-facing parapet (same family and draw call as the wall blades)
		if lot.h >= 18.0 and rng.randf() < 0.38:
			var face3 := street_faces[rng.randi() % 2]
			var fw3 := wall_width(lot, face3)
			var wp5: Array = wall_point(lot, face3, rng.randf_range(1.2, maxf(1.3, fw3 - 1.2)))
			var q5: Vector2 = wp5[0]
			var sy := rng.randf_range(1.7, 2.6)
			var vxf := Transform3D(Basis(Vector3.UP, float(wp5[1])) * Basis.from_scale(Vector3(1.0, sy, 1.5)), Vector3(lot.cx + q5.x, roof_y - 1.2, lot.cz + q5.y))
			var vsv := rng.randf()
			blades.append([vxf, Color(vsv, 0.0, 0.0, 1.0)])
			var vc: Color = NEON_COLORS[int(floor(vsv * 4.0)) % 4]
			props.glow_add(vxf.origin + vxf.basis * Vector3(0.0, 1.6, 0.75), Color(vc.r, vc.g, vc.b, 0.8), 1, 5.5, 0.0, vsv)
		if lot.h <= 44.0 and rng.randf() < 0.22:
			# billboard along the street-facing roof edge, facing outwards
			var face2 := street_faces[rng.randi() % 2]
			var wp4: Array = wall_point(lot, face2, wall_width(lot, face2) * 0.5)
			var q4: Vector2 = wp4[0]
			var inward := Vector2(-sin(float(wp4[1])), -cos(float(wp4[1])))        # opposite of the outward direction
			var bxf := Transform3D(Basis(Vector3.UP, float(wp4[1])), Vector3(lot.cx + q4.x + inward.x * 1.8, roof_y, lot.cz + q4.y + inward.y * 1.8))
			var bs := rng.randf()
			boards.append([bxf, Color(bs, bs, 0.0, 1.0)])
			var bc: Color = NEON_COLORS[int(floor(bs * 4.0)) % 4]
			props.glow_add(bxf.origin + bxf.basis * Vector3(0.0, 5.8, 1.5), Color(bc.r, bc.g, bc.b, 0.55), 0, 20.0, 0.0, bs)

	props.add_family("Awnings", awning_mesh(), awn, false, false, 0, 170.0)
	props.add_family("FireEscapes", fire_escape_mesh(), fire, false, false, 1, 170.0)
	props.add_family("BladeSigns", blade_mesh(), blades, true, false, 0, 270.0)
	props.add_family("RoofAC", ac_mesh(), ac, false, false, 0, 230.0)
	props.add_family("RoofVents", hvac_mesh(), hvacs, false, false, 0, 210.0)
	props.add_family("RoofPipes", pipes_mesh(), pipes, false, false, 1, 180.0)
	props.add_family("RoofSkylights", skylight_mesh(), skylights, false, false, 1, 190.0)
	props.add_family("RoofCover", cover_wall_mesh(), covers, false, false, 0, 230.0)
	props.add_family("RoofTanks", tank_mesh(), tanks, false, false, 0, 270.0)
	props.add_family("RoofMasts", mast_mesh(), masts, false, false, 0, 330.0)
	props.add_family("RoofHouses", stair_house_mesh(), houses, false, false, 0, 250.0)
	props.add_family("Billboards", billboard_mesh(), boards, true, false, 0, 360.0)


## A random free spot on a coarse grid (so clutter never overlaps); Vector2.INF when the roof is full.
static func _free_cell(rng: RandomNumberGenerator, taken: Dictionary, x0: float, x1: float, z0: float, z1: float, size: float, avoid := Vector2.INF, avoid_r := 6.2) -> Vector2:
	var nx := maxi(1, int(floor((x1 - x0) / size)))
	var nz := maxi(1, int(floor((z1 - z0) / size)))
	for attempt in 8:
		var ix := rng.randi() % nx
		var iz := rng.randi() % nz
		var key := ix * 64 + iz
		if taken.has(key):
			continue
		var spot := Vector2(x0 + (float(ix) + 0.5) * (x1 - x0) / float(nx), z0 + (float(iz) + 0.5) * (z1 - z0) / float(nz))
		if avoid != Vector2.INF and spot.distance_to(avoid) < avoid_r:
			continue
		taken[key] = true
		return spot
	return Vector2.INF
