class_name SettlementPlan
extends RefCounted
## The layout of a town (wave 112): where the street runs, which lots stand beside it and along the side streets, what stands on each lot (a house spec of SettlementHouses or a special building of
## SettlementSpecials), the lawns, drives, paths, fences, trees, lamps, mailboxes, the parked cars, the doors, the tall anchors, the people. Pure data, deterministic from the site id, in the TOWN FRAME
## (OutskirtsSites.to_world: x across, z along the main street, origin on the pad). `SettlementPlan.build(site, street)` takes the main street as a polyline of town-frame points (the real road through
## the pad) and returns the plan object; the style functions below fill it.
##
## A placement: {kind: &"house" | &"special", type (special builder), spec (the house spec), x, z, yaw (rotation of the part about Y in the town frame: front is -Z of the part), w, d, door (Vector3 local to the
## part, base of the front door), doors (door x list), interior (country interior type), name}.

const STYLE_KEYS := [&"farm", &"industrial", &"suburb", &"harbour", &"resort", &"lodge", &"outpost"]
const STREET_HALF := 11.2                      ## the road ribbon (6 + 2.6 verge) plus the sidewalk strip
const SIDE_HALF := 5.8                         ## a side street: 3.4 asphalt + 2.4 sidewalk

var id: StringName
var style: StringName
var r := 100.0                                 ## half width across
var ln := 160.0                                ## half length along the street
var rng := RandomNumberGenerator.new()
var street: PackedVector2Array = PackedVector2Array()
var sides: Array[Dictionary] = []              ## side streets {a: Vector2, b: Vector2, w}
var items: Array[Dictionary] = []              ## houses and specials (placements)
var props: Array[Dictionary] = []              ## {kind, x, z, yaw, s, seed}
var ground: Array[Dictionary] = []             ## flat patches {kind, pts: PackedVector2Array (convex polygon), y, p}
var fences: Array[Dictionary] = []             ## {a, b, kind, h}
var parked: Array[Array] = []                  ## [x, z, heading, kind index]
var folk: Array[Dictionary] = []               ## {role, x, z, yaw}
var anchors: Array[Dictionary] = []            ## {kind, name, x, z, height, radius}
var helipads: Array[Dictionary] = []           ## {x, z, y, r}
var pets: Array[Dictionary] = []               ## {kind, x, z}
var livestock: Array[Dictionary] = []          ## {kind, x, z, r, n}
var houses := 0                                ## enterable homes placed (a front door each: a terrace counts its units)
var cap := 999                                 ## the rows stop when this many homes stand
var failed: Array[String] = []                 ## specials and landmarks that did not fit (look-dev and the test read it)
var pad := Vector2.ZERO                        ## the QUANTUM PAD (fast travel) of the town: a clear spot on the lawn beside the street near the entrance
var board := Vector2.ZERO                      ## the notice board (the town's USE spot); its glowing ring lies 2.4 m in front of it, towards the street
var board_front := Vector2(1.0, 0.0)           ## unit vector from the board towards the street
var sea := Vector2.ZERO                        ## unit vector (town frame) towards the nearest large water, ZERO when there is none within 330 m
var sea_d := 1.0e9                             ## distance to that water from the pad centre
var _occ: Array[Array] = []                    ## occupied footprints [cx, cz, hx, hz, yaw]


static func build(site: Dictionary, street_pts: PackedVector2Array) -> SettlementPlan:
	var p := SettlementPlan.new()
	p.id = StringName(site["id"])
	p.style = StringName(site["style"])
	p.r = float(site["r"])
	p.ln = float(site["len"])
	p.rng.seed = hash(String(site["id"])) & 0x7fffffff
	p.street = street_pts
	if p.street.size() < 2:
		p.street = PackedVector2Array([Vector2(0.0, -p.ln), Vector2(0.0, p.ln)])
	p._find_sea(site)
	p._reserve_spots()
	var target := int(site.get("houses", 30))
	p.cap = int(float(target) * 1.12) + 2
	match p.style:
		&"farm":
			SettlementStyles.farm(p, target)
		&"industrial":
			SettlementStyles.industrial(p, target)
		&"suburb":
			SettlementStyles.suburb(p, target)
		&"harbour":
			SettlementStyles.harbour(p, target)
		&"resort":
			SettlementStyles.resort(p, target)
		&"lodge":
			SettlementStyles.lodge(p, target)
		&"outpost":
			SettlementStyles.outpost(p, target)
	return p


## Where the water is (rings of samples round the pad centre; the pad itself is dry): the mean direction of the wet samples, weighted towards the near ones.
func _find_sea(site: Dictionary) -> void:
	var acc := Vector2.ZERO
	for rr in [70.0, 110.0, 160.0, 220.0, 290.0, 330.0]:
		for k in 24:
			var a := TAU * float(k) / 24.0
			var lp := Vector2(cos(a), sin(a)) * float(rr)
			var w := OutskirtsSites.to_world(site, Vector3(lp.x, 0.0, lp.y))
			if TerrainHeight.is_water(w.x, w.z):
				acc += lp.normalized() * (330.0 / float(rr))
				sea_d = minf(sea_d, float(rr))
	if acc.length() > 0.5:
		sea = acc.normalized()


## The pad of the fast travel and the notice board: spots beside the street that no lot may take (the style fills the rest).
func _reserve_spots() -> void:
	var sa := street_at(-ln * 0.5)
	var ta: Vector2 = sa[1]
	var na := Vector2(ta.y, -ta.x)
	pad = (sa[0] as Vector2) + na * (STREET_HALF + 10.0)
	occupy(pad.x, pad.y, 6.5, 6.5, 0.0)
	var sb := street_at(4.0)
	var tb: Vector2 = sb[1]
	var nb := Vector2(tb.y, -tb.x)
	board = (sb[0] as Vector2) - nb * (STREET_HALF + 3.0)
	board_front = nb
	occupy(board.x, board.y, 3.2, 3.2, 0.0)
	occupy(board.x + nb.x * 2.4, board.y + nb.y * 2.4, 2.0, 2.0, 0.0)
	add_prop(&"board", board.x, board.y, yaw_for_front(nb), 1.0)
	var ring: Array[Vector2] = []
	var rc := board + nb * 2.4
	for k in 12:
		var a := TAU * float(k) / 12.0
		ring.append(rc + Vector2(cos(a), sin(a)) * 1.3)
	add_ground(&"glow", ring, 0.14, 0.0, Color(0.3, 0.95, 1.0))


## The point on the pad's ellipse in direction `dir` (unit, town frame), scaled by `f` (1 = the edge).
func edge_point(dir: Vector2, f: float) -> Vector2:
	var k := sqrt((dir.x / r) * (dir.x / r) + (dir.y / ln) * (dir.y / ln))
	return dir * (f / maxf(k, 0.0001))


# --- the main street ----------------------------------------------------------------------------------------------------------------------------

## Centre line point and unit tangent of the main street at town-frame z (the polyline runs roughly along z).
func street_at(z: float) -> Array:
	var best := 0
	var bd := 1.0e9
	for i in street.size() - 1:
		var a := street[i]
		var b := street[i + 1]
		var lo := minf(a.y, b.y)
		var hi := maxf(a.y, b.y)
		var dd := 0.0 if (z >= lo and z <= hi) else minf(absf(z - lo), absf(z - hi))
		if dd < bd:
			bd = dd
			best = i
	var a2 := street[best]
	var b2 := street[best + 1]
	var t := 0.0 if absf(b2.y - a2.y) < 0.001 else clampf((z - a2.y) / (b2.y - a2.y), -0.5, 1.5)
	var c := a2.lerp(b2, t)
	var tg := (b2 - a2).normalized()
	if tg.y < 0.0:
		tg = -tg
	return [c, tg]


## Distance from (x, z) to the main street centre line.
func dist_to_street(p: Vector2) -> float:
	var best := 1.0e9
	for i in street.size() - 1:
		best = minf(best, _seg_dist(p, street[i], street[i + 1]))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func dist_to_sides(p: Vector2) -> float:
	var best := 1.0e9
	for s in sides:
		if s.get("dead", false):
			continue
		best = minf(best, _seg_dist(p, s["a"], s["b"]))
	return best


## True when the point is inside the flat part of the pad (the ellipse), `shrink` metres in.
func inside(p: Vector2, shrink := 0.0) -> bool:
	var rr := maxf(r - shrink, 1.0)
	var ll := maxf(ln - shrink, 1.0)
	return (p.x / rr) * (p.x / rr) + (p.y / ll) * (p.y / ll) < 0.9


# --- placing things ------------------------------------------------------------------------------------------------------------------------------

static func _corners(cx: float, cz: float, hx: float, hz: float, yaw: float) -> Array[Vector2]:
	var s := sin(yaw)
	var c := cos(yaw)
	var out: Array[Vector2] = []
	for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var lx: float = float(k[0]) * hx
		var lz: float = float(k[1]) * hz
		out.append(Vector2(cx + lx * c + lz * s, cz - lx * s + lz * c))
	return out


static func _obb_overlap(a: Array, b: Array) -> bool:
	var ca := _corners(a[0], a[1], a[2], a[3], a[4])
	var cb := _corners(b[0], b[1], b[2], b[3], b[4])
	for poly in [ca, cb]:
		for i in 4:
			var e: Vector2 = (poly[(i + 1) % 4] as Vector2) - (poly[i] as Vector2)
			var ax := Vector2(-e.y, e.x).normalized()
			var amin := 1.0e9
			var amax := -1.0e9
			var bmin := 1.0e9
			var bmax := -1.0e9
			for q: Vector2 in ca:
				var pr := q.dot(ax)
				amin = minf(amin, pr)
				amax = maxf(amax, pr)
			for q: Vector2 in cb:
				var pr2 := q.dot(ax)
				bmin = minf(bmin, pr2)
				bmax = maxf(bmax, pr2)
			if amax < bmin or bmax < amin:
				return false
	return true


## Is a footprint (centre, half sizes, yaw) free: inside the pad, off every street, off every other footprint (with `gap` metres between)?
func fits(cx: float, cz: float, hx: float, hz: float, yaw: float, gap := 2.0, street_clear := 0.0) -> bool:
	var cs := _corners(cx, cz, hx + gap * 0.5, hz + gap * 0.5, yaw)
	for q in cs:
		if not inside(q, 3.0):
			return false
	var pts: Array[Vector2] = [Vector2(cx, cz)]
	pts.append_array(cs)
	for k in 4:
		pts.append((cs[k] + cs[(k + 1) % 4]) * 0.5)
	for q in pts:
		if dist_to_street(q) < STREET_HALF + street_clear:
			return false
		if not sides.is_empty() and dist_to_sides(q) < SIDE_HALF + street_clear:
			return false
	var me: Array = [cx, cz, hx + gap * 0.5, hz + gap * 0.5, yaw]
	for o in _occ:
		if absf(float(o[0]) - cx) > 40.0 or absf(float(o[1]) - cz) > 40.0:
			continue
		if _obb_overlap(me, o):
			return false
	return true


func occupy(cx: float, cz: float, hx: float, hz: float, yaw: float) -> void:
	_occ.append([cx, cz, hx, hz, yaw])


## Register a building on a lot. Returns the item (or {} when it does not fit).
func place(kind: StringName, type_or_spec: Variant, cx: float, cz: float, yaw: float, w: float, d: float, interior := &"", gap := 2.0, street_clear := 0.0, landmark := true) -> Dictionary:
	if not fits(cx, cz, w * 0.5, d * 0.5, yaw, gap, street_clear):
		var moved := _nudge(cx, cz, w, d, yaw, gap, street_clear) if (kind == &"special" and landmark) else Vector2.INF
		if not moved.is_finite():
			if kind == &"special" and landmark:
				failed.append("%s at (%.0f, %.0f)" % [type_or_spec if type_or_spec is StringName else "special", cx, cz])
			return {}
		cx = moved.x
		cz = moved.y
	var it := {"kind": kind, "x": cx, "z": cz, "yaw": yaw, "w": w, "d": d, "interior": interior}
	if houses >= cap and kind == &"house" and type_or_spec is Dictionary and not (type_or_spec as Dictionary).has("shopfront"):
		return {}
	if type_or_spec is Dictionary:
		it["spec"] = type_or_spec
	else:
		it["type"] = type_or_spec
	items.append(it)
	occupy(cx, cz, w * 0.5, d * 0.5, yaw)
	if kind == &"house":
		houses += int((type_or_spec as Dictionary).get("units", 1))
	return it


## A landmark that does not fit where the style wants it slides towards the middle of the pad (then along the street) until it does. Vector2.INF when it never does.
func _nudge(cx: float, cz: float, w: float, d: float, yaw: float, gap: float, street_clear: float) -> Vector2:
	var to_mid := Vector2(-cx, -cz)
	var dir := to_mid.normalized() if to_mid.length() > 1.0 else Vector2.ZERO
	for k in range(1, 15):
		var q := Vector2(cx, cz) + dir * 2.5 * float(k)
		if fits(q.x, q.y, w * 0.5, d * 0.5, yaw, gap, street_clear):
			return q
	var sz := -signf(cz) if absf(cz) > 1.0 else 0.0
	for k in range(1, 15):
		var q2 := Vector2(cx, cz + sz * 3.0 * float(k))
		if fits(q2.x, q2.y, w * 0.5, d * 0.5, yaw, gap, street_clear):
			return q2
	return Vector2.INF


## The yaw (part rotation about Y in the town frame) of a part whose front (-Z of the part) looks along `front` (a town-frame direction (x, z)).
static func yaw_for_front(front: Vector2) -> float:
	return atan2(-front.x, -front.y)


func add_prop(kind: StringName, x: float, z: float, yaw := 0.0, s := 1.0) -> void:
	if kind == &"bale" and (dist_to_street(Vector2(x, z)) < STREET_HALF + 1.5 or not inside(Vector2(x, z), 4.0)):
		return                                                                 # (hay bales and crates are scattered on the land, never on the road)
	props.append({"kind": kind, "x": x, "z": z, "yaw": yaw, "s": s, "seed": rng.randi() & 0xffff})


func add_ground(kind: StringName, pts: Array, y := 0.06, p := 0.0, col := Color(1, 1, 1)) -> void:
	var cl := PackedVector2Array()
	for q: Vector2 in pts:
		var e := (q.x / r) * (q.x / r) + (q.y / ln) * (q.y / ln)
		cl.append(q * sqrt(0.88 / e) if e > 0.88 else q)                    # the flat patches stay on the flat pad (the land beyond slopes away)
	ground.append({"kind": kind, "pts": cl, "y": y, "p": p, "col": col})


## An axis-aligned (in the frame of `yaw`) rectangle as a ground patch: centre, size (across x, along z of the rectangle's own frame), yaw.
func add_rect(kind: StringName, cx: float, cz: float, sx: float, sz: float, yaw: float, y := 0.06, p := 0.0, col := Color(1, 1, 1)) -> void:
	var cs := _corners(cx, cz, sx * 0.5, sz * 0.5, yaw)
	add_ground(kind, cs, y, p, col)


func add_fence(a: Vector2, b: Vector2, kind: StringName, h := 1.0) -> void:
	fences.append({"a": a, "b": b, "kind": kind, "h": h})


func add_parked(x: float, z: float, front: Vector2, kind := -1) -> void:
	parked.append([x, z, atan2(-front.x, -front.y), kind])


func add_folk(role: StringName, x: float, z: float, yaw := 0.0) -> void:
	folk.append({"role": role, "x": x, "z": z, "yaw": yaw})


func add_anchor(kind: StringName, nm: String, x: float, z: float, height: float, radius: float) -> void:
	anchors.append({"kind": kind, "name": nm, "x": x, "z": z, "height": height, "radius": radius})


func rf(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func pick(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]
