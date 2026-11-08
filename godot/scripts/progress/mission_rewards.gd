class_name MissionRewards
extends RefCounted
## What finishing a mission gives (DESIGN.md core loop: "complete the mission, get credits, a new weapon or an upgrade, see the next mission at once").
## Every mission of the game (contract, side job, interior job, heist, stealth, chase, arena, campaign chapter) ends in `complete(kind, title)` (called by MissionRewardHook from the existing
## completion signals): a flat credit bonus, mission XP and ONE unlock from a schedule the player can see:
##   missions 1..10 (FIRST_TEN): something new EVERY mission (a weapon mod, the next weapon, an upgrade level, a weapon crate = weapon + ammo + mod),
##   later (CYCLE, six long): weapon, upgrade, mod, weapon, upgrade, crate, then again. When nothing is left to grant the reward is cash (CASH_FALLBACK).
## The weapon is always the first unowned entry of WeaponLadder.LADDER, so crates on the map and enemy drops only make the next one come sooner. `missions_to_weapon()` feeds the
## What the NEXT finished mission hands out besides credits, in two or three words for a mission card ("NEW WEAPON", "WEAPON MOD", "UPGRADE", "WEAPON CRATE"; "" when nothing is left of it).
## Director review 5, #12: nothing on a card promised a gun.
static func gift_text() -> String:
	var e := entry_for(missions_done + 1)
	match StringName(e["kind"]):
		&"weapon":
			return "NEW WEAPON" if WeaponLadder.next_target() != &"" else ""
		&"crate":
			return "WEAPON CRATE" if WeaponLadder.next_target() != &"" else ""
		&"mod":
			return "WEAPON MOD" if next_unowned_mod() != &"" else ""
		&"upgrade":
			return "UPGRADE"
	return ""


## "NEXT WEAPON IN 2 MISSIONS" line of the result card (scripts/ui/result_card.gd). Static state (like Gear / SkillTree): saved in the `[rewards]` section by Progress.
## Pure rules plus `complete`; the scene tree is only touched through Game.progress / Game.player.

const FIRST_TEN: Array[Dictionary] = [
	{"kind": &"mod", "id": &"reddot"},
	{"kind": &"weapon"},
	{"kind": &"upgrade", "id": &"damage"},
	{"kind": &"mod", "id": &"extended"},
	{"kind": &"crate"},
	{"kind": &"upgrade", "id": &"health"},
	{"kind": &"mod", "id": &"compensator"},
	{"kind": &"weapon"},
	{"kind": &"upgrade", "id": &"power"},
	{"kind": &"crate"},
]
const CYCLE: Array[Dictionary] = [
	{"kind": &"weapon"}, {"kind": &"upgrade"}, {"kind": &"mod"}, {"kind": &"weapon"}, {"kind": &"upgrade"}, {"kind": &"crate"},
]
## Weapon mods in the order they are handed out when a mission does not name one.
const MOD_ORDER: Array[StringName] = [&"reddot", &"extended", &"compensator", &"suppressor", &"scope", &"rapid", &"longbarrel", &"halo", &"overcharge"]
const MOD_FX := {&"reddot": "STEADIER AIM", &"scope": "ZOOM, STEADY AIM", &"halo": "HIP AIM, CRITS", &"suppressor": "QUIET, LESS KICK", &"longbarrel": "LONGER RANGE", &"compensator": "LESS RECOIL",
	&"overcharge": "MORE DAMAGE", &"rapid": "FASTER FIRE", &"extended": "BIGGER MAGAZINE"}
const XP_PER_MISSION := 60
const CRATE_AMMO := 0.6                     ## share of the base reserves a weapon crate restocks
const CASH_FALLBACK := 250
const MOD_DROP_CHANCE := 0.05               ## share of enemy drops that are a weapon mod while one is unowned (WeaponLadder.enemy_drop)
const MOD_PREFIX := "mod_"                  ## a weapon pickup id that carries a mod ("mod_scope")
const SCHEDULE_LOOKAHEAD := 12

static var missions_done := 0
static var new_mods: Array[StringName] = []     ## mods the hero got but has not put on yet (LOADOUT shows NEW)
static var last_result: Dictionary = {}
static var _mark := -1                          ## Progress.earned_total when the running mission started (-1 = none seen)
static var _last_end := 0                       ## Progress.earned_total at the end of the last mission


static func reset() -> void:
	missions_done = 0
	new_mods = []
	last_result = {}
	_mark = -1
	_last_end = 0


static func to_save() -> Dictionary:
	var mods := PackedStringArray()
	for m: StringName in new_mods:
		mods.append(String(m))
	return {"done": missions_done, "new_mods": mods}


static func from_save(d: Dictionary) -> void:
	reset()
	var n: Variant = d.get("done", 0)
	missions_done = clampi(int(n) if (n is int or n is float) else 0, 0, 99999)
	var raw: Variant = d.get("new_mods", [])
	if raw is Array or raw is PackedStringArray:
		for m: Variant in raw:
			var id := StringName(str(m))
			if Attachments.PARTS.has(id) and not new_mods.has(id):
				new_mods.append(id)


# --- the schedule ------------------------------------------------------------------------------------------------------

## The schedule entry of mission number `n` (1 based): {kind, id?}.
static func entry_for(n: int) -> Dictionary:
	if n >= 1 and n <= FIRST_TEN.size():
		return FIRST_TEN[n - 1]
	return CYCLE[posmod(n - FIRST_TEN.size() - 1, CYCLE.size())]


static func in_first_ten() -> bool:
	return missions_done < FIRST_TEN.size()


## Missions until the next WEAPON (or weapon crate) reward counted from now (1 = the very next mission), -1 when the hero owns every weapon.
static func missions_to_weapon(done := -1) -> int:
	if WeaponLadder.next_target() == &"":
		return -1
	var base := missions_done if done < 0 else done
	for k in range(1, SCHEDULE_LOOKAHEAD + 1):
		var kind := StringName(entry_for(base + k)["kind"])
		if kind == &"weapon" or kind == &"crate":
			return k
	return -1


## "NEXT WEAPON IN 2 MISSIONS  PHASE MARKSMAN" ("" when everything is owned).
static func next_weapon_line() -> String:
	var k := missions_to_weapon()
	var id := WeaponLadder.next_target()
	if k < 0 or id == &"":
		return ""
	return "NEXT WEAPON  %s  %s" % [WeaponDefs.title(id), "IN 1 MISSION" if k == 1 else "IN %d MISSIONS" % k]


## The first mod of MOD_ORDER the hero does not own (&"" when he owns all nine).
static func next_unowned_mod() -> StringName:
	for m: StringName in MOD_ORDER:
		if not Attachments.is_owned(m):
			return m
	return &""


static func is_new(part: StringName) -> bool:
	return new_mods.has(part)


static func clear_new(part: StringName) -> void:
	new_mods.erase(part)


## The cheapest upgrade of the flat list that is not at its top level: {id, price, credits, affordable}, {} when everything is maxed.
static func upgrade_hint() -> Dictionary:
	var prog := Game.progress as Progress
	if prog == null:
		return {}
	var best := &""
	var best_price := 1 << 30
	for id: StringName in Upgrades.SIMPLE:
		if prog.level(id) >= Upgrades.MAX_LEVEL:
			continue
		var pr := prog.price(id)
		if pr < best_price:
			best_price = pr
			best = id
	if best == &"":
		return {}
	return {"id": best, "level": prog.level(best) + 1, "price": best_price, "credits": prog.credits, "affordable": prog.credits >= best_price}


## The flat credit bonus of a mission of this kind in this sector.
static func bonus_for(kind: StringName, sector: int) -> int:
	return Economy.mission_bonus(kind, sector)


# --- granting ----------------------------------------------------------------------------------------------------------------

## Remember where the wallet stood when a mission began (the card shows what the mission earned).
static func mark_start() -> void:
	var prog := Game.progress as Progress
	_mark = prog.earned_total if prog != null else -1


## Grant a weapon mod. The loadout flags it NEW until it is equipped. Returns false when it is already owned or unknown.
static func grant_mod(part: StringName) -> bool:
	if not Attachments.give(part):
		return false
	if not new_mods.has(part):
		new_mods.append(part)
	var prog := Game.progress as Progress
	if prog != null:
		prog.changed.emit()
		prog.soft_save()
	return true


## A weapon pickup id that carries a mod ("mod_scope" -> &"scope"), &"" for any other id.
static func mod_of_pickup(id: StringName) -> StringName:
	var s := String(id)
	if s.begins_with(MOD_PREFIX):
		var part := StringName(s.substr(MOD_PREFIX.length()))
		if Attachments.PARTS.has(part):
			return part
	return &""


## Put the mod on the weapon in hand (the card's EQUIP button, one tap). Returns true when it sits there afterwards.
static func equip_now(part: StringName) -> bool:
	var prog := Game.progress as Progress
	var w := WeaponDefs.last_used
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
		w = (pl.get(&"weapon") as PlayerWeapon).current
	if not Attachments.is_owned(part):
		return false
	if Attachments.part_in(w, Attachments.slot_of(part)) != part:
		if prog != null:
			prog.equip_part(w, part)
		else:
			Attachments.equip(w, part)
	clear_new(part)
	return Attachments.part_in(w, Attachments.slot_of(part)) == part


## Finish a mission: bonus credits, XP, the scheduled unlock. Returns the result dictionary (also `last_result`, and `Progress.mission_result` is emitted).
static func complete(kind: StringName, title: String) -> Dictionary:
	var prog := Game.progress as Progress
	if prog == null:
		return {}
	missions_done += 1
	var n := missions_done
	var sector := int(Game.story.get("chapter")) if is_instance_valid(Game.story) and Game.story.get("chapter") != null else 0
	var bonus := bonus_for(kind, sector)
	if bonus > 0:
		prog.add_credits(bonus)
	var lv_before := SkillTree.level()
	SkillTree.add_xp(XP_PER_MISSION)
	var reward := _grant(entry_for(n))
	var start_mark := _mark if _mark >= 0 else _last_end
	var earned := maxi(bonus, prog.earned_total - start_mark)
	_mark = -1
	_last_end = prog.earned_total
	var lp := SkillTree.level_progress()
	var result := {
		"n": n, "kind": kind, "title": title, "credits": earned, "bonus": bonus, "xp": XP_PER_MISSION,
		"level": SkillTree.level(), "level_up": SkillTree.level() > lv_before, "xp_have": int(lp[0]), "xp_need": int(lp[1]),
		"reward": reward, "weapon_line": next_weapon_line(), "weapon_in": missions_to_weapon(), "weapon_next": WeaponLadder.next_target(),
		"first_ten": n <= FIRST_TEN.size(), "ladder": ladder_rows(), "upgrade": upgrade_hint(),
	}
	last_result = result
	prog.mission_result.emit(result)
	prog.changed.emit()
	prog.soft_save()
	return result


static func _grant(e: Dictionary) -> Dictionary:
	var prog := Game.progress as Progress
	var kind := StringName(e["kind"])
	match kind:
		&"weapon", &"crate":
			var w := WeaponLadder.next_target()
			if w != &"" and prog.grant_weapon(w):
				var out := {"kind": &"weapon" if kind == &"weapon" else &"crate", "id": w, "title": WeaponDefs.title(w), "sub": "%s  READY IN LOADOUT" % String(WeaponDefs.CLASS_OF.get(w, &"weapon")).to_upper()}
				if kind == &"crate":
					var pl := Game.player
					if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
						(pl.get(&"weapon") as PlayerWeapon).restock(CRATE_AMMO)
					var m := next_unowned_mod()
					if m != &"" and grant_mod(m):
						out["extra"] = m
						out["sub"] = "+ AMMO"
				return out
		&"mod":
			var m := StringName(e.get("id", &""))
			if m == &"" or Attachments.is_owned(m):
				m = next_unowned_mod()
			if m != &"" and grant_mod(m):
				return {"kind": &"mod", "id": m, "title": String(Attachments.PARTS[m]["name"]), "sub": String(MOD_FX.get(m, "")), "new": true}
		&"upgrade":
			var u := StringName(e.get("id", &""))
			if u == &"" or prog.level(u) >= Upgrades.MAX_LEVEL:
				u = _cheapest_open_upgrade()
			if u != &"" and prog.grant_upgrade(u) == u:
				return {"kind": &"upgrade", "id": u, "title": "%s %d" % [Upgrades.title(u), prog.level(u)], "sub": Upgrades.effect_text(u, prog.level(u) - 1).split(">")[-1].strip_edges()}
	# nothing left of that kind: cash
	prog.add_credits(CASH_FALLBACK)
	return {"kind": &"cash", "id": &"", "title": "+%d CREDITS" % CASH_FALLBACK, "sub": "EVERYTHING OF THAT KIND IS OWNED"}


static func _cheapest_open_upgrade() -> StringName:
	var prog := Game.progress as Progress
	for u: StringName in Upgrades.SIMPLE:
		if prog.level(u) < Upgrades.MAX_LEVEL:
			return u
	return &""


## The schedule as the card draws it: 10 rows {n, kind, done, now} for the first ten missions, [] afterwards.
static func ladder_rows() -> Array:
	var rows: Array = []
	if missions_done > FIRST_TEN.size():
		return rows
	for i in FIRST_TEN.size():
		rows.append({"n": i + 1, "kind": StringName(FIRST_TEN[i]["kind"]), "done": i + 1 <= missions_done, "now": i + 1 == missions_done})
	return rows
