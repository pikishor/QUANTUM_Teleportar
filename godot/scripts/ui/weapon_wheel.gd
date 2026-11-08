class_name WeaponWheel
extends RefCounted
## The WEAPON wheel of the phone HUD, grouped by class like a console shooter's: one wedge per class (PISTOL, SMG, RIFLE, SHOTGUN, SNIPER, HEAVY, MELEE), each showing the weapon you last used in that
## class and how many you own there ("PST 1/4"). Pick a wedge: you get that weapon; pick the class you are already holding: the next weapon of that class. A wheel of eighteen discs would not
## fit a phone (and would overlap), seven always does. The wheel items are RadialWheel items: id = the class, icon = the weapon drawn on the disc.


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
		out.append({"id": cls, "icon": show, "label": label, "ready": true, "active": cls == cur_cls, "cd": 0.0, "current": cls == cur_cls, "cls": cls, "owned": owned.size(), "total": WeaponDefs.in_class(cls).size(),
				"cname": String(WeaponDefs.CLASS_NAMES.get(cls, str(cls).to_upper())), "wname": String(WeaponDefs.DEFS[show].get("name", show)).to_upper()})
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
