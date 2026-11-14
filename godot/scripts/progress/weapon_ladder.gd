class_name WeaponLadder
extends RefCounted
## The weapon unlock ladder: the seven starters are owned from the first minute (WeaponDefs.STARTERS), every other weapon has ONE free route and can always be bought in the shop too.
## There is always a visible NEXT weapon (`next_target()`): the first unowned entry of LADDER, shown on the weapon wheel, the loadout and the pause screen with how to get it.
## Routes: crate (a weapon crate on the map, scripts/freedom/weapon_crates.gd), mission (the weapon is the reward of finishing a campaign chapter), boss (the Overseer drop, Contracts),
## drop (fallen enemies of one type carry it, only while it is the NEXT weapon), shop (credits). Pure data and rules, no scene tree.

const CRATE := &"crate"
const MISSION := &"mission"
const BOSS := &"boss"
const DROP := &"drop"
const SHOP := &"shop"

## id, route, arg: crate = index into CRATES, mission = chapter index (0 = chapter 1), boss = sector number, drop = enemy type, shop = (price from Economy)
const LADDER0: Array[Dictionary] = [
	{"id": &"marksman", "route": CRATE, "arg": 0},
	{"id": &"burst", "route": DROP, "arg": &"operative"},
	{"id": &"mpistol", "route": DROP, "arg": &"flanker"},
	{"id": &"revolver", "route": MISSION, "arg": 0},
	{"id": &"breacher", "route": CRATE, "arg": 1},
	{"id": &"stun", "route": DROP, "arg": &"shield"},
	{"id": &"akimbo", "route": SHOP, "arg": 0},
	{"id": &"arc", "route": MISSION, "arg": 1},
	{"id": &"bat", "route": DROP, "arg": &"brute"},
	{"id": &"whip", "route": DROP, "arg": &"striker"},
	{"id": &"ranger", "route": CRATE, "arg": 12},
	{"id": &"vector", "route": SHOP, "arg": 0},
	{"id": &"swarm", "route": DROP, "arg": &"flanker"},
	{"id": &"magnum", "route": CRATE, "arg": 13},
	{"id": &"battle", "route": CRATE, "arg": 3},
	{"id": &"sawn", "route": CRATE, "arg": 4},
	{"id": &"auto", "route": MISSION, "arg": 2},
	{"id": &"bullpup", "route": MISSION, "arg": 3},
	{"id": &"dmr", "route": CRATE, "arg": 5},
	{"id": &"xbow", "route": CRATE, "arg": 14},
	{"id": &"bolt", "route": MISSION, "arg": 4},
	{"id": &"lmg", "route": MISSION, "arg": 5},
	{"id": &"knife", "route": DROP, "arg": &"sentinel"},
	{"id": &"flame", "route": DROP, "arg": &"striker"},
	{"id": &"lance", "route": BOSS, "arg": 3},
	{"id": &"katana", "route": MISSION, "arg": 6},
	{"id": &"qblink", "route": CRATE, "arg": 15},
	{"id": &"qsuper", "route": CRATE, "arg": 16},
	{"id": &"minigun", "route": DROP, "arg": &"heavy"},
	{"id": &"qlink", "route": MISSION, "arg": 7},
	{"id": &"rocket", "route": CRATE, "arg": 2},
	{"id": &"amr", "route": MISSION, "arg": 8},
	{"id": &"qstasis", "route": DROP, "arg": &"sniper"},
	{"id": &"qphase", "route": MISSION, "arg": 9},
	{"id": &"grenade", "route": BOSS, "arg": 6},
	{"id": &"qcollapse", "route": MISSION, "arg": 11},
	# wave 108: the energy family and the destructive heavies, from light to heavy (crates 17..24 are new, chapter 11 and the shop carry one each, enemy drops the rest)
	{"id": &"tknife", "route": DROP, "arg": &"sentinel"},
	{"id": &"eplasma", "route": CRATE, "arg": 17},
	{"id": &"erepeat", "route": DROP, "arg": &"flanker"},
	{"id": &"espike", "route": CRATE, "arg": 18},
	{"id": &"eblade", "route": MISSION, "arg": 10},
	{"id": &"napalm", "route": CRATE, "arg": 19},
	{"id": &"epod", "route": SHOP, "arg": 0},
	{"id": &"seeker", "route": CRATE, "arg": 20},
	{"id": &"chaingun", "route": DROP, "arg": &"heavy"},
	{"id": &"cmissile", "route": CRATE, "arg": 21},
	{"id": &"ebeam", "route": CRATE, "arg": 22},
	{"id": &"emaul", "route": DROP, "arg": &"brute"},
	{"id": &"railgun", "route": CRATE, "arg": 23},
	{"id": &"sing", "route": SHOP, "arg": 0},
	{"id": &"orbital", "route": CRATE, "arg": 24},
]

## Weapon crates (the first six carry a weapon) and ammo crates: junction (gi, gj) of the road grid, corner sign (+1 / -1 each axis: the sidewalk corner of the junction), a name.
const CRATE_CORNER := 11.5
const CRATES0: Array[Dictionary] = [
	{"g": Vector2i(7, 9), "sx": 1.0, "sz": 1.0, "weapon": &"marksman", "name": "MARKET CRATE"},
	{"g": Vector2i(10, 7), "sx": -1.0, "sz": 1.0, "weapon": &"breacher", "name": "TOWERS CRATE"},
	{"g": Vector2i(13, 4), "sx": 1.0, "sz": -1.0, "weapon": &"rocket", "name": "FOUNDRY CRATE"},
	{"g": Vector2i(6, 6), "sx": -1.0, "sz": -1.0, "weapon": &"battle", "name": "PLAZA CRATE"},
	{"g": Vector2i(10, 10), "sx": 1.0, "sz": -1.0, "weapon": &"sawn", "name": "DOCKS CRATE"},
	{"g": Vector2i(5, 11), "sx": -1.0, "sz": 1.0, "weapon": &"dmr", "name": "ARCH CRATE"},
	{"g": Vector2i(11, 5), "sx": 1.0, "sz": 1.0, "weapon": &"", "name": "AMMO CRATE"},
	{"g": Vector2i(8, 13), "sx": -1.0, "sz": -1.0, "weapon": &"", "name": "AMMO CRATE"},
	{"g": Vector2i(8, 3), "sx": 1.0, "sz": 1.0, "weapon": &"", "name": "AMMO CRATE"},
	{"g": Vector2i(3, 8), "sx": -1.0, "sz": 1.0, "weapon": &"", "name": "AMMO CRATE"},
	{"g": Vector2i(13, 9), "sx": 1.0, "sz": -1.0, "weapon": &"", "name": "AMMO CRATE"},
	{"g": Vector2i(4, 4), "sx": 1.0, "sz": 1.0, "weapon": &"", "name": "AMMO CRATE"},
	{"g": Vector2i(6, 8), "sx": 1.0, "sz": 1.0, "weapon": &"ranger", "name": "RIVER CRATE"},
	{"g": Vector2i(9, 12), "sx": -1.0, "sz": -1.0, "weapon": &"magnum", "name": "CORNER CRATE"},
	{"g": Vector2i(12, 6), "sx": -1.0, "sz": 1.0, "weapon": &"xbow", "name": "ROOFTOP CRATE"},
	{"g": Vector2i(4, 10), "sx": 1.0, "sz": -1.0, "weapon": &"qblink", "name": "RIFT CRATE"},
	{"g": Vector2i(12, 11), "sx": 1.0, "sz": 1.0, "weapon": &"qsuper", "name": "ECHO CRATE"},
	{"g": Vector2i(5, 6), "sx": 1.0, "sz": 1.0, "weapon": &"eplasma", "name": "PLASMA CRATE"},
	{"g": Vector2i(7, 4), "sx": -1.0, "sz": 1.0, "weapon": &"espike", "name": "CRYSTAL CRATE"},
	{"g": Vector2i(8, 7), "sx": 1.0, "sz": -1.0, "weapon": &"napalm", "name": "BURN CRATE"},
	{"g": Vector2i(11, 8), "sx": -1.0, "sz": -1.0, "weapon": &"seeker", "name": "HANGAR CRATE"},
	{"g": Vector2i(9, 5), "sx": 1.0, "sz": 1.0, "weapon": &"cmissile", "name": "CONVOY CRATE"},
	{"g": Vector2i(6, 12), "sx": 1.0, "sz": 1.0, "weapon": &"ebeam", "name": "RIDGE CRATE"},
	{"g": Vector2i(12, 9), "sx": -1.0, "sz": -1.0, "weapon": &"railgun", "name": "VAULT CRATE"},
	{"g": Vector2i(10, 12), "sx": 1.0, "sz": 1.0, "weapon": &"orbital", "name": "ORBITAL CRATE"},
]

## The ladder and the crates of the roster packs are appended (WeaponDefs.PACKS, rows from scripts/player/weapon_defs_v3.gd). A pack ladder row may name its crate by `"crate": key` (the `key` of
## one of its crates) instead of an index, so indices of other packs never matter; crates may carry `"pos": Vector3` (world x, y, z) for the outskirts instead of a city junction.
static var CRATES: Array[Dictionary] = _crates_all()
static var LADDER: Array[Dictionary] = _ladder_all()


static func _crates_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = CRATES0.duplicate()
	for c in WeaponDefs.pack_array("crates"):
		out.append(c)
	return out


static func _ladder_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = LADDER0.duplicate()
	for row in WeaponDefs.pack_array("ladder"):
		var r: Dictionary = (row as Dictionary).duplicate()
		if r.has("crate"):
			for i in CRATES.size():
				if String(CRATES[i].get("key", "")) == String(r["crate"]):
					r["arg"] = i
		out.append(r)
	return out
const AMMO_RESTOCK := 0.6                ## share of every limited weapon's base reserve an ammo crate returns
const CRATE_RESPAWN := 300.0             ## seconds until an opened crate gives ammo again
const DROP_CHANCE := 0.4                 ## chance that a fallen enemy of the NEXT weapon's drop type carries it
const CRATE_RADIUS := 2.6


static func crate_pos(i: int) -> Vector3:
	var c: Dictionary = CRATES[i]
	if c.has("site"):                                                     # a secret cache beside a place of the outskirts (world position once the sites are built, cached)
		if _site_pos.has(i):
			return _site_pos[i]
		var s := OutskirtsSites.by_id(StringName(c["site"]))
		if s.is_empty():
			return Vector3(0.0, -1000.0, 0.0)
		var o: Vector2 = c.get("off", Vector2.ZERO)
		var at := OutskirtsSites.to_world(s, Vector3(o.x, 0.0, o.y))
		if is_instance_valid(Game.world) and Game.world.has_method(&"ground_height"):
			at.y = float(Game.world.call(&"ground_height", at.x, at.z))
		_site_pos[i] = at
		return at
	if c.has("pos"):
		var pp: Vector2 = c["pos"]
		return Vector3(pp.x, 0.0, pp.y)
	var g: Vector2i = c["g"]
	return Vector3(CityLayout.road_center(g.x + CityLayout.SHIFT) + float(c["sx"]) * CRATE_CORNER, 0.0, CityLayout.road_center(g.y + CityLayout.SHIFT) + float(c["sz"]) * CRATE_CORNER)


static var _site_pos := {}


## False for a secret cache whose place of the outskirts is not built yet (the crate stays hidden and shut).
static func crate_known(i: int) -> bool:
	var c: Dictionary = CRATES[i]
	return not c.has("site") or _site_pos.has(i) or not OutskirtsSites.by_id(StringName(c["site"])).is_empty()




static func entry(id: StringName) -> Dictionary:
	for e: Dictionary in LADDER:
		if e["id"] == id:
			return e
	return {}


## The first weapon of the ladder the hero does not own yet (&"" when he owns them all).
static func next_target() -> StringName:
	for e: Dictionary in LADDER:
		if not WeaponDefs.is_unlocked(e["id"]):
			return e["id"]
	return &""


static func owned_count() -> int:
	return WeaponDefs.unlocked.size()


## How to get `id` for free, in a few plain words ("CRATE  MARKET CRATE", "FINISH CHAPTER 1", "BOSS  SECTOR 3", "ENEMY DROP  HEAVY", "BUY  400").
static func route_text(id: StringName) -> String:
	var e := entry(id)
	if e.is_empty():
		return "OWNED" if WeaponDefs.is_unlocked(id) else "BUY  %d" % WeaponDefs.price(id)
	match StringName(e["route"]):
		CRATE:
			return "CRATE  %s" % String(CRATES[int(e["arg"])]["name"])
		MISSION:
			return "FINISH CHAPTER %d" % (int(e["arg"]) + 1)
		BOSS:
			return "BOSS  SECTOR %d" % int(e["arg"])
		DROP:
			return "ENEMY DROP  %s" % String(e["arg"]).to_upper()
	return "BUY  %d" % WeaponDefs.price(id)


## The line the HUD shows for the next weapon: "NEXT  SPIKE REVOLVER  FINISH CHAPTER 1  OR BUY 2100" (empty when everything is owned).
static func next_line() -> String:
	var id := next_target()
	if id == &"":
		return ""
	var e := entry(id)
	var line := "NEXT  %s  %s" % [WeaponDefs.title(id), route_text(id)]
	if not e.is_empty() and StringName(e["route"]) != SHOP:
		line += "  OR BUY %d" % WeaponDefs.price(id)
	return line


## The weapon a fallen enemy of `type` leaves, &"" for nothing: the NEXT weapon when it is a drop of this type (DROP_CHANCE), else ammo for the weapon in hand (always when it is dry),
## else a random owned limited weapon. `r1`, `r2` are 0..1 rolls (tests pass fixed ones). `cur` / `cur_reserve` describe the weapon in hand.
static func enemy_drop(type: StringName, r1: float, r2: float, cur: StringName, cur_reserve: int) -> StringName:
	var nx := next_target()
	if nx != &"":
		var e := entry(nx)
		if not e.is_empty() and StringName(e["route"]) == DROP and StringName(e["arg"]) == type and r1 < DROP_CHANCE:
			return nx
	if r1 > 1.0 - MissionRewards.MOD_DROP_CHANCE and cur_reserve != 0:          # a few drops are a weapon mod the hero does not own yet (picked up like a weapon, scripts/progress/mission_rewards.gd)
		var mod := MissionRewards.next_unowned_mod()
		if mod != &"":
			return StringName(MissionRewards.MOD_PREFIX + String(mod))
	if cur_reserve == 0:
		return cur
	var pool: Array[StringName] = []
	for id: StringName in WeaponDefs.IDS:
		if WeaponDefs.is_unlocked(id) and int(WeaponDefs.def(id)["reserve"]) > 0 and WeaponDefs.def(id)["kind"] != "melee":
			pool.append(id)
	if pool.is_empty():
		return &""
	if cur_reserve > 0 and r2 < 0.5:
		return cur
	return pool[mini(int(r2 * float(pool.size())), pool.size() - 1)]


## A campaign chapter (0 based) was finished: grant its ladder weapon. Returns the id granted or &"".
static func on_chapter_done(chapter: int) -> StringName:
	for e: Dictionary in LADDER:
		if StringName(e["route"]) == MISSION and int(e["arg"]) == chapter and not WeaponDefs.is_unlocked(e["id"]):
			var prog := Game.progress as Progress
			if prog != null and prog.grant_weapon(e["id"]):
				Game.say("NEW WEAPON  %s" % WeaponDefs.title(e["id"]), 3.0)
				return e["id"]
	return &""
