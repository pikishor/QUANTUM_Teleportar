extends RefCounted
## The single economy table: pacing targets, every system reads it, prices and rewards are sane.
## Run: tools/test.sh tests/test_economy.gd


func run(_host: Node) -> void:
	var s := Economy.simulate(16)
	var first: float = s["first_upgrade_minutes"]
	var full: float = s["full_tree_hours"]
	TestLib.check(first >= 4.0 and first <= Economy.FIRST_UPGRADE_MINUTES * 1.5, "first weapon upgrade within ~10 min (%.1f)" % first)
	TestLib.check(full >= Economy.FULL_TREE_HOURS * 0.7 and full <= Economy.FULL_TREE_HOURS * 1.3, "full tree takes ~10 h (%.1f)" % full)
	var prev := -1.0
	var rising := true
	for r: Dictionary in s["rows"]:
		rising = rising and float(r["cum_income"]) > prev and float(r["cum_cost"]) <= float(r["cum_income"])
		prev = float(r["cum_income"])
	TestLib.check(rising, "income curve rises and purchases never exceed income")
	TestLib.check(Economy.hourly_income(0.5)["net"] > 0.0 and Economy.hourly_income(9.5)["net"] > Economy.hourly_income(0.5)["net"], "income grows with the sectors")
	# Systems read the table.
	TestLib.check(Upgrades.cost(&"damage", 0) == int(roundf(float(Economy.upgrade_base(&"damage")) / 5.0)) * 5, "Upgrades read Economy")
	TestLib.check(WeaponDefs.price(&"lance") == Economy.weapon_price(&"lance") and Economy.weapon_price(&"lance") > 800, "WeaponDefs read the scaled price")
	TestLib.check(Attachments.price(&"scope") == Economy.attachment_price(&"scope"), "Attachments read Economy")
	TestLib.check(HeroLook.item_price("accent") == Economy.accent_price() and HeroLook.item_price("scheme:1") == Economy.scheme_price(1), "HeroLook reads Economy")
	TestLib.check(Economy.ammo_price(&"ammo_lance") == int(InteriorData.STOCK[&"weapons"][4]["price"]), "vendor ammo reads Economy")
	TestLib.check(ContractTypes.reward(&"courier", 0)["credits"] == int(roundf(float(Economy.CONTRACT_BASE[&"courier"]) / 5.0)) * 5, "contract pay reads Economy")
	TestLib.check(SideMissions.reward(&"photo", 0, 0, 0.0) == int(roundf(float(Economy.SIDE_PAY[&"photo"]) / 5.0)) * 5, "side missions read Economy")
	TestLib.check(preload("res://scripts/world/city_events.gd").DEF[&"drop"]["credits"] == Economy.EVENT_REWARD[&"drop"] and Activities.REWARD[&"drift"] == Economy.ACTIVITY_REWARD[&"drift"], "events and activities read Economy")
	# Sanity of the table.
	var ok := true
	for it: Dictionary in Economy.gear_items():
		ok = ok and int(it["price"]) > 0 and int(it["price"]) % 5 == 0
	TestLib.check(ok, "every gear price is positive and a multiple of 5")
	TestLib.check(Economy.total_gear_cost() == int(s["total_cost"]), "total cost matches the item list")
	var upg_total := 0
	for id: StringName in Upgrades.IDS:
		for l in Upgrades.MAX_LEVEL:
			upg_total += Upgrades.cost(id, l)
	TestLib.check(upg_total > 10 * int(Economy.hourly_income(0.5)["net"]) * 0.8, "the upgrade tree alone outlasts ~8 early hours of income")
