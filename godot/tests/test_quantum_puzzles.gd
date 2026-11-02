extends RefCounted
## Quantum puzzle layer (B8): six rooms, phase doors (key crate on the pad), pressure plates (decoy), shield barriers (COLLAPSE pulse), latching, mission pools, verb icons.
## Run: tools/test.sh tests/test_quantum_puzzles.gd

func run(host: Node) -> void:
	var root := Node3D.new()
	host.add_child(root)
	TestLib.check(QuantumPuzzles.ROOMS.size() == 6, "six puzzle rooms")
	for k: StringName in [&"safe", &"hostage", &"assassinate", &"hack"]:
		for s in 6:
			var r := QuantumPuzzles.room_for(k, s)
			TestLib.check(r >= 0 and r < 6, "room index valid for %s" % k)
	for which: StringName in [&"entangle", &"super", &"collapse"]:
		TestLib.check(QuantumPuzzles.icon_texture(which) != null, "icon %s" % which)
	var far := Vector3(1e9, 0, 1e9)
	# phase
	var ph := QuantumPuzzles.build(root, 0, Vector3(0, 0, 0), Vector3(0, 0, 1))
	await TestLib.frames(host, 2)
	var g: Dictionary = ph.gates[0]
	TestLib.check(not g["open"] and (g["barrier"] as StaticBody3D).collision_layer != 0, "phase door starts shut")
	ph.tick(0.1, Vector3.ZERO, far, true)
	TestLib.check(ph.open_count() == 0, "a collapse pulse does not open a phase door")
	(g["crate"] as Node3D).global_position = g["ctrl"]
	ph.tick(0.1, Vector3.ZERO, far, false)
	TestLib.check(g["open"] and (g["barrier"] as StaticBody3D).collision_layer == 0, "crate on the pad opens the door")
	TestLib.check(ph.is_solved(), "single-gate room solved")
	(g["crate"] as Node3D).global_position = Vector3(50, 0, 50)
	ph.tick(0.1, Vector3.ZERO, far, false)
	TestLib.check(g["open"], "an open gate stays latched")
	TestLib.check((g["crate"] as Node3D).is_in_group(&"puzzle_crate"), "crate is a swap target group")
	# plate + shield
	var ps := QuantumPuzzles.build(root, 4, Vector3(0, 0, 40), Vector3(0, 0, 1))
	await TestLib.frames(host, 2)
	var plate: Dictionary = ps.gates[0]
	var shield: Dictionary = ps.gates[1]
	TestLib.check(plate["kind"] == &"plate" and shield["kind"] == &"shield", "room 4 is plate then shield")
	ps.tick(0.3, Vector3(0, 0, 40), plate["ctrl"] + Vector3(5, 0, 0), false)
	ps.tick(0.3, Vector3(0, 0, 40), plate["ctrl"], false)
	TestLib.check(not plate["open"], "decoy must stay on the plate")
	ps.tick(0.6, Vector3(0, 0, 40), plate["ctrl"], false)
	TestLib.check(plate["open"] and not ps.is_solved(), "decoy on the plate opens it, room not yet solved")
	ps.tick(0.1, Vector3(0, 0, 200), far, true)
	TestLib.check(not shield["open"], "a collapse too far away does nothing")
	ps.tick(0.1, ps.at(shield["depth"] + 3.0), far, true)
	TestLib.check(shield["open"] and ps.is_solved(), "collapse near the barrier drops it and solves the room")
	# the swap list sees crates
	var sig := [0]
	var p3 := QuantumPuzzles.build(root, 2, Vector3(0, 0, 80), Vector3(1, 0, 0))
	p3.solved.connect(func() -> void: sig[0] += 1)
	p3.tick(0.1, p3.at(2.2), far, true)
	p3.tick(0.1, p3.at(2.2), far, true)
	TestLib.check(sig[0] == 1, "solved emits once")
	root.queue_free()
