class_name StreetClutter
extends RefCounted
## Wave 123 (w123-clutter): street clutter keeps a clear lane in front of every door.
## A door lane is the sidewalk strip from the door's wall out to the kerb, LANE_HALF to each side of the door. Solid street props (the city kit's collidable kinds,
## folded hydrants / kiosks, planters, bus shelters) that reach into a lane are taken out when the city is built, and ParkedCars leaves the kerb bays empty whose car would
## stand across a lane. The probe of wave 123 found 45 of 71 doors near the spawn with a bollard, bin, antenna, planter or kerb car in front.
## Switch: `on` (env CLUTTER_OLD=1 = the wave 122 behaviour).

static var on: bool = OS.get_environment("CLUTTER_OLD") != "1"

const LANE_HALF := 1.25        ## half width of the clear lane (door 1.8 to 2.4 m, the hero 0.9 m)
const CAR_HALF_LEN := 2.6      ## a kerb car's half length along the kerb, with a little air
const CELL := 24.0

static var _grid := {}          ## cell key -> Array of [wall: Vector3, n: Vector3, kerb: float]
static var _towers_in := false
static var _shops_in := false
static var _for_world: Object = null


## Distance from a wall point along n to the road edge (the kerb), capped at 12 m.
static func kerb_out(wall: Vector3, n: Vector3) -> float:
	var o := 0.0
	while o < 12.0:
		var q := wall + n * o
		if _in_road(q.x) or _in_road(q.z):
			return o
		o += 0.25
	return 12.0


static func _in_road(c: float) -> bool:
	var k := roundf((c + CityLayout.HALF) / CityLayout.PITCH)
	return absf(c - (-CityLayout.HALF + k * CityLayout.PITCH)) < CityLayout.ROAD * 0.5


## Is a prop of half extent `r` at (x, z) inside the lane of the door (wall, n, kerb)?
static func in_lane(wall: Vector3, n: Vector3, kerb: float, x: float, z: float, r: float) -> bool:
	var rel := Vector3(x - wall.x, 0.0, z - wall.z)
	var t := Vector3(-n.z, 0.0, n.x)
	var o := rel.dot(n)
	return o > -0.3 - r and o < kerb + r * 0.5 and absf(rel.dot(t)) < LANE_HALF + r


## The lanes of a door list (city.doors entries: wall, normal): [wall, n, kerb] each.
static func lanes_of(doors: Array) -> Array:
	var out: Array = []
	for d: Dictionary in doors:
		var n: Vector3 = d["normal"]
		var w: Vector3 = d["wall"]
		w.y = 0.0
		out.append([w, n, kerb_out(w, n)])
	return out


static func _key(x: float, z: float) -> int:
	return (int(floorf(x / CELL)) + 4096) * 8192 + int(floorf(z / CELL)) + 4096


static func _index(lanes: Array) -> Dictionary:
	var g := {}
	for ln in lanes:
		var w: Vector3 = ln[0]
		var n: Vector3 = ln[1]
		for s in [0.0, 0.5, 1.0]:
			var q: Vector3 = w + n * (float(ln[2]) * float(s))
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var k := _key(q.x + dx * 6.0, q.z + dz * 6.0)
					if not g.has(k):
						g[k] = []
					if not (g[k] as Array).has(ln):
						(g[k] as Array).append(ln)
	return g


## Build-time filter: drop the items ([Transform3D, Color]) that stand in a door lane. `r` = the prop's half extent.
static func filter_items(items: Array, lanes_grid: Dictionary, r: float) -> Array:
	if not on or lanes_grid.is_empty():
		return items
	var out: Array = []
	for it in items:
		var p: Vector3 = (it[0] as Transform3D).origin
		if not blocks_lane(lanes_grid, p.x, p.z, r):
			out.append(it)
	return out


static func blocks_lane(lanes_grid: Dictionary, x: float, z: float, r: float) -> bool:
	for ln in lanes_grid.get(_key(x, z), []):
		if in_lane(ln[0], ln[1], ln[2], x, z, r):
			return true
	return false


static func grid_for(doors: Array) -> Dictionary:
	return _index(lanes_of(doors))


## Runtime: would a kerb car parked at (x, z) stand across a door lane (city doors, shop doors, tower street doors)?
static func no_parking(x: float, z: float) -> bool:
	if not on:
		return false
	var city = Game.world
	if city == null or not is_instance_valid(city) or not (&"doors" in city):
		return false
	var shops_now := ShopFronts.instance != null and ShopFronts.instance._collected
	if _for_world != city or (not _towers_in and TowerFloors.instance != null) or (shops_now and not _shops_in):
		_rebuild(city)
	for ln in _grid.get(_key(x, z), []):
		var w: Vector3 = ln[0]
		var n: Vector3 = ln[1]
		var rel := Vector3(x - w.x, 0.0, z - w.z)
		var o := rel.dot(n)
		if o > 0.0 and o < float(ln[2]) + 4.5 and absf(rel.dot(Vector3(-n.z, 0.0, n.x))) < LANE_HALF + CAR_HALF_LEN:
			return true
	return false


static func _rebuild(city) -> void:
	_for_world = city
	var lanes := lanes_of(city.doors)
	for d: Dictionary in city.doors:                       # a walk-in shop moved its door along the front (ShopFronts._free_door): that spot too
		if d.has("pos0"):
			var n: Vector3 = d["normal"]
			var w: Vector3 = (d["pos"] as Vector3) - n * 1.3
			w.y = 0.0
			lanes.append([w, n, kerb_out(w, n)])
	_towers_in = TowerFloors.instance != null
	_shops_in = ShopFronts.instance != null and ShopFronts.instance._collected
	if _towers_in:
		for tw: Dictionary in TowerFloors.instance.towers:
			var w2 := TowerFloors.door_pos(tw, 0.0)
			w2.y = 0.0
			var n2 := (TowerFloors.door_pos(tw, 1.0) - TowerFloors.door_pos(tw, 0.0))
			n2.y = 0.0
			n2 = n2.normalized()
			lanes.append([w2, n2, kerb_out(w2, n2)])
	_grid = _index(lanes)

