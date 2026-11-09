class_name AirportKit
extends RefCounted
## Meshes of EASTFIELD AIRPORT (layout: Airport), built in the FIELD'S LOCAL FRAME (AirportWorld puts them in the world with Airport.FRAME). Three merged meshes whatever the amount of stuff: GROUND (runway, taxiways, apron, all the paint, the helipads), KIT (terminal, jet bridges, control tower,
## hangars, sheds, fuel tanks) and DETAIL (runway / taxiway / approach lights, floodlight masts, windsocks, PAPI: culled beyond 450 m). One more small mesh per remote helipad (`pad_mesh`). They share the
## harbour kit shader (no texture): the vertex colour is the paint, COLOR.a the material (0 paint, 2 concrete, 3 steel, 4 lit glass or lamp, 5 asphalt, 6 cladding).

const MB := preload("res://scripts/world/mesh_builder.gd")
const PAINT := 0.0
const CONCRETE := 2.0 / 8.0
const STEEL := 3.0 / 8.0
const LAMP := 4.0 / 8.0
const ASPHALT := 5.0 / 8.0
const CLAD := 6.0 / 8.0
const Y_GROUND := 0.04
const Y_PAINT := 0.075
const WHITE := Color(0.92, 0.92, 0.9, PAINT)
const YELLOW := Color(0.95, 0.78, 0.12, PAINT)

# seven segments of a painted digit: a top, b upper right, c lower right, d bottom, e lower left, f upper left, g middle
const DIGITS := {"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg"}


static func _c(col: Color, code: float) -> Color:
	return Color(col.r, col.g, col.b, code)


## A flat painted rectangle on the ground (x0..x1, z0..z1) at height y.
static func _flat(mb: MB, x0: float, x1: float, z0: float, z1: float, y: float, col: Color) -> void:
	mb.quad(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP, col)


# --- the ground ----------------------------------------------------------------------------------------------------------------------------

static func ground() -> ArrayMesh:
	var mb := MB.new()
	var rx := Airport.RUNWAY_X
	var rw := Airport.RUNWAY_W * 0.5
	var asphalt := _c(Color(0.17, 0.17, 0.18), ASPHALT)
	var asphalt2 := _c(Color(0.2, 0.2, 0.21), ASPHALT)
	var apron := _c(Color(0.46, 0.46, 0.45), CONCRETE)
	# runway, shoulders, taxiway, connectors, apron
	_flat(mb, rx - rw - 3.0, rx + rw + 3.0, Airport.RUNWAY_N - 12.0, Airport.RUNWAY_S + 12.0, Y_GROUND - 0.01, asphalt2)
	_flat(mb, rx - rw, rx + rw, Airport.RUNWAY_N, Airport.RUNWAY_S, Y_GROUND, asphalt)
	var tx := Airport.TAXI_X
	var tw := Airport.TAXI_W * 0.5
	_flat(mb, tx - tw, tx + tw, Airport.RUNWAY_N + 25.0, Airport.RUNWAY_S - 15.0, Y_GROUND, asphalt2)
	for cz in Airport.CONNECTORS:
		_flat(mb, tx + tw - 1.0, rx - rw + 1.0, cz - tw, cz + tw, Y_GROUND, asphalt2)
	var A := Airport.APRON
	_flat(mb, A.position.x, A.end.x + 2.0, A.position.y, A.end.y, Y_GROUND, apron)
	_flat(mb, A.end.x, tx - tw + 1.0, A.position.y + 26.0, A.end.y - 26.0, Y_GROUND, asphalt2)       # the link between the apron and the taxiway
	# the runway paint: edge lines, centre dashes, threshold bars, touchdown marks, the numbers
	_flat(mb, rx - rw + 0.6, rx - rw + 1.2, Airport.RUNWAY_N, Airport.RUNWAY_S, Y_PAINT, WHITE)
	_flat(mb, rx + rw - 1.2, rx + rw - 0.6, Airport.RUNWAY_N, Airport.RUNWAY_S, Y_PAINT, WHITE)
	var z := Airport.RUNWAY_N + 130.0
	while z < Airport.RUNWAY_S - 130.0:
		_flat(mb, rx - 0.45, rx + 0.45, z, z + 30.0, Y_PAINT, WHITE)
		z += 50.0
	for end in [Airport.RUNWAY_N, Airport.RUNWAY_S]:
		var sgn := 1.0 if end == Airport.RUNWAY_N else -1.0
		for i in 8:                                                                                   # the threshold bars
			var bx := rx - rw + 3.0 + float(i) * (Airport.RUNWAY_W - 6.0) / 8.0 + 1.0
			_flat(mb, bx, bx + 2.2, end + sgn * 4.0, end + sgn * 34.0, Y_PAINT, WHITE)
		for off in [150.0, 220.0, 300.0]:                                                             # the touchdown zone marks and the aiming point
			var zz: float = end + sgn * off
			var wdt := 6.0 if off < 290.0 else 9.0
			for sx in [-1.0, 1.0]:
				_flat(mb, rx + float(sx) * 7.0 - wdt * 0.5, rx + float(sx) * 7.0 + wdt * 0.5, zz, zz + sgn * (24.0 if off > 290.0 else 18.0), Y_PAINT, WHITE)
	_digits(mb, "09", Vector3(rx, Y_PAINT, Airport.RUNWAY_S - 60.0), -1.0)                                # read by a plane coming from the local south = the west (text up = local north = -Z)
	_digits(mb, "27", Vector3(rx, Y_PAINT, Airport.RUNWAY_N + 60.0), 1.0)
	# taxiway and gate lines (yellow)
	z = Airport.RUNWAY_N + 40.0
	while z < Airport.RUNWAY_S - 40.0:
		_flat(mb, tx - 0.2, tx + 0.2, z, z + 14.0, Y_PAINT, YELLOW)
		z += 20.0
	for cz in Airport.CONNECTORS:
		_flat(mb, tx + tw, rx - rw - 0.5, cz - 0.2, cz + 0.2, Y_PAINT, YELLOW)                       # the connector centre line
		_flat(mb, rx - rw - 6.0, rx - rw - 5.2, cz - tw, cz + tw, Y_PAINT, YELLOW)                   # the hold-short bars
		_flat(mb, rx - rw - 4.4, rx - rw - 3.9, cz - tw, cz + tw, Y_PAINT, YELLOW)
	for gz in Airport.GATE_Z:
		_flat(mb, Airport.GATE_X - 2.0, A.end.x - 4.0, gz - 0.25, gz + 0.25, Y_PAINT, YELLOW)         # the lead-in line of a gate
		_flat(mb, Airport.GATE_X - 4.0, Airport.GATE_X - 3.0, gz - 3.0, gz + 3.0, Y_PAINT, YELLOW)    # the stop bar
	# the helipads of the apron
	for p in Airport.pads():
		if p["kind"] == &"apron":
			_helipad(mb, (p["local"] as Vector3), float(p["r"]), 0.0)
	return mb.build(BridgeKit.kit_material())


## A painted helipad: a lighter disc inside a yellow ring and a big H (`y0` = the surface height; the pad's world position).
static func _helipad(mb: MB, c: Vector3, r: float, y0: float) -> void:
	var y := c.y + y0
	mb.cylinder(Vector3(c.x, y + 0.03, c.z), r, 0.04, 20, _c(Color(0.95, 0.78, 0.12), PAINT), -1.0, true, false)
	mb.cylinder(Vector3(c.x, y + 0.06, c.z), r - 0.7, 0.03, 20, _c(Color(0.46, 0.47, 0.48), CONCRETE), -1.0, true, false)
	var hw := r * 0.34
	var hh := r * 0.46
	var t := r * 0.11
	mb.box(Vector3(c.x - hw, y + 0.11, c.z), Vector3(t, 0.03, hh * 2.0), WHITE, false)
	mb.box(Vector3(c.x + hw, y + 0.11, c.z), Vector3(t, 0.03, hh * 2.0), WHITE, false)
	mb.box(Vector3(c.x, y + 0.11, c.z), Vector3(hw * 2.0, 0.03, t), WHITE, false)


## The mesh of one remote helipad (roof, mountain, site), built around the origin: the node sits at the pad position. A pad on a roof stands on four legs and has a rim of lights.
static func pad_mesh(p: Dictionary) -> ArrayMesh:
	var mb := MB.new()
	var r: float = p["r"]
	var roof: bool = p["kind"] == &"roof"
	if roof:
		mb.cylinder(Vector3(0.0, -0.5, 0.0), r + 1.0, 0.5, 20, _c(Color(0.5, 0.51, 0.53), STEEL), -1.0, true, true)
		for k in 4:
			var a := TAU * (float(k) + 0.5) / 4.0
			mb.box(Vector3(cos(a) * r * 0.7, -1.7, sin(a) * r * 0.7), Vector3(0.5, 2.4, 0.5), _c(Color(0.3, 0.32, 0.35), STEEL), false)
		for k in 12:
			var a2 := TAU * float(k) / 12.0
			mb.box(Vector3(cos(a2) * (r + 0.9), 0.1, sin(a2) * (r + 0.9)), Vector3(0.4, 0.3, 0.4), _c(Color(1.0, 0.86, 0.5), LAMP), true)
		_helipad(mb, Vector3.ZERO, r, 0.0)
	else:
		mb.cylinder(Vector3(0.0, -0.02, 0.0), r + 2.5, 0.06, 20, _c(Color(0.52, 0.52, 0.5), CONCRETE), -1.0, true, false)      # a slab a little wider than the ring
		_helipad(mb, Vector3.ZERO, r, 0.0)
	return mb.build(BridgeKit.kit_material())


## A painted number: two digits side by side, `up` = -1 reads with its top towards -Z (north), +1 towards +Z. `c` = the centre of the pair.
static func _digits(mb: MB, text: String, c: Vector3, up: float) -> void:
	var h := 10.0
	var w := 4.6
	var t := 0.95
	var gap := 2.4
	var total := w * 2.0 + gap
	for i in text.length():
		var u0 := -total * 0.5 + float(i) * (w + gap) + w * 0.5            # the digit's centre along the reading direction
		var segs: String = DIGITS.get(text[i], "")
		for s in segs:
			var seg_u := 0.0
			var seg_v := 0.0
			var su := t
			var sv := t
			match s:
				"a":
					seg_v = h * 0.5 - t * 0.5
					su = w
				"d":
					seg_v = -h * 0.5 + t * 0.5
					su = w
				"g":
					su = w
				"b", "c", "e", "f":
					sv = h * 0.5
					seg_u = (w * 0.5 - t * 0.5) * (1.0 if s in ["b", "c"] else -1.0)
					seg_v = (h * 0.25) * (1.0 if s in ["b", "f"] else -1.0)
			var lu := u0 + seg_u
			# the text's "up" is -Z for up = -1, its "right" is +X (up = -1) or -X (up = +1)
			var wx := c.x + lu * (1.0 if up < 0.0 else -1.0)
			var wz := c.z - seg_v * (1.0 if up < 0.0 else -1.0)
			mb.box(Vector3(wx, c.y + 0.012, wz), Vector3(su, 0.03, sv), WHITE, false)


# --- the buildings -------------------------------------------------------------------------------------------------------------------------

static func kit() -> ArrayMesh:
	var mb := MB.new()
	for b: Dictionary in Airport.BUILDINGS:
		var p: Vector2 = b["pos"]
		var sz: Vector3 = b["size"]
		match b["kind"]:
			&"terminal":
				_terminal(mb, p, sz)
			&"tower":
				_tower(mb, p, sz)
			&"hangar":
				_hangar(mb, p, sz)
			_:
				_shed(mb, p, sz, b["id"] == &"fire_station")
	for t: Dictionary in Airport.TANKS:
		var tp: Vector2 = t["pos"]
		var r: float = t["r"]
		var h: float = t["h"]
		mb.cylinder(Vector3(tp.x, 0.0, tp.y), r, h, 16, _c(Color(0.86, 0.87, 0.88), STEEL), -1.0, true, false)
		mb.cylinder(Vector3(tp.x, h, tp.y), r * 0.96, 0.5, 16, _c(Color(0.6, 0.62, 0.64), STEEL), r * 0.4, true, false)
		mb.box(Vector3(tp.x + r * 0.9, h * 0.5, tp.y), Vector3(0.4, h, 0.4), _c(Color(0.45, 0.47, 0.5), STEEL), false)             # the ladder
		mb.cylinder(Vector3(tp.x, 0.0, tp.y), r + 0.3, 0.9, 16, _c(Color(0.5, 0.5, 0.48), CONCRETE), -1.0, true, false)            # the plinth
	# the fuel apron slab and a couple of ground vehicles' parking bays are paint on the ground mesh; the hangar aprons are the big apron
	return mb.build(BridgeKit.kit_material())


static func _terminal(mb: MB, p: Vector2, sz: Vector3) -> void:
	var c := Vector3(p.x, sz.y * 0.5, p.y)
	mb.box(c, sz, _c(Color(0.78, 0.78, 0.76), CONCRETE), false)
	mb.box(Vector3(p.x - 1.0, sz.y + 0.35, p.y), Vector3(sz.x + 1.4, 0.7, sz.z + 1.4), _c(Color(0.36, 0.38, 0.42), STEEL), true)             # the roof slab
	# the glass front on the apron side (the east face): a lit band with mullions, a lower dark base
	var xf := p.x + sz.x * 0.5 + 0.05
	mb.box(Vector3(xf, 4.2, p.y), Vector3(0.3, 5.6, sz.z - 6.0), _c(Color(0.14, 0.24, 0.36), LAMP), false)
	var z := p.y - sz.z * 0.5 + 6.0
	while z < p.y + sz.z * 0.5 - 5.0:
		mb.box(Vector3(xf + 0.12, 4.2, z), Vector3(0.3, 5.8, 0.35), _c(Color(0.3, 0.32, 0.36), STEEL), false)
		z += 6.0
	mb.box(Vector3(xf + 0.12, 0.9, p.y), Vector3(0.3, 1.8, sz.z - 4.0), _c(Color(0.28, 0.3, 0.33), CONCRETE), false)
	# the canopy over the gates and its columns
	mb.box(Vector3(xf + 3.2, 8.6, p.y), Vector3(7.0, 0.5, sz.z - 2.0), _c(Color(0.3, 0.33, 0.38), STEEL), true)
	z = p.y - sz.z * 0.5 + 8.0
	while z < p.y + sz.z * 0.5 - 6.0:
		mb.box(Vector3(xf + 6.0, 4.3, z), Vector3(0.45, 8.6, 0.45), _c(Color(0.4, 0.42, 0.46), STEEL), false)
		z += 19.0
	# a sign band with the airport's name colours, and the roof plant
	mb.box(Vector3(xf + 0.35, 10.2, p.y), Vector3(0.3, 1.6, 60.0), _c(Color(0.9, 0.55, 0.1), LAMP), false)
	for i in 5:
		mb.box(Vector3(p.x - 3.0, sz.y + 1.7, p.y - 70.0 + float(i) * 34.0), Vector3(5.0, 2.4, 7.0), _c(Color(0.55, 0.57, 0.6), STEEL), true)
	# jet bridges from the terminal to the gates: a long box and a rotunda at each end
	for gz in Airport.GATE_Z:
		var x0 := xf + 0.2
		var x1 := Airport.GATE_X + 1.5
		mb.box(Vector3((x0 + x1) * 0.5, 4.6, gz), Vector3(x1 - x0, 2.6, 2.7), _c(Color(0.7, 0.72, 0.75), STEEL), true)
		mb.box(Vector3((x0 + x1) * 0.5, 4.55, gz), Vector3(x1 - x0 - 3.0, 0.9, 2.78), _c(Color(0.14, 0.24, 0.36), LAMP), false)
		mb.cylinder(Vector3(x1, 0.0, gz), 1.5, 3.4, 10, _c(Color(0.4, 0.42, 0.46), STEEL), -1.0, true, false)
		mb.cylinder(Vector3(x1 - 0.5, 3.4, gz), 1.9, 1.0, 10, _c(Color(0.7, 0.72, 0.75), STEEL), -1.0, true, false)


static func _tower(mb: MB, p: Vector2, sz: Vector3) -> void:
	var h := sz.y
	mb.cylinder(Vector3(p.x, 0.0, p.y), 4.6, h, 12, _c(Color(0.74, 0.74, 0.72), CONCRETE), 3.6, true, false)
	for k in 5:                                                                                     # slim windows up the shaft
		var a := float(k) * TAU / 5.0
		mb.box(Vector3(p.x + cos(a) * 4.0, h * (0.25 + 0.14 * float(k % 3)), p.y + sin(a) * 4.0), Vector3(0.5, 1.4, 0.5), _c(Color(0.14, 0.24, 0.36), LAMP), true)
	mb.cylinder(Vector3(p.x, h, p.y), 5.2, 1.0, 12, _c(Color(0.36, 0.38, 0.42), STEEL), 6.8, true, true)         # the flared base of the cab
	mb.cylinder(Vector3(p.x, h + 1.0, p.y), 6.8, 4.0, 12, _c(Color(0.14, 0.26, 0.38), LAMP), -1.0, true, false)  # the glass cab
	for k in 12:                                                                                    # window frames
		var a2 := float(k) * TAU / 12.0
		mb.box(Vector3(p.x + cos(a2) * 6.85, h + 3.0, p.y + sin(a2) * 6.85), Vector3(0.3, 4.0, 0.3), _c(Color(0.3, 0.32, 0.36), STEEL), false)
	mb.cylinder(Vector3(p.x, h + 5.0, p.y), 7.6, 0.7, 12, _c(Color(0.34, 0.36, 0.4), STEEL), 5.4, true, true)    # the cab roof
	mb.box(Vector3(p.x, h + 8.2, p.y), Vector3(0.3, 5.5, 0.3), _c(Color(0.7, 0.2, 0.2), STEEL), false)          # the mast
	mb.box(Vector3(p.x, h + 11.1, p.y), Vector3(0.9, 0.9, 0.9), _c(Color(1.0, 0.25, 0.2), LAMP), true)           # the warning light


static func _hangar(mb: MB, p: Vector2, sz: Vector3) -> void:
	var body := _c(Color(0.62, 0.64, 0.66), CLAD)
	mb.box(Vector3(p.x, sz.y * 0.5, p.y), sz, body, false)
	# an arched-looking roof: three stepped slabs, wider than the walls
	var roof := _c(Color(0.42, 0.44, 0.48), CLAD)
	mb.box(Vector3(p.x, sz.y + 0.5, p.y), Vector3(sz.x + 1.0, 1.0, sz.z + 1.0), roof, true)
	mb.box(Vector3(p.x, sz.y + 1.4, p.y), Vector3(sz.x - 6.0, 1.0, sz.z - 4.0), roof, true)
	mb.box(Vector3(p.x, sz.y + 2.2, p.y), Vector3(sz.x - 16.0, 0.8, sz.z - 10.0), roof, true)
	# the big door on the apron (east) face: dark, with a lit stripe and a number
	var xf := p.x + sz.x * 0.5 + 0.06
	mb.box(Vector3(xf, sz.y * 0.38, p.y), Vector3(0.2, sz.y * 0.76, sz.z - 6.0), _c(Color(0.22, 0.24, 0.27), CLAD), false)
	mb.box(Vector3(xf + 0.06, sz.y * 0.84, p.y), Vector3(0.2, 0.7, sz.z - 6.0), _c(Color(0.95, 0.6, 0.12), LAMP), false)
	for i in 4:
		mb.box(Vector3(xf + 0.08, sz.y * 0.38, p.y - (sz.z - 6.0) * 0.375 + float(i) * (sz.z - 6.0) * 0.25), Vector3(0.2, sz.y * 0.76, 0.25), _c(Color(0.5, 0.52, 0.55), STEEL), false)
	for k in 3:
		mb.box(Vector3(p.x - sz.x * 0.5 - 1.2, 5.0, p.y - sz.z * 0.3 + float(k) * sz.z * 0.3), Vector3(1.0, 1.4, 1.2), _c(Color(0.4, 0.42, 0.45), STEEL), true)    # vents


static func _shed(mb: MB, p: Vector2, sz: Vector3, red: bool) -> void:
	var col := Color(0.62, 0.2, 0.16) if red else Color(0.7, 0.68, 0.62)
	mb.box(Vector3(p.x, sz.y * 0.5, p.y), sz, _c(col, CLAD), false)
	mb.box(Vector3(p.x, sz.y + 0.4, p.y), Vector3(sz.x + 0.8, 0.8, sz.z + 0.8), _c(Color(0.36, 0.38, 0.42), CLAD), true)
	var xf := p.x + sz.x * 0.5 + 0.05
	var nd := 3 if red else 4
	for i in nd:
		mb.box(Vector3(xf, 2.2, p.y - sz.z * 0.5 + (float(i) + 0.5) * sz.z / float(nd)), Vector3(0.2, 4.0, sz.z / float(nd) - 1.6), _c(Color(0.9, 0.9, 0.9) if red else Color(0.3, 0.32, 0.36), CLAD), false)


# --- lights, masts, windsocks ---------------------------------------------------------------------------------------------------------------

static func detail() -> ArrayMesh:
	var mb := MB.new()
	var rx := Airport.RUNWAY_X
	var rw := Airport.RUNWAY_W * 0.5
	var white := _c(Color(1.0, 0.96, 0.85), LAMP)
	var amber := _c(Color(1.0, 0.7, 0.25), LAMP)
	var blue := _c(Color(0.35, 0.5, 1.0), LAMP)
	var red := _c(Color(1.0, 0.18, 0.12), LAMP)
	var green := _c(Color(0.2, 1.0, 0.4), LAMP)
	# runway edge lights every 30 m, centre-line lights, threshold lights (green on the near end, red on the far end of each direction: both ends show both)
	var z := Airport.RUNWAY_N
	while z <= Airport.RUNWAY_S + 0.1:
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(rx + float(sx) * (rw + 1.4), 0.25, z), Vector3(0.45, 0.5, 0.45), white, false)
		z += 30.0
	for end in [Airport.RUNWAY_N, Airport.RUNWAY_S]:
		var sgn := 1.0 if end == Airport.RUNWAY_N else -1.0
		for i in 9:
			var lx := rx - rw + 1.0 + float(i) * (Airport.RUNWAY_W - 2.0) / 8.0
			mb.box(Vector3(lx, 0.15, end - sgn * 0.6), Vector3(0.45, 0.3, 0.45), green, false)
			mb.box(Vector3(lx, 0.15, end + sgn * 0.6), Vector3(0.45, 0.3, 0.45), red, false)
		for i in 12:                                                                                # the approach lights: a line of posts with a crossbar every fifth
			var az: float = end - sgn * (20.0 + float(i) * 24.0)
			mb.box(Vector3(rx, 0.45, az), Vector3(0.5, 0.9, 0.5), white, false)
			if i % 3 == 0:
				for k in range(-2, 3):
					mb.box(Vector3(rx + float(k) * 2.2, 0.35, az), Vector3(0.4, 0.7, 0.4), white, false)
	# taxiway edge lights (blue) and the gate floodlight masts
	var tx := Airport.TAXI_X
	z = Airport.RUNWAY_N + 40.0
	while z < Airport.RUNWAY_S - 40.0:
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(tx + float(sx) * (Airport.TAXI_W * 0.5 + 0.6), 0.25, z), Vector3(0.35, 0.5, 0.35), blue, false)
		z += 30.0
	for mz in [-940.0, -820.0, -700.0, -580.0, -460.0, -340.0, -220.0]:
		var mx := Airport.APRON.end.x - 6.0
		mb.box(Vector3(mx, 9.0, mz), Vector3(0.5, 18.0, 0.5), _c(Color(0.45, 0.47, 0.5), STEEL), false)
		mb.box(Vector3(mx - 0.8, 18.3, mz), Vector3(2.6, 0.7, 1.0), _c(Color(1.0, 0.95, 0.8), LAMP), true)
	# PAPI beside the south threshold (four boxes, two red two white) and the windsocks
	for i in 4:
		mb.box(Vector3(rx - rw - 14.0 - float(i) * 3.0, 0.5, Airport.RUNWAY_S - 20.0), Vector3(1.0, 1.0, 1.0), red if i < 2 else white, true)
	for ws in [Vector3(rx + rw + 22.0, 0.0, Airport.RUNWAY_S - 90.0), Vector3(rx + rw + 22.0, 0.0, Airport.RUNWAY_N + 90.0)]:
		mb.box(ws + Vector3(0.0, 3.5, 0.0), Vector3(0.25, 7.0, 0.25), _c(Color(0.85, 0.85, 0.85), STEEL), false)
		var start := mb.verts.size()
		mb.cylinder(Vector3(0.0, 0.0, 0.0), 0.9, 4.2, 10, _c(Color(1.0, 0.45, 0.1), PAINT), 0.35, false, false)
		var xf := Transform3D(Basis(Vector3.BACK, -(PI * 0.5 - 0.15)), ws + Vector3(0.5, 6.9, 0.0))                  # a sock hanging out to the side, pointing along +x
		mb.xform_from(start, xf)
		mb.box(ws + Vector3(0.0, 7.1, 0.0), Vector3(0.5, 0.3, 0.5), _c(Color(1.0, 0.2, 0.15), LAMP), true)
	# a fence along the road side of the apron (low posts and a rail), and the control tower's neighbour: a radar dish
	var fz := Airport.APRON.position.y + 4.0
	while fz < Airport.APRON.end.y - 4.0:
		mb.box(Vector3(Airport.APRON.end.x + 0.5, 0.9, fz), Vector3(0.12, 1.8, 0.12), _c(Color(0.5, 0.52, 0.55), STEEL), false)
		fz += 12.0
	mb.box(Vector3(Airport.APRON.end.x + 0.5, 1.5, (Airport.APRON.position.y + Airport.APRON.end.y) * 0.5), Vector3(0.06, 0.1, Airport.APRON.end.y - Airport.APRON.position.y - 8.0), _c(Color(0.5, 0.52, 0.55), STEEL), false)
	return mb.build(BridgeKit.kit_material())
