class_name Attachments
extends RefCounted
## Weapon attachments: five slots per weapon (optic, muzzle, grip, magazine, laser), each holding one owned part with stat modifiers. effective(id) is WeaponDefs.def(id) with the equipped
## parts applied (multipliers on the keys of NUMERIC, "zoom_set" replaces the zoom, "set" / "add" write a key); PlayerWeapon loads that. Static like WeaponDefs: the shop, the loadout screen and the save see it.
## The slot ids `barrel` and `core` are the MUZZLE and MAGAZINE of the loadout (AttachmentPartsV3.SLOT_LABEL). The parts of wave 113 (grip, laser, more of the others) come from
## scripts/player/attachment_parts_v3.gd; `fits(part, weapon)` says who may wear what (a pistol has no angled grip, a knife nothing at all) and `parts_for_weapon` is the list the loadout shows.

const SLOTS: Array[StringName] = [&"optic", &"barrel", &"grip", &"core", &"laser"]
const PARTS0 := {
	&"reddot": {"name": "RED DOT", "slot": &"optic", "price": 250, "mods": {"spread_ads": 0.6, "spread_hip": 0.9}},
	&"scope": {"name": "FOCUS SCOPE", "slot": &"optic", "price": 450, "mods": {"spread_ads": 0.5, "zoom_set": 36.0}},
	&"halo": {"name": "HOLO SIGHT", "slot": &"optic", "price": 350, "mods": {"spread_hip": 0.75, "crit": 1.15}},
	&"suppressor": {"name": "DAMPER", "slot": &"barrel", "price": 300, "mods": {"vol": 0.0, "damage": 0.92, "kick": 0.8, "kick_end": 0.8}},
	&"longbarrel": {"name": "LONG BARREL", "slot": &"barrel", "price": 400, "mods": {"range": 1.35, "spread_hip": 0.85, "interval": 1.05}},
	&"compensator": {"name": "COMPENSATOR", "slot": &"barrel", "price": 350, "mods": {"kick": 0.6, "kick_end": 0.6, "kick_yaw": 0.6, "bloom": 0.7}},
	&"overcharge": {"name": "OVERCHARGE CORE", "slot": &"core", "price": 500, "mods": {"damage": 1.2, "mag": 0.9}},
	&"rapid": {"name": "RAPID CORE", "slot": &"core", "price": 450, "mods": {"interval": 0.82, "spread_hip": 1.1}},
	&"extended": {"name": "EXTENDED CORE", "slot": &"core", "price": 400, "mods": {"mag": 1.4, "reload": 1.1}},
}
const IDS0: Array[StringName] = [&"reddot", &"scope", &"halo", &"suppressor", &"longbarrel", &"compensator", &"overcharge", &"rapid", &"extended"]
## Every part: the nine of the first rosters and the twelve of wave 113.
static var PARTS: Dictionary = PARTS0.merged(AttachmentPartsV3.PARTS)
static var IDS: Array[StringName] = IDS0 + AttachmentPartsV3.IDS
const NUMERIC := ["damage", "crit", "spread_hip", "spread_ads", "kick", "kick_end", "kick_yaw", "bloom", "range", "interval", "reload", "mag", "bloom_max", "spread_move", "falloff_from"]

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


## Who may wear a part: `gun` every gun (a hitscan or charge weapon: no melee, no launcher), `long` a gun that is held with two hands (not a pistol), `shotgun` a weapon that throws pellets, `mag` a gun whose
## magazine holds four rounds or more (a bow has no magazine to change). An unknown weapon or part fits nothing.
static func fits(part: StringName, weapon: StringName) -> bool:
	if not PARTS.has(part) or not WeaponDefs.DEFS.has(weapon):
		return false
	var d: Dictionary = WeaponDefs.DEFS[weapon]
	var kind := String(d.get("kind", "hit"))
	var gun := kind == "hit" or kind == "charge"
	match StringName(PARTS[part].get("fits", &"gun")):
		&"gun":
			return gun
		&"long":
			return gun and WeaponDefs.class_of(weapon) != &"pistol"
		&"shotgun":
			return gun and int(d.get("pellets", 1)) >= 3 and WeaponDefs.class_of(weapon) == &"shotgun"
		&"mag":
			return gun and int(d.get("mag", 1)) >= 4
	return false


## The parts of one slot that `weapon` can wear, in IDS order (what the loadout shows under that slot's tab).
static func parts_for_weapon(slot: StringName, weapon: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in parts_for(slot):
		if fits(id, weapon):
			out.append(id)
	return out


## The slots that hold at least one part `weapon` can wear (a knife has none).
static func slots_for_weapon(weapon: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in SLOTS:
		if not parts_for_weapon(slot, weapon).is_empty():
			out.append(slot)
	return out


## True when `weapon` can wear at least one part (a knife or a launcher cannot: it has no PARTS tab).
static func fits_any(weapon: StringName) -> bool:
	for slot in SLOTS:
		if not parts_for_weapon(slot, weapon).is_empty():
			return true
	return false


static func slot_label(slot: StringName) -> String:
	return String(AttachmentPartsV3.SLOT_LABEL.get(slot, String(slot).to_upper()))


static func price(part: StringName, discount := 0.0) -> int:
	return maxi(5, int(roundf(float(Economy.attachment_price(part)) * (1.0 - discount) / 5.0)) * 5)


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
	if not WeaponDefs.DEFS.has(weapon) or not owned.has(part) or not fits(part, weapon):
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


## Weapon definition with the equipped parts applied (a copy; the base DEFS never change). A part that does not fit the weapon (an old save) is ignored.
static func effective(id: StringName) -> Dictionary:
	var base := WeaponDefs.def(id)
	var d: Dictionary = equipped.get(id, {})
	if d.is_empty() and not Crafting.has_gear(id):
		return base
	var out := base.duplicate()
	for slot: StringName in SLOTS:
		var part: StringName = d.get(slot, &"")
		if part == &"" or not PARTS.has(part) or not fits(part, id):
			continue
		var mods: Dictionary = PARTS[part]["mods"]
		for k: String in mods:
			if k == "zoom_set":
				if String(out["kind"]) != "throw":
					out["zoom"] = minf(float(out["zoom"]), float(mods[k]))
			elif k == "vol":
				out["vol"] = float(out["vol"]) - 6.0
			elif NUMERIC.has(k) and out.has(k):
				var v := float(out[k]) * float(mods[k])
				out[k] = maxi(1, int(roundf(v))) if k == "mag" else v
		var sets: Dictionary = PARTS[part].get("set", {})
		for k: String in sets:
			out[k] = sets[k]
		var adds: Dictionary = PARTS[part].get("add", {})
		for k: String in adds:
			out[k] = maxf(float(out.get(k, 0.0)), float(adds[k]))
	Crafting.apply(out, id)                     # crafted variant and mod (scripts/progress/crafting.gd) on top of the parts
	return out


## The weapon definition as it WOULD be with `part` in its slot (&"" = the slot empty) and everything else as fitted now: the live preview of a part in the Arsenal (the stat bars and the
## "+12%" lines read it before anyone pays or fits anything). The fitted parts are restored before it returns.
static func effective_with(id: StringName, slot: StringName, part: StringName) -> Dictionary:
	var keep: Variant = equipped.get(id, null)
	var tmp: Dictionary = (keep as Dictionary).duplicate() if keep is Dictionary else {}
	if part == &"":
		tmp.erase(slot)
	else:
		tmp[slot] = part
	equipped[id] = tmp
	var out := effective(id)
	if keep == null:
		equipped.erase(id)
	else:
		equipped[id] = keep
	return out


## Short text of what a part changes (the loadout screen).
static func effect_text(part: StringName) -> String:
	var bits: PackedStringArray = []
	var mods: Dictionary = PARTS[part]["mods"]
	if (PARTS[part].get("set", {}) as Dictionary).has("pierce_shield"):
		bits.append("CRACKS SHIELDS")
	if (PARTS[part].get("add", {}) as Dictionary).has("mark"):
		bits.append("TAGS TARGETS")
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
