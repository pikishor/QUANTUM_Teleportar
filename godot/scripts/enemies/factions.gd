class_name Factions
extends RefCounted
## FACTIONS: three armed groups share the city. VAEL (Vael troopers: disciplined, towers), GANGS (street gangs: fast, close, market and foundry), DRONES (rogue drones:
## far-sensing flyers, rain slums). Every district has a primary and a secondary faction (TERRITORY); an enemy takes the camp of the patrol or reinforcement slot that made it
## (Drone.camp), with its own rim colour and its own numbers (BEHAVIOUR: speed, sight). Reputation per faction (Progress.faction_rep, -100..100, saved in [faction]) gives a
## status: HOSTILE (<= HOSTILE_AT), NEUTRAL, ALLIED (>= ALLIED_AT). Effects (all pure helpers below, the hooks are in EnemyManager, Drone, Progress, Contracts, SideMissions, Hud):
##   patrols    allied camps stand about unaware (aware_dist 0, ignore heat); hostile camps see 1.4x as far and add one reinforcement slot in their district.
##   prices     the shop price of the faction that holds the hero's district: allied -10 %, hostile +15 % (Progress.shop_discount).
##   missions   a side job has a client camp (JOB_CLIENT): hostile with it and the job is closed; allied pays +15 %. Contracts stop being offered in a hostile district.
##   reputation a kill costs the victim camp 1 (6 for an allied one) and gives its rival 0.5; a finished job for a client gives it +5.
## Everything here is data and static functions: no nodes, no textures, no draw calls.

const Districts := preload("res://scripts/world/city_districts.gd")
const VAEL := &"vael"
const GANG := &"gang"
const DRONES := &"drones"
const IDS: Array[StringName] = [VAEL, GANG, DRONES]
const TITLES := {&"vael": "VAEL", &"gang": "GANGS", &"drones": "DRONES"}
const COLORS := {&"vael": Color(1.0, 0.22, 0.2), &"gang": Color(1.0, 0.72, 0.15), &"drones": Color(0.35, 0.9, 1.0)}
const RIVAL := {&"vael": &"gang", &"gang": &"vael", &"drones": &"vael"}

const REP_MIN := -100.0
const REP_MAX := 100.0
const HOSTILE_AT := -25.0
const ALLIED_AT := 40.0
const KILL_PENALTY := 1.0
const KILL_PENALTY_ALLIED := 6.0
const RIVAL_GAIN := 0.5
const JOB_REP := 5.0
const PRICE_ALLIED := 0.10               ## discount
const PRICE_HOSTILE := -0.15             ## negative discount = surcharge
const PAY_ALLIED := 0.15
const SECONDARY_SHARE := 0.25            ## share of patrol / reinforcement slots that belong to the district's secondary camp

enum Status { HOSTILE, NEUTRAL, ALLIED }
const STATUS_NAMES: Array[String] = ["HOSTILE", "NEUTRAL", "ALLIED"]

## Districts (CityDistricts: 0 market, 1 foundry, 2 slums, 3 towers) -> [primary, secondary].
const TERRITORY: Array = [[GANG, VAEL], [GANG, DRONES], [DRONES, GANG], [VAEL, DRONES]]

## Behaviour numbers per camp: speed (x walking / running speed), sight (x aware_dist), fire (x seconds between volleys, read by the HUD description only).
const BEHAVIOUR := {
	&"vael": {"speed": 1.0, "sight": 1.0, "label": "DISCIPLINED"},
	&"gang": {"speed": 1.15, "sight": 0.85, "label": "RUSHING"},
	&"drones": {"speed": 1.0, "sight": 1.25, "label": "SWARMING"},
}

## Client camp of a side job (jobs not listed are open to everyone).
const JOB_CLIENT := {
	&"turf": GANG, &"smuggler": GANG, &"car_theft": GANG, &"courier": GANG, &"heist": GANG,
	&"bounty": VAEL, &"hostage": VAEL, &"data_courier": VAEL, &"sniper": VAEL, &"hunt": VAEL,
	&"swarm": DRONES, &"anomaly": DRONES, &"blackout": DRONES, &"relay": DRONES,
}

## Elite squad per camp (Wanted level 5) and the type of a roadblock guard / a hunter drone.
const ELITES := {&"vael": [&"shield", &"sniper", &"shield"], &"gang": [&"brute", &"flanker", &"flanker"], &"drones": [&"heavy", &"heavy", &"sentinel"]}
const GUARD := {&"vael": &"operative", &"gang": &"operative", &"drones": &"sentinel"}


static func title(f: StringName) -> String:
	return String(TITLES.get(f, "?"))


static func color(f: StringName) -> Color:
	return COLORS.get(f, Color(1, 1, 1))


static func is_camp(f: StringName) -> bool:
	return IDS.has(f)


# --- territory -----------------------------------------------------------------------------------------------------

static func primary(district: int) -> StringName:
	return TERRITORY[clampi(district, 0, TERRITORY.size() - 1)][0]


static func secondary(district: int) -> StringName:
	return TERRITORY[clampi(district, 0, TERRITORY.size() - 1)][1]


## The camp that holds the ground at a world position.
static func at(pos: Vector3) -> StringName:
	return primary(Districts.at_v(pos))


## The camp a slot at `pos` belongs to for a roll 0..1 (secondary camp for the lowest SECONDARY_SHARE).
static func camp_for(pos: Vector3, roll: float) -> StringName:
	var d := Districts.at_v(pos)
	return secondary(d) if roll < SECONDARY_SHARE else primary(d)


static func is_drone_type(type: StringName) -> bool:
	var c := EnemyTypes.get_cfg(type)
	return bool(c.get("drone", false)) and not c.has("humanoid")


## The camp an enemy of `type` spawned at `pos` takes. Drones are always DRONES; a trooper takes `want` (vael or gang), else the ground's primary camp,
## else the secondary one where the primary is DRONES.
static func assign(type: StringName, pos: Vector3, want: StringName = &"") -> StringName:
	if is_drone_type(type):
		return DRONES
	if want == VAEL or want == GANG:
		return want
	var d := Districts.at_v(pos)
	var p := primary(d)
	return p if p != DRONES else secondary(d)


## A slot rolled for `camp` as a type that camp fields: drones become sentinels / heavies, troopers stay troopers (a drone type turns into an operative or a flanker).
static func fit_type(type: StringName, camp: StringName, chapter := 0) -> StringName:
	if camp == DRONES:
		if is_drone_type(type):
			return type
		return &"heavy" if EnemyTypes.get_cfg(type).get("role", &"") in [&"brute", &"shield"] else &"sentinel"
	if is_drone_type(type):
		return &"flanker" if (camp == GANG and chapter >= 1 and type == &"striker") else &"operative"
	return type


# --- reputation ----------------------------------------------------------------------------------------------------

static func rep(prog: Object, f: StringName) -> float:
	if prog == null or not is_camp(f):
		return 0.0
	var d: Variant = prog.get("faction_rep")
	return float((d as Dictionary).get(f, 0.0)) if d is Dictionary else 0.0


static func status_of(value: float) -> int:
	if value <= HOSTILE_AT:
		return Status.HOSTILE
	if value >= ALLIED_AT:
		return Status.ALLIED
	return Status.NEUTRAL


static func status(prog: Object, f: StringName) -> int:
	return status_of(rep(prog, f))


static func status_name(prog: Object, f: StringName) -> String:
	return STATUS_NAMES[status(prog, f)]


## Moves a camp's reputation (clamped). Returns the new value.
static func add_rep(prog: Object, f: StringName, n: float) -> float:
	if prog == null or not is_camp(f) or n == 0.0:
		return rep(prog, f)
	var d: Dictionary = prog.get("faction_rep")
	var before := status(prog, f)
	d[f] = snappedf(clampf(float(d.get(f, 0.0)) + n, REP_MIN, REP_MAX), 0.01)
	if status(prog, f) != before and Game.is_playing():
		Game.say("%s: %s" % [title(f), STATUS_NAMES[status(prog, f)]], 2.5)
	if prog.has_signal(&"changed"):
		prog.emit_signal(&"changed")
	return float(d[f])


## A camp member died by the hero's hand.
static func on_kill(prog: Object, camp: StringName) -> void:
	if not is_camp(camp) or prog == null:
		return
	add_rep(prog, camp, -(KILL_PENALTY_ALLIED if status(prog, camp) == Status.ALLIED else KILL_PENALTY))
	add_rep(prog, RIVAL[camp], RIVAL_GAIN)


# --- effects -------------------------------------------------------------------------------------------------------

## Sight range factor of an enemy of the camp (0 for an allied camp that has not been provoked).
static func sight_mult(prog: Object, camp: StringName) -> float:
	if not is_camp(camp):
		return 1.0
	match status(prog, camp):
		Status.ALLIED:
			return 0.0
		Status.HOSTILE:
			return 1.4 * float(BEHAVIOUR[camp]["sight"])
	return float(BEHAVIOUR[camp]["sight"])


static func speed_mult(camp: StringName) -> float:
	return float(BEHAVIOUR[camp]["speed"]) if BEHAVIOUR.has(camp) else 1.0


## Extra reinforcement slots while the camp that holds the hero's ground is hostile.
static func extra_slots(prog: Object, pos: Vector3) -> int:
	return 1 if status(prog, at(pos)) == Status.HOSTILE else 0


## Shop discount (negative: surcharge) from the faction of the hero's district.
static func price_discount(prog: Object) -> float:
	if prog == null or not is_instance_valid(Game.player):
		return 0.0
	match status(prog, at((Game.player as Node3D).global_position)):
		Status.ALLIED:
			return PRICE_ALLIED
		Status.HOSTILE:
			return PRICE_HOSTILE
	return 0.0


static func job_client(mid: StringName) -> StringName:
	return JOB_CLIENT.get(mid, &"")


## A side job is open unless its client camp is hostile.
static func job_open(prog: Object, mid: StringName) -> bool:
	var c := job_client(mid)
	return c == &"" or status(prog, c) != Status.HOSTILE


## Pay factor of a side job (allied client +15 %).
static func pay_mult(prog: Object, mid: StringName) -> float:
	var c := job_client(mid)
	return 1.0 + PAY_ALLIED if c != &"" and status(prog, c) == Status.ALLIED else 1.0


## Contracts are not offered where the ground's camp is hostile.
static func contracts_open(prog: Object, pos: Vector3) -> bool:
	return status(prog, at(pos)) != Status.HOSTILE


## Applies a camp to an enemy: tags, sight, speed and the rim colour of its camp. Called by EnemyManager.spawn after the drone is activated.
static func apply(d: Drone, prog: Object, camp: StringName, passive_ok := true) -> void:
	d.camp = camp
	d.camp_speed = speed_mult(camp)
	var m := sight_mult(prog, camp)
	d.friendly = false
	if m <= 0.0:
		if passive_ok and not d.aware:
			d.friendly = true
			d.aware_dist = 0.0
	else:
		d.aware_dist = Drone.AWARE_DIST * m
	if d.model != null and d._camp_look != camp:
		var first := d._camp_look == &""
		d._camp_look = camp
		if camp == VAEL and first:
			return
		EnemyLook.apply_rim(d.model, EnemyLook.code_color(d.cfg) if camp == VAEL else color(camp), Game.quality)
