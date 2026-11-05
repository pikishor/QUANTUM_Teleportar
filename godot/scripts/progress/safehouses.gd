class_name Safehouses
extends RefCounted
## Four unlockable safehouses (LOFT, DEPOT, PENTHOUSE, BUNKER), bought with credits (Economy.SAFEHOUSE_PRICE, sector gated) or claimed free once their EARN goal is met. State lives on Progress
## (`safehouses_owned`, `safehouse_lv`, `safehouse_save`; the optional [safehouse] save section, older saves have none). An owned house offers, from the pause menu SAFEHOUSE screen
## (scripts/ui/safehouse_screen.gd): the WARDROBE (look screen), the weapon BENCH (loadout), GARAGE (the garage screen), a fast SAVE point (also a HOME marker on the map), REST (heal, pick the
## time of day), the TROPHY wall (achievements and shards) and three upgrades (BED, LOCKER, BENCH, two levels each) whose levels grant cosmetics and attachment parts. GO moves the hero to the door.
## Pure rules and a few world calls; the interior of each house is an existing interior kind (`room`), entered through the screen, not a door in the city.

const IDS: Array[StringName] = SafehouseData.IDS
const UPS: Array[StringName] = SafehouseData.UPS
const MAX_LEVEL := SafehouseData.MAX_LEVEL
const DEFS := {
	&"loft": {"title": "LOFT", "room": &"apartment", "pos": Vector2(-160.0, -80.0), "brief": "A rooftop flat on the north-west blocks.", "earn": "contracts", "goal": 3, "earn_text": "FINISH 3 CONTRACTS",
		"locker": ["suit:stealth", "scheme:1"], "bench": [&"reddot", &"suppressor"]},
	&"depot": {"title": "DEPOT", "room": &"warehouse", "pos": Vector2(160.0, -240.0), "brief": "A freight depot with room for a car.", "earn": "sides", "goal": 5, "earn_text": "FINISH 5 SIDE JOBS",
		"locker": ["scheme:3", "scheme:6"], "bench": [&"scope", &"compensator"]},
	&"penthouse": {"title": "PENTHOUSE", "room": &"lobby", "pos": Vector2(80.0, 80.0), "brief": "The top floor of an office tower.", "earn": "bosses", "goal": 3, "earn_text": "DEFEAT 3 OVERSEERS",
		"locker": ["scheme:7", "accent"], "bench": [&"halo", &"longbarrel"]},
	&"bunker": {"title": "BUNKER", "room": &"control_room", "pos": Vector2(-240.0, 160.0), "brief": "A sealed control room under the south-west slums.", "earn": "heists", "goal": 3, "earn_text": "FINISH 3 HEISTS",
		"locker": ["scheme:4", "scheme:5"], "bench": [&"overcharge", &"rapid"]},
}
const UP_TITLE := {&"bed": "BED", &"locker": "LOCKER", &"bench": "BENCH"}
const UP_NOTE := {&"bed": "REST CLEARS HEAT, THEN RESTORES ENERGY", &"locker": "UNLOCKS LOOK ITEMS", &"bench": "UNLOCKS WEAPON PARTS"}
const REST_HOURS: Array[float] = [6.5, 12.0, 18.5, 22.0]
const REST_NAMES: Array[String] = ["DAWN", "NOON", "DUSK", "NIGHT"]
const TRAVEL_MIN := 2.0              ## metres: GO moves the hero only when he is farther than this from the door

static var rest_to := 0              ## index into REST_HOURS (the TIME button of the screen)
static var sel: StringName = &"loft"
static var last_rest := ""           ## status line of the last REST / SAVE / GO (what the screen shows under the buttons)


static func title(id: StringName) -> String:
	return String(DEFS[id]["title"]) if DEFS.has(id) else "SAFEHOUSE"


static func door_pos(id: StringName) -> Vector3:
	var v: Vector2 = DEFS[id]["pos"]
	return Vector3(v.x, 0.0, v.y)


static func is_owned(prog: Progress, id: StringName) -> bool:
	return prog != null and prog.safehouses_owned.has(id)


static func owned_count(prog: Progress) -> int:
	return prog.safehouses_owned.size() if prog != null else 0


static func level(prog: Progress, id: StringName, up: StringName) -> int:
	return clampi(int(prog.safehouse_lv.get("%s:%s" % [id, up], 0)), 0, MAX_LEVEL) if prog != null else 0


## Price of the next level of an upgrade (-1 at the top).
static func up_price(prog: Progress, id: StringName, up: StringName) -> int:
	var lv := level(prog, id, up)
	return -1 if lv >= MAX_LEVEL else int(Economy.SAFEHOUSE_UPGRADE[up]) * (lv + 1)


static func chapter_ok(prog: Progress, id: StringName) -> bool:
	return prog != null and prog.unlocked - 1 >= int(Economy.SAFEHOUSE_CHAPTER[id])


## [done, goal] of a house's EARN goal.
static func earn_progress(prog: Progress, id: StringName) -> Vector2i:
	var goal := int(DEFS[id]["goal"])
	if prog == null:
		return Vector2i(0, goal)
	var n := 0
	match String(DEFS[id]["earn"]):
		"contracts": n = prog.contracts_done
		"sides": n = _sum(prog.side_done)
		"bosses": n = prog.bosses_cleared.size()
		"heists": n = _sum(prog.heist_done)
	return Vector2i(mini(n, goal), goal)


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


static func earned(prog: Progress, id: StringName) -> bool:
	var e := earn_progress(prog, id)
	return e.x >= e.y


static func can_buy(prog: Progress, id: StringName) -> bool:
	return prog != null and DEFS.has(id) and not is_owned(prog, id) and chapter_ok(prog, id) and prog.credits >= int(Economy.SAFEHOUSE_PRICE[id])


static func buy(prog: Progress, id: StringName) -> bool:
	if not can_buy(prog, id) or not prog.spend(int(Economy.SAFEHOUSE_PRICE[id])):
		return false
	_own(prog, id)
	return true


## Free claim once the EARN goal is met (the sector gate does not apply: the work is the price).
static func claim(prog: Progress, id: StringName) -> bool:
	if prog == null or not DEFS.has(id) or is_owned(prog, id) or not earned(prog, id):
		return false
	_own(prog, id)
	return true


static func _own(prog: Progress, id: StringName) -> void:
	prog.safehouses_owned.append(id)
	prog.changed.emit()
	if prog.autosave_enabled:
		prog.save_file()


static func can_upgrade(prog: Progress, id: StringName, up: StringName) -> bool:
	var pr := up_price(prog, id, up)
	return is_owned(prog, id) and UPS.has(up) and pr > 0 and prog.credits >= pr


static func upgrade(prog: Progress, id: StringName, up: StringName) -> bool:
	if not can_upgrade(prog, id, up) or not prog.spend(up_price(prog, id, up)):
		return false
	var lv := level(prog, id, up) + 1
	prog.safehouse_lv["%s:%s" % [id, up]] = lv
	if up == &"locker":
		prog.hero.grant(String((DEFS[id]["locker"] as Array)[lv - 1]))
	elif up == &"bench":
		Attachments.give((DEFS[id]["bench"] as Array)[lv - 1] as StringName)
	prog.changed.emit()
	if prog.autosave_enabled:
		prog.save_file()
	return true


## REST: full health, the time of day set to REST_HOURS[rest_to]; BED 1 clears the heat, BED 2 also restores energy. False without the hero or the house.
static func rest(prog: Progress, id: StringName) -> bool:
	var p := Game.player as Player
	if not is_owned(prog, id) or p == null or not is_instance_valid(p):
		return false
	p.hp = p.max_hp
	var bed := level(prog, id, &"bed")
	if bed >= 1:
		Game.heat = 0.0
	if bed >= 2:
		p.energy = p.max_energy
	var dn: Variant = Game.world.get("day_night") if is_instance_valid(Game.world) else null
	if dn is DayNight:
		(dn as DayNight).set_hour(REST_HOURS[rest_to])
	last_rest = "RESTED  %s" % REST_NAMES[rest_to]
	Game.say(last_rest, 1.6)
	return true


static func cycle_time() -> void:
	rest_to = (rest_to + 1) % REST_HOURS.size()


## The fast-save point: writes the save file now and remembers the house (the map's HOME marker is highlighted there).
static func fast_save(prog: Progress, id: StringName) -> bool:
	if not is_owned(prog, id):
		return false
	prog.safehouse_save = id
	var ok := prog.save_file()
	last_rest = "SAVED" if ok else "SAVE FAILED"
	Game.say(last_rest, 1.4)
	return ok


## GO: moves the hero to the house's door on the street (not from a vehicle or a room).
static func travel(prog: Progress, id: StringName) -> bool:
	var p := Game.player as Player
	if not is_owned(prog, id) or p == null or p.get(&"vehicle") != null or InteriorGameplay.active:
		return false
	p.teleport_to(PlayerUtil.nearest_street(door_pos(id)) + Vector3(0.0, 0.1, 0.0))
	last_rest = "ARRIVED  %s" % title(id)
	Game.say(last_rest, 1.4)
	return true


## Owned doors for the map: [{id, pos}].
static func markers(prog: Progress) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if prog == null:
		return out
	for id: StringName in IDS:
		if prog.safehouses_owned.has(id):
			out.append({"id": id, "pos": door_pos(id)})
	return out


## Trophy wall line: achievements and shards (collected / total).
static func trophy_text(prog: Progress) -> String:
	if prog == null:
		return ""
	return "ACHIEVEMENTS %d/%d   SHARDS %d/%d" % [prog.achievements.unlocked_count(), Achievements.count(), prog.collectibles.count(), Collectibles.spots().size()]


## DEMO: every house owned and fully upgraded.
static func grant_all(prog: Progress) -> void:
	for id: StringName in IDS:
		if not prog.safehouses_owned.has(id):
			prog.safehouses_owned.append(id)
		for up in UPS:
			for lv in MAX_LEVEL:
				prog.credits += maxi(0, up_price(prog, id, up))
				upgrade(prog, id, up)
