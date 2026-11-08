class_name BalanceEconomy
extends RefCounted
## Economy pacing tables for docs/BALANCE.md: side missions, stealth, heists, safehouses and crafting against the credits per hour of the model (Economy.hourly_income).
## Needs the game classes (SideMissions, HeistScripts, Crafting ...), so it runs inside the test runner (tools/economy_sim.sh, tests/test_balance2.gd).

const SIDE_RATE_BAND := Vector2(0.55, 1.9)       ## a job's credits per minute over the average credits per active minute at its unlock chapter
const HEIST_RATE_BAND := Vector2(0.8, 2.2)       ## heists carry risk and a one-off set piece
const SAFEHOUSE_HOURS := Vector2(0.4, 1.6)       ## a house costs this many hours of income at its unlock chapter
const CRAFT_HOURS_MAX := 0.5                     ## one crafted variant (blueprint excluded) costs at most this many hours at chapter 5
const START_OVERHEAD := 150.0                    ## seconds to reach a job, brief and payout
const STEALTH_SECONDS := 420.0
const HEIST_SECONDS := 600.0


## The hour of play at which sector `ch` is reached (inverse of Economy.sector_at).
static func hour_of(ch: int) -> float:
	return float(ch) / 0.9 + 0.1


## Average credits per minute of play (net of consumables) in sector `ch`.
static func per_minute(ch: int) -> float:
	return float(Economy.hourly_income(hour_of(ch))["net"]) / 60.0


static func side_minutes(mid: StringName) -> float:
	var limit := float(SideMissions.def(mid)["limit"])
	return ((limit * 0.75 if limit > 0.0 else 150.0) + START_OVERHEAD) / 60.0


## [{id, chapter, pay, minutes, per_min, rate}] for every side mission at its unlock chapter, paid with the usual time bonus half of the time.
static func side_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in SideMissions.ORDER:
		var ch := int(Economy.SIDE_CHAPTER[id])
		var pay := (float(SideMissions.reward(id, ch, 0, 1.0)) + float(SideMissions.reward(id, ch, 0, 0.0))) * 0.5
		var mins := side_minutes(id)
		out.append({"id": id, "chapter": ch, "pay": pay, "minutes": mins, "per_min": pay / mins, "rate": pay / mins / per_minute(ch)})
	return out


static func heist_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in Economy.HEIST_PAY:
		var ch := int(Economy.HEIST_CHAPTER[id])
		for ap: StringName in Economy.HEIST_APPROACH:
			var pay := float(HeistScripts.reward(id, ap, ch, 0, false))
			var mins := HEIST_SECONDS / 60.0 * (0.8 if ap == &"loud" else (1.2 if ap == &"quantum" else 1.0))
			out.append({"id": id, "approach": ap, "chapter": ch, "pay": pay, "replay": float(HeistScripts.reward(id, ap, ch, 0, true)), "minutes": mins, "rate": pay / mins / per_minute(ch)})
	return out


static func stealth_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in Economy.STEALTH_PAY:
		var ch := int(Economy.STEALTH_CHAPTER[id])
		var pay := float(StealthScripts.reward(id, ch, 0, true))
		out.append({"id": id, "chapter": ch, "pay": pay, "minutes": STEALTH_SECONDS / 60.0, "rate": pay / (STEALTH_SECONDS / 60.0) / per_minute(ch)})
	return out


## Hours of income a safehouse costs at the chapter that unlocks it, and the cost with both upgrade ladders.
static func safehouse_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in Economy.SAFEHOUSE_PRICE:
		var ch := int(Economy.SAFEHOUSE_CHAPTER[id])
		var ups := 0
		for up: StringName in Economy.SAFEHOUSE_UPGRADE:
			for l in SafehouseData.MAX_LEVEL:
				ups += int(Economy.SAFEHOUSE_UPGRADE[up]) * (l + 1)
		var price := int(Economy.SAFEHOUSE_PRICE[id])
		out.append({"id": id, "chapter": ch, "price": price, "hours": float(price) / (per_minute(ch) * 60.0), "upgrades": ups, "upgrade_hours": float(ups) / (per_minute(ch) * 60.0)})
	return out


## Credits of one craft: fee plus the parts bought at vendor prices, for a mod blueprint and for each weapon variant (blueprint price kept apart).
static func craft_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bp: StringName in Crafting.bp_ids():
		var cost := Crafting.cost_of(bp, false)
		var parts := 0.0
		for p: StringName in cost["parts"]:
			parts += float(cost["parts"][p]) * float(Economy.craft_part_price(p)) / float(Economy.CRAFT_PART_BUNDLE[p])
		var total := float(cost["credits"]) + parts
		out.append({"bp": bp, "blueprint": Economy.blueprint_price(bp), "craft": total, "hours": total / (per_minute(4) * 60.0)})
	return out


## The first ten missions and what each one unlocks, at the pacing model's missions per hour: minute reached, credits banked (net income), whether the first upgrade is affordable by then.
## Needs the game classes (MissionRewards reads WeaponLadder / Attachments), so it runs in the test runner like the rest of this file.
static func mission_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var per_mission_min := 60.0 / Economy.MISSIONS_PER_HOUR
	var first_price := float(Upgrades.price(&"damage", 0))
	var w := 0
	var mods := 0
	for i in MissionRewards.FIRST_TEN.size():
		var e := MissionRewards.entry_for(i + 1)
		var kind := StringName(e["kind"])
		var item := ""
		match kind:
			&"weapon", &"crate":
				item = WeaponDefs.title(WeaponLadder.LADDER[w]["id"])
				w += 1
				if kind == &"crate":
					item += " + MOD"
					mods += 1
			&"mod":
				item = String(Attachments.PARTS[StringName(e["id"])]["name"])
				mods += 1
			&"upgrade":
				item = "%s 1" % Upgrades.title(StringName(e["id"]))
		var minute := per_mission_min * float(i + 1)
		var banked := 0.0
		for m in int(minute):
			banked += float(Economy.hourly_income(float(m) / 60.0)["net"]) / 60.0
		out.append({"n": i + 1, "kind": kind, "item": item, "minute": minute, "banked": banked, "bonus": Economy.mission_bonus(&"contract", 0), "can_buy_first": banked >= first_price})
	return out


static func mission_lines() -> Array[String]:
	var out: Array[String] = []
	out.append("## MISSION REWARDS  the first ten missions each unlock something (%.0f missions per hour, first ten done after %.0f min); bonus per mission %d cr (contract, sector 1)" % [Economy.MISSIONS_PER_HOUR, Economy.first_ten_minutes(), Economy.mission_bonus(&"contract", 0)])
	out.append("  n  unlock                         minute  banked cr  first upgrade (%d cr)" % Upgrades.price(&"damage", 0))
	for r: Dictionary in mission_rows():
		out.append("%3d  %-28s %6.0f  %9.0f  %s" % [r["n"], "%s  %s" % [String(r["kind"]).to_upper(), r["item"]], r["minute"], r["banked"], "yes" if r["can_buy_first"] else "no"])
	var weapons_per_cycle := 0
	for e: Dictionary in MissionRewards.CYCLE:
		if e["kind"] == &"weapon" or e["kind"] == &"crate":
			weapons_per_cycle += 1
	out.append("after 10: weapon, upgrade, mod, weapon, upgrade, crate (repeating); a weapon every %.1f missions on average; free gear value of the first ten: %d cr" % [float(MissionRewards.CYCLE.size()) / float(weapons_per_cycle), Economy.unlock_value(MissionRewards.FIRST_TEN.size())])
	return out


static func lines() -> Array[String]:
	var out: Array[String] = []
	var s := Economy.simulate(14)
	out.append("## ECONOMY  gear items %d, total %d cr, first upgrade %.1f min, full tree %.1f h" % [s["item_count"], s["total_cost"], s["first_upgrade_minutes"], s["full_tree_hours"]])
	out.append("hour  sector  credits/h  cum_income  cum_cost_bought  items")
	for r: Dictionary in s["rows"]:
		out.append("%4d  %6d  %9d  %10d  %15d  %5d" % [r["hour"], Economy.sector_at(float(r["hour"]) - 0.5) + 1, r["income_per_hour"], r["cum_income"], r["cum_cost"], r["items"]])
	out.append("")
	out.append_array(mission_lines())
	out.append("")
	out.append("## SIDE MISSIONS  pay at the unlock chapter, estimated minutes, credits per minute, rate = per minute over the sector average (band %.2f-%.2f)" % [SIDE_RATE_BAND.x, SIDE_RATE_BAND.y])
	for r: Dictionary in side_rows():
		out.append("%-12s ch%2d  pay %5.0f  %4.1f min  %5.1f cr/min  rate %.2f" % [r["id"], int(r["chapter"]) + 1, r["pay"], r["minutes"], r["per_min"], r["rate"]])
	out.append("")
	out.append("## HEISTS  pay (first run / replay), minutes, rate (band %.1f-%.1f)" % [HEIST_RATE_BAND.x, HEIST_RATE_BAND.y])
	for r: Dictionary in heist_rows():
		out.append("%-10s %-8s ch%2d  pay %5.0f  replay %5.0f  %4.1f min  rate %.2f" % [r["id"], r["approach"], int(r["chapter"]) + 1, r["pay"], r["replay"], r["minutes"], r["rate"]])
	out.append("")
	out.append("## STEALTH MISSIONS  clean-run pay, rate")
	for r: Dictionary in stealth_rows():
		out.append("%-10s ch%2d  pay %5.0f  rate %.2f" % [r["id"], int(r["chapter"]) + 1, r["pay"], r["rate"]])
	out.append("")
	out.append("## SAFEHOUSES  price in hours of income at the unlock chapter (band %.1f-%.1f h), upgrades in hours" % [SAFEHOUSE_HOURS.x, SAFEHOUSE_HOURS.y])
	for r: Dictionary in safehouse_rows():
		out.append("%-10s ch%2d  %6d cr  %.2f h   upgrades %5d cr  %.2f h" % [r["id"], int(r["chapter"]) + 1, r["price"], r["hours"], r["upgrades"], r["upgrade_hours"]])
	out.append("")
	out.append("## CRAFTING  one craft (fee + parts) in credits and in hours at chapter 5, blueprint price apart (max %.1f h)" % CRAFT_HOURS_MAX)
	for r: Dictionary in craft_rows():
		out.append("%-16s blueprint %5d  craft %5.0f cr  %.2f h" % [r["bp"], r["blueprint"], r["craft"], r["hours"]])
	return out
