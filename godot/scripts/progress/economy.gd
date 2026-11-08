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
## The seven starters (pistol, SMG, carbine, shotgun, rail, launcher, blade) cost nothing; the rest is the unlock ladder (scripts/progress/weapon_ladder.gd), every one of them can also be bought here.
const WEAPON_PRICE := {&"carbine": 0, &"pistol": 0, &"flux": 0, &"scatter": 0, &"rail": 0, &"gravity": 0, &"blade": 0, &"marksman": 650, &"burst": 400, &"revolver": 750, &"akimbo": 700, &"breacher": 800, &"arc": 850, &"lance": 800, &"whip": 600, &"rocket": 1500, &"minigun": 1400, &"grenade": 650, &"swarm": 450, &"vector": 750, &"battle": 900, &"sawn": 600, &"auto": 800, &"bolt": 1100, &"dmr": 950, &"knife": 400}
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
const SIDE_PAY := {&"courier": 220, &"photo": 290, &"relay": 320, &"rescue": 300, &"car_drop": 380, &"turf": 420, &"rooftop": 410, &"heist": 520, &"hunt": 560, &"smuggler": 500, &"bounty": 360, &"sniper": 400, &"swarm": 460, &"car_theft": 500, &"hostage": 540, &"blackout": 540, &"data_courier": 330, &"arena": 600, &"demolition": 280, &"anomaly": 420}
const SIDE_CHAPTER := {&"courier": 0, &"photo": 0, &"relay": 0, &"rescue": 1, &"car_drop": 1, &"turf": 2, &"rooftop": 2, &"heist": 3, &"hunt": 4, &"smuggler": 4, &"bounty": 1, &"sniper": 2, &"swarm": 2, &"car_theft": 3, &"hostage": 3, &"blackout": 3, &"data_courier": 1, &"arena": 4, &"demolition": 0, &"anomaly": 2}
const INTERIOR_REWARD := {&"safe": 320, &"hostage": 420, &"assassinate": 620, &"hack": 460}
## Stealth missions (StealthScripts): base pay, sector needed, and the bonus share added for a clean run (no kills; the silent route: under par). Not part of the hourly model.
const STEALTH_PAY := {&"infiltrate": 360, &"plant": 440, &"datatheft": 520, &"takedown": 480}
const STEALTH_CHAPTER := {&"infiltrate": 0, &"plant": 1, &"datatheft": 2, &"takedown": 3}
const STEALTH_BONUS := 0.35
## Heist missions (HeistScripts): base pay, sector needed, approach pay factors (stealth / loud / quantum), the share kept on a replay. Not part of the hourly model.
const HEIST_PAY := {&"vault": 900, &"convoy": 1000, &"datacenter": 1150}
const HEIST_CHAPTER := {&"vault": 2, &"convoy": 4, &"datacenter": 6}
const HEIST_APPROACH := {&"stealth": 1.0, &"loud": 1.25, &"quantum": 1.2}
const HEIST_REPLAY := 0.6
## Safehouses (Safehouses): buy price, sector needed (index of the chapter select), and the upgrade base price (x (level + 1), two levels). Credit sinks outside the gear tree and the hourly model.
const SAFEHOUSE_PRICE := {&"loft": 2400, &"depot": 5400, &"penthouse": 9000, &"bunker": 13000}
const SAFEHOUSE_CHAPTER := {&"loft": 0, &"depot": 2, &"penthouse": 4, &"bunker": 6}
const SAFEHOUSE_UPGRADE := {&"bed": 400, &"locker": 600, &"bench": 800}
## Weapon crafting (Crafting, scripts/progress/crafting.gd): part price per unit, blueprint prices, the credit fee per crafted item and what a dismantle returns. All gear-style prices go through
## scaled(); a credit sink outside the gear tree and the hourly model. Variant blueprints cost a share of their weapon's price plus a base.
const CRAFT_PART_PRICE := {&"scrap": 40, &"alloy": 120, &"core": 400}
const CRAFT_PART_BUNDLE := {&"scrap": 5, &"alloy": 2, &"core": 1}              ## units per purchase at a vendor or the bench
const BLUEPRINT_PRICE := {&"mod_basic": 0, &"mod_arc": 500, &"mod_phase": 650, &"mod_singularity": 900}
const BLUEPRINT_VARIANT_SHARE := 0.6
const BLUEPRINT_VARIANT_BASE := 150
const CRAFT_FEE := {&"mod": 120, &"variant": 260}
const CRAFT_BOOST_CORES := 1                                                    ## extra QUANTUM CORE a BOOST costs
const CRAFT_BENCH_DISCOUNT := 0.1                                               ## fee discount per level of the best owned safehouse BENCH
const DISMANTLE_YIELD := [{&"scrap": 2}, {&"scrap": 3, &"alloy": 1}, {&"scrap": 4, &"alloy": 2}, {&"scrap": 5, &"alloy": 3, &"core": 1}]   ## per rarity: COMMON .. LEGENDARY
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


static func craft_part_price(id: StringName) -> int:
	return scaled(int(CRAFT_PART_PRICE.get(id, 0)))


static func craft_fee(kind: StringName) -> int:
	return scaled(int(CRAFT_FEE.get(kind, 0)))


## Price of a blueprint: a fixed one for the mod blueprints, a share of the weapon price (plus a base) for `var_<weapon>`; free when the weapon is free.
static func blueprint_price(bp: StringName) -> int:
	if BLUEPRINT_PRICE.has(bp):
		return scaled(int(BLUEPRINT_PRICE[bp]))
	var w := StringName(String(bp).trim_prefix("var_"))
	var wp := int(WEAPON_PRICE.get(w, 0))
	return 0 if wp <= 0 else scaled(int(float(wp) * BLUEPRINT_VARIANT_SHARE) + BLUEPRINT_VARIANT_BASE)


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
