extends RefCounted
## w127-integrator: the runtime blast entries of the aircraft (AirArms: ord_air_rocket, ord_air_missile) and of the military vehicles (TankArms: ord_atgm, ord_tank_rocket, veh_smoke) join
## the BlastTable only when one of them goes off, not when an armed aircraft or tank is merely set up. Before: AirArms.make / TankArms.make registered all of them at once, so an armed plane
## of the air traffic that spawned during tests/test_blast_arsenal.gd left two entries in the table that never went off, and that test's "every entry went off" check failed about one run in
## three (on the wave 126 tree as well). Data level (no scene, no UI): the vehicles are bare Vehicle objects, never added to the tree.
## Run: tools/test.sh tests/test_blast_registry_w127.gd

const RUNTIME := [&"ord_air_rocket", &"ord_air_missile", &"ord_atgm", &"ord_tank_rocket", &"veh_smoke"]


func _armed_plane_kind() -> StringName:
	for k: StringName in VehicleSpecs.SPECS:
		if str(VehicleSpecs.SPECS[k].get("cls", "")) in ["plane", "heli"]:
			var lo := AirArms.loadout(k)
			if lo.has(&"rocket") or lo.has(&"missile"):
				return k
	return &""


func _armed_tank_kind() -> StringName:
	for k: StringName in VehicleSpecs.SPECS:
		var lo := TankArms.loadout(k)
		if lo.has(&"atgm") or lo.has(&"salvo") or lo.has(&"sam"):
			return k
	return &""


func run(_host: Node) -> void:
	var registered_before := PackedStringArray()
	for id: StringName in RUNTIME:
		if BlastTable.has_entry(id):
			registered_before.append(String(id))
	TestLib.check(registered_before.is_empty(), "no runtime blast is in the table at the start (%s)" % ", ".join(registered_before))
	var made := []
	for pair in [[_armed_plane_kind(), true], [_armed_tank_kind(), false]]:
		var kind: StringName = pair[0]
		TestLib.check(kind != &"", "an armed %s kind exists" % ("aircraft" if pair[1] else "military vehicle"))
		if kind == &"":
			continue
		var v := Vehicle.new()
		v.kind = kind
		v.cls = StringName(str(VehicleSpecs.SPECS[kind].get("cls", "car")))
		var a: RefCounted = AirArms.make(v) if pair[1] else TankArms.make(v)
		TestLib.check(a != null, "%s gets its arms (%s)" % [kind, v.cls])
		made.append(v)
	var early := PackedStringArray()
	for id: StringName in RUNTIME:
		if BlastTable.has_entry(id):
			early.append(String(id))
	TestLib.check(early.is_empty(), "setting up an armed aircraft and an armed tank puts no blast in the table before one goes off (registered early: %s)" % ", ".join(early))
	# each entry joins the table on its own when asked for (the moment it goes off), and the other ones stay out
	TestLib.check(TankArms.ensure_blast(&"ord_atgm") and BlastTable.has_entry(&"ord_atgm"), "the guided missile's blast joins the table when it goes off")
	TestLib.check(not BlastTable.has_entry(&"ord_tank_rocket") and not BlastTable.has_entry(&"veh_smoke") and not BlastTable.has_entry(&"ord_air_rocket"), "...and only that one")
	TestLib.check(TankArms.ensure_blast(&"ord_air_missile") and BlastTable.has_entry(&"ord_air_missile") and not BlastTable.has_entry(&"ord_air_rocket"), "the anti-air tank's seeker uses the aircraft missile blast, and the air rocket stays out")
	TestLib.check(not TankArms.ensure_blast(&"no_such_blast"), "an unknown id is not registered")
	for v: Vehicle in made:
		v.free()
