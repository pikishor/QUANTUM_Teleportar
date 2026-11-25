extends RefCounted
## w123-critic: sidewalk walkers step around the solid kerb furniture instead of walking through it. The crowd walks lines 11.3 m from a road's centre (kerb at 10), and the
## kerb props (transformers, kiosks, benches, planters, lamps, the wave 123 second kerb row ...) stand from 10.45 m inwards: before wave 123 about 5% of walker samples near the
## hero stood inside a prop. One table per sidewalk line (0.5 m cells along it) holds how far from the road centre a walker may be there (the road-side edge of the props, less
## a body radius); a walker eases towards the kerb ahead of a prop and back after it. Built once from the city's collider sources (no nodes, no draw calls).
## Switch: StreetLife.critic (env W123C_OLD=1: off).

const CELL := 0.5
const BODY := 0.32                ## half a walker's width plus air
const BAND_IN := 10.2             ## the walker band (distance from the road centre) a prop must reach into to count
const BAND_OUT := 12.6
const FLOOR := 9.75               ## never step further into the gutter than this
const EASE := 3.5                 ## 1/s: how fast a walker side-steps
const LOOK := [0.0, 0.8, 1.6, 2.4]

static var lines := {}            ## key (axis * 64 + road) * 2 + side -> PackedFloat32Array of limits (INF free)
static var built_for: Object = null
static var u0 := 0.0
static var ncell := 0


static func _line_key(axis: int, road: int, side: int) -> int:
	return (axis * 64 + road) * 2 + (1 if side > 0 else 0)


## Build the tables from the city's collider sources (once per world).
static func build(city) -> void:
	built_for = city
	lines.clear()
	var edge := CityLayout.HALF + 16.0
	u0 = -edge
	ncell = int(ceilf(edge * 2.0 / CELL)) + 1
	if city == null or not city.has_method(&"prop_colliders"):
		return
	var pc = city.prop_colliders()
	if pc == null:
		return
	for id in pc._xf.size():
		var xf: Transform3D = pc._xf[id]
		if absf(xf.origin.y) > 1.5 or absf(xf.origin.x) > edge or absf(xf.origin.z) > edge:
			continue
		var spec: Array = pc._spec_list[pc._spec[id]]
		var sz: Vector3 = spec[1]
		var off: Vector3 = spec[2]
		var c: Vector3 = xf.origin + xf.basis * Vector3(off.x, 0.0, off.z)
		var hx := 0.0
		var hz := 0.0
		if int(spec[0]) == 0:
			var ax: Vector3 = xf.basis.x * sz.x * 0.5
			var az: Vector3 = xf.basis.z * sz.z * 0.5
			hx = absf(ax.x) + absf(az.x)
			hz = absf(ax.z) + absf(az.z)
		else:
			hx = sz.x
			hz = sz.x
		_mark(0, c.x, c.z, hx, hz)          # lines along x: lateral is z
		_mark(1, c.z, c.x, hz, hx)          # lines along z: lateral is x


static func _mark(axis: int, u: float, lat: float, hu: float, hl: float) -> void:
	var road := roundi((lat + CityLayout.HALF) / CityLayout.PITCH)
	if road < 0 or road > CityLayout.N:
		return
	var cen := -CityLayout.HALF + road * CityLayout.PITCH
	var d := lat - cen
	var side := 1 if d > 0.0 else -1
	var near := absf(d) - hl
	var far := absf(d) + hl
	if far < BAND_IN or near > BAND_OUT:
		return
	var lim := maxf(FLOOR, near - BODY)
	var key := _line_key(axis, road, side)
	var arr: PackedFloat32Array = lines.get(key, PackedFloat32Array())
	if arr.is_empty():
		arr.resize(ncell)
		arr.fill(INF)
	var a := clampi(int(floorf((u - hu - BODY - u0) / CELL)), 0, ncell - 1)
	var b := clampi(int(ceilf((u + hu + BODY - u0) / CELL)), 0, ncell - 1)
	for k in range(a, b + 1):
		arr[k] = minf(arr[k], lim)
	lines[key] = arr


## The lateral shift (signed, world lateral axis) a walker on line `lat` of `axis` at `u` walking `dir` wants now, given its own lateral position `l` (lat + off).
static func want(axis: int, lat: float, l: float, u: float, dir: float) -> float:
	var road := roundi((lat + CityLayout.HALF) / CityLayout.PITCH)
	var cen := -CityLayout.HALF + road * CityLayout.PITCH
	var side := 1 if lat > cen else -1
	var arr: PackedFloat32Array = lines.get(_line_key(axis, road, side), PackedFloat32Array())
	if arr.is_empty():
		return 0.0
	var lim := INF
	for la: float in LOOK:
		var k := int(floorf((u + dir * la - u0) / CELL))
		if k >= 0 and k < ncell:
			lim = minf(lim, arr[k])
	var dist := absf(l - cen)
	if dist <= lim:
		return 0.0
	return -(dist - lim) * float(side)        # towards the road centre
