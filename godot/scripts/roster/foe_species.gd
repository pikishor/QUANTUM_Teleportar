class_name FoeSpecies
extends RefCounted
## ENEMY ROSTER LOOK v3 (wave 113): the species rows of the new roster members, in the format of RosterSpecies.TABLE (RosterSpecies.data / has / title / faction_of / encounter / loot_of fall back to this
## table, so the roster-2 tests keep counting their 19). AUTHORITY troopers in hive-grade armour (humans: riot shield, heavy gunner, breacher, ghost sniper, drone operator, engineer with a turret), a
## mercenary OFFICER, and later the alien and machine additions. Every row names a LOOK (`look`: the armoured human of FoeLooks) and reuses a roster brain (`mech`), so ticking, cover, telegraphs,
## weak points, pooling, loot, the director and the damage system work unchanged.
##   specials  `drones` n   the operator launches n wasp drones when he wakes          `turret`   the engineer unfolds an auto turret beside him when he wakes
##             `officer`    his squad within 30 m shoots faster and he calls the contact (RosterFoe._wake)

const AUTHORITY := &"authority"
const HIVE := &"hive"
const GRID := &"grid"
const CONTRACT := &"contract"          ## the same values as RosterSpecies.CONTRACT and AlienSpecies.CAMP / GROUND (literals: the two tables must not need each other to compile)
const CAMP := &"camp"
const GROUND := &"ground"

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

	# ----- VAEL: the alien infantry of the hive (Blender bodies: tools/blender/creaturekit, assets/models/foes/*.glb, animated: idle walk run attack hit dead jump) ------------------------------------
	&"vael_grunt": {"name": "VAEL GRUNT", "faction": HIVE, "role": "RUSHER", "tip": "SHOOT THE LEGS  BLASTS CLEAR A PACK", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_grunt", "proc": &"hiveling", "mech": &"ros_swarm",
		"hp": 62.0, "walk": 2.8, "run": 7.2, "dmg": 9.0, "reach": 1.9, "windup": 0.45, "cool": 1.2, "sight": 50.0, "r": 0.62, "cy": 0.95, "hr": 0.26, "hy": 1.62, "group": [2, 4], "score": 40, "bounty": 18,
		"glow": Color(1.0, 0.55, 0.12), "vis": 1.0, "voice": &"chitter", "ring": [6.0, 10.0], "surge": [3.5, 6.5], "weak": []},
	&"vael_jackal": {"name": "VAEL JACKAL", "faction": HIVE, "role": "PACK HUNTER", "tip": "IT LEAPS  STEP ASIDE AND SHOOT", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_jackal", "proc": &"hiveling", "mech": &"leap",
		"hp": 44.0, "walk": 3.0, "run": 10.0, "dmg": 8.0, "reach": 1.8, "windup": 0.45, "cool": 1.2, "sight": 52.0, "r": 0.6, "cy": 0.6, "hr": 0.3, "hy": 0.8, "group": [3, 5], "score": 35, "bounty": 16,
		"glow": Color(1.0, 0.45, 0.1), "vis": 1.0, "pack": true, "leap": [3.0, 10.0], "voice": &"chitter", "weak": []},
	&"vael_brute": {"name": "VAEL BRUTE", "faction": HIVE, "role": "HEAVY", "tip": "SHOOT THE GLOWING BELLY WHEN IT ROARS", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_brute", "proc": &"plate_brute", "mech": &"ros_charge",
		"hp": 300.0, "walk": 1.6, "run": 5.0, "dmg": 26.0, "reach": 3.6, "windup": 0.9, "cool": 2.6, "sight": 46.0, "r": 1.1, "cy": 1.5, "hr": 0.45, "hy": 2.55, "group": [1, 1], "score": 220, "bounty": 95,
		"glow": Color(1.0, 0.45, 0.1), "vis": 1.0, "voice": &"growl", "slam_r": 5.0, "tier": 1,
		"weak": [{"id": &"belly", "pos": Vector3(0.0, 1.65, -0.6), "r": 0.5, "mult": 1.8, "comp": 0.0, "fx": &"", "tip": "BELLY", "from": &"front"}]},
	&"vael_hunter": {"name": "VAEL HUNTER", "faction": HIVE, "role": "LONG RANGE", "tip": "DODGE THE GLOB  SHOOT THE CANNON ARM", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_hunter", "proc": &"hiveling", "mech": &"ros_gun",
		"hp": 85.0, "walk": 2.2, "run": 5.4, "dmg": 16.0, "reach": 44.0, "windup": 1.0, "cool": 4.2, "sight": 60.0, "r": 0.62, "cy": 1.25, "hr": 0.28, "hy": 2.4, "group": [1, 1], "score": 110, "bounty": 48,
		"glow": Color(0.3, 1.0, 0.95), "vis": 1.0, "voice": &"chitter", "shot": &"rocket", "speed": 16.0, "boom": 2.6, "keep": [16.0, 34.0], "cover": true, "tier": 1,
		"weak": [{"id": &"cannon", "pos": Vector3(0.42, 1.05, -0.9), "r": 0.34, "mult": 2.2, "comp": 40.0, "fx": &"stun", "tip": "CANNON ARM", "from": &"front"}]},
	&"vael_elite": {"name": "VAEL ELITE", "faction": HIVE, "role": "SHIELDED", "tip": "BREAK THE ENERGY SHIELD  THEN FLANK", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_elite", "proc": &"shield_bearer", "mech": &"ros_gun",
		"hp": 150.0, "walk": 2.0, "run": 4.6, "dmg": 8.0, "reach": 30.0, "windup": 0.7, "cool": 2.2, "sight": 50.0, "r": 0.78, "cy": 1.15, "hr": 0.28, "hy": 2.05, "group": [1, 1], "score": 130, "bounty": 60,
		"glow": Color(0.3, 0.9, 1.0), "vis": 1.0, "voice": &"growl", "shot": &"burst", "n": 3, "gap": 0.16, "speed": 28.0, "spread": 0.05, "keep": [8.0, 18.0], "bash": 14.0,
		"shield": 150.0, "shield_arc": 0.55, "shield_down": 4.5, "tier": 1,
		"weak": [{"id": &"spine", "pos": Vector3(0.0, 1.5, 0.45), "r": 0.42, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "SPINE", "from": &"back"}]},
	&"vael_stalker": {"name": "VAEL STALKER", "faction": HIVE, "role": "CLOAKED", "tip": "A SHOT REVEALS IT  AIM HIGH", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_stalker", "proc": &"veil_stalker", "mech": &"ros_stalk",
		"hp": 68.0, "walk": 2.6, "run": 7.6, "dmg": 17.0, "reach": 2.4, "windup": 0.55, "cool": 2.3, "sight": 46.0, "r": 0.58, "cy": 1.0, "hr": 0.26, "hy": 1.9, "group": [1, 2], "score": 100, "bounty": 45,
		"glow": Color(1.0, 0.25, 0.75), "vis": 1.0, "voice": &"chitter", "cloak": 0.86, "tier": 0, "weak": []},
	&"vael_bloater": {"name": "VAEL BLOATER", "faction": HIVE, "role": "WALKING BOMB", "tip": "SHOOT IT FAR AWAY  THE CLOUD LINGERS", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"vael_bloater", "proc": &"hiveling", "mech": &"burst",
		"hp": 48.0, "walk": 1.6, "run": 5.4, "dmg": 28.0, "reach": 3.8, "windup": 1.0, "cool": 0.0, "sight": 38.0, "r": 0.85, "cy": 0.95, "hr": 0.3, "hy": 1.3, "group": [1, 2], "score": 40, "bounty": 18,
		"glow": Color(0.7, 1.0, 0.2), "vis": 1.0, "voice": &"yelp", "weak": []},
	# ----- GRID: the walkers (hard-surface machines) ----------------------------------------------------------------------------------------------------------------------------------------
	&"grid_walker": {"name": "LIGHT WALKER", "faction": GRID, "role": "WALKER", "tip": "SHOOT THE REACTOR ON ITS BACK", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"grid_walker", "proc": &"strider", "mech": &"ros_gun",
		"hp": 210.0, "walk": 2.0, "run": 4.8, "dmg": 7.0, "reach": 40.0, "windup": 0.8, "cool": 2.0, "sight": 56.0, "r": 0.95, "cy": 1.7, "hr": 0.0, "hy": 0.0, "group": [1, 2], "score": 130, "bounty": 60,
		"glow": Color(1.0, 0.5, 0.12), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 4, "gap": 0.13, "speed": 34.0, "spread": 0.05, "keep": [14.0, 30.0], "tier": 0,
		"weak": [{"id": &"reactor", "pos": Vector3(0.0, 1.85, 0.5), "r": 0.42, "mult": 2.4, "comp": 0.0, "fx": &"", "tip": "REACTOR", "from": &"back"}]},
	&"grid_heavy": {"name": "HEAVY MECH", "faction": GRID, "role": "MISSILE MECH", "tip": "DODGE THE MISSILE RINGS  SHOOT THE REAR REACTOR", "family": CAMP, "cls": GROUND, "model": "", "gltf": &"grid_heavy", "proc": &"strider", "mech": &"ros_walker",
		"hp": 560.0, "walk": 1.3, "run": 2.8, "dmg": 8.0, "reach": 52.0, "windup": 1.0, "cool": 2.4, "sight": 66.0, "r": 1.8, "cy": 3.2, "hr": 0.0, "hy": 0.0, "group": [1, 1], "score": 300, "bounty": 140,
		"glow": Color(1.0, 0.4, 0.1), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 5, "gap": 0.12, "speed": 34.0, "spread": 0.05, "keep": [16.0, 34.0], "salvo": 4, "salvo_cd": 8.0, "tier": 1, "kneel": 0.35,
		"weak": [{"id": &"reactor", "pos": Vector3(0.0, 3.3, 0.95), "r": 0.95, "mult": 2.6, "comp": 0.0, "fx": &"", "tip": "REAR REACTOR", "from": &"back"}]},
}
const IDS: Array[StringName] = [&"merc_officer", &"auth_rifle", &"auth_riot", &"auth_heavy", &"auth_breacher", &"auth_ghost", &"auth_drone", &"auth_engineer",
	&"vael_grunt", &"vael_jackal", &"vael_brute", &"vael_hunter", &"vael_elite", &"vael_stalker", &"vael_bloater", &"grid_walker", &"grid_heavy"]

const LOOT := {
	&"merc_officer": {&"gland": [0.5, 1, 1], &"chitin": [0.3, 1, 1]}, &"auth_rifle": {&"chitin": [0.3, 1, 1]}, &"auth_riot": {&"chitin": [0.6, 1, 2]}, &"auth_heavy": {&"chitin": [0.9, 1, 2], &"core": [0.4, 1, 1]},
	&"auth_breacher": {&"chitin": [0.4, 1, 1]}, &"auth_ghost": {&"gland": [0.4, 1, 1], &"crystal": [0.1, 1, 1]}, &"auth_drone": {&"gland": [0.4, 1, 1], &"chitin": [0.3, 1, 1]},
	&"auth_engineer": {&"core": [0.3, 1, 1], &"chitin": [0.4, 1, 1]},
	&"vael_grunt": {&"chitin": [0.6, 1, 2], &"gland": [0.15, 1, 1]}, &"vael_jackal": {&"chitin": [0.4, 1, 1]}, &"vael_brute": {&"chitin": [1.0, 2, 3], &"core": [0.5, 1, 1]},
	&"vael_hunter": {&"gland": [0.6, 1, 1], &"chitin": [0.4, 1, 1]}, &"vael_elite": {&"gland": [0.7, 1, 1], &"chitin": [0.7, 1, 2]}, &"vael_stalker": {&"gland": [0.6, 1, 1]},
	&"vael_bloater": {&"gland": [0.5, 1, 1]}, &"grid_walker": {&"chitin": [0.6, 1, 2], &"core": [0.25, 1, 1]}, &"grid_heavy": {&"core": [0.7, 1, 1], &"chitin": [0.9, 1, 2]},
}
## Muzzles of the creature bodies (model space, -Z forward) and the species whose muzzle alternates between the two arms.
const MUZZLE := {&"vael_elite": Vector3(0.28, 1.2, -0.75), &"vael_hunter": Vector3(0.42, 1.1, -1.25), &"grid_walker": Vector3(0.7, 1.45, -1.05), &"grid_heavy": Vector3(1.26, 2.55, -1.85)}
const FLIP: Array[StringName] = [&"grid_walker", &"grid_heavy"]
const SND := {&"merc_officer": [&"shot_mp", 0.9], &"auth_rifle": [&"shot_ar2", 1.0], &"auth_riot": [&"shot_mp", 1.1], &"auth_heavy": [&"shot_chaingun", 0.9], &"auth_breacher": [&"shot_scatter", 0.9],
	&"auth_ghost": [&"shot_amr", 1.0], &"auth_drone": [&"shot_mp", 1.2], &"auth_engineer": [&"shot_mp", 1.0], &"vael_elite": [&"shot_eplasma", 0.9], &"vael_hunter": [&"shot_cmissile", 1.0], &"grid_walker": [&"shot_chaingun", 0.8], &"grid_heavy": [&"shot_chaingun", 0.7]}

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
	&"vael_pack": {"name": "JACKAL PACK", "faction": HIVE, "members": [[&"vael_jackal", 3, 5]],
		"biomes": {&"forest": 3.0, &"plains": 2.5, &"desert": 1.5, &"mountain": 1.5}, "night": 1.6, "tier": 0},
	&"vael_rush": {"name": "GRUNT RUSH", "faction": HIVE, "members": [[&"vael_grunt", 2, 4], [&"vael_brute", 0, 1]],
		"biomes": {&"forest": 2.5, &"mountain": 2.5, &"plains": 1.5, &"desert": 1.0}, "night": 1.2, "tier": 0},
	&"vael_stalk": {"name": "STALKER HUNT", "faction": HIVE, "members": [[&"vael_stalker", 1, 2], [&"vael_jackal", 2, 3]],
		"biomes": {&"forest": 2.5, &"mountain": 2.0, &"plains": 1.0}, "night": 2.4, "tier": 0},
	&"vael_warband": {"name": "VAEL WARBAND", "faction": HIVE, "members": [[&"vael_elite", 1, 1], [&"vael_grunt", 2, 3], [&"vael_hunter", 0, 1]],
		"biomes": {&"mountain": 3.0, &"forest": 1.5, &"plains": 1.0}, "night": 1.0, "tier": 1},
	&"vael_bloat": {"name": "BLOATER SWARM", "faction": HIVE, "members": [[&"vael_bloater", 1, 2], [&"vael_grunt", 1, 2]],
		"biomes": {&"forest": 2.0, &"desert": 1.0, &"plains": 1.0}, "night": 1.2, "tier": 0},
	&"grid_scouts": {"name": "WALKER SCOUTS", "faction": GRID, "members": [[&"grid_walker", 1, 2]],
		"biomes": {&"plains": 2.5, &"desert": 3.5, &"beach": 1.5, &"city": 1.5, &"forest": 0.5}, "night": 1.0, "tier": 0},
	&"grid_assault": {"name": "MECH ASSAULT", "faction": GRID, "members": [[&"grid_heavy", 1, 1], [&"grid_walker", 1, 1], [&"wasp_drone", 1, 2]],
		"biomes": {&"plains": 2.0, &"desert": 3.0, &"city": 1.0}, "night": 0.9, "tier": 1},
	&"merc_command": {"name": "MERC COMMAND", "faction": CONTRACT, "members": [[&"merc_officer", 1, 1], [&"merc_rifle", 2, 3], [&"merc_medic", 0, 1], [&"merc_rocket", 0, 1]],
		"biomes": {&"plains": 2.0, &"desert": 2.0, &"forest": 1.0, &"beach": 1.5, &"city": 1.5}, "night": 0.7, "tier": 1},
}


static func has(id: StringName) -> bool:
	return TABLE.has(id)


static func data(id: StringName) -> Dictionary:
	return TABLE[id] if TABLE.has(id) else {}
