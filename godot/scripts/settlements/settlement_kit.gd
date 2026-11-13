class_name SettlementKit
extends RefCounted
## Turns a SettlementPlan into meshes (wave 112). `build(plan, rect, far)` merges everything of the plan whose centre lies in `rect` (town frame; an empty Rect2 = the whole town) into ONE SettlementMesh:
## the houses and specials (cached parts, each placed by a transform), the lawns, paths, drives, sidewalks and side streets, fences, lamps, mailboxes, benches, bales, trees and bushes. The result is an
## ArrayMesh with the town material plus what the live node needs: collision boxes and cylinders, doors, rotating parts, the anchors in the rect.
## `part_of(item)` is the cache of building parts (a house spec or a special type -> {mesh, far, size ...}); `reset_cache()` drops it.

const SHADER := preload("res://assets/shaders/settlement.gdshader")

static var _mat: ShaderMaterial
static var _parts := {}
static var _props := {}


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat


static func reset_cache() -> void:
	_parts.clear()
	_props.clear()


## The cached part of a plan item: {mesh, far, size, size_pos, door, doors, anchor, rotors, cyl, extra_boxes, helipad}.
static func part_of(it: Dictionary) -> Dictionary:
	var key: Variant
	if it["kind"] == &"house":
		key = hash(it["spec"])
	else:
		key = StringName(it["type"])
	if _parts.has(key):
		return _parts[key]
	var res: Dictionary
	if it["kind"] == &"house":
		res = SettlementHouses.house(it["spec"])
	else:
		var sp: Dictionary = it.get("spec", {})
		match StringName(it["type"]):
			&"church": res = SettlementSpecials.church(sp)
			&"barn": res = SettlementSpecials.barn(sp)
			&"silo": res = SettlementSpecials.silo(sp)
			&"windmill": res = SettlementSpecials.windmill(sp)
			&"water_tower": res = SettlementSpecials.water_tower(sp)
			&"mast": res = SettlementSpecials.mast(sp)
			&"stack": res = SettlementSpecials.stack(sp)
			&"crane": res = SettlementSpecials.crane(sp)
			&"tank": res = SettlementSpecials.tank(sp)
			&"shed": res = SettlementSpecials.shed(sp)
			&"petrol": res = SettlementSpecials.petrol(sp)
			&"hotel": res = SettlementSpecials.hotel(sp)
			&"lighthouse": res = SettlementSpecials.lighthouse(sp)
			&"container": res = SettlementSpecials.container_house(sp)
			&"solar": res = SettlementSpecials.solar_row(sp)
			&"pier": res = SettlementSpecials.pier(sp)
			&"boat": res = SettlementSpecials.boat(sp)
			&"fish_market": res = SettlementSpecials.fish_market(sp)
			&"lodge_hall": res = SettlementSpecials.lodge_hall(sp)
			&"chapel": res = SettlementSpecials.chapel(sp)
			&"well": res = SettlementSpecials.well(sp)
			_: res = SettlementSpecials._res(SettlementMesh.new(), SettlementMesh.new(), Vector3.ONE)
	_parts[key] = res
	return res


static func prop_part(kind: StringName, seed_v: int) -> SettlementMesh:
	var key := "%s:%d" % [kind, seed_v & 3]
	if _props.has(key):
		return _props[key]
	var m := SettlementMesh.new()
	var P := SettlementParts
	match kind:
		&"lamp": P.lamp(m)
		&"mailbox": P.mailbox(m, [Color(0.8, 0.15, 0.1), Color(0.2, 0.35, 0.6), Color(0.15, 0.4, 0.2), Color(0.85, 0.8, 0.2)][seed_v & 3])
		&"bench": P.bench(m, Color(0.45, 0.32, 0.2))
		&"bale": P.bale(m)
		&"tree_broad": P.tree_broad(m, seed_v & 3, 1.0, [Color(0.2, 0.42, 0.16), Color(0.26, 0.46, 0.16), Color(0.18, 0.38, 0.2), Color(0.34, 0.46, 0.14)][seed_v & 3])
		&"tree_pine": P.tree_pine(m, seed_v & 3)
		&"tree_palm": P.tree_palm(m, seed_v & 3)
		&"bush": P.bush(m, seed_v & 3)
		_: P.bush(m, seed_v & 3)
	_props[key] = m
	return m


## The mesh of the plan's things inside `rect` (town frame, an empty Rect2 means all). `far` builds the cut-down copy of the buildings only.
static func build(plan: SettlementPlan, rect := Rect2(), far := false) -> Dictionary:
	var m := SettlementMesh.new()
	var out := {"boxes": [], "cyls": [], "doors": [], "rotors": [], "anchors": [], "lamps": [], "helipads": []}
	var all := rect.size == Vector2.ZERO
	for it in plan.items:
		var c := Vector2(it["x"], it["z"])
		if not all and not rect.has_point(c):
			continue
		var part := part_of(it)
		var yaw: float = it["yaw"]
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0.0, c.y))
		m.append(part["far"] if far else part["mesh"], xf)
		if far:
			continue
		var sz: Vector3 = part["size"]
		var spos: Vector3 = part.get("size_pos", Vector3.ZERO)
		if part.has("cyl"):
			out["cyls"].append({"pos": xf * spos, "r": float(part["cyl"]), "h": sz.y})
		else:
			out["boxes"].append({"pos": xf * (spos + Vector3(0.0, sz.y * 0.5, 0.0)), "size": sz, "yaw": yaw})
		for eb: Dictionary in part.get("extra_boxes", []):
			out["boxes"].append({"pos": xf * (eb["pos"] as Vector3), "size": eb["size"], "yaw": yaw})
		for rt: Dictionary in part.get("rotors", []):
			out["rotors"].append({"mesh": rt["mesh"], "pos": xf * (rt["pos"] as Vector3), "axis": xf.basis * (rt["axis"] as Vector3), "speed": rt["speed"], "yaw": yaw})
		if part.has("helipad"):
			var hp: Vector3 = xf * (part["helipad"] as Vector3)
			out["helipads"].append({"pos": hp, "r": 8.5})
	if far:
		out["mesh"] = m
		return out
	for pg in plan.ground:
		var pts: PackedVector2Array = pg["pts"]
		var cen := Vector2.ZERO
		for q in pts:
			cen += q
		cen /= float(pts.size())
		if not all and not rect.has_point(cen):
			continue
		_ground_patch(m, pg)
	for fe in plan.fences:
		var mid: Vector2 = ((fe["a"] as Vector2) + (fe["b"] as Vector2)) * 0.5
		if not all and not rect.has_point(mid):
			continue
		_fence(m, fe)
	for pr in plan.props:
		var pc := Vector2(pr["x"], pr["z"])
		if not all and not rect.has_point(pc):
			continue
		var kind: StringName = pr["kind"]
		var part2 := prop_part(kind, int(pr["seed"]))
		var s: float = pr["s"]
		var basis := Basis(Vector3.UP, float(pr["yaw"])) * Basis.from_scale(Vector3(s, s, s))
		m.append(part2, Transform3D(basis, Vector3(pc.x, 0.0, pc.y)))
		if kind == &"lamp":
			out["lamps"].append(Vector3(pc.x, 6.2 * s, pc.y))
		elif String(kind).begins_with("tree_") and kind != &"tree_palm":
			out["cyls"].append({"pos": Vector3(pc.x, 0.0, pc.y), "r": 0.35 * s, "h": 3.0 * s})
		elif kind == &"tree_palm":
			out["cyls"].append({"pos": Vector3(pc.x, 0.0, pc.y), "r": 0.3 * s, "h": 4.0 * s})
	for an in plan.anchors:
		var ac := Vector2(an["x"], an["z"])
		if all or rect.has_point(ac):
			out["anchors"].append(an)
	out["mesh"] = m
	return out


static func _ground_patch(m: SettlementMesh, pg: Dictionary) -> void:
	var pts: PackedVector2Array = pg["pts"]
	var y: float = pg["y"]
	var kind: StringName = pg["kind"]
	var col: Color = pg["col"]
	var code := SettlementMesh.CONCRETE
	var prm := float(pg["p"])
	match kind:
		&"lawn":
			code = SettlementMesh.LAWN
		&"asphalt":
			code = SettlementMesh.ASPHALT
			col = Color(0.2, 0.2, 0.22)
		&"sidewalk":
			code = SettlementMesh.CONCRETE
			col = Color(0.62, 0.61, 0.58)
		&"kerb":
			code = SettlementMesh.CONCRETE
			col = Color(0.8, 0.79, 0.76)
		&"dirt":
			code = SettlementMesh.DIRT
		&"path", &"drive":
			code = SettlementMesh.CONCRETE
		&"water":
			code = SettlementMesh.WATER
		&"plaza":
			code = SettlementMesh.CONCRETE
	var q: Array[Vector3] = []
	for pt in pts:
		q.append(Vector3(pt.x, y, pt.y))
	if q.size() == 4:
		if kind == &"asphalt":
			SettlementParts.quad_h(m, q[0], q[3], q[2], q[1], Vector3.UP, col, code, 1.0, 1.0, Vector2.ZERO, prm)
		else:
			SettlementParts.quad_h(m, q[0], q[1], q[2], q[3], Vector3.UP, col, code, 1.0, 1.0, Vector2.ZERO, prm)
	elif q.size() > 4:                                                     # a convex polygon: a fan
		SettlementParts.poly_h(m, q, Vector3.UP, col, code, 1.0, 1.0)


static func _fence(m: SettlementMesh, fe: Dictionary) -> void:
	var a2: Vector2 = fe["a"]
	var b2: Vector2 = fe["b"]
	var a := Vector3(a2.x, 0.0, a2.y)
	var b := Vector3(b2.x, 0.0, b2.y)
	var h: float = fe["h"]
	match StringName(fe["kind"]):
		&"picket":
			SettlementParts.fence(m, a, b, h, Color(0.94, 0.92, 0.86))
		&"picket_dark":
			SettlementParts.fence(m, a, b, h, Color(0.38, 0.27, 0.18))
		&"rail", &"log":
			_rail(m, a, b, h, Color(0.45, 0.33, 0.2))
		&"wire":
			_rail(m, a, b, h, Color(0.45, 0.45, 0.47), true)
		&"stone":
			SettlementParts.wall_run(m, a, b, 0.8, 0.45, Color(0.58, 0.55, 0.5), SettlementMesh.STONE)
		&"hedge":
			SettlementParts.hedge(m, a, b, 1.2, 0.8, Color(0.16, 0.36, 0.14))
		&"adobe":
			SettlementParts.wall_run(m, a, b, 1.5, 0.4, Color(0.74, 0.58, 0.4), SettlementMesh.ADOBE)
		&"chain":
			_rail(m, a, b, 1.8, Color(0.5, 0.5, 0.52), true)


static func _rail(m: SettlementMesh, a: Vector3, b: Vector3, h: float, col: Color, thin := false) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.3:
		return
	var yaw := atan2(dir.x, dir.z)
	var mid := (a + b) * 0.5
	var posts := maxi(2, int(ceil(length / 3.0)) + 1)
	for i in posts:
		var pp := a + dir * (float(i) / float(posts - 1))
		m.box(Vector3(pp.x, h * 0.5, pp.z), Vector3(0.11, h, 0.11), col, SettlementMesh.WOOD, 32, 1.0, 1.0)
	var rails := 2 if not thin else 3
	for k in rails:
		var y := h * (0.45 + 0.5 * float(k) / float(maxi(rails - 1, 1)))
		var s0 := m.v.size()
		m.box(Vector3(0.0, 0.0, 0.0), Vector3(0.05 if thin else 0.08, 0.05 if thin else 0.1, length), col, SettlementMesh.WOOD if not thin else SettlementMesh.METAL, 32, 1.0, 1.0)
		m.transform_from(s0, Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, y, mid.z)))
