extends RefCounted
## City dressing (wave 62 city art): eleven facade / rooftop / sidewalk kinds that make the four districts read as different places, merged into the same street-kit mesh as the
## other city-kit pieces (city_kit_world.gd, city_kit.gd, city_kit_window.gd): no node and no draw call of their own. Geometry is procedural boxes and cylinders (district paint and
## quantum glow accents, like the street kit) mixed with Quaternius Downtown City MegaKit pieces (CC0, converted by tools/city_kit_extra.py): columns, stoops, shop walls, brick
## trims, slate roof caps, trim cornices.
##
## Per-district composition rules (`layout`, deterministic, own random stream per lot, so no other placement moves):
##   market   low awnings in fabric stripes, blade signs, cafe clusters, balconies with planters, lantern pavilions and roof signs, slate-capped roofs, trim ledges
##   foundry  roll shutters, structural columns, fire escapes, brick parapets, twin smokestacks, tanks and pipe gantries, crate and barrel clusters
##   slums    stoops, torn awnings, many balconies with laundry, fire escapes, water towers, shacks and dish clusters, bins and junk piles
##   towers   colonnades with a glowing architrave, glass canopies, glass balconies, glowing ledges, crowns with a halo ring and a mast, helipads, planter clusters
## Local +Z of a facade item is the street side (the wall plane is z = 0); rooftop items turn their front to the street.

const MB := preload("res://scripts/world/mesh_builder.gd")
const Districts := preload("res://scripts/world/city_districts.gd")

const STOOP := 0
const AWNING := 1
const BALCONY := 2
const SHUTTER := 3
const COLONNADE := 4
const PARAPET := 5
const ROOFTOP := 6
const FIRE_ESCAPE := 7
const CLUSTER := 8
const BLADE := 9
const LEDGE := 10
const COUNT := 11

const NAMES: Array[String] = ["Stoop", "Awning", "Balcony", "Shutter", "Colonnade", "Parapet", "Rooftop", "FireEscape", "Cluster", "BladeSign", "Ledge"]
const PIECES := {
	STOOP: ["stoop", "stoop_flat"], SHUTTER: ["shopwall"], COLONNADE: ["column", "column_small"], PARAPET: ["trim_brick", "trim_half"],
	ROOFTOP: ["slate_cap", "slate_roof", "column_small"], LEDGE: ["cornice_trim"],
}
## Kinds that are also drawn simplified from afar (they read in a skyline or down a street): far radius in metres.
const FAR := {ROOFTOP: 160.0}
const BLOCKING := [STOOP, CLUSTER]            ## kinds with a pooled collider on the sidewalk (city_kit.gd)

const EM_BEACON := 0.30
const EM_POSTER := 0.80
const EM_GLOW := 1.0
const PAINT_GAIN := 3.0
const TINT_MIX := 0.3


class Pal extends RefCounted:
	var d := 0
	var tint := Color.WHITE
	var accent := Color.WHITE
	var accent2 := Color.WHITE
	var fabric: Array = []
	var variant := 0

	func t(c: Color) -> Color:
		return Color(c.r * tint.r * PAINT_GAIN, c.g * tint.g * PAINT_GAIN, c.b * tint.b * PAINT_GAIN, 0.0)

	func glow(k := 0.7, second := false) -> Color:
		var a := accent2 if second else accent
		return Color(a.r * k, a.g * k, a.b * k, EM_GLOW)

	func cloth(i := -1) -> Color:
		var f: Color = fabric[(variant if i < 0 else i) % fabric.size()]
		return Color(f.r * 1.9, f.g * 1.9, f.b * 1.9, 0.0)


static func _pal(d: int, variant: int) -> Pal:
	var src := Districts.palette(d)
	var p := Pal.new()
	p.d = d
	p.tint = src["tint"]
	p.accent = src["accent"]
	p.accent2 = src["accent2"]
	p.fabric = src["fabric"]
	p.variant = variant
	return p


static func _uvq() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])


static func far_radius(kind: int) -> float:
	return float(FAR.get(kind, 0.0))


# --- geometry ----------------------------------------------------------------------------------------------------------------

## Flat geometry of a kind (v, n, uv, uv2, c, count); `pf` looks a glb piece up (KitWorld.piece). Far level = silhouette boxes (only for the kinds in FAR).
static func make_geo(kind: int, d: int, variant: int, near: bool, pf: Callable) -> Dictionary:
	if not near and not FAR.has(kind):
		return {}
	var p := _pal(d, variant)
	var b := MB.new()
	b.uv2 = Vector2(0.5, 0.6)
	var g := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "c": PackedColorArray(), "count": 0}
	match kind:
		STOOP:
			_stoop(g, p, pf)
		AWNING:
			_awning(b, p, near)
		BALCONY:
			_balcony(b, p, near)
		SHUTTER:
			_shutter(b, g, p, pf)
		COLONNADE:
			_colonnade(b, g, p, pf)
		PARAPET:
			_parapet(b, g, p, pf)
		ROOFTOP:
			_rooftop(b, g, p, near, pf)
		FIRE_ESCAPE:
			_fire_escape(b, p)
		CLUSTER:
			_cluster(b, p)
		BLADE:
			_blade(b, p)
		LEDGE:
			_ledge(b, g, p, pf)
	_append_mb(g, b)
	return g


static func _append_mb(g: Dictionary, b: MB) -> void:
	var n := b.idx.size()
	if n == 0:
		return
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	v.resize(n)
	nr.resize(n)
	uv.resize(n)
	uv2.resize(n)
	c.resize(n)
	for i in n:
		var j := b.idx[i]
		v[i] = b.verts[j]
		nr[i] = b.norms[j]
		uv[i] = b.uvs[j]
		uv2[i] = b.uv2s[j]
		c[i] = b.cols[j]
	_cat(g, v, nr, uv, uv2, c)


## Packed arrays are values: read them out of the dictionary, append, store them back.
static func _cat(g: Dictionary, v: PackedVector3Array, nr: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, c: PackedColorArray) -> void:
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	var gc: PackedColorArray = g["c"]
	gv.append_array(v)
	gn.append_array(nr)
	guv.append_array(uv)
	guv2.append_array(uv2)
	gc.append_array(c)
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["uv2"] = guv2
	g["c"] = gc
	g["count"] = int(g["count"]) + v.size()


## A glb piece into the geometry: offset, yaw, per-axis scale, tint mix like city_kit_world.gd. Facade pieces keep their overhang on the +Z side (`front`).
static func _piece(g: Dictionary, pf: Callable, name: String, off: Vector3, yaw: float, sc: Vector3, p: Pal, metal := 0.45, rough := 0.6, tint_mix := TINT_MIX) -> void:
	var d: Dictionary = pf.call(name)
	if d.is_empty():
		return
	var basis := Basis(Vector3.UP, yaw + (0.0 if float(d["front"]) > 0.0 else PI)) * Basis.from_scale(sc)
	var xf := Transform3D(basis, off)
	var n: int = d["count"]
	var cols: PackedColorArray = d["c"]
	var out := PackedColorArray()
	out.resize(n)
	for i in n:
		var c := cols[i]
		out[i] = Color(lerpf(c.r, c.r * p.tint.r, tint_mix), lerpf(c.g, c.g * p.tint.g, tint_mix), lerpf(c.b, c.b * p.tint.b, tint_mix), 0.0)
	var uv := PackedVector2Array()
	uv.resize(n)
	var uv2 := PackedVector2Array()
	uv2.resize(n)
	uv2.fill(Vector2(metal, rough))
	var nb := Basis(Vector3.UP, yaw + (0.0 if float(d["front"]) > 0.0 else PI))
	_cat(g, xf * (d["v"] as PackedVector3Array), Transform3D(nb, Vector3.ZERO) * (d["n"] as PackedVector3Array), uv, uv2, out)


static func _stoop(g: Dictionary, p: Pal, pf: Callable) -> void:
	var flat := p.variant != 3
	_piece(g, pf, "stoop_flat" if flat else "stoop", Vector3(0.0, 0.0, 1.0 if flat else 1.0), 0.0, Vector3(1.0, 0.45 if not flat else 0.3, 1.0), p, 0.1, 0.8, 0.45)


static func _awning(b: MB, p: Pal, near: bool) -> void:
	var w := 2.6 + 0.9 * float(p.variant)
	var hw := w * 0.5
	var drop := 0.6
	var out := 1.7
	var glass := p.d == Districts.TOWERS
	var slum := p.d == Districts.SLUMS
	if slum:
		drop = 0.85
		out = 1.3
	var nrm := Vector3(0.0, out, drop).normalized()
	var stripes := 1 if not near else (6 if p.d == Districts.MARKET else (4 if not glass else 1))
	var pale := Color(0.55, 0.52, 0.46, 0.0)
	b.uv2 = Vector2(0.0, 0.85)
	for s in stripes:
		var x0 := -hw + w * float(s) / float(stripes)
		var x1 := -hw + w * float(s + 1) / float(stripes)
		var col := p.cloth() if (s % 2 == 0 or glass) else pale
		if glass:
			col = Color(0.02, 0.05, 0.065, 0.0)
		elif slum:
			col = Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0)
		b.quad(Vector3(x0, 0.0, 0.0), Vector3(x1, 0.0, 0.0), Vector3(x1, -drop, out), Vector3(x0, -drop, out), nrm, col)
		if near:
			b.quad(Vector3(x0, -drop, out), Vector3(x1, -drop, out), Vector3(x1, -drop - 0.2, out), Vector3(x0, -drop - 0.2, out), Vector3.BACK, col)
			if s % 2 == 0 and not glass:
				b.quad(Vector3(x0, 0.0, 0.0), Vector3(x1, 0.0, 0.0), Vector3(x1, -drop, out), Vector3(x0, -drop, out), -nrm, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.0))
	if not near:
		return
	b.uv2 = Vector2(0.8, 0.45)
	for sx: float in [-hw, hw]:
		b.strut(Vector3(sx, -0.55, out - 0.05), Vector3(sx, 0.05, 0.05), 0.045, p.t(Color(0.05, 0.055, 0.06, 0.0)), false)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0.0, -drop - 0.24, out), Vector3(w, 0.04, 0.04), p.glow(0.9, glass or p.d == Districts.FOUNDRY), false)


static func _balcony(b: MB, p: Pal, near: bool) -> void:
	var conc := p.t(Color(0.12, 0.12, 0.125, 0.0))
	var iron := p.t(Color(0.05, 0.055, 0.06, 0.0))
	var hw := 1.5
	var depth := 1.25
	b.uv2 = Vector2(0.0, 0.8)
	b.box(Vector3(0.0, 0.075, depth * 0.5), Vector3(hw * 2.0, 0.15, depth), conc, true)
	var glass := p.d == Districts.TOWERS
	b.uv2 = Vector2(0.7, 0.45)
	if glass:
		b.box(Vector3(0.0, 0.62, depth - 0.03), Vector3(hw * 2.0, 1.0, 0.04), Color(0.03, 0.07, 0.09, 0.0), false)
		if near:
			for sx: float in [-hw + 0.02, hw - 0.02]:
				b.box(Vector3(sx, 0.62, depth * 0.5), Vector3(0.04, 1.0, depth), Color(0.03, 0.07, 0.09, 0.0), false)
		b.uv2 = Vector2(0.0, 0.3)
		b.box(Vector3(0.0, 1.14, depth - 0.03), Vector3(hw * 2.0, 0.05, 0.06), p.glow(0.9), false)
	else:
		b.box(Vector3(0.0, 1.05, depth - 0.03), Vector3(hw * 2.0, 0.05, 0.05), iron, false)
		if near:
			for k in 3:
				b.box(Vector3(-hw + 0.05 + (hw * 2.0 - 0.1) * float(k) / 2.0, 0.6, depth - 0.03), Vector3(0.035, 0.9, 0.035), iron, false)
			b.uv2 = Vector2(0.0, 0.3)
			b.quad(Vector3(-0.55, 0.3, 0.015), Vector3(0.55, 0.3, 0.015), Vector3(0.55, 2.25, 0.015), Vector3(-0.55, 2.25, 0.015), Vector3.BACK, p.glow(0.18 if p.d != Districts.MARKET else 0.3, true))
	if not near:
		return
	if (p.d == Districts.MARKET or p.d == Districts.SLUMS) and p.variant % 2 == 0:
		b.uv2 = Vector2(0.0, 0.7)
		b.box(Vector3(-0.7, 0.3, depth - 0.25), Vector3(1.1, 0.3, 0.32), Color(0.07, 0.05, 0.035, 0.0), false)
		b.uv2 = Vector2(0.0, 0.5)
		b.box(Vector3(-0.7, 0.5, depth - 0.25), Vector3(0.95, 0.1, 0.22), Color(0.02, 0.2 * p.accent2.g + 0.04, 0.03, 0.0), false)
	if p.d == Districts.SLUMS:                                      # laundry on a line
		b.uv2 = Vector2(0.0, 0.9)
		var cols := [p.cloth(0), p.cloth(1), p.cloth(2)]
		for k in 3:
			var x := -0.9 + 0.65 * float(k)
			b.quad(Vector3(x, 1.0, depth - 0.1), Vector3(x + 0.4, 1.0, depth - 0.1), Vector3(x + 0.4, 0.45, depth - 0.1), Vector3(x, 0.55, depth - 0.1), Vector3.BACK, cols[k])
	if p.d == Districts.MARKET:                                     # string of lanterns
		for k in 3:
			b.uv2 = Vector2(0.0, 0.3)
			b.box(Vector3(-0.9 + 0.9 * float(k), 1.5, depth - 0.05), Vector3(0.17, 0.22, 0.17), p.glow(0.95, k == 1), false)


static func _shutter(b: MB, g: Dictionary, p: Pal, pf: Callable) -> void:
	for x: float in [-1.0, 1.0]:
		_piece(g, pf, "shopwall", Vector3(x, 0.0, 0.14), 0.0, Vector3(1.0, 0.9, 1.0), p, 0.7, 0.5, 0.5)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0.0, 2.95, 0.12), Vector3(3.8, 0.3, 0.1), p.glow(0.8, p.variant % 2 == 1), false)


static func _colonnade(b: MB, g: Dictionary, p: Pal, pf: Callable) -> void:
	var small := p.variant % 2 == 1
	for x: float in [-2.0, 2.0]:
		_piece(g, pf, "column_small" if small else "column", Vector3(x, 0.0, 0.5), 0.0, Vector3(1.0, 1.36, 1.0), p, 0.6, 0.5, 0.6)
		b.uv2 = Vector2(0.4, 0.5)
		b.box(Vector3(x, 0.1, 0.5), Vector3(0.7, 0.2, 0.7), p.t(Color(0.1, 0.1, 0.105, 0.0)), false)
	b.uv2 = Vector2(0.6, 0.45)
	b.box(Vector3(0.0, 4.2, 0.4), Vector3(4.8, 0.3, 0.8), p.t(Color(0.055, 0.06, 0.065, 0.0)), true)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0.0, 4.0, 0.78), Vector3(4.6, 0.05, 0.05), p.glow(0.95), false)
	b.quad(Vector3(-1.8, 3.99, 0.1), Vector3(1.8, 3.99, 0.1), Vector3(1.8, 3.99, 0.74), Vector3(-1.8, 3.99, 0.74), Vector3.DOWN, p.glow(0.35, true))


static func _parapet(b: MB, g: Dictionary, p: Pal, pf: Callable) -> void:
	var name := "trim_half" if p.variant % 2 == 1 else "trim_brick"
	for x: float in [-1.0, 1.0]:
		_piece(g, pf, name, Vector3(x, 0.0, 0.14), 0.0, Vector3(1.0, 0.36, 1.0), p, 0.2, 0.8, 0.5)
	b.uv2 = Vector2(0.5, 0.6)
	b.box(Vector3(0.0, 1.1, 0.12), Vector3(4.1, 0.07, 0.4), p.t(Color(0.075, 0.08, 0.085, 0.0)), false)
	if p.d == Districts.TOWERS or p.d == Districts.FOUNDRY:
		b.uv2 = Vector2(0.0, 0.3)
		b.box(Vector3(0.0, 1.16, 0.3), Vector3(4.0, 0.03, 0.03), p.glow(0.75, p.d == Districts.FOUNDRY), false)


static func _ledge(b: MB, g: Dictionary, p: Pal, pf: Callable) -> void:
	for x: float in [-1.0, 1.0]:
		_piece(g, pf, "cornice_trim", Vector3(x, 0.0, 0.3), 0.0, Vector3(1.0, 0.45, 0.5), p, 0.5, 0.6, 0.5)
	if p.d == Districts.TOWERS or p.d == Districts.MARKET:
		b.uv2 = Vector2(0.0, 0.3)
		b.box(Vector3(0.0, -0.02, 0.58), Vector3(3.9, 0.025, 0.025), p.glow(0.7, p.d == Districts.MARKET), false)


static func _blade(b: MB, p: Pal) -> void:
	var metal := p.t(Color(0.06, 0.065, 0.07, 0.0))
	b.uv2 = Vector2(0.8, 0.4)
	b.strut(Vector3(0.0, 0.2, 0.05), Vector3(0.0, 0.2, 0.9), 0.05, metal, false)
	b.strut(Vector3(0.0, 1.9, 0.05), Vector3(0.0, 1.9, 0.9), 0.05, metal, false)
	b.box(Vector3(0.0, 1.05, 0.9), Vector3(0.12, 2.0, 0.55), p.t(Color(0.04, 0.042, 0.046, 0.0)), false)
	b.uv2 = Vector2(0.0, 0.3)
	for sx: float in [-0.065, 0.065]:
		b.quad(Vector3(sx, 0.25, 0.64), Vector3(sx, 0.25, 1.16), Vector3(sx, 1.85, 1.16), Vector3(sx, 1.85, 0.64), Vector3(signf(sx), 0, 0), Color(1, 1, 1, EM_POSTER), Vector2.ZERO, Vector2.ZERO, _uvq())
	b.box(Vector3(0.0, 2.08, 0.9), Vector3(0.1, 0.06, 0.5), p.glow(0.9), false)


static func _fire_escape(b: MB, p: Pal) -> void:
	var iron := p.t(Color(0.045, 0.05, 0.055, 0.0))
	b.uv2 = Vector2(0.8, 0.5)
	var floors := 2
	var fh := 3.4
	for f in floors:
		var y := float(f) * fh
		b.box(Vector3(0.0, y, 0.5), Vector3(2.0, 0.07, 1.0), iron, false)
		b.box(Vector3(0.0, y + 0.55, 1.0), Vector3(2.0, 0.04, 0.04), iron, false)
		b.box(Vector3(-0.98, y + 0.55, 0.5), Vector3(0.04, 0.04, 1.0), iron, false)
		b.box(Vector3(0.0, y + 0.28, 1.0), Vector3(1.96, 0.05, 0.03), iron, false)
		if f < floors - 1:                                        # flight down to the next landing
			var x0 := -0.55 if f % 2 == 0 else 0.55
			b.strut(Vector3(x0, y + 0.05, 0.9), Vector3(-x0, y + fh, 0.9), 0.07, iron, false)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0.0, float(floors - 1) * fh + 0.12, 0.92), Vector3(0.12, 0.08, 0.04), p.glow(0.8), false)


static func _cluster(b: MB, p: Pal) -> void:
	match p.d:
		Districts.MARKET:                                         # cafe table, stools and a lit umbrella
			b.uv2 = Vector2(0.6, 0.5)
			b.cylinder(Vector3(0, 0, 0), 0.05, 0.72, 6, p.t(Color(0.06, 0.06, 0.065, 0.0)), -1.0, false)
			b.cylinder(Vector3(0, 0.72, 0), 0.45, 0.05, 8, p.t(Color(0.12, 0.1, 0.08, 0.0)), -1.0, true)
			for s in 3:
				var a := TAU * float(s) / 3.0 + 0.4
				b.cylinder(Vector3(cos(a) * 0.7, 0, sin(a) * 0.7), 0.17, 0.45, 6, p.cloth(s), -1.0, true)
			b.cylinder(Vector3(0, 0.75, 0), 0.03, 2.0, 5, p.t(Color(0.07, 0.07, 0.075, 0.0)), -1.0, false)
			b.funnel(Vector3(0, 2.9, 0), 2.4, 1.15, 8, 0.05, p.cloth())
			b.uv2 = Vector2(0.0, 0.3)
			b.cylinder(Vector3(0, 2.38, 0), 1.16, 0.04, 8, p.glow(0.8), -1.0, false)
		Districts.FOUNDRY:                                        # pallet, crate stack, hazard barrels
			b.uv2 = Vector2(0.2, 0.7)
			b.box(Vector3(-0.3, 0.07, 0.0), Vector3(1.2, 0.14, 1.0), p.t(Color(0.1, 0.075, 0.05, 0.0)), false)
			b.box(Vector3(-0.3, 0.55, 0.0), Vector3(1.0, 0.8, 0.9), p.t(Color(0.085, 0.09, 0.095, 0.0)), false)
			b.box(Vector3(-0.2, 1.15, 0.05), Vector3(0.7, 0.4, 0.6), p.t(Color(0.12, 0.085, 0.05, 0.0)), false)
			for s in 2:
				b.uv2 = Vector2(0.6, 0.5)
				b.cylinder(Vector3(0.75, 0, -0.25 + 0.55 * float(s)), 0.26, 0.85, 8, p.t(Color(0.12, 0.06, 0.03, 0.0)), -1.0, true)
				b.uv2 = Vector2(0.0, 0.3)
				b.cylinder(Vector3(0.75, 0.55, -0.25 + 0.55 * float(s)), 0.265, 0.07, 8, p.glow(0.8, s == 1), -1.0, false)
		Districts.SLUMS:                                          # bins, a heap of bags, a glowing cable reel
			b.uv2 = Vector2(0.3, 0.7)
			for s in 2:
				b.box(Vector3(-0.55 + 0.8 * float(s), 0.45, 0.0), Vector3(0.65, 0.9, 0.55), p.t(Color(0.06, 0.1, 0.085, 0.0)), false)
				b.box(Vector3(-0.55 + 0.8 * float(s), 0.93, 0.0), Vector3(0.7, 0.06, 0.6), p.t(Color(0.04, 0.045, 0.045, 0.0)), false)
			b.sphere(Vector3(0.95, 0.3, 0.25), Vector3(0.4, 0.3, 0.35), 6, 4, Color(0.05, 0.06, 0.05, 0.0))
			b.sphere(Vector3(1.05, 0.28, -0.3), Vector3(0.3, 0.25, 0.3), 6, 4, Color(0.09, 0.08, 0.07, 0.0))
			b.uv2 = Vector2(0.0, 0.3)
			b.box(Vector3(-0.15, 0.62, 0.285), Vector3(0.3, 0.06, 0.02), p.glow(0.7), false)
			b.box(Vector3(0.25, 0.7, 0.285), Vector3(0.2, 0.06, 0.02), p.glow(0.5, true), false)
		_:                                                        # towers: planter, bench, charge posts with glowing caps
			b.uv2 = Vector2(0.0, 0.85)
			b.box(Vector3(-0.5, 0.3, 0.0), Vector3(1.3, 0.6, 0.7), p.t(Color(0.15, 0.15, 0.16, 0.0)), false)
			b.uv2 = Vector2(0.0, 0.9)
			b.box(Vector3(-0.5, 0.62, 0.0), Vector3(1.15, 0.06, 0.55), Color(0.02, 0.05, 0.03, 0.0), false)
			b.uv2 = Vector2(0.0, 0.5)
			for k in 3:
				b.strut(Vector3(-0.9 + 0.4 * float(k), 0.62, 0.0), Vector3(-0.95 + 0.4 * float(k), 1.1 + 0.2 * float(k), 0.05), 0.05, Color(0.04, 0.2, 0.1, 0.0), false)
			b.uv2 = Vector2(0.0, 0.3)
			for k in 3:
				b.box(Vector3(-0.9 + 0.4 * float(k), 1.12 + 0.2 * float(k), 0.05), Vector3(0.1, 0.1, 0.1), p.glow(0.7, k == 1), false)
			b.uv2 = Vector2(0.6, 0.5)
			b.box(Vector3(0.75, 0.46, 0.0), Vector3(0.9, 0.06, 0.4), p.t(Color(0.1, 0.1, 0.105, 0.0)), false)
			b.box(Vector3(0.75, 0.2, 0.0), Vector3(0.8, 0.4, 0.3), p.t(Color(0.06, 0.065, 0.07, 0.0)), false)
			b.uv2 = Vector2(0.0, 0.3)
			b.box(Vector3(0.75, 0.5, 0.2), Vector3(0.9, 0.025, 0.025), p.glow(0.9), false)


static func _rooftop(b: MB, g: Dictionary, p: Pal, near: bool, pf: Callable) -> void:
	var v := p.variant
	var metal := p.t(Color(0.075, 0.08, 0.085, 0.0))
	var dark := p.t(Color(0.045, 0.05, 0.055, 0.0))
	b.uv2 = Vector2(0.7, 0.5)
	match p.d:
		Districts.MARKET:
			if v % 2 == 0:                                       # lantern pavilion under a slate cap
				if near:
					for x: float in [-1.1, 1.1]:
						for z: float in [-1.1, 1.1]:
							_piece(g, pf, "column_small", Vector3(x, 0.0, z), 0.0, Vector3(1.0, 0.8, 1.0), p, 0.5, 0.6, 0.6)
				else:
					b.box(Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 2.4), dark, false)
				_piece(g, pf, "slate_cap", Vector3(0.0, 2.4, 0.0), 0.0, Vector3(1.4, 0.55, 1.4), p, 0.2, 0.7, 0.4)
				b.uv2 = Vector2(0.0, 0.3)
				b.sphere(Vector3(0, 1.5, 0), Vector3(0.45, 0.55, 0.45), 6, 4, p.glow(0.9))
			else:                                                # roof sign facing the street
				b.box(Vector3(-1.6, 0.9, 0), Vector3(0.14, 1.8, 0.14), metal, false)
				b.box(Vector3(1.6, 0.9, 0), Vector3(0.14, 1.8, 0.14), metal, false)
				b.box(Vector3(0, 2.6, 0), Vector3(4.2, 1.5, 0.2), dark, false)
				b.uv2 = Vector2(0.0, 0.3)
				b.quad(Vector3(-1.95, 1.95, 0.105), Vector3(1.95, 1.95, 0.105), Vector3(1.95, 3.3, 0.105), Vector3(-1.95, 3.3, 0.105), Vector3.BACK, Color(1, 1, 1, EM_POSTER), Vector2.ZERO, Vector2.ZERO, _uvq())
				b.box(Vector3(0, 3.4, 0.12), Vector3(4.2, 0.06, 0.06), p.glow(0.9, true), false)
		Districts.FOUNDRY:
			if v % 2 == 0:                                       # twin smokestacks, glowing rims
				for x: float in [-1.0, 1.0]:
					b.cylinder(Vector3(x * 1.1, 0.0, 0.0), 0.62, 6.5 + 1.5 * float(x > 0.0), 8 if near else 5, p.t(Color(0.09, 0.07, 0.06, 0.0)), 0.46, false)
					b.uv2 = Vector2(0.0, 0.3)
					b.cylinder(Vector3(x * 1.1, 6.3 + 1.5 * float(x > 0.0), 0.0), 0.47, 0.18, 8 if near else 5, p.glow(0.85, x > 0.0), -1.0, false)
					b.uv2 = Vector2(0.7, 0.5)
				b.box(Vector3(0, 0.5, 0), Vector3(3.6, 1.0, 1.6), dark, false)
			else:                                                # tank on legs and a pipe gantry
				for x: float in [-0.9, 0.9]:
					for z: float in [-0.9, 0.9]:
						b.box(Vector3(x, 1.0, z), Vector3(0.14, 2.0, 0.14), metal, false)
				b.cylinder(Vector3(0, 2.0, 0), 1.3, 2.2, 10 if near else 6, p.t(Color(0.13, 0.09, 0.07, 0.0)), -1.0, true)
				b.strut(Vector3(1.3, 2.9, 0.0), Vector3(3.4, 2.9, 0.0), 0.22, metal, false)
				b.strut(Vector3(3.4, 2.9, 0.0), Vector3(3.4, 0.0, 0.0), 0.22, metal, false)
				b.uv2 = Vector2(0.0, 0.3)
				b.box(Vector3(0, 4.3, 0), Vector3(2.0, 0.07, 0.07), p.glow(0.9), false)
		Districts.SLUMS:
			if v % 2 == 0:                                       # water tower
				for x: float in [-0.9, 0.9]:
					for z: float in [-0.9, 0.9]:
						b.strut(Vector3(x, 0.0, z), Vector3(x * 0.8, 3.0, z * 0.8), 0.14, metal, false)
				b.cylinder(Vector3(0, 3.0, 0), 1.25, 2.2, 10 if near else 6, p.t(Color(0.1, 0.075, 0.055, 0.0)), -1.0, false)
				b.cylinder(Vector3(0, 5.2, 0), 1.3, 0.7, 10 if near else 6, p.t(Color(0.07, 0.07, 0.075, 0.0)), 0.1, true)
				b.uv2 = Vector2(0.0, 0.3)
				b.box(Vector3(0, 5.95, 0), Vector3(0.12, 0.12, 0.12), Color(1, 1, 1, EM_BEACON), false)
			else:                                                # shack with a lit window, dish and laundry
				b.box(Vector3(0, 1.2, 0), Vector3(3.2, 2.4, 2.6), p.t(Color(0.085, 0.09, 0.09, 0.0)), false)
				b.box(Vector3(0, 2.5, 0.0), Vector3(3.6, 0.14, 3.0), p.t(Color(0.05, 0.055, 0.055, 0.0)), true)
				b.uv2 = Vector2(0.0, 0.3)
				b.quad(Vector3(-0.8, 0.9, 1.305), Vector3(0.8, 0.9, 1.305), Vector3(0.8, 1.8, 1.305), Vector3(-0.8, 1.8, 1.305), Vector3.BACK, p.glow(0.4, true))
				if near:
					b.uv2 = Vector2(0.7, 0.5)
					var s := b.verts.size()
					b.cylinder(Vector3(0, 0, 0), 0.5, 0.1, 8, p.t(Color(0.2, 0.2, 0.21, 0.0)), 0.08)
					b.xform_from(s, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60.0)), Vector3(1.0, 3.3, 0.4)))
					b.strut(Vector3(1.0, 2.55, 0.4), Vector3(1.0, 3.1, 0.4), 0.06, metal, false)
		Districts.TOWERS:
			if v % 2 == 0:                                       # crown: setback block, halo ring, mast
				b.box(Vector3(0, 1.4, 0), Vector3(5.0, 2.8, 5.0), p.t(Color(0.06, 0.07, 0.09, 0.0)), false)
				b.box(Vector3(0, 3.5, 0), Vector3(3.2, 1.4, 3.2), p.t(Color(0.05, 0.06, 0.08, 0.0)), true)
				b.uv2 = Vector2(0.0, 0.3)
				b.box(Vector3(0, 2.85, 0), Vector3(5.1, 0.12, 5.1), p.glow(0.9), false)
				b.cylinder(Vector3(0, 4.2, 0), 0.06, 4.5 if near else 3.5, 4, metal, -1.0, false)
				b.box(Vector3(0, 8.7, 0), Vector3(0.18, 0.18, 0.18), Color(1, 1, 1, EM_BEACON), false)
			else:                                                # helipad ring and glass lantern
				b.uv2 = Vector2(0.4, 0.6)
				b.cylinder(Vector3(0, 0, 0), 3.2, 0.35, 12 if near else 6, p.t(Color(0.09, 0.095, 0.1, 0.0)), -1.0, true)
				b.uv2 = Vector2(0.0, 0.3)
				b.cylinder(Vector3(0, 0.34, 0), 3.0, 0.03, 12 if near else 6, p.glow(0.8, true), -1.0, true)
				b.cylinder(Vector3(0, 0.36, 0), 2.5, 0.03, 12 if near else 6, p.t(Color(0.1, 0.1, 0.11, 0.0)), -1.0, true)
				b.box(Vector3(2.6, 0.9, 2.6), Vector3(0.9, 1.1, 0.9), p.t(Color(0.05, 0.06, 0.07, 0.0)), false)
				b.box(Vector3(2.6, 1.5, 2.6), Vector3(0.95, 0.1, 0.95), p.glow(0.9), false)


# --- layout rules -------------------------------------------------------------------------------------------------------------

static func _item(out: Array[Dictionary], kind: int, x: float, y: float, z: float, yaw: float, variant: int) -> void:
	out.append({"kind": kind, "x": x, "y": y, "z": z, "yaw": yaw, "variant": variant})


## Per-district weights of the ground-floor storefront dressing: [stoop, awning, shutter, colonnade, blade] (the rest of a bay stays bare).
const GROUND := [
	[0.06, 0.45, 0.04, 0.04, 0.14],
	[0.06, 0.08, 0.38, 0.14, 0.06],
	[0.26, 0.24, 0.12, 0.00, 0.10],
	[0.00, 0.18, 0.00, 0.40, 0.08],
]
const BALCONY_RATE := [0.45, 0.0, 0.7, 0.3]               ## chance per face to get a balcony stack
const ESCAPE_RATE := [0.1, 0.42, 0.3, 0.0]
const PARAPET_RATE := [0.2, 0.7, 0.4, 0.1]
const LEDGE_RATE := [0.45, 0.2, 0.1, 0.6]
const ROOF_RATE := [0.65, 0.8, 0.9, 0.75]
const CLUSTER_RATE := [0.55, 0.45, 0.6, 0.45]
const KINDS_ORDER: Array[int] = [STOOP, AWNING, SHUTTER, COLONNADE, BLADE]


## Items {kind, x, y, z, yaw, variant} (kind local to this file) for every lot, by district rules. Deterministic; one random stream per lot.
static func layout(lots: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	for lot in lots:
		if lot.h <= 0.0:
			continue
		var d := Districts.at(lot.cx, lot.cz)
		var bxz := Vector2(-CityLayout.HALF + (float(lot.block_i) + 0.5) * CityLayout.PITCH, -CityLayout.HALF + (float(lot.block_j) + 0.5) * CityLayout.PITCH)
		for axis in 2:
			rng.seed = 7000 + int(lot.index) * 31 + axis * 977
			var sgn := (1.0 if lot.cx > bxz.x else -1.0) if axis == 0 else (1.0 if lot.cz > bxz.y else -1.0)
			var nrm := Vector2(sgn, 0.0) if axis == 0 else Vector2(0.0, sgn)
			var wall: float = (lot.rect.end.x if sgn > 0.0 else lot.rect.position.x) if axis == 0 else (lot.rect.end.y if sgn > 0.0 else lot.rect.position.y)
			var width: float = lot.d if axis == 0 else lot.w
			var centre: float = lot.cz if axis == 0 else lot.cx
			var yaw := atan2(nrm.x, nrm.y)
			var gap := BLOCK_HALF - absf(wall - (bxz.x if axis == 0 else bxz.y))
			_face(out, rng, d, lot, axis, nrm, wall, width, centre, yaw, gap)
		_roof(out, rng, d, lot, bxz)
	return out


const BLOCK_HALF := 30.0


static func _pt(axis: int, wall: float, centre: float, u: float, nrm: Vector2, dz: float) -> Vector2:
	return Vector2(wall + nrm.x * dz, centre + u) if axis == 0 else Vector2(centre + u, wall + nrm.y * dz)


static func _face(out: Array[Dictionary], rng: RandomNumberGenerator, d: int, lot: CityLayout.Lot, axis: int, nrm: Vector2, wall: float, width: float, centre: float, yaw: float, gap: float) -> void:
	var weights: Array = GROUND[d]
	var bays := clampi(int(floor((width - 4.0) / 4.5)), 1, 3)
	var used_col := false
	for bay in bays:
		var u := (float(bay) - float(bays - 1) * 0.5) * 4.5
		var r := rng.randf()
		var acc := 0.0
		var pick := -1
		for i in KINDS_ORDER.size():
			acc += float(weights[i])
			if r < acc:
				pick = KINDS_ORDER[i]
				break
		var variant := rng.randi() % 4
		if pick < 0:
			continue
		if pick == COLONNADE:
			if used_col:
				continue
			used_col = true
		var dz := 0.0
		var y := 0.0
		match pick:
			AWNING:
				y = 3.5 if d != Districts.SLUMS else 3.1
			BLADE:
				y = 3.0
				u += 2.25 * (1.0 if rng.randf() < 0.5 else -1.0)
				u = clampf(u, -width * 0.5 + 1.0, width * 0.5 - 1.0)
			STOOP:
				dz = 0.0
		var p := _pt(axis, wall, centre, u, nrm, dz)
		_item(out, pick, p.x, y, p.y, yaw, variant)
	# balconies: a stack of one to three over the same bay
	if rng.randf() < float(BALCONY_RATE[d]) and lot.h >= 20.0:
		var u2 := (rng.randf() - 0.5) * (width - 8.0)
		var p2 := _pt(axis, wall, centre, u2, nrm, 0.0)
		var floors := 1 + rng.randi() % (3 if d == Districts.SLUMS else 2)
		var v := rng.randi() % 4
		var y0 := 7.0 + float(rng.randi() % 2) * 3.4
		for f in floors:
			_item(out, BALCONY, p2.x, y0 + 3.4 * float(f), p2.y, yaw, v)
	if rng.randf() < float(ESCAPE_RATE[d]) and lot.h >= 16.0:
		var u3 := (-1.0 if rng.randf() < 0.5 else 1.0) * (width * 0.5 - 3.0)
		var p3 := _pt(axis, wall, centre, u3, nrm, 0.0)
		_item(out, FIRE_ESCAPE, p3.x, 3.4, p3.y, yaw, rng.randi() % 4)
	if rng.randf() < float(LEDGE_RATE[d]):
		var tiles := mini(2, int(floor(width / 4.0)) - 1)
		var yl := (4.0 + 4.0 * float(1 + rng.randi() % maxi(1, int(lot.h / 12.0)))) if lot.h > 16.0 else 8.0
		yl = minf(yl, lot.h - 2.0)
		for t in tiles:
			var u4 := (float(t) - float(tiles - 1) * 0.5) * 4.0
			var p4 := _pt(axis, wall, centre, u4, nrm, 0.0)
			_item(out, LEDGE, p4.x, yl, p4.y, yaw, 0)
	if rng.randf() < float(PARAPET_RATE[d]):
		var tiles2 := mini(2, int(floor(width / 4.0)))
		for t in tiles2:
			var u5 := (float(t) - float(tiles2 - 1) * 0.5) * 4.0
			var p5 := _pt(axis, wall, centre, u5, nrm, 0.0)
			_item(out, PARAPET, p5.x, lot.h, p5.y, yaw, rng.randi() % 2)
	if gap >= 4.2 and rng.randf() < float(CLUSTER_RATE[d]):
		var u6 := (rng.randf() - 0.5) * (width - 6.0)
		var p6 := _pt(axis, wall, centre, u6, nrm, minf(gap * 0.5, 2.3))
		_item(out, CLUSTER, p6.x, 0.0, p6.y, yaw, rng.randi() % 4)


static func _roof(out: Array[Dictionary], rng: RandomNumberGenerator, d: int, lot: CityLayout.Lot, bxz: Vector2) -> void:
	rng.seed = 9100 + int(lot.index) * 17
	if rng.randf() > float(ROOF_RATE[d]):
		return
	var x: float = lot.cx + (rng.randf() - 0.5) * maxf(lot.w - 10.0, 1.0)
	var z: float = lot.cz + (rng.randf() - 0.5) * maxf(lot.d - 10.0, 1.0)
	var along_x := rng.randf() < 0.5                         # the front of a rooftop piece turns to the street on one of the lot's two outer sides
	var sgn := (1.0 if lot.cx > bxz.x else -1.0) if along_x else (1.0 if lot.cz > bxz.y else -1.0)
	var yaw := atan2(sgn, 0.0) if along_x else (0.0 if sgn > 0.0 else PI)
	_item(out, ROOFTOP, x, lot.h, z, yaw, rng.randi() % 4)
