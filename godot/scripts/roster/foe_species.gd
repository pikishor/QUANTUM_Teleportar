class_name FoeSpecies
extends RefCounted
## ENEMY ROSTER LOOK v3 (wave 113): the species rows of the new roster members, in the format of RosterSpecies.TABLE (RosterSpecies.data / has / title / faction_of / encounter / loot_of fall back to this
## table, so the roster-2 tests keep counting their 19). AUTHORITY troopers in hive-grade armour (humans: riot shield, heavy gunner, breacher, ghost sniper, drone operator, engineer with a turret), a
## mercenary OFFICER, and later the alien and machine additions. Every row names a LOOK (`look`: the armoured human of FoeLooks) and reuses a roster brain (`mech`), so ticking, cover, telegraphs,
## weak points, pooling, loot, the director and the damage system work unchanged.
##   specials  `drones` n   the operator launches n wasp drones when he wakes          `turret`   the engineer unfolds an auto turret beside him when he wakes
##             `officer`    his squad within 30 m shoots faster and he calls the contact (RosterFoe._wake)

const AUTHORITY := &"authority"
const CONTRACT := RosterSpecies.CONTRACT
const CAMP := AlienSpecies.CAMP
const GROUND := AlienSpecies.GROUND

const TABLE := {
	&"merc_officer": {"name": "MERC OFFICER", "faction": CONTRACT, "role": "OFFICER", "tip": "KILL THE OFFICER FIRST  HIS SQUAD FALTERS", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"merc_officer",
		"mech": &"ros_gun", "hp": 110.0, "walk": 2.2, "run": 5.2, "dmg": 8.0, "reach": 34.0, "windup": 0.6, "cool": 1.8, "sight": 56.0, "r": 0.58, "cy": 1.12, "hr": 0.24, "hy": 1.8, "group": [1, 1],
		"score": 100, "bounty": 44, "glow": Color(1.0, 0.85, 0.3), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 2, "gap": 0.2, "speed": 34.0, "spread": 0.04, "keep": [14.0, 26.0], "cover": true,
		"flank": 0.2, "nade": 9.0, "retreat": 0.3, "revivable": true, "officer": true, "tier": 1,
		"weak": [{"id": &"radio", "pos": Vector3(0.0, 1.4, 0.36), "r": 0.36, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "RADIO", "from": &"back"}]},
	&"auth_rifle": {"name": "AUTHORITY TROOPER", "faction": AUTHORITY, "role": "TROOPER", "tip": "HE USES COVER  FLANK HIM", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_rifle",
		"mech": &"ros_gun", "hp": 90.0, "walk": 2.3, "run": 5.4, "dmg": 6.0, "reach": 36.0, "windup": 0.55, "cool": 1.5, "sight": 54.0, "r": 0.58, "cy": 1.12, "hr": 0.24, "hy": 1.82, "group": [2, 3],
		"score": 70, "bounty": 30, "glow": Color(1.0, 0.2, 0.22), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 3, "gap": 0.13, "speed": 36.0, "spread": 0.05, "keep": [12.0, 26.0], "cover": true,
		"flank": 0.3, "retreat": 0.3, "weak": []},
	&"auth_riot": {"name": "RIOT TROOPER", "faction": AUTHORITY, "role": "SHIELDED", "tip": "FLANK THE SHIELD  SHOOT HIS BACK", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_riot",
		"mech": &"ros_gun", "hp": 130.0, "walk": 1.8, "run": 3.6, "dmg": 5.0, "reach": 20.0, "windup": 0.7, "cool": 2.0, "sight": 46.0, "r": 0.7, "cy": 1.1, "hr": 0.26, "hy": 1.82, "group": [1, 2],
		"score": 90, "bounty": 40, "glow": Color(0.3, 0.9, 1.0), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 2, "gap": 0.22, "speed": 30.0, "spread": 0.06, "keep": [5.0, 14.0], "bash": 12.0,
		"shield": 160.0, "shield_arc": 0.55, "shield_down": 4.5, "tier": 0,
		"weak": [{"id": &"back", "pos": Vector3(0.0, 1.3, 0.34), "r": 0.4, "mult": 2.0, "comp": 0.0, "fx": &"", "tip": "BACK", "from": &"back"}]},
	&"auth_heavy": {"name": "HEAVY GUNNER", "faction": AUTHORITY, "role": "ARMOURED", "tip": "SHOOT THE POWER CELL ON HIS BACK", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_heavy",
		"mech": &"ros_gun", "hp": 260.0, "walk": 1.5, "run": 3.4, "dmg": 7.0, "reach": 38.0, "windup": 0.8, "cool": 2.6, "sight": 50.0, "r": 0.8, "cy": 1.2, "hr": 0.3, "hy": 1.95, "group": [1, 1],
		"score": 160, "bounty": 70, "glow": Color(1.0, 0.14, 0.1), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 6, "gap": 0.1, "speed": 34.0, "spread": 0.07, "keep": [14.0, 30.0], "tier": 1,
		"weak": [{"id": &"cell", "pos": Vector3(0.0, 1.35, 0.42), "r": 0.46, "mult": 2.4, "comp": 70.0, "fx": &"ground", "tip": "POWER CELL", "from": &"back"}]},
	&"auth_breacher": {"name": "BREACHER", "faction": AUTHORITY, "role": "SHOTGUN", "tip": "HE CHARGES  KEEP YOUR DISTANCE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_breacher",
		"mech": &"ros_gun", "hp": 110.0, "walk": 3.0, "run": 7.2, "dmg": 16.0, "reach": 12.0, "windup": 0.5, "cool": 1.9, "sight": 50.0, "r": 0.6, "cy": 1.1, "hr": 0.25, "hy": 1.8, "group": [1, 2],
		"score": 80, "bounty": 36, "glow": Color(1.0, 0.5, 0.1), "vis": 1.0, "voice": &"", "shot": &"pellets", "n": 6, "cone": 0.28, "keep": [3.0, 8.0], "flank": 0.6, "retreat": 0.2, "tier": 0,
		"weak": [{"id": &"charges", "pos": Vector3(0.0, 1.25, -0.2), "r": 0.34, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "CHARGES", "from": &"front"}]},
	&"auth_ghost": {"name": "GHOST SNIPER", "faction": AUTHORITY, "role": "LONG RANGE", "tip": "THE LENS GLINTS  SHOOT IT", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_ghost",
		"mech": &"ros_gun", "hp": 60.0, "walk": 1.8, "run": 4.4, "dmg": 20.0, "reach": 74.0, "windup": 1.6, "cool": 3.8, "sight": 86.0, "r": 0.55, "cy": 1.1, "hr": 0.26, "hy": 1.78, "group": [1, 1],
		"score": 120, "bounty": 52, "glow": Color(0.2, 1.0, 0.9), "vis": 1.0, "voice": &"", "shot": &"beam", "spread": 0.0, "keep": [32.0, 62.0], "cover": true, "retreat": 0.35, "tier": 1,
		"weak": [{"id": &"lens", "pos": Vector3(0.04, 1.8, -0.2), "r": 0.22, "mult": 2.6, "comp": 0.0, "fx": &"", "tip": "LENS", "from": &"front"}]},
	&"auth_drone": {"name": "DRONE OPERATOR", "faction": AUTHORITY, "role": "OPERATOR", "tip": "KILL THE OPERATOR  THE DRONES FALL", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_drone",
		"mech": &"ros_gun", "hp": 80.0, "walk": 2.2, "run": 5.0, "dmg": 4.0, "reach": 28.0, "windup": 0.6, "cool": 2.2, "sight": 52.0, "r": 0.56, "cy": 1.1, "hr": 0.24, "hy": 1.82, "group": [1, 1],
		"score": 110, "bounty": 46, "glow": Color(1.0, 0.3, 0.9), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 3, "gap": 0.16, "speed": 32.0, "spread": 0.06, "keep": [14.0, 28.0], "cover": true,
		"retreat": 0.4, "drones": 2, "tier": 1,
		"weak": [{"id": &"rack", "pos": Vector3(0.0, 1.45, 0.34), "r": 0.38, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "DRONE RACK", "from": &"back"}]},
	&"auth_engineer": {"name": "ENGINEER", "faction": AUTHORITY, "role": "TURRET", "tip": "THE TURRET FOLDS OUT  KILL HIM OR FLANK IT", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"auth_engineer",
		"mech": &"ros_gun", "hp": 100.0, "walk": 2.2, "run": 4.8, "dmg": 5.0, "reach": 26.0, "windup": 0.6, "cool": 2.0, "sight": 50.0, "r": 0.6, "cy": 1.1, "hr": 0.25, "hy": 1.8, "group": [1, 1],
		"score": 110, "bounty": 46, "glow": Color(1.0, 0.82, 0.1), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 3, "gap": 0.14, "speed": 32.0, "spread": 0.06, "keep": [10.0, 22.0], "cover": true,
		"retreat": 0.3, "turret": true, "tier": 1,
		"weak": [{"id": &"core", "pos": Vector3(-0.07, 1.4, 0.4), "r": 0.34, "mult": 2.4, "comp": 0.0, "fx": &"", "tip": "TURRET CORE", "from": &"back"}]},
}
const IDS: Array[StringName] = [&"merc_officer", &"auth_rifle", &"auth_riot", &"auth_heavy", &"auth_breacher", &"auth_ghost", &"auth_drone", &"auth_engineer"]

const LOOT := {
	&"merc_officer": {&"gland": [0.5, 1, 1], &"chitin": [0.3, 1, 1]}, &"auth_rifle": {&"chitin": [0.3, 1, 1]}, &"auth_riot": {&"chitin": [0.6, 1, 2]}, &"auth_heavy": {&"chitin": [0.9, 1, 2], &"core": [0.4, 1, 1]},
	&"auth_breacher": {&"chitin": [0.4, 1, 1]}, &"auth_ghost": {&"gland": [0.4, 1, 1], &"crystal": [0.1, 1, 1]}, &"auth_drone": {&"gland": [0.4, 1, 1], &"chitin": [0.3, 1, 1]},
	&"auth_engineer": {&"core": [0.3, 1, 1], &"chitin": [0.4, 1, 1]},
}
const SND := {&"merc_officer": [&"shot_mp", 0.9], &"auth_rifle": [&"shot_ar2", 1.0], &"auth_riot": [&"shot_mp", 1.1], &"auth_heavy": [&"shot_chaingun", 0.9], &"auth_breacher": [&"shot_scatter", 0.9],
	&"auth_ghost": [&"shot_amr", 1.0], &"auth_drone": [&"shot_mp", 1.2], &"auth_engineer": [&"shot_mp", 1.0]}

const ENCOUNTERS := {
	&"auth_patrol": {"name": "AUTHORITY PATROL", "faction": AUTHORITY, "members": [[&"auth_rifle", 2, 3], [&"auth_riot", 0, 1]],
		"biomes": {&"plains": 3.0, &"desert": 2.0, &"beach": 2.5, &"forest": 1.0, &"mountain": 0.6, &"city": 4.0}, "night": 0.8, "tier": 0},
	&"auth_assault": {"name": "AUTHORITY ASSAULT", "faction": AUTHORITY, "members": [[&"auth_heavy", 1, 1], [&"auth_riot", 1, 1], [&"auth_rifle", 2, 2]],
		"biomes": {&"plains": 2.0, &"desert": 1.5, &"city": 2.5, &"beach": 1.0}, "night": 0.9, "tier": 1},
	&"auth_breach": {"name": "BREACH TEAM", "faction": AUTHORITY, "members": [[&"auth_breacher", 2, 2], [&"auth_rifle", 1, 2]],
		"biomes": {&"plains": 1.5, &"desert": 1.5, &"city": 2.5, &"mountain": 1.0}, "night": 1.0, "tier": 0},
	&"auth_overwatch": {"name": "OVERWATCH", "faction": AUTHORITY, "members": [[&"auth_ghost", 1, 1], [&"auth_drone", 1, 1], [&"auth_rifle", 1, 1]],
		"biomes": {&"mountain": 2.0, &"plains": 1.5, &"desert": 1.5, &"city": 1.5, &"forest": 1.0}, "night": 1.1, "tier": 1},
	&"auth_works": {"name": "FIELD WORKS", "faction": AUTHORITY, "members": [[&"auth_engineer", 1, 1], [&"auth_rifle", 2, 2], [&"auth_riot", 0, 1]],
		"biomes": {&"plains": 1.5, &"desert": 1.5, &"city": 2.0, &"beach": 1.0, &"mountain": 0.8}, "night": 1.0, "tier": 1},
	&"merc_command": {"name": "MERC COMMAND", "faction": CONTRACT, "members": [[&"merc_officer", 1, 1], [&"merc_rifle", 2, 3], [&"merc_medic", 0, 1], [&"merc_rocket", 0, 1]],
		"biomes": {&"plains": 2.0, &"desert": 2.0, &"forest": 1.0, &"beach": 1.5, &"city": 1.5}, "night": 0.7, "tier": 1},
}


static func has(id: StringName) -> bool:
	return TABLE.has(id)


static func data(id: StringName) -> Dictionary:
	return TABLE[id] if TABLE.has(id) else {}
