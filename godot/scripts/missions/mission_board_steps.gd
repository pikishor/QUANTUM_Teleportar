class_name MissionBoardSteps
extends RefCounted
## The step recipes of the Mission Board (scripts/missions/mission_board.gd): for each of the sixteen mission types, two or three campaign steps (CampaignSteps dictionaries) whose goals the
## board places near the hero. Pure data and rules, no scene tree. `tier` (0..3, one every four finished missions) adds a guard or a wave; everything stays EASY: no time limits except
## the delivery run and the chase kinds' own, foes with ordinary health, targets that crawl (destroy vehicle) or ease off (chase). Texts are the objective line: at most 40 characters.
## Every recipe starts with a step the hero can walk to at once, and ends where a payout makes sense.

const RANGE_NEAR := [50.0, 90.0]
const RANGE_MID := [70.0, 120.0]
const RANGE_FAR := [100.0, 160.0]


static func _s(kind: String, text: String, extra := {}) -> Dictionary:
	var d := {"kind": kind, "text": text, "quiet": true}
	d.merge(extra, true)
	return d


## The steps of a mission of type `t` at difficulty tier `tier`, drawn with `r` (a seeded RandomNumberGenerator).
static func steps(t: StringName, tier: int, r: RandomNumberGenerator) -> Array[Dictionary]:
	var g := clampi(tier, 0, 3)
	var out: Array[Dictionary] = []
	match String(t):
		"patrol":
			out = [
				_s("kill_target", "TAKE OUT THE FIRST PATROL", {"enemy": "operative", "guards": 1 + g, "hp_mult": 1.0, "name": "PATROL", "range": RANGE_MID}),
				_s("kill_target", "TAKE OUT THE SECOND PATROL", {"enemy": "operative", "guards": 2 + g, "hp_mult": 1.2, "name": "PATROL", "range": [60.0, 110.0]}),
			]
		"vehicle":
			out = [
				_s("chase", "DESTROY THE ARMOURED CAR", {"on_foot": true, "hp": 130.0, "cruise": 2.0, "range": RANGE_MID}),
				_s("chase", "DESTROY THE SECOND CAR", {"on_foot": true, "hp": 150.0 + 20.0 * g, "cruise": 2.5, "range": [60.0, 110.0]}),
			]
		"rescue":
			out = [
				_s("kill_target", "CLEAR THE CAPTORS", {"enemy": "operative", "guards": 2 + g, "hp_mult": 1.0, "name": "CAPTORS", "range": RANGE_MID}),
				_s("escort", "BRING THE HOSTAGE TO SAFETY", {"hp": 160.0, "range": [90.0, 140.0]}),
			]
		"escort":
			out = [
				_s("reach", "MEET THE VIP", {"range": RANGE_NEAR, "radius": 8.0}),
				_s("escort", "ESCORT THE VIP", {"hp": 160.0, "range": [100.0, 150.0]}),
			]
		"courier":
			out = [
				_s("reach", "PICK UP THE PACKAGE", {"range": RANGE_NEAR, "radius": 8.0}),
				_s("reach", "DELIVER THE PACKAGE", {"range": [100.0, 150.0], "radius": 8.0}),
				_s("reach", "DELIVER TO THE SECOND BUYER", {"range": [110.0, 160.0], "radius": 8.0, "time": 170.0}),
			]
		"heist":
			out = [
				_s("reach", "SCOUT THE BUILDING", {"range": RANGE_NEAR, "radius": 8.0}),
				_s("heist", "STEAL THE DATA", {"patrol": 1, "heat": 2.0, "escape_time": 150.0, "dist": 90.0, "interior": ""}),
			]
		"stealth":
			out = [
				_s("reach", "GET INTO POSITION", {"range": RANGE_NEAR, "radius": 8.0}),
				_s("sneak", "SLIP PAST THE GUARDS", {"range": [60.0, 100.0], "guards": 3, "radius": 8.0}),
				_s("reach", "EXTRACT", {"range": RANGE_NEAR, "radius": 8.0}),
			]
		"chase":
			out = [
				_s("chase", "RUN DOWN THE FLEEING CAR", {"hp": 110.0, "cruise": 13.0, "range": [55.0, 100.0]}),
				_s("chase", "RUN DOWN THE SECOND CAR", {"hp": 130.0, "cruise": 14.0, "range": [55.0, 100.0]}),
			]
		"convoy":
			out = [
				_s("convoy_intercept", "STOP THE CONVOY", {"cars": 2, "range": [90.0, 140.0], "time": 160.0}),
				_s("reach", "SECURE THE CARGO", {"range": [30.0, 60.0], "radius": 8.0}),
			]
		"arena":
			out = [
				_s("reach", "ENTER THE ARENA", {"range": RANGE_NEAR, "radius": 10.0}),
				_s("survive", "BEAT THE WAVES", {"hold": 44.0, "gap": 9.0, "count": 3 + g, "near": 18.0, "far": 34.0, "clear": true}),
			]
		"boss":
			out = [
				_s("reach", "TRACK THE ELITE", {"range": RANGE_NEAR, "radius": 10.0}),
				_s("kill_target", "TAKE DOWN THE ELITE", {"target": "specialist", "guards": 2, "hp_mult": 2.0, "name": "ELITE", "range": [60.0, 100.0]}),
			]
		"bounty":
			out = [
				_s("kill_target", "FIND THE BOUNTY TARGET", {"target": "specialist", "guards": 1 + (g / 2), "hp_mult": 1.8, "name": "BOUNTY TARGET", "range": RANGE_FAR}),
				_s("reach", "COLLECT THE BOUNTY", {"range": [40.0, 70.0], "radius": 8.0}),
			]
		"demolition":
			out = [
				_s("smash", "SMASH THE PROPS", {"n": 5, "range": RANGE_NEAR}),
				_s("smash", "SMASH THE SECOND SITE", {"n": 6, "range": [60.0, 100.0]}),
			]
		"hijack":
			out = [
				_s("reach", "TAKE A CAR TO THE DROP", {"car": true, "range": [70.0, 110.0], "radius": 9.0}),
				_s("reach", "DELIVER THE CAR TO THE BUYER", {"car": true, "range": [110.0, 170.0], "radius": 9.0, "time": 170.0}),
			]
		"defend":
			out = [
				_s("reach", "TAKE UP POSITION", {"range": RANGE_NEAR, "radius": 12.0}),
				_s("defend", "HOLD THE POSITION", {"hold": 40.0, "gap": 12.0, "count": 2 + g, "radius": 30.0, "range": [20.0, 40.0]}),
			]
		"hack":
			out = [
				_s("reach", "GET TO THE NODE", {"range": RANGE_NEAR, "radius": 8.0}),
				_s("hack", "HACK THE NODE", {"hold": 20.0, "count": 2 + (g / 2), "radius": 9.0, "range": [20.0, 40.0]}),
			]
	for st: Dictionary in out:
		st["quiet"] = true
	if r != null and not out.is_empty():
		var _roll := r.randf()                      # reserved: a recipe may vary by seed later without changing the signature
	return out


## The first mission of a new game: walk to the beacon, clear one lookout. The first step is a plain walk, the second the smallest fight.
static func first_steps(_r: RandomNumberGenerator) -> Array[Dictionary]:
	return [
		_s("reach", "FOLLOW THE BEACON", {"range": [55.0, 85.0], "radius": 9.0}),
		_s("kill_target", "CLEAR THE LOOKOUT", {"enemy": "operative", "guards": 2, "hp_mult": 1.0, "name": "LOOKOUT", "range": [32.0, 55.0]}),
	]
