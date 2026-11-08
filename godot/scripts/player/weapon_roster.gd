class_name WeaponRoster
extends RefCounted
## The roster the owner asked for (docs/DESIGN.md: every top COD and GTA weapon type, generic names, plus the quantum ones) as ONE table that says which game object fills each slot, so a test and the
## catalogue can ask the same questions of every entry: does it have a MODEL (the mesh in the hero's hand or the thing in the world), a PICTURE (assets/icons), STATS (numbers a player can read),
## a SOUND (a shipped file) and a way to GET it (starter, crate, mission, enemy drop, boss, shop)? Pure data and rules, no scene tree; the objects themselves live in WeaponDefs (guns and melee),
## Gear (throwables) and Gear.CHARGES (the C4 of scripts/freedom/charges.gd).
## Tabs: the weapon wheel and the catalogue group the guns by class (WeaponDefs.CLASS_ORDER: PISTOL SMG RIFLE SHOTGUN SNIPER HEAVY MELEE QUANTUM); the explosives are the last tab.

const WEAPON := &"weapon"
const THROWABLE := &"throwable"
const CHARGE := &"charge"
const EXPLOSIVE_TAB := &"explosive"

## slot id, label (what the owner asked for), the object id, its kind.
const ENTRIES: Array[Dictionary] = [
	{"slot": &"pistol", "label": "PISTOL", "id": &"pistol", "kind": WEAPON},
	{"slot": &"heavy_pistol", "label": "HEAVY PISTOL", "id": &"magnum", "kind": WEAPON},
	{"slot": &"revolver", "label": "REVOLVER", "id": &"revolver", "kind": WEAPON},
	{"slot": &"machine_pistol", "label": "MACHINE PISTOL", "id": &"mpistol", "kind": WEAPON},
	{"slot": &"smg_1", "label": "SMG", "id": &"flux", "kind": WEAPON},
	{"slot": &"smg_2", "label": "SMG", "id": &"vector", "kind": WEAPON},
	{"slot": &"ar_1", "label": "ASSAULT RIFLE", "id": &"carbine", "kind": WEAPON},
	{"slot": &"ar_2", "label": "ASSAULT RIFLE", "id": &"ranger", "kind": WEAPON},
	{"slot": &"ar_3", "label": "ASSAULT RIFLE", "id": &"bullpup", "kind": WEAPON},
	{"slot": &"battle_rifle", "label": "BATTLE RIFLE", "id": &"battle", "kind": WEAPON},
	{"slot": &"lmg", "label": "LMG", "id": &"lmg", "kind": WEAPON},
	{"slot": &"minigun", "label": "MINIGUN", "id": &"minigun", "kind": WEAPON},
	{"slot": &"pump_shotgun", "label": "PUMP SHOTGUN", "id": &"scatter", "kind": WEAPON},
	{"slot": &"auto_shotgun", "label": "AUTO SHOTGUN", "id": &"auto", "kind": WEAPON},
	{"slot": &"sniper", "label": "SNIPER RIFLE", "id": &"rail", "kind": WEAPON},
	{"slot": &"amr", "label": "ANTI-MATERIAL RIFLE", "id": &"amr", "kind": WEAPON},
	{"slot": &"crossbow", "label": "CROSSBOW", "id": &"xbow", "kind": WEAPON},
	{"slot": &"rpg", "label": "RPG", "id": &"rocket", "kind": WEAPON},
	{"slot": &"grenade_launcher", "label": "GRENADE LAUNCHER", "id": &"gravity", "kind": WEAPON},
	{"slot": &"frag", "label": "FRAG GRENADE", "id": &"singularity", "kind": THROWABLE},
	{"slot": &"smoke", "label": "SMOKE GRENADE", "id": &"shroud", "kind": THROWABLE},
	{"slot": &"flash", "label": "FLASH GRENADE", "id": &"flash", "kind": THROWABLE},
	{"slot": &"c4", "label": "C4 WITH DETONATOR", "id": &"c4", "kind": CHARGE},
	{"slot": &"mine", "label": "PROXIMITY MINE", "id": &"mine", "kind": THROWABLE},
	{"slot": &"flamethrower", "label": "FLAMETHROWER", "id": &"flame", "kind": WEAPON},
	{"slot": &"stun_gun", "label": "STUN GUN", "id": &"stun", "kind": WEAPON},
	{"slot": &"katana", "label": "KATANA", "id": &"katana", "kind": WEAPON},
	{"slot": &"knife", "label": "KNIFE", "id": &"knife", "kind": WEAPON},
	{"slot": &"bat", "label": "BASEBALL BAT", "id": &"bat", "kind": WEAPON},
	{"slot": &"quantum_1", "label": "QUANTUM", "id": &"qsuper", "kind": WEAPON},
	{"slot": &"quantum_2", "label": "QUANTUM", "id": &"qlink", "kind": WEAPON},
	{"slot": &"quantum_3", "label": "QUANTUM", "id": &"qcollapse", "kind": WEAPON},
	{"slot": &"quantum_4", "label": "QUANTUM", "id": &"qblink", "kind": WEAPON},
	{"slot": &"quantum_5", "label": "QUANTUM", "id": &"qphase", "kind": WEAPON},
	{"slot": &"quantum_6", "label": "QUANTUM", "id": &"qstasis", "kind": WEAPON},
]


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in ENTRIES:
		out.append(e["id"])
	return out


static func entry(id: StringName) -> Dictionary:
	for e: Dictionary in ENTRIES:
		if e["id"] == id:
			return e
	return {}


## The tab (wheel / catalogue group) of an entry: the weapon class, or EXPLOSIVE_TAB for the throwables and the charge.
static func tab_of(id: StringName) -> StringName:
	var e := entry(id)
	if e.is_empty():
		return &""
	return WeaponDefs.class_of(id) if StringName(e["kind"]) == WEAPON else EXPLOSIVE_TAB


## The tabs in display order with the entries of each: [{tab, name, ids}].
static func tabs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var list: Array[StringName] = []
		for id in ids():
			if tab_of(id) == cls:
				list.append(id)
		out.append({"tab": cls, "name": String(WeaponDefs.CLASS_NAMES[cls]), "ids": list})
	var ex: Array[StringName] = []
	for id in ids():
		if tab_of(id) == EXPLOSIVE_TAB:
			ex.append(id)
	out.append({"tab": EXPLOSIVE_TAB, "name": "EXPLOSIVES", "ids": ex})
	return out


## The 3D model of an entry: the mesh in the hero's hand (WeaponModels), the thing a throwable becomes in the world, the brick of a charge. Null when there is none.
static func model(id: StringName) -> Mesh:
	match StringName(entry(id).get("kind", &"")):
		WEAPON:
			return WeaponModels.mesh(id)
		THROWABLE:
			return Throwables.mesh_of(id)
		CHARGE:
			return Charges.mesh_of()
	return null


## The picture of an entry (assets/icons: w_<id>, g_<id>), null when it has none.
static func icon(id: StringName) -> Texture2D:
	match StringName(entry(id).get("kind", &"")):
		WEAPON:
			return ItemIcons.weapon(id)
		THROWABLE, CHARGE:
			return ItemIcons.gear(id)
	return null


## The sound name of an entry: the shot or swing of a weapon, the blast or the hiss of a throwable, the boom of a charge. Whether a file exists is Sfx.variants_of's business.
static func sound(id: StringName) -> StringName:
	match StringName(entry(id).get("kind", &"")):
		WEAPON:
			return StringName(WeaponDefs.def(id).get("snd", &"shot"))
		THROWABLE, CHARGE:
			return StringName(Gear.def(id).get("snd", &""))
	return &""


## The numbers of an entry as lines a player reads (WeaponStats.lines for a weapon, the gear numbers for the rest). Never empty for a roster entry.
static func stat_lines(id: StringName) -> Array[String]:
	match StringName(entry(id).get("kind", &"")):
		WEAPON:
			return WeaponStats.lines(WeaponStats.card(id))
		THROWABLE, CHARGE:
			return WeaponsScreen.gear_lines(id)
	return []


## A few plain words on what makes the weapon different to use (the new mechanics of the roster); "" for the ordinary guns.
static func trait_text(id: StringName) -> String:
	var d := WeaponDefs.def(id) if WeaponDefs.DEFS.has(id) else {}
	if d.is_empty():
		return ""
	var bits: Array[String] = []
	if bool(d.get("silent", false)):
		bits.append("SILENT")
	if int(d.get("wall", 0)) > 0:
		bits.append("SHOOTS THROUGH %d WALL%s" % [int(d["wall"]), "" if int(d["wall"]) == 1 else "S"])
	if float(d.get("stun", 0.0)) > 0.0:
		bits.append("FREEZES %.1f S" % float(d["stun"]))
	if float(d.get("burn", 0.0)) > 0.0:
		bits.append("SETS ON FIRE")
	if int(d.get("chain", 0)) > 0:
		bits.append("LINKS %d MORE" % int(d["chain"]))
	if bool(d.get("echo", false)):
		bits.append("ECHO SHOT")
	if String(WeaponDefs.alt_of(id).get("kind", "")) == "blink":
		bits.append("ALT = TELEPORT")
	return "  ".join(bits)


## How to get an entry: the plain route text (WeaponLadder.route_text), STARTER for the guns owned from the first minute, the shop price of a throwable, ALWAYS CARRIED for the charge.
static func unlock(id: StringName) -> String:
	match StringName(entry(id).get("kind", &"")):
		WEAPON:
			return "STARTER" if WeaponDefs.STARTERS.has(id) else WeaponLadder.route_text(id)
		THROWABLE:
			var price := int(Economy.THROW_PRICE.get(id, 0))
			return "STARTER" if price <= 0 else "BUY  %d" % Economy.gear_price(id)
		CHARGE:
			return "ALWAYS CARRIED"
	return ""


## Does the entry have a way to be obtained at all (a starter, a ladder route or a price)? The test asks this of every entry.
static func obtainable(id: StringName) -> bool:
	match StringName(entry(id).get("kind", &"")):
		WEAPON:
			return WeaponDefs.STARTERS.has(id) or not WeaponLadder.entry(id).is_empty() or WeaponDefs.price(id) > 0
		THROWABLE:
			return Gear.THROWABLES.has(id)
		CHARGE:
			return Gear.CHARGES.has(id)
	return false
