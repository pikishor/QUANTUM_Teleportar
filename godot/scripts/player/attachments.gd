class_name Attachments
extends RefCounted
## Weapon attachments: three slots (optic, barrel, core) per weapon, each holding one owned part with stat modifiers. effective(id) is WeaponDefs.def(id) with the equipped
## parts applied (multipliers on the keys of MODS, "zoom_set" replaces the zoom); PlayerWeapon loads that. Static like WeaponDefs: the shop, the loadout screen and the save see it.

const SLOTS: Array[StringName] = [&"optic", &"barrel", &"core"]
const PARTS := {
	&"reddot": {"name": "RED DOT", "slot": &"optic", "price": 250, "mods": {"spread_ads": 0.6, "spread_hip": 0.9}},
	&"scope": {"name": "FOCUS SCOPE", "slot": &"optic", "price": 450, "mods": {"spread_ads": 0.5, "zoom_set": 36.0}},
	&"halo": {"name": "HALO SIGHT", "slot": &"optic", "price": 350, "mods": {"spread_hip": 0.75, "crit": 1.15}},
	&"suppressor": {"name": "DAMPER", "slot": &"barrel", "price": 300, "mods": {"vol": 0.0, "damage": 0.92, "kick": 0.8, "kick_end": 0.8}},
	&"longbarrel": {"name": "LONG BARREL", "slot": &"barrel", "price": 400, "mods": {"range": 1.35, "spread_hip": 0.85, "interval": 1.05}},
	&"compensator": {"name": "COMPENSATOR", "slot": &"barrel", "price": 350, "mods": {"kick": 0.6, "kick_end": 0.6, "kick_yaw": 0.6, "bloom": 0.7}},
	&"overcharge": {"name": "OVERCHARGE CORE", "slot": &"core", "price": 500, "mods": {"damage": 1.2, "mag": 0.9}},
	&"rapid": {"name": "RAPID CORE", "slot": &"core", "price": 450, "mods": {"interval": 0.82, "spread_hip": 1.1}},
	&"extended": {"name": "EXTENDED CORE", "slot": &"core", "price": 400, "mods": {"mag": 1.4, "reload": 1.1}},
}
const IDS: Array[StringName] = [&"reddot", &"scope", &"halo", &"suppressor", &"longbarrel", &"compensator", &"overcharge", &"rapid", &"extended"]
const NUMERIC := ["damage", "crit", "spread_hip", "spread_ads", "kick", "kick_end", "kick_yaw", "bloom", "range", "interval", "reload", "mag"]

## Parts the player owns.
static var owned: Array[StringName] = []
## weapon id -> {slot -> part id}
static var equipped: Dictionary = {}


static func reset() -> void:
	owned = []
	equipped = {}


static func slot_of(part: StringName) -> StringName:
	return PARTS[part]["slot"] if PARTS.has(part) else &""


static func parts_for(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in IDS:
		if PARTS[id]["slot"] == slot:
			out.append(id)
	return out


static func price(part: StringName, discount := 0.0) -> int:
	return maxi(5, int(roundf(float(PARTS[part]["price"]) * (1.0 - discount) / 5.0)) * 5)


static func is_owned(part: StringName) -> bool:
	return owned.has(part)


static func give(part: StringName) -> bool:
	if not PARTS.has(part) or owned.has(part):
		return false
	owned.append(part)
	return true


static func part_in(weapon: StringName, slot: StringName) -> StringName:
	var d: Dictionary = equipped.get(weapon, {})
	return d.get(slot, &"")


## Equip an owned part on a weapon (its slot is the part's), or pass &"" with a slot via unequip().
static func equip(weapon: StringName, part: StringName) -> bool:
	if not WeaponDefs.DEFS.has(weapon) or not owned.has(part):
		return false
	var d: Dictionary = equipped.get(weapon, {})
	d[PARTS[part]["slot"]] = part
	equipped[weapon] = d
	return true


static func unequip(weapon: StringName, slot: StringName) -> void:
	if equipped.has(weapon):
		(equipped[weapon] as Dictionary).erase(slot)


## Equip the part, or take it off when it already sits there (the loadout button).
static func toggle(weapon: StringName, part: StringName) -> bool:
	if part_in(weapon, slot_of(part)) == part:
		unequip(weapon, slot_of(part))
		return true
	return equip(weapon, part)


## Weapon definition with the equipped parts applied (a copy; the base DEFS never change).
static func effective(id: StringName) -> Dictionary:
	var base := WeaponDefs.def(id)
	var d: Dictionary = equipped.get(id, {})
	if d.is_empty():
		return base
	var out := base.duplicate()
	for slot: StringName in SLOTS:
		var part: StringName = d.get(slot, &"")
		if part == &"" or not PARTS.has(part):
			continue
		var mods: Dictionary = PARTS[part]["mods"]
		for k: String in mods:
			if k == "zoom_set":
				if String(out["kind"]) != "throw":
					out["zoom"] = minf(float(out["zoom"]), float(mods[k]))
			elif k == "vol":
				out["vol"] = float(out["vol"]) - 6.0
			elif NUMERIC.has(k):
				var v := float(out[k]) * float(mods[k])
				out[k] = maxi(1, int(roundf(v))) if k == "mag" else v
	return out


## Short text of what a part changes (the loadout screen).
static func effect_text(part: StringName) -> String:
	var bits: PackedStringArray = []
	var mods: Dictionary = PARTS[part]["mods"]
	for k: String in mods:
		if k == "zoom_set":
			bits.append("ZOOM")
		elif k == "vol":
			bits.append("QUIET")
		else:
			var pct := int(roundf((float(mods[k]) - 1.0) * 100.0))
			bits.append("%s %+d%%" % [k.replace("_", " ").to_upper(), pct])
	return "  ".join(bits)


## Save helpers: a ConfigFile section "attachments" (owned) and one key per weapon.
static func to_save() -> Dictionary:
	var eq := {}
	for w: StringName in equipped:
		var row := {}
		for s: StringName in equipped[w]:
			row[String(s)] = String(equipped[w][s])
		if not row.is_empty():
			eq[String(w)] = row
	var names := PackedStringArray()
	for p: StringName in owned:
		names.append(String(p))
	return {"owned": names, "equipped": eq}


static func from_save(d: Dictionary) -> void:
	reset()
	var ov: Variant = d.get("owned", [])
	for n: Variant in (Array(ov) if ov is Array or ov is PackedStringArray else []):
		if PARTS.has(StringName(str(n))):
			give(StringName(str(n)))
	var ev: Variant = d.get("equipped", {})
	var eq: Dictionary = ev if ev is Dictionary else {}
	for w: Variant in eq:
		if not (eq[w] is Dictionary):
			continue
		var row: Dictionary = eq[w]
		for s: Variant in row:
			var part := StringName(str(row[s]))
			if WeaponDefs.DEFS.has(StringName(str(w))) and PARTS.has(part) and slot_of(part) == StringName(str(s)):
				equip(StringName(str(w)), part)
