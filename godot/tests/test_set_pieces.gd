extends RefCounted
## Boss set pieces: data, splice into chapters 2 / 5 / 8, hazards, plans, optional skipping.
## Run: tools/test.sh tests/test_set_pieces.gd

func run(_host: Node) -> void:
	TestLib.check(SetPieces.IDS.size() == 5, "five set pieces")
	var chapters := {}
	for id: StringName in SetPieces.IDS:
		var steps := SetPieces.phase_steps(id)
		TestLib.check(steps.size() >= 2, "%s has phases (%d)" % [id, steps.size()])
		TestLib.check(steps[0]["sp_first"] and steps[steps.size() - 1]["sp_last"], "%s marks first and last phase" % id)
		var hz := true
		for s in steps:
			hz = hz and s.get("hazard") is Dictionary and CampaignSteps.kind_of(s) != &""
		TestLib.check(hz, "%s: every phase has a hazard and a valid kind" % id)
		chapters[SetPieces.DEFS[id]["chapter"]] = id
	TestLib.check(chapters.has(1) and chapters.has(4) and chapters.has(7) and chapters.has(10) and chapters.has(11), "hooked into chapters 2, 5, 8, 11 and 12")
	TestLib.check(SetPieces.is_optional(&"bridge_chase") and SetPieces.is_optional(&"rooftop_siege") and not SetPieces.is_optional(&"reactor_core") and SetPieces.is_optional(&"choir_surge") and not SetPieces.is_optional(&"final_aperture"), "ch2, ch5 and ch11 optional, ch8 and ch12 finales")
	for ci: int in chapters:
		var base := CampaignSteps.normalize_chapter(CampaignData.CAMPAIGN[ci], ci)
		var sp := SetPieces.splice(base, ci)
		var n_sp := 0
		for s in sp:
			if s.has("set_piece"):
				n_sp += 1
		TestLib.check(sp.size() == base.size() + n_sp and n_sp >= 2, "chapter %d: phases spliced in" % (ci + 1))
		TestLib.check(SetPieces.splice(sp, ci).size() == sp.size(), "splice is idempotent")
		var first := -1
		for i in sp.size():
			if sp[i].has("set_piece"):
				first = i
				break
		TestLib.check(SetPieces.end_index(sp, first) == first + n_sp, "end_index skips the whole piece")
	TestLib.check(SetPieces.splice(CampaignSteps.normalize_chapter(CampaignData.CAMPAIGN[0], 0), 0).size() == CampaignSteps.normalize_chapter(CampaignData.CAMPAIGN[0], 0).size(), "other chapters unchanged")
	# hazards
	var h := {"period": 6.0, "warn": 1.5, "radius": 5.0, "dmg": 20.0, "count": 2, "spread": 12.0}
	TestLib.check(SetPieces.hazard_state(h, 1.0) == &"idle" and SetPieces.hazard_state(h, 4.9) == &"warn" and SetPieces.hazard_state(h, 5.85) == &"hit", "idle, warn, hit")
	var z := SetPieces.zones(h, 3, Vector3(10, 0, 10))
	TestLib.check(z.size() == 2 and z == SetPieces.zones(h, 3, Vector3(10, 0, 10)), "zones deterministic")
	TestLib.check(SetPieces.damage_at(h, 5.85 + 6.0 * 3, Vector3(10, 0, 10), z[0]) == 20.0, "standing in a zone is hit")
	TestLib.check(SetPieces.damage_at(h, 5.85 + 6.0 * 3, Vector3(10, 0, 10), Vector3(500, 0, 500)) == 0.0, "far away is safe")
	TestLib.check(SetPieces.damage_at(h, 1.0, Vector3.ZERO, z[0]) == 0.0, "no damage while idle")
	# plans
	for pid in [&"sp_in", &"sp_out"]:
		var plan := SetPieces.plan(pid, &"reactor_core", {"boss": Vector3(0, 0, -30), "hero": Vector3.ZERO, "face": Vector3.FORWARD})
		TestLib.check(plan.id == pid and plan.skippable and not plan.slowmo and plan.shots.size() >= 1 and plan.head == "REACTOR CORE", "%s plan" % pid)
		plan.sample(1.0)
		TestLib.check(plan.cam_pos.is_finite(), "%s samples finite" % pid)
	# runner skipping
	var r := CampaignRunner.new()
	r.enabled = false
	TestLib.check(r.start_chapter(1, 0, true), "chapter 2 starts with the spliced piece")
	var has_sp := false
	for s in r.steps:
		has_sp = has_sp or s.has("set_piece")
	TestLib.check(has_sp, "runner steps include the set piece")
	var fi := 0
	while not r.steps[fi].has("set_piece"):
		fi += 1
	r.step_index = fi
	r.state = &"armed"
	TestLib.check(r.in_optional_set_piece() and r.skip_set_piece(), "optional piece can be skipped")
	TestLib.check(not r.steps[r.step_index].has("set_piece") or r.state == &"done", "skip lands after the piece")
	r.free()
