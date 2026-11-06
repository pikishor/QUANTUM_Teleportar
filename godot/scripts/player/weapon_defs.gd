class_name WeaponDefs
extends RefCounted
## The four alien weapons as data (PlayerWeapon reads them) plus the unlocked set (static, like Upgrades.levels: the player, the shop, the HUD and the save file all see it).
##   carbine  Rift Carbine: the default hitscan rifle (the numbers of the original PlayerWeapon constants; its reserve is unlimited).
##   scatter  Shard Scatter: 8 pellets in a wide cone, each pellet rolls the head test on its own (a crit is 2x the pellet), full damage to 12 m, 25 % at 38 m.
##   lance    Pulse Lance: hold to charge (1.1 s, glow at the muzzle and a bar on the HUD), release for a piercing hitscan through every enemy on the line; ADS zooms to 24 degrees.
##   grenade  Singularity Grenade: thrown in an arc, lands, a gravity well pulls and burns everything within 9 m for 1.6 s, then it collapses into Game.explode.
## kind: "hit" (hitscan, pellets), "charge" (lance), "throw" (grenade), "melee" (whip, blade: a 3-step combo, no ammo).
## Wave 61 weapons: minigun (spin_up / heat_per / heat_lock: slow to start, fast once spun, overheats), akimbo (twin: shots alternate hands), arc (chain: a hit jumps to nearby enemies),
## revolver (slow heavy rounds, FAN HAMMER alt), whip (long reach, PULL alt), blade (short reach, LUNGE alt). "snd" = the sound name of a shot (default "shot"). reserve < 0 = unlimited spare ammo. look = the emissive tint of the strip on the rifle.

const IDS: Array[StringName] = [&"carbine", &"scatter", &"lance", &"grenade", &"burst", &"rail", &"flux", &"gravity", &"minigun", &"akimbo", &"arc", &"revolver", &"whip", &"blade"]
const PAGE_SIZE := 8                       ## weapons per page of the touch weapon wheel

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
		"pattern": [Vector2(0.0, 1.0), Vector2(-0.4, 1.15), Vector2(0.4, 1.15)], "shake": 0.14, "vol": -1.0, "pitch_lo": 0.94, "pitch_hi": 1.06, "snd": &"shot_scatter", "eject": 0, "flash": 1.7, "ads_kick": 0.8, "ads_spread": 0.67,
		"spread_hip": 0.075, "spread_ads": 0.05, "spread_move": 0.015, "bloom": 0.0, "bloom_max": 0.0,
		"kick": 0.042, "kick_end": 0.042, "kick_yaw": 0.012, "reload": 1.9, "range": 38.0, "falloff_from": 12.0,
		"tracer": Color(0.45, 1.0, 0.82), "look": Color(0.3, 1.0, 0.75), "look_size": Vector3(0.1, 0.07, 0.34), "zoom": 56.0, "price": 500, "pierce_shield": false,
	},
	&"lance": {
		"name": "PULSE LANCE", "tag": "LNC", "kind": "charge", "mag": 5, "reserve": 20, "interval": 0.5, "damage": 120.0, "crit": 200.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.22, "vol": 0.0, "pitch_lo": 0.96, "pitch_hi": 1.04, "eject": 0, "flash": 2.0, "ads_kick": 0.5, "ads_spread": 0.05,
		"spread_hip": 0.012, "spread_ads": 0.0006, "spread_move": 0.02, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_lance", "charge_time": 1.1, "min_charge": 0.35,
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
	&"burst": {
		"name": "ARC BURST PISTOL", "tag": "BRP", "kind": "hit", "mag": 18, "reserve": 90, "interval": 0.42, "damage": 12.0, "crit": 26.0, "pellets": 1, "burst": 3, "burst_gap": 0.065,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 1.1), Vector2(-0.2, 1.2)], "shake": 0.04, "vol": -3.0, "pitch_lo": 1.0, "pitch_hi": 1.08, "eject": 1, "flash": 1.0, "ads_kick": 0.5, "ads_spread": 0.4,
		"spread_hip": 0.012, "spread_ads": 0.003, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.02, "snd": &"shot_burst",
		"kick": 0.008, "kick_end": 0.008, "kick_yaw": 0.003, "reload": 1.1, "range": 150.0, "falloff_from": 60.0,
		"tracer": Color(1.0, 0.55, 0.9), "look": Color(1.0, 0.45, 0.85), "look_size": Vector3(0.03, 0.03, 0.3), "zoom": 58.0, "price": 400, "pierce_shield": false,
	},
	&"rail": {
		"name": "RAIL RIFLE", "tag": "RAL", "kind": "hit", "mag": 4, "reserve": 24, "interval": 1.0, "damage": 85.0, "crit": 170.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.18, "vol": -1.0, "pitch_lo": 0.97, "pitch_hi": 1.03, "eject": 0, "flash": 2.2, "ads_kick": 0.4, "ads_spread": 0.1,
		"spread_hip": 0.02, "spread_ads": 0.0008, "spread_move": 0.02, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_rail",
		"kick": 0.045, "kick_end": 0.045, "kick_yaw": 0.004, "reload": 2.0, "range": 400.0, "falloff_from": 9999.0,
		"tracer": Color(0.6, 0.9, 1.0), "look": Color(0.5, 0.85, 1.0), "look_size": Vector3(0.025, 0.025, 0.65), "zoom": 32.0, "price": 950, "pierce_shield": true,
	},
	&"flux": {
		"name": "FLUX SMG", "tag": "FLX", "kind": "hit", "mag": 45, "reserve": 260, "interval": 0.055, "damage": 7.5, "crit": 15.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.5, 0.8), Vector2(-0.6, 0.8), Vector2(0.3, 0.7), Vector2(-0.4, 0.7)], "shake": 0.02, "vol": -4.0, "pitch_lo": 0.95, "pitch_hi": 1.1, "eject": 1, "flash": 0.8, "ads_kick": 0.7, "ads_spread": 0.5,
		"spread_hip": 0.022, "spread_ads": 0.009, "spread_move": 0.012, "bloom": 0.0045, "bloom_max": 0.045, "snd": &"shot_flux",
		"kick": 0.005, "kick_end": 0.0035, "kick_yaw": 0.004, "reload": 1.5, "range": 90.0, "falloff_from": 25.0,
		"tracer": Color(0.7, 1.0, 0.5), "look": Color(0.6, 1.0, 0.4), "look_size": Vector3(0.05, 0.04, 0.4), "zoom": 60.0, "price": 600, "pierce_shield": false,
	},
	&"gravity": {
		"name": "GRAVITY LAUNCHER", "tag": "GVL", "kind": "throw", "mag": 3, "reserve": 9, "interval": 1.3, "damage": 65.0, "crit": 65.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.09, "vol": -2.0, "pitch_lo": 0.97, "pitch_hi": 1.03, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_gravity",
		"kick": 0.03, "kick_end": 0.03, "kick_yaw": 0.0, "reload": 2.2, "range": 80.0, "falloff_from": 9999.0,
		"tracer": Color(0.5, 0.4, 1.0), "look": Color(0.45, 0.35, 1.0), "look_size": Vector3(0.14, 0.1, 0.3), "zoom": 56.0, "price": 1100, "pierce_shield": true,
		"speed": 30.0, "fuse": 1.4, "well_time": 2.4, "well_radius": 12.0, "well_pull": 12.0, "well_dps": 16.0, "blast_radius": 5.0,
		# open world freedom: the launcher is a GRENADE LAUNCHER, the round blows on impact (a short pull first), hard on cars and cover
		"impact": true, "blast_damage": 130.0, "car_dmg": 110.0, "blast_color": Color(1.0, 0.6, 0.2), "impact_pull": 4.0,
	},
	&"minigun": {
		"name": "PLASMA MINIGUN", "tag": "PMG", "kind": "hit", "mag": 120, "reserve": 480, "interval": 0.05, "damage": 6.5, "crit": 12.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.8), Vector2(0.4, 0.7), Vector2(-0.4, 0.7), Vector2(0.2, 0.6), Vector2(-0.2, 0.6)], "shake": 0.015, "vol": -6.0, "pitch_lo": 0.95, "pitch_hi": 1.05, "eject": 0, "flash": 0.9, "ads_kick": 0.7, "ads_spread": 0.6,
		"spread_hip": 0.03, "spread_ads": 0.016, "spread_move": 0.02, "bloom": 0.003, "bloom_max": 0.05, "snd": &"shot_mini",
		"kick": 0.003, "kick_end": 0.002, "kick_yaw": 0.003, "reload": 3.0, "range": 80.0, "falloff_from": 25.0,
		"spin_up": 0.8, "spin_ready": 0.35, "heat_per": 0.012, "heat_cool": 0.35, "heat_lock": 1.8,
		"tracer": Color(1.0, 0.45, 0.25), "look": Color(1.0, 0.4, 0.2), "look_size": Vector3(0.09, 0.09, 0.55), "zoom": 64.0, "price": 1400, "pierce_shield": false,
	},
	&"akimbo": {
		"name": "TWIN PISTOLS", "tag": "TWN", "kind": "hit", "mag": 24, "reserve": 200, "interval": 0.14, "damage": 13.5, "crit": 29.0, "pellets": 1, "twin": true,
		"pattern": [Vector2(-1.0, 0.9), Vector2(1.0, 0.9)], "shake": 0.03, "vol": -3.0, "pitch_lo": 1.0, "pitch_hi": 1.12, "eject": 1, "flash": 1.0, "ads_kick": 0.6, "ads_spread": 0.6,
		"spread_hip": 0.018, "spread_ads": 0.01, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.03, "snd": &"shot_twin",
		"kick": 0.006, "kick_end": 0.005, "kick_yaw": 0.005, "reload": 1.6, "range": 110.0, "falloff_from": 40.0,
		"tracer": Color(1.0, 0.9, 0.4), "look": Color(1.0, 0.85, 0.35), "look_size": Vector3(0.05, 0.04, 0.26), "zoom": 60.0, "price": 700, "pierce_shield": false,
	},
	&"arc": {
		"name": "ARC CASTER", "tag": "ARC", "kind": "hit", "mag": 14, "reserve": 70, "interval": 0.3, "damage": 20.0, "crit": 34.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.3, 0.8), Vector2(-0.3, 0.8)], "shake": 0.05, "vol": -2.0, "pitch_lo": 0.95, "pitch_hi": 1.08, "eject": 0, "flash": 1.2, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.016, "spread_ads": 0.005, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.02, "snd": &"shot_arc",
		"kick": 0.01, "kick_end": 0.008, "kick_yaw": 0.003, "reload": 1.7, "range": 120.0, "falloff_from": 50.0,
		"chain": 3, "chain_range": 9.0, "chain_k": 0.6,
		"tracer": Color(0.55, 0.85, 1.0), "look": Color(0.5, 0.8, 1.0), "look_size": Vector3(0.05, 0.05, 0.42), "zoom": 58.0, "price": 850, "pierce_shield": true,
	},
	&"revolver": {
		"name": "SPIKE REVOLVER", "tag": "REV", "kind": "hit", "mag": 6, "reserve": 42, "interval": 0.55, "damage": 48.0, "crit": 110.0, "pellets": 1,
		"pattern": [Vector2(0.2, 1.4), Vector2(-0.3, 1.3)], "shake": 0.12, "vol": 0.0, "pitch_lo": 0.8, "pitch_hi": 0.9, "eject": 0, "flash": 1.6, "ads_kick": 0.55, "ads_spread": 0.3,
		"spread_hip": 0.012, "spread_ads": 0.002, "spread_move": 0.014, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_rev", "burst_gap": 0.1,
		"kick": 0.032, "kick_end": 0.03, "kick_yaw": 0.006, "reload": 2.2, "range": 170.0, "falloff_from": 70.0,
		"tracer": Color(1.0, 0.75, 0.35), "look": Color(1.0, 0.65, 0.3), "look_size": Vector3(0.05, 0.05, 0.3), "zoom": 50.0, "price": 750, "pierce_shield": false,
	},
	&"whip": {
		"name": "ARC WHIP", "tag": "WHP", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.38, "damage": 30.0, "crit": 30.0, "pellets": 1,
		"pattern": [Vector2(0.6, 0.3), Vector2(-0.6, 0.3), Vector2(0.0, 0.6)], "shake": 0.05, "vol": -4.0, "pitch_lo": 0.95, "pitch_hi": 1.05, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_whip",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.004, "reload": 1.0, "range": 6.0, "falloff_from": 9999.0,
		"reach": 6.0, "cone": 0.55, "combo": [1.0, 1.0, 1.9], "combo_window": 0.9,
		"tracer": Color(0.5, 0.9, 1.0), "look": Color(0.45, 0.85, 1.0), "look_size": Vector3(0.03, 0.03, 0.5), "zoom": 62.0, "price": 600, "pierce_shield": false,
	},
	&"blade": {
		"name": "QUANTUM BLADE", "tag": "BLD", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.32, "damage": 38.0, "crit": 38.0, "pellets": 1,
		"pattern": [Vector2(-0.8, 0.2), Vector2(0.8, 0.2), Vector2(0.0, 0.5)], "shake": 0.07, "vol": -4.0, "pitch_lo": 0.95, "pitch_hi": 1.05, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_blade",
		"kick": 0.012, "kick_end": 0.012, "kick_yaw": 0.005, "reload": 1.0, "range": 3.6, "falloff_from": 9999.0,
		"reach": 3.6, "cone": 0.15, "combo": [1.0, 1.15, 2.3], "combo_window": 0.8,
		"tracer": Color(0.7, 0.55, 1.0), "look": Color(0.65, 0.5, 1.0), "look_size": Vector3(0.04, 0.04, 0.8), "zoom": 62.0, "price": 900, "pierce_shield": true,
	},
}

## Alt-fire per class (key B / the ALT touch button). kind: "heavy" = one aimed shot x mult for `cost` rounds (slug / overcharge), "volley" = `count` rounds in a rapid burst,
## "quick" = an instant full-charge lance shot, "cluster" = a pair of grenades thrown in a fan. cd = seconds before anything fires again.
const ALTS := {
	&"carbine": {"name": "OVERCHARGE", "kind": "heavy", "cost": 4, "mult": 3.2, "cd": 0.9},
	&"scatter": {"name": "SLUG", "kind": "heavy", "cost": 1, "mult": 5.5, "cd": 1.0},
	&"lance": {"name": "FULL PIERCE", "kind": "quick", "cost": 2, "mult": 1.0, "cd": 1.4},
	&"grenade": {"name": "CLUSTER", "kind": "cluster", "cost": 1, "mult": 1.0, "cd": 1.3},
	&"burst": {"name": "VOLLEY", "kind": "volley", "cost": 6, "count": 6, "cd": 0.8},
	&"rail": {"name": "OVERCHARGE", "kind": "heavy", "cost": 2, "mult": 2.2, "cd": 1.3},
	&"flux": {"name": "VOLLEY", "kind": "volley", "cost": 12, "count": 12, "cd": 0.7},
	&"gravity": {"name": "CLUSTER", "kind": "cluster", "cost": 1, "mult": 1.0, "cd": 1.6},
	&"minigun": {"name": "VENT", "kind": "vent", "cost": 0, "cd": 0.8},
	&"akimbo": {"name": "FAN", "kind": "volley", "cost": 8, "count": 8, "cd": 0.9},
	&"arc": {"name": "OVERLOAD", "kind": "heavy", "cost": 3, "mult": 2.6, "cd": 1.2},
	&"revolver": {"name": "FAN HAMMER", "kind": "volley", "cost": 6, "count": 6, "cd": 1.2},
	&"whip": {"name": "PULL", "kind": "pull", "cost": 0, "range": 12.0, "cd": 1.6},
	&"blade": {"name": "LUNGE", "kind": "lunge", "cost": 0, "dist": 4.5, "mult": 2.5, "cd": 1.4},
}
## Ammo types for the hitscan weapons (key T): damage multiplier, fire-interval multiplier, shield piercing.
const AMMO_TYPES := [
	{"id": &"standard", "name": "STANDARD", "dmg": 1.0, "rate": 1.0, "pierce": false},
	{"id": &"heavy", "name": "HEAVY", "dmg": 1.3, "rate": 1.25, "pierce": false},
	{"id": &"piercing", "name": "PIERCING", "dmg": 0.85, "rate": 1.0, "pierce": true},
]
## Weapon-specific hit sound: [pitch, volume db, extra layer or &""]. Reload tilt: how far the rifle rolls during the reload / inspect (1 = rig default).
const HIT_SND := {
	&"carbine": [1.0, 0.0, &""], &"scatter": [0.7, 2.0, &"impact_concrete"], &"lance": [0.55, 3.0, &"impact_metal"], &"grenade": [0.8, 0.0, &""],
	&"burst": [1.35, -2.0, &""], &"rail": [0.5, 4.0, &"impact_metal"], &"flux": [1.6, -5.0, &""], &"gravity": [0.65, 1.0, &""],
	&"minigun": [1.5, -6.0, &""], &"akimbo": [1.2, -2.0, &""], &"arc": [1.1, 0.0, &"impact_metal"], &"revolver": [0.6, 3.0, &"impact_concrete"], &"whip": [0.9, 0.0, &""], &"blade": [0.75, 2.0, &"impact_metal"],
}
const TILT := {&"carbine": 1.0, &"scatter": 1.6, &"lance": 0.7, &"grenade": 1.2, &"burst": 1.4, &"rail": 0.8, &"flux": 1.8, &"gravity": 1.3, &"minigun": 2.0, &"akimbo": 1.5, &"arc": 1.0, &"revolver": 1.1, &"whip": 0.5, &"blade": 0.5}


static func alt_of(id: StringName) -> Dictionary:
	return ALTS.get(id, ALTS[&"carbine"])


static func hit_snd(id: StringName) -> Array:
	return HIT_SND.get(id, HIT_SND[&"carbine"])


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
	return maxi(5, int(roundf(float(Economy.weapon_price(id)) * (1.0 - discount) / 5.0)) * 5)


## Magazine size with the shop's magazine upgrade, per weapon: +20 % of the weapon's own base per level (the carbine keeps its +6), small magazines at least +1 every second level.
static func mag_size(id: StringName, level: int) -> int:
	var base := int(Attachments.effective(id)["mag"])
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


## Number of pages of the touch weapon wheel for n weapons (PAGE_SIZE each).
static func pages_for(n: int) -> int:
	return maxi(1, (n + PAGE_SIZE - 1) / PAGE_SIZE)
