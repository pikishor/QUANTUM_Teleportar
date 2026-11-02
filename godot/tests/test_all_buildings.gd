extends RefCounted
## Every building has a working door (city_doors.gd rule: one door per lot, towers get a lobby).
## Run: tools/test.sh tests/test_all_buildings.gd

func run(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 4)
	var lots: int = city.layout.lots.size()
	TestLib.check(city.doors.size() == lots, "one door per building (%d doors, %d lots)" % [city.doors.size(), lots])
	var ids := {}
	var ok := true
	for d: Dictionary in city.doors:
		ids[int(d["id"])] = true
		if not (d["pos"] is Vector3) or (d["pos"] as Vector3).distance_to(d["wall"]) < 0.5 or InteriorData.door_name(d["type"], int(d["id"])).is_empty():
			ok = false
	TestLib.check(ids.size() == lots, "every lot id covered")
	TestLib.check(ok, "doors have prompt position and name")
	var seen := {}
	for d: Dictionary in city.doors:
		seen[d["type"]] = true
	TestLib.check(seen.size() == InteriorData.TYPES.size(), "all interior types present")
	city.queue_free()
