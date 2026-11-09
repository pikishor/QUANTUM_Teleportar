class_name AnimalSpecies
extends RefCounted
## The animals of the outskirts, the coast and the sea (wave 107): one table of species (model, size, speed, nerve, bounty, voice) and the rules of where each lives
## (`weights`: biome, height above the sea, time of day, farm, shore). Models are the converted Quaternius packs in assets/models/animals/ (CC0, art_sources/open_animals);
## the lizard is built in code (WildlifeKit). Pure data and static functions: nothing here touches the scene tree.
##
## Classes (each has its own cap per tier in WildlifeWorld): land (walkers), air (flocks), water (fish, dolphins, sharks, whales), small (lizards, near the hero only).
## Roles: prey flee from the hero, gunfire, blasts, cars and predators; predators hunt prey they can reach; neutral ones just live (fish, birds).
## `stride` is the ground speed one second of the clip covers at speed_scale 1 (the clip plays faster or slower to keep the feet from sliding).

const LAND := &"land"
const AIR := &"air"
const WATER := &"water"
const SMALL := &"small"
const PREY := &"prey"
const PREDATOR := &"predator"
const NEUTRAL := &"neutral"
const DIR := "res://assets/models/animals/"

const TABLE := {
	&"deer": {"name": "DEER", "cls": LAND, "role": PREY, "hp": 40.0, "bounty": 30, "walk": 1.5, "run": 9.5, "stride_walk": 1.5, "stride_run": 6.0, "flee": 34.0, "group": [3, 6], "hit_r": 0.7, "mid": 0.8, "sleeps": true, "sound": &"animal_snort", "gap": 14.0, "mul": [0.9, 1.1]},
	&"goat": {"name": "MOUNTAIN GOAT", "cls": LAND, "role": PREY, "hp": 30.0, "bounty": 30, "walk": 1.4, "run": 8.0, "stride_walk": 1.4, "stride_run": 5.5, "flee": 22.0, "group": [3, 5], "hit_r": 0.55, "mid": 0.7, "sleeps": true, "sound": &"animal_goat", "gap": 11.0, "mul": [0.85, 1.1], "climb": true},
	&"boar": {"name": "WILD BOAR", "cls": LAND, "role": PREY, "hp": 55.0, "bounty": 30, "walk": 1.3, "run": 7.5, "stride_walk": 1.2, "stride_run": 4.5, "flee": 18.0, "group": [2, 4], "hit_r": 0.55, "mid": 0.45, "sleeps": true, "sound": &"", "gap": 0.0, "mul": [0.8, 1.15], "aggro": true},
	&"sheep": {"name": "SHEEP", "cls": LAND, "role": PREY, "hp": 30.0, "bounty": 10, "walk": 1.0, "run": 6.0, "stride_walk": 1.2, "stride_run": 4.5, "flee": 14.0, "group": [4, 8], "hit_r": 0.5, "mid": 0.55, "sleeps": true, "sound": &"animal_sheep", "gap": 9.0, "mul": [0.9, 1.05]},
	&"cow": {"name": "COW", "cls": LAND, "role": PREY, "hp": 70.0, "bounty": 15, "walk": 0.9, "run": 5.0, "stride_walk": 1.3, "stride_run": 5.0, "flee": 9.0, "group": [2, 5], "hit_r": 0.8, "mid": 0.75, "sleeps": true, "sound": &"animal_cow", "gap": 12.0, "mul": [0.92, 1.05]},
	&"horse": {"name": "HORSE", "cls": LAND, "role": PREY, "hp": 80.0, "bounty": 25, "walk": 1.5, "run": 10.0, "stride_walk": 1.6, "stride_run": 6.5, "flee": 22.0, "group": [2, 4], "hit_r": 0.85, "mid": 1.0, "sleeps": true, "sound": &"animal_horse", "gap": 16.0, "mul": [0.8, 1.15]},
	&"zebra": {"name": "ZEBRA", "cls": LAND, "role": PREY, "hp": 60.0, "bounty": 25, "walk": 1.5, "run": 10.5, "stride_walk": 1.6, "stride_run": 6.5, "flee": 30.0, "group": [3, 6], "hit_r": 0.8, "mid": 0.95, "sleeps": true, "sound": &"animal_horse", "gap": 18.0, "mul": [0.95, 1.05]},
	&"wolf": {"name": "WOLF", "cls": LAND, "role": PREDATOR, "hp": 60.0, "bounty": 45, "walk": 1.8, "run": 9.0, "stride_walk": 1.7, "stride_run": 3.4, "flee": 12.0, "group": [2, 4], "hit_r": 0.6, "mid": 0.6, "sleeps": false, "night": 2.5, "sound": &"animal_wolf", "gap": 24.0, "mul": [0.8, 1.1], "aggro": true, "bite": 7.0},
	&"coyote": {"name": "COYOTE", "cls": LAND, "role": PREDATOR, "hp": 40.0, "bounty": 35, "walk": 1.8, "run": 9.0, "stride_walk": 1.7, "stride_run": 3.4, "flee": 14.0, "group": [1, 3], "hit_r": 0.5, "mid": 0.5, "sleeps": false, "night": 2.0, "sound": &"animal_coyote", "gap": 22.0, "mul": [0.85, 1.1], "aggro": true, "bite": 5.0},
	&"fox": {"name": "FOX", "cls": LAND, "role": NEUTRAL, "hp": 25.0, "bounty": 20, "walk": 1.6, "run": 8.0, "stride_walk": 1.4, "stride_run": 3.0, "flee": 18.0, "group": [1, 2], "hit_r": 0.4, "mid": 0.4, "sleeps": false, "night": 1.6, "sound": &"", "gap": 0.0, "mul": [0.9, 1.1]},
	&"lizard": {"vis": 1.0, "name": "LIZARD", "cls": SMALL, "role": NEUTRAL, "hp": 5.0, "bounty": 3, "walk": 0.6, "run": 3.2, "flee": 7.0, "group": [1, 2], "hit_r": 0.22, "mid": 0.08, "sleeps": false, "sound": &"", "gap": 0.0, "mul": [0.8, 1.2], "day_only": true},
	&"songbird": {"vis": 2.2, "name": "BIRDS", "cls": AIR, "role": NEUTRAL, "hp": 5.0, "bounty": 5, "alt": [6.0, 15.0], "orbit": [14.0, 34.0], "speed": 7.5, "flap": 1.8, "flee": 22.0, "group": [4, 9], "hit_r": 0.35, "mid": 0.0, "sound": &"animal_bird", "gap": 7.0, "mul": [0.8, 1.2], "day_only": true},
	&"seagull": {"vis": 1.5, "name": "SEAGULL", "cls": AIR, "role": NEUTRAL, "hp": 8.0, "bounty": 5, "alt": [5.0, 13.0], "orbit": [18.0, 40.0], "speed": 6.5, "flap": 1.2, "flee": 16.0, "group": [3, 7], "hit_r": 0.4, "mid": 0.0, "sound": &"animal_gull", "gap": 5.0, "mul": [0.92, 1.05], "perch": true},
	&"eagle": {"vis": 1.5, "name": "EAGLE", "cls": AIR, "role": NEUTRAL, "hp": 12.0, "bounty": 20, "alt": [45.0, 100.0], "orbit": [50.0, 95.0], "speed": 11.0, "flap": 0.35, "flee": 40.0, "group": [1, 2], "hit_r": 0.7, "mid": 0.0, "sound": &"animal_eagle", "gap": 22.0, "mul": [0.85, 1.1], "day_only": true},
	&"fish": {"vis": 1.9, "name": "FISH", "cls": WATER, "role": NEUTRAL, "hp": 3.0, "bounty": 0, "speed": 1.8, "flee": 7.0, "group": [5, 9], "hit_r": 0.25, "mid": 0.0, "sound": &"", "gap": 0.0, "depth": 0.45, "mul": [0.8, 1.2], "swim_flap": 3.5},
	&"dolphin": {"vis": 1.1, "name": "DOLPHIN", "cls": WATER, "role": NEUTRAL, "hp": 90.0, "bounty": 0, "speed": 6.5, "flee": 0.0, "group": [2, 4], "hit_r": 0.9, "mid": 0.0, "sound": &"animal_dolphin", "gap": 9.0, "depth": 0.0, "mul": [0.9, 1.1], "swim_flap": 1.6, "porpoise": true},
	&"shark": {"vis": 1.0, "name": "SHARK", "cls": WATER, "role": PREDATOR, "hp": 140.0, "bounty": 80, "speed": 3.2, "flee": 0.0, "group": [1, 1], "hit_r": 1.3, "mid": 0.0, "sound": &"", "gap": 0.0, "depth": 0.75, "mul": [0.9, 1.1], "swim_flap": 1.3},
	&"whale": {"vis": 1.0, "name": "WHALE", "cls": WATER, "role": NEUTRAL, "hp": 600.0, "bounty": 0, "speed": 3.0, "flee": 0.0, "group": [1, 1], "hit_r": 4.0, "mid": 0.0, "sound": &"animal_dolphin", "gap": 40.0, "depth": 3.0, "mul": [0.95, 1.05], "swim_flap": 0.6, "far": true},
}
## species id -> model file (one scene per species, converted by tools/open_models/convert_animals.sh); the lizard has no file
const MODELS := {
	&"deer": "deer", &"goat": "goat", &"boar": "boar", &"sheep": "sheep", &"cow": "cow", &"horse": "horse", &"zebra": "zebra", &"wolf": "wolf", &"coyote": "coyote", &"fox": "fox",
	&"songbird": "songbird", &"seagull": "seagull", &"eagle": "eagle", &"fish": "fish", &"dolphin": "dolphin", &"shark": "shark", &"whale": "whale",
}
const FARMS := [&"south_farm", &"north_farm"]
const FARM_RADIUS := 260.0
## the plateau of the city is flat grass beyond the street grid: animals live there only from this distance (max-norm) from the centre
const CITY_SKIRT := 760.0


static func data(id: StringName) -> Dictionary:
	return TABLE[id] if TABLE.has(id) else {}


static func ids() -> Array:
	return TABLE.keys()


static func model_path(id: StringName) -> String:
	return DIR + String(MODELS[id]) + ".scn" if MODELS.has(id) else ""


static func cls_of(id: StringName) -> StringName:
	return TABLE[id]["cls"]


## Land animals of a place. `biome` is TerrainBase.biome_at, `h` the ground height, `slope` rise over run, `night` 0..1, `farm` how close (0..1) a farm is, `shore` true on the beach.
## Returns [[id, weight], ...] for the class asked.
static func weights(cls: StringName, biome: StringName, h: float, slope: float, night: float, farm: float, shore: bool) -> Array:
	var out: Array = []
	match cls:
		LAND:
			match biome:
				TerrainBase.FOREST:
					out = [[&"deer", 5.0], [&"boar", 3.0], [&"fox", 2.0], [&"wolf", 2.0], [&"horse", 0.4 * farm]]
					if h > 90.0 and slope > 0.25:
						out.append([&"goat", 3.0])
				TerrainBase.MOUNTAIN:
					out = [[&"goat", 6.0 if slope > 0.2 else 2.0], [&"wolf", 2.0], [&"fox", 1.0], [&"deer", 1.0 if h < 190.0 else 0.0]]
				TerrainBase.PLAINS, TerrainBase.CITY:
					out = [[&"deer", 2.0], [&"fox", 1.0], [&"coyote", 1.0], [&"sheep", 1.0 + 6.0 * farm], [&"cow", 0.6 + 5.0 * farm], [&"horse", 0.3 + 3.0 * farm]]
				TerrainBase.DESERT:
					out = [[&"coyote", 4.0], [&"zebra", 3.0], [&"fox", 0.6]]
				TerrainBase.BEACH:
					out = [[&"fox", 0.5]]
		AIR:
			match biome:
				TerrainBase.FOREST:
					out = [[&"songbird", 5.0], [&"eagle", 0.6 if h > 50.0 else 0.2]]
				TerrainBase.MOUNTAIN:
					out = [[&"eagle", 2.5], [&"songbird", 0.5]]
				TerrainBase.PLAINS, TerrainBase.CITY:
					out = [[&"songbird", 2.5], [&"eagle", 0.3]]
				TerrainBase.DESERT:
					out = [[&"eagle", 0.8], [&"songbird", 0.5]]
				TerrainBase.BEACH, TerrainBase.OCEAN:
					out = [[&"seagull", 6.0]]
		WATER:
			match biome:
				TerrainBase.OCEAN:
					out = [[&"dolphin", 4.0], [&"shark", 1.6], [&"whale", 0.25]]
				_:
					out = [[&"fish", 1.0]]
		SMALL:
			if biome == TerrainBase.DESERT or (biome == TerrainBase.PLAINS and h > 3.0):
				out = [[&"lizard", 1.0]]
	for e in out:
		var s: Dictionary = TABLE[e[0]]
		var w: float = e[1]
		if s.get("day_only", false):
			w *= 1.0 - night
		w *= lerpf(1.0, float(s.get("night", 1.0)), night)
		e[1] = w
	return out


## Weighted pick from the `weights` list with `r` in 0..1; &"" when nothing has weight.
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
