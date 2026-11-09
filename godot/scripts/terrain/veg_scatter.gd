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
const TREE_LINE := 215.0
const SPACING := [6.0, 4.6, 3.2, 11.0]               ## jitter grid spacing per layer (metres)

static var _clump: FastNoiseLite
static var _patch: FastNoiseLite
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
	_ready_flag = true


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
			var plains := 0.07 * smoothstep(0.15, 0.7, _clump.get_noise_2d(x * 1.7 + 311.0, z * 1.7))
			var forest := lerpf(lerpf(plains, 0.012 * clump, dw * (1.0 - fw)), 0.9 * clump, fw)
			var alpine := 0.62 * clump * mw * smoothstep(40.0, 110.0, h) * (1.0 - smoothstep(tl - 60.0, tl, h) * 0.9)
			d = maxf(forest, alpine)
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
					var pp := clampf(0.3 + 0.7 * smoothstep(30.0, 160.0, h) + 0.25 * mw + 0.35 * fw * smoothstep(-1.0, 1.0, _clump.get_noise_2d(x * 0.5, z * 0.5)), 0.0, 0.97)
					var dead_p := 0.7 * smoothstep(0.35, 0.85, dw * (1.0 - fw)) + 0.18 * smoothstep(TREE_LINE - 60.0, TREE_LINE, h)
					var pick := _rs(hh, 6)
					if pick < dead_p:
						species = DEAD
						scale = 0.75 + rnd * 0.55
					elif _rs(hh, 7) < pp:
						species = PINE
						scale = (1.5 + rnd * 1.1) * (1.0 - 0.3 * smoothstep(120.0, TREE_LINE, h))
					else:
						species = BROAD
						scale = 1.05 + rnd * 0.65
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
					scale = 0.28 + rnd * 0.3
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
