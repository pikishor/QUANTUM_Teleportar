class_name ChaseScripts
extends RefCounted
## Pure data and rules of the six vehicle chase set pieces (wave 68). The runner is scripts/missions/chase_runner.gd (Game.missions.chases); nothing here touches the scene tree.
##
## CHASES (one dictionary per set piece, `mode` picks the rule set of the runner):
##   pursue   a fleeing traffic car (+ `guards` convoy cars) drives off along a road; ram / shoot it down to `DISABLE` of its hit points; lose it (gap > `lose` m for `lose_s` s) and it fails.
##   escape   a net of `net` Vael patrol vehicles stands across the road `net_at` m ahead and closes on you when you come within `net_wake` m; reach the exit `dist` m ahead.
##   gate     `gates` rings along the road, each closing (the ring shrinks) over its `budget` seconds; a closed ring fails the run.
##   escort   an allied car (`hp`) drives `dist` m under fire from `chasers` patrol vehicles (each one within FIRE_RANGE of it burns `fire` hp/s); it must arrive alive and you must stay within `leash` m.
##   duel     one boss patrol vehicle with `hp_mult` x the hit points rams at you; wreck it.
## Common keys: title, time (limit s), gap (start distance to the target / first gate), kind (target car kind), cruise, hp, heat (floor of the heat while it runs), pay, rep, checkpoints (progress fractions).
## RUBBER is the one table that tunes rubber-banding: see rubber() and chase_cap().

const IDS: Array[StringName] = [&"convoy", &"roadblock", &"rooftop", &"gate", &"escort", &"duel"]
const NAMES := {&"convoy": "PURSUE THE CONVOY", &"roadblock": "ESCAPE THE ROADBLOCK", &"rooftop": "ROOFTOP TO STREET", &"gate": "RACE THE GATE", &"escort": "ESCORT UNDER FIRE", &"duel": "VEHICLE DUEL"}

const DISABLE := 0.25                  ## pursue: a target at or below this fraction of its hit points is stopped
const FIRE_RANGE := 18.0               ## escort: a chaser this close to the allied car shoots it
const MAX_TRIES := 3                   ## attempts before a failed run ends for good
const RETRY_DELAY := 3.0               ## s between a failure and the retry from the last checkpoint
const PLAYER_KIND := &"sport"          ## the car the player gets when he is on foot
const MAX_ALONG := 300.0               ## routes stay inside this coordinate on the road

const DEFS := {
	&"convoy": {"mode": &"pursue", "kind": &"sedan", "guards": 2, "hp": 130.0, "cruise": 15.0, "gap": 45.0, "time": 150.0, "lose": 110.0, "lose_s": 8.0, "heat": 0.5, "pay": 420, "rep": 4, "checkpoints": [0.34, 0.67]},
	&"roadblock": {"mode": &"escape", "net": 3, "net_at": 80.0, "net_wake": 38.0, "dist": 260.0, "radius": 14.0, "gap": 0.0, "time": 90.0, "heat": 3.0, "pay": 480, "rep": 5, "checkpoints": [0.5]},
	&"rooftop": {"mode": &"pursue", "kind": &"hover", "guards": 0, "hp": 100.0, "cruise": 19.0, "gap": 55.0, "time": 140.0, "lose": 130.0, "lose_s": 7.0, "heat": 0.5, "pay": 520, "rep": 5, "checkpoints": [0.5]},
	&"gate": {"mode": &"gate", "gates": 4, "gate_gap": 62.0, "radius": 14.0, "budget": [10.0, 9.0, 9.0, 8.0], "gap": 62.0, "time": 0.0, "heat": 0.0, "pay": 450, "rep": 4, "checkpoints": []},
	&"escort": {"mode": &"escort", "kind": &"suv", "hp": 160.0, "cruise": 12.0, "dist": 250.0, "chasers": 2, "fire": 9.0, "leash": 70.0, "leash_s": 8.0, "gap": 0.0, "time": 130.0, "heat": 2.6, "pay": 560, "rep": 6, "checkpoints": [0.34, 0.67]},
	&"duel": {"mode": &"duel", "hp_mult": 4.0, "gap": 70.0, "time": 120.0, "heat": 3.0, "pay": 760, "rep": 8, "checkpoints": [0.5]},
}

## Rubber-banding, ONE table (key: chase id). The gap is the metres between the player's car and the thing he chases / guards.
##   near, far   gap range of the band
##   boost, slow target cruise factor at gap <= near (it runs from you) and at gap >= far (it waits for you)
##   chase_cap   patrol speed cap as a fraction of its top speed when the player is within `near` (a rammer never gets glued to the bumper); 1.0 = no cap
const RUBBER := {
	&"convoy": {"near": 18.0, "far": 62.0, "boost": 1.22, "slow": 0.55, "chase_cap": 1.0},
	&"roadblock": {"near": 20.0, "far": 70.0, "boost": 1.0, "slow": 1.0, "chase_cap": 0.9},
	&"rooftop": {"near": 18.0, "far": 70.0, "boost": 1.25, "slow": 0.5, "chase_cap": 1.0},
	&"gate": {"near": 20.0, "far": 70.0, "boost": 1.0, "slow": 1.0, "chase_cap": 1.0},
	&"escort": {"near": 14.0, "far": 55.0, "boost": 1.1, "slow": 0.35, "chase_cap": 0.88},
	&"duel": {"near": 16.0, "far": 70.0, "boost": 1.0, "slow": 1.0, "chase_cap": 0.82},
}


static func def(id: StringName) -> Dictionary:
	return DEFS.get(id, {})


static func title(id: StringName) -> String:
	return String(NAMES.get(id, String(id).to_upper()))


## Factor for the chased / guarded car's cruise speed at `gap` metres: `boost` up to `near`, `slow` from `far`, linear between.
static func rubber(id: StringName, gap: float) -> float:
	var r: Dictionary = RUBBER.get(id, {})
	if r.is_empty():
		return 1.0
	var t := clampf((gap - float(r["near"])) / maxf(float(r["far"]) - float(r["near"]), 0.001), 0.0, 1.0)
	return lerpf(float(r["boost"]), float(r["slow"]), t)


## Speed cap factor for a chasing patrol: `chase_cap` while the player is within `near`, 1.0 from `far`, linear between.
static func chase_cap(id: StringName, gap: float) -> float:
	var r: Dictionary = RUBBER.get(id, {})
	if r.is_empty():
		return 1.0
	var t := clampf((gap - float(r["near"])) / maxf(float(r["far"]) - float(r["near"]), 0.001), 0.0, 1.0)
	return lerpf(float(r["chase_cap"]), 1.0, t)


## Reward in credits: base pay, +25 % when finished with a third of the clock left (untimed runs: no bonus), never below 1.
static func reward(id: StringName, time_left_frac: float) -> int:
	var v := float(def(id).get("pay", 0))
	if time_left_frac >= 1.0 / 3.0:
		v *= 1.25
	return maxi(1, int(round(v / 5.0)) * 5)


## "" when the table entry is complete and sane, otherwise what is wrong (the test walks every id).
static func validate(id: StringName) -> String:
	if not DEFS.has(id) or not NAMES.has(id) or not RUBBER.has(id):
		return "missing table entry"
	var d: Dictionary = DEFS[id]
	for k: String in ["mode", "gap", "time", "heat", "pay", "rep", "checkpoints"]:
		if not d.has(k):
			return "missing key " + k
	var r: Dictionary = RUBBER[id]
	for k: String in ["near", "far", "boost", "slow", "chase_cap"]:
		if not r.has(k):
			return "rubber: missing key " + k
	if float(r["far"]) <= float(r["near"]) or float(r["slow"]) <= 0.0 or float(r["chase_cap"]) <= 0.0:
		return "rubber band is not sane"
	for c: Variant in d["checkpoints"] as Array:
		if float(c) <= 0.0 or float(c) >= 1.0:
			return "checkpoint fraction outside 0..1"
	if String(NAMES[id]).length() > CampaignSteps.MAX_TEXT:
		return "title too long"
	return ""
