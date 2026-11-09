class_name VehicleSpawns
extends RefCounted
## Where the roster vehicles that are not random traffic wait for the player (docs/DESIGN.md: any vehicle, GTA types). A fixed point stands empty until the player comes within SPAWN_AT metres,
## then a fresh vehicle of its kind appears on it; a destroyed one comes back after RESPAWN_AFTER seconds, one the player drove away is simply replaced when he returns to the point. The manager
## polls this once a second (VehicleManager._tick_spawn_points), the map and the tests read POINTS.
##   heli_pad   helicopter on the open lot east of the start (a plaza of the core)
##   airstrip   small plane on the main avenue just east of the core, nose east (a 730 m straight to the border)
##   depot      tank on the west ring road of the core (a straight, clear of the plaza props)
##   harbour_*  speedboats in the flooded quarter (FloodZone), on its streets
##   dock_*     the boat berths of the harbour on the south coast (Harbour.BERTHS): speedboats, jet skis and the patrol boat on the real water, beside the piers and quays
## Armoured trucks, quads and scooters are rare traffic (VehicleSpecs.STREAM_KINDS).

const SPAWN_AT := 100.0               ## the player comes this close and the vehicle stands there (inside the streaming radius, so it is not released at once)
const RESPAWN_AFTER := 40.0

const POINTS: Array[Dictionary] = [
	{"id": &"heli_pad", "kind": &"heli", "pos": Vector3(105.0, 0.0, 25.0), "h": 0.0, "label": "HELIPAD"},
	{"id": &"airstrip", "kind": &"plane", "pos": Vector3(340.0, 0.0, 0.0), "h": -PI * 0.5, "label": "AIRSTRIP"},
	{"id": &"depot", "kind": &"tank", "pos": Vector3(-320.0, 0.0, 120.0), "h": 0.0, "label": "ARMY DEPOT"},
	{"id": &"depot_light", "kind": &"ltank", "pos": Vector3(-320.0, 0.0, 90.0), "h": 0.0, "label": "LIGHT TANK"},
	{"id": &"depot_apc", "kind": &"apc", "pos": Vector3(-320.0, 0.0, 150.0), "h": 0.0, "label": "ARMOURED CARRIER"},
	{"id": &"depot_gun", "kind": &"artillery", "pos": Vector3(-320.0, 0.0, 180.0), "h": 0.0, "label": "MOBILE ARTILLERY"},
	{"id": &"depot_aa", "kind": &"aatank", "pos": Vector3(-320.0, 0.0, 60.0), "h": 0.0, "label": "ANTI-AIR TANK"},
	{"id": &"harbour_a", "kind": &"boat", "pos": Vector3(-30.0, 0.0, 480.0), "h": -PI * 0.5, "label": "BOAT"},
	{"id": &"harbour_b", "kind": &"boat", "pos": Vector3(40.0, 0.0, 560.0), "h": PI * 0.5, "label": "BOAT"},
	{"id": &"harbour_c", "kind": &"boat", "pos": Vector3(-120.0, 0.0, 400.0), "h": -PI * 0.5, "label": "BOAT"},
	# the outskirts (terrain world): off-road vehicles wait at the gates of the highways, so the way out of the city has a ride (4x4 grip on dirt, sand and rock)
	{"id": &"outpost_rover", "kind": &"rover", "pos": Vector3(1180.0, 0.0, 22.0), "h": -PI * 0.5, "label": "OFF-ROADER"},
	{"id": &"outpost_suv", "kind": &"suv", "pos": Vector3(20.0, 0.0, -1170.0), "h": 0.0, "label": "4X4"},
	{"id": &"outpost_quad", "kind": &"quad", "pos": Vector3(-1170.0, 0.0, -24.0), "h": PI * 0.5, "label": "QUAD"},
]


## Every spawn point: the fixed POINTS above and the boat berths of the harbour (Harbour.BERTHS: speedboats, jet skis and the patrol boat beside the piers).
static func all_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(POINTS)
	out.append_array(Harbour.BERTHS)
	out.append_array(OutskirtsSites.vehicle_points())
	out.append_array(Airport.spawn_points())                      # EASTFIELD AIRPORT: planes, jets, helicopters on the apron, the helipads and the mountain pads (wave 106)
	out.append_array(WorldRoam.vehicle_points())             # the rover and the quad at the foot of QUARRY TRACK (off-road trial)
	return out


static func point(id: StringName) -> Dictionary:
	for p in all_points():
		if p["id"] == id:
			return p
	return {}


## The nearest spawn point of `kind` to `from` (Vector3.INF when the kind has none).
static func nearest_of(kind: StringName, from: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for p in all_points():
		if p["kind"] != kind:
			continue
		var pos: Vector3 = p["pos"]
		var d := Vector2(pos.x - from.x, pos.z - from.z).length()
		if d < bd:
			bd = d
			best = pos
	return best
