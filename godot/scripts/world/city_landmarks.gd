extends RefCounted
## One landmark silhouette per district (wave 16 art library), standing on the empty plaza lot nearest to the district's target point (city_districts.gd LANDMARK_TARGETS):
##   market   LANTERN SPIRE  a slim hex column carrying three glowing lantern pods and a crown of tines (124 m)
##   foundry  TWIN STACKS    two tapering chimneys with furnace bands, a bridge and burning flare tops (113 m)
##   slums    RELAY TOWER    a leaning-braced lattice mast with lit cabins, dishes and a beacon (125 m)
##   towers   VAEL NEEDLE    a thin glass needle with three floating light rings (150 m)
## Each has two levels of geometry (full detail within `LOD_SWITCH` metres of the camera, a coarse silhouette beyond); they are NOT nodes of their own: the street-kit window
## (city_kit_window.gd) merges the level it needs into its one mesh, so all four landmarks and the 16 street props together cost ONE draw call. A solid core column each stands for
## the physics. Nothing here touches the 80 m street grid: the plaza lots are the only empty blocks, and the plaza furniture (ring of bollards, radius 11 m) stays outside the 6 m plinth.
## The reflection under the wet ground is not drawn for the landmarks (one more draw call each), the tall lit parts still bloom.

const MB := preload("res://scripts/world/mesh_builder.gd")
const Districts := preload("res://scripts/world/city_districts.gd")
const Kit := preload("res://scripts/world/city_kit.gd")

const LOD_SWITCH := 230.0
const HEIGHTS: Array[float] = [124.0, 113.0, 125.0, 150.0]
const CORE: Array[float] = [4.4, 5.0, 3.2, 4.8]              ## width of the solid core column

var items: Array[Dictionary] = []                            ## {district, id, pos, height, near: geometry, far: geometry} (geometry = flat arrays, see Kit.make_geo)


func build(layout: CityLayout, _kit_placements: Array = []) -> void:
	items.clear()
	var used := {}
	for d in Districts.COUNT:
		var target: Vector2 = Districts.LANDMARK_TARGETS[d]
		var best := Vector2.INF
		var best_d := 1.0e12
		for pl: Vector2 in layout.plazas:
			if used.has(pl) or Districts.at(pl.x, pl.y) != d:
				continue
			var dd := pl.distance_squared_to(target)
			if dd < best_d:
				best_d = dd
				best = pl
		if best == Vector2.INF:
			continue                                         # a district without a plaza keeps no landmark (never the case for the shipped layout)
		used[best] = true
		items.append({"district": d, "id": Districts.LANDMARKS[d], "pos": Vector3(best.x, 0.0, best.y), "height": HEIGHTS[d], "near": make_geo(d, true), "far": make_geo(d, false), "seed": 0.13 + 0.2 * float(d)})


static func triangle_count(geo: Dictionary) -> int:
	return int(geo["count"]) / 3


## Solid core columns: [center, size, name] boxes for the City's static body.
func collision_boxes() -> Array:
	var out: Array = []
	for it in items:
		var d: int = it["district"]
		var h: float = it["height"]
		var w := CORE[d]
		var pos: Vector3 = it["pos"]
		out.append([pos + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w), "Landmark_%s" % String(it["id"])])
	return out


func item_for(d: int) -> Dictionary:
	for it in items:
		if int(it["district"]) == d:
			return it
	return {}


# --- meshes ----------------------------------------------------------------------------------------------------------------

static func make_geo(d: int, near: bool) -> Dictionary:
	var p := Kit._pal(d, 0)
	var b := MB.new()
	b.uv2 = Vector2(0.6, 0.5)
	match d:
		Districts.MARKET:
			_lantern_spire(b, p, near)
		Districts.FOUNDRY:
			_twin_stacks(b, p, near)
		Districts.SLUMS:
			_relay_tower(b, p, near)
		_:
			_vael_needle(b, p, near)
	return Kit._flat(b)


## A ring of box segments around the Y axis at height y (radius r, segment thickness t), optionally tilted about X.
static func _ring(b: MB, y: float, r: float, segs: int, t: float, c: Color, tilt := 0.0) -> void:
	var start := b.verts.size()
	var seg_len := TAU * r / float(segs) * 1.04
	for k in segs:
		var a := TAU * float(k) / float(segs)
		b.box_yaw(Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3(seg_len, t, t), -a + PI * 0.5, c, false)
	b.xform_from(start, Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0.0, y, 0.0)))


static func _lantern_spire(b: MB, p: Kit.Pal, near: bool) -> void:
	var conc := p.t(Color(0.13, 0.125, 0.12, 0.0))
	var metal := p.t(Color(0.07, 0.065, 0.065, 0.0))
	b.uv2 = Vector2(0.2, 0.8)
	b.box(Vector3(0, 0.6, 0), Vector3(7.0, 1.2, 7.0), conc, false)
	b.uv2 = Vector2(0.7, 0.45)
	b.cylinder(Vector3(0, 1.2, 0), 2.1, 118.0, 8 if near else 5, metal, 0.7, false)
	var pods := [[38.0, 5.8], [66.0, 4.8], [92.0, 3.8]]
	for k in pods.size():
		var y: float = pods[k][0]
		var rad: float = pods[k][1]
		b.uv2 = Vector2(0.0, 0.4)
		b.sphere(Vector3(0, y, 0), Vector3(rad, rad * 0.78, rad), 10 if near else 6, 6 if near else 3, p.glow(0.55, k == 1))
		if near:
			b.uv2 = Vector2(0.7, 0.45)
			b.cylinder(Vector3(0, y - 0.25, 0), rad + 0.12, 0.5, 10, metal, -1.0, false)
			b.cylinder(Vector3(0, y + rad * 0.78 - 0.1, 0), 0.5, 1.3, 6, metal, 0.18, false)
	if near:
		b.uv2 = Vector2(0.7, 0.45)
		for k in 6:
			var a := TAU * float(k) / 6.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			b.strut(Vector3(0, 106.0, 0) + dir * 0.9, Vector3(0, 123.0, 0) + dir * 4.6, 0.35, metal, false)
		b.uv2 = Vector2(0.0, 0.3)
		b.box(Vector3(0, 124.6, 0), Vector3(0.6, 1.2, 0.6), Color(1, 1, 1, Kit.EM_BEACON), false)
		b.box(Vector3(0, 118.0, 0), Vector3(0.8, 0.8, 0.8), p.glow(0.8), false)


static func _twin_stacks(b: MB, p: Kit.Pal, near: bool) -> void:
	var rust := p.t(Color(0.10, 0.075, 0.06, 0.0))
	var steel := p.t(Color(0.07, 0.07, 0.075, 0.0))
	b.uv2 = Vector2(0.3, 0.8)
	b.box(Vector3(0, 5.0, 0), Vector3(14.0, 10.0, 9.0), p.t(Color(0.09, 0.085, 0.085, 0.0)), false)
	for sx in [-5.5, 5.5]:
		b.uv2 = Vector2(0.5, 0.75)
		b.cylinder(Vector3(sx, 10.0, 0), 3.4, 100.0, 10 if near else 6, rust, 2.3, false)
		b.cylinder(Vector3(sx, 110.0, 0), 2.3, 3.0, 10 if near else 6, steel, 3.0, false)
		b.uv2 = Vector2(0.0, 0.3)
		b.cylinder(Vector3(sx, 113.0, 0), 2.7, 0.15, 10 if near else 6, p.glow(0.8), -1.0, true)
		if near:
			for y in [34.0, 56.0, 80.0]:
				var r := lerpf(3.4, 2.3, (y - 10.0) / 100.0) + 0.18
				b.cylinder(Vector3(sx, y, 0), r, 0.9, 10, p.glow(0.55, y > 40.0), -1.0, false)
	b.uv2 = Vector2(0.6, 0.5)
	b.box(Vector3(0, 66.0, 0), Vector3(11.0, 1.4, 1.6), steel, true)
	if near:
		for k in 3:
			b.strut(Vector3(-5.5, 68.0 + float(k) * 4.0, 0.0), Vector3(5.5, 68.0 + float(k) * 4.0, 0.0), 0.5, steel, false)
		b.strut(Vector3(-2.0, 67.0, 0.0), Vector3(-2.0, 11.0, 4.5), 0.5, steel, false)
		b.strut(Vector3(2.0, 67.0, 0.0), Vector3(2.0, 11.0, -4.5), 0.5, steel, false)


static func _relay_tower(b: MB, p: Kit.Pal, near: bool) -> void:
	var iron := p.t(Color(0.075, 0.08, 0.08, 0.0))
	b.uv2 = Vector2(0.2, 0.8)
	b.box(Vector3(0, 0.8, 0), Vector3(11.0, 1.6, 11.0), p.t(Color(0.11, 0.11, 0.115, 0.0)), false)
	b.uv2 = Vector2(0.7, 0.55)
	b.cylinder(Vector3(0, 1.6, 0), 1.3, 120.0 if near else 112.0, 6 if near else 4, iron, 0.5, false)
	var levels := 6 if near else 3
	var top := 124.0
	var half0 := 4.4
	var half1 := 0.9
	var legs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for li in levels:
		var t0 := float(li) / float(levels)
		var t1 := float(li + 1) / float(levels)
		var y0 := lerpf(1.6, top, t0)
		var y1 := lerpf(1.6, top, t1)
		var h0 := lerpf(half0, half1, t0)
		var h1 := lerpf(half0, half1, t1)
		for k in 4:
			var a: Vector2 = legs[k]
			var a2: Vector2 = legs[(k + 1) % 4]
			b.strut(Vector3(a.x * h0, y0, a.y * h0), Vector3(a.x * h1, y1, a.y * h1), 0.34 if near else 0.5, iron, false)
			if near:
				b.strut(Vector3(a.x * h1, y1, a.y * h1), Vector3(a2.x * h1, y1, a2.y * h1), 0.18, iron, false)
				if li % 2 == 0:
					b.strut(Vector3(a.x * h0, y0, a.y * h0), Vector3(a2.x * h1, y1, a2.y * h1), 0.14, iron, false)
	if not near:
		return
	for y in [42.0, 78.0]:
		b.uv2 = Vector2(0.4, 0.6)
		b.box(Vector3(0, y, 0), Vector3(3.6, 2.4, 3.6), p.t(Color(0.09, 0.095, 0.10, 0.0)), true)
		b.uv2 = Vector2(0.0, 0.3)
		for sgn in [-1.0, 1.0]:
			b.quad(Vector3(-1.4, y - 0.3, sgn * 1.81), Vector3(1.4, y - 0.3, sgn * 1.81), Vector3(1.4, y + 0.6, sgn * 1.81), Vector3(-1.4, y + 0.6, sgn * 1.81), Vector3(0, 0, sgn), p.glow(0.5))
	for k in 3:
		var y2 := 94.0 + 9.5 * float(k)
		var start := b.verts.size()
		b.uv2 = Vector2(0.5, 0.5)
		b.cylinder(Vector3(0, 0, 0), 2.2 - 0.3 * float(k), 0.35, 8, p.t(Color(0.2, 0.2, 0.21, 0.0)), 0.3)
		b.xform_from(start, Transform3D(Basis(Vector3.UP, float(k) * 1.9) * Basis(Vector3.RIGHT, deg_to_rad(-60.0)), Vector3(1.5, y2, 0.0)))
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 124.6, 0), Vector3(0.7, 1.4, 0.7), Color(1, 1, 1, Kit.EM_BEACON), false)
	b.box(Vector3(0, 110.0, 0), Vector3(0.9, 0.9, 0.9), p.glow(0.8), false)


static func _vael_needle(b: MB, p: Kit.Pal, near: bool) -> void:
	var glass := p.t(Color(0.05, 0.065, 0.085, 0.0))
	b.uv2 = Vector2(0.2, 0.7)
	b.cylinder(Vector3(0, 0, 0), 6.0, 4.0, 8 if near else 6, p.t(Color(0.12, 0.125, 0.14, 0.0)), 5.2, true)
	b.uv2 = Vector2(0.9, 0.18)
	b.cylinder(Vector3(0, 4.0, 0), 2.6, 144.0, 8 if near else 5, glass, 0.25, false)
	b.uv2 = Vector2(0.0, 0.3)
	if near:
		for k in 4:
			var a := TAU * float(k) / 4.0 + PI * 0.25
			var dir := Vector3(cos(a), 0.0, sin(a))
			for seg in 3:
				var y0 := 8.0 + 40.0 * float(seg)
				var r0 := lerpf(2.6, 0.25, (y0 - 4.0) / 144.0)
				var r1 := lerpf(2.6, 0.25, (y0 + 30.0 - 4.0) / 144.0)
				b.strut(dir * (r0 + 0.04) + Vector3(0, y0, 0), dir * (r1 + 0.04) + Vector3(0, y0 + 30.0, 0), 0.16, p.glow(0.6), false)
		b.box(Vector3(0, 150.6, 0), Vector3(0.5, 1.2, 0.5), Color(1, 1, 1, Kit.EM_BEACON), false)
	var segs := 14 if near else 6
	_ring(b, 96.0, 9.0, segs, 0.7, p.glow(0.65), deg_to_rad(8.0))
	_ring(b, 114.0, 12.0, segs, 0.8, p.glow(0.55, true), deg_to_rad(-10.0))
	_ring(b, 130.0, 7.0, segs, 0.6, p.glow(0.7), deg_to_rad(14.0))
