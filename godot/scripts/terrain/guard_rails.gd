class_name GuardRails
extends RefCounted
## Guard rails on the mountain roads (wave 105): wherever the ground falls away beside a road (the land falls more than 3.5 m below the road within 9 m of the edge of the flat bench) a steel W-beam on posts follows the edge,
## so a car that overshoots a hairpin is held by the rail instead of flying off the mountain. `segments()` is the list of rail pieces ({a, b} world points at the road surface height, 4 m long),
## `mesh()` the merged visual (posts, two beams, reflectors), the collision is made from the segments near the hero by OutskirtsWorld (a small pool of boxes).
## Roads that get rails: every dirt track and the PASS ROAD, only where the drop is real (a road along a valley floor has none).

const ROADS := ["PASS ROAD", "MOUNTAIN TRACK", "SUMMIT ROAD", "RIDGE TRACK", "QUARRY TRACK"]
const POST_STEP := 4.0
const DROP := 3.5

static var _segs: Array[Dictionary] = []
static var _built := false


static func segments() -> Array[Dictionary]:
	if _built:
		return _segs
	_built = true
	TerrainHeight.warm()
	for road in TerrainRoads.roads():
		if not ROADS.has(String(road["name"])):
			continue
		var pts: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var half: float = float(road["w"]) * 0.5 + 0.9
		var bench: float = float(road["bench"])
		var spans: Array = road.get("spans", [])
		var acc := 0.0
		var run := {-1: [], 1: []}
		for i in range(2, pts.size() - 2):
			var t := (pts[i + 1] - pts[i - 1]).normalized()
			var nrm := Vector2(-t.y, t.x)
			var under := false
			for sp: Vector2i in spans:
				if i >= sp.x - 2 and i <= sp.y + 2:
					under = true
			if under:
				continue
			for side in [-1, 1]:
				var p := pts[i] + nrm * float(side) * half
				var q := pts[i] + nrm * float(side) * (bench + 9.0)           # beyond the flat bench: does the land fall away there?
				var drop := prof[i] - TerrainHeight.height_at(q.x, q.y)
				var edge_drop := prof[i] - TerrainHeight.height_at(p.x, p.y)
				if drop > DROP and edge_drop > -1.5 and OutskirtsSites.inside(p.x, p.y, 4.0) < 0:
					(run[side] as Array).append(Vector3(p.x, prof[i], p.y))
		for side in [-1, 1]:
			var pr: Array = run[side]
			var k := 0
			while k + 1 < pr.size():
				var a: Vector3 = pr[k]
				var b: Vector3 = pr[k + 1]
				if a.distance_to(b) < 14.0:                           # consecutive samples (10 m apart): one piece per sample step
					_segs.append({"a": a, "b": b, "road": String(road["name"])})
				k += 1
	return _segs


static func reset() -> void:
	_segs.clear()
	_built = false


## One merged mesh of the posts and beams of the pieces in `segs`, in the frame of `origin` (the chunk node sits there).
static func mesh(segs: Array, origin := Vector3.ZERO) -> ArrayMesh:
	var mb := OutskirtsKit.MB.new()
	var steel := Color(0.5, 0.52, 0.55, OutskirtsKit.METAL)
	var post := Color(0.36, 0.37, 0.4, OutskirtsKit.METAL)
	var refl := Color(1.0, 0.55, 0.15, OutskirtsKit.GLOW)
	var last := Vector3.INF
	for s: Dictionary in segs:
		var a: Vector3 = (s["a"] as Vector3) - origin                  # local to the chunk node (a node's visibility range is measured to its origin)
		var b: Vector3 = (s["b"] as Vector3) - origin
		if a.distance_to(last) > 0.5:
			mb.box(a + Vector3(0.0, 0.5, 0.0), Vector3(0.12, 1.0, 0.12), post, false)
		mb.box(b + Vector3(0.0, 0.5, 0.0), Vector3(0.12, 1.0, 0.12), post, false)
		mb.strut(a + Vector3(0.0, 0.8, 0.0), b + Vector3(0.0, 0.8, 0.0), 0.2, steel)
		mb.strut(a + Vector3(0.0, 0.52, 0.0), b + Vector3(0.0, 0.52, 0.0), 0.12, steel)
		if int(a.x * 0.5 + a.z * 0.5) % 3 == 0:
			mb.box(a + Vector3(0.0, 0.95, 0.0), Vector3(0.1, 0.1, 0.1), refl, false)
		last = b
	return mb.build(OutskirtsKit.material())
