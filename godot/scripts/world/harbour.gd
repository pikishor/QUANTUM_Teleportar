class_name Harbour
extends RefCounted
## THE HARBOUR (wave 105): the working port on the south coast, 1.4 km south of the core, where the COAST ROAD leaves the city. Pure data and the terrain carve; the meshes and colliders come from
## HarbourKit / HarbourWorld, the bridge over its mouth (the suspension landmark) from Bridges.
##
## Layout (metres, x east, z south, y up; the sea is SEA_LEVEL -2):
##   APRON    the raised quay land, y = QUAY_Y (3.2 m above the sea), x -340..400, z 1340..1640, filled into the beach (the terrain is carved to it, blending out over 36 m on the land sides)
##   BASIN    the dredged water (-8 m) cut into the apron, x -100..160, z 1400..1740: open to the sea in the south, three finger PIERS reach into it from the north quay
##   BRIDGE   the HARBOUR GATE suspension bridge crosses the basin at z = BRIDGE_Z between the two headlands (Bridges)
##   west headland: container yard, two gantry cranes on the west quay, the patrol berth; north strip: warehouses and the harbour office; east headland: tank farm, ferry terminal and berth, lighthouse
## `carve(x, z, h)` is called by TerrainHeight.height_at AFTER the roads, so meshes, colliders, boats and the hero's feet all see the same quay.

const QUAY_Y := 1.2
const APRON := Rect2(-340.0, 1340.0, 740.0, 300.0)
const BASIN := Rect2(-100.0, 1400.0, 260.0, 340.0)
const BASIN_DEPTH := 8.0
const BRIDGE_Z := 1604.0
const FAR := Rect2(-440.0, 1240.0, 940.0, 560.0)       ## outside this rectangle the carve is a no-op (one comparison)
const PIER_X: Array[float] = [-60.0, 20.0, 100.0]
const PIER_Z0 := 1400.0
const PIER_Z1 := 1496.0
const PIER_W := 9.0
const ROAD_X := -300.0                                  ## the harbour road: from the coast road south along x = ROAD_X to the bridge
const SEA_BLEND := 2.5                                  ## metres over which the quay drops to the sea floor on the water sides (a quay wall)
const LAND_BLEND := 40.0

## Boat berths: kind, position (on the water, beside a pier or quay), heading (PI = bow south, towards the open water), label. VehicleSpawns appends these to its points.
const BERTHS: Array[Dictionary] = [
	{"id": &"dock_speed_a", "kind": &"boat", "pos": Vector3(-53.6, -2.0, 1448.0), "h": PI, "label": "SPEEDBOAT"},
	{"id": &"dock_speed_b", "kind": &"boat", "pos": Vector3(13.6, -2.0, 1468.0), "h": PI, "label": "SPEEDBOAT"},
	{"id": &"dock_ski_a", "kind": &"jetski", "pos": Vector3(25.6, -2.0, 1452.0), "h": PI, "label": "JET SKI"},
	{"id": &"dock_ski_b", "kind": &"jetski", "pos": Vector3(94.4, -2.0, 1452.0), "h": PI, "label": "JET SKI"},
	{"id": &"dock_patrol", "kind": &"patrol", "pos": Vector3(-96.4, -2.0, 1540.0), "h": PI, "label": "PATROL BOAT"},
	{"id": &"dock_speed_c", "kind": &"boat", "pos": Vector3(157.4, -2.0, 1486.0), "h": PI, "label": "SPEEDBOAT"},
]

## Where the boat missions start and end (hooks for BoatRun and the mission board): dock ids with their world position and a name.
const DOCKS: Array[Dictionary] = [
	{"id": &"pier_a", "name": "PIER A", "pos": Vector3(-60.0, 1.2, 1494.0), "r": 7.0},
	{"id": &"pier_b", "name": "PIER B", "pos": Vector3(20.0, 1.2, 1494.0), "r": 7.0},
	{"id": &"pier_c", "name": "PIER C", "pos": Vector3(100.0, 1.2, 1494.0), "r": 7.0},
	{"id": &"ferry", "name": "FERRY LANDING", "pos": Vector3(154.0, 1.2, 1540.0), "r": 8.0},
	{"id": &"west_quay", "name": "WEST QUAY", "pos": Vector3(-96.0, 1.2, 1560.0), "r": 8.0},
]
## The buoy course of the BOAT RUN (water points, in order): out of the basin, round the channel and back.
const COURSE: Array[Vector3] = [
	Vector3(30.0, -2.0, 1540.0), Vector3(30.0, -2.0, 1700.0), Vector3(90.0, -2.0, 1880.0), Vector3(-60.0, -2.0, 2000.0), Vector3(-90.0, -2.0, 1820.0), Vector3(30.0, -2.0, 1620.0),
]

static var _layout: Dictionary = {}


## The finished land under the harbour. `h` is the land with rivers and roads. Called per terrain sample: the first test must stay cheap.
static func carve(x: float, z: float, h: float) -> float:
	if x < FAR.position.x or x > FAR.end.x or z < FAR.position.y or z > FAR.end.y:
		return h
	# the apron: flat at the quay height, blending into the land
	var dx := maxf(maxf(APRON.position.x - x, x - APRON.end.x), 0.0)
	var dn := maxf(APRON.position.y - z, 0.0)
	var ds := maxf(z - APRON.end.y, 0.0)
	var d := sqrt(dx * dx + dn * dn + ds * ds)
	if d < LAND_BLEND:
		var bw := SEA_BLEND if ds > 0.0 else LAND_BLEND          # the south edge is a quay wall on the sea, the other sides blend into the beach and the hills
		h = lerpf(h, QUAY_Y, 1.0 - smoothstep(0.0, bw, d))
	# the basin: dredged, with a steep bank all round (the quay wall mesh hides the slope above the water)
	var di := minf(minf(x - BASIN.position.x, BASIN.end.x - x), z - BASIN.position.y)
	if di > 0.0:
		var hb := lerpf(QUAY_Y, -BASIN_DEPTH, smoothstep(0.0, 3.0, di))
		if z < APRON.end.y + 2.0:
			h = hb
		else:
			h = minf(h, hb)
	# the deep-water berths along the south face of both headlands (wave 106: the destroyer and the container ship lie there): dredged to 10 m, blending out over 20 m to the south
	if z > APRON.end.y and z < APRON.end.y + 70.0 and x > APRON.position.x + 2.0 and x < APRON.end.x - 4.0:
		var w := smoothstep(APRON.end.y + 1.5, APRON.end.y + 3.5, z) * (1.0 - smoothstep(APRON.end.y + 45.0, APRON.end.y + 68.0, z))
		var side := smoothstep(APRON.position.x + 2.0, APRON.position.x + 20.0, x) * (1.0 - smoothstep(APRON.end.x - 22.0, APRON.end.x - 4.0, x))
		h = minf(h, lerpf(h, -10.0, w * side))
	return h


## True on the walkable deck of a pier, the quays and the apron beside the water (a boat's driver steps out there).
static func on_dock(x: float, z: float, slack := 0.0) -> bool:
	if not APRON.grow(slack).has_point(Vector2(x, z)):
		return false
	if BASIN.grow(-0.5).has_point(Vector2(x, z)):
		for px in PIER_X:
			if absf(x - px) <= PIER_W * 0.5 + slack and z >= PIER_Z0 - 1.0 and z <= PIER_Z1 + slack:
				return true
		return false
	return true


## The place the hero stands after leaving a boat at `boat_pos`: the nearest dock deck point within `reach` metres (a pier, a quay), else Vector3.INF (he steps into the water).
static func exit_point(boat_pos: Vector3, reach := 9.0) -> Vector3:
	if not FAR.has_point(Vector2(boat_pos.x, boat_pos.z)):
		return Vector3.INF
	var best := Vector3.INF
	var bd := reach
	for a in 24:
		var ang := TAU * float(a) / 24.0
		for r in [2.4, 4.0, 6.0, 8.5]:
			var q := Vector2(boat_pos.x, boat_pos.z) + Vector2(cos(ang), sin(ang)) * float(r)
			if on_dock(q.x, q.y):
				var dd := Vector2(boat_pos.x, boat_pos.z).distance_to(q)
				if dd < bd:
					bd = dd
					best = Vector3(q.x, QUAY_Y + 0.15, q.y)
	return best


static func dock(id: StringName) -> Dictionary:
	for d in DOCKS:
		if d["id"] == id:
			return d
	return {}


## The dock nearest to `p` (a Dictionary from DOCKS) and its distance in a Vector2-free pair [dock, metres].
static func nearest_dock(p: Vector3) -> Array:
	var best: Dictionary = {}
	var bd := INF
	for d in DOCKS:
		var q: Vector3 = d["pos"]
		var dist := Vector2(q.x - p.x, q.z - p.z).length()
		if dist < bd:
			bd = dist
			best = d
	return [best, bd]


## Where on the map the harbour is (the middle of the basin), for the map and the tests.
static func center() -> Vector3:
	return Vector3(BASIN.position.x + BASIN.size.x * 0.5, QUAY_Y, 1480.0)


# --- the layout of the kit (deterministic) -------------------------------------------------------------------------------------------

## Everything HarbourKit builds, as data: {"containers": [{pos, size, yaw, col}], "sheds": [{pos, size, col, roof}], "cranes": [{pos, dir}], "tanks": [{pos, r, h}], "lamps": [Vector3],
## "bollards": [Vector3], "office": {pos, size}, "lighthouse": Vector3, "terminal": {pos, size}, "boxes": [{pos, size}] (the collision boxes)}
static func layout() -> Dictionary:
	if not _layout.is_empty():
		return _layout
	var rng := RandomNumberGenerator.new()
	rng.seed = 105105
	var palette: Array[Color] = [Color(0.72, 0.18, 0.14), Color(0.16, 0.34, 0.62), Color(0.86, 0.62, 0.12), Color(0.18, 0.5, 0.34), Color(0.78, 0.78, 0.76), Color(0.4, 0.22, 0.5),
		Color(0.9, 0.38, 0.12), Color(0.2, 0.22, 0.26), Color(0.12, 0.5, 0.58)]
	var containers: Array = []
	var boxes: Array = []
	# the container yard on the west headland: stacks of 12 m boxes along x, rows with aisles
	var rows := 5
	for row in rows:
		var z := 1428.0 + float(row) * 30.0
		var x := -312.0
		while x < -140.0:
			var len_n := 1 + rng.randi() % 3
			var high := 1 + rng.randi() % 3
			var col := palette[rng.randi() % palette.size()]
			var cx := x + float(len_n) * 6.1
			for k in len_n:
				for lv in high:
					containers.append({"pos": Vector3(x + 6.1 + float(k) * 12.4, QUAY_Y + 1.3 + float(lv) * 2.65, z), "size": Vector3(12.2, 2.6, 2.5), "yaw": 0.0,
						"col": col.lerp(palette[rng.randi() % palette.size()], 0.18 if lv > 0 else 0.0)})
					containers.append({"pos": Vector3(x + 6.1 + float(k) * 12.4, QUAY_Y + 1.3 + float(lv) * 2.65, z + 2.7), "size": Vector3(12.2, 2.6, 2.5), "yaw": 0.0,
						"col": palette[rng.randi() % palette.size()]})
			boxes.append({"pos": Vector3(x + float(len_n) * 6.2, QUAY_Y + float(high) * 1.32, z + 1.35), "size": Vector3(float(len_n) * 12.4, float(high) * 2.65, 5.3)})
			x += float(len_n) * 12.4 + 6.0 + float(rng.randi() % 2) * 6.0
			cx += 0.0
	# containers stacked by the east quay and on the apron strip next to the tanks
	for k in 4:
		for lv in 2:
			containers.append({"pos": Vector3(215.0 + float(k) * 12.4, QUAY_Y + 1.3 + float(lv) * 2.65, 1366.0), "size": Vector3(12.2, 2.6, 2.5), "yaw": 0.0, "col": palette[rng.randi() % palette.size()]})
	boxes.append({"pos": Vector3(240.0, QUAY_Y + 2.65, 1366.0), "size": Vector3(50.0, 5.3, 2.6)})
	# warehouses along the north strip
	var sheds: Array = []
	var shed_defs := [[-300.0, 1362.0, 70.0, 30.0, 12.0, Color(0.55, 0.58, 0.6)], [-215.0, 1362.0, 70.0, 30.0, 12.0, Color(0.62, 0.5, 0.36)], [-130.0, 1362.0, 60.0, 30.0, 10.0, Color(0.5, 0.56, 0.52)],
		[110.0, 1362.0, 90.0, 30.0, 13.0, Color(0.58, 0.58, 0.62)], [310.0, 1380.0, 70.0, 34.0, 12.0, Color(0.6, 0.45, 0.4)]]
	for s in shed_defs:
		sheds.append({"pos": Vector3(float(s[0]), QUAY_Y, float(s[1])), "size": Vector3(float(s[2]), float(s[4]), float(s[3])), "col": s[5]})
		boxes.append({"pos": Vector3(float(s[0]), QUAY_Y + float(s[4]) * 0.5, float(s[1])), "size": Vector3(float(s[2]), float(s[4]), float(s[3]))})
	var office := {"pos": Vector3(-30.0, QUAY_Y, 1372.0), "size": Vector3(34.0, 15.0, 20.0)}
	boxes.append({"pos": Vector3(-30.0, QUAY_Y + 7.5, 1372.0), "size": Vector3(34.0, 15.0, 20.0)})
	# gantry cranes: on the west quay (boom out over the water) and the east quay
	var cranes: Array = [{"pos": Vector3(-103.0, QUAY_Y, 1470.0), "dir": 1.0}, {"pos": Vector3(-103.0, QUAY_Y, 1536.0), "dir": 1.0}, {"pos": Vector3(163.0, QUAY_Y, 1590.0), "dir": -1.0}]
	for c in cranes:
		var cp: Vector3 = c["pos"]
		for sz in [-8.0, 8.0]:
			for sx in [-1.2, 15.0 * -float(c["dir"])]:
				boxes.append({"pos": Vector3(cp.x + float(sx), QUAY_Y + 14.0, cp.z + float(sz)), "size": Vector3(2.2, 28.0, 2.2)})
	# tank farm on the east headland
	var tanks: Array = []
	for t in [[260.0, 1470.0, 13.0, 15.0], [296.0, 1470.0, 13.0, 15.0], [332.0, 1470.0, 13.0, 15.0], [278.0, 1520.0, 11.0, 12.0], [316.0, 1520.0, 11.0, 12.0], [354.0, 1470.0, 9.0, 11.0]]:
		tanks.append({"pos": Vector3(float(t[0]), QUAY_Y, float(t[1])), "r": float(t[2]), "h": float(t[3])})
		boxes.append({"pos": Vector3(float(t[0]), QUAY_Y + float(t[3]) * 0.5, float(t[1])), "size": Vector3(float(t[2]) * 1.8, float(t[3]), float(t[2]) * 1.8)})
	# the ferry terminal on the east quay, the lighthouse at the tip of the east headland
	var terminal := {"pos": Vector3(190.0, QUAY_Y, 1536.0), "size": Vector3(30.0, 9.0, 52.0)}
	boxes.append({"pos": Vector3(190.0, QUAY_Y + 4.5, 1536.0), "size": Vector3(30.0, 9.0, 52.0)})
	var lighthouse := Vector3(388.0, QUAY_Y, 1626.0)
	boxes.append({"pos": Vector3(388.0, QUAY_Y + 14.0, 1626.0), "size": Vector3(7.0, 28.0, 7.0)})
	# lamps along the quays and piers, bollards along the pier edges
	var lamps: Array[Vector3] = []
	for pz in range(1410, 1496, 28):
		for px in PIER_X:
			lamps.append(Vector3(px, QUAY_Y, float(pz)))
	for qz in range(1420, 1640, 36):
		lamps.append(Vector3(-103.0, QUAY_Y, float(qz)))
		lamps.append(Vector3(163.0, QUAY_Y, float(qz)))
	for qx in range(-300, -140, 40):
		lamps.append(Vector3(float(qx), QUAY_Y, 1405.0))
	var bollards: Array[Vector3] = []
	for px in PIER_X:
		for pz in range(1408, 1496, 14):
			bollards.append(Vector3(px - 4.1, QUAY_Y, float(pz)))
			bollards.append(Vector3(px + 4.1, QUAY_Y, float(pz)))
	for qz in range(1420, 1630, 20):
		bollards.append(Vector3(-99.0, QUAY_Y, float(qz)))
		bollards.append(Vector3(159.0, QUAY_Y, float(qz)))
	_layout = {"containers": containers, "sheds": sheds, "cranes": cranes, "tanks": tanks, "lamps": lamps, "bollards": bollards, "office": office, "lighthouse": lighthouse,
		"terminal": terminal, "boxes": boxes}
	return _layout
