class_name AlienMesh
extends RefCounted
## A tiny mesh builder for the procedural alien bodies and sites (wave 107b): lofted tubes, ellipsoids, cones, boxes and discs collected into ONE ArrayMesh with vertex colours
## (rgb = paint, a = the glow mask that assets/shaders/alien.gdshader turns into light). No textures, no per-part nodes: a creature or a site is one surface and one draw call.
## Everything is built at final size in metres, facing -Z, standing on y = 0.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var i := PackedInt32Array()


func tris() -> int:
	return i.size() / 3


## A colour given with three components (alpha 1.0) is plain paint: the glow mask is the alpha BELOW 1.0 (0.99 = full glow).
func _push(p: Vector3, nm: Vector3, col: Color) -> int:
	if col.a >= 0.999:
		col.a = 0.0
	v.append(p)
	n.append(nm)
	c.append(col)
	return v.size() - 1


## A tube along `path` (Array of Vector3, at least 2 points). `radii` and `cols` have one entry per path point (a Color alpha is the glow mask). `sides` >= 3.
## `cap_end` closes the far end with a point at its tip (a rounded tip when `tip` > 0: the path's last direction, `tip` metres long), `cap_start` closes the first ring flat.
func tube(path: Array, radii: Array, cols: Array, sides := 8, cap_start := false, cap_end := true, tip := 0.0) -> void:
	var cnt := path.size()
	if cnt < 2:
		return
	# parallel transport frames
	var t0: Vector3 = ((path[1] as Vector3) - (path[0] as Vector3)).normalized()
	var ref := Vector3.RIGHT if absf(t0.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
	var nrm := (ref - t0 * ref.dot(t0)).normalized()
	var base := v.size()
	var last_t := t0
	for k in cnt:
		var tk: Vector3
		if k == 0:
			tk = t0
		elif k == cnt - 1:
			tk = ((path[k] as Vector3) - (path[k - 1] as Vector3)).normalized()
		else:
			tk = ((path[k + 1] as Vector3) - (path[k - 1] as Vector3)).normalized()
		if k > 0:
			nrm = (nrm - tk * nrm.dot(tk))
			if nrm.length() < 0.001:
				nrm = Vector3.UP.cross(tk).normalized()
			nrm = nrm.normalized()
		var bin := tk.cross(nrm).normalized()
		last_t = tk
		var r: float = float(radii[k])
		var col: Color = cols[k]
		for s in sides:
			var a := TAU * float(s) / float(sides)
			var off := nrm * cos(a) + bin * sin(a)
			_push((path[k] as Vector3) + off * r, off, col)
	for k in cnt - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a0 := base + k * sides + s
			var a1 := base + k * sides + s2
			var b0 := base + (k + 1) * sides + s
			var b1 := base + (k + 1) * sides + s2
			i.append_array([a0, b0, a1, a1, b0, b1])
	if cap_start:
		var ctr := _push(path[0] as Vector3, -t0, cols[0])
		for s in sides:
			i.append_array([ctr, base + (s + 1) % sides, base + s])
	if cap_end:
		var lastp: Vector3 = path[cnt - 1]
		var ctr2 := _push(lastp + last_t * tip, last_t, cols[cnt - 1])
		var ring := base + (cnt - 1) * sides
		for s in sides:
			i.append_array([ctr2, ring + s, ring + (s + 1) % sides])


## An ellipsoid (a lumpy body, a head, an egg) with semi-axes `rad`, rotated by `rot`, `lat` rings by `lon` segments.
func ellipsoid(center: Vector3, rad: Vector3, col: Color, lat := 5, lon := 8, rot := Basis.IDENTITY, col_top := Color(0, 0, 0, -1)) -> void:
	var base := v.size()
	var cb := col_top if col_top.a >= 0.0 else col
	for a in lat + 1:
		var phi := PI * float(a) / float(lat)
		var y := cos(phi)
		var rr := sin(phi)
		var cc := col.lerp(cb, 1.0 - (y * 0.5 + 0.5)) if col_top.a >= 0.0 else col
		cc.a = col.a
		for b in lon:
			var th := TAU * float(b) / float(lon)
			var u := Vector3(rr * cos(th), y, rr * sin(th))
			var nm := (rot * Vector3(u.x / maxf(rad.x, 0.001), u.y / maxf(rad.y, 0.001), u.z / maxf(rad.z, 0.001))).normalized()
			_push(center + rot * (u * rad), nm, cc)
	for a in lat:
		for b in lon:
			var b2 := (b + 1) % lon
			var a0 := base + a * lon + b
			var a1 := base + a * lon + b2
			var b0 := base + (a + 1) * lon + b
			var b1 := base + (a + 1) * lon + b2
			i.append_array([a0, a1, b0, a1, b1, b0])


## A cone / spike from `base_c` to `tip` with base radius `r` (a bone, a thorn, a tooth, a tent).
func cone(base_c: Vector3, tip: Vector3, r: float, col: Color, sides := 5, tip_col := Color(0, 0, 0, -1)) -> void:
	var d := tip - base_c
	var len := d.length()
	if len < 0.0001:
		return
	var t := d / len
	var ref := Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
	var a := t.cross(ref).normalized()
	var b := t.cross(a).normalized()
	var base := v.size()
	var tc := tip_col if tip_col.a >= 0.0 else col
	for s in sides:
		var ang := TAU * float(s) / float(sides)
		var off := a * cos(ang) + b * sin(ang)
		_push(base_c + off * r, (off + t * (r / len)).normalized(), col)
	var ti := _push(tip, t, tc)
	for s in sides:
		i.append_array([base + s, ti, base + (s + 1) % sides])
	var ctr := _push(base_c, -t, col)
	for s in sides:
		i.append_array([ctr, base + s, base + (s + 1) % sides])


## An oriented box (crates, slabs, fence posts).
func box(center: Vector3, size: Vector3, col: Color, rot := Basis.IDENTITY, col_top := Color(0, 0, 0, -1)) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	for f in faces:
		var nm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var w: Vector3 = f[2]
		var base := v.size()
		var fc := col
		if col_top.a >= 0.0 and nm.y > 0.5:
			fc = col_top
			fc.a = col.a
		for k in 4:
			var su := -1.0 if (k == 0 or k == 3) else 1.0
			var sw := -1.0 if (k == 0 or k == 1) else 1.0
			var p := nm * _hv(nm, h) + u * su * _hv(u, h) + w * sw * _hv(w, h)
			_push(center + rot * p, rot * nm, fc)
		i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


static func _hv(axis: Vector3, h: Vector3) -> float:
	return h.x * absf(axis.x) + h.y * absf(axis.y) + h.z * absf(axis.z)


## A flat disc / dome base (a platform, a crater rim) lying on y: radius `r` at height `y`, `sides` sides, optional `inner` hole radius.
func disc(center: Vector3, r: float, col: Color, sides := 10, inner := 0.0, up := true) -> void:
	var base := v.size()
	var nm := Vector3.UP if up else Vector3.DOWN
	if inner <= 0.001:
		var ctr := _push(center, nm, col)
		for s in sides:
			var a := TAU * float(s) / float(sides)
			_push(center + Vector3(cos(a), 0, sin(a)) * r, nm, col)
		for s in sides:
			if up:
				i.append_array([ctr, base + 1 + (s + 1) % sides, base + 1 + s])
			else:
				i.append_array([ctr, base + 1 + s, base + 1 + (s + 1) % sides])
	else:
		for s in sides:
			var a := TAU * float(s) / float(sides)
			_push(center + Vector3(cos(a), 0, sin(a)) * inner, nm, col)
			_push(center + Vector3(cos(a), 0, sin(a)) * r, nm, col)
		for s in sides:
			var s2 := (s + 1) % sides
			var a0 := base + s * 2
			var a1 := base + s * 2 + 1
			var b0 := base + s2 * 2
			var b1 := base + s2 * 2 + 1
			if up:
				i.append_array([a0, b0, a1, a1, b0, b1])
			else:
				i.append_array([a0, a1, b0, a1, b1, b0])


func commit() -> ArrayMesh:
	var m := ArrayMesh.new()
	if v.is_empty():
		return m
	# every triangle is wound to face the way its vertex normals point (Godot's front face is clockwise): the builders above do not have to get the winding right by hand
	var k := 0
	while k + 2 < i.size():
		var a := v[i[k]]
		var b := v[i[k + 1]]
		var d := v[i[k + 2]]
		var nn := n[i[k]] + n[i[k + 1]] + n[i[k + 2]]
		if (b - a).cross(d - a).dot(nn) > 0.0:
			var tmp := i[k + 1]
			i[k + 1] = i[k + 2]
			i[k + 2] = tmp
		k += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = i
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
