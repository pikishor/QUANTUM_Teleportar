class_name TerrainBase
extends RefCounted
## The LAND of the big world before water and roads are cut into it (TerrainHeight.base_height delegates here; WaterLayout carves rivers and lakes into the result,
## TerrainRoads cuts the road benches on top of that: TerrainHeight.height_at is the finished surface everybody uses).
##
## Hand-set masks, deterministic noise (fixed seeds, no randomness at run time):
##  - the CITY is the flat plateau at y = 0 (TerrainHeight.CITY_HALF), foothills start right outside it;
##  - the MOUNTAIN RANGE fills the north and the east (`TerrainHeight.mountain_weight`): a domain-warped ridged multifractal up to about PEAK metres, crags on top,
##    snow above SNOW_LINE (the terrain shader), foothills first, then the high country;
##  - FOREST HILLS in the north-west and west: rolling hills up to about 90 m, in the foothills of the north too;
##  - DRY PLAINS / DESERT in the east and the south: low dunes and flat mesas between the city and the mountains;
##  - the COAST on the south-west (`TerrainHeight.coast_distance`): the land falls to a beach and then the sea floor.
## Everything is a pure function of (x, z): safe to call from worker threads once `warm()` has run on the main thread.

const PEAK := 500.0                      ## height scale of the mountain ridges (metres)
const SNOW_LINE := 250.0                 ## metres above which the shader paints snow (with noise); also used by `biome_at`
const FOOTHILL_START := 380.0            ## metres from the city plateau where the land starts to roll
const MOUNT_START := 520.0               ## ... where the mountains start to rise
const MOUNT_FULL := 1500.0

static var _hills: FastNoiseLite
static var _ridge: FastNoiseLite
static var _warp: FastNoiseLite
static var _crag: FastNoiseLite
static var _dune: FastNoiseLite
static var _mesa: FastNoiseLite
static var _patch: FastNoiseLite
static var _bdune: FastNoiseLite
static var _built := false


static func warm() -> void:
	if _built:
		return
	_hills = _make(7301, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0013, FastNoiseLite.FRACTAL_FBM, 4)
	_ridge = _make(4417, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.00055, FastNoiseLite.FRACTAL_RIDGED, 3)
	_warp = _make(881, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0007, FastNoiseLite.FRACTAL_FBM, 2)
	_crag = _make(2203, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0075, FastNoiseLite.FRACTAL_FBM, 3)
	_dune = _make(5519, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0046, FastNoiseLite.FRACTAL_FBM, 2)
	_mesa = _make(6007, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0011, FastNoiseLite.FRACTAL_NONE, 1)
	_patch = _make(3301, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0021, FastNoiseLite.FRACTAL_FBM, 3)
	_bdune = _make(1717, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.024, FastNoiseLite.FRACTAL_FBM, 2)
	_built = true


static func _make(seed_v: int, type: int, freq: float, fractal: int, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


## 0..1: forest hills (north-west and west, and the northern foothills), warped so the border is not a straight line.
static func forest_weight(x: float, z: float) -> float:
	warm()
	var a := atan2(z, x) + _warp.get_noise_2d(x * 1.3 + 900.0, z * 1.3) * 0.5
	return smoothstep(0.3, 0.85, 0.5 + 0.5 * cos(a + PI * 0.75))


## 0..1: dry plains and desert (east and south), the complement of the forest weight across the diagonals.
static func desert_weight(x: float, z: float) -> float:
	warm()
	var a := atan2(z, x) + _warp.get_noise_2d(x * 1.3 + 900.0, z * 1.3) * 0.5
	return smoothstep(0.3, 0.85, 0.5 + 0.5 * cos(a - PI * 0.25))


## The land before water and roads. Metres, y up; the city plateau is exactly 0.
static func height(x: float, z: float) -> float:
	warm()
	var dd := TerrainHeight.city_distance(x, z)
	var m := TerrainHeight.mountain_weight(x, z)
	var cd := TerrainHeight.coast_distance(x, z)
	var u := (cd - dd) / TerrainHeight.BEACH                         # > 0 inland of the waterline, in beach widths
	var fw := forest_weight(x, z)
	var dw := desert_weight(x, z)
	var hn := _hills.get_noise_2d(x, z)
	# rolling land: plains, forest hills (bigger), desert (flat with dunes and the odd mesa)
	var plain := 5.0 + hn * 11.0
	var forest := 26.0 + hn * 46.0 + _crag.get_noise_2d(x, z) * 5.0
	var dune := 4.0 + _dune.get_noise_2d(x, z) * 6.0
	var mesa := smoothstep(0.3, 0.46, _mesa.get_noise_2d(x + 4000.0, z - 1500.0)) * 22.0
	var desert := dune + mesa * smoothstep(300.0, 900.0, dd)
	var low := lerpf(lerpf(plain, forest, fw), desert, dw * (1.0 - fw))
	low = maxf(low, 0.6)
	var elev := lerpf(0.0, low, smoothstep(0.0, FOOTHILL_START, dd))
	# the mountain range: warped, ridged, crag detail, fading towards the coast
	var wx := x + _warp.get_noise_2d(x, z) * 260.0
	var wz := z + _warp.get_noise_2d(x + 500.0, z + 500.0) * 260.0
	var ridge := clampf(_ridge.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
	var coast_fade := 1.0 - smoothstep(cd - 820.0, cd - 260.0, dd)
	var rise := m * smoothstep(MOUNT_START, MOUNT_FULL, dd) * coast_fade
	var mount := (0.26 + 0.78 * pow(ridge, 1.4)) * PEAK * rise      # a broad massif with ridges on it
	mount += _crag.get_noise_2d(x, z) * 0.035 * mount               # crags on the high ground
	elev += mount
	if u >= 1.0:
		return elev
	if u > 0.0:
		# wave 112: a real beach. A steep swash slope (about 2.5 m in the first 30 m: the wet sand band reads as a band, not as a plain), a berm, then the land rises through
		# low dunes over the old 260 m blend (it was one smoothstep from the waterline: a flat pink plain 100 m wide)
		var wl := TerrainHeight.SEA_LEVEL + TerrainHeight.BEACH_TOP
		var sd := u * TerrainHeight.BEACH
		var swash := minf(wl + 2.5 * (1.0 - exp(-sd / 15.0)), elev)
		var base := lerpf(swash, elev, smoothstep(0.0, 1.0, u * u))
		var dunes := _bdune.get_noise_2d(x, z) * 1.5 * smoothstep(0.10, 0.34, u) * (1.0 - smoothstep(0.68, 1.0, u))
		return base + dunes
	var sea_d := -u * TerrainHeight.BEACH
	return TerrainHeight.SEA_LEVEL + TerrainHeight.BEACH_TOP - 42.0 * (1.0 - exp(-sea_d / 420.0)) - sea_d * 0.004


## Biome ids for gameplay (wildlife, grip, map colours). `h` is the finished ground height there.
const CITY := &"city"
const OCEAN := &"ocean"
const BEACH := &"beach"
const MOUNTAIN := &"mountain"
const FOREST := &"forest"
const DESERT := &"desert"
const PLAINS := &"plains"


static func biome_at(x: float, z: float, h: float) -> StringName:
	if TerrainHeight.city_distance(x, z) <= 0.0:
		return CITY
	if h < TerrainHeight.SEA_LEVEL - 0.2:
		return OCEAN
	if h < TerrainHeight.SEA_LEVEL + 3.2 and TerrainHeight.coast_distance(x, z) - TerrainHeight.city_distance(x, z) < TerrainHeight.BEACH * 1.1:
		return BEACH
	if h > 110.0 and TerrainHeight.mountain_weight(x, z) > 0.4:
		return MOUNTAIN
	var fw := forest_weight(x, z)
	var dw := desert_weight(x, z)
	if fw > 0.5:
		return FOREST
	if dw > 0.5:
		return DESERT
	return PLAINS


## Per-vertex shader weights: r forest, g desert, b shoreline (wet sand / beach), a unused (road shoulder is added by the mesher).
static func shade_weights(x: float, z: float, h: float) -> Color:
	var fw := forest_weight(x, z)
	var dw := desert_weight(x, z) * (1.0 - fw)
	var shore := 1.0 - smoothstep(TerrainHeight.SEA_LEVEL + 2.4, TerrainHeight.SEA_LEVEL + 7.0, h)             # wave 112: dry sand up to about 6 m above the sea (was 3.5 m: the beach read as a grass plain with a thin sand edge); the shader ragged-edges it with noise
	var p := _patch.get_noise_2d(x, z)                                   # patchy meadows inside the forest zone, dry scrub inside the plains
	fw = clampf(fw + p * 0.25, 0.0, 1.0)
	return Color(fw, clampf(dw + p * 0.15, 0.0, 1.0), shore, 0.0)
