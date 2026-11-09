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

static var instance: AirTraffic = null

var flights: Array[Flight] = []
var hijacked := 0
var time_scale := 1.0
var _pt := 0.0
var _rng := RandomNumberGenerator.new()


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
	_pt += delta
	var ppos := Vector3.INF
	var pl := Game.player as Node3D
	if is_instance_valid(pl):
		ppos = pl.global_position
	for f in flights:
		_step(f, dt)
		_update_node(f, ppos, delta)
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
	if f.hold > 0.0:
		f.hold -= dt
		f.speed = move_toward(f.speed, 0.0, 6.0 * dt)
		if f.heli and f.hold_phase == &"spool":
			f.rotor = move_toward(f.rotor, 1.0, dt / 6.0)                        # the rotor comes up while the helicopter waits to lift
		if f.hold <= 0.0 and f.idx == 0:
			f.idx = 1                                                            # leave the stand
		_attitude(f, dt, 0.0)
		return
	if f.idx >= f.route.size():                                                  # back at the stand: park for a while, then the same again
		f.idx = 0
		f.laps += 1
		f.hold = 15.0 + _rng.randf() * 40.0
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
	if f.node == null and want:
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
		f.node.queue_free()
		f.node = null


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
