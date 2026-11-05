class_name Economy
extends RefCounted
## The single economy table: every credit reward, shop price and consumable cost in the game lives here and every system reads it
## (Upgrades, WeaponDefs, Attachments, Garage, HeroLook, ContractTypes, SideMissions, InteriorData, CityEvents, Activities, Collectibles).
## Pacing targets (checked by tests/test_economy.gd, printed by tools/economy_sim.sh):
##   - the first weapon upgrade is affordable within FIRST_UPGRADE_MINUTES of play,
##   - the whole upgrade tree (every shop upgrade, weapon, attachment, garage level, suit) takes about FULL_TREE_HOURS.
## Gear prices go through PRICE_SCALE, the one knob for "how long is the grind"; rewards are listed at their final values.

const FIRST_UPGRADE_MINUTES := 10.0
const FULL_TREE_HOURS := 10.0
const PRICE_SCALE := 2.8

## Shop upgrade base price (Upgrades.cost multiplies by 1 + 0.8 * level).
const UPGRADE_BASE := {&"damage": 240, &"mag": 160, &"reload": 160, &"blink": 200, &"regen": 200, &"armour": 260, &"decoy": 180}
const WEAPON_PRICE := {&"carbine": 0, &"scatter": 500, &"lance": 800, &"grenade": 650, &"burst": 400, &"rail": 950, &"flux": 600, &"gravity": 1100, &"minigun": 1400, &"akimbo": 700, &"arc": 850, &"revolver": 750, &"whip": 600, &"blade": 900}
const ATTACHMENT_PRICE := {&"reddot": 250, &"scope": 450, &"halo": 350, &"suppressor": 300, &"longbarrel": 400, &"compensator": 350, &"overcharge": 500, &"rapid": 450, &"extended": 400}
## Throwables and gadgets (Gear, scripts/combat/gear.gd): base price, scaled like the rest of the gear. The singularity frag is the free starter.
const THROW_PRICE := {&"singularity": 0, &"mine": 300, &"decoy": 220, &"shroud": 260, &"emp": 380}
const GADGET_PRICE := {&"scanner": 300, &"grapple": 520, &"drone": 700}
const GARAGE_BASE := {&"speed": 300, &"armour": 250, &"grip": 200, &"weapon": 400}   ## x (level + 1)
const GARAGE_LEVELS := 3
const SUIT_PRICE := {&"standard": 0, &"stealth": 300, &"phase": 0, &"gilded": 0}
const SCHEME_PRICE := [0, 150, 0, 150, 0, 0, 200, 250]
const ACCENT_PRICE := 250

## Ammo packs sold by vendors: id -> {rounds, price}. Services: id -> price.
const AMMO := {&"ammo_scatter": {"rounds": 12, "price": 60}, &"ammo_lance": {"rounds": 5, "price": 90}, &"ammo_grenade": {"rounds": 2, "price": 120}}
const SERVICE := {&"heal": 40, &"heal_kit": 55, &"energy": 30, &"energy_cell": 35, &"rumour": 20, &"drink": 10}

## Rewards (credits, before sector factor and reputation bonus where the system applies them).
const CONTRACT_BASE := {&"officer": 320, &"hack": 260, &"chase": 300, &"courier": 220, &"survive": 420, &"drones": 280, &"boss": 1200}
const SIDE_PAY := {&"courier": 220, &"photo": 260, &"relay": 320, &"rescue": 300, &"car_drop": 380, &"turf": 420, &"rooftop": 440, &"heist": 520, &"hunt": 600, &"smuggler": 680}
const SIDE_CHAPTER := {&"courier": 0, &"photo": 0, &"relay": 0, &"rescue": 1, &"car_drop": 1, &"turf": 2, &"rooftop": 2, &"heist": 3, &"hunt": 4, &"smuggler": 4}
const INTERIOR_REWARD := {&"safe": 320, &"hostage": 420, &"assassinate": 620, &"hack": 460}
const EVENT_REWARD := {&"ambush": 120, &"race": 150, &"rescue": 90, &"drop": 200, &"rift": 60}
const ACTIVITY_REWARD := {&"range": 3, &"parkour": 150, &"drift": 200, &"arena": 40}   ## per hit / on finish / on finish / per wave
const ARENA_CLEAR_BONUS := 100
const SHARD_REWARD := 40


# --- price lookups ------------------------------------------------------------------------------------------------------

static func scaled(v: int) -> int:
	return 0 if v <= 0 else maxi(5, int(roundf(float(v) * PRICE_SCALE / 5.0)) * 5)


static func upgrade_base(id: StringName) -> int:
	return scaled(int(UPGRADE_BASE.get(id, 0)))


static func weapon_price(id: StringName) -> int:
	return scaled(int(WEAPON_PRICE.get(id, 0)))


static func attachment_price(id: StringName) -> int:
	return scaled(int(ATTACHMENT_PRICE.get(id, 0)))


static func gear_price(id: StringName) -> int:
	return scaled(int(THROW_PRICE[id] if THROW_PRICE.has(id) else GADGET_PRICE.get(id, 0)))


static func garage_base(stat: StringName) -> int:
	return scaled(int(GARAGE_BASE.get(stat, 0)))


static func suit_price(id: StringName) -> int:
	return scaled(int(SUIT_PRICE.get(id, 0)))


static func scheme_price(i: int) -> int:
	return scaled(int(SCHEME_PRICE[i])) if i >= 0 and i < SCHEME_PRICE.size() else -1


static func accent_price() -> int:
	return scaled(ACCENT_PRICE)


static func ammo_price(id: StringName) -> int:
	return int(AMMO[id]["price"]) if AMMO.has(id) else 0


static func service_price(id: StringName) -> int:
	return int(SERVICE.get(id, 0))


# --- shop item list and curves ------------------------------------------------------------------------------------------

## Every credit sink of the gear tree at neutral reputation: [{name, price}], in the order a player would buy them (cheapest first within the tree).
static func gear_items() -> Array:
	var out: Array = []
	for id: StringName in UPGRADE_BASE:
		for lvl in Upgrades.MAX_LEVEL:
			out.append({"name": "%s %d" % [id, lvl + 1], "price": Upgrades.cost(id, lvl)})
	for id: StringName in WEAPON_PRICE:
		if weapon_price(id) > 0:
			out.append({"name": "weapon %s" % id, "price": weapon_price(id)})
	for id: StringName in ATTACHMENT_PRICE:
		out.append({"name": "part %s" % id, "price": attachment_price(id)})
	for id: StringName in Gear.THROW_IDS + Gear.GADGET_IDS:
		if gear_price(id) > 0:
			out.append({"name": "gear %s" % id, "price": gear_price(id)})
	for stat: StringName in GARAGE_BASE:
		for lvl in GARAGE_LEVELS:
			out.append({"name": "car %s %d" % [stat, lvl + 1], "price": garage_base(stat) * (lvl + 1)})
	for id: StringName in SUIT_PRICE:
		if suit_price(id) > 0:
			out.append({"name": "suit %s" % id, "price": suit_price(id)})
	for i in SCHEME_PRICE.size():
		if scheme_price(i) > 0:
			out.append({"name": "scheme %d" % i, "price": scheme_price(i)})
	out.append({"name": "accent", "price": accent_price()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["price"]) < int(b["price"]))
	return out


static func total_gear_cost() -> int:
	var n := 0
	for it: Dictionary in gear_items():
		n += int(it["price"])
	return n


# --- the play model -----------------------------------------------------------------------------------------------------

## Typical hour of play: sector reached, how many of each activity, reputation payout bonus.
static func sector_at(hour: float) -> int:
	return clampi(int(hour * 0.9), 0, 12)


static func _rep_bonus_at(hour: float) -> float:
	return 0.0 if hour < 2.0 else (0.1 if hour < 5.0 else 0.25)


static func _avg_unlocked_side(sector: int) -> float:
	var n := 0
	var s := 0.0
	for id: StringName in SIDE_PAY:
		if sector >= int(SIDE_CHAPTER[id]):
			n += 1
			s += float(SIDE_PAY[id])
	return s / maxf(1.0, float(n))


static func _avg_contract() -> float:
	var s := 0.0
	var n := 0
	for id: StringName in CONTRACT_BASE:
		if id != &"boss":
			s += float(CONTRACT_BASE[id])
			n += 1
	return s / float(n)


static func _avg(d: Dictionary) -> float:
	var s := 0.0
	for k: StringName in d:
		s += float(d[k])
	return s / float(d.size())


## Credits earned in one hour of play at `hour` (0-based): {contracts, side, interior, events, activities, shards, campaign, sink, net}.
static func hourly_income(hour: float) -> Dictionary:
	var sec := sector_at(hour)
	var f := float(Progress.difficulty(sec)["reward"]) * (1.0 + _rep_bonus_at(hour))
	var r := {
		"contracts": 7.0 * _avg_contract() * f * 1.1,
		"side": 2.5 * _avg_unlocked_side(sec) * f * 1.1,
		"interior": 1.5 * _avg(INTERIOR_REWARD) * f,
		"events": 4.0 * 0.6 * _avg(EVENT_REWARD),
		"activities": float(ACTIVITY_REWARD[&"parkour"] + ACTIVITY_REWARD[&"drift"]) + float(ACTIVITY_REWARD[&"arena"]) * 3.0 + float(ARENA_CLEAR_BONUS) * 0.3 + 15.0 * float(ACTIVITY_REWARD[&"range"]),
		"shards": 6.0 * float(SHARD_REWARD),
		"campaign": 0.0,
	}
	# Consumables a typical hour burns: three ammo packs, two repairs, two coherence doses.
	r["sink"] = 3.0 * _avg_ammo() + 2.0 * float(SERVICE[&"heal"]) + 2.0 * float(SERVICE[&"energy"])
	var gross := 0.0
	for k: String in ["contracts", "side", "interior", "events", "activities", "shards", "campaign"]:
		gross += float(r[k])
	r["gross"] = gross
	r["net"] = gross - float(r["sink"])
	return r


static func _avg_ammo() -> float:
	var s := 0.0
	for id: StringName in AMMO:
		s += float(AMMO[id]["price"])
	return s / float(AMMO.size())


## Minutes of play until `amount` credits are banked (net of consumables), integrating hourly_income in 1-minute steps.
static func minutes_to_earn(amount: float) -> float:
	var bank := 0.0
	var m := 0
	while bank < amount and m < 60 * 200:
		bank += float(hourly_income(float(m) / 60.0)["net"]) / 60.0
		m += 1
	return float(m)


## Rows for the printout: [{hour, income_per_hour, cum_income, cum_cost_reachable}] for each hour 0..hours-1, plus the milestones.
## cum_cost_reachable = the cheapest-first gear total the banked credits could have bought by the end of that hour.
static func simulate(hours: int) -> Dictionary:
	var items := gear_items()
	var rows: Array = []
	var bank := 0.0
	var spent := 0
	var idx := 0
	for h in hours:
		bank += float(hourly_income(float(h) + 0.5)["net"])
		while idx < items.size() and spent + int(items[idx]["price"]) <= bank:
			spent += int(items[idx]["price"])
			idx += 1
		rows.append({"hour": h + 1, "income_per_hour": float(hourly_income(float(h) + 0.5)["net"]), "cum_income": bank, "cum_cost": spent, "items": idx})
	var total := total_gear_cost()
	var first := minutes_to_earn(float(Upgrades.price(&"damage", 0)))
	var full := minutes_to_earn(float(total)) / 60.0
	return {"rows": rows, "total_cost": total, "first_upgrade_minutes": first, "full_tree_hours": full, "item_count": items.size()}
