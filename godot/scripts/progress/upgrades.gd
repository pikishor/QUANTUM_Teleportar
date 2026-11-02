class_name Upgrades
extends RefCounted
## The shop's maths and the live upgrade state. Pure data plus static helpers, so the player, the weapon, the quantum module and the tests all read the same numbers.
##
## Seven upgrades with MAX_LEVEL levels each. `levels` is the live state (set by Progress when a save loads, an upgrade is bought or a contract grants one);
## nothing here touches the scene tree. Other modules read the multipliers (damage_mult, reload_mult, ...), which are neutral (1.0 / 0) at level 0.
## Prices: cost(id, level) = base * (1 + 0.8 * level), rounded to 5; price() applies the reputation discount (Progress.rep_discount) and rounds to 5.

const IDS: Array[StringName] = [&"damage", &"mag", &"reload", &"blink", &"regen", &"armour", &"decoy"]
const MAX_LEVEL := 5

const DATA := {
	&"damage": {"name": "WEAPON DAMAGE", "base": 240, "per": 0.12},      ## +12 % rifle damage per level
	&"mag": {"name": "MAGAZINE", "base": 160, "per": 6.0},               ## +6 rounds per level (30 -> 60)
	&"reload": {"name": "RELOAD SPEED", "base": 160, "per": 0.12},       ## -12 % reload time per level
	&"blink": {"name": "BLINK RANGE", "base": 200, "per": 8.0},          ## +8 m per level (48 -> 88 m)
	&"regen": {"name": "COHERENCE REGEN", "base": 200, "per": 0.20},     ## +20 % coherence regeneration per level
	&"armour": {"name": "ARMOUR", "base": 260, "per": 0.08},             ## -8 % damage taken per level (-40 % at the top)
	&"decoy": {"name": "DECOY TIME", "base": 180, "per": 0.5},          ## +0.5 s SUPERPOSITION clone lifetime per level
}

const MAG_BASE := 30
const BLINK_BASE := 48.0
const RELOAD_FLOOR := 0.4

## id -> level 0..MAX_LEVEL. Static on purpose: PlayerWeapon, Player and Quantum read it without knowing about the Progress node.
static var levels := {}


static func level(id: StringName) -> int:
	return clampi(int(levels.get(id, 0)), 0, MAX_LEVEL)


static func reset() -> void:
	levels = {}


## Replace the live state from a Dictionary (unknown ids dropped, levels clamped). Returns the cleaned copy.
static func set_levels(d: Dictionary) -> Dictionary:
	var clean := {}
	for id: StringName in IDS:
		var v := clampi(int(d.get(id, d.get(String(id), 0))), 0, MAX_LEVEL)
		if v > 0:
			clean[id] = v
	levels = clean
	return clean


static func total_levels() -> int:
	var n := 0
	for id: StringName in IDS:
		n += level(id)
	return n


static func damage_mult() -> float:
	return 1.0 + float(DATA[&"damage"]["per"]) * level(&"damage")


static func mag_size() -> int:
	return MAG_BASE + int(float(DATA[&"mag"]["per"]) * level(&"mag"))


static func reload_mult() -> float:
	return maxf(RELOAD_FLOOR, 1.0 - float(DATA[&"reload"]["per"]) * level(&"reload"))


## Extra SUPERPOSITION decoy lifetime in seconds (shop row &"decoy"): neutral 0 at level 0.
static func decoy_bonus() -> float:
	return float(DATA[&"decoy"]["per"]) * level(&"decoy")


## Extra blink range in metres.
static func blink_bonus() -> float:
	return float(DATA[&"blink"]["per"]) * level(&"blink")


static func regen_mult() -> float:
	return 1.0 + float(DATA[&"regen"]["per"]) * level(&"regen")


## Factor on every hit the player takes (1.0 at level 0, 0.6 at level 5).
static func damage_taken() -> float:
	return 1.0 - float(DATA[&"armour"]["per"]) * level(&"armour")


static func title(id: StringName) -> String:
	return str(DATA[id]["name"])


## Credits for the NEXT level (from `lvl` to lvl + 1) before any discount. -1 at the top level.
static func cost(id: StringName, lvl: int) -> int:
	if lvl >= MAX_LEVEL or lvl < 0:
		return -1
	return int(roundf(float(DATA[id]["base"]) * (1.0 + 0.8 * lvl) / 5.0)) * 5


## What the shop asks for the next level: cost times (1 - discount), rounded to 5, never below 5. `discount` is Progress.rep_discount (-0.1 .. 0.2).
static func price(id: StringName, lvl: int, discount := 0.0) -> int:
	var c := cost(id, lvl)
	if c < 0:
		return -1
	return maxi(5, int(roundf(float(c) * (1.0 - discount) / 5.0)) * 5)


## "30 -> 36 ROUNDS" style line for the shop row: what the next level changes (the last level shows the current value only).
static func effect_text(id: StringName, lvl: int) -> String:
	var nxt := mini(lvl + 1, MAX_LEVEL)
	var a := _value_text(id, lvl)
	var b := _value_text(id, nxt)
	return a if nxt == lvl else "%s  >  %s" % [a, b]


static func _value_text(id: StringName, lvl: int) -> String:
	var per := float(DATA[id]["per"])
	match id:
		&"damage": return "%d%% DAMAGE" % roundi(100.0 + per * 100.0 * lvl)
		&"mag": return "%d ROUNDS" % (MAG_BASE + int(per * lvl))
		&"reload": return "%d%% RELOAD TIME" % roundi(maxf(RELOAD_FLOOR, 1.0 - per * lvl) * 100.0)
		&"blink": return "%d M BLINK" % roundi(BLINK_BASE + per * lvl)
		&"regen": return "%d%% REGEN" % roundi(100.0 + per * 100.0 * lvl)
		&"armour": return "%d%% DAMAGE TAKEN" % roundi((1.0 - per * lvl) * 100.0)
		&"decoy": return "+%.1f S DECOY" % (per * lvl)
	return ""
