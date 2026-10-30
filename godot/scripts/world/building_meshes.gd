extends RefCounted
## Unit facade meshes for the building classes. A building is a stack of boxes ("parts") in unit space (x, z in [-0.5, 0.5],
## y in [0, 1]) that the instance transform scales to (width, height, depth) metres. The vertex attributes carry the wall frame
## for the facade shader (see assets/shaders/building_core.gdshaderinc):
##   wall:  UV = (start, end) along the wall in the shader's signed coordinate, UV2 = (y0, y1) of the part
##   roof / ledge (up faces): UV = (xmin, zmin), UV2 = (xmax, zmax); ledges store xmin - 100.
## The same part tables feed the colliders, so what you see is what you can stand on.

const MB := preload("res://scripts/world/mesh_builder.gd")

## Part rows: [x0, x1, z0, z1, y0, y1] in unit space, stacked bottom to top.
const CLASSES := {
	&"block": [[-0.5, 0.5, -0.5, 0.5, 0.0, 1.0]],
	&"stepped": [[-0.5, 0.5, -0.5, 0.5, 0.0, 0.80], [-0.36, 0.36, -0.36, 0.36, 0.80, 1.0]],
	&"offset": [[-0.5, 0.5, -0.5, 0.5, 0.0, 0.78], [-0.5, 0.14, -0.34, 0.34, 0.78, 1.0]],
	&"tiered": [[-0.5, 0.5, -0.5, 0.5, 0.0, 0.80], [-0.42, 0.42, -0.42, 0.42, 0.80, 0.92], [-0.30, 0.30, -0.30, 0.30, 0.92, 1.0]],
	&"podium": [[-0.5, 0.5, -0.5, 0.5, 0.0, 0.16], [-0.38, 0.38, -0.38, 0.38, 0.16, 1.0]],
	&"landmark": [[-0.5, 0.5, -0.5, 0.5, 0.0, 0.62], [-0.40, 0.40, -0.40, 0.40, 0.62, 0.84], [-0.26, 0.26, -0.26, 0.26, 0.84, 1.0]],
}

const ORDER: Array[StringName] = [&"block", &"stepped", &"offset", &"tiered", &"podium", &"landmark"]


static func build(cls: StringName) -> ArrayMesh:
	var parts: Array = CLASSES[cls]
	var b := MB.new()
	for i in parts.size():
		var p: Array = parts[i]
		_walls(b, p)
		if i == parts.size() - 1:
			_roof(b, p[0], p[1], p[2], p[3], p[5], false)
		else:
			_ledge(b, p, parts[i + 1])
	return b.build(null, true, false)


static func _walls(b, p: Array) -> void:
	var x0: float = p[0]
	var x1: float = p[1]
	var z0: float = p[2]
	var z1: float = p[3]
	var y0: float = p[4]
	var y1: float = p[5]
	var u2 := Vector2(y0, y1)
	# +Z wall: along = +x
	b.quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, Color.WHITE, Vector2(x0, x1), u2)
	# -Z wall: along = -x
	b.quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD, Color.WHITE, Vector2(-x1, -x0), u2)
	# +X wall: along = -z
	b.quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3.RIGHT, Color.WHITE, Vector2(-z1, -z0), u2)
	# -X wall: along = +z
	b.quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, Color.WHITE, Vector2(z0, z1), u2)


static func _roof(b, x0: float, x1: float, z0: float, z1: float, y: float, ledge: bool) -> void:
	if x1 - x0 < 0.0001 or z1 - z0 < 0.0001:
		return
	var ux := x0 - (100.0 if ledge else 0.0)
	b.quad(Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0), Vector3.UP, Color.WHITE,
			Vector2(ux, z0), Vector2(x1, z1))


## The roof of a lower part around the smaller part standing on it: four strips (front, back, left, right).
static func _ledge(b, p: Array, up: Array) -> void:
	var y: float = p[5]
	_roof(b, p[0], p[1], up[3], p[3], y, true)            # +z strip
	_roof(b, p[0], p[1], p[2], up[2], y, true)            # -z strip
	_roof(b, p[0], up[0], up[2], up[3], y, true)          # -x strip
	_roof(b, up[1], p[1], up[2], up[3], y, true)          # +x strip


## Collision boxes (center, size) of a building of footprint (w, d) and height h centred at (cx, cz).
static func collision_boxes(cls: StringName, cx: float, cz: float, w: float, d: float, h: float) -> Array[Array]:
	var out: Array[Array] = []
	for p: Array in CLASSES[cls]:
		var size := Vector3((p[1] - p[0]) * w, (p[5] - p[4]) * h, (p[3] - p[2]) * d)
		var center := Vector3(cx + (p[0] + p[1]) * 0.5 * w, (p[4] + p[5]) * 0.5 * h, cz + (p[2] + p[3]) * 0.5 * d)
		out.append([center, size])
	return out


## Is the world point inside any part of a building of this class? (p relative: dx, dy, dz from the footprint centre, y from the ground)
static func contains(cls: StringName, dx: float, y: float, dz: float, w: float, d: float, h: float) -> bool:
	for p: Array in CLASSES[cls]:
		if y >= p[4] * h and y < p[5] * h and dx > p[0] * w and dx < p[1] * w and dz > p[2] * d and dz < p[3] * d:
			return true
	return false


## Parts of a class as unit rows (for rooftop placement: the topmost part holds the roof clutter).
static func top_part(cls: StringName) -> Array:
	var parts: Array = CLASSES[cls]
	return parts[parts.size() - 1]
