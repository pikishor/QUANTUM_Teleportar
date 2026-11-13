extends "res://tests/test_interior_reach.gd"
## Interior reachability for the NINETEEN country layouts of the towns (wave 112 critic, PLAY lens; the round 4 audit tests/test_interior_reach.gd only walks the 16 city types): for every country type and
## several seeds, enter it in the real composed game, sweep the physics world for the hero's walkable cells and report what he can NOT reach: the exit, the vendor, the job object, the puzzle gates.
## Run: tools/test.sh tests/test_interior_reach_country.gd

const COUNTRY_SEEDS := 3


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(20)
	p = Game.player as Player
	ig = InteriorGameplay.instance
	(Game.progress as Progress).autosave_enabled = false
	ig.autosave = false
	var total := 0
	var vendors := 0
	InteriorMissions.puzzles_on = true
	for type: StringName in InteriorCountry.TYPES:
		for s in COUNTRY_SEEDS:
			var d := {"id": 7000 + s * 7 + InteriorCountry.TYPES.find(type) * 101, "type": type, "name": "AUDIT %s %d" % [type, s], "wall": Vector3.ZERO, "pos": Vector3(0, 0, 0), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4}
			if InteriorGameplay.active:
				ig.leave(true)
				await frames(2)
			ig.enter(d, true)
			await frames(3)
			if not InteriorGameplay.active:
				findings.append("%s seed %d: could not enter" % [type, s])
				continue
			total += 1
			if ig.actors.vendor != null and ig.actors.vendor.active:
				vendors += 1
			_audit(type, s)
	print("COUNTRYAUDIT rooms %d, vendors %d, findings %d %s" % [total, vendors, findings.size(), str(findings.slice(0, 8))])
	TestLib.check(total == InteriorCountry.TYPES.size() * COUNTRY_SEEDS, "every country interior type was entered with %d seeds (%d rooms)" % [COUNTRY_SEEDS, total])
	TestLib.check(findings.is_empty(), "nothing in any country room is out of the hero's reach (%d findings%s)" % [findings.size(), ": " + "; ".join(findings.slice(0, 6)) if not findings.is_empty() else ""])
	var shops := 0
	for t: StringName in InteriorCountry.TYPES:
		if InteriorCountry.has_vendor(t):
			shops += 1
	TestLib.check(vendors >= shops, "the shops of the towns have a vendor standing in the room (%d vendors in %d shop rooms)" % [vendors, shops * COUNTRY_SEEDS])
	if InteriorGameplay.active:
		ig.leave(true)
	Sfx.muted = false
	main.queue_free()
