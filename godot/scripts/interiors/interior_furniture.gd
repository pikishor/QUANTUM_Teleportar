class_name InteriorFurniture
extends RefCounted
## Real furniture for the interiors: Kenney's Furniture Kit (CC0, see docs/THIRD_PARTY.md) converted by tools/open_models/convert_furniture.py into assets/models/furn_<piece>.glb.
## Like InteriorKit a piece is NOT a node: its triangles are read once, fitted to a footprint and appended to the interior's merged SURFACE builder (no draw call, no collider of its
## own; the prop's DEFS box stays the collider). `build()` returns false when the prop kind has no recipe or a glb is missing, and InteriorProps then draws its box version.
## A recipe is a list of parts [piece, centre x, base y, centre z, width, height, depth, yaw] in the prop's local frame (front = -Z, the pieces' backs are +Z like the kit's own).
## Vertex data written for assets/shaders/interior_surface.gdshader: COLOR rgb = albedo (fabric takes the room's accent and tint, wood and metal are pulled into the palette),
## alpha = emission (lamps, screens); UV.x = surface class (3 metal, 4 soft / painted, 7 screen, 8 strip light), UV.y = per-object phase.

const C_METAL := 3.0
const C_SOFT := 4.0
const C_SCREEN := 7.0
const C_STRIP := 8.0

## glb pieces that are lit screens (their glass class becomes an emissive panel)
const SCREENS := ["monitor", "tv_modern", "tv_vintage", "laptop"]

static var _cache: Dictionary = {}
## QT_FURNITURE=0 puts every prop back to its procedural boxes (before / after captures, and a safety valve); tests flip it.
static var enabled := OS.get_environment("QT_FURNITURE") != "0"


## The parsed triangles of a piece ({} when the glb is not there).
static func data(piece: String) -> Dictionary:
	if _cache.has(piece):
		return _cache[piece]
	var d := {}
	var path := "res://assets/models/furn_%s.glb" % piece
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var root := ps.instantiate()
			var mi := InteriorKit._find_mesh(root)
			if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var arr: Array = mi.mesh.surface_get_arrays(0)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var aabb := AABB(v[0], Vector3.ZERO)
				for p in v:
					aabb = aabb.expand(p)
				d = {"verts": v, "norms": arr[Mesh.ARRAY_NORMAL], "cols": arr[Mesh.ARRAY_COLOR], "uvs": arr[Mesh.ARRAY_TEX_UV], "idx": arr[Mesh.ARRAY_INDEX], "size": aabb.size}
			root.free()
	_cache[piece] = d
	return d


static func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.55 + c.b * 0.15


## Appends one fitted piece (centre x / z, feet at y) to `sb`; false when the glb is missing.
static func append_piece(sb: RefCounted, piece: String, centre: Vector3, fit: Vector3, yaw: float, acc: Color, tint: Color, trim: Color, phase: float) -> bool:
	var d := data(piece)
	if d.is_empty():
		return false
	var src: Vector3 = d["size"]
	var k := Vector3(fit.x / maxf(src.x, 0.01), fit.y / maxf(src.y, 0.01), fit.z / maxf(src.z, 0.01))
	if absf(sin(yaw)) > 0.7:                                       # a quarter turn: the model's x runs along the world z (scale in the model's own axes, then turn it)
		k = Vector3(fit.z / maxf(src.x, 0.01), fit.y / maxf(src.y, 0.01), fit.x / maxf(src.z, 0.01))
	var basis := Basis(Vector3.UP, yaw)
	var v: PackedVector3Array = d["verts"]
	var nr: PackedVector3Array = d["norms"]
	var cl: PackedColorArray = d["cols"]
	var uv: PackedVector2Array = d["uvs"]
	var screen := SCREENS.has(piece)
	var base: int = sb.verts.size()
	for i in v.size():
		var id := roundi(uv[i].x)
		var c := cl[i] if cl.size() > i else Color(0.5, 0.5, 0.5)
		var lum := _lum(c)
		var col := Color(c.r * 0.5, c.g * 0.5, c.b * 0.5).lerp(trim, 0.12)
		var cls := C_SOFT
		var em := 0.0
		match id:
			1:
				col = Color(lum * 0.34, lum * 0.34, lum * 0.37)
				cls = C_METAL
			5:
				col = acc.lerp(Color(1.0, 0.85, 0.6), 0.55)
				cls = C_STRIP
				em = 1.5
			6:
				if screen:
					col = acc.lerp(Color(0.5, 0.85, 1.0), 0.5) * 0.55
					cls = 7.0
					em = 1.0
				else:
					col = Color(0.08, 0.13, 0.16)
					cls = C_METAL
			8:
				col = acc.lerp(tint, 0.5) * (0.5 + lum * 0.55)
			9:
				col = Color(0.05 + c.g * 0.05, 0.1 + c.g * 0.22, 0.06 + c.g * 0.08)
			_:
				if c.b > c.r * 1.08 and c.g > c.r * 1.08:      # the kit's pale cyan metal and white goods: neutral, a little lighter than wood
					var g := lum * 0.62
					col = Color(g, g * 1.02, g * 1.05)
					cls = C_METAL
		var p := basis * (v[i] * k) + centre
		sb.vertex(p, (basis * nr[i]).normalized(), Color(col.r, col.g, col.b, em), Vector2(cls, phase))
	var ix: PackedInt32Array = d["idx"]
	for t in range(0, ix.size(), 3):
		sb.tri(base + ix[t], base + ix[t + 1], base + ix[t + 2])
	return true


## Prop kinds this class draws (everything in `recipe`).
static func has(kind: String) -> bool:
	return enabled and RECIPES.has(kind)


## kind -> the pieces it is made of, as fractions of the prop size: [piece, fx, y_m, fz, fw, h_m_or_frac, fd, yaw]
## fx / fz in -0.5 .. 0.5 of the width / depth, fw / fd as fractions of width / depth, h in metres. A negative h is a fraction of the prop height.
const RECIPES := {
	"couch": [["sofa", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"couch_chair": [["armchair", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"table": [["table", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"table_round": [["table_round", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"stool": [["stool", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"chair": [["chair", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"desk": [["desk", 0.0, 0.0, 0.2, 1.0, -0.66, 0.55, 0.0], ["monitor", -0.22, 0.78, 0.3, 0.3, 0.42, 0.07, 0.0], ["keyboard", -0.22, 0.78, 0.0, 0.3, 0.04, 0.12, 0.0],
		["chair_cushion", 0.1, 0.0, -0.33, 0.28, 0.92, 0.33, 0.0]],
	"bed": [["bed_double", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, -1.5708]],
	"cot": [["bed_single", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, -1.5708]],
	"plant": [["plant", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"lamp_floor": [["lamp_floor", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"bin": [["trashcan", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"cabinet": [["bookcase_wide", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"crate_small": [["box_closed", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"rug": [["rug_rect", 0.0, 0.01, 0.0, 1.0, 0.02, 1.0, 0.0]],
	"bookcase": [["bookcase", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"bookcase_wide": [["bookcase_wide", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"tv_unit": [["tv_cabinet", 0.0, 0.0, 0.0, 1.0, 0.5, 1.0, 0.0], ["tv_modern", 0.0, 0.5, 0.0, 0.55, 0.62, 0.3, 0.0], ["speaker_small", -0.42, 0.0, 0.0, 0.14, 0.9, 0.5, 0.0]],
	"side_table": [["side_table", 0.0, 0.0, 0.0, 1.0, 0.62, 1.0, 0.0], ["lamp_table", -0.2, 0.62, 0.0, 0.3, 0.5, 0.6, 0.0], ["books", 0.22, 0.62, 0.0, 0.3, 0.14, 0.45, 0.0]],
	"coffee_table": [["table_coffee", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0], ["books", 0.2, 0.46, 0.0, 0.22, 0.12, 0.28, 0.4]],
	"kitchen_run": [["kitchen_cabinet", -0.33, 0.0, 0.0, 0.34, -1.0, 1.0, 0.0], ["kitchen_sink", 0.0, 0.0, 0.0, 0.33, -1.0, 1.0, 0.0], ["kitchen_cabinet", 0.33, 0.0, 0.0, 0.34, -1.0, 1.0, 0.0],
		["kitchen_upper", -0.33, 1.45, 0.2, 0.34, 0.7, 0.5, 0.0], ["kitchen_upper", 0.33, 1.45, 0.2, 0.34, 0.7, 0.5, 0.0], ["coffee_machine", 0.34, 0.9, 0.0, 0.14, 0.34, 0.5, 0.0],
		["microwave", -0.33, 0.9, 0.0, 0.2, 0.34, 0.55, 0.0]],
	"fridge_home": [["fridge", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"coat_rack": [["coat_rack", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"wash_station": [["sink", 0.0, 0.0, 0.0, 0.8, -0.55, 0.7, 0.0], ["mirror", 0.0, 1.1, 0.4, 0.8, 0.7, 0.2, 0.0]],
	"box_pile": [["box_closed", -0.22, 0.0, -0.1, 0.42, 0.55, 0.45, 0.2], ["box_open", 0.25, 0.0, 0.1, 0.5, 0.5, 0.5, -0.3], ["box_closed", 0.0, 0.55, 0.0, 0.4, 0.45, 0.42, 0.5]],
	"tv_old": [["side_table", 0.0, 0.0, 0.0, 1.0, 0.7, 1.0, 0.0], ["tv_vintage", 0.0, 0.7, 0.0, 0.7, 0.45, 0.6, 0.0]],
	"speaker": [["speaker", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
	"armchair": [["armchair", 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, 0.0]],
}


## Draws prop `p` ({kind, pos, yaw, size, tint, acc, trim, seed}) from its recipe into `sb`; false (nothing appended) when it has none or a glb is missing.
static func build(sb: RefCounted, p: Dictionary) -> bool:
	var kind: String = p["kind"]
	if not enabled:
		return false
	if kind == "couch" and (p["size"] as Vector3).x < 1.5:
		kind = "couch_chair"
	if not RECIPES.has(kind):
		return false
	var parts: Array = RECIPES[kind]
	for pt: Array in parts:
		if data(String(pt[0])).is_empty():
			return false
	var size: Vector3 = p["size"]
	var tint: Color = p["tint"]
	var acc: Color = p["acc"]
	var trim: Color = p["trim"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var ph := rng.randf() * 20.0
	var s0: int = sb.verts.size()
	for pt: Array in parts:
		var h := float(pt[5])
		var fit := Vector3(size.x * float(pt[4]), size.y * -h if h < 0.0 else h, size.z * float(pt[6]))
		if fit.x < 0.01 or fit.z < 0.01:
			continue
		var centre := Vector3(size.x * float(pt[1]), float(pt[2]), size.z * float(pt[3]))
		append_piece(sb, String(pt[0]), centre, fit, float(pt[7]), acc, tint, trim, ph)
	sb.xform_from(s0, Transform3D(Basis(Vector3.UP, float(p["yaw"])), p["pos"]))
	return true
