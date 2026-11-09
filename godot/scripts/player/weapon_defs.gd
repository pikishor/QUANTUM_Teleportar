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

## Order = keys 1..8 and the order every list shows: the seven starters first (pistol, SMG, assault rifle, shotgun, sniper rail, launcher, melee), then the unlock ladder.
const IDS: Array[StringName] = [&"pistol", &"flux", &"carbine", &"scatter", &"rail", &"gravity", &"blade", &"marksman", &"burst", &"revolver", &"akimbo", &"breacher", &"arc", &"lance", &"whip", &"rocket", &"minigun", &"grenade", &"swarm", &"vector", &"battle", &"sawn", &"auto", &"bolt", &"dmr", &"knife", &"magnum", &"mpistol", &"ranger", &"bullpup", &"lmg", &"amr", &"xbow", &"flame", &"stun", &"katana", &"bat", &"qsuper", &"qlink", &"qcollapse", &"qblink", &"qphase", &"qstasis",
	&"eplasma", &"erepeat", &"espike", &"ebeam", &"eblade", &"emaul", &"epod", &"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker", &"tknife"]
## Owned from the first minute (and in every save): one weapon of each class so the hero is never short of a gun. Everything else is on the ladder (scripts/progress/weapon_ladder.gd).
const STARTERS: Array[StringName] = [&"pistol", &"flux", &"carbine", &"scatter", &"rail", &"gravity", &"blade"]
## The weapon wheel groups the weapons by class (one wedge per class, tap again = the next weapon of that class).
const CLASS_ORDER: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun", &"sniper", &"heavy", &"melee", &"quantum", &"energy", &"blast"]
const CLASS_NAMES := {&"pistol": "PISTOL", &"smg": "SMG", &"rifle": "RIFLE", &"shotgun": "SHOTGUN", &"sniper": "SNIPER", &"heavy": "HEAVY", &"melee": "MELEE", &"quantum": "QUANTUM", &"energy": "ENERGY", &"blast": "BLAST"}
const CLASS_OF := {
	&"pistol": &"pistol", &"burst": &"pistol", &"akimbo": &"pistol", &"revolver": &"pistol", &"flux": &"smg", &"carbine": &"rifle", &"marksman": &"rifle", &"arc": &"rifle",
	&"scatter": &"shotgun", &"breacher": &"shotgun", &"rail": &"sniper", &"lance": &"sniper", &"gravity": &"heavy", &"rocket": &"heavy", &"grenade": &"heavy", &"minigun": &"heavy",
	&"blade": &"melee", &"whip": &"melee",
	&"swarm": &"smg", &"vector": &"smg", &"battle": &"rifle", &"sawn": &"shotgun", &"auto": &"shotgun", &"bolt": &"sniper", &"dmr": &"sniper", &"knife": &"melee",
	&"magnum": &"pistol", &"mpistol": &"pistol", &"stun": &"pistol", &"ranger": &"rifle", &"bullpup": &"rifle", &"lmg": &"heavy", &"flame": &"heavy", &"amr": &"sniper", &"xbow": &"sniper",
	&"katana": &"melee", &"bat": &"melee", &"qsuper": &"quantum", &"qlink": &"quantum", &"qcollapse": &"quantum", &"qblink": &"quantum", &"qphase": &"quantum", &"qstasis": &"quantum",
	&"eplasma": &"energy", &"erepeat": &"energy", &"espike": &"energy", &"ebeam": &"energy", &"eblade": &"energy", &"emaul": &"energy", &"epod": &"energy",
	&"railgun": &"blast", &"chaingun": &"blast", &"cmissile": &"blast", &"napalm": &"blast", &"sing": &"blast", &"orbital": &"blast", &"seeker": &"blast", &"tknife": &"melee",
}
const PAGE_SIZE := 8                       ## weapons per page of the touch weapon wheel

const DEFS := {
	&"pistol": {
		"name": "VOLT PISTOL", "tag": "PST", "kind": "hit", "mag": 15, "reserve": -1, "interval": 0.2, "damage": 22.0, "crit": 46.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 1.1), Vector2(-0.25, 1.0)], "shake": 0.03, "vol": -3.0, "pitch_lo": 0.92, "pitch_hi": 1.0, "eject": 1, "flash": 0.9, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.012, "spread_ads": 0.0035, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.02, "snd": &"shot_twin",
		"kick": 0.012, "kick_end": 0.01, "kick_yaw": 0.003, "reload": 1.0, "range": 120.0, "falloff_from": 45.0,
		"tracer": Color(1.0, 0.95, 0.6), "look": Color(1.0, 0.85, 0.35), "look_size": Vector3(0.03, 0.03, 0.22), "zoom": 60.0, "price": 0, "pierce_shield": false,
	},
	&"marksman": {
		"name": "PHASE MARKSMAN", "tag": "MRK", "kind": "hit", "mag": 12, "reserve": 72, "interval": 0.34, "damage": 36.0, "crit": 84.0, "pellets": 1,
		"pattern": [Vector2(0.1, 1.2), Vector2(-0.1, 1.1)], "shake": 0.08, "vol": -1.5, "pitch_lo": 1.12, "pitch_hi": 1.2, "eject": 1, "flash": 1.3, "ads_kick": 0.5, "ads_spread": 0.15,
		"spread_hip": 0.016, "spread_ads": 0.0015, "spread_move": 0.016, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_rev",
		"kick": 0.02, "kick_end": 0.02, "kick_yaw": 0.004, "reload": 1.7, "range": 300.0, "falloff_from": 9999.0,
		"tracer": Color(0.55, 1.0, 0.7), "look": Color(0.4, 1.0, 0.6), "look_size": Vector3(0.03, 0.03, 0.7), "zoom": 40.0, "price": 650, "pierce_shield": false,
	},
	&"breacher": {
		"name": "SHARD BREACHER", "tag": "BRC", "kind": "hit", "mag": 8, "reserve": 48, "interval": 0.44, "damage": 8.0, "crit": 16.0, "pellets": 7,
		"pattern": [Vector2(0.0, 1.0), Vector2(-0.3, 1.1), Vector2(0.3, 1.1)], "shake": 0.12, "vol": -1.5, "pitch_lo": 1.05, "pitch_hi": 1.15, "snd": &"shot_scatter", "eject": 1, "flash": 1.5, "ads_kick": 0.8, "ads_spread": 0.7,
		"spread_hip": 0.065, "spread_ads": 0.045, "spread_move": 0.015, "bloom": 0.0, "bloom_max": 0.0,
		"kick": 0.032, "kick_end": 0.03, "kick_yaw": 0.008, "reload": 2.3, "range": 34.0, "falloff_from": 11.0,
		"tracer": Color(1.0, 0.6, 0.3), "look": Color(1.0, 0.5, 0.2), "look_size": Vector3(0.1, 0.07, 0.34), "zoom": 56.0, "price": 800, "pierce_shield": false,
	},
	&"rocket": {
		"name": "NOVA LAUNCHER", "tag": "NVA", "kind": "throw", "mag": 1, "reserve": 6, "interval": 1.1, "damage": 220.0, "crit": 220.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.16, "vol": -1.0, "pitch_lo": 0.72, "pitch_hi": 0.78, "flash": 0.0, "eject": 0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_gravity",
		"kick": 0.045, "kick_end": 0.045, "kick_yaw": 0.0, "reload": 2.6, "range": 140.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.55, 0.2), "look": Color(1.0, 0.5, 0.2), "look_size": Vector3(0.14, 0.14, 0.5), "zoom": 52.0, "price": 1500, "pierce_shield": true,
		"speed": 46.0, "fuse": 2.6, "grav": 5.0, "well_time": 0.1, "well_radius": 8.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 7.0,
		"impact": true, "blast_damage": 220.0, "car_dmg": 200.0, "blast_color": Color(1.0, 0.5, 0.15), "impact_pull": 0.0,
	},
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
		"spread_hip": 0.018, "spread_ads": 0.008, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.03, "snd": &"shot_flux",
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
		"spread_hip": 0.024, "spread_ads": 0.012, "spread_move": 0.02, "bloom": 0.003, "bloom_max": 0.034, "snd": &"shot_mini",
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
	# --- round 4: eight more weapons, so every class has three or four (models: CC0 Quaternius Ultimate Gun Pack, tools/open_models/convert_weapons.py)
	&"swarm": {
		"name": "SWARM PDW", "tag": "SWM", "kind": "hit", "mag": 36, "reserve": 216, "interval": 0.07, "damage": 8.5, "crit": 17.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.7), Vector2(0.5, 0.7), Vector2(-0.6, 0.6), Vector2(0.4, 0.6), Vector2(-0.3, 0.6)], "shake": 0.02, "vol": -4.5, "pitch_lo": 1.2, "pitch_hi": 1.34, "eject": 1, "flash": 0.7, "ads_kick": 0.7, "ads_spread": 0.55,
		"spread_hip": 0.022, "spread_ads": 0.01, "spread_move": 0.012, "bloom": 0.005, "bloom_max": 0.036, "snd": &"shot_flux",
		"kick": 0.0045, "kick_end": 0.003, "kick_yaw": 0.0045, "reload": 1.2, "range": 55.0, "falloff_from": 14.0,
		"tracer": Color(1.0, 0.8, 0.45), "look": Color(1.0, 0.75, 0.3), "look_size": Vector3(0.04, 0.04, 0.3), "zoom": 62.0, "price": 450, "pierce_shield": false,
	},
	&"vector": {
		"name": "VECTOR HEAVY SMG", "tag": "VEC", "kind": "hit", "mag": 24, "reserve": 144, "interval": 0.15, "damage": 16.0, "crit": 34.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 1.0), Vector2(-0.3, 0.9), Vector2(0.4, 0.9)], "shake": 0.035, "vol": -2.5, "pitch_lo": 0.85, "pitch_hi": 0.95, "eject": 1, "flash": 1.1, "ads_kick": 0.6, "ads_spread": 0.35,
		"spread_hip": 0.016, "spread_ads": 0.005, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.024, "snd": &"shot_burst",
		"kick": 0.011, "kick_end": 0.007, "kick_yaw": 0.004, "reload": 1.5, "range": 85.0, "falloff_from": 30.0,
		"tracer": Color(1.0, 0.5, 0.6), "look": Color(1.0, 0.4, 0.55), "look_size": Vector3(0.04, 0.04, 0.38), "zoom": 58.0, "price": 750, "pierce_shield": false,
	},
	&"battle": {
		"name": "ION BATTLE RIFLE", "tag": "BTL", "kind": "hit", "mag": 20, "reserve": 100, "interval": 0.24, "damage": 32.0, "crit": 72.0, "pellets": 1,
		"pattern": [Vector2(0.1, 1.2), Vector2(-0.2, 1.1), Vector2(0.3, 1.0)], "shake": 0.06, "vol": -1.5, "pitch_lo": 0.82, "pitch_hi": 0.9, "eject": 1, "flash": 1.3, "ads_kick": 0.55, "ads_spread": 0.2,
		"spread_hip": 0.016, "spread_ads": 0.002, "spread_move": 0.014, "bloom": 0.002, "bloom_max": 0.012, "snd": &"shot",
		"kick": 0.02, "kick_end": 0.016, "kick_yaw": 0.004, "reload": 1.9, "range": 260.0, "falloff_from": 90.0,
		"tracer": Color(0.5, 0.9, 1.0), "look": Color(0.4, 0.85, 1.0), "look_size": Vector3(0.035, 0.035, 0.5), "zoom": 46.0, "price": 900, "pierce_shield": false,
	},
	&"sawn": {
		"name": "SAWN SPLITTER", "tag": "SWN", "kind": "hit", "mag": 2, "reserve": 24, "interval": 0.45, "damage": 8.0, "crit": 16.0, "pellets": 12,
		"pattern": [Vector2(0.0, 1.0), Vector2(-0.5, 1.3)], "shake": 0.16, "vol": -0.5, "pitch_lo": 0.8, "pitch_hi": 0.9, "snd": &"shot_scatter", "eject": 1, "flash": 1.8, "ads_kick": 0.8, "ads_spread": 0.7,
		"spread_hip": 0.095, "spread_ads": 0.07, "spread_move": 0.015, "bloom": 0.0, "bloom_max": 0.0,
		"kick": 0.05, "kick_end": 0.045, "kick_yaw": 0.012, "reload": 1.7, "range": 24.0, "falloff_from": 7.0,
		"tracer": Color(1.0, 0.6, 0.3), "look": Color(1.0, 0.5, 0.2), "look_size": Vector3(0.09, 0.06, 0.3), "zoom": 58.0, "price": 600, "pierce_shield": false,
	},
	&"auto": {
		"name": "STORM AUTOSHOT", "tag": "STM", "kind": "hit", "mag": 10, "reserve": 60, "interval": 0.26, "damage": 7.0, "crit": 14.0, "pellets": 6,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.3, 1.1), Vector2(-0.3, 1.1)], "shake": 0.1, "vol": -1.5, "pitch_lo": 1.0, "pitch_hi": 1.1, "snd": &"shot_scatter", "eject": 1, "flash": 1.4, "ads_kick": 0.8, "ads_spread": 0.65,
		"spread_hip": 0.06, "spread_ads": 0.04, "spread_move": 0.015, "bloom": 0.002, "bloom_max": 0.02,
		"kick": 0.026, "kick_end": 0.022, "kick_yaw": 0.007, "reload": 2.2, "range": 40.0, "falloff_from": 14.0,
		"tracer": Color(0.5, 1.0, 0.7), "look": Color(0.35, 1.0, 0.65), "look_size": Vector3(0.09, 0.06, 0.4), "zoom": 56.0, "price": 800, "pierce_shield": false,
	},
	&"bolt": {
		"name": "VOID BOLT RIFLE", "tag": "BLT", "kind": "hit", "mag": 5, "reserve": 30, "interval": 1.35, "damage": 105.0, "crit": 210.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.2, "vol": -0.5, "pitch_lo": 0.74, "pitch_hi": 0.8, "eject": 1, "flash": 2.0, "ads_kick": 0.4, "ads_spread": 0.1,
		"spread_hip": 0.024, "spread_ads": 0.0006, "spread_move": 0.024, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_rail",
		"kick": 0.05, "kick_end": 0.05, "kick_yaw": 0.005, "reload": 2.4, "range": 450.0, "falloff_from": 9999.0,
		"tracer": Color(0.8, 0.5, 1.0), "look": Color(0.7, 0.4, 1.0), "look_size": Vector3(0.025, 0.025, 0.7), "zoom": 22.0, "price": 1100, "pierce_shield": true,
	},
	&"dmr": {
		"name": "RANGE MARKSMAN DMR", "tag": "DMR", "kind": "hit", "mag": 10, "reserve": 60, "interval": 0.48, "damage": 48.0, "crit": 96.0, "pellets": 1,
		"pattern": [Vector2(0.1, 1.1), Vector2(-0.15, 1.0)], "shake": 0.08, "vol": -1.5, "pitch_lo": 0.95, "pitch_hi": 1.02, "eject": 1, "flash": 1.4, "ads_kick": 0.5, "ads_spread": 0.12,
		"spread_hip": 0.018, "spread_ads": 0.001, "spread_move": 0.018, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_rev",
		"kick": 0.026, "kick_end": 0.024, "kick_yaw": 0.004, "reload": 1.9, "range": 340.0, "falloff_from": 9999.0,
		"tracer": Color(0.9, 1.0, 0.55), "look": Color(0.8, 1.0, 0.45), "look_size": Vector3(0.03, 0.03, 0.62), "zoom": 34.0, "price": 950, "pierce_shield": false,
	},
	&"knife": {
		"name": "PHASE KNIFE", "tag": "KNF", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.22, "damage": 20.0, "crit": 20.0, "pellets": 1,
		"pattern": [Vector2(-0.6, 0.15), Vector2(0.6, 0.15), Vector2(0.0, 0.3)], "shake": 0.04, "vol": -4.0, "pitch_lo": 1.15, "pitch_hi": 1.3, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_blade",
		"kick": 0.008, "kick_end": 0.008, "kick_yaw": 0.004, "reload": 1.0, "range": 2.4, "falloff_from": 9999.0,
		"reach": 2.4, "cone": 0.3, "combo": [1.0, 1.0, 1.8], "combo_window": 0.7,
		"tracer": Color(0.7, 0.9, 1.0), "look": Color(0.6, 0.85, 1.0), "look_size": Vector3(0.03, 0.03, 0.4), "zoom": 62.0, "price": 400, "pierce_shield": false,
	},
	# --- round 5 roster (docs/DESIGN.md: all the top COD / GTA weapon types with generic names): heavy and machine pistols, two more assault rifles, an LMG, an anti-material rifle, a crossbow,
	# a flamethrower, a stun gun, a katana and a bat, then the six QUANTUM weapons. Models: CC0 Quaternius pack where it has the shape (tools/open_models/convert_weapons.py), else procedural (weapon_models.gd).
	# New keys: silent (no noise for the AI), wall + wall_k (rounds pass that many world surfaces, each at wall_k of the damage), stun (seconds an enemy is frozen), burn + burn_time (damage per second over time),
	# flame (a spray of fire instead of a tracer line).
	&"magnum": {
		"name": "HAMMER HEAVY PISTOL", "tag": "HMR", "kind": "hit", "mag": 8, "reserve": 56, "interval": 0.31, "damage": 40.0, "crit": 88.0, "pellets": 1,
		"pattern": [Vector2(0.15, 1.5), Vector2(-0.2, 1.4), Vector2(0.1, 1.3)], "shake": 0.1, "vol": -0.5, "pitch_lo": 0.8, "pitch_hi": 0.9, "eject": 1, "flash": 1.7, "ads_kick": 0.55, "ads_spread": 0.3,
		"spread_hip": 0.013, "spread_ads": 0.0025, "spread_move": 0.014, "bloom": 0.003, "bloom_max": 0.014, "snd": &"shot_magnum",
		"kick": 0.03, "kick_end": 0.026, "kick_yaw": 0.006, "reload": 1.7, "range": 160.0, "falloff_from": 65.0,
		"tracer": Color(1.0, 0.7, 0.3), "look": Color(1.0, 0.6, 0.25), "look_size": Vector3(0.04, 0.04, 0.26), "zoom": 56.0, "price": 900, "pierce_shield": false,
	},
	&"mpistol": {
		"name": "STING MACHINE PISTOL", "tag": "STG", "kind": "hit", "mag": 30, "reserve": 150, "interval": 0.065, "damage": 9.0, "crit": 18.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.8), Vector2(0.5, 0.8), Vector2(-0.6, 0.7), Vector2(0.3, 0.7), Vector2(-0.4, 0.7)], "shake": 0.02, "vol": -4.0, "pitch_lo": 1.05, "pitch_hi": 1.2, "eject": 1, "flash": 0.8, "ads_kick": 0.7, "ads_spread": 0.55,
		"spread_hip": 0.024, "spread_ads": 0.011, "spread_move": 0.012, "bloom": 0.005, "bloom_max": 0.034, "snd": &"shot_mp",
		"kick": 0.0045, "kick_end": 0.003, "kick_yaw": 0.005, "reload": 1.2, "range": 50.0, "falloff_from": 16.0,
		"tracer": Color(1.0, 0.85, 0.4), "look": Color(1.0, 0.8, 0.35), "look_size": Vector3(0.04, 0.04, 0.2), "zoom": 62.0, "price": 500, "pierce_shield": false,
	},
	&"stun": {
		"name": "VOLT STUN GUN", "tag": "STN", "kind": "hit", "mag": 8, "reserve": 40, "interval": 0.56, "damage": 34.0, "crit": 51.0, "pellets": 1, "stun": 2.2,
		"pattern": [Vector2(0.0, 0.8), Vector2(0.2, 0.8)], "shake": 0.05, "vol": -3.0, "pitch_lo": 0.95, "pitch_hi": 1.05, "eject": 0, "flash": 1.2, "ads_kick": 0.5, "ads_spread": 0.3,
		"spread_hip": 0.014, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_stun",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.003, "reload": 1.6, "range": 26.0, "falloff_from": 14.0,
		"tracer": Color(0.45, 0.8, 1.0), "look": Color(0.4, 0.75, 1.0), "look_size": Vector3(0.04, 0.04, 0.22), "zoom": 58.0, "price": 600, "pierce_shield": true,
	},
	&"ranger": {
		"name": "RANGER ASSAULT RIFLE", "tag": "RNG", "kind": "hit", "mag": 30, "reserve": 150, "interval": 0.12, "damage": 17.0, "crit": 36.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.1), Vector2(0.3, 1.1), Vector2(-0.5, 1.0), Vector2(0.6, 0.9), Vector2(-0.3, 0.9), Vector2(-0.7, 0.8)], "shake": 0.04, "vol": -1.5, "pitch_lo": 0.86, "pitch_hi": 0.95, "eject": 1, "flash": 1.2, "ads_kick": 0.6, "ads_spread": 0.28,
		"spread_hip": 0.015, "spread_ads": 0.0045, "spread_move": 0.011, "bloom": 0.0035, "bloom_max": 0.028, "snd": &"shot_ar2",
		"kick": 0.011, "kick_end": 0.0065, "kick_yaw": 0.004, "reload": 1.5, "range": 230.0, "falloff_from": 100.0,
		"tracer": Color(1.0, 0.8, 0.4), "look": Color(1.0, 0.65, 0.3), "look_size": Vector3(0.035, 0.035, 0.5), "zoom": 60.0, "price": 800, "pierce_shield": false,
	},
	&"bullpup": {
		"name": "BULLPUP BURST RIFLE", "tag": "BPR", "kind": "hit", "mag": 30, "reserve": 150, "interval": 0.33, "damage": 16.0, "crit": 34.0, "pellets": 1, "burst": 3, "burst_gap": 0.06,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 1.1), Vector2(-0.2, 1.2)], "shake": 0.04, "vol": -2.0, "pitch_lo": 1.0, "pitch_hi": 1.08, "eject": 1, "flash": 1.1, "ads_kick": 0.55, "ads_spread": 0.25,
		"spread_hip": 0.014, "spread_ads": 0.0035, "spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.02, "snd": &"shot_bpup",
		"kick": 0.009, "kick_end": 0.009, "kick_yaw": 0.003, "reload": 1.5, "range": 240.0, "falloff_from": 110.0,
		"tracer": Color(0.9, 1.0, 0.6), "look": Color(0.8, 1.0, 0.5), "look_size": Vector3(0.035, 0.035, 0.46), "zoom": 56.0, "price": 950, "pierce_shield": false,
	},
	&"lmg": {
		"name": "HAVOC LMG", "tag": "LMG", "kind": "hit", "mag": 100, "reserve": 300, "interval": 0.085, "damage": 12.0, "crit": 24.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.9), Vector2(0.3, 0.8), Vector2(-0.4, 0.8), Vector2(0.5, 0.7), Vector2(-0.2, 0.7)], "shake": 0.03, "vol": -2.5, "pitch_lo": 0.8, "pitch_hi": 0.88, "eject": 1, "flash": 1.3, "ads_kick": 0.65, "ads_spread": 0.4,
		"spread_hip": 0.02, "spread_ads": 0.007, "spread_move": 0.022, "bloom": 0.003, "bloom_max": 0.03, "snd": &"shot_lmg",
		"kick": 0.0055, "kick_end": 0.0038, "kick_yaw": 0.0035, "reload": 4.0, "range": 170.0, "falloff_from": 60.0,
		"tracer": Color(1.0, 0.75, 0.35), "look": Color(1.0, 0.6, 0.25), "look_size": Vector3(0.06, 0.06, 0.55), "zoom": 62.0, "price": 1600, "pierce_shield": false,
	},
	&"amr": {
		"name": "TITAN ANTI-MATERIAL RIFLE", "tag": "AMR", "kind": "hit", "mag": 5, "reserve": 25, "interval": 1.5, "damage": 160.0, "crit": 320.0, "pellets": 1, "wall": 1, "wall_k": 0.6,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.24, "vol": 1.0, "pitch_lo": 0.7, "pitch_hi": 0.76, "eject": 1, "flash": 2.4, "ads_kick": 0.4, "ads_spread": 0.1,
		"spread_hip": 0.026, "spread_ads": 0.0005, "spread_move": 0.026, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_amr",
		"kick": 0.06, "kick_end": 0.06, "kick_yaw": 0.005, "reload": 3.0, "range": 500.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.9, 0.55), "look": Color(1.0, 0.8, 0.4), "look_size": Vector3(0.05, 0.05, 0.9), "zoom": 18.0, "price": 1700, "pierce_shield": true,
	},
	&"xbow": {
		"name": "SILENT CROSSBOW", "tag": "XBW", "kind": "hit", "mag": 3, "reserve": 30, "interval": 0.92, "damage": 70.0, "crit": 160.0, "pellets": 1, "silent": true,
		"pattern": [Vector2(0.0, 0.8)], "shake": 0.04, "vol": -5.0, "pitch_lo": 0.95, "pitch_hi": 1.05, "eject": 0, "flash": 0.0, "ads_kick": 0.5, "ads_spread": 0.1,
		"spread_hip": 0.012, "spread_ads": 0.0008, "spread_move": 0.014, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_xbow",
		"kick": 0.012, "kick_end": 0.012, "kick_yaw": 0.002, "reload": 1.8, "range": 150.0, "falloff_from": 9999.0,
		"tracer": Color(0.85, 0.8, 0.6), "look": Color(0.8, 0.75, 0.5), "look_size": Vector3(0.04, 0.03, 0.5), "zoom": 40.0, "price": 750, "pierce_shield": false,
	},
	&"flame": {
		"name": "INFERNO FLAMETHROWER", "tag": "FLM", "kind": "hit", "mag": 100, "reserve": 300, "interval": 0.06, "damage": 3.5, "crit": 5.0, "pellets": 3, "flame": true, "burn": 5.0, "burn_time": 3.0,
		"pattern": [Vector2(0.0, 0.3), Vector2(0.2, 0.3)], "shake": 0.02, "vol": -3.0, "pitch_lo": 0.92, "pitch_hi": 1.08, "eject": 0, "flash": 1.6, "ads_kick": 0.8, "ads_spread": 0.8,
		"spread_hip": 0.07, "spread_ads": 0.05, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_flame",
		"kick": 0.002, "kick_end": 0.002, "kick_yaw": 0.002, "reload": 2.5, "range": 15.0, "falloff_from": 7.0,
		"tracer": Color(1.0, 0.55, 0.15), "look": Color(1.0, 0.5, 0.1), "look_size": Vector3(0.08, 0.08, 0.5), "zoom": 64.0, "price": 1500, "pierce_shield": false,
	},
	&"katana": {
		"name": "CARBON KATANA", "tag": "KTN", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.25, "damage": 34.0, "crit": 34.0, "pellets": 1,
		"pattern": [Vector2(-0.9, 0.2), Vector2(0.9, 0.2), Vector2(0.0, 0.5)], "shake": 0.06, "vol": -4.0, "pitch_lo": 0.98, "pitch_hi": 1.1, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_katana",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.005, "reload": 1.0, "range": 3.2, "falloff_from": 9999.0,
		"reach": 3.2, "cone": 0.2, "combo": [1.0, 1.0, 2.0], "combo_window": 0.75,
		"tracer": Color(0.85, 0.95, 1.0), "look": Color(0.8, 0.9, 1.0), "look_size": Vector3(0.03, 0.03, 0.9), "zoom": 62.0, "price": 900, "pierce_shield": true,
	},
	&"bat": {
		"name": "SLUGGER BAT", "tag": "BAT", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.52, "damage": 30.0, "crit": 30.0, "pellets": 1,
		"pattern": [Vector2(-1.0, 0.1), Vector2(1.0, 0.1), Vector2(0.0, 0.7)], "shake": 0.1, "vol": -3.0, "pitch_lo": 0.85, "pitch_hi": 0.95, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_bat",
		"kick": 0.02, "kick_end": 0.02, "kick_yaw": 0.008, "reload": 1.0, "range": 2.8, "falloff_from": 9999.0,
		"reach": 2.8, "cone": 0.3, "combo": [1.0, 1.0, 2.4], "combo_window": 0.9,
		"tracer": Color(0.9, 0.75, 0.5), "look": Color(0.8, 0.6, 0.35), "look_size": Vector3(0.06, 0.06, 0.8), "zoom": 62.0, "price": 350, "pierce_shield": false,
	},
	# --- QUANTUM weapons: the verbs of the hero as guns
	&"qsuper": {
		"name": "SUPERPOSITION GUN", "tag": "SUP", "kind": "hit", "mag": 20, "reserve": 100, "interval": 0.46, "damage": 20.0, "crit": 40.0, "pellets": 1, "burst": 2, "burst_gap": 0.11, "echo": true,
		"pattern": [Vector2(0.0, 0.9), Vector2(0.3, 0.9)], "shake": 0.04, "vol": -2.0, "pitch_lo": 0.98, "pitch_hi": 1.04, "eject": 0, "flash": 1.3, "ads_kick": 0.55, "ads_spread": 0.3,
		"spread_hip": 0.014, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.002, "bloom_max": 0.012, "snd": &"shot_qsuper",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.004, "reload": 1.6, "range": 160.0, "falloff_from": 70.0,
		"tracer": Color(0.4, 1.0, 0.93), "look": Color(0.35, 1.0, 0.9), "look_size": Vector3(0.04, 0.04, 0.42), "zoom": 58.0, "price": 1100, "pierce_shield": false,
	},
	&"qlink": {
		"name": "ENTANGLE LINKER", "tag": "ENT", "kind": "hit", "mag": 18, "reserve": 90, "interval": 0.19, "damage": 20.0, "crit": 40.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.9), Vector2(0.3, 0.8), Vector2(-0.3, 0.8)], "shake": 0.03, "vol": -3.0, "pitch_lo": 0.95, "pitch_hi": 1.05, "eject": 0, "flash": 1.1, "ads_kick": 0.6, "ads_spread": 0.35,
		"spread_hip": 0.014, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.02, "snd": &"shot_qlink",
		"chain": 1, "chain_range": 40.0, "chain_k": 1.0,
		"kick": 0.008, "kick_end": 0.008, "kick_yaw": 0.003, "reload": 1.6, "range": 140.0, "falloff_from": 60.0,
		"tracer": Color(1.0, 0.35, 0.92), "look": Color(1.0, 0.3, 0.9), "look_size": Vector3(0.04, 0.04, 0.4), "zoom": 58.0, "price": 1200, "pierce_shield": true,
	},
	&"qcollapse": {
		"name": "COLLAPSE CANNON", "tag": "CLP", "kind": "throw", "mag": 1, "reserve": 4, "interval": 1.4, "damage": 260.0, "crit": 260.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0)], "shake": 0.2, "vol": -0.5, "pitch_lo": 0.6, "pitch_hi": 0.66, "flash": 0.0, "eject": 0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_qcollapse",
		"kick": 0.05, "kick_end": 0.05, "kick_yaw": 0.0, "reload": 3.2, "range": 150.0, "falloff_from": 9999.0,
		"tracer": Color(0.75, 0.35, 1.0), "look": Color(0.7, 0.3, 1.0), "look_size": Vector3(0.16, 0.16, 0.5), "zoom": 52.0, "price": 2200, "pierce_shield": true,
		"speed": 42.0, "fuse": 2.8, "grav": 4.0, "well_time": 0.1, "well_radius": 14.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 10.5,
		"impact": true, "blast_damage": 260.0, "car_dmg": 240.0, "blast_color": Color(0.7, 0.35, 1.0), "blast_element": &"quantum", "impact_pull": 9.0,
	},
	&"qblink": {
		"name": "BLINK PISTOL", "tag": "BLK", "kind": "hit", "mag": 12, "reserve": 84, "interval": 0.29, "damage": 26.0, "crit": 52.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.9), Vector2(0.2, 1.0), Vector2(-0.2, 1.0)], "shake": 0.04, "vol": -3.0, "pitch_lo": 1.0, "pitch_hi": 1.1, "eject": 0, "flash": 1.1, "ads_kick": 0.5, "ads_spread": 0.3,
		"spread_hip": 0.012, "spread_ads": 0.003, "spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.014, "snd": &"shot_qblink",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.003, "reload": 1.4, "range": 120.0, "falloff_from": 50.0,
		"tracer": Color(0.35, 0.9, 1.0), "look": Color(0.3, 0.85, 1.0), "look_size": Vector3(0.04, 0.04, 0.26), "zoom": 58.0, "price": 1000, "pierce_shield": false,
	},
	&"qphase": {
		"name": "PHASE RIFLE", "tag": "PHS", "kind": "hit", "mag": 24, "reserve": 120, "interval": 0.16, "damage": 22.0, "crit": 44.0, "pellets": 1, "wall": 3, "wall_k": 0.85,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.3, 0.9), Vector2(-0.4, 0.9), Vector2(0.4, 0.8)], "shake": 0.035, "vol": -2.5, "pitch_lo": 0.96, "pitch_hi": 1.04, "eject": 0, "flash": 1.2, "ads_kick": 0.6, "ads_spread": 0.3,
		"spread_hip": 0.015, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.022, "snd": &"shot_qphase",
		"kick": 0.008, "kick_end": 0.0055, "kick_yaw": 0.003, "reload": 1.6, "range": 90.0, "falloff_from": 40.0,
		"tracer": Color(0.7, 0.55, 1.0), "look": Color(0.65, 0.5, 1.0), "look_size": Vector3(0.04, 0.04, 0.5), "zoom": 56.0, "price": 1500, "pierce_shield": true,
	},
	&"qstasis": {
		"name": "STASIS RAY", "tag": "STS", "kind": "hit", "mag": 20, "reserve": 100, "interval": 0.21, "damage": 17.0, "crit": 34.0, "pellets": 1, "stun": 2.5,
		"pattern": [Vector2(0.0, 0.8), Vector2(0.2, 0.7)], "shake": 0.03, "vol": -3.0, "pitch_lo": 0.92, "pitch_hi": 1.0, "eject": 0, "flash": 1.2, "ads_kick": 0.6, "ads_spread": 0.3,
		"spread_hip": 0.013, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.002, "bloom_max": 0.012, "snd": &"shot_qstasis",
		"kick": 0.007, "kick_end": 0.007, "kick_yaw": 0.002, "reload": 1.5, "range": 100.0, "falloff_from": 45.0,
		"tracer": Color(0.6, 0.95, 1.0), "look": Color(0.55, 0.9, 1.0), "look_size": Vector3(0.05, 0.05, 0.4), "zoom": 56.0, "price": 1300, "pierce_shield": true,
	},
	# --- wave 108: ENERGY family (original designs, plain names) and the BLAST class of destructive heavies. New def keys (PlayerWeapon + EnergyArms): splash (+ splash_dmg / splash_car / splash_element / splash_every: a blast at
	# the impact), stick (crystals that supercombine), shock (melee shockwave), salvo (rockets per pull), cluster_n (bomblets), fire_* (a burning field), beacon (orbital strike), guided (steered by the crosshair), role (what it is for).
	&"eplasma": {
		"name": "EMBER PLASMA PISTOL", "tag": "EPP", "kind": "hit", "mag": 16, "reserve": 96, "interval": 0.245, "damage": 19.0, "crit": 38.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.04, "vol": -2.5, "pitch_lo": 0.98, "pitch_hi": 1.05, "eject": 0, "flash": 1.4, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.014, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_eplasma",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.003, "reload": 1.4, "range": 90.0, "falloff_from": 40.0,
		"tracer": Color(0.3, 0.9, 1.0), "look": Color(0.25, 0.9, 1.0), "look_size": Vector3(0.04, 0.04, 0.24), "zoom": 58.0, "price": 180, "pierce_shield": true,
		"splash": 1.7, "splash_dmg": 7.0, "splash_car": 14.0, "splash_element": &"plasma",
		"splash_every": 1, "role": "BREAKS SHIELDS AND ARMOUR  OVERCHARGE STUNS A SQUAD",
	},
	&"erepeat": {
		"name": "PULSE REPEATER", "tag": "PRP", "kind": "hit", "mag": 60, "reserve": 300, "interval": 0.072, "damage": 7.5, "crit": 12.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.8), Vector2(0.4, 0.7), Vector2(-0.5, 0.7), Vector2(0.3, 0.6), Vector2(-0.3, 0.6)], "shake": 0.02, "vol": -4.0, "pitch_lo": 1.0, "pitch_hi": 1.12, "eject": 0, "flash": 0.9, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.02, "spread_ads": 0.007, "spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.03, "snd": &"shot_erepeat",
		"kick": 0.004, "kick_end": 0.003, "kick_yaw": 0.004, "reload": 1.8, "range": 70.0, "falloff_from": 25.0,
		"tracer": Color(0.55, 1.0, 0.4), "look": Color(0.5, 1.0, 0.35), "look_size": Vector3(0.05, 0.05, 0.4), "zoom": 58.0, "price": 230, "pierce_shield": false,
		"spin_up": 0.25, "spin_ready": 0.08, "heat_per": 0.011, "heat_cool": 0.4,
		"heat_lock": 1.5, "role": "WINS CLOSE FIGHTS  HOLDS A DOORWAY",
	},
	&"espike": {
		"name": "CRYSTAL SPIKER", "tag": "CSP", "kind": "hit", "mag": 24, "reserve": 144, "interval": 0.145, "damage": 12.0, "crit": 20.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.03, "vol": -3.0, "pitch_lo": 1.0, "pitch_hi": 1.1, "eject": 0, "flash": 1.2, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.016, "spread_ads": 0.004, "spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.02, "snd": &"shot_espike",
		"kick": 0.01, "kick_end": 0.01, "kick_yaw": 0.003, "reload": 1.6, "range": 120.0, "falloff_from": 60.0,
		"tracer": Color(1.0, 0.3, 0.85), "look": Color(1.0, 0.3, 0.85), "look_size": Vector3(0.04, 0.04, 0.4), "zoom": 58.0, "price": 270, "pierce_shield": false,
		"stick": 6, "stick_time": 4.0, "stick_dmg": 75.0, "stick_car": 120.0,
		"stick_radius": 4.2, "stick_element": &"quantum", "role": "TAGS A TARGET  SIX CRYSTALS SUPERCOMBINE INTO A BLAST",
	},
	&"ebeam": {
		"name": "PRISM BEAM RIFLE", "tag": "PBR", "kind": "charge", "mag": 4, "reserve": 16, "interval": 1.05, "damage": 150.0, "crit": 260.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.2, "vol": 0.0, "pitch_lo": 0.96, "pitch_hi": 1.04, "eject": 0, "flash": 2.4, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.02, "spread_ads": 0.0004, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_ebeam",
		"kick": 0.05, "kick_end": 0.05, "kick_yaw": 0.003, "reload": 2.5, "range": 500.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.3, 0.15), "look": Color(1.0, 0.35, 0.15), "look_size": Vector3(0.05, 0.05, 0.8), "zoom": 14.0, "price": 420, "pierce_shield": true,
		"charge_time": 1.4, "min_charge": 0.5, "wall": 2, "wall_k": 0.8,
		"splash": 3.2, "splash_dmg": 45.0, "splash_car": 120.0, "splash_element": &"fire",
		"role": "SNIPES THROUGH TWO WALLS  BURNS OUT COVER AND TURRETS",
	},
	&"eblade": {
		"name": "ION BLADE", "tag": "IBL", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.305, "damage": 40.0, "crit": 40.0, "pellets": 1,
		"pattern": [Vector2(-0.8, 0.2), Vector2(0.8, 0.2), Vector2(0.0, 0.5)], "shake": 0.07, "vol": -2.0, "pitch_lo": 0.96, "pitch_hi": 1.04, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_eblade",
		"kick": 0.012, "kick_end": 0.012, "kick_yaw": 0.005, "reload": 1.0, "range": 3.4, "falloff_from": 9999.0,
		"tracer": Color(0.35, 0.9, 1.0), "look": Color(0.3, 0.85, 1.0), "look_size": Vector3(0.04, 0.04, 0.9), "zoom": 58.0, "price": 300, "pierce_shield": true,
		"reach": 3.4, "cone": 0.15, "combo": [1.0, 1.1, 2.2], "combo_window": 0.8,
		"burn": 7.0, "burn_time": 2.0, "role": "CUTS THROUGH SHIELDS  LUNGE CROSSES A ROOM",
	},
	&"emaul": {
		"name": "TREMOR MAUL", "tag": "TMR", "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.84, "damage": 70.0, "crit": 70.0, "pellets": 1,
		"pattern": [Vector2(-1.0, 0.3), Vector2(1.0, 0.3), Vector2(0.0, 0.9)], "shake": 0.2, "vol": -1.0, "pitch_lo": 0.8, "pitch_hi": 0.9, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_emaul",
		"kick": 0.03, "kick_end": 0.03, "kick_yaw": 0.008, "reload": 1.0, "range": 3.2, "falloff_from": 9999.0,
		"tracer": Color(0.7, 0.55, 1.0), "look": Color(0.65, 0.5, 1.0), "look_size": Vector3(0.1, 0.1, 0.9), "zoom": 58.0, "price": 360, "pierce_shield": true,
		"reach": 3.2, "cone": 0.25, "combo": [1.0, 1.0, 1.8], "combo_window": 1.0,
		"shock": 6.5, "shock_dmg": 60.0, "shock_car": 110.0, "shock_push": 9.0,
		"shock_element": &"quantum", "role": "SHOCKWAVE SHOVES AND SPINS CARS  SCATTERS A SQUAD  BREAKS COVER",
	},
	&"epod": {
		"name": "HORNET ROCKET POD", "tag": "HRN", "kind": "throw", "mag": 12, "reserve": 60, "interval": 1.62, "damage": 45.0, "crit": 45.0, "pellets": 3,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.1, "vol": -1.5, "pitch_lo": 1.1, "pitch_hi": 1.2, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_epod",
		"kick": 0.03, "kick_end": 0.03, "kick_yaw": 0.0, "reload": 3.0, "range": 160.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.55, 0.2), "look": Color(1.0, 0.5, 0.2), "look_size": Vector3(0.14, 0.14, 0.5), "zoom": 52.0, "price": 480, "pierce_shield": true,
		"speed": 52.0, "fuse": 2.2, "grav": 2.5, "well_time": 0.1,
		"well_radius": 6.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 3.4,
		"impact": true, "blast_damage": 45.0, "car_dmg": 70.0, "blast_color": Color(1.0, 0.5, 0.15),
		"blast_element": &"fire", "impact_pull": 0.0, "salvo": 3, "salvo_gap": 0.0,
		"role": "THREE ROCKETS AT ONCE  CLEARS VEHICLES AND CAMPS", "launch": true,
		"slots": 8,
	},
	&"railgun": {
		"name": "COIL RAILGUN", "tag": "RLG", "kind": "charge", "mag": 3, "reserve": 12, "interval": 1.7, "damage": 300.0, "crit": 450.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.3, "vol": 1.0, "pitch_lo": 0.9, "pitch_hi": 0.95, "eject": 0, "flash": 2.6, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.02, "spread_ads": 0.0003, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_railgun",
		"kick": 0.07, "kick_end": 0.07, "kick_yaw": 0.003, "reload": 3.2, "range": 600.0, "falloff_from": 9999.0,
		"tracer": Color(0.7, 0.85, 1.0), "look": Color(0.6, 0.8, 1.0), "look_size": Vector3(0.08, 0.08, 1.0), "zoom": 20.0, "price": 540, "pierce_shield": true,
		"charge_time": 1.2, "min_charge": 0.6, "wall": 4, "wall_k": 0.8,
		"splash": 5.0, "splash_dmg": 90.0, "splash_car": 260.0, "splash_element": &"electric",
		"role": "PUNCHES THROUGH FOUR WALLS AND A TANK  BREAKS BUNKERS",
	},
	&"chaingun": {
		"name": "STORM CHAINGUN", "tag": "CHN", "kind": "hit", "mag": 150, "reserve": 600, "interval": 0.045, "damage": 5.5, "crit": 8.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.8), Vector2(0.4, 0.7), Vector2(-0.4, 0.7), Vector2(0.2, 0.6), Vector2(-0.2, 0.6)], "shake": 0.02, "vol": -4.5, "pitch_lo": 0.9, "pitch_hi": 1.0, "eject": 0, "flash": 1.1, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.026, "spread_ads": 0.012, "spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.034, "snd": &"shot_chaingun",
		"kick": 0.003, "kick_end": 0.002, "kick_yaw": 0.003, "reload": 3.5, "range": 90.0, "falloff_from": 30.0,
		"tracer": Color(1.0, 0.6, 0.2), "look": Color(1.0, 0.5, 0.15), "look_size": Vector3(0.1, 0.1, 0.6), "zoom": 58.0, "price": 480, "pierce_shield": false,
		"spin_up": 0.9, "spin_ready": 0.4, "heat_per": 0.007, "heat_cool": 0.3,
		"heat_lock": 2.0, "splash": 2.2, "splash_dmg": 7.0, "splash_car": 14.0,
		"splash_element": &"fire", "splash_every": 3, "role": "EXPLOSIVE ROUNDS CHEW CARS AND CRATES  SUPPRESSES A WHOLE STREET",
	},
	&"cmissile": {
		"name": "HIVE CLUSTER MISSILE", "tag": "HCM", "kind": "throw", "mag": 2, "reserve": 8, "interval": 1.8, "damage": 70.0, "crit": 70.0, "pellets": 4,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.18, "vol": -0.5, "pitch_lo": 0.8, "pitch_hi": 0.86, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_cmissile",
		"kick": 0.05, "kick_end": 0.05, "kick_yaw": 0.0, "reload": 3.2, "range": 200.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.7, 0.25), "look": Color(1.0, 0.65, 0.2), "look_size": Vector3(0.15, 0.15, 0.6), "zoom": 50.0, "price": 540, "pierce_shield": true,
		"speed": 48.0, "fuse": 3.0, "grav": 4.0, "well_time": 0.1,
		"well_radius": 8.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 3.6,
		"impact": true, "blast_damage": 60.0, "car_dmg": 80.0, "blast_color": Color(1.0, 0.6, 0.15),
		"blast_element": &"fire", "impact_pull": 0.0, "cluster_n": 6, "cluster_spread": 7.0,
		"role": "SIX BOMBLETS COVER A CAR PARK  BREAKS CONVOYS",
		"slots": 3,
		"launch": true,
	},
	&"napalm": {
		"name": "CINDER NAPALM LAUNCHER", "tag": "NPL", "kind": "throw", "mag": 3, "reserve": 12, "interval": 1.45, "damage": 40.0, "crit": 40.0, "pellets": 3,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.12, "vol": -1.0, "pitch_lo": 0.85, "pitch_hi": 0.92, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_napalm",
		"kick": 0.04, "kick_end": 0.04, "kick_yaw": 0.0, "reload": 2.8, "range": 120.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.4, 0.1), "look": Color(1.0, 0.4, 0.1), "look_size": Vector3(0.14, 0.14, 0.5), "zoom": 52.0, "price": 450, "pierce_shield": false,
		"speed": 34.0, "fuse": 2.4, "grav": 9.0, "well_time": 0.1,
		"well_radius": 6.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 4.5,
		"impact": true, "blast_damage": 40.0, "car_dmg": 60.0, "blast_color": Color(1.0, 0.45, 0.1),
		"blast_element": &"fire", "impact_pull": 0.0, "fire_radius": 5.5, "fire_time": 7.0,
		"fire_dps": 16.0, "fire_car": 9.0, "role": "LEAVES A BURNING FIELD  FLUSHES ENEMIES OUT OF CAMPS",
		"slots": 3,
		"launch": true,
	},
	&"sing": {
		"name": "VOID SINGULARITY CANNON", "tag": "VSC", "kind": "throw", "mag": 1, "reserve": 3, "interval": 2.0, "damage": 380.0, "crit": 380.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.25, "vol": 0.0, "pitch_lo": 0.55, "pitch_hi": 0.6, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_sing",
		"kick": 0.06, "kick_end": 0.06, "kick_yaw": 0.0, "reload": 4.0, "range": 160.0, "falloff_from": 9999.0,
		"tracer": Color(0.75, 0.3, 1.0), "look": Color(0.7, 0.3, 1.0), "look_size": Vector3(0.18, 0.18, 0.7), "zoom": 50.0, "price": 660, "pierce_shield": true,
		"speed": 36.0, "fuse": 2.5, "grav": 6.0, "well_time": 3.2,
		"well_radius": 15.0, "well_pull": 22.0, "well_dps": 70.0, "blast_radius": 11.0,
		"blast_damage": 380.0, "car_dmg": 340.0, "blast_color": Color(0.7, 0.3, 1.0), "blast_element": &"quantum",
		"role": "DRAGS A WHOLE SQUAD INTO ONE POINT  THEN COLLAPSES",
		"launch": true,
	},
	&"orbital": {
		"name": "ORBITAL STRIKE BEACON", "tag": "ORB", "kind": "throw", "mag": 1, "reserve": 3, "interval": 3.0, "damage": 520.0, "crit": 520.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.3, "vol": -2.0, "pitch_lo": 1.0, "pitch_hi": 1.05, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_orbital",
		"kick": 0.03, "kick_end": 0.03, "kick_yaw": 0.0, "reload": 3.5, "range": 150.0, "falloff_from": 9999.0,
		"tracer": Color(0.5, 0.9, 1.0), "look": Color(0.4, 0.85, 1.0), "look_size": Vector3(0.1, 0.1, 0.3), "zoom": 50.0, "price": 900, "pierce_shield": true,
		"speed": 26.0, "fuse": 3.0, "grav": 14.0, "well_time": 0.1,
		"well_radius": 6.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 13.0,
		"impact": true, "blast_damage": 300.0, "car_dmg": 400.0, "blast_color": Color(0.35, 0.9, 1.0),
		"blast_element": &"plasma", "impact_pull": 0.0, "beacon": true, "beacon_delay": 2.2,
		"beacon_pulses": 3, "beacon_gap": 0.35, "role": "CALLS A LIGHT FROM ORBIT  LEVELS BUNKERS AND CONVOYS",
		"slots": 4,
		"launch": true,
	},
	&"seeker": {
		"name": "SEEKER GUIDED LAUNCHER", "tag": "SKR", "kind": "throw", "mag": 1, "reserve": 6, "interval": 1.42, "damage": 180.0, "crit": 180.0, "pellets": 1,
		"pattern": [Vector2(0.0, 1.0), Vector2(0.2, 0.9), Vector2(-0.2, 0.9)], "shake": 0.16, "vol": -1.0, "pitch_lo": 0.9, "pitch_hi": 0.95, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0,
		"spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "snd": &"shot_seeker",
		"kick": 0.04, "kick_end": 0.04, "kick_yaw": 0.0, "reload": 2.6, "range": 200.0, "falloff_from": 9999.0,
		"tracer": Color(1.0, 0.8, 0.3), "look": Color(1.0, 0.75, 0.3), "look_size": Vector3(0.12, 0.12, 0.6), "zoom": 44.0, "price": 420, "pierce_shield": true,
		"speed": 38.0, "fuse": 5.0, "grav": 0.0, "well_time": 0.1,
		"well_radius": 8.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 6.0,
		"impact": true, "blast_damage": 180.0, "car_dmg": 260.0, "blast_color": Color(1.0, 0.6, 0.15),
		"blast_element": &"fire", "impact_pull": 0.0, "guided": true, "turn": 2.6,
		"role": "STEER IT WITH THE CROSSHAIR  KILLS TANKS AND HELICOPTERS",
		"slots": 3,
		"launch": true,
	},
	&"tknife": {
		"name": "THROWING KNIVES", "tag": "TKN", "kind": "hit", "mag": 8, "reserve": 40, "interval": 0.28, "damage": 34.0, "crit": 80.0, "pellets": 1,
		"pattern": [Vector2(0.0, 0.5), Vector2(0.2, 0.5)], "shake": 0.03, "vol": -8.0, "pitch_lo": 1.1, "pitch_hi": 1.25, "eject": 0, "flash": 0.0, "ads_kick": 0.6, "ads_spread": 0.4,
		"spread_hip": 0.01, "spread_ads": 0.002, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "snd": &"melee_tknife",
		"kick": 0.006, "kick_end": 0.006, "kick_yaw": 0.002, "reload": 1.2, "range": 45.0, "falloff_from": 25.0,
		"tracer": Color(0.85, 0.92, 1.0), "look": Color(0.8, 0.9, 1.0), "look_size": Vector3(0.03, 0.03, 0.3), "zoom": 60.0, "price": 90, "pierce_shield": false,
		"silent": true, "role": "SILENT KILLS ON GUARDS  PICKS OFF A SENTRY",
	},
}

## Alt-fire per class (key B / the ALT touch button). kind: "heavy" = one aimed shot x mult for `cost` rounds (slug / overcharge), "volley" = `count` rounds in a rapid burst,
## "quick" = an instant full-charge lance shot, "cluster" = a pair of grenades thrown in a fan. cd = seconds before anything fires again.
const ALTS := {
	&"pistol": {"name": "OVERCHARGE", "kind": "heavy", "cost": 3, "mult": 3.0, "cd": 0.8},
	&"marksman": {"name": "OVERCHARGE", "kind": "heavy", "cost": 2, "mult": 2.6, "cd": 1.0},
	&"breacher": {"name": "SLUG", "kind": "heavy", "cost": 2, "mult": 5.0, "cd": 1.0},
	&"rocket": {"name": "CLUSTER", "kind": "cluster", "cost": 1, "mult": 1.0, "cd": 1.8},
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
	&"swarm": {"name": "VOLLEY", "kind": "volley", "cost": 10, "count": 10, "cd": 0.7},
	&"vector": {"name": "VOLLEY", "kind": "volley", "cost": 8, "count": 8, "cd": 0.8},
	&"battle": {"name": "OVERCHARGE", "kind": "heavy", "cost": 3, "mult": 2.8, "cd": 1.0},
	&"sawn": {"name": "SLUG", "kind": "heavy", "cost": 2, "mult": 6.0, "cd": 1.0},
	&"auto": {"name": "SLUG", "kind": "heavy", "cost": 2, "mult": 5.0, "cd": 1.0},
	&"bolt": {"name": "OVERCHARGE", "kind": "heavy", "cost": 2, "mult": 2.0, "cd": 1.5},
	&"dmr": {"name": "OVERCHARGE", "kind": "heavy", "cost": 3, "mult": 2.4, "cd": 1.1},
	&"knife": {"name": "LUNGE", "kind": "lunge", "cost": 0, "dist": 3.4, "mult": 2.2, "cd": 1.1},
	&"magnum": {"name": "OVERCHARGE", "kind": "heavy", "cost": 2, "mult": 2.6, "cd": 0.9},
	&"mpistol": {"name": "VOLLEY", "kind": "volley", "cost": 10, "count": 10, "cd": 0.7},
	&"stun": {"name": "OVERCHARGE", "kind": "heavy", "cost": 2, "mult": 2.0, "cd": 1.0},
	&"ranger": {"name": "OVERCHARGE", "kind": "heavy", "cost": 4, "mult": 3.0, "cd": 0.9},
	&"bullpup": {"name": "VOLLEY", "kind": "volley", "cost": 9, "count": 9, "cd": 0.8},
	&"lmg": {"name": "SUPPRESS", "kind": "volley", "cost": 20, "count": 20, "cd": 1.4},
	&"amr": {"name": "OVERCHARGE", "kind": "heavy", "cost": 2, "mult": 1.8, "cd": 1.6},
	&"xbow": {"name": "SNIPE", "kind": "heavy", "cost": 1, "mult": 2.2, "cd": 1.0},
	&"flame": {"name": "VENT", "kind": "vent", "cost": 0, "cd": 0.8},
	&"katana": {"name": "LUNGE", "kind": "lunge", "cost": 0, "dist": 5.0, "mult": 2.6, "cd": 1.3},
	&"bat": {"name": "LUNGE", "kind": "lunge", "cost": 0, "dist": 3.6, "mult": 2.4, "cd": 1.4},
	&"qsuper": {"name": "VOLLEY", "kind": "volley", "cost": 6, "count": 6, "cd": 0.9},
	&"qlink": {"name": "OVERLOAD", "kind": "heavy", "cost": 3, "mult": 2.4, "cd": 1.2},
	&"qcollapse": {"name": "CLUSTER", "kind": "cluster", "cost": 1, "mult": 1.0, "cd": 2.0},
	&"qblink": {"name": "BLINK", "kind": "blink", "cost": 0, "range": 45.0, "cd": 1.6},
	&"qphase": {"name": "OVERCHARGE", "kind": "heavy", "cost": 3, "mult": 2.4, "cd": 1.1},
	&"qstasis": {"name": "OVERCHARGE", "kind": "heavy", "cost": 3, "mult": 2.2, "cd": 1.2},
	# wave 108 (second fire mode of every new weapon): oc_bolt = a slow charged ball, pop = detonate the crystals now, slam / repulse = a shockwave around the hero, fan = several projectiles at once, airburst = bursts in the air at the crosshair, dive = top-attack
	&"eplasma": {"name": "OVERCHARGE", "kind": "oc_bolt", "cost": 6, "cd": 1.6, "proj": &"eplasma_oc"},
	&"erepeat": {"name": "SURGE", "kind": "volley", "cost": 24, "count": 24, "cd": 1.5},
	&"espike": {"name": "SHATTER", "kind": "pop", "cost": 0, "cd": 1.0},
	&"ebeam": {"name": "SNAP BEAM", "kind": "quick", "cost": 2, "mult": 1.0, "cd": 1.4},
	&"eblade": {"name": "LUNGE", "kind": "lunge", "cost": 0, "dist": 6.5, "mult": 3.0, "cd": 1.5},
	&"emaul": {"name": "GROUND SLAM", "kind": "slam", "cost": 0, "cd": 2.6, "radius": 9.0, "dmg": 110.0, "car": 160.0, "push": 12.0},
	&"epod": {"name": "ALL PODS", "kind": "fan", "cost": 6, "count": 6, "step": 0.05, "cd": 2.2},
	&"railgun": {"name": "OVERLOAD", "kind": "quick", "cost": 2, "mult": 1.0, "cd": 1.6},
	&"chaingun": {"name": "SUPPRESS", "kind": "volley", "cost": 30, "count": 30, "cd": 1.4},
	&"cmissile": {"name": "AIRBURST", "kind": "airburst", "cost": 1, "cd": 1.8},
	&"napalm": {"name": "WALL OF FIRE", "kind": "fire_line", "cost": 2, "count": 5, "cd": 2.4},
	&"sing": {"name": "REPULSE", "kind": "repulse", "cost": 0, "cd": 3.0, "radius": 14.0, "dmg": 40.0, "car": 30.0, "push": 16.0},
	&"orbital": {"name": "BARRAGE", "kind": "fan", "cost": 1, "count": 3, "step": 0.14, "cd": 3.0},
	&"seeker": {"name": "TOP ATTACK", "kind": "dive", "cost": 1, "cd": 1.8},
	&"tknife": {"name": "FAN OF KNIVES", "kind": "volley", "cost": 5, "count": 5, "cd": 1.0},
}
## Ammo types for the hitscan weapons (key T): damage multiplier, fire-interval multiplier, shield piercing.
const AMMO_TYPES := [
	{"id": &"standard", "name": "STANDARD", "dmg": 1.0, "rate": 1.0, "pierce": false},
	{"id": &"heavy", "name": "HEAVY", "dmg": 1.3, "rate": 1.25, "pierce": false},
	{"id": &"piercing", "name": "PIERCING", "dmg": 0.85, "rate": 1.0, "pierce": true},
]
## Weapon-specific hit sound: [pitch, volume db, extra layer or &""]. Reload tilt: how far the rifle rolls during the reload / inspect (1 = rig default).
const HIT_SND := {
	&"pistol": [1.15, -1.0, &""], &"marksman": [0.8, 1.0, &"impact_metal"], &"breacher": [0.75, 1.0, &"impact_concrete"], &"rocket": [0.6, 2.0, &""],
	&"carbine": [1.0, 0.0, &""], &"scatter": [0.7, 2.0, &"impact_concrete"], &"lance": [0.55, 3.0, &"impact_metal"], &"grenade": [0.8, 0.0, &""],
	&"burst": [1.35, -2.0, &""], &"rail": [0.5, 4.0, &"impact_metal"], &"flux": [1.6, -5.0, &""], &"gravity": [0.65, 1.0, &""],
	&"minigun": [1.5, -6.0, &""], &"akimbo": [1.2, -2.0, &""], &"arc": [1.1, 0.0, &"impact_metal"], &"revolver": [0.6, 3.0, &"impact_concrete"], &"whip": [0.9, 0.0, &""], &"blade": [0.75, 2.0, &"impact_metal"],
	&"swarm": [1.5, -5.0, &""], &"vector": [1.1, -1.0, &""], &"battle": [0.9, 0.5, &"impact_metal"], &"sawn": [0.7, 2.0, &"impact_concrete"], &"auto": [0.8, 1.0, &"impact_concrete"],
	&"bolt": [0.5, 4.0, &"impact_metal"], &"dmr": [0.8, 1.0, &"impact_metal"], &"knife": [1.0, 0.0, &""],
	&"magnum": [0.7, 1.5, &"impact_metal"], &"mpistol": [1.4, -4.0, &""], &"stun": [1.3, -1.0, &""], &"ranger": [0.9, 0.5, &"impact_concrete"], &"bullpup": [1.0, 0.0, &""],
	&"lmg": [0.8, 0.5, &"impact_concrete"], &"amr": [0.45, 5.0, &"impact_metal"], &"xbow": [1.2, -2.0, &""], &"flame": [1.6, -6.0, &""], &"katana": [1.1, 1.0, &"impact_metal"], &"bat": [0.6, 2.0, &""],
	&"qsuper": [1.2, 0.0, &""], &"qlink": [1.4, 0.0, &""], &"qcollapse": [0.5, 3.0, &""], &"qblink": [1.5, -1.0, &""], &"qphase": [1.0, 0.0, &"impact_metal"], &"qstasis": [0.9, 0.0, &""],
	&"eplasma": [1.3, -1.0, &""], &"erepeat": [1.5, -4.0, &""], &"espike": [1.4, -1.0, &""], &"ebeam": [0.5, 3.0, &"impact_metal"], &"eblade": [1.0, 1.0, &"impact_metal"], &"emaul": [0.5, 4.0, &"impact_concrete"], &"epod": [0.7, 2.0, &""],
	&"railgun": [0.4, 5.0, &"impact_metal"], &"chaingun": [1.3, -3.0, &"impact_concrete"], &"cmissile": [0.6, 2.0, &""], &"napalm": [0.8, 0.0, &""], &"sing": [0.5, 3.0, &""], &"orbital": [0.5, 3.0, &""], &"seeker": [0.7, 2.0, &""], &"tknife": [1.3, -1.0, &""],
}
const TILT := {&"pistol": 1.3, &"marksman": 0.9, &"breacher": 1.5, &"rocket": 1.1, &"carbine": 1.0, &"scatter": 1.6, &"lance": 0.7, &"grenade": 1.2, &"burst": 1.4, &"rail": 0.8, &"flux": 1.8, &"gravity": 1.3, &"minigun": 2.0, &"akimbo": 1.5, &"arc": 1.0, &"revolver": 1.1, &"whip": 0.5, &"blade": 0.5,
	&"swarm": 1.7, &"vector": 1.4, &"battle": 1.0, &"sawn": 1.5, &"auto": 1.5, &"bolt": 0.7, &"dmr": 0.9, &"knife": 0.5, &"magnum": 1.4, &"mpistol": 1.8, &"stun": 1.3, &"ranger": 1.0, &"bullpup": 1.1, &"lmg": 1.9, &"amr": 0.7, &"xbow": 1.2, &"flame": 1.8, &"katana": 0.5, &"bat": 0.5,
	&"qsuper": 1.0, &"qlink": 1.3, &"qcollapse": 1.1, &"qblink": 1.4, &"qphase": 1.0, &"qstasis": 1.1,
	&"eplasma": 1.3, &"erepeat": 1.6, &"espike": 1.2, &"ebeam": 0.7, &"eblade": 0.5, &"emaul": 0.4, &"epod": 1.6, &"railgun": 0.8, &"chaingun": 2.0, &"cmissile": 1.5, &"napalm": 1.5, &"sing": 1.3, &"orbital": 1.2, &"seeker": 1.3, &"tknife": 0.5}


## Projectiles of alt-fires that are not a weapon of their own (PlayerWeapon._gdef reads them through the `wid` of a thrown round): the OVERCHARGE ball of the plasma pistol.
const PROJ := {
	&"eplasma_oc": {"name": "OVERCHARGE", "kind": "throw", "damage": 90.0, "speed": 34.0, "fuse": 2.4, "grav": 0.6, "well_time": 0.1, "well_radius": 6.0, "well_pull": 0.0, "well_dps": 0.0, "blast_radius": 4.5, "impact": true,
		"blast_damage": 90.0, "car_dmg": 170.0, "blast_color": Color(0.3, 0.9, 1.0), "blast_element": &"plasma", "impact_pull": 0.0, "blast_stun": 2.6, "tracer": Color(0.3, 0.9, 1.0)},
}


static func alt_of(id: StringName) -> Dictionary:
	return ALTS.get(id, ALTS[&"carbine"])


static func hit_snd(id: StringName) -> Array:
	return HIT_SND.get(id, HIT_SND[&"carbine"])


const COLOR_PICKUP := Color(1.0, 0.45, 0.9)
const COLLAPSE_COLOR := Color(0.4, 1.0, 0.93)

## The weapons the player owns (set by Progress when a save loads, a weapon is bought or picked up).
static var unlocked: Array[StringName] = STARTERS.duplicate()
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
	last_in_class.clear()
	unlocked = STARTERS.duplicate()
	last_used = &"carbine"


## Replace the set from saved names (unknown names dropped, the starters are always there even in an old save, order follows IDS).
static func set_unlocked(names: Array) -> void:
	var out: Array[StringName] = []
	for id: StringName in IDS:
		if STARTERS.has(id) or names.has(String(id)) or names.has(id):
			out.append(id)
	unlocked = out


## The weapon last used in each class (the weapon wheel's class wedge selects it).
static var last_in_class := {}


## Every owned weapon, grouped by class (CLASS_ORDER) and in IDS order inside a class: the order SWAP / the mouse wheel cycle in.
static func owned_ordered() -> Array[StringName]:
	var out: Array[StringName] = []
	for cls: StringName in CLASS_ORDER:
		out.append_array(owned_in_class(cls))
	return out


static func class_of(id: StringName) -> StringName:
	return StringName(CLASS_OF.get(id, &"rifle"))


## The weapons of one class in IDS order, owned or not.
static func in_class(cls: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in IDS:
		if class_of(id) == cls:
			out.append(id)
	return out


## The owned weapons of one class in IDS order.
static func owned_in_class(cls: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in in_class(cls):
		if unlocked.has(id):
			out.append(id)
	return out


static func price(id: StringName, discount := 0.0) -> int:
	return maxi(5, int(roundf(float(Economy.weapon_price(id)) * (1.0 - discount) / 5.0)) * 5)


## Magazine size with the shop's magazine upgrade, per weapon: +20 % of the weapon's own base per level (the carbine keeps its +6), small magazines at least +1 every second level.
static func mag_size(id: StringName, level: int) -> int:
	var base := int(Attachments.effective(id)["mag"])
	var extra := int(roundf(float(base) * 0.2 * float(level)))
	if base < 30 and level > 0:
		extra = maxi(extra, (level + 1) / 2)
	return base + extra


## What a drop gives for a random roll 0..1: an unowned weapon (half of the drops) or ammo for an owned one. Never a starter (the starters are always owned).
static func pick_drop(r: float, rng_pick: float) -> StringName:
	var missing: Array[StringName] = []
	var owned: Array[StringName] = []
	for id: StringName in IDS:
		if STARTERS.has(id):
			continue
		(owned if unlocked.has(id) else missing).append(id)
	var pool := missing if (not missing.is_empty() and (r < 0.5 or owned.is_empty())) else owned
	if pool.is_empty():
		return &"scatter"
	return pool[mini(int(rng_pick * pool.size()), pool.size() - 1)]


## Number of pages of the touch weapon wheel for n weapons (PAGE_SIZE each).
static func pages_for(n: int) -> int:
	return maxi(1, (n + PAGE_SIZE - 1) / PAGE_SIZE)
