class_name RosterSpecies
extends RefCounted
## ENEMY ROSTER 2 (wave 108; docs/WORLD_EXPANSION.md "more aliens and better enemies", docs/DESIGN.md "enemies come to you, easy first"). One table of 19 new enemy types in four factions, the
## encounter templates the director picks from by biome, mission and progress, and the loot. Pure data and static functions: nothing here touches the scene tree.
##
##   HIVE      alien infantry: HIVELING (small swarmers), SHIELD BEARER (energy shield, flank it), JET ELITE (jetpack, shoot the pack), VEIL STALKER (cloaked), PLATE BRUTE (armour plates, then the core),
##             BEAM SNIPER (visible beam, shoot the lens).
##   GRID      machines: STRIDER (walker mech, rear core), CRAWLER (spider mech, climbs, dorsal vent), WASP DRONE (flying strafer, rotor ring), AUTO TURRET (sensor on top).
##   CONTRACT  human mercenaries: RIFLE (cover, grenades, flanks), ROCKET, BREACHER (shotgun), MARKSMAN (laser lock) and MEDIC (revives the fallen, heals).
##   TITAN     four bosses, each with weak points and ONE thing to do: MOUNTAIN TITAN (three crystals), MECH COLOSSUS (two knee joints, then the reactor), SEA LEVIATHAN (gills, only when surfaced),
##             AIR GUNSHIP (two engines and the tail rotor).
## Rows are AlienSpecies rows (AlienCreature reads them: hp, speeds, dmg, reach, windup, cool, sight, hit spheres, loot, glow) plus the roster keys documented below. Numbers are EASY-first: every attack
## telegraphs (a ring, a line, a glow), the hero hits hard (HeroPower) and Difficulty scales hp / damage / timing like the rest of the world.
##   faction    HIVE / GRID / CONTRACT / TITAN          role   the one-line job of the unit (HUD tag, tests)         tip   what to shoot (shown for bosses and in the weak-point hint)
##   proc       RosterKit body builder                 weak   [{id, pos, r, mult, comp (component hp, 0 = none), fx, tip, from (any | back | front: the side a shot must come from), need (a plate that must be gone)}]
##                                                            hit spheres in model space, facing -Z (the back is +Z); a weak sphere wins over the body sphere it overlaps
##   shot       burst | rocket | pellets | beam | bolt | none   n gap speed spread (rad) range for the gunners     keep   [min, max] metres the unit tries to hold
##   cover / flank / nade / retreat / revivable / medic / shield / plates / jet / cloak ...   behaviour switches read by RosterFoe (see there)

const HIVE := &"hive"
const GRID := &"grid"
const CONTRACT := &"contract"
const TITAN := &"titan"
const FACTIONS: Array[StringName] = [HIVE, GRID, CONTRACT, TITAN]
const GROUND := AlienSpecies.GROUND
const AIR := AlienSpecies.AIR
const WATER := AlienSpecies.WATER
const STATIC := AlienSpecies.STATIC
const CAMP := AlienSpecies.CAMP
const BOSS := AlienSpecies.BOSS

## Alive at once from the ambient director (bosses and site garrisons are not counted), by graphics tier.
const CAPS: Array[int] = [4, 6, 9]

const TABLE := {
	# ----- HIVE: alien infantry --------------------------------------------------------------------------------------------------------------------
	&"hiveling": {"name": "HIVELING", "faction": HIVE, "role": "SWARMER", "tip": "BLASTS CLEAR A SWARM", "family": CAMP, "cls": GROUND, "model": "", "proc": &"hiveling", "mech": &"ros_swarm",
		"hp": 14.0, "walk": 3.0, "run": 8.6, "dmg": 5.0, "reach": 1.4, "windup": 0.4, "cool": 1.1, "sight": 48.0, "r": 0.4, "cy": 0.36, "hr": 0.0, "hy": 0.0, "group": [5, 8], "score": 14, "bounty": 6,
		"glow": Color(1.0, 0.55, 0.12), "vis": 1.0, "voice": &"chitter", "ring": [5.5, 9.0], "surge": [4.0, 6.5], "weak": []},
	&"shield_bearer": {"name": "SHIELD BEARER", "faction": HIVE, "role": "SHIELDED", "tip": "FLANK IT  SHOOT THE SPINE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"shield_bearer", "mech": &"ros_gun",
		"hp": 130.0, "walk": 1.8, "run": 4.0, "dmg": 8.0, "reach": 22.0, "windup": 0.7, "cool": 2.2, "sight": 46.0, "r": 0.8, "cy": 1.05, "hr": 0.28, "hy": 1.85, "group": [1, 2], "score": 90, "bounty": 40,
		"glow": Color(0.3, 0.9, 1.0), "vis": 1.0, "voice": &"growl", "shot": &"burst", "n": 2, "gap": 0.28, "speed": 24.0, "spread": 0.05, "keep": [6.0, 15.0], "bash": 12.0,
		"shield": 140.0, "shield_arc": 0.55, "shield_down": 4.5,
		"weak": [{"id": &"spine", "pos": Vector3(0.0, 1.35, 0.5), "r": 0.42, "mult": 2.4, "comp": 0.0, "fx": &"", "tip": "SPINE", "from": &"back"}]},
	&"jet_elite": {"name": "JET ELITE", "faction": HIVE, "role": "AIRBORNE", "tip": "SHOOT THE PACK", "family": CAMP, "cls": GROUND, "model": "", "proc": &"jet_elite", "mech": &"ros_jet",
		"hp": 100.0, "walk": 2.2, "run": 6.0, "dmg": 7.0, "reach": 34.0, "windup": 0.6, "cool": 1.6, "sight": 54.0, "r": 0.6, "cy": 1.05, "hr": 0.26, "hy": 1.78, "group": [1, 2], "score": 110, "bounty": 50,
		"glow": Color(1.0, 0.55, 0.15), "vis": 1.0, "voice": &"chitter", "shot": &"burst", "n": 3, "gap": 0.18, "speed": 26.0, "spread": 0.06, "keep": [10.0, 22.0], "lift": [3.5, 8.0],
		"weak": [{"id": &"pack", "pos": Vector3(0.0, 1.3, 0.42), "r": 0.46, "mult": 2.0, "comp": 55.0, "fx": &"ground", "tip": "JETPACK", "from": &"back"}]},
	&"veil_stalker": {"name": "VEIL STALKER", "faction": HIVE, "role": "CLOAKED", "tip": "SHOT REVEALS IT  AIM HIGH", "family": CAMP, "cls": GROUND, "model": "", "proc": &"veil_stalker", "mech": &"ros_stalk",
		"hp": 70.0, "walk": 2.6, "run": 7.4, "dmg": 17.0, "reach": 2.3, "windup": 0.55, "cool": 2.4, "sight": 44.0, "r": 0.55, "cy": 1.0, "hr": 0.26, "hy": 1.72, "group": [1, 2], "score": 100, "bounty": 45,
		"glow": Color(1.0, 0.2, 0.7), "vis": 1.0, "voice": &"chitter", "cloak": 0.86, "weak": []},
	&"plate_brute": {"name": "PLATE BRUTE", "faction": HIVE, "role": "ARMOURED", "tip": "BREAK THE PLATES  THEN THE CORE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"plate_brute", "mech": &"ros_charge",
		"hp": 240.0, "walk": 1.6, "run": 5.2, "dmg": 24.0, "reach": 3.4, "windup": 0.9, "cool": 2.6, "sight": 46.0, "r": 1.0, "cy": 1.55, "hr": 0.5, "hy": 2.6, "group": [1, 1], "score": 210, "bounty": 90,
		"glow": Color(1.0, 0.7, 0.2), "vis": 1.0, "voice": &"growl", "slam_r": 5.0, "plates": [{"side": &"front", "hp": 130.0}, {"side": &"left", "hp": 65.0}, {"side": &"right", "hp": 65.0}], "tier": 1,
		"weak": [{"id": &"core", "pos": Vector3(0.0, 1.7, -0.62), "r": 0.5, "mult": 1.8, "comp": 0.0, "fx": &"", "tip": "CORE", "from": &"front", "need": &"plate_front"}]},
	&"beam_sniper": {"name": "BEAM SNIPER", "faction": HIVE, "role": "LONG RANGE", "tip": "SHOOT THE LENS", "family": CAMP, "cls": GROUND, "model": "", "proc": &"beam_sniper", "mech": &"ros_gun",
		"hp": 58.0, "walk": 1.8, "run": 4.8, "dmg": 20.0, "reach": 70.0, "windup": 1.7, "cool": 4.0, "sight": 80.0, "r": 0.55, "cy": 1.25, "hr": 0.3, "hy": 2.2, "group": [1, 1], "score": 120, "bounty": 55,
		"glow": Color(0.35, 1.0, 1.0), "vis": 1.0, "voice": &"chitter", "shot": &"beam", "spread": 0.0, "keep": [34.0, 62.0], "cover": true, "tier": 1,
		"weak": [{"id": &"lens", "pos": Vector3(0.0, 2.15, -0.28), "r": 0.3, "mult": 2.2, "comp": 30.0, "fx": &"stun", "tip": "LENS", "from": &"front"}]},
	# ----- GRID: machines ---------------------------------------------------------------------------------------------------------------------------
	&"strider": {"name": "STRIDER", "faction": GRID, "role": "WALKER MECH", "tip": "SHOOT THE REAR CORE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"strider", "mech": &"ros_walker",
		"hp": 360.0, "walk": 1.5, "run": 3.2, "dmg": 8.0, "reach": 46.0, "windup": 0.9, "cool": 2.2, "sight": 62.0, "r": 1.6, "cy": 2.7, "hr": 0.0, "hy": 0.0, "group": [1, 1], "score": 240, "bounty": 110,
		"glow": Color(1.0, 0.5, 0.1), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 4, "gap": 0.14, "speed": 34.0, "spread": 0.045, "keep": [14.0, 30.0], "salvo": 3, "salvo_cd": 9.0, "tier": 1, "kneel": 0.35,
		"weak": [{"id": &"core", "pos": Vector3(0.0, 3.1, 1.05), "r": 0.8, "mult": 2.6, "comp": 0.0, "fx": &"", "tip": "REAR CORE", "from": &"back"}]},
	&"crawler": {"name": "CRAWLER", "faction": GRID, "role": "SPIDER MECH", "tip": "SHOOT THE VENT ON ITS BACK", "family": CAMP, "cls": GROUND, "model": "", "proc": &"crawler", "mech": &"ros_crawler",
		"hp": 190.0, "walk": 2.6, "run": 6.8, "dmg": 8.0, "reach": 30.0, "windup": 0.7, "cool": 1.8, "sight": 56.0, "r": 1.05, "cy": 1.1, "hr": 0.5, "hy": 1.9, "group": [1, 2], "score": 150, "bounty": 65,
		"glow": Color(1.0, 0.2, 0.2), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 3, "gap": 0.16, "speed": 30.0, "spread": 0.05, "keep": [9.0, 20.0], "leap": [5.0, 14.0], "slam_r": 4.0, "climb": true,
		"weak": [{"id": &"vent", "pos": Vector3(0.0, 1.95, 0.1), "r": 0.5, "mult": 2.3, "comp": 0.0, "fx": &"", "tip": "VENT"}]},
	&"wasp_drone": {"name": "WASP DRONE", "faction": GRID, "role": "FLYING STRAFER", "tip": "HIT THE ROTOR RING", "family": CAMP, "cls": AIR, "model": "", "proc": &"wasp_drone", "mech": &"ros_drone",
		"hp": 30.0, "walk": 6.0, "run": 15.0, "dmg": 4.0, "reach": 40.0, "windup": 0.7, "cool": 2.4, "sight": 70.0, "r": 0.6, "cy": 0.0, "hr": 0.0, "hy": 0.0, "group": [2, 3], "score": 40, "bounty": 18,
		"glow": Color(1.0, 0.25, 0.2), "vis": 1.0, "voice": &"", "alt": [4.5, 8.5], "shot": &"burst", "n": 4, "gap": 0.09, "speed": 32.0, "spread": 0.07,
		"weak": [{"id": &"rotor", "pos": Vector3(0.0, 0.42, 0.0), "r": 0.5, "mult": 2.0, "comp": 12.0, "fx": &"crash", "tip": "ROTORS"}]},
	&"auto_turret": {"name": "AUTO TURRET", "faction": GRID, "role": "TURRET", "tip": "SHOOT THE SENSOR ON TOP", "family": CAMP, "cls": STATIC, "model": "", "proc": &"auto_turret", "mech": &"ros_turret",
		"hp": 110.0, "walk": 0.0, "run": 0.0, "dmg": 5.0, "reach": 44.0, "windup": 0.9, "cool": 1.8, "sight": 46.0, "r": 0.8, "cy": 0.85, "hr": 0.0, "hy": 0.0, "group": [2, 3], "score": 60, "bounty": 28,
		"glow": Color(1.0, 0.85, 0.1), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 5, "gap": 0.1, "speed": 34.0, "spread": 0.06,
		"weak": [{"id": &"sensor", "pos": Vector3(0.0, 1.55, 0.0), "r": 0.34, "mult": 3.0, "comp": 0.0, "fx": &"", "tip": "SENSOR"}]},
	# ----- CONTRACT: human mercenaries -------------------------------------------------------------------------------------------------------------
	&"merc_rifle": {"name": "MERC RIFLE", "faction": CONTRACT, "role": "RIFLEMAN", "tip": "HE USES COVER  FLUSH HIM OUT", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rifle", "look": &"merc_rifle", "mech": &"ros_gun",
		"hp": 70.0, "walk": 2.4, "run": 5.6, "dmg": 5.0, "reach": 36.0, "windup": 0.55, "cool": 1.6, "sight": 54.0, "r": 0.58, "cy": 1.1, "hr": 0.24, "hy": 1.8, "group": [2, 3], "score": 60, "bounty": 26,
		"glow": Color(1.0, 0.6, 0.15), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 3, "gap": 0.13, "speed": 36.0, "spread": 0.05, "keep": [12.0, 26.0], "cover": true, "flank": 0.3, "nade": 13.0,
		"retreat": 0.3, "revivable": true, "weak": []},
	&"merc_rocket": {"name": "MERC ROCKET", "faction": CONTRACT, "role": "ROCKETEER", "tip": "WATCH THE RING  MOVE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_rocket", "look": &"merc_rocket", "mech": &"ros_gun",
		"hp": 78.0, "walk": 2.2, "run": 5.0, "dmg": 20.0, "reach": 42.0, "windup": 1.1, "cool": 4.6, "sight": 58.0, "r": 0.6, "cy": 1.12, "hr": 0.24, "hy": 1.82, "group": [1, 1], "score": 90, "bounty": 38,
		"glow": Color(1.0, 0.3, 0.2), "vis": 1.0, "voice": &"", "shot": &"rocket", "speed": 17.0, "boom": 3.6, "keep": [18.0, 34.0], "cover": true, "retreat": 0.3, "revivable": true, "tier": 1, "weak": []},
	&"merc_shotgun": {"name": "MERC BREACHER", "faction": CONTRACT, "role": "SHOTGUN", "tip": "KEEP YOUR DISTANCE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_shotgun", "look": &"merc_shotgun", "mech": &"ros_gun",
		"hp": 95.0, "walk": 2.8, "run": 7.0, "dmg": 15.0, "reach": 12.0, "windup": 0.5, "cool": 1.9, "sight": 50.0, "r": 0.64, "cy": 1.1, "hr": 0.25, "hy": 1.8, "group": [1, 2], "score": 75, "bounty": 32,
		"glow": Color(1.0, 0.25, 0.15), "vis": 1.0, "voice": &"", "shot": &"pellets", "n": 6, "cone": 0.26, "keep": [4.0, 9.0], "flank": 0.6, "retreat": 0.25, "revivable": true, "weak": []},
	&"merc_sniper": {"name": "MERC MARKSMAN", "faction": CONTRACT, "role": "SNIPER", "tip": "THE LASER SHOWS WHERE", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_sniper", "look": &"merc_sniper", "mech": &"ros_gun",
		"hp": 55.0, "walk": 1.8, "run": 4.6, "dmg": 18.0, "reach": 72.0, "windup": 1.5, "cool": 3.6, "sight": 84.0, "r": 0.54, "cy": 1.08, "hr": 0.23, "hy": 1.78, "group": [1, 1], "score": 100, "bounty": 42,
		"glow": Color(0.4, 1.0, 1.0), "vis": 1.0, "voice": &"", "shot": &"beam", "spread": 0.0, "keep": [30.0, 60.0], "cover": true, "retreat": 0.35, "revivable": true, "tier": 1, "weak": []},
	&"merc_medic": {"name": "FIELD MEDIC", "faction": CONTRACT, "role": "MEDIC", "tip": "KILL THE MEDIC FIRST", "family": CAMP, "cls": GROUND, "model": "", "proc": &"merc_medic", "look": &"merc_medic", "mech": &"ros_gun",
		"hp": 62.0, "walk": 2.4, "run": 5.4, "dmg": 3.0, "reach": 22.0, "windup": 0.6, "cool": 2.4, "sight": 52.0, "r": 0.58, "cy": 1.1, "hr": 0.24, "hy": 1.78, "group": [1, 1], "score": 90, "bounty": 36,
		"glow": Color(0.3, 1.0, 0.5), "vis": 1.0, "voice": &"", "shot": &"burst", "n": 2, "gap": 0.2, "speed": 30.0, "spread": 0.07, "keep": [16.0, 28.0], "medic": true, "heal": 7.0, "retreat": 0.5, "revivable": true,
		"weak": [{"id": &"pack", "pos": Vector3(0.0, 1.32, 0.3), "r": 0.4, "mult": 2.4, "comp": 0.0, "fx": &"", "tip": "MED PACK", "from": &"back"}]},
	# ----- TITAN: the four bosses ---------------------------------------------------------------------------------------------------------------
	&"mountain_titan": {"name": "MOUNTAIN TITAN", "faction": TITAN, "role": "BOSS", "tip": "SHOOT THE THREE CRYSTALS", "family": BOSS, "cls": GROUND, "model": "", "proc": &"mountain_titan", "mech": &"boss_titan",
		"hp": 1900.0, "walk": 2.0, "run": 4.4, "dmg": 28.0, "reach": 7.0, "windup": 1.3, "cool": 3.4, "sight": 100.0, "r": 3.6, "cy": 5.6, "hr": 1.4, "hy": 10.2, "group": [1, 1], "score": 1000, "bounty": 700,
		"glow": Color(0.4, 0.95, 1.0), "vis": 1.0, "voice": &"growl", "biome": &"mountain", "title": "THE MOUNTAIN TITAN", "tier": 1,
		"weak": [{"id": &"crystal_a", "pos": Vector3(-1.9, 8.2, 1.7), "r": 1.0, "mult": 1.6, "comp": 240.0, "fx": &"crystal", "tip": "CRYSTAL"},
				{"id": &"crystal_b", "pos": Vector3(1.9, 8.2, 1.7), "r": 1.0, "mult": 1.6, "comp": 240.0, "fx": &"crystal", "tip": "CRYSTAL"},
				{"id": &"crystal_c", "pos": Vector3(0.0, 6.0, 2.5), "r": 1.1, "mult": 1.6, "comp": 240.0, "fx": &"crystal", "tip": "CRYSTAL"}]},
	&"mech_colossus": {"name": "MECH COLOSSUS", "faction": TITAN, "role": "BOSS", "tip": "BREAK BOTH KNEES  THEN THE REACTOR", "family": BOSS, "cls": GROUND, "model": "", "proc": &"mech_colossus", "mech": &"boss_colossus",
		"hp": 2000.0, "walk": 1.8, "run": 3.6, "dmg": 8.0, "reach": 60.0, "windup": 1.2, "cool": 3.0, "sight": 110.0, "r": 3.2, "cy": 6.0, "hr": 1.2, "hy": 9.0, "group": [1, 1], "score": 1100, "bounty": 760,
		"glow": Color(1.0, 0.5, 0.1), "vis": 1.0, "voice": &"", "biome": &"desert", "title": "THE MECH COLOSSUS", "tier": 1,
		"weak": [{"id": &"knee_l", "pos": Vector3(-1.9, 3.0, -0.5), "r": 0.95, "mult": 1.5, "comp": 300.0, "fx": &"knee", "tip": "KNEE"},
				{"id": &"knee_r", "pos": Vector3(1.9, 3.0, -0.5), "r": 0.95, "mult": 1.5, "comp": 300.0, "fx": &"knee", "tip": "KNEE"},
				{"id": &"reactor", "pos": Vector3(0.0, 6.6, 2.2), "r": 1.3, "mult": 2.5, "comp": 0.0, "fx": &"", "tip": "REACTOR"}]},
	&"sea_leviathan": {"name": "SEA LEVIATHAN", "faction": TITAN, "role": "BOSS", "tip": "SHOOT THE GILLS WHEN IT SURFACES", "family": BOSS, "cls": WATER, "model": "", "proc": &"sea_leviathan", "mech": &"boss_leviathan2",
		"hp": 1800.0, "walk": 0.0, "run": 13.0, "dmg": 26.0, "reach": 8.0, "windup": 1.5, "cool": 3.6, "sight": 130.0, "r": 2.0, "cy": 3.0, "hr": 1.5, "hy": 8.9, "hz": -4.8, "group": [1, 1], "score": 1000, "bounty": 720,
		"glow": Color(0.3, 1.0, 0.85), "vis": 1.0, "voice": &"growl", "biome": &"ocean", "title": "THE SEA LEVIATHAN", "rise": 9.0, "tier": 1,
		"weak": [{"id": &"gill_l", "pos": Vector3(-1.0, 4.95, -0.95), "r": 0.9, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "GILLS", "from": &"front"},
				{"id": &"gill_r", "pos": Vector3(1.0, 4.95, -0.95), "r": 0.9, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "GILLS", "from": &"front"}]},
	&"air_gunship": {"name": "AIR GUNSHIP", "faction": TITAN, "role": "BOSS", "tip": "SHOOT THE ENGINES  THEN THE TAIL", "family": BOSS, "cls": AIR, "model": "", "proc": &"air_gunship", "mech": &"boss_gunship",
		"hp": 1700.0, "walk": 6.0, "run": 20.0, "dmg": 6.0, "reach": 70.0, "windup": 1.3, "cool": 3.0, "sight": 150.0, "r": 2.6, "cy": 0.0, "hr": 0.0, "hy": 0.0, "group": [1, 1], "score": 1000, "bounty": 700,
		"glow": Color(1.0, 0.4, 0.15), "vis": 1.0, "voice": &"", "biome": &"plains", "title": "THE AIR GUNSHIP", "tier": 1, "alt": [22.0, 24.0],
		"weak": [{"id": &"engine_l", "pos": Vector3(-1.7, 0.9, 0.9), "r": 0.95, "mult": 1.6, "comp": 260.0, "fx": &"engine", "tip": "ENGINE"},
				{"id": &"engine_r", "pos": Vector3(1.7, 0.9, 0.9), "r": 0.95, "mult": 1.6, "comp": 260.0, "fx": &"engine", "tip": "ENGINE"},
				{"id": &"tail", "pos": Vector3(0.0, 1.1, 6.4), "r": 0.9, "mult": 2.2, "comp": 0.0, "fx": &"", "tip": "TAIL ROTOR", "from": &"back"}]},
}
const IDS: Array[StringName] = [&"hiveling", &"shield_bearer", &"jet_elite", &"veil_stalker", &"plate_brute", &"beam_sniper", &"strider", &"crawler", &"wasp_drone", &"auto_turret",
	&"merc_rifle", &"merc_rocket", &"merc_shotgun", &"merc_sniper", &"merc_medic", &"mountain_titan", &"mech_colossus", &"sea_leviathan", &"air_gunship"]
const BOSS_IDS: Array[StringName] = [&"mountain_titan", &"mech_colossus", &"sea_leviathan", &"air_gunship"]
## biome -> the roster boss that roams it (the alien lairs keep their own five)
const BOSS_OF_BIOME := {&"mountain": &"mountain_titan", &"desert": &"mech_colossus", &"ocean": &"sea_leviathan", &"plains": &"air_gunship", &"forest": &"mountain_titan", &"beach": &"sea_leviathan"}

## id -> {part: [chance, min, max]} (AlienSpecies.PARTS): mercenaries and machines drop scrap-grade parts, aliens their glands, bosses everything.
const LOOT := {
	&"hiveling": {&"chitin": [0.2, 1, 1]}, &"shield_bearer": {&"chitin": [0.8, 1, 2], &"gland": [0.3, 1, 1]}, &"jet_elite": {&"gland": [0.6, 1, 1], &"chitin": [0.4, 1, 1]},
	&"veil_stalker": {&"gland": [0.7, 1, 1]}, &"plate_brute": {&"chitin": [1.0, 2, 3], &"core": [0.6, 1, 1]}, &"beam_sniper": {&"gland": [0.7, 1, 1], &"crystal": [0.2, 1, 1]},
	&"strider": {&"core": [0.7, 1, 1], &"chitin": [0.8, 1, 2]}, &"crawler": {&"chitin": [0.8, 1, 2], &"gland": [0.3, 1, 1]}, &"wasp_drone": {&"chitin": [0.3, 1, 1]}, &"auto_turret": {&"chitin": [0.5, 1, 1]},
	&"merc_rifle": {&"chitin": [0.25, 1, 1]}, &"merc_rocket": {&"chitin": [0.4, 1, 1]}, &"merc_shotgun": {&"chitin": [0.3, 1, 1]}, &"merc_sniper": {&"gland": [0.3, 1, 1]}, &"merc_medic": {&"gland": [0.4, 1, 1]},
	&"mountain_titan": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 2], &"gland": [1.0, 3, 4]}, &"mech_colossus": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 3], &"gland": [1.0, 3, 4]},
	&"sea_leviathan": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 2], &"gland": [1.0, 3, 4]}, &"air_gunship": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 2], &"gland": [1.0, 3, 4]},
}

## The encounter templates: [{id, name, faction, members [[species, min, max], ...], biomes {biome: weight}, night (weight multiplier at night), tier (first tier), calm (only without a boss near)}, ...].
## `RosterDirector.pick` weighs them by biome, time of day, faction affinity of the running mission and the hero's progress tier.
const ENCOUNTERS0 := {
	&"merc_patrol": {"name": "MERC PATROL", "faction": CONTRACT, "members": [[&"merc_rifle", 2, 3], [&"merc_medic", 0, 1]],
		"biomes": {&"plains": 4.0, &"desert": 3.0, &"forest": 2.0, &"beach": 3.0, &"mountain": 1.0, &"city": 3.0}, "night": 0.7, "tier": 0},
	&"merc_squad": {"name": "MERC SQUAD", "faction": CONTRACT, "members": [[&"merc_rifle", 2, 2], [&"merc_shotgun", 1, 1], [&"merc_medic", 1, 1], [&"merc_sniper", 0, 1]],
		"biomes": {&"plains": 2.5, &"desert": 2.5, &"forest": 1.5, &"mountain": 1.0, &"city": 2.0}, "night": 0.7, "tier": 1},
	&"merc_rocket_team": {"name": "ROCKET TEAM", "faction": CONTRACT, "members": [[&"merc_rocket", 1, 1], [&"merc_rifle", 2, 2]],
		"biomes": {&"plains": 2.0, &"desert": 2.5, &"mountain": 1.5, &"city": 1.5}, "night": 0.8, "tier": 1},
	&"hive_swarm": {"name": "HIVELING SWARM", "faction": HIVE, "members": [[&"hiveling", 6, 9]],
		"biomes": {&"forest": 4.0, &"plains": 2.5, &"desert": 3.0, &"mountain": 2.0}, "night": 1.5, "tier": 0},
	&"hive_vanguard": {"name": "HIVE VANGUARD", "faction": HIVE, "members": [[&"shield_bearer", 1, 2], [&"hiveling", 3, 4]],
		"biomes": {&"mountain": 3.0, &"forest": 2.5, &"plains": 1.5}, "night": 1.0, "tier": 0},
	&"hive_raid": {"name": "HIVE RAID", "faction": HIVE, "members": [[&"jet_elite", 1, 2], [&"beam_sniper", 0, 1]],
		"biomes": {&"mountain": 3.5, &"forest": 1.5, &"plains": 1.0}, "night": 1.0, "tier": 1},
	&"hive_hunt": {"name": "STALKER HUNT", "faction": HIVE, "members": [[&"veil_stalker", 1, 2], [&"hiveling", 2, 3]],
		"biomes": {&"forest": 3.0, &"mountain": 2.5, &"desert": 1.0}, "night": 2.6, "tier": 0},
	&"hive_siege": {"name": "BRUTE WARBAND", "faction": HIVE, "members": [[&"plate_brute", 1, 1], [&"shield_bearer", 1, 1]],
		"biomes": {&"mountain": 3.0, &"forest": 2.0, &"desert": 1.5}, "night": 1.0, "tier": 1},
	&"grid_patrol": {"name": "DRONE PATROL", "faction": GRID, "members": [[&"wasp_drone", 2, 3]],
		"biomes": {&"plains": 3.0, &"desert": 3.0, &"beach": 3.0, &"forest": 1.5, &"mountain": 1.5, &"city": 2.5}, "night": 1.0, "tier": 0},
	&"grid_walker": {"name": "WALKER GROUP", "faction": GRID, "members": [[&"strider", 1, 1], [&"wasp_drone", 1, 2]],
		"biomes": {&"plains": 2.5, &"desert": 3.0, &"beach": 1.0, &"city": 1.0}, "night": 0.9, "tier": 1},
	&"grid_crawl": {"name": "CRAWLER PACK", "faction": GRID, "members": [[&"crawler", 1, 2]],
		"biomes": {&"mountain": 3.0, &"desert": 2.5, &"forest": 2.0, &"plains": 1.0}, "night": 1.0, "tier": 0},
	&"grid_nest": {"name": "TURRET NEST", "faction": GRID, "members": [[&"auto_turret", 2, 3], [&"crawler", 0, 1]],
		"biomes": {&"plains": 2.0, &"desert": 2.0, &"mountain": 1.5, &"city": 1.5}, "night": 1.0, "tier": 0},
}
## The roster-2 templates plus the wave 113 additions (FoeSpecies.ENCOUNTERS): one table for the director, the tests and the free-roam events.
static var ENCOUNTERS: Dictionary = ENCOUNTERS0.merged(FoeSpecies.ENCOUNTERS)
## mission type (MissionBoard.TYPES and WorldMissions ids) -> faction weight multipliers
const MISSION_BIAS := {
	&"heist": {CONTRACT: 3.0}, &"airport_heist": {CONTRACT: 3.0, GRID: 1.5}, &"hijack": {CONTRACT: 3.0}, &"defend": {CONTRACT: 2.0, HIVE: 2.0}, &"courier": {CONTRACT: 2.0},
	&"convoy": {CONTRACT: 2.5, GRID: 1.5}, &"bounty": {CONTRACT: 3.0}, &"patrol": {CONTRACT: 2.0}, &"hack": {GRID: 3.0}, &"stealth": {GRID: 2.0, CONTRACT: 1.5}, &"demolition": {GRID: 2.5},
	&"rescue": {HIVE: 2.0, CONTRACT: 1.5}, &"escort": {HIVE: 2.0, CONTRACT: 2.0}, &"heli_extract": {HIVE: 2.0, GRID: 2.0}, &"mountain_pursuit": {CONTRACT: 2.0, GRID: 1.5},
	&"river_chase": {CONTRACT: 2.5}, &"chase": {CONTRACT: 2.0}, &"arena": {HIVE: 1.5, GRID: 1.5, CONTRACT: 1.5}, &"boss": {TITAN: 4.0},
}


static func data(id: StringName) -> Dictionary:
	return TABLE[id] if TABLE.has(id) else FoeSpecies.data(id)                  # wave 113: the new roster members (FoeSpecies) are found through the same calls


static func has(id: StringName) -> bool:
	return TABLE.has(id) or FoeSpecies.has(id)


## The encounter template `eid` (the roster-2 ones and the wave 113 additions) or {}.
static func encounter(eid: StringName) -> Dictionary:
	return ENCOUNTERS[eid] if ENCOUNTERS.has(eid) else {}


## The loot row of a species.
static func loot_of(id: StringName) -> Dictionary:
	return LOOT[id] if LOOT.has(id) else (FoeSpecies.LOOT[id] if FoeSpecies.LOOT.has(id) else {})


static func is_boss(id: StringName) -> bool:
	return TABLE.has(id) and TABLE[id]["family"] == BOSS


static func faction_of(id: StringName) -> StringName:
	return StringName(data(id).get("faction", &""))


static func title(id: StringName) -> String:
	return String(data(id).get("name", ""))


static func of_faction(f: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in IDS:
		if TABLE[id]["faction"] == f:
			out.append(id)
	for id in FoeSpecies.IDS:
		if FoeSpecies.TABLE[id]["faction"] == f:
			out.append(id)
	return out


## The progress tier of the hero (0 EASY first minutes, 1 after about ten kills, 2 after thirty): brutes, walkers, snipers, rocket teams and the bosses wait for tier 1.
static func tier_for_kills(kills: int) -> int:
	return 0 if kills < 8 else (1 if kills < 30 else 2)


## One encounter template's weight for a place: `biome` (TerrainBase.biome_at or &"city"), `night` 0..1, `mission` (a mission type or &""), `tier` (tier_for_kills).
static func encounter_weight(eid: StringName, biome: StringName, night: float, mission: StringName, tier: int) -> float:
	var e: Dictionary = encounter(eid)
	if e.is_empty() or tier < int(e["tier"]):
		return 0.0
	var w := float((e["biomes"] as Dictionary).get(biome, 0.0))
	if w <= 0.0:
		return 0.0
	w *= lerpf(1.0, float(e["night"]), clampf(night, 0.0, 1.0))
	if mission != &"" and MISSION_BIAS.has(mission):
		w *= float((MISSION_BIAS[mission] as Dictionary).get(e["faction"], 1.0))
	return w


## [[encounter id, weight], ...] with every weight above zero.
static func weights(biome: StringName, night: float, mission: StringName, tier: int) -> Array:
	var out: Array = []
	for eid: StringName in ENCOUNTERS:
		var w := encounter_weight(eid, biome, night, mission, tier)
		if w > 0.0:
			out.append([eid, w])
	return out


static func pick(list: Array, r: float) -> StringName:
	return AlienSpecies.pick(list, r)


## The members of an encounter as a flat list of species ids (counts rolled with `rng`; EASY drops one from a big group), at most `room` of them.
static func roll_members(eid: StringName, rng: RandomNumberGenerator, easy: bool, room := 99) -> Array[StringName]:
	var out: Array[StringName] = []
	var e: Dictionary = encounter(eid)
	for m: Array in (e.get("members", []) as Array):
		var n := rng.randi_range(int(m[1]), int(m[2]))
		if easy and n > 3:
			n -= 1
		for k in n:
			out.append(StringName(m[0]))
	while out.size() > room:
		out.pop_back()
	return out


## The roster boss of a biome ("" for none).
static func boss_for(biome: StringName) -> StringName:
	return StringName(BOSS_OF_BIOME.get(biome, &""))


## What the HUD / tests read for a weak point: the first tip of the species ("" for none).
static func weak_tip(id: StringName) -> String:
	var d := data(id)
	return String(d.get("tip", ""))
