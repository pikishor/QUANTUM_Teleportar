class_name AttachmentPartsV3
extends RefCounted
## The attachment parts of wave 113 (the nine of the first rosters stay in Attachments.PARTS0): twelve new parts, two new slots and the rule which weapon takes which part. Pure data, nothing here reads
## Attachments or WeaponDefs while it loads (Attachments builds its tables from this file).
## Slots (Attachments.SLOTS, in the order of the loadout): optic, barrel, grip, core, laser. The ids `barrel` and `core` are older than the roster: the loadout calls them MUZZLE and MAGAZINE (SLOT_LABEL).
## A part is {name, slot, price (base credits, Economy scales them), mods, fits, fx}. `mods` multiply the numbers of the weapon (the keys of Attachments.NUMERIC), `zoom_set` replaces the zoom, `vol` makes it
## quieter, `set` writes a key (a bool or number the weapon did not have), `add` raises a key to at least that value (a laser that marks the target). `fits` says who may wear it: gun (every gun), long (a gun
## with two hands on it: not a pistol), shotgun (pellets), mag (a magazine of four or more rounds).

const SLOT_LABEL := {&"optic": "OPTIC", &"barrel": "MUZZLE", &"grip": "GRIP", &"core": "MAGAZINE", &"laser": "LASER"}

const PARTS := {
	&"scope4": {"name": "LONG SCOPE", "slot": &"optic", "price": 520, "fits": &"long", "mods": {"spread_ads": 0.4, "zoom_set": 20.0, "spread_hip": 1.12, "interval": 1.03}},
	&"snap": {"name": "SNAP SIGHT", "slot": &"optic", "price": 300, "fits": &"gun", "mods": {"spread_hip": 0.82, "spread_move": 0.85}},
	&"choke": {"name": "CHOKE", "slot": &"barrel", "price": 380, "fits": &"shotgun", "mods": {"spread_hip": 0.6, "spread_ads": 0.6, "falloff_from": 1.25}},
	&"heavybore": {"name": "HEAVY BORE", "slot": &"barrel", "price": 420, "fits": &"gun", "mods": {"damage": 1.12, "kick": 1.2, "kick_end": 1.2, "range": 0.9}},
	&"foregrip": {"name": "ANGLED GRIP", "slot": &"grip", "price": 280, "fits": &"long", "mods": {"kick": 0.8, "kick_end": 0.8, "kick_yaw": 0.75, "spread_hip": 0.94}},
	&"steadygrip": {"name": "STEADY GRIP", "slot": &"grip", "price": 300, "fits": &"long", "mods": {"bloom": 0.65, "bloom_max": 0.8, "spread_move": 0.8}},
	&"quickgrip": {"name": "QUICK GRIP", "slot": &"grip", "price": 260, "fits": &"gun", "mods": {"reload": 0.82, "spread_hip": 1.06}},
	&"fastmag": {"name": "FAST MAG", "slot": &"core", "price": 300, "fits": &"mag", "mods": {"reload": 0.7}},
	&"armourmag": {"name": "PIERCING MAG", "slot": &"core", "price": 520, "fits": &"gun", "mods": {"damage": 1.06, "crit": 1.1}, "set": {"pierce_shield": true}},
	&"laser": {"name": "LASER SIGHT", "slot": &"laser", "price": 260, "fits": &"gun", "mods": {"spread_hip": 0.78, "spread_move": 0.9}},
	&"precision": {"name": "PRECISION LASER", "slot": &"laser", "price": 420, "fits": &"gun", "mods": {"spread_hip": 0.65, "spread_ads": 0.85, "crit": 1.08}},
	&"marker": {"name": "MARKER LASER", "slot": &"laser", "price": 480, "fits": &"gun", "mods": {}, "add": {"mark": 0.12, "mark_time": 4.0}},
}
const IDS: Array[StringName] = [&"scope4", &"snap", &"choke", &"heavybore", &"foregrip", &"steadygrip", &"quickgrip", &"fastmag", &"armourmag", &"laser", &"precision", &"marker"]

## One short line a card shows under the name of the part: what it does in plain words (all the parts, the first nine included).
const FX := {
	&"reddot": "Steadier aim", &"scope": "Zoom, steady aim", &"halo": "Hip aim, crits", &"suppressor": "Quiet, less kick", &"longbarrel": "Longer range", &"compensator": "Less recoil",
	&"overcharge": "More damage", &"rapid": "Faster fire", &"extended": "Bigger magazine",
	&"scope4": "Big zoom, wide hip", &"snap": "Quick aim on the move", &"choke": "Tight pellets", &"heavybore": "Hits hard, kicks hard",
	&"foregrip": "Much less recoil", &"steadygrip": "Holds the aim", &"quickgrip": "Fast reload",
	&"fastmag": "Much faster reload", &"armourmag": "Cracks shields", &"laser": "Hip aim, moving", &"precision": "Hip and zoom aim", &"marker": "Tags what it hits",
}
