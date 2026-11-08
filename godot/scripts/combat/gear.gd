class_name Gear
extends RefCounted
## Melee, throwables and gadgets: the shared tables and the saved state (static, like Attachments: the loadout screen, the save, the demo and the live modules all see it).
##   MELEE      light / heavy / finisher numbers (Melee reads them).
##   THROWABLES singularity (frag-like), mine (flux mine), decoy, shroud (phase shroud smoke), emp. One slot: the equipped throwable (action `throw_item`).
##   GADGETS    drone (buddy turret), scanner (pulse that shows enemies through walls), grapple (grapple-teleport hook). One slot: the equipped gadget (action `gadget`).
##   LOADOUTS   4 saved sets {weapon, throw, gadget}; apply() equips one. Prices come from Economy (THROW_PRICE, GADGET_PRICE), the save from Progress ([gear] section).
## The carried stock of each throwable is not saved: it refills on a new run, a respawn and slowly over time (Throwables).

const MELEE := {
	"reach": 2.3, "heavy_reach": 2.7, "cone": 0.55,                       ## cone = minimum dot(forward, to enemy) of a hit
	"light": 28.0, "heavy": 70.0, "finisher": 95.0,                       ## damage before HeroPower / TestMode scaling
	"light_time": 0.28, "heavy_time": 0.55, "finisher_time": 0.5,         ## seconds the swing blocks the next one
	"combo_window": 0.7,                                                  ## seconds after a swing the chain continues
	"heavy_hold": 0.35,                                                   ## seconds melee is held before it counts as heavy
	"stagger": [0.9, 1.5, 2.2], "launch": [0.0, 4.0, 11.0],               ## per kind (light, heavy, finisher): stagger power, launch speed
	"energy": [0.0, 6.0, 10.0],
}
const KINDS: Array[StringName] = [&"light", &"heavy", &"finisher"]

const THROW_IDS: Array[StringName] = [&"singularity", &"mine", &"decoy", &"shroud", &"emp", &"flash"]
const THROWABLES := {
	&"singularity": {"name": "SINGULARITY FRAG", "tag": "FRAG", "color": Color(0.7, 0.35, 1.0), "max": 3, "fuse": 1.3, "radius": 5.5, "damage": 90.0, "pull": 7.0, "snd": &"explosion_small", "desc": "Pulls enemies in, then collapses."},
	&"mine": {"name": "FLUX MINE", "tag": "MINE", "color": Color(1.0, 0.6, 0.2), "max": 3, "arm": 0.7, "radius": 5.0, "trigger": 2.6, "damage": 80.0, "life": 40.0, "snd": &"explosion_small", "desc": "Proximity mine: sticks where it lands, blows when enemies step near."},
	&"decoy": {"name": "DECOY GRENADE", "tag": "DECOY", "color": Color(0.4, 0.95, 1.0), "max": 2, "life": 7.0, "lure": 28.0, "snd": &"blink", "desc": "A hologram that draws enemy attention."},
	&"shroud": {"name": "PHASE SHROUD", "tag": "SHROUD", "color": Color(0.5, 0.6, 0.95), "max": 2, "life": 8.0, "radius": 5.5, "snd": &"superpos", "desc": "SMOKE: a cloud enemies cannot see through."},
	&"emp": {"name": "EMP", "tag": "EMP", "color": Color(0.3, 0.8, 1.0), "max": 2, "fuse": 0.9, "radius": 9.0, "disable": 3.2, "damage": 12.0, "snd": &"explosion_small", "desc": "Shuts down every enemy in range."},
	&"flash": {"name": "FLASH GRENADE", "tag": "FLASH", "color": Color(1.0, 1.0, 0.85), "max": 3, "fuse": 0.8, "radius": 12.0, "disable": 2.6, "snd": &"explosion_small", "desc": "A blinding flash: enemies in range freeze and lose you."},
}
## QUANTUM CHARGE (C4 with a detonator, scripts/freedom/charges.gd): free and always carried, so it is not a loadout item; the numbers below mirror the Charges constants (a test keeps them equal).
const CHARGE_IDS: Array[StringName] = [&"c4"]
const CHARGES := {
	&"c4": {"name": "QUANTUM CHARGE C4", "tag": "C4", "color": Color(1.0, 0.68, 0.2), "max": 3, "radius": 6.5, "damage": 170.0, "range": 20.0, "snd": &"boom", "desc": "Stick it anywhere, then DETONATE. Chains with other blasts."},
}
const GADGET_IDS: Array[StringName] = [&"scanner", &"drone", &"grapple"]
const GADGETS := {
	&"scanner": {"name": "SCANNER PULSE", "tag": "SCAN", "color": Color(0.3, 1.0, 0.8), "cooldown": 14.0, "radius": 40.0, "show": 6.0, "energy": 8.0, "desc": "Shows enemies through walls."},
	&"drone": {"name": "DRONE BUDDY", "tag": "DRONE", "color": Color(1.0, 0.85, 0.3), "cooldown": 40.0, "life": 20.0, "range": 22.0, "damage": 9.0, "interval": 0.45, "energy": 15.0, "desc": "A turret drone that follows and shoots."},
	&"grapple": {"name": "GRAPPLE HOOK", "tag": "HOOK", "color": Color(0.6, 1.0, 0.5), "cooldown": 3.0, "range": 32.0, "speed": 48.0, "energy": 12.0, "desc": "Teleport-pull to the point you aim at."},
}
const SLOTS := 4

static var owned: Dictionary = {&"singularity": true}     ## id -> true (throwables and gadgets share the table)
static var throwable: StringName = &"singularity"
static var gadget: StringName = &""                      ## "" = empty slot
static var active_slot := 0                              ## the loadout slot last applied or saved
static var loadouts: Array = []                          ## SLOTS dictionaries {weapon, throw, gadget}, "" where empty


static func reset() -> void:
	owned = {&"singularity": true}
	throwable = &"singularity"
	gadget = &""
	active_slot = 0
	loadouts = []
	for i in SLOTS:
		loadouts.append({"weapon": "carbine", "throw": "singularity", "gadget": ""})


static func _ensure() -> void:
	if loadouts.size() != SLOTS:
		reset()


static func is_throwable(id: StringName) -> bool:
	return THROWABLES.has(id)


static func is_gadget(id: StringName) -> bool:
	return GADGETS.has(id)


static func def(id: StringName) -> Dictionary:
	return THROWABLES[id] if THROWABLES.has(id) else (GADGETS[id] if GADGETS.has(id) else (CHARGES[id] if CHARGES.has(id) else {}))


static func is_charge(id: StringName) -> bool:
	return CHARGES.has(id)


static func title(id: StringName) -> String:
	return String(def(id).get("name", "NONE"))


static func is_owned(id: StringName) -> bool:
	return owned.has(id) or Economy.gear_price(id) <= 0


static func give(id: StringName) -> void:
	if THROWABLES.has(id) or GADGETS.has(id):
		owned[id] = true


static func give_all() -> void:
	for id: StringName in THROW_IDS:
		give(id)
	for id: StringName in GADGET_IDS:
		give(id)


## Equips an owned throwable or gadget (a gadget id of "" empties the slot). Returns false for an unknown or unowned id.
static func equip(id: StringName) -> bool:
	if id == &"":
		gadget = &""
		return true
	if not is_owned(id):
		return false
	if THROWABLES.has(id):
		throwable = id
		return true
	if GADGETS.has(id):
		gadget = id
		return true
	return false


# --- loadouts -----------------------------------------------------------------------------------------------------------

static func save_loadout(i: int) -> bool:
	_ensure()
	if i < 0 or i >= SLOTS:
		return false
	loadouts[i] = {"weapon": String(WeaponDefs.last_used), "throw": String(throwable), "gadget": String(gadget)}
	active_slot = i
	return true


## Equips slot `i`: its weapon (when still owned), throwable and gadget (when still owned). Returns false for a bad slot.
static func apply_loadout(i: int) -> bool:
	_ensure()
	if i < 0 or i >= SLOTS:
		return false
	var l: Dictionary = loadouts[i]
	var w := StringName(str(l.get("weapon", "carbine")))
	if WeaponDefs.is_unlocked(w):
		var pl := Game.player
		if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
			(pl.get(&"weapon") as PlayerWeapon).switch_to(w)
		else:
			WeaponDefs.last_used = w
	var t := StringName(str(l.get("throw", "singularity")))
	throwable = t if THROWABLES.has(t) and is_owned(t) else &"singularity"
	var g := StringName(str(l.get("gadget", "")))
	gadget = g if GADGETS.has(g) and is_owned(g) else &""
	active_slot = i
	return true


static func loadout_label(i: int) -> String:
	_ensure()
	var l: Dictionary = loadouts[clampi(i, 0, SLOTS - 1)]
	var g := StringName(str(l.get("gadget", "")))
	return "%s  %s" % [String(THROWABLES.get(StringName(str(l.get("throw", ""))), {}).get("tag", "-")), String(GADGETS.get(g, {}).get("tag", "-"))]


# --- save ---------------------------------------------------------------------------------------------------------------

static func to_save() -> Dictionary:
	_ensure()
	var names := PackedStringArray()
	for id: StringName in owned:
		names.append(String(id))
	var ls := PackedStringArray()
	for l: Dictionary in loadouts:
		ls.append("%s|%s|%s" % [l["weapon"], l["throw"], l["gadget"]])
	return {"owned": names, "throw": String(throwable), "gadget": String(gadget), "slot": active_slot, "loadouts": ls}


## Tolerant: a missing or damaged section leaves the defaults (older saves have no gear).
static func from_save(d: Dictionary) -> void:
	reset()
	var ow: Variant = d.get("owned", [])
	if ow is Array or ow is PackedStringArray:
		for v: Variant in ow:
			var id := StringName(str(v))
			if THROWABLES.has(id) or GADGETS.has(id):
				owned[id] = true
	var t := StringName(str(d.get("throw", "singularity")))
	throwable = t if THROWABLES.has(t) and owned.has(t) else &"singularity"
	var g := StringName(str(d.get("gadget", "")))
	gadget = g if GADGETS.has(g) and owned.has(g) else &""
	var s: Variant = d.get("slot", 0)
	active_slot = clampi(int(s) if s is int or s is float else 0, 0, SLOTS - 1)
	var ls: Variant = d.get("loadouts", [])
	if ls is Array or ls is PackedStringArray:
		for i in mini(SLOTS, (ls as Array).size() if ls is Array else (ls as PackedStringArray).size()):
			var parts := str(ls[i]).split("|")
			if parts.size() == 3:
				loadouts[i] = {"weapon": parts[0] if WeaponDefs.DEFS.has(StringName(parts[0])) else "carbine", "throw": parts[1] if THROWABLES.has(StringName(parts[1])) else "singularity", "gadget": parts[2] if GADGETS.has(StringName(parts[2])) else ""}


# --- helpers shared by the live modules -----------------------------------------------------------------------------------

static func living_enemies(tree: SceneTree) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in tree.get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e != null and is_instance_valid(e) and e.is_inside_tree() and not bool(e.get(&"dead")) and (e.get(&"active") == null or bool(e.get(&"active"))):
			out.append(e)
	return out


## A shared additive (or alpha) unshaded material for the gear effects.
static func fx_material(color: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m
