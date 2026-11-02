class_name WeaponDefs
extends RefCounted
## The four alien weapons as data (PlayerWeapon reads them) plus the unlocked set (static, like Upgrades.levels: the player, the shop, the HUD and the save file all see it).
##   carbine  Rift Carbine: the default hitscan rifle (the numbers of the original PlayerWeapon constants; its reserve is unlimited).
##   scatter  Shard Scatter: 8 pellets in a wide cone, each pellet rolls the head test on its own (a crit is 2x the pellet), full damage to 12 m, 25 % at 38 m.
##   lance    Pulse Lance: hold to charge (1.1 s, glow at the muzzle and a bar on the HUD), release for a piercing hitscan through every enemy on the line; ADS zooms to 24 degrees.
##   grenade  Singularity Grenade: thrown in an arc, lands, a gravity well pulls and burns everything within 9 m for 1.6 s, then it collapses into Game.explode.
## kind: "hit" (hitscan, pellets), "charge" (lance), "throw" (grenade). reserve < 0 = unlimited spare ammo. look = the emissive tint of the strip on the rifle.

const IDS: Array[StringName] = [&"carbine", &"scatter", &"lance", &"grenade"]

const DEFS := {
	&"carbine": {
		"name": "RIFT CARBINE", "tag": "CRB", "kind": "hit", "mag": 30, "reserve": -1, "interval": 0.105, "damage": 14.0, "crit": 30.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.3, 1.0), Vector2(-0.5, 0.9), Vector2(0.6, 0.85), Vector2(-0.2, 0.8), Vector2(-0.7, 0.8)], "shake": 0.03, "vol": -2.0, "pitch_lo": 0.93, "pitch_hi": 1.07, "eject": 1, "flash": 1.0, "ads_kick": 0.65, "ads_spread": 0.3,
		"spread_hip": 0.014, "spread_ads": 0.004, "spread_move": 0.010, "bloom": 0.0032, "bloom_max": 0.03,
		"kick": 0.0095, "kick_end": 0.0055, "kick_yaw": 0.0035, "reload": 1.3, "range": 220.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.86, 0.5), "look": Color(1.0, 0.7, 0.3), "look_size": Vector3(0.035, 0.035, 0.5), "zoom": 62.0, "price": 0, "pierce_shield": false,
	},
	&"scatter": {
		"name": "SHARD SCATTER", "tag": "SCT", "kind": "hit", "mag": 6, "reserve": 36, "interval": 0.8, "damage": 9.0, "crit": 18.0, "pellets": 8,
		"pattern": [Vector2(0.0, 1.0), Vector2(-0.4, 1.15), Vector2(0.4, 1.15)], "shake": 0.14, "vol": 2.0, "pitch_lo": 0.5, "pitch_hi": 0.62, "eject": 0, "flash": 1.7, "ads_kick": 0.8, "ads_spread": 0.67,
		"spread_hip": 0.075, "spread_ads": 0.05, "spread_move": 0.015, "bloom": 0.0, "bloom_max": 0.0,
		"kick": 0.042, "kick_end": 0.042, "kick_yaw": 0.012, "reload": 1.9, "range": 38.0, "falloff_from": 12.0,
		"tracer": Color(0.45, 1.0, 0.82), "look": Color(0.3, 1.0, 0.75), "look_size": Vector3(0.1, 0.07, 0.34), "zoom": 56.0, "price": 500, "pierce_shield": false,
	},
	&"lance": {
		"name": "PULSE LANCE", "tag": "LNC", "kind": "charge", "mag": 5, "reserve": 20, "interval": 0.5, "damage": 120.0, "crit": 200.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.22, "vol": 0.0, "pitch_lo": 0.66, "pitch_hi": 0.76, "eject": 0, "flash": 2.0, "ads_kick": 0.5, "ads_spread": 0.05,
		"spread_hip": 0.012, "spread_ads": 0.0006, "spread_move": 0.02, "bloom": 0.0, "bloom_max": 0.0, "charge_time": 1.1, "min_charge": 0.35,
		"kick": 0.05, "kick_end": 0.05, "kick_yaw": 0.004, "reload": 2.2, "range": 420.0, "falloff_from": 9999.0,
		"tracer": Color(0.4, 0.72, 1.0), "look": Color(0.35, 0.6, 1.0), "look_size": Vector3(0.025, 0.025, 0.75), "zoom": 24.0, "price": 800, "pierce_shield": true,
	},
	&"grenade": {
		"name": "SINGULARITY GRENADE", "tag": "GRN", "kind": "throw", "mag": 1, "reserve": 5, "interval": 0.9, "damage": 80.0, "crit": 80.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.05, "vol": -4.0, "pitch_lo": 0.9, "pitch_hi": 1.1, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0,
		"kick": 0.012, "kick_end": 0.012, "kick_yaw": 0.0, "reload": 1.4, "range": 60.0, "falloff_from": 9999.0,
		"tracer": Color(0.8, 0.45, 1.0), "look": Color(0.75, 0.35, 1.0), "look_size": Vector3(0.12, 0.12, 0.12), "zoom": 62.0, "price": 650, "pierce_shield": true,
		"speed": 21.0, "fuse": 2.2, "well_time": 1.6, "well_radius": 9.0, "well_pull": 7.5, "well_dps": 24.0, "blast_radius": 7.5,
	},
}

const COLOR_PICKUP := Color(1.0, 0.45, 0.9)
const COLLAPSE_COLOR := Color(0.4, 1.0, 0.93)

## The weapons the player owns (set by Progress when a save loads, a weapon is bought or picked up).
static var unlocked: Array[StringName] = [&"carbine"]
## The weapon in hand (saved with the unlocked set).
static var last_used: StringName = &"carbine"


static func def(id: StringName) -> Dictionary:
	return DEFS[id] if DEFS.has(id) else DEFS[&"carbine"]


## Recoil pattern step for the nth shot of a burst: x = yaw multiplier (-1 left .. 1 right), y = pitch multiplier. The pattern repeats, so each weapon climbs the same way every burst.
static func pattern_at(id: StringName, n: int) -> Vector2:
	var pat: Array = def(id)["pattern"]
	return pat[posmod(n, pat.size())]


static func title(id: StringName) -> String:
	return str(def(id)["name"])


static func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


static func unlock(id: StringName) -> bool:
	if not DEFS.has(id) or unlocked.has(id):
		return false
	unlocked.append(id)
	return true


static func reset_unlocked() -> void:
	unlocked = [&"carbine"]
	last_used = &"carbine"


## Replace the set from saved names (unknown names dropped, the carbine is always there, order follows IDS).
static func set_unlocked(names: Array) -> void:
	var out: Array[StringName] = []
	for id: StringName in IDS:
		if id == &"carbine" or names.has(String(id)) or names.has(id):
			out.append(id)
	unlocked = out


static func price(id: StringName, discount := 0.0) -> int:
	return maxi(5, int(roundf(float(def(id)["price"]) * (1.0 - discount) / 5.0)) * 5)


## Magazine size with the shop's magazine upgrade, per weapon: +20 % of the weapon's own base per level (the carbine keeps its +6), small magazines at least +1 every second level.
static func mag_size(id: StringName, level: int) -> int:
	var base := int(def(id)["mag"])
	var extra := int(roundf(float(base) * 0.2 * float(level)))
	if base < 30 and level > 0:
		extra = maxi(extra, (level + 1) / 2)
	return base + extra


## What a drop gives for a random roll 0..1: an unowned weapon (half of the drops) or ammo for an owned one. Never the carbine.
static func pick_drop(r: float, rng_pick: float) -> StringName:
	var missing: Array[StringName] = []
	var owned: Array[StringName] = []
	for id: StringName in IDS:
		if id == &"carbine":
			continue
		(owned if unlocked.has(id) else missing).append(id)
	var pool := missing if (not missing.is_empty() and (r < 0.5 or owned.is_empty())) else owned
	if pool.is_empty():
		return &"scatter"
	return pool[mini(int(rng_pick * pool.size()), pool.size() - 1)]
