class_name LoadoutSlots
extends RefCounted
## The loadout: FOUR SLOTS (PRIMARY, SIDEARM, SPECIAL, MELEE) that each hold one owned weapon, and the quick swap that cycles through them (wave 114). With 200+ weapons a SWAP that walks
## every owned weapon is useless, so the SWAP button, the keyboard cycle and the mouse wheel walk the slots (`PlayerWeapon.cycle`); the weapon wheel and the Arsenal screen pick any weapon,
## and the Arsenal's EQUIP puts the picked weapon into the ACTIVE slot. A slot may be empty; a slot whose weapon is no longer owned is refilled. Static, saved by Progress with the rest of the
## weapon profile (`WeaponBrowser.to_save` carries it). Nothing here draws.

const COUNT := 4
const LABELS: Array[String] = ["PRIMARY", "SIDEARM", "SPECIAL", "MELEE"]
## The classes a slot likes when it is filled for the first time (the first owned weapon of the first class that has one, not already in another slot).
const PREF: Array = [[&"rifle", &"smg", &"sniper"], [&"pistol", &"shotgun"], [&"shotgun", &"sniper", &"heavy", &"blast", &"energy", &"quantum"], [&"melee"]]

static var slots: Array[StringName] = [&"", &"", &"", &""]
static var active := 0                           ## the slot the Arsenal edits and the next quick swap starts from
static var swaps := 0                            ## quick swaps made (tests wait on it)


static func reset() -> void:
	slots = [&"", &"", &"", &""]
	active = 0


## Fill the empty slots and the ones whose weapon the hero no longer owns. Cheap; callers do it before they read.
static func ensure() -> void:
	for i in COUNT:
		if slots[i] != &"" and WeaponDefs.DEFS.has(slots[i]) and WeaponDefs.is_unlocked(slots[i]):
			continue
		slots[i] = _pick(i)


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
	if i < 0 or i >= COUNT or not WeaponDefs.DEFS.has(id) or not WeaponDefs.is_unlocked(id):
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
	for i in COUNT:
		if slots[i] != &"":
			out.append(i)
	return out


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
