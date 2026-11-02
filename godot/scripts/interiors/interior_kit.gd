class_name InteriorKit
extends RefCounted
## The interior kit: Quaternius modular sci-fi pieces (CC0, see docs/THIRD_PARTY.md) converted by tools/blender/model_kit.py into assets/models/kit_<name>.glb.
## A piece is NOT a node: its triangles are read once from the glb (static cache), scaled to the prop's footprint and appended to the interior's merged surface
## builder, so a kit prop costs triangles and no draw call. Vertex data written for assets/shaders/interior_surface.gdshader: COLOR rgb = albedo (the kit's own colour,
## the Accent material takes the prop's neon colour), alpha = emission; UV.x = surface class (10 kit metal, 11 kit phase glass, 12 kit light), UV.y = per-object phase.
## glb data: COLOR_0 = material colour, UV0.x = material id (0 Main, 1 DarkGrey, 2 Accent, 3 DarkAccent, 4 Black, 5 Light, 6 Glass, 7 Pipes), UV0.y = height 0..1.

const C_KIT := 10.0
const C_PHASE := 11.0
const C_LIGHT := 12.0

## Prop kind -> [glb piece, yaw offset of the mesh (radians), footprint scale (mesh is fitted to the DEFS size on every axis)]
const PIECES := {
	"kit_teleporter": "teleporter_2", "kit_pad": "teleporter_1", "kit_pod": "pod", "kit_server": "computer", "kit_console": "computer_small", "kit_capsule": "capsule",
	"kit_crate": "crate", "kit_crate_long": "crate_long", "kit_container": "container", "kit_shelf": "shelf", "kit_shelf_tall": "shelf_tall", "kit_vessel": "vessel_tall",
	"kit_laser": "laser", "kit_column": "column", "kit_base": "base", "kit_pipes": "pipes",
}
const MESH_YAW := PI

static var _cache: Dictionary = {}          ## piece -> {verts, norms, cols, ids, hts, idx, size: Vector3} or {} when the file is missing


static func is_kit(kind: String) -> bool:
	return PIECES.has(kind)


static func piece_names() -> Array:
	return PIECES.values()


## The parsed triangles of a piece ({} when the glb is not there, e.g. before the first import).
static func data(piece: String) -> Dictionary:
	if _cache.has(piece):
		return _cache[piece]
	var d := {}
	var path := "res://assets/models/kit_%s.glb" % piece
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var root := ps.instantiate()
			var mi := _find_mesh(root)
			if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var arr: Array = mi.mesh.surface_get_arrays(0)
				var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var aabb := AABB(v[0], Vector3.ZERO)
				for p in v:
					aabb = aabb.expand(p)
				d = {"verts": v, "norms": arr[Mesh.ARRAY_NORMAL], "cols": arr[Mesh.ARRAY_COLOR], "uvs": uv, "idx": arr[Mesh.ARRAY_INDEX], "size": aabb.size}
			root.free()
	_cache[piece] = d
	return d


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


static func tris_of(kind: String) -> int:
	var d := data(String(PIECES.get(kind, "")))
	return (d["idx"] as PackedInt32Array).size() / 3 if d.has("idx") else 0


## Append the piece of `kind` to `sb` in prop-local space (feet at y 0 + dy, centred, fitted to `size`; wall-mounted pieces pass dy = -size.y / 2). The caller then places it with xform_from.
static func append(sb: RefCounted, kind: String, size: Vector3, acc: Color, tint: Color, phase: float, dy := 0.0) -> bool:
	var d := data(String(PIECES.get(kind, "")))
	if d.is_empty():
		return false
	var src: Vector3 = d["size"]
	var k := Vector3(size.x / maxf(src.x, 0.01), size.y / maxf(src.y, 0.01), size.z / maxf(src.z, 0.01))
	var basis := Basis(Vector3.UP, MESH_YAW)
	var v: PackedVector3Array = d["verts"]
	var nr: PackedVector3Array = d["norms"]
	var cl: PackedColorArray = d["cols"]
	var uv: PackedVector2Array = d["uvs"]
	var base: int = sb.verts.size()
	for i in v.size():
		var id := roundi(uv[i].x)
		var c := cl[i] if cl.size() > i else Color(0.4, 0.4, 0.4)
		var cls := C_KIT
		var em := 0.0
		var col := Color(c.r * 0.55, c.g * 0.55, c.b * 0.55).lerp(tint, 0.18)          # the kit is lighter than the interiors' palette: pulled into it
		match id:
			2, 3:
				col = acc.lerp(Color(0.1, 0.1, 0.12), 0.0 if id == 2 else 0.7)
				cls = C_LIGHT
				em = 1.15 if id == 2 else 0.35
			5:
				col = acc.lerp(Color.WHITE, 0.4)
				cls = C_LIGHT
				em = 1.6
			6:
				col = acc.lerp(Color(0.6, 0.8, 1.0), 0.5)
				cls = C_PHASE
				em = 0.9
		var p := basis * (v[i] * k) + Vector3(0, dy, 0)
		sb.vertex(p, (basis * nr[i]).normalized(), Color(col.r, col.g, col.b, em), Vector2(cls, phase))
	var ix: PackedInt32Array = d["idx"]
	for t in range(0, ix.size(), 3):
		sb.tri(base + ix[t], base + ix[t + 1], base + ix[t + 2])
	return true
