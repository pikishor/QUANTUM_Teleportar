class_name ContractTypes
extends RefCounted
## Data and pure rules of the contracts (scripts/missions/contracts.gd): the six procedural mission kinds, which kinds each story chapter favours, payouts and
## time limits. Nothing here touches the scene tree, so tests can call it freely.
##
## Kinds: officer (kill a marked Vael officer), hack (hold a node's ring while drones attack), chase (wreck a fleeing car), courier (timed delivery along a route
## line), survive (hold a rift anchor through waves), drones (destroy drones with quantum link kills).

const KINDS: Array[StringName] = [&"officer", &"hack", &"chase", &"courier", &"survive", &"drones"]

const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.3, 0.28)
const CYAN := Color(0.3, 0.94, 1.0)

## title: HUD / banner name · base: credits at sector 1 · time: seconds at sector 1 (courier: computed from the route) · color: marker colour
const DATA := {
	&"officer": {"title": "ELIMINATE OFFICER", "base": 320, "time": 210.0, "color": RED, "upgrade": true},
	&"hack": {"title": "HACK NODE", "base": 260, "time": 150.0, "color": CYAN, "upgrade": false},
	&"chase": {"title": "RUN DOWN TARGET", "base": 300, "time": 130.0, "color": AMBER, "upgrade": false},
	&"courier": {"title": "COURIER RUN", "base": 220, "time": 90.0, "color": AMBER, "upgrade": false},
	&"survive": {"title": "HOLD THE ANCHOR", "base": 420, "time": 240.0, "color": CYAN, "upgrade": true},
	&"drones": {"title": "LINK KILL TRIAL", "base": 280, "time": 150.0, "color": CYAN, "upgrade": false},
}

## Weight of each kind per chapter (index = chapter; the last row covers every later sector). Every kind has weight >= 1 in every chapter, the story decides
## which ones come up most: Glass District teaches the link, the Harvest Floor is relay nodes, Bridge Arcade is traffic, the Gate is sieges.
const WEIGHTS: Array[Dictionary] = [
	{&"officer": 4, &"hack": 1, &"chase": 1, &"courier": 3, &"survive": 1, &"drones": 1},
	{&"officer": 2, &"hack": 2, &"chase": 1, &"courier": 2, &"survive": 1, &"drones": 4},
	{&"officer": 2, &"hack": 4, &"chase": 1, &"courier": 1, &"survive": 3, &"drones": 2},
	{&"officer": 2, &"hack": 1, &"chase": 4, &"courier": 3, &"survive": 1, &"drones": 2},
	{&"officer": 3, &"hack": 2, &"chase": 2, &"courier": 1, &"survive": 4, &"drones": 2},
	{&"officer": 2, &"hack": 2, &"chase": 2, &"courier": 2, &"survive": 2, &"drones": 2},
]

const COURIER_SPEED := 8.5           ## metres per second the time limit assumes (sprinting on foot)
const COURIER_SLACK := 14.0          ## seconds on top of the route time


static func title(kind: StringName) -> String:
	return str(DATA[kind]["title"])


static func color(kind: StringName) -> Color:
	return DATA[kind]["color"]


static func weights(chapter: int) -> Dictionary:
	return WEIGHTS[clampi(chapter, 0, WEIGHTS.size() - 1)]


## A weighted random kind for the chapter. `exclude` (the previous kind) is skipped when another choice exists; kinds in `banned` never come up
## (the chase needs a car within reach, for instance).
static func pick(chapter: int, rng: RandomNumberGenerator, exclude := &"", banned: Array = []) -> StringName:
	var w := weights(chapter)
	var total := 0.0
	for k: StringName in KINDS:
		if k != exclude and not k in banned:
			total += float(w[k])
	if total <= 0.0:
		for k: StringName in KINDS:
			if not k in banned:
				return k
		return &"officer"
	var r := rng.randf() * total
	for k: StringName in KINDS:
		if k == exclude or k in banned:
			continue
		r -= float(w[k])
		if r <= 0.0:
			return k
	return &"officer"


## What a finished contract pays. `bonus` is the reputation payout factor (Progress.rep_bonus), `speed` 0..1 the unused share of the time limit
## (a courier or a fast kill pays up to +25 % extra). credits = base * sector factor * (1 + bonus) * (1 + 0.25 speed).
static func reward(kind: StringName, chapter: int, bonus := 0.0, speed := 0.0) -> Dictionary:
	var diff := Progress.difficulty(chapter)
	var credits := int(roundf(float(DATA[kind]["base"]) * float(diff["reward"]) * (1.0 + bonus) * (1.0 + 0.25 * clampf(speed, 0.0, 1.0)) / 5.0)) * 5
	return {"credits": credits, "energy": 100.0, "heal": 40.0, "upgrade": bool(DATA[kind]["upgrade"]) and chapter >= 1, "rep": 8}


## Time limit in seconds: the base time scaled by the sector's tightening; the courier's comes from the route length.
static func time_limit(kind: StringName, chapter: int, route_len := 0.0) -> float:
	var diff := Progress.difficulty(chapter)
	if kind == &"courier":
		return (route_len / COURIER_SPEED + COURIER_SLACK) * float(diff["time"])
	return float(DATA[kind]["time"]) * float(diff["time"])


## Enemy counts scale with the sector: how many foes a wave / a node attack / the officer's guard has.
static func count(kind: StringName, chapter: int, wave := 0) -> int:
	var extra := int(Progress.difficulty(chapter)["extra"])
	match kind:
		&"officer": return 2 + extra                    ## guards around the officer
		&"hack": return 2 + extra                       ## drones per attack pulse
		&"survive": return 3 + wave + extra             ## enemies in a wave
		&"drones": return 3 + mini(extra, 2)            ## link kills needed
	return 0


## Rough shortest drive-or-run path length between two points on the street grid (Manhattan, which is what the route line follows).
static func route_length(a: Vector3, b: Vector3) -> float:
	return absf(a.x - b.x) + absf(a.z - b.z)
