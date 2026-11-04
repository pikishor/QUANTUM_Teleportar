extends RefCounted
## City kit pieces (Quaternius Downtown City MegaKit, CC0, see docs/THIRD_PARTY.md) converted by tools/blender/model_kit_city.py into assets/models/kit_city_<name>.glb.
## A piece is NOT a node: its triangles are read once from the glb (static cache) and appended, per kind, to the street kit's merged geometry (city_kit.gd), so facade bands,
## rooftop units, street furniture and painted road markings cost triangles and no draw call. Vertex data follows the prop shader (COLOR.rgb = base colour, COLOR.a = emission
## code (0), UV2 = (metallic, roughness)). Local +Z is the front of a prop; road markings lie flat at y = 0 and point along local -Z (or lie along local X for the lane lines).

const Dress := preload("res://scripts/world/city_kit_dress.gd")

const CORNICE := 0          ## 4 m ground-floor cornice band (variant: metal / brick)
const PILASTER := 1         ## brick column at a lot corner
const WINDOW := 2           ## metal window frame on a ground floor wall
const ACUNIT := 3           ## rooftop air-conditioning unit
const BOLLARD := 4
const PLANTER := 5
const DRAIN := 6
const MANHOLE := 7
const ARROW := 8            ## variant: 0 straight, 1 turn left, 2 turn right
const CROSSWALK := 9        ## one 4.5 m zebra block (four across a road)
const DASH := 10            ## 12 m of white dashed line along local X
const DOUBLE := 11          ## 12 m of double yellow line along local X
const DRESS_FIRST := 12     ## the eleven facade, rooftop and sidewalk dressing kinds of city_kit_dress.gd (district composition rules) follow: local kind = DRESS_FIRST + Dress kind
const COUNT := DRESS_FIRST + Dress.COUNT

const NAMES: Array[String] = ["Cornice", "Pilaster", "Window", "AcUnit", "Bollard", "Planter", "Drain", "Manhole", "Arrow", "Crosswalk", "DashLine", "DoubleLine",
		"Stoop", "Awning", "Balcony", "Shutter", "Colonnade", "Parapet", "Rooftop", "FireEscape", "Cluster", "BladeSign", "Ledge"]
## Pieces (glb basenames without "kit_city_") used by a kind, per variant.
const PIECES := {
	CORNICE: ["cornice_metal", "cornice_brick"], PILASTER: ["pilaster"], WINDOW: ["window_metal"], ACUNIT: ["acunit"], BOLLARD: ["bollard"], PLANTER: ["planter"],
	DRAIN: ["drain"], MANHOLE: ["manhole"], ARROW: ["decal_arrow", "decal_arrow_left", "decal_arrow_right"], CROSSWALK: ["decal_crosswalk"], DASH: ["decal_dash"], DOUBLE: ["decal_double"],
}
const FLAT_KINDS := [ARROW, CROSSWALK, DASH, DOUBLE]
const DECAL_Y := 0.03
const TINT_MIX := 0.3

static var _cache: Dictionary = {}          ## piece -> {v, n, c, count, size, front} (non-indexed) or {} when the glb is missing


static func all_pieces() -> Array:
	var out := []
	for k in PIECES:
		for p in PIECES[k]:
			if not out.has(p):
				out.append(p)
	for k in Dress.PIECES:
		for p in Dress.PIECES[k]:
			if not out.has(p):
				out.append(p)
	return out


static func is_flat(kind: int) -> bool:
	return FLAT_KINDS.has(kind)


static func piece(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var d := {}
	var path := "res://assets/models/kit_city_%s.glb" % name
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var root := ps.instantiate()
			var mi := _find_mesh(root)
			if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				d = _flatten(mi.mesh.surface_get_arrays(0))
			root.free()
	_cache[name] = d
	return d


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


static func _flatten(arr: Array) -> Dictionary:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := idx.size()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var c := PackedColorArray()
	v.resize(n)
	nr.resize(n)
	c.resize(n)
	var aabb := AABB(vs[0], Vector3.ZERO)
	for p in vs:
		aabb = aabb.expand(p)
	var top := 0.0
	var top_n := 0
	var low := 0.0
	var low_n := 0
	for i in n:
		var j := idx[i]
		v[i] = vs[j]
		nr[i] = ns[j]
		c[i] = cs[j] if j < cs.size() else Color(0.3, 0.3, 0.3, 1.0)
		if vs[j].y > aabb.size.y * 0.6:
			top += vs[j].z
			top_n += 1
		elif vs[j].y < aabb.size.y * 0.4:
			low += vs[j].z
			low_n += 1
	# which way does the profile bulge? facade pieces carry their overhang on top: that side is the front (+Z)
	var bulge := (top / maxf(float(top_n), 1.0)) - (low / maxf(float(low_n), 1.0))
	return {"v": v, "n": nr, "c": c, "count": n, "size": aabb.size, "front": -1.0 if bulge < -0.01 else 1.0}


static func tris_of(name: String) -> int:
	var d := piece(name)
	return int(d["count"]) / 3 if d.has("count") else 0


## Geometry of a kind (flat arrays like city_kit.gd's make_geo: v, n, uv, uv2, c, count); {} while the glb pieces are missing.
static func make_geo(kind: int, d: int, variant: int, tint: Color) -> Dictionary:
	if kind >= DRESS_FIRST:
		return Dress.make_geo(kind - DRESS_FIRST, d, variant, true, piece)
	var names: Array = PIECES[kind]
	var d_piece := piece(String(names[variant % names.size()]))
	if d_piece.is_empty():
		return {}
	var g := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(), "c": PackedColorArray(), "count": 0}
	var metal := 0.0 if is_flat(kind) else 0.45
	var rough := 0.5 if is_flat(kind) else 0.6
	var sz: Vector3 = d_piece["size"]
	match kind:
		CORNICE:
			for x: float in [-1.0, 1.0]:
				_add(g, d_piece, Vector3(x, 0.0, sz.z * 0.5 - 0.03), 0.0 if float(d_piece["front"]) > 0.0 else PI, tint, metal, rough)
		PILASTER, WINDOW:
			_add(g, d_piece, Vector3(0.0, 0.0, sz.z * 0.5 - 0.03), 0.0 if float(d_piece["front"]) > 0.0 else PI, tint, metal, rough)
		DASH, DOUBLE:
			for x: float in [-3.0, 3.0]:
				_add(g, d_piece, Vector3(x, 0.0, 0.0), 0.0, tint, metal, rough)
		_:
			_add(g, d_piece, Vector3.ZERO, 0.0, tint, metal, rough)
	return g


## Simplified geometry of a dressing kind seen from afar ({} for the kinds without a far level).
static func make_far(kind: int, d: int, variant: int) -> Dictionary:
	return Dress.make_geo(kind - DRESS_FIRST, d, variant, false, piece) if kind >= DRESS_FIRST else {}


static func far_radius(kind: int) -> float:
	return Dress.far_radius(kind - DRESS_FIRST) if kind >= DRESS_FIRST else 0.0


static func _add(g: Dictionary, p: Dictionary, off: Vector3, yaw: float, tint: Color, metal: float, rough: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), off)
	var n: int = p["count"]
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var gc: PackedColorArray = g["c"]
	var guv: PackedVector2Array = g["uv"]
	var guv2: PackedVector2Array = g["uv2"]
	gv.append_array(xf * (p["v"] as PackedVector3Array))
	gn.append_array(Transform3D(xf.basis, Vector3.ZERO) * (p["n"] as PackedVector3Array))
	var cols: PackedColorArray = p["c"]
	var out := PackedColorArray()
	out.resize(n)
	for i in n:
		var c := cols[i]
		out[i] = Color(lerpf(c.r, c.r * tint.r, TINT_MIX), lerpf(c.g, c.g * tint.g, TINT_MIX), lerpf(c.b, c.b * tint.b, TINT_MIX), 0.0)
	gc.append_array(out)
	var uv := PackedVector2Array()
	uv.resize(n)
	guv.append_array(uv)
	uv.fill(Vector2(metal, rough))
	guv2.append_array(uv)
	g["v"] = gv
	g["n"] = gn
	g["c"] = gc
	g["uv"] = guv
	g["uv2"] = guv2
	g["count"] = int(g["count"]) + n


# --- placements (positions only; city_kit.gd stores them) -------------------------------------------------------------------

## Facade, rooftop and road-marking placements as dictionaries {kind (local), x, y, z, yaw, variant}. Deterministic.
static func layout_items(layout: CityLayout) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 190019
	_facades(out, rng, layout)
	_roofs(out, rng, layout)
	_markings(out, rng)
	for it in Dress.layout(layout.lots):                                        # district dressing (own random streams, so the placements above do not move)
		out.append(_item(DRESS_FIRST + int(it["kind"]), it["x"], it["y"], it["z"], it["yaw"], int(it["variant"])))
	return out


static func _item(kind: int, x: float, y: float, z: float, yaw: float, variant := 0) -> Dictionary:
	return {"kind": kind, "x": x, "y": y, "z": z, "yaw": yaw, "variant": variant}


static func _facades(out: Array[Dictionary], rng: RandomNumberGenerator, layout: CityLayout) -> void:
	for lot in layout.lots:
		var bx := -CityLayout.HALF + (float(lot.block_i) + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (float(lot.block_j) + 0.5) * CityLayout.PITCH
		for axis in 2:                                                          # the two faces that look at the street: +-x and +-z of the lot's outer side
			var sgn := (1.0 if lot.cx > bx else -1.0) if axis == 0 else (1.0 if lot.cz > bz else -1.0)
			var nrm := Vector2(sgn, 0.0) if axis == 0 else Vector2(0.0, sgn)
			var wall := (lot.rect.end.x if sgn > 0.0 else lot.rect.position.x) if axis == 0 else (lot.rect.end.y if sgn > 0.0 else lot.rect.position.y)
			var width := lot.d if axis == 0 else lot.w
			var centre := lot.cz if axis == 0 else lot.cx
			var yaw := atan2(nrm.x, nrm.y)
			var tiles := mini(2, int(floor(width / 4.0)) - 1)
			var variant := (lot.tint + axis) % 2
			for t in tiles:
				var u := (float(t) - float(tiles - 1) * 0.5) * 4.0
				var p := Vector2(wall, centre + u) if axis == 0 else Vector2(centre + u, wall)
				out.append(_item(CORNICE, p.x, 4.6, p.y, yaw, variant))
			if rng.randf() < 0.55:                                              # one window frame beside the band
				var wu := (-1.0 if rng.randf() < 0.5 else 1.0) * (width * 0.5 - 3.5)
				var wp := Vector2(wall, centre + wu) if axis == 0 else Vector2(centre + wu, wall)
				out.append(_item(WINDOW, wp.x, 0.5, wp.y, yaw, 0))
			if rng.randf() < 0.5:                                               # pilaster on the street corner
				var cu := (width * 0.5 - 0.2) * (1.0 if rng.randf() < 0.5 else -1.0)
				var cp := Vector2(wall, centre + cu) if axis == 0 else Vector2(centre + cu, wall)
				out.append(_item(PILASTER, cp.x, 0.0, cp.y, yaw, 0))


static func _roofs(out: Array[Dictionary], rng: RandomNumberGenerator, layout: CityLayout) -> void:
	for lot in layout.lots:
		if lot.h <= 0.0 or rng.randf() > 0.6:
			continue
		var n := 1 + rng.randi() % 2
		for i in n:
			var x := lot.rect.position.x + 2.0 + rng.randf() * maxf(lot.w - 4.0, 0.1)
			var z := lot.rect.position.y + 2.0 + rng.randf() * maxf(lot.d - 4.0, 0.1)
			out.append(_item(ACUNIT, x, lot.h, z, float(rng.randi() % 4) * PI * 0.5, 0))


static func _markings(out: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var half := CityLayout.ROAD * 0.5
	var nn := CityLayout.N
	for i in range(1, nn):
		for j in range(1, nn):
			var cx := CityLayout.road_center(i)
			var cz := CityLayout.road_center(j)
			for arm in 4:
				var dir := Vector2(1, 0) if arm == 0 else (Vector2(-1, 0) if arm == 1 else (Vector2(0, 1) if arm == 2 else Vector2(0, -1)))
				var perp := Vector2(-dir.y, dir.x)
				var travel := -dir                                              # towards the junction
				var yaw_travel := atan2(-travel.x, -travel.y)
				var c := Vector2(cx, cz)
				# zebra crossing: four blocks across the road, bars along the road
				for k in 4:
					var lat := (float(k) - 1.5) * 4.54
					var p := c + dir * 13.0 + perp * lat
					out.append(_item(CROSSWALK, p.x, DECAL_Y, p.y, yaw_travel, 0))
				# turn arrow in the lane that drives into the junction (right-hand traffic: the right of the travel direction)
				var right := Vector2(-travel.y, travel.x)
				var pa := c + dir * 24.0 + right * CityLayout.LANE
				var r := rng.randf()
				out.append(_item(ARROW, pa.x, DECAL_Y, pa.y, yaw_travel, 0 if r < 0.6 else (1 if r < 0.8 else 2)))
				# the road segment up to the next junction is drawn once, from its lower end (or from the inner end next to the ring road)
				var positive := arm == 0 or arm == 2
				if not (positive or (arm == 1 and i == 1) or (arm == 3 and j == 1)):
					continue
				var yaw_line := 0.0 if arm < 2 else PI * 0.5
				for k in 4:
					var pc := c + dir * (22.0 + 12.0 * float(k))
					out.append(_item(DOUBLE, pc.x, DECAL_Y, pc.y, yaw_line, 0))
					for s: float in [-1.0, 1.0]:
						var pd := pc + perp * s * (half - 1.4)
						out.append(_item(DASH, pd.x, DECAL_Y, pd.y, yaw_line, 0))
