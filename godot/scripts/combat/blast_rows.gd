class_name BlastRows
extends RefCounted
## The rows of the BLAST ARSENAL (wave 113): 65 explosives, launchers, mines, strikes, ordnance, hero ultimates and world blasters, every one with its own radius, core, falloff curve, damage per
## target type, knockback, status, colours and delivery. BlastTable expands a row into a full entry (category defaults + the row) and is the only reader; WeaponDefsBlast builds the hero's weapons
## from the same rows. Pure data: this file reads nothing else, so WeaponDefs may load it while its own tables are being built.
##
## Row: [id, NAME, radius m, core m, enemy damage, vehicle damage, element, extra]
##   radius  distance from the centre at which damage reaches its edge value (nothing is hurt beyond it; vehicles count their own length on top)
##   core    flat full-damage core (m)                         enemy / vehicle  damage at the centre (civilians x1.3, animals x0.9, the hero's share `hero` x0.3 of the enemy value)
## extra keys: curve (flat | linear | quad), edge (damage share at the radius, linear and quad), knock + lift (m/s of launch for a person at the centre), status {k, t, p}, wave, shake, snd,
##   crater, scorch, debris, level (structure destruction 0..3), friendly (hurts the hero), cover (walls shelter), fx (recipe), hold (s the area stays), fire [radius, seconds, dps], cone (half angle),
##   civ / hero / animal (damage multipliers on the enemy value), prop (0 = props are not broken), tags, tier (1..6, ladder and price), note (one line for the card), tag (3 letters),
##   deliver {mode: throw | launch | place | mark | drop | cast | world, ...} and w {weapon numbers: mag, reserve, interval, reload, range, snd, vol, pitch}.

const CATS: Array[StringName] = [&"grenade", &"launcher", &"mine", &"strike", &"ordnance", &"ultimate", &"world"]
const CAT_NAMES := {&"grenade": "THROWN GRENADES", &"launcher": "LAUNCHERS", &"mine": "MINES AND CHARGES", &"strike": "CALLED-IN STRIKES", &"ordnance": "VEHICLE AND AIRCRAFT ORDNANCE", &"ultimate": "HERO ULTIMATES",
	&"world": "WORLD BLASTERS"}

## What every entry of a category has unless its row says otherwise.
const DEFAULTS := {
	&"grenade": {"curve": &"linear", "edge": 0.25, "knock": 6.0, "lift": 6.1, "shake": 1.0, "wave": &"ring", "snd": &"boom", "crater": 0.8, "scorch": 0.9, "debris": &"rubble", "level": 1, "friendly": true, "cover": true, "fx": &"default",
		"deliver": {"mode": &"throw", "speed": 20.0, "grav": 22.0, "fuse": 2.2, "bounce": 0.35, "stick": false, "range": 34.0}, "w": {"mag": 1, "reserve": 4, "interval": 0.9, "reload": 1.4, "range": 40.0, "vol": -4.0, "pitch": 1.0}},
	&"launcher": {"curve": &"linear", "edge": 0.25, "knock": 8.0, "lift": 7.9, "shake": 1.1, "wave": &"ring", "snd": &"boom", "crater": 1.0, "scorch": 1.0, "debris": &"rubble", "level": 2, "friendly": true, "cover": true, "fx": &"default",
		"deliver": {"mode": &"launch", "speed": 55.0, "grav": 5.0, "life": 4.0, "guide": &"none", "turn": 0.0, "airburst": 0.0, "range": 150.0}, "w": {"mag": 1, "reserve": 8, "interval": 1.1, "reload": 2.4, "range": 150.0, "vol": -1.0, "pitch": 1.0}},
	&"mine": {"curve": &"linear", "edge": 0.3, "knock": 9.0, "lift": 10.5, "shake": 1.1, "wave": &"ring", "snd": &"boom", "crater": 1.0, "scorch": 1.0, "debris": &"rubble", "level": 2, "friendly": true, "cover": true, "fx": &"default",
		"deliver": {"mode": &"place", "arm": 0.8, "trigger": 2.6, "life": 120.0, "reach": 14.0, "cone": 0.0, "wire": 0.0, "remote": false, "timer": 0.0, "stick": true, "hop": 0.0}, "w": {"mag": 1, "reserve": 4, "interval": 0.7, "reload": 1.2, "range": 14.0, "vol": -6.0, "pitch": 1.0}},
	&"strike": {"curve": &"linear", "edge": 0.25, "knock": 12.0, "lift": 12.2, "shake": 1.3, "wave": &"ring", "snd": &"boom", "crater": 1.2, "scorch": 1.2, "debris": &"rubble", "level": 2, "friendly": true, "cover": true, "fx": &"default",
		"deliver": {"mode": &"mark", "delay": 3.5, "count": 1, "spread": 0.0, "gap": 0.5, "pattern": &"single", "length": 0.0, "range": 90.0, "speed": 24.0, "grav": 16.0}, "w": {"mag": 1, "reserve": 2, "interval": 1.2, "reload": 1.8, "range": 90.0, "vol": -4.0, "pitch": 1.0}},
	&"ordnance": {"curve": &"linear", "edge": 0.25, "knock": 12.0, "lift": 12.2, "shake": 1.3, "wave": &"ring", "snd": &"boom", "crater": 1.2, "scorch": 1.2, "debris": &"rubble", "level": 3, "friendly": false, "cover": true, "fx": &"default",
		"deliver": {"mode": &"drop", "grav": 22.0, "fuse": 0.0}},
	&"ultimate": {"curve": &"linear", "edge": 0.3, "knock": 14.0, "lift": 14.0, "shake": 1.6, "wave": &"ring", "snd": &"boom", "crater": 1.4, "scorch": 1.2, "debris": &"rubble", "level": 3, "friendly": false, "cover": false, "fx": &"default",
		"deliver": {"mode": &"cast", "delay": 0.0}},
	&"world": {"curve": &"quad", "edge": 0.2, "knock": 10.0, "lift": 10.5, "shake": 1.2, "wave": &"ring", "snd": &"boom", "crater": 1.2, "scorch": 1.3, "debris": &"metal", "level": 2, "friendly": true, "cover": true, "fx": &"default",
		"deliver": {"mode": &"world"}},
}

const GRENADES: Array = [
	[&"gr_frag", "FRAG POP", 6.0, 1.2, 130.0, 90.0, &"fire", {"tag": "FRG", "curve": &"quad", "edge": 0.18, "knock": 7.0, "lift": 7.0, "debris": &"metal", "tier": 1, "note": "BOUNCES, THEN GOES  SHREDS A ROOM",
		"deliver": {"fuse": 2.4, "bounce": 0.45}, "w": {"reserve": 5, "interval": 0.8}}],
	[&"gr_tick", "TICK GRENADE", 4.5, 1.0, 150.0, 170.0, &"plasma", {"tag": "TCK", "knock": 5.0, "lift": 5.2, "tier": 2, "note": "STICKS TO A PERSON, A CAR OR A WALL",
		"deliver": {"fuse": 1.6, "stick": true, "bounce": 0.0}, "w": {"reserve": 4}}],
	[&"gr_scatter", "SCATTER POD", 3.2, 0.6, 70.0, 60.0, &"fire", {"tag": "SCP", "tier": 3, "note": "OPENS IN THE AIR  SIX BOMBLETS IN A RING", "wave": &"ring", "cluster": [6, 7.0, 0.14],
		"deliver": {"fuse": 1.2, "bounce": 0.2, "opens": 1.0}, "w": {"reserve": 4, "interval": 1.0}}],
	[&"gr_ember", "EMBER BOTTLE", 4.0, 1.5, 40.0, 50.0, &"fire", {"tag": "EMB", "knock": 3.0, "lift": 3.5, "tier": 2, "note": "SPLASHES FIRE  A BURNING FIELD FOR 7 SECONDS", "status": {"k": &"burn", "t": 4.0, "p": 14.0},
		"fire": [5.0, 7.0, 22.0], "crater": 0.4, "scorch": 1.5, "fx": &"ember", "wave": &"flat", "deliver": {"fuse": 0.0, "bounce": 0.0, "impact": true}, "w": {"reserve": 4}}],
	[&"gr_blinder", "BLINDER", 11.0, 4.0, 0.0, 0.0, &"fire", {"tag": "BLN", "curve": &"flat", "knock": 0.0, "lift": 0.0, "tier": 1, "note": "A WHITE FLASH  GUARDS FREEZE AND LOSE YOU", "status": {"k": &"blind", "t": 4.0, "p": 1.0},
		"fx": &"flash", "wave": &"flat", "snd": &"explosion_small", "snd_pitch": 1.6, "crater": 0.0, "scorch": 0.0, "debris": &"none", "prop": 0, "level": 0, "civ": 0.0, "hero": 0.0, "animal": 0.0, "cover": true,
		"deliver": {"fuse": 1.4}, "w": {"reserve": 5, "interval": 0.7}}],
	[&"gr_fog", "FOG CAN", 7.0, 7.0, 0.0, 0.0, &"fire", {"tag": "FOG", "curve": &"flat", "knock": 0.0, "lift": 0.0, "tier": 1, "note": "A SMOKE CLOUD FOR 14 SECONDS  NOBODY SEES THROUGH IT", "status": {"k": &"smoke", "t": 14.0, "p": 1.0},
		"hold": 14.0, "fx": &"smoke", "wave": &"none", "snd": &"explosion_small", "snd_pitch": 0.8, "crater": 0.0, "scorch": 0.0, "debris": &"none", "prop": 0, "level": 0, "civ": 0.0, "hero": 0.0, "animal": 0.0, "cover": false,
		"deliver": {"fuse": 0.9, "bounce": 0.1}, "w": {"reserve": 4}}],
	[&"gr_spark", "SPARK PULSE", 10.0, 10.0, 14.0, 60.0, &"electric", {"tag": "SPK", "curve": &"flat", "knock": 0.0, "lift": 0.0, "tier": 2, "note": "SHUTS DOWN MACHINES AND ENGINES FOR 3 SECONDS", "status": {"k": &"emp", "t": 3.5, "p": 1.0},
		"fx": &"emp", "wave": &"pulse", "snd": &"explosion_small", "snd_pitch": 1.25, "crater": 0.0, "scorch": 0.1, "debris": &"sparks", "prop": 0, "level": 0, "civ": 0.0, "cover": false, "deliver": {"fuse": 0.9}, "w": {"reserve": 3}}],
	[&"gr_well", "WELL SEED", 8.0, 0.0, 70.0, 60.0, &"quantum", {"tag": "WEL", "curve": &"linear", "edge": 0.35, "knock": -9.0, "lift": 1.8, "tier": 3, "note": "DRAGS EVERYONE IN FOR 2 SECONDS, THEN COLLAPSES", "status": {"k": &"pull", "t": 2.0, "p": 9.0},
		"hold": 2.0, "fx": &"well", "wave": &"implode", "snd": &"collapse", "deliver": {"fuse": 0.0, "bounce": 0.0, "impact": true}, "w": {"reserve": 3, "interval": 1.0}}],
	[&"gr_still", "STILL POD", 6.0, 6.0, 0.0, 0.0, &"plasma", {"tag": "STL", "curve": &"flat", "knock": 0.0, "lift": 0.0, "tier": 3, "note": "A BUBBLE THAT FREEZES EVERYONE INSIDE FOR 6 SECONDS", "status": {"k": &"freeze", "t": 6.0, "p": 1.0},
		"hold": 6.0, "fx": &"bubble", "wave": &"dome", "snd": &"shield_up", "crater": 0.0, "scorch": 0.0, "debris": &"none", "prop": 0, "level": 0, "civ": 0.0, "hero": 0.0, "animal": 0.0, "cover": false,
		"deliver": {"fuse": 0.0, "bounce": 0.0, "impact": true}, "w": {"reserve": 3}}],
	[&"gr_arc", "ARC COIL", 7.0, 2.0, 85.0, 70.0, &"electric", {"tag": "ARC", "knock": 3.0, "lift": 3.5, "tier": 2, "note": "LIGHTNING JUMPS TO EVERYONE NEAR THE BLAST", "status": {"k": &"shock", "t": 2.0, "p": 0.4}, "fx": &"shock",
		"debris": &"sparks", "snd": &"explosion_small", "snd_pitch": 0.9, "deliver": {"fuse": 1.8}, "w": {"reserve": 4}}],
	[&"gr_rattle", "RATTLE BANG", 5.0, 1.0, 45.0, 40.0, &"fire", {"tag": "RAT", "knock": 4.0, "lift": 4.4, "tier": 1, "note": "A DECOY THAT DRAWS GUARDS IN, THEN BANGS", "status": {"k": &"stun", "t": 1.6, "p": 1.0},
		"hold": 3.0, "fx": &"decoy", "deliver": {"fuse": 3.0, "lure": 30.0, "bounce": 0.1}, "w": {"reserve": 4}}],
	[&"gr_collapse", "COLLAPSE CHARGE", 9.0, 2.5, 160.0, 140.0, &"quantum", {"tag": "COL", "curve": &"quad", "edge": 0.2, "knock": -6.0, "lift": 8.8, "tier": 4, "note": "THE SPACE CLOSES IN, THEN BURSTS OUT", "fx": &"collapse", "wave": &"implode", "snd": &"collapse",
		"shake": 1.3, "hold": 0.7, "deliver": {"fuse": 1.7, "bounce": 0.2}, "w": {"reserve": 3, "interval": 1.1}}],
]

const LAUNCHERS: Array = [
	[&"la_pump", "PUMP LAUNCHER", 4.5, 1.0, 105.0, 90.0, &"fire", {"tag": "PMP", "tier": 2, "note": "SIX LOBBED GRENADES  EACH ONE BLOWS ON IMPACT", "deliver": {"speed": 34.0, "grav": 16.0, "life": 3.0, "impact": true, "range": 70.0},
		"w": {"mag": 6, "reserve": 30, "interval": 0.75, "reload": 2.8, "range": 70.0, "snd": &"shot_gravity", "pitch": 1.25}}],
	[&"la_revolver", "REVOLVER LAUNCHER", 4.0, 0.8, 90.0, 80.0, &"fire", {"tag": "RVL", "tier": 3, "note": "SIX FAST GRENADES IN A DRUM", "deliver": {"speed": 38.0, "grav": 14.0, "life": 3.0, "impact": true, "range": 70.0},
		"w": {"mag": 6, "reserve": 36, "interval": 0.42, "reload": 3.0, "range": 70.0, "snd": &"shot_cmissile", "pitch": 1.4}}],
	[&"la_rotary", "ROTARY LAUNCHER", 3.0, 0.5, 55.0, 50.0, &"plasma", {"tag": "ROT", "tier": 4, "note": "EIGHTEEN SMALL BLASTS AT FIVE A SECOND", "shake": 0.7, "deliver": {"speed": 40.0, "grav": 12.0, "life": 2.6, "impact": true, "range": 65.0},
		"w": {"mag": 18, "reserve": 108, "interval": 0.2, "reload": 3.4, "range": 65.0, "snd": &"shot_epod", "pitch": 1.15}}],
	[&"la_rocket", "UNGUIDED ROCKET", 6.5, 1.5, 200.0, 220.0, &"fire", {"tag": "RKT", "tier": 3, "note": "FAST AND STRAIGHT  FLATTENS A CAR", "knock": 10.0, "lift": 9.6, "deliver": {"speed": 58.0, "grav": 3.0, "life": 4.0, "impact": true},
		"w": {"mag": 1, "reserve": 8, "interval": 1.0, "reload": 2.4, "snd": &"shot_gravity", "pitch": 0.8}}],
	[&"la_laser", "LASER-GUIDED ROCKET", 6.0, 1.2, 190.0, 230.0, &"fire", {"tag": "LSR", "tier": 4, "note": "FOLLOWS THE DOT OF YOUR CROSSHAIR", "deliver": {"speed": 40.0, "grav": 1.0, "life": 5.0, "guide": &"laser", "turn": 3.4, "impact": true},
		"w": {"mag": 1, "reserve": 6, "interval": 1.2, "reload": 2.6, "snd": &"shot_seeker", "pitch": 1.0}}],
	[&"la_wire", "WIRE-GUIDED ROCKET", 5.5, 1.2, 180.0, 240.0, &"fire", {"tag": "WIR", "tier": 4, "note": "SLOW AND STEERED BY YOU ALL THE WAY", "deliver": {"speed": 30.0, "grav": 0.5, "life": 7.0, "guide": &"wire", "turn": 4.4, "impact": true},
		"w": {"mag": 1, "reserve": 5, "interval": 1.3, "reload": 2.8, "snd": &"shot_seeker", "pitch": 0.85}}],
	[&"la_swarm", "SWARM LAUNCHER", 3.4, 0.6, 80.0, 85.0, &"fire", {"tag": "SWM", "tier": 5, "note": "SIX MINI MISSILES  EACH SEEKS A TARGET", "shake": 0.8, "deliver": {"speed": 36.0, "grav": 2.0, "life": 3.6, "guide": &"lock", "turn": 3.0, "impact": true, "salvo": 6},
		"w": {"mag": 1, "reserve": 5, "interval": 1.6, "reload": 3.2, "snd": &"shot_epod", "pitch": 0.9}}],
	[&"la_antiair", "ANTI-AIR ROCKET", 7.5, 2.0, 90.0, 320.0, &"electric", {"tag": "AAR", "tier": 4, "note": "HOMES ON AIRCRAFT  BURSTS NEAR THE TARGET", "debris": &"sparks", "tags": ["air"],
		"deliver": {"speed": 62.0, "grav": 0.0, "life": 5.0, "guide": &"air", "turn": 3.6, "proximity": 5.0, "impact": true}, "w": {"mag": 1, "reserve": 5, "interval": 1.3, "reload": 2.8, "snd": &"shot_seeker", "pitch": 1.3}}],
	[&"la_bunker", "BUNKER BUSTER", 8.0, 3.0, 160.0, 200.0, &"fire", {"tag": "BNK", "tier": 5, "note": "GOES THROUGH A WALL, THEN BLOWS INSIDE", "level": 3, "knock": 14.0, "lift": 14.0, "shake": 1.4, "crater": 1.4,
		"deliver": {"speed": 46.0, "grav": 2.0, "life": 4.0, "impact": true, "pen": 1.8, "delay": 0.45}, "w": {"mag": 1, "reserve": 4, "interval": 1.4, "reload": 3.0, "snd": &"shot_gravity", "pitch": 0.7}}],
	[&"la_cluster", "CLUSTER ROCKET", 2.8, 0.5, 60.0, 60.0, &"fire", {"tag": "CLU", "tier": 4, "note": "OPENS ABOVE THE TARGET  NINE BOMBLETS", "cluster": [9, 8.0, 0.1], "wave": &"flat",
		"deliver": {"speed": 48.0, "grav": 4.0, "life": 3.0, "airburst": 3.5, "impact": true}, "w": {"mag": 1, "reserve": 5, "interval": 1.2, "reload": 2.8, "snd": &"shot_cmissile", "pitch": 0.85}}],
	[&"la_recoilless", "RECOILLESS GUN", 5.0, 1.2, 170.0, 260.0, &"fire", {"tag": "REC", "tier": 4, "note": "A FLAT FAST SHELL  MADE FOR TANKS", "knock": 9.0, "deliver": {"speed": 76.0, "grav": 1.5, "life": 3.0, "impact": true, "kick": 6.0},
		"w": {"mag": 1, "reserve": 6, "interval": 1.5, "reload": 3.0, "snd": &"shot_railgun", "pitch": 0.75}}],
	[&"la_mortar", "MORTAR TUBE", 7.5, 1.5, 150.0, 130.0, &"fire", {"tag": "MTR", "tier": 3, "note": "A HIGH ARC OVER WALLS  LANDS ON THE CROSSHAIR", "shake": 1.2,
		"deliver": {"speed": 44.0, "grav": 30.0, "life": 5.0, "impact": true, "lob": true, "range": 110.0}, "w": {"mag": 1, "reserve": 8, "interval": 1.4, "reload": 2.2, "range": 110.0, "snd": &"shot_sing", "pitch": 1.5}}],
	[&"la_plasma", "HEAVY PLASMA LAUNCHER", 9.0, 3.0, 190.0, 170.0, &"plasma", {"tag": "PLA", "tier": 5, "note": "A SLOW BRIGHT BALL THAT MELTS WHAT IT HITS", "knock": 10.0, "status": {"k": &"burn", "t": 3.0, "p": 20.0},
		"fire": [4.0, 4.0, 18.0], "shake": 1.3, "deliver": {"speed": 30.0, "grav": 1.0, "life": 4.5, "impact": true}, "w": {"mag": 1, "reserve": 5, "interval": 1.6, "reload": 3.0, "snd": &"shot_eplasma", "pitch": 0.6}}],
	[&"la_thermo", "THERMOBARIC LAUNCHER", 10.0, 6.0, 140.0, 110.0, &"fire", {"tag": "THM", "tier": 6, "note": "A PRESSURE DOME  KILLS EVERYTHING INSIDE IT", "curve": &"flat", "edge": 0.3, "knock": 12.0, "lift": 10.5, "level": 2,
		"fire": [6.0, 3.0, 16.0], "wave": &"dome", "fx": &"dome", "shake": 1.5, "deliver": {"speed": 36.0, "grav": 6.0, "life": 4.0, "impact": true}, "w": {"mag": 1, "reserve": 4, "interval": 1.8, "reload": 3.4, "snd": &"shot_napalm", "pitch": 0.7}}],
]

const MINES: Array = [
	[&"mn_prox", "PROXIMITY MINE", 5.0, 1.0, 120.0, 140.0, &"fire", {"tag": "PRX", "tier": 2, "lift": 11.4, "note": "ARMS IN A SECOND  GOES WHEN ANYONE STEPS NEAR", "deliver": {"arm": 0.8, "trigger": 2.6}}],
	[&"mn_trip", "TRIPWIRE MINE", 4.5, 1.0, 110.0, 90.0, &"fire", {"tag": "TRP", "tier": 2, "note": "A LASER LINE ACROSS A DOORWAY", "deliver": {"arm": 1.0, "trigger": 0.0, "wire": 6.0, "reach": 10.0}}],
	[&"mn_directional", "DIRECTIONAL MINE", 9.0, 1.5, 160.0, 100.0, &"fire", {"tag": "DIR", "tier": 3, "note": "BLASTS ONLY IN A CONE IN FRONT OF IT", "cone": 0.9, "knock": 10.0, "debris": &"metal",
		"deliver": {"arm": 1.0, "trigger": 7.0, "cone": 0.9, "reach": 10.0}}],
	[&"mn_gravity", "GRAVITY MINE", 7.0, 0.0, 90.0, 80.0, &"quantum", {"tag": "GRV", "tier": 4, "note": "DRAGS THEM IN, THEN COLLAPSES", "knock": -8.0, "lift": 1.8, "status": {"k": &"pull", "t": 1.6, "p": 8.0}, "hold": 1.6, "fx": &"well",
		"wave": &"implode", "snd": &"collapse", "deliver": {"arm": 1.0, "trigger": 3.0}}],
	[&"mn_c4", "STICKY CHARGE", 7.0, 1.5, 210.0, 260.0, &"fire", {"tag": "C4S", "tier": 3, "note": "STICKS TO A CAR OR A WALL  BLOWS ON A 5 SECOND TIMER", "knock": 11.0, "lift": 10.5, "shake": 1.3,
		"deliver": {"arm": 0.0, "trigger": 0.0, "timer": 5.0, "remote": true, "stick": true, "reach": 18.0}, "w": {"reserve": 3, "interval": 0.8}}],
	[&"mn_remote", "REMOTE CHARGE", 7.5, 1.5, 230.0, 280.0, &"fire", {"tag": "RMT", "tier": 3, "note": "BLOWS WHEN YOU PRESS DETONATE  UP TO FOUR", "knock": 12.0, "lift": 11.4, "shake": 1.4,
		"deliver": {"arm": 0.0, "trigger": 0.0, "remote": true, "stick": true, "reach": 18.0}, "w": {"reserve": 4}}],
	[&"mn_satchel", "SATCHEL CHARGE", 8.0, 2.0, 190.0, 170.0, &"fire", {"tag": "SAT", "tier": 4, "note": "THROWN, THEN DETONATED  BREACHES A WALL", "level": 3, "knock": 13.0, "lift": 12.2, "shake": 1.4, "crater": 1.3,
		"deliver": {"mode": &"throw", "speed": 18.0, "grav": 22.0, "fuse": 0.0, "bounce": 0.0, "remote": true, "range": 26.0, "arm": 0.0, "stick": false}, "w": {"reserve": 3}}],
	[&"mn_shaped", "SHAPED CHARGE", 3.0, 1.5, 120.0, 400.0, &"fire", {"tag": "SHP", "tier": 5, "note": "A SMALL BLAST THAT PUNCHES THROUGH ARMOUR AND DOORS", "level": 3, "knock": 8.0, "lift": 5.2, "curve": &"flat", "edge": 0.5,
		"debris": &"metal", "deliver": {"arm": 0.0, "trigger": 0.0, "remote": true, "stick": true, "reach": 6.0}, "w": {"reserve": 3}}],
	[&"mn_bounce", "BOUNCE MINE", 5.5, 1.0, 130.0, 100.0, &"fire", {"tag": "BNC", "tier": 3, "note": "JUMPS UP, THEN BLOWS OVER LOW COVER", "lift": 12.2, "deliver": {"arm": 0.9, "trigger": 2.4, "hop": 1.7}}],
	[&"mn_emp", "EMP MINE", 8.0, 8.0, 10.0, 40.0, &"electric", {"tag": "EMM", "tier": 2, "note": "SHUTS DOWN ENGINES AND MACHINES THAT PASS", "curve": &"flat", "knock": 0.0, "lift": 0.0, "status": {"k": &"emp", "t": 4.0, "p": 1.0},
		"fx": &"emp", "wave": &"pulse", "snd": &"explosion_small", "snd_pitch": 1.2, "crater": 0.0, "scorch": 0.1, "debris": &"sparks", "prop": 0, "level": 0, "civ": 0.0, "cover": false, "deliver": {"arm": 1.0, "trigger": 3.2}}],
]

const STRIKES: Array = [
	[&"st_artillery", "ARTILLERY BARRAGE", 6.0, 1.2, 160.0, 140.0, &"fire", {"tag": "ART", "tier": 4, "note": "THREE SHELLS WHISTLE IN ON YOUR MARKER", "deliver": {"delay": 3.5, "count": 3, "spread": 9.0, "gap": 0.6, "pattern": &"scatter"}}],
	[&"st_smokescreen", "SMOKE SCREEN", 7.0, 7.0, 0.0, 0.0, &"fire", {"tag": "SMK", "tier": 2, "note": "FIVE SMOKE SHELLS  A WALL OF SMOKE FOR 18 SECONDS", "curve": &"flat", "knock": 0.0, "lift": 0.0, "status": {"k": &"smoke", "t": 18.0, "p": 1.0},
		"hold": 18.0, "fx": &"smoke", "wave": &"none", "snd": &"explosion_small", "snd_pitch": 0.8, "crater": 0.0, "scorch": 0.0, "debris": &"none", "prop": 0, "level": 0, "civ": 0.0, "hero": 0.0, "animal": 0.0, "cover": false,
		"deliver": {"delay": 2.0, "count": 5, "spread": 11.0, "gap": 0.25, "pattern": &"ring"}}],
	[&"st_air_s", "AIRSTRIKE SMALL", 8.0, 2.5, 230.0, 260.0, &"fire", {"tag": "AS1", "tier": 4, "note": "ONE BOMB FROM A FAST JET", "level": 2, "deliver": {"delay": 4.0, "count": 1, "pattern": &"single", "jet": true}}],
	[&"st_air_m", "AIRSTRIKE MEDIUM", 10.0, 3.0, 260.0, 300.0, &"fire", {"tag": "AS2", "tier": 5, "note": "TWO BOMBS, TWELVE METRES APART", "level": 3, "shake": 1.4, "deliver": {"delay": 5.0, "count": 2, "spread": 12.0, "gap": 0.45, "pattern": &"line", "length": 12.0, "jet": true}}],
	[&"st_air_l", "AIRSTRIKE LARGE", 13.0, 4.0, 300.0, 380.0, &"fire", {"tag": "AS3", "tier": 6, "note": "THREE HEAVY BOMBS  LEVELS A STREET CORNER", "level": 3, "shake": 1.6, "crater": 1.6,
		"deliver": {"delay": 6.0, "count": 3, "spread": 18.0, "gap": 0.5, "pattern": &"line", "length": 36.0, "jet": true}}],
	[&"st_carpet", "CARPET BOMB RUN", 6.5, 1.5, 170.0, 150.0, &"fire", {"tag": "CPT", "tier": 6, "note": "NINE BOMBS IN A LINE, SIXTY METRES LONG", "level": 3, "shake": 1.5, "deliver": {"delay": 5.5, "count": 9, "gap": 0.25, "pattern": &"carpet", "length": 60.0, "jet": true}}],
	[&"st_fireline", "FIRE LINE", 4.5, 1.0, 60.0, 70.0, &"fire", {"tag": "FLN", "tier": 5, "note": "A 40 METRE WALL OF FLAMES THAT BURNS FOR 8 SECONDS", "fire": [4.0, 8.0, 20.0], "status": {"k": &"burn", "t": 4.0, "p": 16.0},
		"fx": &"ember", "crater": 0.5, "scorch": 1.5, "deliver": {"delay": 3.0, "count": 8, "gap": 0.12, "pattern": &"line", "length": 40.0}}],
	[&"st_orbital", "ORBITAL BEAM", 14.0, 5.0, 400.0, 500.0, &"plasma", {"tag": "ORB", "tier": 6, "note": "A COLUMN OF LIGHT FROM ABOVE  THREE PULSES", "level": 3, "shake": 1.8, "wave": &"column", "fx": &"beam", "crater": 1.5,
		"deliver": {"delay": 3.5, "count": 3, "gap": 0.7, "pattern": &"beam"}}],
	[&"st_emp", "EMP PULSE", 30.0, 30.0, 5.0, 80.0, &"electric", {"tag": "EMP", "tier": 4, "note": "A WAVE ACROSS THE DISTRICT  MACHINES AND ENGINES STOP", "curve": &"flat", "knock": 0.0, "lift": 0.0, "status": {"k": &"emp", "t": 5.0, "p": 1.0},
		"fx": &"emp", "wave": &"pulse", "snd": &"explosion_small", "snd_pitch": 0.7, "crater": 0.0, "scorch": 0.0, "debris": &"sparks", "prop": 0, "level": 0, "civ": 0.0, "cover": false, "shake": 0.8, "deliver": {"delay": 2.5, "count": 1}}],
	[&"st_supply", "SUPPLY DROP", 3.5, 1.0, 80.0, 60.0, &"fire", {"tag": "SUP", "tier": 1, "note": "A CRATE ON A PARACHUTE  AMMO AND HEALTH ON LANDING", "knock": 4.0, "lift": 5.2, "fx": &"dust", "wave": &"flat", "snd": &"explosion_small",
		"snd_pitch": 0.7, "crater": 0.3, "scorch": 0.1, "debris": &"none", "level": 0, "friendly": false, "deliver": {"delay": 4.5, "count": 1, "supply": true}}],
]

const ORDNANCE: Array = [
	[&"ord_tank_he", "TANK SHELL HE", 7.0, 1.5, 190.0, 230.0, &"fire", {"tag": "THE", "tier": 3, "note": "THE TANK GUN'S ROUND  A WIDE BLAST", "deliver": {"speed": 120.0, "grav": 4.0}}],
	[&"ord_tank_ap", "TANK SHELL AP", 2.6, 1.2, 100.0, 520.0, &"fire", {"tag": "TAP", "tier": 3, "note": "A SMALL BLAST THAT CRACKS ARMOUR", "curve": &"flat", "edge": 0.5, "level": 2, "debris": &"metal", "deliver": {"speed": 150.0, "grav": 2.0}}],
	[&"ord_tank_cluster", "TANK SHELL CLUSTER", 3.4, 0.6, 70.0, 70.0, &"fire", {"tag": "TCL", "tier": 4, "note": "OPENS ABOVE THE TARGET  SEVEN BOMBLETS", "cluster": [7, 9.0, 0.1], "deliver": {"speed": 110.0, "grav": 6.0, "airburst": 4.0}}],
	[&"ord_bomb_dumb", "AIRCRAFT BOMB", 12.0, 3.5, 280.0, 340.0, &"fire", {"tag": "ABD", "tier": 4, "note": "DROPPED STRAIGHT DOWN FROM AN AIRCRAFT", "level": 3, "shake": 1.6, "crater": 1.5, "deliver": {"grav": 22.0}}],
	[&"ord_bomb_guided", "GUIDED BOMB", 10.0, 3.0, 260.0, 320.0, &"fire", {"tag": "ABG", "tier": 5, "note": "STEERS ITSELF TO THE LASER MARK", "level": 3, "shake": 1.5, "deliver": {"grav": 16.0, "guide": &"laser", "turn": 1.6}}],
	[&"ord_bomb_cluster", "CLUSTER BOMB", 3.5, 0.6, 90.0, 80.0, &"fire", {"tag": "ABC", "tier": 5, "note": "FOURTEEN BOMBLETS OVER A WIDE FIELD", "cluster": [14, 22.0, 0.06], "wave": &"flat", "deliver": {"grav": 20.0, "airburst": 40.0}}],
	[&"ord_bomb_runway", "RUNWAY BUSTER", 11.0, 5.0, 200.0, 300.0, &"fire", {"tag": "ABR", "tier": 6, "note": "A DEEP CRATER IN ANY AIRSTRIP", "curve": &"flat", "edge": 0.4, "level": 3, "shake": 1.7, "crater": 2.6, "deliver": {"grav": 24.0}}],
	[&"ord_naval_mine", "NAVAL MINE", 9.0, 2.5, 150.0, 420.0, &"fire", {"tag": "NVM", "tier": 4, "note": "FLOATS AT THE SURFACE  GOES UNDER A HULL", "wave": &"column", "fx": &"water", "debris": &"none", "crater": 0.0, "scorch": 0.0, "deliver": {"trigger": 4.0, "arm": 1.5}}],
	[&"ord_depth_charge", "DEPTH CHARGE", 12.0, 3.0, 100.0, 400.0, &"fire", {"tag": "DPC", "tier": 5, "note": "SINKS, THEN BLOWS UNDER THE SURFACE  HURTS SEA LIFE", "animal": 2.2, "wave": &"column", "fx": &"water", "debris": &"none",
		"crater": 0.0, "scorch": 0.0, "shake": 1.4, "deliver": {"fuse": 2.2, "grav": 6.0}}],
]

const ULTIMATES: Array = [
	[&"ult_mega", "MEGA BLAST", 16.0, 5.0, 500.0, 600.0, &"quantum", {"tag": "MEG", "tier": 6, "note": "A SHOCKWAVE FROM THE HERO  BLASTS THE WHOLE STREET", "unlock": 1, "wave": &"ring", "fx": &"mega", "shake": 1.8, "knock": 18.0, "lift": 17.5,
		"deliver": {"delay": 0.0, "cost": 100}}],
	[&"ult_collapse", "COLLAPSE FIELD", 14.0, 0.0, 300.0, 260.0, &"quantum", {"tag": "CLF", "tier": 6, "note": "A FIELD THAT DRAGS EVERYONE IN FOR 4 SECONDS, THEN COLLAPSES", "unlock": 2, "knock": -12.0, "lift": 5.2, "curve": &"quad", "edge": 0.3,
		"status": {"k": &"pull", "t": 4.0, "p": 11.0}, "hold": 4.0, "fx": &"well", "wave": &"implode", "snd": &"collapse", "deliver": {"delay": 0.0, "cost": 100}}],
	[&"ult_storm", "CHAIN LIGHTNING STORM", 18.0, 18.0, 40.0, 60.0, &"electric", {"tag": "STM", "tier": 6, "note": "TWELVE BOLTS IN THREE SECONDS  EACH ONE FINDS A TARGET", "unlock": 3, "curve": &"flat", "knock": 4.0, "lift": 5.2,
		"fx": &"storm", "wave": &"pulse", "status": {"k": &"shock", "t": 2.0, "p": 0.5}, "debris": &"sparks", "hold": 3.0, "deliver": {"delay": 0.0, "cost": 100, "strikes": 12, "strike_radius": 3.0}}],
	[&"ult_meteor", "METEOR CALL", 12.0, 4.0, 450.0, 520.0, &"fire", {"tag": "MET", "tier": 6, "note": "A METEOR FROM THE SKY  LEAVES A BURNING CRATER", "unlock": 4, "fire": [8.0, 8.0, 24.0], "fx": &"meteor", "wave": &"dome", "crater": 2.0, "shake": 1.8,
		"deliver": {"delay": 2.0, "cost": 100, "range": 60.0}}],
	[&"ult_blackhole", "BLACK-HOLE DROP", 20.0, 0.0, 400.0, 360.0, &"quantum", {"tag": "BLH", "tier": 6, "note": "PULLS CARS AND PEOPLE IN FOR 5 SECONDS, THEN BURSTS", "unlock": 5, "knock": -14.0, "lift": 7.0, "curve": &"quad", "edge": 0.25,
		"status": {"k": &"pull", "t": 5.0, "p": 13.0}, "hold": 5.0, "fx": &"blackhole", "wave": &"implode", "snd": &"collapse", "shake": 1.8, "deliver": {"delay": 1.0, "cost": 100, "range": 50.0}}],
	[&"ult_freeze", "TIME-FREEZE BUBBLE", 16.0, 16.0, 0.0, 0.0, &"plasma", {"tag": "TFB", "tier": 6, "note": "EVERYONE INSIDE STANDS STILL FOR 7 SECONDS  YOU DO NOT", "unlock": 6, "curve": &"flat", "knock": 0.0, "lift": 0.0,
		"status": {"k": &"freeze", "t": 7.0, "p": 1.0}, "hold": 7.0, "fx": &"bubble", "wave": &"dome", "snd": &"shield_up", "crater": 0.0, "scorch": 0.0, "debris": &"none", "prop": 0, "level": 0, "civ": 0.0, "hero": 0.0, "animal": 0.0,
		"cover": false, "deliver": {"delay": 0.0, "cost": 100}}],
]

const WORLD: Array = [
	[&"wb_gas_tank", "GAS TANK", 12.0, 4.0, 260.0, 300.0, &"fire", {"tag": "GAS", "tier": 3, "note": "A STORAGE TANK  SETS OFF EVERYTHING AROUND IT", "fire": [8.0, 10.0, 22.0], "knock": 14.0, "lift": 14.0, "shake": 1.5, "level": 3, "crater": 1.6,
		"status": {"k": &"burn", "t": 4.0, "p": 16.0}, "deliver": {"mode": &"world", "hp": 6.0, "pos_kind": &"tank"}}],
	[&"wb_barrel", "BARREL", 5.5, 1.0, 120.0, 100.0, &"fire", {"tag": "BRL", "tier": 1, "note": "A RED BARREL  GOES UP WHEN SHOT", "fire": [3.0, 5.0, 16.0], "knock": 8.0, "lift": 8.8, "level": 1, "deliver": {"mode": &"world", "hp": 2.0, "pos_kind": &"barrel"}}],
	[&"wb_car", "CAR BLAST", 9.0, 2.5, 80.0, 70.0, &"fire", {"tag": "CAR", "tier": 2, "note": "A WRECKED CAR GOES UP", "curve": &"linear", "edge": 0.4, "knock": 9.0, "lift": 10.5, "level": 1, "hero": 0.44, "civ": 2.5,
		"deliver": {"mode": &"world", "pos_kind": &"car"}}],
	[&"wb_fuel_truck", "FUEL TRUCK", 16.0, 5.0, 340.0, 400.0, &"fire", {"tag": "FTK", "tier": 4, "note": "A TANKER  THE BIGGEST BANG IN THE CITY", "fire": [10.0, 14.0, 26.0], "knock": 18.0, "lift": 17.5, "shake": 1.7, "level": 3, "crater": 2.0,
		"status": {"k": &"burn", "t": 5.0, "p": 18.0}, "deliver": {"mode": &"world", "hp": 10.0, "pos_kind": &"truck"}}],
]


## Every row of the arsenal in catalogue order, each as [category, row].
static func all() -> Array:
	var out: Array = []
	for pair: Array in [[&"grenade", GRENADES], [&"launcher", LAUNCHERS], [&"mine", MINES], [&"strike", STRIKES], [&"ordnance", ORDNANCE], [&"ultimate", ULTIMATES], [&"world", WORLD]]:
		for row: Array in pair[1]:
			out.append([pair[0], row])
	return out
