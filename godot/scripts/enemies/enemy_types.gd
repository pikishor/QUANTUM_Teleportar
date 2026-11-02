class_name EnemyTypes
extends RefCounted
## The ENEMY table of src/models.js (numbers play-tested in the prototype) plus the human operative.
## Models are authored at final size: `scale` of the prototype is not applied. center_y / radius follow the asset contract
## (body centres at 1.25 / 0.82 / 1.40 m for the drones, hit radii 1.25 / 0.8 / 1.35 m). The sentinel model is drawn at `scale` 1.35 so it reads at 25 m.
##   hover: height of the drone's node above the ground (the model's origin is its ground contact, the body hangs 0.7-1.4 m above it)
##   fire:  seconds between shots (drones) or between bursts (operative); burst: rounds per volley; dmg per round / bolt

const TYPES := {
	&"sentinel": {
		"hp": 60.0, "speed": 4.6, "range": 22.0, "fire": Vector2(1.0, 1.7), "dmg": 7.0, "bolt": 30.0, "burst": 1,
		"color": Color(1.0, 0.24, 0.37), "score": 50, "radius": 1.25, "heat": 0.22, "center_y": 1.25, "hover": 0.35, "scale": 1.35,
		"model": "drone_sentinel", "drone": true, "kamikaze": false,
	},
	&"striker": {
		"hp": 34.0, "speed": 10.5, "range": 0.0, "fire": Vector2(1.0, 1.0), "dmg": 30.0, "bolt": 0.0, "burst": 0,
		"color": Color(1.0, 0.63, 0.23), "score": 40, "radius": 0.8, "heat": 0.15, "center_y": 0.82, "hover": 0.4,
		"model": "drone_striker", "drone": true, "kamikaze": true,
	},
	&"heavy": {
		"hp": 230.0, "speed": 3.0, "range": 30.0, "fire": Vector2(1.5, 2.1), "dmg": 9.0, "bolt": 26.0, "burst": 3,
		"color": Color(0.70, 0.36, 1.0), "score": 160, "radius": 1.35, "heat": 0.5, "center_y": 1.40, "hover": 0.1,
		"model": "drone_heavy", "drone": true, "kamikaze": false,
	},
	&"operative": {
		"hp": 80.0, "speed": 4.4, "range": 30.0, "fire": Vector2(1.1, 2.0), "dmg": 5.0, "bolt": 0.0, "burst": 3,
		"color": Color(1.0, 0.22, 0.2), "score": 70, "radius": 0.55, "heat": 0.25, "center_y": 1.05, "hover": 0.0,
		"model": "operative", "drone": false, "kamikaze": false,
		"walk": 1.5, "burst_gap": 0.12, "aim_time": 0.45, "spread": 0.035, "spread_per_m": 0.0008, "cover": true,
	},
	# --- the specialists (Specialist, scripts/enemies/specialist.gd): the operative model and rig with a tint and a scale, no new model.
	&"shield": {
		"hp": 150.0, "speed": 3.4, "range": 24.0, "fire": Vector2(1.4, 2.2), "dmg": 5.0, "bolt": 0.0, "burst": 3,
		"color": Color(0.25, 0.8, 1.0), "score": 110, "radius": 0.62, "heat": 0.35, "center_y": 1.1, "hover": 0.0, "scale": 1.08,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"shield", "shield_hp": 160.0,
		"walk": 1.4, "burst_gap": 0.14, "aim_time": 0.5, "spread": 0.04, "spread_per_m": 0.0008, "min_chapter": 1, "limit": 3,
	},
	&"flanker": {
		"hp": 55.0, "speed": 8.2, "range": 15.0, "fire": Vector2(0.8, 1.3), "dmg": 4.0, "bolt": 0.0, "burst": 2,
		"color": Color(1.0, 0.62, 0.15), "score": 80, "radius": 0.5, "heat": 0.25, "center_y": 0.98, "hover": 0.0, "scale": 0.94,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"flanker",
		"walk": 2.2, "burst_gap": 0.08, "aim_time": 0.22, "spread": 0.05, "spread_per_m": 0.0012, "min_chapter": 1, "limit": 3,
	},
	&"sniper": {
		"hp": 50.0, "speed": 4.0, "range": 70.0, "fire": Vector2(2.4, 3.4), "dmg": 30.0, "bolt": 0.0, "burst": 1,
		"color": Color(1.0, 0.2, 0.8), "score": 120, "radius": 0.55, "heat": 0.4, "center_y": 1.05, "hover": 0.0, "scale": 1.0,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"sniper", "cover": true, "cover_radius": 30.0,
		"walk": 1.2, "burst_gap": 0.1, "aim_time": 0.8, "spread": 0.002, "spread_per_m": 0.00005, "min_chapter": 2, "limit": 2,
	},
	&"brute": {
		"hp": 380.0, "speed": 6.0, "range": 4.0, "fire": Vector2(1.0, 1.0), "dmg": 26.0, "bolt": 0.0, "burst": 0,
		"color": Color(1.0, 0.5, 0.1), "score": 200, "radius": 0.9, "heat": 0.6, "center_y": 1.45, "hover": 0.0, "scale": 1.38,
		"model": "operative", "body": "enemy_bluedemon", "drone": false, "kamikaze": false, "role": &"brute",
		"walk": 1.6, "burst_gap": 0.1, "aim_time": 0.5, "spread": 0.0, "spread_per_m": 0.0, "min_chapter": 3, "limit": 2,
	},
	# --- enemy variety (D3/D4): four more types and two elite minibosses, picked through variety_for() / tier_limit(); "variety" marks them for the tier limit scale.
	&"stalker": {
		"hp": 60.0, "speed": 5.6, "range": 20.0, "fire": Vector2(1.0, 1.6), "dmg": 6.0, "bolt": 0.0, "burst": 2,
		"color": Color(0.3, 1.0, 0.6), "score": 130, "radius": 0.52, "heat": 0.3, "center_y": 1.0, "hover": 0.0, "scale": 0.98,
		"model": "operative", "body": "enemy_alien", "drone": false, "kamikaze": false, "role": &"stalker", "variety": true,
		"walk": 1.8, "burst_gap": 0.09, "aim_time": 0.3, "spread": 0.04, "spread_per_m": 0.001, "min_chapter": 2, "limit": 2,
	},
	&"carrier": {
		"hp": 120.0, "speed": 3.2, "range": 24.0, "fire": Vector2(1.5, 2.3), "dmg": 5.0, "bolt": 0.0, "burst": 3,
		"color": Color(0.95, 0.95, 0.4), "score": 150, "radius": 0.66, "heat": 0.4, "center_y": 1.12, "hover": 0.0, "scale": 1.12,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"carrier", "variety": true, "shield_hp": 140.0, "release": 2,
		"walk": 1.3, "burst_gap": 0.14, "aim_time": 0.55, "spread": 0.04, "spread_per_m": 0.0008, "min_chapter": 3, "limit": 2,
	},
	&"walker": {
		"hp": 210.0, "speed": 2.4, "range": 60.0, "fire": Vector2(3.5, 5.0), "dmg": 24.0, "bolt": 0.0, "burst": 0,
		"color": Color(0.55, 0.6, 0.95), "score": 180, "radius": 0.8, "heat": 0.5, "center_y": 1.3, "hover": 0.0, "scale": 1.25,
		"model": "operative", "body": "enemy_demon", "drone": false, "kamikaze": false, "role": &"walker", "variety": true, "shell_radius": 4.5,
		"walk": 1.1, "burst_gap": 0.1, "aim_time": 0.5, "spread": 0.0, "spread_per_m": 0.0, "min_chapter": 4, "limit": 1,
	},
	&"swarmer": {
		"hp": 10.0, "speed": 12.5, "range": 0.0, "fire": Vector2(1.0, 1.0), "dmg": 9.0, "bolt": 0.0, "burst": 0,
		"color": Color(0.4, 0.9, 1.0), "score": 15, "radius": 0.45, "heat": 0.03, "center_y": 0.42, "hover": 0.25, "scale": 0.45,
		"model": "drone_striker", "drone": true, "kamikaze": true, "variety": true, "min_chapter": 2, "limit": 4,
	},
	# --- the elite minibosses (Specialist roles, one at a time by tier: ELITE_CAPS), no new model.
	&"warden": {
		"hp": 700.0, "speed": 4.8, "range": 26.0, "fire": Vector2(1.1, 1.7), "dmg": 6.0, "bolt": 0.0, "burst": 3,
		"color": Color(0.9, 0.9, 1.0), "score": 600, "radius": 1.05, "heat": 0.8, "center_y": 1.55, "hover": 0.0, "scale": 1.5,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"warden", "variety": true, "elite": true, "pulse_radius": 6.5, "pulse_dmg": 20.0,
		"walk": 1.5, "burst_gap": 0.1, "aim_time": 0.4, "spread": 0.03, "spread_per_m": 0.0006, "min_chapter": 3, "limit": 1,
	},
	&"hivemother": {
		"hp": 600.0, "speed": 3.2, "range": 32.0, "fire": Vector2(1.4, 2.0), "dmg": 6.0, "bolt": 0.0, "burst": 3,
		"color": Color(1.0, 0.4, 0.55), "score": 600, "radius": 1.1, "heat": 0.8, "center_y": 1.6, "hover": 0.0, "scale": 1.55,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"hivemother", "variety": true, "elite": true, "summon": 2,
		"walk": 1.2, "burst_gap": 0.12, "aim_time": 0.5, "spread": 0.035, "spread_per_m": 0.0007, "min_chapter": 5, "limit": 1,
	},
	# --- the boss (Overseer, scripts/enemies/overseer.gd): only a contract spawns it.
	&"overseer": {
		"hp": 1500.0, "speed": 3.6, "range": 34.0, "fire": Vector2(1.2, 1.8), "dmg": 7.0, "bolt": 0.0, "burst": 4,
		"color": Color(0.72, 0.3, 1.0), "score": 2000, "radius": 1.45, "heat": 1.0, "center_y": 2.0, "hover": 0.0, "scale": 1.95,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"overseer", "boss": true, "drops_weapon": false,
		"walk": 1.3, "burst_gap": 0.1, "aim_time": 0.5, "spread": 0.03, "spread_per_m": 0.0006, "limit": 1,
	},
	# --- the verb bosses (scripts/enemies/verb_boss.gd): only the campaign (chapters 4 and 7) spawns them.
	&"smelter": {
		"hp": 2400.0, "speed": 3.0, "range": 30.0, "fire": Vector2(1.4, 2.0), "dmg": 7.0, "bolt": 0.0, "burst": 4,
		"color": Color(1.0, 0.24, 0.94), "score": 2500, "radius": 1.4, "heat": 1.0, "center_y": 1.9, "hover": 0.0, "scale": 1.9,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"verb_boss", "verb": "hazard", "boss": true, "drops_weapon": false,
		"walk": 1.2, "burst_gap": 0.1, "aim_time": 0.5, "spread": 0.03, "spread_per_m": 0.0006, "limit": 1,
	},
	&"bulwark": {
		"hp": 2000.0, "speed": 2.8, "range": 32.0, "fire": Vector2(1.3, 1.9), "dmg": 7.0, "bolt": 0.0, "burst": 4,
		"color": Color(0.3, 0.94, 1.0), "score": 2500, "radius": 1.5, "heat": 1.0, "center_y": 2.0, "hover": 0.0, "scale": 2.0,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"verb_boss", "verb": "shield", "boss": true, "drops_weapon": false,
		"walk": 1.1, "burst_gap": 0.1, "aim_time": 0.5, "spread": 0.03, "spread_per_m": 0.0006, "limit": 1,
	},
	&"hound": {
		"hp": 1800.0, "speed": 4.2, "range": 28.0, "fire": Vector2(1.0, 1.6), "dmg": 6.0, "bolt": 0.0, "burst": 3,
		"color": Color(1.0, 0.55, 0.2), "score": 2500, "radius": 1.3, "heat": 1.0, "center_y": 1.8, "hover": 0.0, "scale": 1.8,
		"model": "operative", "drone": false, "kamikaze": false, "role": &"verb_boss", "verb": "hunter", "boss": true, "drops_weapon": false,
		"walk": 1.5, "burst_gap": 0.1, "aim_time": 0.4, "spread": 0.03, "spread_per_m": 0.0006, "limit": 1,
	},
}

## Alive at once, per graphics tier (Game.quality): LOW, MED, HIGH.
const CAPS: Array[int] = [5, 8, 12]
## Energy the player gets back for a kill.
const ENERGY_REFUND := 8.0


## Whether a type is a Specialist-driven human (shield, flanker, sniper, brute, overseer).
static func is_specialist(type: StringName) -> bool:
	return TYPES.has(type) and TYPES[type].has("role")


## Share of the operative reinforcement slots that become specialists, per chapter index (the last row covers every later sector). Chapters 1-4 keep the original 55 %,
## the late chapters push it up to 75 % (the Gate and the free city are all specialists and squads); the per-type `limit` and the tier caps keep the draw budget the same.
const SPECIALIST_SHARE: Array[float] = [0.55, 0.55, 0.55, 0.55, 0.60, 0.65, 0.70, 0.75, 0.75]
## Extra pick weight of a specialist type per chapter index (1 each for every type in the pool otherwise), the last row covers every later sector: snipers from chapter 5,
## brutes from chapter 6, shields from chapter 7 (index 6), so the late fights are long-range and heavy rather than just more flankers.
const PICK_BIAS: Array[Dictionary] = [
	{}, {}, {}, {}, {&"sniper": 1}, {&"sniper": 1, &"brute": 1}, {&"sniper": 1, &"brute": 1, &"shield": 1}, {&"sniper": 2, &"brute": 1, &"shield": 1}, {&"sniper": 2, &"brute": 1, &"shield": 1},
]


static func specialist_share(chapter: int) -> float:
	return SPECIALIST_SHARE[clampi(chapter, 0, SPECIALIST_SHARE.size() - 1)]


## The operative slot of a reinforcement, replaced by a specialist by chapter and heat: flankers and shields from chapter 2 (index 1), snipers from chapter 3, brutes from
## chapter 4 at heat 2.5. `r` and `r2` are rolls 0..1 (the slot is a specialist when r <= specialist_share(chapter)); the late chapters weight the pool (PICK_BIAS).
## Falls back to the operative.
static func specialist_for(chapter: int, heat: float, r: float, r2: float) -> StringName:
	if r > specialist_share(chapter):
		return &"operative"
	var pool: Array[StringName] = []
	var bias: Dictionary = PICK_BIAS[clampi(chapter, 0, PICK_BIAS.size() - 1)]
	for t: StringName in [&"flanker", &"shield", &"sniper", &"brute"]:
		var c: Dictionary = TYPES[t]
		if chapter >= int(c["min_chapter"]) and (t != &"brute" or heat >= 2.5) and (t != &"shield" or heat >= 1.5 or chapter >= 2):
			for k in 1 + int(bias.get(t, 0)):
				pool.append(t)
	if pool.is_empty():
		return &"operative"
	return pool[mini(int(r2 * pool.size()), pool.size() - 1)]


## Share of the reinforcement slots that become a variety type (not the elites), per chapter index (the last row covers every later sector).
const VARIETY_SHARE: Array[float] = [0.0, 0.0, 0.15, 0.2, 0.25, 0.3, 0.3, 0.35, 0.35]
const VARIETY_TYPES: Array[StringName] = [&"stalker", &"swarmer", &"carrier", &"walker"]
const ELITE_TYPES: Array[StringName] = [&"warden", &"hivemother"]
## Elites alive at once per graphics tier (LOW, MED, HIGH) and the heat at which they start to show.
const ELITE_CAPS: Array[int] = [0, 1, 2]
const ELITE_HEAT := 3.0
const ELITE_SHARE := 0.1
## Per-type limit scale by tier for the variety types (LOW, MED, HIGH).
const TIER_LIMIT_SCALE: Array[float] = [0.5, 0.75, 1.0]


static func is_elite(type: StringName) -> bool:
	return TYPES.has(type) and bool(TYPES[type].get("elite", false))


## Alive at once of a type on a tier: the cfg limit scaled down on LOW / MED for the variety types, the tier elite cap for elites, the plain cfg limit otherwise.
static func tier_limit(type: StringName, tier: int) -> int:
	var c := get_cfg(type)
	var t := clampi(tier, 0, 2)
	if bool(c.get("elite", false)):
		return mini(int(c.get("limit", 1)), ELITE_CAPS[t])
	if not bool(c.get("variety", false)):
		return int(c.get("limit", 99))
	return maxi(1, ceili(float(c.get("limit", 1)) * TIER_LIMIT_SCALE[t]))


## The variety type of a reinforcement slot, or &"" for none. `r` rolls the slot (variety when r <= the chapter share), `r2` picks the type; an elite takes the slot
## when heat >= ELITE_HEAT and r <= ELITE_SHARE (warden from chapter 4, hivemother from chapter 6, index 3 / 5), the elite pick alternating by r2.
static func variety_for(chapter: int, heat: float, r: float, r2: float) -> StringName:
	if heat >= ELITE_HEAT and r <= ELITE_SHARE:
		var pool_e: Array[StringName] = []
		for t: StringName in ELITE_TYPES:
			if chapter >= int(TYPES[t]["min_chapter"]):
				pool_e.append(t)
		if not pool_e.is_empty():
			return pool_e[mini(int(r2 * pool_e.size()), pool_e.size() - 1)]
	if r > VARIETY_SHARE[clampi(chapter, 0, VARIETY_SHARE.size() - 1)]:
		return &""
	var pool: Array[StringName] = []
	for t: StringName in VARIETY_TYPES:
		if chapter >= int(TYPES[t]["min_chapter"]):
			pool.append(t)
	if pool.is_empty():
		return &""
	return pool[mini(int(r2 * pool.size()), pool.size() - 1)]


static func get_cfg(type: StringName) -> Dictionary:
	return TYPES[type] if TYPES.has(type) else TYPES[&"sentinel"]
