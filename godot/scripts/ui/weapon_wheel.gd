class_name WeaponWheel
extends RefCounted
## The WEAPON wheel of the phone HUD, grouped by class like a console shooter's: one wedge per class (PISTOL, SMG, RIFLE, SHOTGUN, SNIPER, HEAVY, MELEE ...), each showing the weapon you last used in that
## class and how many you own there ("PST 1/4"), plus RECENT (the weapons in your hand lately: a pick is the weapon before this one) and FAVOURITES (the stars of the loadout) when they hold something.
## Two levels (wave 113, 200+ weapons): a pick of a wedge equips its weapon at once (the last one used in the class), and when the class holds more than one weapon the wheel stays open as a RING of
## that class (`ring_items`: up to RING weapons around the thumb, a NEXT disc turns the page); a tap on a weapon disc picks it, a tap anywhere else closes the wheel and keeps the weapon in hand.
## A wheel of two hundred discs would not fit a phone (and would overlap), at most a dozen always do. The wheel items are RadialWheel items: id = the class (or the weapon), icon = the weapon drawn on the disc,
## `type` = class | tab | weapon | page.

const RING := 8                                    ## weapons on one page of a ring (plus the NEXT disc)
const RECENT: StringName = &"recent"
const FAV: StringName = &"fav"


## The wedges, in CLASS_ORDER: {id: class, icon: weapon id, label, ready, active, cd, current, cls, owned, total}.
static func items() -> Array:
	var out: Array = []
	var cur: StringName = &""
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	if p != null and p.get("weapon") is PlayerWeapon:
		cur = (p.get("weapon") as PlayerWeapon).current
	var cur_cls := WeaponDefs.class_of(cur)
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var owned := WeaponDefs.owned_in_class(cls)
		if owned.is_empty():
			continue
		var show: StringName = cur if cls == cur_cls and owned.has(cur) else weapon_for(cls)
		var label := str(WeaponDefs.DEFS[show].get("tag", show))
		if owned.size() > 1:
			label += " %d/%d" % [owned.find(show) + 1, owned.size()]
		out.append({"id": cls, "type": &"class", "icon": show, "label": label, "ready": true, "active": cls == cur_cls, "cd": 0.0, "current": cls == cur_cls, "cls": cls, "owned": owned.size(), "total": WeaponDefs.in_class(cls).size(),
				"cname": String(WeaponDefs.CLASS_NAMES.get(cls, str(cls).to_upper())), "wname": String(WeaponDefs.DEFS[show].get("name", show)).to_upper()})
	var rec := recent_others(cur)
	if not rec.is_empty():
		out.append(_tab_item(RECENT, "RECENT", rec, cur))
	var fav := WeaponBrowser.fav_list(true)
	if not fav.is_empty():
		out.append(_tab_item(FAV, "FAVOURITES", fav, cur))
	return out


## The owned weapons used lately, without the one in hand, newest first.
static func recent_others(cur: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in WeaponBrowser.recent_list(true):
		if id != cur:
			out.append(id)
	return out


static func _tab_item(tab: StringName, nm: String, ids: Array, cur: StringName) -> Dictionary:
	var show: StringName = ids[0]
	return {"id": tab, "type": &"tab", "icon": show, "label": nm, "ready": true, "active": false, "cd": 0.0, "current": false, "cls": tab, "owned": ids.size(), "total": ids.size(), "cname": nm,
			"wname": String(WeaponDefs.DEFS[show].get("name", show)).to_upper() + ("" if cur == &"" else "")}


## The owned weapons of a wheel tab (a class, RECENT or FAV) in display order.
static func tab_ids(tab: StringName, cur: StringName = &"") -> Array[StringName]:
	if tab == RECENT:
		return recent_others(cur)
	if tab == FAV:
		return WeaponBrowser.fav_list(true)
	return WeaponDefs.owned_in_class(tab)


static func ring_pages(tab: StringName, cur: StringName = &"") -> int:
	return WeaponBrowser.pages_for(tab_ids(tab, cur).size(), RING)


## The page of a ring that holds `id` (0 when it is not there).
static func ring_page_of(tab: StringName, id: StringName, cur: StringName = &"") -> int:
	var at := tab_ids(tab, cur).find(id)
	return maxi(at, 0) / RING


## Level two: the weapons of `tab` on page `page` as wheel discs, then a NEXT disc when there is more than one page. `cur` is the weapon in hand.
static func ring_items(tab: StringName, page: int, cur: StringName) -> Array:
	var ids := tab_ids(tab, cur)
	var n := ring_pages(tab, cur)
	page = posmod(page, n)
	var out: Array = []
	for id in ids.slice(page * RING, mini(ids.size(), (page + 1) * RING)):
		var d: Dictionary = WeaponDefs.DEFS[id]
		out.append({"id": id, "type": &"weapon", "icon": id, "label": str(d.get("tag", id)), "ready": true, "active": id == cur, "cd": 0.0, "current": id == cur, "cls": tab, "owned": 1, "total": 1,
				"cname": String(d.get("name", id)).split(" ")[0], "wname": String(d.get("name", id)).to_upper(), "tab": tab, "page": page, "fav": WeaponBrowser.is_favourite(id)})
	if n > 1:
		out.append({"id": &"page", "type": &"page", "icon": &"", "label": "NEXT", "ready": true, "active": false, "cd": 0.0, "current": false, "cls": tab, "owned": 1, "total": 1,
				"cname": "PAGE %d / %d" % [page + 1, n], "wname": "NEXT PAGE  %d OF %d" % [posmod(page + 1, n) + 1, n], "tab": tab, "page": page + 1})
	return out


## The weapon a class wedge selects: the last one used in the class, else its first owned.
static func weapon_for(cls: StringName) -> StringName:
	var owned := WeaponDefs.owned_in_class(cls)
	if owned.is_empty():
		return &""
	var last: StringName = StringName(WeaponDefs.last_in_class.get(cls, &""))
	return last if owned.has(last) else owned[0]


## The next owned weapon of the class after `cur` (wraps; `cur` itself when it is the only one).
static func next_in_class(cls: StringName, cur: StringName) -> StringName:
	var owned := WeaponDefs.owned_in_class(cls)
	if owned.is_empty():
		return cur
	var i := owned.find(cur)
	return owned[posmod(i + 1, owned.size())]


## A pick of class wedge `cls` for the weapon node `w`. Returns true when the weapon changed.
static func pick(cls: StringName, w: PlayerWeapon) -> bool:
	if w == null:
		return false
	if WeaponDefs.class_of(w.current) == cls:
		return w.switch_to(next_in_class(cls, w.current))
	var id := weapon_for(cls)
	return id != &"" and w.switch_to(id)


## A pick of wheel disc `it` (an item of items() or ring_items()) for the weapon node `w`. Returns the ring to open next ({tab, page}) or {} when the wheel closes.
## class: the last weapon of the class (or the next one when it is already in hand and the class has no ring) and, when the class holds more than one weapon, its ring; RECENT: the weapon before this one and the
## ring of the recent weapons; FAV: only the ring; a weapon disc: that weapon, wheel closed; the NEXT disc: the next page of the ring.
static func activate(it: Dictionary, w: PlayerWeapon) -> Dictionary:
	if w == null:
		return {}
	var id: StringName = it["id"]
	match StringName(it.get("type", &"class")):
		&"weapon":
			w.switch_to(id)
			return {}
		&"page":
			return {"tab": it["tab"], "page": int(it["page"])}
		&"tab":
			var cur := w.current
			var ids := tab_ids(id, cur)
			if id == RECENT and not ids.is_empty():
				w.switch_to(ids[0])
			return {"tab": id, "page": 0} if ids.size() > 1 or id == FAV else {}
		_:
			var owned := WeaponDefs.owned_in_class(id)
			var had_it := WeaponDefs.class_of(w.current) == id
			if not had_it:
				w.switch_to(weapon_for(id))
			if owned.size() > 1:
				return {"tab": id, "page": ring_page_of(id, w.current if had_it else weapon_for(id))}
			if had_it:
				w.switch_to(next_in_class(id, w.current))
			return {}
