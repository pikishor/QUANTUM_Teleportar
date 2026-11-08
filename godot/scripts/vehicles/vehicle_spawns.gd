class_name VehicleSpawns
extends RefCounted
## Where the roster vehicles that are not random traffic wait for the player (docs/DESIGN.md: any vehicle, GTA types). A fixed point stands empty until the player comes within SPAWN_AT metres,
## then a fresh vehicle of its kind appears on it; a destroyed one comes back after RESPAWN_AFTER seconds, one the player drove away is simply replaced when he returns to the point. The manager
## polls this once a second (VehicleManager._tick_spawn_points), the map and the tests read POINTS.
##   heli_pad   helicopter on the open lot east of the start (a plaza of the core)
##   airstrip   small plane on the main avenue just east of the core, nose east (a 730 m straight to the border)
##   depot      tank on the west ring road of the core (a straight, clear of the plaza props)
##   harbour_*  speedboats in the flooded quarter (FloodZone), on its streets
## Armoured trucks, quads and scooters are rare traffic (VehicleSpecs.STREAM_KINDS).

const SPAWN_AT := 100.0               ## the player comes this close and the vehicle stands there (inside the streaming radius, so it is not released at once)
const RESPAWN_AFTER := 40.0

const POINTS: Array[Dictionary] = [
	{"id": &"heli_pad", "kind": &"heli", "pos": Vector3(105.0, 0.0, 25.0), "h": 0.0, "label": "HELIPAD"},
	{"id": &"airstrip", "kind": &"plane", "pos": Vector3(340.0, 0.0, 0.0), "h": -PI * 0.5, "label": "AIRSTRIP"},
	{"id": &"depot", "kind": &"tank", "pos": Vector3(-320.0, 0.0, 120.0), "h": 0.0, "label": "ARMY DEPOT"},
	{"id": &"harbour_a", "kind": &"boat", "pos": Vector3(-30.0, 0.0, 480.0), "h": -PI * 0.5, "label": "BOAT"},
	{"id": &"harbour_b", "kind": &"boat", "pos": Vector3(40.0, 0.0, 560.0), "h": PI * 0.5, "label": "BOAT"},
	{"id": &"harbour_c", "kind": &"boat", "pos": Vector3(-120.0, 0.0, 400.0), "h": -PI * 0.5, "label": "BOAT"},
]


static func point(id: StringName) -> Dictionary:
	for p in POINTS:
		if p["id"] == id:
			return p
	return {}


## The nearest spawn point of `kind` to `from` (Vector3.INF when the kind has none).
static func nearest_of(kind: StringName, from: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for p in POINTS:
		if p["kind"] != kind:
			continue
		var pos: Vector3 = p["pos"]
		var d := Vector2(pos.x - from.x, pos.z - from.z).length()
		if d < bd:
			bd = d
			best = pos
	return best
