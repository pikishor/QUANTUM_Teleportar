class_name WorldExtent
extends RefCounted
## How big the world is and where its land reaches (round 6, wave 112: "the map must be at least twice as big as the 6 km square").
##
## The play area is a 9 km square (TerrainHeight.WORLD_HALF 4500: 2.25 times the area of the old 6 km world; CHUNK 250 m and FAR_TILE 1000 m both divide it). The old island kept its
## shape in the south (the harbour, the ships, the airport and the south-east sea stay exactly where they were); the land now reaches further to the WEST (more forest hills), the NORTH
## and the EAST (more mountains, a new coast near the world edge so the wall stands on a beach). It is done in one place: `coast_push(x, z)` is added to TerrainHeight.coast_distance, the
## distance of the coastline from the city plateau in the direction of (x, z).
##
##   WorldExtent.coast_push(x, z)   metres the coast is pushed outwards there (0 in the south: from south-east through south to south-west, up to PUSH_W / PUSH_NE elsewhere)
##   WorldExtent.AREA_FACTOR        the playable area against the old 6 km world (the test checks it is at least 2)
##   WorldExtent.keep_sea_weight    0..1: how much a point lies in the sector that must stay as it was (harbour, ships, airport, south-east sea)

const HALF := 4500.0                        ## TerrainHeight.WORLD_HALF
const OLD_HALF := 3000.0
const AREA_FACTOR := (HALF * HALF) / (OLD_HALF * OLD_HALF)
const KEEP_CENTRE := 1.6929                 ## 97 degrees (atan2(z, x): +x east, +z south): the south, a little to the west of it
const KEEP_HALF := 0.9599                   ## 55 degrees: nothing changes within this angle of the centre (south-east .. south-west)
const KEEP_RAMP := 0.5236                   ## 30 degrees over which the push grows from 0 to its full value
const PUSH_W := 1680.0                      ## the west coast moves out by this much (it was 520 m from the plateau: now about 2.2 km)
const PUSH_NE := 1050.0                     ## the north and east coast (it was 1950 m from the plateau: now about 3 km, 4.1 km from the origin)


## 0 inside the sector that keeps its old coast (about 55 degrees either side of south), 1 from 85 degrees away from the centre on.
static func push_weight(x: float, z: float) -> float:
	var a := atan2(z, x)
	var d := absf(wrapf(a - KEEP_CENTRE, -PI, PI))
	return smoothstep(KEEP_HALF, KEEP_HALF + KEEP_RAMP, d)


## Metres to add to the coast distance of the old island at (x, z).
static func coast_push(x: float, z: float) -> float:
	var w := push_weight(x, z)
	if w <= 0.0:
		return 0.0
	return w * lerpf(PUSH_W, PUSH_NE, TerrainHeight.mountain_weight(x, z))
