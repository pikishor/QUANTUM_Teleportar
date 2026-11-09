class_name AlienSpecies
extends RefCounted
## The alien life outside the city (wave 107b: alien wildlife and factions; docs/WORLD_EXPANSION.md "more aliens and better enemies"). One table of species, the spawn rules per biome and the
## loot. Pure data and static functions, nothing here touches the scene tree.
##
## Three families:
##   FAUNA  hunt on their own, no camp needed: SKITTER (pack hunters, forest / plains / desert fringe), POPPER (a walking spore bomb), SWARMER (flying swarms over the mountains), DUNE MAW (a giant burrower
##          under the desert sand), REEF LURKER (a sea serpent that strikes out of the water) and DRIFT RAY (a floating stinger over the sea).
##   CAMP   the garrisons of the alien camps in the mountains and canyons, the crash sites and the hive nests: HIVE GRUNT, ACID SPITTER, CRAG BRUTE, SHADE STALKER, SPORE SENTRY (a turret) and the HIVE HEART
##          (the pulsing core of a nest that keeps hatching skitters until it is destroyed).
##   BOSS   one per biome with its own mechanic (see AlienBoss): BROODMOTHER (forest), STORM DRAKE (mountains), SAND LEVIATHAN (desert), DEEP KRAKEN (ocean), HIVE WARDEN (crash sites, plains).
## `mech` picks the behaviour in AlienCreature / AlienBoss; `cls` the way it moves (ground, air, water, burrow, static). Models: the converted Quaternius monster rigs in assets/models/aliens/
## (CC0, tools/open_models/convert_monsters.sh) or procedural bodies built by AlienKit (`proc`). Numbers are EASY-first: the hero hits hard (HeroPower), enemies scale with Difficulty.

const FAUNA := &"fauna"
const CAMP := &"camp"
const BOSS := &"boss"
const GROUND := &"ground"
const AIR := &"air"
const WATER := &"water"
const BURROW := &"burrow"
const STATIC := &"static"
const DIR := "res://assets/models/aliens/"

## id -> row. name | family | cls | model (file in DIR, "" = procedural) | proc (AlienKit builder) | mech | hp | walk run (m/s) | dmg (hero damage, before Difficulty) | reach (melee metres) |
## windup (telegraph s) | cool (s between attacks) | sight (aggro metres) | r cy (body hit sphere radius, centre height) | hr hy (head sphere) | group [min, max] | score | bounty (credits) | glow | vis (drawn scale)
const TABLE := {
	&"skitter": {"name": "SKITTER", "family": FAUNA, "cls": GROUND, "model": "skitter", "mech": &"leap", "hp": 46.0, "walk": 2.6, "run": 9.5, "dmg": 9.0, "reach": 1.9, "windup": 0.5, "cool": 1.3, "sight": 46.0,
		"r": 0.62, "cy": 0.62, "hr": 0.34, "hy": 1.05, "group": [3, 5], "score": 45, "bounty": 22, "glow": Color(1.0, 0.62, 0.15), "vis": 1.1, "pack": true, "leap": [3.0, 9.5], "voice": &"chitter"},
	&"popper": {"name": "SPORE POPPER", "family": FAUNA, "cls": GROUND, "model": "popper", "mech": &"burst", "hp": 34.0, "walk": 1.8, "run": 6.5, "dmg": 24.0, "reach": 3.4, "windup": 1.0, "cool": 0.0, "sight": 36.0,
		"r": 0.55, "cy": 0.55, "hr": 0.3, "hy": 0.85, "group": [1, 3], "score": 35, "bounty": 15, "glow": Color(0.95, 1.0, 0.2), "vis": 1.05, "voice": &"yelp"},
	&"swarmer": {"name": "SWARMER", "family": FAUNA, "cls": AIR, "model": "swarmer", "mech": &"swoop", "hp": 18.0, "walk": 5.0, "run": 13.0, "dmg": 5.0, "reach": 1.3, "windup": 0.45, "cool": 1.6, "sight": 70.0,
		"r": 0.5, "cy": 0.0, "hr": 0.0, "hy": 0.0, "group": [5, 8], "score": 20, "bounty": 8, "glow": Color(1.0, 0.7, 0.1), "vis": 1.2, "alt": [3.0, 9.0], "voice": &"chitter"},
	&"dune_maw": {"name": "DUNE MAW", "family": FAUNA, "cls": BURROW, "model": "", "proc": &"worm", "mech": &"burrow", "hp": 420.0, "walk": 0.0, "run": 11.0, "dmg": 30.0, "reach": 4.2, "windup": 1.4, "cool": 3.5, "sight": 60.0,
		"r": 2.0, "cy": 3.2, "hr": 1.5, "hy": 5.2, "group": [1, 1], "score": 260, "bounty": 120, "glow": Color(1.0, 0.5, 0.15), "vis": 1.0, "voice": &"growl", "rise": 10.0},
	&"reef_lurker": {"name": "REEF LURKER", "family": FAUNA, "cls": WATER, "model": "", "proc": &"serpent", "mech": &"serpent", "hp": 220.0, "walk": 0.0, "run": 12.0, "dmg": 16.0, "reach": 6.0, "windup": 0.9, "cool": 3.0, "sight": 55.0,
		"r": 1.2, "cy": 2.2, "hr": 0.9, "hy": 3.4, "group": [1, 1], "score": 150, "bounty": 70, "glow": Color(0.3, 1.0, 0.95), "vis": 1.0, "voice": &"growl", "rise": 8.0},
	&"drift_ray": {"name": "DRIFT RAY", "family": FAUNA, "cls": AIR, "model": "glider", "mech": &"float", "hp": 52.0, "walk": 2.6, "run": 6.0, "dmg": 9.0, "reach": 0.0, "windup": 0.8, "cool": 2.4, "sight": 52.0,
		"r": 0.9, "cy": 0.0, "hr": 0.0, "hy": 0.0, "group": [2, 3], "score": 60, "bounty": 30, "glow": Color(0.3, 1.0, 0.95), "vis": 1.3, "alt": [4.0, 9.0], "voice": &"chitter", "shot": 20.0},
	# --- the camps ---
	&"hive_grunt": {"name": "HIVE GRUNT", "family": CAMP, "cls": GROUND, "model": "grunt", "mech": &"melee", "hp": 90.0, "walk": 2.0, "run": 6.2, "dmg": 12.0, "reach": 2.1, "windup": 0.55, "cool": 1.5, "sight": 42.0,
		"r": 0.62, "cy": 0.95, "hr": 0.34, "hy": 1.65, "group": [1, 1], "score": 70, "bounty": 30, "glow": Color(0.35, 1.0, 0.55), "vis": 1.0, "voice": &"growl"},
	&"acid_spitter": {"name": "ACID SPITTER", "family": CAMP, "cls": GROUND, "model": "spitter", "mech": &"spit", "hp": 70.0, "walk": 2.0, "run": 5.0, "dmg": 10.0, "reach": 24.0, "windup": 0.7, "cool": 2.2, "sight": 50.0,
		"r": 0.6, "cy": 0.9, "hr": 0.34, "hy": 1.55, "group": [1, 1], "score": 80, "bounty": 35, "glow": Color(0.75, 1.0, 0.15), "vis": 1.0, "voice": &"chitter", "keep": [11.0, 20.0]},
	&"crag_brute": {"name": "CRAG BRUTE", "family": CAMP, "cls": GROUND, "model": "brute", "mech": &"slam", "hp": 360.0, "walk": 1.8, "run": 5.4, "dmg": 26.0, "reach": 3.4, "windup": 1.0, "cool": 2.8, "sight": 44.0,
		"r": 1.1, "cy": 1.6, "hr": 0.6, "hy": 2.8, "group": [1, 1], "score": 220, "bounty": 90, "glow": Color(0.35, 0.8, 1.0), "vis": 1.0, "voice": &"growl", "slam_r": 5.5},
	&"shade_stalker": {"name": "SHADE STALKER", "family": CAMP, "cls": GROUND, "model": "stalker", "mech": &"ambush", "hp": 64.0, "walk": 2.4, "run": 8.5, "dmg": 16.0, "reach": 2.2, "windup": 0.4, "cool": 2.2, "sight": 38.0,
		"r": 0.55, "cy": 0.95, "hr": 0.32, "hy": 1.6, "group": [1, 1], "score": 110, "bounty": 55, "glow": Color(1.0, 0.25, 0.4), "vis": 1.0, "voice": &"chitter", "pounce": [3.0, 11.0]},
	&"spore_sentry": {"name": "SPORE SENTRY", "family": CAMP, "cls": STATIC, "model": "", "proc": &"sentry", "mech": &"turret", "hp": 120.0, "walk": 0.0, "run": 0.0, "dmg": 6.0, "reach": 38.0, "windup": 0.8, "cool": 1.8, "sight": 38.0,
		"r": 0.9, "cy": 1.5, "hr": 0.0, "hy": 0.0, "group": [1, 1], "score": 60, "bounty": 30, "glow": Color(0.8, 1.0, 0.2), "vis": 1.0, "voice": &""},
	&"hive_heart": {"name": "HIVE HEART", "family": CAMP, "cls": STATIC, "model": "", "proc": &"heart", "mech": &"nest", "hp": 320.0, "walk": 0.0, "run": 0.0, "dmg": 0.0, "reach": 0.0, "windup": 0.0, "cool": 9.0, "sight": 60.0,
		"r": 1.9, "cy": 1.7, "hr": 0.0, "hy": 0.0, "group": [1, 1], "score": 200, "bounty": 140, "glow": Color(1.0, 0.3, 0.55), "vis": 1.0, "voice": &""},
	&"relay_pod": {"name": "SHIELD RELAY", "family": CAMP, "cls": STATIC, "model": "", "proc": &"relay", "mech": &"relay", "hp": 140.0, "walk": 0.0, "run": 0.0, "dmg": 0.0, "reach": 0.0, "windup": 0.0, "cool": 0.0, "sight": 0.0,
		"r": 1.1, "cy": 1.8, "hr": 0.0, "hy": 0.0, "group": [1, 1], "score": 90, "bounty": 45, "glow": Color(0.3, 0.9, 1.0), "vis": 1.0, "voice": &""},
	# --- the bosses (one per biome) ---
	&"broodmother": {"name": "BROODMOTHER", "family": BOSS, "cls": GROUND, "model": "broodmother", "mech": &"boss_brood", "hp": 1500.0, "walk": 2.0, "run": 4.6, "dmg": 28.0, "reach": 4.6, "windup": 1.1, "cool": 3.2, "sight": 90.0,
		"r": 1.9, "cy": 2.3, "hr": 1.0, "hy": 4.1, "group": [1, 1], "score": 900, "bounty": 600, "glow": Color(0.8, 0.4, 1.0), "vis": 1.0, "voice": &"growl", "biome": &"forest", "title": "THE FOREST BROODMOTHER"},
	&"storm_drake": {"name": "STORM DRAKE", "family": BOSS, "cls": AIR, "model": "storm_drake", "mech": &"boss_drake", "hp": 1300.0, "walk": 6.0, "run": 24.0, "dmg": 30.0, "reach": 5.0, "windup": 1.4, "cool": 3.0, "sight": 140.0,
		"r": 2.4, "cy": 0.0, "hr": 1.1, "hy": 0.0, "group": [1, 1], "score": 900, "bounty": 600, "glow": Color(0.45, 0.85, 1.0), "vis": 1.0, "voice": &"growl", "biome": &"mountain", "title": "THE STORM DRAKE"},
	&"sand_leviathan": {"name": "SAND LEVIATHAN", "family": BOSS, "cls": BURROW, "model": "", "proc": &"worm", "mech": &"boss_leviathan", "hp": 1700.0, "walk": 0.0, "run": 15.0, "dmg": 34.0, "reach": 9.0, "windup": 1.5, "cool": 4.0, "sight": 120.0,
		"r": 3.4, "cy": 5.0, "hr": 2.4, "hy": 8.4, "group": [1, 1], "score": 1000, "bounty": 700, "glow": Color(1.0, 0.45, 0.1), "vis": 1.9, "voice": &"growl", "biome": &"desert", "title": "THE SAND LEVIATHAN", "rise": 11.0},
	&"deep_kraken": {"name": "DEEP KRAKEN", "family": BOSS, "cls": WATER, "model": "", "proc": &"kraken", "mech": &"boss_kraken", "hp": 1600.0, "walk": 0.0, "run": 6.0, "dmg": 26.0, "reach": 26.0, "windup": 1.3, "cool": 3.0, "sight": 150.0,
		"r": 4.2, "cy": 1.5, "hr": 2.0, "hy": 3.2, "group": [1, 1], "score": 1000, "bounty": 700, "glow": Color(0.3, 1.0, 0.9), "vis": 1.0, "voice": &"growl", "biome": &"ocean", "title": "THE DEEP KRAKEN"},
	&"kraken_arm": {"name": "KRAKEN ARM", "family": BOSS, "cls": WATER, "model": "", "proc": &"tentacle", "mech": &"arm", "hp": 260.0, "walk": 0.0, "run": 0.0, "dmg": 20.0, "reach": 12.0, "windup": 0.9, "cool": 2.6, "sight": 100.0,
		"r": 1.0, "cy": 4.0, "hr": 0.7, "hy": 8.0, "group": [1, 1], "score": 80, "bounty": 40, "glow": Color(0.3, 1.0, 0.9), "vis": 1.0, "voice": &"", "rise": 11.0},
	&"hive_warden": {"name": "HIVE WARDEN", "family": BOSS, "cls": AIR, "model": "warden", "mech": &"boss_warden", "hp": 1400.0, "walk": 4.0, "run": 9.0, "dmg": 24.0, "reach": 30.0, "windup": 1.0, "cool": 2.6, "sight": 110.0,
		"r": 1.7, "cy": 0.0, "hr": 0.9, "hy": 0.0, "group": [1, 1], "score": 900, "bounty": 600, "glow": Color(0.3, 1.0, 0.9), "vis": 1.0, "voice": &"growl", "biome": &"plains", "title": "THE HIVE WARDEN"},
}
const FAUNA_IDS: Array[StringName] = [&"skitter", &"popper", &"swarmer", &"dune_maw", &"reef_lurker", &"drift_ray"]
const CAMP_IDS: Array[StringName] = [&"hive_grunt", &"acid_spitter", &"crag_brute", &"shade_stalker", &"spore_sentry", &"hive_heart", &"relay_pod"]
const BOSS_IDS: Array[StringName] = [&"broodmother", &"storm_drake", &"sand_leviathan", &"deep_kraken", &"hive_warden"]
## biome -> boss (the lairs in AlienSites say where each one lives)
const BOSS_OF_BIOME := {&"forest": &"broodmother", &"mountain": &"storm_drake", &"desert": &"sand_leviathan", &"ocean": &"deep_kraken", &"plains": &"hive_warden"}

## Loot: part id -> {name, value (credits at pickup), crafting (the Crafting part it also adds, "" none), color}. Tech parts (docs: "loot (alien tech parts)").
const PARTS := {
	&"chitin": {"name": "CHITIN PLATE", "value": 12, "crafting": &"scrap", "color": Color(0.7, 0.85, 0.55)},
	&"gland": {"name": "NEURAL GLAND", "value": 30, "crafting": &"alloy", "color": Color(0.85, 0.5, 1.0)},
	&"core": {"name": "HIVE CORE", "value": 80, "crafting": &"core", "color": Color(1.0, 0.45, 0.3)},
	&"crystal": {"name": "QUANTA CRYSTAL", "value": 150, "crafting": &"core", "color": Color(0.4, 0.95, 1.0)},
}
const PART_IDS: Array[StringName] = [&"chitin", &"gland", &"core", &"crystal"]
## species (or family) -> {part: [chance, min, max]}
const LOOT := {
	&"skitter": {&"chitin": [0.5, 1, 1]}, &"popper": {&"gland": [0.35, 1, 1]}, &"swarmer": {&"chitin": [0.3, 1, 1]},
	&"dune_maw": {&"chitin": [1.0, 2, 3], &"gland": [1.0, 1, 2], &"core": [0.7, 1, 1]}, &"reef_lurker": {&"gland": [1.0, 1, 2], &"core": [0.4, 1, 1]}, &"drift_ray": {&"gland": [0.5, 1, 1]},
	&"hive_grunt": {&"chitin": [0.7, 1, 2], &"gland": [0.15, 1, 1]}, &"acid_spitter": {&"gland": [0.5, 1, 1], &"chitin": [0.4, 1, 1]},
	&"crag_brute": {&"chitin": [1.0, 2, 3], &"core": [0.6, 1, 1]}, &"shade_stalker": {&"gland": [0.6, 1, 1], &"core": [0.15, 1, 1]},
	&"spore_sentry": {&"chitin": [0.6, 1, 1]}, &"hive_heart": {&"core": [1.0, 1, 2], &"gland": [1.0, 2, 3]}, &"relay_pod": {&"crystal": [0.5, 1, 1]},
	&"broodmother": {&"core": [1.0, 2, 3], &"crystal": [1.0, 1, 2], &"gland": [1.0, 3, 4]}, &"storm_drake": {&"core": [1.0, 2, 3], &"crystal": [1.0, 1, 2], &"gland": [1.0, 3, 4]},
	&"sand_leviathan": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 2], &"gland": [1.0, 3, 4]}, &"deep_kraken": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 2], &"gland": [1.0, 3, 4]},
	&"hive_warden": {&"core": [1.0, 2, 3], &"crystal": [1.0, 2, 3], &"gland": [1.0, 3, 4]},
}


static func data(id: StringName) -> Dictionary:
	if TABLE.has(id):
		return TABLE[id]
	return RosterSpecies.data(id)                       # the roster-2 enemies (mercenaries, machines, hive infantry, four bosses) share every code path of the alien world


static func ids() -> Array:
	return TABLE.keys()                                 # the alien table only: RosterSpecies.IDS lists the roster-2 enemies


static func family_of(id: StringName) -> StringName:
	return TABLE[id]["family"] if TABLE.has(id) else (StringName(RosterSpecies.data(id).get("family", &"")))


static func model_path(id: StringName) -> String:
	if not TABLE.has(id):
		return ""
	var m := String((TABLE[id] as Dictionary).get("model", ""))
	return DIR + m + ".scn" if m != "" else ""


static func title(id: StringName) -> String:
	if TABLE.has(id):
		return String((TABLE[id] as Dictionary)["name"])
	return RosterSpecies.title(id) if RosterSpecies.has(id) else String(id).to_upper()


## What a place spawns by itself: [[species, weight], ...] for the biome `biome` (TerrainBase.biome_at), ground height `h`, `slope` (rise over run), `night` 0..1 (DayNight.night_now) and `cls`
## (GROUND / AIR / WATER / BURROW). Aliens never live in the city (CITY_SKIRT in AlienWorld). Night makes the pack hunters and the stalking things bolder, the flying swarms come out by day.
static func weights(cls: StringName, biome: StringName, h: float, slope: float, night: float) -> Array:
	var out: Array = []
	match cls:
		GROUND:
			match biome:
				TerrainBase.FOREST:
					out = [[&"skitter", 5.0 + 3.0 * night], [&"popper", 3.0], [&"shade_stalker", 1.2 * night]]
				TerrainBase.MOUNTAIN:
					out = [[&"skitter", 2.0], [&"popper", 1.0], [&"shade_stalker", 1.0 + night]] if slope < 0.9 else [[&"skitter", 1.0]]
				TerrainBase.PLAINS:
					out = [[&"popper", 4.0], [&"skitter", 2.5 + 2.0 * night]]
				TerrainBase.DESERT:
					out = [[&"skitter", 4.0 + 2.0 * night], [&"popper", 2.0]]
				TerrainBase.BEACH:
					out = [[&"popper", 1.5]]
		AIR:
			match biome:
				TerrainBase.MOUNTAIN:
					out = [[&"swarmer", 5.0 * (1.0 - 0.6 * night)]]
				TerrainBase.FOREST:
					out = [[&"swarmer", 1.5 * (1.0 - 0.6 * night)]]
				TerrainBase.OCEAN, TerrainBase.BEACH:
					out = [[&"drift_ray", 4.0]]
		BURROW:
			if biome == TerrainBase.DESERT and slope < 0.5:
				out = [[&"dune_maw", 1.0]]
		WATER:
			if biome == TerrainBase.OCEAN:
				out = [[&"reef_lurker", 1.0]]
	return out


static func pick(list: Array, r: float) -> StringName:
	var sum := 0.0
	for e in list:
		sum += float(e[1])
	if sum <= 0.0001:
		return &""
	var t := r * sum
	for e in list:
		t -= float(e[1])
		if t <= 0.0:
			return e[0]
	return list[list.size() - 1][0]


## The loot of one kill: [[part id, count], ...] (random `rng` draws so tests can seed it).
static func roll_loot(id: StringName, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var tab: Dictionary = LOOT.get(id, RosterSpecies.LOOT.get(id, {}))
	for pid: StringName in tab:
		var row: Array = tab[pid]
		if rng.randf() <= float(row[0]):
			out.append([pid, rng.randi_range(int(row[1]), int(row[2]))])
	return out
