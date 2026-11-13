class_name SettlementStyles
extends RefCounted
## The seven town styles (wave 112): each fills a SettlementPlan with its own streets, lots, palettes, specials, fences, trees, cars and people. Shared helpers lay lots along the main street and along
## side streets; a style is a handful of recipes (a house spec generator per kind of house) and a list of landmarks.

const SM := SettlementMesh


# --- shared layout helpers ----------------------------------------------------------------------------------------------------------------------

static func _nrm(t: Vector2) -> Vector2:
	return Vector2(t.y, -t.x)


## A side street leaving the main street at town-frame z towards `side` (+1 / -1, the +x / -x side), `length` metres long (cut where the pad ends). Returns its index.
static func side_street(p: SettlementPlan, z: float, side: float, length: float, width_h := 0.0) -> int:
	var sf: Array = p.street_at(z)
	var c: Vector2 = sf[0]
	var t: Vector2 = sf[1]
	var nr: Vector2 = _nrm(t) * side
	var a := c + nr * (SettlementPlan.STREET_HALF - 1.0)
	var b := a
	var step := 4.0
	var run := 0.0
	while run < length:
		var q := a + nr * (run + step)
		if not p.inside(q, 6.0):
			break
		run += step
		b = q
	if run < 20.0:
		return -1
	p.sides.append({"a": a, "b": b, "w": 6.8, "side": side, "z": z})
	return p.sides.size() - 1


## Lots along the main street on one side between z0 and z1: `make` is a Callable(plan, side_sign) -> {kind, spec | type, w, d, interior, setback}, called until z1 is reached. Returns how many were placed.
static func street_row(p: SettlementPlan, side: float, z0: float, z1: float, make: Callable, gap: float, chance := 1.0, street_clear := 0.0) -> int:
	var z := z0
	var made := 0
	var guard := 0
	while z < z1 and guard < 80:
		guard += 1
		var it: Dictionary = make.call(p, side)
		if it.is_empty():
			z += 6.0
			continue
		if p.rng.randf() > chance:
			z += float(it["w"]) * 0.5 + gap
			continue
		var w: float = it["w"]
		var d: float = it["d"]
		var setback: float = it.get("setback", 5.0)
		var adv: float = maxf(float((it.get("lot", {}) as Dictionary).get("pitch", 0.0)), w + gap)
		var zc := z + adv * 0.5
		var sf: Array = p.street_at(zc)
		var c: Vector2 = sf[0]
		var t: Vector2 = sf[1]
		var nr: Vector2 = _nrm(t) * side
		var centre := c + nr * (SettlementPlan.STREET_HALF + setback + d * 0.5)
		var front := -nr
		var yaw := SettlementPlan.yaw_for_front(front)
		var placed := _put(p, it, centre, yaw, gap, street_clear)
		if not placed.is_empty():
			made += 1
			_lot_extras(p, placed, centre, nr, setback, side, it)
			z += adv
		else:
			z += 5.0
	return made


## Lots along side street `si` on one side of it (`side2` +1 / -1) from distance t0 to t1 along it.
static func side_row(p: SettlementPlan, si: int, side2: float, t0: float, t1: float, make: Callable, gap: float, chance := 1.0) -> int:
	if si < 0:
		return 0
	var s: Dictionary = p.sides[si]
	var a: Vector2 = s["a"]
	var b: Vector2 = s["b"]
	var u := (b - a).normalized()
	var nn := Vector2(u.y, -u.x) * side2
	var t := t0
	var made := 0
	var guard := 0
	while t < t1 and guard < 60:
		guard += 1
		var it: Dictionary = make.call(p, side2)
		if it.is_empty():
			t += 6.0
			continue
		if p.rng.randf() > chance:
			t += float(it["w"]) * 0.5 + gap
			continue
		var w: float = it["w"]
		var d: float = it["d"]
		var setback: float = it.get("setback", 4.0)
		var adv: float = maxf(float((it.get("lot", {}) as Dictionary).get("pitch", 0.0)), w + gap)
		var centre := a + u * (t + adv * 0.5) + nn * (SettlementPlan.SIDE_HALF + setback + d * 0.5)
		var front := -nn
		var yaw := SettlementPlan.yaw_for_front(front)
		var placed := _put(p, it, centre, yaw, gap, 0.0)
		if not placed.is_empty():
			made += 1
			_lot_extras(p, placed, centre, nn, setback, side2, it)
			t += adv
		else:
			t += 5.0
	return made


static func _put(p: SettlementPlan, it: Dictionary, centre: Vector2, yaw: float, gap: float, street_clear: float) -> Dictionary:
	var k: StringName = it["kind"]
	var payload: Variant = it["spec"] if it.has("spec") else it["type"]
	return p.place(k, payload, centre.x, centre.y, yaw, float(it["w"]), float(it["d"]), StringName(it.get("interior", &"")), gap, street_clear)


## The lawn, path, fence, mailbox and trees of a lot, driven by the item's `lot` flags: lawn, fence (kind), path, drive (garage side), mailbox, trees (n), tree (kind).
static func _lot_extras(p: SettlementPlan, placed: Dictionary, centre: Vector2, out_n: Vector2, setback: float, side: float, it: Dictionary) -> void:
	var lot: Dictionary = it.get("lot", {})
	if lot.is_empty():
		return
	var w: float = float(it["w"])
	var d: float = float(it["d"])
	var front := -out_n
	var right := Vector2(-front.y, front.x)                    # across the lot as seen from the street
	var pitch: float = float(lot.get("pitch", w + 6.0))
	var back := float(lot.get("back", 6.0))
	# the lot rectangle from the sidewalk edge to the back
	var depth := setback + d + back
	var front_pt := centre + front * (d * 0.5 + setback)
	var yaw := SettlementPlan.yaw_for_front(front)
	var lc := front_pt - front * (depth * 0.5)
	if lot.get("lawn", true):
		p.add_rect(&"lawn", lc.x, lc.y, pitch, depth, yaw, 0.05, 0.0, lot.get("lawn_col", Color(0.3, 0.45, 0.2)))
	# path from the sidewalk to the door
	var door_x: float = float(it.get("spec", {}).get("door_x", 0.0)) if it.has("spec") else 0.0
	var door_pt := centre + front * (d * 0.5) - right * door_x                 # (the part's local +X is the lot's -right as seen from outside: front is -Z)
	var walk_a := front_pt
	var walk_b := centre + front * (d * 0.5 + 0.3)
	var pc: Vector2 = (door_pt + front * setback * 0.5)
	if lot.get("path", true):
		p.add_rect(&"path", pc.x, pc.y, 1.3, setback + 0.4, yaw, 0.09, 0.0, lot.get("path_col", Color(0.62, 0.6, 0.56)))
	# garage drive
	var gs: int = int(it.get("spec", {}).get("garage", 0)) if it.has("spec") else 0
	if gs != 0 and lot.get("drive", true):
		var gx := -right * float(gs) * (w * 0.5 + 1.7)
		var dc := centre + front * (d * 0.5 + setback * 0.5) + (-right) * float(gs) * (w * 0.5 + 1.7) * -1.0
		dc = centre + front * (d * 0.5 + setback * 0.5 - 0.0) + right * float(gs) * (w * 0.5 + 1.7) * -1.0
		p.add_rect(&"drive", dc.x, dc.y, 3.2, setback + 1.2, yaw, 0.09, 0.0, Color(0.58, 0.57, 0.55))
		if lot.get("car", true) and p.rng.randf() < float(lot.get("car_chance", 0.7)):
			p.add_parked(dc.x, dc.y, -front, -1)
	elif lot.get("car_front", false) and p.rng.randf() < float(lot.get("car_chance", 0.4)):
		var cc := centre + front * (d * 0.5 + setback * 0.6) + right * (w * 0.5 + 2.2)
		p.add_parked(cc.x, cc.y, -front if p.rng.randf() < 0.5 else front, -1)
	# fence along the front (with a gap at the path) and the sides
	var fk: StringName = lot.get("fence", &"")
	if fk != &"":
		var fa := front_pt + right * (pitch * 0.5)
		var fb := front_pt - right * (pitch * 0.5)
		var gap_c := pc
		var gap_t := (gap_c - fa).dot((fb - fa).normalized())
		var len := fa.distance_to(fb)
		var u := (fb - fa).normalized()
		var g0 := clampf(gap_t - 0.9, 0.0, len)
		var g1 := clampf(gap_t + 0.9, 0.0, len)
		p.add_fence(fa, fa + u * g0, fk, float(lot.get("fence_h", 1.0)))
		p.add_fence(fa + u * g1, fb, fk, float(lot.get("fence_h", 1.0)))
		if lot.get("side_fence", true):
			p.add_fence(fa, fa - front * depth, fk if lot.get("side_kind", &"") == &"" else lot["side_kind"], float(lot.get("fence_h", 1.0)))
			p.add_fence(fb, fb - front * depth, fk if lot.get("side_kind", &"") == &"" else lot["side_kind"], float(lot.get("fence_h", 1.0)))
		if lot.get("back_fence", false):
			p.add_fence(fa - front * depth, fb - front * depth, lot.get("back_kind", fk), float(lot.get("fence_h", 1.0)))
	if lot.get("mailbox", true):
		var mb := front_pt + right * (pitch * 0.5 - 1.6) + front * -0.4
		p.add_prop(&"mailbox", mb.x, mb.y, SettlementPlan.yaw_for_front(front), 1.0)
	var nt: int = int(lot.get("trees", 1))
	for i in nt:
		var tk: StringName = lot.get("tree", &"broad")
		var tp := centre - front * (d * 0.5 + 3.5 + p.rf(0.0, back * 0.8)) + right * p.rf(-pitch * 0.4, pitch * 0.4)
		if p.rng.randf() < 0.5:
			tp = centre + front * (d * 0.5 + setback * 0.45) + right * (pitch * 0.5 - 2.0 if p.rng.randf() < 0.5 else -(pitch * 0.5 - 2.0))
		p.add_prop(StringName("tree_" + String(tk)), tp.x, tp.y, p.rf(0.0, TAU), p.rf(0.8, 1.15))
	if lot.get("bush", true):
		var bp := centre + front * (d * 0.5 + 0.9) + right * (w * 0.5 - 0.6 if p.rng.randf() < 0.5 else -(w * 0.5 - 0.6))
		p.add_prop(&"bush", bp.x, bp.y, 0.0, p.rf(0.7, 1.1))
	# a person or a pet at the door
	if it.has("spec") and p.rng.randf() < float(lot.get("folk", 0.35)):
		p.add_folk(lot.get("role", &"villager"), door_pt.x + front.x * 2.0, door_pt.y + front.y * 2.0, yaw)
	if it.has("spec") and p.rng.randf() < float(lot.get("pet", 0.25)):
		var pp := centre + front * (d * 0.5 + setback * 0.5) + right * p.rf(-3.0, 3.0)
		p.pets.append({"kind": lot.get("pet_kind", &"dog"), "x": pp.x, "z": pp.y})


## Streetlamps every `every` metres on both sides, offset along the street, plus the sidewalks and kerbs of the main street.
static func street_furniture(p: SettlementPlan, every := 30.0, lamps := true) -> void:
	var z := -p.ln + 12.0
	var k := 0
	while z < p.ln - 8.0:
		var sf: Array = p.street_at(z)
		var c: Vector2 = sf[0]
		var t: Vector2 = sf[1]
		var nr: Vector2 = _nrm(t)
		var side := 1.0 if k % 2 == 0 else -1.0
		var pos := c + nr * side * (SettlementPlan.STREET_HALF - 1.0)
		if p.inside(pos, 4.0) and lamps:
			p.add_prop(&"lamp", pos.x, pos.y, SettlementPlan.yaw_for_front(-nr * side), 1.0)
		k += 1
		z += every
	# sidewalks and kerbs along the real street (a patch per segment)
	var n := p.street.size()
	var step := maxi(1, int(round(10.0 / maxf(p.street[0].distance_to(p.street[1]), 1.0)))) if n > 2 else 1
	var i := 0
	while i < n - 1:
		var j := mini(i + step, n - 1)
		var a := p.street[i]
		var b := p.street[j]
		if absf(a.y) > p.ln or absf(b.y) > p.ln:
			i = j
			continue
		var tg := (b - a).normalized()
		var nr2 := _nrm(tg)
		for sd in [-1.0, 1.0]:
			var o0: float = 8.7
			var o1: float = SettlementPlan.STREET_HALF
			var s: float = float(sd)
			p.add_ground(&"sidewalk", [a + nr2 * s * o0, b + nr2 * s * o0, b + nr2 * s * o1, a + nr2 * s * o1], 0.13, 0.0)
			p.add_ground(&"kerb", [a + nr2 * s * (o0 - 0.18), b + nr2 * s * (o0 - 0.18), b + nr2 * s * o0, a + nr2 * s * o0], 0.14, 0.0)
		i = j
	# side streets: asphalt, with sidewalks along both sides
	for sdv in p.sides:
		var sa: Vector2 = sdv["a"]
		var sb: Vector2 = sdv["b"]
		var u := (sb - sa).normalized()
		var nn := Vector2(u.y, -u.x)
		var w: float = float(sdv["w"])
		p.add_ground(&"asphalt", [sa - nn * w * 0.5, sb - nn * w * 0.5, sb + nn * w * 0.5, sa + nn * w * 0.5], 0.09, w)
		for sd2 in [-1.0, 1.0]:
			var s2: float = float(sd2)
			p.add_ground(&"sidewalk", [sa + nn * s2 * w * 0.5, sb + nn * s2 * w * 0.5, sb + nn * s2 * (w * 0.5 + 2.4), sa + nn * s2 * (w * 0.5 + 2.4)], 0.13, 0.0)
		var slen := sa.distance_to(sb)
		var lz := 14.0
		var kk := 0
		while lz < slen - 6.0:
			var lp := sa + u * lz + nn * (1.0 if kk % 2 == 0 else -1.0) * (w * 0.5 + 1.2)
			if p.inside(lp, 4.0) and lamps:
				p.add_prop(&"lamp", lp.x, lp.y, SettlementPlan.yaw_for_front(-nn * (1.0 if kk % 2 == 0 else -1.0)), 1.0)
			kk += 1
			lz += 28.0


# --- generic house spec makers ------------------------------------------------------------------------------------------------------------------

static func house_item(spec: Dictionary, interior: StringName, lot := {}, setback := 5.0) -> Dictionary:
	var it := {"kind": &"house", "spec": spec, "w": float(spec["w"]) + (3.4 if int(spec.get("garage", 0)) != 0 else 0.0), "d": float(spec["d"]), "interior": interior, "setback": setback, "lot": lot}
	if int(spec.get("garage", 0)) != 0:
		it["w"] = float(spec["w"]) + 3.4
	return it


static func special_item(type: StringName, w: float, d: float, interior: StringName = &"", lot := {}, setback := 6.0) -> Dictionary:
	return {"kind": &"special", "type": type, "w": w, "d": d, "interior": interior, "setback": setback, "lot": lot}


# --- FARM: HARROW FIELD --------------------------------------------------------------------------------------------------------------------------

const FARM_WALLS: Array[Color] = [Color(0.93, 0.91, 0.84), Color(0.9, 0.84, 0.62), Color(0.62, 0.2, 0.15), Color(0.82, 0.86, 0.82), Color(0.86, 0.78, 0.68), Color(0.7, 0.8, 0.86)]
const FARM_ROOFS: Array[Color] = [Color(0.3, 0.3, 0.33), Color(0.42, 0.2, 0.16), Color(0.25, 0.3, 0.26), Color(0.36, 0.3, 0.26)]


static func _farm_house(p: SettlementPlan, side: float) -> Dictionary:
	var r := p.rng.randf()
	var wall: Color = FARM_WALLS[p.rng.randi() % FARM_WALLS.size()]
	var roof: Color = FARM_ROOFS[p.rng.randi() % FARM_ROOFS.size()]
	var trim := Color(0.95, 0.94, 0.9) if wall.get_luminance() < 0.75 else Color(0.35, 0.3, 0.26)
	var sd := p.rng.randi() & 0xffff
	var lot := {"fence": &"picket", "fence_h": 0.95, "trees": 2, "tree": &"broad", "pitch": 0.0, "back": 14.0, "path": true, "mailbox": true, "folk": 0.4, "role": &"farmer", "car_front": true, "car_chance": 0.5, "pet": 0.45, "side_fence": true, "side_kind": &"picket"}
	var spec: Dictionary
	var it: Dictionary
	if r < 0.55:
		spec = {"w": p.rf(9.0, 11.0), "d": p.rf(7.5, 8.5), "floors": 2, "wall": wall, "wall_code": SM.SIDING, "trim": trim, "roof": roof, "roof_code": SM.SHINGLE, "roof_type": &"gable", "slope": 0.62, "ridge": &"z",
			"ov": 0.45, "ovg": 0.3, "porch": true, "porch_w": 3.6, "chimney": true, "chim_side": 1 if p.rng.randf() < 0.5 else -1, "shutter": Color(0.2, 0.32, 0.25, 1.0) if p.rng.randf() < 0.5 else Color(0, 0, 0, 0),
			"door_x": 0.0 if p.rng.randf() < 0.5 else p.rf(-1.5, 1.5), "door_col": Color(0.4, 0.15, 0.12) if p.rng.randf() < 0.5 else Color(0.2, 0.3, 0.4), "seed": sd, "glow": 0.7}
		it = house_item(spec, &"farmhouse", lot, p.rf(7.0, 11.0))
	elif r < 0.85:
		spec = {"w": p.rf(7.0, 8.5), "d": p.rf(6.0, 7.0), "floors": 1, "wall": wall, "wall_code": SM.SIDING if p.rng.randf() < 0.7 else SM.BRICK, "trim": trim, "roof": roof, "roof_code": SM.SHINGLE, "roof_type": &"hip",
			"slope": 0.55, "ov": 0.5, "chimney": true, "chim_side": 1, "porch": p.rng.randf() < 0.5, "porch_w": 3.0, "door_x": 0.0, "door_col": Color(0.35, 0.18, 0.12), "seed": sd, "glow": 0.6}
		if spec["wall_code"] == SM.BRICK:
			spec["wall"] = Color(0.6, 0.3, 0.22)
		it = house_item(spec, &"cottage", lot, p.rf(6.0, 9.0))
	else:
		spec = {"w": p.rf(9.5, 11.5), "d": p.rf(8.0, 9.0), "floors": 2, "wall": wall, "wall_code": SM.SIDING, "trim": trim, "roof": roof, "roof_code": SM.SHINGLE, "roof_type": &"gable", "slope": 0.5, "ridge": &"x",
			"ov": 0.5, "ovg": 0.4, "porch": true, "porch_w": 5.0, "chimney": true, "chim_side": -1, "balcony": false, "door_x": 1.2, "seed": sd, "glow": 0.7, "shutter": Color(0.55, 0.15, 0.12, 1.0)}
		it = house_item(spec, &"farmhouse", lot, p.rf(8.0, 12.0))
	(it["lot"] as Dictionary)["pitch"] = float(it["w"]) + p.rf(10.0, 18.0)
	return it


static func farm(p: SettlementPlan, target: int) -> void:
	var rng := p.rng
	# landmarks first: the church at the head of the street, the store, the silos and the windmill at the other end, the water tower
	for pos in [[-118.0, 1.0], [-84.0, -1.0]]:
		var z: float = pos[0]
		var side: float = pos[1]
		var sf: Array = p.street_at(z)
		var c: Vector2 = sf[0]
		var nr: Vector2 = _nrm(sf[1]) * side
		var centre := c + nr * (SettlementPlan.STREET_HALF + 7.0 + 8.0)
		var yaw := SettlementPlan.yaw_for_front(-nr)
		if z < -100.0:
			var item := p.place(&"special", &"church", centre.x, centre.y, yaw, 9.0, 20.0, &"chapel", 3.0)
			if not item.is_empty():
				p.add_rect(&"lawn", centre.x, centre.y, 24.0, 32.0, yaw, 0.05, 0.0, Color(0.32, 0.46, 0.22))
				p.add_prop(&"bench", centre.x - nr.x * 0.0 + (-nr.y) * 7.0, centre.y + nr.x * 7.0, yaw, 1.0)
		else:
			var spec := {"w": 10.0, "d": 9.0, "floors": 2, "wall": Color(0.88, 0.82, 0.62), "wall_code": SM.SIDING, "trim": Color(0.95, 0.94, 0.9), "roof": Color(0.34, 0.2, 0.17), "roof_code": SM.SHINGLE,
				"roof_type": &"gable", "slope": 0.4, "ridge": &"x", "shopfront": true, "awning": Color(0.7, 0.18, 0.14, 1.0), "door_x": 2.5, "seed": 5, "glow": 0.9, "chimney": true, "chim_side": -1}
			p.place(&"house", spec, centre.x, centre.y, yaw, 10.0, 9.0, &"general_store", 3.0)
			p.houses -= 1                                                    # (a shop, not a home)
	# the south end: a barn, three silos, the windmill and the water tower
	var barn_c := Vector2(40.0, 96.0)
	p.place(&"special", &"barn", barn_c.x, barn_c.y, SettlementPlan.yaw_for_front(Vector2(-1, 0)), 11.0, 16.0, &"barn", 3.0)
	for sp in [Vector2(54.0, 112.0), Vector2(54.0, 104.0), Vector2(46.0, 112.0)]:
		p.place(&"special", &"silo", sp.x, sp.y, 0.0, 5.4, 5.4, &"", 1.0)
	p.place(&"special", &"windmill", -46.0, 118.0, 0.0, 6.8, 6.8, &"", 2.0)
	p.place(&"special", &"water_tower", 46.0, -26.0, 0.0, 6.0, 6.0, &"", 2.0)
	p.place(&"special", &"well", -14.0, 30.0, 0.0, 2.2, 2.2, &"", 1.0)
	# houses along both sides of the main street, then along two side streets
	var made := 0
	made += street_row(p, 1.0, -150.0, 150.0, Callable(SettlementStyles, "_farm_house"), 6.0, 1.0)
	made += street_row(p, -1.0, -150.0, 150.0, Callable(SettlementStyles, "_farm_house"), 6.0, 1.0)
	var s1 := side_street(p, -40.0, 1.0, 80.0)
	var s2 := side_street(p, 52.0, -1.0, 80.0)
	if made < target:
		made += side_row(p, s1, 1.0, 6.0, 80.0, Callable(SettlementStyles, "_farm_house"), 6.0)
		made += side_row(p, s1, -1.0, 6.0, 80.0, Callable(SettlementStyles, "_farm_house"), 6.0)
		made += side_row(p, s2, 1.0, 6.0, 80.0, Callable(SettlementStyles, "_farm_house"), 6.0)
		made += side_row(p, s2, -1.0, 6.0, 80.0, Callable(SettlementStyles, "_farm_house"), 6.0)
	street_furniture(p, 32.0)
	# fields round the edge, an orchard, a paddock with animals
	var fcols: Array[Color] = [Color(0.62, 0.62, 0.22), Color(0.3, 0.5, 0.2), Color(0.5, 0.42, 0.2), Color(0.34, 0.5, 0.28)]
	var placed_fields := 0
	for k in 14:
		var fx := rng.randf_range(-p.r * 0.92, p.r * 0.92)
		var fz := rng.randf_range(-p.ln * 0.9, p.ln * 0.9)
		var fw := rng.randf_range(24.0, 38.0)
		var fd := rng.randf_range(20.0, 34.0)
		if p.fits(fx, fz, fw * 0.5, fd * 0.5, 0.0, 1.0, 2.0) and absf(fx) > 38.0:
			p.occupy(fx, fz, fw * 0.5, fd * 0.5, 0.0)
			p.add_rect(&"lawn", fx, fz, fw, fd, 0.0, 0.05, 1.0, fcols[placed_fields % fcols.size()])
			placed_fields += 1
	var ob := Vector2(-58.0, -70.0)
	if p.fits(ob.x, ob.y, 16.0, 16.0, 0.0, 1.0, 2.0):
		p.occupy(ob.x, ob.y, 16.0, 16.0, 0.0)
		for ix in 4:
			for iz in 4:
				p.add_prop(&"tree_broad", ob.x - 12.0 + float(ix) * 8.0, ob.y - 12.0 + float(iz) * 8.0, rng.randf() * TAU, 0.75)
		p.add_rect(&"lawn", ob.x, ob.y, 32.0, 32.0, 0.0, 0.05, 0.0, Color(0.34, 0.48, 0.24))
	var pd := Vector2(-52.0, 60.0)
	if p.fits(pd.x, pd.y, 14.0, 12.0, 0.0, 1.0, 2.0):
		p.occupy(pd.x, pd.y, 14.0, 12.0, 0.0)
		p.add_rect(&"lawn", pd.x, pd.y, 28.0, 24.0, 0.0, 0.05, 0.0, Color(0.36, 0.5, 0.25))
		p.add_fence(pd + Vector2(-14, -12), pd + Vector2(14, -12), &"rail", 1.1)
		p.add_fence(pd + Vector2(14, -12), pd + Vector2(14, 12), &"rail", 1.1)
		p.add_fence(pd + Vector2(14, 12), pd + Vector2(-14, 12), &"rail", 1.1)
		p.add_fence(pd + Vector2(-14, 12), pd + Vector2(-14, -12), &"rail", 1.1)
		p.livestock.append({"kind": &"cow", "x": pd.x, "z": pd.y, "r": 9.0, "n": 4})
	for i in 5:
		p.add_prop(&"bale", rng.randf_range(30.0, 56.0), rng.randf_range(70.0, 90.0), rng.randf() * TAU, 1.0)
	p.add_folk(&"farmer", 10.0, 0.0, 0.0)
	p.add_folk(&"farmer", -10.0, 40.0, 1.0)
	p.add_folk(&"shopkeeper", 0.0, -84.0, 0.0)


# --- the other styles (filled in step by step) ----------------------------------------------------------------------------------------------------

static func industrial(p: SettlementPlan, target: int) -> void:
	street_furniture(p, 34.0)


static func suburb(p: SettlementPlan, target: int) -> void:
	street_furniture(p, 30.0)


static func harbour(p: SettlementPlan, target: int) -> void:
	street_furniture(p, 30.0)


static func resort(p: SettlementPlan, target: int) -> void:
	street_furniture(p, 30.0)


static func lodge(p: SettlementPlan, target: int) -> void:
	street_furniture(p, 36.0)


static func outpost(p: SettlementPlan, target: int) -> void:
	street_furniture(p, 36.0)
