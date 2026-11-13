extends RefCounted
## Dev helper (not a test): prints the plan counts of every town without the scene (no autoload needed beyond TerrainHeight).
func run(_host: Node) -> void:
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	for s in SettlementData.towns():
		var pl := SettlementData.plan_of(s)
		var bad := 0
		var kinds := {}
		for it in pl.items:
			kinds[str(it["kind"])] = int(kinds.get(str(it["kind"]), 0)) + 1
			if not it.has("type") and not it.has("spec"):
				bad += 1
			elif str(it["kind"]) != "house" and not it.has("type"):
				bad += 1
				print("  BAD item: ", it)
		print("TOWN %s houses=%d items=%d bad=%d kinds=%s failed=%s" % [s["id"], pl.houses, pl.items.size(), bad, kinds, pl.failed])
