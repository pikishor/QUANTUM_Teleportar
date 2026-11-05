extends RefCounted
## Prints the economy curves. Run: tools/economy_sim.sh


func run(_host: Node) -> void:
	var s := Economy.simulate(14)
	print("ECONOMY  gear items %d  total cost %d cr  first upgrade %.1f min  full tree %.1f h" % [s["item_count"], s["total_cost"], s["first_upgrade_minutes"], s["full_tree_hours"]])
	print("hour  sector  credits/h  cum_income  cum_cost_bought  items")
	for r: Dictionary in s["rows"]:
		print("%4d  %6d  %9d  %10d  %15d  %5d" % [r["hour"], Economy.sector_at(float(r["hour"]) - 0.5) + 1, r["income_per_hour"], r["cum_income"], r["cum_cost"], r["items"]])
	var inc := Economy.hourly_income(0.5)
	print("hour-1 mix: %s" % str(inc))
	for l in BalanceEconomy.lines():
		print(l)
