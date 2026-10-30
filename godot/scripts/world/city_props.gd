extends RefCounted
## Street furniture of the city: lamps, traffic signals, bus stops, kiosks, dumpsters, trash, hydrants, barriers, plaza sets,
## steam vent grates, plus the additive glow sprites and light shafts that give the street its air. Placement is deterministic
## (own RNG, independent of the layout random stream). Every family is one MultiMesh.
##
## Instance data of the prop shader: INSTANCE_CUSTOM = (seed, variant 0..1, phase, intensity). Mesh vertex colour alpha is the
## emission code (see assets/shaders/prop_core.gdshaderinc), UV2 = (metallic, roughness).

const MB := preload("res://scripts/world/mesh_builder.gd")
const Roofs := preload("res://scripts/world/city_roofs.gd")

const EM_LAMP := 0.15
const EM_FLASHER := 0.45
const EM_SCREEN := 0.60
const EM_BLADE := 0.70
const EM_POSTER := 0.80
const EM_RED := 0.90
const EM_AMBER := 0.93
const EM_GREEN := 0.96
const EM_GLOW := 1.0

## Result entries: {name, mm, kind (&"prop" | &"glow" | &"shaft"), mirror, shadow}
var parts: Array[Dictionary] = []
var vents: Array[Vector3] = []            ## steam vent positions (x, 0, z) and yaw in y? no: x, z in x/z, strength in y
var rng := RandomNumberGenerator.new()

var _glow: Array = []                     ## [pos: Vector3, color: Color(rgb, brightness), kind, size, phase, seed]


## Street lamps: Vector4(x, z, arm_dx, arm_dz). Corner lamps follow the prototype (two diagonal corners per junction), plus a
## lamp per block face on both sides so the streets never go completely dark between junctions.
static func lamp_list() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var n := CityLayout.N
	var lim := CityLayout.HALF + 11.0
	var s2 := 0.7071
	for i in range(0, n + 1):
		for j in range(0, n + 1):
			var x := CityLayout.road_center(i)
			var z := CityLayout.road_center(j)
			if absf(x - 10.6) < lim and absf(z - 10.6) < lim:
				out.append(Vector4(x - 10.6, z - 10.6, s2, s2))
			if absf(x + 10.6) < lim and absf(z + 10.6) < lim:
				out.append(Vector4(x + 10.6, z + 10.6, -s2, -s2))
	for i in range(0, n + 1):
		for k in range(0, n):
			var c := CityLayout.road_center(i)
			var m := CityLayout.road_center(k) + CityLayout.PITCH * 0.5
			for side in [-1.0, 1.0]:
				out.append(Vector4(m, c + side * 10.6, 0.0, -side))        # road along x
				out.append(Vector4(c + side * 10.6, m, -side, 0.0))        # road along z
	return out


# --- meshes ----------------------------------------------------------------------------------------------------------------

static func _mb(metal: float, rough: float) -> MB:
	var b := MB.new()
	b.uv2 = Vector2(metal, rough)
	return b


static func _finish(b: MB) -> ArrayMesh:
	return b.build(null, true, true)


static func lamp_mesh() -> ArrayMesh:
	var b := _mb(0.8, 0.45)
	var metal := Color(0.075, 0.08, 0.085, 0.0)
	b.cylinder(Vector3(0, 0, 0), 0.21, 0.5, 6, Color(0.10, 0.10, 0.105, 0.0), 0.15, false)
	b.cylinder(Vector3(0, 0.45, 0), 0.11, 7.0, 6, metal, 0.07, false)
	b.strut(Vector3(0, 7.3, 0), Vector3(1.1, 7.78, 0), 0.10, metal)
	b.strut(Vector3(1.1, 7.78, 0), Vector3(2.35, 7.72, 0), 0.08, metal)
	b.box(Vector3(2.5, 7.67, 0), Vector3(1.05, 0.2, 0.44), Color(0.12, 0.125, 0.13, 0.0), false)
	b.uv2 = Vector2(0.0, 0.2)
	var y := 7.565
	b.quad(Vector3(2.08, y, -0.15), Vector3(2.92, y, -0.15), Vector3(2.92, y, 0.15), Vector3(2.08, y, 0.15), Vector3.DOWN, Color(1, 1, 1, EM_LAMP))
	return _finish(b)


static func signal_mesh() -> ArrayMesh:
	var b := _mb(0.7, 0.5)
	var metal := Color(0.10, 0.105, 0.11, 0.0)
	b.cylinder(Vector3(0, 0, 0), 0.12, 5.1, 6, metal, 0.075, false)
	b.strut(Vector3(0, 5.15, 0), Vector3(4.6, 5.3, 0), 0.13, metal)
	b.box(Vector3(0.0, 4.75, 0.14), Vector3(0.9, 0.2, 0.03), Color(0.02, 0.18, 0.12, 0.0), false)
	var ys := [5.08, 4.75, 4.42]
	var codes := [EM_RED, EM_AMBER, EM_GREEN]
	for hx in [4.3, 2.4]:
		b.box(Vector3(hx, 4.75, 0.0), Vector3(0.38, 1.12, 0.3), Color(0.03, 0.03, 0.035, 0.0), false)
		b.uv2 = Vector2(0.0, 0.2)
		for k in 3:
			var c := Vector3(hx, ys[k], 0.152)
			b.quad(c + Vector3(-0.1, -0.1, 0), c + Vector3(0.1, -0.1, 0), c + Vector3(0.1, 0.1, 0), c + Vector3(-0.1, 0.1, 0), Vector3.BACK, Color(1, 1, 1, codes[k]))
		b.uv2 = Vector2(0.7, 0.5)
	return _finish(b)


static func bus_stop_mesh() -> ArrayMesh:
	var b := _mb(0.6, 0.5)
	var metal := Color(0.10, 0.105, 0.11, 0.0)
	b.box(Vector3(0, 2.55, 0.1), Vector3(3.3, 0.1, 1.5), Color(0.06, 0.065, 0.07, 0.0))
	b.box(Vector3(0, 2.62, 0.1), Vector3(3.3, 0.04, 1.5), Color(0.13, 0.135, 0.14, 0.0))
	for x in [-1.6, 1.6]:
		b.cylinder(Vector3(x, 0, -0.55), 0.05, 2.5, 6, metal)
		b.cylinder(Vector3(x, 0, 0.7), 0.05, 2.5, 6, metal)
	b.uv2 = Vector2(0.0, 0.08)
	b.box(Vector3(-0.35, 1.25, -0.6), Vector3(2.4, 2.1, 0.03), Color(0.03, 0.045, 0.06, 0.0))      # glass back
	b.uv2 = Vector2(0.6, 0.5)
	b.box(Vector3(1.9, 1.0, -0.6), Vector3(0.9, 1.8, 0.14), Color(0.07, 0.075, 0.08, 0.0))         # poster box housing
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(1.45, 0.25, -0.52), Vector3(2.35, 0.25, -0.52), Vector3(2.35, 1.75, -0.52), Vector3(1.45, 1.75, -0.52), Vector3.BACK,
			Color(1, 1, 1, EM_POSTER), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	b.uv2 = Vector2(0.4, 0.6)
	b.box(Vector3(-0.4, 0.5, -0.38), Vector3(1.9, 0.06, 0.4), Color(0.12, 0.10, 0.08, 0.0))       # bench
	for x in [-1.2, 0.4]:
		b.box(Vector3(x, 0.25, -0.38), Vector3(0.05, 0.5, 0.36), metal)
	# route sign on a short pole
	b.cylinder(Vector3(2.2, 0, 0.7), 0.04, 3.0, 6, metal)
	b.box(Vector3(2.2, 3.0, 0.7), Vector3(0.5, 0.5, 0.04), Color(0.1, 0.25, 0.6, 0.0))
	return _finish(b)


static func kiosk_mesh() -> ArrayMesh:
	var b := _mb(0.5, 0.55)
	b.box(Vector3(0, 1.25, 0), Vector3(2.4, 2.5, 1.7), Color(0.07, 0.075, 0.08, 0.0))
	b.box(Vector3(0, 2.58, 0), Vector3(2.7, 0.16, 2.0), Color(0.05, 0.05, 0.055, 0.0))
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-1.0, 0.9, 0.86), Vector3(1.0, 0.9, 0.86), Vector3(1.0, 2.0, 0.86), Vector3(-1.0, 2.0, 0.86), Vector3.BACK,
			Color(1, 1, 1, EM_POSTER), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	b.quad(Vector3(-1.1, 2.15, 0.87), Vector3(1.1, 2.15, 0.87), Vector3(1.1, 2.5, 0.87), Vector3(-1.1, 2.5, 0.87), Vector3.BACK,
			Color(1, 1, 1, EM_BLADE), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(0, 0.2), Vector2(0.3, 0.2), Vector2(0.3, 0.0), Vector2(0, 0.0)]))
	b.uv2 = Vector2(0.5, 0.55)
	b.box(Vector3(0, 0.55, 0.9), Vector3(2.2, 0.1, 0.25), Color(0.04, 0.04, 0.045, 0.0))
	return _finish(b)


static func dumpster_mesh() -> ArrayMesh:
	var b := _mb(0.25, 0.65)
	var body := Color(0.10, 0.24, 0.17, 0.0)
	b.box(Vector3(0, 0.62, 0), Vector3(1.9, 1.05, 1.0), body)
	b.box(Vector3(0, 0.12, 0), Vector3(1.8, 0.14, 0.95), Color(0.04, 0.04, 0.04, 0.0))
	var lid := Color(0.06, 0.07, 0.065, 0.0)
	b.box_yaw(Vector3(-0.5, 1.2, 0.0), Vector3(0.95, 0.06, 1.06), 0.0, lid)
	b.box(Vector3(0.45, 1.22, 0.0), Vector3(0.95, 0.06, 1.06), lid)
	for x in [-0.75, 0.75]:
		b.box(Vector3(x, 0.1, 0.45), Vector3(0.14, 0.2, 0.08), Color(0.02, 0.02, 0.02, 0.0))
		b.box(Vector3(x, 0.1, -0.45), Vector3(0.14, 0.2, 0.08), Color(0.02, 0.02, 0.02, 0.0))
	b.box(Vector3(0, 0.85, 0.52), Vector3(1.9, 0.07, 0.04), Color(0.05, 0.05, 0.05, 0.0))
	return _finish(b)


static func trash_mesh() -> ArrayMesh:
	var b := _mb(0.0, 0.38)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var cols: Array[Color] = [Color(0.025, 0.025, 0.03, 0.0), Color(0.04, 0.06, 0.045, 0.0), Color(0.09, 0.09, 0.1, 0.0), Color(0.05, 0.04, 0.03, 0.0)]
	for i in 4:
		var p := Vector3(r.randf_range(-0.6, 0.6), 0.0, r.randf_range(-0.4, 0.4))
		var s := Vector3(r.randf_range(0.26, 0.42), r.randf_range(0.2, 0.32), r.randf_range(0.24, 0.38))
		p.y = s.y * 0.7 + (0.25 if i == 3 else 0.0)
		b.sphere(p, s, 5, 3, cols[r.randi() % cols.size()])
	b.box(Vector3(0.5, 0.12, 0.3), Vector3(0.5, 0.24, 0.4), Color(0.15, 0.10, 0.06, 0.0), false)
	return _finish(b)


static func hydrant_mesh() -> ArrayMesh:
	var b := _mb(0.3, 0.45)
	var red := Color(0.40, 0.035, 0.03, 0.0)
	b.cylinder(Vector3(0, 0, 0), 0.13, 0.7, 6, red, 0.1, false)
	b.sphere(Vector3(0, 0.74, 0), Vector3(0.12, 0.09, 0.12), 6, 2, red)
	b.box(Vector3(0, 0.42, 0), Vector3(0.4, 0.12, 0.12), red, false)
	return _finish(b)


static func barrier_mesh() -> ArrayMesh:
	var b := _mb(0.0, 0.8)
	var profile := PackedVector2Array([Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.24, 0.3), Vector2(0.11, 0.8), Vector2(-0.11, 0.8), Vector2(-0.24, 0.3)])
	b.prism(profile, -1.2, 1.2, Color(0.42, 0.42, 0.40, 0.0))
	# hazard stripes on the top portion
	for k in 4:
		var z0 := -1.2 + 0.6 * k
		var c := Color(0.55, 0.20, 0.03, 0.0) if k % 2 == 0 else Color(0.5, 0.5, 0.48, 0.0)
		b.box(Vector3(0, 0.62, z0 + 0.3), Vector3(0.33, 0.14, 0.58), c)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 0.9, 0), Vector3(0.14, 0.12, 0.14), Color(1.0, 0.5, 0.05, EM_FLASHER))
	return _finish(b)


static func vent_mesh() -> ArrayMesh:
	var b := _mb(0.7, 0.5)
	b.box(Vector3(0, 0.03, 0), Vector3(1.5, 0.06, 1.0), Color(0.04, 0.04, 0.045, 0.0))
	b.uv2 = Vector2(0.0, 0.5)
	for k in 6:
		b.box(Vector3(0, 0.065, -0.4 + k * 0.16), Vector3(1.3, 0.012, 0.06), Color(1.0, 0.45, 0.15, EM_GLOW))
	return _finish(b)


## Plaza furniture set: bollards with light rings around the plaza, two benches, a planter and a lit column.
static func plaza_mesh() -> ArrayMesh:
	var b := _mb(0.5, 0.5)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var p := Vector3(cos(a), 0.0, sin(a)) * 11.0
		b.cylinder(p, 0.12, 0.9, 6, Color(0.07, 0.075, 0.08, 0.0), -1.0, false)
		b.uv2 = Vector2(0.0, 0.3)
		b.cylinder(p + Vector3(0, 0.9, 0), 0.115, 0.05, 6, Color(0.3, 0.95, 1.0, EM_GLOW), -1.0, true)
		b.uv2 = Vector2(0.5, 0.5)
	for sgn in [-1.0, 1.0]:
		var c := Vector3(sgn * 4.5, 0.0, 0.0)
		b.box(c + Vector3(0, 0.45, 0), Vector3(0.5, 0.08, 2.6), Color(0.12, 0.10, 0.08, 0.0), false)
		b.box(c + Vector3(-0.22, 0.75, 0), Vector3(0.08, 0.5, 2.6), Color(0.12, 0.10, 0.08, 0.0), false)
		b.box(c + Vector3(0, 0.2, 1.1), Vector3(0.4, 0.4, 0.1), Color(0.05, 0.05, 0.05, 0.0), false)
		b.box(c + Vector3(0, 0.2, -1.1), Vector3(0.4, 0.4, 0.1), Color(0.05, 0.05, 0.05, 0.0), false)
	b.box(Vector3(0, 0.4, 5.5), Vector3(3.0, 0.8, 1.4), Color(0.1, 0.1, 0.105, 0.0), false)
	b.uv2 = Vector2(0.0, 0.9)
	b.sphere(Vector3(0, 1.1, 5.5), Vector3(1.3, 0.7, 0.6), 7, 3, Color(0.03, 0.08, 0.04, 0.0))
	b.uv2 = Vector2(0.4, 0.5)
	b.cylinder(Vector3(0, 0, -5.5), 0.5, 3.6, 8, Color(0.06, 0.065, 0.07, 0.0), -1.0, false)
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-0.45, 1.0, -5.0), Vector3(0.45, 1.0, -5.0), Vector3(0.45, 3.2, -5.0), Vector3(-0.45, 3.2, -5.0), Vector3.BACK,
			Color(1, 1, 1, EM_SCREEN), Vector2.ZERO, Vector2.ZERO, PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	return _finish(b)


static func shaft_mesh() -> ArrayMesh:
	var b := MB.new()
	b.funnel(Vector3(0, 7.5, 0), 0.0, 4.6, 12, 0.12, Color(1, 1, 1, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.verts
	arrays[Mesh.ARRAY_NORMAL] = b.norms
	arrays[Mesh.ARRAY_TEX_UV] = b.uvs
	arrays[Mesh.ARRAY_COLOR] = b.cols
	arrays[Mesh.ARRAY_INDEX] = b.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func glow_quad_mesh() -> ArrayMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var arrays := q.get_mesh_arrays()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# --- placement -------------------------------------------------------------------------------------------------------------

func add_family(name: String, mesh: Mesh, items: Array, mirror := false, shadow := false) -> void:
	## items: [Transform3D, custom Color]
	if items.is_empty():
		return
	var mm := MB.new_multimesh(mesh, items.size(), false, true)
	var buf := MB.new_buffer(items.size(), false, true)
	for i in items.size():
		MB.write_instance(buf, i, items[i][0], false, Color.WHITE, true, items[i][1])
	mm.buffer = buf
	parts.append({"name": name, "mm": mm, "kind": &"prop", "mirror": mirror, "shadow": shadow})


func glow_add(pos: Vector3, color: Color, kind: int, size: float, phase := 0.0, seed_v := 0.0) -> void:
	_glow.append([pos, color, kind, size, phase, seed_v])


func _flush_glow() -> void:
	if _glow.is_empty():
		return
	var mm := MB.new_multimesh(glow_quad_mesh(), _glow.size(), true, true)
	var buf := MB.new_buffer(_glow.size(), true, true)
	for i in _glow.size():
		var g: Array = _glow[i]
		MB.write_instance(buf, i, Transform3D(Basis.IDENTITY, g[0]), true, g[1], true, Color(float(g[2]), g[3], g[4], g[5]))
	mm.buffer = buf
	parts.append({"name": "Glow", "mm": mm, "kind": &"glow", "mirror": true, "shadow": false})
	_glow.clear()


static func _lamp_color(variant: float) -> Color:
	var t := clampf(variant * 2.0, 0.0, 1.0)
	var c := Color(1.0, 0.62, 0.30).lerp(Color(0.78, 0.90, 1.0), t)
	return c.lerp(Color(0.45, 0.90, 1.0), clampf(variant * 2.0 - 1.0, 0.0, 1.0))


func build(layout: CityLayout, building_data: Array = []) -> void:
	rng.seed = 90210
	parts.clear()
	_glow.clear()
	_place_lamps()
	_place_signals()
	_place_bus_stops()
	_place_lot_props(layout)
	_place_corner_props()
	_place_plazas(layout)
	_place_vents()
	if not building_data.is_empty():
		Roofs.new().build(self, layout, building_data)
	_flush_glow()


func _place_lamps() -> void:
	var items: Array = []
	var shafts: Array = []
	for lamp in lamp_list():
		var dir := Vector2(lamp.z, lamp.w)
		var theta := atan2(-dir.y, dir.x)
		var variant := 0.0
		var r := rng.randf()
		if r > 0.9:
			variant = 1.0
		elif r > 0.72:
			variant = 0.5
		var seed_v := rng.randf()
		var xf := Transform3D(Basis(Vector3.UP, theta), Vector3(lamp.x, 0.0, lamp.y))
		items.append([xf, Color(seed_v, variant, 0.0, 1.0)])
		var lens := Vector3(lamp.x + dir.x * 2.5, 7.55, lamp.y + dir.y * 2.5)
		var col := _lamp_color(variant)
		glow_add(lens, Color(col.r, col.g, col.b, 1.5), 1 if seed_v > 0.86 else 0, 6.0, 0.0, seed_v)
		shafts.append([Transform3D(Basis.IDENTITY, Vector3(lens.x, 0.0, lens.z)), Color(col.r, col.g, col.b, 0.55)])
	add_family("Lamps", lamp_mesh(), items, false, false)
	# light shafts: one MultiMesh with instance colour
	var mm := MB.new_multimesh(shaft_mesh(), shafts.size(), true, false)
	var buf := MB.new_buffer(shafts.size(), true, false)
	for i in shafts.size():
		MB.write_instance(buf, i, shafts[i][0], true, shafts[i][1])
	mm.buffer = buf
	parts.append({"name": "LampShafts", "mm": mm, "kind": &"shaft", "mirror": false, "shadow": false})


func _place_signals() -> void:
	var items: Array = []
	for i in range(0, CityLayout.N + 1):
		for j in range(0, CityLayout.N + 1):
			var x := CityLayout.road_center(i)
			var z := CityLayout.road_center(j)
			var phase := rng.randf() * 22.0
			# pole A over the road along x (heads face -x), pole B over the road along z (heads face +z)
			var corners := [[Vector3(x + 10.6, 0.0, z - 10.6), -PI * 0.5, 0.0], [Vector3(x - 10.6, 0.0, z + 10.6), 0.0, 11.0]]
			for c in corners:
				var pos: Vector3 = c[0]
				if absf(pos.x) > CityLayout.HALF + 11.0 or absf(pos.z) > CityLayout.HALF + 11.0:
					continue
				var theta: float = c[1]
				var ph: float = phase + c[2]
				var basis := Basis(Vector3.UP, theta)
				items.append([Transform3D(basis, pos), Color(rng.randf(), 0.0, ph, 1.0)])
				for hx in [4.3, 2.4]:
					var ys := [5.08, 4.75, 4.42]
					var cols := [Color(1.0, 0.08, 0.05, 1.3), Color(1.0, 0.62, 0.05, 1.3), Color(0.10, 1.0, 0.45, 1.3)]
					for k in 3:
						var wp := pos + basis * Vector3(hx, ys[k], 0.24)
						glow_add(wp, cols[k], 2, 1.7, ph, float(k))
	add_family("Signals", signal_mesh(), items, false, false)


func _place_bus_stops() -> void:
	var items: Array = []
	var n := CityLayout.N
	for k in 34:
		var axis := rng.randi() % 2
		var road := rng.randi_range(1, n - 1)
		var seg := rng.randi_range(0, n - 1)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var c := CityLayout.road_center(road)
		var m := CityLayout.road_center(seg) + CityLayout.PITCH * 0.5 + rng.randf_range(-14.0, 14.0)
		var pos: Vector3
		var theta: float
		if axis == 0:
			pos = Vector3(m, 0.0, c + side * 11.8)
			theta = PI if side > 0.0 else 0.0
		else:
			pos = Vector3(c + side * 11.8, 0.0, m)
			theta = -side * PI * 0.5
		items.append([Transform3D(Basis(Vector3.UP, theta), pos), Color(rng.randf(), 0.0, 0.0, 1.0)])
		var cn := Vector3(0.0, 1.0, -0.5)
		glow_add(pos + Basis(Vector3.UP, theta) * Vector3(1.9, 1.0, -0.4), Color(0.7, 0.85, 1.0, 0.7), 0, 3.4, 0.0, rng.randf())
	add_family("BusStops", bus_stop_mesh(), items, false, false)


## Dumpsters, trash heaps and lit kiosks in the block alleys and on the sidewalks.
func _place_lot_props(layout: CityLayout) -> void:
	var dump: Array = []
	var trash: Array = []
	var kiosks: Array = []
	var hyd: Array = []
	var barr: Array = []
	for lot: CityLayout.Lot in layout.lots:
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var sx := 1.0 if lot.cx > bx else -1.0
		var sz := 1.0 if lot.cz > bz else -1.0
		# alley wall (towards the block centre line) of this lot
		var wall_x := lot.cx - sx * lot.w * 0.5
		if rng.randf() < 0.45:
			var z := lot.cz + sz * (lot.d * 0.5 - rng.randf_range(1.6, 4.5))
			var p := Vector3(wall_x - sx * 1.0, 0.0, z)
			dump.append([Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.08, 0.08)), p), Color(rng.randf(), rng.randf(), 0.0, 1.0)])
			if rng.randf() < 0.8:
				trash.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(-sx * 0.2, 0.0, rng.randf_range(1.6, 2.4) * (1.0 if rng.randf() < 0.5 else -1.0))), Color(rng.randf(), 0.0, 0.0, 1.0)])
		if rng.randf() < 0.55:
			# rubbish bags against the front wall (towards the street)
			var wz := lot.cz + sz * lot.d * 0.5
			var px := lot.cx + rng.randf_range(-lot.w * 0.35, lot.w * 0.35)
			trash.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, 0.0, wz + sz * 0.7)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		if rng.randf() < 0.11 and lot.h < 50.0:
			# lit kiosk on the sidewalk in front, facing the street
			var wz2 := lot.cz + sz * (lot.d * 0.5 + 1.6)
			var theta := 0.0 if sz > 0.0 else PI
			kiosks.append([Transform3D(Basis(Vector3.UP, theta), Vector3(lot.cx + rng.randf_range(-lot.w * 0.3, lot.w * 0.3), 0.0, wz2)), Color(rng.randf(), 0.0, 0.0, 1.0)])
	add_family("Dumpsters", dumpster_mesh(), dump, false, false)
	add_family("Trash", trash_mesh(), trash, false, false)
	add_family("Kiosks", kiosk_mesh(), kiosks, false, false)
	for k in kiosks.size():
		var xf: Transform3D = kiosks[k][0]
		glow_add(xf.origin + xf.basis * Vector3(0.0, 1.4, 1.0), Color(0.9, 0.95, 1.0, 0.8), 1, 3.2, 0.0, rng.randf())


func _place_corner_props() -> void:
	var hyd: Array = []
	var barr: Array = []
	var n := CityLayout.N
	for i in range(1, n):
		for j in range(1, n):
			var x := CityLayout.road_center(i)
			var z := CityLayout.road_center(j)
			if rng.randf() < 0.5:
				var sx := 1.0 if rng.randf() < 0.5 else -1.0
				var sz := 1.0 if rng.randf() < 0.5 else -1.0
				hyd.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x + sx * 10.5, 0.0, z + sz * 14.0)), Color(rng.randf(), 0.0, 0.0, 1.0)])
	# road works: a row of barriers along a kerb, with flashers
	for k in 10:
		var axis := rng.randi() % 2
		var road := rng.randi_range(1, n - 1)
		var seg := rng.randi_range(0, n - 1)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var c := CityLayout.road_center(road)
		var m := CityLayout.road_center(seg) + CityLayout.PITCH * 0.5 + rng.randf_range(-12.0, 12.0)
		var cnt := rng.randi_range(3, 5)
		for q in cnt:
			var along := m + (float(q) - float(cnt) * 0.5) * 2.5
			var lat := c + side * 8.6
			var pos := Vector3(along, 0.0, lat) if axis == 0 else Vector3(lat, 0.0, along)
			var theta := 0.0 if axis == 1 else PI * 0.5
			barr.append([Transform3D(Basis(Vector3.UP, theta), pos), Color(rng.randf(), 0.0, float(q), 1.0)])
			if q == 0 or q == cnt - 1:
				glow_add(pos + Vector3(0, 0.9, 0), Color(1.0, 0.5, 0.08, 1.0), 4, 1.6, 0.0, rng.randf())
	add_family("Hydrants", hydrant_mesh(), hyd, false, false)
	add_family("Barriers", barrier_mesh(), barr, false, false)


func _place_plazas(layout: CityLayout) -> void:
	var items: Array = []
	for p in layout.plazas:
		items.append([Transform3D(Basis(Vector3.UP, 0.0), Vector3(p.x, 0.0, p.y)), Color(rng.randf(), 0.0, 0.0, 1.0)])
		glow_add(Vector3(p.x, 3.6, p.y - 5.5), Color(0.5, 0.9, 1.0, 1.1), 0, 6.0, 0.0, rng.randf())
	add_family("Plazas", plaza_mesh(), items, false, false)


## Steam vents: grates on the roads near kerbs and at alley mouths (the steam itself is built by city_misc.gd).
func _place_vents() -> void:
	var items: Array = []
	var n := CityLayout.N
	vents.clear()
	for k in 16:
		var axis := rng.randi() % 2
		var road := rng.randi_range(0, n)
		var seg := rng.randi_range(0, n - 1)
		var c := CityLayout.road_center(road)
		var m := CityLayout.road_center(seg) + rng.randf_range(16.0, CityLayout.PITCH - 16.0)
		var lat := c + (rng.randf_range(6.2, 8.8) * (1.0 if rng.randf() < 0.5 else -1.0))
		var pos := Vector3(m, 0.0, lat) if axis == 0 else Vector3(lat, 0.0, m)
		if absf(pos.x) > CityLayout.HALF - 12.0 or absf(pos.z) > CityLayout.HALF - 12.0:
			continue
		var theta := 0.0 if axis == 0 else PI * 0.5
		items.append([Transform3D(Basis(Vector3.UP, theta), pos), Color(rng.randf(), 0.0, 0.0, 1.0)])
		vents.append(pos)
		glow_add(pos + Vector3(0, 0.15, 0), Color(1.0, 0.5, 0.2, 0.8), 0, 2.6, 0.0, rng.randf())
	add_family("VentGrates", vent_mesh(), items, false, false)
