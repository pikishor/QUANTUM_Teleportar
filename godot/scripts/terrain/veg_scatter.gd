class_name VegScatter
extends RefCounted
## Where the plants and rocks of the outskirts stand: a pure, deterministic function of the cell, no state, safe on worker threads once `TerrainHeight.warm()` has run on the main thread.
##
## The world is cut into CELL (32 m) squares; a LAYER decides what is scattered (trees, shrubs, grass, rocks), a jittered grid inside the cell gives the candidate spots, and the biome decides
## whether a candidate becomes a plant: forests of pines and broadleaf trees in the north-west and west hills and the foothills, pines and dead trunks climbing the mountains up to a tree line
## (about 215 m, ragged), a few lone trees and shrubs on the plains, scrub and dead trees in the desert, rocks everywhere (boulders and cliffs on steep or high ground). Nothing grows on
## water, on the beach, on a road or inside a site pad. Clumps and clearings come from a low-frequency noise so a forest is not a lawn.
## Result: PackedFloat32Array, STRIDE floats per plant: x, y, z, yaw, scale, species, random 0..1, variant (0, 1, 2).

const CELL := 32.0
const STRIDE := 8
const T_TREES := 0
const T_SHRUBS := 1
const T_GRASS := 2
const T_ROCKS := 3
const PINE := 0
const BROAD := 1
const DEAD := 2
const BUSH := 3
const FERN := 4
const GRASS := 5
const TUFT := 6
const ROCK := 7
const FIR := 8                                       ## wave 112: the nine landscape tree species (scripts/landscape/land_kit.gd); BROAD is the oak
const BIRCH := 9
const PALM := 10
const ALIEN := 11
const POPLAR := 12
const ACACIA := 13
const FLOWER := 14                                   ## variants: 0 daisies, 1 poppies, 2 lavender, 3 clover
const REED := 15
const OAK := 1
const T_LINES := 4                                   ## roadside avenues (poplars, palms) on the approaches of the city, laid out along the road samples
const T_REEDS := 5                                   ## reeds on the banks of rivers and lakes
const LAYERS := 6
const TREE_LINE := 215.0
const SPACING := [6.0, 4.6, 1.6, 11.0, 6.0, 2.4]     ## jitter grid spacing per layer (metres)
const LINE_OFFSET := 16.2                            ## distance of an avenue from the road centre line: just outside the 15 m bench
const LINE_RANGE := 900.0                            ## avenues only within this distance of the city plateau

static var _clump: FastNoiseLite
static var _patch: FastNoiseLite
static var _grove: FastNoiseLite
static var _alien: FastNoiseLite
static var _lines := {}                               ## cell key -> PackedFloat32Array of avenue trees (built once in warm())
static var _ready_flag := false


static func warm() -> void:
	if _ready_flag:
		return
	TerrainHeight.warm()
	_clump = FastNoiseLite.new()
	_clump.seed = 1207
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_clump.frequency = 0.0085
	_clump.fractal_type = FastNoiseLite.FRACTAL_FBM
	_clump.fractal_octaves = 2
	_patch = FastNoiseLite.new()
	_patch.seed = 6151
	_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_patch.frequency = 0.0031
	_grove = FastNoiseLite.new()
	_grove.seed = 3719
	_grove.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_grove.frequency = 0.0105
	_alien = FastNoiseLite.new()
	_alien.seed = 8123
	_alien.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_alien.frequency = 0.0021
	_alien.fractal_type = FastNoiseLite.FRACTAL_FBM
	_alien.fractal_octaves = 2
	_ready_flag = true
	_build_lines()


static func _hash(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 0x85ebca6b
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _r01(h: int) -> float:
	return float(h & 0xffff) / 65535.0


## An independent 0..1 number for (hash, salt): shifting one hash for every use ran out of bits.
static func _rs(h: int, salt: int) -> float:
	return _r01(_hash(h, salt, 977))


## What grows at (x, z) for the layer: 0..1 density (before the clump noise) and nothing else is computed here. `h` is the ground height there.
static func density(layer: int, x: float, z: float, h: float, mw: float, fw: float, dw: float) -> float:
	var tl := TREE_LINE + _patch.get_noise_2d(x, z) * 28.0
	var clump := smoothstep(-0.28, 0.32, _clump.get_noise_2d(x, z))
	var d := 0.0
	match layer:
		T_TREES:
			if h > tl:
				return 0.0
			var desert := dw * (1.0 - fw)
			var plains := 0.07 * smoothstep(0.15, 0.7, _clump.get_noise_2d(x * 1.7 + 311.0, z * 1.7)) + 0.10 * smoothstep(0.25, 0.6, _grove.get_noise_2d(x, z)) * (1.0 - desert)
			var savanna := 0.012 + 0.05 * smoothstep(-0.2, 0.5, _clump.get_noise_2d(x * 0.7 + 71.0, z * 0.7 - 33.0))
			var forest := lerpf(lerpf(plains, savanna, desert), 0.9 * clump, fw)
			var alpine := 0.62 * clump * mw * smoothstep(40.0, 110.0, h) * (1.0 - smoothstep(tl - 60.0, tl, h) * 0.9)
			d = maxf(forest, alpine)
			var al := alien_weight(x, z, fw, desert, mw)
			if al > 0.0:
				d = maxf(d, 0.36 * al)
			var sd := TerrainHeight.coast_distance(x, z) - TerrainHeight.city_distance(x, z)
			if sd < 760.0 and h < 26.0:
				d = maxf(d, 0.30 * (1.0 - smoothstep(340.0, 760.0, sd)) * (1.0 - smoothstep(14.0, 26.0, h)) * smoothstep(-0.35, 0.3, _clump.get_noise_2d(x * 1.3, z * 1.3 + 91.0)))
			if desert > 0.25:
				d = maxf(d, 0.34 * (1.0 - smoothstep(10.0, 70.0, WaterLayout.inland_distance(x, z, 72.0))))
		T_SHRUBS:
			if h > tl + 25.0:
				return 0.0
			d = lerpf(lerpf(0.14, 0.05, dw * (1.0 - fw)), 0.45 * clump + 0.08, fw) * (1.0 - 0.5 * mw)
		T_GRASS:
			if h > tl:
				return 0.0
			d = lerpf(lerpf(0.5, 0.3, dw * (1.0 - fw)), 0.55, fw) * (1.0 - 0.6 * smoothstep(100.0, tl, h)) * (0.4 + 0.6 * clump)
		T_ROCKS:
			d = 0.09 + 0.3 * smoothstep(60.0, 220.0, h) * mw + 0.1 * dw
	return d


## Alien patches: blobs of strange forest in open country (never inside a real forest), strongest in the desert and on the high plateaus.
static func alien_weight(x: float, z: float, fw: float, desert: float, mw: float) -> float:
	var n := smoothstep(0.50, 0.70, _alien.get_noise_2d(x, z))
	if n <= 0.0:
		return 0.0
	return n * (1.0 - fw) * (0.35 + 0.65 * clampf(desert + mw * 0.3, 0.0, 1.0))


## Which tree grows at (x, z): Vector2(species, scale). `r` = four independent random numbers of the spot (0..1).
static func tree_species(x: float, z: float, h: float, mw: float, fw: float, dw: float, r: Vector4) -> Vector2:
	var desert := dw * (1.0 - fw)
	var al := alien_weight(x, z, fw, desert, mw)
	if r.x < al * 0.9:
		return Vector2(ALIEN, 0.85 + r.w * 0.55)
	var sd := TerrainHeight.coast_distance(x, z) - TerrainHeight.city_distance(x, z)
	var shore := (1.0 - smoothstep(340.0, 760.0, sd)) * (1.0 - smoothstep(14.0, 26.0, h))
	var oasis := 0.0
	if desert > 0.25:
		oasis = (1.0 - smoothstep(10.0, 70.0, WaterLayout.inland_distance(x, z, 72.0))) * smoothstep(0.25, 0.6, desert)
	if r.y < maxf(shore * 0.8, oasis * 0.92):
		return Vector2(PALM, 0.85 + r.w * 0.4)
	var dead_p := 0.18 * smoothstep(0.35, 0.85, desert) + 0.2 * smoothstep(TREE_LINE - 60.0, TREE_LINE, h) + 0.025
	if r.z < dead_p:
		return Vector2(DEAD, 0.8 + r.w * 0.55)
	var lowl := 1.0 - smoothstep(60.0, 130.0, h)
	var mid := smoothstep(70.0, 130.0, h) * (1.0 - smoothstep(170.0, 215.0, h))
	var high := smoothstep(110.0, 190.0, h)
	var grove := smoothstep(0.05, 0.45, _grove.get_noise_2d(x, z))
	var riv := 0.0
	if lowl > 0.3 and desert < 0.7:
		riv = 1.0 - smoothstep(14.0, 110.0, WaterLayout.inland_distance(x, z, 120.0))
	var w_oak := (0.5 + 0.3 * fw) * lowl * (1.0 - 0.8 * desert) * (1.0 - 0.5 * mw) * (1.0 - 0.7 * grove)
	var w_birch := (0.07 + 0.6 * grove + 0.45 * riv) * (0.4 + 0.6 * lowl) * (1.0 - desert) * (1.0 - 0.5 * high)
	var w_pine := (0.22 + 0.5 * mid) * (1.0 - 0.85 * desert) * (0.5 + 0.5 * maxf(fw, mw))
	var w_fir := (0.06 + 1.0 * high) * (0.25 + 0.75 * maxf(fw, mw)) * (1.0 - desert)
	var w_acacia := desert * 1.6
	var tot := w_oak + w_birch + w_pine + w_fir + w_acacia
	if tot <= 0.001:
		return Vector2(OAK, 1.0 + r.w * 0.3)
	var pick := r.w * tot
	var alt_k := 1.0 - 0.3 * smoothstep(120.0, TREE_LINE, h)
	var rr := fposmod(r.w * 7.31 + r.x * 3.7, 1.0)
	if pick < w_oak:
		return Vector2(OAK, (0.85 + rr * 0.55) * alt_k)
	pick -= w_oak
	if pick < w_birch:
		return Vector2(BIRCH, (0.85 + rr * 0.45) * alt_k)
	pick -= w_birch
	if pick < w_pine:
		return Vector2(PINE, (0.85 + rr * 0.5) * alt_k)
	pick -= w_pine
	if pick < w_fir:
		return Vector2(FIR, (0.8 + rr * 0.6) * alt_k)
	return Vector2(ACACIA, 0.85 + rr * 0.5)


## Avenues (poplars; palms on the warm coast and in the dry south and east) along the highways on the approaches of the city, one tree per road sample and side, built once.
static func _build_lines() -> void:
	_lines.clear()
	for r: Dictionary in TerrainRoads.roads():
		if String(r["kind"]) != "highway" or String(r["name"]) == "HARBOUR ROAD":
			continue
		var pos: PackedVector2Array = r["pos"]
		for i in range(2, pos.size() - 2):
			var a := pos[i]
			var cdist := TerrainHeight.city_distance(a.x, a.y)
			if cdist > LINE_RANGE or cdist < 12.0:
				continue
			var tan := (pos[i + 1] - pos[i - 1]).normalized()
			var nrm := Vector2(-tan.y, tan.x)
			for side: float in [-1.0, 1.0]:
				var hh := _hash(i * 7 + (1 if side > 0.0 else 0), int(a.x * 0.37), int(a.y * 0.37))
				if _rs(hh, 21) < 0.12:
					continue                                                   # a gap now and then: an avenue is never perfect
				var along := (_rs(hh, 22) - 0.5) * 3.2
				var off := LINE_OFFSET + (_rs(hh, 23) - 0.5) * 1.6
				var q: Vector2 = a + tan * along + nrm * off * side
				var h := TerrainHeight.height_at(q.x, q.y)
				if h < TerrainHeight.SEA_LEVEL + 2.5 or TerrainHeight.water_level_for(q.x, q.y, h) != TerrainHeight.NO_WATER:
					continue
				if TerrainRoads.in_span(q.x, q.y) or OutskirtsSites.inside(q.x, q.y, 6.0) >= 0 or Airport.inside(q.x, q.y, 10.0):
					continue
				var fwq := TerrainBase.forest_weight(q.x, q.y)
				if TerrainHeight.slope_at(q.x, q.y) > 0.45 or fwq > 0.7:
					continue
				var sd := TerrainHeight.coast_distance(q.x, q.y) - TerrainHeight.city_distance(q.x, q.y)
				var dry := TerrainBase.desert_weight(q.x, q.y) * (1.0 - fwq)
				var sp := POPLAR
				if sd < 900.0 or dry > 0.55:
					sp = PALM
				var scale := 0.92 + _rs(hh, 24) * 0.28
				var key := _cell_key(int(floor(q.x / CELL)), int(floor(q.y / CELL)))
				var arr: PackedFloat32Array = _lines.get(key, PackedFloat32Array())
				arr.append_array(PackedFloat32Array([q.x, h - 0.05, q.y, _rs(hh, 25) * TAU, scale, float(sp), _rs(hh, 26), 0.0]))
				_lines[key] = arr


static func _cell_key(ci: int, cj: int) -> int:
	return ((ci + 4096) << 20) | (cj + 4096)


## The plants of one cell of one layer.
static func cell(layer: int, ci: int, cj: int) -> PackedFloat32Array:
	warm()
	var out := PackedFloat32Array()
	var x0 := float(ci) * CELL
	var z0 := float(cj) * CELL
	if TerrainHeight.city_distance(x0 + CELL * 0.5, z0 + CELL * 0.5) <= 0.0 and TerrainHeight.city_distance(x0, z0) <= 0.0 and TerrainHeight.city_distance(x0 + CELL, z0 + CELL) <= 0.0:
		return out                                                       # wholly inside the city plateau
	if absf(x0) > TerrainHeight.WORLD_HALF or absf(z0) > TerrainHeight.WORLD_HALF:
		return out
	if layer == T_LINES:
		return _lines.get(_cell_key(ci, cj), out)
	var sp: float = SPACING[layer]
	var n := int(ceil(CELL / sp))
	var base := _hash(ci, cj, layer + 17)
	for gj in n:
		for gi in n:
			var hh := _hash(base, gi, gj)
			var x := x0 + (float(gi) + 0.15 + 0.7 * _rs(hh, 1)) * sp
			var z := z0 + (float(gj) + 0.15 + 0.7 * _rs(hh, 2)) * sp
			var roll := _rs(hh, 3)
			if TerrainHeight.city_distance(x, z) < 8.0:
				continue
			var h := TerrainHeight.height_at(x, z)
			if h < TerrainHeight.SEA_LEVEL + 3.6:
				continue                                                  # beach and sea
			var mw := TerrainHeight.mountain_weight(x, z)
			var fw := TerrainBase.forest_weight(x, z)
			var dw := TerrainBase.desert_weight(x, z)
			var d := density(layer, x, z, h, mw, fw, dw)
			if layer == T_REEDS:
				if roll >= 0.62 or WaterLayout.inland_distance(x, z, 16.0) > 6.0:
					continue
				var wl := TerrainHeight.water_level_for(x, z, h)
				if wl != TerrainHeight.NO_WATER and wl - h > 0.55:
					continue
				out.append_array(PackedFloat32Array([x, h - 0.05, z, _rs(hh, 5) * TAU, 0.8 + _rs(hh, 4) * 0.7, float(REED), _rs(hh, 4), 0.0]))
				continue
			if roll >= d:
				continue
			if TerrainHeight.water_level_for(x, z, h) != TerrainHeight.NO_WATER:
				continue
			var sl := TerrainHeight.slope_at(x, z)
			var rnd := _rs(hh, 4)
			var yaw := _rs(hh, 5) * TAU
			var species := 0
			var scale := 1.0
			var variant := int(rnd * 3.0) % 3
			var sink := 0.0
			match layer:
				T_TREES:
					if sl > 0.85:
						continue
					var ts := tree_species(x, z, h, mw, fw, dw, Vector4(_rs(hh, 6), _rs(hh, 7), _rs(hh, 8), rnd))
					species = int(ts.x)
					scale = ts.y
					sink = 0.12 + 0.7 * clampf(sl, 0.0, 1.0)
				T_SHRUBS:
					if sl > 1.0:
						continue
					species = FERN if (fw > 0.45 and _rs(hh, 8) < 0.5) else BUSH
					scale = (0.55 + rnd * 0.5) * (1.25 if species == BUSH else 0.85)
				T_GRASS:
					if sl > 0.9:
						continue
					species = TUFT if (dw * (1.0 - fw) > 0.4 or h > 150.0) else GRASS
					scale = 0.62 + rnd * 0.55
					if dw * (1.0 - fw) < 0.5 and h < 130.0:
						var fl := _patch.get_noise_2d(x * 3.1 + 17.0, z * 3.1 - 5.0)
						if fl > 0.38 and _rs(hh, 11) < 0.7:
							species = FLOWER
							variant = int(_rs(hh, 12) * 4.0) % 4
							scale = 0.7 + rnd * 0.5
				T_ROCKS:
					species = ROCK
					var big := smoothstep(0.45, 1.1, sl) + 0.35 * smoothstep(110.0, 260.0, h) * mw
					scale = minf((0.55 + rnd * 0.9) * (1.0 + big * (1.0 + 1.6 * _rs(hh, 9))), 4.6)
					sink = scale * (0.26 + 0.9 * clampf(sl, 0.0, 1.2))                # dig into a slope: the coarse terrain mesh is a few metres off the true height under a big rock
			if OutskirtsSites.inside(x, z, 7.0) >= 0 or Airport.inside(x, z, 10.0):
				continue
			var rd := TerrainRoads.nearest(x, z)
			if int(rd[1]) >= 0:
				# a road cut is a sharp edge the coarse terrain mesh cannot follow: boulders keep clear of the whole bench, trees and shrubs of the carriageway and a margin
				var need := 5.0
				if layer == T_TREES:
					need = 13.0
				elif layer == T_SHRUBS:
					need = 9.0
				elif species == ROCK:
					need = 28.0 if (scale > 1.5 or sl > 0.4) else 9.0
				if float(rd[0]) < need:
					continue
			out.append_array(PackedFloat32Array([x, h - sink, z, yaw, scale, float(species), rnd, float(variant)]))
	return out
