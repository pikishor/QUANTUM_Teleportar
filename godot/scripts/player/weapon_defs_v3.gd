class_name WeaponDefsV3
extends RefCounted
## Roster pack of wave 113: 125 new guns, melee, energy, quantum and exotic weapons (rows in weapon_rows_v3.gd) expanded into full defs and merged into the tables of WeaponDefs by its PACKS hook
## (`tables()`): DEFS, IDS, CLASS_OF, FAMILY_OF, ALTS, HIT_SND, TILT, PROJ plus the rows of Economy.WEAPON_PRICE, PlayerWeapon.AMMO_PACK, BalanceModel.ACC, AimAssist.STAGGER, QuantumVfx.WEAPON_CLASS,
## HeroAnimTuning.WEAPON_CLASS, WeaponModels.SPEC, ShopScreen.SHOP_WEAPONS, WeaponLadder.LADDER and WeaponLadder.CRATES.
## This file must not read WeaponDefs, Economy and the other tables while it builds (they are being built from it); it only reads its own constants.
## How a number is worked out: every row says its `power` (sustained damage per second relative to the RIFT CARBINE, the model of BalanceModel.weapon_dps), its fire rate, magazine and reload; the
## damage per round follows from them, so the whole roster sits inside the balance band of tests/test_balance2.gd and a row never has to be rebalanced by hand: change `power`.

const Rows := preload("res://scripts/player/weapon_rows_v3.gd")

const CARBINE_DPS := 42.47                   ## BalanceModel.weapon_dps(carbine): 14 x 0.45 / 0.105 x (3.15 / (3.15 + 1.3))
const MELEE_UPTIME := 0.4                    ## BalanceModel.MELEE_UPTIME

const TIER_PRICE := [0, 90, 190, 340, 560, 900, 1400]            ## base credits by tier (Economy scales them); a row's family factor `pk` multiplies it
const TIER_NAMES := ["", "TIER 1", "TIER 2", "TIER 3", "TIER 4", "TIER 5", "TIER 6"]
const FAMILY_ORDER: Array[StringName] = [&"pistol", &"smg", &"assault", &"battle", &"carbine", &"dmr", &"sniper", &"shotgun", &"lmg", &"rotary", &"bow", &"flamer", &"melee", &"energy", &"quantum", &"exotic"]
const FAMILY_NAMES := {&"pistol": "PISTOLS", &"smg": "SMGS", &"assault": "ASSAULT RIFLES", &"battle": "BATTLE RIFLES", &"carbine": "CARBINES", &"dmr": "MARKSMAN RIFLES", &"sniper": "SNIPER RIFLES",
	&"shotgun": "SHOTGUNS", &"lmg": "LIGHT MACHINE GUNS", &"rotary": "HEAVY ROTARY", &"bow": "BOWS AND CROSSBOWS", &"flamer": "FLAMERS AND SPRAYERS", &"melee": "MELEE", &"energy": "ENERGY",
	&"quantum": "QUANTUM GUNS", &"exotic": "EXOTIC"}
## the wheel class (WeaponDefs.CLASS_ORDER) of every family
const CLASS_FOR := {&"pistol": &"pistol", &"smg": &"smg", &"assault": &"rifle", &"battle": &"rifle", &"carbine": &"rifle", &"dmr": &"sniper", &"sniper": &"sniper", &"shotgun": &"shotgun",
	&"lmg": &"heavy", &"rotary": &"heavy", &"bow": &"sniper", &"flamer": &"heavy", &"melee": &"melee", &"energy": &"energy", &"quantum": &"quantum", &"exotic": &"energy"}
## the families of the weapons of the first rosters (for the family tabs and the roster counts)
const OLD_FAMILY := {&"pistol": &"pistol", &"burst": &"pistol", &"akimbo": &"pistol", &"revolver": &"pistol", &"magnum": &"pistol", &"mpistol": &"pistol", &"stun": &"pistol",
	&"flux": &"smg", &"swarm": &"smg", &"vector": &"smg", &"carbine": &"carbine", &"ranger": &"assault", &"bullpup": &"assault", &"battle": &"battle", &"marksman": &"dmr", &"dmr": &"dmr", &"arc": &"energy",
	&"scatter": &"shotgun", &"breacher": &"shotgun", &"sawn": &"shotgun", &"auto": &"shotgun", &"rail": &"sniper", &"lance": &"sniper", &"bolt": &"sniper", &"amr": &"sniper", &"xbow": &"bow",
	&"lmg": &"lmg", &"minigun": &"rotary", &"flame": &"flamer", &"gravity": &"launcher", &"rocket": &"launcher", &"grenade": &"launcher",
	&"blade": &"melee", &"whip": &"melee", &"knife": &"melee", &"katana": &"melee", &"bat": &"melee", &"tknife": &"melee",
	&"qsuper": &"quantum", &"qlink": &"quantum", &"qcollapse": &"quantum", &"qblink": &"quantum", &"qphase": &"quantum", &"qstasis": &"quantum",
	&"eplasma": &"energy", &"erepeat": &"energy", &"espike": &"energy", &"ebeam": &"energy", &"eblade": &"energy", &"emaul": &"energy", &"epod": &"launcher",
	&"railgun": &"launcher", &"chaingun": &"launcher", &"cmissile": &"launcher", &"napalm": &"launcher", &"sing": &"launcher", &"orbital": &"launcher", &"seeker": &"launcher"}
## who carries a weapon of this family when the row does not say (the DROP route of the ladder)
const DROP_DEFAULT := {&"pistol": &"operative", &"smg": &"flanker", &"assault": &"operative", &"battle": &"shield", &"carbine": &"operative", &"dmr": &"sniper", &"sniper": &"sniper", &"shotgun": &"brute",
	&"lmg": &"heavy", &"rotary": &"heavy", &"bow": &"operative", &"flamer": &"striker", &"melee": &"brute", &"energy": &"sentinel", &"quantum": &"sentinel", &"exotic": &"sentinel"}

const PALETTE := {&"amber": Color(1.0, 0.82, 0.4), &"gold": Color(1.0, 0.78, 0.3), &"orange": Color(1.0, 0.5, 0.2), &"red": Color(1.0, 0.3, 0.25), &"magenta": Color(1.0, 0.35, 0.85),
	&"violet": Color(0.7, 0.45, 1.0), &"blue": Color(0.4, 0.7, 1.0), &"cyan": Color(0.35, 0.95, 1.0), &"ice": Color(0.65, 0.9, 1.0), &"green": Color(0.5, 1.0, 0.5), &"lime": Color(0.8, 1.0, 0.4),
	&"white": Color(0.95, 0.95, 1.0), &"pink": Color(1.0, 0.55, 0.8), &"teal": Color(0.3, 0.9, 0.75), &"steel": Color(0.75, 0.8, 0.9)}

## Family templates: every key a def needs, plus the builder inputs (power, acc, crit_k, pat, pat_n, size, col, tier, pk, ammo, hit, anim, vfx, tilt, stagger, spec).
const FAMILIES := {
	&"pistol": {"ammo_types": [0, 1, 2, 3], "kind": "hit", "mag": 12, "reserve": 96, "interval": 0.2, "reload": 1.2, "power": 0.82, "acc": 0.5, "crit_k": 2.0, "range": 100.0, "falloff_from": 45.0, "spread_hip": 0.013, "spread_ads": 0.0032,
		"spread_move": 0.012, "bloom": 0.004, "bloom_max": 0.02, "kick": 0.011, "kick_end": 0.009, "kick_yaw": 0.004, "shake": 0.03, "vol": -3.0, "pitch": 1.0, "eject": 1, "flash": 1.0, "ads_kick": 0.6,
		"ads_spread": 0.4, "zoom": 58.0, "snd": &"shot_v3_pistol", "tilt": 1.3, "stagger": 0.4, "anim": "rifle", "vfx": &"rifle", "hit": [1.15, -1.0, &""], "pat": &"climb", "pat_n": 3,
		"size": Vector3(0.03, 0.03, 0.24), "col": &"amber", "tier": 2, "pk": 0.8, "ammo": 36, "spec": [0.6, Vector3(0.0, -0.085, 0.17), Vector3(-0.025, -0.1, 0.12)]},
	&"smg": {"ammo_types": [0, 2, 3, 4], "kind": "hit", "mag": 32, "reserve": 224, "interval": 0.08, "reload": 1.4, "power": 1.0, "acc": 0.38, "crit_k": 2.0, "range": 70.0, "falloff_from": 22.0, "spread_hip": 0.02, "spread_ads": 0.008,
		"spread_move": 0.012, "bloom": 0.0045, "bloom_max": 0.032, "kick": 0.0048, "kick_end": 0.0033, "kick_yaw": 0.004, "shake": 0.02, "vol": -4.0, "pitch": 1.15, "eject": 1, "flash": 0.8, "ads_kick": 0.7,
		"ads_spread": 0.5, "zoom": 60.0, "snd": &"shot_v3_smg", "tilt": 1.7, "stagger": 0.2, "anim": "rifle", "vfx": &"flux", "hit": [1.5, -5.0, &""], "pat": &"zig", "pat_n": 5,
		"size": Vector3(0.045, 0.04, 0.34), "col": &"amber", "tier": 3, "pk": 1.0, "ammo": 64, "spec": [0.66, Vector3(0.0, -0.09, 0.34), Vector3(0.0, -0.085, 0.14)]},
	&"assault": {"ammo_types": [0, 1, 2, 3, 4], "kind": "hit", "mag": 30, "reserve": 150, "interval": 0.12, "reload": 1.5, "power": 1.0, "acc": 0.45, "crit_k": 2.0, "range": 230.0, "falloff_from": 100.0, "spread_hip": 0.015, "spread_ads": 0.0042,
		"spread_move": 0.011, "bloom": 0.0033, "bloom_max": 0.028, "kick": 0.0105, "kick_end": 0.006, "kick_yaw": 0.0038, "shake": 0.035, "vol": -2.0, "pitch": 0.92, "eject": 1, "flash": 1.1, "ads_kick": 0.62,
		"ads_spread": 0.3, "zoom": 60.0, "snd": &"shot_v3_ar", "tilt": 1.0, "stagger": 0.4, "anim": "rifle", "vfx": &"rifle", "hit": [0.95, 0.3, &"impact_concrete"], "pat": &"climb", "pat_n": 6,
		"size": Vector3(0.035, 0.035, 0.5), "col": &"amber", "tier": 3, "pk": 1.1, "ammo": 30, "spec": [0.86, Vector3(0.0, -0.095, 0.68), Vector3(-0.012, -0.08, 0.39)]},
	&"battle": {"ammo_types": [0, 1, 2, 3, 5], "kind": "hit", "mag": 20, "reserve": 100, "interval": 0.26, "reload": 1.9, "power": 1.05, "acc": 0.55, "crit_k": 2.2, "range": 260.0, "falloff_from": 110.0, "spread_hip": 0.016, "spread_ads": 0.002,
		"spread_move": 0.014, "bloom": 0.002, "bloom_max": 0.012, "kick": 0.02, "kick_end": 0.016, "kick_yaw": 0.004, "shake": 0.06, "vol": -1.5, "pitch": 0.84, "eject": 1, "flash": 1.3, "ads_kick": 0.55,
		"ads_spread": 0.2, "zoom": 46.0, "snd": &"shot_v3_battle", "tilt": 1.0, "stagger": 0.7, "anim": "rifle", "vfx": &"rifle", "hit": [0.9, 0.5, &"impact_metal"], "pat": &"heavy", "pat_n": 3,
		"size": Vector3(0.035, 0.035, 0.55), "col": &"amber", "tier": 4, "pk": 1.2, "ammo": 20, "spec": [0.88, Vector3(0.0, -0.09, 0.7), Vector3(0.0, -0.08, 0.4)]},
	&"carbine": {"ammo_types": [0, 1, 2, 3, 4], "kind": "hit", "mag": 28, "reserve": 168, "interval": 0.1, "reload": 1.2, "power": 0.95, "acc": 0.45, "crit_k": 2.0, "range": 170.0, "falloff_from": 70.0, "spread_hip": 0.014, "spread_ads": 0.0045,
		"spread_move": 0.009, "bloom": 0.0032, "bloom_max": 0.026, "kick": 0.0085, "kick_end": 0.005, "kick_yaw": 0.0035, "shake": 0.03, "vol": -2.0, "pitch": 1.0, "eject": 1, "flash": 1.0, "ads_kick": 0.65,
		"ads_spread": 0.3, "zoom": 62.0, "snd": &"shot_v3_carbine", "tilt": 1.0, "stagger": 0.35, "anim": "rifle", "vfx": &"rifle", "hit": [1.0, 0.0, &""], "pat": &"climb", "pat_n": 6,
		"size": Vector3(0.033, 0.033, 0.42), "col": &"amber", "tier": 3, "pk": 1.0, "ammo": 28, "spec": [0.78, Vector3(0.0, -0.095, 0.55), Vector3(-0.01, -0.08, 0.32)]},
	&"dmr": {"ammo_types": [0, 2, 3, 5], "kind": "hit", "mag": 12, "reserve": 72, "interval": 0.42, "reload": 1.9, "power": 0.92, "acc": 0.65, "crit_k": 2.2, "range": 340.0, "falloff_from": 9999.0, "spread_hip": 0.018, "spread_ads": 0.001,
		"spread_move": 0.018, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.026, "kick_end": 0.024, "kick_yaw": 0.004, "shake": 0.08, "vol": -1.5, "pitch": 0.95, "eject": 1, "flash": 1.4, "ads_kick": 0.5,
		"ads_spread": 0.12, "zoom": 36.0, "snd": &"shot_v3_dmr", "tilt": 0.9, "stagger": 0.9, "anim": "rifle", "vfx": &"beam", "hit": [0.8, 1.0, &"impact_metal"], "pat": &"heavy", "pat_n": 2,
		"size": Vector3(0.03, 0.03, 0.64), "col": &"amber", "tier": 4, "pk": 1.2, "ammo": 12, "spec": [0.94, Vector3(0.0, -0.09, 0.76), Vector3(0.0, -0.08, 0.46)]},
	&"sniper": {"ammo_types": [0, 2, 3, 5], "kind": "hit", "mag": 5, "reserve": 30, "interval": 1.2, "reload": 2.6, "power": 0.9, "acc": 0.75, "crit_k": 2.0, "range": 450.0, "falloff_from": 9999.0, "spread_hip": 0.024, "spread_ads": 0.0006,
		"spread_move": 0.024, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.05, "kick_end": 0.05, "kick_yaw": 0.005, "shake": 0.2, "vol": -0.5, "pitch": 0.78, "eject": 1, "flash": 2.0, "ads_kick": 0.4,
		"ads_spread": 0.1, "zoom": 22.0, "snd": &"shot_v3_sniper", "tilt": 0.7, "stagger": 1.4, "anim": "rifle", "vfx": &"beam", "hit": [0.5, 4.0, &"impact_metal"], "pat": &"single", "pat_n": 1,
		"size": Vector3(0.025, 0.025, 0.72), "col": &"amber", "tier": 4, "pk": 1.4, "ammo": 6, "spec": [0.98, Vector3(0.0, -0.09, 0.8), Vector3(0.0, -0.08, 0.48)]},
	&"shotgun": {"ammo_types": [0, 1, 3, 4], "kind": "hit", "mag": 7, "reserve": 42, "interval": 0.7, "reload": 2.0, "pellets": 8, "power": 1.15, "acc": 0.55, "crit_k": 2.0, "range": 36.0, "falloff_from": 11.0, "spread_hip": 0.07,
		"spread_ads": 0.045, "spread_move": 0.015, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.04, "kick_end": 0.04, "kick_yaw": 0.01, "shake": 0.13, "vol": -1.0, "pitch": 0.95, "eject": 1, "flash": 1.7,
		"ads_kick": 0.8, "ads_spread": 0.67, "zoom": 56.0, "snd": &"shot_v3_shotgun", "tilt": 1.5, "stagger": 0.9, "anim": "shotgun", "vfx": &"shotgun", "hit": [0.75, 1.5, &"impact_concrete"],
		"pat": &"climb", "pat_n": 3, "size": Vector3(0.1, 0.07, 0.38), "col": &"orange", "tier": 3, "pk": 1.0, "ammo": 8, "spec": [0.84, Vector3(0.0, -0.09, 0.66), Vector3(0.0, -0.1, 0.34)]},
	&"lmg": {"ammo_types": [0, 2, 3, 5], "kind": "hit", "mag": 100, "reserve": 300, "interval": 0.09, "reload": 4.0, "power": 1.05, "acc": 0.4, "crit_k": 2.0, "range": 190.0, "falloff_from": 70.0, "spread_hip": 0.02, "spread_ads": 0.007,
		"spread_move": 0.022, "bloom": 0.003, "bloom_max": 0.03, "kick": 0.0055, "kick_end": 0.0038, "kick_yaw": 0.0035, "shake": 0.03, "vol": -2.5, "pitch": 0.84, "eject": 1, "flash": 1.3, "ads_kick": 0.65,
		"ads_spread": 0.4, "zoom": 62.0, "snd": &"shot_v3_lmg", "tilt": 1.9, "stagger": 0.25, "anim": "heavy", "vfx": &"spray", "hit": [0.8, 0.5, &"impact_concrete"], "pat": &"climb", "pat_n": 5,
		"size": Vector3(0.06, 0.06, 0.58), "col": &"amber", "tier": 4, "pk": 1.3, "ammo": 100, "spec": [0.88, Vector3(0.0, -0.1, 0.5), Vector3(0.0, -0.09, 0.26)]},
	&"rotary": {"ammo_types": [0, 3, 4], "kind": "hit", "mag": 180, "reserve": 540, "interval": 0.05, "reload": 4.0, "power": 1.1, "acc": 0.35, "crit_k": 1.5, "range": 90.0, "falloff_from": 30.0, "spread_hip": 0.024, "spread_ads": 0.012,
		"spread_move": 0.02, "bloom": 0.003, "bloom_max": 0.034, "kick": 0.003, "kick_end": 0.002, "kick_yaw": 0.003, "shake": 0.015, "vol": -6.0, "pitch": 0.98, "eject": 0, "flash": 0.9, "ads_kick": 0.7,
		"ads_spread": 0.6, "zoom": 64.0, "snd": &"shot_v3_rotary", "tilt": 2.0, "stagger": 0.15, "anim": "heavy", "vfx": &"spray", "hit": [1.5, -6.0, &""], "pat": &"tight", "pat_n": 5,
		"size": Vector3(0.09, 0.09, 0.58), "col": &"orange", "tier": 5, "pk": 1.5, "ammo": 100, "spin_up": 0.9, "spin_ready": 0.38, "spec": [0.84, Vector3(0.0, -0.12, 0.6), Vector3(0.0, -0.14, 0.3)]},
	&"bow": {"ammo_types": [0, 3, 5], "kind": "hit", "mag": 1, "reserve": 40, "interval": 0.8, "reload": 1.0, "power": 0.8, "acc": 0.8, "crit_k": 2.5, "range": 150.0, "falloff_from": 9999.0, "spread_hip": 0.012, "spread_ads": 0.0008,
		"spread_move": 0.014, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.012, "kick_end": 0.012, "kick_yaw": 0.002, "shake": 0.04, "vol": -5.0, "pitch": 1.0, "eject": 0, "flash": 0.0, "ads_kick": 0.5,
		"ads_spread": 0.1, "zoom": 44.0, "snd": &"shot_v3_bow", "tilt": 1.2, "stagger": 0.8, "anim": "rifle", "vfx": &"rifle", "hit": [1.2, -2.0, &""], "pat": &"single", "pat_n": 1,
		"size": Vector3(0.04, 0.03, 0.5), "col": &"gold", "tier": 2, "pk": 0.9, "ammo": 6, "silent": true, "spec": [0.8, Vector3(0.0, -0.09, 0.52), Vector3(0.0, -0.06, 0.28)]},
	&"flamer": {"ammo_types": [0], "kind": "hit", "mag": 100, "reserve": 300, "interval": 0.06, "reload": 2.5, "pellets": 3, "power": 1.1, "acc": 0.5, "crit_k": 1.0, "range": 15.0, "falloff_from": 7.0, "spread_hip": 0.07,
		"spread_ads": 0.05, "spread_move": 0.012, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.002, "kick_end": 0.002, "kick_yaw": 0.002, "shake": 0.02, "vol": -3.0, "pitch": 1.0, "eject": 0, "flash": 1.6,
		"ads_kick": 0.8, "ads_spread": 0.8, "zoom": 64.0, "snd": &"shot_v3_flame", "tilt": 1.8, "stagger": 0.1, "anim": "heavy", "vfx": &"spray", "hit": [1.6, -6.0, &""], "pat": &"flat", "pat_n": 2,
		"size": Vector3(0.08, 0.08, 0.5), "col": &"orange", "tier": 3, "pk": 1.2, "ammo": 100, "flame": true, "burn": 5.0, "burn_time": 3.0, "spec": [0.84, Vector3(0.0, -0.1, 0.62), Vector3(0.0, -0.06, 0.34)]},
	&"melee": {"ammo_types": [0], "kind": "melee", "mag": 1, "reserve": -1, "interval": 0.3, "reload": 1.0, "power": 1.1, "acc": 0.85, "crit_k": 1.0, "reach": 3.0, "cone": 0.2, "combo": [1.0, 1.0, 2.0], "combo_window": 0.8,
		"range": 3.0, "falloff_from": 9999.0, "spread_hip": 0.0, "spread_ads": 0.0, "spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.012, "kick_end": 0.012, "kick_yaw": 0.005, "shake": 0.07, "vol": -4.0,
		"pitch": 1.0, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0, "zoom": 62.0, "snd": &"shot_v3_blade", "tilt": 0.5, "stagger": 1.0, "anim": "rifle", "vfx": &"melee",
		"hit": [0.9, 0.0, &"impact_metal"], "pat": &"swing", "pat_n": 3, "size": Vector3(0.04, 0.04, 0.8), "col": &"steel", "tier": 2, "pk": 0.7, "ammo": 0, "spec": [1.05, Vector3(0.0, 0.0, 0.8), Vector3(0.0, 0.0, 0.92)]},
	&"energy": {"ammo_types": [0, 4, 6], "kind": "hit", "mag": 30, "reserve": 180, "interval": 0.12, "reload": 1.6, "power": 1.0, "acc": 0.5, "crit_k": 2.0, "range": 150.0, "falloff_from": 60.0, "spread_hip": 0.015, "spread_ads": 0.0045,
		"spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.022, "kick": 0.008, "kick_end": 0.0055, "kick_yaw": 0.003, "shake": 0.03, "vol": -3.0, "pitch": 1.1, "eject": 0, "flash": 1.3, "ads_kick": 0.6,
		"ads_spread": 0.35, "zoom": 58.0, "snd": &"shot_v3_energy", "tilt": 1.3, "stagger": 0.4, "anim": "rifle", "vfx": &"flux", "hit": [1.3, -1.0, &""], "pat": &"climb", "pat_n": 4,
		"size": Vector3(0.05, 0.05, 0.4), "col": &"cyan", "tier": 3, "pk": 1.2, "ammo": 30, "spec": [0.8, Vector3(0.0, -0.095, 0.58), Vector3(0.0, -0.08, 0.3)]},
	&"quantum": {"ammo_types": [0, 2, 6], "kind": "hit", "mag": 20, "reserve": 120, "interval": 0.2, "reload": 1.6, "power": 0.95, "acc": 0.5, "crit_k": 2.0, "range": 130.0, "falloff_from": 55.0, "spread_hip": 0.014, "spread_ads": 0.004,
		"spread_move": 0.012, "bloom": 0.003, "bloom_max": 0.02, "kick": 0.009, "kick_end": 0.007, "kick_yaw": 0.003, "shake": 0.035, "vol": -2.5, "pitch": 1.05, "eject": 0, "flash": 1.2, "ads_kick": 0.6,
		"ads_spread": 0.3, "zoom": 56.0, "snd": &"shot_v3_quantum", "tilt": 1.1, "stagger": 0.4, "anim": "rifle", "vfx": &"arc", "hit": [1.1, 0.0, &""], "pat": &"wild", "pat_n": 4,
		"size": Vector3(0.045, 0.045, 0.42), "col": &"violet", "tier": 5, "pk": 1.4, "ammo": 24, "spec": [0.8, Vector3(0.0, -0.1, 0.5), Vector3(0.0, -0.08, 0.26)]},
	&"exotic": {"ammo_types": [0, 4, 6], "kind": "hit", "mag": 24, "reserve": 144, "interval": 0.15, "reload": 2.0, "power": 0.9, "acc": 0.5, "crit_k": 2.0, "range": 100.0, "falloff_from": 40.0, "spread_hip": 0.016, "spread_ads": 0.005,
		"spread_move": 0.014, "bloom": 0.002, "bloom_max": 0.016, "kick": 0.01, "kick_end": 0.008, "kick_yaw": 0.003, "shake": 0.06, "vol": -2.0, "pitch": 0.9, "eject": 0, "flash": 1.4, "ads_kick": 0.7,
		"ads_spread": 0.4, "zoom": 56.0, "snd": &"shot_v3_exotic", "tilt": 1.3, "stagger": 0.6, "anim": "heavy", "vfx": &"arc", "hit": [0.9, 1.0, &""], "pat": &"heavy", "pat_n": 2,
		"size": Vector3(0.07, 0.06, 0.5), "col": &"violet", "tier": 5, "pk": 1.5, "ammo": 24, "spec": [0.82, Vector3(0.0, -0.1, 0.56), Vector3(0.0, -0.08, 0.3)]},
}

## The ammo types of the pack (appended to WeaponDefs.AMMO_TYPES after the three classic ones: STANDARD, HEAVY, PIERCING = armour piercing). Keys beyond dmg / rate / pierce are read by WeaponMech.on_hit.
const AMMO := [
	{"id": &"incendiary", "name": "INCENDIARY", "dmg": 0.8, "rate": 1.1, "pierce": false, "burn": 6.0, "burn_time": 2.5},
	{"id": &"shock", "name": "SHOCK", "dmg": 0.85, "rate": 1.0, "pierce": true, "zap": 6.0, "zap_time": 1.5, "zap_chain": 1},
	{"id": &"explosive", "name": "EXPLOSIVE TIPPED", "dmg": 0.75, "rate": 1.2, "pierce": false, "splash": 1.8, "splash_dmg": 10.0},
	{"id": &"quantum", "name": "QUANTUM", "dmg": 0.9, "rate": 1.0, "pierce": true, "dissolve": 0.04, "dissolve_time": 2.5},
]

## Alt-fire presets: a row says [preset, {overrides}]. Old kinds are run by PlayerWeapon / EnergyArms, the new ones (ub_nade, zoom, brace, mode, surge, spin, shove, throw_melee) by WeaponMech.
const ALT := {
	&"oc": {"name": "OVERCHARGE", "kind": "heavy", "cost": 3, "mult": 3.0, "cd": 0.9},
	&"slug": {"name": "SLUG", "kind": "heavy", "cost": 2, "mult": 5.0, "cd": 1.0},
	&"volley": {"name": "VOLLEY", "kind": "volley", "cost": 8, "count": 8, "cd": 0.9},
	&"quick": {"name": "SNAP SHOT", "kind": "quick", "cost": 1, "mult": 1.0, "cd": 1.4},
	&"vent": {"name": "VENT", "kind": "vent", "cost": 0, "cd": 0.8},
	&"lunge": {"name": "LUNGE", "kind": "lunge", "cost": 0, "dist": 4.5, "mult": 2.5, "cd": 1.4},
	&"pull": {"name": "PULL", "kind": "pull", "cost": 0, "range": 12.0, "cd": 1.6},
	&"blink": {"name": "BLINK", "kind": "blink", "cost": 0, "range": 45.0, "cd": 1.6},
	&"slam": {"name": "GROUND SLAM", "kind": "slam", "cost": 0, "cd": 2.6, "radius": 8.0, "dmg": 90.0, "car": 130.0, "push": 10.0},
	&"repulse": {"name": "REPULSE", "kind": "repulse", "cost": 0, "cd": 3.0, "radius": 12.0, "dmg": 40.0, "car": 30.0, "push": 16.0},
	&"oc_bolt": {"name": "OVERCHARGE", "kind": "oc_bolt", "cost": 6, "cd": 1.6, "proj": &"eplasma_oc"},
	&"nade": {"name": "UNDERBARREL GRENADE", "kind": "ub_nade", "cost": 3, "cd": 2.4, "proj": &"ub_nade"},
	&"flare": {"name": "UNDERBARREL FLARE", "kind": "ub_nade", "cost": 2, "cd": 2.0, "proj": &"ub_flare"},
	&"zoom": {"name": "SCOPE SWITCH", "kind": "zoom", "cost": 0, "cd": 0.3},
	&"brace": {"name": "DEPLOY BIPOD", "kind": "brace", "cost": 0, "cd": 0.6},
	&"mode": {"name": "FIRE MODE", "kind": "mode", "cost": 0, "cd": 0.3, "burst": 3},
	&"surge": {"name": "OVERDRIVE", "kind": "surge", "cost": 0, "cd": 7.0, "time": 3.0, "rate": 1.6},
	&"spin": {"name": "SPIN SWEEP", "kind": "spin", "cost": 0, "cd": 2.2, "radius": 3.4, "mult": 1.6},
	&"shove": {"name": "SHOVE", "kind": "shove", "cost": 0, "cd": 1.6, "radius": 3.2, "push": 6.0, "mult": 0.8},
	&"throw": {"name": "THROW", "kind": "throw_melee", "cost": 0, "cd": 1.8, "range": 28.0, "mult": 1.8},
}

## Sub-projectiles of the alt-fires (WeaponDefs.PROJ rows: `_throw` with `wid`).
const PROJ := {
	&"ub_nade": {"name": "UNDERBARREL GRENADE", "kind": "throw", "damage": 85.0, "speed": 34.0, "fuse": 2.2, "grav": 12.0, "well_time": 0.1, "well_radius": 4.0, "well_pull": 0.0, "well_dps": 0.0,
		"blast_radius": 3.6, "impact": true, "blast_damage": 85.0, "car_dmg": 110.0, "blast_color": Color(1.0, 0.65, 0.25), "blast_element": &"fire", "impact_pull": 0.0, "tracer": Color(1.0, 0.7, 0.3)},
	&"ub_flare": {"name": "UNDERBARREL FLARE", "kind": "throw", "damage": 25.0, "speed": 32.0, "fuse": 2.0, "grav": 10.0, "well_time": 0.1, "well_radius": 4.0, "well_pull": 0.0, "well_dps": 0.0,
		"blast_radius": 2.4, "impact": true, "blast_damage": 25.0, "car_dmg": 30.0, "blast_color": Color(1.0, 0.5, 0.15), "blast_element": &"fire", "impact_pull": 0.0, "fire_radius": 4.5, "fire_time": 6.0,
		"fire_dps": 12.0, "fire_car": 8.0, "tracer": Color(1.0, 0.5, 0.2)},
}

## Secret caches (WeaponLadder.CRATES rows with `site`): a crate near a place of the outskirts, shown on the map only close by. Offsets are metres from the site's centre.
const CACHE_SITES: Array = [
	[&"observatory", Vector2(14.0, 10.0)], [&"radio_tower", Vector2(-12.0, 9.0)], [&"mine", Vector2(11.0, -9.0)], [&"crash", Vector2(30.0, 12.0)], [&"cave", Vector2(7.0, 5.0)],
	[&"lodge", Vector2(-16.0, 10.0)], [&"hunters", Vector2(18.0, -12.0)], [&"pine_hollow", Vector2(26.0, 18.0)], [&"dust_wells", Vector2(-24.0, 16.0)], [&"south_farm", Vector2(22.0, -20.0)],
	[&"north_farm", Vector2(-20.0, 18.0)], [&"harrow_field", Vector2(34.0, 14.0)], [&"iron_hollow", Vector2(-32.0, 12.0)], [&"bayview", Vector2(30.0, -16.0)], [&"salt_quay", Vector2(-28.0, 14.0)],
	[&"sunset_cove", Vector2(26.0, 20.0)], [&"high_lark", Vector2(-22.0, -14.0)], [&"mirage_point", Vector2(24.0, 18.0)]]
## City crates of the new roster: road junction (x, z of the grid), sidewalk corner sign (sx, sz).
const CITY_SPOTS: Array = [
	[3, 3, 1.0, 1.0], [3, 13, 1.0, -1.0], [14, 3, -1.0, 1.0], [14, 12, -1.0, -1.0], [2, 6, 1.0, 1.0], [2, 11, 1.0, -1.0], [5, 14, 1.0, -1.0], [8, 2, 1.0, 1.0], [11, 3, 1.0, 1.0], [12, 13, -1.0, 1.0],
	[13, 7, -1.0, -1.0], [9, 9, -1.0, 1.0], [6, 10, 1.0, 1.0], [7, 6, -1.0, 1.0], [10, 4, 1.0, -1.0], [4, 7, -1.0, -1.0]]

## melee: id -> [total length in metres (tip at the origin), two handed]; the model (weapon_models_v3.gd) and the hands of the rig read the same numbers.
const MELEE := {&"m_dagger": [0.36, false], &"m_hook": [0.42, false], &"m_machete": [0.7, false], &"m_twinkat": [0.95, true], &"m_hatchet": [0.5, false], &"m_axe": [0.9, true],
	&"m_greataxe": [1.15, true], &"m_mallet": [0.8, true], &"m_sledge": [1.1, true], &"m_crowbar": [0.7, false], &"m_spear": [1.42, true], &"m_staff": [1.36, true], &"m_chainblade": [0.85, true],
	&"m_arcsabre": [0.95, false], &"m_cutlass": [0.9, false], &"m_phaseblade": [1.0, false], &"m_baton": [0.55, false], &"m_gauntlet": [0.35, false], &"m_chainwhip": [0.5, false],
	&"m_shield": [0.6, false], &"m_tonfa": [0.5, false], &"m_scythe": [1.38, true], &"q_blinkblade": [0.95, false]}

static var _built := false
static var _defs := {}
static var _ids: Array = []
static var _class_of := {}
static var _family_of := {}
static var _alts := {}
static var _hit_snd := {}
static var _tilt := {}
static var _price := {}
static var _ammo_pack := {}
static var _acc := {}
static var _stagger := {}
static var _vfx := {}
static var _anim := {}
static var _spec := {}
static var _shop: Array = []
static var _ladder: Array = []
static var _crates: Array = []
static var _drop_type := {}
static var _routes := {}


static func tables() -> Dictionary:
	_build()
	var fam := OLD_FAMILY.duplicate()
	fam.merge(_family_of, true)
	return {"defs": _defs, "ids": _ids, "class_of": _class_of, "family_of": fam, "alts": _alts, "hit_snd": _hit_snd, "tilt": _tilt, "proj": PROJ, "ammo_types": AMMO, "price": _price, "ammo_pack": _ammo_pack,
			"acc": _acc, "stagger": _stagger, "vfx_class": _vfx, "anim_class": _anim, "spec": _spec, "shop": _shop, "ladder": _ladder, "crates": _crates}


## The ids of this pack in display order (also valid before WeaponDefs exists).
static func ids() -> Array:
	_build()
	return _ids


static func tier_of(id: StringName) -> int:
	_build()
	return int(_defs.get(id, {}).get("tier", 1))


## The route a weapon of this pack is found by: {route: "crate" | "drop" | "shop", arg}.
static func route_of(id: StringName) -> Dictionary:
	_build()
	return _routes.get(id, {})


## Unowned weapons that the enemy `type` may carry at progress tier `tier` (the random drops: WeaponLadder.enemy_drop). `owned` is asked for every candidate.
static func drop_candidates(type: StringName, tier: int, owned: Callable) -> Array[StringName]:
	_build()
	var out: Array[StringName] = []
	for id: StringName in _ids:
		if _drop_type.get(id, &"") == type and int(_defs[id]["tier"]) <= tier and not bool(owned.call(id)):
			out.append(id)
	return out


# --- the build ----------------------------------------------------------------------------------------------------------

static func _build() -> void:
	if _built:
		return
	_built = true
	var rows: Array = Rows.ROWS
	for row in rows:
		var id: StringName = row[0]
		var fam: StringName = row[3]
		var t: Dictionary = (FAMILIES[fam] as Dictionary).duplicate(true)
		t.merge(row[4] as Dictionary, true)
		var d := _make(id, String(row[1]), String(row[2]), fam, t)
		_defs[id] = d
		_ids.append(id)
		var cls: StringName = CLASS_FOR[fam]
		_class_of[id] = cls
		_family_of[id] = fam
		_price[id] = int(d["price"])
		_ammo_pack[id] = int(t["ammo"])
		_acc[id] = float(t["acc"])
		_stagger[id] = float(t["stagger"])
		_vfx[id] = StringName(t["vfx"])
		_anim[id] = String(t["anim"])
		_tilt[id] = float(t["tilt"])
		var hs: Array = t["hit"]
		_hit_snd[id] = [float(hs[0]) + _jit(id, 3) * 0.12, float(hs[1]), StringName(hs[2])]
		_alts[id] = _alt_of(t)
		_spec[id] = _spec_of(id, d, t)
		_shop.append(id)
	_build_ladder(rows)


## A def from its merged template + overrides.
static func _make(id: StringName, nm: String, tag: String, fam: StringName, t: Dictionary) -> Dictionary:
	var kind := String(t["kind"])
	var d := {"name": nm, "tag": tag, "kind": kind, "family": fam}
	var dmg := _damage(t)
	var crit_k := float(t["crit_k"])
	d["mag"] = int(t["mag"])
	d["reserve"] = int(t["reserve"])
	d["interval"] = float(t["interval"])
	d["damage"] = dmg
	d["crit"] = snappedf(dmg * crit_k, 0.1 if dmg < 20.0 else 0.5)
	d["pellets"] = int(t.get("pellets", 1))
	var cn := int(t["pat_n"])
	d["pattern"] = _pattern(StringName(t["pat"]), cn, _seed(id))
	for k: String in ["shake", "vol", "eject", "flash", "ads_kick", "ads_spread", "spread_hip", "spread_ads", "spread_move", "bloom", "bloom_max", "kick", "kick_end", "kick_yaw", "reload", "range", "falloff_from", "zoom"]:
		d[k] = t[k]
	if kind == "melee":
		d["range"] = float(t["reach"])
		d["reload"] = 1.0
	d["snd"] = StringName(t["snd"])
	var pc := float(t["pitch"]) + _jit(id, 1) * 0.05
	d["pitch_lo"] = snappedf(pc - 0.06, 0.001)
	d["pitch_hi"] = snappedf(pc + 0.06, 0.001)
	var tracer: Color = PALETTE[StringName(t["col"])]
	d["tracer"] = tracer
	d["look"] = tracer
	var sz: Vector3 = t["size"]
	d["look_size"] = Vector3(sz.x, sz.y, sz.z * (0.9 + 0.2 * (_jit(id, 2) * 0.5 + 0.5)))
	d["pierce_shield"] = bool(t.get("pierce_shield", false))
	d["tier"] = int(t["tier"])
	d["price"] = _price_of(int(t["tier"]), float(t["pk"]), id)
	d["role"] = String(t.get("role", ""))
	# every other key of the row is a mechanic key that the game reads by its own name
	for k in t.keys():
		var ks := String(k)
		if d.has(ks) or ks in BUILDER_KEYS:
			continue
		d[ks] = t[k]
	if kind == "melee":
		d["combo"] = t["combo"]
		d["combo_window"] = float(t.get("combo_window", 0.8))
		d["cone"] = float(t.get("cone", 0.2))
		d["reach"] = float(t["reach"])
	if t.has("charge_time"):
		d["charge_time"] = float(t["charge_time"])
		d["min_charge"] = float(t.get("min_charge", 0.4))
	d["mlen"] = _model_len(id, fam, t)
	d["model_seed"] = _seed(id)
	return d


## Keys of the template and of a row that are consumed by the builder and not copied into the def.
const BUILDER_KEYS := ["power", "acc", "crit_k", "pat", "pat_n", "size", "col", "pk", "ammo", "hit", "anim", "vfx", "tilt", "stagger", "spec", "alt", "pitch", "drop", "snd", "pierce_shield", "role"]


## Damage per round (per pellet) that puts the weapon at `power` times the sustained dps of the RIFT CARBINE in BalanceModel.weapon_dps.
static func _damage(t: Dictionary) -> float:
	var target := float(t["power"]) * CARBINE_DPS
	var acc := float(t["acc"])
	var interval := float(t["interval"])
	var kind := String(t["kind"])
	if t.has("chain"):
		target /= 1.0 + float(t["chain_k"]) * 0.5
	var raw := 1.0
	match kind:
		"melee":
			var combo: Array = t["combo"]
			var avg := 0.0
			for c in combo:
				avg += float(c)
			avg /= float(combo.size())
			raw = target / (avg * acc / interval * MELEE_UPTIME)
		"charge":
			var cycle := interval + float(t["charge_time"]) * 0.7
			var mag := float(t["mag"])
			raw = target / (acc / cycle * mag / (mag + float(t["reload"]) / cycle))
		_:
			var burst := float(t.get("burst", 1))
			var pellets := float(t.get("pellets", 1))
			var mag2 := float(t["mag"])
			var mag_time := mag2 * interval / burst
			var uptime := mag_time / (mag_time + float(t["reload"]))
			raw = target / (pellets * burst * acc / interval * uptime)
	return maxf(snappedf(raw, 0.1 if raw < 5.0 else (0.5 if raw < 40.0 else 1.0)), 0.5)


static func _price_of(tier: int, pk: float, id: StringName) -> int:
	var base := float(TIER_PRICE[clampi(tier, 1, 6)]) * pk * (0.92 + 0.16 * (_jit(id, 4) * 0.5 + 0.5))
	return maxi(5, int(roundf(base / 5.0)) * 5)


static func _alt_of(t: Dictionary) -> Dictionary:
	var spec: Array = t["alt"] if t.has("alt") else [&"oc", {}]
	var a: Dictionary = (ALT[StringName(spec[0])] as Dictionary).duplicate()
	a.merge(spec[1] as Dictionary, true)
	return a


## [reach, right grip, left grip] of the rig: the family's, moved with the length factor (the model has the same).
static func _spec_of(id: StringName, d: Dictionary, t: Dictionary) -> Dictionary:
	var sp: Array = t["spec"]
	var lf := float(d["mlen"])
	var reach := float(sp[0])
	var gr: Vector3 = sp[1]
	var gl: Vector3 = sp[2]
	if String(d["kind"]) == "melee":
		var mi: Array = MELEE.get(id, [0.9, false])
		var gz := float(mi[0]) - 0.12                                          # the hand sits at the back of the weapon, the tip at the origin
		gr = Vector3(0.0, 0.0, gz)
		gl = Vector3(0.0, 0.0, gz + (0.14 if bool(mi[1]) else 0.0))
		reach = clampf(gz + 0.2, 0.75, 1.25)
	else:
		reach *= (0.94 + 0.12 * lf)
		gr = Vector3(gr.x, gr.y, gr.z * lf)
		gl = Vector3(gl.x, gl.y, gl.z * lf)
	return {"reach": reach, "gr": gr, "gl": gl}


## 0.85 .. 1.15 : how long the weapon is next to the family's average (range, silencer, big magazine all make a longer gun).
static func _model_len(id: StringName, fam: StringName, t: Dictionary) -> float:
	var l := 1.0 + _jit(id, 5) * 0.06
	if bool(t.get("silent", false)):
		l += 0.05
	if float(t["range"]) > 300.0:
		l += 0.08
	if int(t["mag"]) >= 100:
		l += 0.04
	if fam == &"pistol" or fam == &"smg" or fam == &"carbine":
		l -= 0.02
	return clampf(l, 0.85, 1.15)


# --- recoil patterns, deterministic noise ----------------------------------------------------------------------------------------

## A small integer per id (same everywhere, whatever the platform): the seed of its recoil pattern, model and sound jitter.
static func _seed(id: StringName) -> int:
	var h := 7
	for c in String(id).to_utf8_buffer():
		h = (h * 31 + int(c)) % 100003
	return h


## -1 .. 1, a stable pseudo random number of an id and a salt.
static func _jit(id: StringName, salt: int) -> float:
	var h := (_seed(id) * (salt * 2 + 3) + salt * 977) % 2003
	return float(h) / 1001.0 - 1.0


static func _pattern(kind: StringName, n: int, seed_: int) -> Array:
	var out: Array = []
	var r := seed_
	for i in n:
		r = (r * 1103 + 12345) % 65521
		var j := float(r % 200) / 100.0 - 1.0                               # -1 .. 1
		var f := float(i) / float(maxi(n - 1, 1))
		match kind:
			&"climb":
				out.append(Vector2(0.22 * j + (0.25 if i % 2 == 0 else -0.25) * f, 1.0 + 0.3 * f))
			&"zig":
				out.append(Vector2((0.7 if i % 2 == 0 else -0.7) * (0.8 + 0.2 * j), 0.8 - 0.1 * f))
			&"heavy":
				out.append(Vector2(0.2 * j, 1.35 - 0.2 * float(i % 2)))
			&"single":
				out.append(Vector2(0.1 * j, 1.0))
			&"tight":
				out.append(Vector2(0.45 * j, 0.7 - 0.1 * f))
			&"wild":
				out.append(Vector2(0.9 * j, 0.8 + 0.3 * absf(j)))
			&"flat":
				out.append(Vector2(0.2 + 0.1 * j, 0.3))
			&"swing":
				out.append([Vector2(-0.8, 0.2), Vector2(0.8, 0.2), Vector2(0.0, 0.5)][i % 3])
			_:
				out.append(Vector2(0.0, 1.0))
	return out


# --- the ladder: where every weapon of the pack is found ------------------------------------------------------------------------

static func _build_ladder(rows: Array) -> void:
	var order: Array = []
	for id: StringName in _ids:
		order.append(id)
	order.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ta := int(_defs[a]["tier"])
		var tb := int(_defs[b]["tier"])
		if ta != tb:
			return ta < tb
		var fa := FAMILY_ORDER.find(StringName(_defs[a]["family"]))
		var fb := FAMILY_ORDER.find(StringName(_defs[b]["family"]))
		if fa != fb:
			return fa < fb
		return _ids.find(a) < _ids.find(b))
	var drops := {}
	for row in rows:
		var r: Dictionary = row[4]
		if r.has("drop"):
			drops[row[0]] = (r["drop"] as Array)[0]
	var cycle := [&"shop", &"drop", &"crate", &"drop", &"shop", &"crate", &"drop", &"shop", &"drop"]
	var city_i := 0
	var site_i := 0
	for i in order.size():
		var id: StringName = order[i]
		var route: StringName = cycle[i % cycle.size()]
		if drops.has(id) and route != &"crate":
			route = &"drop"
		var fam: StringName = _defs[id]["family"]
		match route:
			&"crate":
				var key := "w3_%s" % String(id)
				var title := "%s CRATE" % String(_defs[id]["name"]).split(" ")[0]
				var crate := {"key": key, "weapon": id, "name": title}
				var secret := city_i >= CITY_SPOTS.size() or (int(_defs[id]["tier"]) >= 4 and site_i < CACHE_SITES.size())          # the strong weapons hide in the outskirts, the rest stands on a sidewalk
				if secret:
					var cs: Array = CACHE_SITES[site_i % CACHE_SITES.size()]
					site_i += 1
					crate["site"] = cs[0]
					crate["off"] = cs[1]
					crate["secret"] = true
					crate["name"] = "SECRET CACHE"
				else:
					var sp: Array = CITY_SPOTS[city_i]
					city_i += 1
					crate["g"] = Vector2i(int(sp[0]), int(sp[1]))
					crate["sx"] = float(sp[2])
					crate["sz"] = float(sp[3])
				_crates.append(crate)
				_ladder.append({"id": id, "route": &"crate", "crate": key, "arg": 0, "tier": int(_defs[id]["tier"])})
				_routes[id] = {"route": &"crate", "arg": key}
			&"drop":
				var et: StringName = drops.get(id, DROP_DEFAULT[fam])
				_drop_type[id] = et
				_ladder.append({"id": id, "route": &"drop", "arg": et, "tier": int(_defs[id]["tier"])})
				_routes[id] = {"route": &"drop", "arg": et}
			_:
				_ladder.append({"id": id, "route": &"shop", "arg": 0, "tier": int(_defs[id]["tier"])})
				_routes[id] = {"route": &"shop", "arg": 0}
	for id: StringName in _ids:                                              # every weapon of the pack can be carried by someone (the random drops), whatever its own route is
		if not _drop_type.has(id):
			_drop_type[id] = drops.get(id, DROP_DEFAULT[StringName(_defs[id]["family"])])
