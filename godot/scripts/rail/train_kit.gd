class_name TrainKit
extends RefCounted
## Rolling stock meshes and collision. Every car type is ONE merged mesh (paint = vertex colour, rail_kit.gdshader) built once and shared by all instances. A car is modelled in its own space:
## origin on the rail head, x across (the car is 3.0 m wide), z along (the nose / front end faces -Z), the floor at FLOOR_Y over the bed. `spec(type)` returns the data the world needs:
##   len, roof_y (the walkable top), shapes [{pos, size}] (the colliders: floor, roof, end walls, side walls with door gaps), doors (z of the door gaps), seats [Vector3], ladders [Vector3 end positions]
## Passenger cars are hollow (the hero walks in through the door gaps, sits on a seat, climbs to the roof from a ladder at the end); freight wagons are solid on top of a flat bed.
## Types: coach, maglev_cab, maglev_mid, loco_electric, loco_diesel, boxcar, tankcar, hopper, flatcar (with a container). Train consists: CONSISTS.

const MB := preload("res://scripts/world/mesh_builder.gd")
const W := 3.0
const FLOOR := 1.15
const ROOF_Y := 3.9
const GAP := 0.9                                ## metres between cars (couplers)
const GLASS := Color(0.55, 0.78, 1.0, 7.0 / 8.0)
const STEEL := Color(0.52, 0.54, 0.58, 3.0 / 8.0)
const STEEL_DARK := Color(0.18, 0.2, 0.23, 3.0 / 8.0)
const LAMP := Color(1.0, 0.9, 0.62, 4.0 / 8.0)
const LAMP_RED := Color(1.0, 0.25, 0.2, 4.0 / 8.0)
const INTERIOR := Color(0.78, 0.76, 0.7, 0.0)
const SEAT := Color(0.16, 0.3, 0.55, 0.0)
const CONSISTS := {
	&"maglev": [&"maglev_cab", &"maglev_mid", &"maglev_mid", &"maglev_cab"],
	&"express": [&"loco_electric", &"coach", &"coach", &"coach", &"coach", &"loco_electric"],
	&"ore": [&"loco_diesel", &"hopper", &"hopper", &"boxcar", &"tankcar", &"hopper", &"boxcar", &"tankcar", &"hopper", &"loco_diesel"],
	&"regional": [&"loco_diesel", &"coach", &"coach", &"loco_diesel"],
	&"container": [&"loco_diesel", &"flatcar", &"flatcar", &"flatcar", &"flatcar", &"flatcar", &"flatcar", &"loco_diesel"],
}
## Paint per consist: body, stripe.
const PAINT := {
	&"maglev": [Color(0.93, 0.94, 0.96), Color(0.1, 0.5, 0.95)],
	&"express": [Color(0.78, 0.12, 0.1), Color(0.95, 0.9, 0.8)],
	&"ore": [Color(0.8, 0.5, 0.12), Color(0.15, 0.15, 0.17)],
	&"regional": [Color(0.12, 0.34, 0.6), Color(0.95, 0.75, 0.15)],
	&"container": [Color(0.16, 0.45, 0.32), Color(0.95, 0.95, 0.9)],
}

static var _cache := {}                         ## "type/paint" -> {mesh, spec}


static func _c(col: Color, code: float) -> Color:
	return Color(col.r, col.g, col.b, code / 8.0)


static func car_len(type: StringName) -> float:
	match type:
		&"coach":
			return 21.0
		&"maglev_cab":
			return 24.4
		&"maglev_mid":
			return 24.0
		&"loco_electric":
			return 18.0
		&"loco_diesel":
			return 19.0
		&"boxcar":
			return 14.0
		&"tankcar":
			return 13.0
		&"hopper":
			return 12.0
		&"flatcar":
			return 15.0
	return 15.0


static func consist_length(kind: StringName) -> float:
	var total := 0.0
	for t: StringName in CONSISTS[kind]:
		total += car_len(t) + GAP
	return total - GAP


## Offsets (centre of each car along the consist, from the consist centre, + = towards the front end -Z of car 0... here + = towards the last car) and flip flags.
static func layout(kind: StringName) -> Array[Dictionary]:
	var types: Array = CONSISTS[kind]
	var total := consist_length(kind)
	var out: Array[Dictionary] = []
	var acc := -total * 0.5
	for k in types.size():
		var l := car_len(types[k])
		out.append({"type": types[k], "off": acc + l * 0.5, "len": l, "flip": k >= types.size() / 2 and k > 0})
		acc += l + GAP
	return out


## {mesh, spec} for a type in a paint (consist kind).
static func car(type: StringName, kind: StringName) -> Dictionary:
	var key := "%s/%s" % [type, kind]
	if _cache.has(key):
		return _cache[key]
	var p: Array = PAINT[kind]
	var body: Color = p[0]
	var stripe: Color = p[1]
	var mb := MB.new()
	var spec := {"len": car_len(type), "roof_y": ROOF_Y, "shapes": [], "doors": [], "seats": [], "ladders": [], "type": type, "hollow": false}
	match type:
		&"coach":
			_coach(mb, spec, body, stripe, false)
		&"maglev_mid":
			_coach(mb, spec, body, stripe, true)
		&"maglev_cab":
			_maglev_cab(mb, spec, body, stripe)
		&"loco_electric":
			_loco(mb, spec, body, stripe, true)
		&"loco_diesel":
			_loco(mb, spec, body, stripe, false)
		&"boxcar":
			_boxcar(mb, spec, body)
		&"tankcar":
			_tankcar(mb, spec)
		&"hopper":
			_hopper(mb, spec)
		&"flatcar":
			_flatcar(mb, spec, key)
	_bogies(mb, car_len(type), type in [&"maglev_cab", &"maglev_mid"])
	var mesh := mb.build(RailKit.material(), true)
	var res := {"mesh": mesh, "spec": spec, "tris": mb.idx.size() / 3}
	_cache[key] = res
	return res


static func _shape(spec: Dictionary, pos: Vector3, size: Vector3) -> void:
	(spec["shapes"] as Array).append({"pos": pos, "size": size})


## A box seen from the inside (the faces point at the centre): the cabin lining.
static func _inner_box(mb: MB, c: Vector3, size: Vector3, col: Color, skip_bottom := true) -> void:
	var h := size * 0.5
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	mb.quad(Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.LEFT, col)
	mb.quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.RIGHT, col)
	mb.quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.DOWN, col)
	mb.quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.FORWARD, col)
	mb.quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.BACK, col)
	if not skip_bottom:
		mb.quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.UP, col)


static func _bogies(mb: MB, l: float, maglev: bool) -> void:
	if maglev:
		for sx in [-1.0, 1.0]:                                   # hover skirts hugging the guideway
			mb.box(Vector3(float(sx) * 1.25, 0.62, 0.0), Vector3(0.5, 0.9, l - 7.0), STEEL_DARK, false)
		return
	for sz in [-1.0, 1.0]:
		var z := float(sz) * (l * 0.5 - 3.2)
		mb.box(Vector3(0.0, 0.62, z), Vector3(2.5, 0.5, 3.4), STEEL_DARK, false)
		for sx in [-1.0, 1.0]:
			for wz in [-1.1, 1.1]:
				mb.box(Vector3(float(sx) * 0.72, 0.5, z + float(wz)), Vector3(0.14, 0.92, 0.92), STEEL, true)
	mb.box(Vector3(0.0, 0.6, 0.0), Vector3(2.7, 0.45, l - 9.0), STEEL_DARK, false)          # the underframe
	for sz in [-1.0, 1.0]:
		mb.box(Vector3(0.0, 0.95, float(sz) * (l * 0.5 + 0.35)), Vector3(0.3, 0.3, 0.8), STEEL_DARK, false)      # couplers


# --- passenger cars -------------------------------------------------------------------------------------------------------------------

## A hollow coach: floor, roof, end walls, side walls with two door gaps, window bands (outside and inside), seats, ceiling lamps. `slim`: the maglev mid car (rounder roof, blue stripe).
static func _coach(mb: MB, spec: Dictionary, body: Color, stripe: Color, slim: bool) -> void:
	var l: float = spec["len"]
	spec["hollow"] = true
	var bodyc := _c(body, 0.0)
	var wall_h := ROOF_Y - 0.35 - FLOOR
	var doors := [-l * 0.25, l * 0.25]
	spec["doors"] = doors
	_hollow(mb, spec, l, bodyc, _c(stripe, 0.0), doors, 0.0)
	_roof_gear(mb, l, slim)
	spec["ladders"] = [Vector3(0.0, FLOOR, -l * 0.5 - 0.3), Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
	_ladder(mb, Vector3(1.55, 0.0, -l * 0.5 + 0.1))
	_ladder(mb, Vector3(-1.55, 0.0, l * 0.5 - 0.1))
	spec["roof_y"] = ROOF_Y


static func _hollow(mb: MB, spec: Dictionary, l: float, bodyc: Color, stripe: Color, doors: Array, nose: float) -> void:
	var half := W * 0.5
	var wall_t := 0.14
	var y_lo := FLOOR
	var y_hi := ROOF_Y - 0.35
	var wh := y_hi - y_lo
	# floor and roof
	mb.box(Vector3(0.0, FLOOR - 0.1, 0.0), Vector3(W, 0.2, l), _c(Color(0.3, 0.3, 0.32), 0.0), true)
	_shape(spec, Vector3(0.0, FLOOR - 0.15, 0.0), Vector3(W, 0.3, l))
	mb.box(Vector3(0.0, ROOF_Y - 0.17, 0.0), Vector3(W - 0.1, 0.34, l), bodyc, true)
	_shape(spec, Vector3(0.0, ROOF_Y - 0.17, 0.0), Vector3(W, 0.4, l))
	_inner_box(mb, Vector3(0.0, (y_lo + y_hi) * 0.5, 0.0), Vector3(W - 2.0 * wall_t, wh, l - 0.4), INTERIOR, true)
	# end walls
	for sz in [-1.0, 1.0]:
		var zc := float(sz) * (l * 0.5 - 0.1)
		mb.box(Vector3(0.0, (y_lo + y_hi) * 0.5, zc), Vector3(W, wh, 0.2), bodyc, false)
		_shape(spec, Vector3(0.0, (y_lo + y_hi) * 0.5, zc), Vector3(W, wh, 0.25))
	# side walls in pieces between the door gaps, a header over every gap
	var cuts: Array[Vector2] = []
	var cursor := -l * 0.5
	for d: float in doors:
		cuts.append(Vector2(cursor, d - 0.85))
		cursor = d + 0.85
	cuts.append(Vector2(cursor, l * 0.5))
	for sx in [-1.0, 1.0]:
		var xc := float(sx) * (half - wall_t * 0.5)
		for cseg in cuts:
			var ln := cseg.y - cseg.x
			if ln < 0.1:
				continue
			var zc := (cseg.x + cseg.y) * 0.5
			mb.box(Vector3(xc, (y_lo + y_hi) * 0.5, zc), Vector3(wall_t, wh, ln), bodyc, false)
			_shape(spec, Vector3(xc, (y_lo + y_hi) * 0.5, zc), Vector3(wall_t, wh, ln))
			# windows: a band at eye height outside and inside, skipping the ends
			var wx0 := cseg.x + 0.6
			var wx1 := cseg.y - 0.6
			var k := 0
			while wx0 + 1.9 * float(k) + 1.6 <= wx1 + 0.001:
				var zw := wx0 + 1.9 * float(k) + 0.8
				mb.box(Vector3(float(sx) * (half + 0.02), y_lo + 1.35, zw), Vector3(0.05, 0.95, 1.6), GLASS, false)
				mb.quad(Vector3(float(sx) * (half - wall_t - 0.01), y_lo + 0.88, zw - 0.8), Vector3(float(sx) * (half - wall_t - 0.01), y_lo + 1.82, zw - 0.8),
					Vector3(float(sx) * (half - wall_t - 0.01), y_lo + 1.82, zw + 0.8), Vector3(float(sx) * (half - wall_t - 0.01), y_lo + 0.88, zw + 0.8), Vector3(-float(sx), 0.0, 0.0), GLASS)
				k += 1
		for d: float in doors:
			mb.box(Vector3(xc, y_hi - 0.55, d), Vector3(wall_t, 1.1, 1.7), bodyc, false)
			_shape(spec, Vector3(xc, y_hi - 0.55, d), Vector3(wall_t, 1.1, 1.7))
			mb.box(Vector3(xc + float(sx) * 0.02, y_lo + 1.0, d - 0.9), Vector3(0.06, 2.0, 0.08), STEEL_DARK, false)     # door frames
			mb.box(Vector3(xc + float(sx) * 0.02, y_lo + 1.0, d + 0.9), Vector3(0.06, 2.0, 0.08), STEEL_DARK, false)
		# the stripe under the windows
		mb.box(Vector3(float(sx) * (half + 0.01), y_lo + 0.55, 0.0), Vector3(0.04, 0.22, l - 0.6), stripe, false)
	# seats along both walls (clear of the doors), a ceiling lamp strip
	var seats: Array = spec["seats"]
	var z := -l * 0.5 + 1.4
	while z < l * 0.5 - 1.2:
		var near_door := false
		for d: float in doors:
			if absf(z - d) < 1.3:
				near_door = true
		if not near_door:
			for sx in [-1.0, 1.0]:
				var sxc := float(sx) * (half - 0.55)
				mb.box(Vector3(sxc, y_lo + 0.42, z), Vector3(0.55, 0.3, 0.55), SEAT, false)
				mb.box(Vector3(float(sx) * (half - 0.3), y_lo + 0.85, z), Vector3(0.14, 0.7, 0.55), SEAT, false)
				seats.append(Vector3(sxc, y_lo + 0.55, z))
		z += 1.15
	mb.box(Vector3(0.0, ROOF_Y - 0.4, 0.0), Vector3(0.5, 0.05, l - 3.0), LAMP, false)
	spec["seats"] = seats


static func _roof_gear(mb: MB, l: float, slim: bool) -> void:
	for sz in [-1.0, 0.0, 1.0]:
		mb.box(Vector3(0.0, ROOF_Y + 0.16, float(sz) * l * 0.28), Vector3(1.9, 0.3, 3.0), _c(Color(0.78, 0.8, 0.82), 6.0), true)
	if not slim:
		mb.box(Vector3(0.0, ROOF_Y + 0.05, 0.0), Vector3(0.9, 0.1, l - 4.0), STEEL_DARK, false)


static func _ladder(mb: MB, at: Vector3) -> void:
	for k in 7:
		mb.box(Vector3(at.x + signf(at.x) * 0.05, 1.3 + float(k) * 0.4, at.z), Vector3(0.12, 0.05, 0.5), STEEL, false)
	for sz in [-0.22, 0.22]:
		mb.box(Vector3(at.x + signf(at.x) * 0.05, 2.5, at.z + float(sz)), Vector3(0.08, 2.6, 0.05), STEEL, false)


static func _maglev_cab(mb: MB, spec: Dictionary, body: Color, stripe: Color) -> void:
	var l: float = spec["len"]
	spec["hollow"] = true
	var bodyc := _c(body, 0.0)
	var doors := [l * 0.18]
	spec["doors"] = doors
	var nose := 6.4
	# the passenger part is a coach shortened by the nose; the nose is a solid wedge
	var seg_l := l - nose
	var shift := nose * 0.5
	var sub := MB.new()
	var sub_spec := {"len": seg_l, "shapes": [], "doors": [], "seats": []}
	_hollow(sub, sub_spec, seg_l, bodyc, _c(stripe, 0.0), [seg_l * 0.2], 0.0)
	# merge the sub mesh moved by +shift along z
	var start := mb.verts.size()
	for i in sub.verts.size():
		mb.verts.append(sub.verts[i] + Vector3(0.0, 0.0, shift))
		mb.norms.append(sub.norms[i])
		mb.uvs.append(sub.uvs[i])
		mb.uv2s.append(sub.uv2s[i])
		mb.cols.append(sub.cols[i])
	for ix in sub.idx:
		mb.idx.append(ix + start)
	for sh: Dictionary in sub_spec["shapes"]:
		_shape(spec, (sh["pos"] as Vector3) + Vector3(0.0, 0.0, shift), sh["size"])
	for sd: Vector3 in sub_spec["seats"]:
		(spec["seats"] as Array).append(sd + Vector3(0.0, 0.0, shift))
	spec["doors"] = [seg_l * 0.2 + shift]
	# nose: a tapering solid, front at z = -l/2
	var zf := -l * 0.5
	var zb := zf + nose
	var half := W * 0.5
	var top_b := ROOF_Y - 0.05
	var bot_b := 0.75
	var top_f := 2.5
	var bot_f := 1.0
	var hf := 0.55
	var A := [Vector3(-half, bot_b, zb), Vector3(half, bot_b, zb), Vector3(half, top_b, zb), Vector3(-half, top_b, zb)]
	var B := [Vector3(-hf, bot_f, zf), Vector3(hf, bot_f, zf), Vector3(hf, top_f, zf), Vector3(-hf, top_f, zf)]
	mb.quad(A[3], A[2], B[2], B[3], Vector3(0.0, 0.6, -0.6).normalized(), bodyc)
	mb.quad(A[0], A[1], B[1], B[0], Vector3(0.0, -0.6, -0.4).normalized(), STEEL_DARK)
	mb.quad(A[1], A[2], B[2], B[1], Vector3(1.0, 0.0, -0.5).normalized(), bodyc)
	mb.quad(A[0], A[3], B[3], B[0], Vector3(-1.0, 0.0, -0.5).normalized(), bodyc)
	mb.quad(B[0], B[1], B[2], B[3], Vector3(0.0, 0.0, -1.0), bodyc)
	# the windscreen: a dark glass quad on the sloping top, a headlight pair, the stripe
	mb.quad(Vector3(-half + 0.35, top_b - 0.2, zb - 0.2), Vector3(half - 0.35, top_b - 0.2, zb - 0.2), Vector3(hf - 0.1, top_f - 0.05, zf + 0.1), Vector3(-hf + 0.1, top_f - 0.05, zf + 0.1), Vector3(0.0, 0.6, -0.6).normalized(), GLASS)
	mb.box(Vector3(-0.38, 1.5, zf - 0.02), Vector3(0.28, 0.14, 0.06), LAMP, false)
	mb.box(Vector3(0.38, 1.5, zf - 0.02), Vector3(0.28, 0.14, 0.06), LAMP, false)
	mb.quad(Vector3(-half - 0.01, 1.7, zb), Vector3(-half - 0.01, 2.0, zb), Vector3(-hf - 0.01, 1.5, zf), Vector3(-hf - 0.01, 1.2, zf), Vector3.LEFT, _c(stripe, 0.0))
	mb.quad(Vector3(half + 0.01, 1.7, zb), Vector3(half + 0.01, 2.0, zb), Vector3(hf + 0.01, 1.5, zf), Vector3(hf + 0.01, 1.2, zf), Vector3.RIGHT, _c(stripe, 0.0))
	_shape(spec, Vector3(0.0, 2.05, zf + nose * 0.5), Vector3(W * 0.8, 2.3, nose))          # the nose is solid (the hero walks on its top, not through it)
	spec["roof_y"] = ROOF_Y
	spec["ladders"] = [Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
	_ladder(mb, Vector3(1.55, 0.0, l * 0.5 - 0.1))
	for sz in [0.0]:
		mb.box(Vector3(0.0, ROOF_Y + 0.12, 4.0), Vector3(1.8, 0.24, 3.2), _c(Color(0.78, 0.8, 0.82), 6.0), true)


# --- locomotives --------------------------------------------------------------------------------------------------------------------

static func _loco(mb: MB, spec: Dictionary, body: Color, stripe: Color, electric: bool) -> void:
	var l: float = spec["len"]
	var bodyc := _c(body, 6.0)
	var half := W * 0.5
	var top := 3.7 if electric else 3.5
	mb.box(Vector3(0.0, 0.95, 0.0), Vector3(W + 0.1, 0.5, l), STEEL_DARK, true)                               # the frame
	_shape(spec, Vector3(0.0, 2.3, 0.0), Vector3(W, top - 0.75, l))
	# the cab at the front end (-Z): a taller block with the windscreen; the hood behind it
	var cab_l := 6.0
	mb.box(Vector3(0.0, (0.75 + top) * 0.5 + 0.2, -l * 0.5 + cab_l * 0.5), Vector3(W, top - 0.55, cab_l), bodyc, false)
	mb.box(Vector3(0.0, (0.75 + top - 0.5) * 0.5, 2.0), Vector3(W - 0.1, top - 1.0, l - cab_l), bodyc, false)
	mb.box(Vector3(0.0, top + 0.1, -l * 0.5 + cab_l * 0.5), Vector3(W - 0.15, 0.2, cab_l), _c(Color(0.82, 0.83, 0.85), 6.0), true)
	mb.box(Vector3(0.0, 2.9, -l * 0.5 - 0.02), Vector3(W - 0.5, 1.0, 0.08), GLASS, false)                    # windscreen
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * (half + 0.01), 2.85, -l * 0.5 + 2.4), Vector3(0.05, 0.9, 1.5), GLASS, false)   # side windows
		mb.box(Vector3(float(sx) * (half + 0.015), 1.6, 0.0), Vector3(0.04, 0.3, l - 1.0), _c(stripe, 0.0), false)   # the stripe
		mb.box(Vector3(float(sx) * 0.6, 1.5, -l * 0.5 - 0.03), Vector3(0.3, 0.2, 0.06), LAMP, false)              # head lamps
		mb.box(Vector3(float(sx) * 0.9, 1.5, l * 0.5 + 0.03), Vector3(0.22, 0.18, 0.06), LAMP_RED, false)
	mb.box(Vector3(0.0, 1.2, -l * 0.5 - 0.35), Vector3(W - 0.4, 0.9, 0.7), STEEL_DARK, false)              # the pilot
	if electric:
		mb.strut(Vector3(0.0, top + 0.2, 1.2), Vector3(0.0, top + 1.5, 0.2), 0.12, STEEL_DARK)                # pantograph
		mb.strut(Vector3(0.0, top + 1.5, 0.2), Vector3(0.0, top + 0.3, -0.9), 0.12, STEEL_DARK)
		mb.box(Vector3(0.0, top + 1.5, 0.2), Vector3(1.8, 0.07, 0.18), STEEL, false)
	else:
		mb.box(Vector3(0.0, top + 0.28, 4.0), Vector3(1.6, 0.5, 2.0), STEEL_DARK, true)                       # exhaust and fan
		mb.cylinder(Vector3(0.0, top + 0.5, 6.0), 0.55, 0.3, 10, STEEL_DARK, -1.0, true, false)
	for sx in [-1.0, 1.0]:                                                                                   # side walkway rails
		mb.box(Vector3(float(sx) * (half + 0.05), 1.65, 2.0), Vector3(0.05, 0.05, l - cab_l - 0.8), STEEL, false)
	_ladder(mb, Vector3(1.55, 0.0, l * 0.5 - 0.1))
	spec["ladders"] = [Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
	spec["roof_y"] = top + 0.2


# --- freight wagons ----------------------------------------------------------------------------------------------------------------

static func _bed(mb: MB, spec: Dictionary, l: float) -> void:
	mb.box(Vector3(0.0, FLOOR - 0.12, 0.0), Vector3(W, 0.24, l), STEEL_DARK, true)
	_shape(spec, Vector3(0.0, FLOOR - 0.12, 0.0), Vector3(W, 0.3, l))


static func _boxcar(mb: MB, spec: Dictionary, body: Color) -> void:
	var l: float = spec["len"]
	_bed(mb, spec, l)
	var top := 4.0
	var col := _c(body.darkened(0.15), 6.0)
	mb.box(Vector3(0.0, (FLOOR + top) * 0.5, 0.0), Vector3(W - 0.1, top - FLOOR, l - 0.3), col, false)
	_shape(spec, Vector3(0.0, (FLOOR + top) * 0.5, 0.0), Vector3(W - 0.1, top - FLOOR, l - 0.3))
	mb.box(Vector3(0.0, top + 0.1, 0.0), Vector3(W - 0.4, 0.2, l - 0.6), _c(Color(0.5, 0.5, 0.52), 6.0), true)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(float(sx) * (W * 0.5 - 0.02), 2.6, 0.0), Vector3(0.08, 2.4, 3.6), _c(body.darkened(0.4), 0.0), false)     # sliding door
		mb.box(Vector3(float(sx) * (W * 0.5 + 0.02), 2.6, 0.0), Vector3(0.05, 0.12, 3.8), STEEL, false)
	spec["roof_y"] = top + 0.2
	spec["ladders"] = [Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
	_ladder(mb, Vector3(1.55, 0.0, l * 0.5 - 0.1))


static func _tankcar(mb: MB, spec: Dictionary) -> void:
	var l: float = spec["len"]
	_bed(mb, spec, l)
	var cyl := MB.new()
	cyl.cylinder(Vector3.ZERO, 1.38, l - 1.4, 16, _c(Color(0.14, 0.15, 0.17), 3.0), -1.0, true, true)
	var start := mb.verts.size()
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 2.6, -(l * 0.5 - 0.7)))            # lay the cylinder along z, centred
	for i in cyl.verts.size():
		mb.verts.append(xf * cyl.verts[i])
		mb.norms.append(xf.basis * cyl.norms[i])
		mb.uvs.append(cyl.uvs[i])
		mb.uv2s.append(cyl.uv2s[i])
		mb.cols.append(cyl.cols[i])
	for ix in cyl.idx:
		mb.idx.append(ix + start)
	mb.box(Vector3(0.0, 4.0, 0.0), Vector3(0.9, 0.24, 1.2), STEEL, false)                                # the dome
	mb.box(Vector3(0.0, 3.2, 0.0), Vector3(W - 0.8, 0.14, 0.14), STEEL_DARK, false)
	for sz in [-1.0, 1.0]:
		mb.box(Vector3(0.0, 1.5, float(sz) * (l * 0.5 - 1.6)), Vector3(W - 0.9, 0.5, 0.5), STEEL_DARK, false)   # saddles
	_shape(spec, Vector3(0.0, 2.6, 0.0), Vector3(2.4, 2.4, l - 1.4))
	spec["roof_y"] = 3.98
	spec["ladders"] = [Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
	_ladder(mb, Vector3(1.55, 0.0, l * 0.5 - 0.1))


static func _hopper(mb: MB, spec: Dictionary) -> void:
	var l: float = spec["len"]
	_bed(mb, spec, l)
	var col := _c(Color(0.32, 0.24, 0.2), 6.0)
	mb.box(Vector3(0.0, 2.7, 0.0), Vector3(W - 0.1, 2.9, l - 0.3), col, false)
	_shape(spec, Vector3(0.0, 2.7, 0.0), Vector3(W - 0.1, 2.9, l - 0.3))
	mb.box(Vector3(0.0, 4.2, 0.0), Vector3(W - 0.5, 0.35, l - 1.0), _c(Color(0.28, 0.2, 0.15), 5.0), false)      # a heap of ore on top
	mb.box(Vector3(0.0, 4.45, 0.0), Vector3(W - 1.2, 0.3, l - 2.8), _c(Color(0.34, 0.24, 0.17), 5.0), false)
	for k in 4:
		mb.box(Vector3(0.0, 2.7, -l * 0.5 + 1.5 + float(k) * (l - 3.0) / 3.0), Vector3(W + 0.02, 0.14, 0.18), STEEL_DARK, false)
	spec["roof_y"] = 4.1
	spec["ladders"] = [Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
	_ladder(mb, Vector3(1.55, 0.0, l * 0.5 - 0.1))


static func _flatcar(mb: MB, spec: Dictionary, key: String) -> void:
	var l: float = spec["len"]
	_bed(mb, spec, l)
	var palette: Array[Color] = [Color(0.72, 0.18, 0.14), Color(0.16, 0.34, 0.62), Color(0.86, 0.62, 0.12), Color(0.18, 0.5, 0.34), Color(0.78, 0.78, 0.76), Color(0.4, 0.22, 0.5)]
	var h := absi(key.hash())
	var col := palette[h % palette.size()]
	mb.box(Vector3(0.0, FLOOR + 1.3, 0.0), Vector3(2.5, 2.6, 12.2), Color(col.r, col.g, col.b, 1.0 / 8.0), false)
	mb.box(Vector3(0.0, FLOOR + 1.3, 6.12), Vector3(2.2, 2.4, 0.06), Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 1.0 / 8.0), false)
	_shape(spec, Vector3(0.0, FLOOR + 1.3, 0.0), Vector3(2.5, 2.6, 12.2))
	for sz in [-1.0, 1.0]:                                                                                    # twist locks
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(float(sx) * 1.1, FLOOR + 0.1, float(sz) * 5.9), Vector3(0.2, 0.2, 0.2), STEEL_DARK, false)
	spec["roof_y"] = FLOOR + 2.65
	spec["ladders"] = [Vector3(0.0, FLOOR, l * 0.5 + 0.3)]
