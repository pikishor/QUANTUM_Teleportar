class_name TrafficField
extends RefCounted
## One registry of every vehicle hull in play (owner round 6: "cars go inside other cars"). The real cars of the VehicleManager, the near (MultiMesh) traffic, the road traffic of the outskirts,
## the bridge cars, the parked decor cars and the wrecks each write their hulls here (oriented boxes of the REAL sizes, a heading and a speed) and every system that places or steers a car asks
## the same question through the same functions: what is in front of me (`lead`), is this spot free (`clear`), is the junction box busy (`box_busy`), who overlaps whom (`pairs`, the audit).
## Storage is flat packed arrays (no allocation while playing) with a hashed cell grid rebuilt at most once per frame. A hull with `hl` <= 0 is dead. Everything is XZ (the street plane).
## Conventions: heading h (Node3D.rotation.y) gives forward (-sin h, -cos h) and right (cos h, -sin h); the forward vector is stored, so callers pass (fx, fz) directly.

const REAL := 0
const NEAR := 1
const PATH := 2
const BRIDGE := 3
const PARKED := 4
const WRECK := 5
const SRC_N := 6
const SRC_CAP: Array[int] = [72, 160, 140, 48, 420, 24]
const SRC_NAMES: Array[String] = ["real", "near", "path", "bridge", "parked", "wreck"]
const CELL := 20.0
const BUCKETS := 2048
const MAX_R := 7.0                       ## a hull longer than this (an aircraft, a ship) is not tracked: it does not drive on the street grid
const F_STATIC := 1                      ## flag: stands still on purpose (parked, wreck)
const F_AI := 2                          ## flag: follows a lane (traffic)
const F_CROSSING_OK := 4                 ## flag: a lane car whose turn is being driven (its heading changes)

static var _base := PackedInt32Array()
static var _n := PackedInt32Array()                ## high-water mark per source
static var _x := PackedFloat32Array()
static var _z := PackedFloat32Array()
static var _fx := PackedFloat32Array()
static var _fz := PackedFloat32Array()
static var _hl := PackedFloat32Array()
static var _hw := PackedFloat32Array()
static var _v := PackedFloat32Array()
static var _flag := PackedByteArray()
static var _head := PackedInt32Array()
static var _next := PackedInt32Array()
static var _total := 0
static var _stamp := -1
static var _dirty := true
static var _ready := false
static var _since := 0                              ## writes since the grid was built
static var _live := 0                               ## live hulls


static func _init_arrays() -> void:
	if _ready:
		return
	_ready = true
	_base.resize(SRC_N)
	_n.resize(SRC_N)
	var acc := 0
	for s in SRC_N:
		_base[s] = acc
		acc += SRC_CAP[s]
	_total = acc
	for a: PackedFloat32Array in [_x, _z, _fx, _fz, _hl, _hw, _v]:
		a.resize(_total)
	_flag.resize(_total)
	_next.resize(_total)
	_head.resize(BUCKETS)
	_head.fill(-1)


## Wipe everything (a new game, a test that wants a clean field).
static func reset() -> void:
	_init_arrays()
	for s in SRC_N:
		_n[s] = 0
	for i in _total:
		_hl[i] = 0.0
	_live = 0
	_dirty = true
	_stamp = -1


## Writes hull `i` of source `src`: centre (x, z), forward (fx, fz) (unit), half length / width, signed speed along the forward, flags.
static func put(src: int, i: int, x: float, z: float, fx: float, fz: float, hl: float, hw: float, v := 0.0, flags := 0) -> void:
	_init_arrays()
	if i < 0 or i >= SRC_CAP[src]:
		return
	var k := _base[src] + i
	if hl > MAX_R or not is_finite(x) or not is_finite(z):
		if _hl[k] > 0.0:
			_live -= 1
			_dirty = true
		_hl[k] = 0.0
		return
	if _hl[k] <= 0.0:                                     # a new hull: the grid must learn about it (a moved one stays in its cell until the next rebuild: cells are 20 m, a car moves a few cm a frame)
		_live += 1
		_dirty = true
	_x[k] = x
	_z[k] = z
	_fx[k] = fx
	_fz[k] = fz
	_hl[k] = hl
	_hw[k] = hw
	_v[k] = v
	_flag[k] = flags
	if i >= _n[src]:
		_n[src] = i + 1
	_since += 1


## Same, with a heading angle instead of a forward vector.
static func put_yaw(src: int, i: int, x: float, z: float, yaw: float, hl: float, hw: float, v := 0.0, flags := 0) -> void:
	put(src, i, x, z, -sin(yaw), -cos(yaw), hl, hw, v, flags)


static var _used := PackedByteArray()


## A permanent slot of source `src` for a long-lived owner (a pooled Vehicle): its hull is written at this index and the owner skips itself with it. -1 when the source is full.
static func alloc(src: int) -> int:
	_init_arrays()
	if _used.size() != _total:
		_used.resize(_total)
	for i in SRC_CAP[src]:
		if _used[_base[src] + i] == 0:
			_used[_base[src] + i] = 1
			_hl[_base[src] + i] = 0.0
			return i
	return -1


static func release(src: int, i: int) -> void:
	_init_arrays()
	if i >= 0 and i < SRC_CAP[src]:
		if _used.size() == _total:
			_used[_base[src] + i] = 0
		if _hl[_base[src] + i] > 0.0:
			_live -= 1
		_hl[_base[src] + i] = 0.0
		_dirty = true


static func remove(src: int, i: int) -> void:
	_init_arrays()
	if i >= 0 and i < SRC_CAP[src] and _hl[_base[src] + i] > 0.0:
		_hl[_base[src] + i] = 0.0
		_live -= 1
		_dirty = true


static func clear_source(src: int) -> void:
	_init_arrays()
	for i in _n[src]:
		if _hl[_base[src] + i] > 0.0:
			_live -= 1
		_hl[_base[src] + i] = 0.0
	_n[src] = 0
	_dirty = true


static func live_count(src := -1) -> int:
	_init_arrays()
	var c := 0
	for s in SRC_N:
		if src >= 0 and s != src:
			continue
		for i in _n[s]:
			if _hl[_base[s] + i] > 0.0:
				c += 1
	return c


static func _cell_hash(cx: int, cz: int) -> int:
	return ((cx * 73856093) ^ (cz * 19349663)) & (BUCKETS - 1)


static func _ensure() -> void:
	_init_arrays()
	var st := Engine.get_physics_frames() * 3 + Engine.get_process_frames() * 7
	if not _dirty and st == _stamp and _since <= _live + 8:
		return
	_stamp = st
	_dirty = false
	_since = 0
	_head.fill(-1)
	for s in SRC_N:
		var b := _base[s]
		for i in _n[s]:
			var k := b + i
			if _hl[k] <= 0.0:
				continue
			var h := _cell_hash(floori(_x[k] / CELL), floori(_z[k] / CELL))
			_next[k] = _head[h]
			_head[h] = k


# --- geometry --------------------------------------------------------------------------------------------------------------------------

## Penetration depth (m) of two oriented boxes, 0 when apart: the smallest overlap along the four hull axes. Boxes are (centre, forward, half length, half width).
static func obb_depth(ax: float, az: float, afx: float, afz: float, ahl: float, ahw: float, bx: float, bz: float, bfx: float, bfz: float, bhl: float, bhw: float) -> float:
	var dx := ax - bx
	var dz := az - bz
	var arx := -afz
	var arz := afx
	var brx := -bfz
	var brz := bfx
	var best := INF
	for t in 4:
		var ux: float
		var uz: float
		match t:
			0:
				ux = afx
				uz = afz
			1:
				ux = arx
				uz = arz
			2:
				ux = bfx
				uz = bfz
			_:
				ux = brx
				uz = brz
		var ra := ahl * absf(ux * afx + uz * afz) + ahw * absf(ux * arx + uz * arz)
		var rb := bhl * absf(ux * bfx + uz * bfz) + bhw * absf(ux * brx + uz * brz)
		var ov := ra + rb - absf(dx * ux + dz * uz)
		if ov <= 0.0:
			return 0.0
		if ov < best:
			best = ov
	return best


## The extent of a box along direction (ux, uz): the support function the corridor and gap tests use.
static func extent(hl: float, hw: float, bfx: float, bfz: float, ux: float, uz: float) -> float:
	return hl * absf(ux * bfx + uz * bfz) + hw * absf(ux * -bfz + uz * bfx)


# --- queries ---------------------------------------------------------------------------------------------------------------------------

## The nearest hull ahead of a car at (x, z) heading (fx, fz) with half size (hl, hw) inside its swept corridor (its width plus `pad` each side), up to `look` m beyond its bumper.
## Returns Vector3(gap, lead speed along my forward, source * 1000 + index) with gap INF when the road is clear. A hull already overlapping gets a negative gap (stop now).
static func lead(x: float, z: float, fx: float, fz: float, hl: float, hw: float, look: float, skip_src := -1, skip_i := -1, pad := 0.3) -> Vector3:
	_ensure()
	var rx := -fz
	var rz := fx
	var best := INF
	var best_v := 0.0
	var best_id := -1.0
	var cx := x + fx * (look * 0.5)
	var cz := z + fz * (look * 0.5)
	var half_x := absf(fx) * (look * 0.5 + hl + 1.0) + absf(rx) * (hw + 0.5) + MAX_R             # the box round the swept corridor (thin along a road, not a square)
	var half_z := absf(fz) * (look * 0.5 + hl + 1.0) + absf(rz) * (hw + 0.5) + MAX_R
	var c0x := floori((cx - half_x) / CELL)
	var c1x := floori((cx + half_x) / CELL)
	var c0z := floori((cz - half_z) / CELL)
	var c1z := floori((cz + half_z) / CELL)
	var skip_k := -1
	if skip_src >= 0 and skip_i >= 0:
		skip_k = _base[skip_src] + skip_i
	for gx in range(c0x, c1x + 1):
		for gz in range(c0z, c1z + 1):
			var k := _head[_cell_hash(gx, gz)]
			while k >= 0:
				var nk := _next[k]
				if k != skip_k:
					var qx := _x[k] - x
					var qz := _z[k] - z
					var ahead := qx * fx + qz * fz
					if ahead > 0.0 and ahead < look + hl + MAX_R:
						var lat := qx * rx + qz * rz
						if absf(lat) < hw + MAX_R + 0.5:
							var bhl := _hl[k]
							var bhw := _hw[k]
							var bfx := _fx[k]
							var bfz := _fz[k]
							var cf := bfx * fx + bfz * fz                      # inlined `extent`: this runs for every neighbour of every car every look
							var sf := -bfz * fx + bfx * fz
							var cl := bfx * rx + bfz * rz
							var sl := -bfz * rx + bfx * rz
							var e_f := bhl * absf(cf) + bhw * absf(sf)
							var e_l := bhl * absf(cl) + bhw * absf(sl)
							var pd := pad if (_flag[k] & F_STATIC) == 0 else minf(pad, -0.25)                 # a parked car beside the lane is passed with a quarter metre to spare, not waited for
							if absf(lat) < hw + e_l + pd:
								var gap := ahead - hl - e_f
								if gap < best and gap < look:
									best = gap
									best_v = _v[k] * cf
									best_id = float(k)
				k = nk
	if best == INF:
		return Vector3(INF, 0.0, -1.0)
	return Vector3(best, best_v, best_id)


## True when no hull (other than the skipped one) overlaps the box at (x, z) heading (fx, fz) of half size (hl, hw) grown by `margin`.
static func clear(x: float, z: float, fx: float, fz: float, hl: float, hw: float, margin := 0.5, skip_src := -1, skip_i := -1, flags_skip := 0) -> bool:
	return first_overlap(x, z, fx, fz, hl, hw, margin, skip_src, skip_i, flags_skip) < 0


## The index (source * 1000 + i) of the first hull overlapping that box, or -1.
static func first_overlap(x: float, z: float, fx: float, fz: float, hl: float, hw: float, margin := 0.5, skip_src := -1, skip_i := -1, flags_skip := 0) -> int:
	_ensure()
	var rad := hl + margin + MAX_R + 1.0
	var skip_k := -1
	if skip_src >= 0 and skip_i >= 0:
		skip_k = _base[skip_src] + skip_i
	for gx in range(floori((x - rad) / CELL), floori((x + rad) / CELL) + 1):
		for gz in range(floori((z - rad) / CELL), floori((z + rad) / CELL) + 1):
			var k := _head[_cell_hash(gx, gz)]
			while k >= 0:
				var nk := _next[k]
				if k != skip_k and (flags_skip == 0 or (_flag[k] & flags_skip) == 0):
					if absf(_x[k] - x) < rad and absf(_z[k] - z) < rad:
						if obb_depth(x, z, fx, fz, hl + margin, hw + margin, _x[k], _z[k], _fx[k], _fz[k], _hl[k], _hw[k]) > 0.0:
							return source_of(k) * 1000 + (k - _base[source_of(k)])
				k = nk
	return -1


static func source_of(k: int) -> int:
	for s in range(SRC_N - 1, -1, -1):
		if k >= _base[s]:
			return s
	return 0


## True when a hull that is NOT travelling along (fx, fz) (it crosses, or it stands across the box) has its centre inside the square box of half size `half` at (cx, cz): the junction is busy.
static func box_busy(cx: float, cz: float, half: float, fx: float, fz: float, skip_src := -1, skip_i := -1) -> bool:
	_ensure()
	var skip_k := -1
	if skip_src >= 0 and skip_i >= 0:
		skip_k = _base[skip_src] + skip_i
	var rad := half + MAX_R
	for gx in range(floori((cx - rad) / CELL), floori((cx + rad) / CELL) + 1):
		for gz in range(floori((cz - rad) / CELL), floori((cz + rad) / CELL) + 1):
			var k := _head[_cell_hash(gx, gz)]
			while k >= 0:
				var nk := _next[k]
				if k != skip_k and absf(_x[k] - cx) < half and absf(_z[k] - cz) < half:
					if absf(_fx[k] * fx + _fz[k] * fz) < 0.75:
						return true
				k = nk
	return false


## Every pair of live hulls that overlap by more than `min_depth`: appends [src_a, i_a, src_b, i_b, depth] arrays to `out` (the audit and the resolver). Static hulls of the same
## source are not tested against each other (two parked cars are placed by the same generator).
static func pairs(min_depth: float, out: Array) -> void:
	_ensure()
	for s in SRC_N:
		var b := _base[s]
		for i in _n[s]:
			var k := b + i
			if _hl[k] <= 0.0:
				continue
			var rad := _hl[k] + MAX_R
			for gx in range(floori((_x[k] - rad) / CELL), floori((_x[k] + rad) / CELL) + 1):
				for gz in range(floori((_z[k] - rad) / CELL), floori((_z[k] + rad) / CELL) + 1):
					var j := _head[_cell_hash(gx, gz)]
					while j >= 0:
						var nj := _next[j]
						if j > k and absf(_x[j] - _x[k]) < rad + 0.5 and absf(_z[j] - _z[k]) < rad + 0.5:
							var d := obb_depth(_x[k], _z[k], _fx[k], _fz[k], _hl[k], _hw[k], _x[j], _z[j], _fx[j], _fz[j], _hl[j], _hw[j])
							if d > min_depth:
								var sj := source_of(j)
								if not (sj == s and (_flag[k] & F_STATIC) != 0 and (_flag[j] & F_STATIC) != 0):
									out.append([s, i, sj, j - _base[sj], d])
						j = nj


## (live hulls, hulls faster than `min_v` m/s) of one source: the flow the audit and the density test report.
static func flow(src: int, min_v := 1.0) -> Vector2i:
	_init_arrays()
	var n := 0
	var m := 0
	for i in _n[src]:
		var k := _base[src] + i
		if _hl[k] > 0.0:
			n += 1
			if absf(_v[k]) > min_v:
				m += 1
	return Vector2i(n, m)


## Hull fields of one entry (tests and the audit print them).
static func describe(src: int, i: int) -> Dictionary:
	_init_arrays()
	var k := _base[src] + i
	return {"src": SRC_NAMES[src], "i": i, "x": _x[k], "z": _z[k], "fx": _fx[k], "fz": _fz[k], "hl": _hl[k], "hw": _hw[k], "v": _v[k], "flag": _flag[k]}


## The hull a `lead` result (its z) points at.
static func describe_id(k: float) -> Dictionary:
	if k < 0.0:
		return {}
	var s := source_of(int(k))
	return describe(s, int(k) - _base[s])


## Nearest live hull centre within `r` of (x, z) that is not skipped: its index (source * 1000 + i) or -1.
static func nearest(x: float, z: float, r: float, skip_src := -1, skip_i := -1) -> int:
	_ensure()
	var best := r * r
	var out := -1
	var skip_k := -1
	if skip_src >= 0 and skip_i >= 0:
		skip_k = _base[skip_src] + skip_i
	for gx in range(floori((x - r) / CELL), floori((x + r) / CELL) + 1):
		for gz in range(floori((z - r) / CELL), floori((z + r) / CELL) + 1):
			var k := _head[_cell_hash(gx, gz)]
			while k >= 0:
				var nk := _next[k]
				if k != skip_k:
					var d2 := (_x[k] - x) * (_x[k] - x) + (_z[k] - z) * (_z[k] - z)
					if d2 < best:
						best = d2
						var s := source_of(k)
						out = s * 1000 + (k - _base[s])
				k = nk
	return out


## A bare street for a test (or a photo): the near traffic, the road traffic and the parked decor cars are switched off and emptied; the real cars of the VehicleManager are the test's own business.
static func bare_street() -> void:
	if NearTraffic.instance != null:
		NearTraffic.instance.enabled = false
		NearTraffic.instance.count = 0
		NearTraffic.instance.reset()
	if RoadTraffic.instance != null:
		RoadTraffic.instance.enabled = false
		RoadTraffic.instance.reset()
	if ParkedCars.instance != null:
		ParkedCars.instance.enabled = false
		ParkedCars.instance.reset()
