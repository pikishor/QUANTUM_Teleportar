class_name Airport
extends RefCounted
## THE AIRPORT (wave 106): EASTFIELD AIRPORT on the flat south-east plain, 1.1 km south of the city's southern edge (z = 1100): the runway runs EAST-WEST along z = 1255 from x = 480 to x = 1280 (the sea
## and the harbour's open water are to its west, the plains and the river to its east, so both approaches are clear of the city and the mountains). Pure data and the terrain carve; the meshes are AirportKit,
## the live nodes AirportWorld, the air traffic AirTraffic, the flight data AircraftFlight.
##
## The field is described in its own LOCAL FRAME (the numbers below): the runway along z (north = -z), the apron on its west side; `FRAME` places that frame in the world (rotated a quarter turn, so local
## north is world east and the apron lies on the north side of the runway, the city side). Everything that leaves this class for the world (`to_world`, `pads()`, `spawn_points()`, `hooks()`, `thresholds()`,
## `guide()`, `carve()`) is in WORLD coordinates; the data the kit and the traffic read (BUILDINGS, TANKS, PARKED, the route points) is local. Local layout (the whole pad is cut to y = 0, the height of the plateau):
##   RUNWAY 09 / 27   local x 1240..1284, z -950..-150 (800 m x 44 m); 09 = eastbound (the touchdown end is the west threshold = local south), 27 = westbound
##   TAXIWAY          local x 1199..1221 along the runway, three connectors
##   APRON            local x 1104..1198, z -985..-200: the TERMINAL (local x 1104..1132) with four gates, the CONTROL TOWER, three HANGARS and a cargo shed, the tank farm at the west end
##   PADS             helipads on the apron (and the roof of a tall tower in the east of the city, and three mountain pads and the two mountain sites: `pads()`)
## `carve(x, z, h)` is called by TerrainHeight.height_at AFTER the roads, so meshes, colliders, aircraft and the hero's feet all see the same flat ground.
##   hooks()           the mission contract of WorldSites.airport(): terminal / gate, hangar, runway (start + heading), helipad
##   guide(p, heading, speed, agl)   the landing guide of the flight HUD
##   spawn_points()    the flyable aircraft that wait on the apron, the helipads and the pads (VehicleSpawns appends them)

const NAME := "EASTFIELD AIRPORT"
const FRAME_ORIGIN := Vector3(330.0, 0.0, -7.0)             ## world = FRAME * local: x_w = 330 - z_l, z_w = x_l - 7 (local (1262, -150) is the west end of the runway, world (480, 1255))
static var FRAME := Transform3D(Basis(Vector3.UP, -PI * 0.5), FRAME_ORIGIN)
const PAD := Rect2(1100.0, -985.0, 280.0, 845.0)           ## the flat ground (local): x 1100..1380, z -985..-140 = world x 475..1315, z 1093..1373
const BLEND := 40.0                                          ## metres over which the pad blends into the land (the river is 50 m beyond its east end)
const FAR := Rect2(1000.0, -1100.0, 520.0, 1000.0)           ## local: outside this rectangle the carve is a no-op (one comparison)
const RUNWAY_X := 1262.0
const RUNWAY_W := 44.0
const RUNWAY_N := -950.0                                     ## z of the north end
const RUNWAY_S := -150.0                                     ## z of the south end
const RUNWAY_LEN := 800.0
const TAXI_X := 1210.0
const TAXI_W := 22.0
const APRON := Rect2(1104.0, -985.0, 94.0, 785.0)
const GATE_X := 1146.0                                       ## the nose of a nosed-in airliner
const GATE_Z: Array[float] = [-697.0, -652.0, -607.0, -562.0]
const CONNECTORS: Array[float] = [-960.0, -585.0, -175.0]    ## z of the taxiway connectors to the runway
const GLIDE := 0.087                                         ## tan of the landing guide's glide slope (5 degrees: an easy one)
const PAD_R := 11.0                                          ## helipad radius

## Mountain pads (flown to, not driven to): flat discs cut into the high country. id, name, centre (x, z), radius; the height is the land there (smoothed), see `ensure()`.
const MOUNTAIN_PADS: Array[Dictionary] = [
	{"id": &"pad_ridge", "name": "RIDGE PAD", "pos": Vector2(-330.0, -1930.0), "r": 13.0},
	{"id": &"pad_peak", "name": "PEAK PAD", "pos": Vector2(760.0, -2330.0), "r": 13.0},
	{"id": &"pad_hill", "name": "WEST HILL PAD", "pos": Vector2(-1420.0, -870.0), "r": 13.0},
]
## Buildings (collision boxes and the kit): kind, centre of the base (x, z), size (x, y, z), yaw (0 = long side along z)
const BUILDINGS: Array[Dictionary] = [
	{"id": &"terminal", "kind": &"terminal", "pos": Vector2(1118.0, -630.0), "size": Vector3(28.0, 12.0, 190.0), "yaw": 0.0},
	{"id": &"tower", "kind": &"tower", "pos": Vector2(1121.0, -498.0), "size": Vector3(9.0, 36.0, 9.0), "yaw": 0.0},
	{"id": &"hangar_a", "kind": &"hangar", "pos": Vector2(1136.0, -940.0), "size": Vector3(50.0, 16.0, 44.0), "yaw": 0.0},
	{"id": &"hangar_b", "kind": &"hangar", "pos": Vector2(1136.0, -876.0), "size": Vector3(50.0, 16.0, 44.0), "yaw": 0.0},
	{"id": &"cargo_shed", "kind": &"shed", "pos": Vector2(1128.0, -770.0), "size": Vector3(40.0, 11.0, 50.0), "yaw": 0.0},
	{"id": &"fire_station", "kind": &"shed", "pos": Vector2(1122.0, -390.0), "size": Vector3(22.0, 8.0, 36.0), "yaw": 0.0},
]
## Fuel tanks: centre (x, z), radius, height
const TANKS: Array[Dictionary] = [
	{"pos": Vector2(1122.0, -172.0), "r": 7.5, "h": 10.0}, {"pos": Vector2(1140.0, -172.0), "r": 7.5, "h": 10.0}, {"pos": Vector2(1158.0, -172.0), "r": 7.5, "h": 10.0},
	{"pos": Vector2(1176.0, -172.0), "r": 7.5, "h": 10.0}, {"pos": Vector2(1124.0, -150.0), "r": 6.0, "h": 8.0}, {"pos": Vector2(1142.0, -150.0), "r": 6.0, "h": 8.0},
]
## Parked scenery (no flying): the model (assets/models/<model>.glb), centre (x, z), heading (rad; PI / 2 = nose west), paint index into the kind's palette, length (m) for the footprint
const PARKED: Array[Dictionary] = [
	{"id": &"gate_1", "model": "xv_airliner", "kind": &"airliner", "pos": Vector2(1163.0, -697.0), "h": PI * 0.5, "paint": 0, "len": 34.0},
	{"id": &"gate_2", "model": "xv_airliner", "kind": &"airliner", "pos": Vector2(1163.0, -652.0), "h": PI * 0.5, "paint": 2, "len": 34.0},
	{"id": &"gate_3", "model": "xv_bizjet", "kind": &"bizjet", "pos": Vector2(1156.0, -607.0), "h": PI * 0.5, "paint": 1, "len": 19.0},
]

static var built := false
static var _pads: Array[Dictionary] = []
static var _roof := {}


## Called once by TerrainHeight.warm: the mountain pads take the height of the land under them (a ring mean, so a ridge does not tilt them).
static func ensure() -> void:
	if built:
		return
	TerrainBase.warm()
	_pads.clear()
	for d in MOUNTAIN_PADS:
		var c: Vector2 = d["pos"]
		var r: float = d["r"]
		var sum := TerrainBase.height(c.x, c.y)
		var n := 1.0
		for k in 8:
			var a := TAU * float(k) / 8.0
			sum += TerrainBase.height(c.x + cos(a) * r * 1.4, c.y + sin(a) * r * 1.4)
			n += 1.0
		var e: Dictionary = d.duplicate()
		e["y"] = sum / n
		e["pos3"] = Vector3(c.x, sum / n, c.y)
		_pads.append(e)
	built = true


## World -> local frame of the field and back.
static func to_local(p: Vector3) -> Vector3:
	return Vector3(p.z - FRAME_ORIGIN.z, p.y, FRAME_ORIGIN.x - p.x)


static func to_world(p: Vector3) -> Vector3:
	return Vector3(FRAME_ORIGIN.x - p.z, p.y, FRAME_ORIGIN.z + p.x)


## The flat pad as a world rectangle (x, z), grown by `margin`: the far skyline towers keep out of it (CitySkyline), so do the props of the city's edge.
static func world_rect(margin := 0.0) -> Rect2:
	return Rect2(Vector2(FRAME_ORIGIN.x - PAD.end.y, FRAME_ORIGIN.z + PAD.position.x), Vector2(PAD.size.y, PAD.size.x)).grow(margin)


## A local heading (Node3D yaw, 0 = local north) as a world heading.
static func heading_world(h: float) -> float:
	return h - PI * 0.5


## The finished land under the airport and the mountain pads. `h` is the land with rivers and roads. Called per terrain sample: the first test must stay cheap.
static func carve(x: float, z: float, h: float) -> float:
	var lx := z - FRAME_ORIGIN.z                                  # the local frame (to_local without the vector)
	var lz := FRAME_ORIGIN.x - x
	if lx >= FAR.position.x and lx <= FAR.end.x and lz >= FAR.position.y and lz <= FAR.end.y:
		var dx := maxf(maxf(PAD.position.x - lx, lx - PAD.end.x), 0.0)
		var dz := maxf(maxf(PAD.position.y - lz, lz - PAD.end.y), 0.0)
		var d := sqrt(dx * dx + dz * dz)
		if d < BLEND:
			h = lerpf(h, 0.0, 1.0 - smoothstep(0.0, BLEND, d))
		return h
	if not built:
		return h
	for e in _pads:
		var c: Vector2 = e["pos"]
		var r: float = e["r"]
		if absf(x - c.x) > r + 30.0 or absf(z - c.y) > r + 30.0:
			continue
		var dd := Vector2(x - c.x, z - c.y).length()
		if dd < r + 30.0:
			h = lerpf(h, float(e["y"]), 1.0 - smoothstep(r, r + 30.0, dd))
	return h


## True on the airport (the flat pad plus `margin`): vegetation, props and roadside things keep out of it. Also true on a mountain pad.
static func inside(x: float, z: float, margin := 0.0) -> bool:
	if PAD.grow(margin).has_point(Vector2(z - FRAME_ORIGIN.z, FRAME_ORIGIN.x - x)):
		return true
	for e in _pads:
		if Vector2(x - (e["pos"] as Vector2).x, z - (e["pos"] as Vector2).y).length() < float(e["r"]) + margin:
			return true
	return false


# --- the places ------------------------------------------------------------------------------------------------------------------------

## The two ends of the runway as landing thresholds (WORLD): id (the number painted on it), the touchdown end, the heading an aircraft lands on (Node3D yaw: -PI/2 = east) and the far end.
## 09 = eastbound: the touchdown end is the west threshold; 27 = westbound.
static func thresholds() -> Array[Dictionary]:
	var w := to_world(Vector3(RUNWAY_X, 0.0, RUNWAY_S))
	var e := to_world(Vector3(RUNWAY_X, 0.0, RUNWAY_N))
	return [
		{"id": "09", "pos": w, "heading": heading_world(0.0), "far": e},
		{"id": "27", "pos": e, "heading": heading_world(PI), "far": w},
	]


## The helipads of the apron (local frame): id, name, centre, radius.
const APRON_PADS: Array[Dictionary] = [
	{"id": &"apron_a", "name": "APRON H1", "local": Vector3(1124.0, 0.0, -262.0), "r": 11.0},
	{"id": &"apron_b", "name": "APRON H2", "local": Vector3(1124.0, 0.0, -230.0), "r": 11.0},
	{"id": &"apron_c", "name": "APRON H3", "local": Vector3(1166.0, 0.0, -246.0), "r": 14.0},
	{"id": &"apron_d", "name": "APRON H4", "local": Vector3(1166.0, 0.0, -212.0), "r": 11.0},
	{"id": &"apron_e", "name": "APRON H5", "local": Vector3(1124.0, 0.0, -198.0), "r": 11.0},
]


## Every helipad (WORLD positions): the apron pads, the roof pad of the tower in the east of the city, the mountain pads and the pads of the two mountain sites. {id, name, pos (y = pad surface), r, kind};
## an apron pad also carries `local`, its place in the field's own frame (what AirportKit paints).
static func pads() -> Array[Dictionary]:
	ensure()
	var out: Array[Dictionary] = []
	for a in APRON_PADS:
		out.append({"id": a["id"], "name": a["name"], "pos": to_world(a["local"]), "local": a["local"], "r": float(a["r"]), "kind": &"apron"})
	var rf := roof()
	if not rf.is_empty():
		out.append({"id": &"pad_roof", "name": "CITY ROOF PAD", "pos": rf["pos"], "r": 8.0, "kind": &"roof"})
	for e in _pads:
		out.append({"id": e["id"], "name": e["name"], "pos": e["pos3"], "r": float(e["r"]), "kind": &"mountain"})
	for sid in [&"observatory", &"radio_tower"]:                    # the flat pads of the mountain sites: a helipad on the side of the pad that is clear of the buildings
		var s := OutskirtsSites.by_id(sid)
		if s.is_empty():
			continue
		var sp: Vector3 = s["pos"]
		var off := Vector3(sin(float(s["yaw"])), 0.0, cos(float(s["yaw"]))) * (float(s["r"]) * 0.55)
		out.append({"id": StringName("pad_" + String(sid)), "name": String(s["name"]) + " PAD", "pos": Vector3(sp.x + off.x, sp.y, sp.z + off.z), "r": 9.0, "kind": &"site"})
	return out


static func pad(id: StringName) -> Dictionary:
	for p in pads():
		if p["id"] == id:
			return p
	return {}


## The elevated helipad on a tall tower in the east of the city (the highest lot with room for it, at least 540 m from the spawn so the start of the game never draws it).
## {lot: the CityLayout lot index, pos: the pad surface (x, roof + HEIGHT, z)}.
const ROOF_LIFT := 2.6
static func roof() -> Dictionary:
	if not _roof.is_empty():
		return _roof
	var lay := CityLayout.new()
	var best: CityLayout.Lot = null
	var bs := -1.0e9
	for lot: CityLayout.Lot in lay.lots:
		if lot.cx < 420.0 or lot.cx > 960.0 or absf(lot.cz) > 700.0 or lot.w < 22.0 or lot.d < 22.0:
			continue
		var dist := Vector2(lot.cx, lot.cz).length()
		if dist < 540.0:
			continue
		var score := lot.h * 10.0 - dist * 0.05 - absf(lot.cz) * 0.02
		if score > bs:
			bs = score
			best = lot
	if best != null:
		_roof = {"lot": best.index, "pos": Vector3(best.cx, best.h + ROOF_LIFT, best.cz), "h": best.h}
	return _roof


## The flyable aircraft that wait on the field (local frame): id, kind, position, heading, label.
const SPAWN_LOCAL: Array[Dictionary] = [
	{"id": &"ap_plane_a", "kind": &"plane", "pos": Vector3(1172.0, 0.0, -470.0), "h": PI * 0.5, "label": "SMALL PLANE"},
	{"id": &"ap_plane_b", "kind": &"plane", "pos": Vector3(1172.0, 0.0, -444.0), "h": PI * 0.5, "label": "SMALL PLANE"},
	{"id": &"ap_airliner", "kind": &"airliner", "pos": Vector3(1178.0, 0.0, -795.0), "h": -PI * 0.5, "label": "AIRLINER"},
	{"id": &"ap_biz", "kind": &"bizjet", "pos": Vector3(1170.0, 0.0, -402.0), "h": PI * 0.5, "label": "BUSINESS JET"},
	{"id": &"ap_cargo", "kind": &"cargo", "pos": Vector3(1160.0, 0.0, -330.0), "h": 0.0, "label": "CARGO PLANE"},
	{"id": &"ap_jet_a", "kind": &"jet", "pos": Vector3(1180.0, 0.0, -944.0), "h": -PI * 0.5, "label": "JET FIGHTER"},
	{"id": &"ap_jet_b", "kind": &"jet", "pos": Vector3(1180.0, 0.0, -914.0), "h": -PI * 0.5, "label": "JET FIGHTER"},
	{"id": &"ap_gunship", "kind": &"gunship", "pos": Vector3(1178.0, 0.0, -878.0), "h": -PI * 0.5, "label": "GUNSHIP"},
	{"id": &"ap_hauler", "kind": &"hauler", "pos": Vector3(1180.0, 0.0, -840.0), "h": -PI * 0.5, "label": "TRANSPORT HELICOPTER"},
	{"id": &"ap_runway", "kind": &"plane", "pos": Vector3(RUNWAY_X, 0.0, RUNWAY_S - 24.0), "h": 0.0, "label": "RUNWAY 09"},
	{"id": &"ap_heli_a", "kind": &"heli", "pos": Vector3(1124.0, 0.0, -262.0), "h": 0.0, "label": "HELICOPTER"},
	{"id": &"ap_heli_b", "kind": &"gunship", "pos": Vector3(1124.0, 0.0, -230.0), "h": 0.0, "label": "GUNSHIP"},
	{"id": &"ap_heli_c", "kind": &"hauler", "pos": Vector3(1166.0, 0.0, -246.0), "h": 0.0, "label": "TRANSPORT HELICOPTER"},
]


## The flyable aircraft that wait at fixed points (WORLD; VehicleSpawns.all_points appends these): the apron, the hangar line, the helipads and every mountain pad. id, kind, pos, h (heading), label.
static func spawn_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sp in SPAWN_LOCAL:
		out.append({"id": sp["id"], "kind": sp["kind"], "pos": to_world(sp["pos"]), "h": heading_world(float(sp["h"])), "label": sp["label"]})
	for p in pads():
		if p["kind"] == &"apron":
			continue
		var kind := &"heli"
		if p["id"] == &"pad_peak" or p["id"] == &"pad_pad_radio_tower":
			kind = &"gunship"
		var pp: Vector3 = p["pos"]
		out.append({"id": StringName("sp_" + String(p["id"])), "kind": kind, "pos": pp, "h": 0.0, "label": String(p["name"])})
	return out


## The map's pins: the airport (one pin), the roof pad and the mountain pads.
static func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"kind": &"garage", "pos": to_world(Vector3(1170.0, 0.0, -560.0)), "fog": false, "label": NAME + ": PLANES AND HELICOPTERS", "glyph": &"airport"}]
	for p in pads():
		if p["kind"] in [&"roof", &"mountain"]:
			out.append({"kind": &"garage", "pos": p["pos"], "fog": true, "label": String(p["name"]) + ": HELICOPTER", "glyph": &"helipad"})
	for hp in SettlementData.helipads():                                     # the hotel roof and the lodge's clearing (wave 112, scripts/settlements)
		out.append({"kind": &"garage", "pos": hp["pos"], "fog": true, "label": String(hp["name"]) + ": HELICOPTER", "glyph": &"helipad"})
	return out


## The mission contract of WorldSites.airport() (WORLD): kind terminal (the walk-up point), hangar, runway (the start of the strip, heading = the heading a plane stands at), helipad.
static func hooks() -> Array[Dictionary]:
	return [
		{"id": &"airport_terminal", "kind": &"terminal", "name": NAME + " TERMINAL", "pos": to_world(Vector3(1146.0, 0.0, -630.0)), "r": 14.0},
		{"id": &"airport_hangar", "kind": &"hangar", "name": "HANGAR", "pos": to_world(Vector3(1158.0, 0.0, -905.0)), "r": 18.0},
		{"id": &"airport_runway", "kind": &"runway", "name": "RUNWAY 09", "pos": to_world(Vector3(RUNWAY_X, 0.0, RUNWAY_S - 24.0)), "heading": heading_world(0.0), "r": 22.0},
		{"id": &"airport_heli", "kind": &"helipad", "name": "APRON H1", "pos": to_world(Vector3(1124.0, 0.0, -262.0)), "r": PAD_R},
	]


# --- landing guide ---------------------------------------------------------------------------------------------------------------------

## The landing guide for an aircraft at `p` (world) flying `heading` (0 = north): while it lines up on a runway end within 2.6 km, {on: true, rwy: "09", dist (m to the threshold, + before it), lat (m, + = the
## runway is to the right of the nose line), vert (m above (+) or below the 5 degree glide path), slope (the path's height at this distance)}; else {on: false}.
static func guide(p: Vector3, heading: float, _speed: float, agl: float) -> Dictionary:
	if Vector2(p.x - 880.0, p.z - 1255.0).length() > 3900.0:
		return {"on": false}
	var best := {"on": false}
	var bd := 1.0e9
	for t in thresholds():
		var th: float = t["heading"]
		var d := Vector3(-sin(th), 0.0, -cos(th))                       # the direction the landing runs in
		var rel := p - (t["pos"] as Vector3)
		var along := -(rel.x * d.x + rel.z * d.z)                       # metres before the threshold (negative past it)
		if along < -(RUNWAY_LEN + 40.0) or along > 2600.0 or (along < -30.0 and agl > 6.0):                # (past the threshold and still in the air: the landing is over, the guide goes)
			continue
		var right := Vector3(-d.z, 0.0, d.x)
		var lat := (rel.x * right.x + rel.z * right.z)                  # + = the plane is to the right of the runway axis
		var off := absf(wrapf(heading - th, -PI, PI))
		if off > 0.9 or absf(lat) > maxf(260.0, along * 0.35):
			continue
		var slope := maxf(along, 0.0) * GLIDE
		var e := absf(lat) + maxf(along, 0.0) * 0.1
		if e < bd:
			bd = e
			best = {"on": true, "rwy": String(t["id"]), "dist": along, "lat": -lat, "vert": agl - slope, "slope": slope, "heading": th}
	return best
