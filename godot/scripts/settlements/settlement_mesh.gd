class_name SettlementMesh
extends RefCounted
## The vertex-colour mesh builder of the towns (wave 112). Everything a town is made of ends up as arrays in this layout (assets/shaders/settlement.gdshader reads it):
##   COLOR.rgb = the paint (wall colour, trim colour for a window frame, ...), COLOR.a = material code / 16 (see CODE_*), UV = metres on the face (u along the first edge, v up or along the slope: the shader
##   draws siding boards, bricks, tiles, planks and window panes from it), UV2.x = baked ambient occlusion (1 open, 0.55 in a corner or at the foot of a wall), UV2.y = a free parameter of the material
##   (a window's glow chance, a street's width, a fence's board count).
## Faces are corner lists p0 (bottom left) p1 (bottom right) p2 (top right) p3 (top left) seen from OUTSIDE; the normal is (p1 - p0) x (p3 - p0). Front faces are clockwise (Godot).
## A builder builds one part in its own frame (origin on the ground, front is -Z); `append(src, xf)` copies a finished part into another builder with a transform (towns place a handful of cached
## variants hundreds of times, so a house costs one pass over its vertices, not one pass of GDScript geometry code).

const PAINT := 0              ## plain painted plaster, smooth (the shader adds grime at the foot)
const SIDING := 1             ## horizontal boards
const BRICK := 2
const STONE := 3
const LOG := 4
const TILE := 5               ## clay roof tiles
const SHINGLE := 6            ## slate / wood / asphalt shingles
const SHEET := 7              ## corrugated sheet (roofs, sheds, containers)
const GLASS := 8              ## a window pane with its frame (UV 0..1 across the pane, COLOR.rgb = the frame paint)
const WOOD := 9               ## door, deck, fence post, planks
const CONCRETE := 10          ## pavement, kerb, sidewalk joints
const LAWN := 11              ## grass, crops (UV2.y = 1 crop rows)
const DIRT := 12
const METAL := 13             ## painted steel: silos, tanks, masts, containers
const ADOBE := 14             ## rough plaster
const GLOW := 15              ## lamp bulbs, lit signs
const ASPHALT := 16           ## side streets
const PICKET := 17            ## fence boards with gaps (the shader cuts them)
const LEAF := 18              ## hedges, tree crowns (colour noise)
const WATER := 19             ## a pool
const AWNING := 20            ## a shop awning (stripes)
const CODE_SCALE := 21.0

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var idx := PackedInt32Array()


static func col(base: Color, code: int) -> Color:
	return Color(base.r, base.g, base.b, float(code) / CODE_SCALE)


func vcount() -> int:
	return v.size()


func tris() -> int:
	return idx.size() / 3


func is_empty() -> bool:
	return v.is_empty()


## One face. `ao` darkens the whole face, `ao_bottom` the bottom edge only (walls meeting the ground), `uv_origin` offsets the UV, `p` is the material parameter.
func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, base: Color, code: int, ao := 1.0, ao_bottom := 1.0, uv_origin := Vector2.ZERO, p := 0.0, nrm := Vector3.ZERO, unit_uv := false) -> void:
	var e01 := p1 - p0
	var e03 := p3 - p0
	var nn := nrm if nrm != Vector3.ZERO else e01.cross(e03).normalized()
	if nn.length_squared() < 0.0001:
		return
	var cc := col(base, code)
	var lu := e01.length()
	var lv := e03.length()
	var i0 := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	v.append(p3)
	for k in 4:
		n.append(nn)
		c.append(cc)
	if unit_uv:                                                  # a window pane: UV 0..1 across it
		uv.append(Vector2(0.0, 0.0))
		uv.append(Vector2(1.0, 0.0))
		uv.append(Vector2(1.0, 1.0))
		uv.append(Vector2(0.0, 1.0))
	else:
		uv.append(uv_origin)
		uv.append(uv_origin + Vector2(lu, 0.0))
		uv.append(uv_origin + Vector2(lu, lv))
		uv.append(uv_origin + Vector2(0.0, lv))
	uv2.append(Vector2(ao * ao_bottom, p))
	uv2.append(Vector2(ao * ao_bottom, p))
	uv2.append(Vector2(ao, p))
	uv2.append(Vector2(ao, p))
	idx.append(i0)
	idx.append(i0 + 3)
	idx.append(i0 + 2)
	idx.append(i0)
	idx.append(i0 + 2)
	idx.append(i0 + 1)


## A triangle (a gable end): p0 p1 on the base, p2 the apex, seen from outside.
func tri(p0: Vector3, p1: Vector3, p2: Vector3, base: Color, code: int, ao := 1.0, ao_bottom := 1.0, uv_origin := Vector2.ZERO, p := 0.0) -> void:
	var nn := (p1 - p0).cross(p2 - p0).normalized()
	if nn.length_squared() < 0.0001:
		return
	var cc := col(base, code)
	var lu := (p1 - p0).length()
	var i0 := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	for k in 3:
		n.append(nn)
		c.append(cc)
	uv.append(uv_origin)
	uv.append(uv_origin + Vector2(lu, 0.0))
	var apex_u := (p2 - p0).dot((p1 - p0).normalized())
	uv.append(uv_origin + Vector2(apex_u, p2.y - p0.y))
	uv2.append(Vector2(ao * ao_bottom, p))
	uv2.append(Vector2(ao * ao_bottom, p))
	uv2.append(Vector2(ao, p))
	idx.append(i0)
	idx.append(i0 + 2)
	idx.append(i0 + 1)


## Axis aligned box: faces as `skip` bits (1 +X, 2 -X, 4 top, 8 +Z, 16 -Z, 32 bottom) left out. `ao_foot` darkens the lower part of the side faces (a wall meeting the ground).
func box(centre: Vector3, size: Vector3, base: Color, code: int, skip := 32, ao := 1.0, ao_foot := 1.0, p := 0.0) -> void:
	var h := size * 0.5
	var x0 := centre.x - h.x
	var x1 := centre.x + h.x
	var y0 := centre.y - h.y
	var y1 := centre.y + h.y
	var z0 := centre.z - h.z
	var z1 := centre.z + h.z
	var top_col := base
	if skip & 1 == 0:
		quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), base, code, ao, ao_foot, Vector2.ZERO, p)
	if skip & 2 == 0:
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), base, code, ao, ao_foot, Vector2.ZERO, p)
	if skip & 4 == 0:
		quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), top_col, code, ao, 1.0, Vector2.ZERO, p)
	if skip & 8 == 0:
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), base, code, ao, ao_foot, Vector2.ZERO, p)
	if skip & 16 == 0:
		quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), base, code, ao, ao_foot, Vector2.ZERO, p)
	if skip & 32 == 0:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), base, code, ao * 0.6, 1.0, Vector2.ZERO, p)


## A box with its base on `base_pos` (footprint centred), rotated by `yaw` about Y.
func box_at(base_pos: Vector3, size: Vector3, yaw: float, base: Color, code: int, skip := 32, ao := 1.0, ao_foot := 1.0, p := 0.0) -> void:
	var s := v.size()
	box(Vector3(0.0, size.y * 0.5, 0.0), size, base, code, skip, ao, ao_foot, p)
	if absf(yaw) > 0.0001 or base_pos != Vector3.ZERO:
		transform_from(s, Transform3D(Basis(Vector3.UP, yaw), base_pos))


## Upright cylinder with a flat top (and optionally a cone / dome cap by the caller): UV u = metres round the circumference, v = height.
func cylinder(base_pos: Vector3, radius: float, height: float, segs: int, base: Color, code: int, top_radius := -1.0, cap := true, ao := 1.0, ao_foot := 1.0, p := 0.0) -> void:
	var tr := radius if top_radius < 0.0 else top_radius
	var slope := (radius - tr) / maxf(height, 0.001)
	var i0 := v.size()
	for s in segs + 1:
		var a := TAU * float(s) / float(segs)
		var d := Vector3(cos(a), 0.0, sin(a))
		var nn := Vector3(d.x, slope, d.z).normalized()
		var u := TAU * radius * float(s) / float(segs)
		v.append(base_pos + d * radius)
		n.append(nn)
		c.append(col(base, code))
		uv.append(Vector2(u, 0.0))
		uv2.append(Vector2(ao * ao_foot, p))
		v.append(base_pos + Vector3(0.0, height, 0.0) + d * tr)
		n.append(nn)
		c.append(col(base, code))
		uv.append(Vector2(u, height))
		uv2.append(Vector2(ao, p))
	for s in segs:
		var a0 := i0 + s * 2
		var a1 := i0 + s * 2 + 1
		var b0 := i0 + s * 2 + 2
		var b1 := i0 + s * 2 + 3
		idx.append(a0)
		idx.append(b1)
		idx.append(a1)
		idx.append(a0)
		idx.append(b0)
		idx.append(b1)
	if cap and tr > 0.001:
		var ci := v.size()
		v.append(base_pos + Vector3(0.0, height, 0.0))
		n.append(Vector3.UP)
		c.append(col(base, code))
		uv.append(Vector2.ZERO)
		uv2.append(Vector2(ao, p))
		for s in segs:
			var a := TAU * float(s) / float(segs)
			v.append(base_pos + Vector3(0.0, height, 0.0) + Vector3(cos(a), 0.0, sin(a)) * tr)
			n.append(Vector3.UP)
			c.append(col(base, code))
			uv.append(Vector2(cos(a) * tr, sin(a) * tr))
			uv2.append(Vector2(ao, p))
		for s in segs:
			idx.append(ci)
			idx.append(ci + 1 + s)
			idx.append(ci + 1 + (s + 1) % segs)


## A slanted tube (a palm trunk, a pole, a strut with a round section) from p0 (radius r0) to p1 (radius r1).
func tube(p0: Vector3, p1: Vector3, r0: float, r1: float, segs: int, base: Color, code: int, ao := 1.0, ao_foot := 1.0, p := 0.0) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.001:
		return
	var a := axis / length
	var ref := Vector3.UP if absf(a.y) < 0.95 else Vector3.RIGHT
	var ux := a.cross(ref).normalized()
	var uz := a.cross(ux).normalized()
	var i0 := v.size()
	for s in segs + 1:
		var ang := TAU * float(s) / float(segs)
		var d := ux * cos(ang) + uz * sin(ang)
		var u := TAU * r0 * float(s) / float(segs)
		v.append(p0 + d * r0)
		n.append(d)
		c.append(col(base, code))
		uv.append(Vector2(u, 0.0))
		uv2.append(Vector2(ao * ao_foot, p))
		v.append(p1 + d * r1)
		n.append(d)
		c.append(col(base, code))
		uv.append(Vector2(u, length))
		uv2.append(Vector2(ao, p))
	for s in segs:
		var a0 := i0 + s * 2
		var a1 := i0 + s * 2 + 1
		var b0 := i0 + s * 2 + 2
		var b1 := i0 + s * 2 + 3
		# the ring runs counter-clockwise round the axis (ux -> uz): from outside it runs to the viewer's right, the opposite of cylinder()'s
		idx.append(a0)
		idx.append(a1)
		idx.append(b1)
		idx.append(a0)
		idx.append(b1)
		idx.append(b0)


## A cone / pointed roof of a tower: base ring at `base_pos`, apex `height` above.
func cone(base_pos: Vector3, radius: float, height: float, segs: int, base: Color, code: int, ao := 1.0, p := 0.0, offset := Vector2.ZERO) -> void:
	var i0 := v.size()
	var slope := radius / maxf(height, 0.001)
	for s in segs + 1:
		var a := TAU * float(s) / float(segs)
		var d := Vector3(cos(a), 0.0, sin(a))
		var nn := Vector3(d.x, slope, d.z).normalized()
		var u := TAU * radius * float(s) / float(segs)
		v.append(base_pos + d * radius)
		n.append(nn)
		c.append(col(base, code))
		uv.append(Vector2(u, 0.0))
		uv2.append(Vector2(ao, p))
		v.append(base_pos + Vector3(offset.x, height, offset.y))
		n.append(nn)
		c.append(col(base, code))
		uv.append(Vector2(u, sqrt(radius * radius + height * height)))
		uv2.append(Vector2(ao, p))
	for s in segs:
		var a0 := i0 + s * 2
		var a1 := i0 + s * 2 + 1
		var b0 := i0 + s * 2 + 2
		idx.append(a0)
		idx.append(b0)
		idx.append(a1)


## A smooth blob (tree crown, bush, dome): an ellipsoid of `segs` x `rings` with colour noise by the caller's colour. UV in metres on the surface.
func blob(centre: Vector3, radii: Vector3, segs: int, rings: int, base: Color, code: int, ao := 1.0, p := 0.0, squash_bottom := 1.0) -> void:
	var i0 := v.size()
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		for s in segs + 1:
			var th := TAU * float(s) / float(segs)
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var pos := centre + Vector3(d.x * radii.x, d.y * radii.y * (squash_bottom if d.y < 0.0 else 1.0), d.z * radii.z)
			var nn := Vector3(d.x / radii.x, d.y / radii.y, d.z / radii.z).normalized()
			v.append(pos)
			n.append(nn)
			c.append(col(base, code))
			uv.append(Vector2(float(s) / float(segs) * TAU * radii.x, float(r) / float(rings) * PI * radii.y))
			uv2.append(Vector2(ao * (0.72 + 0.28 * clampf(d.y * 0.5 + 0.5, 0.0, 1.0)), p))
	for r in rings:
		for s in segs:
			var a := i0 + r * (segs + 1) + s
			var b := a + segs + 1
			idx.append(a)
			idx.append(b)
			idx.append(b + 1)
			idx.append(a)
			idx.append(b + 1)
			idx.append(a + 1)


## Transform every vertex added since `from_vertex` (build a part where it is easy, then place it).
func transform_from(from_vertex: int, xf: Transform3D) -> void:
	for i in range(from_vertex, v.size()):
		v[i] = xf * v[i]
		n[i] = (xf.basis * n[i]).normalized()


## Copy `src` into this builder with `xf` applied (positions and normals); `tint` multiplies the colour's rgb of the faces of the given codes (mask bit per code), `ao_mul` darkens.
func append(src: SettlementMesh, xf: Transform3D) -> void:
	var base := v.size()
	var cnt := src.v.size()
	var b := xf.basis
	var o := xf.origin
	v.resize(base + cnt)
	n.resize(base + cnt)
	var sv := src.v
	var sn := src.n
	for i in cnt:
		v[base + i] = b * sv[i] + o
		n[base + i] = b * sn[i]
	c.append_array(src.c)
	uv.append_array(src.uv)
	uv2.append_array(src.uv2)
	var si := src.idx
	var ic := si.size()
	var old := idx.size()
	idx.resize(old + ic)
	for i in ic:
		idx[old + i] = si[i] + base


func to_mesh(material: Material = null) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh
