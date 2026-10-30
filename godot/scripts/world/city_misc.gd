extends RefCounted
## Atmosphere props of the city that are not furniture: overhead cables strung across streets, steam plumes over the vents and
## rooftop hologram columns. Steam, cables and holograms are each a single draw call.

const MB := preload("res://scripts/world/mesh_builder.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const STEAM_SHADER := preload("res://assets/shaders/steam.gdshader")
const CABLE_SHADER := preload("res://assets/shaders/cable.gdshader")
const HOLO_SHADER := preload("res://assets/shaders/hologram.gdshader")

const PUFFS_PER_VENT := 22

var cable_mesh: ArrayMesh
var steam_mm: MultiMesh
var hologram_mm: MultiMesh
var cable_count := 0


func build(layout: CityLayout, buildings: Array, vents: Array[Vector3], rng: RandomNumberGenerator) -> void:
	_build_cables(layout, rng)
	_build_steam(vents, rng)
	_build_holograms(buildings, rng)


static func make_material(shader: Shader, priority := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	return m


# --- cables ----------------------------------------------------------------------------------------------------------------

func _build_cables(layout: CityLayout, rng: RandomNumberGenerator) -> void:
	# lots by (block i, block j, sx, sz) so facing walls across a road can be paired
	var table := {}
	for lot: CityLayout.Lot in layout.lots:
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var sx := 1 if lot.cx > bx else -1
		var sz := 1 if lot.cz > bz else -1
		table["%d,%d,%d,%d" % [lot.block_i, lot.block_j, sx, sz]] = lot
	var verts := PackedVector3Array()
	var tans := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := CityLayout.N
	cable_count = 0
	for k in range(1, n):                # inner roads only
		for i in n:
			for q in [-1, 1]:
				# road along x at z = c_k: lots north (block row k-1, sz=+1) and south (row k, sz=-1), same column i and quadrant q
				var a: CityLayout.Lot = table.get("%d,%d,%d,%d" % [i, k - 1, q, 1])
				var b: CityLayout.Lot = table.get("%d,%d,%d,%d" % [i, k, q, -1])
				if a != null and b != null and rng.randf() < 0.75:
					var x0 := maxf(a.rect.position.x, b.rect.position.x) + 1.5
					var x1 := minf(a.rect.end.x, b.rect.end.x) - 1.5
					if x1 > x0:
						_span(verts, tans, uvs, idx, Vector3(0, 0, a.rect.end.y), Vector3(0, 0, b.rect.position.y), rng.randf_range(x0, x1), 0, rng)
				# road along z at x = c_k: lots west (block col k-1, sx=+1) and east (col k, sx=-1)
				var c: CityLayout.Lot = table.get("%d,%d,%d,%d" % [k - 1, i, 1, q])
				var d: CityLayout.Lot = table.get("%d,%d,%d,%d" % [k, i, -1, q])
				if c != null and d != null and rng.randf() < 0.75:
					var z0 := maxf(c.rect.position.y, d.rect.position.y) + 1.5
					var z1 := minf(c.rect.end.y, d.rect.end.y) - 1.5
					if z1 > z0:
						_span(verts, tans, uvs, idx, Vector3(c.rect.end.x, 0, 0), Vector3(d.rect.position.x, 0, 0), rng.randf_range(z0, z1), 1, rng)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = tans
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	cable_mesh = ArrayMesh.new()
	cable_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	cable_mesh.custom_aabb = AABB(Vector3(-400, 0, -400), Vector3(800, 20, 800))


## One span of 2-3 parallel wires between two facing walls. axis 0: wall points differ in z (x given), axis 1: differ in x (z given).
func _span(verts: PackedVector3Array, tans: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array, pa: Vector3, pb: Vector3,
		along: float, axis: int, rng: RandomNumberGenerator) -> void:
	var wires := rng.randi_range(2, 3)
	var y0 := rng.randf_range(6.0, 11.0)
	var y1 := y0 + rng.randf_range(-1.2, 1.2)
	var sag := rng.randf_range(0.8, 1.8)
	for w in wires:
		var off := (float(w) - float(wires - 1) * 0.5) * 0.28
		var a := pa
		var b := pb
		if axis == 0:
			a.x = along + off
			b.x = along + off
		else:
			a.z = along + off
			b.z = along + off
		a.y = y0 + float(w) * 0.12
		b.y = y1 + float(w) * 0.12
		var segs := 8
		var base := verts.size()
		var prev := Vector3.ZERO
		for s in segs + 1:
			var t := float(s) / float(segs)
			var p := a.lerp(b, t)
			p.y -= sag * 4.0 * t * (1.0 - t) * (1.0 + 0.1 * float(w))
			var t2 := minf(1.0, t + 0.05)
			var p2 := a.lerp(b, t2)
			p2.y -= sag * 4.0 * t2 * (1.0 - t2) * (1.0 + 0.1 * float(w))
			var tp := (p2 - p)
			if tp.length() < 0.0001:
				tp = (p - prev)
			tp = tp.normalized()
			verts.append(p)
			tans.append(tp)
			uvs.append(Vector2(-1.0, t))
			verts.append(p)
			tans.append(tp)
			uvs.append(Vector2(1.0, t))
			prev = p
		for s in segs:
			var i0 := base + s * 2
			idx.append_array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2])


# --- steam ----------------------------------------------------------------------------------------------------------------

func _build_steam(vents: Array[Vector3], rng: RandomNumberGenerator) -> void:
	if vents.is_empty():
		return
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, q.get_mesh_arrays())
	var count := vents.size() * PUFFS_PER_VENT
	steam_mm = MB.new_multimesh(mesh, count, false, true)
	var buf := MB.new_buffer(count, false, true)
	var seeds: Array[float] = []
	var neons: Array[float] = []
	for v in vents:
		seeds.append(rng.randf())
		neons.append(float(rng.randi() % 4))
	var i := 0
	for k in PUFFS_PER_VENT:                 # puff-major: the first N instances hold the first puffs of every vent
		for j in vents.size():
			MB.write_instance(buf, i, Transform3D(Basis.IDENTITY, vents[j] + Vector3(0, 0.1, 0)), false, Color.WHITE, true,
					Color(float(k) / float(PUFFS_PER_VENT), seeds[j] + float(k) * 0.137, 0.8 + 0.4 * seeds[j], neons[j]))
			i += 1
	steam_mm.buffer = buf


# --- holograms ---------------------------------------------------------------------------------------------------------------

func _build_holograms(buildings: Array, rng: RandomNumberGenerator) -> void:
	var picks: Array = []
	for b in buildings:
		if b.lot.h >= 62.0 and rng.randf() < 0.30:
			picks.append(b)
	if picks.is_empty():
		return
	var mb := MB.new()
	mb.funnel(Vector3(0, 17.0, 0), 0.0, 3.6, 18, 3.0, Color(1, 1, 1, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mb.verts
	arrays[Mesh.ARRAY_NORMAL] = mb.norms
	arrays[Mesh.ARRAY_TEX_UV] = mb.uvs
	arrays[Mesh.ARRAY_INDEX] = mb.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	hologram_mm = MB.new_multimesh(mesh, picks.size(), false, true)
	var buf := MB.new_buffer(picks.size(), false, true)
	for k in picks.size():
		var b = picks[k]
		var lot: CityLayout.Lot = b.lot
		var tp: Array = BM.top_part(b.cls)
		var cx: float = lot.cx + (tp[0] + tp[1]) * 0.5 * lot.w
		var cz: float = lot.cz + (tp[2] + tp[3]) * 0.5 * lot.d
		MB.write_instance(buf, k, Transform3D(Basis.IDENTITY, Vector3(cx, lot.h + 0.5, cz)), false, Color.WHITE, true,
				Color(rng.randf(), float(rng.randi() % 4), 1.0, 0.0))
	hologram_mm.buffer = buf
