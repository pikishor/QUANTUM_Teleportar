class_name LoadoutSlots
extends RefCounted
## The CARRIED weapons (wave 128, owner: "why only 4 weapons allowed? allow 30-40 to be switched"): COUNT = 36 slots that each hold one owned weapon, and the quick swap that cycles through them.
## The first four keep their names (PRIMARY, SIDEARM, SPECIAL, MELEE) and are filled from the classes they like; slots 5 to 36 carry every weapon the hero picks up, buys or is given (in the order he got
## it), until all 36 are full. The SWAP button, the keyboard cycle and the mouse wheel walk the carried slots (`PlayerWeapon.cycle`); the weapon wheel's CARRIED wedge shows them as a paged ring; the
## Arsenal shows them four at a time with a page chip and its EQUIP puts the picked weapon into the ACTIVE slot (wave 114). A slot may be empty; a slot whose weapon is no longer owned is emptied (the first
## four are refilled). Static, saved by Progress with the rest of the weapon profile (`WeaponBrowser.to_save` carries it; a save of the old four slots is topped up on load). Nothing here draws.

const COUNT := 36
const PAGE := 4                                  ## slots the Arsenal's bottom bar shows at once (a page chip turns to the next four)
const NAMED := 4                                 ## the first slots have a name and a class preference
const LABELS: Array[String] = ["PRIMARY", "SIDEARM", "SPECIAL", "MELEE"]
## The classes a named slot likes when it is filled for the first time (the first owned weapon of the first class that has one, not already in another slot).
const PREF: Array = [[&"rifle", &"smg", &"sniper"], [&"pistol", &"shotgun"], [&"shotgun", &"sniper", &"heavy", &"blast", &"energy", &"quantum"], [&"melee"]]

static var slots: Array[StringName] = _empty()
static var active := 0                           ## the slot the Arsenal edits and the next quick swap starts from
static var swaps := 0                            ## quick swaps made (tests wait on it)
static var page := 0                             ## the Arsenal's page of slots (0 = slots 1-4)
static var _sig := -1                            ## what ensure() last saw (the owned set, hero mode, the slots): unchanged = nothing to do
static var OLD := OS.get_environment("W128A_OLD") == "1"     ## the fail-first run of tests/test_arsenal_w128.gd: the four slots of wave 114 (nothing past slot 4, no page chip, 24 favourites)


## The slots in use: COUNT (four with W128A_OLD=1).
static func used() -> int:
	return NAMED if OLD else COUNT


static func _empty() -> Array[StringName]:
	var out: Array[StringName] = []
	out.resize(COUNT)
	out.fill(&"")
	return out


static func reset() -> void:
	slots = _empty()
	active = 0
	page = 0
	_sig = -1


static func label(i: int) -> String:
	return LABELS[i] if i >= 0 and i < NAMED else "SLOT %d" % (i + 1)


## Fill the empty slots and the ones whose weapon the hero no longer owns: the named ones from their classes, the others from the weapons the hero got (not the starters: those he has from the first minute
## sit in the named slots or in the wheel). Cheap when nothing changed (callers do it before they read).
static func ensure() -> void:
	var sig := hash([WeaponDefs.unlocked.size(), WeaponDefs.unlocked.hash(), WeaponDefs.hero_mode, slots.hash()])
	if sig == _sig:
		return
	for i in COUNT:
		if slots[i] != &"" and WeaponDefs.DEFS.has(slots[i]) and WeaponDefs.is_unlocked(slots[i]):
			continue
		slots[i] = _pick(i) if i < NAMED else &""
	var free := COUNT if OLD else 0
	for id: StringName in _candidates():
		while free < COUNT and (free < NAMED or slots[free] != &""):
			free += 1
		if free >= COUNT:
			break
		slots[free] = id
	_sig = hash([WeaponDefs.unlocked.size(), WeaponDefs.unlocked.hash(), WeaponDefs.hero_mode, slots.hash()])


## The owned weapons that wait for a carried slot (not the starters, not carried yet), in the order the hero got them; when more wait than there is room (the demo grants all 229 at once) they are
## dealt round the classes (one pistol, one SMG, one rifle ... then the second of each), so 36 carried weapons are a mixed set, not 32 pistols.
static func _candidates() -> Array[StringName]:
	var by_cls := {}
	var n := 0
	for id: StringName in WeaponDefs.unlocked:
		if WeaponDefs.STARTERS.has(id) or slots.has(id) or not WeaponDefs.DEFS.has(id):
			continue
		var c := WeaponDefs.class_of(id)
		if not by_cls.has(c):
			by_cls[c] = []
		(by_cls[c] as Array).append(id)
		n += 1
	var out: Array[StringName] = []
	if n <= COUNT:
		for id: StringName in WeaponDefs.unlocked:
			if not WeaponDefs.STARTERS.has(id) and not slots.has(id) and WeaponDefs.DEFS.has(id):
				out.append(id)
		return out
	var k := 0
	while out.size() < n and out.size() < COUNT:
		for c: StringName in WeaponDefs.CLASS_ORDER:
			var lst: Array = by_cls.get(c, [])
			if k < lst.size():
				out.append(lst[k])
		for c: Variant in by_cls:
			if not WeaponDefs.CLASS_ORDER.has(c) and k < (by_cls[c] as Array).size():
				out.append((by_cls[c] as Array)[k])
		k += 1
	return out


static func _pick(i: int) -> StringName:
	for cls: StringName in PREF[i]:
		for id: StringName in WeaponDefs.owned_in_class(cls):
			if not slots.has(id):
				return id
	return &""


static func get_slot(i: int) -> StringName:
	ensure()
	return slots[clampi(i, 0, COUNT - 1)]


## The slot that holds `id`, -1 when none does.
static func slot_of(id: StringName) -> int:
	return slots.find(id)


## Put an owned weapon into slot `i`. A weapon that sits in another slot trades places with this slot's weapon (a weapon is in one slot at most). Returns false for a weapon the hero does not own.
static func assign(i: int, id: StringName) -> bool:
	if i < 0 or i >= used() or not WeaponDefs.DEFS.has(id) or not WeaponDefs.is_unlocked(id):
		return false
	ensure()
	var other := slots.find(id)
	if other >= 0 and other != i:
		slots[other] = slots[i]
	slots[i] = id
	return true


## Which slots hold a weapon.
static func filled() -> Array[int]:
	ensure()
	var out: Array[int] = []
	for i in used():
		if slots[i] != &"":
			out.append(i)
	return out


## The carried weapons in slot order (the wheel's CARRIED ring).
static func carried() -> Array[StringName]:
	var out: Array[StringName] = []
	for i in filled():
		out.append(slots[i])
	return out


## The pages of the Arsenal's slot bar.
static func pages() -> int:
	return used() / PAGE


## Turn the Arsenal's slot bar by `dir` pages (wraps). Returns the new page.
static func flip_page(dir: int) -> int:
	page = posmod(page + dir, pages())
	return page


## The weapon the quick swap goes to from `cur`: the next (dir 1) or previous (dir -1) filled slot after the one that holds `cur`; a weapon in no slot (it came from the wheel) swaps to the ACTIVE slot
## first. &"" when no slot holds anything.
static func next_after(cur: StringName, dir: int) -> StringName:
	var f := filled()
	if f.is_empty():
		return &""
	var at := slots.find(cur)
	var to: int
	if at < 0:
		to = active if f.has(active) else f[0]
	else:
		var k := f.find(at)
		to = f[posmod(k + dir, f.size())]
	active = to
	swaps += 1
	return slots[to]


static func to_save() -> PackedStringArray:
	var out := PackedStringArray()
	for id in slots:
		out.append(String(id))
	return out


static func from_save(v: Variant) -> void:
	reset()
	var arr: Array = Array(v) if (v is Array or v is PackedStringArray) else []
	for i in mini(COUNT, arr.size()):
		var id := StringName(str(arr[i]))
		slots[i] = id if WeaponDefs.DEFS.has(id) else &""
