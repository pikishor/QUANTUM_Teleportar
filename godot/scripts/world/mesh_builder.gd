extends RefCounted
## Tiny procedural mesh builder for the world module: flat-shaded quads, boxes, cylinders and cones with optional
## vertex colour, UV and UV2. Front faces are clockwise (Godot convention); quad() orients itself from the wanted normal,
## so callers only need to list the corners in any consistent order.
##
## Also hosts the MultiMesh helpers (bulk buffer writes, no per-instance GDScript calls into the engine).

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()

## Defaults applied to vertices that do not pass their own values.
var color := Color(1, 1, 1, 0)
var uv := Vector2.ZERO
var uv2 := Vector2.ZERO


func vertex(p: Vector3, n: Vector3, c: Color = color, u: Vector2 = uv, u2: Vector2 = uv2) -> int:
	verts.append(p)
	norms.append(n)
	cols.append(c)
	uvs.append(u)
	uv2s.append(u2)
	return verts.size() - 1


func tri(a: int, b: int, c: int) -> void:
	idx.append(a)
	idx.append(b)
	idx.append(c)


## Quad from four corners (any winding), facing `n`. uv/uv2 are shared by the four vertices unless uv_corners is given.
func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color = color, u: Vector2 = uv, u2: Vector2 = uv2,
		uv_corners: PackedVector2Array = PackedVector2Array()) -> void:
	var has_uv := uv_corners.size() == 4
	var i0 := vertex(p0, n, c, uv_corners[0] if has_uv else u, u2)
	var i1 := vertex(p1, n, c, uv_corners[1] if has_uv else u, u2)
	var i2 := vertex(p2, n, c, uv_corners[2] if has_uv else u, u2)
	var i3 := vertex(p3, n, c, uv_corners[3] if has_uv else u, u2)
	var geo := (p1 - p0).cross(p2 - p0)
	if geo.dot(n) > 0.0:       # counter-clockwise seen from n: flip to clockwise
		tri(i0, i2, i1)
		tri(i0, i3, i2)
	else:
		tri(i0, i1, i2)
		tri(i0, i2, i3)


## Axis-aligned box with all six faces (or without the bottom).
func box(center: Vector3, size: Vector3, c: Color = color, bottom := true, u2: Vector2 = uv2) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	quad(Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.RIGHT, c, uv, u2)
	quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.LEFT, c, uv, u2)
	quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.UP, c, uv, u2)
	quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, c, uv, u2)
	quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD, c, uv, u2)
	if bottom:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, c, uv, u2)


## Box rotated about Y (yaw, radians) around its own centre.
func box_yaw(center: Vector3, size: Vector3, yaw: float, c: Color = color, bottom := true) -> void:
	var start := verts.size()
	box(Vector3.ZERO, size, c, bottom)
	var b := Basis(Vector3.UP, yaw)
	for i in range(start, verts.size()):
		verts[i] = b * verts[i] + center
		norms[i] = b * norms[i]


## Box between two arbitrary points with a square cross-section (struts, rails, cables, braces).
func strut(a: Vector3, b: Vector3, thickness: float, c: Color = color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var start := verts.size()
	box(Vector3.ZERO, Vector3(thickness, thickness, length), c)
	var dir := d / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	var mid := (a + b) * 0.5
	for i in range(start, verts.size()):
		verts[i] = basis * verts[i] + mid
		norms[i] = basis * norms[i]


## Upright cylinder (or frustum when top_radius differs), smooth side normals, flat caps.
func cylinder(base: Vector3, radius: float, height: float, segments := 12, c: Color = color, top_radius := -1.0,
		cap_top := true, cap_bottom := false) -> void:
	var tr := radius if top_radius < 0.0 else top_radius
	var ring_a: PackedInt32Array = []
	var ring_b: PackedInt32Array = []
	var slope := (radius - tr) / maxf(height, 0.0001)
	for s in segments + 1:
		var a := TAU * float(s) / float(segments)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var n := Vector3(dir.x, slope, dir.z).normalized()
		ring_a.append(vertex(base + dir * radius, n, c))
		ring_b.append(vertex(base + Vector3(0, height, 0) + dir * tr, n, c))
	for s in segments:
		# two triangles per segment, clockwise seen from outside
		tri(ring_a[s], ring_b[s + 1], ring_b[s])
		tri(ring_a[s], ring_a[s + 1], ring_b[s + 1])
	if cap_top and tr > 0.0:
		_cap(base + Vector3(0, height, 0), tr, segments, c, true)
	if cap_bottom:
		_cap(base, radius, segments, c, false)


func _cap(center: Vector3, radius: float, segments: int, c: Color, up: bool) -> void:
	var n := Vector3.UP if up else Vector3.DOWN
	var ci := vertex(center, n, c)
	var ring: PackedInt32Array = []
	for s in segments + 1:
		var a := TAU * float(s) / float(segments)
		ring.append(vertex(center + Vector3(cos(a), 0.0, sin(a)) * radius, n, c))
	for s in segments:
		if up:
			tri(ci, ring[s], ring[s + 1])
		else:
			tri(ci, ring[s + 1], ring[s])


## Open cone / funnel from a small top ring to a wide bottom ring (used for light shafts). UV.y = 0 at the apex, 1 at the base.
func funnel(apex: Vector3, base_y: float, base_radius: float, segments := 12, apex_radius := 0.05, c: Color = color) -> void:
	var ring_a: PackedInt32Array = []
	var ring_b: PackedInt32Array = []
	for s in segments + 1:
		var a := TAU * float(s) / float(segments)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var n := Vector3(dir.x, 0.3, dir.z).normalized()
		ring_a.append(vertex(Vector3(apex.x, base_y, apex.z) + dir * base_radius, n, c, Vector2(float(s) / segments, 1.0)))
		ring_b.append(vertex(apex + dir * apex_radius, n, c, Vector2(float(s) / segments, 0.0)))
	for s in segments:
		tri(ring_a[s], ring_b[s + 1], ring_b[s])
		tri(ring_a[s], ring_a[s + 1], ring_b[s + 1])


## Ellipsoid with smooth normals (rubbish bags, foliage, domes).
func sphere(center: Vector3, radii: Vector3, segments := 8, rings := 5, c: Color = color) -> void:
	var grid: Array = []
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		var row: PackedInt32Array = []
		for s in segments + 1:
			var th := TAU * float(s) / float(segments)
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var nn := Vector3(n.x / radii.x, n.y / radii.y, n.z / radii.z).normalized()
			row.append(vertex(center + n * radii, nn, c))
		grid.append(row)
	for r in rings:
		for s in segments:
			var v00: int = grid[r][s]
			var v01: int = grid[r][s + 1]
			var v10: int = grid[r + 1][s]
			var v11: int = grid[r + 1][s + 1]
			tri(v00, v10, v11)
			tri(v00, v11, v01)


## Extrude a convex 2D profile (x, y pairs, listed counter-clockwise seen from +Z) along Z from z0 to z1 (jersey barriers, curbs).
func prism(profile: PackedVector2Array, z0: float, z1: float, c: Color = color) -> void:
	var n := profile.size()
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var edge := b - a
		var nrm := Vector3(edge.y, -edge.x, 0.0).normalized()
		quad(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), nrm, c)
	# caps (fan)
	for i in range(1, n - 1):
		quad(Vector3(profile[0].x, profile[0].y, z1), Vector3(profile[i].x, profile[i].y, z1), Vector3(profile[i + 1].x, profile[i + 1].y, z1),
				Vector3(profile[i + 1].x, profile[i + 1].y, z1), Vector3.BACK, c)
		quad(Vector3(profile[0].x, profile[0].y, z0), Vector3(profile[i + 1].x, profile[i + 1].y, z0), Vector3(profile[i].x, profile[i].y, z0),
				Vector3(profile[i].x, profile[i].y, z0), Vector3.FORWARD, c)


func is_empty() -> bool:
	return verts.is_empty()


func build(material: Material = null, use_uv2 := false, use_colors := true) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if use_uv2:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if use_colors:
		arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(0, material)
	return mesh


# --- MultiMesh helpers -----------------------------------------------------------------------------------------------

## Floats per instance for a MultiMesh with the given optional channels (3D transform = 12 floats).
static func stride(use_colors: bool, use_custom: bool) -> int:
	return 12 + (4 if use_colors else 0) + (4 if use_custom else 0)


## Create a MultiMesh sized for `count` instances; fill it with write_instance() into a buffer, then commit_buffer().
static func new_multimesh(mesh: Mesh, count: int, use_colors := false, use_custom := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.use_custom_data = use_custom
	mm.mesh = mesh
	mm.instance_count = count
	return mm


static func new_buffer(count: int, use_colors := false, use_custom := false) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(count * stride(use_colors, use_custom))
	return buf


## Write instance `i` into a buffer made by new_buffer() (same channel flags!). The transform is row-major 3x4.
static func write_instance(buf: PackedFloat32Array, i: int, xf: Transform3D, use_colors := false, col := Color.WHITE,
		use_custom := false, custom := Color.BLACK) -> void:
	var o := i * stride(use_colors, use_custom)
	var b := xf.basis
	var p := xf.origin
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = p.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = p.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = p.z
	o += 12
	if use_colors:
		buf[o] = col.r
		buf[o + 1] = col.g
		buf[o + 2] = col.b
		buf[o + 3] = col.a
		o += 4
	if use_custom:
		buf[o] = custom.r
		buf[o + 1] = custom.g
		buf[o + 2] = custom.b
		buf[o + 3] = custom.a
