class_name AirTraffic
extends Node3D
## AIR TRAFFIC of EASTFIELD AIRPORT (wave 106; every position inside the flights is in the FIELD'S LOCAL FRAME, Airport.to_world turns it into the world): airliners and a business jet that take off and land on the runway (gate, pushback, taxi, line up, take-off roll, climb, a circuit over the plains,
## a 5 degree approach, flare, roll-out, taxi in), a small plane doing the same, and three helicopters (a light one, a gunship, a transport) that lift from their pads, patrol the east plain and the city
## edge and come back down. Seven FLIGHTS, kinematic (no physics, no collisions, a few vectors each) that run all the time and are only drawn (AircraftScenery models) within SHOW metres of the player:
## nothing here costs a draw call anywhere near the city's start. A grounded or hovering flight is HIJACKABLE: when the hero on foot comes within PROMOTE_R of one that stands or crawls on the apron, it is
## replaced by a real Vehicle (VehicleManager.spawn_parked, flagged `ai`, a pilot at the controls) the hero can ENTER; entering throws the pilot out (Hijack) and the flight is gone for a while.
##   flights               Array[Flight]
##   fast_forward(secs)    runs the whole simulation `secs` game seconds at once (tests, and a returning player finds the field in a plausible state)
##   stats()               {flights, takeoffs, landings, laps, promoted, hijacked, min_clear}
## A Flight follows a ROUTE: waypoints {p (Vector3, y = height above the ground), v (m/s on arrival), hold (s to wait there), rev (reverse: heading kept), ground (stays on the ground), phase}.

const SHOW := 900.0                       ## flights nearer than this to the player get a model; none exist as nodes beyond HIDE
const HIDE := 1150.0
const PROMOTE_R := 24.0                   ## the hero on foot this close to a grounded flight turns it into a real aircraft
const DEMOTE_R := 70.0
const PROMOTE_MAX := 30.0                 ## seconds a promoted aircraft waits for the hero
const GATE_X := 1163.0
## WAVE 126 (w126-air): the ROSTER flies. The second airliner comes back each lap as the next airliner of the roster (the first stays the classic one, the small plane, the business jet and
## the three helicopters keep their kinds), the airliners leave on a TIMETABLE (one departure every DEPART_EVERY s, in turn), and four CROSSERS (two helicopters of the 23 of wave 125, two
## planes of the wave 126 roster) cross the sky over the outskirts, a new line and a new kind each time. Models are POOLED (a model that leaves the view waits hidden for the next flight of its kind)
## and LOD'd: beyond LOD_R a flight is a SPECK of one shared MultiMesh (one draw for all of them), its model is only built inside LOD_R.
## W126A_OLD=1 (or roster_on = false): the wave 125 traffic (seven flights, fixed kinds, no timetable, no crossers, no pool, no specks).
const DEPART_EVERY := 150.0
const LOD_R := 480.0
const POOL_KEEP := 2                       ## hidden models kept per kind
const CROSS_AGL := [170.0, 230.0, 200.0, 260.0]
const LINER_KINDS: Array[StringName] = [&"airliner", &"p_narrow", &"p_regional", &"p_wide", &"p_jumbo"]
const CROSS_PLANES: Array[StringName] = [&"p_cub", &"p_regional", &"p_twin", &"p_freighter", &"p_trainer", &"p_fighter", &"p_seaplane", &"p_bomber", &"p_biplane", &"p_glider", &"p_awacs",
		&"p_bush", &"jet", &"cargo", &"p_tanker", &"p_racer", &"p_duster", &"p_interceptor"]
static var roster_on := OS.get_environment("W126A_OLD") != "1"
## w128-airlook: six crossers (three helicopters, three planes) instead of four, and the three pad helicopters cycle through the new helicopter kinds that fit a pad (W128_OLD=1: off).
static var more_on := OS.get_environment("W128_OLD") != "1"
const APRON_A: Array[StringName] = [&"h_scout", &"h_news", &"h_police", &"h_trainer", &"h_ultra", &"h_vip", &"h_medic"]
const APRON_B: Array[StringName] = [&"h_attack", &"h_stealth", &"h_coax", &"h_naval", &"h_quantum", &"h_void"]
const APRON_C: Array[StringName] = [&"h_utility", &"h_fire", &"h_gull"]

class Flight extends RefCounted:
	var id: StringName
	var kind: StringName
	var paint := 0
	var heli := false
	var route: Array[Dictionary] = []
	var idx := 0
	var pos := Vector3.ZERO               ## world position, y = height above the ground (the airport ground is y = 0)
	var heading := 0.0
	var pitch := 0.0
	var roll := 0.0
	var speed := 0.0
	var hold := 0.0
	var hold_phase: StringName = &"parked"
	var rotor := 0.0
	var ang := 0.0
	var stand := Vector3.ZERO             ## where it parks (planes) or the pad it lifts from (helicopters)
	var stand_h := 0.0
	var phase: StringName = &"parked"
	var airborne := false
	var node: Node3D
	var vehicle: Vehicle                  ## the real aircraft it was turned into for the hero (null otherwise)
	var promote_t := 0.0
	var cooldown := 0.0
	var gone := 0.0                       ## > 0: hijacked, comes back at its stand after this many seconds
	var takeoffs := 0
	var landings := 0
	var laps := 0
	var min_clear := 1.0e9                ## the lowest clearance over the terrain while it was flying (tests)
	var kinds: Array[StringName] = []     ## w126-air: the kinds this flight takes in turn (one per lap); empty = always `kind`
	var ki := 0
	var cross := false                    ## a crosser: one straight line over the outskirts, then a new line
	var slot := -1                        ## the airliners' place in the timetable (-1: no timetable)
	var kinds_flown := {}                 ## kind -> laps flown as it (tests)
	var lod := false                      ## drawn as a speck now
	var wp_cache := Vector3.ZERO          ## the speck's world position

	func node_kind() -> StringName:
		return StringName(node.get_meta(&"kind", kind)) if node != null and is_instance_valid(node) else kind

static var instance: AirTraffic = null

var flights: Array[Flight] = []
var hijacked := 0
var time_scale := 1.0
var _pt := 0.0
var _rng := RandomNumberGenerator.new()
var clock := 0.0                          ## game seconds the traffic has run (the timetable's clock; fast_forward counts too)
var departures := 0                       ## timetable departures so far (tests)
var _pool := {}                           ## kind -> Array[Node3D] hidden models
var pool_reused := 0                      ## models taken from the pool (tests)
var models_built := 0
var _specks: MultiMeshInstance3D


func _ready() -> void:
	instance = self
	_rng.seed = 1061
	_build()
	set_physics_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	for f in flights:
		if f.node != null and is_instance_valid(f.node):
			f.node.queue_free()


# --- the flights ------------------------------------------------------------------------------------------------------------------------

func _build() -> void:
	# an airliner on final approach, one at gate 4 about to leave, a business jet in the circuit, a small plane at the apron
	_add_plane(&"air_a", &"airliner", 1, Vector3(GATE_X, 0.0, -562.0), &"approach")
	_add_plane(&"air_b", &"airliner", 3, Vector3(GATE_X, 0.0, -562.0), &"parked")
	_add_plane(&"biz", &"bizjet", 2, Vector3(1172.0, 0.0, -368.0), &"circuit")
	_add_plane(&"ga", &"plane", 0, Vector3(1172.0, 0.0, -505.0), &"parked")
	_add_heli(&"heli_a", &"heli", Airport.pad(&"apron_d"), 0)
	_add_heli(&"heli_b", &"gunship", Airport.pad(&"apron_e"), 20)
	_add_heli(&"heli_c", &"hauler", Airport.pad(&"apron_c"), 45)
	flights[1].hold = 25.0                                                      # the airliner at the gate leaves soon after the start
	flights[3].hold = 55.0
	if roster_on:
		_roster()


## w126-air: the kinds each flight takes in turn, the timetable, the crossers and the specks.
func _roster() -> void:
	flights[0].slot = 0                                                         # the first airliner stays the classic airliner (the field always shows one), the second flies the roster's
	flights[1].kinds = _have(LINER_KINDS)
	flights[1].slot = 1
	var hl := _have(HeliRoster.NEW)
	var pl := _have(CROSS_PLANES)
	var nc := 6 if more_on else 4
	if more_on:                                                                 # w128-airlook: the pad helicopters fly the wave 125 kinds in turn (the classic kind first)
		var pads := {&"heli_a": APRON_A, &"heli_b": APRON_B, &"heli_c": APRON_C}
		for f in flights:
			if pads.has(f.id):
				var ks: Array[StringName] = [f.kind]
				ks.append_array(_have(pads[f.id]))
				f.kinds = ks
	for i in nc:
		var f := Flight.new()
		f.id = StringName("cross_%d" % i)
		f.cross = true
		f.heli = i % 2 == 0
		var src: Array[StringName] = hl if f.heli else pl
		if src.is_empty():
			continue
		var mine2: Array[StringName] = []
		for j in range(i / 2, src.size(), nc / 2):
			mine2.append(src[j])
		f.kinds = mine2
		f.kind = mine2[0]
		f.paint = i
		flights.append(f)
		_new_line(f, i)
	_specks = MultiMeshInstance3D.new()
	_specks.name = "Specks"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.82, 0.84, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.albedo_texture = _speck_tex()
	q.material = mat
	mm.mesh = q
	mm.instance_count = flights.size()
	mm.visible_instance_count = 0
	_specks.multimesh = mm
	_specks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_specks.custom_aabb = AABB(Vector3(-6000, -100, -6000), Vector3(12000, 2000, 12000))
	_specks.visible = false
	add_child(_specks)


## A small aircraft silhouette (cross shape) for the far specks.
static func _speck_tex() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 16:
		for y in range(7, 9):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	for y in range(3, 14):
		for x in range(7, 9):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	for x in range(5, 11):
		img.set_pixel(x, 12, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


static func _have(list: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in list:
		if VehicleSpecs.SPECS.has(StringName(str(k))):
			out.append(StringName(str(k)))
	return out


## A crosser's next line: from one side of the outskirts to the other (local frame of the field, never over the city), at its own height and speed.
func _new_line(f: Flight, seed_i := -1) -> void:
	var a := _rng.randf() * TAU if seed_i < 0 else float(seed_i) * 1.7
	var c := Vector3(1500.0, 0.0, -500.0)                                         # the middle of the east plain, east of the field (world z > 1400: far from the city)
	var d := Vector3(cos(a), 0.0, sin(a))
	var half := 1700.0
	var p0 := c - d * half
	var p1 := c + d * half
	p0.x = clampf(p0.x, 1150.0, 2900.0)                                         # w126-critic: and not past local x 2900 (a crosser 3.2 km out broke test_airport_aircraft "every flight is somewhere on the map")
	p1.x = clampf(p1.x, 1150.0, 2900.0)
	var agl: float = CROSS_AGL[absi(hash(f.id)) % CROSS_AGL.size()]
	var v := 34.0 if f.heli else clampf(float(VehicleSpecs.SPECS.get(f.kind, {}).get("stall", 30.0)) * 1.6, 30.0, 90.0)
	f.route = [_wp(Vector3(p1.x, agl, p1.z), v, 0.0, false, false, &"cross")]
	f.idx = 0
	f.pos = Vector3(p0.x, agl, p0.z)
	f.heading = atan2(-d.x, -d.z)
	f.speed = v
	f.airborne = true
	f.rotor = 1.0
	f.phase = &"cross"
	f.hold = 0.0


## The next kind of a flight's list (a lap is over): its model goes back to the pool.
func _next_kind(f: Flight) -> void:
	if f.kinds.size() < 2:
		return
	_drop_node(f)
	f.ki = (f.ki + 1) % f.kinds.size()
	f.kind = f.kinds[f.ki]
	if not f.heli and not f.cross:
		f.route = plane_route(f.kind, f.stand)


## Seconds until the timetable's next departure for slot `slot`.
func until_departure(slot: int) -> float:
	var n := 2
	var period := DEPART_EVERY * float(n)
	var at := fposmod(float(slot) * DEPART_EVERY - clock, period)
	return at


## The timetable: [{id, kind, in (s)}] of the airliners, next departure first.
func timetable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in flights:
		if f.slot >= 0:
			out.append({"id": f.id, "kind": f.kind, "in": until_departure(f.slot) if f.idx == 0 else 0.0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["in"]) < float(b["in"]))
	return out


func _speeds(kind: StringName) -> Dictionary:
	var sp: Dictionary = VehicleSpecs.SPECS[kind]
	var stall := float(sp["stall"])
	var vr := stall * 1.2
	return {"vr": vr, "climb": vr * 1.28, "app": stall * 1.5, "td": stall * 1.12}


func _add_plane(id: StringName, kind: StringName, paint: int, stand: Vector3, start: StringName) -> void:
	var f := Flight.new()
	f.id = id
	f.kind = kind
	f.paint = paint
	f.stand = stand
	f.stand_h = PI * 0.5
	f.route = plane_route(kind, stand)
	flights.append(f)
	_start_at(f, start)


func _add_heli(id: StringName, kind: StringName, pad: Dictionary, delay: int) -> void:
	var f := Flight.new()
	f.id = id
	f.kind = kind
	f.heli = true
	f.paint = flights.size()
	var pp: Vector3 = pad["local"]                                               # the pad's place in the field's frame
	f.stand = Vector3(pp.x, 0.0, pp.z)
	f.stand_h = 0.0
	f.route = heli_route(kind, f.stand)
	f.hold = float(delay)
	flights.append(f)
	_start_at(f, &"parked")


## The route of a plane out of its stand and back: pushback, taxi to the south end, line up on 36, roll, climb, a circuit over the plains, final, flare, roll-out, taxi in. Public so a test can walk it.
func plane_route(kind: StringName, stand: Vector3) -> Array[Dictionary]:
	var v := _speeds(kind)
	var sz := stand.z
	var r: Array[Dictionary] = []
	r.append(_wp(Vector3(stand.x, 0.0, sz), 0.0, 0.0, false, true, &"parked"))
	r.append(_wp(Vector3(1192.0, 0.0, sz), 2.5, 0.0, true, true, &"push"))
	r.append(_wp(Vector3(1203.0, 0.0, sz + 14.0), 5.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1210.0, 0.0, sz + 32.0), 9.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1210.0, 0.0, -195.0), 13.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1224.0, 0.0, -176.0), 7.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1250.0, 0.0, -170.0), 6.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1262.0, 0.0, -176.0), 4.0, 3.0, false, true, &"lineup"))
	r.append(_wp(Vector3(1262.0, 0.0, -330.0), float(v["vr"]) * 0.75, 0.0, false, true, &"roll"))
	r.append(_wp(Vector3(1262.0, 0.0, -480.0), float(v["vr"]) * 1.04, 0.0, false, true, &"roll"))
	r.append(_wp(Vector3(1262.0, 7.0, -640.0), float(v["climb"]), 0.0, false, false, &"climb"))
	r.append(_wp(Vector3(1262.0, 60.0, -1000.0), float(v["climb"]), 0.0, false, false, &"climb"))
	r.append(_wp(Vector3(1262.0, 140.0, -1380.0), float(v["climb"]), 0.0, false, false, &"circuit"))
	r.append(_wp(Vector3(1560.0, 190.0, -1520.0), float(v["climb"]), 0.0, false, false, &"circuit"))
	r.append(_wp(Vector3(1690.0, 215.0, -700.0), float(v["climb"]), 0.0, false, false, &"circuit"))
	r.append(_wp(Vector3(1650.0, 215.0, 800.0), float(v["climb"]), 0.0, false, false, &"circuit"))
	r.append(_wp(Vector3(1262.0, 150.0, 1560.0), float(v["app"]), 0.0, false, false, &"circuit"))
	r.append(_wp(Vector3(1262.0, 78.0, 700.0), float(v["app"]), 0.0, false, false, &"approach"))
	r.append(_wp(Vector3(1262.0, 25.0, 80.0), float(v["app"]), 0.0, false, false, &"approach"))
	r.append(_wp(Vector3(1262.0, 11.0, -120.0), float(v["td"]) * 1.03, 0.0, false, false, &"flare"))
	r.append(_wp(Vector3(1262.0, 0.0, -215.0), float(v["td"]), 0.0, false, true, &"touchdown"))
	r.append(_wp(Vector3(1262.0, 0.0, -400.0), 22.0, 0.0, false, true, &"rollout"))
	r.append(_wp(Vector3(1262.0, 0.0, -560.0), 12.0, 0.0, false, true, &"rollout"))
	r.append(_wp(Vector3(1246.0, 0.0, -585.0), 9.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1210.0, 0.0, -585.0), 9.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1210.0, 0.0, sz - 18.0), 11.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(1196.0, 0.0, sz), 5.0, 0.0, false, true, &"taxi"))
	r.append(_wp(Vector3(stand.x, 0.0, sz), 1.5, 0.0, false, true, &"park"))
	return r


## The route of a helicopter from its pad: wait with the rotor still, spool up, lift, patrol a loop over the east plain (the gunship and the transport go further, over the edge of the city),
## come back and set down on the same pad.
func heli_route(kind: StringName, pad: Vector3) -> Array[Dictionary]:
	var big := kind != &"heli"
	var r: Array[Dictionary] = []
	r.append(_wp(Vector3(pad.x, 0.0, pad.z), 0.0, 0.0, false, true, &"parked"))
	r.append(_wp(Vector3(pad.x, 0.0, pad.z), 0.0, 7.0, false, true, &"spool"))
	r.append(_wp(Vector3(pad.x, 55.0, pad.z), 7.0, 0.0, false, false, &"lift"))
	var loop: Array[Vector3] = [Vector3(1262.0, 85.0, -250.0), Vector3(1420.0, 95.0, -600.0), Vector3(1300.0, 110.0, -960.0), Vector3(1120.0, 100.0, -700.0)]
	if big:
		loop = [Vector3(1262.0, 110.0, -300.0), Vector3(1000.0, 140.0, -330.0), Vector3(880.0, 150.0, -720.0), Vector3(1250.0, 125.0, -1100.0), Vector3(1500.0, 120.0, -650.0)]
	for p in loop:
		r.append(_wp(p, 32.0 if big else 28.0, 0.0, false, false, &"patrol"))
	r.append(_wp(Vector3(pad.x + 30.0, 60.0, pad.z + 6.0), 14.0, 0.0, false, false, &"return"))
	r.append(_wp(Vector3(pad.x, 4.0, pad.z), 5.0, 0.0, false, false, &"descend"))
	r.append(_wp(Vector3(pad.x, 0.0, pad.z), 1.5, 0.0, false, true, &"park"))
	return r


static func _wp(p: Vector3, v: float, hold: float, rev: bool, ground: bool, phase: StringName) -> Dictionary:
	return {"p": p, "v": v, "hold": hold, "rev": rev, "ground": ground, "phase": phase}


## Put a flight where its `start` says: parked (at the stand), approach (on final, 600 m out), circuit (over the plains).
func _start_at(f: Flight, start: StringName) -> void:
	f.idx = 0
	f.pos = Vector3(f.stand.x, 0.0, f.stand.z)
	f.heading = f.stand_h
	f.speed = 0.0
	f.airborne = false
	f.phase = &"parked"
	f.rotor = 0.0
	f.pitch = 0.0
	f.roll = 0.0
	if start == &"parked":
		f.hold = maxf(f.hold, 1.0)
		return
	var want := &"approach" if start == &"approach" else &"circuit"
	for i in f.route.size():
		if f.route[i]["phase"] == want and (want == &"approach" or i >= 14):
			f.idx = i
			var wp: Vector3 = f.route[i]["p"]
			f.pos = wp
			f.heading = 0.0 if want == &"approach" else atan2(-(1650.0 - wp.x), -(800.0 - wp.z))
			f.speed = float(f.route[i]["v"])
			f.airborne = true
			f.phase = want
			f.hold = 0.0
			return


# --- the simulation ---------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var dt := delta * time_scale
	clock += dt
	_pt += delta
	var ppos := Vector3.INF
	var pl := Game.player as Node3D
	if is_instance_valid(pl):
		ppos = pl.global_position
	var ns := 0
	for f in flights:
		_step(f, dt)
		_update_node(f, ppos, delta)
		if f.lod and _specks != null:
			_set_speck(ns, f)
			ns += 1
	if _specks != null:
		_specks.multimesh.visible_instance_count = ns
		_specks.visible = ns > 0
	if _pt >= 0.25:
		_pt = 0.0
		_hijack_tick(ppos, 0.25)


## The whole simulation `secs` game seconds at once, in 0.1 s steps (a test, a returning player).
func fast_forward(secs: float) -> void:
	var t := 0.0
	while t < secs:
		for f in flights:
			_step(f, 0.1)
		t += 0.1
		clock += 0.1


func _step(f: Flight, dt: float) -> void:
	if f.gone > 0.0:
		f.gone -= dt
		if f.gone <= 0.0:
			f.hold = 8.0
			_start_at(f, &"parked")
		return
	if f.vehicle != null:
		return                                                                   # the hero's aircraft stands there: the flight waits
	f.cooldown = maxf(f.cooldown - dt, 0.0)
	if f.cross and f.idx >= f.route.size():                                      # a crosser at the end of its line: the next kind, a new line
		f.laps += 1
		f.kinds_flown[f.kind] = int(f.kinds_flown.get(f.kind, 0)) + 1
		_next_kind(f)
		_new_line(f)
		return
	if f.hold > 0.0:
		f.hold -= dt
		f.speed = move_toward(f.speed, 0.0, 6.0 * dt)
		if f.heli and f.hold_phase == &"spool":
			f.rotor = move_toward(f.rotor, 1.0, dt / 6.0)                        # the rotor comes up while the helicopter waits to lift
		if f.hold <= 0.0 and f.idx == 0:
			f.idx = 1                                                            # leave the stand
			if f.slot >= 0:
				departures += 1
		_attitude(f, dt, 0.0)
		return
	if f.idx >= f.route.size():                                                  # back at the stand: park for a while, then the same again
		f.idx = 0
		f.laps += 1
		f.kinds_flown[f.kind] = int(f.kinds_flown.get(f.kind, 0)) + 1
		_next_kind(f)
		f.hold = 15.0 + _rng.randf() * 40.0
		if f.slot >= 0:
			f.hold = maxf(until_departure(f.slot), 20.0)                         # w126-air: the timetable (at least 20 s at the gate)
		f.hold_phase = &"parked"
		f.phase = &"parked"
		f.rotor = 0.0
		f.speed = 0.0
		return
	var wp: Dictionary = f.route[f.idx]
	var tgt: Vector3 = wp["p"]
	var tv := float(wp["v"])
	var ground: bool = wp["ground"]
	var ph: StringName = wp["phase"]
	if separate and not f.heli and not f.cross and (ph == &"approach" or ph == &"flare") and f.pos.y > 3.0 and (runway_vehicle() != "" or _landing_conflict(f)):
		for i in f.route.size():                                                 # something stands on the runway (the RUNWAY 09 plane, the hero's aircraft): go around
			if f.route[i]["phase"] == &"circuit":
				f.idx = i
				go_arounds += 1
				return
	if separate and not f.heli and not f.cross and _must_wait(f, ground, ph):
		f.phase = ph
		f.speed = move_toward(f.speed, 0.0, 9.0 * dt)
		_attitude(f, dt, 0.0)
		return
	var clear_h := tgt.y
	if not ground and not f.heli and ph == &"circuit":                            # the circuit never flies lower than 70 m over whatever is under it
		var tw := Airport.to_world(tgt)
		clear_h = maxf(tgt.y, TerrainHeight.height_at(tw.x, tw.z) + 70.0)
	var to := Vector3(tgt.x - f.pos.x, 0.0, tgt.z - f.pos.z)
	var hd := to.length()
	f.phase = ph
	var rev: bool = wp["rev"]
	var dir := to / hd if hd > 0.001 else Vector3.ZERO
	var dh := 0.0
	if not rev and hd > 0.001:
		dh = wrapf(atan2(-dir.x, -dir.z) - f.heading, -PI, PI)
		if f.heli and hd < 8.0:
			dh = 0.0
	# the speed: it accelerates and brakes at a plausible rate towards the waypoint's speed, crawls through a sharp turn on the ground and slows for a stop
	var rate := 6.0 if (f.heli or not ground) else 3.2
	var goal := tv
	if f.heli and ph in [&"lift", &"descend", &"park", &"return"]:
		goal = minf(tv, maxf(1.5, hd * 0.55))
	elif ground and tv < 3.0 and hd < 40.0:
		goal = maxf(tv, hd * 0.2)
	if ground and not f.heli and absf(dh) > 0.4:
		goal = minf(goal, 4.0)
	f.speed = move_toward(f.speed, goal, rate * dt)
	if f.heli:
		f.rotor = move_toward(f.rotor, 1.0, dt / 4.0)
	var arrive := maxf(2.5, f.speed * dt * 1.6)
	if hd <= arrive:
		f.pos.x = tgt.x
		f.pos.z = tgt.z
		if not ground:
			f.pos.y = clear_h
		f.idx += 1
		f.hold = float(wp["hold"])
		f.hold_phase = ph
		_track(f)
		return
	var turn := 0.6 if (ground and not f.heli) else (0.45 if not f.heli else 1.2)
	if rev:
		f.pos += dir * minf(f.speed, 3.0) * dt                                   # a pushback: the nose stays where it is
	else:
		f.heading += clampf(dh, -turn * dt, turn * dt)
		f.pos += dir * f.speed * dt
	# the height: a straight line to the waypoint's height over the rest of the distance
	var vy := 0.0
	if not ground or f.pos.y > 0.01:
		var t_left := hd / maxf(f.speed, 2.0)
		vy = clampf((clear_h - f.pos.y) / maxf(t_left, 0.2), -14.0, 16.0 if not f.heli else 7.0)
		f.pos.y = maxf(f.pos.y + vy * dt, 0.0)
	_track(f)
	_attitude(f, dt, vy)


## w126-critic: GROUND SEPARATION. A plane on the ground stops while another aircraft (a flight, or a real vehicle such as a promoted flight, the RUNWAY 09 plane or the hero's
## aircraft) stands ahead of it on its way, and a departure waits off the runway (before it lines up) while the runway is in use: something lines up, rolls, climbs out low,
## is on final or rolls out. Before this, an airliner lined up under a bizjet touching down, took off 3 m over a bizjet rolling out, and a light plane taxied into an airliner
## that waited for the hero (two aircraft in one spot for 15 s). `separate` = false (W126C_OLD=1) is the wave 126 traffic.
static var separate := OS.get_environment("W126C_OLD") != "1"
const RUNWAY_BUSY: Array[StringName] = [&"lineup", &"roll", &"flare", &"touchdown", &"rollout", &"approach"]


static func _len_of(kind: StringName) -> float:
	var sp: Dictionary = VehicleSpecs.SPECS.get(kind, {})
	return float(sp.get("len", 12.0))


func _must_wait(f: Flight, ground: bool, ph: StringName) -> bool:
	if f.idx >= 1 and f.idx + 1 < f.route.size() and f.route[f.idx + 1]["phase"] == &"lineup":
		var prev: Vector3 = f.route[f.idx - 1]["p"]
		if Vector2(f.pos.x - prev.x, f.pos.z - prev.z).length() < 3.0 and runway_busy(f):
			return true                                                          # hold short of the runway
	var n := f.route.size()
	if f.idx == n - 4 and not f.cross and stand_taken(f):
		var nx: Vector3 = f.route[f.idx]["p"]
		if Vector2(f.pos.x - nx.x, f.pos.z - nx.z).length() < 14.0:
			return true                                                          # its stand is not free yet (the other airliner of the gate): wait 14 m short of the taxiway corner
	if not ground or ph == &"parked" or ph == &"push" or f.pos.y > 0.5:
		return false                                                             # only on the wheels (a flight in the flare never stops in the air)
	return blocked_ahead(f) != ""


## A landing `f` would come down on another plane: one lines up, rolls, touches down or rolls out, or lands just ahead of it (less than 900 m ahead on the approach).
func _landing_conflict(f: Flight) -> bool:
	for g in flights:
		if g == f or g.heli or g.cross or g.gone > 0.0 or g.vehicle != null:
			continue
		if g.phase in [&"lineup", &"roll", &"touchdown", &"rollout"]:
			return true
		if g.phase in [&"approach", &"flare"] and g.pos.z < f.pos.z and f.pos.z - g.pos.z < 900.0:
			return true
	return false


## Another flight of the same stand has not left it yet (parked, pushing back, or on its first taxi legs).
func stand_taken(f: Flight) -> bool:
	for g in flights:
		if g != f and not g.heli and g.gone <= 0.0 and g.stand.distance_to(f.stand) < 5.0 and g.idx <= 3:
			return true
	return false


var go_arounds := 0                       ## landings broken off because the runway was not free (tests)


## The kind of a real vehicle standing on the runway (on its wheels), "" when the runway is free.
func runway_vehicle() -> String:
	var vm := Game.vehicles as VehicleManager
	if vm == null:
		return ""
	for v in vm.list:
		if not v.active or v.dead or (v.craft != null and v.craft.airborne):
			continue
		var lp := Airport.to_local(v.global_position)
		if absf(lp.x - Airport.RUNWAY_X) < Airport.RUNWAY_W * 0.5 + 3.0 and lp.z > Airport.RUNWAY_N - 5.0 and lp.z < Airport.RUNWAY_S + 5.0:
			return String(v.kind)
	return ""


## Something in use on the runway for a departure `f` (another plane lining up, rolling, climbing out under 40 m, on final, flaring, touching down, rolling out).
func runway_busy(f: Flight) -> bool:
	for g in flights:
		if g == f or g.heli or g.cross or g.gone > 0.0 or g.vehicle != null:
			continue
		if g.phase in RUNWAY_BUSY or (g.phase == &"climb" and g.pos.y < 40.0):
			return true
	return runway_vehicle() != ""


## What stands ahead of `f` on the ground (in its lane: sideways closer than both half wing spans plus 3 m, ahead closer than both half lengths plus 12 m): a flight's kind or a
## vehicle's, "" when the way is free. Two planes nose to nose: the one earlier in the list goes first.
func blocked_ahead(f: Flight) -> String:
	var fwd := Vector2(-sin(f.heading), -cos(f.heading))
	var lf := _len_of(f.kind)
	var wf := _span_of(f.kind)
	var me := flights.find(f)
	for i in flights.size():
		var g := flights[i]
		if g == f or g.gone > 0.0 or g.vehicle != null or g.pos.y > 4.0:
			continue
		var rel := Vector2(g.pos.x - f.pos.x, g.pos.z - f.pos.z)
		if not _in_lane(rel, fwd, lf, wf, _len_of(g.kind), _span_of(g.kind)):
			continue
		var gf := Vector2(-sin(g.heading), -cos(g.heading))
		if (-rel).dot(gf) > 0.0 and _in_lane(-rel, gf, _len_of(g.kind), _span_of(g.kind), lf, wf) and i > me and g.speed > 0.5:
			continue                                                             # nose to nose: the earlier one in the list goes
		return String(g.kind)
	var vm := Game.vehicles as VehicleManager
	if vm != null:
		for v in vm.list:
			if not v.active or v.dead:
				continue
			var lp := Airport.to_local(v.global_position)
			var rel2 := Vector2(lp.x - f.pos.x, lp.z - f.pos.z)
			if _in_lane(rel2, fwd, lf, wf, float(v.spec.get("len", 4.0)), float(v.spec.get("span", v.spec.get("rotor_r", 1.0) * 2.0 if v.spec.has("rotor_r") else v.spec.get("wid", 2.0)))):
				return String(v.kind)
	return ""


static func _span_of(kind: StringName) -> float:
	var sp: Dictionary = VehicleSpecs.SPECS.get(kind, {})
	return float(sp.get("span", float(sp.get("rotor_r", 0.0)) * 2.0 if sp.has("rotor_r") else float(sp.get("wid", 3.0))))


static func _in_lane(rel: Vector2, fwd: Vector2, la: float, wa: float, lb: float, wb: float) -> bool:
	var ahead := rel.dot(fwd)
	var side := absf(rel.cross(fwd))
	return ahead > 0.0 and ahead < 0.5 * (la + lb) + 12.0 and side < 0.5 * (wa + wb) + 3.0


## Take-offs, landings and the clearance over the terrain.
func _track(f: Flight) -> void:
	var was := f.airborne
	f.airborne = f.pos.y > (1.0 if f.heli else 1.5)
	if f.airborne and not was:
		f.takeoffs += 1
	elif was and not f.airborne:
		f.landings += 1
	if f.airborne and f.phase in [&"circuit", &"patrol", &"return"]:                # the cruise legs (take-off, flare and landing are low by nature)
		var wp := Airport.to_world(f.pos)
		var th := 0.0
		if absf(wp.x) > TerrainHeight.CITY_HALF or absf(wp.z) > TerrainHeight.CITY_HALF:
			th = TerrainHeight.height_at(wp.x, wp.z)
		f.min_clear = minf(f.min_clear, f.pos.y - th)


## The pitch and the bank of the picture from what the flight does.
func _attitude(f: Flight, dt: float, vy: float) -> void:
	var tp := 0.0
	var tr := 0.0
	if f.heli:
		tp = -clampf(f.speed / 40.0, 0.0, 0.8) * 0.22
	else:
		if f.airborne:
			tp = clampf(vy / maxf(f.speed, 15.0), -0.3, 0.3)
		elif f.phase in [&"roll", &"touchdown", &"rollout"]:
			tp = 0.0
		if f.phase == &"flare":
			tp = 0.1
	var dh := wrapf(f.heading - _last_heading(f), -PI, PI) / maxf(dt, 0.001)
	tr = clampf(-dh * (0.6 if not f.heli else 0.5), -0.5, 0.5) if f.airborne else 0.0
	f.pitch = lerpf(f.pitch, tp, 1.0 - exp(-3.0 * dt))
	f.roll = lerpf(f.roll, tr, 1.0 - exp(-2.5 * dt))
	_set_last_heading(f)


var _lh := {}


func _last_heading(f: Flight) -> float:
	return float(_lh.get(f.id, f.heading))


func _set_last_heading(f: Flight) -> void:
	_lh[f.id] = f.heading


# --- the pictures -----------------------------------------------------------------------------------------------------------------------

func _update_node(f: Flight, ppos: Vector3, delta: float) -> void:
	var wp := Airport.to_world(f.pos)
	var d := INF
	if ppos.is_finite():
		d = Vector2(ppos.x - wp.x, ppos.z - wp.z).length()
	var want := d < SHOW and f.gone <= 0.0 and f.vehicle == null
	f.lod = false
	if roster_on:
		if want and d > LOD_R and f.airborne:
			want = false
			f.lod = true                                                         # far and in the air: a speck of the shared MultiMesh
			f.wp_cache = Vector3(wp.x, f.pos.y + (TerrainHeight.height_at(wp.x, wp.z) if (absf(wp.x) > TerrainHeight.CITY_HALF or absf(wp.z) > TerrainHeight.CITY_HALF) else 0.0), wp.z)
		if f.node == null and want:
			f.node = _take_node(f.kind, f.paint)
			if f.node != null:
				f.node.name = String(f.id)
		elif f.node != null and not want:
			_drop_node(f)
	elif f.node == null and want:
		f.node = AircraftScenery.make(f.kind, f.paint)
		if f.node != null:
			f.node.name = String(f.id)
			add_child(f.node)
	elif f.node != null and (d > HIDE or f.gone > 0.0 or f.vehicle != null):
		f.node.queue_free()
		f.node = null
	if f.node == null or not is_instance_valid(f.node):
		return
	var b := Basis(Vector3.UP, f.heading) * Basis(Vector3.RIGHT, f.pitch) * Basis(Vector3.BACK, f.roll)
	var gy := 0.0
	if absf(wp.x) > TerrainHeight.CITY_HALF or absf(wp.z) > TerrainHeight.CITY_HALF:
		gy = TerrainHeight.height_at(wp.x, wp.z)
	f.node.global_transform = Transform3D(Airport.FRAME.basis * b, Vector3(wp.x, f.pos.y + gy, wp.z))
	if f.heli:
		f.ang = fposmod(f.ang + f.rotor * 38.0 * delta, TAU)
		AircraftScenery.spin(f.node, f.rotor, f.ang)


## w126-air: a model of `kind` from the pool (or a new one).
func _take_node(kind: StringName, paint: int) -> Node3D:
	var arr: Array = _pool.get(kind, [])
	while not arr.is_empty():
		var n := arr.pop_back() as Node3D
		if is_instance_valid(n):
			n.visible = true
			pool_reused += 1
			return n
	var m := AircraftScenery.make(kind, paint)
	if m != null:
		models_built += 1
		m.set_meta(&"kind", kind)
		add_child(m)
	return m


## The flight's model goes back to the pool (hidden), or is freed when the pool of its kind is full.
func _drop_node(f: Flight) -> void:
	if f.node == null:
		return
	if is_instance_valid(f.node):
		var arr: Array = _pool.get(f.node_kind(), [])
		if roster_on and arr.size() < POOL_KEEP:
			f.node.visible = false
			arr.append(f.node)
			_pool[f.node_kind()] = arr
		else:
			f.node.queue_free()
	f.node = null


func _set_speck(i: int, f: Flight) -> void:
	var sz := 3.0 + float(VehicleSpecs.SPECS.get(f.kind, {}).get("len", 10.0)) * 0.45
	_specks.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(sz, sz, sz)), f.wp_cache))


func pooled_count() -> int:
	var n := 0
	for k: StringName in _pool:
		n += (_pool[k] as Array).size()
	return n


func speck_count() -> int:
	return _specks.multimesh.visible_instance_count if _specks != null else 0


# --- hijack -----------------------------------------------------------------------------------------------------------------------------

## A grounded flight near the hero on foot becomes a real aircraft with a pilot in it; one that was not taken goes back to the flight plan when the hero walks away or waits too long.
func _hijack_tick(ppos: Vector3, dt: float) -> void:
	var vm := Game.vehicles as VehicleManager
	if vm == null or not is_instance_valid(Game.player) or not ppos.is_finite():
		return
	var on_foot: bool = Game.player.get(&"vehicle") == null
	for f in flights:
		if f.vehicle != null:
			var v := f.vehicle
			if not is_instance_valid(v) or not v.active or v.dead:
				f.vehicle = null
				f.gone = 60.0
				continue
			if v.driver_is_player:                                                # taken: the pilot was thrown out, the flight stays gone for a while
				f.vehicle = null
				f.gone = 90.0
				hijacked += 1
				continue
			f.promote_t += dt
			var far := Vector2(ppos.x - v.global_position.x, ppos.z - v.global_position.z).length() > DEMOTE_R
			if far or f.promote_t > PROMOTE_MAX or not on_foot:
				_demote(f, vm)
			continue
		if f.gone > 0.0 or f.cooldown > 0.0 or not on_foot or not Game.is_playing():
			continue
		if f.pos.y > 2.0 or f.speed > 14.0:
			continue                                                              # in the air or rolling fast: nobody can reach it
		var fw := Airport.to_world(f.pos)
		var flat := Vector2(ppos.x - fw.x, ppos.z - fw.z).length()
		if flat > PROMOTE_R or absf(ppos.y - f.pos.y) > 4.0 or f.phase in [&"roll", &"touchdown"]:
			continue
		_promote(f, vm)


func _promote(f: Flight, vm: VehicleManager) -> void:
	var v := vm.spawn_parked(f.kind, Airport.to_world(Vector3(f.pos.x, 0.0, f.pos.z)), Airport.heading_world(f.heading))
	if v == null:
		f.cooldown = 4.0
		return
	v.ai = true                                                                  # a pilot is at the controls (VehicleManager.enter makes it a hijack)
	v.set_meta(&"hold", true)
	v.set_meta(&"air_flight", f.id)
	v.craft.spool = f.rotor
	v.craft.airborne = false
	v.vel = Vector3.ZERO
	v.speed = 0.0
	f.vehicle = v
	f.promote_t = 0.0
	if f.node != null:
		_drop_node(f)


func _demote(f: Flight, vm: VehicleManager) -> void:
	var v := f.vehicle
	if is_instance_valid(v):
		var lp := Airport.to_local(v.global_position)
		f.pos = Vector3(lp.x, 0.0, lp.z)
		f.heading = wrapf(v.heading + PI * 0.5, -PI, PI)
		v.remove_meta(&"hold")
		v.remove_meta(&"air_flight")
		v.ai = false
		vm._release(v)
	f.vehicle = null
	f.cooldown = 8.0


func promoted_count() -> int:
	var n := 0
	for f in flights:
		if f.vehicle != null:
			n += 1
	return n


func stats() -> Dictionary:
	var air := 0
	var tk := 0
	var ld := 0
	var laps := 0
	var mc := 1.0e9
	for f in flights:
		if f.airborne:
			air += 1
		tk += f.takeoffs
		ld += f.landings
		laps += f.laps
		mc = minf(mc, f.min_clear)
	return {"flights": flights.size(), "airborne": air, "takeoffs": tk, "landings": ld, "laps": laps, "promoted": promoted_count(), "hijacked": hijacked, "min_clear": mc}
