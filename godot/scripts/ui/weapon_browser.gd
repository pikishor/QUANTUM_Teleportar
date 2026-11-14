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

const CAP_MAX := 11                               ## characters of a tile caption (a tile is 132 px wide; the caption never goes under the legible size)
const GENERIC := ["GUN", "RIFLE", "PISTOL", "SMG", "SHOTGUN", "CARBINE", "SNIPER", "LMG", "DMR", "BOW", "CROSSBOW", "CANNON", "LAUNCHER", "COMPACT", "REPEATER", "SPRAYER", "EMITTER", "ROTARY", "PISTOLS"]

static var favourites: Array[StringName] = []
static var recent: Array[StringName] = []
static var _caps := {}
static var _seen := {}                            ## weapons the hero has looked at on a card (the NEW filter shows the owned ones that are not here)
static var _seen_ready := false                   ## false until the first question: then everything owned at that moment counts as seen (an old save, a fresh game)


## The caption under a weapon tile: the whole name when it is short ("ARC SABRE"), else its first two words ("ION BATTLE"), else the first word ("PILLAR"): at most CAP_MAX characters, the same on every
## page and different for every weapon of a class (a clash falls through to the next form). A def may carry its own `cap`.
static func caption(id: StringName) -> String:
	if _caps.is_empty():
		_build_captions()
	return String(_caps.get(id, WeaponDefs.title(id).substr(0, CAP_MAX)))


static func _build_captions() -> void:
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var taken := {}
		var ids := WeaponDefs.in_class(cls)
		for id in ids:
			var own := String(WeaponDefs.DEFS[id].get("cap", ""))
			if own != "":
				_caps[id] = own
				taken[own] = true
		for id in ids:
			if _caps.has(id):
				continue
			var words := WeaponDefs.title(id).split(" ", false)
			var forms: Array[String] = [" ".join(words)]
			if words.size() > 2:
				forms.append(" ".join(words.slice(0, 2)))
			var last := String(words[words.size() - 1])
			if words.size() == 2 and not GENERIC.has(last) and last.length() >= 5:
				forms.append(last)                                              # "PLASMA CUTLASS" is a CUTLASS, "TRAIL MACHETE" a MACHETE: the noun names it better than the adjective
			forms.append(String(words[0]))
			if words.size() > 1 and not GENERIC.has(last):
				forms.append(last)
			var pick := ""
			for f in forms:
				if f.length() <= CAP_MAX and not taken.has(f):
					pick = f
					break
			if pick == "":
				pick = String(words[0]).substr(0, CAP_MAX - 1) + "."                  # "SUPERPOSIT."
				if taken.has(pick) or words.size() < 1:
					pick = String(WeaponDefs.DEFS[id].get("tag", pick))
			taken[pick] = true
			_caps[id] = pick


static func reset() -> void:
	favourites.clear()
	recent.clear()
	_seen.clear()
	_seen_ready = false
	LoadoutSlots.reset()


static func _ensure_seen() -> void:
	if _seen_ready:
		return
	_seen_ready = true
	for id: StringName in WeaponDefs.all_ids():
		if WeaponDefs.is_unlocked(id):
			_seen[id] = true


## An owned weapon the hero has not looked at on its card yet (a crate, a mission reward, a purchase): the NEW filter and the NEW badge of the Arsenal.
static func is_new(id: StringName) -> bool:
	_ensure_seen()
	return WeaponDefs.is_unlocked(id) and not _seen.has(id)


static func mark_seen(id: StringName) -> void:
	_ensure_seen()
	_seen[id] = true


static func new_count() -> int:
	_ensure_seen()
	var n := 0
	for id: StringName in WeaponDefs.all_ids():
		if WeaponDefs.is_unlocked(id) and not _seen.has(id):
			n += 1
	return n


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


## The tabs in display order: [{id, name, ids}]: FAVOURITES and RECENT when they hold something (and `special` is on: the catalogue lists classes only), then every class that holds a (owned) weapon.
static func tabs(owned_only := true, special := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := fav_list(owned_only)
	if special and not f.is_empty():
		out.append({"id": FAV, "name": "FAVOURITES", "ids": f})
	var r := recent_list(owned_only)
	if special and not r.is_empty():
		out.append({"id": RECENT, "name": "RECENT", "ids": r})
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var ids: Array[StringName] = []
		for id in WeaponDefs.in_class(cls):
			if _owned(id, owned_only):
				ids.append(id)
		if not ids.is_empty():
			out.append({"id": cls, "name": String(WeaponDefs.CLASS_NAMES.get(cls, str(cls).to_upper())), "ids": ids})
	return out


## `ids` cut into the fewest pages of at most `size`, evenly: 20 weapons on three pages are 7, 7 and 6, 53 on seven pages are 8, 8, 8, 8, 7, 7 and 7 (pages differ by one item at most).
static func split(ids: Array, size := PAGE) -> Array:
	var n := pages_for(ids.size(), size)
	var base := ids.size() / n
	var extra := ids.size() % n
	var out: Array = []
	var at := 0
	for i in n:
		var cnt := base + (1 if i < extra else 0)
		out.append(ids.slice(at, at + cnt))
		at += cnt
	return out


## Number of pages of `n` items.
static func pages_for(n: int, size := PAGE) -> int:
	return maxi(1, (n + size - 1) / size)


## Every page of every tab in one sequence: [{tab, name, ids (at most `size`, balanced over the pages of the tab), sub (0 based page of the tab), subs (pages of the tab)}].
static func pages(owned_only := true, size := PAGE, special := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in tabs(owned_only, special):
		var ids: Array[StringName] = t["ids"]
		var n := pages_for(ids.size(), size)
		var chunks := split(ids, size)
		for sub in n:
			out.append({"tab": t["id"], "name": t["name"], "ids": chunks[sub], "sub": sub, "subs": n})
	return out


## The index in `pages()` of the first page holding `id`: its own class tab first (the page follows a selected weapon into its class, not into FAVOURITES), else any tab; -1 when it is nowhere.
static func page_of(id: StringName, owned_only := true, size := PAGE, special := true) -> int:
	var ps := pages(owned_only, size, special)
	var cls := WeaponDefs.class_of(id)
	for i in ps.size():
		if ps[i]["tab"] == cls and (ps[i]["ids"] as Array).has(id):
			return i
	for i in ps.size():
		if (ps[i]["ids"] as Array).has(id):
			return i
	return -1


## The index in `pages()` of the first page of the tab after (dir 1) or before (dir -1) the tab that page `at` belongs to (wraps).
static func tab_jump(at: int, dir: int, owned_only := true, size := PAGE, special := true) -> int:
	var ps := pages(owned_only, size, special)
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
	_ensure_seen()
	var sn := PackedStringArray()
	for id: StringName in _seen:
		sn.append(String(id))
	return {"favourites": f, "recent": r, "seen": sn, "slots": LoadoutSlots.to_save()}


static func from_save(d: Dictionary) -> void:
	reset()
	if d.has("seen"):                                                    # a save without the key (older builds) keeps _seen_ready false: everything owned is seen at the first question
		var sv: Variant = d["seen"]
		for n: Variant in (Array(sv) if sv is Array or sv is PackedStringArray else []):
			var sid := StringName(str(n))
			if WeaponDefs.DEFS.has(sid):
				_seen[sid] = true
		_seen_ready = true
	if d.has("slots"):
		LoadoutSlots.from_save(d["slots"])
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
