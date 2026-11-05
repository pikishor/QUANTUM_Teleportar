class_name InteriorPlan
extends RefCounted
## The data of one interior (no nodes, no meshes): a room graph of 1-4 rooms, walls with door gaps and windows, props, anchors, lights, light pools and the collision boxes.
## Pure function of (type, seed): the same pair always gives the same plan, whatever the graphics tier (a tier only decides which DETAIL props are drawn, see InteriorMesher).
## Coordinates are local to the interior: x right, z toward the street (the street room's front wall is at the largest z), y up, floor top at y = 0, the footprint centred on (0, 0).
## Generation order: layout -> openings (doors, windows) -> wall segments -> prop programs (InteriorKinds) -> anchors -> lighting -> walkability repair (a flood fill on a 0.3 m grid removes
## the last-placed big props until the entrance reaches every room and every anchor).

const T := 0.3                       ## wall thickness
const DOOR_W := 1.4                  ## the street door
const IDOOR_W := 1.3                 ## doors between rooms
const DOOR_H := 2.35
const MAX_SPAN := 34.0               ## the whole footprint stays inside 36 m (the interface allows 40)
const NAV_CELL := 0.25
const NAV_RADIUS := 0.35
const SIDE_FRONT := 0
const SIDE_BACK := 1
const SIDE_LEFT := 2
const SIDE_RIGHT := 3
const SIDE_NAMES := ["front", "back", "left", "right"]

var type: StringName = &"bodega"
var seed_value := 0
var spec: Dictionary = {}
var pal: Dictionary = {}
var rng := RandomNumberGenerator.new()

var rooms: Array = []                ## {rect: Rect2 (inner x/z), h, role, wall: Color, floor: Color, ceil: Color, dance: Rect2, parent: int}
var doors: Array = []                ## {a, b (-1 = the street), axis, line, c, w}
var segs: Array = []                 ## wall segments {axis, line, a0, a1, h, owner, side, other, pos_room, neg_room, doors: [[c, w]], windows: [[c, w, y0, y1]]}
var posts: Array = []                ## corner posts (Vector2 centres)
var props: Array = []                ## see InteriorProps; plus room, major, rank, cover
var strips: Array = []               ## emissive strips {a: Vector3, b: Vector3, th, col: Color, em, cls}
var beams: Array = []                ## club light-show rigs {pos: Vector3, col: Color, len, radius}
var pools: Array = []                ## fake light pools {pos: Vector3, radius, col: Color, inten, prio}
var lights: Array = []               ## the (at most two) real lights {pos, col, energy, range}
var anchors: Dictionary = {}         ## StringName -> Array of {pos: Vector3, yaw: float}
var colliders: Array = []            ## AABB (local) of walls, floor, ceilings and the big props
var covers: Array = []               ## {pos: Vector3, r: float, h: float}: props an enemy can hide behind
var entry := Vector3.ZERO
var entry_yaw := 0.0
var exit_pos := Vector3.ZERO
var bounds := Rect2()
var removed_props := 0               ## how many big props the walkability repair had to drop (0 in nearly all seeds)

var _occ: Array = []                 ## Rect2 footprints of big props
var _reserved: Array = []            ## Rect2 areas kept free (vendor spot, in front of a safe or terminal)
var _dance: Array = []               ## Rect2 dance floors (props keep off, people may stand on them)
var _zones: Array = []               ## Rect2 in front of every door
var _wm_used: Array = []             ## per room, per side: Array of [lo, hi] intervals taken by wall-mounted props
var _prop_seq := 0
var _anchor_ops: Array = []          ## deferred ["anchor", ...] steps: [room, kind, n]


static func generate(p_type: StringName, p_seed: int) -> InteriorPlan:
	var plan := InteriorPlan.new()
	plan._run(p_type, p_seed)
	return plan


func _run(p_type: StringName, p_seed: int) -> void:
	type = p_type if InteriorKinds.has_type(p_type) else &"bodega"
	seed_value = p_seed
	spec = InteriorKinds.spec(type)
	pal = spec["pal"]
	rng.seed = int((String(type).hash() * 2654435761 + p_seed * 40503 + 12345) & 0x7fffffffffff)
	_layout()
	_openings()
	_build_segments()
	_windows()
	_programs()
	_decor_pass()
	_anchors_pass()
	_finish_anchors()
	_lighting()
	_wall_colliders()
	_repair_walkability()
	_finish_entry()
	_collect_covers()


# ---------------------------------------------------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------------------------------------------------

func _snap(v: float) -> float:
	return roundf(v * 20.0) / 20.0


func _room_size(rs: Dictionary, shrink: float) -> Vector2:
	var w: Array = rs["w"]
	var d: Array = rs["d"]
	return Vector2(_snap(maxf(rng.randf_range(w[0], w[1]) * shrink, minf(w[0], 3.2))), _snap(maxf(rng.randf_range(d[0], d[1]) * shrink, minf(d[0], 3.2))))


func _layout() -> void:
	var rspecs: Array = spec["rooms"]
	var rects: Array = []
	var parents: Array = []
	var ceil_rng: Array = spec["ceil"]
	rects.append(Rect2(Vector2.ZERO, _room_size(rspecs[0], 1.0)))
	parents.append(-1)
	var kept := [0]
	for k in range(1, rspecs.size()):
		var placed := false
		for attempt in 28:
			var shrink := 1.0 if attempt < 14 else 0.85
			var sz := _room_size(rspecs[k], shrink)
			var pi := rng.randi() % rects.size()
			var pr: Rect2 = rects[pi]
			var side := rng.randi() % 3
			var cand := Rect2()
			if side == 0:                                                   # behind the parent
				var x0 := _snap(rng.randf_range(pr.position.x - (sz.x - 3.2), pr.end.x - 3.2))
				cand = Rect2(Vector2(x0, pr.position.y - T - sz.y), sz)
			else:
				var z0 := 0.0
				match rng.randi() % 3:
					0: z0 = pr.end.y - sz.y                                  # fronts aligned
					1: z0 = pr.position.y                                    # backs aligned
					_: z0 = _snap(rng.randf_range(pr.position.y - (sz.y - 3.2), pr.end.y - 3.2))
				var x := pr.end.x + T if side == 2 else pr.position.x - T - sz.x
				cand = Rect2(Vector2(x, _snap(z0)), sz)
			var overlap := _overlap_with(pr, cand)
			if overlap < 3.1:
				continue
			var ok := true
			var all := cand
			for e: Rect2 in rects:
				if cand.intersects(e.grow(T - 0.02)):
					ok = false
					break
				all = all.merge(e)
			if not ok or all.size.x > MAX_SPAN - 2.0 * T or all.size.y > MAX_SPAN - 2.0 * T:
				continue
			rects.append(cand)
			parents.append(pi)
			kept.append(k)
			placed = true
			break
		if not placed:
			continue
	var total := Rect2()
	for i in rects.size():
		var rr: Rect2 = rects[i]
		total = rr if i == 0 else total.merge(rr)
	total = total.grow(T)
	var shift := Vector2(-_snap(total.position.x + total.size.x * 0.5), -_snap(total.position.y + total.size.y * 0.5))
	for i in rects.size():
		var rr: Rect2 = rects[i]
		rr.position += shift
		var rs: Dictionary = rspecs[kept[i]]
		var h := rng.randf_range(ceil_rng[0], ceil_rng[1])
		if i > 0 and float(ceil_rng[0]) > 4.6:
			h = rng.randf_range(3.2, 3.6)
		var wall_c: Color = _natural(pal["wall"] if i % 2 == 0 else pal["wall2"])
		var fl: Color = _natural(pal["floor"])
		var room := {"rect": rr, "h": snappedf(h, 0.05), "role": String(rs["role"]), "wall": wall_c, "floor": fl.lerp(wall_c, rng.randf() * 0.3), "ceil": pal["ceil"],
			"dance": Rect2(), "parent": parents[i], "spec_i": kept[i]}
		rooms.append(room)
		_wm_used.append([[], [], [], []])
	bounds = total
	bounds.position += shift


func _overlap_with(a: Rect2, b: Rect2) -> float:
	# adjacent rooms share a wall: the overlap length along the wall axis
	if absf(b.position.x - (a.end.x + T)) < 0.03 or absf(b.end.x + T - a.position.x) < 0.03:
		return minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if absf(b.end.y + T - a.position.y) < 0.03:
		return minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	return 0.0


## The wall shared by rooms i and j: {axis, line, lo, hi, side_i} or {} (rooms are exactly one wall thickness apart and overlap along the wall).
func _shared(i: int, j: int) -> Dictionary:
	var a: Rect2 = rooms[i]["rect"]
	var b: Rect2 = rooms[j]["rect"]
	var zlo := maxf(a.position.y, b.position.y)
	var zhi := minf(a.end.y, b.end.y)
	var xlo := maxf(a.position.x, b.position.x)
	var xhi := minf(a.end.x, b.end.x)
	if absf(b.position.x - (a.end.x + T)) < 0.03 and zhi - zlo > 0.05:
		return {"axis": 1, "line": a.end.x + T * 0.5, "lo": zlo, "hi": zhi, "side_i": SIDE_RIGHT}
	if absf(b.end.x + T - a.position.x) < 0.03 and zhi - zlo > 0.05:
		return {"axis": 1, "line": a.position.x - T * 0.5, "lo": zlo, "hi": zhi, "side_i": SIDE_LEFT}
	if absf(b.end.y + T - a.position.y) < 0.03 and xhi - xlo > 0.05:
		return {"axis": 0, "line": a.position.y - T * 0.5, "lo": xlo, "hi": xhi, "side_i": SIDE_BACK}
	if absf(b.position.y - (a.end.y + T)) < 0.03 and xhi - xlo > 0.05:
		return {"axis": 0, "line": a.end.y + T * 0.5, "lo": xlo, "hi": xhi, "side_i": SIDE_FRONT}
	return {}


# ---------------------------------------------------------------------------------------------------------------------
# doors, windows, wall segments
# ---------------------------------------------------------------------------------------------------------------------

func _openings() -> void:
	# the street door in the front wall of the street room
	var r0: Rect2 = rooms[0]["rect"]
	var cx := _snap(rng.randf_range(r0.position.x + 2.3, r0.end.x - 2.3))
	doors.append({"a": 0, "b": -1, "axis": 0, "line": r0.end.y + T * 0.5, "c": cx, "w": DOOR_W})
	# one door from every room to its parent, plus a second one between neighbours that share a long wall
	for i in range(1, rooms.size()):
		var sh := _shared(int(rooms[i]["parent"]), i)
		if sh.is_empty():
			continue
		doors.append(_door_in(sh, int(rooms[i]["parent"]), i))
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if int(rooms[j]["parent"]) == i or int(rooms[i]["parent"]) == j:
				continue
			var sh := _shared(i, j)
			if not sh.is_empty() and float(sh["hi"]) - float(sh["lo"]) > 3.4 and rng.randf() < 0.6:
				doors.append(_door_in(sh, i, j))
	for dd: Dictionary in doors:
		_add_zone(dd)


func _door_in(sh: Dictionary, a: int, b: int) -> Dictionary:
	var lo := float(sh["lo"]) + 0.85 + IDOOR_W * 0.5
	var hi := float(sh["hi"]) - 0.85 - IDOOR_W * 0.5
	var c := _snap((lo + hi) * 0.5 if hi <= lo else rng.randf_range(lo, hi))
	return {"a": a, "b": b, "axis": int(sh["axis"]), "line": float(sh["line"]), "c": c, "w": IDOOR_W}


func _add_zone(dd: Dictionary) -> void:
	var c := float(dd["c"])
	var half := float(dd["w"]) * 0.5 + 0.45
	var line := float(dd["line"])
	if int(dd["axis"]) == 0:
		var z0 := line - T * 0.5 - (2.3 if int(dd["b"]) < 0 else 1.5)
		var z1 := line + T * 0.5 + (0.0 if int(dd["b"]) < 0 else 1.5)
		_zones.append(Rect2(c - half, z0, half * 2.0, z1 - z0))
	else:
		_zones.append(Rect2(line - T * 0.5 - 1.5, c - half, T + 3.0, half * 2.0))


func _build_segments() -> void:
	for i in rooms.size():
		var r: Rect2 = rooms[i]["rect"]
		for side in 4:
			var axis := 0 if side < 2 else 1
			var line := 0.0
			var a0 := 0.0
			var a1 := 0.0
			match side:
				SIDE_FRONT:
					line = r.end.y + T * 0.5
					a0 = r.position.x
					a1 = r.end.x
				SIDE_BACK:
					line = r.position.y - T * 0.5
					a0 = r.position.x
					a1 = r.end.x
				SIDE_LEFT:
					line = r.position.x - T * 0.5
					a0 = r.position.y
					a1 = r.end.y
				_:
					line = r.end.x + T * 0.5
					a0 = r.position.y
					a1 = r.end.y
			var cuts: Array = []
			var pts: Array = [a0, a1]
			for j in rooms.size():
				if j == i:
					continue
				var sh := _shared(i, j)
				if sh.is_empty() or int(sh["side_i"]) != side:
					continue
				cuts.append([float(sh["lo"]), float(sh["hi"]), j])
				pts.append(clampf(float(sh["lo"]), a0, a1))
				pts.append(clampf(float(sh["hi"]), a0, a1))
			pts.sort()
			for k in pts.size() - 1:
				var s0: float = pts[k]
				var s1: float = pts[k + 1]
				if s1 - s0 < 0.02:
					continue
				var mid := (s0 + s1) * 0.5
				var other := -1
				var dropped := false
				for c: Array in cuts:
					if mid > float(c[0]) and mid < float(c[1]):
						if int(c[2]) < i:
							dropped = true
						else:
							other = int(c[2])
				if dropped:
					continue
				var hh := float(rooms[i]["h"])
				if other >= 0:
					hh = maxf(hh, float(rooms[other]["h"]))
				var owner_neg := side == SIDE_FRONT or side == SIDE_RIGHT
				segs.append({"axis": axis, "line": line, "a0": s0, "a1": s1, "h": hh, "owner": i, "side": side, "other": other,
					"pos_room": other if owner_neg else i, "neg_room": i if owner_neg else other, "doors": [], "windows": []})
	for dd: Dictionary in doors:
		for s: Dictionary in segs:
			if int(s["axis"]) == int(dd["axis"]) and absf(float(s["line"]) - float(dd["line"])) < 0.03 and float(dd["c"]) - float(dd["w"]) * 0.5 >= float(s["a0"]) - 0.001 \
					and float(dd["c"]) + float(dd["w"]) * 0.5 <= float(s["a1"]) + 0.001 and (int(dd["b"]) < 0 or (int(s["other"]) == int(dd["b"]) or int(s["other"]) == int(dd["a"]))):
				s["doors"].append([float(dd["c"]), float(dd["w"])])
				break
	# corner posts where no wall segment covers the corner square
	for i in rooms.size():
		var r: Rect2 = rooms[i]["rect"]
		for cx in [r.position.x - T * 0.5, r.end.x + T * 0.5]:
			for cz in [r.position.y - T * 0.5, r.end.y + T * 0.5]:
				var p := Vector2(cx, cz)
				var covered := false
				for s: Dictionary in segs:
					if _seg_rect(s).grow(0.01).has_point(p):
						covered = true
						break
				if not covered:
					for q: Vector2 in posts:
						if q.distance_to(p) < 0.05:
							covered = true
							break
				if not covered:
					posts.append(p)


func _seg_rect(s: Dictionary) -> Rect2:
	if int(s["axis"]) == 0:
		return Rect2(float(s["a0"]), float(s["line"]) - T * 0.5, float(s["a1"]) - float(s["a0"]), T)
	return Rect2(float(s["line"]) - T * 0.5, float(s["a0"]), T, float(s["a1"]) - float(s["a0"]))


## Free intervals of a segment (not taken by doors with a margin).
func _free_intervals(s: Dictionary, margin: float) -> Array:
	var cuts: Array = []
	for d: Array in s["doors"]:
		cuts.append([float(d[0]) - float(d[1]) * 0.5 - margin, float(d[0]) + float(d[1]) * 0.5 + margin])
	for wv: Array in s["windows"]:
		cuts.append([float(wv[0]) - float(wv[1]) * 0.5 - margin, float(wv[0]) + float(wv[1]) * 0.5 + margin])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	var cur := float(s["a0"]) + 0.5
	var end := float(s["a1"]) - 0.5
	for c: Array in cuts:
		if float(c[0]) > cur:
			out.append([cur, minf(float(c[0]), end)])
		cur = maxf(cur, float(c[1]))
	if end > cur:
		out.append([cur, end])
	return out


func _windows() -> void:
	var prob: float = spec["windows"]
	for s: Dictionary in segs:
		if int(s["other"]) >= 0:
			continue
		var street := int(s["side"]) == SIDE_FRONT
		var chance := 1.0 if street else prob * 0.35
		if street and prob < 0.5:
			chance = 0.6
		var iv := _free_intervals(s, 0.5)
		var h := float(s["h"])
		for it: Array in iv:
			var lo: float = it[0]
			var hi: float = it[1]
			var guard := 20
			while hi - lo >= 1.5 and guard > 0:
				guard -= 1
				if rng.randf() > chance * (1.0 if street else 0.6):
					break
				var w := minf(hi - lo - 0.3, rng.randf_range(1.8, 2.7) if street else rng.randf_range(1.0, 1.6))
				if w < 1.0:
					break
				var c := _snap(lo + w * 0.5 + rng.randf_range(0.0, maxf(hi - lo - w, 0.0) * 0.5))
				var y0 := 0.35 if (street and type != &"apartment" and h < 4.6) else 0.95
				var y1 := minf(h - 0.45, 2.55)
				s["windows"].append([c, w, y0, y1])
				lo = c + w * 0.5 + 0.9
				if not street:
					break


# ---------------------------------------------------------------------------------------------------------------------
# prop programs
# ---------------------------------------------------------------------------------------------------------------------

func _quarter(yaw: float) -> bool:
	return absf(sin(yaw)) > 0.5


func _footprint(size: Vector3, yaw: float) -> Vector2:
	return Vector2(size.z, size.x) if _quarter(yaw) else Vector2(size.x, size.z)


## The wall of a room as {face: coordinate of the inner face, lo, hi (along the wall), yaw (the prop's), inward: Vector2}.
func _side_geom(room: int, side: int) -> Dictionary:
	var r: Rect2 = rooms[room]["rect"]
	match side:
		SIDE_BACK:
			return {"face": r.position.y, "lo": r.position.x, "hi": r.end.x, "yaw": PI, "inward": Vector2(0, 1), "axis": 0}
		SIDE_FRONT:
			return {"face": r.end.y, "lo": r.position.x, "hi": r.end.x, "yaw": 0.0, "inward": Vector2(0, -1), "axis": 0}
		SIDE_LEFT:
			return {"face": r.position.x, "lo": r.position.y, "hi": r.end.y, "yaw": -PI * 0.5, "inward": Vector2(1, 0), "axis": 1}
		_:
			return {"face": r.end.x, "lo": r.position.y, "hi": r.end.y, "yaw": PI * 0.5, "inward": Vector2(-1, 0), "axis": 1}


func _pick_side(room: int, which: String) -> int:
	match which:
		"back": return SIDE_BACK
		"front": return SIDE_FRONT
		"left": return SIDE_LEFT
		"right": return SIDE_RIGHT
	return [SIDE_BACK, SIDE_LEFT, SIDE_RIGHT, SIDE_FRONT][rng.randi() % 4]


func _can_fit(room: int, c: Vector2, f: Vector2, gap: float, ignore_reserved := false) -> bool:
	var r: Rect2 = rooms[room]["rect"]
	var rect := Rect2(c - f * 0.5, f)
	if not r.grow(0.001).encloses(rect):
		return false
	for z: Rect2 in _zones:
		if z.intersects(rect):
			return false
	var g := rect.grow(gap)
	for o: Rect2 in _occ:
		if g.intersects(o):
			return false
	if not ignore_reserved:
		for o: Rect2 in _reserved:
			if rect.intersects(o):
				return false
		for o: Rect2 in _dance:
			if rect.intersects(o):
				return false
	return true


## Colour balance of a surface: the kinds' palettes are warm and dark, and under warm light the post grade turned them crimson. 55 % of the saturation goes, the hue stays.
static func _natural(c: Color) -> Color:
	var l := c.get_luminance()
	return c.lerp(Color(l, l, l * 1.04), 0.55)


func _tint_for(kind: String) -> Color:
	var base: Color = pal["wall"]
	var k := float(kind.hash() % 97) / 97.0
	return Color(0.24, 0.23, 0.23).lerp(base, 0.3 + 0.4 * k)


func _new_prop(room: int, kind: String, pos: Vector3, yaw: float, size_override := Vector3.ZERO) -> Dictionary:
	_prop_seq += 1
	var size := InteriorProps.size_of(kind) if size_override == Vector3.ZERO else size_override
	var neon: Array = pal["neon"]
	var flags := InteriorProps.flags_of(kind)
	var p := {"kind": kind, "pos": pos, "yaw": yaw, "size": size, "tint": _tint_for(kind), "acc": neon[rng.randi() % neon.size()], "trim": pal["trim"],
		"seed": int(rng.randi() & 0x7fffffff), "room": room, "major": flags & InteriorProps.F_COLLIDER != 0, "detail": flags & InteriorProps.F_DETAIL != 0, "rank": rng.randf(), "seq": _prop_seq}
	return p


## Place a floor prop with its centre at c (x, z). Returns the prop or {} when it does not fit.
func _place(room: int, kind: String, c: Vector2, yaw: float, gap := 0.7, size_override := Vector3.ZERO) -> Dictionary:
	var size := InteriorProps.size_of(kind) if size_override == Vector3.ZERO else size_override
	var major := InteriorProps.has_collider(kind)
	var f := _footprint(size, yaw)
	if major:
		if not _can_fit(room, c, f, gap):
			return {}
	else:
		var r: Rect2 = rooms[room]["rect"]
		var rect := Rect2(c - f * 0.5, f)
		if not r.grow(0.001).encloses(rect):
			return {}
		for z: Rect2 in _zones:
			if z.intersects(rect):
				return {}
		for o: Rect2 in _occ:
			if rect.grow(0.08).intersects(o):
				return {}
		if kind != "rug":
			for o: Rect2 in _reserved:
				if rect.intersects(o):
					return {}
	var p := _new_prop(room, kind, Vector3(c.x, 0.0, c.y), yaw, size_override)
	props.append(p)
	if major:
		_occ.append(Rect2(c - f * 0.5, f))
	return p


func _free_spot(room: int, kind: String, tries := 40, gap := 0.7, margin := 0.0) -> Array:
	var r: Rect2 = rooms[room]["rect"]
	var size := InteriorProps.size_of(kind)
	for t in tries:
		var yaw := float(rng.randi() % 4) * PI * 0.5
		var f := _footprint(size, yaw)
		var cx := rng.randf_range(r.position.x + f.x * 0.5 + margin, r.end.x - f.x * 0.5 - margin)
		var cz := rng.randf_range(r.position.y + f.y * 0.5 + margin, r.end.y - f.y * 0.5 - margin)
		if InteriorProps.has_collider(kind):
			if _can_fit(room, Vector2(cx, cz), f, gap):
				return [Vector2(cx, cz), yaw]
		else:
			var rect := Rect2(Vector2(cx, cz) - f * 0.5, f)
			var bad := false
			for z: Rect2 in _zones:
				if z.intersects(rect):
					bad = true
					break
			if not bad:
				for o: Rect2 in _occ:
					if rect.grow(0.1).intersects(o):
						bad = true
						break
			if not bad:
				for o: Rect2 in _reserved:
					if rect.intersects(o):
						bad = true
						break
			if not bad:
				for o: Rect2 in _dance:
					if rect.intersects(o):
						bad = true
						break
			if not bad:
				return [Vector2(cx, cz), yaw]
	return []


func _programs() -> void:
	# first: the street room's neon sign on the back wall (the first thing a visitor sees), before anything takes the wall
	_sign_for_room0()
	var rspecs: Array = spec["rooms"]
	for i in rooms.size():
		var rs: Dictionary = rspecs[int(rooms[i]["spec_i"])]
		for step: Array in rs["prog"]:
			_step(i, step)


## Extra decor on top of the type's own program: lights, vents, cable runs, air-conditioners, box piles and bags, a little per square metre. All of it is detail the lower tiers thin out.
func _decor_pass() -> void:
	for i in rooms.size():
		var r: Rect2 = rooms[i]["rect"]
		var area := r.size.x * r.size.y
		var n := clampi(int(area / 5.0), 3, 14)
		for k in n:
			var pick := rng.randi() % 8
			match pick:
				0, 1:
					_op_wm(i, "wall_light", "any")
				2:
					_op_wm(i, "cables", "any")
				3:
					_op_wm(i, "ac_unit", "any")
				4:
					var kind := "box_stack" if rng.randf() < 0.6 else "trash_bag"
					var sp := _free_spot(i, kind, 16, 0.1)
					if not sp.is_empty():
						_place(i, kind, sp[0], rng.randf() * TAU, 0.1)
				5, 6:
					var h: float = rooms[i]["h"]
					var x := rng.randf_range(r.position.x + 1.0, r.end.x - 1.0)
					var z := rng.randf_range(r.position.y + 1.0, r.end.y - 1.0)
					props.append(_new_prop(i, "vent", Vector3(x, h, z), float(rng.randi() % 2) * PI * 0.5))
				_:
					_op_wm(i, "poster", "any")


func _sign_for_room0() -> void:
	var r: Rect2 = rooms[0]["rect"]
	var h: float = rooms[0]["h"]
	var neon: Array = pal["neon"]
	var size := InteriorProps.size_of("neon_sign")
	var sw := clampf(r.size.x * 0.28, 1.6, 3.4)
	size = Vector3(sw, 0.55 if h < 4.5 else 0.9, size.z)
	var y := clampf(h * 0.72, 2.3, 4.2)
	var c := (r.position.x + r.end.x) * 0.5 + rng.randf_range(-r.size.x * 0.15, r.size.x * 0.15)
	var side := SIDE_BACK
	var g := _side_geom(0, side)
	var p := _new_prop(0, "neon_sign", Vector3(c, y, float(g["face"]) + size.z * 0.5 + 0.03), float(g["yaw"]), size)
	p["acc"] = neon[0]
	props.append(p)
	_wm_used[0][side].append([c - sw * 0.5 - 0.3, c + sw * 0.5 + 0.3])
	pools.append({"pos": Vector3(c, 1.9, float(g["face"]) + 1.3), "radius": 3.8, "col": (neon[0] as Color).lerp(Color(1.0, 0.95, 0.88), 0.6 if type != &"club" else 0.0), "inten": 0.6, "prio": 4})


func _step(room: int, step: Array) -> void:
	var op: String = step[0]
	match op:
		"counter":
			_op_counter(room, step[1], step[2] if step.size() > 2 else "back")
		"wall":
			var n := _count(step[2], step[3])
			for k in n:
				_op_wall(room, step[1], str(step[4]))
		"free":
			var n := _count(step[2], step[3])
			for k in n:
				var sp := _free_spot(room, step[1])
				if not sp.is_empty():
					_place(room, step[1], sp[0], sp[1])
		"aisles":
			_op_aisles(room, step[1], _count(step[2], step[3]))
		"sets":
			var n := _count(step[3], step[4])
			for k in n:
				_op_set(room, step[1], step[2], int(step[5]))
		"corner":
			var n := _count(step[2], step[3])
			for k in n:
				_op_corner(room, step[1])
		"detail":
			var n := _count(step[2], step[3])
			for k in n:
				var kind: String = step[1]
				var sp := _free_spot(room, kind, 20, 0.1)
				if not sp.is_empty():
					_place(room, kind, sp[0], rng.randf() * TAU if kind != "rug" else float(rng.randi() % 2) * PI * 0.5, 0.1)
		"wm":
			var n := _count(step[2], step[3])
			for k in n:
				_op_wm(room, step[1], str(step[4]))
		"hang":
			_op_hang(room, int(step[1]))
		"pipes":
			_op_pipes(room, int(step[1]))
		"dance":
			_op_dance(room)
		"beams":
			_op_beams(room, int(step[1]))
		"safe":
			_op_wall_anchor(room, "safe", &"safe")
		"terminal":
			_op_wall_anchor(room, "terminal", &"terminal")
		"hostage":
			_anchor_ops.append([room, &"hostage", 1])
		"officer":
			_anchor_ops.append([room, &"officer", 1])
		"anchor":
			_anchor_ops.append([room, StringName(step[1]), _count(step[2], step[3])])


func _count(a: Variant, b: Variant) -> int:
	return rng.randi_range(int(a), int(b))


func _add_anchor(kind: StringName, pos: Vector3, yaw: float) -> void:
	if not anchors.has(kind):
		anchors[kind] = []
	anchors[kind].append({"pos": pos, "yaw": yaw})


func _op_counter(room: int, kind: String, side_name: String) -> void:
	var r: Rect2 = rooms[room]["rect"]
	var base := InteriorProps.size_of(kind)
	var side := _pick_side(room, side_name)
	var g := _side_geom(room, side)
	var span := float(g["hi"]) - float(g["lo"])
	var wc := minf(base.x, span - 1.9 - 0.4)
	if wc < 1.6:
		return
	wc = snappedf(wc, 0.1)
	var size := Vector3(wc, base.y, base.z)
	var inward: Vector2 = g["inward"]
	var yaw: float = g["yaw"]
	var face := float(g["face"])
	var gap_first := rng.randf() < 0.5
	# the first position (counter at one end of the wall, one distance from it) that clears the door zones and everything placed so far
	var start := 0.0
	var mid := 0.0
	var depth_off := 0.0
	var c := Vector2.ZERO
	var vendor := Vector2.ZERO
	var found := false
	for attempt in 6:
		depth_off = (2.2 if kind == "bar" else 1.95) + 0.4 * float(attempt / 2)
		var gf := gap_first if attempt % 2 == 0 else not gap_first
		start = float(g["lo"]) + 0.2 if not gf else float(g["hi"]) - 0.2 - wc
		mid = start + wc * 0.5
		if int(g["axis"]) == 0:
			c = Vector2(mid, face + inward.y * depth_off)
			vendor = Vector2(mid, face + inward.y * (depth_off - base.z * 0.5 - 0.55))
		else:
			c = Vector2(face + inward.x * depth_off, mid)
			vendor = Vector2(face + inward.x * (depth_off - base.z * 0.5 - 0.55), mid)
		if _can_fit(room, c, _footprint(size, yaw), 0.5):
			gap_first = gf
			found = true
			break
	if not found:
		return
	var res := Rect2(vendor - Vector2(0.45, 0.45), Vector2(0.9, 0.9))
	var p := _place(room, kind, c, yaw, 0.5, size)
	if p.is_empty():
		return
	_reserved.append(res)       # kept clear: a back-bar or a later prop can never wall the vendor in
	# the passage round the counter's free end, from the wall to the counter's customer side
	var gap_lo := float(g["lo"]) if gap_first else start + wc
	var gap_hi := start if gap_first else float(g["hi"])
	var pa := Vector2(gap_lo, float(g["face"])) if int(g["axis"]) == 0 else Vector2(float(g["face"]), gap_lo)
	var pb := Vector2(gap_hi, float(g["face"]) + inward.y * (depth_off + base.z * 0.5)) if int(g["axis"]) == 0 else Vector2(float(g["face"]) + inward.x * (depth_off + base.z * 0.5), gap_hi)
	_reserved.append(Rect2(pa, Vector2.ZERO).expand(pb))
	_add_anchor(&"vendor", Vector3(vendor.x, 0.0, vendor.y), yaw + PI)
	if kind == "bar":
		# back-bar shelves on the wall behind the vendor and stools on the customer side
		var shelf_n := 2
		for k in shelf_n:
			var sh_w := 2.0
			var pos_along := float(g["lo"]) + 1.3 + (span - 2.6) * (float(k) + 0.5) / float(shelf_n)
			var sc := Vector2.ZERO
			if int(g["axis"]) == 0:
				sc = Vector2(pos_along, face + inward.y * (InteriorProps.size_of("shelf").z * 0.5 + 0.04))
			else:
				sc = Vector2(face + inward.x * (InteriorProps.size_of("shelf").z * 0.5 + 0.04), pos_along)
			_place(room, "shelf", sc, yaw, 0.0, Vector3(sh_w, 2.0, 0.5))
		var n_st := int((wc - 0.6) / 0.95)
		for k in n_st:
			var along := mid - wc * 0.5 + 0.45 + float(k) * 0.95
			var sp := Vector2.ZERO
			if int(g["axis"]) == 0:
				sp = Vector2(along, c.y + inward.y * (base.z * 0.5 + 0.55))
			else:
				sp = Vector2(c.x + inward.x * (base.z * 0.5 + 0.55), along)
			_place(room, "stool", sp, 0.0, 0.05)


func _op_wall(room: int, kind: String, which: String) -> void:
	var side := _pick_side(room, which)
	var g := _side_geom(room, side)
	var size := InteriorProps.size_of(kind)
	var yaw: float = g["yaw"]
	var inward: Vector2 = g["inward"]
	var lo := float(g["lo"]) + size.x * 0.5 + 0.1
	var hi := float(g["hi"]) - size.x * 0.5 - 0.1
	if hi < lo:
		return
	var tall := size.y > 0.9
	for t in 24:
		var a := rng.randf_range(lo, hi)
		if tall and _blocked_by_window(room, side, a, size.x):
			continue
		var c := Vector2.ZERO
		var face := float(g["face"])
		if int(g["axis"]) == 0:
			c = Vector2(a, face + inward.y * (size.z * 0.5 + 0.03))
		else:
			c = Vector2(face + inward.x * (size.z * 0.5 + 0.03), a)
		if not _place(room, kind, c, yaw, 0.35).is_empty():
			return


func _blocked_by_window(room: int, side: int, a: float, w: float) -> bool:
	for s: Dictionary in segs:
		if int(s["owner"]) != room or int(s["side"]) != side:
			continue
		for wv: Array in s["windows"]:
			if absf(float(wv[0]) - a) < (float(wv[1]) + w) * 0.5 + 0.1:
				return true
	return false


func _op_aisles(room: int, kind: String, n: int) -> void:
	var r: Rect2 = rooms[room]["rect"]
	var size := InteriorProps.size_of(kind)
	var depth := size.z
	var length := size.x
	var pitch := depth + 1.7                                     # column to column: the unit's depth plus an aisle of at least 1.7 m
	var z_start := r.position.y + (3.3 if kind == "shelf" else 1.4)
	var z_end := r.end.y - 0.5
	var x := r.position.x + 0.9 + depth * 0.5
	var placed := 0
	var col := 0
	while x + depth * 0.5 < r.end.x - 0.9 and placed < n:
		var z := z_start + length * 0.5
		while z + length * 0.5 <= z_end and placed < n:
			if not _place(room, kind, Vector2(x, z), PI * 0.5 if col % 2 == 0 else -PI * 0.5, 0.15).is_empty():
				placed += 1
			z += length + 0.1
		x += pitch
		col += 1


func _op_set(room: int, table: String, seat: String, k: int) -> void:
	var sp := _free_spot(room, table, 40, 1.3, 0.6)
	if sp.is_empty():
		return
	var t := _place(room, table, sp[0], sp[1], 1.0)
	if t.is_empty():
		return
	var c: Vector2 = sp[0]
	var ts := InteriorProps.size_of(table)
	var offs: Array = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	for i in mini(k, 4):
		var o: Vector2 = offs[i]
		var q := c + Vector2(o.x * (ts.x * 0.5 + 0.3), o.y * (ts.z * 0.5 + 0.3))
		_place(room, seat, q, 0.0, 0.02)


func _op_corner(room: int, kind: String) -> void:
	var r: Rect2 = rooms[room]["rect"]
	var size := InteriorProps.size_of(kind)
	var corners: Array = [Vector2(r.position.x + size.x * 0.5 + 0.05, r.position.y + size.z * 0.5 + 0.05), Vector2(r.end.x - size.x * 0.5 - 0.05, r.position.y + size.z * 0.5 + 0.05),
		Vector2(r.position.x + size.x * 0.5 + 0.05, r.end.y - size.z * 0.5 - 0.05), Vector2(r.end.x - size.x * 0.5 - 0.05, r.end.y - size.z * 0.5 - 0.05)]
	corners.shuffle()
	for c: Vector2 in corners:
		if not _place(room, kind, c, 0.0, 0.2).is_empty():
			return


func _op_wm(room: int, kind: String, which: String) -> void:
	var side := _pick_side(room, which)
	var g := _side_geom(room, side)
	var size := InteriorProps.size_of(kind)
	var h := float(rooms[room]["h"])
	var inward: Vector2 = g["inward"]
	var lo := float(g["lo"]) + size.x * 0.5 + 0.35
	var hi := float(g["hi"]) - size.x * 0.5 - 0.35
	if hi < lo:
		return
	var y := {"screen": 1.75, "poster": 1.55, "rack": 1.6}.get(kind, 1.7) as float
	y = minf(y, h - size.y * 0.5 - 0.3)
	for t in 24:
		var a := rng.randf_range(lo, hi)
		if _blocked_by_window(room, side, a, size.x + 0.3) or _wm_taken(room, side, a, size.x):
			continue
		if _near_door(room, side, a, size.x):
			continue
		if kind == "rack" and _blocked_low(room, side, a, size.x):
			continue
		var face := float(g["face"])
		var c := Vector3.ZERO
		if int(g["axis"]) == 0:
			c = Vector3(a, y, face + inward.y * (size.z * 0.5 + 0.02))
		else:
			c = Vector3(face + inward.x * (size.z * 0.5 + 0.02), y, a)
		props.append(_new_prop(room, kind, c, float(g["yaw"])))
		_wm_used[room][side].append([a - size.x * 0.5 - 0.15, a + size.x * 0.5 + 0.15])
		return


func _wm_taken(room: int, side: int, a: float, w: float) -> bool:
	for iv: Array in _wm_used[room][side]:
		if a + w * 0.5 > float(iv[0]) and a - w * 0.5 < float(iv[1]):
			return true
	return false


func _near_door(room: int, side: int, a: float, w: float) -> bool:
	for s: Dictionary in segs:
		if int(s["owner"]) != room or int(s["side"]) != side:
			continue
		for d: Array in s["doors"]:
			if absf(float(d[0]) - a) < (float(d[1]) + w) * 0.5 + 0.2:
				return true
	return false


func _blocked_low(room: int, side: int, a: float, w: float) -> bool:
	return false


func _op_hang(room: int, n: int) -> void:
	var r: Rect2 = rooms[room]["rect"]
	var h: float = rooms[room]["h"]
	var cols := maxi(1, int(ceil(sqrt(float(n) * r.size.x / maxf(r.size.y, 1.0)))))
	var rows := maxi(1, int(ceil(float(n) / float(cols))))
	var k := 0
	for iz in rows:
		for ix in cols:
			if k >= n:
				return
			k += 1
			var x := r.position.x + r.size.x * (float(ix) + 0.5) / float(cols)
			var z := r.position.y + r.size.y * (float(iz) + 0.5) / float(rows)
			props.append(_new_prop(room, "lamp_hang", Vector3(x, h, z), 0.0))
			if k <= 2:
				_add_pool(Vector3(x, h - 0.9, z), 3.4, (pal["neon"] as Array)[1] if rng.randf() < 0.4 else pal["key"], 0.55, 1)


func _op_pipes(room: int, n: int) -> void:
	var r: Rect2 = rooms[room]["rect"]
	var h: float = rooms[room]["h"]
	for k in n:
		var side := rng.randi() % 4
		var g := _side_geom(room, side)
		var len := (float(g["hi"]) - float(g["lo"])) - 1.0
		if len < 2.0:
			continue
		var mid := (float(g["lo"]) + float(g["hi"])) * 0.5
		var inward: Vector2 = g["inward"]
		var off := 0.22 + 0.34 * float(k % 2)
		var pos := Vector3.ZERO
		var yaw := 0.0
		if int(g["axis"]) == 0:
			pos = Vector3(mid, h - 0.3 - 0.02 * k, float(g["face"]) + inward.y * off)
		else:
			pos = Vector3(float(g["face"]) + inward.x * off, h - 0.3 - 0.02 * k, mid)
			yaw = PI * 0.5
		props.append(_new_prop(room, "pipe_run", pos, yaw, Vector3(len, 0.3, 0.3)))


func _op_dance(room: int) -> void:
	var r: Rect2 = rooms[room]["rect"]
	var w := snappedf(r.size.x * 0.46, 0.9)
	var d := snappedf(r.size.y * 0.4, 0.9)
	var c := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 0.4)
	var rect := Rect2(Vector2(snappedf(c.x - w * 0.5, 0.9), snappedf(c.y - d * 0.5, 0.9)), Vector2(w, d))
	rooms[room]["dance"] = rect
	_dance.append(rect.grow(0.4))


func _op_beams(room: int, n: int) -> void:
	var h: float = rooms[room]["h"]
	var dance: Rect2 = rooms[room]["dance"]
	var neon: Array = pal["neon"]
	if dance.size == Vector2.ZERO:
		dance = (rooms[room]["rect"] as Rect2).grow(-2.0)
	for k in n:
		var x := dance.position.x + dance.size.x * (float(k) + 0.5) / float(n)
		var z := dance.position.y + dance.size.y * (0.25 if k % 2 == 0 else 0.75)
		var col: Color = neon[k % neon.size()]
		beams.append({"pos": Vector3(x, h - 0.25, z), "col": col, "len": h - 0.4, "radius": 0.9 + 0.3 * float(k % 3)})
		strips.append({"a": Vector3(x - 0.3, h - 0.12, z), "b": Vector3(x + 0.3, h - 0.12, z), "th": 0.14, "col": col, "em": 2.4, "cls": 8.0})
	for k in mini(4, n):
		var col: Color = neon[k % neon.size()]
		_add_pool(Vector3(dance.position.x + dance.size.x * (float(k) + 0.5) / 4.0, 1.2, dance.position.y + dance.size.y * (0.3 if k % 2 == 0 else 0.7)), 5.2, col, 0.9, 5 if k < 2 else 3)


func _add_pool(pos: Vector3, radius: float, col: Color, inten: float, prio: int) -> void:
	if type != &"club":
		col = col.lerp(Color(0.98, 0.96, 0.92), 0.6)         # colour balance: stacked saturated neon pools wash a room one colour; the club keeps its light show
	pools.append({"pos": pos, "radius": radius, "col": col, "inten": inten, "prio": prio})


func _op_wall_anchor(room: int, kind: String, anchor_kind: StringName) -> void:
	for attempt in 3:
		var side := _pick_side(room, "any")
		var g := _side_geom(room, side)
		var size := InteriorProps.size_of(kind)
		var inward: Vector2 = g["inward"]
		var lo := float(g["lo"]) + size.x * 0.5 + 0.2
		var hi := float(g["hi"]) - size.x * 0.5 - 0.2
		if hi < lo:
			continue
		for t in 16:
			var a := rng.randf_range(lo, hi)
			var face := float(g["face"])
			var c := Vector2.ZERO
			var front := Vector2.ZERO
			if int(g["axis"]) == 0:
				c = Vector2(a, face + inward.y * (size.z * 0.5 + 0.03))
				front = Vector2(a, face + inward.y * (size.z + 0.95))
			else:
				c = Vector2(face + inward.x * (size.z * 0.5 + 0.03), a)
				front = Vector2(face + inward.x * (size.z + 0.95), a)
			var res := Rect2(front - Vector2(0.6, 0.6), Vector2(1.2, 1.2))
			var clear := true
			for o: Rect2 in _occ:
				if o.intersects(res):
					clear = false
					break
			for z: Rect2 in _zones:
				if z.intersects(res):
					clear = false
					break
			if not clear:
				continue
			var p := _place(room, kind, c, float(g["yaw"]), 0.2)
			if p.is_empty():
				continue
			_reserved.append(res)
			_add_anchor(anchor_kind, Vector3(front.x, 0.0, front.y), float(g["yaw"]) + PI)
			return
	# no wall spot: the anchor alone, in the room's free floor
	_anchor_ops.append([room, anchor_kind, 1])


# ---------------------------------------------------------------------------------------------------------------------
# anchors
# ---------------------------------------------------------------------------------------------------------------------

func _spot_free(room: int, p: Vector2, clear: float, inflate_walls := 0.55) -> bool:
	var r: Rect2 = rooms[room]["rect"]
	if not r.grow(-inflate_walls).has_point(p):
		return false
	for o: Rect2 in _occ:
		if o.grow(clear).has_point(p):
			return false
	for z: Rect2 in _zones:
		if z.has_point(p):
			return false
	for o: Rect2 in _reserved:
		if o.has_point(p):
			return false
	for k in anchors:
		for a: Dictionary in anchors[k]:
			var av: Vector3 = a["pos"]
			if Vector2(av.x, av.z).distance_to(p) < 1.15:
				return false
	return true


func _find_anchor_spot(room: int, tries := 60) -> Array:
	var r: Rect2 = rooms[room]["rect"]
	for clear in [0.65, 0.5]:
		for t in tries:
			var p := Vector2(rng.randf_range(r.position.x + 0.7, r.end.x - 0.7), rng.randf_range(r.position.y + 0.7, r.end.y - 0.7))
			if _spot_free(room, p, clear):
				return [p]
	return []


func _anchors_pass() -> void:
	for op: Array in _anchor_ops:
		var room: int = op[0]
		for k in int(op[2]):
			_try_add_anchor(room, op[1])


func _try_add_anchor(room: int, kind: StringName) -> bool:
	var sp := _find_anchor_spot(room)
	if sp.is_empty():
		return false
	var p: Vector2 = sp[0]
	var rc: Vector2 = (rooms[room]["rect"] as Rect2).get_center()
	var to_c := rc - p
	_add_anchor(kind, Vector3(p.x, 0.0, p.y), atan2(-to_c.x, -to_c.y))
	return true


func _finish_anchors() -> void:
	var need: Dictionary = InteriorKinds.GUARANTEED.get(type, {})
	for kind: StringName in need:
		var have := (anchors.get(kind, []) as Array).size()
		var guard := 0
		while have < int(need[kind]) and guard < 80:
			guard += 1
			var room := 0 if kind == &"vendor" or kind == &"terminal" else guard % rooms.size()
			if kind == &"civilian" and type != &"warehouse":
				room = guard % mini(rooms.size(), 2)
			if _try_add_anchor(room, kind):
				have += 1


# ---------------------------------------------------------------------------------------------------------------------
# lighting
# ---------------------------------------------------------------------------------------------------------------------

func area_big(r: Rect2) -> bool:
	return r.size.x * r.size.y > 90.0


func _lighting() -> void:
	var key: Color = pal["key"]
	var neon: Array = pal["neon"]
	for i in rooms.size():
		var r: Rect2 = rooms[i]["rect"]
		var h: float = rooms[i]["h"]
		var long_x := r.size.x >= r.size.y
		var n := clampi(int(minf(r.size.x, r.size.y) / 3.6), 1, 3)
		if type == &"club" and i == 0:
			n = 0
		for k in n:
			var f := (float(k) + 0.5) / float(n)
			var c := key.lerp(Color.WHITE, 0.25)
			if type == &"checkpoint" or type == &"warehouse":
				c = c.lerp(neon[0], 0.2)
			if long_x:
				var z := r.position.y + r.size.y * f
				strips.append({"a": Vector3(r.position.x + 0.8, h - 0.05, z), "b": Vector3(r.end.x - 0.8, h - 0.05, z), "th": 0.14, "col": c, "em": 1.1, "cls": 8.0})
			else:
				var x := r.position.x + r.size.x * f
				strips.append({"a": Vector3(x, h - 0.05, r.position.y + 0.8), "b": Vector3(x, h - 0.05, r.end.y - 0.8), "th": 0.14, "col": c, "em": 1.1, "cls": 8.0})
		_add_pool(Vector3(r.get_center().x, h - 0.6, r.get_center().y), maxf(r.size.x, r.size.y) * 0.75 + 1.0, key, 0.42 if i == 0 else 0.38, 4)
		if area_big(r):
			for q in [0.25, 0.75]:
				_add_pool(Vector3(r.position.x + r.size.x * q, h - 0.8, r.position.y + r.size.y * (1.0 - q)), maxf(r.size.x, r.size.y) * 0.5 + 1.0, key.lerp(neon[(i + 1) % neon.size()], 0.25), 0.4, 3)
		# a neon trim line round the room's back wall
		if i == 0 or type == &"club":
			var col: Color = neon[(i + 1) % neon.size()]
			var y := minf(h - 0.75, 2.75)
			strips.append({"a": Vector3(r.position.x + 0.4, y, r.position.y + 0.04), "b": Vector3(r.end.x - 0.4, y, r.position.y + 0.04), "th": 0.05, "col": col, "em": 2.0, "cls": 5.0})
	# the street's glow through the shop windows
	for s: Dictionary in segs:
		if int(s["side"]) == SIDE_FRONT and int(s["owner"]) == 0 and int(s["other"]) < 0 and not (s["windows"] as Array).is_empty():
			var wv: Array = s["windows"][0]
			var street_col: Color = (neon[1] if neon.size() > 1 else neon[0]).lerp(key, 0.5)      # the street's neon, warmed toward the room's key light: never a red wash
			_add_pool(Vector3(float(wv[0]), 1.4, float(s["line"]) - 1.5), 4.4, street_col, 0.5, 3)
			break
	pools.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prio"]) > int(b["prio"]))
	var r0: Rect2 = rooms[0]["rect"]
	var h0: float = rooms[0]["h"]
	lights.append({"pos": Vector3(r0.get_center().x, minf(h0 - 0.5, 3.0), r0.get_center().y), "col": key.lerp(Color(1.0, 0.95, 0.88), 0.6), "energy": 1.0, "range": maxf(r0.size.x, r0.size.y) * 0.9 + 2.0})
	var r1: Rect2 = rooms[1]["rect"] if rooms.size() > 1 and type == &"apartment" else r0
	var accent: Color = (neon[0] as Color).lerp(Color(0.85, 0.92, 1.0), 0.72)             # the second real light is an accent, balanced against the key (a pure neon red lit whole rooms red)
	lights.append({"pos": Vector3(r1.get_center().x + (r1.size.x * 0.25 if r1 == r0 else 0.0), 2.3, r1.position.y + r1.size.y * 0.35), "col": accent, "energy": 0.9, "range": 6.5})


# ---------------------------------------------------------------------------------------------------------------------
# collision
# ---------------------------------------------------------------------------------------------------------------------

## Solid pieces of a segment as [a0, a1, y0, y1]. For colliders only doors cut the wall (a window is glass nobody walks through); for the mesh windows cut it too.
func seg_pieces(s: Dictionary, with_windows: bool) -> Array:
	var cuts: Array = []
	var h := float(s["h"])
	for d: Array in s["doors"]:
		cuts.append([float(d[0]) - float(d[1]) * 0.5, float(d[0]) + float(d[1]) * 0.5, 0.0, DOOR_H])
	if with_windows:
		for wv: Array in s["windows"]:
			cuts.append([float(wv[0]) - float(wv[1]) * 0.5, float(wv[0]) + float(wv[1]) * 0.5, float(wv[2]), float(wv[3])])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	var cur := float(s["a0"])
	for c: Array in cuts:
		if float(c[0]) > cur + 0.01:
			out.append([cur, float(c[0]), 0.0, h])
		if float(c[2]) > 0.001:
			out.append([float(c[0]), float(c[1]), 0.0, float(c[2])])
		if float(c[3]) < h - 0.001:
			out.append([float(c[0]), float(c[1]), float(c[3]), h])
		cur = maxf(cur, float(c[1]))
	if float(s["a1"]) > cur + 0.01:
		out.append([cur, float(s["a1"]), 0.0, h])
	return out


func _box_of(axis: int, line: float, a0: float, a1: float, y0: float, y1: float) -> AABB:
	if axis == 0:
		return AABB(Vector3(a0, y0, line - T * 0.5), Vector3(a1 - a0, y1 - y0, T))
	return AABB(Vector3(line - T * 0.5, y0, a0), Vector3(T, y1 - y0, a1 - a0))


func _wall_colliders() -> void:
	for s: Dictionary in segs:
		for pc: Array in seg_pieces(s, false):
			colliders.append(_box_of(int(s["axis"]), float(s["line"]), float(pc[0]), float(pc[1]), float(pc[2]), float(pc[3])))
	for p: Vector2 in posts:
		var hh := 3.2
		colliders.append(AABB(Vector3(p.x - T * 0.5, 0.0, p.y - T * 0.5), Vector3(T, hh + 2.0, T)))
	# the street door is closed: a plug in its gap (the way out is the door interaction, never a walk-through)
	var dd: Dictionary = doors[0]
	colliders.append(AABB(Vector3(float(dd["c"]) - float(dd["w"]) * 0.5, 0.0, float(dd["line"]) - T * 0.5), Vector3(float(dd["w"]), DOOR_H, T)))
	for i in rooms.size():
		var r: Rect2 = rooms[i]["rect"]
		var h: float = rooms[i]["h"]
		colliders.append(AABB(Vector3(r.position.x - T, h, r.position.y - T), Vector3(r.size.x + 2.0 * T, 0.4, r.size.y + 2.0 * T)))
	colliders.append(AABB(Vector3(bounds.position.x - 0.5, -0.6, bounds.position.y - 0.5), Vector3(bounds.size.x + 1.0, 0.6, bounds.size.y + 1.0)))
	_collect_prop_colliders(0)


var _prop_collider_start := 0


func _collect_prop_colliders(from_prop: int) -> void:
	_prop_collider_start = colliders.size()
	for p: Dictionary in props:
		if not bool(p["major"]):
			continue
		var kind: String = p["kind"]
		var pos: Vector3 = p["pos"]
		var yaw: float = p["yaw"]
		var b := Basis(Vector3.UP, yaw)
		for lb: Array in InteriorProps.local_boxes(kind, p["size"]):
			var c: Vector3 = pos + b * (lb[0] as Vector3)
			var sz: Vector3 = lb[1]
			var half := Vector3(absf(b.x.x) * sz.x + absf(b.z.x) * sz.z, sz.y, absf(b.x.z) * sz.x + absf(b.z.z) * sz.z) * 0.5
			colliders.append(AABB(c - half, half * 2.0))


# ---------------------------------------------------------------------------------------------------------------------
# walkability repair (flood fill on a 0.3 m grid)
# ---------------------------------------------------------------------------------------------------------------------

## Runs the flood fill: returns {reached: PackedByteArray, ...}; used by the repair here and a different one in the test.
func nav_unreachable() -> Array:
	var gx0 := bounds.position.x
	var gz0 := bounds.position.y
	var nx := int(ceil(bounds.size.x / NAV_CELL)) + 1
	var nz := int(ceil(bounds.size.y / NAV_CELL)) + 1
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	# everything outside the rooms and the door gaps is blocked; walls and props are blocked by their inflated boxes
	var open := PackedByteArray()
	open.resize(nx * nz)
	for room: Dictionary in rooms:
		_mark(open, (room["rect"] as Rect2), nx, nz, gx0, gz0, 1)
	for dd: Dictionary in doors:
		var hw := float(dd["w"]) * 0.5
		if int(dd["b"]) < 0:
			continue
		if int(dd["axis"]) == 0:
			_mark(open, Rect2(float(dd["c"]) - hw, float(dd["line"]) - T * 0.5 - 0.05, hw * 2.0, T + 0.1), nx, nz, gx0, gz0, 1)
		else:
			_mark(open, Rect2(float(dd["line"]) - T * 0.5 - 0.05, float(dd["c"]) - hw, T + 0.1, hw * 2.0), nx, nz, gx0, gz0, 1)
	for bx: AABB in colliders:
		if bx.position.y > 1.6 or bx.end.y < 0.1:
			continue
		if bx.size.y > 20.0:
			continue
		_mark(blocked, Rect2(bx.position.x - NAV_RADIUS, bx.position.z - NAV_RADIUS, bx.size.x + 2.0 * NAV_RADIUS, bx.size.z + 2.0 * NAV_RADIUS), nx, nz, gx0, gz0, 1)
	var start := Vector2(entry.x, entry.z)
	var si := int((start.x - gx0) / NAV_CELL) + int((start.y - gz0) / NAV_CELL) * nx
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var queue := PackedInt32Array()
	queue.append(si)
	seen[si] = 1
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var cx := cur % nx
		var cz := cur / nx
		for k in 4:
			var ax := cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var az := cz + (1 if k == 2 else (-1 if k == 3 else 0))
			if ax < 0 or az < 0 or ax >= nx or az >= nz:
				continue
			var ni := ax + az * nx
			if seen[ni] == 1 or blocked[ni] == 1 or open[ni] == 0:
				continue
			seen[ni] = 1
			queue.append(ni)
	var bad: Array = []
	for i in rooms.size():
		if not _room_reached(seen, (rooms[i]["rect"] as Rect2).grow(-0.3), nx, nz, gx0, gz0):
			bad.append(["room", i])
	for kind in anchors:
		var list: Array = anchors[kind]
		for k in list.size():
			var ap: Vector3 = list[k]["pos"]
			if not _nav_reached(seen, blocked, Vector2(ap.x, ap.z), nx, nz, gx0, gz0):
				bad.append(["anchor", kind, k])
	return bad


func _mark(grid: PackedByteArray, rect: Rect2, nx: int, nz: int, gx0: float, gz0: float, v: int) -> void:
	var x0 := maxi(int(floor((rect.position.x - gx0) / NAV_CELL)), 0)
	var x1 := mini(int(ceil((rect.end.x - gx0) / NAV_CELL)), nx - 1)
	var z0 := maxi(int(floor((rect.position.y - gz0) / NAV_CELL)), 0)
	var z1 := mini(int(ceil((rect.end.y - gz0) / NAV_CELL)), nz - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var cx := gx0 + (float(x) + 0.5) * NAV_CELL
			var cz := gz0 + (float(z) + 0.5) * NAV_CELL
			if cx >= rect.position.x and cx < rect.end.x and cz >= rect.position.y and cz < rect.end.y:
				grid[x + z * nx] = v


func _room_reached(seen: PackedByteArray, rect: Rect2, nx: int, nz: int, gx0: float, gz0: float) -> bool:
	var x0 := maxi(int(floor((rect.position.x - gx0) / NAV_CELL)), 0)
	var x1 := mini(int(ceil((rect.end.x - gx0) / NAV_CELL)), nx - 1)
	var z0 := maxi(int(floor((rect.position.y - gz0) / NAV_CELL)), 0)
	var z1 := mini(int(ceil((rect.end.y - gz0) / NAV_CELL)), nz - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if seen[x + z * nx] == 1:
				return true
	return false


func _nav_reached(seen: PackedByteArray, blocked: PackedByteArray, p: Vector2, nx: int, nz: int, gx0: float, gz0: float) -> bool:
	var cx := int((p.x - gx0) / NAV_CELL)
	var cz := int((p.y - gz0) / NAV_CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var z := cz + dz
			if x >= 0 and z >= 0 and x < nx and z < nz and seen[x + z * nx] == 1:
				return true
	return false


func _repair_walkability() -> void:
	entry = Vector3(float(doors[0]["c"]), 0.0, (rooms[0]["rect"] as Rect2).end.y - 1.5)
	var guard := 0
	var moved := 0
	while guard < 28:
		var bad := nav_unreachable()
		if bad.is_empty():
			return
		guard += 1
		var rooms_bad := false
		var anchors_bad: Array = []
		for b: Array in bad:
			if b[0] == "room":
				rooms_bad = true
			else:
				anchors_bad.append(b)
		if not rooms_bad and moved < 8 and not anchors_bad.is_empty():
			# an anchor in a pocket: move it to a reachable-looking free spot instead of deleting furniture
			anchors_bad.sort_custom(func(x: Array, y: Array) -> bool: return int(x[2]) > int(y[2]))
			for b: Array in anchors_bad:
				var list: Array = anchors[b[1]]
				var old: Vector3 = (list[int(b[2])] as Dictionary)["pos"]
				list.remove_at(int(b[2]))
				var room := maxi(_room_at(Vector2(old.x, old.z)), 0)
				if not _try_add_anchor(room, b[1]):
					_try_add_anchor(0, b[1])
				moved += 1
			continue
		# otherwise drop the last-placed big prop that is not a counter, and rebuild the box list
		var drop := -1
		for i in range(props.size() - 1, -1, -1):
			var p: Dictionary = props[i]
			if bool(p["major"]) and p["kind"] != "counter" and p["kind"] != "bar":
				drop = i
				break
		if drop < 0:
			return
		props.remove_at(drop)
		removed_props += 1
		colliders.resize(_prop_collider_start)
		_collect_prop_colliders(0)
		_rebuild_occ()


func _rebuild_occ() -> void:
	_occ.clear()
	for p: Dictionary in props:
		if bool(p["major"]):
			var f := _footprint(p["size"], float(p["yaw"]))
			var pos: Vector3 = p["pos"]
			_occ.append(Rect2(Vector2(pos.x, pos.z) - f * 0.5, f))


func _finish_entry() -> void:
	var dd: Dictionary = doors[0]
	var r0: Rect2 = rooms[0]["rect"]
	entry = Vector3(float(dd["c"]), 0.0, r0.end.y - 1.5)
	entry_yaw = 0.0
	exit_pos = Vector3(float(dd["c"]), 0.0, r0.end.y - 0.25)


func _collect_covers() -> void:
	for p: Dictionary in props:
		if bool(p["major"]) and float((p["size"] as Vector3).y) >= 0.9 and p["kind"] != "gate":
			var pos: Vector3 = p["pos"]
			var f := _footprint(p["size"], float(p["yaw"]))
			covers.append({"pos": pos, "r": maxf(f.x, f.y) * 0.5, "h": float((p["size"] as Vector3).y)})
	# cover anchors beside the first few cover props, on the far side from the entrance
	var n := 0
	for cv: Dictionary in covers:
		if n >= 4:
			break
		var cp: Vector3 = cv["pos"]
		var away := Vector2(cp.x - entry.x, cp.z - entry.z)
		if away.length() < 0.1:
			continue
		var spot := Vector2(cp.x, cp.z) + away.normalized() * (float(cv["r"]) + 0.8)
		var room := _room_at(spot)
		if room >= 0 and _spot_free(room, spot, 0.65, 0.65):
			_add_anchor(&"cover", Vector3(spot.x, 0.0, spot.y), atan2(away.x, away.y))
			n += 1
	# optional anchors: drop the ones the entrance cannot reach
	var bad := nav_unreachable()
	var drop: Array = []
	for b: Array in bad:
		if b[0] == "anchor" and b[1] == &"cover":
			drop.append(int(b[2]))
	drop.sort()
	drop.reverse()
	for k: int in drop:
		(anchors[&"cover"] as Array).remove_at(k)


func _room_at(p: Vector2) -> int:
	for i in rooms.size():
		if (rooms[i]["rect"] as Rect2).has_point(p):
			return i
	return -1


# ---------------------------------------------------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------------------------------------------------

func floor_rects() -> Array:
	var out: Array = []
	for r: Dictionary in rooms:
		out.append(r["rect"])
	for dd: Dictionary in doors:
		if int(dd["b"]) < 0:
			continue
		var hw := float(dd["w"]) * 0.5
		if int(dd["axis"]) == 0:
			out.append(Rect2(float(dd["c"]) - hw, float(dd["line"]) - T * 0.5, hw * 2.0, T))
		else:
			out.append(Rect2(float(dd["line"]) - T * 0.5, float(dd["c"]) - hw, T, hw * 2.0))
	return out


func wall_rects() -> Array:
	var out: Array = []
	for s: Dictionary in segs:
		for pc: Array in seg_pieces(s, false):
			if float(pc[2]) < 0.5:
				var b := _box_of(int(s["axis"]), float(s["line"]), float(pc[0]), float(pc[1]), 0.0, 1.0)
				out.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	for p: Vector2 in posts:
		out.append(Rect2(p.x - T * 0.5, p.y - T * 0.5, T, T))
	var dd: Dictionary = doors[0]
	out.append(Rect2(float(dd["c"]) - float(dd["w"]) * 0.5, float(dd["line"]) - T * 0.5, float(dd["w"]), T))
	for o: Rect2 in _occ:
		out.append(o)
	return out


## Wall lines (pairs of x/z points) for a line-drawn minimap: the pieces of every segment at floor level.
func wall_segments() -> PackedVector2Array:
	var out := PackedVector2Array()
	for s: Dictionary in segs:
		for pc: Array in seg_pieces(s, false):
			if float(pc[2]) > 0.5:
				continue
			if int(s["axis"]) == 0:
				out.append(Vector2(float(pc[0]), float(s["line"])))
				out.append(Vector2(float(pc[1]), float(s["line"])))
			else:
				out.append(Vector2(float(s["line"]), float(pc[0])))
				out.append(Vector2(float(s["line"]), float(pc[1])))
	return out


## A stable text signature of everything the generator decided (determinism tests compare two of these).
func signature() -> String:
	var parts := PackedStringArray()
	parts.append(String(type) + str(seed_value))
	for r: Dictionary in rooms:
		var rc: Rect2 = r["rect"]
		parts.append("R%.2f,%.2f,%.2f,%.2f,%.2f,%s" % [rc.position.x, rc.position.y, rc.size.x, rc.size.y, float(r["h"]), r["role"]])
	for dd: Dictionary in doors:
		parts.append("D%d,%d,%.2f,%.2f" % [int(dd["a"]), int(dd["b"]), float(dd["line"]), float(dd["c"])])
	for s: Dictionary in segs:
		parts.append("S%d,%.2f,%.2f,%.2f,%d,%d" % [int(s["axis"]), float(s["line"]), float(s["a0"]), float(s["a1"]), (s["doors"] as Array).size(), (s["windows"] as Array).size()])
	for p: Dictionary in props:
		var pp: Vector3 = p["pos"]
		parts.append("P%s,%.2f,%.2f,%.2f,%.2f,%d" % [p["kind"], pp.x, pp.y, pp.z, float(p["yaw"]), int(p["seed"]) % 100000])
	for k in anchors:
		for a: Dictionary in anchors[k]:
			var ap: Vector3 = a["pos"]
			parts.append("A%s,%.2f,%.2f" % [k, ap.x, ap.z])
	parts.append("C%d,L%d,B%d,Q%d" % [colliders.size(), pools.size(), beams.size(), strips.size()])
	return "\n".join(parts)
