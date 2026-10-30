class_name CityLayout
extends RefCounted
## Deterministic city layout and spatial queries for the world module. Pure data: no nodes, no rendering,
## so it can be unit-tested headless and shared by the visual builders.
##
## The rules and the random stream are ported from src/world.js (mulberry32(2025), same call order), so the lots
## are the same ones the play-tested Three.js prototype had: 8x8 blocks, 4 lots per block, footprints 18/26 m,
## heights 16/28/44/62/88 m (taller toward the centre) and 10 % plazas.

const PITCH := 80.0            ## distance between road centre lines
const ROAD := 20.0             ## road width
const N := 8                   ## blocks per side
const HALF := 320.0            ## N * PITCH / 2
const BLOCK := 60.0            ## PITCH - ROAD: the block (sidewalk) square between roads
const LANE := 5.0              ## lane centre offset from a road's centre line
const BORDER := 30.0           ## invisible walls stand at HALF + BORDER
const LOT_OFFSET := 15.0       ## lot centre offset from the block centre
const SEED := 2025

const HEIGHTS: Array[float] = [16.0, 28.0, 44.0, 62.0, 88.0]
const FOOT: Array[float] = [18.0, 26.0]
const NTINTS := 6
const NNEON := 4

## One building footprint. `rect` is (x0, z0) / (w, d) in world metres.
class Lot extends RefCounted:
	var rect := Rect2()
	var cx := 0.0
	var cz := 0.0
	var w := 0.0
	var d := 0.0
	var h := 0.0
	var tint := 0              ## index into the facade tint palette
	var neon := 0              ## index into the neon palette
	var block_i := 0
	var block_j := 0

	func contains_xz(x: float, z: float, margin := 0.0) -> bool:
		return x > rect.position.x - margin and x < rect.end.x + margin and z > rect.position.y - margin and z < rect.end.y + margin


var lots: Array[Lot] = []
## Lot centres that stayed empty (plazas), as (x, z).
var plazas: Array[Vector2] = []
## buckets[i * N + j] = lots of block (i, j). Lots never leave their block, so a point query touches at most 4 lots.
var _buckets: Array = []

# Scratch buffers for road_point_near (one slot per candidate inner road; no allocation per call).
const NROADS := 2 * (N - 1)
var _r_f := PackedFloat32Array()      # fixed coordinate of the road (z for roads along x, x for roads along z)
var _r_axis := PackedByteArray()      # 0: road runs along x, 1: along z
var _r_lo1 := PackedFloat32Array()    # first feasible interval start
var _r_l1 := PackedFloat32Array()      # ... and its length
var _r_lo2 := PackedFloat32Array()
var _r_l2 := PackedFloat32Array()


func _init() -> void:
	_generate()
	_r_f.resize(NROADS)
	_r_axis.resize(NROADS)
	_r_lo1.resize(NROADS)
	_r_l1.resize(NROADS)
	_r_lo2.resize(NROADS)
	_r_l2.resize(NROADS)


# --- mulberry32, bit-exact with util.js --------------------------------------------------------------------------

class Mulberry extends RefCounted:
	var a := 0

	func _init(seed_value: int) -> void:
		a = seed_value & 0xFFFFFFFF

	static func imul(x: int, y: int) -> int:
		return (x * y) & 0xFFFFFFFF

	func next() -> float:
		a = (a + 0x6d2b79f5) & 0xFFFFFFFF
		var t := imul(a ^ (a >> 15), 1 | a)
		t = ((t + imul(t ^ (t >> 7), 61 | t)) ^ t) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


# --- generation --------------------------------------------------------------------------------------------------

func _generate() -> void:
	var rnd := Mulberry.new(SEED)
	_buckets.clear()
	for k in N * N:
		_buckets.append([] as Array[Lot])
	for i in N:
		for j in N:
			var bx := -HALF + (i + 0.5) * PITCH
			var bz := -HALF + (j + 0.5) * PITCH
			var central := 1.0 - minf(1.0, Vector2(bx, bz).length() / (HALF * 1.1))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var cx: float = bx + sx * LOT_OFFSET
					var cz: float = bz + sz * LOT_OFFSET
					if rnd.next() < 0.1:                                   # plaza
						plazas.append(Vector2(cx, cz))
						continue
					var w: float = FOOT[0 if rnd.next() < 0.5 else 1]
					var d: float = FOOT[0 if rnd.next() < 0.5 else 1]
					var hi := clampi(int(floor(rnd.next() * 2.0 + central * 3.4)), 0, 4)
					var tint := int(floor(rnd.next() * NTINTS))
					var neon := int(floor(rnd.next() * NNEON))
					var lot := Lot.new()
					lot.cx = cx
					lot.cz = cz
					lot.w = w
					lot.d = d
					lot.h = HEIGHTS[hi]
					lot.rect = Rect2(cx - w * 0.5, cz - d * 0.5, w, d)
					lot.tint = tint
					lot.neon = neon
					lot.block_i = i
					lot.block_j = j
					lots.append(lot)
					(_buckets[i * N + j] as Array).append(lot)


# --- grid helpers ------------------------------------------------------------------------------------------------

static func road_center(i: int) -> float:
	return -HALF + i * PITCH


## Signed offset from v to the nearest road centre line.
static func road_offset(v: float) -> float:
	return v - road_center(clampi(roundi((v + HALF) / PITCH), 0, N))


## True when (x, z) lies on the road network (within `margin` metres of the road edges), including the outer ring roads.
static func on_road(x: float, z: float, margin := 0.0) -> bool:
	var lim := HALF + ROAD * 0.5
	if absf(x) > lim or absf(z) > lim:
		return false
	var half := ROAD * 0.5 - margin
	return absf(road_offset(x)) <= half or absf(road_offset(z)) <= half


## The 49 inner junctions (y = 0), x-major.
static func make_intersections() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(1, N):
		for j in range(1, N):
			out.append(Vector3(road_center(i), 0.0, road_center(j)))
	return out


# --- queries -----------------------------------------------------------------------------------------------------

func block_lots(x: float, z: float) -> Array:
	var i := int(floor((x + HALF) / PITCH))
	var j := int(floor((z + HALF) / PITCH))
	if i < 0 or j < 0 or i >= N or j >= N:
		return []
	return _buckets[i * N + j]


func lot_at(x: float, z: float, margin := 0.0) -> Lot:
	for lot: Lot in block_lots(x, z):
		if lot.contains_xz(x, z, margin):
			return lot
	return null


## Footprint x building volume test: footprint x [0, height). `margin` grows the footprint in x/z.
func inside(p: Vector3, margin := 0.0) -> bool:
	if p.y < 0.0:
		return false
	var lot := lot_at(p.x, p.z, margin)
	return lot != null and p.y < lot.h


## Height of the building top under (x, z), 0 on roads / plazas.
func height_at(x: float, z: float) -> float:
	var lot := lot_at(x, z)
	return lot.h if lot != null else 0.0


## A uniformly random point on the road network (inside the lane band, never inside a building footprint).
func random_road_point() -> Vector3:
	var c := road_center(randi() % (N + 1))
	var u := randf_range(-1.0, 1.0) * (HALF - 12.0)
	var o := randf_range(-1.0, 1.0) * 7.0
	return Vector3(u, 0.0, c + o) if randf() < 0.5 else Vector3(c + o, 0.0, u)


## A random road position whose XZ distance from `center` lies in [rmin, rmax], or Vector3.INF when none exists.
## Exact: every inner road is intersected with the annulus, so it only fails when the ring misses all roads.
func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
	if rmax < rmin or rmax <= 0.0:
		return Vector3.INF
	# Three passes: a random lateral offset, then the centre lines, so thin rings still find a road.
	for pass_i in 3:
		var p := _road_point_pass(center, rmin, rmax, pass_i)
		if p != Vector3.INF:
			return p
	return Vector3.INF


func _road_point_pass(center: Vector3, rmin: float, rmax: float, pass_i: int) -> Vector3:
	var lim := HALF - 8.0
	var total := 0.0
	var n := 0
	for axis in 2:
		var cf := center.z if axis == 0 else center.x        # the centre's coordinate across the road
		var cs := center.x if axis == 0 else center.z        # ... and along it
		for k in range(1, N):
			var f := road_center(k) + (0.0 if pass_i > 0 else randf_range(-7.0, 7.0))
			var dz := f - cf
			var m_max := rmax * rmax - dz * dz
			var lo1 := 0.0
			var l1 := 0.0
			var lo2 := 0.0
			var l2 := 0.0
			if m_max > 0.0:
				# |s - cs| must lie in [a, b]: two intervals, clipped to the walkable extent
				var a := sqrt(maxf(0.0, rmin * rmin - dz * dz)) + 0.002
				var b := sqrt(m_max) - 0.002
				if b > a:
					lo1 = maxf(cs + a, -lim)
					l1 = maxf(0.0, minf(cs + b, lim) - lo1)
					lo2 = maxf(cs - b, -lim)
					l2 = maxf(0.0, minf(cs - a, lim) - lo2)
			_r_f[n] = f
			_r_axis[n] = axis
			_r_lo1[n] = lo1
			_r_l1[n] = l1
			_r_lo2[n] = lo2
			_r_l2[n] = l2
			total += l1 + l2
			n += 1
	if total <= 0.0:
		return Vector3.INF
	var pick := randf() * total
	var chosen := -1
	for idx in n:
		var sum := _r_l1[idx] + _r_l2[idx]
		if sum <= 0.0:
			continue
		chosen = idx
		if pick <= sum:
			break
		pick -= sum
	if chosen < 0:
		return Vector3.INF
	var c1 := _r_l1[chosen]
	var c2 := _r_l2[chosen]
	pick = minf(pick, c1 + c2)
	var s := _r_lo1[chosen] + pick if pick <= c1 else _r_lo2[chosen] + (pick - c1)
	return Vector3(s, 0.0, _r_f[chosen]) if _r_axis[chosen] == 0 else Vector3(_r_f[chosen], 0.0, s)
