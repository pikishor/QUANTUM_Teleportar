class_name BridgeKit
extends RefCounted
## Meshes of the bridges (data: Bridges). Every bridge is TWO meshes and two draw calls: the STRUCTURE (deck slab with parapets, girders, piers, abutments, railings, towers and cables, one
## merged mesh with the vertex colour as paint and COLOR.a as the material code of harbour_kit.gdshader) and the ROAD SURFACE (a ribbon with the highway / track shader of the outskirts roads, so
## the deck has the same asphalt, lane marks and edge lines as the road it carries). Pure builders: nothing here touches the scene tree.
## Kit codes (COLOR.a * 8): 0 paint, 1 container, 2 concrete, 3 steel, 4 lamp, 5 asphalt, 6 cladding.

const MB := preload("res://scripts/world/mesh_builder.gd")
const KIT_SHADER := preload("res://assets/shaders/harbour_kit.gdshader")
const ROAD_SHADER := preload("res://assets/shaders/terrain_road.gdshader")
const SLAB := 1.1                                    ## deck slab thickness (m)
const CONCRETE := Color(0.62, 0.61, 0.58, 2.0 / 8.0)
const CONCRETE_DARK := Color(0.46, 0.46, 0.45, 2.0 / 8.0)
const STEEL := Color(0.5, 0.52, 0.55, 3.0 / 8.0)
const STEEL_RED := Color(0.72, 0.2, 0.14, 3.0 / 8.0)          ## the landmark's International-orange-like paint
const STEEL_DARK := Color(0.22, 0.24, 0.27, 3.0 / 8.0)
const LAMP := Color(1.0, 0.86, 0.55, 4.0 / 8.0)
const WOOD := Color(0.44, 0.32, 0.2, 0.0)
const BALLAST := Color(0.36, 0.34, 0.32, 2.0 / 8.0)

static var _kit_mat: ShaderMaterial
static var _road_mats := {}


static func kit_material() -> ShaderMaterial:
	if _kit_mat == null:
		_kit_mat = ShaderMaterial.new()
		_kit_mat.shader = KIT_SHADER
	return _kit_mat


static func road_material(kind: StringName) -> ShaderMaterial:
	var k := 1 if kind == &"track" else 0
	if not _road_mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = ROAD_SHADER
		m.set_shader_parameter(&"kind", k)
		m.render_priority = 2
		_road_mats[k] = m
	return _road_mats[k]


# --- frames and sweeps ---------------------------------------------------------------------------------------------------------------

## One frame per point of the centre line: the position, the unit tangent in the ground plane and the lateral axis.
static func frames(pts: PackedVector3Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		out.append({"p": pts[i], "t": t, "lat": Vector3(-t.z, 0.0, t.x)})
	return out


## Extrude a (lateral, dy) profile along the frames. `closed` joins the last point to the first. The outward normal of every edge is worked out from the polygon orientation.
static func sweep(mb: MB, fr: Array[Dictionary], profile: PackedVector2Array, col: Color, closed := true) -> void:
	var n := profile.size()
	var area := 0.0
	for k in n:
		var a := profile[k]
		var b := profile[(k + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var edges := n if closed else n - 1
	for i in fr.size() - 1:
		var f0: Dictionary = fr[i]
		var f1: Dictionary = fr[i + 1]
		for k in edges:
			var a := profile[k]
			var b := profile[(k + 1) % n]
			var e := b - a
			if e.length_squared() < 1.0e-8:
				continue
			var nn := Vector2(e.y, -e.x).normalized() * sgn
			var n3: Vector3 = (f0["lat"] as Vector3) * nn.x + Vector3.UP * nn.y
			var p00: Vector3 = (f0["p"] as Vector3) + (f0["lat"] as Vector3) * a.x + Vector3.UP * a.y
			var p01: Vector3 = (f0["p"] as Vector3) + (f0["lat"] as Vector3) * b.x + Vector3.UP * b.y
			var p10: Vector3 = (f1["p"] as Vector3) + (f1["lat"] as Vector3) * a.x + Vector3.UP * a.y
			var p11: Vector3 = (f1["p"] as Vector3) + (f1["lat"] as Vector3) * b.x + Vector3.UP * b.y
			mb.quad(p00, p01, p11, p10, n3, col)


static func _yaw(t: Vector3) -> float:
	return atan2(t.x, t.z)


## A box on the deck centre line at distance fraction along frame segment `i`, offset laterally: (position on the line at frame i, lateral offset, dy above the line).
static func _at(fr: Array[Dictionary], i: int, lat: float, dy: float) -> Vector3:
	var f: Dictionary = fr[i]
	return (f["p"] as Vector3) + (f["lat"] as Vector3) * lat + Vector3.UP * dy


## Resample the centre line every `step` metres (the deck follows the ramps and the arch exactly; long straight runs get a frame per step for the posts and piers).
static func resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var l := Vector2(b.x - a.x, b.z - a.z).length()
		var n := maxi(1, int(ceil(l / step)))
		for k in n:
			out.append(a.lerp(b, float(k) / float(n)))
	out.append(pts[pts.size() - 1])
	return out


# --- the road surface ----------------------------------------------------------------------------------------------------------------

## The carriageway ribbon: UV x across 0..1, UV y metres along, COLOR.r = width / 32 (terrain_road.gdshader), raised 6 cm over the deck line.
static func road_ribbon(b: Dictionary) -> ArrayMesh:
	var pts := resample(b["pts"], 10.0)
	var fr := frames(pts)
	var hw := float(b["road_w"]) * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var run := 0.0
	for i in fr.size():
		if i > 0:
			run += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		verts.append(_at(fr, i, hw, 0.06))
		verts.append(_at(fr, i, -hw, 0.06))
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		cols.append(Color(2.0 * hw / 32.0, 0.0, 0.0, 1.0))
		cols.append(Color(2.0 * hw / 32.0, 0.0, 0.0, 1.0))
		uvs.append(Vector2(0.0, run))
		uvs.append(Vector2(1.0, run))
		if i < fr.size() - 1:
			var k := i * 2
			idx.append_array(PackedInt32Array([k, k + 2, k + 1, k + 1, k + 2, k + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- the structures ------------------------------------------------------------------------------------------------------------------

static func structure(b: Dictionary) -> ArrayMesh:
	var mb := MB.new()
	match b["kind"]:
		&"suspension":
			_suspension(mb, b)
		&"foot":
			_foot(mb, b)
		&"rail":
			_rail(mb, b)
		_:
			_road(mb, b)
	return mb.build(kit_material())


## A road bridge: slab with kerbs and parapets, two steel girders, railing posts, piers every `piers` metres (two columns and a cap), abutments where the deck stands over a drop.
static func _road(mb: MB, b: Dictionary) -> void:
	var pts := resample(b["pts"], 8.0)
	var fr := frames(pts)
	var hw := float(b["w"]) * 0.5
	var rh := float(b["road_w"]) * 0.5
	var prof := PackedVector2Array([Vector2(-hw, -SLAB), Vector2(hw, -SLAB), Vector2(hw, 1.0), Vector2(hw - 0.45, 1.0), Vector2(hw - 0.45, 0.18), Vector2(rh, 0.18), Vector2(rh, 0.0),
		Vector2(-rh, 0.0), Vector2(-rh, 0.18), Vector2(-hw + 0.45, 0.18), Vector2(-hw + 0.45, 1.0), Vector2(-hw, 1.0)])
	sweep(mb, fr, prof, CONCRETE)
	if b["kind"] == &"road":
		for sx in [-1.0, 1.0]:                                                    # two girders under the slab
			sweep(mb, fr, PackedVector2Array([Vector2(sx * rh * 0.55 - 0.3, -SLAB), Vector2(sx * rh * 0.55 + 0.3, -SLAB), Vector2(sx * rh * 0.55 + 0.3, -SLAB - 0.9), Vector2(sx * rh * 0.55 - 0.3, -SLAB - 0.9)]), STEEL_DARK)
		_rail_posts(mb, fr, hw - 0.22, 1.0, 4.0, STEEL)
	else:
		_rail_posts(mb, fr, hw - 0.22, 1.0, 3.0, WOOD)
	_supports(mb, b, fr, SLAB + (0.9 if b["kind"] == &"road" else 0.0), hw, rh)


## Railing: a post every `gap` metres and a rail on top, both sides, at lateral +-`lat` from the deck line, `dy` above it.
static func _rail_posts(mb: MB, fr: Array[Dictionary], lat: float, dy: float, gap: float, col: Color) -> void:
	var run := 0.0
	var next := 0.0
	for i in fr.size() - 1:
		var l := Vector2(fr[i + 1]["p"].x - fr[i]["p"].x, fr[i + 1]["p"].z - fr[i]["p"].z).length()
		for sx in [-1.0, 1.0]:
			mb.strut(_at(fr, i, sx * lat, dy + 0.55), _at(fr, i + 1, sx * lat, dy + 0.55), 0.09, col, false)
		while next <= run + l:
			var u := clampf((next - run) / maxf(l, 0.01), 0.0, 1.0)
			for sx in [-1.0, 1.0]:
				var base := _at(fr, i, sx * lat, dy).lerp(_at(fr, i + 1, sx * lat, dy), u)
				mb.box(base + Vector3(0.0, 0.3, 0.0), Vector3(0.1, 0.6, 0.1), col, false)
			next += gap
		run += l


## Piers (bents) and abutments under the deck: found from the terrain under the centre line, only where there is something to stand on below.
static func _supports(mb: MB, b: Dictionary, fr: Array[Dictionary], depth: float, hw: float, rh: float) -> void:
	var every: float = float(b.get("piers", 0.0))
	var total := fr.size()
	var run := 0.0
	var next := every * 0.5
	var runs := PackedFloat32Array([0.0])
	for i in range(1, total):
		run += Vector2(fr[i]["p"].x - fr[i - 1]["p"].x, fr[i]["p"].z - fr[i - 1]["p"].z).length()
		runs.append(run)
	var kind: StringName = b["kind"]
	if every > 0.0:
		for i in range(1, total - 1):
			if runs[i] < next or runs[i] < 6.0 or runs[total - 1] - runs[i] < 6.0:
				continue
			next = runs[i] + every
			var f: Dictionary = fr[i]
			var p: Vector3 = f["p"]
			var yaw := _yaw(f["t"])
			var cap_y := p.y - depth
			var col_w := 1.6 if kind != &"foot" else 0.5
			for sx in [-1.0, 1.0]:
				var c: Vector3 = p + (f["lat"] as Vector3) * sx * rh * 0.55
				var g := TerrainHeight.height_at(c.x, c.z) - 1.2
				if cap_y - g > 0.5:
					mb.box_yaw(Vector3(c.x, (cap_y + g) * 0.5, c.z), Vector3(col_w, cap_y - g, col_w), yaw, CONCRETE_DARK, false)
			if kind != &"foot":
				mb.box_yaw(Vector3(p.x, cap_y - 0.45, p.z), Vector3(hw * 1.7, 0.9, 1.7), yaw, CONCRETE, true)
	# abutments at both ends: a block from the deck underside down to the ground
	for end in [0, total - 1]:
		var f: Dictionary = fr[end]
		var p: Vector3 = f["p"]
		var g := TerrainHeight.height_at(p.x, p.z) - 1.0
		var top := p.y - depth
		if top - g > 0.4 and kind != &"foot":
			var inward: Vector3 = (f["t"] as Vector3) * (1.6 if end == 0 else -1.6)
			mb.box_yaw(Vector3(p.x + inward.x, (top + g) * 0.5, p.z + inward.z), Vector3(hw * 2.0 + 0.4, top - g, 3.4), _yaw(f["t"]), CONCRETE_DARK, false)


## Footbridge: planks, two side stringers, a handrail, posts at the ends.
static func _foot(mb: MB, b: Dictionary) -> void:
	var fr := frames(resample(b["pts"], 4.0))
	var hw := float(b["w"]) * 0.5
	sweep(mb, fr, PackedVector2Array([Vector2(-hw, -0.32), Vector2(hw, -0.32), Vector2(hw, 0.0), Vector2(-hw, 0.0)]), WOOD)
	for sx in [-1.0, 1.0]:
		sweep(mb, fr, PackedVector2Array([Vector2(sx * hw - 0.08, -0.7), Vector2(sx * hw + 0.08, -0.7), Vector2(sx * hw + 0.08, 0.0), Vector2(sx * hw - 0.08, 0.0)]), STEEL_DARK)
	_rail_posts(mb, fr, hw - 0.1, 0.0, 2.0, STEEL)
	_supports(mb, b, fr, 0.7, hw, 1.0)
	for end in [0, fr.size() - 1]:
		var p: Vector3 = fr[end]["p"]
		mb.box(Vector3(p.x, p.y - 0.7, p.z), Vector3(3.4, 1.4, 1.2), CONCRETE_DARK, false)


## The rail trestle: a ballast bed with two tracks (sleepers and rails) on two plate girders, steel bents with X bracing on the ground below.
static func _rail(mb: MB, b: Dictionary) -> void:
	var pts := resample(b["pts"], 11.0)
	var fr := frames(pts)
	var hw := float(b["w"]) * 0.5
	var half_sep: float = float(b.get("sep", 3.4)) * 0.5
	sweep(mb, fr, PackedVector2Array([Vector2(-hw, -0.5), Vector2(hw, -0.5), Vector2(hw, 0.0), Vector2(-hw, 0.0)]), BALLAST)
	for sx in [-1.0, 1.0]:
		sweep(mb, fr, PackedVector2Array([Vector2(sx * hw - 0.2, -2.1), Vector2(sx * hw + 0.2, -2.1), Vector2(sx * hw + 0.2, 0.7), Vector2(sx * hw - 0.2, 0.7)]), STEEL_DARK)
	sweep(mb, fr, PackedVector2Array([Vector2(-hw + 0.4, -2.0), Vector2(hw - 0.4, -2.0), Vector2(hw - 0.4, -0.5), Vector2(-hw + 0.4, -0.5)]), STEEL_DARK)
	# rails and sleepers: two tracks
	var run := 0.0
	for i in fr.size() - 1:
		var l := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		for tr in [-half_sep, half_sep]:
			for rr in [-0.72, 0.72]:
				mb.strut(_at(fr, i, float(tr) + float(rr), 0.16), _at(fr, i + 1, float(tr) + float(rr), 0.16), 0.14, STEEL, false)
		var k := 0
		while float(k) * 0.85 < l:
			var u := float(k) * 0.85 / maxf(l, 0.01)
			var c := _at(fr, i, 0.0, 0.07).lerp(_at(fr, i + 1, 0.0, 0.07), u)
			for tr in [-half_sep, half_sep]:
				mb.box_yaw(c + (fr[i]["lat"] as Vector3) * float(tr), Vector3(2.6, 0.12, 0.28), _yaw(fr[i]["t"]), WOOD, false)
			k += 1
		run += l
	# bents: two battered legs with a cap and an X brace
	var total := fr.size()
	var every := float(b.get("piers", 22.0))
	var next := every * 0.5
	var acc := 0.0
	for i in range(1, total - 1):
		acc += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		if acc < next:
			continue
		next = acc + every
		var f: Dictionary = fr[i]
		var p: Vector3 = f["p"]
		var lat: Vector3 = f["lat"]
		var g := TerrainHeight.height_at(p.x, p.z) - 1.0
		var top := p.y - 2.1
		if top - g < 1.0:
			continue
		var l0 := p - lat * (hw - 0.6)
		var r0 := p + lat * (hw - 0.6)
		var lb := Vector3(l0.x - lat.x * 2.2, g, l0.z - lat.z * 2.2)
		var rb := Vector3(r0.x + lat.x * 2.2, g, r0.z + lat.z * 2.2)
		var lt := Vector3(l0.x, top, l0.z)
		var rt := Vector3(r0.x, top, r0.z)
		mb.strut(lb, lt, 0.7, STEEL_DARK)
		mb.strut(rb, rt, 0.7, STEEL_DARK)
		mb.strut(lt, rt, 0.6, STEEL_DARK)
		mb.strut(lb, rt, 0.28, STEEL)
		mb.strut(rb, lt, 0.28, STEEL)


# --- the suspension bridge ------------------------------------------------------------------------------------------------------------

## The HARBOUR GATE: slab and parapets like a road bridge, a steel truss under the span, two H towers 46 m over the span deck painted red, a main cable parabola per side, hangers every 14 m,
## back stays to the deck ends, lamps along both sides, piers under the ramps over the headlands.
static func _suspension(mb: MB, b: Dictionary) -> void:
	var S := Bridges.SUSPENSION
	var pts := resample(b["pts"], 10.0)
	var fr := frames(pts)
	var hw := float(b["w"]) * 0.5
	var rh := float(b["road_w"]) * 0.5
	var prof := PackedVector2Array([Vector2(-hw, -SLAB), Vector2(hw, -SLAB), Vector2(hw, 1.0), Vector2(hw - 0.45, 1.0), Vector2(hw - 0.45, 0.18), Vector2(rh, 0.18), Vector2(rh, 0.0),
		Vector2(-rh, 0.0), Vector2(-rh, 0.18), Vector2(-hw + 0.45, 0.18), Vector2(-hw + 0.45, 1.0), Vector2(-hw, 1.0)])
	sweep(mb, fr, prof, STEEL_RED)
	# the stiffening truss: a deep girder under each edge with diagonals
	for sx in [-1.0, 1.0]:
		sweep(mb, fr, PackedVector2Array([Vector2(sx * (hw - 0.7) - 0.25, -SLAB), Vector2(sx * (hw - 0.7) + 0.25, -SLAB), Vector2(sx * (hw - 0.7) + 0.25, -SLAB - 2.2), Vector2(sx * (hw - 0.7) - 0.25, -SLAB - 2.2)]), STEEL_RED)
	var xa: float = S["tower_x0"]
	var xb: float = S["tower_x1"]
	var z: float = S["z"]
	var y_span: float = S["y_span"]
	var ground := Harbour.QUAY_Y
	var y_top := y_span + 46.0
	var cab_lat := hw + 0.3
	# towers: two legs each side of the deck, cross beams, a cap
	for tx in [xa, xb]:
		for sx in [-1.0, 1.0]:
			var lz: float = z + float(sx) * (hw + 1.4)
			mb.box(Vector3(tx, (ground + y_top) * 0.5 - 0.3, lz), Vector3(3.6, y_top - ground + 0.6, 2.6), STEEL_RED, false)
			mb.box(Vector3(tx, y_top + 0.5, lz), Vector3(4.4, 1.0, 3.2), STEEL_DARK, true)
		for by in [y_span + 8.0, y_span + 22.0, y_top - 5.0]:
			mb.box(Vector3(tx, by, z), Vector3(2.6, 2.4, (hw + 1.4) * 2.0), STEEL_RED, true)
			for sx in [-1.0, 1.0]:                                                          # a portal brace under each cross beam
				mb.strut(Vector3(tx, by - 1.2, z + float(sx) * (hw + 1.4)), Vector3(tx, by - 4.0, z + float(sx) * (hw - 0.6)), 0.5, STEEL_RED)
		mb.box(Vector3(tx, y_top + 2.0, z), Vector3(1.4, 4.0, 0.7), STEEL_DARK, true)
		mb.box(Vector3(tx, y_top + 4.2, z), Vector3(0.7, 0.7, 0.7), LAMP, true)             # a warning light on the top
	# main cable per side: parabola between the tower tops over the span, straight back stays to the deck ends
	var y_mid := y_span + 10.0
	var seg := 14
	for sx in [-1.0, 1.0]:
		var cz: float = z + float(sx) * cab_lat
		var prev := Vector3(xa, y_top, cz)
		for k in range(1, seg + 1):
			var u := float(k) / float(seg)
			var cx := lerpf(xa, xb, u)
			var cy := y_mid + (y_top - y_mid) * pow(2.0 * u - 1.0, 2.0)
			var cur := Vector3(cx, cy, cz)
			mb.strut(prev, cur, 0.5, STEEL_RED)
			prev = cur
		# hangers
		var hx := xa + 10.0
		while hx < xb - 6.0:
			var u2 := (hx - xa) / (xb - xa)
			var cy2 := y_mid + (y_top - y_mid) * pow(2.0 * u2 - 1.0, 2.0)
			var dk := Bridges.y_at(b, hx - float(b["pts"][0].x)) + 1.0
			mb.strut(Vector3(hx, cy2, cz), Vector3(hx, dk, cz), 0.12, STEEL)
			hx += 14.0
		# back stays: tower top to the deck edge on each headland, with hangers
		for side in [0, 1]:
			var tx2: float = xa if side == 0 else xb
			var ex: float = float(S["x0"]) + 14.0 if side == 0 else float(S["x1"]) - 14.0
			var ey: float = Bridges.y_at(b, ex - float(b["pts"][0].x)) + 1.0
			mb.strut(Vector3(tx2, y_top, cz), Vector3(ex, ey, cz), 0.45, STEEL_RED)
			for h in 5:
				var t3 := (float(h) + 1.0) / 6.0
				var px := lerpf(tx2, ex, t3)
				var py := lerpf(y_top, ey, t3)
				var dy3 := Bridges.y_at(b, px - float(b["pts"][0].x)) + 1.0
				mb.strut(Vector3(px, py, cz), Vector3(px, dy3, cz), 0.1, STEEL)
	# lamps along both edges
	var lx := float(S["x0"]) + 20.0
	while lx < float(S["x1"]) - 10.0:
		var yy := Bridges.y_at(b, lx - float(b["pts"][0].x)) + 1.0
		for sx in [-1.0, 1.0]:
			var lz2: float = z + float(sx) * (hw - 0.3)
			mb.box(Vector3(lx, yy + 3.3, lz2), Vector3(0.12, 6.6, 0.12), STEEL_DARK, false)
			mb.box(Vector3(lx, yy + 6.7, lz2 - float(sx) * 0.5), Vector3(0.4, 0.2, 1.1), LAMP, false)
		lx += 36.0
	# piers under the ramps over the headlands (the span between the towers is free)
	var px2 := float(S["x0"]) + 22.0
	while px2 < float(S["x1"]) - 20.0:
		if px2 < xa - 8.0 or px2 > xb + 8.0:
			var yd := Bridges.y_at(b, px2 - float(b["pts"][0].x)) - SLAB - 2.2
			var gg := ground - 0.4
			if yd - gg > 0.5:
				for sx in [-1.0, 1.0]:
					mb.box(Vector3(px2, (yd + gg) * 0.5, z + float(sx) * (hw - 2.2)), Vector3(2.2, yd - gg, 2.2), CONCRETE, false)
				mb.box(Vector3(px2, yd - 0.45, z), Vector3(2.2, 0.9, hw * 2.0), CONCRETE, true)
		px2 += 30.0
