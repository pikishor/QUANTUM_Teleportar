class_name TerrainHeight
extends RefCounted
## THE source of truth for the height of the ground outside (and under) the city, and for where water stands on it.
## Terrain meshes, colliders, vegetation, roads, water and the hero's feet all ask this one class; nobody keeps a second copy of the land.
##
##   height_at(x, z)       ground height in metres (y), with rivers and lakes already carved in
##   base_height(x, z)     the land WITHOUT water carving: the coast, the hills and the mountains. The terrain builder owns this function:
##                         replace its body freely, the water layer (WaterLayout) adapts: river beds are cut relative to it when the layout is built.
##   water_level_at(x, z)  y of the water surface standing over that point (ocean, river or lake), NO_WATER where the point is dry
##   depth_at(x, z)        metres of water over the ground there (0 when dry)
##   flow_at(x, z)         river current at the point in m/s (x, z), zero on still water and on land
##   slope_at(x, z)        gradient magnitude (rise over run) of the ground
##   warm()                builds the river and lake tables: call it once on the main thread before sampling from worker threads
##
## Layout (metres, forward is -Z): the city is the flat plateau |x|, |z| <= CITY_HALF at y = 0 (the 2080 m city plus its border walls). Beyond it hills and then
## MOUNTAINS rise to the north (-Z) and the east (+X); the west and the south end in beaches and the OCEAN (a coast 500-900 m from the city edge). The sea surface is
## SEA_LEVEL everywhere. Three rivers run from the mountains to the sea (WaterLayout), three lakes sit in the high country. WORLD_HALF is the edge of the play area; the
## sea goes on beyond it.

const SEA_LEVEL := -2.0                  ## y of the ocean surface (the city plateau is 2 m above it)
const WORLD_HALF := 3000.0               ## the world is a 6 km square
const CITY_HALF := 1100.0                ## flat plateau half-size around the origin
const NO_WATER := -1.0e9
const BEACH := 260.0                     ## metres of beach slope between the open land and the waterline
const BEACH_TOP := 0.35                  ## the waterline sits this far above SEA_LEVEL on the sand

static var _hills: FastNoiseLite
static var _ridge: FastNoiseLite
static var _coast: FastNoiseLite
static var _ready_flag := false


static func warm() -> void:
	_ensure()
	TerrainBase.warm()
	WaterLayout.ensure()
	TerrainRoads.ensure()                 # ends with RailNet.ensure() (the railway is routed over the finished roads)
	OutskirtsSites.ensure()
	Airport.ensure()


static func _ensure() -> void:
	if _ready_flag:
		return
	_hills = FastNoiseLite.new()
	_hills.seed = 7301
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0013
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 4
	_ridge = FastNoiseLite.new()
	_ridge.seed = 4417
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 0.0011
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_coast = FastNoiseLite.new()
	_coast.seed = 991
	_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast.frequency = 0.0009
	_ready_flag = true


## 0 on the sea sides (west, south), 1 on the mountain sides (north, east), smooth around the compass.
static func mountain_weight(x: float, z: float) -> float:
	var a := atan2(z, x)
	var w := 0.5 + 0.5 * cos(a + PI * 0.25)
	return smoothstep(0.25, 0.8, w)


## Distance from the city plateau (0 on it).
static func city_distance(x: float, z: float) -> float:
	var dx := maxf(absf(x) - CITY_HALF, 0.0)
	var dz := maxf(absf(z) - CITY_HALF, 0.0)
	return sqrt(dx * dx + dz * dz)


## Distance of the coastline from the plateau in the direction of (x, z).
static func coast_distance(x: float, z: float) -> float:
	_ensure()
	return lerpf(520.0, 1950.0, mountain_weight(x, z)) + _coast.get_noise_2d(x, z) * 170.0


## The land before any river or lake is cut into it. (Terrain builder: this is the function to replace.)
static func base_height(x: float, z: float) -> float:
	return TerrainBase.height(x, z)               # scripts/terrain/terrain_base.gd: biomes, mountains, coast


## The ground height with rivers and lakes carved in.
static func height_at(x: float, z: float) -> float:
	return Airport.carve(x, z, OutskirtsSites.carve(x, z, Harbour.carve(x, z, RailNet.carve(x, z, TerrainRoads.carve(x, z, WaterLayout.carve(x, z, base_height(x, z)))))))       # land, then the rivers, then the road benches (scripts/terrain/terrain_roads.gd), then the railway benches (scripts/rail/rail_net.gd), then the harbour quay (scripts/world/harbour.gd), then the pads of the mountain and outskirt sites (scripts/terrain/outskirts_sites.gd)


## y of the water surface over (x, z), NO_WATER where the ground is dry.
static func water_level_at(x: float, z: float) -> float:
	return water_level_for(x, z, height_at(x, z))


## Same as water_level_at when the ground height is already known (saves a second terrain sample).
static func water_level_for(x: float, z: float, ground: float) -> float:
	var best := NO_WATER
	if ground < SEA_LEVEL:
		best = SEA_LEVEL
	var inland := WaterLayout.surface_at(x, z)
	if inland > best:
		best = inland
	if best > ground + 0.001:
		return best
	return NO_WATER


static func depth_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	var w := water_level_for(x, z, h)
	return maxf(0.0, w - h) if w != NO_WATER else 0.0


## The height a vehicle rides at (x, z): the finished ground, or the deck of a bridge when `y_hint` (the vehicle's own height) is within reach of it (Bridges.deck_y).
static func drive_height_at(x: float, z: float, y_hint: float) -> float:
	var d := Bridges.deck_y(x, z, y_hint)
	return d if d != NO_WATER else height_at(x, z)


static func is_water(x: float, z: float) -> bool:
	return water_level_at(x, z) != NO_WATER


static func flow_at(x: float, z: float) -> Vector2:
	return WaterLayout.flow_at(x, z)


static func slope_at(x: float, z: float) -> float:
	var e := 2.0
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return sqrt(dx * dx + dz * dz) / (2.0 * e)
