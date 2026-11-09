class_name PathFollow
extends RefCounted
## A polyline a scripted vehicle follows (WorldSteps pursuit: the mountain-road chase by 4x4, the river chase by boat). Pure maths, no scene tree except `drive`, which writes the
## stick of a `Vehicle` (scripted = true): it steers at a point `look` metres ahead on the line, slows for bends and can be told to hold back.
##   s                      metres travelled along the line (only grows: the nearest point is searched ahead of the last one, so a hairpin never snaps to the road above or below it)
##   advance(pos)           project the vehicle's position onto the line
##   point_at(s) / dir_at   the line at a distance
##   drive(v, want, dt)     thr / steer for the vehicle: returns Vector2(thr, steer) and writes them to v.script_thr / v.script_steer
## Steering convention (Vehicle.step_drive): steer +1 turns right; heading grows when the vehicle turns left; forward = (-sin h, -cos h).

const SEARCH := 40                       ## polyline points looked at ahead of the last index per advance
const LOOK_MIN := 9.0
const LOOK_TIME := 0.55                  ## seconds of travel the steering looks ahead

var pts := PackedVector3Array()
var cum := PackedFloat32Array()
var total := 0.0
var s := 0.0
var _i := 0


func _init(points: PackedVector3Array = PackedVector3Array()) -> void:
	set_points(points)


func set_points(points: PackedVector3Array) -> void:
	pts = points
	cum = PackedFloat32Array()
	total = 0.0
	s = 0.0
	_i = 0
	for i in pts.size():
		if i > 0:
			total += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		cum.append(total)


func is_valid() -> bool:
	return pts.size() >= 2 and total > 1.0


## The point at distance `d` metres along the line (clamped to its ends), with the height of the line there.
func point_at(d: float) -> Vector3:
	if pts.is_empty():
		return Vector3.ZERO
	if d <= 0.0:
		return pts[0]
	if d >= total:
		return pts[pts.size() - 1]
	var lo := 0
	var hi := pts.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.0001)
	return pts[lo].lerp(pts[hi], (d - cum[lo]) / seg)


## Unit direction (x, z) of the line at distance `d`.
func dir_at(d: float) -> Vector3:
	var a := point_at(d - 2.0)
	var b := point_at(d + 2.0)
	var v := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return v.normalized() if v.length() > 0.001 else Vector3(0.0, 0.0, -1.0)


## Moves `s` to the point of the line nearest to `pos`, looking only forward from the last index (and a few points back).
func advance(pos: Vector3) -> float:
	if not is_valid():
		return s
	var best := INF
	var bi := _i
	var lo := maxi(_i - 3, 0)
	var hi := mini(_i + SEARCH, pts.size() - 1)
	for i in range(lo, hi + 1):
		var d := Vector2(pts[i].x - pos.x, pts[i].z - pos.z).length_squared()
		if d < best:
			best = d
			bi = i
	_i = bi
	var ds := cum[bi]
	# refine on the segment ahead of the nearest point
	if bi + 1 < pts.size():
		var a := pts[bi]
		var b := pts[bi + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var l2 := maxf(ab.length_squared(), 0.0001)
		var t := clampf((Vector2(pos.x - a.x, pos.z - a.z)).dot(ab) / l2, 0.0, 1.0)
		ds = cum[bi] + t * sqrt(l2)
	s = maxf(s, ds)
	return s


## Metres between `pos` and the end of the line.
func remaining() -> float:
	return maxf(total - s, 0.0)


## How sharply the line bends in the next `ahead` metres, in radians (0 = straight).
func bend_ahead(from_s: float, ahead: float) -> float:
	var a := dir_at(from_s)
	var b := dir_at(from_s + ahead)
	return absf(wrapf(atan2(-b.x, -b.z) - atan2(-a.x, -a.z), -PI, PI))


## Writes the stick of `v` (a scripted vehicle): follow the line at about `want` m/s. Returns Vector2(thr, steer).
func drive(v: Vehicle, want: float, _dt: float) -> Vector2:
	var p := v.global_position
	advance(p)
	var look := maxf(LOOK_MIN, absf(v.speed) * LOOK_TIME)
	var tgt := point_at(s + look)
	var dx := tgt.x - p.x
	var dz := tgt.z - p.z
	var hd := atan2(-dx, -dz)
	var err := wrapf(hd - v.heading, -PI, PI)
	var steer := clampf(-err * 1.7, -1.0, 1.0)
	var bend := bend_ahead(s, maxf(look * 2.2, 22.0))
	var cap := lerpf(want, minf(want, 8.5), clampf(bend / 1.1, 0.0, 1.0))      # slow into a hairpin
	if absf(err) > 0.9:
		cap = minf(cap, 6.0)
	var thr := clampf((cap - v.speed) * 0.45, -0.6, 1.0)
	if remaining() < 4.0:
		thr = -0.4 if v.speed > 1.0 else 0.0
	v.script_thr = thr
	v.script_steer = steer
	return Vector2(thr, steer)
