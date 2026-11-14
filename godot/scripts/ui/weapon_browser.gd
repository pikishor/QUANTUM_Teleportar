class_name WeaponBrowser
extends RefCounted
## How a long weapon list is browsed on a phone (wave 113: 180+ weapons): FAVOURITES (the hero stars the weapons he likes), RECENT (the last eight weapons in hand, automatic) and one tab per weapon class,
## every tab cut into pages of PAGE weapons. The LOADOUT screen, the weapon wheel of the touch HUD and the catalogue all read this one model. Pure data and rules, static state saved with the profile
## (Progress writes `to_save()` into the "weapons" section). Nothing here draws.

const PAGE := 8                                   ## weapons per page (the loadout grid is 2 x 4, the wheel keeps two discs for BACK and NEXT PAGE)
const FAV: StringName = &"fav"
const RECENT: StringName = &"recent"
const RECENT_MAX := 8
const FAV_MAX := 24

static var favourites: Array[StringName] = []
static var recent: Array[StringName] = []


static func reset() -> void:
	favourites.clear()
	recent.clear()


## The weapon in hand changed: it goes to the front of RECENT.
static func note_used(id: StringName) -> void:
	if not WeaponDefs.DEFS.has(id):
		return
	recent.erase(id)
	recent.push_front(id)
	while recent.size() > RECENT_MAX:
		recent.pop_back()


static func is_favourite(id: StringName) -> bool:
	return favourites.has(id)


## Star or unstar a weapon. Returns whether it is a favourite now (false too when the list is full).
static func toggle_favourite(id: StringName) -> bool:
	if not WeaponDefs.DEFS.has(id):
		return false
	if favourites.has(id):
		favourites.erase(id)
		return false
	if favourites.size() >= FAV_MAX:
		return false
	favourites.append(id)
	return true


static func _owned(id: StringName, owned_only: bool) -> bool:
	return not owned_only or WeaponDefs.is_unlocked(id)


static func fav_list(owned_only := true) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in favourites:
		if WeaponDefs.DEFS.has(id) and _owned(id, owned_only):
			out.append(id)
	return out


static func recent_list(owned_only := true) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in recent:
		if WeaponDefs.DEFS.has(id) and _owned(id, owned_only):
			out.append(id)
	return out


## The tabs in display order: [{id, name, ids}]: FAVOURITES and RECENT when they hold something, then every class that holds a (owned) weapon.
static func tabs(owned_only := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := fav_list(owned_only)
	if not f.is_empty():
		out.append({"id": FAV, "name": "FAVOURITES", "ids": f})
	var r := recent_list(owned_only)
	if not r.is_empty():
		out.append({"id": RECENT, "name": "RECENT", "ids": r})
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var ids: Array[StringName] = []
		for id in WeaponDefs.in_class(cls):
			if _owned(id, owned_only):
				ids.append(id)
		if not ids.is_empty():
			out.append({"id": cls, "name": String(WeaponDefs.CLASS_NAMES.get(cls, str(cls).to_upper())), "ids": ids})
	return out


## Number of pages of `n` items.
static func pages_for(n: int, size := PAGE) -> int:
	return maxi(1, (n + size - 1) / size)


## Every page of every tab in one sequence: [{tab, name, ids (at most `size`), sub (0 based page of the tab), subs (pages of the tab)}].
static func pages(owned_only := true, size := PAGE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in tabs(owned_only):
		var ids: Array[StringName] = t["ids"]
		var n := pages_for(ids.size(), size)
		for sub in n:
			out.append({"tab": t["id"], "name": t["name"], "ids": ids.slice(sub * size, mini(ids.size(), (sub + 1) * size)), "sub": sub, "subs": n})
	return out


## The index in `pages()` of the first page holding `id`: its own class tab first (the page follows a selected weapon into its class, not into FAVOURITES), else any tab; -1 when it is nowhere.
static func page_of(id: StringName, owned_only := true, size := PAGE) -> int:
	var ps := pages(owned_only, size)
	var cls := WeaponDefs.class_of(id)
	for i in ps.size():
		if ps[i]["tab"] == cls and (ps[i]["ids"] as Array).has(id):
			return i
	for i in ps.size():
		if (ps[i]["ids"] as Array).has(id):
			return i
	return -1


## The index in `pages()` of the first page of the tab after (dir 1) or before (dir -1) the tab that page `at` belongs to (wraps).
static func tab_jump(at: int, dir: int, owned_only := true, size := PAGE) -> int:
	var ps := pages(owned_only, size)
	if ps.is_empty():
		return 0
	at = clampi(at, 0, ps.size() - 1)
	var starts: Array[int] = []
	for i in ps.size():
		if int(ps[i]["sub"]) == 0:
			starts.append(i)
	var cur := 0
	for k in starts.size():
		if starts[k] <= at:
			cur = k
	return starts[posmod(cur + dir, starts.size())]


# --- the profile ---------------------------------------------------------------------------------------------------------------

static func to_save() -> Dictionary:
	var f := PackedStringArray()
	for id in favourites:
		f.append(String(id))
	var r := PackedStringArray()
	for id in recent:
		r.append(String(id))
	return {"favourites": f, "recent": r}


static func from_save(d: Dictionary) -> void:
	reset()
	for key in ["favourites", "recent"]:
		var v: Variant = d.get(key, [])
		for n: Variant in (Array(v) if v is Array or v is PackedStringArray else []):
			var id := StringName(str(n))
			if not WeaponDefs.DEFS.has(id):
				continue
			if key == "favourites" and not favourites.has(id) and favourites.size() < FAV_MAX:
				favourites.append(id)
			elif key == "recent" and not recent.has(id) and recent.size() < RECENT_MAX:
				recent.append(id)
