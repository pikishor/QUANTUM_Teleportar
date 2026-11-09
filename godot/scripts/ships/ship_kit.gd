class_name ShipKit
extends RefCounted
## Meshes of the big ships (shared by every instance, rail_kit.gdshader, vertex colour = paint). Every ship is modelled in its own space: the origin on the waterline in the middle, the bow at -Z,
## +Y up. `spec(type)` returns {len, beam, draft, free (deck height over the waterline), bow, shapes [{pos, size}] (colliders in ship space), helm (Vector3), turrets [{pos, kind}], pad, name}.
## Types: cargo (container ship, 190 m), tanker (200 m), cruise (cruise liner, 250 m), destroyer (naval ship with two gun turrets, a helipad, CIWS and missile cells, 140 m), submarine (75 m, surfaced).
## `turret_mesh()` is the rotating gun house of the destroyer (origin at its ring, barrel along -Z). `buoys()` is one mesh of channel buoys.

const MB := preload("res://scripts/world/mesh_builder.gd")
const GLASS := Color(0.55, 0.78, 1.0, 7.0 / 8.0)
const STEEL := Color(0.52, 0.54, 0.58, 3.0 / 8.0)
const STEEL_DARK := Color(0.18, 0.2, 0.23, 3.0 / 8.0)
const LAMP := Color(1.0, 0.9, 0.62, 4.0 / 8.0)
const WHITE := Color(0.93, 0.94, 0.95, 6.0 / 8.0)
const NAVY := Color(0.42, 0.46, 0.5, 6.0 / 8.0)
const BOOT_RED := Color(0.5, 0.12, 0.1, 0.0)

static var _cache := {}


static func _c(col: Color, code: float) -> Color:
	return Color(col.r, col.g, col.b, code / 8.0)


static func spec(type: StringName) -> Dictionary:
	return build(type)["spec"]


static func mesh(type: StringName) -> ArrayMesh:
	return build(type)["mesh"]


static func build(type: StringName) -> Dictionary:
	if _cache.has(type):
		return _cache[type]
	var mb := MB.new()
	var sp := {"type": type, "shapes": [], "turrets": [], "helm": Vector3.ZERO, "pad": Vector3.INF, "name": "", "max_speed": 10.0, "len": 100.0, "beam": 20.0, "draft": 5.0, "free": 6.0, "bow": 30.0,
		"gangway": Vector3.ZERO, "boardable": false, "tris": 0}
	match type:
		&"destroyer":
			_destroyer(mb, sp)
		&"cargo":
			_cargo(mb, sp)
		&"tanker":
			_tanker(mb, sp)
		&"cruise":
			_cruise(mb, sp)
		&"submarine":
			_submarine(mb, sp)
	var m := mb.build(RailKit.material(), true)
	sp["tris"] = mb.idx.size() / 3
	var res := {"mesh": m, "spec": sp}
	_cache[type] = res
	return res


static func _shape(sp: Dictionary, pos: Vector3, size: Vector3) -> void:
	(sp["shapes"] as Array).append({"pos": pos, "size": size})


## The hull: below-water prism and above-water prism along z with a tapered bow, a deck on top, a flat stern.
static func _hull(mb: MB, sp: Dictionary, L: float, B: float, draft: float, free: float, bow: float, top: Color, bottom: Color, deck: Color) -> void:
	sp["len"] = L
	sp["beam"] = B
	sp["draft"] = draft
	sp["free"] = free
	sp["bow"] = bow
	var hw := B * 0.5
	var zb := -L * 0.5 + bow
	var zt := -L * 0.5
	var zs := L * 0.5
	var above := PackedVector2Array([Vector2(-hw, 0.0), Vector2(hw, 0.0), Vector2(hw - 0.3, free), Vector2(-hw + 0.3, free)])
	var below := PackedVector2Array([Vector2(-hw + hw * 0.35, -draft), Vector2(hw - hw * 0.35, -draft), Vector2(hw, 0.0), Vector2(-hw, 0.0)])
	mb.prism(above, zb, zs, top)
	mb.prism(below, zb, zs, bottom)
	# the bow
	var rake := free * 0.25
	for sx in [-1.0, 1.0]:
		var x := float(sx)
		var n_up := Vector3(x * 1.0, 0.1, -0.5).normalized()
		mb.quad(Vector3(x * hw, 0.0, zb), Vector3(x * (hw - 0.3), free, zb), Vector3(0.0, free + rake, zt), Vector3(0.0, 0.0, zt), n_up, top)
		mb.quad(Vector3(x * hw, 0.0, zb), Vector3(x * hw * 0.65, -draft, zb), Vector3(0.0, -draft * 0.8, zt), Vector3(0.0, 0.0, zt), Vector3(x, -0.3, -0.5).normalized(), bottom)
	mb.quad(Vector3(-hw + 0.3, free, zb), Vector3(hw - 0.3, free, zb), Vector3(0.0, free + rake, zt), Vector3(0.0, free + rake, zt), Vector3(0.0, 0.8, -0.3).normalized(), deck)
	mb.quad(Vector3(-hw * 0.65, -draft, zb), Vector3(hw * 0.65, -draft, zb), Vector3(0.0, -draft * 0.8, zt), Vector3(0.0, -draft * 0.8, zt), Vector3.DOWN, bottom)
	# the deck over the middle body and the stern
	mb.quad(Vector3(-hw + 0.3, free + 0.02, zb), Vector3(hw - 0.3, free + 0.02, zb), Vector3(hw - 0.3, free + 0.02, zs), Vector3(-hw + 0.3, free + 0.02, zs), Vector3.UP, deck)
	mb.quad(Vector3(-hw + hw * 0.35, -draft, zs), Vector3(hw - hw * 0.35, -draft, zs), Vector3(hw, 0.0, zs), Vector3(-hw, 0.0, zs), Vector3.BACK, bottom)
	mb.quad(Vector3(-hw, 0.0, zs), Vector3(hw, 0.0, zs), Vector3(hw - 0.3, free, zs), Vector3(-hw + 0.3, free, zs), Vector3.BACK, top)
	# the waterline stripe and the bulwark
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * (hw + 0.02), 0.5, (zb + zs) * 0.5), Vector3(0.06, 0.45, zs - zb), bottom, false)
		mb.box(Vector3(float(sx) * (hw - 0.45), free + 0.5, (zb + zs) * 0.5), Vector3(0.12, 1.0, zs - zb - 6.0), STEEL, false)
	# the solid for the hero and the boats: the hull block under the deck
	_shape(sp, Vector3(0.0, (free - draft * 0.7) * 0.5, (zb + zs) * 0.5 + bow * 0.15), Vector3(B - 1.2, free + draft * 0.7, zs - zb - bow * 0.3))


static func _windows(mb: MB, c: Vector3, w: float, h: float, l: float, rows := 1) -> void:
	# glass bands on both sides and the front of a block centred at c (size w x h x l)
	for r in rows:
		var y := c.y - h * 0.5 + (float(r) + 0.6) * h / float(rows)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(c.x + float(sx) * (w * 0.5 + 0.02), y, c.z), Vector3(0.05, h / float(rows) * 0.45, l - 1.2), GLASS, false)
		mb.box(Vector3(c.x, y, c.z - l * 0.5 - 0.02), Vector3(w - 1.0, h / float(rows) * 0.5, 0.05), GLASS, false)


static func _funnel(mb: MB, base: Vector3, r: float, h: float, col: Color, top: Color) -> void:
	mb.cylinder(base, r, h, 14, col, r * 0.85, true, false)
	mb.cylinder(base + Vector3(0.0, h, 0.0), r * 0.85, h * 0.12, 14, top, -1.0, true, false)


# --- the destroyer ----------------------------------------------------------------------------------------------------------------------

static func _destroyer(mb: MB, sp: Dictionary) -> void:
	var L := 140.0
	var free := 6.0
	_hull(mb, sp, L, 17.0, 5.0, free, 38.0, NAVY, Color(0.3, 0.1, 0.09, 0.0), _c(Color(0.34, 0.37, 0.4), 6.0))
	sp["name"] = "NAVAL DESTROYER"
	sp["max_speed"] = 17.0
	sp["boardable"] = true
	var y := free
	# bridge block (forward), a hangar (aft), two funnels between them
	var bridge_c := Vector3(0.0, y + 3.2, -L * 0.5 + 56.0)
	mb.box(bridge_c, Vector3(11.0, 6.4, 15.0), NAVY, false)
	mb.box(bridge_c + Vector3(0.0, 4.3, 1.0), Vector3(8.4, 2.2, 8.0), NAVY, false)
	_windows(mb, bridge_c + Vector3(0.0, 4.3, 1.0), 8.4, 2.2, 8.0)
	_windows(mb, bridge_c, 11.0, 6.4, 15.0, 2)
	mb.box(bridge_c + Vector3(0.0, 6.4, 1.0), Vector3(1.0, 6.0, 1.0), STEEL, false)               # the mast
	mb.box(bridge_c + Vector3(0.0, 9.6, 1.0), Vector3(5.0, 0.2, 1.4), STEEL, false)
	mb.box(bridge_c + Vector3(0.0, 11.2, 1.0), Vector3(3.4, 1.6, 0.2), STEEL_DARK, false)         # a radar array
	mb.strut(bridge_c + Vector3(0.0, 12.0, 1.0), bridge_c + Vector3(0.0, 15.0, 1.0), 0.18, STEEL)
	_shape(sp, bridge_c, Vector3(11.0, 6.4, 15.0))
	_shape(sp, bridge_c + Vector3(0.0, 4.3, 1.0), Vector3(8.4, 2.2, 8.0))
	sp["helm"] = Vector3(0.0, y + 4.3, bridge_c.z - 1.0)
	mb.box(Vector3(0.0, y + 2.4, L * 0.5 - 38.0), Vector3(10.0, 4.8, 13.0), NAVY, false)            # the hangar
	mb.box(Vector3(0.0, y + 4.9, L * 0.5 - 38.0), Vector3(10.4, 0.25, 13.4), STEEL_DARK, true)
	_windows(mb, Vector3(0.0, y + 2.4, L * 0.5 - 38.0), 10.0, 4.8, 13.0)
	_shape(sp, Vector3(0.0, y + 2.4, L * 0.5 - 38.0), Vector3(10.0, 4.8, 13.0))
	_funnel(mb, Vector3(-1.6, y, -4.0), 2.6, 7.0, NAVY, STEEL_DARK)
	_funnel(mb, Vector3(1.6, y, 12.0), 2.6, 6.0, NAVY, STEEL_DARK)
	_shape(sp, Vector3(0.0, y + 3.2, 4.0), Vector3(6.4, 6.4, 24.0))
	# the helipad: a dark disc with a white H and ring, flush with the deck, aft
	var pad := Vector3(0.0, y + 0.06, L * 0.5 - 11.0)
	mb.cylinder(pad, 7.4, 0.06, 28, _c(Color(0.2, 0.24, 0.22), 5.0), -1.0, true, false)
	mb.cylinder(pad + Vector3(0.0, 0.05, 0.0), 6.4, 0.03, 28, Color(0.92, 0.92, 0.9, 0.0), -1.0, true, false)
	mb.cylinder(pad + Vector3(0.0, 0.08, 0.0), 6.0, 0.03, 28, _c(Color(0.2, 0.24, 0.22), 5.0), -1.0, true, false)
	mb.box(pad + Vector3(-1.5, 0.11, 0.0), Vector3(0.7, 0.03, 5.0), Color(0.95, 0.95, 0.9, 0.0), false)
	mb.box(pad + Vector3(1.5, 0.11, 0.0), Vector3(0.7, 0.03, 5.0), Color(0.95, 0.95, 0.9, 0.0), false)
	mb.box(pad + Vector3(0.0, 0.11, 0.0), Vector3(3.0, 0.03, 0.7), Color(0.95, 0.95, 0.9, 0.0), false)
	sp["pad"] = pad + Vector3(0.0, 0.2, 0.0)
	# missile cells, close-in guns, rails, boats
	for g in [0, 1]:
		var vc := Vector3(0.0, y + 0.08, -L * 0.5 + 21.0)
		if g == 1:
			vc = Vector3(0.0, y + 0.08, 18.0)
		mb.box(vc, Vector3(6.0, 0.14, 5.0), STEEL_DARK, false)
		for i in 4:
			for j in 3:
				mb.box(vc + Vector3(-2.1 + float(i) * 1.4, 0.1, -1.5 + float(j) * 1.5), Vector3(1.0, 0.05, 1.0), _c(Color(0.35, 0.36, 0.38), 3.0), false)
	for p: Vector3 in [Vector3(-4.2, y, -4.0 - 14.0), Vector3(4.2, y, 24.0)]:
		mb.box(p + Vector3(0.0, 0.7, 0.0), Vector3(1.6, 1.4, 1.6), NAVY, false)
		mb.sphere(p + Vector3(0.0, 2.0, 0.0), Vector3(1.0, 0.9, 1.0), 10, 6, Color(0.88, 0.88, 0.9, 6.0 / 8.0))
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * 5.0, y + 0.5, 0.0), Vector3(0.08, 1.0, L - 60.0), STEEL, false)
		mb.box(Vector3(float(sx) * 6.2, y + 1.2, 38.0), Vector3(2.2, 1.8, 6.0), _c(Color(0.9, 0.5, 0.1), 0.0), false)       # a rescue boat
	# gun pedestals (the rotating houses are nodes): forward and amidships
	var tz := [-L * 0.5 + 26.0, L * 0.5 - 62.0]
	for z in tz:
		mb.cylinder(Vector3(0.0, y, float(z)), 3.0, 0.9, 16, NAVY, -1.0, true, false)
		sp["turrets"].append({"pos": Vector3(0.0, y + 0.9, float(z)), "kind": &"gun"})
	_shape(sp, Vector3(0.0, y + 0.45, tz[0]), Vector3(6.0, 0.9, 6.0))
	_shape(sp, Vector3(0.0, y + 0.45, tz[1]), Vector3(6.0, 0.9, 6.0))
	sp["gangway"] = Vector3(8.0, y, 6.0)


static func turret_mesh() -> ArrayMesh:
	if _cache.has(&"turret"):
		return _cache[&"turret"]["mesh"]
	var mb := MB.new()
	mb.box(Vector3(0.0, 1.1, 0.0), Vector3(4.6, 2.0, 5.2), NAVY, false)
	mb.box(Vector3(0.0, 1.9, -2.6), Vector3(3.6, 1.2, 1.2), NAVY, false)
	mb.box(Vector3(0.0, 2.3, 0.6), Vector3(3.0, 0.5, 3.4), NAVY, false)
	mb.box(Vector3(0.0, 1.5, -3.8), Vector3(0.9, 0.9, 1.0), STEEL_DARK, false)
	mb.box(Vector3(0.0, 1.5, -6.8), Vector3(0.45, 0.45, 5.6), STEEL_DARK, false)                      # the barrel
	mb.box(Vector3(0.0, 1.5, -9.6), Vector3(0.6, 0.6, 0.5), STEEL_DARK, false)                       # the muzzle brake
	mb.box(Vector3(0.0, 1.25, -1.0), Vector3(1.3, 0.14, 0.14), LAMP, false)
	var m := mb.build(RailKit.material(), true)
	_cache[&"turret"] = {"mesh": m, "spec": {}}
	return m


# --- the container ship -----------------------------------------------------------------------------------------------------------------

static func _cargo(mb: MB, sp: Dictionary) -> void:
	var L := 190.0
	var free := 9.0
	_hull(mb, sp, L, 29.0, 6.5, free, 42.0, Color(0.12, 0.16, 0.22, 6.0 / 8.0), Color(0.62, 0.14, 0.1, 0.0), _c(Color(0.45, 0.42, 0.38), 6.0))
	sp["name"] = "CONTAINER SHIP"
	sp["max_speed"] = 12.0
	sp["boardable"] = true
	var y := free
	var bz := L * 0.5 - 24.0
	var house := Vector3(0.0, y + 11.0, bz)
	mb.box(house, Vector3(24.0, 22.0, 16.0), Color(0.93, 0.93, 0.92, 6.0 / 8.0), false)
	for d in 5:
		_windows(mb, Vector3(0.0, y + 3.0 + float(d) * 3.8, bz), 24.0, 3.8, 16.0)
	mb.box(Vector3(0.0, y + 22.6, bz - 3.0), Vector3(26.0, 3.2, 8.0), Color(0.93, 0.93, 0.92, 6.0 / 8.0), false)              # the bridge wings
	_windows(mb, Vector3(0.0, y + 22.6, bz - 3.0), 26.0, 3.2, 8.0)
	_funnel(mb, Vector3(0.0, y + 22.0, bz + 4.0), 3.2, 6.0, Color(0.15, 0.3, 0.6, 6.0 / 8.0), STEEL_DARK)
	_shape(sp, house, Vector3(24.0, 22.0, 16.0))
	_shape(sp, Vector3(0.0, y + 22.6, bz - 3.0), Vector3(26.0, 3.2, 8.0))
	sp["helm"] = Vector3(0.0, y + 21.4, bz - 4.0)
	# the containers: bays of 12.4 m, eight columns across (20 m), one to four high
	var pal: Array[Color] = [Color(0.72, 0.18, 0.14), Color(0.16, 0.34, 0.62), Color(0.86, 0.62, 0.12), Color(0.18, 0.5, 0.34), Color(0.78, 0.78, 0.76), Color(0.4, 0.22, 0.5), Color(0.9, 0.38, 0.12)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3106
	var z0 := -L * 0.5 + 50.0
	var bays := 9
	for b in bays:
		var z := z0 + float(b) * 12.6 + 6.2
		for c in 8:
			var h := 1 + rng.randi() % 4
			var col := pal[rng.randi() % pal.size()]
			for lv in h:
				mb.box(Vector3(-8.75 + float(c) * 2.5, y + 1.3 + float(lv) * 2.62, z), Vector3(2.46, 2.58, 12.2), Color(col.r, col.g, col.b, 1.0 / 8.0), false, Vector2.ZERO, MB.F_BOTTOM)
		_shape(sp, Vector3(0.0, y + 4.5, z), Vector3(20.0, 9.0, 12.4))
	# deck cranes and a forward mast, hatch coamings
	for cz in [-L * 0.5 + 62.0, L * 0.5 - 70.0]:
		mb.box(Vector3(12.5, y + 5.0, cz), Vector3(0.8, 10.0, 0.8), Color(0.88, 0.42, 0.1, 3.0 / 8.0), false)
		mb.strut(Vector3(12.5, y + 10.0, cz), Vector3(12.5, y + 14.0, cz + 18.0), 0.5, Color(0.88, 0.42, 0.1, 3.0 / 8.0))
	mb.box(Vector3(0.0, y + 8.0, -L * 0.5 + 38.0), Vector3(0.6, 16.0, 0.6), STEEL, false)
	sp["gangway"] = Vector3(14.0, y, L * 0.5 - 70.0)


# --- the tanker -------------------------------------------------------------------------------------------------------------------------

static func _tanker(mb: MB, sp: Dictionary) -> void:
	var L := 200.0
	var free := 6.5
	_hull(mb, sp, L, 32.0, 9.0, free, 38.0, Color(0.55, 0.1, 0.08, 6.0 / 8.0), Color(0.1, 0.1, 0.12, 0.0), _c(Color(0.34, 0.36, 0.34), 5.0))
	sp["name"] = "TANKER"
	sp["max_speed"] = 10.0
	var y := free
	var bz := L * 0.5 - 20.0
	mb.box(Vector3(0.0, y + 8.0, bz), Vector3(26.0, 16.0, 16.0), Color(0.93, 0.93, 0.9, 6.0 / 8.0), false)
	for d in 4:
		_windows(mb, Vector3(0.0, y + 2.0 + float(d) * 3.8, bz), 26.0, 3.8, 16.0)
	_funnel(mb, Vector3(0.0, y + 16.0, bz + 4.0), 2.6, 6.0, Color(0.55, 0.1, 0.08, 6.0 / 8.0), STEEL_DARK)
	_shape(sp, Vector3(0.0, y + 8.0, bz), Vector3(26.0, 16.0, 16.0))
	sp["helm"] = Vector3(0.0, y + 15.0, bz - 4.0)
	# the deck: pipes, manifolds, tank hatches, the catwalk
	for k in 5:
		var x := -4.0 + float(k) * 2.0
		mb.box(Vector3(x, y + 0.8, -L * 0.5 + 45.0 + (L - 90.0) * 0.5), Vector3(0.5, 0.5, L - 90.0), Color(0.75 if k % 2 == 0 else 0.3, 0.55 if k % 2 == 0 else 0.1, 0.12, 3.0 / 8.0), false)
	for z in range(int(-L * 0.5 + 52.0), int(L * 0.5 - 40.0), 16):
		mb.box(Vector3(0.0, y + 0.6, float(z)), Vector3(18.0, 0.4, 0.5), STEEL_DARK, false)
		mb.box(Vector3(-8.0, y + 0.5, float(z) + 5.0), Vector3(2.6, 1.0, 2.6), STEEL, false)
		mb.box(Vector3(8.0, y + 0.5, float(z) + 5.0), Vector3(2.6, 1.0, 2.6), STEEL, false)
	mb.box(Vector3(0.0, y + 1.7, -L * 0.5 + 45.0 + (L - 90.0) * 0.5), Vector3(1.2, 0.12, L - 90.0), STEEL, false)
	mb.box(Vector3(0.0, y + 6.0, -L * 0.5 + 40.0), Vector3(0.5, 12.0, 0.5), STEEL, false)
	sp["gangway"] = Vector3(15.0, y, 0.0)


# --- the cruise liner -------------------------------------------------------------------------------------------------------------------

static func _cruise(mb: MB, sp: Dictionary) -> void:
	var L := 250.0
	var free := 11.0
	_hull(mb, sp, L, 34.0, 8.0, free, 55.0, Color(0.95, 0.95, 0.96, 6.0 / 8.0), Color(0.14, 0.2, 0.4, 0.0), _c(Color(0.7, 0.62, 0.5), 5.0))
	sp["name"] = "CRUISE LINER"
	sp["max_speed"] = 11.0
	var y := free
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * 17.04, 6.0, 0.0), Vector3(0.06, 1.2, L - 70.0), Color(0.1, 0.3, 0.7, 0.0), false)               # the blue stripe
		for k in 3:
			mb.box(Vector3(float(sx) * 17.04, 8.2 + float(k) * 0.9, 0.0), Vector3(0.05, 0.5, L - 80.0), GLASS, false)                # cabin windows in the hull
	var l := 196.0
	var w := 29.0
	for d in 6:
		var c := Vector3(0.0, y + 1.6 + float(d) * 3.3, 12.0 - float(d) * 2.0)
		mb.box(c, Vector3(w, 3.2, l), Color(0.96, 0.96, 0.97, 6.0 / 8.0), false)
		_windows(mb, c, w, 3.2, l)
		l -= 16.0
		w -= 2.6
		if d == 5:
			break
	for k in 10:                                                                                                    # lifeboats on the second deck
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(float(sx) * 14.6, y + 3.6, -60.0 + float(k) * 12.0), Vector3(1.8, 1.4, 7.0), Color(0.95, 0.5, 0.1, 0.0), false)
	_funnel(mb, Vector3(0.0, y + 19.0, -4.0), 4.4, 8.0, Color(0.14, 0.2, 0.4, 6.0 / 8.0), Color(0.95, 0.95, 0.96, 6.0 / 8.0))
	_funnel(mb, Vector3(0.0, y + 19.0, 26.0), 4.0, 7.0, Color(0.14, 0.2, 0.4, 6.0 / 8.0), Color(0.95, 0.95, 0.96, 6.0 / 8.0))
	mb.box(Vector3(0.0, y + 21.0, -64.0), Vector3(14.0, 4.0, 10.0), Color(0.96, 0.96, 0.97, 6.0 / 8.0), false)             # the bridge
	_windows(mb, Vector3(0.0, y + 21.0, -64.0), 14.0, 4.0, 10.0)
	mb.strut(Vector3(0.0, y + 23.0, -64.0), Vector3(0.0, y + 32.0, -64.0), 0.4, STEEL)
	_shape(sp, Vector3(0.0, y + 10.0, 12.0), Vector3(24.0, 20.0, 170.0))
	sp["helm"] = Vector3(0.0, y + 19.0, -66.0)
	sp["gangway"] = Vector3(17.0, y, 0.0)


# --- the submarine ----------------------------------------------------------------------------------------------------------------------

static func _along_z(mb: MB, base_r: float, top_r: float, length: float, z0: float, y: float, col: Color) -> void:
	var cyl := MB.new()
	cyl.cylinder(Vector3.ZERO, base_r, length, 16, col, top_r, true, true)
	var start := mb.verts.size()
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, y, z0))
	for i in cyl.verts.size():
		mb.verts.append(xf * cyl.verts[i])
		mb.norms.append(xf.basis * cyl.norms[i])
		mb.uvs.append(cyl.uvs[i])
		mb.uv2s.append(cyl.uv2s[i])
		mb.cols.append(cyl.cols[i])
	for ix in cyl.idx:
		mb.idx.append(ix + start)


static func _submarine(mb: MB, sp: Dictionary) -> void:
	sp["name"] = "SUBMARINE"
	sp["len"] = 75.0
	sp["beam"] = 9.0
	sp["draft"] = 4.0
	sp["free"] = 3.4
	sp["bow"] = 12.0
	sp["max_speed"] = 9.0
	sp["boardable"] = true
	var hull := Color(0.16, 0.18, 0.22, 3.0 / 8.0)
	# main pressure hull: z from -26 to +26, bow cone to -37.5, stern cone to +37.5
	_along_z(mb, 4.4, 4.4, 52.0, -26.0, 0.2, hull)
	# the bow: a cone pointing at -Z (rotate: a cylinder along +z from z0; the cone narrows toward its end, so start at -37 and widen)
	_along_z(mb, 1.0, 4.4, 11.5, -37.5, 0.2, hull)
	_along_z(mb, 4.4, 0.9, 11.5, 26.0, 0.2, hull)
	# the casing (a flat walkable deck), the sail, periscope, planes, rudder, a deck gun
	mb.box(Vector3(0.0, 3.3, 0.0), Vector3(3.6, 0.3, 58.0), Color(0.2, 0.22, 0.24, 5.0 / 8.0), false)
	_shape(sp, Vector3(0.0, 1.6, 0.0), Vector3(3.6, 3.3, 58.0))
	mb.box(Vector3(0.0, 6.6, -8.0), Vector3(3.2, 6.4, 12.0), hull, false)
	mb.box(Vector3(0.0, 9.9, -8.0), Vector3(2.8, 0.3, 11.0), hull, false)
	_shape(sp, Vector3(0.0, 6.6, -8.0), Vector3(3.2, 6.4, 12.0))
	mb.strut(Vector3(0.0, 9.9, -4.0), Vector3(0.0, 13.0, -4.0), 0.18, STEEL)
	mb.strut(Vector3(0.0, 9.9, -7.0), Vector3(0.0, 12.0, -7.0), 0.14, STEEL)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * 3.0, 7.6, -7.0), Vector3(2.6, 0.2, 3.2), hull, false)
		mb.box(Vector3(float(sx) * 4.0, 0.4, 32.0), Vector3(3.4, 0.2, 3.0), hull, false)
	mb.box(Vector3(0.0, 4.2, 33.0), Vector3(0.3, 4.0, 3.4), hull, false)
	mb.box(Vector3(0.0, 4.2, 22.0), Vector3(1.0, 1.0, 2.0), STEEL_DARK, false)
	mb.box(Vector3(0.0, 4.5, 22.5), Vector3(0.2, 0.2, 3.2), STEEL_DARK, false)
	sp["helm"] = Vector3(0.0, 9.4, -9.0)
	sp["gangway"] = Vector3(4.0, 3.3, 14.0)


# --- buoys -------------------------------------------------------------------------------------------------------------------------------

## A mesh of channel buoys at the given points (world positions, origin at the first), red to port and green to starboard along the fairway.
static func buoy_mesh(points: Array, cols: Array) -> ArrayMesh:
	var mb := MB.new()
	for i in points.size():
		var p: Vector3 = points[i]
		var col: Color = cols[i]
		mb.cylinder(p + Vector3(0.0, -0.4, 0.0), 0.9, 1.6, 10, Color(col.r, col.g, col.b, 0.0), 0.55, true, false)
		mb.cylinder(p + Vector3(0.0, 1.2, 0.0), 0.55, 1.4, 10, Color(col.r, col.g, col.b, 0.0), 0.2, true, false)
		mb.box(p + Vector3(0.0, 2.9, 0.0), Vector3(0.7, 0.7, 0.7), Color(col.r, col.g, col.b, 4.0 / 8.0), false)
		mb.strut(p + Vector3(0.0, 2.6, 0.0), p + Vector3(0.0, 4.2, 0.0), 0.12, STEEL)
	return mb.build(RailKit.material(), true)
