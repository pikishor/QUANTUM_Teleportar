class_name SnakeRows
extends RefCounted
## The QUANTUM SNAKE COMBAT roster as data (wave 115, combat side): ten VERBS (SNAKE PULL, GRAB, DISARM, YANK COVER, NET, LASH, SHIELD, DECOY, TRAP, GUARD) and twelve SNAKE BOMBS (COIL, SWARM,
## CONSTRICTOR MINE, SEEKER, CHAIN, GRAVITY, CLUSTER, BURROWER, FLARE, FREEZING VIPER, STORM COBRA, MEGA PYTHON). Plain names, no real brands. Pure data plus a few static helpers: scripts/quantum/snake_war.gd
## (the controller on the player), snake_verbs.gd / snake_bombs.gd (what each one does) and snake_ui.gd (wheel, icons, HUD text) read it, and the bombs are registered in the BlastTable of wave 113
## (category `snake`) the first time anything snake-related needs them (`ensure()`), so a test that never touches snakes sees the old table.
## Every power is ammo-free and paid with SNAKE ENERGY (the pool of Player.snake, SnakePower.cost scales it by difficulty and HERO MODE) and a cooldown (SnakePower.cd, SkillTree `sw_cool`).
## Row keys: id, name, tag (3 letters), cat (&"verb" | &"bomb"), cost (energy, base), cd (seconds, base), range (reach or throw range in metres), radius (area in metres: the preview ring), lvl (skill level
## needed, 1 = open from the start, HERO MODE opens all), color, icon, note (one line on the card), alt (name of the second mode on ALT, "" = none), hold (true: FIRE is held), plus `entry` for bombs (the BlastTable
## partial: radius, core, enemy, vehicle, element, status, knock, lift, deliver ... and `snake` = the numbers only this roster reads).

const CYAN := Color(0.16, 0.88, 1.0)
const GREEN := Color(0.45, 1.0, 0.3)
const VIOLET := Color(0.72, 0.38, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.82)
const AMBER := Color(1.0, 0.72, 0.2)
const ICE := Color(0.62, 0.88, 1.0)
const STORM := Color(0.62, 0.78, 1.0)
const GOLD := Color(1.0, 0.86, 0.35)
const CAT := &"snake"                                   ## the BlastTable category of the bombs
const SLAM := &"sv_slam"                                ## the table entry of a thrown body landing (SNAKE GRAB)
const LASH_FINISH := &"sv_lash_finish"                  ## the burst that ends a LASH combo

const VERB_IDS: Array[StringName] = [&"sv_pull", &"sv_grab", &"sv_disarm", &"sv_yank", &"sv_net", &"sv_lash", &"sv_shield", &"sv_decoy", &"sv_trap", &"sv_guard"]
const BOMB_IDS: Array[StringName] = [&"sb_coil", &"sb_swarm", &"sb_flare", &"sb_freeze", &"sb_seeker", &"sb_chain", &"sb_cluster", &"sb_constrict", &"sb_burrow", &"sb_gravity", &"sb_storm", &"sb_mega"]

const VERBS := {
	&"sv_pull": {"name": "SNAKE PULL", "tag": "PUL", "cost": 9.0, "cd": 0.9, "range": 38.0, "radius": 0.0, "lvl": 1, "color": CYAN, "icon": &"pull", "alt": "ZIP TO",
		"note": "YANKS AN ENEMY, A PROP, A CAR OR A PICKUP TO YOU  ALT PULLS YOU TO A HEAVY TARGET", "hold": false},
	&"sv_grab": {"name": "SNAKE GRAB", "tag": "GRB", "cost": 14.0, "cd": 1.4, "range": 24.0, "radius": 3.6, "lvl": 1, "color": MAGENTA, "icon": &"grab", "alt": "DROP",
		"note": "HOLD FIRE TO LIFT  LET GO TO THROW  EVERYONE NEAR THE LANDING IS KNOCKED DOWN", "hold": true},
	&"sv_disarm": {"name": "SNAKE DISARM", "tag": "DSM", "cost": 12.0, "cd": 1.2, "range": 32.0, "radius": 0.0, "lvl": 1, "color": AMBER, "icon": &"disarm", "alt": "",
		"note": "SNATCHES THE GUN OUT OF A HAND  YOU CAN FIRE IT FOR A FEW SECONDS", "hold": false},
	&"sv_yank": {"name": "YANK COVER", "tag": "YNK", "cost": 14.0, "cd": 1.8, "range": 30.0, "radius": 3.0, "lvl": 1, "color": GREEN, "icon": &"yank", "alt": "",
		"note": "TEARS A CAR, CRATE OR BARRIER AWAY FROM IN FRONT OF THE ENEMY  IT FLIES AT THEM", "hold": false},
	&"sv_net": {"name": "SNAKE NET", "tag": "NET", "cost": 26.0, "cd": 6.0, "range": 34.0, "radius": 6.0, "lvl": 1, "color": VIOLET, "icon": &"net", "alt": "",
		"note": "A NET OF SNAKES  EVERYONE IN IT DROPS THEIR WEAPON AND CAN NOT MOVE", "hold": false},
	&"sv_lash": {"name": "SNAKE LASH", "tag": "LSH", "cost": 3.0, "cd": 0.3, "range": 7.5, "radius": 0.0, "lvl": 1, "color": CYAN, "icon": &"lash", "alt": "FINISHER",
		"note": "FAST SNAKE WHIPS  THREE HITS AND A FINISHER  A STUNNED ENEMY GOES DOWN AT ONCE", "hold": true},
	&"sv_shield": {"name": "SNAKE SHIELD", "tag": "SHD", "cost": 30.0, "cd": 10.0, "range": 0.0, "radius": 3.5, "lvl": 1, "color": CYAN, "icon": &"shield", "alt": "",
		"note": "THREE SNAKES CIRCLE YOU  THEY STOP SHOTS AND BITE ANYONE WHO COMES CLOSE", "hold": false},
	&"sv_decoy": {"name": "SNAKE DECOY", "tag": "DCY", "cost": 24.0, "cd": 9.0, "range": 20.0, "radius": 0.0, "lvl": 1, "color": MAGENTA, "icon": &"decoy", "alt": "",
		"note": "A COIL THAT LOOKS LIKE YOU  ENEMIES SHOOT AT IT INSTEAD", "hold": false},
	&"sv_trap": {"name": "SNAKE TRAP", "tag": "TRP", "cost": 16.0, "cd": 3.0, "range": 18.0, "radius": 3.2, "lvl": 1, "color": GREEN, "icon": &"trap", "alt": "",
		"note": "A COIL ON THE GROUND  THE FIRST ENEMY WHO STEPS IN IS CAUGHT", "hold": false},
	&"sv_guard": {"name": "SNAKE GUARD", "tag": "GRD", "cost": 36.0, "cd": 14.0, "range": 0.0, "radius": 25.0, "lvl": 1, "color": GREEN, "icon": &"guard", "alt": "",
		"note": "THREE SNAKES FIGHT FOR YOU FOR TWELVE SECONDS  THEY HUNT THE NEAREST ENEMY", "hold": false},
}

## Bombs: `entry` is what BlastTable.register gets. `snake` holds the numbers of the behaviour (wrap seconds, crush damage per second, snakes released, bite damage, marks, hops ...).
const BOMBS := {
	&"sb_coil": {"name": "COIL BOMB", "tag": "COL", "cost": 22.0, "cd": 2.5, "range": 34.0, "lvl": 1, "color": VIOLET, "icon": &"coil", "alt": "", "hold": false,
		"note": "BURSTS INTO COILS  THEY WRAP EVERYONE IN REACH, HOLD THEM STILL AND CRUSH",
		"entry": {"name": "COIL BOMB", "tag": "COL", "radius": 4.5, "core": 1.2, "enemy": 70.0, "vehicle": 110.0, "element": &"quantum", "knock": 2.0, "lift": 1.5, "curve": &"linear", "edge": 0.5, "tier": 1,
			"status": {"k": &"stun", "t": 3.0, "p": 1.0}, "level": 1, "fx": &"snake", "debris": &"none", "crater": 0.0, "scorch": 0.0, "shake": 0.7, "wave": &"ring", "snd": &"snw_burst",
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 1.2, "bounce": 0.25, "range": 34.0},
			"snake": {"wrap": 3.0, "dps": 14.0, "coils": 3}, "note": "WRAPS AND CRUSHES"}},
	&"sb_swarm": {"name": "SWARM BOMB", "tag": "SWM", "cost": 34.0, "cd": 5.0, "range": 34.0, "lvl": 1, "color": GREEN, "icon": &"swarm", "alt": "",  "hold": false,
		"note": "TEN SNAKES SLITHER OUT AND HUNT DOWN EVERYONE IN REACH",
		"entry": {"name": "SWARM BOMB", "tag": "SWM", "radius": 11.0, "core": 0.0, "enemy": 30.0, "vehicle": 30.0, "element": &"toxic", "knock": 0.0, "lift": 0.0, "curve": &"linear", "edge": 0.4, "tier": 2,
			"level": 0, "fx": &"snake", "debris": &"none", "crater": 0.0, "scorch": 0.0, "shake": 0.4, "wave": &"pulse", "prop": 0, "snd": &"snw_burst",
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 1.0, "bounce": 0.2, "range": 34.0},
			"snake": {"snakes": 10, "bite": 24.0, "speed": 13.0, "reach": 11.0}, "note": "SNAKES HUNT"}},
	&"sb_flare": {"name": "FLARE SERPENT", "tag": "FLR", "cost": 16.0, "cd": 4.0, "range": 34.0, "lvl": 1, "color": AMBER, "icon": &"flare", "alt": "", "hold": false,
		"note": "BLINDS EVERYONE IN SIGHT AND MARKS THEM FOR YOUR EYES",
		"entry": {"name": "FLARE SERPENT", "tag": "FLR", "radius": 12.0, "core": 12.0, "enemy": 8.0, "vehicle": 0.0, "element": &"fire", "knock": 0.0, "lift": 0.0, "curve": &"flat", "tier": 1,
			"status": {"k": &"blind", "t": 4.5, "p": 1.0}, "level": 0, "fx": &"flash", "debris": &"none", "crater": 0.0, "scorch": 0.0, "shake": 0.5, "wave": &"pulse", "prop": 0, "civ": 0.0, "cover": false,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 0.8, "bounce": 0.2, "range": 34.0},
			"snake": {"mark": 9.0}, "note": "BLINDS AND MARKS"}},
	&"sb_freeze": {"name": "FREEZING VIPER", "tag": "FRZ", "cost": 30.0, "cd": 8.0, "range": 34.0, "lvl": 1, "color": ICE, "icon": &"freeze", "alt": "", "hold": false,
		"note": "A FIELD OF STILLNESS  EVERYONE INSIDE STANDS FROZEN FOR FIVE SECONDS",
		"entry": {"name": "FREEZING VIPER", "tag": "FRZ", "radius": 7.0, "core": 7.0, "enemy": 30.0, "vehicle": 20.0, "element": &"plasma", "knock": 0.0, "lift": 0.0, "curve": &"flat", "tier": 3,
			"status": {"k": &"freeze", "t": 5.0, "p": 1.0}, "hold": 5.0, "level": 0, "fx": &"bubble", "debris": &"none", "crater": 0.0, "scorch": 0.0, "shake": 0.4, "wave": &"dome", "prop": 0, "snd": &"shield_up", "civ": 0.0,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 0.8, "bounce": 0.2, "range": 34.0},
			"snake": {"fangs": 5}, "note": "STASIS FIELD"}},
	&"sb_seeker": {"name": "SEEKER SNAKE", "tag": "SEK", "cost": 28.0, "cd": 3.5, "range": 60.0, "lvl": 2, "color": CYAN, "icon": &"seeker", "alt": "", "hold": false,
		"note": "A SNAKE THAT HUGS THE GROUND AND DRIVES STRAIGHT AT THE ENEMY BEHIND COVER",
		"entry": {"name": "SEEKER SNAKE", "tag": "SEK", "radius": 4.0, "core": 1.0, "enemy": 150.0, "vehicle": 190.0, "element": &"plasma", "knock": 6.0, "lift": 5.0, "curve": &"quad", "edge": 0.25, "tier": 2,
			"level": 2, "fx": &"snake", "shake": 0.9, "snd": &"snw_burst", "debris": &"none", "crater": 0.0, "scorch": 0.1,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 1.0, "range": 60.0},
			"snake": {"speed": 15.0, "life": 7.0, "steer": 5.0}, "note": "GUIDED SNAKE"}},
	&"sb_chain": {"name": "CHAIN BOMB", "tag": "CHN", "cost": 30.0, "cd": 4.0, "range": 34.0, "lvl": 3, "color": STORM, "icon": &"chain", "alt": "", "hold": false,
		"note": "ARCS FROM ONE ENEMY TO THE NEXT  UP TO SIX IN A ROW",
		"entry": {"name": "CHAIN BOMB", "tag": "CHN", "radius": 6.0, "core": 1.0, "enemy": 55.0, "vehicle": 70.0, "element": &"electric", "knock": 3.0, "lift": 3.0, "curve": &"linear", "edge": 0.4, "tier": 3,
			"status": {"k": &"shock", "t": 2.0, "p": 0.6}, "level": 1, "fx": &"snake", "debris": &"none", "shake": 0.8, "wave": &"pulse", "snd": &"snw_storm", "crater": 0.0, "scorch": 0.0,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 1.2, "bounce": 0.25, "range": 34.0},
			"snake": {"hops": 6, "hop_dmg": 42.0, "hop_range": 9.0, "gap": 0.11}, "note": "CHAIN LIGHTNING SNAKES"}},
	&"sb_cluster": {"name": "CLUSTER SNAKE BOMB", "tag": "CLU", "cost": 38.0, "cd": 6.0, "range": 34.0, "lvl": 4, "color": CYAN, "icon": &"cluster", "alt": "", "hold": false,
		"note": "SPLITS INTO FIVE SNAKES THAT BLOW UP IN A RING AROUND THE TARGET",
		"entry": {"name": "CLUSTER SNAKE BOMB", "tag": "CLU", "radius": 3.6, "core": 0.8, "enemy": 48.0, "vehicle": 70.0, "element": &"plasma", "knock": 4.0, "lift": 4.0, "curve": &"linear", "edge": 0.35, "tier": 3,
			"level": 1, "fx": &"snake", "shake": 0.6, "snd": &"snw_burst", "debris": &"none", "crater": 0.0, "scorch": 0.1,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 1.0, "bounce": 0.3, "range": 34.0},
			"snake": {"bomblets": 4}, "note": "BOMBLET SNAKES"}},
	&"sb_constrict": {"name": "CONSTRICTOR MINE", "tag": "CNS", "cost": 26.0, "cd": 4.0, "range": 14.0, "lvl": 5, "color": VIOLET, "icon": &"constrict", "alt": "", "hold": false,
		"note": "A COIL ON THE GROUND  IT SPRINGS ON THE FIRST FOOT AND CRUSHES EVERYONE AROUND",
		"entry": {"name": "CONSTRICTOR MINE", "tag": "CNS", "radius": 5.0, "core": 1.5, "enemy": 90.0, "vehicle": 130.0, "element": &"quantum", "knock": 3.0, "lift": 2.5, "curve": &"linear", "edge": 0.5, "tier": 3,
			"status": {"k": &"stun", "t": 4.0, "p": 1.0}, "level": 1, "fx": &"snake", "debris": &"none", "shake": 0.8, "snd": &"snw_burst", "crater": 0.0, "scorch": 0.0,
			"deliver": {"mode": &"place", "arm": 0.6, "trigger": 3.0, "life": 90.0, "reach": 14.0, "stick": true},
			"snake": {"wrap": 4.0, "dps": 16.0, "coils": 4}, "note": "A MINE OF COILS"}},
	&"sb_burrow": {"name": "BURROWER", "tag": "BRW", "cost": 30.0, "cd": 5.0, "range": 50.0, "lvl": 6, "color": GREEN, "icon": &"burrow", "alt": "", "hold": false,
		"note": "DIVES INTO THE GROUND, SLITHERS UNDER THE NEAREST CAR AND BLOWS IT SKY HIGH",
		"entry": {"name": "BURROWER", "tag": "BRW", "radius": 5.5, "core": 1.5, "enemy": 90.0, "vehicle": 340.0, "element": &"toxic", "knock": 10.0, "lift": 12.0, "curve": &"quad", "edge": 0.3, "tier": 3,
			"level": 2, "fx": &"dust", "debris": &"rubble", "crater": 1.0, "shake": 1.1,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 1.0, "range": 50.0},
			"snake": {"speed": 11.0, "reach": 26.0, "life": 6.0}, "note": "UNDER THE CAR"}},
	&"sb_gravity": {"name": "GRAVITY SNAKE", "tag": "GRV", "cost": 40.0, "cd": 7.0, "range": 34.0, "lvl": 8, "color": VIOLET, "icon": &"gravity", "alt": "", "hold": false,
		"note": "PULLS EVERYONE IN REACH INTO ONE KNOT  THEN COLLAPSES",
		"entry": {"name": "GRAVITY SNAKE", "tag": "GRV", "radius": 9.0, "core": 0.0, "enemy": 130.0, "vehicle": 150.0, "element": &"quantum", "knock": -10.0, "lift": 4.0, "curve": &"quad", "edge": 0.3, "tier": 4,
			"status": {"k": &"pull", "t": 1.4, "p": 9.0}, "hold": 1.4, "level": 2, "fx": &"well", "wave": &"implode", "snd": &"collapse", "shake": 1.0,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 0.8, "range": 34.0},
			"snake": {"knots": 5}, "note": "A KNOT OF SNAKES"}},
	&"sb_storm": {"name": "STORM COBRA", "tag": "STC", "cost": 45.0, "cd": 9.0, "range": 34.0, "lvl": 10, "color": STORM, "icon": &"storm", "alt": "", "hold": false,
		"note": "A COBRA RISES, FLARES ITS HOOD AND ARCS LIGHTNING AT EVERYONE NEARBY",
		"entry": {"name": "STORM COBRA", "tag": "STC", "radius": 8.0, "core": 2.0, "enemy": 28.0, "vehicle": 36.0, "element": &"electric", "knock": 3.0, "lift": 3.0, "curve": &"flat", "tier": 4,
			"status": {"k": &"shock", "t": 2.0, "p": 0.5}, "level": 1, "fx": &"snake", "debris": &"none", "shake": 0.8, "wave": &"pulse", "snd": &"snw_storm", "crater": 0.0, "scorch": 0.0,
			"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 0.6, "range": 34.0},
			"snake": {"bolts": 10, "gap": 0.3, "bolt_dmg": 30.0, "rise": 0.7}, "note": "LIGHTNING COBRA"}},
	&"sb_mega": {"name": "MEGA PYTHON", "tag": "MGP", "cost": 100.0, "cd": 40.0, "range": 40.0, "lvl": 15, "color": GOLD, "icon": &"mega", "alt": "", "hold": false,
		"note": "A GIANT PYTHON RISES AND SLAMS  THE WHOLE STREET IS FLATTENED  HERO MODE OR LEVEL 15",
		"entry": {"name": "MEGA PYTHON", "tag": "MGP", "radius": 20.0, "core": 6.0, "enemy": 400.0, "vehicle": 520.0, "element": &"quantum", "knock": 18.0, "lift": 14.0, "curve": &"linear", "edge": 0.3, "tier": 6,
			"level": 3, "fx": &"mega", "shake": 1.8, "wave": &"ring", "crater": 1.6, "scorch": 1.0, "debris": &"rubble", "cover": false, "snd": &"boom",
			"deliver": {"mode": &"cast", "delay": 0.0},
			"snake": {"rise": 1.1, "coils": 8}, "note": "THE ULTIMATE"}},
}

static var _done := false


## Registers the bombs (and the two internal blasts of the verbs) in the BlastTable. Idempotent; called by anything that needs the table entries of this roster.
static func ensure() -> void:
	if _done and BlastTable.has_entry(&"sb_coil"):
		return
	_done = true
	for id: StringName in BOMB_IDS:
		var b: Dictionary = BOMBS[id]
		var e: Dictionary = (b["entry"] as Dictionary).duplicate(true)
		e["cat"] = CAT
		e["id"] = id
		BlastTable.register(id, e)
	BlastTable.register(SLAM, {"cat": &"internal", "name": "SNAKE SLAM", "tag": "SLM", "radius": 3.6, "core": 0.8, "enemy": 60.0, "vehicle": 80.0, "element": &"quantum", "knock": 7.0, "lift": 6.0,
		"curve": &"linear", "edge": 0.4, "level": 1, "fx": &"default", "shake": 0.8, "friendly": false, "debris": &"sparks", "crater": 0.2, "scorch": 0.2})
	BlastTable.register(&"sb_bomblet", {"cat": &"internal", "name": "BOMBLET SNAKE", "tag": "BML", "radius": 3.4, "core": 0.6, "enemy": 48.0, "vehicle": 70.0, "element": &"plasma", "knock": 4.0, "lift": 4.0,
		"curve": &"linear", "edge": 0.35, "level": 1, "fx": &"snake", "shake": 0.45, "friendly": false, "debris": &"none", "crater": 0.0, "scorch": 0.0, "snd": &"snw_burst"})
	BlastTable.register(LASH_FINISH, {"cat": &"internal", "name": "SNAKE LASH FINISH", "tag": "LSF", "radius": 2.6, "core": 0.5, "enemy": 70.0, "vehicle": 40.0, "element": &"plasma", "knock": 8.0, "lift": 4.0,
		"curve": &"linear", "edge": 0.4, "level": 0, "fx": &"shock", "shake": 0.5, "friendly": false, "debris": &"sparks", "crater": 0.0, "scorch": 0.0, "prop": 0})


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(VERB_IDS)
	out.append_array(BOMB_IDS)
	return out


static func has(id: StringName) -> bool:
	return VERBS.has(id) or BOMBS.has(id)


static func is_bomb(id: StringName) -> bool:
	return BOMBS.has(id)


## The row of a power (verb or bomb); {} for an unknown id.
static func row(id: StringName) -> Dictionary:
	if VERBS.has(id):
		var v: Dictionary = (VERBS[id] as Dictionary).duplicate()
		v["id"] = id
		v["cat"] = &"verb"
		return v
	if BOMBS.has(id):
		var b: Dictionary = (BOMBS[id] as Dictionary).duplicate()
		b["id"] = id
		b["cat"] = &"bomb"
		return b
	return {}


static func title(id: StringName) -> String:
	return String((VERBS.get(id, BOMBS.get(id, {})) as Dictionary).get("name", String(id).to_upper()))


## The blast radius of a bomb as the table says it (the preview ring and the card read this), or the area of a verb.
static func radius_of(id: StringName) -> float:
	if BOMBS.has(id):
		ensure()
		return float(BlastTable.entry(id).get("radius", 0.0))
	return float((VERBS.get(id, {}) as Dictionary).get("radius", 0.0))


static func color_of(id: StringName) -> Color:
	return (VERBS.get(id, BOMBS.get(id, {})) as Dictionary).get("color", CYAN)


static func lvl_of(id: StringName) -> int:
	return int((VERBS.get(id, BOMBS.get(id, {})) as Dictionary).get("lvl", 1))


## Open to the hero: HERO MODE opens all; the others by skill level (verbs and the first bombs from the start).
static func unlocked(id: StringName) -> bool:
	if not has(id):
		return false
	if WeaponDefs.hero_mode:
		return true
	return SkillTree.level() >= lvl_of(id)


## The second mode on ALT: a name ("" = the power has none).
static func alt_name(id: StringName) -> String:
	return String((VERBS.get(id, BOMBS.get(id, {})) as Dictionary).get("alt", ""))


## The caption of the wheel and the card: NAME  COST  RADIUS.
static func caption(id: StringName) -> String:
	var r := row(id)
	if r.is_empty():
		return ""
	var s := "%s   %d ENERGY" % [String(r["name"]), roundi(SnakePower.cost(float(r["cost"])) / maxf(SnakePower.cost(1.0), 0.0001)) if SnakePower.cost(1.0) > 0.0 else roundi(float(r["cost"]))]
	var rad := radius_of(id)
	if rad > 0.5:
		s += "   RADIUS %d M" % roundi(rad)
	if not unlocked(id):
		s += "   LEVEL %d" % lvl_of(id)
	return s
